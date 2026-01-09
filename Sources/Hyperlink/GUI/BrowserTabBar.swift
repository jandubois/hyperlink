import SwiftUI

/// Horizontal tab bar showing available browsers
struct BrowserTabBar: View {
    let browsers: [PickerViewModel.BrowserData]
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                BrowserTab(
                    name: browser.name,
                    icon: browser.icon,
                    isSelected: index == selectedIndex,
                    shortcutNumber: index < 9 ? index + 1 : nil
                )
                .onTapGesture {
                    selectedIndex = index
                }
            }
        }
    }
}

/// Individual browser tab button
struct BrowserTab: View {
    let name: String
    let icon: NSImage
    let isSelected: Bool
    let shortcutNumber: Int?

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)

            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            if let number = shortcutNumber {
                Text("\(number)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }
}
