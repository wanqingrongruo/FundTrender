import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class FundListViewModel: ObservableObject {
    @Published var funds: [FundEntity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isAddingFund = false

    private var context: ModelContext?

    func setup(context: ModelContext) {
        self.context = context
        loadFunds()
    }

    func loadFunds() {
        guard let context else { return }
        let descriptor = FetchDescriptor<FundEntity>(sortBy: [SortDescriptor(\.sortOrder)])
        funds = (try? context.fetch(descriptor)) ?? []
    }

    func refreshAll() async {
        guard !funds.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: (String, FundQuote?).self) { group in
            for fund in funds {
                let code = fund.code
                group.addTask {
                    (code, try? await FundAPIService.shared.fetchQuote(code: code))
                }
            }
            for await (code, quote) in group {
                guard let quote, let fund = funds.first(where: { $0.code == code }) else { continue }
                fund.prevPreviousNav = fund.previousNav  // 滚动保存，用于计算昨日涨跌幅
                fund.name = quote.name
                fund.previousNav = Double(quote.dwjz) ?? 0
                fund.currentEstimate = Double(quote.gsz) ?? 0
                fund.changePercent = Double(quote.gszzl) ?? 0
                fund.lastUpdated = Date()
            }
        }
        try? context?.save()
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
