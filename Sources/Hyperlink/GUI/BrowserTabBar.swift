import SwiftUI

/// Horizontal tab bar showing available browsers (styled like browser tabs)
struct BrowserTabBar: View {
    let browsers: [PickerViewModel.BrowserData]
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                BrowserTab(
                    name: browser.name,
                    icon: browser.icon,
                    isSelected: index == selectedIndex,
                    isFirst: index == 0,
                    isLast: index == browsers.count - 1
                )
                .onTapGesture {
                    selectedIndex = index
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Individual browser tab styled like a real browser tab
struct BrowserTab: View {
    let name: String
    let icon: NSImage
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)

            Text(name)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Group {
                if isSelected {
                    Color(NSColor.controlBackgroundColor)
                } else {
                    Color.clear
                }
            }
        )
        .overlay(
            // Separator line on the right edge (except for last tab or selected tab)
            HStack {
                Spacer()
                if !isLast && !isSelected {
                    Rectangle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 1)
                        .padding(.vertical, 6)
                }
            }
        )
        .clipShape(
            RoundedCorners(
                topLeft: isFirst ? 8 : 0,
                topRight: isLast ? 8 : 0,
                bottomLeft: isFirst ? 8 : 0,
                bottomRight: isLast ? 8 : 0
            )
        )
        .contentShape(Rectangle())
    }
}

/// Shape with individually rounded corners
struct RoundedCorners: Shape {
    var topLeft: CGFloat = 0
    var topRight: CGFloat = 0
    var bottomLeft: CGFloat = 0
    var bottomRight: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tl = min(topLeft, min(rect.width, rect.height) / 2)
        let tr = min(topRight, min(rect.width, rect.height) / 2)
        let bl = min(bottomLeft, min(rect.width, rect.height) / 2)
        let br = min(bottomRight, min(rect.width, rect.height) / 2)

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                    radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                    radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                    radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                    radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        return path
    }
}
