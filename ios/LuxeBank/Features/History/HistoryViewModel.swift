import Foundation
import Observation

/// History of one account with filters, search and cursor paging (TXN-01…03).
@MainActor
@Observable
final class HistoryViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case empty
        case failed
    }

    struct DaySection: Identifiable, Equatable {
        let day: Date
        let items: [Transaction]
        var id: Date { day }
    }

    private(set) var state: State = .loading
    private(set) var items: [Transaction] = []
    private(set) var totals: MoneyTotals?
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    var query = TransactionQuery()

    let account: Account
    private let repository: TransactionRepository
    private let calendar: Calendar
    private let debounce: Duration
    private var nextCursor: String?
    private var loadedQuery: TransactionQuery?
    private var generation = 0

    init(account: Account, repository: TransactionRepository, calendar: Calendar = .current, debounce: Duration = .milliseconds(300)) {
        self.account = account
        self.repository = repository
        self.calendar = calendar
        self.debounce = debounce
    }

    var hasActiveFilters: Bool {
        query.direction != nil || query.category != nil || query.periodDays != TransactionQuery().periodDays || !query.text.isEmpty
    }

    var canLoadMore: Bool { nextCursor != nil }

    /// Rows grouped by calendar day, newest first.
    var sections: [DaySection] {
        var result: [DaySection] = []
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            if let last = result.last, last.day == day {
                result[result.count - 1] = DaySection(day: day, items: last.items + [item])
            } else {
                result.append(DaySection(day: day, items: [item]))
            }
        }
        return result
    }

    /// Loads the first page for the current query. Typing in the search box is debounced;
    /// a response for an older query is dropped.
    func reload() async {
        if let loadedQuery, loadedQuery.text != query.text, debounce > .zero {
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
        }
        generation += 1
        let current = generation
        let requested = query
        if items.isEmpty { state = .loading }
        do {
            let page = try await Signposts.measure(.historyLoad) {
                try await repository.transactions(accountID: account.id, query: requested, cursor: nil)
            }
            guard current == generation else { return }
            items = page.items
            totals = page.totals
            nextCursor = page.nextCursor
            loadedQuery = requested
            loadMoreFailed = false
            state = page.items.isEmpty ? .empty : .loaded
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            items = []
            nextCursor = nil
            state = .failed
        }
    }

    /// Fetches the next page when the last row appears.
    func loadMoreIfNeeded(after item: Transaction) async {
        guard item.id == items.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        let current = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.transactions(accountID: account.id, query: query, cursor: cursor)
            guard current == generation else { return }
            items += page.items
            nextCursor = page.nextCursor
            loadMoreFailed = false
        } catch {
            loadMoreFailed = true
        }
    }

    func clearFilters() {
        query = TransactionQuery()
    }

    /// Keeps the list in sync after the detail screen edits a transaction.
    func replace(_ transaction: Transaction) {
        guard let index = items.firstIndex(where: { $0.id == transaction.id }) else { return }
        items[index] = transaction
    }
}
