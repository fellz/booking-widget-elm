module UpdateTest exposing (suite)

{-| "Story" tests for the pure `update`: drive the model with messages and assert
the resulting state, ignoring the emitted commands.
-}

import Api.Mock
import Api.Types
import Calendar
import Date exposing (Date)
import Domain.BookableDate as BookableDate exposing (BookableDate)
import Domain.Date
import Domain.Rooms
import Domain.Types exposing (Locale(..), RoomId(..), Selection(..))
import Expect
import Model exposing (CalendarState(..), Model, Msg(..), Phase(..), RoomSelection(..), RoomsState(..), Theme(..))
import Set
import Test exposing (Test, describe, test)
import Time exposing (Month(..))
import Update exposing (update)


d : Int -> Date
d day =
    Date.fromCalendarDate 2026 Jun day


{-| A `BookableDate` for a raw date, anchored well before any test date so it
always constructs. `BookableDate` is opaque, so this is the only way to write an
expected `Selection` in a test.
-}
bdOf : Date -> BookableDate
bdOf date =
    case BookableDate.fromDate (d 1) date of
        Just b ->
            b

        Nothing ->
            Debug.todo "test date should be bookable"


bd : Int -> BookableDate
bd day =
    bdOf (d day)


base : Model
base =
    { today = d 19
    , assetBase = ""
    , locale = Ru
    , theme = Light
    , phase = Editing
    , selection = NoSelection
    , guests = 2
    , roomSelection = NoRoom
    , rooms = RoomsReady Domain.Rooms.rooms
    , roomsRequestId = 0
    , calendarRequestId = 0
    , monthCursor = Calendar.firstOfMonth (d 19)
    , api = Api.Mock.withDelays { rooms = 0, calendar = 0, submit = 0 }
    }


{-| The window a freshly-loaded calendar covers in these tests: today .. today+180.
-}
windowTo : Date
windowTo =
    Domain.Date.addDays Model.horizonDays (d 19)


readyEmpty : CalendarState
readyEmpty =
    CalReady (d 19) windowTo Set.empty


step : Msg -> Model -> Model
step msg model =
    update msg model |> Tuple.first


steps : List Msg -> Model -> Model
steps msgs model =
    List.foldl step model msgs


suite : Test
suite =
    describe "Update"
        [ describe "selectDate state machine"
            [ test "first click sets the check-in" <|
                \_ ->
                    (step (SelectDate (d 22)) base).selection
                        |> Expect.equal (CheckIn (bd 22))
            , test "a later second click completes the range" <|
                \_ ->
                    (steps [ SelectDate (d 22), SelectDate (d 25) ] base).selection
                        |> Expect.equal (Range (bd 22) (bd 25))
            , test "clicking the start again clears the range" <|
                \_ ->
                    (steps [ SelectDate (d 22), SelectDate (d 25), SelectDate (d 22) ] base).selection
                        |> Expect.equal NoSelection
            , test "clicking before the check-in restarts the selection" <|
                \_ ->
                    (steps [ SelectDate (d 22), SelectDate (d 20) ] base).selection
                        |> Expect.equal (CheckIn (bd 20))
            , test "with a full range, a later click moves the end" <|
                \_ ->
                    (steps [ SelectDate (d 22), SelectDate (d 25), SelectDate (d 28) ] base).selection
                        |> Expect.equal (Range (bd 22) (bd 28))
            , test "a past day (before today) is refused outright (audit hole 5.2)" <|
                \_ ->
                    -- base.today is the 19th; the 18th can't become a BookableDate.
                    (step (SelectDate (d 18)) base).selection
                        |> Expect.equal NoSelection
            ]
        , describe "selectRoom"
            [ test "picking a room starts loading its calendar" <|
                \_ ->
                    let
                        m =
                            step (SelectRoom Comfort) base
                    in
                    ( Model.selectedRoomId m, Model.roomCalendar m, m.calendarRequestId )
                        |> Expect.equal ( Just Comfort, Just CalLoading, 1 )
            , test "clicking the selected room again deselects and clears" <|
                \_ ->
                    let
                        m =
                            steps [ SelectRoom Comfort, SelectRoom Comfort ] base
                    in
                    ( Model.selectedRoomId m, Model.roomCalendar m )
                        |> Expect.equal ( Nothing, Nothing )
            ]
        , describe "setGuests"
            [ test "drops a selected room that can no longer host the party" <|
                \_ ->
                    let
                        m =
                            steps [ SelectRoom Standard, SetGuests 3 ] base
                    in
                    ( Model.selectedRoomId m, Model.roomCalendar m )
                        |> Expect.equal ( Nothing, Nothing )
            , test "keeps a room that still fits" <|
                \_ ->
                    let
                        m =
                            steps [ SelectRoom Family, SetGuests 4 ] base
                    in
                    Model.selectedRoomId m |> Expect.equal (Just Family)
            ]
        , describe "calendar staleness"
            [ test "a stale response (older request id) is ignored" <|
                \_ ->
                    let
                        loading =
                            step (SelectRoom Comfort) base

                        -- request id is now 1; a reply tagged 0 is stale.
                        m =
                            step (CalendarLoaded 0 (Ok [ "2026-06-20" ])) loading
                    in
                    Model.roomCalendar m |> Expect.equal (Just CalLoading)
            , test "the current response is applied, carrying the fetch window" <|
                \_ ->
                    let
                        loading =
                            step (SelectRoom Comfort) base

                        m =
                            step (CalendarLoaded loading.calendarRequestId (Ok [ "2026-06-20" ])) loading
                    in
                    Model.roomCalendar m
                        |> Expect.equal (Just (CalReady (d 19) windowTo (Set.fromList [ "2026-06-20" ])))
            ]
        , describe "catalogue staleness"
            [ test "a stale rooms response (older request id) is ignored" <|
                \_ ->
                    let
                        loading =
                            step LoadRooms { base | rooms = RoomsError }

                        m =
                            step (RoomsLoaded 0 (Ok Domain.Rooms.rooms)) loading
                    in
                    m.rooms |> Expect.equal RoomsLoading
            , test "the current rooms response is applied" <|
                \_ ->
                    let
                        loading =
                            step LoadRooms base

                        m =
                            step (RoomsLoaded loading.roomsRequestId (Err Api.Types.NetworkError)) loading
                    in
                    m.rooms |> Expect.equal RoomsError
            ]
        , describe "calendar retry"
            [ test "RetryCalendar reloads the selected room's calendar" <|
                \_ ->
                    let
                        errored =
                            { base | roomSelection = RoomChosen Comfort CalError, calendarRequestId = 2 }

                        m =
                            step RetryCalendar errored
                    in
                    ( Model.roomCalendar m, m.calendarRequestId ) |> Expect.equal ( Just CalLoading, 3 )
            , test "RetryCalendar is a no-op with no room selected" <|
                \_ ->
                    step RetryCalendar base |> Model.roomCalendar |> Expect.equal Nothing
            ]
        , describe "phase flow gating"
            [ test "review is refused while the booking is invalid" <|
                \_ ->
                    (step Review base).phase |> phaseTag |> Expect.equal "Editing"
            , test "review is allowed once the booking is valid" <|
                \_ ->
                    (step Review validModel).phase |> phaseTag |> Expect.equal "Reviewing"
            , test "confirm from review starts a real submit" <|
                \_ ->
                    (steps [ Review, Confirm ] validModel).phase |> phaseTag |> Expect.equal "Submitting"
            , test "confirm from editing is a no-op (no review payload)" <|
                \_ ->
                    (step Confirm validModel).phase |> phaseTag |> Expect.equal "Editing"
            , test "edit returns to the editing step" <|
                \_ ->
                    (steps [ Review, Edit ] validModel).phase |> phaseTag |> Expect.equal "Editing"
            ]
        , describe "submit outcome"
            [ test "a successful submit confirms with the reference" <|
                \_ ->
                    let
                        m =
                            steps [ Review, Confirm, BookingSubmitted (Ok "BK-REF") ] validModel
                    in
                    case m.phase of
                        Confirmed _ ref ->
                            ref |> Expect.equal "BK-REF"

                        other ->
                            Expect.fail ("expected Confirmed, got " ++ phaseTag other)
            , test "a failed submit lands in SubmitFailed, keeping the cause" <|
                \_ ->
                    case (steps [ Review, Confirm, BookingSubmitted (Err Api.Types.RoomTaken) ] validModel).phase of
                        SubmitFailed _ err ->
                            err |> Expect.equal Api.Types.RoomTaken

                        other ->
                            Expect.fail ("expected SubmitFailed, got " ++ phaseTag other)
            , test "retry from SubmitFailed re-enters Submitting (not a no-op)" <|
                \_ ->
                    (steps [ Review, Confirm, BookingSubmitted (Err Api.Types.SubmitNetwork), Confirm ] validModel).phase
                        |> phaseTag
                        |> Expect.equal "Submitting"
            , test "a submit result arriving outside Submitting is ignored" <|
                \_ ->
                    (step (BookingSubmitted (Ok "BK-REF")) validModel).phase
                        |> phaseTag
                        |> Expect.equal "Editing"
            ]
        , describe "horizon (audit hole 5.1)"
            [ test "a stay reaching past the fetch horizon is not valid" <|
                \_ ->
                    let
                        m =
                            { base
                                | roomSelection = RoomChosen Standard readyEmpty
                                , calendarRequestId = 1
                                , selection =
                                    Range (bdOf (Domain.Date.addDays 1 windowTo)) (bdOf (Domain.Date.addDays 3 windowTo))
                            }
                    in
                    Model.isValid m |> Expect.equal False
            ]
        , describe "reset"
            [ test "clears the whole booking" <|
                \_ ->
                    let
                        m =
                            step Reset validModel
                    in
                    ( m.selection, m.guests, Model.selectedRoomId m )
                        |> Expect.equal ( NoSelection, 2, Nothing )
            ]
        ]


phaseTag : Phase -> String
phaseTag phase =
    case phase of
        Editing ->
            "Editing"

        Reviewing _ ->
            "Reviewing"

        Submitting _ ->
            "Submitting"

        SubmitFailed _ _ ->
            "SubmitFailed"

        Confirmed _ _ ->
            "Confirmed"


{-| A fully valid booking: a fitting room with a resolved (empty) calendar and a
clean date range, so `isValid` holds.
-}
validModel : Model
validModel =
    { base
        | selection = Range (bd 22) (bd 25)
        , roomSelection = RoomChosen Standard readyEmpty
        , calendarRequestId = 1
    }
