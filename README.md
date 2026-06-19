# booking_widget_elm

🇷🇺 [Читать на русском](./README-RU.md)

An [Elm](https://elm-lang.org) (The Elm Architecture) reimplementation of the
Vue 3 hotel booking widget in `../booking_widget`, built to measure how many of
the original's **correctness holes** a pure TEA architecture with a strong,
inference-driven type system closes structurally — not by remembering to be careful.

Same domain, same deterministic availability data, same flow (dates → guests →
room → review → confirm), same ru/en i18n, theme toggle, calendar, and a
mock/http data boundary. The difference is entirely in *how state is modelled and
transitions are expressed*.

See **[COMPARISON.md](./COMPARISON.md)** for the full audit-to-architecture
mapping (12 of 13 holes closed structurally, 1 in practice, 0 left open).

## Architecture

| Concern | File |
|---------|------|
| Domain — pure types & rules, no `Browser`/`Html` | `src/Domain/` |
| Calendar dates on `justinmimbs/date` (no time, no zone) | `src/Domain/Date.elm` |
| Opaque `BookableDate` — past dates can't be constructed | `src/Domain/BookableDate.elm` |
| Model — sum types that make bad states unrepresentable | `src/Model.elm` |
| `ValidBooking` smart constructor + `Phase` that carries it | `src/Model.elm` |
| Pure `update` — total over `Msg`, request-id staleness | `src/Update.elm` |
| Data port + adapters (mock with delay / http with decoders) | `src/Api.elm`, `src/Api/` |
| Typed error channel (`ApiError` ADT) | `src/Api/Types.elm` |
| i18n — exhaustive locale matching, hand-rolled formatting | `src/I18n.elm` |
| View — the `Html` tree, built from a small UI kit | `src/View.elm`, `src/Ui.elm` |
| Startup flags (`today`, theme, api url) + ports | `src/Main.elm`, `src/Ports.elm`, `src/main.ts` |
| Tests — property-based datetime, domain, i18n, `update` "stories" | `tests/` |

## Commands

```bash
npm install
npm run dev        # Vite dev server at http://localhost:5173
npm run build      # production build (elm make --optimize via vite-plugin-elm)
npm test           # elm-test: 77 unit / property / update-story tests
npm run typecheck  # elm make --output=/dev/null
npm run lint       # elm-format --validate
```

By default the widget runs against an in-memory mock adapter (simulated network
latency, loading/error states). Set `VITE_API_URL` (see `.env.example`) to point
the JSON-decoding HTTP adapter at a real backend — the only line that changes.

## Property-based testing

The pure calendar-day core in `src/Domain/Date.elm` is covered by
[`elm-test`](https://github.com/elm-explorations/test) **fuzz** tests in
`tests/DomainDateTest.elm` — instead of hand-picked examples, each test asserts
an **invariant** over hundreds of randomly generated calendar dates, and any
counterexample is automatically shrunk to its minimal form. Checked properties
include:

- `eachDayInRange` — empty iff `to < from`, length `= daysBetween + 1`, one-day
  steps, every entry within `[from, to]`
- `stayNights` — check-in inclusive / check-out exclusive (never the checkout day)
- `nightsBetween` — never negative; `nights(a, a+n) == max(n, 0)`
- `toIsoKey` — always `YYYY-MM-DD`, round-trips through `Date.fromIsoString`, injective

The rest of the suite drives the pure `update` with sequences of messages and
asserts the resulting model ("story" tests), plus exact-string tests pinning the
hand-rolled currency/date formatting.

## License

MIT
