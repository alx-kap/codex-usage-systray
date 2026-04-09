import Foundation
import OSLog

final class UsageClient {
    private let logger = Logger(subsystem: "com.chatgpt.codex-usage-tray", category: "UsageClient")
    var urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchCodexUsage(credential: UsageRequestCredential) async throws -> CodexUsageResponse {
        let request = request(for: credential)
        let (data, response) = try await urlSession.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw UsageServiceError.httpStatus(-1, "Invalid response")
        }

        let body = String(decoding: data, as: UTF8.self)

        if let mitigation = http.value(forHTTPHeaderField: "cf-mitigated"),
           mitigation.lowercased() == "challenge" {
            logger.notice("Cloudflare challenge encountered while fetching usage")
            throw UsageServiceError.blockedByCloudflare
        }

        if http.statusCode == 401 {
            logger.notice("Usage request returned 401")
            throw UsageServiceError.invalidSession
        }

        if http.statusCode == 403 {
            if body.localizedCaseInsensitiveContains("Enable JavaScript and cookies to continue") {
                logger.notice("Usage request returned Cloudflare 403 challenge")
                throw UsageServiceError.blockedByCloudflare
            }
            logger.notice("Usage request returned 403 invalid session")
            throw UsageServiceError.invalidSession
        }

        if (300..<400).contains(http.statusCode) {
            logger.notice("Usage request redirected with status \(http.statusCode)")
            throw UsageServiceError.invalidSession
        }

        guard http.statusCode == 200 else {
            logger.error("Usage request failed with status \(http.statusCode)")
            throw UsageServiceError.httpStatus(http.statusCode, String(body.prefix(200)))
        }

        return try parseUsageResponse(data: data, mimeType: http.mimeType)
    }

    private func request(for credential: UsageRequestCredential) -> URLRequest {
        switch credential {
        case .installedCodexBearer(let accessToken):
            var whamRequest = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            whamRequest.httpMethod = "GET"
            whamRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            whamRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            whamRequest.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            whamRequest.setValue("CodexUsageSystray/1.0", forHTTPHeaderField: "User-Agent")
            whamRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            return whamRequest
        case .sessionCookie(let sessionCookie):
            var dashboardRequest = URLRequest(url: URL(string: "https://chatgpt.com/codex/settings/usage")!)
            dashboardRequest.httpMethod = "GET"
            dashboardRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            dashboardRequest.setValue("text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            dashboardRequest.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            dashboardRequest.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            dashboardRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            return dashboardRequest
        }
    }
}
