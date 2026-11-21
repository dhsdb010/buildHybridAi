import Foundation
import SwiftData

/// The traveler's emergency medical card (Figma: App Screens → "Emergency info card · flow").
/// Stored on this iPhone only. Labels and common allergies/conditions are pre-translated (no AI);
/// the traveler's own words are translated once while online and checked by `SafetyCheck`.
@Model
final class EmergencyCard {
  var bloodType: String?           // "A+", "O−", nil = don't know
  var medicinesData: Data = Data() // [EmergencyMedicine], JSON
  var allergies: [String] = []     // English, as tapped or typed
  var conditions: [String] = []
  var contactName: String = ""
  var contactPhone: String = ""
  var contactRelation: String = ""  // Partner · Parent · Child · Friend · Other
  var speaks: String = "English"
  /// English text → its translation, for the card's language (only the traveler's own words).
  var translations: [String: String] = [:]
  var translationLanguage: String = ""
  var updatedAt: Date = Date()

  init() {}

  var medicines: [EmergencyMedicine] {
    get { (try? JSONDecoder().decode([EmergencyMedicine].self, from: medicinesData)) ?? [] }
    set { medicinesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
  }

  var isEmpty: Bool {
    bloodType == nil && medicines.isEmpty && allergies.isEmpty && conditions.isEmpty && contactName.isEmpty
  }
}

struct EmergencyMedicine: Codable, Hashable, Sendable {
  var name: String       // "Ibuprofen 200 mg"
  var schedule: String   // "twice a day"
  var fromHealth = false
  var text: String { schedule.isEmpty ? name : "\(name), \(schedule)" }
}

/// Pre-translated text for the card. Never generated, so it's right every time and works offline.
enum EmergencyText {
  struct Labels: Equatable {
    let title, allergies, medicines, conditions, bloodType, contact: String
    let none: String
  }

  static let english = Labels(title: "Emergency medical card", allergies: "Allergies", medicines: "Medicines",
                              conditions: "Conditions", bloodType: "Blood type", contact: "Emergency contact", none: "None")

  static let labels: [String: Labels] = [
    "ja": .init(title: "緊急医療情報", allergies: "アレルギー", medicines: "服用中の薬", conditions: "持病",
                bloodType: "血液型", contact: "緊急連絡先", none: "なし"),
    "ko": .init(title: "응급 의료 정보", allergies: "알레르기", medicines: "복용 중인 약", conditions: "지병",
                bloodType: "혈액형", contact: "비상 연락처", none: "없음"),
    "zh": .init(title: "紧急医疗信息", allergies: "过敏", medicines: "正在服用的药物", conditions: "既往病史",
                bloodType: "血型", contact: "紧急联系人", none: "无"),
  ]

  /// Common allergies and conditions offered as chips, with fixed translations.
  static let commonAllergies = ["Penicillin", "Aspirin / NSAIDs", "Sulfa drugs", "Peanuts", "Tree nuts", "Shellfish",
                                "Eggs", "Milk", "Wheat", "Latex", "Bee stings"]
  static let commonConditions = ["Asthma", "Diabetes", "Heart condition", "High blood pressure", "Epilepsy", "Pregnant"]
  static let relations = ["Partner", "Parent", "Child", "Friend", "Other"]

  static let fixed: [String: [String: String]] = [
    "ja": ["Penicillin": "ペニシリン", "Aspirin / NSAIDs": "アスピリン・解熱鎮痛薬（NSAIDs）", "Sulfa drugs": "サルファ剤",
           "Peanuts": "ピーナッツ", "Tree nuts": "ナッツ類", "Shellfish": "甲殻類・貝類", "Eggs": "卵", "Milk": "乳",
           "Wheat": "小麦", "Latex": "ラテックス", "Bee stings": "ハチ刺され",
           "Asthma": "喘息", "Diabetes": "糖尿病", "Heart condition": "心臓病", "High blood pressure": "高血圧",
           "Epilepsy": "てんかん", "Pregnant": "妊娠中",
           "Partner": "パートナー", "Parent": "親", "Child": "子", "Friend": "友人", "Other": "その他"],
    "ko": ["Penicillin": "페니실린", "Peanuts": "땅콩", "Shellfish": "갑각류·조개류", "Eggs": "달걀", "Milk": "우유",
           "Wheat": "밀", "Asthma": "천식", "Diabetes": "당뇨병", "Pregnant": "임신 중",
           "Partner": "배우자", "Parent": "부모", "Child": "자녀", "Friend": "친구", "Other": "기타"],
    "zh": ["Penicillin": "青霉素", "Peanuts": "花生", "Shellfish": "甲壳类·贝类", "Eggs": "鸡蛋", "Milk": "牛奶",
           "Wheat": "小麦", "Asthma": "哮喘", "Diabetes": "糖尿病", "Pregnant": "怀孕",
           "Partner": "伴侣", "Parent": "父母", "Child": "子女", "Friend": "朋友", "Other": "其他"],
  ]

  static func labels(for language: String) -> Labels? { labels[String(language.prefix(2))] }

  /// The local word for an English item: fixed table first, then the card's saved translation.
  static func local(_ english: String, language: String, card: EmergencyCard) -> String? {
    let code = String(language.prefix(2))
    if let f = fixed[code]?[english] { return f }
    return card.translationLanguage == code ? card.translations[english] : nil
  }

  /// "A+" → "A型 Rh+" in Japanese; other languages keep "A+".
  static func bloodType(_ t: String, language: String) -> String {
    guard language.hasPrefix("ja"), let sign = t.last, "+−-".contains(sign) else { return t }
    return "\(t.dropLast())型 Rh\(sign == "+" ? "+" : "−")"
  }

  /// Items whose translation still has to come from AI (the traveler's own words).
  /// Medicines imported from Apple Health are left out: Health data never leaves the iPhone,
  /// so those stay in English on the card (drug names are widely read in English).
  static func needsTranslation(_ card: EmergencyCard, language: String) -> [String] {
    let code = String(language.prefix(2))
    let items = card.allergies + card.conditions + card.medicines.filter { !$0.fromHealth }.map(\.text)
    return items.filter { fixed[code]?[$0] == nil && (card.translationLanguage != code || card.translations[$0] == nil) }
  }
}

/// One row on the card: label in both languages, the value in the primary language, the other under it.
struct EmergencyRow: Equatable {
  let label: String
  let labelOther: String
  let value: String
  let valueOther: String?
}

extension EmergencyCard {
  /// `local`: the card's language first (the side for a doctor); otherwise English first.
  func rows(language: String, localFirst: Bool) -> [EmergencyRow] {
    let en = EmergencyText.english
    let loc = EmergencyText.labels(for: language) ?? en
    func pair(_ items: [String]) -> (en: String, local: String?) {
      guard !items.isEmpty else { return (en.none, loc.none) }
      let locals = items.map { EmergencyText.local($0, language: language, card: self) }
      let hasLocal = locals.contains { $0 != nil }
      // Medicine names stay readable: "イブプロフェン (ibuprofen)" comes from the translation itself.
      return (items.joined(separator: "\n"), hasLocal ? zip(items, locals).map { $1 ?? $0 }.joined(separator: "\n") : nil)
    }
    func row(_ l: String, _ lLocal: String, _ v: (en: String, local: String?)) -> EmergencyRow {
      localFirst
        ? EmergencyRow(label: lLocal, labelOther: l, value: v.local ?? v.en, valueOther: v.local == nil ? nil : v.en.replacingOccurrences(of: "\n", with: ", "))
        : EmergencyRow(label: l, labelOther: lLocal, value: v.en, valueOther: v.local?.replacingOccurrences(of: "\n", with: "、"))
    }
    var out: [EmergencyRow] = [
      row(en.allergies, loc.allergies, pair(allergies)),
      row(en.medicines, loc.medicines, pair(medicines.map(\.text))),
      row(en.conditions, loc.conditions, pair(conditions)),
    ]
    if let bloodType {
      let local = EmergencyText.bloodType(bloodType, language: language)
      out.append(row(en.bloodType, loc.bloodType, (bloodType, local == bloodType ? nil : local)))
    }
    if !contactName.isEmpty {
      // Name and number read the same in both languages; only the relation changes ("Partner" / "パートナー").
      let relLocal = EmergencyText.local(contactRelation, language: language, card: self)
      let first = localFirst ? (relLocal ?? contactRelation) : contactRelation.lowercased()
      let value = "\(contactName)\(first.isEmpty ? "" : " (\(first))")\n\(contactPhone)"
      let other = localFirst ? (contactRelation.isEmpty ? nil : contactRelation) : relLocal
      out.append(localFirst
        ? EmergencyRow(label: loc.contact, labelOther: en.contact, value: value, valueOther: other)
        : EmergencyRow(label: en.contact, labelOther: loc.contact, value: value, valueOther: other))
    }
    return out
  }
}
