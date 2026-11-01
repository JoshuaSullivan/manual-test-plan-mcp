//
//  AppDelegate.swift
//  ManualTestPlan
//

import AppKit

/// Makes sure debounced saves reach disk before the app quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the app once its model exists.
    var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store = model?.store else { return .terminateNow }
        Task {
            await store.flushPendingSaves()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
