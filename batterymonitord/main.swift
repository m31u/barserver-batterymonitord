import Foundation
import IOKit.ps

func postJSON(_ json: [String: Any]) {
    guard let url = URL(string: "http://localhost:3000/update-battery") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: json)

    let task = URLSession.shared.dataTask(with: request) { _, _, error in
        if let error = error {
            print("POST error: \(error)")
        }
    }
    task.resume()
}

func getBatteryInfo() -> [String: Any]? {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
        let sources: NSArray = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()
    else {
        return nil
    }

    for ps in sources {
        guard
            let info = IOPSGetPowerSourceDescription(snapshot, ps as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any]
        else {
            continue
        }

        if let current = info[kIOPSCurrentCapacityKey] as? Int,
            let max = info[kIOPSMaxCapacityKey] as? Int,
            let state = info[kIOPSPowerSourceStateKey] as? String,
            let isChargingStatus = info[kIOPSIsChargingKey] as? Bool
        {

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
    }
    return nil
}

func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    if let info = getBatteryInfo() {
        print("Change detected: \(info)")
        postJSON(info)
    }
}

let callback: IOPowerSourceCallbackType = { context in
    powerSourceChanged(context)
}

if CommandLine.arguments.last == "--get" {
    if let info = getBatteryInfo() {
        let json = try JSONSerialization.data(withJSONObject: info)
        print(String(data: json, encoding: .utf8) ?? "")
        exit(0)
    }
    exit(1)
}

if let runLoopSource = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
    // Send once at start
    powerSourceChanged(nil)
    CFRunLoopRun()
} else {
    print("Failed to create power source run loop source")
}
