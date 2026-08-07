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
    let type: FoodRescueEventType
    let timestamp: Date
    let rawPreview: String
    let addressId: Int
    let locationName: String
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
