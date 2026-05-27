import SwiftUI

struct AddFundView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: FundListViewModel

    @State private var input = ""
    @State private var category: FundCategory = .holding
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var codes: [String] {
        input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: #"^\d{6}$"#, options: .regularExpression) != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("多个基金代码用逗号分隔，如：110022,000001")) {
                    TextField("基金代码", text: $input)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .onChange(of: input) { errorMessage = nil }
                    
                    Button {
                        if let text = UIPasteboard.general.string {
                            input = text
                            errorMessage = nil
                        }
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }
                }
                Section {
                    Picker("分类", selection: $category) {
                        ForEach(FundCategory.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("添加基金")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("添加") { addFunds() }
                            .disabled(codes.isEmpty)
                    }
                }
            }
        }
    }

    private func addFunds() {
        isLoading = true
        Task {
            var failed: [String] = []
            for code in codes {
                do {
                    try await vm.addFund(code: code, category: category)
                } catch {
                    failed.append(code)
                }
            }
            if failed.isEmpty {
                dismiss()
            } else {
                input = failed.joined(separator: ",")
                errorMessage = "以下代码添加失败：\(failed.joined(separator: ", "))"
            }
            isLoading = false
        }
    }
}
