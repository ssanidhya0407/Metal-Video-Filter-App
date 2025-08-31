import Foundation
import MetalKit
import AVFoundation

enum MetalFilterType: Int {
    case none = 0, blur, edge, warp, wave, chromatic, tone, film
}

class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private weak var metalView: MTKView?
    private var textureCache: CVMetalTextureCache?
    private var currentTexture: MTLTexture?

    // State
    private var pipelineStates: [MetalFilterType: MTLRenderPipelineState] = [:]
    private var computePipelines: [MetalFilterType: MTLComputePipelineState] = [:]
    private var vertexBuffer: MTLBuffer!
    private var sampler: MTLSamplerState!
    private var filterType: MetalFilterType = .none

    // For temporal effects
    private var time: Float = 0

    init(metalView: MTKView) {
        guard let device = metalView.device else { fatalError("Metal device not found") }
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.metalView = metalView
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        setupVertexBuffer()
        setupSampler()
        setupPipelines()
    }

    private func setupVertexBuffer() {
        // Fullscreen quad: position(x, y), texCoord(x, y)
        let quad: [Float] = [
            -1, -1, 0, 1,  // left-bottom
             1, -1, 1, 1,  // right-bottom
            -1,  1, 0, 0,  // left-top
             1,  1, 1, 0   // right-top
        ]
        vertexBuffer = device.makeBuffer(bytes: quad, length: MemoryLayout<Float>.size * quad.count, options: [])
    }

    private func setupSampler() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    private func setupPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to load default Metal library")
            return
        }
        // Render pipelines
        pipelineStates[.none] = makeRenderPipeline(library: library, vertex: "passthrough_vertex", fragment: "passthrough_fragment")
        pipelineStates[.warp] = makeRenderPipeline(library: library, vertex: "warp_vertex", fragment: "passthrough_fragment")
        pipelineStates[.wave] = makeRenderPipeline(library: library, vertex: "wave_vertex", fragment: "passthrough_fragment")
        pipelineStates[.chromatic] = makeRenderPipeline(library: library, vertex: "passthrough_vertex", fragment: "chromatic_fragment")
        pipelineStates[.tone] = makeRenderPipeline(library: library, vertex: "passthrough_vertex", fragment: "tonemap_fragment")
        pipelineStates[.film] = makeRenderPipeline(library: library, vertex: "passthrough_vertex", fragment: "film_fragment")
        // Compute pipelines
        computePipelines[.blur] = makeComputePipeline(library: library, name: "gaussian_blur")
        computePipelines[.edge] = makeComputePipeline(library: library, name: "edge_detect")
    }

    private func makeRenderPipeline(library: MTLLibrary, vertex: String, fragment: String) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Vertex descriptor setup (required for [[stage_in]])
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        descriptor.vertexDescriptor = vertexDescriptor

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to create pipeline for vertex: \(vertex), fragment: \(fragment): \(error)")
            return nil
        }
    }

    private func makeComputePipeline(library: MTLLibrary, name: String) -> MTLComputePipelineState? {
        guard let kernel = library.makeFunction(name: name) else {
            print("Compute function \(name) not found in Metal library")
            return nil
        }
        do {
            return try device.makeComputePipelineState(function: kernel)
        } catch {
            print("Failed to create compute pipeline for \(name): \(error)")
            return nil
        }
    }

    func setFilter(_ filter: Int) {
        filterType = MetalFilterType(rawValue: filter) ?? .none
    }

    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let texture = makeTexture(from: pixelBuffer) else { return }
        self.currentTexture = texture
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTextureOut: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache!, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvTextureOut
        )
        guard status == kCVReturnSuccess, let cvTexture = cvTextureOut else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    func draw(in view: MTKView) {
        guard let currentDrawable = view.currentDrawable,
              let inputTexture = currentTexture,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

        time += 1.0 / Float(view.preferredFramesPerSecond)

        let outputTexture = inputTexture // For filter chaining, you can allocate intermediate textures

        // Compute Filter (Blur, Edge)
        if filterType == .blur || filterType == .edge {
            if let pipeline = computePipelines[filterType],
               let intermediate = makeIntermediateTexture(width: inputTexture.width, height: inputTexture.height) {
                let encoder = commandBuffer.makeComputeCommandEncoder()!
                encoder.setComputePipelineState(pipeline)
                encoder.setTexture(inputTexture, index: 0)
                encoder.setTexture(intermediate, index: 1)
                var sigma: Float = 8
                if filterType == .blur { encoder.setBytes(&sigma, length: MemoryLayout<Float>.size, index: 0) }
                let w = pipeline.threadExecutionWidth
                let h = pipeline.maxTotalThreadsPerThreadgroup / w
                let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
                let threads = MTLSize(width: inputTexture.width, height: inputTexture.height, depth: 1)
                encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
                encoder.endEncoding()
                drawTexture(intermediate, commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor, drawable: currentDrawable)
            }
        } else {
            guard let pipeline = pipelineStates[filterType] ?? pipelineStates[.none] else {
                print("No valid pipeline state for filter \(filterType)")
                return
            }
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(outputTexture, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.setVertexBytes(&time, length: MemoryLayout<Float>.size, index: 1)
            encoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            commandBuffer.present(currentDrawable)
        }
        commandBuffer.commit()
    }

    private func drawTexture(_ texture: MTLTexture, commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor, drawable: MTLDrawable) {
        guard let pipeline = pipelineStates[.none] else {
            print("No valid pipeline state for .none filter")
            return
        }
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
    }

    private func makeIntermediateTexture(width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        return device.makeTexture(descriptor: desc)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
