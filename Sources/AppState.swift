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

    // Locations (multi-select)
    @Published var locations: [UserLocation] = []
    @Published var selectedLocations: [UserLocation] = []
    @Published var isLoadingLocations = false

    // Monitoring (aggregate + per-address)
    @Published var monitorState: MonitorState = .idle
    @Published var isMonitoring = false
    @Published var lastConnectedDescription = "Not connected"
    @Published var locationStatuses: [LocationMonitorStatus] = []
    @Published var events: [RescueEvent] = []
    @Published var alertCountToday = 0
    @Published var lastAlertAt: Date?

    // Settings
    @AppStorage("cooldownSeconds") var cooldownSeconds: Double = 180
    @AppStorage("playSound") var playSound = true
    /// When on, fetches restaurant/price via create-cart (may consume in-app flyer pitch).
    @AppStorage("fetchDealDetails") var fetchDealDetails = true
    @AppStorage("launchAtLogin") var launchAtLoginPref = false {
        didSet { LaunchAtLogin.isEnabled = launchAtLoginPref }
    }

    private let auth = AuthService()
    private let api = ZomatoAPI()
    private var tokens: AuthTokens?

    /// addressId → live MQTT session
    private var monitors: [Int: MQTTMonitor] = [:]
    /// addressId → last Food Rescue channel (for reconnect)
    private var channels: [Int: FoodRescueChannel] = [:]
    /// addressId → city id from tabbed-home
    private var cityIdByAddress: [Int: Int] = [:]
    /// addressId → per-address state
    private var statusByAddress: [Int: LocationMonitorStatus] = [:]

    private var reliabilityTask: Task<Void, Never>?
    private var lastNotifiedAt: Date = .distantPast
    private var connectedAt: Date?

    /// Global dedupe across all MQTT sessions (message id + semantic keys).
    private var seenMessageKeys = Set<String>()
    private var seenSemanticKeys = Set<String>()

    init() {
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
        selectedLocations = loadPersistedLocations()

        if !selectedLocations.isEmpty {
            screen = .home
            rebuildStatusPlaceholders()
            Task { await refreshProfileQuietly() }
        } else {
            screen = .location
            Task { await loadLocations() }
        }
    }

    private func loadPersistedLocations() -> [UserLocation] {
        if let multi = KeychainStore.getCodable([UserLocation].self, for: .selectedLocations), !multi.isEmpty {
            return Array(multi.prefix(AppLimits.maxMonitoredAddresses))
        }
        // Migrate legacy single selection
        if let single = KeychainStore.getCodable(UserLocation.self, for: .selectedLocation) {
            KeychainStore.setCodable([single], for: .selectedLocations)
            return [single]
        }
        return []
    }

    func persistSelectedLocations() {
        KeychainStore.setCodable(selectedLocations, for: .selectedLocations)
        if let first = selectedLocations.first {
            KeychainStore.setCodable(first, for: .selectedLocation)
        } else {
            KeychainStore.delete(.selectedLocation)
        }
    }

    func clearLocationSelection() {
        selectedLocations = []
        persistSelectedLocations()
        rebuildStatusPlaceholders()
    }

    // MARK: - Auth

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
        selectedLocations = []
        locationStatuses = []
        statusByAddress = [:]
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

    // MARK: - Locations (multi)

    func loadLocations() async {
        guard let token = tokens?.accessToken else { return }
        isLoadingLocations = true
        defer { isLoadingLocations = false }
        do {
            locations = try await api.fetchLocations(accessToken: token)
            // Refresh selected objects from server list when possible
            selectedLocations = selectedLocations.compactMap { sel in
                locations.first(where: { $0.addressId == sel.addressId }) ?? sel
            }
            persistSelectedLocations()
            rebuildStatusPlaceholders()
        } catch let err as APIError where err == .unauthorized || isUnauthorized(err) {
            await forceReauth()
        } catch {
            flash(error.localizedDescription, error: true)
        }
    }

    func isLocationSelected(_ location: UserLocation) -> Bool {
        selectedLocations.contains(where: { $0.addressId == location.addressId })
    }

    func toggleLocationSelection(_ location: UserLocation) {
        if let idx = selectedLocations.firstIndex(where: { $0.addressId == location.addressId }) {
            selectedLocations.remove(at: idx)
        } else {
            guard selectedLocations.count < AppLimits.maxMonitoredAddresses else {
                flash("You can monitor up to \(AppLimits.maxMonitoredAddresses) addresses", error: true)
                return
            }
            // Avoid duplicate cells (same rescue topic)
            if selectedLocations.contains(where: { $0.cellId == location.cellId && $0.addressId != location.addressId }) {
                flash("Another selected address already uses this delivery cell", error: true)
                return
            }
            selectedLocations.append(location)
        }
        persistSelectedLocations()
        rebuildStatusPlaceholders()
    }

    func confirmLocationSelection() {
        guard !selectedLocations.isEmpty else {
            flash("Select at least one address", error: true)
            return
        }
        persistSelectedLocations()
        rebuildStatusPlaceholders()
        screen = .home
        let names = selectedLocations.map(\.name).joined(separator: ", ")
        flash("Watching \(selectedLocations.count) area\(selectedLocations.count == 1 ? "" : "s"): \(names)")
    }

    private func rebuildStatusPlaceholders() {
        // Keep live states if monitoring; otherwise idle placeholders
        var next: [LocationMonitorStatus] = []
        for loc in selectedLocations {
            if let existing = statusByAddress[loc.addressId], isMonitoring {
                next.append(LocationMonitorStatus(
                    addressId: loc.addressId,
                    name: loc.name,
                    state: existing.state,
                    detail: existing.detail
                ))
            } else if !isMonitoring {
                let status = LocationMonitorStatus(
                    addressId: loc.addressId,
                    name: loc.name,
                    state: .idle,
                    detail: "Not listening"
                )
                statusByAddress[loc.addressId] = status
                next.append(status)
            } else if let existing = statusByAddress[loc.addressId] {
                next.append(existing)
            } else {
                let status = LocationMonitorStatus(
                    addressId: loc.addressId,
                    name: loc.name,
                    state: .idle,
                    detail: "—"
                )
                statusByAddress[loc.addressId] = status
                next.append(status)
            }
        }
        // Drop statuses for deselected addresses
        let ids = Set(selectedLocations.map(\.addressId))
        statusByAddress = statusByAddress.filter { ids.contains($0.key) }
        locationStatuses = next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        recomputeAggregateState()
    }

    // MARK: - Monitoring

    func startMonitoring() async {
        guard !selectedLocations.isEmpty, let token = tokens?.accessToken else {
            flash("Pick at least one saved address first", error: true)
            return
        }

        await NotificationManager.shared.requestAuthorization()

        isMonitoring = true
        monitorState = .connecting
        lastConnectedDescription = "Connecting \(selectedLocations.count) area\(selectedLocations.count == 1 ? "" : "s")…"

        // Tear down any prior sessions
        for m in monitors.values { m.disconnect() }
        monitors.removeAll()
        channels.removeAll()

        for loc in selectedLocations {
            setStatus(addressId: loc.addressId, name: loc.name, state: .connecting, detail: "Fetching channel…")
        }
        recomputeAggregateState()

        await withTaskGroup(of: Void.self) { group in
            for location in selectedLocations {
                group.addTask { @MainActor in
                    await self.connectLocation(location, token: token, initial: true)
                }
            }
        }

        startReliabilityLoop()
        recomputeAggregateState()

        let live = locationStatuses.filter { $0.state.isLive }.count
        if live > 0 {
            flash("Listening on \(live)/\(selectedLocations.count) address\(selectedLocations.count == 1 ? "" : "es")")
        } else {
            flash("Could not connect any Food Rescue channels", error: true)
        }
    }

    private func connectLocation(_ location: UserLocation, token: String, initial: Bool) async {
        setStatus(addressId: location.addressId, name: location.name, state: .connecting, detail: "Fetching channel…")
        do {
            let essentials = try await api.fetchTabbedHome(
                cellId: location.cellId,
                addressId: location.addressId,
                accessToken: token
            )
            guard let fr = essentials.foodRescue else {
                setStatus(
                    addressId: location.addressId,
                    name: location.name,
                    state: .error("No channel"),
                    detail: "Food Rescue unavailable"
                )
                return
            }
            channels[location.addressId] = fr
            cityIdByAddress[location.addressId] = essentials.cityId

            let monitor = MQTTMonitor(addressId: location.addressId, locationName: location.name)
            monitor.onEvent = { [weak self] event in
                Task { @MainActor in
                    self?.handleMQTT(event, addressId: location.addressId, locationName: location.name)
                }
            }
            monitors[location.addressId]?.disconnect()
            monitors[location.addressId] = monitor
            monitor.connect(channel: fr)
            setStatus(addressId: location.addressId, name: location.name, state: .connecting, detail: "MQTT connecting…")
        } catch {
            setStatus(
                addressId: location.addressId,
                name: location.name,
                state: .error("Failed"),
                detail: error.localizedDescription
            )
            if isUnauthorized(error) {
                await forceReauth()
            }
        }
    }

    func stopMonitoring() {
        reliabilityTask?.cancel()
        reliabilityTask = nil
        for m in monitors.values { m.disconnect() }
        monitors.removeAll()
        channels.removeAll()
        isMonitoring = false
        monitorState = .idle
        lastConnectedDescription = "Stopped"
        connectedAt = nil
        // Keep semantic dedupe so a quick restart doesn't re-show retained claimed spam
        for loc in selectedLocations {
            setStatus(addressId: loc.addressId, name: loc.name, state: .idle, detail: "Stopped")
        }
        recomputeAggregateState()
    }

    /// Remove noisy claimed duplicates already in the feed (one-shot cleanup).
    func pruneDuplicateEvents() {
        // 1) One row per (type, address, orderId or time-bucket)
        var firstPass: [RescueEvent] = []
        var keys = Set<String>()
        for event in events {
            let key: String
            if let oid = event.orderId, !oid.isEmpty {
                key = "\(event.type.rawValue):\(event.addressId):\(oid)"
            } else {
                let bucket = Int(event.timestamp.timeIntervalSince1970 / ZomatoConfig.semanticDedupeWindowSeconds)
                key = "\(event.type.rawValue):\(event.addressId):t\(bucket)"
            }
            if keys.contains(key) { continue }
            keys.insert(key)
            firstPass.append(event)
        }

        // 2) Same order id → keep a single row (prefer claimed)
        var byOrder: [String: RescueEvent] = [:]
        var noOrder: [RescueEvent] = []
        for event in firstPass {
            guard let oid = event.orderId, !oid.isEmpty else {
                noOrder.append(event)
                continue
            }
            let k = "\(event.addressId):\(oid)"
            if let existing = byOrder[k] {
                if event.type == .orderClaimed {
                    var preferred = event
                    // Keep restaurant/price from whichever side had them
                    if preferred.restaurantName == nil { preferred.restaurantName = existing.restaurantName }
                    if preferred.cartFinalCost == nil { preferred.cartFinalCost = existing.cartFinalCost }
                    if preferred.catalogTotalCost == nil { preferred.catalogTotalCost = existing.catalogTotalCost }
                    byOrder[k] = preferred
                } else if existing.type != .orderClaimed {
                    byOrder[k] = event.timestamp >= existing.timestamp ? event : existing
                }
            } else {
                byOrder[k] = event
            }
        }

        events = (Array(byOrder.values) + noOrder)
            .sorted { $0.timestamp > $1.timestamp }
    }

    func toggleMonitoring() async {
        if isMonitoring {
            stopMonitoring()
            flash("Stopped listening")
        } else {
            await startMonitoring()
        }
    }

    /// Called when iOS returns to foreground — reconnect any dead MQTT sessions.
    func ensureMonitoringAlive() async {
        guard isMonitoring, tokens?.accessToken != nil else { return }
        let needsWork = selectedLocations.contains { loc in
            let m = monitors[loc.addressId]
            return m == nil || !(m?.isConnected ?? false)
        }
        if needsWork {
            await reliabilityTick()
        } else {
            recomputeAggregateState()
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
        guard isMonitoring, let token = tokens?.accessToken else { return }

        for location in selectedLocations {
            let monitor = monitors[location.addressId]
            let needsReconnect = monitor == nil || !(monitor?.isConnected ?? false) || (monitor?.shouldForceReconnect() ?? true)
            if needsReconnect {
                setStatus(
                    addressId: location.addressId,
                    name: location.name,
                    state: .reconnecting,
                    detail: "Refreshing…"
                )
                await connectLocation(location, token: token, initial: false)
            }
        }
        recomputeAggregateState()
    }

    private func handleMQTT(_ event: MQTTMonitor.Event, addressId: Int, locationName: String) {
        switch event {
        case .connected:
            connectedAt = Date()
            setStatus(addressId: addressId, name: locationName, state: .connected, detail: "Listening")
            recomputeAggregateState()

        case .disconnected(let reason):
            if isMonitoring {
                setStatus(
                    addressId: addressId,
                    name: locationName,
                    state: .reconnecting,
                    detail: reason.map { "Disconnected: \($0)" } ?? "Disconnected"
                )
            } else {
                setStatus(addressId: addressId, name: locationName, state: .idle, detail: "Idle")
            }
            recomputeAggregateState()

        case .message(let parsed):
            // Ignore non-rescue noise
            guard parsed.eventType == .orderCancelled || parsed.eventType == .orderClaimed else { return }

            // Stale retained messages (especially claimed floods on reconnect)
            let age = Date().timeIntervalSince(parsed.timestamp)
            if parsed.eventType == .orderCancelled, age > ZomatoConfig.staleMessageSeconds {
                return
            }
            if parsed.eventType == .orderClaimed, age > ZomatoConfig.staleClaimedSeconds {
                return
            }

            if isDuplicateEvent(parsed, addressId: addressId) {
                return
            }

            // Collapse claim onto an existing cancel row for the same order
            if parsed.eventType == .orderClaimed,
               let orderId = parsed.orderId,
               let idx = events.firstIndex(where: {
                   $0.addressId == addressId
                       && $0.orderId == orderId
                       && ($0.type == .orderCancelled || $0.type == .orderClaimed)
               }) {
                events[idx].type = .orderClaimed
                events[idx].timestamp = max(events[idx].timestamp, parsed.timestamp)
                // Move updated row to top
                let updated = events.remove(at: idx)
                events.insert(updated, at: 0)
                return
            }

            // Without order id: collapse rapid claimed spam for same area into one row
            if parsed.eventType == .orderClaimed, parsed.orderId == nil,
               let idx = events.firstIndex(where: {
                   $0.addressId == addressId
                       && $0.type == .orderClaimed
                       && $0.orderId == nil
                       && abs($0.timestamp.timeIntervalSince(parsed.timestamp)) < ZomatoConfig.semanticDedupeWindowSeconds
               }) {
                events[idx].timestamp = max(events[idx].timestamp, parsed.timestamp)
                return
            }

            let location = selectedLocations.first(where: { $0.addressId == addressId })
            let eventId = "\(addressId)-\(parsed.messageId)"
            let item = RescueEvent(
                id: eventId,
                type: parsed.eventType,
                timestamp: parsed.timestamp,
                rawPreview: String(parsed.raw.prefix(400)),
                addressId: addressId,
                locationName: locationName,
                locationAddress: location?.fullAddress ?? "",
                orderId: parsed.orderId,
                restaurantId: nil,
                restaurantName: nil,
                restaurantLat: nil,
                restaurantLng: nil,
                cartFinalCost: nil,
                catalogTotalCost: nil,
                viewersCount: nil,
                cartExpiry: nil,
                isEnriching: parsed.eventType == .orderCancelled && fetchDealDetails,
                enrichmentFailed: false
            )
            events.insert(item, at: 0)
            if events.count > 50 { events = Array(events.prefix(50)) }

            if parsed.eventType == .orderCancelled {
                Task {
                    await enrichAndAlert(eventId: eventId, addressId: addressId, locationName: locationName)
                }
            }

        case .log:
            break
        }
    }

    /// Dedupe by MQTT message id and by semantic key (order id or time bucket).
    private func isDuplicateEvent(_ parsed: MQTTPayloadParser.Parsed, addressId: Int) -> Bool {
        let msgKey = "msg:\(addressId):\(parsed.messageId)"
        if seenMessageKeys.contains(msgKey) { return true }

        let semanticKey: String
        if let orderId = parsed.orderId, !orderId.isEmpty {
            semanticKey = "ord:\(parsed.eventType.rawValue):\(addressId):\(orderId)"
        } else {
            let bucket = Int(parsed.timestamp.timeIntervalSince1970 / ZomatoConfig.semanticDedupeWindowSeconds)
            semanticKey = "t:\(parsed.eventType.rawValue):\(addressId):\(bucket)"
        }

        if seenSemanticKeys.contains(semanticKey) { return true }

        seenMessageKeys.insert(msgKey)
        seenSemanticKeys.insert(semanticKey)

        if seenMessageKeys.count > 800 {
            seenMessageKeys.removeAll(keepingCapacity: true)
            seenSemanticKeys.removeAll(keepingCapacity: true)
            // Re-seed current keys so we don't immediately re-accept floods
            seenMessageKeys.insert(msgKey)
            seenSemanticKeys.insert(semanticKey)
        }
        return false
    }

    private func enrichAndAlert(eventId: String, addressId: Int, locationName: String) async {
        var shouldNotify = true
        let now = Date()
        let elapsed = now.timeIntervalSince(lastNotifiedAt)
        if elapsed < cooldownSeconds {
            shouldNotify = false
        }

        if fetchDealDetails,
           let token = tokens?.accessToken,
           let location = selectedLocations.first(where: { $0.addressId == addressId }) {
            let cityId = cityIdByAddress[addressId] ?? 0
            do {
                let deal = try await api.fetchFoodRescueDeal(
                    location: location,
                    cityId: cityId,
                    accessToken: token
                )
                var restaurantName: String?
                var lat: Double?
                var lng: Double?
                if let meta = try? await api.fetchRestaurantMeta(resId: deal.resId, accessToken: token) {
                    restaurantName = meta.name
                    lat = meta.lat
                    lng = meta.lng
                }
                updateEvent(id: eventId) { event in
                    event.restaurantId = deal.resId
                    event.restaurantName = restaurantName
                    event.restaurantLat = lat
                    event.restaurantLng = lng
                    event.cartFinalCost = deal.cartFinalCost
                    event.catalogTotalCost = deal.catalogTotalCost
                    event.viewersCount = deal.viewersCount
                    if let exp = deal.cartExpiryTimestamp {
                        event.cartExpiry = Date(timeIntervalSince1970: exp > 10_000_000_000 ? exp / 1000 : exp)
                    }
                    if event.orderId == nil {
                        event.orderId = deal.parentOrderId
                    }
                    event.isEnriching = false
                    event.enrichmentFailed = false
                }
            } catch {
                updateEvent(id: eventId) { event in
                    event.isEnriching = false
                    event.enrichmentFailed = true
                }
            }
        } else {
            updateEvent(id: eventId) { event in
                event.isEnriching = false
            }
        }

        guard shouldNotify else { return }
        lastNotifiedAt = now
        lastAlertAt = now
        alertCountToday += 1
        if let event = events.first(where: { $0.id == eventId }) {
            NotificationManager.shared.sendFoodRescueAlert(for: event, playSound: playSound)
        }
    }

    private func updateEvent(id: String, mutate: (inout RescueEvent) -> Void) {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        var copy = events[idx]
        mutate(&copy)
        events[idx] = copy
    }

    private func setStatus(addressId: Int, name: String, state: MonitorState, detail: String) {
        let status = LocationMonitorStatus(addressId: addressId, name: name, state: state, detail: detail)
        statusByAddress[addressId] = status
        locationStatuses = selectedLocations.compactMap { statusByAddress[$0.addressId] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func recomputeAggregateState() {
        let statuses = locationStatuses
        guard isMonitoring else {
            monitorState = .idle
            lastConnectedDescription = selectedLocations.isEmpty
                ? "No addresses selected"
                : "\(selectedLocations.count) address\(selectedLocations.count == 1 ? "" : "es") ready"
            return
        }

        let live = statuses.filter { $0.state.isLive }.count
        let errors = statuses.filter {
            if case .error = $0.state { return true }
            return false
        }.count
        let connecting = statuses.filter { $0.state.isTransient }.count
        let total = max(selectedLocations.count, 1)

        if live == total {
            monitorState = .connected
            lastConnectedDescription = live == 1
                ? "Listening on \(statuses.first?.name ?? "1 area")"
                : "Listening on all \(live) areas"
        } else if live > 0 {
            monitorState = .connected
            lastConnectedDescription = "Listening on \(live)/\(total) areas"
        } else if connecting > 0 {
            monitorState = .connecting
            lastConnectedDescription = "Connecting \(connecting)/\(total)…"
        } else if errors == total {
            monitorState = .error("All areas failed")
            lastConnectedDescription = "No active channels"
        } else {
            monitorState = .reconnecting
            lastConnectedDescription = "Reconnecting…"
        }

        if let connectedAt, live > 0 {
            let mins = Int(Date().timeIntervalSince(connectedAt) / 60)
            let age: String
            if mins < 1 { age = "just now" }
            else if mins == 1 { age = "1 min ago" }
            else { age = "\(mins) min ago" }
            lastConnectedDescription += " · \(age)"
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

    var selectionSummary: String {
        let n = selectedLocations.count
        if n == 0 { return "No addresses" }
        if n == 1 { return selectedLocations[0].name }
        return "\(n) addresses"
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
