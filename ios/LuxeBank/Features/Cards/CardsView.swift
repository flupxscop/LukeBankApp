import SwiftUI

/// Card management (CARD-*) arrives in M4.
struct CardsView: View {
    var body: some View {
        ComingSoonView(title: "tab.cards", message: "cards.placeholder", symbol: "creditcard")
    }
}

#Preview {
    CardsView()
}
