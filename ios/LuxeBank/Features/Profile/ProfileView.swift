import SwiftUI

/// Profile and settings (PROF-*) arrive in M5.
struct ProfileView: View {
    var body: some View {
        ComingSoonView(title: "tab.profile", message: "profile.placeholder", symbol: "person.crop.circle")
    }
}

#Preview {
    ProfileView()
}
