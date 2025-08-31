//
//  ModernFilterRow.swift
//  MetalVideoFilterApp
//
//  Created by Rohan Saha on 06/08/25.
//


import UIKit

class ModernFilterRow: UIView {
    var filterNames: [String] = []
    var selectedIndex: Int = 0 {
        didSet { updateUI() }
    }
    var filterTapped: ((Int) -> Void)?
    private var buttons: [UIButton] = []

    init(filterNames: [String]) {
        self.filterNames = filterNames
        super.init(frame: .zero)
        backgroundColor = .clear
        setupButtons()
        updateUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        for (i, name) in filterNames.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            button.tag = i
            button.layer.cornerRadius = 18
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            button.addTarget(self, action: #selector(filterTapped(_:)), for: .touchUpInside)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
    }

    private func updateUI() {
        for (i, button) in buttons.enumerated() {
            if i == selectedIndex {
                button.backgroundColor = tintColor
                button.setTitleColor(.white, for: .normal)
            } else {
                button.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.7)
                button.setTitleColor(.label, for: .normal)
            }
        }
    }

    @objc private func filterTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
        filterTapped?(sender.tag)
    }
}