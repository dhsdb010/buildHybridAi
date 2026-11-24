# TestFlight

## Upload a build

```bash
ios/scripts/testflight.sh
```

The version stays 1.0. Each upload gets a new build number from the date and time, so no file needs to change. `--archive-only` checks that it builds without uploading.

## Test Information (TestFlight › 테스트 정보)

**Beta App Description**

> Travel Copilot keeps your trip on your iPhone and works with no signal. Paste your booking emails once on Wi-Fi; then Blue, the trip chat, answers questions about your flights and hotel on the device, Say translates for you in the local language, and the map, taxi card and emergency card all work offline. AI runs on Apple's on-device model first and uses Gemini in the cloud when it needs to, including later, once you're back online. Built for #BuildHybridAI 2026 with Firebase AI Logic.

**Feedback Email:** your email

**Marketing URL:** https://github.com/dhsdb010/buildHybridAi

**Privacy Policy URL:** https://github.com/dhsdb010/buildHybridAi/blob/main/PRIVACY.md

## Beta App Review Information (베타 앱 심사 정보)

**Contact:** your name, phone and email

**Sign-in required:** No (leave the demo account empty)

**Review Notes**

> No account is needed. On first launch, tap Skip on the sign-in screen. The trip planner asks for Sign in with Apple or Google; any Apple ID works.
>
> To try it quickly: during setup tap "Use a sample trip to Tokyo" (or "Sample" at the top of Prepare), then tap the button to read it. Ask Blue "When is my flight?" or "What's the hotel address?". Turn on Airplane Mode and ask again: Blue answers on the device.
>
> On-device AI needs Apple Intelligence (iPhone 15 Pro or later). On other iPhones the same features use Gemini in the cloud. The Log tab shows where every request ran.
>
> Health access is optional and read-only (blood type and medications for the emergency card). Location is used only to show you on the offline map.

## What to Test (per build)

> First TestFlight build. Please try:
> 1. Plan a trip by chatting with Blue, or paste a booking email in Prepare.
> 2. Ask Blue about your bookings, then turn on Airplane Mode and ask again.
> 3. Say: translate a sentence for a taxi driver or a pharmacy.
> 4. Set up the emergency card and add it to Apple Wallet.
> 5. Open the Log to see which requests ran on the iPhone and which in the cloud.
