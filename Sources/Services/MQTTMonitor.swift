import Foundation
import Security
import CocoaMQTT

/// One MQTT connection for a single Food Rescue cell / address.
final class MQTTMonitor: NSObject, CocoaMQTTDelegate {
    enum Event {
        case connected
        case disconnected(String?)
        case message(MQTTPayloadParser.Parsed)
        case log(String)
    }

    let addressId: Int
    let locationName: String

    var onEvent: ((Event) -> Void)?

    private var mqtt: CocoaMQTT?
    private var channel: FoodRescueChannel?
    private let processedLock = NSLock()
    private var processedIDs = Set<String>()
    private var lastConnectedAt: Date?

    init(addressId: Int, locationName: String) {
        self.addressId = addressId
        self.locationName = locationName
        super.init()
    }

    func connect(channel: FoodRescueChannel) {
        disconnect()
        self.channel = channel

        let clientID = "frbar\(addressId)\(Int(Date().timeIntervalSince1970) % 100_000)\(Int.random(in: 10...99))"
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

        onEvent?(.log("[\(locationName)] Connecting MQTT…"))
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
                onEvent?(.log("[\(locationName)] Subscribed to \(channel.channelName)"))
            }
        } else {
            onEvent?(.disconnected("CONNACK \(ack)"))
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let raw = message.string ?? String(data: Data(message.payload), encoding: .utf8) ?? ""
        guard let parsed = MQTTPayloadParser.parse(raw) else {
            onEvent?(.log("[\(locationName)] Non-JSON MQTT payload"))
            return
        }

        processedLock.lock()
        let seen = processedIDs.contains(parsed.messageId)
        if !seen {
            processedIDs.insert(parsed.messageId)
            if processedIDs.count > 500 {
                processedIDs.removeAll(keepingCapacity: true)
            }
        }
        processedLock.unlock()
        if seen {
            onEvent?(.log("[\(locationName)] Deduped \(parsed.messageId.prefix(8))…"))
            return
        }

        if parsed.eventType == .orderCancelled {
            let age = Date().timeIntervalSince(parsed.timestamp)
            if age > ZomatoConfig.staleMessageSeconds {
                onEvent?(.log("[\(locationName)] Ignored stale cancel (\(Int(age))s old)"))
                return
            }
        }

        onEvent?(.message(parsed))
    }

    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        if !failed.isEmpty {
            onEvent?(.log("[\(locationName)] Subscribe failed: \(failed.joined(separator: ", "))"))
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}

    func mqttDidPing(_ mqtt: CocoaMQTT) {}

    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        onEvent?(.disconnected(err?.localizedDescription))
    }

    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        onEvent?(.log("[\(locationName)] MQTT state: \(state)"))
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        var error: CFError?
        let ok = SecTrustEvaluateWithError(trust, &error)
        completionHandler(ok)
    }
}
