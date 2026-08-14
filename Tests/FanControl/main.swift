import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let maximum = try FanControlResponse.parse(
    #"{"success":true,"operation":"maximum","fanCount":2,"targetRPM":[5200,4900]}"#,
    expectedMode: .maximum
)
expect(maximum == FanControlResponse(mode: .maximum, fanCount: 2, targetRPM: [5200, 4900]),
       "maximum response should retain per-fan hardware targets")

let automatic = try FanControlResponse.parse(
    #"{"success":true,"operation":"automatic","fanCount":1,"targetRPM":[]}"#,
    expectedMode: .automatic
)
expect(automatic.mode == .automatic && automatic.fanCount == 1,
       "automatic response should validate its operation")

do {
    _ = try FanControlResponse.parse(
        #"{"success":true,"operation":"maximum","fanCount":1,"targetRPM":[5000]}"#,
        expectedMode: .automatic
    )
    expect(false, "a response for the wrong operation must be rejected")
} catch FanControlResponseError.incompatibleHelper {
    // Expected.
}

do {
    _ = try FanControlResponse.parse(#"{"fanRPM":1800}"#, expectedMode: .maximum)
    expect(false, "an older read-only helper must not be mistaken for a successful write")
} catch FanControlResponseError.incompatibleHelper {
    // Expected.
}

do {
    _ = try FanControlResponse.parse(
        #"{"success":true,"operation":"maximum","fanCount":2,"targetRPM":[5000]}"#,
        expectedMode: .maximum
    )
    expect(false, "every detected fan needs a confirmed maximum target")
} catch FanControlResponseError.invalidResponse {
    // Expected.
}

do {
    _ = try FanControlResponse.parse(
        #"{"success":false,"operation":"maximum","error":"No controllable fans were detected."}"#,
        expectedMode: .maximum
    )
    expect(false, "helper failures must be surfaced")
} catch FanControlResponseError.helperRejected(let message) {
    expect(message.contains("No controllable fans"), "the helper error should be preserved")
}

expect(PrivilegedHelperSecurity.isSafe(ownerID: 0, permissions: 0o755, isSymbolicLink: false),
       "a root-owned non-writable helper should be accepted")
expect(!PrivilegedHelperSecurity.isSafe(ownerID: 501, permissions: 0o755, isSymbolicLink: false),
       "a user-owned helper must never receive passwordless sudo")
expect(!PrivilegedHelperSecurity.isSafe(ownerID: 0, permissions: 0o775, isSymbolicLink: false),
       "a group-writable helper must never receive passwordless sudo")
expect(!PrivilegedHelperSecurity.isSafe(ownerID: 0, permissions: 0o755, isSymbolicLink: true),
       "a symlinked helper must be rejected")

print("Fan control response tests passed")
