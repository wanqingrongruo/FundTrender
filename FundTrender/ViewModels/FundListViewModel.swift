import Foundation
import SwiftUI
import SwiftData
import Combine
import OSLog

@MainActor
class FundListViewModel: ObservableObject {
    @Published var funds: [FundEntity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var refreshFailures: [FundRefreshFailure] = []
    @Published var isAddingFund = false

    private var context: ModelContext?
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "FundTrender",
        category: "FundListViewModel"
    )

    func setup(context: ModelContext) {
        Self.logger.info("[FundList] setup context")
        self.context = context
        loadFunds()
    }

    func loadFunds() {
        guard let context else {
            Self.logger.error("[FundList] load skipped: model context is nil")
            return
        }
        let descriptor = FetchDescriptor<FundEntity>(sortBy: [SortDescriptor(\.sortOrder)])
        do {
            funds = try context.fetch(descriptor)
            let codes = funds.map(\.code).joined(separator: ",")
            Self.logger.debug("[FundList] loaded count=\(self.funds.count) codes=\(codes, privacy: .private)")
        } catch {
            funds = []
            Self.logger.error("[FundList] load failed error=\(String(describing: error), privacy: .private)")
        }
    }

    func refreshAll() async {
        let refreshID = String(UUID().uuidString.prefix(8))
        guard !isLoading else {
            Self.logger.notice("[Refresh \(refreshID, privacy: .public)] skipped: another refresh is running")
            return
        }
        guard !funds.isEmpty else {
            Self.logger.notice("[Refresh \(refreshID, privacy: .public)] skipped: fund list is empty")
            return
        }
        errorMessage = nil
        refreshFailures = []
        let startedAt = Date()
        let requestedFunds = funds.map { (code: $0.code, name: $0.name) }
        let requestCount = requestedFunds.count
        let requestedCodes = requestedFunds.map(\.code).joined(separator: ",")
        Self.logger.notice(
            "[Refresh \(refreshID, privacy: .public)] start count=\(requestCount) codes=\(requestedCodes, privacy: .private)"
        )
        isLoading = true
        defer {
            isLoading = false
            let elapsed = Date().timeIntervalSince(startedAt)
            Self.logger.notice(
                "[Refresh \(refreshID, privacy: .public)] end elapsed=\(elapsed, format: .fixed(precision: 3))s"
            )
        }

        var successCount = 0
        var failureReasons: [Int: String] = [:]
        var cancellationCount = 0
        await withTaskGroup(of: (Int, FundQuote?, String?, Bool).self) { group in
            for (index, fund) in requestedFunds.enumerated() {
                let code = fund.code
                group.addTask {
                    do {
                        return (index, try await FundAPIService.shared.fetchQuote(code: code), nil, false)
                    } catch is CancellationError {
                        return (index, nil, nil, true)
                    } catch let error as URLError where error.code == .cancelled {
                        return (index, nil, nil, true)
                    } catch {
                        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        return (index, nil, reason, false)
                    }
                }
            }
            for await (index, quote, errorDescription, wasCancelled) in group {
                let code = requestedFunds[index].code
                if wasCancelled {
                    cancellationCount += 1
                    failureReasons[index] = "请求已取消，请重试"
                    continue
                }
                guard let quote else {
                    failureReasons[index] = errorDescription ?? "未知错误，请稍后重试"
                    Self.logger.error(
                        "[Refresh \(refreshID, privacy: .public)] quote failed code=\(code, privacy: .private) error=\(errorDescription ?? "unknown", privacy: .private)"
                    )
                    continue
                }
                guard let fund = funds.first(where: { $0.code == code }) else {
                    failureReasons[index] = "基金已从列表移除，本次结果未保存"
                    Self.logger.error(
                        "[Refresh \(refreshID, privacy: .public)] result ignored: fund disappeared code=\(code, privacy: .private)"
                    )
                    continue
                }

                successCount += 1
                let oldPreviousNav = fund.previousNav
                let oldEstimate = fund.currentEstimate
                let oldChangePercent = fund.changePercent
                let newPreviousNav = Double(quote.dwjz) ?? 0
                let newEstimate = Double(quote.gsz) ?? 0
                let newChangePercent = Double(quote.gszzl) ?? 0
                let valuesChanged = oldPreviousNav != newPreviousNav
                    || oldEstimate != newEstimate
                    || oldChangePercent != newChangePercent
                Self.logger.debug(
                    "[Refresh \(refreshID, privacy: .public)] apply code=\(code, privacy: .private) gztime=\(quote.gztime, privacy: .public) changed=\(valuesChanged) nav=\(oldPreviousNav, format: .fixed(precision: 4), privacy: .private)->\(newPreviousNav, format: .fixed(precision: 4), privacy: .private) estimate=\(oldEstimate, format: .fixed(precision: 4), privacy: .private)->\(newEstimate, format: .fixed(precision: 4), privacy: .private) percent=\(oldChangePercent, format: .fixed(precision: 2), privacy: .private)->\(newChangePercent, format: .fixed(precision: 2), privacy: .private)"
                )
                fund.prevPreviousNav = fund.previousNav  // 滚动保存，用于计算昨日涨跌幅
                fund.name = quote.name
                fund.previousNav = newPreviousNav
                fund.currentEstimate = newEstimate
                fund.changePercent = newChangePercent
                fund.lastUpdated = Date()
            }
        }
        guard !Task.isCancelled else {
            Self.logger.notice(
                "[Refresh \(refreshID, privacy: .public)] cancelled completed=\(successCount + failureReasons.count - cancellationCount) cancelled=\(cancellationCount)"
            )
            return
        }
        refreshFailures = requestedFunds.enumerated().compactMap { index, fund in
            guard let reason = failureReasons[index] else { return nil }
            return FundRefreshFailure(code: fund.code, name: fund.name, reason: reason)
        }
        let failureCount = refreshFailures.count
        Self.logger.notice(
            "[Refresh \(refreshID, privacy: .public)] requests finished success=\(successCount) failure=\(failureCount)"
        )
        if failureCount == requestCount {
            errorMessage = "刷新失败，行情服务暂不可用，已保留上次数据"
        } else if failureCount > 0 {
            errorMessage = "部分基金刷新失败（\(failureCount)/\(requestCount)），成功数据已更新，其余保留上次数据"
        }
        do {
            try context?.save()
            Self.logger.info("[Refresh \(refreshID, privacy: .public)] model context saved")
        } catch {
            errorMessage = "刷新结果保存失败，请稍后重试"
            Self.logger.error(
                "[Refresh \(refreshID, privacy: .public)] model context save failed error=\(String(describing: error), privacy: .private)"
            )
        }
        loadFunds()
    }

    func addFund(code: String, category: FundCategory) async throws {
        guard let context else { return }
        let quote = try await FundAPIService.shared.fetchQuote(code: code)
        let entity = FundEntity(
            code: quote.fundcode,
            name: quote.name,
            category: category,
            previousNav: Double(quote.dwjz) ?? 0,
            currentEstimate: Double(quote.gsz) ?? 0,
            changePercent: Double(quote.gszzl) ?? 0,
            sortOrder: funds.count
        )
        context.insert(entity)
        try context.save()
        loadFunds()
    }

    func deleteFund(_ fund: FundEntity) {
        context?.delete(fund)
        try? context?.save()
        loadFunds()
    }

    func moveFunds(in category: FundCategory, from source: IndexSet, to destination: Int) {
        var catFunds = funds.filter { $0.category == category.rawValue }
        catFunds.move(fromOffsets: source, toOffset: destination)
        // 重新分配该分类内的 sortOrder，保持其他分类不变
        let base = funds.filter { $0.category != category.rawValue }.count
        for (index, fund) in catFunds.enumerated() {
            fund.sortOrder = base + index
        }
        try? context?.save()
        loadFunds()
    }

    func exportCSV() -> URL {
        CSVExporter.export(funds: funds)
    }
}
