import AuthenticationServices
import CryptoKit
@preconcurrency import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
import UIKit

/// Sign in with Google or Apple through Firebase Auth. The account gives the user an identity for
/// cloud planning (per-user limits). Nothing from the trip is uploaded. Offline features never need it.
/// Note: Gemini runs on the app's Firebase project, not on the user's own Google AI subscription.
@MainActor
@Observable
final class AuthService {
  struct Account: Equatable { let name: String; let email: String; let provider: String; var uid: String = "" }

  private(set) var account: Account?
  var error: String?
  var busy = false
  private var currentNonce: String?
  private var listener: AuthStateDidChangeListenerHandle?

  var isSignedIn: Bool { account != nil }

  init() {
    guard TravelCopilotApp.firebaseConfigured else { return }
    listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
      MainActor.assumeIsolated { self?.account = user.map(Self.account) }
    }
  }

  private static func account(_ user: User) -> Account {
    let provider = user.providerData.first?.providerID == "apple.com" ? "Apple" : "Google"
    return Account(name: user.displayName ?? "", email: user.email ?? "", provider: provider, uid: user.uid)
  }

  // MARK: Google

  func signInWithGoogle() async {
    error = nil
    guard TravelCopilotApp.firebaseConfigured else { error = ModelRouter.NotConfigured().errorDescription; return }
    guard let clientID = FirebaseApp.app()?.options.clientID else {
      error = "Google sign-in isn't turned on yet. In the Firebase console, open Authentication → Sign-in method, enable Google, then download GoogleService-Info.plist again."
      return
    }
    guard let presenter = Self.topViewController() else { return }
    busy = true; defer { busy = false }
    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    do {
      let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
      guard let idToken = result.user.idToken?.tokenString else { error = "Google didn't return a sign-in token."; return }
      let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
      try await Auth.auth().signIn(with: credential)
    } catch let e as GIDSignInError where e.code == .canceled {
      // User closed the sheet.
    } catch {
      self.error = error.localizedDescription
    }
  }

  // MARK: Apple

  func prepare(_ request: ASAuthorizationAppleIDRequest) {
    let nonce = Self.randomNonce()
    currentNonce = nonce
    request.requestedScopes = [.fullName, .email]
    request.nonce = Self.sha256(nonce)
  }

  func complete(_ result: Result<ASAuthorization, any Error>) async {
    error = nil
    switch result {
    case let .failure(e):
      if (e as? ASAuthorizationError)?.code != .canceled { error = e.localizedDescription }
    case let .success(auth):
      guard TravelCopilotApp.firebaseConfigured else { error = ModelRouter.NotConfigured().errorDescription; return }
      guard let apple = auth.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = apple.identityToken, let token = String(data: tokenData, encoding: .utf8),
            let nonce = currentNonce else { error = "Apple didn't return a sign-in token."; return }
      busy = true; defer { busy = false }
      let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: apple.fullName)
      do { try await Auth.auth().signIn(with: credential) } catch { self.error = error.localizedDescription }
    }
  }

  func signOut() {
    GIDSignIn.sharedInstance.signOut()
    try? Auth.auth().signOut()
  }

  // MARK: Delete account

  /// Deletes the Firebase account. Firebase needs a fresh sign-in first, so this shows the
  /// Google or Apple sheet again. For Apple, the app's Sign in with Apple token is also revoked,
  /// as Apple requires. The trip on this iPhone is not affected (it was never in the account).
  /// Returns true when the account is gone.
  @discardableResult
  func deleteAccount() async -> Bool {
    error = nil
    guard let user = Auth.auth().currentUser else { return true }
    busy = true; defer { busy = false }
    do {
      if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
        let apple = try await AppleReauth.run()
        guard let codeData = apple.authorizationCode, let code = String(data: codeData, encoding: .utf8),
              let tokenData = apple.identityToken, let token = String(data: tokenData, encoding: .utf8)
        else { error = "Apple didn't return a sign-in token."; return false }
        try await user.reauthenticate(with: OAuthProvider.appleCredential(
          withIDToken: token, rawNonce: AppleReauth.lastNonce, fullName: nil))
        try await Auth.auth().revokeToken(withAuthorizationCode: code)
      } else {
        guard let presenter = Self.topViewController() else { return false }
        if let clientID = FirebaseApp.app()?.options.clientID {
          GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        guard let idToken = result.user.idToken?.tokenString else { error = "Google didn't return a sign-in token."; return false }
        try await user.reauthenticate(with: GoogleAuthProvider.credential(
          withIDToken: idToken, accessToken: result.user.accessToken.tokenString))
        try? await GIDSignIn.sharedInstance.disconnect()
      }
      try await user.delete()
      GIDSignIn.sharedInstance.signOut()
      try? Auth.auth().signOut()
      return true
    } catch let e as GIDSignInError where e.code == .canceled {
      return false
    } catch let e as ASAuthorizationError where e.code == .canceled {
      return false
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  // MARK: Helpers

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  static func randomNonce(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var bytes = [UInt8](repeating: 0, count: length)
    _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
    return String(bytes.map { charset[Int($0) % charset.count] })
  }

  static func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

/// Runs Sign in with Apple once more, outside SwiftUI, to get a fresh credential and
/// authorization code for deleting the account.
@MainActor
private final class AppleReauth: NSObject, ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding {
  private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, any Error>?
  private static var current: AppleReauth?
  static var lastNonce = ""

  static func run() async throws -> ASAuthorizationAppleIDCredential {
    let nonce = AuthService.randomNonce()
    lastNonce = nonce
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.nonce = AuthService.sha256(nonce)
    let reauth = AppleReauth()
    current = reauth
    defer { current = nil }
    return try await withCheckedThrowingContinuation { c in
      reauth.continuation = c
      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = reauth
      controller.presentationContextProvider = reauth
      controller.performRequests()
    }
  }

  nonisolated func authorizationController(controller: ASAuthorizationController,
                                           didCompleteWithAuthorization authorization: ASAuthorization) {
    let credential = authorization.credential as? ASAuthorizationAppleIDCredential
    MainActor.assumeIsolated {
      if let credential { continuation?.resume(returning: credential) }
      else { continuation?.resume(throwing: ASAuthorizationError(.failed)) }
      continuation = nil
    }
  }

  nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
    MainActor.assumeIsolated {
      continuation?.resume(throwing: error)
      continuation = nil
    }
  }

  nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
      return scene?.keyWindow ?? ASPresentationAnchor()
    }
  }
}
