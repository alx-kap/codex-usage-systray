import XCTest
@testable import CodexUsageSystray

final class ParseUsageResponseTests: XCTestCase {
    func testParsesMetricsFromInstalledCodexJSONPayload() throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 48,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 10630,
              "reset_at": 1774044576
            },
            "secondary_window": {
              "used_percent": 15,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 597430,
              "reset_at": 1774631376
            }
          },
          "code_review_rate_limit": {
            "primary_window": {
              "used_percent": 0,
              "limit_window_seconds": 604800,
              "reset_after_seconds": 604800,
              "reset_at": 1774638747
            },
            "secondary_window": null
          }
        }
        """.data(using: .utf8)!

        let response = try parseUsageResponse(data: json, mimeType: "application/json")

        XCTAssertEqual(response.metrics.map(\.label), ["Weekly", "Session", "Code review"])
        XCTAssertEqual(response.metrics.map(\.utilization), [15, 48, 0])
        XCTAssertEqual(response.metrics.map(\.displayedUtilization), [85, 52, 100])
    }

    func testParsesMetricsFromRenderedHTML() throws {
        let html = """
        <html>
          <body>
            <section>
              <h2>Weekly quota</h2>
              <div>71%</div>
              <div>Resets in 1d 4h</div>
            </section>
            <section>
              <h2>Session quota</h2>
              <div>35%</div>
              <div>Resets in 2h 5m</div>
            </section>
          </body>
        </html>
        """.data(using: .utf8)!

        let response = try parseUsageResponse(data: html, mimeType: "text/html")

        XCTAssertEqual(response.metrics.count, 2)
        XCTAssertEqual(response.metrics[0].label, "Weekly quota")
        XCTAssertEqual(response.metrics[0].utilization, 71)
        XCTAssertEqual(response.metrics[0].resetDescription, "Resets in 1d 4h")
        XCTAssertEqual(response.metrics[1].label, "Session quota")
        XCTAssertEqual(response.metrics[1].utilization, 35)
    }

    func testThrowsForUnrecognizedPayload() {
        let html = "<html><body><div>No metrics here</div></body></html>".data(using: .utf8)!

        XCTAssertThrowsError(try parseUsageResponse(data: html, mimeType: "text/html")) { error in
            XCTAssertEqual(error as? UsageServiceError, .invalidPayload)
        }
    }
}

final class UsageSnapshotTests: XCTestCase {
    func testCreatesPrimarySecondaryAndBreakdownMetrics() {
        let response = CodexUsageResponse(metrics: [
            CodexUsageMetric(label: "Session", utilization: 35, displayPercent: nil, resetAt: nil, resetDescription: "Resets in 2h"),
            CodexUsageMetric(label: "Weekly", utilization: 71, displayPercent: nil, resetAt: nil, resetDescription: "Resets in 1d"),
            CodexUsageMetric(label: "Codex", utilization: 42, displayPercent: nil, resetAt: nil, resetDescription: nil)
        ])

        let snapshot = makeUsageSnapshot(from: response, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(snapshot.primaryLabel, "Weekly")
        XCTAssertEqual(snapshot.primaryUsage, 71)
        XCTAssertEqual(snapshot.primaryUsedPercent, 71)
        XCTAssertEqual(snapshot.primaryResetIn, "Resets in 1d")
        XCTAssertEqual(snapshot.secondaryLabel, "Session")
        XCTAssertEqual(snapshot.secondaryUsage, 35)
        XCTAssertEqual(snapshot.secondaryUsedPercent, 35)
        XCTAssertEqual(snapshot.breakdowns, [UsageBreakdown(label: "Codex", utilization: 42, usedPercent: 42, resetIn: nil)])
    }

    func testCreatesSingleMetricSnapshot() {
        let response = CodexUsageResponse(metrics: [
            CodexUsageMetric(label: "Codex quota", utilization: 58, displayPercent: nil, resetAt: nil, resetDescription: nil)
        ])

        let snapshot = makeUsageSnapshot(from: response)

        XCTAssertEqual(snapshot.primaryLabel, "Codex quota")
        XCTAssertEqual(snapshot.primaryUsage, 58)
        XCTAssertEqual(snapshot.primaryUsedPercent, 58)
        XCTAssertNil(snapshot.secondaryUsage)
        XCTAssertTrue(snapshot.breakdowns.isEmpty)
    }

    func testCreatesRemainingDisplaySnapshotForInstalledCodexMetrics() {
        let response = CodexUsageResponse(metrics: [
            CodexUsageMetric(label: "Session", utilization: 48, displayPercent: 52, resetAt: nil, resetDescription: nil),
            CodexUsageMetric(label: "Weekly", utilization: 16, displayPercent: 84, resetAt: nil, resetDescription: nil)
        ])

        let snapshot = makeUsageSnapshot(from: response)

        XCTAssertEqual(snapshot.primaryLabel, "Weekly")
        XCTAssertEqual(snapshot.primaryUsage, 84)
        XCTAssertEqual(snapshot.primaryUsedPercent, 16)
        XCTAssertEqual(snapshot.secondaryUsage, 52)
        XCTAssertEqual(snapshot.secondaryUsedPercent, 48)
    }
}

final class UsageServiceCredentialFlowTests: XCTestCase {
    func testInstalledCodexAuthConfiguresServiceWithoutFallbackCookie() {
        let service = UsageService(
            credentialStore: MockSessionCredentialStore(),
            installedCodexAuthProvider: MockInstalledCodexAuthProvider(accessToken: "token-123"),
            urlSession: makeURLSession(statusCode: 200, mimeType: "application/json", body: "{}")
        )

        XCTAssertEqual(service.authState, .configured)
        XCTAssertTrue(service.hasInstalledCodexAuth)
        XCTAssertEqual(service.activeCredentialSource, .installedCodex)
    }

    func testSaveSessionValidatesAndStoresCookie() async throws {
        let store = MockSessionCredentialStore()
        let session = makeURLSession(statusCode: 200, mimeType: "application/json", body: """
        { "metrics": [ { "label": "Weekly", "utilization": 71.0 } ] }
        """)
        let service = UsageService(
            credentialStore: store,
            installedCodexAuthProvider: MockInstalledCodexAuthProvider(accessToken: nil),
            urlSession: session
        )

        try await service.saveSessionCookie("Cookie: session=abc; cf_clearance=xyz")

        XCTAssertEqual(store.savedCookie, "session=abc; cf_clearance=xyz")
        XCTAssertEqual(service.authState, .configured)
        XCTAssertEqual(service.currentUsage.primaryUsage, 71)
        XCTAssertEqual(service.activeCredentialSource, .storedSessionCookie)
    }

    func testSaveSessionDoesNotStoreInvalidCookie() async {
        let store = MockSessionCredentialStore()
        let session = makeURLSession(statusCode: 403, mimeType: "text/html", body: "Enable JavaScript and cookies to continue", headers: ["cf-mitigated": "challenge"])
        let service = UsageService(
            credentialStore: store,
            installedCodexAuthProvider: MockInstalledCodexAuthProvider(accessToken: nil),
            urlSession: session
        )

        do {
            try await service.saveSessionCookie("session=abc")
            XCTFail("Expected validation to fail")
        } catch {
            XCTAssertEqual(error as? UsageServiceError, .blockedByCloudflare)
        }

        XCTAssertNil(store.savedCookie)
        XCTAssertEqual(service.authState, .invalidSession)
    }

    func testClearSessionResetsState() {
        let store = MockSessionCredentialStore(initialCookie: "session=abc")
        let service = UsageService(
            credentialStore: store,
            installedCodexAuthProvider: MockInstalledCodexAuthProvider(accessToken: nil),
            urlSession: makeURLSession(statusCode: 200, mimeType: "application/json", body: "{}")
        )

        service.clearSessionCookie()

        XCTAssertEqual(service.authState, .missingSession)
        XCTAssertTrue(store.cleared)
        XCTAssertNil(service.currentUsage.primaryUsage)
    }

    func testClearSessionKeepsInstalledCodexAuthAvailable() {
        let store = MockSessionCredentialStore(initialCookie: "session=abc")
        let service = UsageService(
            credentialStore: store,
            installedCodexAuthProvider: MockInstalledCodexAuthProvider(accessToken: "token-123"),
            urlSession: makeURLSession(statusCode: 200, mimeType: "application/json", body: """
            {
              "rate_limit": {
                "primary_window": { "used_percent": 33, "limit_window_seconds": 18000, "reset_at": 1774044576 }
              }
            }
            """)
        )

        service.clearSessionCookie()

        XCTAssertTrue(store.cleared)
        XCTAssertEqual(service.authState, .configured)
    }

    func testMissingStoreStartsInMissingSessionState() {
        let service = UsageService(
            credentialStore: MockSessionCredentialStore(),
            installedCodexAuthProvider: MockInstalledCodexAuthProvider(accessToken: nil),
            urlSession: makeURLSession(statusCode: 200, mimeType: "application/json", body: "{}")
        )

        XCTAssertEqual(service.authState, .missingSession)
    }

    func testFetchCodexUsageUsesBearerAuthForInstalledCodex() async throws {
        let service = UsageService(
            credentialStore: MockSessionCredentialStore(),
            installedCodexAuthProvider: MockInstalledCodexAuthProvider(accessToken: "token-123"),
            urlSession: makeURLSession(statusCode: 200, mimeType: "application/json", body: """
            {
              "rate_limit": {
                "primary_window": { "used_percent": 48, "limit_window_seconds": 18000, "reset_at": 1774044576 },
                "secondary_window": { "used_percent": 15, "limit_window_seconds": 604800, "reset_at": 1774631376 }
              }
            }
            """)
        )

        _ = try await service.fetchCodexUsage(credential: .installedCodexBearer("token-123"))

        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer token-123")
    }

    func testFetchCodexUsageUsesCookieForFallbackSession() async throws {
        let service = UsageService(
            credentialStore: MockSessionCredentialStore(),
            installedCodexAuthProvider: MockInstalledCodexAuthProvider(accessToken: nil),
            urlSession: makeURLSession(statusCode: 200, mimeType: "application/json", body: """
            { "metrics": [ { "label": "Weekly", "utilization": 71.0 } ] }
            """)
        )

        _ = try await service.fetchCodexUsage(credential: .sessionCookie("session=abc; cf_clearance=xyz"))

        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://chatgpt.com/codex/settings/usage")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Cookie"), "session=abc; cf_clearance=xyz")
    }
}

final class UsageNotificationTests: XCTestCase {
    func testWarningFiresOnceAndRearmsAfterDrop() {
        let first = evaluateUsageNotification(
            currentUsage: 82,
            warningThreshold: 80,
            criticalThreshold: 90,
            previousState: UsageNotificationState()
        )
        XCTAssertEqual(first.event, .warning(82))

        let second = evaluateUsageNotification(
            currentUsage: 84,
            warningThreshold: 80,
            criticalThreshold: 90,
            previousState: first.state
        )
        XCTAssertNil(second.event)

        let reset = evaluateUsageNotification(
            currentUsage: 20,
            warningThreshold: 80,
            criticalThreshold: 90,
            previousState: second.state
        )
        XCTAssertNil(reset.event)

        let rearmed = evaluateUsageNotification(
            currentUsage: 85,
            warningThreshold: 80,
            criticalThreshold: 90,
            previousState: reset.state
        )
        XCTAssertEqual(rearmed.event, .warning(85))
    }

    func testCriticalOverridesWarning() {
        let warning = evaluateUsageNotification(
            currentUsage: 82,
            warningThreshold: 80,
            criticalThreshold: 90,
            previousState: UsageNotificationState()
        )

        let critical = evaluateUsageNotification(
            currentUsage: 95,
            warningThreshold: 80,
            criticalThreshold: 90,
            previousState: warning.state
        )

        XCTAssertEqual(critical.event, .critical(95))
    }
}

final class UtilityFunctionTests: XCTestCase {
    func testCalculateUtilizationCapsAtHundred() {
        XCTAssertEqual(calculateUtilization(tokens: 300, limit: 100), 100)
    }

    func testFormatTimeRemainingExactlyOneHour() {
        let now = Date()
        XCTAssertEqual(formatTimeRemaining(until: now.addingTimeInterval(3600), from: now), "1h 0m")
    }

    func testNormalizeSessionCookieRemovesPrefixAndJoinsLines() throws {
        let cookie = try normalizeSessionCookie("""
        Cookie: session=abc;
        cf_clearance=xyz
        """)

        XCTAssertEqual(cookie, "session=abc; cf_clearance=xyz")
    }
}

private final class MockSessionCredentialStore: SessionCredentialStore {
    var savedCookie: String?
    var cleared = false
    private var storedCookie: String?

    init(initialCookie: String? = nil) {
        self.storedCookie = initialCookie
    }

    func readSessionCookie() throws -> String {
        guard let storedCookie else {
            throw SessionCredentialError.missingSession
        }
        return storedCookie
    }

    func saveSessionCookie(_ cookie: String) throws {
        savedCookie = cookie
        storedCookie = cookie
    }

    func clearSessionCookie() throws {
        cleared = true
        storedCookie = nil
    }

    func hasSessionCookie() -> Bool {
        storedCookie != nil
    }
}

private final class MockInstalledCodexAuthProvider: InstalledCodexAuthProviding {
    let authFilePath: String
    private let accessToken: String?

    init(accessToken: String?, authFilePath: String = "/Users/test/.codex/auth.json") {
        self.accessToken = accessToken
        self.authFilePath = authFilePath
    }

    func readAccessToken() throws -> String {
        guard let accessToken else {
            throw InstalledCodexAuthError.missingToken
        }
        return accessToken
    }

    func hasAccessToken() -> Bool {
        accessToken != nil
    }
}

private final class MockURLProtocol: URLProtocol {
    static var statusCode = 200
    static var mimeType = "application/json"
    static var body = Data()
    static var headers: [String: String] = [:]
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: Self.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeURLSession(statusCode: Int, mimeType: String, body: String, headers: [String: String] = [:]) -> URLSession {
    MockURLProtocol.statusCode = statusCode
    MockURLProtocol.mimeType = mimeType
    MockURLProtocol.body = Data(body.utf8)
    MockURLProtocol.headers = headers.merging(["Content-Type": mimeType]) { _, new in new }
    MockURLProtocol.lastRequest = nil

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}
