# Plan — "Help me plan" (AI trip-planning chat)

Today the app only starts once the user already has bookings. This adds a step **before** "Add your bookings". The user talks with the AI to pick where to go, when, where to stay, how to get there, and what to eat and see. The app then hands off to the existing set-up (bookings → pack → places → offline map).

## 1 · What similar products do

| Product | Pipeline | What to take | What to avoid |
|---|---|---|---|
| **Mindtrip** | A preference quiz first, then chat. Suggestions come from a database of 11M+ places; booking goes through partners | **Quiz first**: a few taps beat typing. Every suggestion is a real place card | Pretty cards that don't add up to a day plan |
| **Layla** | Destination and trip type in chat, then flights, hotels, activities and prices in one plan | One conversation that produces a whole plan | Chat only, with no way to edit the plan by hand |
| **Google Gemini / AI Mode** | Itinerary that respects locations, travel times, existing plans and preferences. Places come from Google Maps; saves to Maps lists | **Ground on Maps** so places are real. Respect travel time between stops | Booking still not live for flights and hotels |
| **Expedia Romie, Kayak AI** | Search and compare prices (Kayak). Shop, book and assist during the trip (Romie) | Hand off to a real booking site with the search filled in | Kayak has no day-by-day plan |

Shared pipeline: **preferences → destination → days → stay → transport → food and sights → book (partner) → in-trip help**. Our app already covers the in-trip part, offline, which none of these does. So the plan feeds straight into it.

## 1b · Decisions (Nov 18)
- **Planning is online only.** Accurate, current places need live data. Offline, the chat shows a notice, keeps the answers so far, and makes no suggestions.
- **Two scores per place:**
  - **Google:** rating and review count from Maps grounding, or the Places API.
  - **Local:** the country's own review site (Japan: Tabelog for food and Jalan for hotels; Korea: Naver/Kakao; US: Yelp Fusion).
  - **Licensed data only:** use a local score only through a licensed API. Tabelog has no clear public API, so the default is a "Check on Tabelog ↗" link. Never scrape or estimate.
- **Plan bar order:** Where · When · Stay · Eat · See · Book. The flight moves into the Book step.
- **Design:** Figma page "06 · Plan Flow" (Day and Night), plus the new components on page 04.
- **Destinations limited to on-device languages:** suggestions only include countries whose language `SystemLanguageModel.default.supportedLanguages` covers, so offline translation works there. An ⓘ sheet explains why and promises more languages later.
- **Memories step:** the chat asks about past trips the user loved and disliked, not just a list of interests. The on-device model summarizes the answers into Loves / Avoid / Pace tags, and only that summary goes to Gemini.
- **Sign in first (page 05, step 0):**
  - **Options:** Google via Firebase Auth, plus Sign in with Apple (required by App Store rule 4.8), or skip.
  - **What it gives:** a user identity for per-user cloud limits and a backup of the trip.
  - **What it doesn't do:** Gemini still runs on the app's Firebase project, not on the user's own Google AI subscription.
  - **Without an account:** offline features work; "Help me plan it" asks the user to sign in.

## 2 · Our pipeline

```
Welcome ──► "Have you booked yet?"
              ├─ Yes ─────────────────────────────► Add bookings (today)
              └─ Help me plan ─► Plan chat
                                   1 Brief      chips: when · days · who · budget · pace · likes · food
                                   2 Where      3 destination cards (why + best area)        ─ pick 1
                                   3 Days       day-by-day outline, max 3 stops/day, walk/taxi times
                                   4 Stay       3 hotels near the day plans (Maps)            ─ pick 1
                                   5 Get there  flight search handed off to Google Flights / airline
                                   6 Eat & see  restaurants + sights per day (Maps)          ─ keep / swap
                                 ─► "Book, then paste the confirmations" ─► Add bookings ─► Building ─► Ready
```

- **Sticky "Plan so far" bar:** six milestones (Where · When · Stay · Fly · Eat · See), reusing `Milestone`.
- **Every step can be changed later:** tap a milestone to reopen that step. This avoids Layla's "chat only" trap.
- **Save point:** after step 6, kept items become `TripPlan` (source `suggested`) and `Place` rows, so they appear in the calendar and on the offline map.

## 3 · Hybrid AI split

| Part | Where | Why |
|---|---|---|
| Turn the user's free text into brief fields (dates, budget, likes) | **On-device** | Private, instant, works offline. It only classifies, never invents |
| Destination ideas, day outline, "why" lines | **Cloud · Gemini** | Needs world knowledge |
| Hotels, restaurants, sights | **Cloud · Gemini + Grounding with Google Maps** | Real places with Maps IDs, ratings and links. The installed Firebase SDK (12.13) has `Tool.googleMaps()` |
| During the trip: "Somewhere to eat near me?" | **On-device**, over the saved places | Picks from the stored list, with distance from `PlaceFacts`. Works with no signal |

Routing: the plan chat is a new `TaskKind.plan`, cloud only, on Wi-Fi or with the data saver off. It's logged in the Log tab like every other call.

## 4 · Trust rules (same as the rest of the app)

- **Place facts aren't generated.** The name, address, rating and Maps link come from the grounding metadata (`groundingChunks`). The model writes only the one-line "why". Show the Google Maps attribution the grounding terms require.
- **Suggestions aren't bookings.** They're labelled "Suggested" in the calendar. Only a pasted confirmation becomes a Vault booking, and only Vault facts appear in Live Activities and the taxi card.
- **No prices or availability are promised.** We say "check price" and hand off.
- **Booking happens outside the app.** Buttons open Google Flights, the hotel's Maps page, or the restaurant's Maps page, with the search filled in. In-app payment is out of scope.

## 5 · Data

- **`TripBrief` (new, SwiftData):** destination, dates, travelers, budget level, pace, interests, food likes and dislikes, and the current step.
- **`PlanMessage` (new):** role, text, attached option IDs, and the route used.
- **`PlanOption` (`@Generable` for ideas, built from grounding for places):** kind (destination / hotel / food / sight), name, why, area, Maps place ID, URI, lat and lon, and day.
- On save, the brief goes into the existing **`TripPlan`** and **`Place`**. No change to the Vault.

## 6 · Screens (MTA style)

1. **"Have you booked yet?"**: two big buttons on the blue Welcome poster.
2. **Plan chat:** AI turns are plain text rows (no bubbles), with `Chip` rows for quick answers and `OutlineCard` option cards (name, why, area, a "Google Maps" label, Keep / Swap). The Ask bar style is used for typing, and the "Plan so far" bar sits on top.
3. **Day outline:** reuse `PlanDayView` cards with a "Suggested" chip.
4. **Hand-off sheet:** a "Book these" checklist (flight, hotel), each with an Open button. Then "I've booked — paste confirmations" leads to Add bookings.

Figma: a new page **"06 · Plan Flow"**, Day and Night, built from the existing components plus new Option Card and Plan-so-far components.

## 7 · Build order (deadline Mon Nov 30, 2 pm)

| # | Slice | Est. |
|---|---|---|
| 1 | Branch screen, plus `TripBrief` and brief chips with on-device fill-in | 0.5 day |
| 2 | Destination and day outline (cloud, `@Generable`) | 1 day |
| 3 | Maps-grounded hotels, food and sights; option cards and attribution | 1.5 days |
| 4 | Save to `TripPlan` / `Place`, map download, hand-off links into Add bookings | 1 day |
| 5 | Offline "eat near me" over saved places (on-device) | 0.5 day |
| 6 | Figma page 06, DESIGN.md, tests | 0.5 day |

## 8 · Risks

- **Maps grounding and structured output:** Gemini may not allow a JSON response schema together with grounding tools. The fallback is two calls: a grounded call for real places, read from the grounding metadata, then a small `@Generable` call to write the "why" lines. Check this first in slice 3.
- **Model and region support** for Maps grounding: confirm in the Firebase docs. If it's unavailable, fall back to MapKit `MKLocalSearch` for real places (already used in `MapService`).
- **Cost and quota:** every chat turn is a cloud call. Cap destination ideas at 3 and options at 3 per step.
- **Demo time:** the 3-minute video needs one tight path. Use a "Plan a sample: 5 days in Tokyo, food + design" chip.
