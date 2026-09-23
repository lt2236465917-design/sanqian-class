//
//  AppConstants.swift
//  Runner
//
//  Centralized app configuration constants
//

import Foundation

/// The only App Group id is the `ScheduleAppGroup` build setting baked into Info.plist.
enum ScheduleAppGroup {
    static let fallback = "group.local.chaoxi.schedule"

    static func resolve(_ infoValue: String?) -> String {
        let value = infoValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.hasPrefix("group."), !value.contains("$") else { return fallback }
        return value
    }

    static var identifier: String {
        resolve(Bundle.main.object(forInfoDictionaryKey: "ScheduleAppGroup") as? String)
    }
}

let kAppGroupIdentifier = ScheduleAppGroup.identifier