import PassKit
import SwiftUI

/// "Add to Apple Wallet": choose what the front of the pass shows (it's readable on a locked
/// phone), then add it. The pass is made and signed on this iPhone.
struct WalletPassSheet: View {
  let card: EmergencyCard
  let language: String
  let ambulance: String
  @Environment(\.dismiss) private var dismiss
  @AppStorage("walletFront7") private var stored = WalletPass.Field.defaultFront.map(\.rawValue).sorted().joined(separator: ",")
  @State private var pass: PKPass?
  @State private var name = ""
  @Environment(AuthService.self) private var auth
  @State private var error: String?

  private var front: Set<WalletPass.Field> {
    Set(stored.split(separator: ",").compactMap { WalletPass.Field(rawValue: String($0)) })
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text("Anyone holding your phone can read the front of the pass, even when it's locked. Your address and conditions are on the back, and in the QR code. Turn off anything else you'd rather keep there.")
            .mta(.body1).foregroundStyle(MTA.text2)
          VStack(alignment: .leading, spacing: 6) {
            MTALabel("Name on the pass")
            TextField("Your name", text: $name).mta(.body1).textContentType(.name)
              .padding(14).overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MTA.border, lineWidth: 2) }
          }
          VStack(spacing: 0) {
            ForEach(Array(WalletPass.Field.allCases.enumerated()), id: \.element) { i, f in
              Toggle(isOn: binding(f)) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(f.title).mta(.body1).foregroundStyle(MTA.text)
                  if let v = preview(f) { Text(v).mta(.body2).foregroundStyle(MTA.text2).lineLimit(1) }
                }
              }
              .tint(MTA.onTrack)
              .padding(.horizontal, 14).padding(.vertical, 10)
              if i < WalletPass.Field.allCases.count - 1 { Rectangle().fill(MTA.subtle).frame(height: 1) }
            }
          }
          .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(MTA.border, lineWidth: 2) }
          Text("Off = on the back of the pass only. Add the pass again after you change the card.")
            .mta(.body2).foregroundStyle(MTA.text2)
          if let error { Text(error).mta(.body2).foregroundStyle(MTA.urgent) }
        }
        .mtaScreen().padding(.top, 8).padding(.bottom, 24)
      }
      .background(MTA.surface)
      .safeAreaInset(edge: .bottom) {
        AddPassButton { make() }
          .frame(height: 52).padding(.horizontal, MTA.margin).padding(.bottom, 8)
      }
      .onAppear { name = card.ownerName.isEmpty ? (auth.account?.name ?? "") : card.ownerName }
      .navigationTitle("Add to Apple Wallet")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel", systemImage: "xmark") { dismiss() } } }
      .sheet(item: Binding(get: { pass.map(PassItem.init) }, set: { if $0 == nil { pass = nil } })) { item in
        AddPassController(pass: item.pass) { pass = nil; dismiss() }.ignoresSafeArea()
      }
    }
  }

  private func binding(_ f: WalletPass.Field) -> Binding<Bool> {
    Binding(get: { front.contains(f) }, set: { on in
      var s = front; if on { s.insert(f) } else { s.remove(f) }
      stored = s.map(\.rawValue).sorted().joined(separator: ",")
    })
  }

  private func preview(_ f: WalletPass.Field) -> String? {
    switch f {
    case .birthDate: card.birthDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not set"
    case .bloodType: card.bloodType ?? "Not set"
    case .allergies: card.allergies.isEmpty ? "None" : card.allergies.joined(separator: ", ")
    case .medicines: card.medicines.isEmpty ? "None" : card.medicines.map(\.text).joined(separator: ", ")
    case .contact: card.contactName.isEmpty ? "Not set" : "\(card.contactName) · \(card.contactPhone)"
    }
  }

  private func make() {
    error = nil
    card.ownerName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      let data = try WalletPass.make(card: card, language: language, ambulance: ambulance, front: front)
      pass = try PKPass(data: data)
    } catch {
      self.error = error.localizedDescription
    }
  }
}

private struct PassItem: Identifiable { let pass: PKPass; var id: String { pass.serialNumber } }

/// Apple's black "Add to Apple Wallet" button.
struct AddPassButton: UIViewRepresentable {
  var action: () -> Void
  func makeUIView(context: Context) -> PKAddPassButton {
    let b = PKAddPassButton(addPassButtonStyle: .black)
    b.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
    return b
  }
  func updateUIView(_ b: PKAddPassButton, context: Context) { context.coordinator.action = action }
  func makeCoordinator() -> Coordinator { Coordinator(action: action) }
  final class Coordinator: NSObject {
    var action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func tap() { action() }
  }
}

/// The system sheet that shows the pass and adds it to Wallet.
struct AddPassController: UIViewControllerRepresentable {
  let pass: PKPass
  var onDone: () -> Void
  func makeUIViewController(context: Context) -> UIViewController {
    let vc = PKAddPassesViewController(pass: pass) ?? UIViewController()
    (vc as? PKAddPassesViewController)?.delegate = context.coordinator
    return vc
  }
  func updateUIViewController(_ vc: UIViewController, context: Context) {}
  func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }
  final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
    let onDone: () -> Void
    init(onDone: @escaping () -> Void) { self.onDone = onDone }
    func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) { onDone() }
  }
}
