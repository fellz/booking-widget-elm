module DomainDateTest exposing (suite)

{-| Property-based tests for the pure calendar-day core. Instead of hand-picked
examples, each test asserts an invariant over hundreds of randomly generated
calendar dates; elm-test shrinks any counterexample to its minimal form. This is
the Elm counterpart to the fast-check suite in the foldkit/Effect port.
-}

import Date exposing (Date)
import Domain.Availability exposing (stayNights)
import Domain.BookableDate as BookableDate exposing (BookableDate)
import Domain.Booking exposing (nightsBetween)
import Domain.Date exposing (addDays, daysBetween, eachDayInRange, isBefore, isSameDay, toIsoKey)
import Domain.Types exposing (Selection(..))
import Expect
import Fuzz exposing (Fuzzer)
import Test exposing (Test, describe, fuzz, fuzz2)


{-| Calendar dates spanning roughly the years 1999–2028.
-}
dateFuzzer : Fuzzer Date
dateFuzzer =
    Fuzz.map Date.fromRataDie (Fuzz.intRange 730000 740000)


{-| Wrap a date as `BookableDate` for a `Selection`. The anchor day (rata die
700000, well before every fuzzed date) is always earlier, so construction
succeeds even for the negative-offset cases.
-}
bdOf : Date -> BookableDate
bdOf date =
    case BookableDate.fromDate (Date.fromRataDie 700000) date of
        Just b ->
            b

        Nothing ->
            Debug.todo "fuzzed date should be bookable"


{-| A day count offset, deliberately including negatives and zero.
-}
offsetFuzzer : Fuzzer Int
offsetFuzzer =
    Fuzz.intRange -10 40


suite : Test
suite =
    describe "Domain.Date (property-based)"
        [ describe "daysBetween / addDays"
            [ fuzz2 dateFuzzer offsetFuzzer "daysBetween a (addDays n a) == n" <|
                \date n ->
                    daysBetween date (addDays n date)
                        |> Expect.equal n
            , fuzz dateFuzzer "isSameDay is reflexive" <|
                \date ->
                    isSameDay date date
                        |> Expect.equal True
            , fuzz2 dateFuzzer (Fuzz.intRange 1 40) "isBefore d (addDays positive d)" <|
                \date n ->
                    isBefore date (addDays n date)
                        |> Expect.equal True
            ]
        , describe "eachDayInRange"
            [ fuzz2 dateFuzzer offsetFuzzer "empty iff to < from" <|
                \from n ->
                    let
                        to =
                            addDays n from
                    in
                    List.isEmpty (eachDayInRange from to)
                        |> Expect.equal (n < 0)
            , fuzz2 dateFuzzer (Fuzz.intRange 0 40) "length == daysBetween + 1 for from <= to" <|
                \from n ->
                    let
                        to =
                            addDays n from
                    in
                    List.length (eachDayInRange from to)
                        |> Expect.equal (n + 1)
            , fuzz2 dateFuzzer (Fuzz.intRange 0 40) "every entry is one day after the previous" <|
                \from n ->
                    let
                        days =
                            eachDayInRange from (addDays n from)

                        steps =
                            List.map2 (\a b -> daysBetween a b) days (List.drop 1 days)
                    in
                    List.all ((==) 1) steps
                        |> Expect.equal True
            , fuzz2 dateFuzzer (Fuzz.intRange 0 40) "all entries lie within [from, to]" <|
                \from n ->
                    let
                        to =
                            addDays n from
                    in
                    eachDayInRange from to
                        |> List.all (\day -> not (isBefore day from) && not (isBefore to day))
                        |> Expect.equal True
            ]
        , describe "stayNights (check-in inclusive, check-out exclusive)"
            [ fuzz2 dateFuzzer (Fuzz.intRange 1 40) "length == nights for a valid range" <|
                \checkIn n ->
                    List.length (stayNights checkIn (addDays n checkIn))
                        |> Expect.equal n
            , fuzz2 dateFuzzer (Fuzz.intRange 1 40) "never includes the check-out day" <|
                \checkIn n ->
                    let
                        checkOut =
                            addDays n checkIn
                    in
                    stayNights checkIn checkOut
                        |> List.any (\day -> isSameDay day checkOut)
                        |> Expect.equal False
            , fuzz2 dateFuzzer (Fuzz.intRange -10 0) "empty when checkout <= checkin" <|
                \checkIn n ->
                    stayNights checkIn (addDays n checkIn)
                        |> Expect.equal []
            ]
        , describe "nightsBetween"
            [ fuzz2 dateFuzzer (Fuzz.intRange -10 40) "equals max 0 n for Range a (a+n)" <|
                \checkIn n ->
                    nightsBetween (Range (bdOf checkIn) (bdOf (addDays n checkIn)))
                        |> Expect.equal (max 0 n)
            ]
        , describe "toIsoKey"
            [ fuzz dateFuzzer "matches YYYY-MM-DD" <|
                \date ->
                    isIsoShaped (toIsoKey date)
                        |> Expect.equal True
            , fuzz dateFuzzer "round-trips through Date.fromIsoString" <|
                \date ->
                    Date.fromIsoString (toIsoKey date)
                        |> Expect.equal (Ok date)
            , fuzz2 dateFuzzer offsetFuzzer "is injective (distinct days → distinct keys)" <|
                \date n ->
                    let
                        other =
                            addDays n date
                    in
                    Expect.equal (toIsoKey date == toIsoKey other) (n == 0)
            ]
        ]


{-| A dependency-free `YYYY-MM-DD` shape check: three dash-separated all-digit
parts of lengths 4, 2, 2.
-}
isIsoShaped : String -> Bool
isIsoShaped key =
    case String.split "-" key of
        [ year, month, day ] ->
            (String.length year == 4)
                && (String.length month == 2)
                && (String.length day == 2)
                && List.all allDigits [ year, month, day ]

        _ ->
            False


allDigits : String -> Bool
allDigits text =
    not (String.isEmpty text) && String.all Char.isDigit text
