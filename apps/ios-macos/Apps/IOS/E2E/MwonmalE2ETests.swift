import XCTest

/// v1.0 해석 흐름 E2E(로컬 서버 필요). 실제 서버·실제 DB로 끝까지 돈다.
///
///     cd services/api && uv run python scripts/dev_server.py --fresh --port 8080
///     xcodebuild test -workspace Mwonmal.xcworkspace -scheme MwonmalE2E -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
///
/// 로그인은 개발용 로그인(`-MWDevLogin <이름>`, Debug 빌드 전용, ADR-0020). 화면마다 스크린숏을 결과에 붙인다.
final class MwonmalE2ETests: XCTestCase {
    static let message = "이번 스프린트 스코프 아웃하고 넥스트로 밀죠. 그 전에 R&R 정리해서 내일까지 얼라인 쳐주세요"

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-MWResetSession", "-MWDevLogin", "e2e\(Int(Date().timeIntervalSince1970))"]
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "안 보임: \(element)", file: file, line: line)
    }

    func testDecodeFlowEndToEnd() {
        app.launch()
        signInAndDecode()
        reviewResult()
        browseTabs()
        settingsConsentAndSignOut()
    }

    private func signInAndDecode() {
        // 1. S-01 로그인
        let apple = app.buttons["signin.apple"]
        wait(apple)
        shot("01-login")
        apple.tap()

        // 2. A-01 홈(첫 사용자 → 할 일 없음)
        wait(app.buttons["tab.home"], 15)
        wait(app.staticTexts["오늘"])
        shot("02-home-empty")

        // 3. A-11 프로젝트 → 판교어 해석
        app.buttons["tab.project"].tap()
        let decode = app.buttons["project.decode"]
        wait(decode)
        shot("03-project-empty")
        decode.tap()

        // 4. 붙여넣기 시트
        let editor = app.textViews["compose.editor"]
        wait(editor)
        editor.tap()
        editor.typeText(Self.message)
        shot("04-compose")
        app.buttons["compose.submit"].tap()
    }

    private func reviewResult() {
        // 5. A-06 결과(사전 간이 해석: 동의 꺼짐 기본)
        let plain = app.staticTexts["result.plain"]
        wait(plain, 20)
        XCTAssertTrue(plain.label.contains("작업 범위에서 제외"), plain.label)
        wait(app.staticTexts["간이 해석"])
        wait(app.staticTexts["나한테 시킨 일"])
        shot("05-result")

        // 할 일 체크
        let check = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'action.check.'")).firstMatch
        wait(check)
        check.tap()
        shot("06-result-checked")

        // 용어 시트(칩)
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '얼라인'")).firstMatch
        wait(chip)
        chip.tap()
        wait(app.staticTexts["방향 맞추기"])
        shot("07-term")
        app.buttons["term.close"].tap()
        XCTAssertTrue(app.buttons["result.close"].waitForExistence(timeout: 5))
        app.buttons["result.close"].tap()

        // 6. 기록 목록에 방금 해석이 있다
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS '이번 스프린트'")).firstMatch
        wait(card)
        shot("08-project-list")

        // 같은 결과를 기록에서 다시 연다
        card.tap()
        wait(app.staticTexts["result.plain"])
        app.buttons["result.close"].tap()
    }

    private func browseTabs() {
        // 7. 홈: 할 일(체크한 것은 목록에서 빠지고 남은 것 표시)
        app.buttons["tab.home"].tap()
        wait(app.staticTexts["다가오는 할 일"])
        shot("09-home-actions")

        // 8. 복습 탭(v1.1 안내)
        app.buttons["tab.review"].tap()
        wait(app.staticTexts["복습은 다음 업데이트에서 열려요"])
        shot("10-review")
    }

    private func settingsConsentAndSignOut() {
        // 9. MY → 설정 → AI 외부 전송 동의 → 로그아웃
        app.buttons["tab.my"].tap()
        wait(app.staticTexts["판교 등급"])
        shot("11-my")
        app.buttons["my.settings"].tap()
        let toggle = app.switches["settings.aiToggle"]
        wait(toggle)
        shot("12-settings")
        toggle.switches.firstMatch.tap()
        let agree = app.buttons["consent.agree"]
        wait(agree)
        shot("13-consent")
        agree.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: agree)
        wait(for: [gone], timeout: 5)
        XCTAssertEqual(toggle.value as? String, "1")
        shot("13b-consent-on")
        app.buttons["settings.signOut"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == '로그아웃' AND identifier != 'settings.signOut'")).firstMatch
        wait(confirm)
        confirm.tap()
        wait(app.buttons["signin.apple"], 10)
        // 직접 로그아웃은 "세션 만료" 안내를 띄우지 않는다(QA H1).
        XCTAssertFalse(app.staticTexts["로그인이 풀렸어요. 다시 로그인해 주세요."].exists)
        shot("14-signed-out")
    }
}
