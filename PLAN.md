# #BuildHybridAI 2026: Build Plan (iOS)

**Deadline:** Mon Nov 30, 2026 @ 2:00 pm (Devpost; check the timezone on the page). That leaves 14 days from Nov 16.
**Target category:** Best iOS App, plus Grand Prize eligibility.
**Platform:** iOS / SwiftUI, with Apple Foundation Models on-device and Gemini in the cloud, both through **Firebase AI Logic** (hybrid is experimental, SDK ≥ 12.13.0, SPM only).
**Local toolchain:** Xcode 27.0, iOS 27 simulator (iPhone 17), macOS 27.2.

---

## 1. What the rules and the iOS SDK mean for this concept

| Fact | Effect on the build |
|---|---|
| Hybrid is configured as `HybridModel(primary:secondary:)` with `FirebaseAI.SystemLanguageModel.default` and `ai.geminiModel(name:)` | There are three model setups. **Hybrid** puts the system model first and the cloud second. **Cloud-only** is a session with only the cloud model. **Device-only** is a session with only the system model. These are the iOS equivalents of `PREFER_ON_DEVICE` / `ONLY_IN_CLOUD` / `ONLY_ON_DEVICE`. |
| A `GenerativeModelSession` **keeps chat history** | Create a **new session per request** so every translation is single-turn and free of history. |
| On-device = **text only**, no image input, **≤ 4096 tokens** | Photo reading is cloud work. Offline, use **Apple Vision OCR** (`RecognizeTextRequest`, which runs on-device with no AI Logic) to pull the text and translate it on-device, then queue the photo for a full cloud re-read. This is stronger than "photo needs network". |
| On-device runs **only while the app is in the foreground** | Run the upgrade pass in the foreground (it is cloud work anyway). Don't rely on background tasks. |
| Needs a device **with Apple Intelligence enabled**, and the model downloads with the OS. The app can't trigger the download. | Check availability at launch. If it's missing, show an "Enable Apple Intelligence for offline mode" banner and run cloud-only. Record the demo on an **iPhone 15 Pro or later**. |
| Structured output and function calling on-device are "supported, docs coming soon" | The spike decides it. If structured output works, return `{translation, romanization, note}`. If not, use a delimiter-based prompt and a parser. |
| The response reports which model was used | Use it for the 📱/☁️ badge and the Routing Log. |
| App Check is **required** (debug tokens accepted) | Use the debug provider for development and submission, and **App Attest** if there's time. Never commit the debug token. |
| AI Logic plus other Firebase products are encouraged | Use **Anonymous Auth**, **Firestore** (travel log, offline cache), **Remote Config** (cloud model name, prompt versions, phrase-pack version). |
| Public repo with an open-source license, video ≤ 3 min, a hosted/testable link is "highly encouraged" | GitHub with Apache-2.0. A **TestFlight public link** serves as the testable URL. |
| Pitch risk: "Why not Apple's Translation framework?" | Answer: an LLM adds context (politeness level, cultural note, "show this to a pharmacist" framing), fixes its own drafts in the upgrade pass, and supports the emergency-card framing. Say this in the README and video. |

### Day-1 risk spike (before anything else)
1. **Does on-device inference through AI Logic work in Airplane Mode with App Check enforced?** The SDK might try to fetch an App Check token before routing. Test on a **real device**. If the hybrid session fails offline, use the device-only session when `NWPathMonitor` reports no network. **The whole concept depends on this.**
2. How the response exposes the model used (property name/type).
3. Does on-device structured output work in this SDK version?
4. Does the simulator run the on-device model on this Mac (for faster iteration), or is a device needed for every on-device test?

---

## 2. Architecture (SwiftUI + SwiftData)

```
App/
├─ AI/
│   ├─ ModelRouter.swift     ← the only file that calls Firebase AI Logic
│   │    func run(_ task: AITask, route: Route) async throws -> AIResult
│   │      Route: .hybrid (system→cloud) | .cloudOnly | .deviceOnly
│   │      AIResult: text, source (.onDevice/.inCloud), latencyMs
│   │    • a new GenerativeModelSession per call (single-turn)
│   │    • appends a RoutingEntry for every call
│   │    • on-device results → UpgradeQueue
│   ├─ Prompts.swift         translate / polish / photoRead / travelLog (versions in Remote Config)
│   └─ Availability.swift    on-device model availability + reason
├─ Network/Connectivity.swift   NWPathMonitor → @Observable isOnline
├─ Upgrade/UpgradePass.swift    when the connection returns + the app is in the foreground → drain the queue (cloudOnly)
├─ Vision/OCR.swift             offline text extraction from photos
├─ Store/ (SwiftData)           Message, QueueItem, RoutingEntry, TravelLogEntry
├─ Emergency/
│   ├─ InfoCard (Keychain / file protection .complete, never synced)
│   ├─ PhrasePacks.json (bundled, pre-translated)
│   └─ EmergencyNumbers.json (bundled, by country)
└─ Features/ Chat · BigCard · Photo · Emergency · Log · Onboarding
Firebase: AI Logic · App Check · Anonymous Auth · Firestore · Remote Config
```

**Data boundary (part of the pitch):** the info card and raw offline messages stay on the device. Only polished travel-log entries are written to Firestore.

---

## 3. Features → implementation

1. **Onboarding**: pick home and destination languages and the destination country, run the on-device availability check, and show an offline-readiness checklist (model ✓, phrase pack ✓, emergency numbers ✓).
2. **Translation chat** (`.hybrid`): each bubble shows a badge such as 📱 On-device · 120 ms or ☁️ Cloud · 640 ms. Offline on-device answers get a "draft" chip and are queued.
3. **Big-text card**: full screen, high contrast, Dynamic Type, auto-fit text with the translation large and the source small. **Flip** turns it into a "reply here" mode for the other person, which sends their text back through the router translated the other way.
4. **Photo**: PhotosPicker or camera. **Online:** `.cloudOnly` with the image, giving a full interpretation of the menu or sign. **Offline:** Vision OCR → on-device translation of the extracted text, labeled "rough, text only" and queued for a cloud re-read.
5. **Upgrade pass**: when the connection comes back, a toast says "Back online: upgrading 4 offline translations…". Each item animates from draft to polished with a highlighted diff and a one-line "what changed". The pass then assembles a travel log (cloud) and saves it to Firestore for the Log tab.
6. **Emergency mode** (no free-form generation in the critical path):
   - Info card (contacts, meds, allergies, blood type) is stored on the device only and shown as a big card in the destination language. The labels are pre-translated.
   - **Verified pre-translated phrase packs** for the top ~8 languages are the primary source. Other languages are translated on-device with a "machine translated" label.
   - Local emergency numbers come from a bundled table with a tap-to-call button and work offline.
7. **Routing log**: lists every call with time, task, route requested, actual source, latency, and "upgraded ✓". A summary strip shows "12 📱 · 5 ☁️ · 4 upgraded".

---

## 4. Schedule (14 days)

| Dates | Work |
|---|---|
| **Nov 16–17** | Firebase project with an iOS app, AI Logic (Gemini Developer API), App Check debug provider, Anonymous Auth. Xcode project + SPM (`FirebaseAILogic`, `FirebaseAppCheck`, `FirebaseAuth`, `FirebaseFirestore`, `FirebaseRemoteConfig`). GitHub repo + Apache-2.0 + a `.gitignore` for `GoogleService-Info.plist`. **Risk spike (§1) on a real device.** |
| Nov 18–20 | `ModelRouter`, Connectivity, translation chat, badges, Routing Log, big-text card |
| Nov 21–22 | SwiftData queue, upgrade pass, draft→polished diff UI, Firestore travel log |
| Nov 23 | Photo: cloud interpretation + offline Vision OCR path |
| Nov 24–25 | Emergency mode: info card, phrase packs, emergency number table |
| Nov 26–27 | Visual polish, empty/error/unavailable states, Remote Config, TestFlight build (App Attest, or document the debug-token setup for judges) |
| Nov 28 | Record the demo video on a real iPhone (screen recording plus a Control Center shot of Airplane Mode toggling), English subtitles, upload to YouTube |
| Nov 29 | README (setup, value proposition, how AI Logic is used, architecture), Devpost text, submit (platform: **iOS**) |
| Nov 30 | Buffer only. Submit before 2 pm. |

---

## 5. Demo script (≤ 3:00)
1. **0:00–0:20** Problem: no network at the moment you need language help most.
2. **0:20–0:50** Online: photograph a menu → ☁️ interpretation.
3. **0:50–1:40** Airplane Mode ON: "Where is the nearest pharmacy?" → 📱 instant answer → big-text card → the other person replies on the flipped card. Photo of a sign → Vision OCR → 📱 rough translation.
4. **1:40–2:10** Still offline: Emergency → allergy phrase plus the info card in the local language, with the local number one tap away.
5. **2:10–2:45** Airplane Mode OFF: the upgrade pass fires on its own, drafts turn into polished translations, the sign is re-read in the cloud, the travel log appears, and the routing log tells the 📱→☁️ story.
6. **2:45–3:00** Closing line and architecture slide.

---

## 6. Open decisions
- **Test device:** an Apple Intelligence iPhone (15 Pro or later) is required for the airplane-mode demo. Confirm you have one.
- **Testable link:** TestFlight public link (needs Apple Developer Program membership and App Attest or a debug token) or a repo-plus-build-instructions route.
- **Name:** still TBD.
- **Phrase-pack languages:** pick the top 8 based on the demo destination.

## 7. Submission checklist
- [ ] Public GitHub repo with an Apache-2.0 license visible in About
- [ ] AI Logic imported and called at runtime (`AI/ModelRouter.swift`)
- [ ] Testable link (TestFlight) + README note: on-device needs Apple Intelligence
- [ ] YouTube video ≤ 3 min, in English, filmed on a real iPhone
- [ ] Devpost text: how AI Logic is used, features, value proposition
- [ ] Platform selected: iOS
