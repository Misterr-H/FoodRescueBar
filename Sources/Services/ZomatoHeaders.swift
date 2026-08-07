import Foundation

enum ZomatoConfig {
    static let apiBase = "https://api.zomato.com"
    static let accountsBase = "https://accounts.zomato.com"
    static let clientId = "5276d7f1-910b-4243-92ea-d27e758ad02b"
    static let apiKey = "7749b19667964b87a3efc739e254ada2"
    static let appVersionCode = "1710019761"
    static let appVersion = "931"
    static let packageName = "com.application.zomato"
    static let mqttBroker = "ssl://hedwig.zomato.com:443"
    static let redirectURI = "https://accounts.zomato.com/zoauth/callback"

    /// Stale MQTT messages older than this are ignored (seconds).
    static let staleMessageSeconds: TimeInterval = 120
    /// Force MQTT reconnect interval.
    static let forceReconnectSeconds: TimeInterval = 20 * 60
}

enum ZomatoHeaders {
    private static let sessionUUID = UUID().uuidString
    private static let appSessionId = UUID().uuidString
    private static let accessUUID = UUID().uuidString
    private static let androidId = randomHex(16)
    private static let firebaseId = randomHex(32)

    static func common(accessToken: String? = nil) -> [String: String] {
        var h: [String: String] = [
            "Accept": "application/json, text/plain, */*",
            "Connection": "Keep-Alive",
            "X-Zomato-API-Key": ZomatoConfig.apiKey,
            "X-Zomato-App-Version": ZomatoConfig.appVersion,
            "X-Zomato-App-Version-Code": ZomatoConfig.appVersionCode,
            "X-Zomato-Client-Id": ZomatoConfig.clientId,
            "X-Zomato-UUID": sessionUUID,
            "X-Client-Id": "zomato_android_v2",
            "User-Agent": "&source=android_market&version=14&device_manufacturer=Apple&device_brand=apple&device_model=Mac&api_version=\(ZomatoConfig.appVersion)&app_version=v19.7.6",
            "X-Android-Id": androidId,
            "X-Device-Height": "2208",
            "X-Device-Width": "1080",
            "X-Device-Pixel-Ratio": "2.0",
            "X-Device-Language": "en",
            "X-APP-APPEARANCE": "LIGHT",
            "X-APP-THEME": "default",
            "X-SYSTEM-APPEARANCE": "UNSPECIFIED",
            "X-App-Language": "&lang=en&android_language=en&android_country=",
            "X-App-Session-Id": appSessionId,
            "X-Access-UUID": accessUUID,
            "X-Request-Id": UUID().uuidString,
            "X-City-Id": "-1",
            "X-O2-City-Id": "-1",
            "X-Present-Lat": "0.0",
            "X-Present-Long": "0.0",
            "X-User-Defined-Lat": "0.0",
            "X-User-Defined-Long": "0.0",
            "X-Network-Type": "wifi",
            "X-VPN-Active": "0",
            "X-BLINKIT-INSTALLED": "false",
            "X-DISTRICT-INSTALLED": "false",
            "USER-BUCKET": "0",
            "USER-HIGH-PRIORITY": "0"
        ]
        if let token = accessToken {
            h["X-Zomato-Access-Token"] = token
        }
        return h
    }

    private static func randomHex(_ length: Int) -> String {
        let chars = Array("0123456789abcdef")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}
