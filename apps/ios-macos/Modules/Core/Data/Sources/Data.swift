import MwonmalAPI

/// Data 모듈. 역할과 의존 방향은 docs/design/12_앱_아키텍처_설계.md §0 참고.
/// Repository 구현은 Day 4부터. 지금은 생성 클라이언트(MwonmalAPI)가 링크되는지만 확인한다.
public enum DataModule {
    public static let name = "Data"
    static let apiModuleName = MwonmalAPIModule.name
}
