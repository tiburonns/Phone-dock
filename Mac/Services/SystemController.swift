import AppKit
import ApplicationServices
import CoreAudio
import Darwin
import Foundation

@MainActor
final class SystemController {
    enum ControllerError: LocalizedError {
        case applicationNotFound
        case invalidURL
        case shortcutFailed(String)
        case accessibilityRequired
        case brightnessUnavailable
        case audioUnavailable

        var errorDescription: String? {
            switch self {
            case .applicationNotFound: localized("The selected application is not installed.")
            case .invalidURL: localized("The website address is invalid.")
            case .shortcutFailed(let message): localizedFormat("Shortcut failed: %@", message)
            case .accessibilityRequired: localized("Enable Phone Dock in System Settings → Privacy & Security → Accessibility.")
            case .brightnessUnavailable: localized("Brightness control is unavailable for this display.")
            case .audioUnavailable: localized("The current audio output does not expose a master volume.")
            }
        }
    }

    func execute(_ command: RemoteCommand) async throws {
        switch command {
        case .launchApp(let bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                throw ControllerError.applicationNotFound
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        case .openURL(let value):
            guard let url = URL(string: value) else { throw ControllerError.invalidURL }
            NSWorkspace.shared.open(url)
        case .runShortcut(let name):
            try runProcess("/usr/bin/shortcuts", arguments: ["run", name])
        case .insertText(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            try sendKey(9, flags: .maskCommand)
        case .setVolume(let value):
            try setVolume(value)
        case .setMuted(let muted):
            try setMuted(muted)
        case .setBrightness(let value):
            try setBrightness(value)
        case .setRecentAppPinned:
            break
        case .window(let action):
            try performWindowAction(action)
        case .clipboard(let action):
            try sendKey(action == .copy ? 8 : 9, flags: .maskCommand)
        }
    }

    func currentState() -> MacState {
        MacState(
            volume: (try? readVolume()) ?? 0,
            isMuted: (try? readMuted()) ?? false,
            brightness: try? readBrightness(),
            frontmostApplication: NSWorkspace.shared.frontmostApplication?.localizedName
        )
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { throw ControllerError.audioUnavailable }
        return device
    }

    private func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func readVolume() throws -> Double {
        let device = try defaultOutputDevice()
        var address = volumeAddress()
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            throw ControllerError.audioUnavailable
        }
        return Double(value)
    }

    private func setVolume(_ value: Double) throws {
        let device = try defaultOutputDevice()
        var address = volumeAddress()
        var scalar = Float32(min(max(value, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectSetPropertyData(device, &address, 0, nil, size, &scalar) == noErr else {
            throw ControllerError.audioUnavailable
        }
    }

    private func readMuted() throws -> Bool {
        let device = try defaultOutputDevice()
        var address = muteAddress()
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    private func setMuted(_ muted: Bool) throws {
        let device = try defaultOutputDevice()
        var address = muteAddress()
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr else {
            throw ControllerError.audioUnavailable
        }
    }

    private typealias DisplayServicesGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private let fallbackBrightnessKey = "cocoalift.softwareBrightness"

    private func displayService<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private func readBrightness() throws -> Double {
        if let function = displayService("DisplayServicesGetBrightness", as: DisplayServicesGetBrightness.self) {
            var value: Float = 0
            if function(CGMainDisplayID(), &value) == 0 { return Double(value) }
        }
        return UserDefaults.standard.object(forKey: fallbackBrightnessKey) as? Double ?? 1
    }

    private func setBrightness(_ value: Double) throws {
        let level = min(max(value, 0), 1)
        if let function = displayService("DisplayServicesSetBrightness", as: DisplayServicesSetBrightness.self),
           function(CGMainDisplayID(), Float(level)) == 0 {
            UserDefaults.standard.removeObject(forKey: fallbackBrightnessKey)
            return
        }
        let softwareLevel = Float(max(level, 0.08))
        let error = CGSetDisplayTransferByFormula(
            CGMainDisplayID(),
            0, softwareLevel, 1,
            0, softwareLevel, 1,
            0, softwareLevel, 1
        )
        guard error == .success else { throw ControllerError.brightnessUnavailable }
        UserDefaults.standard.set(level, forKey: fallbackBrightnessKey)
    }

    private func runProcess(_ executable: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw ControllerError.shortcutFailed(String(decoding: data, as: UTF8.self))
        }
    }

    private func sendKey(_ keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard AXIsProcessTrusted() else { throw ControllerError.accessibilityRequired }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func performWindowAction(_ action: WindowCommand) throws {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else {
            throw ControllerError.accessibilityRequired
        }
        if action == .hide {
            app.hide()
            return
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let window = focused else { throw ControllerError.accessibilityRequired }
        if action == .minimize {
            AXUIElementSetAttributeValue(window as! AXUIElement, kAXMinimizedAttribute as CFString, true as CFBoolean)
        } else {
            AXUIElementSetAttributeValue(window as! AXUIElement, "AXFullScreen" as CFString, true as CFBoolean)
        }
    }
}
