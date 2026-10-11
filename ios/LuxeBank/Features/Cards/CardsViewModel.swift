import Foundation
import Observation

/// S15 — the customer's cards, the selected card's summary and its latest purchases (CARD-01, 02, 08, 09).
@MainActor
@Observable
final class CardsViewModel {
    enum State: Equatable {
        case loading
        case loaded
        case empty
        case failed
    }

    private(set) var state: State = .loading
    private(set) var cards: [BankCard] = []
    private(set) var recent: [Transaction] = []
    private(set) var isUpdating = false
    private(set) var error: LocalizedStringResource?
    var selectedID: UUID?
    /// Lost card → its replacement, so screens opened for the old card follow it.
    private var replacements: [UUID: UUID] = [:]

    let repository: CardRepository

    init(repository: CardRepository) {
        self.repository = repository
    }

    var selected: BankCard? { cards.first { $0.id == selectedID } ?? cards.first }

    /// The card with [id], or the card that replaced it.
    func card(id: UUID) -> BankCard? {
        var current = id
        while let next = replacements[current] { current = next }
        return cards.first { $0.id == current }
    }

    func load() async {
        do {
            cards = try await repository.cards()
            if selectedID == nil || !cards.contains(where: { $0.id == selectedID }) { selectedID = cards.first?.id }
            state = cards.isEmpty ? .empty : .loaded
            await loadRecent()
        } catch {
            if cards.isEmpty { state = .failed }
        }
    }

    func select(_ id: UUID) async {
        guard id != selectedID else { return }
        selectedID = id
        recent = []
        await loadRecent()
    }

    /// CARD-03 from the card's action row.
    func toggleFreeze() async {
        guard let card = selected, !isUpdating else { return }
        isUpdating = true
        error = nil
        defer { isUpdating = false }
        do {
            replace(try await repository.setFrozen(cardID: card.id, frozen: !card.isFrozen))
        } catch {
            self.error = "error.generic"
        }
    }

    /// Keeps the list in step with the detail screen; a reported-lost card is swapped for its replacement.
    func replace(_ card: BankCard, replacing old: UUID? = nil) {
        if let old, let index = cards.firstIndex(where: { $0.id == old }) {
            cards[index] = card
            replacements[old] = card.id
            selectedID = card.id
        } else if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        }
    }

    private func loadRecent() async {
        guard let card = selected else { return }
        recent = (try? await repository.transactions(cardID: card.id, cursor: nil).items.prefix(5)).map(Array.init) ?? []
    }
}
