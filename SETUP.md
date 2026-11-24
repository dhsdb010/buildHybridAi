# Setup

## 1. Generate the Xcode project
```bash
cd ios && xcodegen generate && open TravelCopilot.xcodeproj
```
`project.yml` is the source of truth; `TravelCopilot.xcodeproj` is generated.

## 2. Firebase (console steps)
1. Go to https://console.firebase.google.com and create a project (Analytics optional).
2. In **AI Services → AI Logic**, click **Get started** and choose **Gemini Developer API**. This also enforces App Check for AI Logic.
3. Under **Project settings → Your apps**, add an **iOS app** with bundle ID `dev.buildhybridai.travelcopilot`.
4. Download `GoogleService-Info.plist` to `ios/TravelCopilot/Resources/GoogleService-Info.plist`. Git ignores it, so it is never committed.
5. *(Not needed until day 3–4.)* Under **Security → Authentication**, click **Get started**, open the **Sign-in method** tab, and enable **Anonymous**. This lets the app sign in silently with no login screen, so Firestore can store the Expense Report per user.
6. *(Not needed until day 3–4.)* Under **Databases & Storage → Firestore**, create a database in test mode.
7. Run the app once. Copy the `App Check debug token: ...` line from the Xcode console, then go to **Security → App Check → Apps → ⋮ → Manage debug tokens** and add it. Each simulator or device prints its own token.
8. **Sign-in (Google / Apple):**
   1. Under **Security → Authentication → Sign-in method**, enable **Google** and **Apple**.
   2. Download `GoogleService-Info.plist` again. It now contains `CLIENT_ID` and `REVERSED_CLIENT_ID`, and the build adds the URL scheme automatically.
   3. Sign in with Apple also needs a development team with the capability in Xcode (Signing & Capabilities). It only works on a signed build.
9. **Plan chat with Google Maps:** Grounding with Google Maps needs the **Blaze** (pay-as-you-go) plan. On the free tier it returns HTTP 429, and the app falls back to Apple Maps search: the places are real, but there are no Google scores.
   - Google scores also need the **Places API (New)** enabled on the project's API key.
   - Without it, the card shows a "Reviews ↗" link to Google Maps instead of a score.

### Signing, App Attest and TestFlight
- `project.yml` sets the development team (`DEVELOPMENT_TEAM`) with automatic signing. If you build from a fork, change it to your own Team ID.
- **Debug builds** (simulator, or run from Xcode) use the App Check **debug token**, as above.
- **Release builds** (TestFlight, App Store) use **App Attest**. In Firebase, go to **Security → App Check → Apps → travelcopilot** and register **App Attest** (no extra settings). Leave the debug token registered for the simulator.
- `ITSAppUsesNonExemptEncryption` is `NO` (the app only uses standard HTTPS), so App Store Connect doesn't ask about encryption on each upload.
- **Upload:** in Xcode, choose **Any iOS Device**, then **Product → Archive → Distribute App → TestFlight & App Store**.

### Keeping one debug token across reinstalls
Deleting the app makes App Check print a **new** debug token. To keep the token you already registered, pass it as the `FIRAAppCheckDebugToken` environment variable:
- **Xcode:** Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables. This is stored in your user-local scheme data, so it isn't committed.
- **Command line:** `SIMCTL_CHILD_FIRAAppCheckDebugToken=<token> xcrun simctl launch <device> dev.buildhybridai.travelcopilot`

Debug launch arguments (DEBUG builds only):
- `-autoPrepareSample` loads the sample booking and runs Prepare once you open the Prepare tab.
- `-askQuestion "What time is check-in?"` asks the Vault once on launch (Ask mode).
- `-sayText "At the pharmacy: …"` translates once on launch (Say mode) and opens the big card.
- `-replyText "…"` flips the first big card and submits that reply. The simulator can't type Japanese/Korean/Chinese, so use this to test Flip mode.
- `-now 2026-12-03T13:40` fakes the current time, so Home's countdown and the calendar's "today" show the sample trip mid-way.
- `-tab trip|prepare|log` opens a tab. `-tripMode calendar` opens Trip as a calendar. `-planDay 2026-12-04` opens Plan a day.
- `-screen settings|help|ask` opens Settings, Help or Ask.
- `-appearance 1|2` forces Day (1) or Night (2) for this launch.
- `-screen taxi` opens the taxi card. Add `-replyStage handover` to stop on the "Turn the phone around" screen.
- `-onboarding` shows the Welcome / set-up flow even after set-up. `-welcomeAuto` runs it with the sample trip (bookings → pack → places → offline map). `-onboarded YES` skips it.
- `-signInSeen NO` shows the sign-in screen again. `-welcomePage 3` opens "Have you booked yet?".
- `-planAuto` opens the plan chat and answers it with sample data, running the real cloud calls. Add `-planStep brief|memories|destination|days|stay|eat|book` to stop at a step; it stops at `book` if you leave it out.
- `-liveDemo` starts a sample journey Live Activity to the hotel (train → bus → walk → check-in). Add `-liveDemoStep far|train|bus|walk|arriving|arrived` to pick where you are along it. Tap **Done** on the Live Activity to move to the next step.
- `-notifyIn 8` (debug builds): the next trip reminder fires in 8 seconds instead of at its real time, so you can check the banner and its long-press buttons (Show ticket · Done · Ask Blue). Each scheduled reminder is also printed to the console as `Reminder scheduled: …`.
- `-offlineFor 30` (debug builds): the app acts offline for the first 30 seconds, then comes back online. Combine with `-sayText "At the pharmacy: I'm allergic to penicillin"` to make an on-device draft and watch the catch-up pass improve it (needs a registered App Check debug token for the cloud step). The Log tab's **Catch-up** filter shows each step.
- `-logKeep 10` (debug builds): compacts all but the latest 10 Log rows into daily summaries at launch, to see the Log's **Earlier · compacted by day** section. Normally the app keeps the newest calls in detail up to about 10 MB (`RoutingLog.detailBudgetBytes`, roughly 20,000 calls) and compacts older ones; Clear removes both.
- `-emergency setup|card|english` (debug builds): opens the emergency card quiz, the card, or its English side. Add `-emergencySample` to fill a sample card (penicillin, peanuts, ibuprofen 200 mg, asthma, A+) and run the real one-time translation; add `-emergencyStep 1…6` to jump to a quiz step. `-onboarding -welcomePage 4` shows the emergency card Welcome page. `travelcopilot://emergency` opens the card too.
- **Emergency card quick access** (on a device): say "Show my emergency card in Travel Copilot" to Siri, or search Spotlight for "Emergency card". Action Button: Settings → Action Button → Shortcut → Travel Copilot → Show emergency card. Control Center: edit → Add a Control → Travel Copilot → Emergency card (also placeable on the Lock Screen). Lock Screen widget: customize the Lock Screen → add Travel Copilot → Emergency card (shows no medical details while locked; a tap opens the card after Face ID).
- `-tab map -mapMode offline` opens the Map on the saved offline snapshot. Set a fake GPS position with `xcrun simctl location <device> set 35.6905,139.7000`.

## 3. Day-1 spike checklist (real iPhone with Apple Intelligence)
| # | Question | How |
|---|---|---|
| 1 | Does on-device inference work offline with App Check enforced? | Turn Airplane Mode on and tap **Run .hybrid** and **Run .deviceOnly** |
| 2 | Is on-device vs cloud reported? | Each result header shows 📱/☁️ and the `modelVersion` |
| 3 | Does structured output work on-device? | Tap **Structured output** and expect `item=hotel field=checkInTime` |
| 4 | Can the simulator run Foundation Models? | ✅ Yes on this Mac (simulator reports "available") |

### Results so far (iPhone 17 simulator, Wi-Fi, Nov 17)
| Test | Result |
|---|---|
| `.deviceOnly` | ✅ 📱 `apple-foundation-models-system-language-model`, 6.4 s cold / ~3 s warm, returns just the translation |
| `.cloudOnly` | ✅ ☁️ `gemini-3.5-flash-lite`, 0.9–2.9 s. App Check debug token accepted. The output is verbose markdown, so the prompts need to constrain the format |
| `.hybrid` (online) | ✅ chose 📱 on-device first, as designed |
| Structured output on-device (`@Generable`) | ✅ `item=hotel field=checkInTime` (correct) |
| On-device vs cloud detection | ✅ via `rawResponse.modelVersion` |
| **Offline + App Check** | ⏳ needs a real Apple Intelligence iPhone (Airplane Mode) |
| `isExpensive` / `isConstrained` | ⏳ needs a real iPhone on cellular |
| 5 | Cellular / Low Data flags | Turn Wi-Fi off and use cellular (look for 💸), then turn on Low Data Mode |

## Blue's question test set

67 real questions about the sample Tokyo trip, run against the real on-device model and scored by what Blue would actually show: **correct**, **missed** (said "not in your bookings" when it was saved) or **wrong** (showed a value that doesn't answer the question). It needs Apple Intelligence, takes about a minute, and only runs when asked:

```bash
cd ios && TEST_RUNNER_BLUE_EVAL=1 xcodebuild test -project TravelCopilot.xcodeproj -scheme TravelCopilot -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TravelCopilotTests/BlueEvalTests 2>&1 | grep BLUE_EVAL
```

- The first 40 questions were used to tune Blue's rules (`AskResolver`, `AskGuard`); the last 16 ("held out") were written afterwards and are never tuned on, so their score is the honest one.
- The test fails if Blue shows a single wrong value; accuracy is reported, not enforced.
- Baseline on 19 Nov 2026 (iPhone 17 simulator): before the fixes 28/40 with 6 wrong; after, 40/40 tuned and 14/16 held out, 0 wrong, all on-device, about 1.1 s per question.
- 20 Nov 2026: a second held-out set (10 questions, including traps) was written before changing rules. It found one wrong value ("What time is it in Tokyo now?" got the departure time) and three misses; a general rule fixed them (a time question counts for a booking time only when it names what it's about). Result: 67/67, 0 wrong. Both held-out sets have now informed the rules, so write a fresh set before the next change.

## Emergency card in Apple Wallet (optional)

The pass is made and signed on the iPhone, so it needs a Pass Type ID certificate inside the app.
For a public release, move signing to a server: a key inside an app can be extracted.

1. In [Certificates, IDs & Profiles](https://developer.apple.com/account/resources/identifiers/list/passTypeId),
   add a **Pass Type ID**: `pass.dev.buildhybridai.emergency`.
2. Select it and create a certificate. Keychain Access → Certificate Assistant → *Request a Certificate
   From a Certificate Authority…* → saved to disk makes the CSR it asks for. Download the `.cer` and
   double-click it.
3. In Keychain Access (My Certificates), right-click **Pass Type ID: pass.dev.buildhybridai…** →
   *Export…* as `PassCertificate.p12` with a password.
4. Download Apple's intermediate certificate
   [AppleWWDRCAG4.cer](https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer).
5. Put both files in `ios/TravelCopilot/Resources/Wallet/`, plus a text file `PassCertificate.password`
   holding the password. Git ignores this folder. Build again.
