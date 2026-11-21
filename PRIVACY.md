# Travel Copilot privacy policy

Effective November 20, 2026

Travel Copilot is a travel app for iPhone. This policy explains what the app keeps on your iPhone, what it sends to other services and why, and the choices you have.

**In short:** your trip lives on your iPhone. There is no Travel Copilot server and no trip backup. The app sends text to Google's Gemini only when a feature needs the cloud, and the app's Routing Log shows every one of those requests. There are no ads, no analytics and no tracking, and nothing is sold.

## What stays on your iPhone

These are stored only on your device, in the app's own storage:

- Bookings you paste into Prepare, after the app reads them.
- The phrase and safety pack, saved places and offline maps.
- Your chats with Blue and the translations in Say.
- Your emergency card.
- The Routing Log: each AI request's task, where it ran, how long it took and why.
- Your settings.

Deleting the app deletes all of this. Travel Copilot does not copy it to any server.

## When the app uses the cloud

Travel Copilot uses Firebase AI Logic, a Google service, to send requests to Google's Gemini models. When your iPhone can run Apple's on-device model, many requests run on the iPhone and are not sent anywhere. The Routing Log shows which requests ran on the device and which ran in the cloud.

| Feature | What is sent to Gemini |
|---|---|
| Prepare | The booking text you paste, so the app can read your bookings. Then the destination country and city, to build the phrase and safety pack. |
| Blue (questions) | Your question, with the bookings and saved places it may need for the answer. On iPhones that can't run Apple's on-device model, every question goes to the cloud. |
| Blue (open questions) | Your question, with only the trip's country, hotel name and address, and dates. No confirmation codes or personal details. |
| Say (translation) | The text you ask the app to translate. |
| Catch-up | Answers and translations that were made offline, so they can be checked and improved once you are back online. |
| Emergency card | The allergies, conditions and medicines you typed on your card that are not in the app's built-in list, so they can be translated once into the destination's language. Medicines imported from Apple Health are never sent; they stay in English on the card. |
| Trip planner | What you tell the planner, and the destination city and area. Place suggestions use Grounding with Google Maps, which receives the city's map location, not your own location. |

Google processes these requests under the [Gemini API terms](https://ai.google.dev/gemini-api/terms) and the [Firebase terms](https://firebase.google.com/terms). Under those terms, Google may use content sent to free-of-charge Gemini services to improve its products. Don't put information in the app that you don't want sent to Google for these features.

## Other services

- **Firebase App Check (Google and Apple).** It checks that requests come from the real app, using Apple's App Attest. It doesn't send your trip data.
- **Sign in with Google or Apple.** Only the trip planner needs an account. If you sign in, Firebase Authentication stores your name, email address and an account ID. The app uses the account only to identify you for cloud planning. Nothing from your trip is stored in the account. Everything else, including all offline features, works without an account. You can sign out or delete your account in Settings; deleting it removes it from Firebase Authentication and, for Sign in with Apple, revokes the app's access to your Apple ID.
- **Apple Maps.** Searching for places and saving offline maps sends those searches and map areas to Apple, under [Apple's privacy policy](https://www.apple.com/legal/privacy/).

## Permissions

- **Location (while using the app).** It shows where you are on your saved trip map. Your location is used on the iPhone only and is not sent to Gemini.
- **Apple Health (read only, optional).** It can fill your emergency card with your blood type and the medicines you choose. Health data stays on your iPhone: it is never sent to Gemini or any other service, used for advertising, or sold. The app never writes to Health.
- **Notifications.** Trip reminders are scheduled on the iPhone. No push server is involved.

## Children

Travel Copilot is not directed at children under 13, and it doesn't knowingly collect their information.

## Your choices

- Use the app without signing in. Only the trip planner needs an account.
- Sign out or delete your account in Settings at any time.
- Turn on Airplane Mode: offline features keep working, and nothing is sent.
- Check the Routing Log at any time to see what went to the cloud.
- Delete the app to remove everything stored on your iPhone.

## Changes and contact

If this policy changes, the new version will be posted here with a new effective date.

For questions, open an issue in the project's [GitHub repository](https://github.com/dhsdb010/buildHybridAi/issues). Don't include personal or health information in a public issue.
