import CryptoKit
import Foundation
import Security
import UIKit

/// The emergency card as an Apple Wallet pass, made and signed on this iPhone (health data never
/// leaves it). A .pkpass is a zip of pass.json, images, manifest.json (SHA-1 of every file) and
/// `signature`: a detached CMS signature of the manifest with the Pass Type ID certificate.
///
/// The certificate (PassCertificate.p12 + PassCertificate.password) and Apple's WWDR G4
/// intermediate (AppleWWDRCAG4.cer) are copied into the app at build time from
/// ios/TravelCopilot/Resources/Wallet/, which git ignores. See SETUP.md.
enum WalletPass {
  static let passTypeIdentifier = "pass.dev.buildhybridai.emergency"
  static let teamIdentifier = "WGAA2WP5T4"

  /// What the front of the pass shows (readable on a locked phone). The rest goes on the back.
  enum Field: String, CaseIterable, Identifiable {
    // Front rows (the traveler's order): birth date · blood type, allergies · medicines, contact.
    case birthDate, bloodType, allergies, medicines, contact
    var id: String { rawValue }
    var title: String {
      switch self {
      case .birthDate: "Date of birth"
      case .bloodType: "Blood type"
      case .allergies: "Allergies"
      case .medicines: "Medicines"
      case .contact: "Emergency contact"
      }
    }
    static let defaultFront = Set(Field.allCases)
  }

  enum Failure: LocalizedError {
    case notSetUp, badCertificate(String), signing(String)
    var errorDescription: String? {
      switch self {
      case .notSetUp: "The Wallet pass isn't set up in this build yet (no pass certificate). See SETUP.md."
      case let .badCertificate(why): "The pass certificate couldn't be read: \(why)"
      case let .signing(why): "The pass couldn't be signed: \(why)"
      }
    }
  }

  // MARK: Pass

  /// The signed .pkpass for this card.
  @MainActor
  static func make(card: EmergencyCard, language: String, ambulance: String, front: Set<Field>) throws -> Data {
    let credentials = try Credentials.load()
    var files: [(String, Data)] = [("pass.json", try passJSON(card: card, language: language, ambulance: ambulance, front: front))]
    files += images()
    let manifest = try JSONSerialization.data(
      withJSONObject: Dictionary(uniqueKeysWithValues: files.map { ($0.0, sha1($0.1)) }), options: [.sortedKeys])
    files.append(("manifest.json", manifest))
    files.append(("signature", try CMS.signDetached(manifest, with: credentials)))
    return Zip.stored(files)
  }

  @MainActor
  static func passJSON(card: EmergencyCard, language: String, ambulance: String, front: Set<Field>) throws -> Data {
    // Front, like an event ticket (the traveler's pick): 119 and blood type small in the top
    // corner, the name big, then one item per row: allergies, medicines, contact. Wallet shows at
    // most three rows under the name on this style, and a value that wraps runs into the next
    // row, so each stays on one line; the back has everything in full.
    let code = String(language.prefix(2))
    let local = ICEText.local[code]
    let labels = EmergencyText.labels(for: language)
    func label(_ localWord: String?, _ en: String) -> String { localWord.map { "\($0) · \(en)" } ?? en }
    /// Cut to a display width (CJK characters count double), first line only.
    func brief(_ t: String, _ width: Int = 30) -> String {
      let one = t.components(separatedBy: .newlines).first ?? t
      var out = "", w = 0
      for ch in one {
        let cw = ch.unicodeScalars.first.map { $0.value >= 0x2E80 ? 2 : 1 } ?? 1
        if w + cw > width - 1 { return out.trimmingCharacters(in: .whitespaces) + "…" }
        out.append(ch); w += cw
      }
      return out
    }
    let rows = card.rows(language: language, localFirst: true)
    /// "ペニシリン、ピーナッツ / Penicillin, Peanuts", or just one side when they read the same.
    func both(_ i: Int) -> String {
      guard rows.indices.contains(i) else { return "" }
      let r = rows[i]
      let first = r.value.replacingOccurrences(of: "\n", with: "、")
      guard let other = r.valueOther, other != first else { return first }
      return "\(first) / \(other)"
    }
    var header: [[String: Any]] = [], primary: [[String: Any]] = [], secondary: [[String: Any]] = [], auxiliary: [[String: Any]] = []
    header.append(["key": "call", "label": local == nil ? "EMERGENCY" : "救急", "value": ambulance])
    let name = card.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
    primary.append(name.isEmpty
      ? ["key": "title", "label": "EMERGENCY MEDICAL CARD", "value": labels?.title ?? "Emergency medical card"]
      : ["key": "name", "label": label(local?["name"], "NAME"), "value": name])

    // Two items a row (one when the other is off or empty); a row with two gets half the width.
    var allergies: [String: Any]?, birth: [String: Any]?, medicines: [String: Any]?, blood: [String: Any]?, contact: [String: Any]?
    if front.contains(.allergies) {
      allergies = ["key": "allergies", "label": label(labels?.allergies, "ALLERGIES"), "value": both(0)]
    }
    if front.contains(.birthDate), let d = card.birthDate {
      let f = DateFormatter()
      f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
      f.timeZone = .current; f.dateFormat = "yyyy/MM/dd"
      birth = ["key": "birthDate", "label": label(local?["birth"], "BORN"), "value": f.string(from: d)]
    }
    if front.contains(.medicines) {
      let first = card.medicines.first.map { m in EmergencyText.local(m.text, language: language, card: card) ?? m.name }
      medicines = ["key": "medicines", "label": label(labels?.medicines, "MEDICINES"),
                   "value": first.map { $0 + (card.medicines.count > 1 ? " +\(card.medicines.count - 1)" : "") } ?? both(1)]
    }
    if front.contains(.bloodType), let b = card.bloodType {
      blood = ["key": "bloodType", "label": label(labels?.bloodType, "BLOOD"),
               "value": b + (code == "ja" ? " (\(b.dropLast())型)" : "")]
    }
    if front.contains(.contact), !card.contactName.isEmpty {
      let phone = card.contactPhone.trimmingCharacters(in: .whitespaces)
      contact = ["key": "contact", "label": label(labels?.contact, "CONTACT"),
                 "value": card.contactName + (phone.isEmpty ? "" : " (\(phone))")]
    }
    let rowsOnFront = [[birth, blood], [allergies, medicines], [contact]]
      .map { $0.compactMap { $0 } }.filter { !$0.isEmpty }
    for (i, row) in rowsOnFront.enumerated() {
      let width = row.count == 1 ? 30 : 13  // wider wrapped CJK onto a second line (iPhone SE is 375 pt)
      let fields = row.map { f -> [String: Any] in
        var f = f; f["value"] = brief(f["value"] as? String ?? "", width)
        if i > 0 { f["row"] = i - 1 }
        return f
      }
      if i == 0 { secondary = fields } else { auxiliary += fields }
    }

    // Back: the whole card, section by section like a paper ICE card, both languages.
    var back: [[String: Any]] = []
    for sec in card.iceSections(language: language, localFirst: false) {
      let body = sec.rows.map { r -> String in
        let label = [r.label, r.labelOther].filter { !$0.isEmpty }.joined(separator: " · ")
        let value = [r.value, r.valueOther].compactMap { $0 }.joined(separator: "\n")
        return label.isEmpty || label.allSatisfy(\.isNumber) ? value : "\(label): \(value)"
      }.joined(separator: "\n\n")
      back.append(["key": "ice-\(sec.id)", "label": "\(sec.title) · \(sec.titleOther)", "value": body,
                   "dataDetectorTypes": ["PKDataDetectorTypePhoneNumber"]])
    }
    back.append(["key": "number", "label": "Emergency number · 救急", "value": ambulance,
                 "dataDetectorTypes": ["PKDataDetectorTypePhoneNumber"]])
    back.append(["key": "about", "label": "Made by Travel Copilot",
                 "value": "From your emergency card on this iPhone. Common items use fixed translations, not AI. Add the pass again after you change the card."])

    let pass: [String: Any] = [
      "formatVersion": 1,
      // The whole card as text, for anyone who scans it with a phone camera (works offline).
      "barcodes": [["format": "PKBarcodeFormatQR", "message": qrText(card: card, language: language, ambulance: ambulance),
                    "messageEncoding": "utf-8"]],   // no caption: the code stands alone
      "passTypeIdentifier": passTypeIdentifier,
      "teamIdentifier": teamIdentifier,
      "serialNumber": "emergency-card",
      "organizationName": "Travel Copilot",
      "description": "Emergency medical card",
      "logoText": "Emergency card",
      "foregroundColor": "rgb(255, 255, 255)",
      "backgroundColor": "rgb(22, 107, 173)",
      "labelColor": "rgb(217, 235, 255)",
      "sharingProhibited": true,
      "eventTicket": ["headerFields": header, "primaryFields": primary, "secondaryFields": secondary,
                  "auxiliaryFields": auxiliary, "backFields": back],
    ]
    return try JSONSerialization.data(withJSONObject: pass, options: [.sortedKeys])
  }

  /// The QR code's text: the whole card in short English lines, one item a line, empty ones
  /// left out. Short text keeps the code coarse and quick to scan off a phone screen (the local
  /// words would triple its size); the back of the pass has both languages.
  @MainActor
  static func qrText(card: EmergencyCard, language: String, ambulance: String) -> String {
    func list(_ items: [String]) -> String { items.joined(separator: ", ") }
    func person(_ name: String, _ relation: String, _ phone: String) -> String {
      [name, relation.isEmpty ? "" : "(\(relation))", phone].filter { !$0.isEmpty }.joined(separator: " ")
    }
    let dob = card.birthDate.map { d -> String in
      let f = DateFormatter()
      f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
      f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"
      return f.string(from: d)
    }
    let address = card.homeAddress.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    let lines: [(String, String?)] = [
      ("Name", card.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)),
      ("DOB", dob),
      ("Blood", card.bloodType),
      ("Allergies", card.allergies.isEmpty ? "None" : list(card.allergies)),
      ("Meds", card.medicines.isEmpty ? "None" : list(card.medicines.map(\.text))),
      ("Conditions", card.conditions.isEmpty ? nil : list(card.conditions)),
      ("Surgeries", card.surgeries.isEmpty ? nil : list(card.surgeries)),
      ("Contact", card.contactName.isEmpty ? nil : person(card.contactName, card.contactRelation, card.contactPhone)),
      ("Contact 2", card.contact2Name.isEmpty ? nil : person(card.contact2Name, card.contact2Relation, card.contact2Phone)),
      ("Doctor", card.doctorName.isEmpty ? nil : person(card.doctorName, "", card.doctorPhone)),
      ("Insurance", card.insuranceProvider.isEmpty ? nil
        : [card.insuranceProvider, card.insurancePolicy, card.insurancePhone].filter { !$0.isEmpty }.joined(separator: " ")),
      ("Address", address),
      ("Phone", card.ownPhone),
    ]
    let body = lines.compactMap { label, value in (value ?? "").isEmpty ? nil : "\(label): \(value!)" }
    return (["EMERGENCY MEDICAL CARD · Call \(ambulance)"] + body).joined(separator: "\n")
  }

  /// icon (Lock Screen / notifications) and logo (top-left of the pass), drawn from the Star of Life.
  @MainActor
  static func images() -> [(String, Data)] {
    let star = UIImage(named: "StarOfLife")
    func draw(_ side: CGFloat, scale: CGFloat, background: UIColor?) -> Data {
      let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = background != nil
      return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { ctx in
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        if let background { background.setFill(); ctx.fill(rect) }
        else { UIColor.white.setFill(); UIBezierPath(ovalIn: rect).fill() }
        star?.draw(in: rect.insetBy(dx: side * 0.14, dy: side * 0.14))
      }
    }
    return [
      ("icon.png", draw(29, scale: 1, background: .white)), ("icon@2x.png", draw(29, scale: 2, background: .white)),
      ("icon@3x.png", draw(29, scale: 3, background: .white)),
      ("logo.png", draw(40, scale: 1, background: nil)), ("logo@2x.png", draw(40, scale: 2, background: nil)),
      ("logo@3x.png", draw(40, scale: 3, background: nil)),
    ]
  }

  static func sha1(_ d: Data) -> String { Insecure.SHA1.hash(data: d).map { String(format: "%02x", $0) }.joined() }

  // MARK: Credentials

  struct Credentials {
    let key: SecKey
    let certificate: Data      // DER
    let intermediate: Data     // Apple WWDR G4, DER

    static func load(bundle: Bundle = .main) throws -> Credentials {
      guard let p12 = bundle.url(forResource: "PassCertificate", withExtension: "p12").flatMap({ try? Data(contentsOf: $0) }),
            let wwdr = bundle.url(forResource: "AppleWWDRCAG4", withExtension: "cer").flatMap({ try? Data(contentsOf: $0) })
      else { throw Failure.notSetUp }
      let password = bundle.url(forResource: "PassCertificate", withExtension: "password")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return try load(p12: p12, password: password, intermediate: wwdr)
    }

    static func load(p12: Data, password: String, intermediate: Data) throws -> Credentials {
      var items: CFArray?
      let status = SecPKCS12Import(p12 as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &items)
      guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
            let anyIdentity = first[kSecImportItemIdentity as String]
      else { throw Failure.badCertificate(status == errSecAuthFailed ? "wrong password" : "OSStatus \(status)") }
      let identity = anyIdentity as! SecIdentity
      var cert: SecCertificate?, key: SecKey?
      SecIdentityCopyCertificate(identity, &cert)
      SecIdentityCopyPrivateKey(identity, &key)
      guard let cert, let key else { throw Failure.badCertificate("no certificate or key inside") }
      return Credentials(key: key, certificate: SecCertificateCopyData(cert) as Data, intermediate: intermediate)
    }
  }
}

// MARK: - CMS (PKCS #7) detached signature, DER-encoded

enum CMS {
  static func signDetached(_ content: Data, with c: WalletPass.Credentials, date: Date = .now) throws -> Data {
    guard let (issuer, serial) = DER.issuerAndSerial(c.certificate) else { throw WalletPass.Failure.signing("bad certificate") }
    let sha256 = DER.seq(DER.oid("2.16.840.1.101.3.4.2.1") + DER.null)
    let attrs = [
      DER.seq(DER.oid("1.2.840.113549.1.9.3") + DER.set(DER.oid("1.2.840.113549.1.7.1"))),       // contentType: data
      DER.seq(DER.oid("1.2.840.113549.1.9.5") + DER.set(DER.utcTime(date))),                     // signingTime
      DER.seq(DER.oid("1.2.840.113549.1.9.4") + DER.set(DER.octets(Data(SHA256.hash(data: content))))), // messageDigest
    ].sorted { $0.lexicographicallyPrecedes($1) }                                               // DER: SET OF is sorted
    let signedAttrs = attrs.reduce(Data(), +)
    var error: Unmanaged<CFError>?
    guard let sig = SecKeyCreateSignature(c.key, .rsaSignatureMessagePKCS1v15SHA256, DER.set(signedAttrs) as CFData, &error) as Data?
    else { throw WalletPass.Failure.signing(error?.takeRetainedValue().localizedDescription ?? "unknown") }
    let signerInfo = DER.seq(
      DER.int(1) + DER.seq(issuer + serial) + sha256 + DER.tag(0xA0, signedAttrs)
      + DER.seq(DER.oid("1.2.840.113549.1.1.1") + DER.null) + DER.octets(sig))
    let signedData = DER.seq(
      DER.int(1) + DER.set(sha256) + DER.seq(DER.oid("1.2.840.113549.1.7.1"))
      + DER.tag(0xA0, c.certificate + c.intermediate) + DER.set(signerInfo))
    return DER.seq(DER.oid("1.2.840.113549.1.7.2") + DER.tag(0xA0, signedData))
  }
}

enum DER {
  static func tag(_ t: UInt8, _ content: Data) -> Data {
    var d = Data([t]); let n = content.count
    if n < 0x80 { d.append(UInt8(n)) }
    else {
      var len = [UInt8](); var v = n
      while v > 0 { len.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
      d.append(0x80 | UInt8(len.count)); d.append(contentsOf: len)
    }
    return d + content
  }
  static func seq(_ c: Data) -> Data { tag(0x30, c) }
  static func set(_ c: Data) -> Data { tag(0x31, c) }
  static func octets(_ c: Data) -> Data { tag(0x04, c) }
  static var null: Data { Data([0x05, 0x00]) }
  static func int(_ v: UInt8) -> Data { tag(0x02, Data([v])) }
  static func utcTime(_ d: Date) -> Data {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyMMddHHmmss"
    return tag(0x17, Data((f.string(from: d) + "Z").utf8))
  }
  static func oid(_ s: String) -> Data {
    let p = s.split(separator: ".").compactMap { UInt64($0) }
    var out = Data([UInt8(p[0] * 40 + p[1])])
    for v in p.dropFirst(2) {
      var bytes = [UInt8(v & 0x7f)]; var x = v >> 7
      while x > 0 { bytes.insert(UInt8(x & 0x7f) | 0x80, at: 0); x >>= 7 }
      out.append(contentsOf: bytes)
    }
    return tag(0x06, out)
  }

  /// One TLV at `i`: (tag, start of content, end of element).
  static func read(_ d: [UInt8], _ i: Int) -> (tag: UInt8, body: Int, end: Int)? {
    guard i + 1 < d.count else { return nil }
    var len = Int(d[i + 1]), body = i + 2
    if len & 0x80 != 0 {
      let n = len & 0x7f; guard n > 0, n <= 4, i + 2 + n <= d.count else { return nil }
      len = 0; for k in 0..<n { len = len << 8 | Int(d[i + 2 + k]) }
      body = i + 2 + n
    }
    return body + len <= d.count ? (d[i], body, body + len) : nil
  }

  /// The issuer Name and serialNumber INTEGER (whole TLVs) of an X.509 certificate.
  static func issuerAndSerial(_ cert: Data) -> (Data, Data)? {
    let d = [UInt8](cert)
    guard let c = read(d, 0), let tbs = read(d, c.body) else { return nil }
    var i = tbs.body
    guard var e = read(d, i) else { return nil }
    if e.tag == 0xA0 { i = e.end; guard let n = read(d, i) else { return nil }; e = n }   // [0] version
    let serial = Data(d[i..<e.end])
    i = e.end; guard let alg = read(d, i) else { return nil }                          // signature algorithm
    i = alg.end; guard let issuer = read(d, i) else { return nil }
    return (Data(d[i..<issuer.end]), serial)
  }
}

// MARK: - Zip (stored, no compression), enough for a .pkpass

enum Zip {
  static func stored(_ files: [(String, Data)]) -> Data {
    var out = Data(), central = Data()
    func u16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
    func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    for (name, data) in files {
      let n = Data(name.utf8), crc = crc32(data), offset = UInt32(out.count)
      out += u32(0x04034b50) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0x21)
      out += u32(crc) + u32(UInt32(data.count)) + u32(UInt32(data.count)) + u16(n.count) + u16(0) + n + data
      central += u32(0x02014b50) + u16(20) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0x21)
      central += u32(crc) + u32(UInt32(data.count)) + u32(UInt32(data.count)) + u16(n.count) + u16(0) + u16(0)
      central += u16(0) + u16(0) + u32(0) + u32(offset) + n
    }
    let start = UInt32(out.count)
    out += central
    out += u32(0x06054b50) + u16(0) + u16(0) + u16(files.count) + u16(files.count)
    out += u32(UInt32(central.count)) + u32(start) + u16(0)
    return out
  }

  static func crc32(_ d: Data) -> UInt32 {
    var c: UInt32 = 0xFFFF_FFFF
    for b in d {
      c ^= UInt32(b)
      for _ in 0..<8 { c = (c >> 1) ^ (0xEDB8_8320 & (0 &- (c & 1))) }
    }
    return ~c
  }
}
