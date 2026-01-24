import Cocoa
import Carbon.HIToolbox

/// A native global hotkey manager using CGEvent tap
final class GlobalHotKeyManager {
  typealias Handler = () -> Void
  
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private let handler: Handler
  private let keyCode: CGKeyCode
  
  // Carbon modifier flag masks
  private static let kCommandKeyMask: UInt64 = 0x00100000
  private static let kShiftKeyMask: UInt64 = 0x00020000
  private static let kOptionKeyMask: UInt64 = 0x00080000   // Option/Alt key
  private static let kControlKeyMask: UInt64 = 0x00040000
  
  init?(keyCode: CGKeyCode, handler: @escaping Handler) {
    self.handler = handler
    self.keyCode = keyCode
    
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
        
        // Check if this is the Escape key
        if eventKeyCode == manager.keyCode {
          // Check modifiers using raw bitmask
          let hasCommand = (modifierFlags & GlobalHotKeyManager.kCommandKeyMask) != 0
          let hasShift = (modifierFlags & GlobalHotKeyManager.kShiftKeyMask) != 0
          let hasOption = (modifierFlags & GlobalHotKeyManager.kOptionKeyMask) != 0
          let hasControl = (modifierFlags & GlobalHotKeyManager.kControlKeyMask) != 0
          
           // Only Control should be pressed (no other modifiers)
          if hasControl && !hasShift && !hasCommand && !hasOption {
            print("GlobalHotKeyManager: Control+Escape detected! Calling handler.")
            DispatchQueue.main.async {
              manager.handler()
            }
            // Consume the event so it doesn't propagate
            return nil
          }
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
    
    print("GlobalHotKeyManager: Successfully registered hotkey Control+Escape")
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

// MARK: - Convenience initializer for Control+Escape
extension GlobalHotKeyManager {
  /// Creates a hotkey for Control + Escape
  static func controlEscape(handler: @escaping Handler) -> GlobalHotKeyManager? {
    // kVK_Escape = 0x35 (53)
    return GlobalHotKeyManager(
      keyCode: CGKeyCode(kVK_Escape),
      handler: handler
    )
  }
}
