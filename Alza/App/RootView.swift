import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isLoadingSession {
                ProgressView()
            } else if !appState.isSignedIn {
                AuthView()
            } else if appState.onboardingStatus == .unknown {
                ProgressView()
            } else if appState.onboardingStatus == .pending {
                OnboardingView()
            } else if !appState.subscriptionStatus.isEntitled {
                PaywallView(subscriptionStore: appState.subscriptionStore)
            } else {
                DashboardTabView()
            }
        }
    }
}
