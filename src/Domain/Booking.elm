module Domain.Booking exposing
    ( calcTotal
    , nightsBetween
    , roomsForGuests
    , validateBooking
    )

{-| Pure booking calculations and structural validation. No view, no effects —
just the rules, so they can be unit-tested without rendering and reused anywhere.
-}

import Domain.BookableDate as BookableDate
import Domain.Date exposing (daysBetween, isBefore)
import Domain.Types exposing (BookingError(..), Room, Selection(..))


{-| Number of nights in a selection. Zero unless a full range is chosen.
-}
nightsBetween : Selection -> Int
nightsBetween selection =
    case selection of
        Range checkIn checkOut ->
            max 0 (daysBetween (BookableDate.toDate checkIn) (BookableDate.toDate checkOut))

        _ ->
            0


{-| Rooms whose capacity can host the requested number of guests.
-}
roomsForGuests : List Room -> Int -> List Room
roomsForGuests rooms guests =
    List.filter (\room -> room.capacity >= guests) rooms


{-| Total price for a stay, in the room's per-locale currency units.
-}
calcTotal : Int -> Int -> Int
calcTotal pricePerNight nights =
    pricePerNight * nights


{-| Validate the structural parts of a booking (dates, room choice, capacity),
returning stable error codes the UI maps to localized messages. Availability for
the chosen dates is decided separately (the store adds `DatesUnavailable`), since
it depends on fetched data.

The past-date rule isn't here anymore — it lives in the type. `Selection` carries
`BookableDate`, so a past check-in can't reach this function (audit hole 5.2,
closed structurally), and no `today` argument is needed. Likewise `Range` is only
ever built with `checkIn < checkOut`, so the `InvalidRange` branch is effectively
unreachable — kept only so the mapping stays faithful to the original error set.

-}
validateBooking : Selection -> Int -> Maybe Room -> List BookingError
validateBooking selection guests maybeRoom =
    let
        dateErrors =
            case selection of
                NoSelection ->
                    [ NoDates ]

                CheckIn _ ->
                    [ NoCheckOut ]

                Range checkIn checkOut ->
                    if isBefore (BookableDate.toDate checkIn) (BookableDate.toDate checkOut) then
                        []

                    else
                        [ InvalidRange ]

        roomErrors =
            case maybeRoom of
                Nothing ->
                    [ NoRoom ]

                Just room ->
                    if room.capacity < guests then
                        [ CapacityExceeded ]

                    else
                        []
    in
    dateErrors ++ roomErrors
