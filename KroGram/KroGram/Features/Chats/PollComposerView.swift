import SwiftUI

struct PollComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options = ["", ""]
    @State private var isAnonymous = true
    @State private var allowsMultipleAnswers = false
    @State private var isSending = false
    @State private var errorMessage: String?

    let onSend: (String, [String], Bool, Bool) async throws -> Void

    private var trimmedOptions: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var canSend: Bool {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isSending && !trimmedQuestion.isEmpty && (trimmedQuestion as NSString).length <= 300
            && (2...10).contains(trimmedOptions.count)
            && trimmedOptions.allSatisfy { !$0.isEmpty && ($0 as NSString).length <= 100 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("poll.question") {
                    TextField("poll.question.placeholder", text: $question, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityHint(Text("poll.question.limit"))
                }
                Section("poll.options") {
                    ForEach(options.indices, id: \.self) { index in
                        HStack {
                            TextField(
                                String(format: L("poll.option.placeholder"), index + 1),
                                text: $options[index]
                            )
                            if options.count > 2 {
                                Button(role: .destructive) {
                                    options.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .accessibilityLabel(Text("poll.removeOption"))
                            }
                        }
                    }
                    if options.count < 10 {
                        Button {
                            options.append("")
                        } label: {
                            Label("poll.addOption", systemImage: "plus")
                        }
                    }
                }
                Section("poll.settings") {
                    Toggle("poll.anonymous", isOn: $isAnonymous)
                    Toggle("poll.multipleAnswers", isOn: $allowsMultipleAnswers)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("poll.create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("poll.send", action: send)
                        .disabled(!canSend)
                }
            }
        }
    }

    private func send() {
        guard canSend else { return }
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await onSend(trimmedQuestion, trimmedOptions, isAnonymous, allowsMultipleAnswers)
                dismiss()
            } catch {
                errorMessage = TGErrors.message(for: error)
                isSending = false
            }
        }
    }
}
