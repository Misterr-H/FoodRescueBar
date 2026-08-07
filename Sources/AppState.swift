import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // Navigation
    @Published var screen: AppScreen = .login
    @Published var isBusy = false
    @Published var bannerMessage: String?
    @Published var bannerIsError = false

    // Auth
    @Published var phoneDigits = ""
    @Published var otpCode = ""
    @Published var otpChannel: OTPChannel = .sms
    @Published var otpSent = false
    @Published var user: ZomatoUser?
    @Published private(set) var isLoggedIn = false

    // Location
    @Published var locations: [UserLocation] = []
    @Published var selectedLocation: UserLocation?
    @Published var isLoadingLocations = false

    // Monitoring
    @Published var monitorState: MonitorState = .idle
    @Published var isMonitoring = false
    @Published var lastConnectedDescription = "Not connected"
    @Published var events: [RescueEvent] = []
    @Published var alertCountToday = 0
    @Published var lastAlertAt: Date?

    // Settings
    @AppStorage("cooldownSeconds") var cooldownSeconds: Double = 180
    @AppStorage("playSound") var playSound = true
    @AppStorage("launchAtLogin") var launchAtLoginPref = false {
        didSet { LaunchAtLogin.isEnabled = launchAtLoginPref }
    }

    private let auth = AuthService()
    private let api = ZomatoAPI()
    private let mqtt = MQTTMonitor()
    private var tokens: AuthTokens?
    private var channel: FoodRescueChannel?
    private var cityId: Int = 0
    private var reliabilityTask: Task<Void, Never>?
    private var lastNotifiedAt: Date = .distantPast
    private var connectedAt: Date?

    init() {
        mqtt.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleMQTT(event)
            }
        }
        restoreSession()
    }

    // MARK: - Session

    private func restoreSession() {
        guard let access = KeychainStore.get(.accessToken) else {
            screen = .login
            return
        }
        let refresh = KeychainStore.get(.refreshToken) ?? ""
        tokens = AuthTokens(accessToken: access, refreshToken: refresh)
        isLoggedIn = true
        user = KeychainStore.getCodable(ZomatoUser.self, for: .userProfile)
        selectedLocation = KeychainStore.getCodable(UserLocation.self, for: .selectedLocation)

        if selectedLocation != nil {
            screen = .home
            Task { await refreshProfileQuietly() }
        } else {
            screen = .location
            Task { await loadLocations() }
        }
    }

    // MARK: - Auth actions

    func sendOTP() async {
        let phone = normalizedPhone
        guard phone.count == 10 else {
            flash("Enter a valid 10-digit Indian mobile number", error: true)
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await auth.sendOTP(phone: phone, channel: otpChannel)
            otpSent = true
            flash("OTP sent via \(otpChannel.title)")
        } catch {
            flash(error.localizedDescription, error: true)
        }
    }

    func verifyOTP() async {
        let phone = normalizedPhone
        guard otpCode.count >= 4 else {
            flash("Enter the OTP you received", error: true)
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await auth.verifyOTP(phone: phone, otp: otpCode)
            tokens = result
            KeychainStore.set(result.accessToken, for: .accessToken)
            KeychainStore.set(result.refreshToken, for: .refreshToken)
            isLoggedIn = true

            if let profile = try? await api.fetchUser(accessToken: result.accessToken) {
                user = profile
                KeychainStore.setCodable(profile, for: .userProfile)
            }

            otpCode = ""
            otpSent = false
            screen = .location
            flash("Signed in successfully")
            await loadLocations()
        } catch {
            flash(error.localizedDescription, error: true)
        }
    }

    func logout() async {
        stopMonitoring()
        if let tokens {
            await auth.logout(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
        }
        tokens = nil
        user = nil
        locations = []
        selectedLocation = nil
        isLoggedIn = false
        otpSent = false
        otpCode = ""
        events = []
        monitorState = .idle
        KeychainStore.clearSession()
        screen = .login
        flash("Signed out")
    }

    private var normalizedPhone: String {
        let digits = phoneDigits.filter(\.isNumber)
        if digits.count == 12, digits.hasPrefix("91") {
            return String(digits.suffix(10))
        }
        return digits
    }

    // MARK: - Locations

    func loadLocations() async {
        guard let token = tokens?.accessToken else { return }
        isLoadingLocations = true
        defer { isLoadingLocations = false }
        do {
            locations = try await api.fetchLocations(accessToken: token)
            if let selected = selectedLocation,
               let match = locations.first(where: { $0.addressId == selected.addressId }) {
                selectedLocation = match
            }
        } catch let err as APIError where err == .unauthorized || isUnauthorized(err) {
            await forceReauth()
        } catch {
            flash(error.localizedDescription, error: true)
        }
    }

    func selectLocation(_ location: UserLocation) {
        selectedLocation = location
        KeychainStore.setCodable(location, for: .selectedLocation)
        screen = .home
        flash("Monitoring area: \(location.name)")
    }

    // MARK: - Monitoring

    func startMonitoring() async {
        guard let location = selectedLocation, let token = tokens?.accessToken else {
            flash("Pick a saved address first", error: true)
            return
        }

        await NotificationManager.shared.requestAuthorization()

        isMonitoring = true
        monitorState = .connecting
        lastConnectedDescription = "Fetching Food Rescue channel…"

        do {
            let essentials = try await api.fetchTabbedHome(
                cellId: location.cellId,
                addressId: location.addressId,
                accessToken: token
            )
            cityId = essentials.cityId
            guard let fr = essentials.foodRescue else {
                isMonitoring = false
                monitorState = .error("No Food Rescue channel")
                flash("Food Rescue isn’t available for this address right now.", error: true)
                return
            }
            channel = fr
            mqtt.connect(channel: fr)
            startReliabilityLoop()
        } catch {
            isMonitoring = false
            monitorState = .error(error.localizedDescription)
            flash(error.localizedDescription, error: true)
            if isUnauthorized(error) {
                await forceReauth()
            }
        }
    }

    func stopMonitoring() {
        reliabilityTask?.cancel()
        reliabilityTask = nil
        mqtt.disconnect()
        isMonitoring = false
        monitorState = .idle
        lastConnectedDescription = "Stopped"
        connectedAt = nil
    }

    func toggleMonitoring() async {
        if isMonitoring {
            stopMonitoring()
            flash("Stopped listening")
        } else {
            await startMonitoring()
        }
    }

    private func startReliabilityLoop() {
        reliabilityTask?.cancel()
        reliabilityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, self.isMonitoring else { break }
                await self.reliabilityTick()
            }
        }
    }

    private func reliabilityTick() async {
        guard isMonitoring, let location = selectedLocation, let token = tokens?.accessToken else { return }

        // Refresh channel credentials periodically / on disconnect
        let needsReconnect = !mqtt.isConnected || mqtt.shouldForceReconnect()
        if needsReconnect {
            monitorState = .reconnecting
            lastConnectedDescription = "Refreshing session…"
            do {
                let essentials = try await api.fetchTabbedHome(
                    cellId: location.cellId,
                    addressId: location.addressId,
                    accessToken: token
                )
                if let fr = essentials.foodRescue {
                    channel = fr
                    cityId = essentials.cityId
                    mqtt.connect(channel: fr)
                } else {
                    monitorState = .error("Channel missing")
                }
            } catch {
                monitorState = .error(error.localizedDescription)
                if isUnauthorized(error) {
                    await forceReauth()
                }
            }
        } else if mqtt.isConnected {
            monitorState = .connected
            updateConnectedDescription()
        }
    }

    private func handleMQTT(_ event: MQTTMonitor.Event) {
        switch event {
        case .connected:
            connectedAt = Date()
            monitorState = .connected
            updateConnectedDescription()
            flash("Listening for Food Rescue near \(selectedLocation?.name ?? "you")")

        case .disconnected(let reason):
            if isMonitoring {
                monitorState = .reconnecting
                lastConnectedDescription = reason.map { "Disconnected: \($0)" } ?? "Disconnected"
            } else {
                monitorState = .idle
            }

        case .message(let id, let type, let timestamp, let raw):
            let item = RescueEvent(id: id, type: type, timestamp: timestamp, rawPreview: raw)
            events.insert(item, at: 0)
            if events.count > 40 { events = Array(events.prefix(40)) }

            if type == .orderCancelled {
                handleCancelAlert()
            }

        case .log:
            break
        }
    }

    private func handleCancelAlert() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastNotifiedAt)
        guard elapsed >= cooldownSeconds else { return }
        lastNotifiedAt = now
        lastAlertAt = now
        alertCountToday += 1
        NotificationManager.shared.sendFoodRescueAlert(playSound: playSound)
    }

    private func updateConnectedDescription() {
        if let connectedAt {
            let mins = Int(Date().timeIntervalSince(connectedAt) / 60)
            if mins < 1 {
                lastConnectedDescription = "Connected just now"
            } else if mins == 1 {
                lastConnectedDescription = "Connected 1 min ago"
            } else {
                lastConnectedDescription = "Connected \(mins) min ago"
            }
        }
    }

    private func refreshProfileQuietly() async {
        guard let token = tokens?.accessToken else { return }
        if let profile = try? await api.fetchUser(accessToken: token) {
            user = profile
            KeychainStore.setCodable(profile, for: .userProfile)
        }
    }

    private func forceReauth() async {
        stopMonitoring()
        tokens = nil
        isLoggedIn = false
        KeychainStore.clearSession()
        screen = .login
        flash("Session expired — please sign in again", error: true)
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        if let api = error as? APIError, case .unauthorized = api { return true }
        return false
    }

    func flash(_ message: String, error: Bool = false) {
        bannerMessage = message
        bannerIsError = error
        Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if bannerMessage == message {
                bannerMessage = nil
            }
        }
    }

    func openZomato() {
        NotificationManager.openZomato()
    }

    var menuBarSystemImage: String {
        if !isLoggedIn { return "fork.knife.circle" }
        switch monitorState {
        case .connected: return "leaf.circle.fill"
        case .connecting, .reconnecting: return "leaf.circle"
        case .error: return "exclamationmark.circle.fill"
        case .idle: return "fork.knife.circle"
        }
    }

    var statusColor: Color {
        switch monitorState {
        case .connected: return FRTheme.success
        case .connecting, .reconnecting: return FRTheme.warning
        case .error: return FRTheme.brand
        case .idle: return .secondary
        }
    }
}

extension APIError: Equatable {
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.missingFoodRescue, .missingFoodRescue): return true
        case (.noLocations, .noLocations): return true
        case (.http(let a, _), .http(let b, _)): return a == b
        case (.decode, .decode): return true
        default: return false
        }
    }
}
