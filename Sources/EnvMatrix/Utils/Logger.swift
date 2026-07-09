import Foundation
import os

public enum AppLog {
    public static let subsystem = "com.envmatrix.app"

    public static func general() -> Logger {
        Logger(subsystem: subsystem, category: "general")
    }
}
