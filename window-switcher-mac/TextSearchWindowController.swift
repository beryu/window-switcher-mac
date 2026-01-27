import AppKit

class TextSearchWindow: NSWindow {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onCancel: (() -> Void)?
    
    // Only intercept arrow keys when in selection mode
    var isSelectionMode: Bool = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Only intercept navigation keys if we are in the special selection mode
            if isSelectionMode && !event.modifierFlags.contains(.command) {
                let chars = event.charactersIgnoringModifiers ?? ""
                
                // Vim-style navigation
                if chars == "j" || chars == "l" { // Down / Right -> Next
                    onMoveDown?()
                    return // Consume
                }
                if chars == "k" || chars == "h" { // Up / Left -> Prev
                    onMoveUp?()
                    return // Consume
                }
                
                // Arrow Keys (Fallback)
                if event.keyCode == 126 { // Arrow Up
                    onMoveUp?()
                    return // Consume event (No beep)
                }
                if event.keyCode == 125 { // Arrow Down
                    onMoveDown?()
                    return // Consume event (No beep)
                }
            }
            
            // Escape always cancels
            if event.keyCode == 53 { // Escape
                 // Check modifiers? standard Escape usually has no modifiers or maybe option?
                 if !event.modifierFlags.contains(.command) { // Allow Cmd+Esc to pass? Usually Cmd+Esc shows Front Row or something legacy? System takes it. 
                     // Just intercept standard Escape
                     onCancel?()
                     return
                 }
            }
        }
        super.sendEvent(event)
    }
}

/// Floating window controller for text search input (Spotlight-style)
/// Uses NSSearchField for proper native behavior
final class TextSearchWindowController: NSObject, NSTextFieldDelegate {
    private var window: TextSearchWindow? // Update type
    private var textField: NSTextField?
    private var matchCountLabel: NSTextField?
    
    var onTextChanged: ((String) -> Void)?
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    
    // Proxy for window state
    var isSelectionMode: Bool = false {
        didSet {
            window?.isSelectionMode = isSelectionMode
        }
    }
    
    override init() {
        super.init()
    }
    
    func show() {
        if window == nil {
            createWindow()
        }
        
        guard let window = window else { return }
        
        // Position at top center of main screen
        if let screen = NSScreen.main {
            let windowWidth: CGFloat = 600
            let windowHeight: CGFloat = 60
            let x = (screen.frame.width - windowWidth) / 2 + screen.frame.origin.x
            let y = screen.frame.maxY - windowHeight - 120
            window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
        }
        
        // Show and focus
        // Order: Activate app -> Make key and order front -> Make first responder
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        if let textField = textField {
            // Ensure search field is enabled and editable
            textField.isEnabled = true
            textField.isEditable = true
            window.makeFirstResponder(textField)
            
            // Force reset input state
            textField.stringValue = ""
            if let editor = textField.currentEditor() {
                editor.string = ""
                editor.selectedRange = NSRange(location: 0, length: 0)
            }
        }
        
        updateMatchCount(0)
    }
    
    func hide() {
        window?.orderOut(nil)
    }
    
    func updateMatchCount(_ count: Int) {
        matchCountLabel?.stringValue = count > 0 ? "\(count) matches" : ""
    }
    
    private func createWindow() {
        // Create borderless floating window
        let window = TextSearchWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        
        // Wire up events directly to window
        window.onMoveUp = { [weak self] in self?.onMoveUp?() }
        window.onMoveDown = { [weak self] in self?.onMoveDown?() }
        window.onCancel = { [weak self] in self?.onCancel?() }
        window.isSelectionMode = isSelectionMode // Sync initial state
        
        // Create content view with rounded corners
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.95).cgColor
        contentView.layer?.cornerRadius = 10
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor(white: 0.3, alpha: 0.5).cgColor
        
        // Custom search icon
        let searchIcon = NSImageView(frame: NSRect(x: 20, y: 18, width: 24, height: 24))
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search") 
            ?? NSImage(named: NSImage.touchBarSearchTemplateName)
        searchIcon.imageScaling = .scaleProportionallyUpOrDown
        searchIcon.contentTintColor = .lightGray
        contentView.addSubview(searchIcon)
        
        // Create search field (using NSTextField for custom layout)
        let textField = NSTextField(frame: NSRect(x: 52, y: 12, width: 420, height: 36))
        textField.placeholderString = "Window Search..."
        textField.font = NSFont.systemFont(ofSize: 22, weight: .regular)
        textField.textColor = .white
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.isBordered = false
        textField.isBezeled = false
        textField.delegate = self
        // Remove default action to prevent firing during IME confirmation
        // searchField.action = #selector(textFieldAction(_:))
        
        self.textField = textField
        contentView.addSubview(textField)
        
        // Create match count label
        let matchCountLabel = NSTextField(frame: NSRect(x: 480, y: 18, width: 100, height: 24))
        matchCountLabel.isEditable = false
        matchCountLabel.isBordered = false
        matchCountLabel.backgroundColor = .clear
        matchCountLabel.textColor = .gray
        matchCountLabel.font = NSFont.systemFont(ofSize: 14)
        matchCountLabel.alignment = .right
        self.matchCountLabel = matchCountLabel
        contentView.addSubview(matchCountLabel)
        
        window.contentView = contentView
        self.window = window
    }
    
    // MARK: - NSSearchFieldDelegate / NSTextFieldDelegate
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Handle Enter key manually to distinguish between IME confirmation and Search submit
            if textView.hasMarkedText() {
                // IME composition is active, let system handle the confirmation
                print("TextSearchWindow: Enter key ignored (in IME composition)")
                return false
            } else {
                // No IME composition, trigger search submit
                print("TextSearchWindow: Enter key pressed (submit)")
                onSubmit?()
                return true
            }
        }
        
        return false
    }
    
    // MARK: - NSTextFieldDelegate
    
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        
        // Use currentEditor string to capture IME confirmed/unconfirmed text
        // Fallback to stringValue if editor is not available
        let text = textField.currentEditor()?.string ?? textField.stringValue
        print("TextSearchWindow: Text changed to '\(text)' (stringValue: '\(textField.stringValue)')")
        onTextChanged?(text)
    }
}
