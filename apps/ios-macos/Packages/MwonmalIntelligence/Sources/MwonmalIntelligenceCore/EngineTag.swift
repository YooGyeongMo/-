internal import Foundation

/// 엔진 출처 태그. ADR-0007 §4-5 규약 `{track}/{model}#p{ver}` 그대로(서버 `aiModel` varchar 50과 같은 문자열).
///
/// 예: `fm/apple-26.4#p1`, `fm/apple-27-core#p1`, `tagger/pangyo-c-crf-v1#p1`, `none/dictionary#p1`.
/// - `track`: 소문자 영숫자.
/// - `model`: 소문자 영숫자와 `.`, `-`.
/// - `p{ver}`: FM은 프롬프트 버전, 태거는 후처리(하이브리드 정책) 버전.
public struct EngineTag: Hashable, Sendable, Codable, LosslessStringConvertible {
    public static let maxLength = 50

    public let track: String
    public let model: String
    public let pipelineVersion: Int

    public init?(track: String, model: String, pipelineVersion: Int) {
        guard Self.isTrack(track), Self.isModel(model), pipelineVersion >= 0 else { return nil }
        self.track = track
        self.model = model
        self.pipelineVersion = pipelineVersion
        guard description.count <= Self.maxLength else { return nil }
    }

    public init?(_ description: String) {
        guard description.count <= Self.maxLength,
              let slash = description.firstIndex(of: "/"),
              let hash = description.lastIndex(of: "#"),
              slash < hash
        else { return nil }
        let track = String(description[..<slash])
        let model = String(description[description.index(after: slash) ..< hash])
        let ver = description[description.index(after: hash)...]
        guard ver.first == "p", let number = Int(ver.dropFirst()), String(number) == String(ver.dropFirst()) else { return nil }
        self.init(track: track, model: model, pipelineVersion: number)
    }

    public var description: String {
        "\(track)/\(model)#p\(pipelineVersion)"
    }

    /// 프롬프트 버전을 뺀 "모델 태그". 점수 게이트·기능 플래그의 키(ADR-0015 §4 "모델 태그별").
    public var modelKey: String {
        "\(track)/\(model)"
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let tag = EngineTag(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "잘못된 엔진 태그: \(raw)"))
        }
        self = tag
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static func isTrack(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { ("a" ... "z").contains($0) || ("0" ... "9").contains($0) }
    }

    private static func isModel(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            ("a" ... "z").contains($0) || ("0" ... "9").contains($0) || $0 == "." || $0 == "-"
        }
    }
}

public extension EngineTag {
    /// 사전만 쓰는 경로(서버 `none/dictionary#p1`과 같은 이름).
    static let dictionaryOnly = EngineTag(track: "none", model: "dictionary", pipelineVersion: 1)!
}
