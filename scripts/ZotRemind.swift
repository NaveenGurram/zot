import SwiftUI
import Observation

struct Reminder: Identifiable {
    let id: Int
    let message: String
    let project: String
    let due: String
    var checked: Bool = false
}

@Observable
class AppState {
    var reminders: [Reminder] = []
    let zotPath: String

    init() {
        let selfPath = ProcessInfo.processInfo.arguments[0]
        let binDir = (selfPath as NSString).deletingLastPathComponent
        let candidates = [
            "\(binDir)/zot",
            "\(NSHomeDirectory())/.local/bin/zot",
            "/usr/local/bin/zot"
        ]
        zotPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/zot"
        loadReminders()
    }

    func loadReminders() {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: zotPath)
        proc.arguments = ["remind"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        proc.environment = ProcessInfo.processInfo.environment.merging(["TERM": "dumb"]) { _, new in new }
        try? proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        reminders = output.components(separatedBy: "\n").compactMap { line in
            let clean = line.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression)
            guard let hashIdx = clean.range(of: "(#") else { return nil }
            guard let parenClose = clean.range(of: ") ", range: hashIdx.upperBound..<clean.endIndex) else { return nil }
            let idStr = clean[hashIdx.upperBound..<parenClose.lowerBound]
            guard let id = Int(idStr) else { return nil }
            let rest = String(clean[parenClose.upperBound...]).trimmingCharacters(in: .whitespaces)
            var msg = rest, project = "", due = ""
            if let dueRange = rest.range(of: " - due: ") {
                msg = String(rest[rest.startIndex..<dueRange.lowerBound])
                due = String(rest[dueRange.upperBound...])
            }
            if let pStart = msg.range(of: " ["), let pEnd = msg.range(of: "]", range: pStart.upperBound..<msg.endIndex) {
                project = String(msg[pStart.upperBound..<pEnd.lowerBound])
                msg = String(msg[msg.startIndex..<pStart.lowerBound])
            }
            return Reminder(id: id, message: msg.trimmingCharacters(in: .whitespaces),
                          project: project, due: due)
        }
    }

    func markDone(_ ids: [Int]) {
        for id in ids {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: zotPath)
            proc.arguments = ["done", "\(id)"]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
        }
    }
}

struct ContentView: View {
    @State var state = AppState()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("📝")
                    .font(.title)
                Text("Zot Reminders")
                    .font(.title2.bold())
                Spacer()
                Text("\(state.reminders.count) due")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if state.reminders.isEmpty {
                Spacer()
                Text("No reminders due ✨")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(0..<state.reminders.count, id: \.self) { idx in
                            HStack(spacing: 12) {
                                Image(systemName: state.reminders[idx].checked ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(state.reminders[idx].checked ? .green : .secondary)
                                    .onTapGesture { state.reminders[idx].checked.toggle() }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(state.reminders[idx].message)
                                        .font(.body.weight(.medium))
                                        .strikethrough(state.reminders[idx].checked)
                                        .foregroundStyle(state.reminders[idx].checked ? .secondary : .primary)
                                    HStack(spacing: 8) {
                                        if !state.reminders[idx].project.isEmpty {
                                            Label(state.reminders[idx].project, systemImage: "folder")
                                        }
                                        if !state.reminders[idx].due.isEmpty {
                                            Label(state.reminders[idx].due, systemImage: "calendar")
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("#\(state.reminders[idx].id)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(idx % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Dismiss") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                let checkedCount = state.reminders.filter(\.checked).count
                Button("✓ Mark Done (\(checkedCount))") {
                    let ids = state.reminders.filter(\.checked).map(\.id)
                    state.markDone(ids)
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(checkedCount == 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: min(CGFloat(state.reminders.count) * 62 + 140, 500))
    }
}

@main
struct ZotRemindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first?.level = .floating
        NSApplication.shared.windows.first?.center()
    }
}
