import Foundation

public enum HostsParser {
    public static func parse(_ text: String) -> HostsDocument {
        let lineEnding: String = text.contains("\r\n") ? "\r\n" : "\n"
        let trailingNewline = text.hasSuffix(lineEnding) || text.hasSuffix("\n")

        var rawLines = text.components(separatedBy: lineEnding)
        if trailingNewline, let last = rawLines.last, last.isEmpty {
            rawLines.removeLast()
        }

        var lines: [HostsLine] = []
        lines.reserveCapacity(rawLines.count)
        for line in rawLines {
            lines.append(parseLine(line))
        }
        return HostsDocument(
            lines: lines,
            lineEnding: lineEnding,
            trailingNewline: trailingNewline
        )
    }

    public static func serialize(_ doc: HostsDocument) -> String {
        var parts: [String] = []
        parts.reserveCapacity(doc.lines.count)
        for line in doc.lines {
            parts.append(serializeLine(line))
        }
        var output = parts.joined(separator: doc.lineEnding)
        if doc.trailingNewline {
            output += doc.lineEnding
        }
        return output
    }

    private static func serializeLine(_ line: HostsLine) -> String {
        switch line {
        case .entry(let e):
            var head = e.isEnabled ? "" : "#"
            head += e.ip
            let host = e.hostnames.joined(separator: " ")
            let body = host.isEmpty ? head : "\(head) \(host)"
            if let comment = e.comment, !comment.isEmpty {
                return "\(body) # \(comment)"
            }
            return body
        case .comment(let s):
            return s
        case .blank:
            return ""
        case .unparsed(let s):
            return s
        }
    }

    private static func parseLine(_ line: String) -> HostsLine {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }

        // Try to detect disabled entry: `#<ws?>IP HOST...`
        if trimmed.hasPrefix("#") {
            let afterHash = trimmed.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
            if let entry = tryParseEntry(String(afterHash), enabled: false) {
                return .entry(entry)
            }
            return .comment(line)
        }

        if let entry = tryParseEntry(trimmed, enabled: true) {
            return .entry(entry)
        }
        return .unparsed(line)
    }

    private static func tryParseEntry(_ body: String, enabled: Bool) -> HostsEntry? {
        var main = body
        var comment: String?
        if let hashRange = main.range(of: "#") {
            let after = main[hashRange.upperBound...].trimmingCharacters(in: .whitespaces)
            comment = after.isEmpty ? nil : after
            main = String(main[..<hashRange.lowerBound])
        }
        let tokens = main
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard tokens.count >= 2 else { return nil }
        let ip = tokens[0]
        guard isPlausibleIP(ip) else { return nil }
        let hostnames = Array(tokens.dropFirst())
        return HostsEntry(
            isEnabled: enabled,
            ip: ip,
            hostnames: hostnames,
            comment: comment
        )
    }

    private static func isPlausibleIP(_ s: String) -> Bool {
        if s.isEmpty { return false }
        if s.contains(":") {
            // IPv6 (loose check)
            for ch in s where !(ch.isHexDigit || ch == ":" || ch == ".") {
                return false
            }
            return true
        }
        let parts = s.split(separator: ".")
        guard parts.count == 4 else { return false }
        for p in parts {
            guard let n = Int(p), (0...255).contains(n) else { return false }
        }
        return true
    }
}
