import Foundation

struct MessageReplayProtector {
    private var acceptedIDs: [String: [UUID: Date]] = [:]
    let maximumIDsPerDevice: Int
    let freshnessWindow: TimeInterval

    init(maximumIDsPerDevice: Int = 4_096, freshnessWindow: TimeInterval = 120) {
        self.maximumIDsPerDevice = max(maximumIDsPerDevice, 1)
        self.freshnessWindow = max(freshnessWindow, 1)
    }

    mutating func accept(_ id: UUID, sentAt: Int64, from device: String, now: Date = Date()) -> Bool {
        let messageDate = Date(timeIntervalSince1970: TimeInterval(sentAt))
        guard abs(now.timeIntervalSince(messageDate)) <= freshnessWindow else { return false }

        var ids = acceptedIDs[device, default: [:]]
        ids = ids.filter { now.timeIntervalSince($0.value) <= freshnessWindow }
        guard ids[id] == nil, ids.count < maximumIDsPerDevice else { return false }
        ids[id] = now
        acceptedIDs[device] = ids
        return true
    }

    mutating func reset(device: String) {
        acceptedIDs.removeValue(forKey: device)
    }
}

struct PairingAttemptLimiter {
    let maximumFailures: Int
    let failureWindow: TimeInterval
    let lockoutDuration: TimeInterval

    private var failures: [Date] = []
    private var lockedUntil: Date?

    init(maximumFailures: Int = 5, failureWindow: TimeInterval = 60, lockoutDuration: TimeInterval = 30) {
        self.maximumFailures = max(maximumFailures, 1)
        self.failureWindow = max(failureWindow, 1)
        self.lockoutDuration = max(lockoutDuration, 1)
    }

    mutating func remainingLockout(at date: Date = Date()) -> TimeInterval? {
        guard let lockedUntil else { return nil }
        let remaining = lockedUntil.timeIntervalSince(date)
        if remaining > 0 { return remaining }
        self.lockedUntil = nil
        failures.removeAll()
        return nil
    }

    mutating func recordFailure(at date: Date = Date()) -> TimeInterval? {
        if let remaining = remainingLockout(at: date) { return remaining }
        let window = failureWindow
        failures.removeAll { date.timeIntervalSince($0) > window }
        failures.append(date)
        guard failures.count >= maximumFailures else { return nil }
        failures.removeAll()
        lockedUntil = date.addingTimeInterval(lockoutDuration)
        return lockoutDuration
    }

    mutating func recordSuccess() {
        failures.removeAll()
        lockedUntil = nil
    }
}
