# booking_widget (Vue 3) → booking_widget_elm (Elm)

🇷🇺 [Читать на русском](./COMPARISON-RU.md)

A side-by-side rewrite of the same hotel-room booking widget, built to answer one
question: **how many of the original's correctness holes does a pure TEA
architecture in Elm close — structurally, not by remembering to be careful?**

Same domain, same deterministic availability data, same flow (dates → guests →
room → review → confirm), same ru/en i18n, theme toggle, calendar, and a
mock/http data boundary. The difference is entirely in *how state is modelled and
transitions are expressed*.

- Vue version: `../booking_widget`
- Effect/foldkit version: `../booking_widget_effect`
- Elm version: this project (`src/`)

Run it: `npm run dev`. Verify it: `npm test` (77 tests), `npm run typecheck`, `npm run build`.

---

## The architecture: full TEA

Elm *is* The Elm Architecture — the same loop the Effect/foldkit sibling
re-implements in TypeScript, here as the language's only way to build an app:

- **Model** — the entire app state in one immutable record (`src/Model.elm`). No
  component-local state.
- **Msg** — every input (clicks, command results) is a variant of one custom type
  (`Model.Msg`). Nothing happens that isn't a `Msg`.
- **update** — a single *pure* function `Msg -> Model -> (Model, Cmd Msg)`
  (`src/Update.elm`), matched with a `case` the compiler checks for
  exhaustiveness. It is the only place state transitions, and it performs no I/O.
- **view** — a pure function `Model -> Html Msg` (`src/View.elm`). The UI is a
  projection of the Model; it cannot hold state of its own.
- **Cmd** — side effects are *values* returned from `update`, run by the Elm
  runtime, which feeds their results back in as `Msg`s (`src/Api/`). The view never
  calls an API; it dispatches a `Msg`, `update` returns a `Cmd`.

`Browser.element` (`src/Main.elm`) closes the loop, with `Flags` for startup
inputs (`today`, theme, api url) and two `port`s for the only DOM writes that
escape the Elm root (theme on `<html>`, `<html lang>`).

---

## The audit

A correctness audit of the Vue widget found **13 holes** (the same set the Effect
sibling is scored against). "Structurally closed" = the bad state is unrepresentable
in the type/model, or a transition that would produce it is a compile error or an
exhaustiveness requirement — not a convention a future edit can quietly break.

| # | Hole (Vue) | Severity | Closed | How Elm closes it (or doesn't) |
|---|------------|----------|--------|--------------------------------|
| 4.1 | `DateRange = { checkIn, checkOut }` could hold `checkOut` set with `checkIn` null | LOW-MED | ✅ structural | `Selection = NoSelection \| CheckIn BookableDate \| Range BookableDate BookableDate`. The half-set state has no representation. `Range` is only ever constructed when `checkIn < date`, so "check-in before check-out" holds by construction. (`Domain.Types`, `Update.selectDate`) |
| 2.1 | `status: editing\|review\|confirmed` was a flag *decoupled* from validity, kept consistent only by conditional rendering | MED | ✅ structural | `Phase` has no bare review/confirmed flag: every post-editing variant (`Reviewing`/`Submitting`/`SubmitFailed`/`Confirmed`) **carries** a `ValidBooking` built only by the smart constructor `validBooking`. You cannot construct a confirmed booking without the validated payload that justifies it; the review and confirmation views take that payload, so "confirmed but nothing to show" is unrepresentable. (`Model.Phase`, `View`) |
| 3.1 | Booking spread across 4 refs + 1 reactive object; cross-field rules ("dropped room ⇒ clear calendar") held only because every mutator remembered to call them | MED | ✅ structural | One immutable `Model`, one pure `update`. Each transition returns a whole consistent state; there is no second writer to forget a rule. |
| 7.1 | Non-exhaustive `locale === 'ru' ? … : …` ternaries in 3 places — a third locale would silently format as `en-GB` | MED | ✅ structural | Locale is resolved by `case` on the `Locale` type in every formatting site (`messages`, `errorMessage`, `currencyCode`, month names…). A new locale is a compile error at each. (`I18n.elm`) |
| 1.1 | `loadRooms` had no request-invalidation → a slow/duplicated retry could overwrite fresh rooms or flip status to error while data is present | HIGH | ✅ structural | Both loads carry a monotonic request id; `update` discards any `RoomsLoaded`/`CalendarLoaded` whose id ≠ the model's current id. The Vue version had this for the calendar only; here it's uniform. (`Update.elm`) |
| 5.3 | Calendar load error = disabled button, no hint, no retry (the error branch was never rendered) | MED | ✅ structural | `CalendarState` includes `CalError`; the legend's `case` is exhaustive, so the error state *cannot* be silently skipped (the Vue branch was). It forces a visible, recoverable banner with a `RetryCalendar` action. (`Model.CalendarState`, `View.calendarLegend`) |
| 1.2 | Calendar's `today` (fetch time) could diverge from the picker's `today` (mount time) across midnight | LOW | ✅ structural | One `today` in the model, sourced once from a startup `Flag`. One value, used everywhere. |
| 4.2 | `calendarStatus === 'ready'` was representable with no room selected, and "ready" didn't guarantee the data existed | LOW | ✅ structural | Availability is *nested in the selection*: `RoomSelection = NoRoom \| RoomChosen RoomId CalendarState`. With no room there is no calendar field at all, and `CalReady from to (Set String)` carries the data, so "ready with no room" and "ready with no data" are both unrepresentable. (`Model.RoomSelection`/`CalendarState`) |
| 7.2 | `goToStep` hard-coded `index === 0 ⇒ edit()`; reordering steps silently breaks nav | LOW | ✅ structural | `Ui.steps` no longer takes `onSelect : Int -> msg`; each step carries its own `onBack : Maybe msg`, decided by an exhaustive `backMsg : Phase -> Step -> Maybe Msg` over a named `Step = ChooseStep \| ReviewStep \| DoneStep`. Navigation is by step *identity*, not position — there is no `index == 0` check to break, and the `GoToStep` message is gone. (`Ui.steps`, `View.backMsg`) |
| 6.1 | No request cancellation; superseded fetches completed and were merely ignored | LOW | ⚠️ partly | Now genuinely cancelled: the HTTP adapter issues `getRoomCalendar` with `tracker = Just "room-calendar"` and `cancelCalendar = Http.cancel …`, and `update` aborts the in-flight request on supersede/deselect/reset. The `requestId` guard stays as defense-in-depth. **Not** structural: a stale response can't be *forbidden* by a type — cancellation is a runtime effect, so this is "improved", not "closed by construction" (the mock has nothing to abort → `Cmd.none`). (`Api/Http.elm`, `Update.startCalendarLoad`) |
| 2.2 | `confirm()` set a flag and performed **no side effect** — the one operation that matters couldn't fail or report failure | MED | ✅ structural | Confirm dispatches a real `submitBooking` effect; `Phase` gains `Submitting`, `SubmitFailed ValidBooking SubmitError`, and `Confirmed ValidBooking String` (the backend reference). You cannot reach `Confirmed` without a reference from the effect. Failures travel a dedicated `SubmitError = SubmitNetwork \| SubmitServer Int \| RoomTaken` (409 → `RoomTaken`), and i18n renders a **distinct message per cause** (exhaustive `submitErrorMessage`). Retry resubmits from `SubmitFailed` (handled in `update`, so not the silent no-op the Effect sibling hit). (`Model.Phase`, `Update.submit`, `Api/`, `I18n`) |
| 5.1 | A stay beyond the 180-day fetch horizon was reported **available & bookable** — the busy-set simply had no data for those days | HIGH | ✅ structural | `CalReady` carries the *window* `from`/`to` it actually covers. `availabilityErrors` flags any stay reaching past that carried `to` as `AvailabilityUnknown` (not bookable) instead of silently free, and month navigation is clamped to the horizon month (next-button disables). The "bookable with no data" state can't occur through the UI or pass validation. (`Model.CalendarState`/`availabilityErrors`/`maxMonthCursor`) |
| 5.2 | Past-date rule lived **only** in the calendar UI (`isPast`); the domain accepted past dates from any other path | MED | ✅ structural | The rule moved into the *type*. An opaque `Domain.BookableDate` is built only by `fromDate today candidate`, which rejects a past day; `Selection` and `ValidBooking` carry `BookableDate`, so a past check-in is **unrepresentable** — there is no value to put in the model and no `PastDates` error left to forget (it's gone from `BookingError`). `validateBooking` no longer takes `today`. Cost: wrap/unwrap ceremony at the boundaries (`toDate` to render or submit). (`Domain.BookableDate`, `Domain.Types`, `Update.selectDate`) |

**Tally: 12 of 13 closed structurally, 1 closed in practice (cancellation is a
runtime effect, not a type), 0 left open.**

The honest read: the representation and exhaustiveness holes — impossible states,
decoupled flags, non-exhaustive matches, scattered state — close cleanly with sum
types and a total `update`. The headline is 2.1/2.2: `Phase` carries a
smart-constructed `ValidBooking` through review, submit, failure and confirmation,
so none of those screens can render without the data that justifies them; the
write side has its own typed `SubmitError` with a distinct message per cause. The
last batch went the same way: 5.2 moved the past-date rule into an opaque
`BookableDate` (a past check-in is now unrepresentable, not merely re-checked),
and 7.2 replaced the positional `index == 0` back-nav with per-step `onBack`
decided by an exhaustive `Phase × Step` match. The **one** hole that stays "in
practice" is 6.1: superseded calendar fetches are now genuinely cancelled (`Http`
`tracker` + `Http.cancel`), but a stale response can't be *forbidden* by a type —
cancellation is a runtime effect, so the `requestId` guard remains the real
correctness mechanism. On the 13-hole audit Elm now edges ahead (Elm 12/1/0,
Effect 9/4/0). Where the Effect sibling stays genuinely ahead is **outside** this
list: its Schema *is* the domain type at the IO boundary (decoder and type can't
drift — see below), and it expresses DI as a typed `Layer` graph rather than one
adapter record. Those are real, and not reachable in vanilla Elm.

---

## Two wins not in the 13-hole list

The original Vue README also listed type gaps that aren't TEA-state bugs. Elm
closes the two biggest by construction:

**1. The IO boundary — decoded, not asserted.** The Vue `httpBookingApi` did
`(await res.json()) as RoomDto[]` and `dto.id as RoomId` — `as` switches checking
off, so an unknown id, a missing field, or a wrong currency compiled fine and blew
up later (`roomImages[room.id]` → a broken image, no type error). The Elm HTTP
adapter runs every byte through a `Json.Decode.Decoder`, and `roomIdDecoder`
*fails decoding* on an unknown category instead of producing a broken `RoomId`
(`src/Api/Http.elm`). Bad input cannot reach the domain. Failures travel a typed
`ApiError` channel (`NetworkError | BadStatus Int | DecodeError String`) rather
than collapsing to one `'error'` boolean.

> The one caveat Elm shares with any hand-written-decoder approach: the decoder
> and the domain type are *separate* declarations and can drift (the Effect
> sibling's Schema-is-the-type avoids that). Here they're kept in one small file
> and exercised by the type checker at the call site, but it's a convention, not a
> guarantee.

**2. Timezones — gone, not normalised.** The Vue code normalised `Date` to local
midnight everywhere (`startOfDay` called defensively in `addDays`, `daysBetween`,
…) to dodge time-of-day bugs, and the README flagged TZ-key mismatches as a latent
invariant. Elm's `justinmimbs/date` `Date` is a pure calendar day (a rata-die
integer) — no time, no zone. The entire class of bug, and the defensive
normalisation, disappears. The single zone boundary is converting "now" to a
`Date` once at startup (`src/main.ts` → a flag); it never re-enters comparisons.

---

## What it cost

The closures are paid in **up-front modelling**, much like the Effect version but
with a lighter vocabulary:

- More named states: `Selection`, `RoomsState`, `CalendarState`, `Phase`, plus the
  `ValidBooking` smart-constructed payload — the states the Vue store tracked
  implicitly across refs.
- No `Intl`: currency, month names and Russian plurals are formatted by hand
  (`src/I18n.elm`). The upside is they're pure and unit-tested; the downside is the
  formatting is approximate (e.g. a fixed non-breaking-space thousands separator),
  not ICU-exact.
- The view is a verbose `Html` DSL with a hand-built UI kit instead of Vue's
  `<template>` + scoped CSS (the CSS itself is reused verbatim).

The payoff: the representation and exhaustiveness bugs an audit *found* in the Vue
version are, here, mostly things you cannot express or cannot forget — with the
whole flow covered by fast, deterministic `elm-test` (unit, property-based
datetime, and pure-`update` "story" tests; no DOM, no timer mocks).

---

## Tests (no DOM, no mocks)

Because TEA splits the pure `update` from `view` and from effects-as-values, the
logic is tested in isolation — `tests/UpdateTest.elm` drives the real `update`
with message sequences and asserts the resulting model (the date state machine,
the request-id staleness guard for both loads, the room/guest cross-field rule,
the phase gates, calendar retry). `tests/DomainDateTest.elm` is property-based
(fuzz) over the calendar core; `tests/BookingTest.elm` and `tests/I18nTest.elm`
pin the pure rules and the hand-rolled formatting. 77 tests, ~120 ms.

---

## Where the holes were closed (file map)

- Impossible states removed → `src/Model.elm` (`Selection`, `RoomsState`, `CalendarState`, `Phase`, `ValidBooking`) and `src/Domain/Types.elm`
- Past dates unrepresentable (opaque smart constructor) → `src/Domain/BookableDate.elm`
- Single source of validity + smart constructor → `Model.validBooking` / `Model.isValid`
- Step navigation by identity (per-step `onBack`) → `src/Ui.elm` (`steps`) / `View.backMsg`
- Request-id staleness + real calendar cancellation, total transitions → `src/Update.elm`
- Effects as values, decoded boundary, typed errors → `src/Api/` (`Types.elm`, `Mock.elm`, `Http.elm`)
- Calendar-date core (kills the TZ class) → `src/Domain/Date.elm`
- Exhaustive locale handling → `src/I18n.elm`
- Behavioural proof → `tests/`
