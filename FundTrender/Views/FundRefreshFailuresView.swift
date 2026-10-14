import SwiftUI

struct FundRefreshFailuresView: View {
    @Environment(\.dismiss) private var dismiss

    let failures: [FundRefreshFailure]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(failures) { failure in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(failure.name.isEmpty ? failure.code : failure.name)
                                .font(.headline)
                            Text("基金代码：\(failure.code)")
                                .foregroundStyle(.secondary)
                            Label(failure.reason, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                        .textSelection(.enabled)
                    }
                } header: {
                    Text("本次刷新失败的基金（\(failures.count)）")
                } footer: {
                    Text("包含“我买的”和“待观察”两个分类。刷新成功的基金已更新，其余保留上次数据。")
                }
            }
            .navigationTitle("刷新失败详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
