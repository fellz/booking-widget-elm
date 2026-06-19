module BookingTest exposing (suite)

import Date
import Domain.BookableDate as BookableDate exposing (BookableDate)
import Domain.Booking exposing (calcTotal, nightsBetween, roomsForGuests, validateBooking)
import Domain.Rooms
import Domain.Types exposing (BookingError(..), RoomId(..), Selection(..))
import Expect
import Test exposing (Test, describe, test)
import Time exposing (Month(..))


d : Int -> Date.Date
d day =
    Date.fromCalendarDate 2026 Jun day


{-| A `BookableDate` for the given June day, anchored well before any test date so
construction always succeeds. (`BookableDate` is opaque; this is the only way to
build one in a test.)
-}
bd : Int -> BookableDate
bd day =
    case BookableDate.fromDate (d 1) (d day) of
        Just b ->
            b

        Nothing ->
            Debug.todo "test date should be bookable"


roomOf : RoomId -> Maybe Domain.Types.Room
roomOf id =
    Domain.Rooms.rooms |> List.filter (\r -> r.id == id) |> List.head


suite : Test
suite =
    describe "Domain.Booking"
        [ describe "nightsBetween"
            [ test "zero for no selection" <|
                \_ -> nightsBetween NoSelection |> Expect.equal 0
            , test "zero for a single check-in" <|
                \_ -> nightsBetween (CheckIn (bd 10)) |> Expect.equal 0
            , test "counts nights for a valid range" <|
                \_ -> nightsBetween (Range (bd 10) (bd 13)) |> Expect.equal 3
            ]
        , describe "roomsForGuests"
            [ test "keeps rooms that can host the party" <|
                \_ ->
                    roomsForGuests Domain.Rooms.rooms 3
                        |> List.map .id
                        |> Expect.equal [ Comfort, Family ]
            , test "five guests leaves only the family room" <|
                \_ ->
                    roomsForGuests Domain.Rooms.rooms 5
                        |> List.map .id
                        |> Expect.equal [ Family ]
            ]
        , describe "calcTotal"
            [ test "multiplies price by nights" <|
                \_ -> calcTotal 4500 3 |> Expect.equal 13500
            ]
        , describe "validateBooking"
            [ test "no dates and no room → noDates + noRoom" <|
                \_ ->
                    validateBooking NoSelection 2 Nothing
                        |> Expect.equal [ NoDates, NoRoom ]
            , test "only a check-in → noCheckOut" <|
                \_ ->
                    validateBooking (CheckIn (bd 10)) 2 (roomOf Standard)
                        |> Expect.equal [ NoCheckOut ]
            , test "a complete, fitting booking → no errors" <|
                \_ ->
                    validateBooking (Range (bd 10) (bd 13)) 2 (roomOf Standard)
                        |> Expect.equal []
            , test "party larger than capacity → capacityExceeded" <|
                \_ ->
                    validateBooking (Range (bd 10) (bd 13)) 3 (roomOf Standard)
                        |> Expect.equal [ CapacityExceeded ]
            , test "no room chosen but dates valid → noRoom only" <|
                \_ ->
                    validateBooking (Range (bd 10) (bd 13)) 2 Nothing
                        |> Expect.equal [ NoRoom ]

            -- The old "check-in before today → PastDates" test is gone: a past
            -- check-in can no longer be constructed (`Selection` carries
            -- `BookableDate`), so the case is unrepresentable. The rejection is
            -- now covered by `BookableDateTest` instead.
            ]
        ]
