import SwiftUI
import SwiftData

struct FundListView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = FundListViewModel()
    @State private var selectedCategory: FundCategory = .holding

    private var filteredFunds: [FundEntity] {
        vm.funds.filter { $0.category == selectedCategory.rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredFunds.isEmpty {
                    ContentUnavailableView("暂无基金", systemImage: "chart.line.uptrend.xyaxis", description: Text("点击右上角 + 添加基金"))
                } else {
                    List {
                        Section(header: FundListHeader().textCase(nil)) {
                            ForEach(filteredFunds) { fund in
                                FundRowView(fund: fund)
                            }
                            .onDelete { indexSet in
                                indexSet.forEach { vm.deleteFund(filteredFunds[$0]) }
                            }
                            .onMove { source, dest in
                                vm.moveFunds(in: selectedCategory, from: source, to: dest)
                            }
                        }
                    }
                    .refreshable { await vm.refreshAll() }
                }
            }
            .navigationTitle("基金估值")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isLoading)

                    ShareLink(item: vm.exportCSV(), preview: SharePreview("基金数据.csv", image: Image(systemName: "doc.text")))
                        .disabled(vm.funds.isEmpty)

                    Button {
                        vm.isAddingFund = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $vm.isAddingFund) {
                AddFundView(vm: vm)
            }
            .alert("错误", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .overlay {
                if vm.isLoading {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Picker("分类", selection: $selectedCategory) {
                    ForEach(FundCategory.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .onAppear { vm.setup(context: modelContext) }
    }
}
