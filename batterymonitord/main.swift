import Foundation
import IOKit.ps

class WebSocketDaemonClient {
    private var url: String
    private var ws: URLSessionWebSocketTask?
    private var onRequestData: () -> Void

    init(_ url: String, _ handler: @escaping () -> Void) {
        onRequestData = handler
        self.url = url
        connect(withURL: self.url)
    }

    func connect(withURL url: String) {
        guard let url = URL(string: url) else {
            print("Invalid url client not initialized")
            return
        }

        ws = URLSession(configuration: .default).webSocketTask(with: url)

        if let ws = ws {
            ws.resume()
            register()
        }
    }

    func register() {
        guard let ws = ws else {
            print("couldn't register, Websocket task not initialized")
            return
        }

        let data: [String: Any] = [
            "type": "daemon",
            "name": "BATTERY_DAEMON",
        ]

        guard let json = try? JSONSerialization.data(withJSONObject: data) else {
            print("failed to create registration payload")
            return
        }

        guard let payload = String(data: json, encoding: .utf8) else {
            print("failed to create registration payload")
            return
        }

        ws.send(URLSessionWebSocketTask.Message.string(payload)) { [self] error in
            if let error = error {
                print("error sending registration message \(error)")
                return
            }
            onRequestData()
            receive()
        }
    }

    func send(data: [String: Any]) {
        guard let ws = ws else {
            print("couldn't send, Websocket task not initialized")
            return
        }

        guard let json = try? JSONSerialization.data(withJSONObject: data) else {
            print("couldn't serialize message")
            return
        }

        guard let payload = String(data: json, encoding: .utf8) else {
            print("couldn't serialize message")
            return
        }

        ws.send(URLSessionWebSocketTask.Message.string(payload)) { error in
            if let error = error {
                print("error sending message \(error)")
            }
        }
    }

    func receive() {
        guard let ws = ws else {
            print("couldn't receive, Websocket task not initialized")
            return
        }

        ws.receive { [self] result in
            switch result {
            case .success:
                onRequestData()
                receive()
                break
            case .failure:
                connect(withURL: url)
                break
            }
        }
    }

}

class BatteryMonitorWebSocketManager {
    private var ws: WebSocketDaemonClient?

    init() {
        ws = WebSocketDaemonClient("ws://localhost:3000/listen") { [self] in
            sendBatteryInfo()
        }
    }

    func sendBatteryInfo() {
        guard let ws = ws else {
            return
        }

        guard let info = getBatteryInfo() else {
            return
        }

        ws.send(data: ["type": "UPDATE_BATTERY", "data": info])
    }

    func getBatteryInfo() -> [String: Any]? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            print("couldn't get power sources info")
            return nil
        }

        guard let sources: NSArray = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() else {
            print("couldn't copy power sources")
            return nil
        }

        for source in sources {
            guard
                let info = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?
                    .takeUnretainedValue() as? [String: Any]
            else {
                continue
            }

            guard
                let current = info[kIOPSCurrentCapacityKey] as? Int,
                let max = info[kIOPSMaxCapacityKey] as? Int,
                let state = info[kIOPSPowerSourceStateKey] as? String,
                let isChargingStatus = info[kIOPSIsChargingKey] as? Bool
            else {
                continue
            }

            let percent = Int(Double(current) / Double(max) * 100.0)

            var powerSource = "Unknown"
            if state == kIOPSACPowerValue {
                powerSource = "AC"
            } else if state == kIOPSBatteryPowerValue {
                powerSource = "Battery"
            } else if state == kIOPSOffLineValue {
                powerSource = "Offline"
            }

            return [
                "percentage": percent,
                "source": powerSource,
                "charging": isChargingStatus,
            ]

        }
        return nil
    }
}

let ws = BatteryMonitorWebSocketManager()

if let runLoopSource = IOPSNotificationCreateRunLoopSource({ _ in ws.sendBatteryInfo() }, nil)?
    .takeUnretainedValue()
{
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
    CFRunLoopRun()
}
