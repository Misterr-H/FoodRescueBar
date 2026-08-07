import Foundation

enum MQTTPayloadParser {
    struct Parsed {
        var messageId: String
        var eventType: FoodRescueEventType
        var timestamp: Date
        var orderId: String?
        var raw: String
    }

    static func parse(_ raw: String) -> Parsed? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let msgId = (json["id"] as? String) ?? UUID().uuidString
        let dataObj = json["data"] as? [String: Any]
        let eventType = FoodRescueEventType(raw: dataObj?["event_type"] as? String)

        var ts = Date()
        if let t = json["timestamp"] as? Double {
            ts = Date(timeIntervalSince1970: t > 10_000_000_000 ? t / 1000 : t)
        } else if let t = json["timestamp"] as? Int {
            let d = Double(t)
            ts = Date(timeIntervalSince1970: d > 10_000_000_000 ? d / 1000 : d)
        }

        let orderId = extractOrderId(from: dataObj) ?? extractOrderId(from: json)

        return Parsed(
            messageId: msgId,
            eventType: eventType,
            timestamp: ts,
            orderId: orderId,
            raw: raw
        )
    }

    /// Pull order id from food_rescue_order_cancelled / claimed action blocks.
    private static func extractOrderId(from root: [String: Any]?) -> String? {
        guard let root else { return nil }

        if let actions = root["success_actions"] as? [[String: Any]] {
            for action in actions {
                if let cancelled = action["food_rescue_order_cancelled"] as? [String: Any] {
                    if let id = stringValue(cancelled["orderId"] ?? cancelled["order_id"] ?? cancelled["identifier"]) {
                        return id
                    }
                }
                if let claimed = action["food_rescue_order_claimed"] as? [String: Any] {
                    if let id = stringValue(claimed["identifier"] ?? claimed["orderId"] ?? claimed["order_id"]) {
                        return id
                    }
                }
                if let type = action["type"] as? String {
                    if type == "food_rescue_order_cancelled" || type == "food_rescue_order_claimed" {
                        if let id = stringValue(action["orderId"] ?? action["order_id"] ?? action["identifier"]) {
                            return id
                        }
                    }
                }
            }
        }

        // Fallback deep search
        return deepOrderId(root)
    }

    private static func deepOrderId(_ any: Any) -> String? {
        if let dict = any as? [String: Any] {
            for key in ["orderId", "order_id", "ParentOrderID", "identifier"] {
                if let v = stringValue(dict[key]), v.count >= 4, key != "identifier" || dict["food_rescue_order_claimed"] != nil {
                    // prefer explicit order keys
                    if key != "identifier" { return v }
                }
            }
            if let cancelled = dict["food_rescue_order_cancelled"] as? [String: Any],
               let id = stringValue(cancelled["orderId"] ?? cancelled["order_id"] ?? cancelled["identifier"]) {
                return id
            }
            if let claimed = dict["food_rescue_order_claimed"] as? [String: Any],
               let id = stringValue(claimed["identifier"] ?? claimed["orderId"]) {
                return id
            }
            for v in dict.values {
                if let found = deepOrderId(v) { return found }
            }
        } else if let arr = any as? [Any] {
            for v in arr {
                if let found = deepOrderId(v) { return found }
            }
        }
        return nil
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
        if let n = any as? Int { return String(n) }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }
}
