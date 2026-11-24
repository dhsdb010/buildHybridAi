import Foundation
import UIKit

/// The traveler's profile (Figma: 10 · Profile). Kept on this iPhone, in UserDefaults, and only used
/// to plan with you (Blue's taste line), for your currency and budget, and for Home and the trip summary.
enum Profile {
  enum Key {
    static let name = "profileName", city = "profileCity", airport = "profileAirport", currency = "profileCurrency"
    static let languages = "profileLanguages", likes = "profileLikes", pace = "profilePace", skip = "profileSkip"
    static let countSteps = "countSteps"
  }

  static let likeOptions = ["Food", "Design", "Night markets", "Museums", "Slow mornings", "Nature", "Coffee",
                            "Shopping", "Art", "Hot springs", "Hiking", "Nightlife"]
  static let paces = ["Relaxed", "Balanced", "Packed"]

  private static var d: UserDefaults { .standard }
  private static func text(_ k: String) -> String? {
    guard let v = d.string(forKey: k)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
    return v
  }

  static var name: String? { text(Key.name) }
  static var likes: [String] { (text(Key.likes) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
  /// "USD" etc. when the traveler picked one; nil = the iPhone's region.
  static var currency: String? { text(Key.currency).map { $0.uppercased() }.flatMap { $0.count == 3 ? $0 : nil } }

  /// "Welcome back, Alex": the profile name, else the account's first name.
  static func firstName(account: String?) -> String? {
    if let name { return name }
    guard let a = account?.split(separator: " ").first, !a.isEmpty else { return nil }
    return String(a)
  }

  /// For Blue's planner prompt: what the traveler said about how they travel. No name, city or contact.
  static var tasteLine: String {
    var parts: [String] = []
    if !likes.isEmpty { parts.append("They like: " + likes.joined(separator: ", ")) }
    if let p = text(Key.pace) { parts.append("Preferred pace: \(p)") }
    if let s = text(Key.skip) { parts.append("Skip: \(s)") }
    return parts.joined(separator: ". ")
  }

  // MARK: Photo (a small JPEG in Application Support; never uploaded)

  static var photoURL: URL {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("profile.jpg")
  }
  static var photo: UIImage? { UIImage(contentsOfFile: photoURL.path) }
  static func savePhoto(_ data: Data?) {
    guard let data, let img = UIImage(data: data) else { try? FileManager.default.removeItem(at: photoURL); return }
    let side: CGFloat = 400
    let scale = side / max(1, min(img.size.width, img.size.height))
    let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
    let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
      img.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
    }
    try? small.jpegData(compressionQuality: 0.8)?.write(to: photoURL, options: .atomic)
  }
}
