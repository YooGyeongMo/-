import MwonmalAPI

/// Data 모듈. Repository 구현, 서버 에러 → DomainError 변환(12번 §5). DTO는 이 모듈 밖으로 나가지 않는다.
public enum DataModule {
    public static let name = "Data"
    static let apiModuleName = MwonmalAPIModule.name
}
