import UIKit

class FilterRow: UIView {
    var filterNames: [String]
    var selectedIndex: Int = 0 {
        didSet { updateUI() }
    }
    var filterTapped: ((Int) -> Void)?
    private var buttons: [UIButton] = []
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    init(filterNames: [String]) {
        self.filterNames = filterNames
        super.init(frame: .zero)
        backgroundColor = .clear
        setupScrollStack()
        setupButtons()
        updateUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupScrollStack() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 56)
        ])

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    private func setupButtons() {
        for (i, name) in filterNames.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            button.tag = i
            button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            button.addTarget(self, action: #selector(filterTapped(_:)), for: .touchUpInside)
            button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 22, bottom: 12, right: 22)
            button.clipsToBounds = true
            button.layer.cornerRadius = 18 // Rounded corners, but not a perfect pill
            button.setContentHuggingPriority(.required, for: .horizontal)
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
    }

    private func updateUI() {
        for (i, button) in buttons.enumerated() {
            if i == selectedIndex {
                button.backgroundColor = tintColor
                button.setTitleColor(.white, for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .bold)
                button.layer.borderWidth = 1.2
                button.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
                button.layer.shadowColor = tintColor.cgColor
                button.layer.shadowOpacity = 0.13
                button.layer.shadowRadius = 5
                button.layer.shadowOffset = CGSize(width: 0, height: 3)
            } else {
                button.backgroundColor = UIColor.systemGray6.withAlphaComponent(0.8)
                button.setTitleColor(.label, for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
                button.layer.borderWidth = 0
                button.layer.shadowOpacity = 0
            }
        }
    }

    @objc private func filterTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
        filterTapped?(sender.tag)
        // Optionally, scroll to make the selected button visible
        scrollToButton(sender)
    }

    private func scrollToButton(_ button: UIButton) {
        guard let superview = button.superview else { return }
        let buttonFrame = superview.convert(button.frame, to: scrollView)
        scrollView.scrollRectToVisible(buttonFrame.insetBy(dx: -16, dy: 0), animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the buttons a bit rounded, not a full pill
        for button in buttons {
            button.layer.cornerRadius = 18
        }
    }
}
