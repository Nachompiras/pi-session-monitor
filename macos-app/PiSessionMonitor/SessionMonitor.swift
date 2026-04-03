import Foundation
import UserNotifications

class SessionMonitor {
    private let entry: RegistryEntry
    private var webSocketTask: URLSessionWebSocketTask?
    private var currentStatus: SessionStatus?
    
    var onUpdate: ((SessionStatus) -> Void)?
    
    init(entry: RegistryEntry) {
        self.entry = entry
    }
    
    func connect() {
        // First fetch current status via HTTP
        fetchStatus { [weak self] result in
            if case .success(let status) = result {
                self?.currentStatus = status
                self?.onUpdate?(status)
                // Then connect WebSocket for real-time updates
                self?.connectWebSocket()
            }
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel()
        webSocketTask = nil
    }
    
    private func fetchStatus(completion: @escaping (Result<SessionStatus, Error>) -> Void) {
        let url = URL(string: "http://127.0.0.1:\(entry.port)/status")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: -1)))
                return
            }
            
            do {
                let status = try JSONDecoder().decode(SessionStatus.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(status))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func connectWebSocket() {
        let url = URL(string: "ws://127.0.0.1:\(entry.port)/events")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self?.handleWebSocketMessage(text)
                }
                self?.receiveMessage() // Continue listening
            case .failure(let error):
                print("WebSocket error: \(error)")
            }
        }
    }
    
    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(ServerEvent.self, from: data) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            switch event.type {
            case "status_update":
                if let status = event.status {
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            case "model_changed":
                if let model = event.model, var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: model,
                        state: status.state,
                        lastActivity: status.lastActivity,
                        lastMessage: status.lastMessage,
                        pendingApproval: status.pendingApproval
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            case "state_changed":
                if let state = event.state, var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: status.model,
                        state: state,
                        lastActivity: Date().timeIntervalSince1970 * 1000,
                        lastMessage: status.lastMessage,
                        pendingApproval: status.pendingApproval
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            case "approval_needed":
                if let toolCall = event.toolCall, var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: status.model,
                        state: .needsApproval,
                        lastActivity: Date().timeIntervalSince1970 * 1000,
                        lastMessage: status.lastMessage,
                        pendingApproval: toolCall
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                    
                    // Post notification
                    self?.postNotification(title: "Pi Approval Needed", body: toolCall.description)
                }
            case "approval_resolved":
                if var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: status.model,
                        state: .idle,
                        lastActivity: Date().timeIntervalSince1970 * 1000,
                        lastMessage: status.lastMessage,
                        pendingApproval: nil
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            case "message_received":
                if let preview = event.preview, var status = self?.currentStatus {
                    status = SessionStatus(
                        sessionId: status.sessionId,
                        sessionName: status.sessionName,
                        cwd: status.cwd,
                        port: status.port,
                        token: status.token,
                        model: status.model,
                        state: status.state,
                        lastActivity: Date().timeIntervalSince1970 * 1000,
                        lastMessage: preview,
                        pendingApproval: status.pendingApproval
                    )
                    self?.currentStatus = status
                    self?.onUpdate?(status)
                }
            default:
                break
            }
        }
    }
    
    private func postNotification(title: String, body: String) {
        let notification = UNMutableNotificationContent()
        notification.title = title
        notification.body = body
        notification.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notification,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Actions
    
    func sendMessage(_ content: String) {
        guard let url = URL(string: "http://127.0.0.1:\(entry.port)/message") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["content": content])
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func abort() {
        guard let url = URL(string: "http://127.0.0.1:\(entry.port)/abort") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func approve(toolCallId: String) {
        guard let url = URL(string: "http://127.0.0.1:\(entry.port)/approve") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["toolCallId": toolCallId])
        
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func reject(toolCallId: String, reason: String) {
        guard let url = URL(string: "http://127.0.0.1:\(entry.port)/reject") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(entry.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["toolCallId": toolCallId, "reason": reason])
        
        URLSession.shared.dataTask(with: request).resume()
    }
}
