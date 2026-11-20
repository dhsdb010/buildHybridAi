import Foundation
import HealthKit

/// Reads the two things Health lets apps read for the emergency card: blood type and
/// the medications the traveler chooses to share (iOS 26, per-medication permission).
/// The Medical ID itself (allergies, conditions, contacts) is private to iOS and can't be read.
@MainActor
enum EmergencyHealth {
  struct Found: Equatable {
    var bloodType: String?
    var medicines: [EmergencyMedicine] = []
  }

  static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  static func read() async -> Found {
    guard isAvailable else { return Found() }
    let store = HKHealthStore()
    var found = Found()
    // 1. Blood type (one standard read permission).
    if let bloodType = HKObjectType.characteristicType(forIdentifier: .bloodType) {
      try? await store.requestAuthorization(toShare: [], read: [bloodType])
      if let value = try? store.bloodType().bloodType { found.bloodType = Self.text(value) }
    }
    // 2. Medications: the traveler picks which ones to share.
    let medType = HKObjectType.userAnnotatedMedicationType()
    if (try? await store.requestPerObjectReadAuthorization(for: medType, predicate: nil)) != nil {
      found.medicines = await medicines(store)
    }
    return found
  }

  private static func medicines(_ store: HKHealthStore) async -> [EmergencyMedicine] {
    await withCheckedContinuation { cont in
      var out: [EmergencyMedicine] = []
      let active = NSPredicate(format: "%K == NO", HKUserAnnotatedMedicationPredicateKeyPathIsArchived)
      let q = HKUserAnnotatedMedicationQuery(predicate: active, limit: HKObjectQueryNoLimit) { _, med, done, _ in
        if let med {
          let name = med.nickname?.isEmpty == false ? med.nickname! : med.medication.displayText
          out.append(EmergencyMedicine(name: name, schedule: "", fromHealth: true))
        }
        if done { cont.resume(returning: out) }
      }
      store.execute(q)
    }
  }

  static func text(_ t: HKBloodType) -> String? {
    switch t {
    case .aPositive: "A+"
    case .aNegative: "A−"
    case .bPositive: "B+"
    case .bNegative: "B−"
    case .abPositive: "AB+"
    case .abNegative: "AB−"
    case .oPositive: "O+"
    case .oNegative: "O−"
    default: nil
    }
  }
}
