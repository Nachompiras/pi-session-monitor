import SwiftUI

struct TerminalRowView: View {
    let session: SessionStatus
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.displayName)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(session.model.id)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
    }
    
    private var statusIndicator: some View {
        let color: Color
        let systemName: String
        
        switch session.state {
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
            .font(.system(size: 8))
    }
}
