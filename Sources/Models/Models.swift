import Foundation

// MARK: - Auth

struct AuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
}

// MARK: - User

struct ZomatoUser: Codable, Equatable {
    let id: Int
    let name: String
    let mobile: String
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id, name, mobile, email
    }
}

// MARK: - Location

struct UserLocation: Codable, Equatable, Identifiable, Hashable {
    var id: Int { addressId }

    var name: String
    var fullAddress: String
    var addressId: Int
    var cellId: String
    var entityType: String
    var entityId: Int?
    var placeType: String
    var placeId: String?
    var lat: Double?
    var lng: Double?

    enum CodingKeys: String, CodingKey {
        case name
        case fullAddress = "full_address"
        case addressId = "address_id"
        case cellId = "cell_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case placeType = "place_type"
        case placeId = "place_id"
        case lat, lng
    }

    init(
        name: String,
        fullAddress: String,
        addressId: Int,
        cellId: String,
        entityType: String = "subzone",
        entityId: Int? = nil,
        placeType: String = "DSZ",
        placeId: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil
    ) {
        self.name = name
        self.fullAddress = fullAddress
        self.addressId = addressId
        self.cellId = cellId
        self.entityType = entityType
        self.entityId = entityId
        self.placeType = placeType
        self.placeId = placeId
        self.lat = lat
        self.lng = lng
    }
}

// MARK: - Food Rescue MQTT config

struct FoodRescueClientCreds: Codable, Equatable {
    var username: String
    var password: String
    var keepalive: Int
}

struct FoodRescueChannel: Codable, Equatable {
    var channelName: String
    var qos: Int
    var validUntil: Int64
    var client: FoodRescueClientCreds
}

struct TabbedHomeEssentials: Equatable {
    var cityId: Int
    var foodRescue: FoodRescueChannel?
}

// MARK: - Per-address monitor status (UI)

struct LocationMonitorStatus: Identifiable, Equatable {
    var id: Int { addressId }
    let addressId: Int
    let name: String
    var state: MonitorState
    var detail: String
}

// MARK: - Events

enum FoodRescueEventType: String, Codable {
    case orderCancelled = "order_cancelled"
    case orderClaimed = "order_claimed"
    case unknown

    init(raw: String?) {
        switch raw {
        case "order_cancelled": self = .orderCancelled
        case "order_claimed": self = .orderClaimed
        default: self = .unknown
        }
    }
}

struct RescueEvent: Identifiable, Equatable {
    let id: String
    var type: FoodRescueEventType
    var timestamp: Date
    let rawPreview: String
    /// Your watched saved-address id (which subscription fired).
    let addressId: Int
    /// e.g. Home / Work
    let locationName: String
    /// Full saved-address line for that subscription
    var locationAddress: String
    /// From MQTT success_actions when present
    var orderId: String?
    /// Enriched via create-cart / res_info (optional)
    var restaurantId: String?
    var restaurantName: String?
    var restaurantLat: Double?
    var restaurantLng: Double?
    var cartFinalCost: Double?
    var catalogTotalCost: Double?
    var viewersCount: Int?
    var cartExpiry: Date?
    var isEnriching: Bool
    var enrichmentFailed: Bool
    /// create-cart confirmed an active Food Rescue deal for this cancel.
    var isVerifiedDeal: Bool
    /// Retained/stale MQTT noise — not a live claim opportunity.
    var isLikelyNoise: Bool

    var isClaimable: Bool { type == .orderCancelled && isVerifiedDeal && !isLikelyNoise }

    var titleText: String {
        if type == .orderCancelled {
            if isLikelyNoise {
                return "Past cancel signal (not claimable)"
            }
            if isEnriching {
                return "Loading restaurant details…"
            }
            if let restaurantName {
                return "\(restaurantName) — open Zomato now"
            }
            // MQTT-first signal: do not imply we already opened the pitch
            return "Food Rescue nearby — open Zomato now"
        }
        return restaurantName.map { "\($0) — claimed" } ?? "Order claimed"
    }

    var priceText: String? {
        guard let cartFinalCost, cartFinalCost > 0 else { return nil }
        if let catalog = catalogTotalCost, catalog > cartFinalCost {
            return String(format: "₹%.0f  (was ₹%.0f)", cartFinalCost, catalog)
        }
        return String(format: "₹%.0f", cartFinalCost)
    }

    var subscribedAreaText: String {
        if locationAddress.isEmpty { return locationName }
        return "\(locationName) · \(locationAddress)"
    }
}

struct FoodRescueDealDetails: Equatable {
    var resId: String
    var cartFinalCost: Double
    var viewersCount: Int
    var cartId: String
    var parentOrderId: String?
    var cartExpiryTimestamp: TimeInterval?
    var catalogTotalCost: Double?
}

struct RestaurantMeta: Equatable {
    var resId: String
    var name: String
    var lat: Double?
    var lng: Double?
}

// MARK: - App connection state

enum MonitorState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting…"
        case .connected: return "Listening"
        case .reconnecting: return "Reconnecting…"
        case .error(let m): return m
        }
    }

    var isLive: Bool {
        if case .connected = self { return true }
        return false
    }

    var isTransient: Bool {
        switch self {
        case .connecting, .reconnecting: return true
        default: return false
        }
    }
}

enum AppScreen: Equatable {
    case login
    case location
    case home
    case settings
}

enum OTPChannel: String, CaseIterable, Identifiable {
    case sms
    case whatsapp
    case call

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sms: return "SMS"
        case .whatsapp: return "WhatsApp"
        case .call: return "Call"
        }
    }

    var systemImage: String {
        switch self {
        case .sms: return "message.fill"
        case .whatsapp: return "phone.bubble.fill"
        case .call: return "phone.fill"
        }
    }
}

enum AppLimits {
    /// Soft cap so we don't open too many MQTT sockets.
    static let maxMonitoredAddresses = 5
}
