import Foundation
import FirebaseAILogic

/// Retries a cloud call when Gemini has a temporary problem ("high demand" 500/503,
/// gateway errors, a dropped connection). Anything else fails at once: a bad request,
/// a blocked prompt or a quota error won't get better by asking again.
enum CloudRetry {
  /// Waits before the 2nd and 3rd attempt. Three attempts in all.
  static let delays: [Duration] = [.seconds(1), .seconds(3)]

  /// HTTP codes the backend uses for "try again shortly".
  static let transientCodes: Set<Int> = [500, 502, 503, 504]

  static func isTransient(_ error: any Error) -> Bool {
    if let e = error as? GenerateContentError, case let .internalError(underlying) = e {
      return isTransient(underlying)
    }
    if let e = error as? URLError {
      return [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(e.code)
    }
    // The SDK's `BackendError` is internal; it bridges to NSError with the HTTP code.
    let ns = error as NSError
    return ns.domain.hasSuffix("BackendError") && transientCodes.contains(ns.code)
  }

  /// Runs `operation`, retrying temporary failures. Returns the value and how many retries it took.
  static func run<T>(
    delays: [Duration] = delays,
    isolation: isolated (any Actor)? = #isolation,
    _ operation: () async throws -> T
  ) async throws -> (value: T, retries: Int) {
    var retries = 0
    while true {
      do {
        return (try await operation(), retries)
      } catch where retries < delays.count && isTransient(error) {
        try await Task.sleep(for: delays[retries])
        retries += 1
      }
    }
  }

  /// "· retried once" / "· retried 2×" for the Log reason, or "" when no retry was needed.
  static func note(_ retries: Int) -> String {
    switch retries {
    case 0: ""
    case 1: " · retried once"
    default: " · retried \(retries)×"
    }
  }
}
