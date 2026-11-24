import ContactsUI
import SwiftData
import SwiftUI

/// Sets up the emergency card as a short quiz (Figma: Emergency info card · flow, A3 and B1–B6):
/// Health permission first, then one question per screen, then Review. Saving translates the
/// traveler's own words once (cloud, checked by code) and opens the card.
struct EmergencySetupView: View {
  var onDone: (EmergencyCard) -> Void = { _ in }
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Environment(AIService.self) private var ai
  @Query private var cards: [EmergencyCard]
  @Query private var packs: [DestinationPack]

  enum Step: Int, CaseIterable { case health, blood, medicines, allergies, conditions, contact, details, review }
  @State private var step: Step = EmergencyHealth.isAvailable ? .health : .blood
  @State private var readingHealth = false
  @State private var bloodType: String?
  @State private var bloodFromHealth = false
  /// Tried Health but it gave no blood type (not set there, or the toggle was left off).
  @State private var healthGaveNoBlood = false
  @Environment(\.openURL) private var openHealthURL
  @State private var medicines: [EmergencyMedicine] = []
  @State private var medicineOn: Set<String> = []
  @State private var allergies: Set<String> = []
  @State private var conditions: Set<String> = []
  @State private var otherAllergy = ""
  @State private var otherCondition = ""
  @State private var contactName = ""
  @State private var contactPhone = ""
  @State private var relation = "Partner"
  @State private var addingMedicine = false
  @State private var newMedicine = ""
  @State private var newSchedule = ""
  @State private var pickingContact = false
  @State private var saving = false
  // "More details" (the rest of a paper ICE card), all optional.
  @State private var ownerName = ""
  @State private var birthDate: Date?
  @State private var ownPhone = ""
  @State private var homeAddress = ""
  @State private var surgeries: [String] = []
  @State private var newSurgery = ""
  @State private var contact2Name = ""
  @State private var contact2Phone = ""
  @State private var contact2Relation = "Parent"
  @State private var pickingContact2 = false
  @State private var doctorName = ""
  @State private var doctorPhone = ""
  @State private var insuranceProvider = ""
  @State private var insurancePolicy = ""
  @State private var insurancePhone = ""
  @State private var loaded = false

  private var pack: DestinationPack? { packs.first }
  private var language: String { pack?.languageCode ?? "ja" }
  private var languageName: String { pack?.languageName ?? "Japanese" }

  var body: some View {
    VStack(spacing: 0) {
      if step != .health { topBar }
      ScrollView {
        VStack(alignment: .leading, spacing: 14) { content }
          .padding(.horizontal, 16).padding(.top, step == .health ? 24 : 8).padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
      bottomButtons
    }
    .background(MTA.surface)
    .tint(MTA.emergency)
    .sheet(isPresented: $pickingContact) {
      ContactPicker { name, phone in contactName = name; contactPhone = phone }.ignoresSafeArea()
    }
    .sheet(isPresented: $pickingContact2) {
      ContactPicker { name, phone in contact2Name = name; contact2Phone = phone }.ignoresSafeArea()
    }
    .task {
      if !loaded { loadExisting(); loaded = true }
      #if DEBUG
        // `-emergencyStep 3`: jump to a quiz step (simulator checks), with a few answers filled in.
        if let n = Int(UserDefaults.standard.string(forKey: "emergencyStep") ?? ""), let s = Step(rawValue: n) {
          bloodType = bloodType ?? "A+"; allergies.formUnion(["Penicillin", "Peanuts"]); conditions.insert("Asthma")
          if medicines.isEmpty { medicines = [EmergencyMedicine(name: "Ibuprofen 200 mg", schedule: "twice a day", fromHealth: true)]; medicineOn = [medicines[0].text] }
          if contactName.isEmpty { contactName = "Jamie Lee"; contactPhone = "+1 415 555 0134" }
          step = s
        }
      #endif
    }
  }

  // MARK: - Chrome

  private var topBar: some View {
    HStack(spacing: 14) {
      Button { back() } label: {
        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(MTA.text)
          .frame(width: 44, height: 44).background(MTA.raised, in: .circle)
      }
      .accessibilityLabel("Back")
      if step == .details {
        Text("Optional").mta(.subheadNormal).foregroundStyle(MTA.text).frame(maxWidth: .infinity)
        Button("Skip") { next() }.font(.system(size: 17, weight: .medium)).foregroundStyle(MTA.emergency)
      } else if step != .review {
        HStack(spacing: 6) {
          ForEach(1...5, id: \.self) { i in
            Capsule().fill(i <= step.rawValue ? MTA.emergency : Color.gray.opacity(0.3)).frame(height: 6)
          }
        }
        .accessibilityElement().accessibilityLabel("Step \(step.rawValue) of 5")
        Button("Skip") { next() }.font(.system(size: 17, weight: .medium)).foregroundStyle(MTA.emergency)
      } else {
        Text("Review").mta(.subheadNormal).foregroundStyle(MTA.text).frame(maxWidth: .infinity)
        Color.clear.frame(width: 44, height: 44)
      }
    }
    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
  }

  @ViewBuilder
  private var content: some View {
    switch step {
    case .health: healthStep
    case .blood: bloodStep
    case .medicines: medicinesStep
    case .allergies: allergiesStep
    case .conditions: conditionsStep
    case .contact: contactStep
    case .details: detailsStep
    case .review: reviewStep
    }
  }

  private func question(_ n: Int, _ q: String, _ helper: String?) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      MTALabel("Emergency card · step \(n) of 5", color: MTA.emergency)
      Text(q).font(.system(size: 30, weight: .bold)).foregroundStyle(MTA.text).fixedSize(horizontal: false, vertical: true)
      if let helper { Text(helper).mta(.body2).foregroundStyle(MTA.text2) }
    }
  }

  @ViewBuilder
  private var bottomButtons: some View {
    VStack(spacing: 10) {
      switch step {
      case .health:
        Button { Task { await useHealth() } } label: {
          HStack(spacing: 8) { if readingHealth { ProgressView().tint(.white) }; Text(readingHealth ? "Reading Health…" : "Use Health data") }
        }
        .buttonStyle(EmergencyButton(primary: true)).disabled(readingHealth)
        Button("Answer myself") { step = .blood }.buttonStyle(EmergencyButton(primary: false))
        Button("Not now") { dismiss() }.font(.system(size: 15, weight: .medium)).foregroundStyle(MTA.text2)
      case .contact:
        Button("Next") { next() }.buttonStyle(EmergencyButton(primary: true))
      case .details:
        Button("Review my card") { step = .review }.buttonStyle(EmergencyButton(primary: true))
      case .review:
        Button { Task { await save() } } label: {
          HStack(spacing: 8) { if saving { ProgressView().tint(.white) }; Text(saving ? "Saving…" : "Save card") }
        }
        .buttonStyle(EmergencyButton(primary: true)).disabled(saving)
      default:
        Button("Next") { next() }.buttonStyle(EmergencyButton(primary: true))
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
  }

  // MARK: - Steps

  private var healthStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        Image(systemName: "heart.fill").font(.system(size: 30)).foregroundStyle(.pink)
          .frame(width: 60, height: 60).background(.white, in: .rect(cornerRadius: 14))
          .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.gray.opacity(0.3)) }
        Image(systemName: "arrow.right").foregroundStyle(MTA.text2)
        Image("StarOfLifeOnColor").resizable().scaledToFit().padding(6).frame(width: 60, height: 60)
          .background(MTA.emergency, in: .rect(cornerRadius: 14))
      }
      .accessibilityHidden(true)
      Text("Start from your Health app?").font(.system(size: 30, weight: .bold)).foregroundStyle(MTA.text)
      Text("Travel Copilot can read two things to answer the first questions for you:").mta(.body1).foregroundStyle(MTA.text)
      ForEach([("Blood type", "From your Health details"), ("Medications", "From Health → Medications · you choose which")], id: \.0) { t in
        HStack(spacing: 12) {
          Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(MTA.onTrack)
          VStack(alignment: .leading, spacing: 2) { Text(t.0).mta(.subheadNormal); Text(t.1).mta(.body2).foregroundStyle(MTA.text2) }
          Spacer()
        }
        .padding(14).background(MTA.raised, in: .rect(cornerRadius: 14))
      }
      Text("Your Medical ID (allergies, conditions, contacts) stays private to iOS, so you'll answer those in a few taps.")
        .mta(.body2).foregroundStyle(MTA.text2)
      Text("Read only, saved on this iPhone only. Change it any time in Settings → Health → Data Access.")
        .mta(.body2).foregroundStyle(MTA.text2)
    }
  }

  private var bloodStep: some View {
    VStack(alignment: .leading, spacing: 14) {
      question(1, "What's your blood type?", bloodFromHealth ? "Filled in from Health. Change it if it's wrong." : nil)
      if healthGaveNoBlood {
        VStack(alignment: .leading, spacing: 8) {
          Text("Health didn't share a blood type. Either it isn't in Health → Health Details, or Blood Type was left off when you allowed access.")
            .mta(.body2).foregroundStyle(MTA.text2)
          Text("To fix: Settings → Health → Data Access & Devices → Travel Copilot → turn on Blood Type. Or just tap yours below.")
            .mta(.body2).foregroundStyle(MTA.text2)
          Button("Open Health") { if let u = URL(string: "x-apple-health://") { openHealthURL(u) } }
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(MTA.emergency)
        }
        .padding(12).background(MTA.raised, in: .rect(cornerRadius: 12))
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
        ForEach(["A+", "A−", "B+", "B−", "AB+", "AB−", "O+", "O−"], id: \.self) { t in
          Button { bloodType = t } label: {
            Text(t).font(.system(size: 20, weight: .bold)).foregroundStyle(bloodType == t ? .white : MTA.text)
              .frame(maxWidth: .infinity, minHeight: 56)
              .background(bloodType == t ? MTA.emergency : MTA.raised, in: .rect(cornerRadius: 14))
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(bloodType == t ? .isSelected : [])
        }
      }
      option("I don't know", selected: bloodType == nil) { bloodType = nil }
    }
  }

  private var medicinesStep: some View {
    VStack(alignment: .leading, spacing: 12) {
      question(2, "Do you take any medicines?", medicines.contains(where: \.fromHealth) ? "From Health → Medications. Untick any you're not taking on this trip." : nil)
      ForEach(medicines, id: \.self) { m in
        option(m.name, sub: m.schedule.isEmpty ? nil : m.schedule, selected: medicineOn.contains(m.text), health: m.fromHealth) {
          if medicineOn.contains(m.text) { medicineOn.remove(m.text) } else { medicineOn.insert(m.text) }
        }
      }
      if addingMedicine {
        VStack(spacing: 8) {
          TextField("Name and dose, e.g. Insulin 10 units", text: $newMedicine).textFieldStyle(.roundedBorder)
          TextField("How often, e.g. twice a day", text: $newSchedule).textFieldStyle(.roundedBorder)
          Button("Add") {
            let m = EmergencyMedicine(name: newMedicine.trimmingCharacters(in: .whitespaces), schedule: newSchedule.trimmingCharacters(in: .whitespaces))
            guard !m.name.isEmpty else { return }
            medicines.append(m); medicineOn.insert(m.text); newMedicine = ""; newSchedule = ""; addingMedicine = false
          }
          .buttonStyle(EmergencyButton(primary: false))
        }
      } else {
        option("＋ Add a medicine", sub: "Name and dose, e.g. “Insulin 10 units”", selected: false) { addingMedicine = true }
      }
      option("I don't take any", selected: medicineOn.isEmpty) { medicineOn = [] }
    }
  }

  private var allergiesStep: some View {
    VStack(alignment: .leading, spacing: 14) {
      question(3, "Any allergies?", "Tap all that apply.")
      chips(EmergencyText.commonAllergies + allergies.filter { !EmergencyText.commonAllergies.contains($0) }.sorted(), selected: $allergies)
      otherField("Something else? Type it", text: $otherAllergy) { allergies.insert($0) }
      option("No allergies", selected: allergies.isEmpty) { allergies = [] }
    }
  }

  private var conditionsStep: some View {
    VStack(alignment: .leading, spacing: 14) {
      question(4, "Anything a doctor should know?", "Long-term conditions, or if you're pregnant.")
      chips(EmergencyText.commonConditions + conditions.filter { !EmergencyText.commonConditions.contains($0) }.sorted(), selected: $conditions)
      otherField("Something else? Type it", text: $otherCondition) { conditions.insert($0) }
      option("Nothing to add", selected: conditions.isEmpty) { conditions = [] }
    }
  }

  private var contactStep: some View {
    VStack(alignment: .leading, spacing: 14) {
      question(5, "Who should we call?", "Someone at home who can speak for you.")
      if !contactName.isEmpty {
        HStack(spacing: 12) {
          Image(systemName: "person.crop.circle.fill").font(.system(size: 40)).foregroundStyle(MTA.emergency.opacity(0.5))
          VStack(alignment: .leading, spacing: 2) { Text(contactName).mta(.subheadNormal); Text(contactPhone).mta(.body2).foregroundStyle(MTA.text2) }
          Spacer()
        }
        .padding(14).background(MTA.emergency.opacity(0.1), in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(MTA.emergency, lineWidth: 2) }
        MTALabel("Who are they to you?")
        FlowLayout(spacing: 8) {
          ForEach(EmergencyText.relations, id: \.self) { r in pill(r, selected: relation == r) { relation = r } }
        }
      }
      option(contactName.isEmpty ? "Pick from Contacts" : "Pick another from Contacts", selected: false) { pickingContact = true }
    }
  }

  private var detailsStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        MTALabel("Emergency card · optional", color: MTA.emergency)
        Text("A few more details?").font(.system(size: 30, weight: .bold)).foregroundStyle(MTA.text)
        Text("Like a paper ICE card. All optional and kept on this iPhone. On the Wallet pass these go on the back only.")
          .mta(.body2).foregroundStyle(MTA.text2)
      }
      detailGroup("About you") {
        field("Your name", $ownerName, .name)
        if let b = birthDate {
          HStack {
            DatePicker("Date of birth", selection: Binding(get: { b }, set: { birthDate = $0 }), in: ...Date.now, displayedComponents: .date)
            Button { birthDate = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(MTA.text2) }
              .accessibilityLabel("Remove date of birth")
          }
          .padding(.horizontal, 16).padding(.vertical, 8).background(MTA.raised, in: .rect(cornerRadius: 12))
        } else {
          Button { birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now) } label: {
            Label("Add date of birth", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 16).padding(.vertical, 14).background(MTA.raised, in: .rect(cornerRadius: 12))
          }
          .buttonStyle(.plain).foregroundStyle(MTA.emergency)
        }
        field("Your phone", $ownPhone, .telephoneNumber, keyboard: .phonePad)
        field("Home address", $homeAddress, .fullStreetAddress)
      }
      detailGroup("Recent surgeries") {
        ForEach(surgeries, id: \.self) { sgy in
          HStack { Text(sgy).mta(.body1); Spacer()
            Button { surgeries.removeAll { $0 == sgy } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(MTA.text2) }
              .accessibilityLabel("Remove \(sgy)") }
            .padding(.horizontal, 16).padding(.vertical, 12).background(MTA.raised, in: .rect(cornerRadius: 12))
        }
        TextField("e.g. Appendectomy (2021)", text: $newSurgery).submitLabel(.done)
          .onSubmit { let t = newSurgery.trimmingCharacters(in: .whitespaces); if !t.isEmpty { surgeries.append(t); newSurgery = "" } }
          .padding(.horizontal, 16).padding(.vertical, 14).background(MTA.raised, in: .rect(cornerRadius: 12))
      }
      detailGroup("Second emergency contact") {
        if contact2Name.isEmpty {
          option("Pick from Contacts", selected: false) { pickingContact2 = true }
        } else {
          field("Name", $contact2Name, .name)
          field("Phone", $contact2Phone, .telephoneNumber, keyboard: .phonePad)
          FlowLayout(spacing: 8) {
            ForEach(EmergencyText.relations, id: \.self) { r in pill(r, selected: contact2Relation == r) { contact2Relation = r } }
          }
        }
      }
      detailGroup("Primary doctor") {
        field("Name and clinic", $doctorName, nil)
        field("Phone", $doctorPhone, .telephoneNumber, keyboard: .phonePad)
      }
      detailGroup("Travel insurance") {
        field("Provider", $insuranceProvider, .organizationName)
        field("Policy number", $insurancePolicy, nil)
        field("Emergency assistance phone", $insurancePhone, .telephoneNumber, keyboard: .phonePad)
      }
    }
  }

  private func detailGroup<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 8) { MTALabel(title); content() }
  }

  private func field(_ prompt: String, _ text: Binding<String>, _ type: UITextContentType?, keyboard: UIKeyboardType = .default) -> some View {
    TextField(prompt, text: text).textContentType(type).keyboardType(keyboard)
      .padding(.horizontal, 16).padding(.vertical, 14).background(MTA.raised, in: .rect(cornerRadius: 12))
  }

  private var detailsSummary: String {
    var parts: [String] = []
    if !ownerName.isEmpty { parts.append(ownerName) }
    if let b = birthDate { parts.append("Born \(b.formatted(date: .abbreviated, time: .omitted))") }
    if !surgeries.isEmpty { parts.append("\(surgeries.count) surger\(surgeries.count == 1 ? "y" : "ies")") }
    if !contact2Name.isEmpty { parts.append("2nd contact: \(contact2Name)") }
    if !doctorName.isEmpty { parts.append("Doctor: \(doctorName)") }
    if !insuranceProvider.isEmpty { parts.append("Insurance: \(insuranceProvider)") }
    return parts.isEmpty ? "None" : parts.joined(separator: "\n")
  }

  private var reviewStep: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Check your card").font(.system(size: 30, weight: .bold)).foregroundStyle(MTA.text)
      reviewRow("Blood type", bloodType ?? "Don't know", .blood)
      reviewRow("Medicines", chosenMedicines.isEmpty ? "None" : chosenMedicines.map(\.text).joined(separator: "\n"), .medicines)
      reviewRow("Allergies", allergies.isEmpty ? "None" : allergies.sorted().joined(separator: ", "), .allergies)
      reviewRow("Conditions", conditions.isEmpty ? "None" : conditions.sorted().joined(separator: ", "), .conditions)
      reviewRow("Emergency contact", contactName.isEmpty ? "None" : "\(contactName) · \(relation.lowercased()) · \(contactPhone)", .contact)
      reviewRow("More details", detailsSummary, .details)
      VStack(alignment: .leading, spacing: 4) {
        MTALabel("\(languageName) on save", color: MTA.onTrack)
        Text("Labels and common items are pre-translated. Anything you typed is translated once while online; medicine names and numbers are checked by code.")
          .mta(.body2).foregroundStyle(MTA.text)
      }
      .padding(14).overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(MTA.onTrack, lineWidth: 1.5) }
      Text("Saved on this iPhone only.").mta(.body2).foregroundStyle(MTA.text2)
    }
  }

  // MARK: - Small pieces

  private func option(_ title: String, sub: String? = nil, selected: Bool, health: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.system(size: 17, weight: selected ? .semibold : .medium)).foregroundStyle(MTA.text)
          if let sub { Text(sub).mta(.body2).foregroundStyle(MTA.text2) }
        }
        Spacer()
        if health { Text("HEALTH").font(.system(size: 9, weight: .bold)).foregroundStyle(.pink).padding(.horizontal, 6).padding(.vertical, 3).overlay { Capsule().strokeBorder(.pink) } }
        Image(systemName: selected ? "checkmark.square.fill" : "square").font(.system(size: 22)).foregroundStyle(selected ? MTA.emergency : Color.gray.opacity(0.5))
      }
      .padding(.horizontal, 16).padding(.vertical, 14)
      .background(selected ? MTA.emergency.opacity(0.1) : MTA.raised, in: .rect(cornerRadius: 14))
      .overlay { if selected { RoundedRectangle(cornerRadius: 14).strokeBorder(MTA.emergency, lineWidth: 2) } }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func pill(_ t: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(t).font(.system(size: 15, weight: .medium)).foregroundStyle(selected ? .white : MTA.text)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(selected ? MTA.emergency : Color.clear, in: .capsule)
        .overlay { Capsule().strokeBorder(selected ? MTA.emergency : Color.gray.opacity(0.35), lineWidth: 1.5) }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func chips(_ list: [String], selected: Binding<Set<String>>) -> some View {
    FlowLayout(spacing: 8) {
      ForEach(list, id: \.self) { t in
        pill(t, selected: selected.wrappedValue.contains(t)) {
          if selected.wrappedValue.contains(t) { selected.wrappedValue.remove(t) } else { selected.wrappedValue.insert(t) }
        }
      }
    }
  }

  private func otherField(_ prompt: String, text: Binding<String>, add: @escaping (String) -> Void) -> some View {
    TextField(prompt, text: text)
      .submitLabel(.done)
      .onSubmit {
        let t = text.wrappedValue.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { add(t); text.wrappedValue = "" }
      }
      .padding(.horizontal, 16).padding(.vertical, 14)
      .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.gray.opacity(0.35), lineWidth: 1.5) }
  }

  private func reviewRow(_ label: String, _ value: String, _ s: Step) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack { MTALabel(label); Spacer(); Button("Edit") { step = s }.font(.system(size: 13, weight: .medium)).foregroundStyle(MTA.emergency) }
      Text(value).mta(.body1).foregroundStyle(MTA.text).fixedSize(horizontal: false, vertical: true)
    }
    .padding(14).background(MTA.raised, in: .rect(cornerRadius: 14))
  }

  // MARK: - Logic

  private var chosenMedicines: [EmergencyMedicine] { medicines.filter { medicineOn.contains($0.text) } }

  private func next() {
    if let n = Step(rawValue: step.rawValue + 1) { withAnimation(.snappy) { step = n } }
  }

  private func back() {
    switch step {
    case .health: dismiss()
    case .blood: if EmergencyHealth.isAvailable { withAnimation(.snappy) { step = .health } } else { dismiss() }
    default: if let p = Step(rawValue: step.rawValue - 1) { withAnimation(.snappy) { step = p } }
    }
  }

  private func useHealth() async {
    readingHealth = true
    defer { readingHealth = false }
    let found = await EmergencyHealth.read()
    if let t = found.bloodType { bloodType = t; bloodFromHealth = true } else { healthGaveNoBlood = true }
    for m in found.medicines where !medicines.contains(where: { $0.name == m.name }) {
      medicines.append(m); medicineOn.insert(m.text)
    }
    withAnimation(.snappy) { step = .blood }
  }

  private func loadExisting() {
    guard let c = cards.first else { return }
    bloodType = c.bloodType
    medicines = c.medicines; medicineOn = Set(c.medicines.map(\.text))
    allergies = Set(c.allergies); conditions = Set(c.conditions)
    contactName = c.contactName; contactPhone = c.contactPhone
    relation = c.contactRelation.isEmpty ? "Partner" : c.contactRelation
    ownerName = c.ownerName; birthDate = c.birthDate; ownPhone = c.ownPhone; homeAddress = c.homeAddress
    surgeries = c.surgeries
    contact2Name = c.contact2Name; contact2Phone = c.contact2Phone
    contact2Relation = c.contact2Relation.isEmpty ? "Parent" : c.contact2Relation
    doctorName = c.doctorName; doctorPhone = c.doctorPhone
    insuranceProvider = c.insuranceProvider; insurancePolicy = c.insurancePolicy; insurancePhone = c.insurancePhone
  }

  private func save() async {
    saving = true
    defer { saving = false }
    let card = cards.first ?? { let c = EmergencyCard(); context.insert(c); return c }()
    card.bloodType = bloodType
    card.medicines = chosenMedicines
    card.allergies = EmergencyText.commonAllergies.filter(allergies.contains) + allergies.filter { !EmergencyText.commonAllergies.contains($0) }.sorted()
    card.conditions = EmergencyText.commonConditions.filter(conditions.contains) + conditions.filter { !EmergencyText.commonConditions.contains($0) }.sorted()
    card.contactName = contactName; card.contactPhone = contactPhone
    card.contactRelation = contactName.isEmpty ? "" : relation
    let trim = { (t: String) in t.trimmingCharacters(in: .whitespacesAndNewlines) }
    card.ownerName = trim(ownerName); card.birthDate = birthDate
    card.ownPhone = trim(ownPhone); card.homeAddress = trim(homeAddress)
    card.surgeries = surgeries
    card.contact2Name = trim(contact2Name); card.contact2Phone = trim(contact2Phone)
    card.contact2Relation = card.contact2Name.isEmpty ? "" : contact2Relation
    card.doctorName = trim(doctorName); card.doctorPhone = trim(doctorPhone)
    card.insuranceProvider = trim(insuranceProvider); card.insurancePolicy = trim(insurancePolicy)
    card.insurancePhone = trim(insurancePhone)
    card.updatedAt = .now
    try? context.save()
    _ = await EmergencyTranslator.translate(card, to: language, languageName: languageName, ai: ai)
    try? context.save()
    onDone(card)
  }
}

/// Primary (filled blue) or secondary (outlined) button for the emergency flow.
struct EmergencyButton: ButtonStyle {
  var primary: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(primary ? .white : MTA.text)
      .frame(maxWidth: .infinity, minHeight: 54)
      .background(primary ? MTA.emergency : Color.clear, in: .capsule)
      .overlay { if !primary { Capsule().strokeBorder(MTA.text, lineWidth: 1.5) } }
      .opacity(configuration.isPressed ? 0.8 : 1)
  }
}

/// The system contact picker: no Contacts permission needed, the traveler picks one person.
struct ContactPicker: UIViewControllerRepresentable {
  var onPick: (String, String) -> Void

  func makeUIViewController(context: Context) -> CNContactPickerViewController {
    let vc = CNContactPickerViewController()
    vc.displayedPropertyKeys = [CNContactPhoneNumbersKey]
    vc.delegate = context.coordinator
    return vc
  }
  func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}
  func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

  final class Coordinator: NSObject, CNContactPickerDelegate {
    let onPick: (String, String) -> Void
    init(onPick: @escaping (String, String) -> Void) { self.onPick = onPick }
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
      let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.givenName
      onPick(name, contact.phoneNumbers.first?.value.stringValue ?? "")
    }
  }
}
