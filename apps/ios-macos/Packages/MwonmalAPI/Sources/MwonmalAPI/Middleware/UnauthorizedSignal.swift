/// 401 재로그인 신호(D-11). 동시에 401이 여러 개 와도 신호는 한 번만 보낸다.
/// 받는 쪽(Composition의 AppCoordinator)이 다시 로그인한 뒤 `reset()`을 부르면 다음 401을 다시 알린다.
public actor UnauthorizedSignal {
    public nonisolated let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var pending = false
    /// 지금까지 실제로 보낸 신호 수(테스트·진단용).
    public private(set) var deliveredCount = 0

    public init() {
        (events, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    public func notify() {
        guard !pending else { return }
        pending = true
        deliveredCount += 1
        continuation.yield()
    }

    public func reset() {
        pending = false
    }

    public var isPending: Bool {
        pending
    }
}
