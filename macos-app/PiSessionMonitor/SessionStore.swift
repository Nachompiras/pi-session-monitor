import Foundation
import Combine

class SessionStore: ObservableObject {
    @Published var sessions: [SessionStatus] = []
    @Published var errorMessage: String?
    
    private var monitors: [String: SessionMonitor] = [:]
    private let registryPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".pi/agent/.session-servers.json")
    
    var groupedSessions: [String: [SessionStatus]] {
        Dictionary(grouping: sessions) { $0.cwd }
    }
    
    var needsApprovalCount: Int {
        sessions.filter { $0.state == .needsApproval }.count
    }
    
    func refreshSessions() {
        do {
            let data = try Data(contentsOf: registryPath)
            let registry = try JSONDecoder().decode(Registry.self, from: data)
            
            // Remove sessions no longer in registry
            let currentIds = Set(registry.servers.map { $0.sessionId })
            let removedIds = Set(monitors.keys).subtracting(currentIds)
            
            for id in removedIds {
                monitors[id]?.disconnect()
                monitors.removeValue(forKey: id)
                sessions.removeAll { $0.sessionId == id }
            }
            
            // Add new sessions
            for entry in registry.servers {
                if monitors[entry.sessionId] == nil {
                    let monitor = SessionMonitor(entry: entry)
                    monitor.onUpdate = { [weak self] status in
                        self?.updateSession(status)
                    }
                    monitor.connect()
                    monitors[entry.sessionId] = monitor
                }
            }
        } catch {
            errorMessage = "Failed to read registry: \(error.localizedDescription)"
        }
    }
    
    private func updateSession(_ status: SessionStatus) {
        if let index = sessions.firstIndex(where: { $0.sessionId == status.sessionId }) {
            sessions[index] = status
        } else {
            sessions.append(status)
        }
    }
    
    // MARK: - Actions
    
    func sendMessage(sessionId: String, content: String) {
        monitors[sessionId]?.sendMessage(content)
    }
    
    func abortSession(sessionId: String) {
        monitors[sessionId]?.abort()
    }
    
    func approveTool(sessionId: String, toolCallId: String) {
        monitors[sessionId]?.approve(toolCallId: toolCallId)
    }
    
    func rejectTool(sessionId: String, toolCallId: String, reason: String = "Rejected by user") {
        monitors[sessionId]?.reject(toolCallId: toolCallId, reason: reason)
    }
    
    func focusTerminal(port: Int) {
        // Use AppleScript to bring terminal with pi to front
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if (custom title of t as string) contains "pi-\(port)" or (custom title of t as string) contains "Terminal" then
                        set selected tab of w to t
                        set frontmost of w to true
                        return
                    end if
                end repeat
            end repeat
            -- If not found, just activate Terminal
            activate
        end tell
        """
        
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
        }
    }
}
