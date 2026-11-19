import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
import UIKit

/// Sign in with Google or Apple through Firebase Auth. The account gives the user an identity for
/// cloud planning (per-user limits) and a backup of the trip. Offline features never need it.
/// Note: Gemini runs on the app's Firebase project, not on the user's own Google AI subscription.
@MainActor
@Observable
final class AuthService {
  struct Account: Equatable { let name: String; let email: String; let provider: String }

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
    return Account(name: user.displayName ?? "", email: user.email ?? "", provider: provider)
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

  // MARK: Helpers

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  private static func randomNonce(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var bytes = [UInt8](repeating: 0, count: length)
    _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
    return String(bytes.map { charset[Int($0) % charset.count] })
  }

  private static func sha256(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
