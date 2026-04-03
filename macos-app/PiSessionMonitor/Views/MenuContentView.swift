import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selectedSession: SessionStatus?
    @State private var messageText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with count
            headerView
            
            Divider()
            
            // Session list grouped by project
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.groupedSessions.keys.sorted(), id: \.self) { cwd in
                        if let sessions = store.groupedSessions[cwd] {
                            ProjectGroupView(
                                cwd: cwd,
                                sessions: sessions,
                                selectedSession: $selectedSession
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 250)
            
            Divider()
            
            // Action panel for selected session
            if let session = selectedSession {
                actionPanel(for: session)
                    .padding(12)
                    .frame(height: 120)
            } else {
                Text("Select a session to view actions")
                    .foregroundColor(.secondary)
                    .frame(height: 120)
            }
            
            if let error = store.errorMessage {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
            }
        }
        .frame(width: 380)
    }
    
    private var headerView: some View {
        HStack {
            Text("Pi Sessions")
                .font(.headline)
            Spacer()
            if store.needsApprovalCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text("\(store.needsApprovalCount)")
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                }
            }
            Text("\(store.sessions.count) active")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func actionPanel(for session: SessionStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with name and focus button
            HStack {
                Text(session.displayName)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Button("Focus") {
                    store.focusTerminal(port: session.port)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            // Model info
            HStack(spacing: 4) {
                statusIndicator(for: session.state)
                Text(session.model.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Action controls based on state
            if session.state == .needsApproval, let approval = session.pendingApproval {
                // Approval controls
                VStack(alignment: .leading, spacing: 4) {
                    Text(approval.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    HStack {
                        Button("Approve") {
                            store.approveTool(sessionId: session.sessionId, toolCallId: approval.toolCallId)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                        
                        Button("Reject") {
                            store.rejectTool(sessionId: session.sessionId, toolCallId: approval.toolCallId)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
                .padding(6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            } else {
                // Message input and abort
                HStack {
                    TextField("Send message...", text: $messageText)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Send") {
                        store.sendMessage(sessionId: session.sessionId, content: messageText)
                        messageText = ""
                    }
                    .disabled(messageText.isEmpty)
                    .controlSize(.small)
                    
                    if session.state == .thinking || session.state == .executing {
                        Button("Abort") {
                            store.abortSession(sessionId: session.sessionId)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                }
            }
        }
    }
    
    private func statusIndicator(for state: SessionState) -> some View {
        let color: Color
        let systemName: String
        
        switch state {
        case .idle:
            color = .green
            systemName = "circle.fill"
        case .thinking:
            color = .yellow
            systemName = "circle.dashed"
        case .executing:
            color = .blue
            systemName = "circle.hexagongrid.fill"
        case .needsApproval:
            color = .red
            systemName = "pause.circle.fill"
        }
        
        return Image(systemName: systemName)
            .foregroundColor(color)
            .font(.caption)
    }
}
