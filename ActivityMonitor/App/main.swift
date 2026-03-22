// main.swift
// ActivityMonitor
//
// Manual entry point for the application.
//
// We use main.swift instead of @main / @NSApplicationMain so that we have
// full control over NSApplication initialisation order and can keep
// AppDelegate free of any special annotations.
//
// IMPORTANT: Only ONE file in a Swift target may be named "main.swift".
// Do not rename or duplicate this file.

import AppKit

// Instantiate the shared application and hook up our delegate.
let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Activation policy is also enforced by LSUIElement = YES in Info.plist,
// but setting it here provides a belt-and-suspenders guarantee: the app
// will never appear in the Dock even if the plist key is accidentally removed.
app.setActivationPolicy(.accessory)

// Blocks until the app terminates.
app.run()
