import SwiftUI
import AppKit

/// Settings sheet for transformation rules
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let currentTab: TabInfo?
    let onDismiss: () -> Void

    @State private var selectedGroupIndex: Int = 0
    @State private var previewTitle: String = ""
    @State private var previewURL: String = ""

    private var isGlobalSelected: Bool {
        selectedGroupIndex == 0
    }

    private var selectedAppGroupIndex: Int? {
        guard selectedGroupIndex > 0 else { return nil }
        return selectedGroupIndex - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transform Rules")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Preview section (compact)
            PreviewSection(
                title: $previewTitle,
                url: $previewURL,
                settings: preferences.transformSettings
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Main content: sidebar + detail using HStack
            HStack(spacing: 0) {
                // Groups sidebar
                GroupsSidebar(
                    settings: $preferences.transformSettings,
                    selectedIndex: $selectedGroupIndex
                )
                .frame(width: 140)

                Divider()

                // Rules detail
                if isGlobalSelected {
                    RulesDetail(
                        groupName: "Global",
                        rules: Binding(
                            get: { preferences.transformSettings.globalGroup.rules },
                            set: { preferences.transformSettings.globalGroup.rules = $0 }
                        )
                    )
                } else if let appIndex = selectedAppGroupIndex,
                          appIndex < preferences.transformSettings.appGroups.count {
                    RulesDetail(
                        groupName: preferences.transformSettings.appGroups[appIndex].displayName,
                        rules: Binding(
                            get: { preferences.transformSettings.appGroups[appIndex].rules },
                            set: { preferences.transformSettings.appGroups[appIndex].rules = $0 }
                        )
                    )
                } else {
                    Text("Select a group")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 650, height: 450)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 10)
        .onAppear {
            if let tab = currentTab {
                previewTitle = tab.title
                previewURL = tab.url.absoluteString
            } else {
                previewTitle = "Example Page Title · owner/repo"
                previewURL = "https://github.com/owner/repo"
            }
        }
    }
}

/// Preview section showing before/after of transforms
struct PreviewSection: View {
    @Binding var title: String
    @Binding var url: String
    let settings: TransformSettings

    private var transformedResult: TransformEngine.Result {
        guard let parsedURL = URL(string: url) else {
            return TransformEngine.Result(title: title, url: url)
        }
        let engine = TransformEngine(settings: settings, targetBundleID: nil)
        return engine.apply(title: title, url: parsedURL)
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text("Input")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .gridColumnAlignment(.trailing)
                EditableTextField(text: $title, placeholder: "Title")
                EditableTextField(text: $url, placeholder: "URL")
            }

            GridRow {
                Text("Result")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("", text: .constant(transformedResult.title))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(true)
                TextField("", text: .constant(transformedResult.url))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(true)
            }
        }
    }
}

/// Sidebar showing groups
struct GroupsSidebar: View {
    @Binding var settings: TransformSettings
    @Binding var selectedIndex: Int
    @State private var showingAppPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Groups list
            ScrollView {
                VStack(spacing: 2) {
                    // Global group (always first, cannot be deleted)
                    GroupRow(
                        icon: "globe",
                        name: "Global",
                        isSelected: selectedIndex == 0,
                        isEnabled: true
                    )
                    .onTapGesture { selectedIndex = 0 }

                    // App-specific groups
                    ForEach(Array(settings.appGroups.enumerated()), id: \.element.id) { index, group in
                        GroupRow(
                            bundleID: group.bundleID,
                            name: group.displayName,
                            isSelected: selectedIndex == index + 1,
                            isEnabled: group.isEnabled
                        )
                        .onTapGesture { selectedIndex = index + 1 }
                        .contextMenu {
                            Button(group.isEnabled ? "Disable" : "Enable") {
                                settings.appGroups[index].isEnabled.toggle()
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                deleteAppGroup(at: index)
                            }
                        }
                    }
                }
                .padding(8)
            }

            Divider()

            // Add app group button
            Button(action: { showingAppPicker = true }) {
                Label("Add App", systemImage: "plus")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(8)
            .popover(isPresented: $showingAppPicker) {
                RunningAppsPicker { bundleID, displayName in
                    addAppGroup(bundleID: bundleID, displayName: displayName)
                    showingAppPicker = false
                }
            }
        }
        .background(Color.secondary.opacity(0.05))
    }

    private func addAppGroup(bundleID: String, displayName: String) {
        guard !settings.appGroups.contains(where: { $0.bundleID == bundleID }) else {
            return
        }
        let newGroup = AppRuleGroup(bundleID: bundleID, displayName: displayName)
        settings.appGroups.append(newGroup)
        selectedIndex = settings.appGroups.count
    }

    private func deleteAppGroup(at index: Int) {
        settings.appGroups.remove(at: index)
        if selectedIndex > settings.appGroups.count {
            selectedIndex = 0
        }
    }
}

/// Row for a group in the sidebar
struct GroupRow: View {
    var icon: String? = nil
    var bundleID: String? = nil
    let name: String
    let isSelected: Bool
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .frame(width: 16, height: 16)
            } else if let bundleID = bundleID {
                AppIcon(bundleID: bundleID)
                    .frame(width: 16, height: 16)
            }

            Text(name)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            if !isEnabled {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

/// Picker showing running applications
struct RunningAppsPicker: View {
    let onSelect: (String, String) -> Void

    private var runningApps: [(bundleID: String, name: String, icon: NSImage)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String, NSImage)? in
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return (bundleID, name, app.icon ?? NSImage())
            }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Select Application")
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(runningApps, id: \.bundleID) { app in
                        Button(action: { onSelect(app.bundleID, app.name) }) {
                            HStack {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(app.name)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(width: 250, height: 300)
        }
    }
}

/// App icon view
struct AppIcon: View {
    let bundleID: String

    private var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

/// Detail view for rules in a group
struct RulesDetail: View {
    let groupName: String
    @Binding var rules: [TransformRule]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Rules for \"\(groupName)\"")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Rules list
            if rules.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No rules")
                        .foregroundColor(.secondary)
                    Text("Click \"Add Rule\" to create one")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(rules.enumerated()), id: \.element.id) { index, _ in
                            RuleRow(
                                rule: $rules[index],
                                onDelete: { deleteRule(at: index) }
                            )
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            // Add rule button
            Button(action: addRule) {
                Label("Add Rule", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addRule() {
        let newRule = TransformRule(
            name: "New Rule",
            transforms: [Transform()]
        )
        rules.append(newRule)
    }

    private func deleteRule(at index: Int) {
        rules.remove(at: index)
    }
}

/// Row for a single rule
struct RuleRow: View {
    @Binding var rule: TransformRule
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Rule header
            HStack {
                Toggle("", isOn: $rule.isEnabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                TextField("Rule name", text: $rule.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
            }

            // URL match
            HStack {
                Text("URL match:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 65, alignment: .trailing)
                TextField("Leave empty to match all URLs", text: $rule.urlMatch)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            // Transforms
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rule.transforms.enumerated()), id: \.element.id) { index, _ in
                    TransformRow(
                        transform: $rule.transforms[index],
                        onDelete: { deleteTransform(at: index) }
                    )
                }
            }

            // Add transform button
            Button(action: addTransform) {
                Label("Add Transform", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .opacity(rule.isEnabled ? 1.0 : 0.6)
    }

    private func addTransform() {
        rule.transforms.append(Transform())
    }

    private func deleteTransform(at index: Int) {
        rule.transforms.remove(at: index)
    }
}

/// Row for a single transform
struct TransformRow: View {
    @Binding var transform: Transform
    let onDelete: () -> Void

    @State private var patternError: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $transform.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()

            Picker("", selection: $transform.target) {
                Text("Title").tag(TransformTarget.title)
                Text("URL").tag(TransformTarget.url)
            }
            .labelsHidden()
            .frame(width: 65)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Find (regex)", text: $transform.pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 120)
                    .onChange(of: transform.pattern) { _, newValue in
                        patternError = TransformEngine.validatePattern(newValue)
                    }

                if let error = patternError {
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            TextField("Replace", text: $transform.replacement)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(minWidth: 80)

            Button(action: onDelete) {
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .opacity(transform.isEnabled ? 1.0 : 0.6)
    }
}

/// TextField wrapper that properly shows i-beam cursor using tracking areas
struct EditableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""

    func makeNSView(context: Context) -> CursorTrackingTextField {
        let textField = CursorTrackingTextField()
        textField.placeholderString = placeholder
        textField.font = NSFont.systemFont(ofSize: 11)
        textField.bezelStyle = .roundedBezel
        textField.delegate = context.coordinator
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: CursorTrackingTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text.wrappedValue = textField.stringValue
            }
        }
    }
}

/// Custom NSTextField that manages its own cursor via tracking area
class CursorTrackingTextField: NSTextField {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.iBeam.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        // Override to prevent system from changing cursor
        NSCursor.iBeam.set()
    }
}
