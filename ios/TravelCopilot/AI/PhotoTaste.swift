import CoreGraphics
import Foundation
import Vision

/// Reads trip photos on this iPhone with Apple's Vision framework (offline, no AI model, no network)
/// and turns them into a few taste words: "street food", "market", "old town"…
/// Only these words go to the cloud for planning; the photos never leave the phone.
enum PhotoTaste {
  /// Vision labels that say nothing about taste.
  static let generic: Set<String> = [
    "outdoor", "indoor", "structure", "people", "adult", "child", "sky", "daytime", "night_sky", "cloudy",
    "land", "plant", "wood_processed", "material", "textile", "liquid", "water_body", "machine", "vehicle",
    "conveyance", "consumer_electronics", "document", "screenshot", "printed_page", "clothing", "footwear",
    "headgear", "furniture", "wall", "floor", "ceiling", "window", "sign", "text", "art", "selfie", "portrait",
    "interior_room", "light", "lamp", "shelf", "container", "tableware", "utensil", "bag", "jacket",
  ]

  /// Labels for one photo with their confidence, best first.
  static func labels(for image: CGImage) throws -> [(String, Float)] {
    let request = VNClassifyImageRequest()
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    return (request.results ?? [])
      .filter { $0.confidence >= 0.3 && !generic.contains($0.identifier) }
      .map { ($0.identifier, $0.confidence) }
  }

  /// Taste words across several photos: labels that appear most often (then most confidently), as words.
  static func summarize(_ perPhoto: [[(String, Float)]], limit: Int = 6) -> [String] {
    var count: [String: Int] = [:], score: [String: Float] = [:]
    for labels in perPhoto {
      for (id, c) in labels.prefix(6) { count[id, default: 0] += 1; score[id, default: 0] += c }
    }
    return count.keys
      .sorted { (count[$0]!, score[$0]!) > (count[$1]!, score[$1]!) }
      .prefix(limit)
      .map(word)
  }

  /// "street_food" → "Street food".
  static func word(_ id: String) -> String {
    let w = id.replacingOccurrences(of: "_", with: " ")
    return w.prefix(1).uppercased() + w.dropFirst()
  }
}
