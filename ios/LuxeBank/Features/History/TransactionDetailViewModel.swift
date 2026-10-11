import Foundation
import Observation

/// One transaction: reference, channel, account, category and memo (TXN-04, TXN-05).
@MainActor
@Observable
final class TransactionDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded(TransactionDetail)
        case failed
    }

    private(set) var state: State = .loading
    private(set) var isSaving = false
    private(set) var saveFailed = false

    let transactionID: UUID
    private let repository: TransactionRepository
    private let onChange: (Transaction) -> Void

    init(transactionID: UUID, repository: TransactionRepository, onChange: @escaping (Transaction) -> Void = { _ in }) {
        self.transactionID = transactionID
        self.repository = repository
        self.onChange = onChange
    }

    var detail: TransactionDetail? {
        if case .loaded(let detail) = state { return detail }
        return nil
    }

    /// Only spending can be recategorised; income, transfers and cashback keep their category.
    var canChangeCategory: Bool {
        guard let category = detail?.transaction.category else { return false }
        return TransactionCategory.assignable.contains(category)
    }

    func load() async {
        do {
            state = .loaded(try await repository.transaction(id: transactionID))
        } catch {
            state = .failed
        }
    }

    func retry() async {
        state = .loading
        await load()
    }

    func changeCategory(_ category: TransactionCategory) async {
        guard canChangeCategory, category != detail?.transaction.category else { return }
        await save(category: category, memo: nil)
    }

    /// Empty text clears the memo.
    func saveMemo(_ memo: String) async {
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (detail?.transaction.memo ?? "") else { return }
        await save(category: nil, memo: String(trimmed.prefix(Self.memoLimit)))
    }

    private func save(category: TransactionCategory?, memo: String?) async {
        isSaving = true
        saveFailed = false
        defer { isSaving = false }
        do {
            let updated = try await repository.updateTransaction(id: transactionID, category: category, memo: memo)
            state = .loaded(updated)
            onChange(updated.transaction)
        } catch {
            saveFailed = true
        }
    }

    static let memoLimit = 100
}
