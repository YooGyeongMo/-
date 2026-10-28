import XCTest

/// macOS 해석 흐름 E2E(로컬 서버 필요, iOS E2E와 같은 서버).
///
///     cd services/api && MWONMAL_ENV=local uv run python scripts/dev_server.py --fresh --port 8080
///     xcodebuild test -workspace Mwonmal.xcworkspace -scheme MwonmalMacE2E -destination 'platform=macOS'
///
/// 넓은 화면 규칙(ADR-0006)을 같이 본다: 사이드바, 붙여넣기·결과가 상세 영역 페이지, 키보드(⌘↩ 해석, Esc 닫기, ⌘4 MY).
final class MwonmalMacE2ETests: XCTestCase {
    static let message = "이번 스프린트 스코프 아웃하고 넥스트로 밀죠. 그 전에 R&R 정리해서 내일까지 얼라인 쳐주세요"

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // 저장된 창 상태(창 0개)를 복원하지 않게 한다 — 전에 창을 닫고 끝냈으면 창 없이 뜬다.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-MWResetSession", "-MWDevLogin", "mac\(Int(Date().timeIntervalSince1970))"]
    }

    override func tearDown() {
        app.terminate()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "안 보임: \(element)", file: file, line: line)
    }

    func testWideDecodeFlowEndToEnd() {
        app.launch()

        // 1. 로그인(넓은 화면에서는 가운데 기기 폭 기둥)
        let apple = element("signin.apple")
        wait(apple, 15)
        shot("01-login")
        apple.click()

        // 2. 사이드바 + 홈 두 열
        let decode = element("sidebar.decode")
        wait(decode, 15)
        wait(app.staticTexts["다가오는 할 일"])
        shot("02-home-wide")

        // 3. 사이드바 "판교어 해석" → 상세 영역의 붙여넣기 페이지(시트 아님) + 최근 해석 열
        decode.click()
        let editor = element("compose.editor")
        wait(editor)
        wait(app.staticTexts["최근 해석"])
        editor.click()
        editor.typeText(Self.message)
        shot("03-compose-wide")
        app.typeKey(.return, modifierFlags: .command) // ⌘↩ 해석

        // 4. 결과 두 열(왼쪽 원문·쉬운 말, 오른쪽 시킨 일·모르는 말)
        let plain = element("result.plain")
        wait(plain, 20)
        XCTAssertTrue((plain.value as? String ?? plain.label).contains("작업 범위에서 제외") || app.staticTexts.containing(
            NSPredicate(format: "value CONTAINS '작업 범위에서 제외' OR label CONTAINS '작업 범위에서 제외'")
        ).firstMatch.exists)
        wait(app.staticTexts["나한테 시킨 일"])
        shot("04-result-wide")

        // 5. 용어 칩 → 용어 창(모달)
        let chip = app.buttons.matching(NSPredicate(format: "identifier == 'result.term' AND label BEGINSWITH '얼라인'")).firstMatch
        wait(chip)
        chip.click()
        wait(app.staticTexts["방향 맞추기"])
        shot("05-term")
        element("term.close").click()

        // 6. Esc → 결과 페이지 닫힘 → 사이드바 "프로젝트"에서 기록 확인
        app.typeKey(.escape, modifierFlags: [])
        element("sidebar.project").click()
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '이번 스프린트'")).firstMatch
        wait(card)
        shot("06-project-wide")

        // 7. ⌘4 → MY → 설정 → 로그아웃
        app.typeKey("4", modifierFlags: .command)
        wait(app.staticTexts["판교 등급"])
        shot("07-my-wide")
        element("my.settings").click()
        let signOut = element("settings.signOut")
        wait(signOut)
        shot("08-settings")
        signOut.click()
        let confirm = app.buttons.matching(NSPredicate(format: "label == '로그아웃' AND identifier != 'settings.signOut'")).firstMatch
        wait(confirm)
        confirm.click()
        wait(element("signin.apple"), 10)
        shot("09-signed-out")
    }
}
