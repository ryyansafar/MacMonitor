import Foundation

enum FanControlMode: String {
    case automatic
    case maximum
}

struct FanControlResponse: Equatable {
    let mode: FanControlMode
    let fanCount: Int
    let targetRPM: [Int]

    static func parse(_ output: String, expectedMode: FanControlMode) throws -> FanControlResponse {
        guard let data = output.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FanControlResponseError.invalidResponse
        }

        guard let successNumber = payload["success"] as? NSNumber else {
            throw FanControlResponseError.incompatibleHelper
        }
        let success = successNumber.boolValue
        if !success {
            let message = payload["error"] as? String
            throw FanControlResponseError.helperRejected(message ?? "The helper rejected the request.")
        }
        guard let operation = payload["operation"] as? String,
              operation == expectedMode.rawValue else {
            throw FanControlResponseError.incompatibleHelper
        }

        let fanCount = (payload["fanCount"] as? NSNumber)?.intValue ?? 0
        guard fanCount > 0 else { throw FanControlResponseError.invalidResponse }
        let targets = (payload["targetRPM"] as? [NSNumber])?.map(\.intValue) ?? []
        if expectedMode == .maximum && targets.count != fanCount {
            throw FanControlResponseError.invalidResponse
        }
        return FanControlResponse(mode: expectedMode, fanCount: fanCount, targetRPM: targets)
    }
}

enum FanControlResponseError: LocalizedError, Equatable {
    case invalidResponse
    case incompatibleHelper
    case helperRejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The fan helper returned an invalid response."
        case .incompatibleHelper:
            return "Reinstall or update MacMonitor before using fan control."
        case .helperRejected(let message):
            return message
        }
    }
}

enum PrivilegedHelperSecurity {
    static func isSafe(ownerID: Int, permissions: Int, isSymbolicLink: Bool) -> Bool {
        ownerID == 0 && permissions & 0o022 == 0 && !isSymbolicLink
    }
}
