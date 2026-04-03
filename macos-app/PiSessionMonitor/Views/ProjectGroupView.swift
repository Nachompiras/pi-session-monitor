import SwiftUI

struct ProjectGroupView: View {
    let cwd: String
    let sessions: [SessionStatus]
    @Binding var selectedSession: SessionStatus?
    @State private var isExpanded = true
    
    var projectName: String {
        let components = cwd.split(separator: "/")
        return String(components.last ?? "Unknown")
    }
    
    var needsApprovalCount: Int {
        sessions.filter { $0.state == .needsApproval }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text(projectName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    if needsApprovalCount > 0 {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Text("(\(sessions.count))")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            
            if isExpanded {
                ForEach(sessions) { session in
                    TerminalRowView(
                        session: session,
                        isSelected: selectedSession?.sessionId == session.sessionId
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSession = session
                    }
                }
            }
        }
    }
}
