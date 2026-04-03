import Foundation

struct ModelInfo: Codable {
    let provider: String
    let id: String
    let thinkingLevel: String
}

struct PendingApproval: Codable {
    let toolCallId: String
    let toolName: String
    let description: String
    let timestamp: TimeInterval
}

struct SessionStatus: Codable, Identifiable {
    let sessionId: String
    let sessionName: String?
    let cwd: String
    let port: Int
    let token: String
    let model: ModelInfo
    let state: SessionState
    let lastActivity: TimeInterval
    let lastMessage: String
    let pendingApproval: PendingApproval?
    
    var id: String { sessionId }
    
    var displayName: String {
        sessionName ?? "Terminal \(port)"
    }
    
    var projectName: String {
        let components = cwd.split(separator: "/")
        return String(components.last ?? "Unknown")
    }
}

enum SessionState: String, Codable {
    case idle
    case thinking
    case executing
    case needsApproval = "needs_approval"
}

struct ServerEvent: Codable {
    let type: String
    let status: SessionStatus?
    let model: ModelInfo?
    let state: SessionState?
    let toolCall: PendingApproval?
    let toolCallId: String?
    let approved: Bool?
    let preview: String?
}

struct RegistryEntry: Codable {
    let sessionId: String
    let port: Int
    let cwd: String
    let token: String
    let startedAt: TimeInterval
}

struct Registry: Codable {
    let version: Int
    let servers: [RegistryEntry]
}
