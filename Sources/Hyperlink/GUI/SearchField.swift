import SwiftUI

/// Search field for filtering tabs
struct SearchField: View {
    @Binding var text: String
    @Binding var isActive: Bool
    var onActivate: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isActive ? .accentColor : .secondary)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Filter tabs...")
                        .foregroundColor(.secondary)
                }
                Text(text)
                    .foregroundColor(.primary)
            }

            Spacer()

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isActive = true
            onActivate?()
        }
    }
}
