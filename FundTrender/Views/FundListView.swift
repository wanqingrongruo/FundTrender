import SwiftUI
import SwiftData

struct FundListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @StateObject private var vm = FundListViewModel()
    @State private var selectedCategory: FundCategory = .holding
    @State private var isShowingRefreshFailures = false

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
            .sheet(isPresented: $isShowingRefreshFailures) {
                FundRefreshFailuresView(failures: vm.refreshFailures)
            }
            .safeAreaInset(edge: .top) {
                if !vm.refreshFailures.isEmpty {
                    Button {
                        isShowingRefreshFailures = true
                    } label: {
                        Label("查看失败详情（\(vm.refreshFailures.count)）", systemImage: "exclamationmark.triangle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                    }
                    .padding(.horizontal)
                    .background(.bar)
                }
            }
            .overlay {
                if vm.isLoading {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .overlay(alignment: .top) {
                if let message = vm.errorMessage {
                    ErrorToastView(message: message, showDetails: vm.refreshFailures.isEmpty ? nil : {
                        vm.errorMessage = nil
                        isShowingRefreshFailures = true
                    }) {
                        withAnimation {
                            vm.errorMessage = nil
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        guard !isVoiceOverEnabled else { return }
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled, vm.errorMessage == message else { return }
                        withAnimation {
                            vm.errorMessage = nil
                        }
                    }
                    .onAppear {
                        AccessibilityNotification.Announcement(message).post()
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.errorMessage)
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

private struct ErrorToastView: View {
    let message: String
    let showDetails: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)

                if let showDetails {
                    Button("查看失败详情", action: showDetails)
                        .frame(minHeight: 44)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.orange.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .accessibilityElement(children: .contain)
    }
}
