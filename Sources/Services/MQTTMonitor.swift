import Foundation
import Security
import CocoaMQTT

/// Thread-safe MQTT listener for Food Rescue cell topics.
final class MQTTMonitor: NSObject, CocoaMQTTDelegate {
    enum Event {
        case connected
        case disconnected(String?)
        case message(id: String, eventType: FoodRescueEventType, timestamp: Date, raw: String)
        case log(String)
    }

    var onEvent: ((Event) -> Void)?

    private var mqtt: CocoaMQTT?
    private var channel: FoodRescueChannel?
    private let processedLock = NSLock()
    private var processedIDs = Set<String>()
    private var lastConnectedAt: Date?

    func connect(channel: FoodRescueChannel) {
        disconnect()
        self.channel = channel

        let clientID = "frbar\(Int(Date().timeIntervalSince1970))\(Int.random(in: 100...999))"
        let mqtt = CocoaMQTT(clientID: clientID, host: "hedwig.zomato.com", port: 443)
        mqtt.username = channel.client.username
        mqtt.password = channel.client.password
        mqtt.keepAlive = 30
        mqtt.cleanSession = true
        mqtt.autoReconnect = false
        mqtt.enableSSL = true
        mqtt.allowUntrustCACertificate = false
        mqtt.delegate = self
        mqtt.logLevel = .warning
        self.mqtt = mqtt

        onEvent?(.log("Connecting MQTT as \(channel.client.username)…"))
        _ = mqtt.connect()
    }

    func disconnect() {
        mqtt?.delegate = nil
        if mqtt?.connState == .connected {
            mqtt?.disconnect()
        }
        mqtt = nil
        lastConnectedAt = nil
    }

    var isConnected: Bool {
        mqtt?.connState == .connected
    }

    var secondsSinceConnect: TimeInterval? {
        guard let lastConnectedAt else { return nil }
        return Date().timeIntervalSince(lastConnectedAt)
    }

    func shouldForceReconnect(interval: TimeInterval = ZomatoConfig.forceReconnectSeconds) -> Bool {
        guard let lastConnectedAt else { return false }
        return Date().timeIntervalSince(lastConnectedAt) >= interval
    }

    // MARK: - CocoaMQTTDelegate

    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if ack == .accept {
            lastConnectedAt = Date()
            onEvent?(.connected)
            if let channel {
                let qos: CocoaMQTTQoS
                switch channel.qos {
                case 0: qos = .qos0
                case 2: qos = .qos2
                default: qos = .qos1
                }
                mqtt.subscribe(channel.channelName, qos: qos)
                onEvent?(.log("Subscribed to \(channel.channelName)"))
            }
        } else {
            onEvent?(.disconnected("CONNACK \(ack)"))
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let raw = message.string ?? String(data: Data(message.payload), encoding: .utf8) ?? ""
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            onEvent?(.log("Non-JSON MQTT payload"))
            return
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

        processedLock.lock()
        let seen = processedIDs.contains(msgId)
        if !seen {
            processedIDs.insert(msgId)
            if processedIDs.count > 500 {
                processedIDs.removeAll(keepingCapacity: true)
            }
        }
        processedLock.unlock()
        if seen {
            onEvent?(.log("Deduped \(msgId.prefix(8))…"))
            return
        }

        if eventType == .orderCancelled {
            let age = Date().timeIntervalSince(ts)
            if age > ZomatoConfig.staleMessageSeconds {
                onEvent?(.log("Ignored stale cancel (\(Int(age))s old)"))
                return
            }
        }

        onEvent?(.message(id: msgId, eventType: eventType, timestamp: ts, raw: String(raw.prefix(280))))
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        if !failed.isEmpty {
            onEvent?(.log("Subscribe failed: \(failed.joined(separator: ", "))"))
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}

    func mqttDidPing(_ mqtt: CocoaMQTT) {}

    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        onEvent?(.disconnected(err?.localizedDescription))
    }

    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        onEvent?(.log("MQTT state: \(state)"))
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        var error: CFError?
        let ok = SecTrustEvaluateWithError(trust, &error)
        completionHandler(ok)
    }
}
