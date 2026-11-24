import Foundation
import Testing
@testable import TravelCopilot

struct WalletPassTests {
  /// Folder with a throwaway self-signed certificate (test.p12, password "testpw", inter.cer), passed in
  /// with TEST_RUNNER_WALLET_FIXTURE=<folder> on the xcodebuild test command. Without it the signing test is skipped.
  static var fixture: URL? {
    ProcessInfo.processInfo.environment["WALLET_FIXTURE"].map { URL(fileURLWithPath: $0) }
  }

  @Test func zipCRC() {
    #expect(Zip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)   // the standard CRC-32 check value
  }

  @Test func derLengthsAndOIDs() {
    #expect(DER.oid("1.2.840.113549.1.7.2") == Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]))
    #expect(DER.tag(0x04, Data(count: 200)).prefix(3) == Data([0x04, 0x81, 0xC8]))
  }

  @MainActor @Test func passJSONRespectsTheFrontChoice() throws {
    let data = try WalletPass.passJSON(card: Self.sample(), language: "ja", ambulance: "119", front: [.medicines])
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let ticket = try #require(json["eventTicket"] as? [String: Any])
    let header = (ticket["headerFields"] as? [[String: Any]]) ?? []
    #expect(header.map { $0["key"] as? String } == ["call"])
    #expect(((ticket["secondaryFields"] as? [[String: Any]]) ?? []).map { $0["key"] as? String } == ["medicines"])
    #expect(((ticket["auxiliaryFields"] as? [[String: Any]]) ?? []).isEmpty)
    let back = (ticket["backFields"] as? [[String: Any]]) ?? []
    #expect(back.contains { ($0["key"] as? String) == "ice-personal" && (($0["value"] as? String) ?? "").contains("A+") })
    #expect(back.first?["key"] as? String == "ice-personal")
    #expect(json["passTypeIdentifier"] as? String == WalletPass.passTypeIdentifier)
    #expect((ticket["primaryFields"] as? [[String: Any]])?.first?["value"] as? String == "Alex Traveler")
  }

  /// Signs with the throwaway certificate and leaves the files next to it so openssl can verify them.
  @Test func signsWithAPKCS12Identity() throws {
    guard let dir = Self.fixture, let p12 = try? Data(contentsOf: dir.appendingPathComponent("test.p12")),
          let inter = try? Data(contentsOf: dir.appendingPathComponent("inter.cer")) else { return }
    let creds = try WalletPass.Credentials.load(p12: p12, password: "testpw", intermediate: inter)
    let manifest = Data(#"{"pass.json":"abc"}"#.utf8)
    let sig = try CMS.signDetached(manifest, with: creds)
    #expect(sig.first == 0x30)
    try manifest.write(to: dir.appendingPathComponent("manifest.json"))
    try sig.write(to: dir.appendingPathComponent("signature"))
    try Zip.stored([("manifest.json", manifest), ("signature", sig)]).write(to: dir.appendingPathComponent("test.zip"))
  }

  @MainActor static func sample() -> EmergencyCard {
    let card = EmergencyCard()
    card.ownerName = "Alex Traveler"; card.bloodType = "A+"; card.homeAddress = "1 Example St\nSpringfield"
    card.birthDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2000, month: 1, day: 2))
    card.allergies = ["Penicillin", "Peanuts"]; card.conditions = ["Asthma"]
    card.medicines = [EmergencyMedicine(name: "Ibuprofen 200 mg", schedule: "twice a day")]
    card.contactName = "Jamie Lee"; card.contactPhone = "+1 415 555 0134"; card.contactRelation = "Partner"
    return card
  }

  /// The traveler's order: birth date · blood type, allergies · medicines, then the contact
  /// with their phone number.
  @MainActor @Test func twoItemsPerRowUnderTheName() throws {
    let data = try WalletPass.passJSON(card: Self.sample(), language: "ja", ambulance: "119", front: WalletPass.Field.defaultFront)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let ticket = try #require(json["eventTicket"] as? [String: Any])
    let header = try #require(ticket["headerFields"] as? [[String: Any]])
    #expect(header.map { $0["key"] as? String } == ["call"])
    let second = try #require(ticket["secondaryFields"] as? [[String: Any]])
    let aux = try #require(ticket["auxiliaryFields"] as? [[String: Any]])
    #expect(second.map { $0["key"] as? String } == ["birthDate", "bloodType"])
    #expect(aux.map { $0["key"] as? String } == ["allergies", "medicines", "contact"])
    #expect(aux.map { $0["row"] as? Int } == [0, 0, 1])
    #expect(second[0]["value"] as? String == "2000/01/02")
    #expect(second[1]["value"] as? String == "A+ (A型)")
    #expect(aux[2]["value"] as? String == "Jamie Lee (+1 415 555 0134)")
  }

  /// The QR code carries what isn't on the front: birth date, address, conditions, phone numbers.
  @MainActor @Test func qrCodeHasTheWholeCard() throws {
    let data = try WalletPass.passJSON(card: Self.sample(), language: "ja", ambulance: "119", front: WalletPass.Field.defaultFront)
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let code = try #require((json["barcodes"] as? [[String: Any]])?.first)
    #expect(code["format"] as? String == "PKBarcodeFormatQR")
    #expect(code["altText"] == nil)   // the code stands alone in its box
    let text = try #require(code["message"] as? String)
    for part in ["1 Example St", "2000", "Asthma", "+1 415 555 0134", "Penicillin", "119"] { #expect(text.contains(part), "\(part)") }
    #expect(text.utf8.count <= 400)   // short, so the code stays coarse and easy to scan
  }

  /// Writes a signed sample pass to PASS_PREVIEW (a folder) to look at in the Simulator.
  @MainActor @Test func writesAPreviewPass() throws {
    guard let dir = ProcessInfo.processInfo.environment["PASS_PREVIEW"] else { return }
    let data = try WalletPass.make(card: Self.sample(), language: "ja", ambulance: "119", front: WalletPass.Field.defaultFront)
    try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("preview.pkpass"))
  }
}
