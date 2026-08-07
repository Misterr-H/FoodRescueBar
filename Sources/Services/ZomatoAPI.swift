import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case http(Int, String)
    case decode(String)
    case missingFoodRescue
    case noLocations

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired. Please log in again."
        case .http(let c, let m): return "HTTP \(c): \(m)"
        case .decode(let m): return m
        case .missingFoodRescue: return "Food Rescue channel not available for this address yet."
        case .noLocations: return "No saved addresses found on this Zomato account."
        }
    }
}

actor ZomatoAPI {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.httpAdditionalHeaders = ["Accept-Encoding": "gzip, deflate, br"]
        session = URLSession(configuration: config)
    }

    // MARK: - User info

    func fetchUser(accessToken: String) async throws -> ZomatoUser {
        let data = try await get(path: "/gw/user/info", token: accessToken)
        // Response may be flat user object
        if let user = try? JSONDecoder().decode(ZomatoUser.self, from: data) {
            return user
        }
        // Or nested
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let src = (json["user"] as? [String: Any]) ?? json
            guard let id = src["id"] as? Int ?? (src["id"] as? String).flatMap(Int.init),
                  let name = src["name"] as? String,
                  let mobile = src["mobile"] as? String ?? src["phone"] as? String else {
                throw APIError.decode("Could not parse user info")
            }
            return ZomatoUser(id: id, name: name, mobile: mobile, email: src["email"] as? String)
        }
        throw APIError.decode("Could not parse user info")
    }

    // MARK: - Locations

    func fetchLocations(accessToken: String) async throws -> [UserLocation] {
        let body: [String: Any] = [
            "android_country": "",
            "location_permissions": [
                "device_location_on": false,
                "location_permission_available": false,
                "precise_location_permission_available": false
            ],
            "current_app_address_id": NSNull(),
            "incremental_call": false,
            "source": "delivery_home",
            "lang": "en",
            "android_language": "en",
            "postback_params": "{}",
            "recent_locations": [],
            "city_id": "1"
        ]
        let data = try await post(path: "/gw/user/location/selection", token: accessToken, json: body)
        let root = try JSONSerialization.jsonObject(with: data)
        let snippets = Self.findLocationSnippets(root)
        let locations = snippets.compactMap { Self.parseLocationSnippet($0) }
        if locations.isEmpty { throw APIError.noLocations }
        return locations
    }

    // MARK: - Tabbed home / MQTT channel

    func fetchTabbedHome(cellId: String, addressId: Int, accessToken: String) async throws -> TabbedHomeEssentials {
        let path = "/gw/tabbed-home?cell_id=\(cellId)&address_id=\(addressId)"
        let data = try await get(path: path, token: accessToken)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decode("Invalid tabbed-home JSON")
        }

        var cityId = 0
        if let location = root["location"] as? [String: Any],
           let city = location["city"] as? [String: Any] {
            if let id = city["id"] as? Int {
                cityId = id
            } else if let id = city["id"] as? String, let n = Int(id) {
                cityId = n
            }
        }

        var channel: FoodRescueChannel?
        if let channels = root["subscription_channels"] as? [[String: Any]] {
            for ch in channels {
                let type = ch["type"] as? String
                guard type == "food_rescue" else { continue }
                let names = ch["name"] as? [String]
                let name = names?.first ?? ""
                let qos = ch["qos"] as? Int ?? 1
                let time: Int64
                if let t = ch["time"] as? Int64 { time = t }
                else if let t = ch["time"] as? Int { time = Int64(t) }
                else if let t = ch["time"] as? Double { time = Int64(t) }
                else { time = 0 }
                let client = ch["client"] as? [String: Any] ?? [:]
                let username = client["username"] as? String ?? ""
                let password = client["password"] as? String ?? ""
                let keepalive = client["keepalive"] as? Int ?? 900
                guard !name.isEmpty, !username.isEmpty, !password.isEmpty else { continue }
                channel = FoodRescueChannel(
                    channelName: name,
                    qos: qos,
                    validUntil: time,
                    client: FoodRescueClientCreds(
                        username: username,
                        password: password,
                        keepalive: keepalive
                    )
                )
                break
            }
        }

        return TabbedHomeEssentials(cityId: cityId, foodRescue: channel)
    }

    // MARK: - HTTP

    private func get(path: String, token: String) async throws -> Data {
        var req = URLRequest(url: URL(string: ZomatoConfig.apiBase + path)!)
        req.httpMethod = "GET"
        apply(token: token, to: &req)
        return try await perform(req)
    }

    private func post(path: String, token: String, json: [String: Any]) async throws -> Data {
        var req = URLRequest(url: URL(string: ZomatoConfig.apiBase + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        apply(token: token, to: &req)
        return try await perform(req)
    }

    private func apply(token: String, to request: inout URLRequest) {
        for (k, v) in ZomatoHeaders.common(accessToken: token) {
            request.setValue(v, forHTTPHeaderField: k)
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.http(-1, "No response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw APIError.http(http.statusCode, String(snippet))
        }
        return data
    }

    // MARK: - Location SDUI parse

    private static func findLocationSnippets(_ element: Any) -> [[String: Any]] {
        var matches: [[String: Any]] = []
        if let dict = element as? [String: Any] {
            if let layout = dict["layout_config"] as? [String: Any],
               let snippetType = layout["snippet_type"] as? String,
               snippetType == "location_address_snippet",
               let snippet = dict["location_address_snippet"] as? [String: Any] {
                matches.append(snippet)
            }
            for value in dict.values {
                matches.append(contentsOf: findLocationSnippets(value))
            }
        } else if let arr = element as? [Any] {
            for item in arr {
                matches.append(contentsOf: findLocationSnippets(item))
            }
        }
        return matches
    }

    private static func parseLocationSnippet(_ snippet: [String: Any]) -> UserLocation? {
        guard let click = snippet["click_action"] as? [String: Any],
              let update = click["update_location_result"] as? [String: Any],
              let address = update["address"] as? [String: Any] else {
            return nil
        }

        let addressId: Int
        if let id = address["id"] as? Int {
            addressId = id
        } else if let id = address["id"] as? String, let n = Int(id) {
            addressId = n
        } else {
            return nil
        }

        let place = address["place"] as? [String: Any]
        let cellId = place?["cell_id"] as? String ?? ""
        guard !cellId.isEmpty else { return nil }

        let title = (snippet["title"] as? [String: Any])?["text"] as? String
            ?? address["alias"] as? String
            ?? "Saved address"
        let subtitle = (snippet["subtitle"] as? [String: Any])?["text"] as? String
            ?? address["display_subtitle"] as? String
            ?? ""

        let entityId: Int?
        if let e = address["subzone_id"] as? Int { entityId = e }
        else if let e = address["subzone_id"] as? String { entityId = Int(e) }
        else { entityId = nil }

        let placeId = (address["delivery_subzone_id"] as? String)
            ?? (address["delivery_subzone_id"] as? Int).map(String.init)
            ?? place?["place_id"] as? String

        let lat = place?["latitude"] as? Double
            ?? (place?["latitude"] as? NSNumber)?.doubleValue
        let lng = place?["longitude"] as? Double
            ?? (place?["longitude"] as? NSNumber)?.doubleValue

        return UserLocation(
            name: title,
            fullAddress: subtitle,
            addressId: addressId,
            cellId: cellId,
            entityType: "subzone",
            entityId: entityId,
            placeType: "DSZ",
            placeId: placeId,
            lat: lat,
            lng: lng
        )
    }
}
