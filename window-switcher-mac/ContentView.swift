//
//  ContentView.swift
//  window-switcher-mac
//
//  Created by 岐部龍太 on 2024/03/24.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack {
      Image(systemName: "globe")
        .imageScale(.large)
        .foregroundStyle(.tint)
      Text("Hello, world!")
    }
    .padding()
    .onAppear {
      let type = CGWindowListOption.optionOnScreenOnly
      let windowList = CGWindowListCopyWindowInfo(type, kCGNullWindowID) as NSArray? as? [[String: AnyObject]]
      
      for entry  in windowList ?? [] {
        let owner = entry[kCGWindowOwnerName as String] as! String
        var bounds = entry[kCGWindowBounds as String] as? [String: Int]
        let pid = entry[kCGWindowOwnerPID as String] as? Int32
        
        print("detected: \(owner)")
        if owner == "Microsoft Edge" {
          let appRef = AXUIElementCreateApplication(pid!);  //TopLevel Accessability Object of PID
          
          var value: AnyObject?
          let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
          if result != .success {
            fatalError("AXUIElementCopyAttributeValue is failed with \(result.rawValue)...")
          }
          
          if let windowList = value as? [AXUIElement], let window = windowList.first {
            var pid: pid_t = 0
            var result = AXUIElementGetPid(window, &pid)
            if result != .success {
              fatalError("AXUIElementGetPid is failed with \(result.rawValue)")
            }
            guard let app = NSRunningApplication(processIdentifier: pid) else {
              fatalError("NSRunningApplication(processIdentifier:) is failed")
            }
            if !app.activate(options: .activateIgnoringOtherApps) {
              fatalError("app.activate(options:) is failed")
            }
            result = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if result != .success {
              fatalError("Set kAXFocusedAttribute with AXUIElementSetAttributeValue is failed with \(result.rawValue)...")
            }
            //                print ("windowList #\(windowList)")
            //                if let window = windowList.first {
            //                  var position : CFTypeRef
            //                  var size : CFTypeRef
            //                  var newPoint = CGPoint(x: 0, y: 0)
            //                  var newSize = CGSize(width: 800, height: 800)
            //
            //                  position = AXValueCreate(AXValueType(rawValue: kAXValueCGPointType)!,&newPoint)!;
            //                  AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position);
            //
            //                  size = AXValueCreate(AXValueType(rawValue: kAXValueCGSizeType)!,&newSize)!;
            //                  AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, size);
            //                }
          }
        }
      }
    }
  }
}

#Preview {
  ContentView()
}
