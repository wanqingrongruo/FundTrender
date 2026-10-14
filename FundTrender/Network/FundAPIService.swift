import Foundation
import OSLog

enum FundAPIError: LocalizedError {
    case invalidCode
    case parseError
    case networkError(Error)
    case httpError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCode: return "基金代码无效或不存在"
        case .parseError: return "数据解析失败"
        case .networkError(let e): return e.localizedDescription
        case .httpError(let statusCode): return "行情服务异常（HTTP \(statusCode)），请稍后重试"
        case .invalidResponse: return "行情服务返回了无效响应"
        }
    }
}

struct FundAPIService {
    static let shared = FundAPIService()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FundTrender",
        category: "FundAPIService"
    )

    func fetchQuote(code: String) async throws -> FundQuote {
        var components = URLComponents(string: "https://fund.eastmoney.com/data/funddataforgznew.aspx")
        components?.queryItems = [
            URLQueryItem(name: "cb", value: "jsonpgz"),
            URLQueryItem(name: "fc", value: code),
            URLQueryItem(name: "t", value: "basewap"),
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1_000)))
        ]
        guard let url = components?.url else {
            Self.logger.error("[Quote] invalid URL code=\(code, privacy: .private)")
            throw FundAPIError.invalidCode
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("https://fund.eastmoney.com", forHTTPHeaderField: "Referer")

        let startedAt = Date()
        Self.logger.debug(
            "[Quote] request start code=\(code, privacy: .private) cachePolicy=\(String(describing: request.cachePolicy), privacy: .public) url=\(url.absoluteString, privacy: .private)"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            Self.logger.error(
                "[Quote] request failed code=\(code, privacy: .private) elapsed=\(elapsed, format: .fixed(precision: 3))s error=\(String(describing: error), privacy: .private)"
            )
            throw error
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error(
                "[Quote] non-HTTP response code=\(code, privacy: .private) elapsed=\(elapsed, format: .fixed(precision: 3))s response=\(String(describing: response), privacy: .private)"
            )
            throw FundAPIError.invalidResponse
        }
        let cacheControl = httpResponse.value(forHTTPHeaderField: "Cache-Control") ?? "-"
        let age = httpResponse.value(forHTTPHeaderField: "Age") ?? "-"
        let responseDate = httpResponse.value(forHTTPHeaderField: "Date") ?? "-"
        let mimeType = httpResponse.mimeType ?? "-"
        Self.logger.info(
            "[Quote] response code=\(code, privacy: .private) status=\(httpResponse.statusCode) mime=\(mimeType, privacy: .public) bytes=\(data.count) elapsed=\(elapsed, format: .fixed(precision: 3))s cacheControl=\(cacheControl, privacy: .public) age=\(age, privacy: .public) date=\(responseDate, privacy: .public)"
        )

        guard httpResponse.statusCode == 200 else {
            let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
            Self.logger.error(
                "[Quote] unexpected status code=\(code, privacy: .private) status=\(httpResponse.statusCode) body=\(bodyPreview, privacy: .private)"
            )
            throw FundAPIError.httpError(httpResponse.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            Self.logger.error("[Quote] invalid UTF-8 code=\(code, privacy: .private) bytes=\(data.count)")
            throw FundAPIError.parseError
        }
        do {
            let quote = try parseJSONP(text)
            guard quote.fundcode == code,
                  let previousNav = Double(quote.dwjz),
                  previousNav.isFinite,
                  previousNav > 0,
                  let currentEstimate = Double(quote.gsz),
                  currentEstimate.isFinite,
                  currentEstimate > 0,
                  let changePercent = Double(quote.gszzl),
                  changePercent.isFinite else {
                Self.logger.error(
                    "[Quote] validation failed requestedCode=\(code, privacy: .private) responseCode=\(quote.fundcode, privacy: .private)"
                )
                throw FundAPIError.parseError
            }
            Self.logger.debug(
                "[Quote] parsed code=\(code, privacy: .private) responseCode=\(quote.fundcode, privacy: .private) gztime=\(quote.gztime, privacy: .public) dwjz=\(quote.dwjz, privacy: .private) gsz=\(quote.gsz, privacy: .private) gszzl=\(quote.gszzl, privacy: .private)"
            )
            return quote
        } catch {
            let bodyPreview = String(text.prefix(200))
            Self.logger.error(
                "[Quote] parse failed code=\(code, privacy: .private) bytes=\(data.count) body=\(bodyPreview, privacy: .private) error=\(String(describing: error), privacy: .private)"
            )
            throw error
        }
    }

    private func parseJSONP(_ text: String) throws -> FundQuote {
        // 提取 jsonpgz({...}); 中的 JSON 部分
        let pattern = #"jsonpgz\((\{.+\})\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            throw FundAPIError.parseError
        }
        let json = String(text[range])
        guard let jsonData = json.data(using: .utf8),
              let quote = try? JSONDecoder().decode(FundQuote.self, from: jsonData) else {
            throw FundAPIError.parseError
        }
        return quote
    }
}
