module BookableDateTest exposing (suite)

{-| The smart constructor that replaces the old `PastDates` rule (audit hole 5.2).
A past day cannot become a `BookableDate`, so it cannot enter a `Selection`.
-}

import Date exposing (Date)
import Domain.BookableDate as BookableDate
import Expect
import Test exposing (Test, describe, test)
import Time exposing (Month(..))


d : Int -> Date
d day =
    Date.fromCalendarDate 2026 Jun day


today : Date
today =
    d 10


suite : Test
suite =
    describe "Domain.BookableDate"
        [ test "a day before today cannot be constructed" <|
            \_ ->
                BookableDate.fromDate today (d 9)
                    |> Expect.equal Nothing
        , test "today itself is bookable" <|
            \_ ->
                BookableDate.fromDate today today
                    |> Maybe.map BookableDate.toDate
                    |> Expect.equal (Just today)
        , test "a future day is bookable and round-trips through toDate" <|
            \_ ->
                BookableDate.fromDate today (d 20)
                    |> Maybe.map BookableDate.toDate
                    |> Expect.equal (Just (d 20))
        ]
