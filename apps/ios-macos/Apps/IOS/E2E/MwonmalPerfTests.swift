import XCTest

/// 움직임 성능(ADR-0024·0025): 끊김(hitch)·CPU·메모리를 잰다. 기준은 실기기다(시뮬레이터 수치는 참고용).
/// 평소 E2E에서는 건너뛴다. 잴 때만 켠다:
///
///     cd services/api && uv run python scripts/dev_server.py --fresh --port 8080
///     TEST_RUNNER_MW_PERF=1 xcodebuild test -workspace Mwonmal.xcworkspace -scheme MwonmalE2E \
///       -destination '<기기>' -only-testing:MwonmalE2E/MwonmalPerfTests
///
/// 합격선(ADR-0025): 끊김 시간 비율 5ms/s 미만(Apple "눈에 띔" 기준 5, "심함" 10).
final class MwonmalPerfTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MW_PERF"] == "1", "MW_PERF=1 일 때만 잰다")
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func metrics() -> [any XCTMetric] {
        var list: [any XCTMetric] = [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)]
        if #available(iOS 26, *) {
            list.insert(XCTHitchMetric(application: app), at: 0)
        }
        return list
    }

    private func options(_ count: Int = 5) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = count
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        return options
    }

    private func wait(_ element: XCUIElement, _ timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "안 보임: \(element)", file: file, line: line)
    }

    /// 실기기는 처음 한 번 "로컬 네트워크" 허용을 묻는다(측정 서버가 Mac에 있다).
    private func allowLocalNetworkIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["허용", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }

    /// 시작 연출 → 온보딩 3쪽(다이브 전환·줄 차례 등장·칩·반딧불·물결) → 로그인 화면.
    func testOnboardingMotion() {
        measure(metrics: metrics(), options: options()) {
            app.launchArguments = ["-MWResetOnboarding", "-MWResetSession"]
            app.launch()
            let next = app.buttons["onboarding.next"]
            startMeasuring()
            wait(next)
            next.tap()
            wait(app.staticTexts["메신저에서도, 회의에서도"])
            next.tap()
            let start = app.buttons["onboarding.start"]
            wait(start)
            // 3쪽의 계속 도는 움직임(반딧불·떠다니기·물결)을 잠시 그대로 둔다.
            Thread.sleep(forTimeInterval: 3)
            start.tap()
            wait(app.buttons["signin.apple"])
            stopMeasuring()
            app.terminate()
        }
    }

    /// 온보딩 각 쪽에 가만히 4초(계속 도는 움직임만 남은 상태)의 CPU. 쪽마다 따로 재서 무거운 쪽을 찾는다.
    func testIdleOnboardingPage1() {
        idle(onPage: 1)
    }

    func testIdleOnboardingPage2() {
        idle(onPage: 2)
    }

    func testIdleOnboardingPage3() {
        idle(onPage: 3)
    }

    /// 쪽 넘김 한 번(다이브 전환 + 다음 쪽 등장) + 가라앉을 때까지 3초의 CPU. 가만히 있는 값과 비교한다.
    func testTransitionOnboarding() {
        app.launchArguments = ["-MWResetOnboarding", "-MWResetSession"]
        app.launch()
        let next = app.buttons["onboarding.next"]
        wait(next)
        Thread.sleep(forTimeInterval: 2)
        measure(metrics: [XCTCPUMetric(application: app)], options: options(2)) {
            startMeasuring()
            next.tap()
            Thread.sleep(forTimeInterval: 3)
            stopMeasuring()
            app.swipeRight() // 1쪽으로 되돌아간다(다음 회차 준비)
            Thread.sleep(forTimeInterval: 2)
        }
    }

    /// 앱 실행 시간(첫 화면까지)과 그동안의 CPU. 시작 연출이 실행을 늦추지 않아야 한다.
    func testLaunch() {
        app.launchArguments = ["-MWResetSession"]
        let launchOptions = XCTMeasureOptions()
        launchOptions.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(), XCTCPUMetric(application: app)], options: launchOptions) {
            app.launch()
            app.terminate()
        }
    }

    /// 보조 기능(VoiceOver·테스트 도구)이 화면을 계속 물어볼 때 1쪽의 CPU. 계속 도는 움직임이 접근성 트리를
    /// 매 프레임 흔들면 여기서 커진다.
    func testAccessibilityPollingPage1() {
        app.launchArguments = ["-MWResetOnboarding", "-MWResetSession"]
        app.launch()
        let next = app.buttons["onboarding.next"]
        wait(next)
        Thread.sleep(forTimeInterval: 2)
        measure(metrics: [XCTCPUMetric(application: app)], options: options(3)) {
            startMeasuring()
            for _ in 0 ..< 20 {
                _ = next.exists
                Thread.sleep(forTimeInterval: 0.2)
            }
            stopMeasuring()
        }
    }

    private func idle(onPage page: Int) {
        app.launchArguments = ["-MWResetOnboarding", "-MWResetSession"]
        app.launch()
        let next = app.buttons["onboarding.next"]
        wait(next)
        for _ in 1 ..< page {
            next.tap()
        }
        if page == 3 {
            wait(app.buttons["onboarding.start"])
        }
        Thread.sleep(forTimeInterval: 2) // 등장 움직임이 끝날 때까지
        // 끝 상태(모든 칩·카드가 자리 잡은 뒤) 스크린숏: Figma O-\(page)와 비교한다.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "onboarding-\(page)-rest"
        attachment.lifetime = .keepAlways
        add(attachment)
        measure(metrics: [XCTCPUMetric(application: app)], options: options(3)) {
            startMeasuring()
            Thread.sleep(forTimeInterval: 4)
            stopMeasuring()
        }
    }

    /// 메인 화면: 탭 전환(홈 등장) → 프로젝트 → 결과 열기(카드 차례 등장) → 닫기 → 홈 스크롤.
    func testMainScreensMotion() {
        app.launchArguments = ["-MWResetOnboarding", "-MWResetSession", "-MWDevLogin", "perf\(Int(Date().timeIntervalSince1970))"]
        app.launch()
        wait(app.buttons["onboarding.skip"])
        app.buttons["onboarding.skip"].tap()
        wait(app.buttons["signin.apple"])
        app.buttons["signin.apple"].tap()
        allowLocalNetworkIfAsked()
        wait(app.buttons["tab.home"], 30)
        // 데이터 한 건(해석 → 결과 → 할 일).
        app.buttons["tab.project"].tap()
        app.buttons["project.decode"].tap()
        let editor = app.textViews["compose.editor"]
        wait(editor)
        editor.tap()
        editor.typeText(MwonmalE2ETests.message)
        app.buttons["compose.submit"].tap()
        wait(app.staticTexts["result.plain"], 30)
        app.buttons["result.close"].tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS '이번 스프린트'")).firstMatch
        wait(card)

        measure(metrics: metrics(), options: options()) {
            startMeasuring()
            app.buttons["tab.home"].tap()
            wait(app.staticTexts["다가오는 할 일"])
            app.swipeUp()
            app.swipeDown()
            app.buttons["tab.project"].tap()
            wait(card)
            card.tap()
            wait(app.staticTexts["result.plain"])
            app.buttons["result.close"].tap()
            wait(card)
            stopMeasuring()
        }
    }
}
