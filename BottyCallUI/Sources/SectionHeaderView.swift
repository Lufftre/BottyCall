import AppKit

class SectionHeaderView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")

    static let headerHeight: CGFloat = 24

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        nameLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        nameLabel.textColor = NSColor(white: 0.38, alpha: 1)
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    func configure(name: String) {
        nameLabel.stringValue = name
    }
}
