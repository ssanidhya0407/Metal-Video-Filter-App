import UIKit
import AVFoundation
import MetalKit

class CameraViewController: UIViewController {
    private var metalView: MTKView!
    private var renderer: MetalRenderer!
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let filterNames = ["None", "Blur", "Edge", "Warp", "Wave", "Chromatic", "Tone", "Film"]
    private var selectedFilter: Int = 0 {
        didSet {
            renderer.setFilter(selectedFilter)
            filterRow.selectedIndex = selectedFilter
        }
    }
    private lazy var filterRow: FilterRow = {
        let row = FilterRow(filterNames: filterNames)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.filterTapped = { [weak self] idx in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self?.selectedFilter = idx
        }
        return row
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupMetalView()
        setupFilterRow()
        setupCamera()
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged),
                                               name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    private func setupMetalView() {
        metalView = MTKView(frame: view.bounds, device: MTLCreateSystemDefaultDevice())
        metalView.backgroundColor = .black
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        metalView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(metalView)
        renderer = MetalRenderer(metalView: metalView)
        metalView.delegate = renderer
        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.leftAnchor.constraint(equalTo: view.leftAnchor),
            metalView.rightAnchor.constraint(equalTo: view.rightAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupFilterRow() {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blur.clipsToBounds = true
        blur.layer.cornerRadius = 28
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.shadowColor = UIColor.black.cgColor
        blur.layer.shadowOpacity = 0.15
        blur.layer.shadowRadius = 8
        blur.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.addSubview(blur)
        blur.contentView.addSubview(filterRow)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            blur.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            blur.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            blur.heightAnchor.constraint(equalToConstant: 64),

            filterRow.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 8),
            filterRow.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -8),
            filterRow.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 8),
            filterRow.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -8)
        ])
    }

    private func setupCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera) else {
                print("Unable to access back camera!")
                self.captureSession.commitConfiguration()
                return
            }

            self.captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            if self.captureSession.canAddInput(input) {
                self.captureSession.addInput(input)
            }

            let queue = DispatchQueue(label: "videoQueue")
            self.videoOutput.setSampleBufferDelegate(self, queue: queue)
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.captureSession.outputs.forEach { self.captureSession.removeOutput($0) }
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            self.setVideoOrientationAndStabilization()
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }

    @objc private func orientationChanged() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setVideoOrientationAndStabilization()
        }
    }

    private func setVideoOrientationAndStabilization() {
        guard let connection = self.videoOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .off
        }
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        renderer.processSampleBuffer(sampleBuffer)
    }
}
