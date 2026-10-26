import Foundation
@testable import FoundationModelsEngine
import IntelligenceTesting
import MwonmalIntelligenceCore
import Testing

@Suite("FM 다섯 겹 게이트 (FoundationModels 없이 도는 순수 로직)")
struct FMGateTests {
    static let tag264 = EngineTag("fm/apple-26.4#p1")!
    static let open = FMGatePolicy(enabledModelKeys: ["fm/apple-26.4"])

    func input(_ edit: (inout FMGateInput) -> Void = { _ in }) -> FMGateInput {
        var gateInput = FMGateInput(
            osSupported: true,
            model: .available,
            supportsKorean: true,
            contextSize: 4096,
            inputScalarCount: 120,
            modelTag: Self.tag264
        )
        edit(&gateInput)
        return gateInput
    }

    @Test func allOpen() {
        #expect(FMGate.evaluate(input(), policy: Self.open) == .available)
    }

    @Test func defaultPolicyIsClosed() {
        #expect(FMGate.evaluate(input(), policy: .closed) == .unavailable(.tagDisabled(modelKey: "fm/apple-26.4")))
    }

    @Test func firstFailingLayerWins() {
        // OS 실패가 모델·로케일 실패보다 먼저 보고된다.
        let allFailing = input { $0.osSupported = false; $0.model = .modelNotReady; $0.supportsKorean = false }
        #expect(FMGate.evaluate(allFailing, policy: Self.open) == .unavailable(.osTooOld))
        #expect(FMGate.evaluate(input { $0.model = .appleIntelligenceNotEnabled; $0.supportsKorean = false }, policy: Self.open)
            == .unavailable(.appleIntelligenceNotEnabled))
        #expect(FMGate.evaluate(input { $0.supportsKorean = false }, policy: Self.open) == .unavailable(.localeUnsupported))
    }

    @Test(arguments: [(500, 4096, true), (501, 4096, false), (300, 1500, true), (301, 1500, false)])
    func tokenBudget(scalars: Int, context: Int, expectedAvailable: Bool) {
        // 한도 = min(500, contextSize − 1200)
        let availability = FMGate.evaluate(input { $0.inputScalarCount = scalars; $0.contextSize = context }, policy: Self.open)
        #expect(availability.isAvailable == expectedAvailable)
    }

    @Test func ios27WithoutVariantIsFailClosed() {
        let tag = FMModelTag.resolve(os: .init(majorVersion: 27, minorVersion: 0, patchVersion: 0), promptVersion: 1)
        #expect(tag.description == "fm/apple-27-unknown#p1")
        let policy = FMGatePolicy(enabledModelKeys: ["fm/apple-26.4", "fm/apple-27-core"])
        #expect(FMGate.evaluate(input { $0.modelTag = tag }, policy: policy) == .unavailable(.tagDisabled(modelKey: "fm/apple-27-unknown")))
    }

    @Test(arguments: [
        ModelTagCase(26, 0, nil, "fm/apple-26.0"), ModelTagCase(26, 3, nil, "fm/apple-26.0"),
        ModelTagCase(26, 4, nil, "fm/apple-26.4"), ModelTagCase(26, 5, nil, "fm/apple-26.4"),
        ModelTagCase(27, 0, "core3", "fm/apple-27-core"), ModelTagCase(27, 1, "coreAdvanced3", "fm/apple-27-adv"),
        ModelTagCase(28, 0, nil, "fm/apple-28-unknown"),
    ])
    func modelTags(_ testCase: ModelTagCase) {
        let osVersion = OperatingSystemVersion(majorVersion: testCase.major, minorVersion: testCase.minor, patchVersion: 0)
        #expect(FMModelTag.resolve(os: osVersion, variant: testCase.variant, promptVersion: 1).modelKey == testCase.key)
    }

    @Test func promptKeepsUserTextOut() {
        let prompt = FMPrompt.forModel("fm/apple-26.4")
        #expect(prompt.instructions.hasPrefix("The person's locale is ko_KR."))
        #expect(prompt.version == 1)
    }

    @Test func fakeMatrixHasSixStates() {
        #expect(Set(FakeDraftEngine.availabilityMatrix).count == 6)
    }
}

/// `modelTags` 인자 한 줄(OS major·minor, 27 변형, 기대 모델 키).
struct ModelTagCase: Sendable, CustomTestStringConvertible {
    let major: Int
    let minor: Int
    let variant: String?
    let key: String

    init(_ major: Int, _ minor: Int, _ variant: String?, _ key: String) {
        self.major = major
        self.minor = minor
        self.variant = variant
        self.key = key
    }

    var testDescription: String {
        "\(major).\(minor) \(variant ?? "nil") → \(key)"
    }
}

/// 실제 시스템 모델 호출. Apple Intelligence가 켜진 Mac 26 에서만 돈다.
/// **조용히 건너뛰지 않는다**: Swift Testing이 "skipped" 로 집계하고 사유를 출력한다(CI 로그에서 skip 수를 센다).
@Suite("FM 실호출 스모크", .enabled(if: FMProbe.liveModelReason == nil, "FM 사용 불가: \(FMProbe.liveModelReason ?? "-")"))
struct FMLiveSmokeTests {
    @Test(.timeLimit(.minutes(1)))
    func draftsKoreanPlainText() async throws {
        let engine = try #require(FMEngineFactory.makeIfSupported(policy: FMGatePolicy(enabledModelKeys: [
            "fm/apple-26.0",
            "fm/apple-26.4",
        ])))
        let req = DraftRequest(text: "이번 스프린트 얼라인 한번 하고 다음 주에 킥오프 밀죠.")
        #expect(await engine.availability(for: req) == .available)
        let clock = ContinuousClock()
        let startedAt = clock.now
        let draft = try await engine.draft(for: req)
        let summary = "engine=\(draft.engine) latency=\(clock.now - startedAt) intent=\(draft.intent?.rawValue ?? "nil")"
        print("[fm-live] \(summary) actions=\(draft.actionTexts.count)")
        #expect(!draft.resultText.isEmpty)
        #expect(draft.engine.track == "fm")
    }
}
