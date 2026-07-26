import XCTest
@testable import EnvMatrix

final class HostsParserTests: XCTestCase {
    func testParseEmptyString() {
        let doc = HostsParser.parse("")
        XCTAssertFalse(doc.trailingNewline)
        XCTAssertEqual(HostsParser.serialize(doc), "")
    }

    func testParseSimpleEntry() {
        let text = "127.0.0.1 localhost\n"
        let doc = HostsParser.parse(text)
        XCTAssertEqual(doc.lines.count, 1)
        guard case .entry(let entry) = doc.lines[0] else {
            return XCTFail("Expected entry")
        }
        XCTAssertTrue(entry.isEnabled)
        XCTAssertEqual(entry.ip, "127.0.0.1")
        XCTAssertEqual(entry.hostnames, ["localhost"])
        XCTAssertNil(entry.comment)
    }

    func testParseDisabledEntry() {
        let doc = HostsParser.parse("#127.0.0.1 blocked.example.com\n")
        guard case .entry(let entry) = doc.lines[0] else {
            return XCTFail("Expected entry")
        }
        XCTAssertFalse(entry.isEnabled)
        XCTAssertEqual(entry.ip, "127.0.0.1")
        XCTAssertEqual(entry.hostnames, ["blocked.example.com"])
    }

    func testParseWithComment() {
        let doc = HostsParser.parse("127.0.0.1 dev.local # local dev\n")
        guard case .entry(let entry) = doc.lines[0] else {
            return XCTFail("Expected entry")
        }
        XCTAssertEqual(entry.comment, "local dev")
        XCTAssertEqual(entry.hostnames, ["dev.local"])
    }

    func testParsePureCommentLine() {
        let doc = HostsParser.parse("# Just a comment\n")
        guard case .comment(let str) = doc.lines[0] else {
            return XCTFail("Expected comment")
        }
        XCTAssertEqual(str, "# Just a comment")
    }

    func testParseBlankLine() {
        let doc = HostsParser.parse("\n")
        guard case .blank = doc.lines[0] else {
            return XCTFail("Expected blank")
        }
    }

    func testSerializeRoundTrip() {
        let text = """
        ##
        # Host Database
        ##

        127.0.0.1 localhost
        255.255.255.255 broadcasthost
        ::1 localhost
        #127.0.0.1 blocked.example.com
        192.168.1.10 dev.local alias.local # dev machine

        """
        let doc = HostsParser.parse(text)
        XCTAssertEqual(HostsParser.serialize(doc), text)
    }

    func testToggleEnabledSerializesWithHash() {
        let text = "127.0.0.1 example.com\n"
        var doc = HostsParser.parse(text)
        if case .entry(var e) = doc.lines[0] {
            e.isEnabled = false
            doc.lines[0] = .entry(e)
        }
        XCTAssertEqual(HostsParser.serialize(doc), "#127.0.0.1 example.com\n")
    }

    func testMultipleHostnamesPreserved() {
        let doc = HostsParser.parse("10.0.0.1 a.local b.local c.local\n")
        guard case .entry(let entry) = doc.lines[0] else {
            return XCTFail("Expected entry")
        }
        XCTAssertEqual(entry.hostnames, ["a.local", "b.local", "c.local"])
    }

    func testTabSeparatorParsedAndSerializedWithSpace() {
        let doc = HostsParser.parse("127.0.0.1\tlocalhost\n")
        XCTAssertEqual(HostsParser.serialize(doc), "127.0.0.1 localhost\n")
    }

    func testUnparsedLineKept() {
        let doc = HostsParser.parse("not an ip line\n")
        guard case .unparsed(let raw) = doc.lines[0] else {
            return XCTFail("Expected unparsed")
        }
        XCTAssertEqual(raw, "not an ip line")
        XCTAssertEqual(HostsParser.serialize(doc), "not an ip line\n")
    }

    func testCRLFLineEndingPreserved() {
        let text = "127.0.0.1 a\r\n127.0.0.2 b\r\n"
        let doc = HostsParser.parse(text)
        XCTAssertEqual(doc.lineEnding, "\r\n")
        XCTAssertEqual(HostsParser.serialize(doc), text)
    }
}
