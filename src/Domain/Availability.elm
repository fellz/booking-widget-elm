module Domain.Availability exposing
    ( blockedDateKeys
    , isDateAvailable
    , isRangeAvailable
    , stayNights
    )

{-| Fake "already booked" dates. Real availability would come from a backend;
here we derive it deterministically from the date and room so that the demo is
reproducible and the tests are stable (no randomness). Each room follows its own
simple occupancy rhythm.
-}

import Date exposing (Date)
import Domain.Date exposing (daysBetween, eachDayInRange, toIsoKey)
import Domain.Types exposing (RoomId(..))
import Set exposing (Set)
import Time exposing (Month(..))


type alias Rhythm =
    { period : Int, blocked : Int, offset : Int }


rhythm : RoomId -> Rhythm
rhythm id =
    case id of
        Standard ->
            { period = 11, blocked = 2, offset = 3 }

        Comfort ->
            { period = 7, blocked = 2, offset = 1 }

        Family ->
            { period = 9, blocked = 3, offset = 5 }


{-| A fixed epoch keeps the day index stable regardless of "today".
-}
epoch : Date
epoch =
    Date.fromCalendarDate 2020 Jan 1


{-| True if the room is free on the given day.
-}
isDateAvailable : RoomId -> Date -> Bool
isDateAvailable id date =
    let
        r =
            rhythm id

        dayIndex =
            daysBetween epoch date + r.offset
    in
    -- Elm's modBy always returns a non-negative result for a positive divisor,
    -- so the manual `((x % n) + n) % n` guard from the TS version is unneeded.
    modBy r.period dayIndex >= r.blocked


{-| The nights actually slept in the room (check-in inclusive, check-out exclusive).
-}
stayNights : Date -> Date -> List Date
stayNights checkIn checkOut =
    if daysBetween checkIn checkOut <= 0 then
        []

    else
        let
            days =
                eachDayInRange checkIn checkOut
        in
        List.take (List.length days - 1) days


{-| True if every day of the (check-out exclusive) stay is free.
-}
isRangeAvailable : RoomId -> Date -> Date -> Bool
isRangeAvailable id checkIn checkOut =
    stayNights checkIn checkOut
        |> List.all (isDateAvailable id)


{-| Set of `YYYY-MM-DD` keys blocked for a room within a range — handy for the calendar.
-}
blockedDateKeys : RoomId -> Date -> Date -> Set String
blockedDateKeys id from to =
    eachDayInRange from to
        |> List.filter (\day -> not (isDateAvailable id day))
        |> List.map toIsoKey
        |> Set.fromList
