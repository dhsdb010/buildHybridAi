import Testing
@testable import TravelCopilot

struct RoutingPolicyTests {
  let wifi = RoutingContext(isOnline: true, isExpensive: false, isConstrained: false, deviceModelAvailable: true)
  var offline: RoutingContext { var c = wifi; c.isOnline = false; return c }
  var roaming: RoutingContext { var c = wifi; c.isExpensive = true; return c }
  var lowData: RoutingContext { var c = wifi; c.isConstrained = true; return c }

  @Test func surviveOnWiFiIsHybrid() {
    #expect(RoutingPolicy.decide(.survive, wifi) == .run(.hybrid, reason: "On-device first, cloud fallback"))
  }

  @Test func surviveOfflineIsDeviceOnly() {
    guard case .run(.deviceOnly, _) = RoutingPolicy.decide(.survive, offline) else { Issue.record(); return }
  }

  @Test func surviveOfflineWithoutModelIsBlocked() {
    var c = offline; c.deviceModelAvailable = false
    guard case .blocked = RoutingPolicy.decide(.survive, c) else { Issue.record(); return }
  }

  @Test func surviveRoamingStaysOnDevice() {
    guard case .run(.deviceOnly, _) = RoutingPolicy.decide(.survive, roaming) else { Issue.record(); return }
    guard case .run(.deviceOnly, _) = RoutingPolicy.decide(.survive, lowData) else { Issue.record(); return }
  }

  @Test func surviveRoamingWithSaverOffUsesHybrid() {
    var c = roaming; c.dataSaver = false
    guard case .run(.hybrid, _) = RoutingPolicy.decide(.survive, c) else { Issue.record(); return }
  }

  @Test func surviveWithoutModelUsesCloud() {
    var c = wifi; c.deviceModelAvailable = false
    guard case .run(.cloudOnly, _) = RoutingPolicy.decide(.survive, c) else { Issue.record(); return }
  }

  @Test func prepareNeedsInternet() {
    guard case .blocked = RoutingPolicy.decide(.prepare, offline) else { Issue.record(); return }
    guard case .run(.cloudOnly, _) = RoutingPolicy.decide(.prepare, roaming) else { Issue.record(); return }
  }

  @Test func catchUpWaitsForGoodWiFi() {
    guard case .deferToWiFi = RoutingPolicy.decide(.catchUp, offline) else { Issue.record(); return }
    guard case .deferToWiFi = RoutingPolicy.decide(.catchUp, roaming) else { Issue.record(); return }
    guard case .run(.cloudOnly, _) = RoutingPolicy.decide(.catchUp, wifi) else { Issue.record(); return }
  }
}
