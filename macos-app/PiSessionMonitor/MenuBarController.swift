import SwiftUI
import AppKit
import Combine

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var sessionStore = SessionStore()
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        
        super.init()
        
        setupMenuBar()
        setupPopover()
        startPolling()
        
        // Update badge when approval count changes
        sessionStore.$needsApprovalCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.updateBadge(count: count)
            }
            .store(in: &cancellables)
    }
    
    private func setupMenuBar() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Pi Sessions")
        }
        
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
    }
    
    private func setupPopover() {
        popover.contentSize = NSSize(width: 350, height: 400)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuContentView().environmentObject(sessionStore)
        )
    }
    
    @objc private func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    private func startPolling() {
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sessionStore.refreshSessions()
        }
        
        // Initial refresh
        sessionStore.refreshSessions()
    }
    
    private func updateBadge(count: Int) {
        if let button = statusItem.button {
            if count > 0 {
                button.image = NSImage(systemSymbolName: "terminal.fill.badge.exclamationmark", accessibilityDescription: "Pi Sessions Need Attention")
                button.contentTintColor = .systemRed
            } else {
                button.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Pi Sessions")
                button.contentTintColor = nil
            }
        }
    }
}
