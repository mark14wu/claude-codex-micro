// Explicit, bounded test of exclusive access to the physical Micro vendor HID.
// Default/list mode never opens a device. Seize mode sends no reports, changes
// no keymap or lighting, and closes normally or is reaped at its hard deadline.
import Foundation
import IOKit.hid
import Darwin

func emit(_ fields: [String: Any]) {
    var value = fields
    value["time"] = ISO8601DateFormatter().string(from: Date())
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func integer(_ device: IOHIDDevice, _ key: String) -> Int {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? -1
}

func identity(_ device: IOHIDDevice) -> [String: Any] {
    var registryID: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID)
    let pairs = IOHIDDeviceGetProperty(device, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] ?? []
    return [
        "registryID": String(registryID),
        "vendorID": integer(device, kIOHIDVendorIDKey),
        "productID": integer(device, kIOHIDProductIDKey),
        "primaryUsagePage": integer(device, kIOHIDPrimaryUsagePageKey),
        "primaryUsage": integer(device, kIOHIDPrimaryUsageKey),
        "usagePairs": pairs,
        "transport": IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "unknown"
    ]
}

func returnValue(_ value: IOReturn) -> String {
    String(format: "0x%08x", UInt32(bitPattern: value))
}

let args = Array(CommandLine.arguments.dropFirst())
var seconds = 8
var shouldSeize = false
if args == ["--help"] {
    print("Usage: probe-hid-seize [--list | --seize --seconds 1..30]")
    print("Only USB 303A:8360 with primary usage FF00 is eligible. No reports are sent.")
    exit(0)
} else if args.isEmpty || args == ["--list"] {
    // Enumeration only.
} else if args.count == 3, args[0] == "--seize", args[1] == "--seconds",
          let value = Int(args[2]), (1...30).contains(value) {
    shouldSeize = true
    seconds = value
} else {
    emit(["event": "invalid_arguments"])
    exit(64)
}

// Bounds enumeration/open/close as well as the hold itself. On abnormal exit,
// macOS tears down the process's HID user client and releases its claim.
signal(SIGALRM) { _ in _exit(124) }
alarm(UInt32(seconds + 10))

emit([
    "event": "access", "listen": IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue,
    "post": IOHIDCheckAccess(kIOHIDRequestTypePostEvent).rawValue,
    "uid": getuid(), "euid": geteuid(), "mode": shouldSeize ? "seize" : "list",
    "hardDeadlineSeconds": seconds + 10,
    "sendsReports": false
])

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDVendorIDKey: 0x303a,
    kIOHIDProductIDKey: 0x8360,
] as CFDictionary)
let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
var seen = Set<String>()
var candidates: [IOHIDDevice] = []
for device in devices {
    let fields = identity(device)
    guard let id = fields["registryID"] as? String, seen.insert(id).inserted else { continue }
    emit(["event": "device", "identity": fields])
    // No fallback to keyboard, consumer, Bluetooth, or a device that merely
    // contains a vendor usage in its secondary collections.
    if integer(device, kIOHIDPrimaryUsagePageKey) == 0xff00,
       integer(device, kIOHIDPrimaryUsageKey) == 1,
       fields["transport"] as? String == "USB" {
        candidates.append(device)
    }
}
guard shouldSeize else { alarm(0); exit(0) }
guard candidates.count == 1, let device = candidates.first else {
    emit(["event": "refused_ambiguous_or_missing_target", "candidateCount": candidates.count])
    exit(3)
}

let options = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
let opened = IOHIDDeviceOpen(device, options)
emit(["event": "open_result", "result": returnValue(opened), "identity": identity(device)])
guard opened == kIOReturnSuccess else { exit(2) }
emit(["event": "seized", "holdSeconds": seconds])
let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
while ProcessInfo.processInfo.systemUptime < deadline {
    Thread.sleep(forTimeInterval: 0.05)
}
let closed = IOHIDDeviceClose(device, options)
emit(["event": "released", "result": returnValue(closed)])
alarm(0)
exit(closed == kIOReturnSuccess ? 0 : 4)
