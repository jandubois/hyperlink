import SwiftUI

/// Keyboard shortcuts help overlay
struct HelpOverlay: View {
    let onDismiss: () -> Void

    private let shortcuts: [(key: String, description: String)] = [
        ("1-9", "Select and copy tab"),
        ("Ctrl+1-9", "Select tab (always)"),
        ("Up/Down", "Navigate tabs"),
        ("Return", "Copy highlighted tab"),
        ("Space", "Toggle checkbox"),
        ("Cmd+←/→", "Switch browser"),
        ("Cmd+1-9", "Switch to browser"),
        ("Tab", "Switch focus (list/search)"),
        ("Escape", "Clear search / Close"),
        ("Cmd+Return", "Copy selected tabs"),
        ("?", "Show this help"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                ForEach(shortcuts, id: \.key) { shortcut in
                    HStack {
                        Text(shortcut.key)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(.accentColor)
                        Text(shortcut.description)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(.primary)
                    }
                }
            }

            Text("Press any key or click to dismiss")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .shadow(radius: 20)
    }
}
