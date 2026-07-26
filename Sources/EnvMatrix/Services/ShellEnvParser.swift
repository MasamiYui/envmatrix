import Foundation

public enum ShellEnvParser {
    public static func parse(_ text: String) -> ShellEnvDocument {
        let lineEnding: String = text.contains("\r\n") ? "\r\n" : "\n"
        let trailingNewline = text.hasSuffix(lineEnding) || text.hasSuffix("\n")

        var rawLines = text.components(separatedBy: lineEnding)
        if trailingNewline, let last = rawLines.last, last.isEmpty {
            rawLines.removeLast()
        }

        var entries: [ShellEnvEntry] = []
        for line in rawLines {
            if let entry = parseLine(line) {
                entries.append(entry)
            } else {
                entries.append(.unparsed(line))
            }
        }

        return ShellEnvDocument(
            entries: entries,
            lineEnding: lineEnding,
            trailingNewline: trailingNewline
        )
    }

    public static func serialize(_ doc: ShellEnvDocument) -> String {
        var parts: [String] = []
        parts.reserveCapacity(doc.entries.count)
        for entry in doc.entries {
            parts.append(serializeEntry(entry))
        }
        var output = parts.joined(separator: doc.lineEnding)
        if doc.trailingNewline {
            output += doc.lineEnding
        }
        return output
    }

    private static func serializeEntry(_ entry: ShellEnvEntry) -> String {
        switch entry {
        case .variable(let v):
            let prefix = v.isExported ? "export " : ""
            let quoted: String
            switch v.quoting {
            case .double: quoted = "\"\(v.value)\""
            case .single: quoted = "'\(v.value)'"
            case .none: quoted = v.value
            }
            return "\(prefix)\(v.key)=\(quoted)"
        case .pathAppend(let p):
            let joined = p.segments.joined(separator: ":")
            switch p.style {
            case .doubleQuoted:
                return "export PATH=\"$PATH:\(joined)\""
            case .unquoted:
                return "export PATH=$PATH:\(joined)"
            }
        case .unparsed(let s):
            return s
        }
    }

    private static func parseLine(_ line: String) -> ShellEnvEntry? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("#") { return nil }

        var scanner = Substring(trimmed)
        var isExported = false
        if scanner.hasPrefix("export ") || scanner.hasPrefix("export\t") {
            scanner = scanner.dropFirst("export".count)
            while let first = scanner.first, first == " " || first == "\t" {
                scanner = scanner.dropFirst()
            }
            isExported = true
        }

        guard let eqIndex = scanner.firstIndex(of: "=") else { return nil }
        let keyPart = scanner[scanner.startIndex..<eqIndex]
        let valuePart = scanner[scanner.index(after: eqIndex)..<scanner.endIndex]

        let key = String(keyPart)
        guard isValidKey(key) else { return nil }

        guard let parsedValue = parseValue(String(valuePart)) else { return nil }

        if key == "PATH" {
            if let pathAppend = detectPathAppend(value: parsedValue.raw, quoting: parsedValue.quoting) {
                return .pathAppend(pathAppend)
            }
        }

        let variable = ShellVariable(
            key: key,
            value: parsedValue.raw,
            quoting: parsedValue.quoting,
            isExported: isExported
        )
        return .variable(variable)
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first else { return false }
        if !(first.isLetter || first == "_") { return false }
        for ch in key.dropFirst() {
            if !(ch.isLetter || ch.isNumber || ch == "_") { return false }
        }
        return true
    }

    private struct ParsedValue {
        let raw: String
        let quoting: ShellQuoting
    }

    private static func parseValue(_ value: String) -> ParsedValue? {
        if value.hasPrefix("\"") {
            guard value.count >= 2, value.hasSuffix("\"") else { return nil }
            let inner = value.dropFirst().dropLast()
            if inner.contains("\"") { return nil }
            return ParsedValue(raw: String(inner), quoting: .double)
        }
        if value.hasPrefix("'") {
            guard value.count >= 2, value.hasSuffix("'") else { return nil }
            let inner = value.dropFirst().dropLast()
            if inner.contains("'") { return nil }
            return ParsedValue(raw: String(inner), quoting: .single)
        }
        if value.contains("\"") || value.contains("'") { return nil }
        return ParsedValue(raw: value, quoting: .none)
    }

    private static func detectPathAppend(value: String, quoting: ShellQuoting) -> ShellPathAppend? {
        let style: ShellPathAppend.Style
        switch quoting {
        case .double: style = .doubleQuoted
        case .none: style = .unquoted
        case .single: return nil
        }
        guard value.hasPrefix("$PATH:") else { return nil }
        let rest = value.dropFirst("$PATH:".count)
        if rest.isEmpty { return nil }
        let segments = rest.components(separatedBy: ":")
        for seg in segments where seg.isEmpty { return nil }
        return ShellPathAppend(segments: segments, style: style)
    }
}
