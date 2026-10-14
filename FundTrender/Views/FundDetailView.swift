import Charts
import SwiftUI

struct FundDetailView: View {
    let fundCode: String
    let fundName: String

    @State private var selectedRange: FundTrendRange = .thirtyDays
    @State private var loadState: LoadState = .loading
    @State private var refreshErrorMessage: String?

    private var allPoints: [FundHistoryPoint] {
        guard case .loaded(let points) = loadState else { return [] }
        return points
    }

    private var displayedPoints: [FundHistoryPoint] {
        guard let endDate = allPoints.last?.date,
              let startDate = selectedRange.startDate(relativeTo: endDate) else {
            return allPoints
        }
        return allPoints.filter { $0.date >= startDate && $0.date <= endDate }
    }

    private var chartPoints: [FundHistoryPoint] {
        let maximumPointCount = 800
        guard displayedPoints.count > maximumPointCount else { return displayedPoints }

        let interiorPointCount = displayedPoints.count - 2
        let bucketCount = max(1, (maximumPointCount - 2) / 2)
        let bucketSize = Int(ceil(Double(interiorPointCount) / Double(bucketCount)))
        var sampled: [FundHistoryPoint] = []
        var includedIDs: Set<Int64> = []

        func appendIfNeeded(_ point: FundHistoryPoint) {
            guard includedIDs.insert(point.id).inserted else { return }
            sampled.append(point)
        }

        if let first = displayedPoints.first {
            appendIfNeeded(first)
        }
        for start in Swift.stride(from: 1, to: displayedPoints.count - 1, by: bucketSize) {
            let end = min(start + bucketSize, displayedPoints.count - 1)
            let bucket = displayedPoints[start..<end]
            guard let minimum = bucket.min(by: { $0.netAssetValue < $1.netAssetValue }),
                  let maximum = bucket.max(by: { $0.netAssetValue < $1.netAssetValue }) else {
                continue
            }
            if minimum.timestamp <= maximum.timestamp {
                appendIfNeeded(minimum)
                appendIfNeeded(maximum)
            } else {
                appendIfNeeded(maximum)
                appendIfNeeded(minimum)
            }
        }
        if let last = displayedPoints.last {
            appendIfNeeded(last)
        }
        return sampled
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = displayedPoints.map(\.netAssetValue)
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let span = maximum - minimum
        let padding = max(span * 0.08, maximum * 0.005, 0.001)
        return max(0, minimum - padding)...(maximum + padding)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                fundIdentity
                rangePicker
                content
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("净值趋势")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadHistory(forceRefresh: true)
        }
        .task(id: fundCode) {
            await loadHistory()
        }
    }

    private var fundIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fundName)
                .font(.headline)
            Text(fundCode)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rangePicker: some View {
        LabeledContent("时间范围") {
            Picker("时间范围", selection: $selectedRange) {
                ForEach(FundTrendRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.menu)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView("正在加载历史净值…")
                .frame(maxWidth: .infinity, minHeight: 320)
        case .failed(let message):
            ContentUnavailableView {
                Label("历史数据加载失败", systemImage: "chart.line.downtrend.xyaxis")
            } description: {
                Text(message)
            } actions: {
                Button("重新加载") {
                    Task { await loadHistory(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 320)
        case .loaded:
            if let refreshErrorMessage {
                Label("刷新失败：\(refreshErrorMessage)", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if displayedPoints.isEmpty {
                ContentUnavailableView(
                    "暂无历史净值",
                    systemImage: "chart.line.flattrend.xyaxis",
                    description: Text("当前时间范围内没有可展示的数据")
                )
                .frame(minHeight: 320)
            } else {
                summary
                trendChart
                Text("数据截至 \(displayedPoints.last?.date.formatted(date: .abbreviated, time: .omitted) ?? "--")，时间范围以最新净值日为基准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("单位净值变化按所选区间首尾净值计算，不包含分红再投资。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 0) {
            metric(title: "最新净值", value: latestValueText, color: .primary)
            Divider().frame(height: 42)
            metric(title: "单位净值变化", value: rangeChangeText, color: rangeChangeColor)
            Divider().frame(height: 42)
            metric(title: "数据点", value: "\(displayedPoints.count)", color: .primary)
        }
        .padding(.vertical, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var trendChart: some View {
        Chart(chartPoints) { point in
            AreaMark(
                x: .value("日期", point.date),
                yStart: .value("图表下限", chartYDomain.lowerBound),
                yEnd: .value("单位净值", point.netAssetValue)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("日期", point.date),
                y: .value("单位净值", point.netAssetValue)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .chartYScale(domain: chartYDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        axisLabel(for: date)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: Decimal.FormatStyle.number.precision(.fractionLength(2...4)))
            }
        }
        .frame(height: 320)
        .padding(.vertical, 12)
        .padding(.trailing, 8)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("\(fundName)\(selectedRange.title)单位净值趋势图")
    }

    @ViewBuilder
    private func axisLabel(for date: Date) -> some View {
        switch selectedRange {
        case .thirtyDays, .sixMonths:
            Text(date, format: .dateTime.month().day())
        case .oneYear, .threeYears, .fiveYears, .all:
            Text(date, format: .dateTime.year().month())
        }
    }

    private var latestValueText: String {
        guard let value = displayedPoints.last?.netAssetValue else { return "--" }
        return String(format: "%.4f", value)
    }

    private var rangeChange: Double? {
        guard displayedPoints.count >= 2,
              let first = displayedPoints.first?.netAssetValue,
              let last = displayedPoints.last?.netAssetValue,
              first > 0 else { return nil }
        return (last - first) / first * 100
    }

    private var rangeChangeText: String {
        guard let rangeChange else { return "--" }
        return String(format: "%@%.2f%%", rangeChange > 0 ? "+" : "", rangeChange)
    }

    private var rangeChangeColor: Color {
        guard let rangeChange else { return .secondary }
        return rangeChange > 0 ? .red : (rangeChange < 0 ? .green : .secondary)
    }

    private func loadHistory(forceRefresh: Bool = false) async {
        let hasLoadedData: Bool
        if case .loaded = loadState {
            hasLoadedData = true
        } else {
            hasLoadedData = false
            loadState = .loading
        }
        refreshErrorMessage = nil

        do {
            let points = try await FundHistoryService.shared.fetchHistory(
                code: fundCode,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            loadState = .loaded(points)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if hasLoadedData {
                refreshErrorMessage = message
            } else {
                loadState = .failed(message)
            }
        }
    }
}

private enum LoadState {
    case loading
    case loaded([FundHistoryPoint])
    case failed(String)
}
