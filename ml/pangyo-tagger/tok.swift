import NaturalLanguage

let ss = ["이번 스프린트 얼라인을 하고 싱크해서 R&R 정리해요.", "ASAP으로 컨펌 부탁드려요~ 1on1에서 팔로업할게요", "킥오프 미팅은 아삽하게, MECE하게 디벨롭해주세요!"]
for s in ss {
    let t = NLTokenizer(unit: .word); t.string = s; t.setLanguage(.korean)
    var out: [String] = []
    t.enumerateTokens(in: s.startIndex ..< s.endIndex) { r, _ in out.append(String(s[r])); return true }
    print(out)
}

let r = NLContextualEmbedding(language: .korean)
print("ctx emb ko:", r as Any, r?.hasAvailableAssets as Any, r?.dimension as Any)
print("wordEmbedding ko:", NLEmbedding.wordEmbedding(for: .korean) as Any)
