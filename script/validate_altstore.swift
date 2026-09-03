import Foundation

func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "PhoneDock.AltStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let ipaURL = URL(fileURLWithPath: CommandLine.arguments[2])
let source = try JSONSerialization.jsonObject(with: Data(contentsOf: sourceURL)) as! [String: Any]
let app = (source["apps"] as! [[String: Any]])[0]
let version = (app["versions"] as! [[String: Any]])[0]
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
process.arguments = ["-p", ipaURL.path, "Payload/Phone Dock.app/Info.plist"]
let pipe = Pipe(); process.standardOutput = pipe
try process.run()
let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
try require(process.terminationStatus == 0, "IPA must contain Payload/Phone Dock.app/Info.plist")
let info = try PropertyListSerialization.propertyList(from: bytes, format: nil) as! [String: Any]
try require(app["bundleIdentifier"] as? String == info["CFBundleIdentifier"] as? String, "Bundle ID mismatch")
try require(version["version"] as? String == info["CFBundleShortVersionString"] as? String, "Version mismatch")
try require(version["buildVersion"] as? String == info["CFBundleVersion"] as? String, "Build mismatch")
try require(version["minOSVersion"] as? String == info["MinimumOSVersion"] as? String, "Minimum OS mismatch")
try require(info["CFBundleSupportedPlatforms"] as? [String] == ["iPhoneOS"], "Not a physical-device build")
let size = try FileManager.default.attributesOfItem(atPath: ipaURL.path)[.size] as! NSNumber
try require((version["size"] as? NSNumber)?.uint64Value == size.uint64Value, "IPA byte size mismatch")
let permissions = app["appPermissions"] as! [String: Any]
let declared = permissions["privacy"] as! [String: String]
let actual = info.filter { $0.key.hasSuffix("UsageDescription") }.mapValues { $0 as! String }
try require(declared == actual, "Privacy declarations must match Info.plist exactly")
try require((permissions["entitlements"] as? [String]) == [], "This unsigned app has no custom entitlements")
try require((version["downloadURL"] as? String)?.hasPrefix("https://github.com/tiburonns/Phone-dock/releases/download/") == true, "Unexpected download URL")
print("PASS: IPA layout, iPhoneOS platform, bundle ID, version, build, minimum OS, byte size and privacy permissions")
