import CoreLocation
import Observation

/// "You are here" for the map. GPS works without any network, so this is fully offline.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private(set) var location: CLLocation?
  private(set) var status: CLAuthorizationStatus = .notDetermined

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    status = manager.authorizationStatus
  }

  func start() {
    if status == .notDetermined { manager.requestWhenInUseAuthorization() }
    manager.startUpdatingLocation()
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let last = locations.last else { return }
    Task { @MainActor in self.location = last }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let s = manager.authorizationStatus
    Task { @MainActor in
      self.status = s
      if s == .authorizedWhenInUse || s == .authorizedAlways { self.manager.startUpdatingLocation() }
    }
  }
}
