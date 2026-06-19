module Domain.Date exposing
    ( addDays
    , daysBetween
    , eachDayInRange
    , isBefore
    , isSameDay
    , toIsoKey
    )

{-| Thin calendar-day helpers over `justinmimbs/date`. A `Date` here is a pure
calendar day (a rata-die integer) with no time-of-day and no zone — exactly the
right model for hotel bookings. This is what structurally removes the original's
timezone hole: client `stayNights` and server `blockedDates` are compared as
calendar days, never as `Date` objects whose meaning shifts with the runtime's
zone. The single zone boundary is converting "now" to a `Date` at startup
(`Main`/`entry.ts`), and that conversion never leaks back into comparisons.
-}

import Date exposing (Date)


{-| A new date shifted by `amount` days (may be negative).
-}
addDays : Int -> Date -> Date
addDays amount date =
    Date.add Date.Days amount date


{-| Whole calendar days between two dates (b - a). Negative if b precedes a.
-}
daysBetween : Date -> Date -> Int
daysBetween a b =
    Date.diff Date.Days a b


isSameDay : Date -> Date -> Bool
isSameDay a b =
    daysBetween a b == 0


{-| `isBefore a b` is True when `a` is strictly earlier than `b`.
-}
isBefore : Date -> Date -> Bool
isBefore a b =
    daysBetween a b > 0


{-| Inclusive list of every calendar day from `from` to `to`. Empty if to < from.
-}
eachDayInRange : Date -> Date -> List Date
eachDayInRange from to =
    -- Date.range's end is exclusive, so push it one day past `to`.
    Date.range Date.Day 1 from (addDays 1 to)


{-| Stable `YYYY-MM-DD` key, handy for sets/maps and tests.
-}
toIsoKey : Date -> String
toIsoKey date =
    Date.toIsoString date
