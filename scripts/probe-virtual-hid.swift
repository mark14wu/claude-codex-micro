// Bounded CoreHID capability probe. This never opens a physical device and
// never dispatches input reports. Build without restricted entitlements for
// a negative permission test. A positive test needs an authorized signature
// and provisioning profile, not an ad-hoc entitlement assertion.
import CoreHID
import Foundation
import Darwin

private func emit(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let line = String(data: data, encoding: .utf8) {
        print(line)
        fflush(stdout)
    }
}

@available(macOS 15, *)
private actor ProbeDelegate: HIDVirtualDeviceDelegate {
    enum RequestError: Error { case unsupported }

    func hidVirtualDevice(_ device: HIDVirtualDevice,
                          receivedSetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, data: Data) async throws {
        // Never claim an arbitrary host request succeeded or send input back.
        emit(["event": "unexpected_set_report", "bytes": data.count])
        throw RequestError.unsupported
    }

    func hidVirtualDevice(_ device: HIDVirtualDevice,
                          receivedGetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, maxSize: Int) async throws -> Data {
        emit(["event": "unexpected_get_report", "maxSize": maxSize])
        throw RequestError.unsupported
    }
}

@main
struct VirtualHIDProbe {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args == ["--help"] {
            print("""
            Usage: virtual-hid-probe --attempt-create [--seconds 1..30]
            Creates only a vendor-defined test device (FFFF:C0DE), never a keyboard,
            mouse or Codex Micro. Sends no input; opens no physical device.
            Without approved virtual-HID entitlement, creation is expected to fail.
            Exit 2 means CoreHID returned nil; it is not a definitive error code.
            """)
            return
        }
        let seconds: Int
        if args == ["--attempt-create"] {
            seconds = 5
        } else if args.count == 3, args[0] == "--attempt-create", args[1] == "--seconds",
                  let value = Int(args[2]), (1...30).contains(value) {
            seconds = value
        } else {
            emit(["event": "invalid_arguments"])
            exit(64)
        }
        guard #available(macOS 15, *) else {
            emit(["event": "unsupported_os"])
            exit(1)
        }

        // Application collection, vendor page FF00, input/output report 06,
        // 63 data bytes + report ID. No keyboard or mouse usages.
        let descriptor = Data([
            0x06, 0x00, 0xff, 0x09, 0x01, 0xa1, 0x01,
            0x85, 0x06, 0x15, 0x00, 0x26, 0xff, 0x00,
            0x75, 0x08, 0x95, 0x3f,
            0x09, 0x01, 0x81, 0x02,
            0x09, 0x01, 0x91, 0x02, 0xc0,
        ])
        emit([
            "event": "attempt", "api": "CoreHID.HIDVirtualDevice",
            "vendorID": 65535, "productID": 49374, "usagePage": 65280,
            "durationSeconds": seconds, "dispatchesInput": false,
            "opensPhysicalDevice": false,
        ])
        let properties = HIDVirtualDevice.Properties(
            descriptor: descriptor, vendorID: 0xffff, productID: 0xc0de,
            transport: .virtual, product: "Micro Bridge Capability Probe",
            manufacturer: "Local development probe", versionNumber: 1,
            serialNumber: "micro-bridge-probe-\(UUID().uuidString)"
        )
        guard let device = HIDVirtualDevice(properties: properties) else {
            emit([
                "event": "creation_failed", "apiReturned": "nil",
                "reason": "CoreHID supplies no detailed error here. Check approved entitlement, signature/profile and system consent separately.",
            ])
            exit(2)
        }
        await device.activate(delegate: ProbeDelegate())
        emit(["event": "created", "vendorID": 65535, "productID": 49374])
        try? await Task.sleep(for: .seconds(seconds))
        // The object stays retained through this point; process exit removes
        // the virtual device. No persistent service or background job is left.
        withExtendedLifetime(device) {
            emit(["event": "finished", "dispatchesInput": false])
        }
    }
}
