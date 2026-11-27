// What the app and its helper say to each other. This one file is compiled
// into BOTH programs, so they can't disagree about the words.
//
// Why a helper at all: the hosts file belongs to the administrator (root), and
// an app run by a normal user may not change it. The helper is a tiny second
// program that macOS runs as root on the user's behalf, after the user has
// approved it once in System Settings. The app talks to it over XPC: a way for
// two programs on one Mac to call each other's functions. The helper can do
// exactly two things: block some sites until a time, and unblock them.

import Foundation

/// The helper's whole interface. `@objc` because XPC is an older Apple technology built on Objective-C.
///
/// Swift note: each function ends with a `reply` closure, because the answer comes back from the other
/// program later. `nil` as the error text means "worked".
@objc(NowboardFocusBlockHelper)
public protocol FocusBlockHelperProtocol {
    /// Blocks these host names until `until` (the helper cuts it to at most four hours and checks every name again).
    func block(domains: [String], until: Date, reply: @escaping (String?) -> Void)
    /// Takes the block out now.
    func unblock(reply: @escaping (String?) -> Void)
    /// When the current block ends, or nil if nothing is blocked.
    func activeUntil(reply: @escaping (Date?) -> Void)
}

/// The names both sides must agree on.
public enum FocusBlockHelperNames {
    /// The app.
    public static let appBundleID = "com.nestoririondo.nowboard.swiftui"
    /// The helper's own id, and the name of its XPC service (launchd listens on it).
    public static let helperBundleID = "com.nestoririondo.nowboard.swiftui.helper"
    public static let machServiceName = helperBundleID
    /// The launchd description file inside the app (`Contents/Library/LaunchDaemons`).
    public static let plistName = "\(helperBundleID).plist"
}
