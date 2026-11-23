import Foundation
import Testing
import UIKit
@testable import TravelCopilot

struct PlanChatTests {
  @Test func bookingEmailsAreSpotted() {
    #expect(FileReader.looksLikeBooking("Your reservation is confirmed. Confirmation number: HSZ-48213. Check-in from 15:00"))
    #expect(!FileReader.looksLikeBooking("We loved the dawn fish market in Lisbon and the tile workshops."))
  }

  @Test func readsTextFiles() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID()).txt")
    try "Dawn fish markets and tram rides".write(to: url, atomically: true, encoding: .utf8)
    let r = FileReader.read(url)
    #expect(r?.text == "Dawn fish markets and tram rides")
    #expect(r?.pages == nil)
  }

  @Test func readsPDFTextAndPages() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("trip-\(UUID()).pdf")
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 300)).pdfData { ctx in
      for page in ["Lisbon tile workshops", "Copenhagen design shops"] {
        ctx.beginPage()
        (page as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
      }
    }
    try data.write(to: url)
    let r = FileReader.read(url)
    #expect(r?.pages == 2)
    #expect(r?.text.contains("tile workshops") == true)
  }
}
