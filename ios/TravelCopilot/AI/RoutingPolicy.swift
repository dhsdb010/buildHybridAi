import Foundation

/// What kind of work a request is. Each kind has different needs:
/// - `survive`: in-trip, must work anywhere → prefers the device.
/// - `prepare`: builds the Vault before the trip → needs the cloud, user-initiated.
/// - `catchUp`: improves earlier drafts → cloud, and can wait for good Wi-Fi.
enum TaskKind: String, Codable, Sendable {
  case survive, prepare, catchUp
}

/// The network + device facts the policy needs, as a plain value so it can be unit-tested.
struct RoutingContext: Equatable, Sendable {
  var isOnline: Bool
  var isExpensive: Bool
  var isConstrained: Bool
  var deviceModelAvailable: Bool
  /// User setting "Roaming data saver" (on by default).
  var dataSaver: Bool = true

  var isMetered: Bool { isExpensive || isConstrained }
}

enum RoutingDecision: Equatable, Sendable {
  /// Run now on this route.
  case run(Route, reason: String)
  /// Don't run now; queue it for Catch-up on good Wi-Fi.
  case deferToWiFi(reason: String)
  /// Can't run at all right now.
  case blocked(reason: String)

  var reason: String {
    switch self {
    case let .run(_, reason), let .deferToWiFi(reason), let .blocked(reason): reason
    }
  }
}

/// Routing by availability, cost and task type (see plan_ios.md §2).
enum RoutingPolicy {
  static func decide(_ kind: TaskKind, _ ctx: RoutingContext) -> RoutingDecision {
    switch kind {
    case .survive:
      if !ctx.isOnline {
        return ctx.deviceModelAvailable
          ? .run(.deviceOnly, reason: "Offline → on-device")
          : .blocked(reason: "Offline and Apple Intelligence is unavailable")
      }
      if ctx.isMetered && ctx.dataSaver && ctx.deviceModelAvailable {
        return .run(.deviceOnly, reason: "Roaming data saver → on-device")
      }
      return ctx.deviceModelAvailable
        ? .run(.hybrid, reason: "On-device first, cloud fallback")
        : .run(.cloudOnly, reason: "Apple Intelligence unavailable → cloud")

    case .prepare:
      guard ctx.isOnline else { return .blocked(reason: "Preparing a trip needs internet") }
      return .run(.cloudOnly, reason: ctx.isMetered
        ? "Prepare needs the cloud (uses mobile data)"
        : "Prepare needs the cloud")

    case .catchUp:
      guard ctx.isOnline else { return .deferToWiFi(reason: "Offline → waiting for Wi-Fi") }
      if ctx.isMetered && ctx.dataSaver {
        return .deferToWiFi(reason: "Roaming data saver → waiting for Wi-Fi")
      }
      return .run(.cloudOnly, reason: "Good connection → cloud catch-up")
    }
  }
}
