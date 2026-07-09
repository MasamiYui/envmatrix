import Foundation
import SwiftUI

public enum LogLevel: String, Codable, Hashable, CaseIterable {
    case info
    case warning
    case error

    public var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    public var systemImage: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }
}

public struct LogEntry: Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

@MainActor
public final class LogStore: ObservableObject {
    public static let shared = LogStore()

    public static let maxEntries = 500

    @Published public var entries: [LogEntry] = []

    public init() {}

    public func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    public func log(_ level: LogLevel, _ message: String) {
        append(LogEntry(level: level, message: message))
    }

    public func clear() {
        entries.removeAll()
    }

    public static func log(_ level: LogLevel, _ message: String) {
        LogStore.shared.log(level, message)
    }
}
