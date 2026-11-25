# Travel Copilot privacy policy

Effective November 20, 2026

Travel Copilot is a travel app for iPhone. This policy explains what the app keeps on your iPhone, what it sends to other services and why, and the choices you have.

**In short:** your trip lives on your iPhone. There is no trip backup, and the only things stored on a server are the optional friends and trip rooms you choose to use (see below). The app sends text to Google's Gemini only when a feature needs the cloud, and the app's Routing Log shows every one of those requests. There are no ads, no analytics and no tracking, and nothing is sold.

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
| Files you add to the planner | A short summary request with the file's text, when your iPhone can't summarize it on the device (Apple Intelligence is used first). A booking confirmation you choose to add is read the same way as in Prepare. |
| Emergency card | The allergies, conditions and medicines you typed on your card that are not in the app's built-in list, so they can be translated once into the destination's language. Medicines imported from Apple Health are never sent; they stay in English on the card. |
| Trip planner | What you tell the planner, the taste words read from your photos (never the photos), dates, number of travelers and budget, and the destination city and area. Place suggestions use Grounding with Google Maps, which receives the city's map location, not your own location. |

Google processes these requests under the [Gemini API terms](https://ai.google.dev/gemini-api/terms) and the [Firebase terms](https://firebase.google.com/terms). Under those terms, Google may use content sent to free-of-charge Gemini services to improve its products. Don't put information in the app that you don't want sent to Google for these features.

## Friends and trip rooms (optional)

Planning with friends needs a signed-in account. If you use it, Travel Copilot stores the following in Google Cloud Firestore (part of Firebase), so the people you plan with can see it:

- **Your @ID and display name.** Anyone signed in can look up an @ID if they type it exactly; nobody can browse or search a list of people. Your email, photo and account details are never shown to friends.
- **Your friends, friend requests and the people you block.** Only you can see your friends and blocked lists.
- **Invite codes.** A friend link or QR holds a random code that works for 7 days. Reset it in Add friend → Link at any time.
- **Trip rooms.** Each room's name, its members (their names and @IDs) and the messages written in it. Only the room's members can read them. Only friends can be added to a room.
- **Reports.** If you report a message, the message, who wrote it and the reason are kept so the Travel Copilot team can review it.

Rooms share only what you write in them and the trip's day plan. Your bookings (Vault), receipts, emergency card, health data and chats with Blue stay on your iPhone and are never added to a room.

Blocking someone ends the friendship, hides their messages and stops their requests; they aren't told. Leaving a trip leaves its room; when the owner leaves, the room is closed for everyone. Mute and pin are saved on your iPhone only.

Deleting your account removes your @ID, friends, requests, invites and blocked list, and takes you out of every room. Messages you already sent stay in rooms you were in, under the name you used.

## Other services

- **Firebase App Check (Google and Apple).** It checks that requests come from the real app, using Apple's App Attest. It doesn't send your trip data.
- **Sign in with Google or Apple.** Only the trip planner needs an account. If you sign in, Firebase Authentication stores your name, email address and an account ID. The app uses the account only to identify you for cloud planning. Nothing from your trip is stored in the account. Everything else, including all offline features, works without an account. You can sign out or delete your account in Settings; deleting it removes it from Firebase Authentication and, for Sign in with Apple, revokes the app's access to your Apple ID.
- **Apple Maps.** Searching for places, finding the planner's stops, showing Look Around photos and saving offline maps send those searches, places and map areas to Apple, under [Apple's privacy policy](https://www.apple.com/legal/privacy/).
- **Wikipedia.** The planner shows a photo of each suggested destination from Wikipedia. Only the city's name is sent.

## Permissions

- **Location (while using the app).** It shows where you are on your saved trip map. Your location is used on the iPhone only and is not sent to Gemini.
- **Apple Health (read only, optional).** It can fill your emergency card with your blood type and the medicines you choose. Health data stays on your iPhone: it is never sent to Gemini or any other service, used for advertising, or sold. The app never writes to Health.
- **Microphone and speech recognition (optional).** Used only when you tap the mic or Talk in the planner. Apple's speech recognizer turns your voice into text on the iPhone when the iPhone supports it; otherwise Apple's speech service does, under [Apple's privacy policy](https://www.apple.com/legal/privacy/). Recordings are not kept by Travel Copilot.
- **Camera and photos (optional).** A photo you take or pick in the planner is read on the iPhone with Apple Vision; only the words it finds are used for planning. Travel Copilot can only see the photos you choose. The camera also scans a friend's QR code when you tap Scan; the image isn't saved or sent.
- **Notifications.** Trip reminders are scheduled on the iPhone. No push server is involved.

## Children

Travel Copilot is not directed at children under 13, and it doesn't knowingly collect their information.

## Your choices

- Use the app without signing in. Only the trip planner and planning with friends need an account.
- Sign out or delete your account in Settings at any time.
- Turn on Airplane Mode: offline features keep working, and nothing is sent.
- Check the Routing Log at any time to see what went to the cloud.
- Delete the app to remove everything stored on your iPhone.

## Changes and contact

If this policy changes, the new version will be posted here with a new effective date.

For questions, open an issue in the project's [GitHub repository](https://github.com/dhsdb010/buildHybridAi/issues). Don't include personal or health information in a public issue.
