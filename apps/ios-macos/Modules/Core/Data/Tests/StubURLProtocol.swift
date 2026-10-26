import Foundation

/// URLSession을 가로채는 스텁. 테스트마다 고유 호스트로 응답을 나눠 병렬 실행에도 섞이지 않는다.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status: Int
        var body: String
        var error: URLError?
    }

    private nonisolated(unsafe) static var replies: [String: Reply] = [:]
    private nonisolated(unsafe) static var seen: [String: [URLRequest]] = [:]
    private static let lock = NSLock()

    static func register(host: String, _ reply: Reply) {
        lock.withLock { replies[host] = reply }
    }

    static func requests(host: String) -> [URLRequest] {
        lock.withLock { seen[host] ?? [] }
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let reply: Reply? = Self.lock.withLock {
            Self.seen[host, default: []].append(request)
            return Self.replies[host]
        }
        guard let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
