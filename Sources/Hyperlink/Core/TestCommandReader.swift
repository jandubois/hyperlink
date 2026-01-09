import Foundation
import AppKit

/// Thread-safe command queue
private class CommandQueue: @unchecked Sendable {
    private var commands: [String] = []
    private let lock = NSLock()

    func append(_ command: String) {
        lock.lock()
        commands.append(command)
        lock.unlock()
    }

    func popFirst() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return commands.isEmpty ? nil : commands.removeFirst()
    }
}

/// Reads and executes test commands from stdin
/// Commands:
/// - wait:<ms>          - Wait for specified milliseconds
/// - key:<keyname>      - Simulate key press (down, up, return, escape, 1-9, etc.)
/// - click:<row>        - Click on tab row
/// - search:<text>      - Type in search field
/// - browser:<index>    - Switch to browser at index
/// - quit               - Exit the app
@MainActor
class TestCommandReader: NSObject {
    private var inputThread: Thread?
    private let commandQueue = CommandQueue()
    weak var viewModel: PickerViewModel?
    var onDismiss: (() -> Void)?

    func start() {
        // Read all commands from stdin first (non-blocking for the main thread)
        let queue = commandQueue
        inputThread = Thread {
            while let line = readLine() {
                queue.append(line)
            }
        }
        inputThread?.start()

        // Process commands after a brief delay to let GUI initialize
        scheduleNextCommandCheck(delay: 0.1)
    }

    private func scheduleNextCommandCheck(delay: TimeInterval) {
        // Use performSelector which integrates with NSApplication's run loop
        self.perform(#selector(processNextCommandObjc), with: nil, afterDelay: delay)
    }

    @objc private func processNextCommandObjc() {
        processNextCommand()
    }

    private func processNextCommand() {
        guard let command = commandQueue.popFirst() else {
            // No more commands, check again later
            scheduleNextCommandCheck(delay: 0.05)
            return
        }

        executeCommand(command)
    }

    private func executeCommand(_ command: String) {
        let parts = command.split(separator: ":", maxSplits: 1)
        let cmd = String(parts[0]).lowercased().trimmingCharacters(in: .whitespaces)
        let arg = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""

        TestLogger.logAction("command", details: ["command": cmd, "arg": arg])

        switch cmd {
        case "wait":
            let ms = Int(arg) ?? 100
            scheduleNextCommandCheck(delay: Double(ms) / 1000.0)
            return

        case "key":
            simulateKey(arg)

        case "click":
            if let row = Int(arg) {
                simulateClick(row: row)
            }

        case "search":
            viewModel?.searchText = arg
            TestLogger.logState("searchText", value: arg)

        case "browser":
            if let index = Int(arg) {
                viewModel?.selectedBrowserIndex = index
                TestLogger.logState("selectedBrowserIndex", value: index)
            }

        case "select":
            if let index = Int(arg) {
                viewModel?.toggleSelection(at: index)
            }

        case "quit", "exit":
            TestLogger.logResult("quit")
            onDismiss?()
            return

        default:
            TestLogger.logAction("unknown_command", details: ["command": command])
        }

        // Process next command
        scheduleNextCommandCheck(delay: 0.01)
    }

    private func simulateKey(_ keyName: String) {
        TestLogger.logKeyPress(keyName)

        switch keyName.lowercased() {
        case "down":
            viewModel?.moveHighlight(by: 1)
            TestLogger.logState("highlightedIndex", value: viewModel?.highlightedIndex ?? -1)

        case "up":
            viewModel?.moveHighlight(by: -1)
            TestLogger.logState("highlightedIndex", value: viewModel?.highlightedIndex ?? -1)

        case "return", "enter":
            if let index = viewModel?.highlightedIndex,
               let tabs = viewModel?.filteredTabs,
               index < tabs.count {
                let tab = tabs[index]
                viewModel?.copyAndDismiss(tab: tab)
                TestLogger.logResult("copy", details: [
                    "title": tab.title,
                    "url": tab.url.absoluteString
                ])
                onDismiss?()
            }

        case "escape", "esc":
            TestLogger.logResult("dismiss", details: ["reason": "escape"])
            onDismiss?()

        case "space":
            if let index = viewModel?.highlightedIndex {
                viewModel?.toggleSelection(at: index)
                TestLogger.logState("selectedCount", value: viewModel?.selectedTabs.count ?? 0)
            }

        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            if let index = Int(keyName), let tabs = viewModel?.filteredTabs {
                let tabIndex = index - 1
                if tabIndex < tabs.count {
                    let tab = tabs[tabIndex]
                    viewModel?.copyAndDismiss(tab: tab)
                    TestLogger.logResult("copy", details: [
                        "title": tab.title,
                        "url": tab.url.absoluteString
                    ])
                    onDismiss?()
                }
            }

        default:
            break
        }
    }

    private func simulateClick(row: Int) {
        guard let tabs = viewModel?.filteredTabs, row < tabs.count else { return }

        let tab = tabs[row]
        viewModel?.copyAndDismiss(tab: tab)
        TestLogger.logResult("copy", details: [
            "title": tab.title,
            "url": tab.url.absoluteString,
            "method": "click"
        ])
        onDismiss?()
    }
}
