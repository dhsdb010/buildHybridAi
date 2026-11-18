# #BuildHybridAI 2026: Build Plan (iOS)
**Concept:** An offline-first travel copilot for the **travel lifecycle: Prepare → Survive → Catch-up**
**One-liner:** Your trip's brain lives on your phone. The cloud prepares it before you leave, Apple's on-device model runs it when your connection is unreliable, expensive, or blocked, and the cloud cleans up after it whenever you're back on good Wi-Fi.

**Deadline:** Mon Nov 30, 2026 @ 2:00 pm (Devpost; check the timezone on the page). That leaves 13 days from Nov 17.
**Target category:** Best iOS App, plus Grand Prize eligibility.
**Platform:** iOS / SwiftUI, with **Apple Foundation Models** on-device and **Gemini** in the cloud, both through **Firebase AI Logic** (hybrid is experimental, SDK ≥ 12.13.0, SPM only).
**Local toolchain:** Xcode 27.0, iOS 27 simulator (iPhone 17), macOS 27.2.

---

## 0. Positioning: why this isn't "another translator"

iOS 27 already translates offline (the Translate app and Live Translation). **Translation is a supporting feature here, not the product.** The product is the thing no built-in translator has: **your own trip** (bookings, hotel address, allergies, receipts), available and understood when the network isn't.

**The problem, in one line:** a traveler's connection is unreliable, expensive, or blocked at exactly the moments that matter, and their trip data is too personal to send to a server anyway.

| Real travel problem | Evidence (industry surveys, mostly from eSIM vendors and insurers) | What the app does |
|---|---|---|
| **Arrival gap:** you've landed with no SIM or Wi-Fi yet and need the hotel address, a booking code, or how to get to town | Losing internet and maps is travelers' #1 anxiety; ~46% lost coverage crossing borders | **Vault Q&A** on-device + **Hotel Big-Card** |
| **Medical or allergy emergency abroad** | 63% couldn't explain an allergic reaction abroad; 28% think they'd understand medical advice | **Emergency card:** verified and pre-translated, with no generation in the critical path |
| **Roaming cost anxiety** | ~47% hit unexpected roaming charges | **Cost-aware routing:** stay on-device while roaming, defer cloud work to Wi-Fi |
| **Foreign receipts nobody can read later** | Foreign-language receipts plus currency conversion need live rates | **Offline receipt capture** → cloud settles with live FX |
| **Cloud blocked for a whole trip** (e.g., Google services in mainland China) | Gemini and Google are blocked there and VPNs are unreliable | Pitch line: the on-device side keeps working, and Catch-up runs after you leave |
| **Privacy of booking and passport data** | Itinerary apps store your trips on their servers | The Vault and info card **never leave the device** |

---

## 1. The lifecycle

1. **Prepare (online, ☁️ cloud Gemini):** paste or share confirmation emails or PDFs → the cloud extracts **structured** `VaultItem`s (flight, hotel, train) and builds a **Destination Pack**: the hotel address in local script, situational phrases, typical scams and fares, and local emergency numbers.
2. **Survive (offline, roaming, or blocked, 📱 Apple Foundation Models + Vision OCR):**
   - **Vault Q&A:** "What time is check-in?" / "Show my hotel to the taxi driver."
   - **Context-aware translation:** knows your hotel, your allergy, and the politeness level, and shows the result on a big-text card.
   - **Sign and receipt capture:** Vision OCR → on-device read and extraction → queued.
   - **Emergency mode:** static, verified, one tap.
3. **Catch-up (back on good Wi-Fi, ☁️ cloud):** runs **every time you reconnect** (e.g., at the hotel each evening), not only after the trip. It polishes draft translations (with a diff), re-reads queued sign photos with full multimodal Gemini, and settles receipts into a home-currency **Expense Report**.

### Cut from the previous version (scope)
- ❌ Travel Log / daily journal (weakest "who needs this?" feature)
- ❌ Online multimodal menu interpretation as a standalone feature (the sign re-read in Catch-up covers the multimodal cloud story)
- ⏸ Stretch only: scam and fare sanity checks beyond what's cached in the Destination Pack

---

## 2. Routing policy (the technical core)

Routing is decided by **availability, cost, and trust**, not just "online or offline".

| Situation (from `NWPathMonitor`) | Route | Why |
|---|---|---|
| No network | `.deviceOnly` | Only option. Result queued as a **draft**. |
| `path.isExpensive` (cellular roaming) or `path.isConstrained` (Low Data Mode) | `.deviceOnly` for Survive tasks; cloud tasks **deferred** | Saves the user's roaming money. Shown as "💸 Saving data: queued for Wi-Fi". |
| Good Wi-Fi / unmetered | `.hybrid` (system → cloud) for chat; `.cloudOnly` for Prepare and Catch-up | Best quality, and the queue drains. |
| Apple Intelligence unavailable | `.cloudOnly` + banner | Graceful fallback. |
| Emergency mode | **No model** for primary content | Verified data only. The on-device model is used only for languages without a bundled pack, and those are labeled "machine-translated". |

A user setting, "Roaming data saver (on by default)", makes the policy visible and controllable.

### Trust rule: no generated facts
Booking facts (confirmation codes, times, addresses) are **stored as structured fields during Prepare** and are **never produced by the on-device model**. For Vault Q&A, the on-device model only **classifies the question** (which item, which field) and **phrases the answer** around the stored value. The UI always shows the **source card** under the answer. The rule also guards against the 4096-token limit: only the matching item goes into the prompt, never the whole vault.

---

## 3. Technical constraints & SDK strategy

| Fact | Effect on the build |
|---|---|
| `HybridModel(primary:secondary:)` with `FirebaseAI.SystemLanguageModel.default` and `ai.geminiModel(name:)` | Three routes: `.hybrid` (system → cloud), `.cloudOnly`, `.deviceOnly`. |
| `GenerativeModelSession` keeps history | A **new session per request**, so every call is single-turn. |
| On-device = **text only**, **≤ 4096 tokens** | Vision OCR produces the text. Vault Q&A injects only the matched item. Images are queued for a cloud re-read. |
| On-device runs **only in the foreground** | Catch-up runs in the foreground when `isOnline && !isExpensive`. |
| Needs **Apple Intelligence** | Check availability at launch and show a banner with `.cloudOnly` fallback. Record the demo on an **iPhone 15 Pro or later**. |
| On-device structured output is experimental ("docs coming soon") | Spike. Use it if it works; otherwise use delimiter-based prompts with a Swift parser. Only *classification* depends on it (small enum output). |
| The response exposes which model ran | Used for the 📱/☁️ badge and the Routing Log. |
| App Check is **required** | Debug provider for development and submission (App Attest if there's time). Never commit `GoogleService-Info.plist` or debug tokens. |
| Other Firebase services | **Anonymous Auth**, **Firestore** (Expense Report + anonymized trip summary only), **Remote Config** (cloud model name, prompt versions, phrase-pack version, routing defaults). |

### Day-1 risk spike (on a real iPhone, before any UI)
1. **Does on-device inference through AI Logic work in Airplane Mode with App Check enforced?** If `.hybrid` fails offline, force `.deviceOnly` when offline. **The concept depends on this.**
2. The exact property that exposes on-device vs cloud on the response.
3. Does on-device structured or enum output work (for Vault question classification and receipt extraction)?
4. Can the simulator run Foundation Models on this Mac, or is a device needed for on-device tests?
5. Read `NWPath.isExpensive` on cellular, and test with Low Data Mode to see `isConstrained`.

---

## 4. Architecture (SwiftUI + SwiftData)

```text
App/
├─ AI/
│   ├─ ModelRouter.swift      ← the only gateway to Firebase AI Logic
│   │    func run(_ task: AITask) async throws -> AIResult
│   │    • decides Route from RoutingPolicy (availability · cost · task type)
│   │    • a fresh GenerativeModelSession per call
│   │    • logs a RoutingEntry (task, route, actual source, latency, reason)
│   │    • drafts / deferred cloud work → CatchUpQueue
│   ├─ RoutingPolicy.swift    ← pure function, unit-tested
│   ├─ Prompts.swift          parseBooking · buildDestinationPack · classifyVaultQuestion
│   │                         translateInContext · extractReceipt · polishDraft · rereadSign
│   └─ Availability.swift
├─ Network/Connectivity.swift   NWPathMonitor → isOnline, isExpensive, isConstrained
├─ CatchUp/CatchUpPass.swift    drains the queue on good Wi-Fi in the foreground
├─ Vision/OCR.swift             RecognizeTextRequest (signs, receipts)
├─ Store/ (SwiftData)           VaultItem · DestinationPack · Message · ExpenseItem · QueueItem · RoutingEntry
├─ Emergency/
│   ├─ InfoCard                 Keychain / .complete file protection (never synced)
│   ├─ PhrasePacks.json         bundled, pre-translated (top 8 languages)
│   └─ EmergencyNumbers.json    bundled, by country
└─ Features/
    ├─ PrepareView      paste or share a booking → Vault + Destination Pack, offline-readiness checklist
    ├─ TripView         itinerary cards, Hotel Big-Card, Ask bar (Vault Q&A + translation)
    ├─ CaptureView      camera: sign / receipt
    ├─ EmergencyView
    └─ CatchUpView      queue progress, draft→polished diffs, Expense Report, Routing Log
Firebase: AI Logic · App Check · Anonymous Auth · Firestore · Remote Config
```

**Data boundary:** raw booking emails, the Vault, the info card, and raw offline queries stay on the device. Only the Expense Report and an anonymized trip summary sync to Firestore.

---

## 5. Features → implementation (priority order)

**P0: must exist for the demo**
1. **Prepare:** paste text (plus a Share Extension if time allows) → `.cloudOnly` `parseBooking` → structured `VaultItem`s. `buildDestinationPack` → hotel address in local script, 10–15 situational phrases, typical scams and fares, and emergency numbers (checked against the bundled table). An offline-readiness checklist shows: Model ✓ · Vault ✓ · Destination Pack ✓ · Emergency ✓.
2. **Vault Q&A (Ask bar):** on-device `classifyVaultQuestion` → stored field → phrased answer + source card. Badge: `📱 On-device · 110 ms`.
3. **Hotel Big-Card + context translation:** a full-screen high-contrast card. Translation prompts include context such as "I'm at a pharmacy and I'm allergic to penicillin". A **Flip** mode lets a local type a reply that's translated back. Offline results get a `Draft` chip.
4. **Routing policy + Routing Log:** a summary strip ("14 📱 · 6 ☁️ · 3 💸 deferred · 5 caught up") and a per-call list showing the routing *reason*.
5. **Catch-up pass:** a toast ("Back on Wi-Fi: catching up 3 translations, 2 receipts, 1 sign…"), draft→polished diffs, and receipts converted with live FX into the Expense Report (written to Firestore).

**P1: strong but cuttable**
6. **Capture:** a receipt → OCR → on-device `{merchant, amount, currency, category}` → `ExpenseItem`. A sign → OCR → on-device rough translation → queued for a cloud multimodal re-read.
7. **Emergency mode:** the info card with pre-translated labels, verified phrase packs, and tap-to-call local numbers.

**P2: stretch**
8. Share Extension for booking emails and PDFs.
9. A "Is this fare normal?" check against the cached Destination Pack.
10. App Attest + a TestFlight public link.

---

## 6. 13-day schedule (Nov 17 – Nov 30)

| Dates | Milestones |
|---|---|
| **Nov 17–18** | Firebase project (AI Logic, App Check debug, Anonymous Auth, Firestore, Remote Config). Xcode project + SPM. GitHub repo (Apache-2.0, `.gitignore` for `GoogleService-Info.plist`). **Risk spike (§3) on a real iPhone.** |
| **Nov 19–20** | `ModelRouter`, `RoutingPolicy` (+ unit tests), `Connectivity`, SwiftData models, Routing Log. **Prepare** flow (booking parser + Destination Pack). |
| **Nov 21–22** | **Vault Q&A** with source cards, Hotel Big-Card, context translation + Flip mode, badges. |
| **Nov 23–24** | **Catch-up pass:** queue, draft→polished diffs, deferred-while-roaming handling. |
| **Nov 25** | **Capture:** receipt extraction → Expense Report with live FX. Sign OCR → cloud re-read. |
| **Nov 26** | **Emergency mode:** info card, phrase packs, emergency numbers. |
| **Nov 27** | Polish: empty, error, and Apple-Intelligence-off states, Remote Config, TestFlight upload. **Feature freeze at end of day.** |
| **Nov 28** | Record the ≤ 3-minute demo on a real iPhone (Airplane Mode and Wi-Fi toggles in Control Center), English captions, upload to YouTube. |
| **Nov 29** | README (value proposition, how AI Logic is used, routing policy, architecture, setup), Devpost text, submit. |
| **Nov 30** | Buffer only. Submit before 2:00 pm. |

---

## 7. Demo script (≤ 3:00)

- **0:00–0:15 | Hook:** "Translation is built into your iPhone. Your *trip* isn't. And your connection fails exactly when you need it."
- **0:15–0:40 | Prepare (Wi-Fi · ☁️):** paste a messy hotel and flight email → the Vault fills in → the Destination Pack is ready → the checklist is all green.
- **0:40–1:35 | Survive (Airplane Mode ON · 📱):**
  - "What time is check-in?" → instant on-device answer + source card.
  - "Show my hotel to the taxi driver" → Hotel Big-Card in local script.
  - Pharmacy: a context translation about the allergy → the pharmacist replies on the flipped card.
  - Snap a receipt → expense logged offline as a draft.
- **1:35–1:55 | Roaming (cellular ON, roaming):** a sign photo → on-device rough read, with "💸 Saving data: full read queued for Wi-Fi".
- **1:55–2:10 | Emergency:** the allergy card in the local language + one-tap local number. No AI in the critical path.
- **2:10–2:45 | Catch-up (hotel Wi-Fi · ☁️):** the queue drains on its own, drafts become polished, the sign is re-read, the Expense Report appears in your home currency, and the Routing Log tells the story: 📱 → 💸 → ☁️.
- **2:45–3:00 | Close:** privacy (the Vault never left the phone) + the hybrid routing diagram.

---

## 8. Submission checklist
- [ ] Public GitHub repo with an **Apache-2.0** license visible in About
- [ ] Firebase AI Logic imported and called at runtime (`AI/ModelRouter.swift`)
- [ ] Testable link (TestFlight) + README note: on-device needs an Apple Intelligence device
- [ ] YouTube video ≤ 3 min, in English, filmed on a real iPhone
- [ ] Devpost text: the problem (with survey sources cited as industry surveys), Prepare → Survive → Catch-up, the routing policy, the trust rule, and the Firebase products used
- [ ] Platform selected: **iOS**
