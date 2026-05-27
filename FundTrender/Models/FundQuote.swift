import Foundation

struct FundQuote: Codable {
    let fundcode: String
    let name: String
    let dwjz: String   // 昨日净值
    let gsz: String    // 今日估算净值
    let gszzl: String  // 估算涨跌幅
    let gztime: String // 估算时间
}
