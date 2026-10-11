import Foundation
import Observation

/// NOTI-03: the in-app inbox, newest first, with read state.
@MainActor
@Observable
final class InboxViewModel {
    private(set) var items: [InboxItem] = []
    private(set) var unreadCount = 0
    private(set) var isLoading = false
    private(set) var failed = false
    private var nextCursor: String?
    private let repository: ProfileRepository
    private let onUnreadChange: (Int) -> Void

    init(repository: ProfileRepository, onUnreadChange: @escaping (Int) -> Void = { _ in }) {
        self.repository = repository
        self.onUnreadChange = onUnreadChange
    }

    var hasMore: Bool { nextCursor != nil }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repository.notifications(cursor: nil)
            items = page.items
            nextCursor = page.nextCursor
            setUnread(page.unreadCount)
            failed = false
        } catch {
            failed = items.isEmpty
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await repository.notifications(cursor: cursor) else { return }
        let known = Set(items.map(\.id))
        items += page.items.filter { !known.contains($0.id) }
        nextCursor = page.nextCursor
        setUnread(page.unreadCount)
    }

    func open(_ item: InboxItem) async {
        // Uses the current state, not the row's copy: a second tap must not count twice.
        guard let index = items.firstIndex(where: { $0.id == item.id }), !items[index].isRead else { return }
        items[index].isRead = true
        setUnread(max(0, unreadCount - 1))
        do {
            try await repository.markRead(id: item.id)
        } catch {
            items[index].isRead = false
            setUnread(unreadCount + 1)
        }
    }

    func markAllRead() async {
        guard unreadCount > 0 else { return }
        let before = items
        let count = unreadCount
        for index in items.indices { items[index].isRead = true }
        setUnread(0)
        do {
            try await repository.markAllRead()
        } catch {
            items = before
            setUnread(count)
        }
    }

    private func setUnread(_ count: Int) {
        unreadCount = count
        onUnreadChange(count)
    }
}
