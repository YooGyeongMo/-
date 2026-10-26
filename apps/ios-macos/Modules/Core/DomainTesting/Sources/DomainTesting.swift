#if DEBUG
    import Domain

    /// DomainTesting 모듈(ADR-0016). 모든 Tests·Example·Preview가 같이 쓰는 Fake/Spy/고정 시계.
    /// 릴리스 빌드에서는 빈 모듈이 된다(`#if DEBUG`).
    public enum DomainTestingModule {
        public static let name = "DomainTesting"
        static let domain = DomainModule.name
    }
#endif
