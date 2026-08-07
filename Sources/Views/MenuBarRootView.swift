import SwiftUI

struct MenuBarRootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let banner = state.bannerMessage {
                BannerToast(message: banner, isError: state.bannerIsError)
                    .padding(.horizontal, FRTheme.contentPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 2)
            }

            Group {
                switch state.screen {
                case .login:
                    LoginView()
                case .location:
                    LocationView()
                case .home:
                    HomeView()
                case .settings:
                    SettingsView()
                }
            }
            .padding(FRTheme.contentPadding)
        }
        .frPopoverPanel()
        .background(FRTheme.surface)
        .animation(.easeInOut(duration: 0.15), value: state.screen)
        .animation(.easeInOut(duration: 0.15), value: state.bannerMessage)
    }
}
