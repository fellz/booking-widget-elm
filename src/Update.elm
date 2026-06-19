module Update exposing (selectDate, update)

{-| The pure heart of the widget. `update` is total over `Msg`, so adding a
message is a compile error until it's handled — there is no silent fall-through.
Effects (catalogue/calendar loads, theme/lang side effects) are returned as
commands, never performed inline.
-}

import Calendar exposing (shiftMonth)
import Date exposing (Date)
import Domain.BookableDate as BookableDate exposing (BookableDate)
import Domain.Date exposing (addDays, isBefore, isSameDay)
import Domain.Types exposing (Locale(..), RoomId, Selection(..))
import Model exposing (CalendarState(..), Model, Msg(..), Phase(..), RoomSelection(..), RoomsState(..), Theme(..), ValidBooking, horizonDays, maxMonthCursor, selectedRoom, selectedRoomId, validBooking)
import Ports
import Set


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetLocale locale ->
            ( { model | locale = locale }, Ports.setLang (langCode locale) )

        ToggleTheme ->
            let
                next =
                    toggleTheme model.theme
            in
            ( { model | theme = next }, Ports.setTheme (themeCode next) )

        PrevMonth ->
            ( { model | monthCursor = shiftMonth -1 model.monthCursor }, Cmd.none )

        NextMonth ->
            -- Clamp to the horizon: there is no availability data beyond it.
            let
                next =
                    shiftMonth 1 model.monthCursor
            in
            ( if isBefore (maxMonthCursor model) next then
                model

              else
                { model | monthCursor = next }
            , Cmd.none
            )

        SelectDate date ->
            -- The view only emits this for selectable days (not past/occupied);
            -- `selectDate` still refuses a past day via `BookableDate`, so the
            -- rule holds even if a click slips through.
            ( { model | selection = selectDate model.today date model.selection }, Cmd.none )

        SetGuests count ->
            ( setGuests count model, Cmd.none )

        SelectRoom id ->
            selectRoom id model

        Review ->
            -- Move to review only with a booking the type vouches for.
            ( case validBooking model of
                Just booking ->
                    { model | phase = Reviewing booking }

                Nothing ->
                    model
            , Cmd.none
            )

        Edit ->
            ( { model | phase = Editing }, Cmd.none )

        Confirm ->
            -- Submit the already-validated booking. Reachable from review and
            -- (as retry) from a failed submit — handling both here avoids the
            -- "retry is a silent no-op" bug the Effect sibling hit.
            case model.phase of
                Reviewing booking ->
                    submit booking model

                SubmitFailed booking _ ->
                    submit booking model

                _ ->
                    ( model, Cmd.none )

        BookingSubmitted result ->
            -- Apply the outcome only while a submit is in flight.
            ( case model.phase of
                Submitting booking ->
                    case result of
                        Ok ref ->
                            { model | phase = Confirmed booking ref }

                        Err err ->
                            { model | phase = SubmitFailed booking err }

                _ ->
                    model
            , Cmd.none
            )

        Reset ->
            ( clearRoom
                { model
                    | selection = NoSelection
                    , guests = 2
                    , phase = Editing
                }
            , model.api.cancelCalendar
            )

        LoadRooms ->
            let
                newId =
                    model.roomsRequestId + 1
            in
            ( { model | rooms = RoomsLoading, roomsRequestId = newId }
            , model.api.getRooms (RoomsLoaded newId)
            )

        RetryCalendar ->
            case selectedRoomId model of
                Just roomId ->
                    startCalendarLoad roomId model

                Nothing ->
                    ( model, Cmd.none )

        RoomsLoaded requestId result ->
            -- Ignore a stale catalogue response superseded by a newer request.
            if requestId /= model.roomsRequestId then
                ( model, Cmd.none )

            else
                case result of
                    Ok rooms ->
                        ( { model | rooms = RoomsReady rooms }, Cmd.none )

                    Err _ ->
                        ( { model | rooms = RoomsError }, Cmd.none )

        CalendarLoaded requestId result ->
            -- Ignore a stale response superseded by a newer request, or one that
            -- arrives after the room was deselected.
            if requestId /= model.calendarRequestId then
                ( model, Cmd.none )

            else
                case model.roomSelection of
                    RoomChosen id _ ->
                        let
                            calendar =
                                case result of
                                    Ok keys ->
                                        CalReady model.today (addDays horizonDays model.today) (Set.fromList keys)

                                    Err _ ->
                                        CalError
                        in
                        ( { model | roomSelection = RoomChosen id calendar }, Cmd.none )

                    NoRoom ->
                        ( model, Cmd.none )



-- ACTIONS


{-| Calendar click handler implementing range selection:

  - a past day (before `today`) is refused outright — `BookableDate.fromDate`
    returns `Nothing`, so the selection is left untouched and `PastDates` can
    never enter the model (audit hole 5.2);
  - 1st click sets the start A;
  - 2nd click after A sets the end B;
  - once A–B is set, clicking A clears the range, while any later day moves the
    end B there (clicking before A starts a fresh selection).

The `Range` constructor is only ever built when `checkIn < date`, so the
invariant "check-in is before check-out" holds by construction.

-}
selectDate : Date -> Date -> Selection -> Selection
selectDate today date selection =
    case BookableDate.fromDate today date of
        Nothing ->
            selection

        Just bookable ->
            case selection of
                NoSelection ->
                    CheckIn bookable

                CheckIn checkIn ->
                    if isBefore (BookableDate.toDate checkIn) date then
                        Range checkIn bookable

                    else
                        CheckIn bookable

                Range checkIn _ ->
                    if isSameDay date (BookableDate.toDate checkIn) then
                        NoSelection

                    else if isBefore (BookableDate.toDate checkIn) date then
                        Range checkIn bookable

                    else
                        CheckIn bookable


{-| Start the submit effect, moving into the `Submitting` state. The result comes
back as `BookingSubmitted`.
-}
submit : ValidBooking -> Model -> ( Model, Cmd Msg )
submit booking model =
    ( { model | phase = Submitting booking }
    , model.api.submitBooking
        { roomId = booking.room.id
        , checkIn = BookableDate.toDate booking.checkIn
        , checkOut = BookableDate.toDate booking.checkOut
        }
        BookingSubmitted
    )


setGuests : Int -> Model -> Model
setGuests count model =
    let
        next =
            { model | guests = count }
    in
    case selectedRoom model of
        Just room ->
            if room.capacity < count then
                -- Drop a selection that can no longer host the party.
                clearRoom next

            else
                next

        Nothing ->
            next


selectRoom : RoomId -> Model -> ( Model, Cmd Msg )
selectRoom id model =
    if selectedRoomId model == Just id then
        -- Clicking the selected room again deselects it and aborts its load.
        ( clearRoom model, model.api.cancelCalendar )

    else
        startCalendarLoad id model


startCalendarLoad : RoomId -> Model -> ( Model, Cmd Msg )
startCalendarLoad roomId model =
    let
        newId =
            model.calendarRequestId + 1

        from =
            model.today

        to =
            addDays horizonDays from
    in
    ( { model | roomSelection = RoomChosen roomId CalLoading, calendarRequestId = newId }
      -- Abort any request still in flight before starting the new one, so a
      -- rapid room switch doesn't leave a superseded connection running.
    , Cmd.batch
        [ model.api.cancelCalendar
        , model.api.getRoomCalendar roomId from to (CalendarLoaded newId)
        ]
    )


{-| Deselect the room (and so its calendar) and invalidate any in-flight request.
-}
clearRoom : Model -> Model
clearRoom model =
    { model | roomSelection = NoRoom, calendarRequestId = model.calendarRequestId + 1 }



-- HELPERS


toggleTheme : Theme -> Theme
toggleTheme theme =
    case theme of
        Dark ->
            Light

        Light ->
            Dark


themeCode : Theme -> String
themeCode theme =
    case theme of
        Dark ->
            "dark"

        Light ->
            "light"


langCode : Locale -> String
langCode locale =
    case locale of
        Ru ->
            "ru"

        En ->
            "en"
