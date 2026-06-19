module View exposing (view)

{-| The view layer: organisms (`calendar`, `rooms`, `summary`, `confirmation`)
assembled from the `Ui` kit, mirroring `src/components/*.vue`. The flow is
rendered by an exhaustive `case` on `model.phase`; the `Reviewing`/`Confirmed`
branches receive the `ValidBooking` the phase carries, so they render from proven
data rather than re-deriving and re-checking it.
-}

import Api.Types exposing (SubmitError)
import Calendar exposing (CalendarDay, isCurrentMonth, monthGrid)
import Date exposing (Date)
import Domain.BookableDate as BookableDate
import Domain.Date exposing (daysBetween, isBefore, isSameDay, toIsoKey)
import Domain.Types exposing (BookingError(..), Locale(..), Room, RoomId(..), Selection(..), localize, localizeInt)
import Html exposing (Html, text)
import Html.Attributes exposing (alt, attribute, class, classList, disabled, src)
import Html.Events exposing (onClick)
import I18n exposing (Messages)
import Model
    exposing
        ( CalendarState(..)
        , Model
        , Msg(..)
        , Phase(..)
        , RoomsState(..)
        , Theme(..)
        , ValidBooking
        , calendarReady
        , errors
        , isValid
        , maxGuests
        , maxMonthCursor
        , nights
        , roomList
        , selectedRoom
        , selectedRoomBusy
        , stepIndex
        , total
        )
import Set exposing (Set)
import Ui


view : Model -> Html Msg
view model =
    let
        t =
            I18n.messages model.locale
    in
    Html.main_ [ class "page" ]
        [ Html.div [ class "widget" ]
            [ header model t
            , Ui.steps
                { current = stepIndex model
                , steps =
                    List.map2
                        (\label flowStep -> { label = label, onBack = backMsg model.phase flowStep })
                        t.steps
                        flowSteps
                }
                |> withClass "widget__steps"
            , body model t
            ]
        , Html.footer [ class "page__footer" ]
            [ Html.a [ Html.Attributes.href "https://github.com", attribute "target" "_blank", attribute "rel" "noopener" ]
                [ text "Elm · The Elm Architecture · demo" ]
            ]
        ]


{-| `Ui.steps` renders a fixed `<ol>`; wrap it to attach the layout class.
-}
withClass : String -> Html msg -> Html msg
withClass cls child =
    Html.div [ class cls ] [ child ]


{-| The three steps of the flow, named rather than indexed. The stepper navigates
by this identity, so the back-target is decided here from the phase — there is no
`index == 0` positional check that a reordering could silently break (hole 7.2).
-}
type Step
    = ChooseStep
    | ReviewStep
    | DoneStep


flowSteps : List Step
flowSteps =
    [ ChooseStep, ReviewStep, DoneStep ]


{-| The message a step emits when clicked as a "back" target, or `Nothing` if it
is not navigable from the current phase. Exhaustive over `(Phase, Step)`, so a new
phase or step forces the rule to be reconsidered. Only the first step is ever a
back-target (it returns to editing), and never once the booking is confirmed.
-}
backMsg : Phase -> Step -> Maybe Msg
backMsg phase step =
    case ( phase, step ) of
        ( Confirmed _ _, _ ) ->
            -- A confirmed booking is terminal: no step navigates anywhere.
            Nothing

        ( Editing, _ ) ->
            -- Nothing is behind the first step.
            Nothing

        ( _, ChooseStep ) ->
            -- From review/submit, the first step goes back to editing.
            Just Edit

        _ ->
            Nothing


header : Model -> Messages -> Html Msg
header model t =
    Html.header [ class "widget__header" ]
        [ Html.div []
            [ Html.h1 [ class "widget__title" ] [ text t.title ]
            , Html.p [ class "widget__subtitle" ] [ text t.subtitle ]
            ]
        , Ui.stack { direction = Ui.Row, gap = 2, align = "", justify = "", attrs = [ class "widget__controls" ] }
            [ Ui.segmented
                { options = [ { value = Ru, label = "RU" }, { value = En, label = "EN" } ]
                , selected = model.locale
                , onSelect = SetLocale
                }
            , Ui.button Ui.Icon
                [ attribute "aria-label" (themeLabel model.theme)
                , onClick ToggleTheme
                ]
                [ text (themeIcon model.theme) ]
            ]
        ]


themeLabel : Theme -> String
themeLabel theme =
    case theme of
        Dark ->
            "Light theme"

        Light ->
            "Dark theme"


themeIcon : Theme -> String
themeIcon theme =
    case theme of
        Dark ->
            "☀"

        Light ->
            "☾"


body : Model -> Messages -> Html Msg
body model t =
    case model.phase of
        Confirmed booking ref ->
            confirmation t model.locale booking ref

        Reviewing booking ->
            reviewPanel t model.locale booking ReviewIdle

        Submitting booking ->
            reviewPanel t model.locale booking ReviewBusy

        SubmitFailed booking err ->
            reviewPanel t model.locale booking (ReviewError err)

        Editing ->
            Ui.column 5
                [ Ui.split
                    [ calendar model t
                    , Ui.column 4
                        [ guestSelector model t
                        , editingSummary model t
                        ]
                    ]
                , rooms model t
                ]



-- CALENDAR (DateRangePicker)


calendar : Model -> Messages -> Html Msg
calendar model t =
    Html.section [ class "calendar" ]
        [ Html.header [ class "calendar__bar" ]
            [ Ui.button Ui.Icon
                [ disabled (isCurrentMonth model.today model.monthCursor)
                , attribute "aria-label" "‹"
                , onClick PrevMonth
                ]
                [ text "‹" ]
            , Html.span [ class "calendar__month" ] [ text (I18n.monthLabel model.locale model.monthCursor) ]
            , Ui.button Ui.Icon
                [ disabled (atHorizonMonth model)
                , attribute "aria-label" "›"
                , onClick NextMonth
                ]
                [ text "›" ]
            ]
        , Html.div [ class "calendar__weekdays" ]
            (List.map (\label -> Html.span [] [ text label ]) (I18n.weekdayLabels model.locale))
        , Html.div [ class "calendar__grid" ]
            (monthGrid model.today model.monthCursor
                |> List.concatMap (List.map (dayCell model))
            )
        , Html.p [ class "calendar__summary" ] [ text (summaryText model t) ]
        , calendarLegend model t
        ]


dayCell : Model -> CalendarDay -> Html Msg
dayCell model day =
    let
        past =
            isBefore day.date model.today

        occupied =
            isOccupied model day.date

        isDisabled =
            past || occupied

        st =
            dayState model.selection day.date
    in
    Html.button
        [ Html.Attributes.type_ "button"
        , class "day"
        , classList
            [ ( "day--muted", not day.inCurrentMonth )
            , ( "day--today", day.isToday )
            , ( "day--disabled", isDisabled )
            , ( "day--occupied", occupied )
            , ( "day--start", st.isStart )
            , ( "day--end", st.isEnd )
            , ( "day--in-range", st.inRange )
            ]
        , disabled isDisabled
        , attribute "aria-label" (I18n.formatDate model.locale day.date)
        , onClick (SelectDate day.date)
        ]
        [ text (String.fromInt (Date.day day.date)) ]


{-| True once the calendar can't scroll any further forward (the horizon month).
-}
atHorizonMonth : Model -> Bool
atHorizonMonth model =
    not (isBefore model.monthCursor (maxMonthCursor model))


{-| The selected room's busy days come from the server and are shown right in the
calendar — only once the room's calendar is ready.
-}
showingRoomCalendar : Model -> Bool
showingRoomCalendar model =
    calendarReady model


blockedSet : Model -> Set String
blockedSet model =
    case Model.roomCalendar model of
        Just (CalReady _ _ set) ->
            set

        _ ->
            Set.empty


isOccupied : Model -> Date -> Bool
isOccupied model date =
    showingRoomCalendar model && Set.member (toIsoKey date) (blockedSet model)


type alias DayState =
    { isStart : Bool, isEnd : Bool, inRange : Bool }


dayState : Selection -> Date -> DayState
dayState selection date =
    case selection of
        NoSelection ->
            DayState False False False

        CheckIn checkIn ->
            DayState (isSameDay date (BookableDate.toDate checkIn)) False False

        Range checkIn checkOut ->
            let
                ci =
                    BookableDate.toDate checkIn

                co =
                    BookableDate.toDate checkOut
            in
            { isStart = isSameDay date ci
            , isEnd = isSameDay date co
            , inRange = not (isBefore date ci) && not (isBefore co date)
            }


summaryText : Model -> Messages -> String
summaryText model t =
    case model.selection of
        Range checkIn checkOut ->
            let
                ci =
                    BookableDate.toDate checkIn

                co =
                    BookableDate.toDate checkOut
            in
            I18n.formatDate model.locale ci
                ++ " — "
                ++ I18n.formatDate model.locale co
                ++ " · "
                ++ t.nights (daysBetween ci co)

        CheckIn checkIn ->
            t.checkIn ++ ": " ++ I18n.formatDate model.locale (BookableDate.toDate checkIn)

        NoSelection ->
            t.pickDates


{-| The legend under the grid. Matching on `CalendarState` is exhaustive, so the
`CalError` state cannot be silently skipped the way the Vue calendar's error
branch was (audit hole 5.3) — Elm forces a visible, recoverable state with retry.
-}
calendarLegend : Model -> Messages -> Html Msg
calendarLegend model t =
    case Model.roomCalendar model of
        Nothing ->
            text ""

        Just CalLoading ->
            Html.p [ class "calendar__legend" ]
                [ Html.span [ class "calendar__spinner", attribute "aria-hidden" "true" ] []
                , text t.loadingCalendar
                ]

        Just CalError ->
            Html.p [ class "calendar__legend" ]
                [ text t.loadError
                , Ui.button Ui.Ghost [ onClick RetryCalendar ] [ text t.retry ]
                ]

        Just (CalReady _ _ _) ->
            Html.p [ class "calendar__legend" ]
                [ Html.span [ class "calendar__legend-swatch", attribute "aria-hidden" "true" ] []
                , text t.roomBusyHint
                ]



-- GUEST SELECTOR


guestSelector : Model -> Messages -> Html Msg
guestSelector model t =
    Ui.stack { direction = Ui.Row, gap = 4, align = "center", justify = "space-between", attrs = [] }
        [ Html.span [ class "guests__label" ] [ text t.guests ]
        , Ui.stepper
            { value = model.guests
            , min = 1
            , max = maxGuests model
            , ariaLabel = t.guests
            , onChange = SetGuests
            }
            [ text (String.fromInt model.guests ++ " ")
            , Html.small [ class "guests__unit" ] [ text (t.guest model.guests) ]
            ]
        ]



-- ROOMS (RoomList + RoomCard)


rooms : Model -> Messages -> Html Msg
rooms model t =
    Html.section [ class "rooms" ]
        [ Html.h2 [ class "rooms__title" ] [ text t.selectRoom ]
        , case model.rooms of
            RoomsLoading ->
                Html.div [ class "rooms__grid" ] (List.repeat 3 (Ui.skeleton 140))

            RoomsError ->
                Ui.surfaceMuted [ class "rooms__error" ]
                    [ Ui.stack { direction = Ui.Column, gap = 3, align = "center", justify = "", attrs = [] }
                        [ Html.span [] [ text t.loadError ]
                        , Ui.button Ui.Ghost [ onClick LoadRooms ] [ text t.retry ]
                        ]
                    ]

            RoomsReady roomItems ->
                Html.div [ class "rooms__grid" ] (List.map (roomCard model t) roomItems)
        ]


roomCard : Model -> Messages -> Room -> Html Msg
roomCard model t room =
    let
        isSelected =
            Model.selectedRoomId model == Just room.id

        tooSmall =
            room.capacity < model.guests

        checking =
            isSelected && Model.roomCalendar model == Just CalLoading

        busy =
            isSelected && selectedRoomBusy model
    in
    Ui.surface
        { tag = Ui.SurfaceButton
        , tone = Ui.ToneSurface
        , pad = Ui.PadSm
        , interactive = True
        , selected = isSelected
        , attrs =
            [ class "room"
            , Html.Attributes.type_ "button"
            , attribute "aria-pressed" (boolString isSelected)
            , disabled tooSmall
            , onClick (SelectRoom room.id)
            ]
        }
        [ Ui.stack { direction = Ui.Row, gap = 4, align = "stretch", justify = "", attrs = [ class "ui-stack--room" ] }
            [ Html.img
                [ class "room__image"
                , src (roomImage model room.id)
                , alt (localize model.locale room.name)
                ]
                []
            , Ui.stack { direction = Ui.Column, gap = 2, align = "", justify = "", attrs = [ class "room__body" ] }
                [ Html.div [ class "room__head" ]
                    [ Html.h3 [ class "room__name" ] [ text (localize model.locale room.name) ]
                    , Ui.badge Ui.Muted (t.upToGuests room.capacity)
                    ]
                , Html.p [ class "room__desc" ] [ text (localize model.locale room.description) ]
                , Html.div [ class "room__foot" ]
                    [ Html.span [ class "room__price" ]
                        [ text (I18n.formatPrice model.locale (localizeInt model.locale room.pricePerNight))
                        , Html.small [] [ text ("/ " ++ t.perNight) ]
                        ]
                    , roomCardStatus model t isSelected tooSmall checking busy
                    ]
                ]
            ]
        ]


roomCardStatus : Model -> Messages -> Bool -> Bool -> Bool -> Bool -> Html Msg
roomCardStatus model t isSelected tooSmall checking busy =
    if tooSmall then
        Ui.badge Ui.Danger (I18n.errorMessage model.locale CapacityExceeded)

    else if checking then
        Ui.badge Ui.Muted t.checkingAvailability

    else if busy then
        Ui.badge Ui.Danger t.unavailableForDates

    else if isSelected then
        Html.span [ class "room__check", attribute "aria-hidden" "true" ] [ text "✓" ]

    else
        text ""


roomImage : Model -> RoomId -> String
roomImage model id =
    model.assetBase
        ++ (case id of
                Standard ->
                    "standard.jpg"

                Comfort ->
                    "comfort.jpg"

                Family ->
                    -- Family reuses the comfort double-room photo for now.
                    "comfort.jpg"
           )



-- SUMMARY (BookingSummary)


{-| The live summary on the editing screen: it reads straight from the model
(which may be incomplete), so the "Book" action is gated by `isValid` and the
first blocking error is shown as a hint.
-}
editingSummary : Model -> Messages -> Html Msg
editingSummary model t =
    let
        rows =
            roomRow model
                ++ datesRow model t
                ++ [ totalRow model t ]
    in
    Ui.surfaceMuted [ class "summary" ]
        [ Ui.column 3
            (Ui.column 2 rows
                :: hintRow model t
                ++ [ Ui.row 3
                        [ Ui.button Ui.Primary
                            [ Ui.block, disabled (not (isValid model)), onClick Review ]
                            [ text t.book ]
                        ]
                   ]
            )
        ]


{-| The submit state of the review screen, derived from the `Phase`.
-}
type ReviewState
    = ReviewIdle
    | ReviewBusy
    | ReviewError SubmitError


{-| The review screen renders from a `ValidBooking`, so it shows no errors and
needs no validity gate — the data's existence is the proof it's bookable. The
`ReviewState` controls the submit button and the error hint.
-}
reviewPanel : Messages -> Locale -> ValidBooking -> ReviewState -> Html Msg
reviewPanel t locale booking state =
    let
        bookButton =
            case state of
                ReviewBusy ->
                    Ui.button Ui.Primary [ Ui.block, disabled True ] [ text t.submitting ]

                _ ->
                    Ui.button Ui.Primary [ Ui.block, onClick Confirm ] [ text t.book ]

        errorHint =
            case state of
                ReviewError err ->
                    [ Html.p [ class "summary__hint" ] [ text (I18n.submitErrorMessage locale err) ] ]

                _ ->
                    []
    in
    Html.div [ class "widget__review" ]
        [ Ui.surfaceMuted [ class "summary" ]
            [ Ui.column 3
                (Ui.column 2
                    [ summaryRow "summary__row"
                        [ Html.span [] [ text (localize locale booking.room.name) ]
                        , Html.span []
                            [ text
                                (I18n.formatPrice locale (localizeInt locale booking.room.pricePerNight)
                                    ++ " × "
                                    ++ String.fromInt booking.nights
                                )
                            ]
                        ]
                    , summaryRow "summary__row summary__row--muted"
                        [ Html.span [] [ text (t.checkIn ++ " — " ++ t.checkOut) ]
                        , Html.span [] [ text (I18n.formatDate locale (BookableDate.toDate booking.checkIn) ++ " — " ++ I18n.formatDate locale (BookableDate.toDate booking.checkOut)) ]
                        ]
                    , summaryRow "summary__row summary__row--total"
                        [ Html.span [] [ text t.total ]
                        , Html.span [] [ text (I18n.formatPrice locale (localizeInt locale booking.total)) ]
                        ]
                    ]
                    :: errorHint
                    ++ [ Ui.row 3
                            [ Ui.button Ui.Ghost [ disabled (state == ReviewBusy), onClick Edit ] [ text t.back ]
                            , bookButton
                            ]
                       ]
                )
            ]
        ]


roomRow : Model -> List (Html Msg)
roomRow model =
    case selectedRoom model of
        Just room ->
            [ summaryRow "summary__row"
                [ Html.span [] [ text (localize model.locale room.name) ]
                , Html.span []
                    [ text
                        (I18n.formatPrice model.locale (localizeInt model.locale room.pricePerNight)
                            ++ " × "
                            ++ String.fromInt (nights model)
                        )
                    ]
                ]
            ]

        Nothing ->
            []


datesRow : Model -> Messages -> List (Html Msg)
datesRow model t =
    case model.selection of
        Range checkIn checkOut ->
            [ summaryRow "summary__row summary__row--muted"
                [ Html.span [] [ text (t.checkIn ++ " — " ++ t.checkOut) ]
                , Html.span [] [ text (I18n.formatDate model.locale (BookableDate.toDate checkIn) ++ " — " ++ I18n.formatDate model.locale (BookableDate.toDate checkOut)) ]
                ]
            ]

        _ ->
            []


totalRow : Model -> Messages -> Html Msg
totalRow model t =
    summaryRow "summary__row summary__row--total"
        [ Html.span [] [ text t.total ]
        , Html.span [] [ text (I18n.formatPrice model.locale (localizeInt model.locale (total model))) ]
        ]


summaryRow : String -> List (Html Msg) -> Html Msg
summaryRow cls children =
    Ui.stack { direction = Ui.Row, gap = 3, align = "", justify = "space-between", attrs = [ class cls ] } children


hintRow : Model -> Messages -> List (Html Msg)
hintRow model t =
    case errors model of
        first :: _ ->
            [ Html.p [ class "summary__hint" ] [ text (I18n.errorMessage model.locale first) ] ]

        [] ->
            []



-- CONFIRMATION (ConfirmationView)


{-| The confirmation screen takes a `ValidBooking`, so — unlike the Vue version,
which guarded `v-if="selectedRoom && checkIn && checkOut"` — the details cannot be
missing. There is no "confirmed but nothing to show" state to handle.
-}
confirmation : Messages -> Locale -> ValidBooking -> String -> Html Msg
confirmation t locale booking ref =
    Ui.stack { direction = Ui.Column, gap = 4, align = "center", justify = "", attrs = [ class "confirm" ] }
        [ Html.div [ class "confirm__badge", attribute "aria-hidden" "true" ] [ text "✓" ]
        , Html.h2 [ class "confirm__title" ] [ text t.confirmTitle ]
        , Ui.surfaceMuted [ class "confirm__details" ]
            [ Ui.column 2
                [ confirmRow t.selectRoom (localize locale booking.room.name)
                , confirmRow (t.checkIn ++ " — " ++ t.checkOut)
                    (I18n.formatDate locale (BookableDate.toDate booking.checkIn) ++ " — " ++ I18n.formatDate locale (BookableDate.toDate booking.checkOut))
                , confirmRow t.total (I18n.formatPrice locale (localizeInt locale booking.total))
                , confirmRow t.reference ref
                ]
            ]
        , Html.p [ class "confirm__text" ] [ text t.confirmText ]
        , Ui.button Ui.Ghost [ onClick Reset ] [ text t.newBooking ]
        ]


confirmRow : String -> String -> Html Msg
confirmRow key value =
    Ui.stack { direction = Ui.Row, gap = 3, align = "", justify = "space-between", attrs = [] }
        [ Html.span [ class "confirm__key" ] [ text key ]
        , Html.span [ class "confirm__value" ] [ text value ]
        ]


boolString : Bool -> String
boolString value =
    if value then
        "true"

    else
        "false"
