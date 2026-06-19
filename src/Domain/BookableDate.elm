module Domain.BookableDate exposing
    ( BookableDate
    , fromDate
    , toDate
    )

{-| A calendar day that is known not to be in the past. The constructor is
**opaque**: the only way to make a `BookableDate` is `fromDate today candidate`,
which returns `Nothing` for a day before `today`. Once you hold one, the type is
proof the day is bookable.

This is what closes audit hole 5.2 structurally. The original enforced "no
past dates" with a UI check (the disabled calendar cell) plus a re-validation in
the store — two places that could drift. Here `Selection` and `ValidBooking`
carry `BookableDate`, so a past check-in is **unrepresentable**: there is no value
to put in the model, no `PastDates` error to forget, and the rule cannot be
bypassed by any caller. The cost is wrap/unwrap ceremony at the boundaries
(`toDate` to render or send, `fromDate` to admit a click).

-}

import Date exposing (Date)
import Domain.Date exposing (isBefore)


{-| A calendar day proven to be today or later. Opaque on purpose — see the
module doc.
-}
type BookableDate
    = BookableDate Date


{-| The single door from a raw `Date` into `BookableDate`. Returns `Nothing` when
`candidate` is strictly before `today`, so a past day can never be admitted.
`today` itself is bookable.
-}
fromDate : Date -> Date -> Maybe BookableDate
fromDate today candidate =
    if isBefore candidate today then
        Nothing

    else
        Just (BookableDate candidate)


{-| Recover the underlying calendar day — for rendering, range maths, or sending
to the backend. Total: every `BookableDate` wraps a real day.
-}
toDate : BookableDate -> Date
toDate (BookableDate date) =
    date
