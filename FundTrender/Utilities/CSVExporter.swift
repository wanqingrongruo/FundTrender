import Foundation

struct CSVExporter {
    static func export(funds: [FundEntity]) -> URL {
        var csv = "\u{FEFF}基金代码,基金名称,昨日净值,今日估算净值,估算涨跌幅(%),更新时间\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        for f in funds {
            let updated = f.lastUpdated.map { formatter.string(from: $0) } ?? "--"
            csv += "\(f.code),\(f.name),\(f.previousNav),\(f.currentEstimate),\(f.changePercent),\(updated)\n"
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("funds_export.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
