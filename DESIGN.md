# Design rules — Travel Copilot × MTA

Source: the MTA UX/UI Design System (Spring 2021). The Figma file is "Travel Copilot · Live Activities (MTA style)":
https://www.figma.com/design/YVtC8LUcZoFlw3X2jpwkQm

| Page | Contents |
|---|---|
| 00 · Rules | The rules below, as a board |
| 01 · Foundations | Color variables, type scale, grids (with visible column overlays) |
| 02 · Live Activities | Components: Bullet, Pill, Progress, Lock Screen ×7, Dynamic Island Expanded/Compact/Minimal ×7. **Journey v2**: one step at a time toward a goal (train → bus → walk → check-in → arrived), Dynamic Island, one-step notifications with long-press actions |
| 03 · Wire Flow | 7 trip moments: trigger → Lock Screen → Dynamic Island → screen that a tap opens; App Screen components |
| 04 · App Screens | Home, Settings, Trip, Calendar, Plan a day, Ask, Prepare, Log, Help (Day + Night) |
| 05 · Onboarding Flow | First launch: Welcome → Add bookings → Building → You're ready → Home, with branches for "I'll do it later", offline, and a partial set-up (Day + Night) |
| 06 · Plan Flow | "Help me plan" before bookings: Booked yet? → Brief → Memories → Where → Days → Stay → Eat & see → Book these → Add bookings, with branches for already booked, offline (plus the ⓘ "Why only these places?" sheet), no local score, and Swap (Day + Night) |

Page 05 now starts with **0 · Sign in**: Continue with Google, Sign in with Apple (App Store rule 4.8 requires it when Google sign-in is offered), or "Continue without an account". Offline features never need an account; "Help me plan it" asks you to sign in first.

## Plan chat (page "06 · Plan Flow")
- **Online only.** Planning needs live, accurate places, so it runs in the cloud (Gemini with Grounding with Google Maps). Offline, it shows a notice and makes no suggestions. The trip still works offline after set-up.
- **Components** (page 04, "Plan chat" column):
  - **Quick Chip** (Default / Selected).
  - **Chat Turn:** AI is plain text with the asterisk, no bubble; You is a raised pill.
  - **Plan Step** (Done / Current / Upcoming) and **Plan so far:** Where · When · Stay · Eat · See · Book.
  - **Option Card** (Default / Kept).
  - **Book Row** (To book / Booked).
- **Two scores on every place:** the **Google** score (rating and review count from Maps grounding) next to the **Local** score from the country's own review site: Tabelog (food) and Jalan (hotels) in Japan, Naver/Kakao in Korea, Yelp in the US. A local score comes only from a licensed API. If there's none, the badge reads "Check on Tabelog ↗" and opens the site. Never scrape or estimate a score.
- **Destinations follow the on-device model's languages:** "Suggest for me" and the destination chips only offer countries whose language the on-device model supports. The app reads the list at runtime from `SystemLanguageModel.default.supportedLanguages`, so offline translation works on the trip. An `info.circle` link, "Why only these places?", opens a sheet that explains this, apologizes for the short list, and says more languages are coming. The user can still type any place.
- **Memories step:** the chat asks about a trip the user loved and what they didn't enjoy. The on-device model turns the answers into a "What I'll remember" card (Loves / Avoid / Pace). Only that summary goes to the cloud for planning.
- **Facts vs. words:** the name, address, scores and link come from the data source. The model writes only the "Why" line. Source labels stay visible.
- **Suggestions aren't bookings:** booking happens on the airline or hotel site, and only pasted confirmations become Vault items.

## App screens (page "04 · App Screens")
Day is the main look, following the MTA-style reference (white base, big bold numbers, outlined boxes). There's a Night copy too. Screens are 402 × 874 on the 4·30·15 grid, built only from these components: Nav Bar, Tab Bar, Button, Number Box, Milestone, Card (Notice/Feature), Segmented, Settings Row, Ask Bar.

| Screen | What it shows |
|---|---|
| Home | Next moment as a big number (15:00) · countdown boxes · offline-readiness milestones · taxi card shortcut · Ask bar. **Gear (top right) opens Settings**. With no trip yet, the screen says "Start your trip here", has a "Prepare my trip →" button, and shows trip-idea cards (Tokyo, Seoul, …) that open the planner already filled in |
| Map | **Full screen.** The map runs under the status bar and tab bar. Floating glass controls: Live / Offline, the connection state, and recenter (`location.fill`). A bottom sheet lists places with walk or taxi times plus the Ask bar. Offline: the saved snapshot, area chips, and a "Saved" chip. Pins: hotel = New Blue with `bed.double.fill`, plan = inverse with `mappin`; the GPS dot is New Blue with a halo |
| Settings | Pushed from Home (not a tab). Network (data saver, wait for Wi-Fi, cloud model) · Day/Night · Trip · Privacy |
| Trip | Trip days as milestones · Vault cards with bullets · check-out notice |
| Ask | Ask / Say segmented · answer as a big number · 📱 on-device chip · "From your booking" source card |
| Prepare | Paste box · what you'll have offline · notice that Prepare is the only cloud step · primary button |
| Log | Device / Cloud / Deferred / Failed boxes · routing entries. Failed rows show only a short cause ("Over quota · details"); tapping a row opens Request details with every field and the raw error |
| Help | 110 / 119 call tiles · medical info card · pre-checked Japanese phrases |

| Trip · Calendar | List / Calendar switch · blue "TOKYO" poster with flight/hotel badges · month grid (done green, today blue ring, planned outline, check-out red, outside the trip gray) · selected-day preview |
| Plan a day | Time-ordered plan cards with a source chip: You added / From booking / Suggested · Wi-Fi · Live Activity reminder toggle · Add a plan |

### Layout rules (checked on every screen)
- **Snap to the 4-column grid:** columns are 74.25pt with 15pt gutters inside the 30pt margins. Rows of 4 (number boxes, readiness circles) use one item per column. Rows of 2 (Help tiles) span 2 columns each. Badges on the right edge center on column 4.
- **Even spacing:** day strips and calendar weeks use equal cells, never spacing driven by text width.
- **Nav title is truly centered:** the left and right slots are fixed at 88pt each, and the title fills the middle.

### Tab bar: iOS 26 Liquid Glass
- **Tabs:** 5 tabs, **Home · Trip · Map · Prepare · Log**. Settings isn't a tab; it opens from the **gearshape** on Home.
- **Shape:** a floating 370 × 70 capsule, 20pt above the bottom edge, with content scrolling under it.
- **Material:** a Figma `GLASS` effect over a `color/bg/glass` tint. Use `.glassEffect()` / the system `TabView` on iOS.
- **Active tab:** a `color/fill/selected` pill with the **.fill** SF Symbol in New Blue.
- **Labels:** the `MTA/Tab` style (11pt Medium, normal case).

### Icons: SF Symbols only
- **In Figma:** the icons are components named `SF Symbol/<name>`, built from the real glyph outlines in SF Pro. The description of each one gives the SwiftUI code.
- **In code:** always `Image(systemName:)`.

| Where | Symbol |
|---|---|
| Tabs | `house` / `house.fill` · `suitcase.rolling` / `.fill` · `map` / `map.fill` · `square.and.arrow.down` / `.fill` · `list.bullet` |
| Map | `location.fill` (recenter) · `mappin` (plan pins) · `figure.walk` (walk time) |
| Nav | `chevron.left` (push) · `xmark` (modal) · `gearshape` (Home → Settings) |
| Trip bullets | `airplane` · `bed.double.fill` · `icloud.dashed` (waiting for Wi-Fi) · `checkmark` · `square.and.arrow.down` |
| Other | `arrow.up` (Ask send) · `phone.fill` (Help call tiles) · `info.circle` (explanations) · `globe` (languages) · `apple.logo` (Sign in with Apple) |

### Where AI ran / connection (always with a text label)
| State | Symbol | Used in |
|---|---|---|
| Ran on this iPhone | `iphone` | Log rows (green disc), Ask "On-device" chip |
| Ran in the cloud (Gemini) | `icloud` | Log rows (New Blue disc) |
| Waiting for Wi-Fi / Catch-up pending | `icloud.dashed` | Log "Deferred" rows (yellow disc, black glyph), Catch-up Live Activity |
| Offline | `icloud.slash` | Home "Offline" chip |

Label the cloud as "Cloud · Gemini", never plain "iCloud", so nobody thinks the app syncs to iCloud.

### Brand mark
- **Mark:** the SF Symbol `asterisk`, which echoes the MTA starburst poster.
- **App icon:** Day is New Blue with a white mark; Night is black with a New Blue mark. It's the "App Icon · Brand mark" component.
- **In the app:** a New Blue asterisk at the top left of Home only. It's not a tab icon; Home stays `house`.
- **Brand Badge:** the asterisk with "TRAVEL COPILOT ·" set on a circle around it (MTA Label style). It's the Figma "Brand Badge" component (tones: On blue, On surface) and `BrandBadge` in SwiftUI. It's used on the Welcome screen; the ring turns once every 24 s and stays still with Reduce Motion.

## Color: always means status
| Token | Hex | Use |
|---|---|---|
| bg/surface | #000000 | Every surface, including Live Activities |
| text/primary · text/secondary | #FFFFFF · #969696 | |
| accent/primary (New Blue) | #0050EA | Actions, neutral bullets |
| status/on-track | #139240 | Plan is fine |
| status/obstacle | #FF6B00 | Needs attention (offline pack missing). Black glyphs |
| status/urgent | #FF0000 | Deadline under 30 min |
| status/notice | #FFD51F | Waiting (drafts waiting for Wi-Fi). Black glyphs |
| status/assistance | #8A05B9 | Help and emergency |
| bg/raised · border/subtle | #3B3B3B | Trigger cards, tracks, outlines |

Use one status color per view. Lifestyle pink (#FF0099) and Dark Blue (#0524C8) are brand-only, so never use them in a Live Activity.

### Day & night (modes of the `MTA Color` collection)
| Token | Night (Dark) | Day (Light) |
|---|---|---|
| bg/surface | #000000 | #FFFFFF |
| bg/raised | #3B3B3B | #F5F5F5 |
| text/primary | #FFFFFF | #000000 |
| text/secondary | #969696 | #3B3B3B |
| text/inverse · bg/inverse | #000000 · #F5F5F5 | #FFFFFF · #000000 |
| border/default · border/subtle | #FFFFFF · #3B3B3B | #000000 · #969696 |
| text/on-color | #FFFFFF | #FFFFFF |
| text/on-notice | #000000 | #000000 |
| status/* · accent · brand | unchanged | unchanged |

- **Theme:** the app follows the system appearance.
- **Glyphs and labels on a status fill** use `on-color`, or `on-notice` on yellow and orange. They never use `text/primary`, which flips with the theme.
- **Dynamic Island** (Expanded, Compact, Minimal) is always Night because it's black hardware.
- **Taxi Big-Card** is always Night, for maximum contrast when you show it to a driver.
- **In Figma:**
  - The Live Activities page has a "Day · Live Activities" set.
  - The Wire Flow page has a "Day mode" copy of the flow.
  - Foundations shows the Night and Day swatches.

## Type
- **Typeface:** Helvetica Neue on iOS. Figma uses Inter as a stand-in because Helvetica Neue isn't installed there, and Noto Sans JP for Japanese.
- **Tracking:** −1% on all styles. The Label style is UPPERCASE with +8% tracking.
- **Weights:** Bold for numbers and headlines, Medium for labels and buttons, Regular for body.

| Style | Size/Line | Weight |
|---|---|---|
| Display Large | 48/52 | Bold |
| Display Medium (Lock Screen hero) | 30/34 | Bold |
| Headline (Expanded hero) | 26/30 | Bold |
| Subhead Medium | 24/28 | Medium |
| Button 1 | 20/24 | Medium |
| Subhead Normal | 18/22 | Medium |
| Body 1 | 18/24 | Regular |
| Button 2 (trailing number, pill) | 16/20 | Medium |
| Body 2 | 14/18 | Regular |
| Label | 11/14 | Bold, uppercase |

The PDF's mobile table reuses the desktop line heights (for example 80 for 48pt), so mobile line heights are normalized to about 1.15–1.3×.

## Grid
- **App screens:** 4 columns · 30 margin · 15 gutter. This is the MTA mobile grid.
- **Lock Screen Live Activity and Expanded island:** 4 columns · 16 margin · 15 gutter, 16pt top/bottom inset. Size is 370 × 160 maximum on iPhone 17.
- **Compact island:** 250 × 37, with the bullet on the left and the number on the right.
- **Minimal island:** 37 × 37, bullet only.
- **Spacing:** 4 · 8 · 12 · 16 · 24 · 30, on a 4pt baseline.
- **Radius:** card 20, inner 12, pills and bullets fully round.

## Bullets (from the MTA subway line bullets)
- **Glyph** says what the item is: ✈ flight, H hotel, ↓ offline pack, ↻ catch-up, ✓ done.
- **Fill** is the current status color.
- **Sizes:** 32 on the Lock Screen and Expanded island, 24 on Compact and Minimal.

## Live Activity rules
1. **Content:** one reminder, one number, one action. Use at most one Pill; tapping anywhere else opens the matching screen through a deep link.
2. **Facts:** values come only from the Vault. No AI-generated text in a Live Activity.
3. **Offline:** countdowns use the system timer (`Text(timerInterval:)`), so they keep running offline.
4. **Copy:** write like a station sign, noun + time ("Check-out 11:00"), in two lines at most.
5. **Lifetime:** each activity covers one moment and lasts up to 8 hours. It ends with a final state and `dismissalPolicy: .after(+5 min)`.

## Reminder states
| # | State | Status | Trigger | Who updates it |
|---|---|---|---|---|
| 1 | Leave for airport | On track | Departure − 3 h | App, local |
| 2 | Leave now | Urgent | Leave-by − 30 min | Push (FCM) when online; the timer keeps counting offline |
| 3 | Offline pack missing | Obstacle | Before boarding, no destination pack | App, foreground |
| 4 | Hotel check-in | On track | First app open after landing | App, local, offline |
| 5 | Check-out | Urgent | Check-out day − 2 h | App, local |
| 6 | Waiting for Wi-Fi | Notice | Drafts queued on a metered or offline network | App (routing policy `deferToWiFi`) |
| 7 | All caught up | On track | Catch-up pass finished on Wi-Fi | App, cloud; then the activity ends |

## Journey Live Activity (v2)

- **Grid:** 4 columns inside 16 pt margins, 8 pt gutters. "What" spans columns 1–3 (detail 13/16 over title 26/32); "When" is column 4 (status or day word 11/16 over the time 26/32), so both sides line up. Bottom strip: card (cols 1–2) · Ask (col 3) · Done (col 4).
- **When:** under an hour → live countdown with the status word (ON TRACK · LEAVE NOW · NOW); later today → TODAY + clock time; tomorrow → TOMORROW; further → "THU 3 DEC" + time. Never a multi-day timer.
- **Track:** one segment per step; the last step ends at the goal (`bed.double.fill` / `airplane`). The vehicle (`tram.fill`, `bus.fill`, `figure.walk`, `figure.outdoor.cycle`, `car.fill`, `ferry.fill`) rides the segment you're on.
- **Cards:** train/bus → `tram.card.fill`; taxi → `car.fill`; walk/cycle → `map.fill`; check-in → `doc.text.fill` "Show booking"; arrived → `key.fill` "Room info".
- **Done** (App Intent) marks the step finished; a step also ends when the next one starts. Arrived shows the ref and check-out from the booking for 2 h.
- **Notifications:** one per step, "Step 2 of 3 · …"; long-press: Show card · Done · Ask Travel Copilot.
- **Blue button:** 48 pt brand button with "NEED HELP? · ASK ANYTHING!" slowly circling it clockwise (one turn every 24 s) (84 pt with the ring; still under Reduce Motion). It stays at the side (Home, Trip, and above the Map sheet) and there is no chat bar on any screen: tapping it opens Blue's chat page.
- **Blue · Chat** (Figma: App Screens → "Blue · Chat flow"): laid out like Messages. Header is Blue's logo and name; Blue says hi and offers suggestions built from saved bookings; your question is a blue bubble on the right; Blue types (three dots), then answers in a grey bubble on the left with its logo — big value, one line, the booking it came from — and a green caption (ON-DEVICE · time · FROM YOUR BOOKING), followed by two follow-up suggestions. Small talk gets a help reply, never a booking value. The あ button left of the field switches to Say in <language>.
- **Catch-up pass** (Figma: App Screens → "Catch-up pass · flow"; built in `AI/CatchUpService.swift`): on-device translations are drafts (orange caption ON-DEVICE · DRAFT). When good Wi-Fi returns, Home shows a black toast "Back online · improving N translations…" and the orange Drafts tile counts down; on roaming / Low Data it waits and offers Improve now. The same chat bubble updates: improved text, the draft struck through, one blue ✦ line saying what changed, green caption IMPROVED IN THE CLOUD. Code checks numbers, doses and medicine names are identical; if not, the draft is kept with a red Check this box. The Log shows draft → improved with a summary strip.
