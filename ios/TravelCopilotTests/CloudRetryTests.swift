import Foundation
import FirebaseAILogic
import Testing
@testable import TravelCopilot

struct CloudRetryTests {
  /// What the SDK's internal `BackendError` looks like once bridged to NSError.
  func backend(_ code: Int) -> NSError {
    NSError(domain: "com.google.firebase.firebaseai.BackendError", code: code)
  }

  struct Flaky: Error {}

  @Test func highDemandIsTransient() {
    #expect(CloudRetry.isTransient(backend(500)))
    #expect(CloudRetry.isTransient(backend(503)))
    #expect(CloudRetry.isTransient(GenerateContentError.internalError(underlying: backend(500))))
    #expect(CloudRetry.isTransient(URLError(.timedOut)))
  }

  @Test func otherErrorsAreNotRetried() {
    #expect(!CloudRetry.isTransient(backend(400)))
    #expect(!CloudRetry.isTransient(backend(429)))   // quota: retrying burns more
    #expect(!CloudRetry.isTransient(backend(403)))   // App Check rejected
    #expect(!CloudRetry.isTransient(URLError(.notConnectedToInternet)))
    #expect(!CloudRetry.isTransient(Flaky()))
  }

  @Test func retriesThenSucceeds() async throws {
    var calls = 0
    let (value, retries) = try await CloudRetry.run(delays: [.zero, .zero]) {
      calls += 1
      if calls < 3 { throw GenerateContentError.internalError(underlying: backend(500)) }
      return "ok"
    }
    #expect(value == "ok")
    #expect(retries == 2)
    #expect(calls == 3)
  }

  @Test func givesUpAfterThreeAttempts() async {
    var calls = 0
    await #expect(throws: (any Error).self) {
      _ = try await CloudRetry.run(delays: [.zero, .zero]) { () async throws -> String in
        calls += 1
        throw backend(503)
      }
    }
    #expect(calls == 3)
  }

  @Test func doesNotRetryPermanentErrors() async {
    var calls = 0
    await #expect(throws: (any Error).self) {
      _ = try await CloudRetry.run(delays: [.zero, .zero]) { () async throws -> String in
        calls += 1
        throw backend(400)
      }
    }
    #expect(calls == 1)
  }

  @Test func logNote() {
    #expect(CloudRetry.note(0) == "")
    #expect(CloudRetry.note(1) == " · retried once")
    #expect(CloudRetry.note(2) == " · retried 2×")
  }
}
