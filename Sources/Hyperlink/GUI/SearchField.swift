import SwiftUI
import AppKit

/// Search field for filtering tabs - uses a real NSTextField for proper input handling
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isActive: Bool
    var onActivate: (() -> Void)? = nil

    func makeNSView(context: Context) -> SearchFieldView {
        let view = SearchFieldView()
        view.textField.delegate = context.coordinator
        view.textField.target = context.coordinator
        view.textField.action = #selector(Coordinator.textFieldAction(_:))
        view.onActivate = onActivate
        return view
    }

    func updateNSView(_ nsView: SearchFieldView, context: Context) {
        if nsView.textField.stringValue != text {
            nsView.textField.stringValue = text
        }
        nsView.updateActiveState(isActive: isActive, hasText: !text.isEmpty)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isActive: $isActive)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isActive: Binding<Bool>

        init(text: Binding<String>, isActive: Binding<Bool>) {
            self.text = text
            self.isActive = isActive
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text.wrappedValue = textField.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isActive.wrappedValue = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if text.wrappedValue.isEmpty {
                isActive.wrappedValue = false
            }
        }

        @objc func textFieldAction(_ sender: NSTextField) {
            // Return key pressed - do nothing special, just keep focus
        }
    }
}

/// Custom view that contains the search field with styling
class SearchFieldView: NSView {
    let textField = NSTextField()
    private let iconView = NSImageView()
    private let clearButton = NSButton()
    var onActivate: (() -> Void)?

    private var isActive = false
    private var hasText = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 8

        // Search icon
        iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Text field
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.placeholderString = "Filter tabs..."
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        // Clear button
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clearText)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isHidden = true
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16),

            heightAnchor.constraint(equalToConstant: 32),
        ])

        updateAppearance()
    }

    func updateActiveState(isActive: Bool, hasText: Bool) {
        self.isActive = isActive
        self.hasText = hasText
        clearButton.isHidden = !hasText
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        layer?.borderWidth = isActive ? 2 : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        iconView.contentTintColor = isActive ? .controlAccentColor : .secondaryLabelColor
    }

    @objc private func clearText() {
        textField.stringValue = ""
        if let delegate = textField.delegate as? SearchField.Coordinator {
            delegate.text.wrappedValue = ""
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(textField)
        onActivate?()
    }
}
