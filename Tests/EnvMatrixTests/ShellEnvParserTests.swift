import XCTest
@testable import EnvMatrix

final class ShellEnvParserTests: XCTestCase {
    func testParsesDoubleQuotedVariable() {
        let doc = ShellEnvParser.parse("export FOO=\"bar baz\"\n")
        XCTAssertEqual(doc.entries.count, 1)
        guard case .variable(let variable) = doc.entries[0] else {
            return XCTFail("Expected .variable entry")
        }
        XCTAssertEqual(variable.key, "FOO")
        XCTAssertEqual(variable.value, "bar baz")
        XCTAssertEqual(variable.quoting, .double)
        XCTAssertTrue(variable.isExported)
    }

    func testParsesPathAppendDoubleQuoted() {
        let doc = ShellEnvParser.parse("export PATH=\"$PATH:/opt/x/bin:/opt/y/bin\"\n")
        XCTAssertEqual(doc.entries.count, 1)
        guard case .pathAppend(let path) = doc.entries[0] else {
            return XCTFail("Expected .pathAppend entry")
        }
        XCTAssertEqual(path.segments, ["/opt/x/bin", "/opt/y/bin"])
        XCTAssertEqual(path.style, .doubleQuoted)
    }

    func testParsesPathAppendUnquoted() {
        let doc = ShellEnvParser.parse("export PATH=$PATH:/opt/z\n")
        XCTAssertEqual(doc.entries.count, 1)
        guard case .pathAppend(let path) = doc.entries[0] else {
            return XCTFail("Expected .pathAppend entry")
        }
        XCTAssertEqual(path.segments, ["/opt/z"])
        XCTAssertEqual(path.style, .unquoted)
    }

    func testRoundTripPreservesUnparsedLines() {
        let text = """
        # a comment
        alias ll='ls -al'
        export FOO=bar

        export PATH="$PATH:/opt/x/bin"
        source ~/.something
        """ + "\n"
        XCTAssertEqual(ShellEnvParser.serialize(ShellEnvParser.parse(text)), text)
    }

    func testEditingVariableAndPathReserializes() {
        let text = """
        # a comment
        alias ll='ls -al'
        export FOO=bar

        export PATH="$PATH:/opt/x/bin"
        source ~/.something
        """ + "\n"
        var doc = ShellEnvParser.parse(text)

        for index in doc.entries.indices {
            if case .variable(let existing) = doc.entries[index], existing.key == "FOO" {
                let updated = ShellVariable(
                    id: existing.id,
                    key: existing.key,
                    value: "baz",
                    quoting: existing.quoting,
                    isExported: existing.isExported
                )
                doc.entries[index] = .variable(updated)
            }
            if case .pathAppend(let existing) = doc.entries[index] {
                var segments = existing.segments
                segments.append("/opt/y/bin")
                let updated = ShellPathAppend(
                    id: existing.id,
                    segments: segments,
                    style: existing.style
                )
                doc.entries[index] = .pathAppend(updated)
            }
        }

        let output = ShellEnvParser.serialize(doc)
        XCTAssertTrue(output.contains("export FOO=baz"))
        XCTAssertFalse(output.contains("export FOO=bar"))
        XCTAssertTrue(output.contains("export PATH=\"$PATH:/opt/x/bin:/opt/y/bin\""))
        XCTAssertTrue(output.contains("# a comment"))
        XCTAssertTrue(output.contains("alias ll='ls -al'"))
        XCTAssertTrue(output.contains("source ~/.something"))
    }

    func testEmptyStringParses() {
        let doc = ShellEnvParser.parse("")
        XCTAssertFalse(doc.trailingNewline)
        XCTAssertEqual(ShellEnvParser.serialize(doc), "")
    }
}
