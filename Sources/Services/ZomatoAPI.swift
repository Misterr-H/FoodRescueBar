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

    // MARK: - Food Rescue deal details (create-cart)

    /// Enriches an active rescue near `location`. Pitch-once on Zomato’s side.
    func fetchFoodRescueDeal(
        location: UserLocation,
        cityId: Int,
        accessToken: String
    ) async throws -> FoodRescueDealDetails {
        var locationBody: [String: Any] = [
            "entity_type": location.entityType,
            "place_type": location.entityId != nil ? "DSZ" : "PLACE",
            "address_id": String(location.addressId),
            "cell_id": location.cellId,
            "current_city_id": String(cityId),
            "city_id": String(cityId)
        ]
        if let lng = location.lng { locationBody["lng"] = lng }
        if let lat = location.lat { locationBody["lat"] = lat }
        if let entityId = location.entityId { locationBody["entity_id"] = String(entityId) }
        if let placeId = location.placeId { locationBody["place_id"] = placeId }

        let body: [String: Any] = [
            "identifier": [] as [Any],
            "location": locationBody
        ]

        var extra: [String: String] = [
            "X-City-Id": String(cityId),
            "X-O2-City-Id": String(cityId)
        ]
        if let lat = location.lat { extra["X-User-Defined-Lat"] = String(lat) }
        if let lng = location.lng { extra["X-User-Defined-Long"] = String(lng) }

        let data = try await post(
            path: "/gw/gamification/food-rescue/create-cart",
            token: accessToken,
            json: body,
            extraHeaders: extra
        )
        return try Self.parseFoodRescueDeal(data)
    }

    func fetchRestaurantMeta(resId: String, accessToken: String) async throws -> RestaurantMeta {
        let data = try await post(
            path: "/gw/menu/res_info/\(resId)",
            token: accessToken,
            json: ["should_fetch_res_info_from_agg": true]
        )
        return try Self.parseRestaurantMeta(resId: resId, data: data)
    }

    // MARK: - HTTP

    private func get(path: String, token: String) async throws -> Data {
        var req = URLRequest(url: URL(string: ZomatoConfig.apiBase + path)!)
        req.httpMethod = "GET"
        apply(token: token, to: &req)
        return try await perform(req)
    }

    private func post(
        path: String,
        token: String,
        json: [String: Any],
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        var req = URLRequest(url: URL(string: ZomatoConfig.apiBase + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        apply(token: token, to: &req)
        for (k, v) in extraHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        return try await perform(req)
    }

    private func apply(token: String, to request: inout URLRequest) {
        for (k, v) in ZomatoHeaders.common(accessToken: token) {
            request.setValue(v, forHTTPHeaderField: k)
        }
    }

    // MARK: - Deal / restaurant parsers

    private static func parseFoodRescueDeal(_ data: Data) throws -> FoodRescueDealDetails {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decode("Invalid create-cart JSON")
        }
        // Walk nested SDUI for deeplink post_body + tracking
        guard let response = root["response"] as? [String: Any] else {
            throw APIError.decode("No active Food Rescue cart in response")
        }

        // Prefer deeplink post_body (stable structure from public RE)
        if let deeplink = deepFind(response, key: "deeplink") as? [String: Any],
           let postBodyStr = deeplink["post_body"] as? String,
           let postData = postBodyStr.data(using: .utf8),
           let post = try? JSONSerialization.jsonObject(with: postData) as? [String: Any] {
            let cartId = post["cart_id"] as? String ?? ""
            let context = post["context"] as? [String: Any] ?? [:]
            let mod = context["cart_modification"] as? [String: Any] ?? [:]
            let analytics = context["cart_analytics_data"] as? [String: Any] ?? [:]
            let parentOrder = mod["ParentOrderID"] as? String
            let viewers = Int(analytics["number_of_people_watching"] as? String ?? "")
                ?? analytics["number_of_people_watching"] as? Int
            let expiryRaw = analytics["cart_expiry_timestamp"] as? String
                ?? (analytics["cart_expiry_timestamp"] as? NSNumber).map(String.init)
            let expiry = expiryRaw.flatMap(TimeInterval.init)

            var resId = ""
            if let url = deeplink["url"] as? String,
               let comps = URLComponents(string: url),
               let rid = comps.queryItems?.first(where: { $0.name == "res_id" })?.value {
                resId = rid
            }

            var cartFinal = 0.0
            var catalog: Double?
            if let tracking = deepFind(response, key: "tracking_data") as? [[String: Any]] {
                for t in tracking {
                    guard let payloadStr = t["payload"] as? String,
                          let pdata = payloadStr.data(using: .utf8),
                          let pjson = try? JSONSerialization.jsonObject(with: pdata) as? [String: Any],
                          let value = pjson["value"] as? [String: Any] else { continue }
                    if let c = value["cart_final_cost"] as? Double { cartFinal = c }
                    else if let c = value["cart_final_cost"] as? Int { cartFinal = Double(c) }
                    else if let c = value["cart_final_cost"] as? String { cartFinal = Double(c) ?? cartFinal }
                    if let c = value["catalog_total_cost"] as? Double { catalog = c }
                    else if let c = value["catalog_total_cost"] as? Int { catalog = Double(c) }
                    else if let c = value["catalog_total_cost"] as? String { catalog = Double(c) }
                    break
                }
            }

            if resId.isEmpty { throw APIError.decode("Missing res_id in deal payload") }
            return FoodRescueDealDetails(
                resId: resId,
                cartFinalCost: cartFinal,
                viewersCount: viewers ?? 0,
                cartId: cartId,
                parentOrderId: parentOrder,
                cartExpiryTimestamp: expiry,
                catalogTotalCost: catalog
            )
        }

        throw APIError.decode("Could not parse Food Rescue deal details")
    }

    private static func parseRestaurantMeta(resId: String, data: Data) throws -> RestaurantMeta {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [Any] else {
            throw APIError.decode("Invalid restaurant meta")
        }
        var name = "Restaurant"
        var lat: Double?
        var lng: Double?

        for result in results {
            guard let dict = result as? [String: Any],
                  let snippet = dict["v4_image_text_snippet_type_3"] as? [String: Any],
                  let items = snippet["items"] as? [[String: Any]] else { continue }
            if let title = items.first?["title"] as? [String: Any],
               let text = title["text"] as? String, !text.isEmpty {
                name = text
            }
            for item in items {
                guard let containers = item["icon_text_containers"] as? [[String: Any]] else { continue }
                for container in containers {
                    guard let click = container["click_action"] as? [String: Any],
                          click["type"] as? String == "open_map",
                          let openMap = click["open_map"] as? [String: Any] else { continue }
                    lat = openMap["latitude"] as? Double ?? (openMap["latitude"] as? NSNumber)?.doubleValue
                    lng = openMap["longitude"] as? Double ?? (openMap["longitude"] as? NSNumber)?.doubleValue
                }
            }
        }
        return RestaurantMeta(resId: resId, name: name, lat: lat, lng: lng)
    }

    /// Recursive key search in nested JSON.
    private static func deepFind(_ any: Any, key: String) -> Any? {
        if let dict = any as? [String: Any] {
            if let v = dict[key] { return v }
            for v in dict.values {
                if let found = deepFind(v, key: key) { return found }
            }
        } else if let arr = any as? [Any] {
            for v in arr {
                if let found = deepFind(v, key: key) { return found }
            }
        }
        return nil
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
