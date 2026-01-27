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
          // Handle Escape key to close overlay (allow with no modifiers)
          if eventKeyCode == CGKeyCode(kVK_Escape) && !hasCommand && !hasShift && !hasOption && !hasControl {
            print("GlobalHotKeyManager: Escape detected during overlay, closing.")
            DispatchQueue.main.async {
              manager.overlayEscapeHandler?()
            }
            return nil
          }
          
          // If no key handler is set, pass through all key events to the app (for TextField input)
          // This allows Backspace, Return, and normal typing to reach the NSTextField
          guard manager.overlayKeyHandler != nil else {
            return Unmanaged.passRetained(event)
          }
          
          // Handle Backspace key
          if eventKeyCode == CGKeyCode(kVK_Delete) && !hasCommand && !hasOption && !hasControl {
            print("GlobalHotKeyManager: Backspace detected during overlay.")
            DispatchQueue.main.async {
              manager.overlayKeyHandler?("\u{08}")  // Backspace character
            }
            return nil
          }
          
          // Handle Return key
          if (eventKeyCode == CGKeyCode(kVK_Return) || eventKeyCode == CGKeyCode(kVK_ANSI_KeypadEnter)) && !hasCommand && !hasOption && !hasControl {
            print("GlobalHotKeyManager: Return detected during overlay.")
            DispatchQueue.main.async {
              manager.overlayKeyHandler?("\n")
            }
            return nil
          }
          
          // Get Unicode characters from the event (supports IME input including Japanese)
          if !hasCommand && !hasControl {
            var actualStringLength: Int = 0
            var unicodeString = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &actualStringLength, unicodeString: &unicodeString)
            
            if actualStringLength > 0 {
              let chars = unicodeString.prefix(actualStringLength)
              let character = String(utf16CodeUnits: Array(chars), count: actualStringLength)
              
              if !character.isEmpty {
                print("GlobalHotKeyManager: Unicode character '\(character)' captured during overlay.")
                DispatchQueue.main.async {
                  manager.overlayKeyHandler?(character)
                }
                return nil
              }
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
  /// If keyHandler is nil, key events will be passed through (for TextField input)
  func enableOverlayMode(keyHandler: KeyHandler?, escapeHandler: @escaping Handler) {
    self.overlayKeyHandler = keyHandler
    self.overlayEscapeHandler = escapeHandler
    self.isOverlayActive = true
    print("GlobalHotKeyManager: Overlay mode enabled - \(keyHandler != nil ? "capturing" : "passing through") keyboard input")
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
      // Special Keys
      CGKeyCode(kVK_Return): "\n",
      CGKeyCode(kVK_ANSI_KeypadEnter): "\n",
      CGKeyCode(kVK_Space): " ",
      CGKeyCode(kVK_Delete): "\u{08}",  // Backspace
      // Symbols
      CGKeyCode(kVK_ANSI_Minus): "-",
      CGKeyCode(kVK_ANSI_Equal): "=",
      CGKeyCode(kVK_ANSI_LeftBracket): "[",
      CGKeyCode(kVK_ANSI_RightBracket): "]",
      CGKeyCode(kVK_ANSI_Semicolon): ";",
      CGKeyCode(kVK_ANSI_Quote): "'",
      CGKeyCode(kVK_ANSI_Comma): ",",
      CGKeyCode(kVK_ANSI_Period): ".",
      CGKeyCode(kVK_ANSI_Slash): "/",
      CGKeyCode(kVK_ANSI_Backslash): "\\",
      CGKeyCode(kVK_ANSI_Grave): "`",
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
    
  /// Creates a hotkey for Control + / (slash)
  static func controlSlash(handler: @escaping Handler) -> GlobalHotKeyManager? {
    // kVK_ANSI_Slash = 0x2C (44)
    return GlobalHotKeyManager(
      keyCode: CGKeyCode(kVK_ANSI_Slash),
      modifiers: kControlKeyMask,
      handler: handler
    )
  }
}
