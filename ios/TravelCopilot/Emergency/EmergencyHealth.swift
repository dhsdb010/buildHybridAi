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
      do { try await store.requestAuthorization(toShare: [], read: [bloodType]) }
      catch { NSLog("Health blood type auth: %@", error.localizedDescription) }
      do {
        let value = try store.bloodType().bloodType
        found.bloodType = Self.text(value)
        // .notSet also means "not allowed": iOS hides whether read access was denied.
        NSLog("Health blood type: %@", found.bloodType ?? "not set or not shared (raw \(value.rawValue))")
      } catch {
        NSLog("Health blood type read: %@", error.localizedDescription)
      }
    }
    // 2. Medications: the traveler picks which ones to share.
    let medType = HKObjectType.userAnnotatedMedicationType()
    do {
      try await store.requestPerObjectReadAuthorization(for: medType, predicate: nil)
      found.medicines = await medicines(store)
      NSLog("Health medications: %d shared", found.medicines.count)
    } catch {
      NSLog("Health medications: %@", error.localizedDescription)
    }
    return found
  }

  /// Active medications the traveler shared. Always finishes: on an error, with no medications
  /// (Health may never report "done" then), or after `timeout`, it returns what it has.
  private static func medicines(_ store: HKHealthStore, timeout: Duration = .seconds(6)) async -> [EmergencyMedicine] {
    let box = Once<[EmergencyMedicine]>()
    let active = NSPredicate(format: "%K == NO", HKUserAnnotatedMedicationPredicateKeyPathIsArchived)
    let q = HKUserAnnotatedMedicationQuery(predicate: active, limit: HKObjectQueryNoLimit) { _, med, done, error in
      if let med {
        let name = med.nickname?.isEmpty == false ? med.nickname! : med.medication.displayText
        box.append(EmergencyMedicine(name: name, schedule: "", fromHealth: true))
      }
      if done || error != nil || med == nil { box.finish() }
    }
    store.execute(q)
    return await withTaskGroup(of: [EmergencyMedicine].self) { group in
      group.addTask { await box.value() }
      group.addTask { try? await Task.sleep(for: timeout); box.finish(); return await box.value() }
      let first = await group.next() ?? []
      group.cancelAll()
      store.stop(q)
      return first
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

/// Collects results from a callback and hands them over once, however many times it's finished.
final class Once<T: Sendable>: @unchecked Sendable where T: RangeReplaceableCollection {
  private let lock = NSLock()
  private var items = T()
  private var done = false
  private var waiters: [CheckedContinuation<T, Never>] = []

  func append(_ e: T.Element) { lock.lock(); if !done { items.append(e) }; lock.unlock() }

  func finish() {
    lock.lock()
    guard !done else { lock.unlock(); return }
    done = true
    let w = waiters; waiters = []; let v = items
    lock.unlock()
    w.forEach { $0.resume(returning: v) }
  }

  func value() async -> T {
    await withCheckedContinuation { c in
      lock.lock()
      if done { let v = items; lock.unlock(); c.resume(returning: v) } else { waiters.append(c); lock.unlock() }
    }
  }
}
