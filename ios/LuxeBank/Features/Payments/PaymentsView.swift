import SwiftUI

/// Transfers and bill payments (TRF-*, BILL-*) arrive in M3.
struct PaymentsView: View {
    var body: some View {
        ComingSoonView(title: "tab.payments", message: "payments.placeholder", symbol: "arrow.left.arrow.right")
    }
}

#Preview {
    PaymentsView()
}
