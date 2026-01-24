import Cocoa
import Carbon.HIToolbox

/// A native global hotkey manager using CGEvent tap
final class GlobalHotKeyManager {
  typealias Handler = () -> Void
  typealias KeyHandler = (String) -> Void
  
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private let hotKeyHandler: Handler
  private let keyCode: CGKeyCode
  private let modifiers: UInt64
  
  // Overlay mode handlers
  private var overlayKeyHandler: KeyHandler?
  private var overlayEscapeHandler: Handler?
  private var isOverlayActive: Bool = false
  
  // Carbon modifier flag masks
  public static let kCommandKeyMask: UInt64 = 0x00100000
  public static let kShiftKeyMask: UInt64 = 0x00020000
  public static let kOptionKeyMask: UInt64 = 0x00080000   // Option/Alt key
  public static let kControlKeyMask: UInt64 = 0x00040000
  
  init?(keyCode: CGKeyCode, modifiers: UInt64, handler: @escaping Handler) {
    self.hotKeyHandler = handler
    self.keyCode = keyCode
    self.modifiers = modifiers
    
    // Check accessibility permissions
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
      print("GlobalHotKeyManager: Accessibility permissions not granted")
      return nil
    }
    
    // Create a context object to pass to the callback
    let contextPtr = UnsafeMutablePointer<HotKeyContext>.allocate(capacity: 1)
    contextPtr.initialize(to: HotKeyContext(manager: self))
    
    // Create event tap for keyDown events
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
      callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
        guard let refcon = refcon else {
          return Unmanaged.passRetained(event)
        }
        
        let context = refcon.assumingMemoryBound(to: HotKeyContext.self).pointee
        guard let manager = context.manager else {
          return Unmanaged.passRetained(event)
        }
        
        // Get key code and modifiers
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierFlags = event.flags.rawValue
        
        // Check modifiers
        let hasCommand = (modifierFlags & GlobalHotKeyManager.kCommandKeyMask) != 0
        let hasShift = (modifierFlags & GlobalHotKeyManager.kShiftKeyMask) != 0
        let hasOption = (modifierFlags & GlobalHotKeyManager.kOptionKeyMask) != 0
        let hasControl = (modifierFlags & GlobalHotKeyManager.kControlKeyMask) != 0
        
        // Calculate current modifiers mask
        var currentModifiers: UInt64 = 0
        if hasCommand { currentModifiers |= GlobalHotKeyManager.kCommandKeyMask }
        if hasShift { currentModifiers |= GlobalHotKeyManager.kShiftKeyMask }
        if hasOption { currentModifiers |= GlobalHotKeyManager.kOptionKeyMask }
        if hasControl { currentModifiers |= GlobalHotKeyManager.kControlKeyMask }
        
        // Handle trigger hotkey (always active)
        if eventKeyCode == manager.keyCode {
          // Check if modifiers match exactly
          if currentModifiers == manager.modifiers {
            print("GlobalHotKeyManager: Hotkey detected! Calling handler.")
            DispatchQueue.main.async {
              manager.hotKeyHandler()
            }
            // Consume the event so it doesn't propagate
            return nil
          }
        }
        
        // Handle overlay mode key capture
        if manager.isOverlayActive {
          // No modifiers should be pressed for overlay key handling
          if !hasCommand && !hasShift && !hasOption && !hasControl {
            // Handle Escape key to close overlay
            if eventKeyCode == CGKeyCode(kVK_Escape) {
              print("GlobalHotKeyManager: Escape detected during overlay, closing.")
              DispatchQueue.main.async {
                manager.overlayEscapeHandler?()
              }
              return nil
            }
            
            // Convert key code to character
            if let character = manager.keyCodeToCharacter(eventKeyCode) {
              print("GlobalHotKeyManager: Key '\(character)' captured during overlay.")
              DispatchQueue.main.async {
                manager.overlayKeyHandler?(character)
              }
              return nil
            }
          }
          
          // During overlay mode, consume all key events to prevent other apps from receiving them
          return nil
        }
        
        return Unmanaged.passRetained(event)
      },
      userInfo: contextPtr
    ) else {
      print("GlobalHotKeyManager: Failed to create event tap. Check accessibility permissions.")
      contextPtr.deallocate()
      return nil
    }
    
    self.eventTap = tap
    
    // Create run loop source and add to main run loop
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    self.runLoopSource = source
    
    // Add to the MAIN run loop
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    
    // Enable the event tap
    CGEvent.tapEnable(tap: tap, enable: true)
    
    print("GlobalHotKeyManager: Successfully registered hotkey")
  }
  
  /// Enable overlay mode to capture all keyboard input
  func enableOverlayMode(keyHandler: @escaping KeyHandler, escapeHandler: @escaping Handler) {
    self.overlayKeyHandler = keyHandler
    self.overlayEscapeHandler = escapeHandler
    self.isOverlayActive = true
    print("GlobalHotKeyManager: Overlay mode enabled - capturing all keyboard input")
  }
  
  /// Disable overlay mode and stop capturing all keyboard input
  func disableOverlayMode() {
    self.isOverlayActive = false
    self.overlayKeyHandler = nil
    self.overlayEscapeHandler = nil
    print("GlobalHotKeyManager: Overlay mode disabled")
  }
  
  /// Convert CGKeyCode to character string
  private func keyCodeToCharacter(_ keyCode: CGKeyCode) -> String? {
    // Map of key codes to characters (US keyboard layout)
    let keyMap: [CGKeyCode: String] = [
      // Letters
      CGKeyCode(kVK_ANSI_A): "a",
      CGKeyCode(kVK_ANSI_B): "b",
      CGKeyCode(kVK_ANSI_C): "c",
      CGKeyCode(kVK_ANSI_D): "d",
      CGKeyCode(kVK_ANSI_E): "e",
      CGKeyCode(kVK_ANSI_F): "f",
      CGKeyCode(kVK_ANSI_G): "g",
      CGKeyCode(kVK_ANSI_H): "h",
      CGKeyCode(kVK_ANSI_I): "i",
      CGKeyCode(kVK_ANSI_J): "j",
      CGKeyCode(kVK_ANSI_K): "k",
      CGKeyCode(kVK_ANSI_L): "l",
      CGKeyCode(kVK_ANSI_M): "m",
      CGKeyCode(kVK_ANSI_N): "n",
      CGKeyCode(kVK_ANSI_O): "o",
      CGKeyCode(kVK_ANSI_P): "p",
      CGKeyCode(kVK_ANSI_Q): "q",
      CGKeyCode(kVK_ANSI_R): "r",
      CGKeyCode(kVK_ANSI_S): "s",
      CGKeyCode(kVK_ANSI_T): "t",
      CGKeyCode(kVK_ANSI_U): "u",
      CGKeyCode(kVK_ANSI_V): "v",
      CGKeyCode(kVK_ANSI_W): "w",
      CGKeyCode(kVK_ANSI_X): "x",
      CGKeyCode(kVK_ANSI_Y): "y",
      CGKeyCode(kVK_ANSI_Z): "z",
      // Numbers
      CGKeyCode(kVK_ANSI_0): "0",
      CGKeyCode(kVK_ANSI_1): "1",
      CGKeyCode(kVK_ANSI_2): "2",
      CGKeyCode(kVK_ANSI_3): "3",
      CGKeyCode(kVK_ANSI_4): "4",
      CGKeyCode(kVK_ANSI_5): "5",
      CGKeyCode(kVK_ANSI_6): "6",
      CGKeyCode(kVK_ANSI_7): "7",
      CGKeyCode(kVK_ANSI_8): "8",
      CGKeyCode(kVK_ANSI_9): "9",
    ]
    return keyMap[keyCode]
  }
  
  deinit {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    print("GlobalHotKeyManager: Deinitialized")
  }
}

// MARK: - Context wrapper for callback
private struct HotKeyContext {
  weak var manager: GlobalHotKeyManager?
}

// MARK: - Convenience initializer
extension GlobalHotKeyManager {
  /// Creates a hotkey for Control + Escape
  static func controlEscape(handler: @escaping Handler) -> GlobalHotKeyManager? {
    // kVK_Escape = 0x35 (53)
    return GlobalHotKeyManager(
      keyCode: CGKeyCode(kVK_Escape),
      modifiers: kControlKeyMask,
      handler: handler
    )
  }
    
  /// Creates a hotkey for Option + Escape
  static func optionEscape(handler: @escaping Handler) -> GlobalHotKeyManager? {
    // kVK_Escape = 0x35 (53)
    return GlobalHotKeyManager(
      keyCode: CGKeyCode(kVK_Escape),
      modifiers: kOptionKeyMask,
      handler: handler
    )
  }
    
  /// Creates a hotkey for Command + Shift + S
  static func commandShiftS(handler: @escaping Handler) -> GlobalHotKeyManager? {
    // kVK_ANSI_S = 0x01 (1)
    return GlobalHotKeyManager(
      keyCode: CGKeyCode(kVK_ANSI_S),
      modifiers: kCommandKeyMask | kShiftKeyMask,
      handler: handler
    )
  }
    
  /// Creates a hotkey for Control + Option + Escape
  static func controlOptionEscape(handler: @escaping Handler) -> GlobalHotKeyManager? {
    // kVK_Escape = 0x35 (53)
    return GlobalHotKeyManager(
      keyCode: CGKeyCode(kVK_Escape),
      modifiers: kControlKeyMask | kOptionKeyMask,
      handler: handler
    )
  }
}
