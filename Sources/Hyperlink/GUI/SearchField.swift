import SwiftUI
import AppKit

/// Search field for filtering tabs - uses a real NSTextField for proper input handling
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeNSView(context: Context) -> SearchFieldView {
        let view = SearchFieldView()
        view.textField.delegate = context.coordinator
        view.textField.target = context.coordinator
        view.textField.action = #selector(Coordinator.textFieldAction(_:))
        context.coordinator.searchFieldView = view
        return view
    }

    func updateNSView(_ nsView: SearchFieldView, context: Context) {
        if nsView.textField.stringValue != text {
            nsView.textField.stringValue = text
        }
        nsView.updateActiveState(isActive: isFocused, hasText: !text.isEmpty)

        // Handle focus changes from parent
        if isFocused {
            if nsView.window?.firstResponder != nsView.textField &&
               nsView.window?.firstResponder != nsView.textField.currentEditor() {
                nsView.window?.makeFirstResponder(nsView.textField)
            }
        } else {
            if nsView.window?.firstResponder == nsView.textField ||
               nsView.window?.firstResponder == nsView.textField.currentEditor() {
                nsView.window?.makeFirstResponder(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        weak var searchFieldView: SearchFieldView?

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text.wrappedValue = textField.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isFocused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            // Only update if we're losing focus, not if text is just being committed
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let view = self.searchFieldView else { return }
                let currentResponder = view.window?.firstResponder
                if currentResponder != view.textField && currentResponder != view.textField.currentEditor() {
                    self.isFocused.wrappedValue = false
                }
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
    }
}
