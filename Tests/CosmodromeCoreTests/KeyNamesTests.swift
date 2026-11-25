import XCTest
@testable import CosmodromeCore

final class KeyNamesTests: XCTestCase {
    func testFunctionKeysAreExactlyF1ToF19() {
        XCTAssertEqual(KeyNames.functionKeyCodes.count, 19)
        let names = Set(KeyNames.functionKeyCodes.map(KeyNames.keyName(for:)))
        XCTAssertEqual(names, Set((1...19).map { "F\($0)" }))
    }

    func testNavigationKeysAreNotFunctionKeys() {
        // Help, Home, Page Up, Forward Delete, End, Page Down sit inside the
        // F-key keycode range but must never become bare shortcuts.
        for keyCode: UInt32 in [114, 115, 116, 117, 119, 121] {
            XCTAssertFalse(KeyNames.functionKeyCodes.contains(keyCode), "keyCode \(keyCode)")
        }
    }
}
