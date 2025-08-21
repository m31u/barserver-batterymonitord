import Foundation
import IOKit.ps

func postJSON(_ json: [String: Any], _ target: String) {
    guard let url = URL(string: target) else { return }
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

        if let target = context?.assumingMemoryBound(to: CChar.self) {
            postJSON(info, String(cString: target))
        }

    }
}

let callback: IOPowerSourceCallbackType = { context in
    powerSourceChanged(context)
}

if CommandLine.arguments.last == "--get" || CommandLine.arguments.last == "-g" {
    if let info = getBatteryInfo() {
        let json = try JSONSerialization.data(withJSONObject: info)
        print(String(data: json, encoding: .utf8) ?? "{}")
        exit(0)
    }
    exit(1)
}

let args = CommandLine.arguments

if let index = (args.lastIndex(of: "-d") ?? args.lastIndex(of: "--daemonize")) {

    let target = CommandLine.arguments[index + 1].utf8CString
    let context = UnsafeMutableRawPointer.allocate(
        byteCount: target.count, alignment: MemoryLayout<UInt8>.alignment)

    defer { context.deallocate() }

    target.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
        context.copyMemory(from: buffer.baseAddress!, byteCount: target.count)
    }
    if let runLoopSource = IOPSNotificationCreateRunLoopSource(callback, context)?
        .takeRetainedValue()
    {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        powerSourceChanged(context)
        CFRunLoopRun()
    } else {
        print("Failed to create power source run loop source")
    }
}

print("No valid option provided")
print("Options:")
print("--get, -g             - Print current battery information as json and exit")
print(
    "--daemonize, -d [url] - Daemonize, battery status changes will be posted to the provided url")
