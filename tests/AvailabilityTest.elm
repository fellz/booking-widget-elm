module AvailabilityTest exposing (suite)

import Date exposing (Date)
import Domain.Availability exposing (blockedDateKeys, isDateAvailable, isRangeAvailable, stayNights)
import Domain.Date exposing (addDays, toIsoKey)
import Domain.Types exposing (RoomId(..))
import Expect
import Fuzz exposing (Fuzzer)
import Set
import Test exposing (Test, describe, fuzz, test)
import Time exposing (Month(..))


dateFuzzer : Fuzzer Date
dateFuzzer =
    Fuzz.map Date.fromRataDie (Fuzz.intRange 737000 738000)


roomFuzzer : Fuzzer RoomId
roomFuzzer =
    Fuzz.oneOfValues [ Standard, Comfort, Family ]


suite : Test
suite =
    describe "Domain.Availability"
        [ describe "isDateAvailable (deterministic anchors against the documented rhythm)"
            [ test "standard is free on the epoch" <|
                \_ -> isDateAvailable Standard (Date.fromCalendarDate 2020 Jan 1) |> Expect.equal True
            , test "standard is blocked on 2020-01-09" <|
                \_ -> isDateAvailable Standard (Date.fromCalendarDate 2020 Jan 9) |> Expect.equal False
            , test "comfort is blocked on the epoch" <|
                \_ -> isDateAvailable Comfort (Date.fromCalendarDate 2020 Jan 1) |> Expect.equal False
            , test "family is free on the epoch" <|
                \_ -> isDateAvailable Family (Date.fromCalendarDate 2020 Jan 1) |> Expect.equal True
            , fuzz2dates "is deterministic (same args, same answer)" <|
                \room date ->
                    isDateAvailable room date |> Expect.equal (isDateAvailable room date)
            ]
        , describe "blockedDateKeys"
            [ fuzz dateFuzzer "a key is present iff that day is unavailable" <|
                \from ->
                    let
                        to =
                            addDays 30 from

                        keys =
                            blockedDateKeys Comfort from to

                        daysInRange =
                            Domain.Date.eachDayInRange from to
                    in
                    daysInRange
                        |> List.all (\day -> Set.member (toIsoKey day) keys == not (isDateAvailable Comfort day))
                        |> Expect.equal True
            ]
        , describe "isRangeAvailable"
            [ fuzz dateFuzzer "agrees with every stay night being free" <|
                \checkIn ->
                    let
                        checkOut =
                            addDays 5 checkIn
                    in
                    isRangeAvailable Standard checkIn checkOut
                        |> Expect.equal (List.all (isDateAvailable Standard) (stayNights checkIn checkOut))
            ]
        ]


fuzz2dates : String -> (RoomId -> Date -> Expect.Expectation) -> Test
fuzz2dates name run =
    Test.fuzz2 roomFuzzer dateFuzzer name run
