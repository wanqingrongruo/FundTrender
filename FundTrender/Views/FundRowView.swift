import SwiftUI

struct FundRowView: View {
    let fund: FundEntity

    private var isMarketOpen: Bool { fund.currentEstimate > 0 }

    private var changeColor: Color {
        guard isMarketOpen else { return .secondary }
        return fund.changePercent > 0 ? .red : (fund.changePercent < 0 ? .green : .secondary)
    }

    private var changeText: String {
        guard isMarketOpen else { return "--" }
        let sign = fund.changePercent > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", fund.changePercent))%"
    }

    var body: some View {
        HStack(spacing: 0) {
            // 基金名称列
            VStack(alignment: .leading, spacing: 2) {
                Text(fund.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(fund.code)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 估算列
            VStack(alignment: .trailing, spacing: 2) {
                Text(isMarketOpen ? String(format: "%.4f", fund.currentEstimate) : "--")
                    .font(.subheadline.monospacedDigit())
                Text(changeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(changeColor)
            }
            .frame(width: 80, alignment: .trailing)

            // 昨日净值列
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.4f", fund.previousNav))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Group {
                    if fund.prevPreviousNav > 0 {
                        let change = (fund.previousNav - fund.prevPreviousNav) / fund.prevPreviousNav * 100
                        let sign = change > 0 ? "+" : ""
                        Text("\(sign)\(String(format: "%.2f", change))%")
                            .foregroundStyle(change > 0 ? .red : (change < 0 ? .green : .secondary))
                    } else {
                        Text("--").foregroundStyle(.secondary)
                    }
                }
                .font(.caption.monospacedDigit())
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

struct FundListHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("基金名称")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("估算")
                .frame(width: 80, alignment: .trailing)
            Text("昨日净值")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(.systemGroupedBackground))
    }
}
