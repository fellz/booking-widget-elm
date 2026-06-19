module Model exposing
    ( CalendarState(..)
    , Model
    , Msg(..)
    , Phase(..)
    , RoomSelection(..)
    , RoomsState(..)
    , Theme(..)
    , ValidBooking
    , availableRooms
    , calendarReady
    , errors
    , horizonDays
    , horizonEnd
    , isConfirmed
    , isValid
    , maxGuests
    , maxMonthCursor
    , nights
    , roomCalendar
    , roomList
    , selectedRoom
    , selectedRoomBusy
    , selectedRoomId
    , stayNights
    , stepIndex
    , total
    , validBooking
    )

{-| The widget's single source of truth, plus the pure selectors derived from
it. Load states are sum types that carry exactly the data each state owns:
`RoomsReady` holds the catalogue, `CalReady` holds the blocked-date set. There is
no way to read `blockedDates` while the calendar is still loading, and no
`status` flag that could disagree with the data it describes — two of the
original's "flag and data can drift apart" risks are gone by construction.
-}

import Api.Types exposing (ApiError, BookingApi, SubmitError)
import Calendar
import Date exposing (Date)
import Domain.Availability
import Domain.BookableDate as BookableDate exposing (BookableDate)
import Domain.Booking exposing (nightsBetween, roomsForGuests, validateBooking)
import Domain.Date exposing (addDays, isBefore, toIsoKey)
import Domain.Types exposing (BookingError(..), Locale, LocalizedPrice, Room, RoomId, Selection(..))
import Set


type Theme
    = Light
    | Dark


{-| A booking that has passed validation, carrying the data that justifies it.
Built only through the smart constructor `validBooking`, so it cannot represent
an incomplete or invalid booking.
-}
type alias ValidBooking =
    { room : Room
    , checkIn : BookableDate
    , checkOut : BookableDate
    , nights : Int
    , total : LocalizedPrice
    }


{-| Where the user is in the booking flow. Unlike the original's
`status: 'editing' | 'review' | 'confirmed'` — a flag kept in sync with validity
only by conditional rendering — every post-editing variant **carries** a
`ValidBooking`. You cannot construct a confirmed booking without the validated
payload that justifies it (audit hole 2.1, closed structurally). The
`Submitting`/`SubmitFailed`/`Confirmed` states model the real submit effect and
its typed outcome (audit hole 2.2); `Confirmed` carries the backend reference,
`SubmitFailed` the typed `SubmitError` cause, both impossible to fabricate without
going through the effect.
-}
type Phase
    = Editing
    | Reviewing ValidBooking
    | Submitting ValidBooking
    | SubmitFailed ValidBooking SubmitError
    | Confirmed ValidBooking String


{-| Room-catalogue load state. The catalogue only exists once ready.
-}
type RoomsState
    = RoomsLoading
    | RoomsReady (List Room)
    | RoomsError


{-| A selected room's availability calendar. `CalReady` carries the _window_
`from`/`to` it actually covers alongside the blocked-date set, so "is this day
busy?" can only be asked when there's an answer, and "do we even have data for
this day?" is answerable from the data itself (audit hole 5.1). There is no idle
state: a chosen room is always at least loading.
-}
type CalendarState
    = CalLoading
    | CalReady Date Date (Set.Set String)
    | CalError


{-| Room selection with its availability nested inside. With no room chosen there
is no calendar field at all, so the original's "calendar ready with no room
selected" state is unrepresentable rather than guarded (audit hole 4.2).
-}
type RoomSelection
    = NoRoom
    | RoomChosen RoomId CalendarState


type alias Model =
    { today : Date
    , assetBase : String
    , locale : Locale
    , theme : Theme
    , phase : Phase
    , selection : Selection
    , guests : Int
    , roomSelection : RoomSelection
    , rooms : RoomsState

    -- Monotonic tokens: a response is applied only if it matches the latest
    -- request, so a slow/duplicated earlier reply can't overwrite fresh data.
    -- The Vue version had this guard for the calendar only; here both loads use
    -- it (closes audit hole 1.1 — a retried catalogue load racing a stale one).
    , roomsRequestId : Int
    , calendarRequestId : Int

    -- First day of the month shown in the calendar grid.
    , monthCursor : Date

    -- The injected data adapter (mock or http). Lives in the model so `update`
    -- can issue effects through it without a global.
    , api : BookingApi Msg
    }


type Msg
    = SetLocale Locale
    | ToggleTheme
    | PrevMonth
    | NextMonth
    | SelectDate Date
    | SetGuests Int
    | SelectRoom RoomId
    | Review
    | Edit
    | Confirm
    | Reset
    | LoadRooms
    | RetryCalendar
    | RoomsLoaded Int (Result ApiError (List Room))
    | CalendarLoaded Int (Result ApiError (List String))
    | BookingSubmitted (Result SubmitError String)



-- SELECTORS (the "computed" layer)


roomList : Model -> List Room
roomList model =
    case model.rooms of
        RoomsReady rooms ->
            rooms

        _ ->
            []


selectedRoomId : Model -> Maybe RoomId
selectedRoomId model =
    case model.roomSelection of
        NoRoom ->
            Nothing

        RoomChosen id _ ->
            Just id


{-| The chosen room's calendar, if a room is chosen.
-}
roomCalendar : Model -> Maybe CalendarState
roomCalendar model =
    case model.roomSelection of
        NoRoom ->
            Nothing

        RoomChosen _ calendar ->
            Just calendar


selectedRoom : Model -> Maybe Room
selectedRoom model =
    case selectedRoomId model of
        Nothing ->
            Nothing

        Just id ->
            roomList model
                |> List.filter (\room -> room.id == id)
                |> List.head


availableRooms : Model -> List Room
availableRooms model =
    roomsForGuests (roomList model) model.guests


{-| Upper bound for the guest stepper, derived from the loaded catalogue. While
the catalogue is empty we don't clamp the current value.
-}
maxGuests : Model -> Int
maxGuests model =
    case roomList model of
        [] ->
            model.guests

        rooms ->
            rooms
                |> List.map .capacity
                |> List.maximum
                |> Maybe.withDefault model.guests


nights : Model -> Int
nights model =
    nightsBetween model.selection


total : Model -> LocalizedPrice
total model =
    case selectedRoom model of
        Nothing ->
            { ru = 0, en = 0 }

        Just room ->
            { ru = room.pricePerNight.ru * nights model
            , en = room.pricePerNight.en * nights model
            }


{-| Nights actually slept (check-in inclusive, check-out exclusive).
-}
stayNights : Model -> List Date
stayNights model =
    case model.selection of
        Range checkIn checkOut ->
            Domain.Availability.stayNights (BookableDate.toDate checkIn) (BookableDate.toDate checkOut)

        _ ->
            []


calendarReady : Model -> Bool
calendarReady model =
    case roomCalendar model of
        Just (CalReady _ _ _) ->
            True

        _ ->
            False


{-| True when the selected room's loaded calendar shows the stay overlaps a busy
day. Reads the blocked set straight out of `CalReady`, so it is only ever true
when there is a real answer to read.
-}
selectedRoomBusy : Model -> Bool
selectedRoomBusy model =
    case roomCalendar model of
        Just (CalReady _ _ blocked) ->
            stayNights model
                |> List.any (\day -> Set.member (toIsoKey day) blocked)

        _ ->
            False


{-| How far ahead the per-room availability calendar is fetched. Availability is
only _known_ inside this window from `today`.
-}
horizonDays : Int
horizonDays =
    180


{-| The last day for which availability data exists.
-}
horizonEnd : Model -> Date
horizonEnd model =
    addDays horizonDays model.today


{-| The latest month the calendar may scroll to — the month containing the
horizon end. Past it there is no availability data, so navigation is clamped.
-}
maxMonthCursor : Model -> Date
maxMonthCursor model =
    Calendar.firstOfMonth (horizonEnd model)


errors : Model -> List BookingError
errors model =
    validateBooking model.selection model.guests (selectedRoom model)
        ++ availabilityErrors model


{-| Availability is only trustworthy once the room's calendar is ready. A stay
that overlaps a known busy day is `DatesUnavailable`; a stay reaching past the
window the calendar actually covers (its carried `to`) has _no data_, so it is
`AvailabilityUnknown` (not bookable) rather than silently treated as free —
closing audit hole 5.1 from the data itself.
-}
availabilityErrors : Model -> List BookingError
availabilityErrors model =
    case roomCalendar model of
        Just (CalReady _ to blocked) ->
            let
                nightsList =
                    stayNights model

                busy =
                    List.any (\day -> Set.member (toIsoKey day) blocked) nightsList

                beyondWindow =
                    List.any (\day -> isBefore to day) nightsList
            in
            if busy then
                [ DatesUnavailable ]

            else if beyondWindow then
                [ AvailabilityUnknown ]

            else
                []

        _ ->
            []


isValid : Model -> Bool
isValid model =
    if not (List.isEmpty (errors model)) then
        False

    else
        -- A picked room needs its calendar resolved before we trust availability.
        case ( selectedRoom model, model.selection ) of
            ( Just _, Range _ _ ) ->
                calendarReady model

            _ ->
                True


{-| The smart constructor for `ValidBooking`: the single door from a `Model` to a
booking the type system will vouch for. Returns `Nothing` unless a room is chosen,
a full date range is set, and `isValid` holds.
-}
validBooking : Model -> Maybe ValidBooking
validBooking model =
    case ( selectedRoom model, model.selection ) of
        ( Just room, Range checkIn checkOut ) ->
            if isValid model then
                Just
                    { room = room
                    , checkIn = checkIn
                    , checkOut = checkOut
                    , nights = nights model
                    , total = total model
                    }

            else
                Nothing

        _ ->
            Nothing


isConfirmed : Model -> Bool
isConfirmed model =
    case model.phase of
        Confirmed _ _ ->
            True

        _ ->
            False


{-| The step the flow is on (0-based), derived from the phase by an exhaustive
match — adding a phase forces this to be reconsidered.
-}
stepIndex : Model -> Int
stepIndex model =
    case model.phase of
        Editing ->
            0

        Reviewing _ ->
            1

        Submitting _ ->
            1

        SubmitFailed _ _ ->
            1

        Confirmed _ _ ->
            2
