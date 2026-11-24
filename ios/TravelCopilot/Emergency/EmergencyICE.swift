import Foundation

/// The emergency card laid out like a paper ICE ("In Case of Emergency") card: titled sections in
/// a fixed order, each row with its label and value in the local language and English.
struct ICESection: Identifiable, Equatable {
  let id: String
  let title: String        // in the first language
  let titleOther: String   // in the other
  let rows: [EmergencyRow]
  /// Allergies are shown in red, like a paper card's warning.
  var alert = false
}

enum ICEText {
  /// Section and field labels in English, and per card language. Fixed, never generated.
  static let english: [String: String] = [
    "personal": "PERSONAL INFORMATION", "name": "Name", "birth": "Date of birth", "blood": "Blood type",
    "speaks": "Speaks", "phone": "Phone", "address": "Home address",
    "allergies": "ALLERGIES", "drug": "Drug", "food": "Food", "insect": "Insect", "otherAllergy": "Other",
    "medicines": "MEDICATIONS", "conditions": "CONDITIONS", "surgeries": "RECENT SURGERIES",
    "contacts": "EMERGENCY CONTACTS", "doctor": "PRIMARY DOCTOR", "doctorRow": "Doctor",
    "insurance": "TRAVEL INSURANCE", "provider": "Provider", "policy": "Policy no.", "assist": "Assistance",
    "none": "None",
  ]
  static let local: [String: [String: String]] = [
    "ja": ["personal": "個人情報", "name": "氏名", "birth": "生年月日", "blood": "血液型", "speaks": "話せる言語",
           "phone": "電話番号", "address": "住所", "allergies": "アレルギー", "drug": "薬", "food": "食べ物",
           "insect": "虫", "otherAllergy": "その他", "medicines": "服用中の薬", "conditions": "持病",
           "surgeries": "手術歴", "contacts": "緊急連絡先", "doctor": "主治医", "doctorRow": "医師",
           "insurance": "旅行保険", "provider": "保険会社", "policy": "証券番号", "assist": "緊急サポート", "none": "なし"],
    "ko": ["personal": "개인 정보", "name": "이름", "birth": "생년월일", "blood": "혈액형", "speaks": "사용 언어",
           "phone": "전화번호", "address": "주소", "allergies": "알레르기", "drug": "약물", "food": "음식",
           "insect": "곤충", "otherAllergy": "기타", "medicines": "복용 중인 약", "conditions": "지병",
           "surgeries": "수술 이력", "contacts": "비상 연락처", "doctor": "주치의", "doctorRow": "의사",
           "insurance": "여행자 보험", "provider": "보험사", "policy": "증권 번호", "assist": "긴급 지원", "none": "없음"],
    "zh": ["personal": "个人信息", "name": "姓名", "birth": "出生日期", "blood": "血型", "speaks": "使用语言",
           "phone": "电话", "address": "住址", "allergies": "过敏", "drug": "药物", "food": "食物",
           "insect": "昆虫", "otherAllergy": "其他", "medicines": "正在服用的药物", "conditions": "既往病史",
           "surgeries": "手术史", "contacts": "紧急联系人", "doctor": "主治医生", "doctorRow": "医生",
           "insurance": "旅行保险", "provider": "保险公司", "policy": "保单号", "assist": "紧急援助", "none": "无"],
  ]
  /// "English" in each card language (for the Speaks row).
  static let englishWord: [String: String] = ["ja": "英語", "ko": "영어", "zh": "英语"]

  /// Allergy type, like the columns on a paper card. Typed-in allergies are "Other".
  static func kind(of allergy: String) -> String {
    switch allergy {
    case "Penicillin", "Aspirin / NSAIDs", "Sulfa drugs": "drug"
    case "Peanuts", "Tree nuts", "Shellfish", "Eggs", "Milk", "Wheat": "food"
    case "Bee stings": "insect"
    default: "otherAllergy"
    }
  }
}

extension EmergencyCard {
  /// The ICE sections, in paper-card order. Empty optional sections are left out; allergies,
  /// medications and conditions always show (a medic needs "none" too).
  func iceSections(language: String, localFirst: Bool) -> [ICESection] {
    let code = String(language.prefix(2))
    let loc = ICEText.local[code]
    func t(_ k: String) -> (String, String) {
      let en = ICEText.english[k] ?? k, l = loc?[k] ?? en
      return localFirst ? (l, en) : (en, l)
    }
    func r(_ k: String, _ en: String, _ l: String?) -> EmergencyRow {
      let (a, b) = t(k)
      let other = (l == nil || l == en) ? nil : l
      return localFirst ? EmergencyRow(label: a, labelOther: b, value: other ?? en, valueOther: other == nil ? nil : en)
                        : EmergencyRow(label: a, labelOther: b, value: en, valueOther: other)
    }
    func item(_ en: String) -> String? { EmergencyText.local(en, language: language, card: self) }
    func section(_ k: String, _ rows: [EmergencyRow], alert: Bool = false) -> ICESection {
      let (a, b) = t(k); return ICESection(id: k, title: a, titleOther: b, rows: rows, alert: alert)
    }
    func numbered(_ items: [String]) -> [EmergencyRow] {
      guard !items.isEmpty else { return [r("none", "None", loc?["none"])] }
      return items.enumerated().map { i, en in
        let l = item(en)
        return EmergencyRow(label: "\(i + 1)", labelOther: "", value: localFirst ? (l ?? en) : en,
                            valueOther: l == nil ? nil : (localFirst ? en : l))
      }
    }

    var out: [ICESection] = []
    // Personal information
    var personal: [EmergencyRow] = []
    if !ownerName.isEmpty { personal.append(r("name", ownerName, nil)) }
    if let birthDate {
      let en = birthDate.formatted(.dateTime.year().month(.wide).day().locale(Locale(identifier: "en_US")))
      let l = loc == nil ? nil : birthDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: code)))
      personal.append(r("birth", en, l))
    }
    if let bloodType {
      let l = EmergencyText.bloodType(bloodType, language: language)
      personal.append(r("blood", bloodType, l == bloodType ? nil : l))
    }
    personal.append(r("speaks", speaks, speaks == "English" ? ICEText.englishWord[code] : nil))
    if !ownPhone.isEmpty { personal.append(r("phone", ownPhone, nil)) }
    if !homeAddress.isEmpty { personal.append(r("address", homeAddress, nil)) }
    out.append(section("personal", personal))

    // Allergies by type
    let groups = Dictionary(grouping: allergies, by: ICEText.kind)
    let allergyRows: [EmergencyRow] = allergies.isEmpty ? [r("none", "None", loc?["none"])] :
      ["drug", "food", "insect", "otherAllergy"].compactMap { k in
        guard let items = groups[k], !items.isEmpty else { return nil }
        let en = items.joined(separator: ", ")
        let ls = items.map { item($0) }
        let l = ls.contains { $0 != nil } ? zip(items, ls).map { $1 ?? $0 }.joined(separator: "、") : nil
        return r(k, en, l)
      }
    out.append(section("allergies", allergyRows, alert: !allergies.isEmpty))
    out.append(section("medicines", numbered(medicines.map(\.text))))
    out.append(section("conditions", numbered(conditions)))
    if !surgeries.isEmpty { out.append(section("surgeries", numbered(surgeries))) }

    // Emergency contacts
    var contacts: [EmergencyRow] = []
    for (name, phone, rel) in [(contactName, contactPhone, contactRelation), (contact2Name, contact2Phone, contact2Relation)] where !name.isEmpty {
      let relEN = rel.isEmpty ? "Contact" : rel
      let relL = item(rel)
      contacts.append(EmergencyRow(label: localFirst ? (relL ?? relEN) : relEN,
                                   labelOther: localFirst ? (relL == nil ? "" : relEN) : (relL ?? ""),
                                   value: name, valueOther: phone.isEmpty ? nil : phone))
    }
    if !contacts.isEmpty { out.append(section("contacts", contacts)) }
    if !doctorName.isEmpty || !doctorPhone.isEmpty {
      let (a, b) = t("doctorRow")
      out.append(section("doctor", [EmergencyRow(label: a, labelOther: b, value: doctorName.isEmpty ? doctorPhone : doctorName,
                                                 valueOther: doctorName.isEmpty || doctorPhone.isEmpty ? nil : doctorPhone)]))
    }
    var ins: [EmergencyRow] = []
    if !insuranceProvider.isEmpty { ins.append(r("provider", insuranceProvider, nil)) }
    if !insurancePolicy.isEmpty { ins.append(r("policy", insurancePolicy, nil)) }
    if !insurancePhone.isEmpty { ins.append(r("assist", insurancePhone, nil)) }
    if !ins.isEmpty { out.append(section("insurance", ins)) }
    return out
  }
}
