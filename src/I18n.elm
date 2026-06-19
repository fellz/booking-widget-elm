module I18n exposing
    ( Messages
    , currencyCode
    , errorMessage
    , formatDate
    , formatPrice
    , localeTag
    , messages
    , monthLabel
    , submitErrorMessage
    , weekdayLabels
    )

{-| A small, dependency-free i18n layer. The original leaned on `Intl` for
currency and dates; Elm has no `Intl`, so prices, month names and Russian
plurals are formatted by hand here. The upside is that all of it is pure and
unit-testable; the downside is that locale formatting is approximate rather than
ICU-exact (e.g. the thousands separator is a fixed non-breaking space). This is
a deliberate trade — see COMPARISON.md.
-}

import Api.Types exposing (SubmitError(..))
import Date exposing (Date)
import Domain.Types exposing (BookingError(..), Locale(..))
import Time exposing (Month(..))


type alias Messages =
    { title : String
    , subtitle : String
    , steps : List String
    , guests : String
    , guest : Int -> String
    , upToGuests : Int -> String
    , perNight : String
    , checkIn : String
    , checkOut : String
    , pickDates : String
    , selectRoom : String
    , unavailableForDates : String
    , checkingAvailability : String
    , roomBusyHint : String
    , loadingCalendar : String
    , loadError : String
    , retry : String
    , nights : Int -> String
    , total : String
    , book : String
    , submitting : String
    , back : String
    , confirmTitle : String
    , confirmText : String
    , reference : String
    , newBooking : String
    }


messages : Locale -> Messages
messages locale =
    case locale of
        Ru ->
            { title = "Бронирование номера"
            , subtitle = "Выберите даты, число гостей и подходящий номер"
            , steps = [ "Выбор", "Проверка", "Готово" ]
            , guests = "Гости"
            , guest = \n -> plural n ( "гость", "гостя", "гостей" )
            , upToGuests = \n -> "до " ++ String.fromInt n ++ " " ++ plural n ( "гостя", "гостей", "гостей" )
            , perNight = "за ночь"
            , checkIn = "Заезд"
            , checkOut = "Выезд"
            , pickDates = "Выберите даты заезда и выезда"
            , selectRoom = "Выберите номер"
            , unavailableForDates = "Занято на выбранные даты"
            , checkingAvailability = "Проверяем доступность…"
            , roomBusyHint = "Подсвечены занятые даты этого номера"
            , loadingCalendar = "Загружаем доступность номера…"
            , loadError = "Не удалось загрузить номера"
            , retry = "Повторить"
            , nights = \n -> String.fromInt n ++ " " ++ plural n ( "ночь", "ночи", "ночей" )
            , total = "Итого"
            , book = "Забронировать"
            , submitting = "Бронируем…"
            , back = "Назад"
            , confirmTitle = "Бронирование подтверждено"
            , confirmText = "Мы отправили детали на вашу почту. Ждём вас!"
            , reference = "Номер брони"
            , newBooking = "Новое бронирование"
            }

        En ->
            { title = "Book a room"
            , subtitle = "Pick your dates, number of guests and a matching room"
            , steps = [ "Choose", "Review", "Done" ]
            , guests = "Guests"
            , guest =
                \n ->
                    if n == 1 then
                        "guest"

                    else
                        "guests"
            , upToGuests = \n -> "up to " ++ String.fromInt n ++ " guests"
            , perNight = "per night"
            , checkIn = "Check-in"
            , checkOut = "Check-out"
            , pickDates = "Select check-in and check-out dates"
            , selectRoom = "Select a room"
            , unavailableForDates = "Unavailable for the selected dates"
            , checkingAvailability = "Checking availability…"
            , roomBusyHint = "Highlighted dates are booked for this room"
            , loadingCalendar = "Loading room availability…"
            , loadError = "Couldn’t load rooms"
            , retry = "Retry"
            , nights =
                \n ->
                    String.fromInt n
                        ++ (if n == 1 then
                                " night"

                            else
                                " nights"
                           )
            , total = "Total"
            , book = "Book now"
            , submitting = "Booking…"
            , back = "Back"
            , confirmTitle = "Booking confirmed"
            , confirmText = "We have emailed you the details. See you soon!"
            , reference = "Booking reference"
            , newBooking = "New booking"
            }


{-| Localized text for a structural booking error. Exhaustive over the ADT, so a
new `BookingError` constructor forces a new message — no missing-key gaps.
-}
errorMessage : Locale -> BookingError -> String
errorMessage locale error =
    case locale of
        Ru ->
            case error of
                NoDates ->
                    "Выберите даты"

                NoCheckOut ->
                    "Выберите дату выезда"

                InvalidRange ->
                    "Дата выезда должна быть позже заезда"

                NoRoom ->
                    "Выберите номер"

                CapacityExceeded ->
                    "Номер не вмещает столько гостей"

                DatesUnavailable ->
                    "Номер занят на выбранные даты"

                AvailabilityUnknown ->
                    "Доступность на эти даты пока неизвестна"

        En ->
            case error of
                NoDates ->
                    "Select your dates"

                NoCheckOut ->
                    "Select a check-out date"

                InvalidRange ->
                    "Check-out must be after check-in"

                NoRoom ->
                    "Select a room"

                CapacityExceeded ->
                    "This room cannot host that many guests"

                DatesUnavailable ->
                    "This room is booked for the selected dates"

                AvailabilityUnknown ->
                    "Availability for these dates isn’t known yet"


{-| A distinct message per submit-failure cause, exhaustive over `SubmitError` —
"the room was just taken" reads differently from "no connection" or "server
error". A new variant forces a new message at compile time.
-}
submitErrorMessage : Locale -> SubmitError -> String
submitErrorMessage locale err =
    case locale of
        Ru ->
            case err of
                RoomTaken ->
                    "Этот номер только что забронировали"

                SubmitNetwork ->
                    "Нет связи с сервером. Попробуйте ещё раз."

                SubmitServer _ ->
                    "Сервер недоступен. Попробуйте позже."

        En ->
            case err of
                RoomTaken ->
                    "This room was just taken"

                SubmitNetwork ->
                    "No connection to the server. Please try again."

                SubmitServer _ ->
                    "The server is unavailable. Please try again later."


{-| Russian pluralization: (one, few, many).
-}
plural : Int -> ( String, String, String ) -> String
plural n ( one, few, many ) =
    let
        mod10 =
            modBy 10 n

        mod100 =
            modBy 100 n
    in
    if mod10 == 1 && mod100 /= 11 then
        one

    else if mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20) then
        few

    else
        many



-- FORMATTING


currencyCode : Locale -> String
currencyCode locale =
    case locale of
        Ru ->
            "RUB"

        En ->
            "EUR"


localeTag : Locale -> String
localeTag locale =
    case locale of
        Ru ->
            "ru-RU"

        En ->
            "en-GB"


{-| Price in the locale's currency, no fractional units. Approximates
`Intl.NumberFormat` currency style: "4 500 ₽" for ru, "€49" for en.
-}
formatPrice : Locale -> Int -> String
formatPrice locale amount =
    case locale of
        Ru ->
            groupThousands "\u{00A0}" amount ++ "\u{00A0}₽"

        En ->
            "€" ++ groupThousands "," amount


groupThousands : String -> Int -> String
groupThousands sep n =
    let
        grouped =
            String.fromInt (abs n)
                |> String.toList
                |> List.reverse
                |> chunksOf 3
                |> List.map (List.reverse >> String.fromList)
                |> List.reverse
                |> String.join sep
    in
    if n < 0 then
        "-" ++ grouped

    else
        grouped


chunksOf : Int -> List a -> List (List a)
chunksOf size list =
    case list of
        [] ->
            []

        _ ->
            List.take size list :: chunksOf size (List.drop size list)


{-| A date for inline display: "19 июня" (ru, genitive month) / "19 June" (en).
-}
formatDate : Locale -> Date -> String
formatDate locale date =
    String.fromInt (Date.day date) ++ " " ++ monthNameGenitive locale (Date.month date)


{-| The calendar header: "июнь 2026" (ru) / "June 2026" (en). Lower-cased like
`Intl`; the calendar CSS capitalizes the first letter.
-}
monthLabel : Locale -> Date -> String
monthLabel locale date =
    monthNameNominative locale (Date.month date) ++ " " ++ String.fromInt (Date.year date)


{-| Monday-first short weekday initials, localized.
-}
weekdayLabels : Locale -> List String
weekdayLabels locale =
    case locale of
        Ru ->
            [ "пн", "вт", "ср", "чт", "пт", "сб", "вс" ]

        En ->
            [ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" ]


monthNameNominative : Locale -> Month -> String
monthNameNominative locale month =
    case locale of
        En ->
            englishMonth month

        Ru ->
            case month of
                Jan ->
                    "январь"

                Feb ->
                    "февраль"

                Mar ->
                    "март"

                Apr ->
                    "апрель"

                May ->
                    "май"

                Jun ->
                    "июнь"

                Jul ->
                    "июль"

                Aug ->
                    "август"

                Sep ->
                    "сентябрь"

                Oct ->
                    "октябрь"

                Nov ->
                    "ноябрь"

                Dec ->
                    "декабрь"


monthNameGenitive : Locale -> Month -> String
monthNameGenitive locale month =
    case locale of
        En ->
            englishMonth month

        Ru ->
            case month of
                Jan ->
                    "января"

                Feb ->
                    "февраля"

                Mar ->
                    "марта"

                Apr ->
                    "апреля"

                May ->
                    "мая"

                Jun ->
                    "июня"

                Jul ->
                    "июля"

                Aug ->
                    "августа"

                Sep ->
                    "сентября"

                Oct ->
                    "октября"

                Nov ->
                    "ноября"

                Dec ->
                    "декабря"


englishMonth : Month -> String
englishMonth month =
    case month of
        Jan ->
            "January"

        Feb ->
            "February"

        Mar ->
            "March"

        Apr ->
            "April"

        May ->
            "May"

        Jun ->
            "June"

        Jul ->
            "July"

        Aug ->
            "August"

        Sep ->
            "September"

        Oct ->
            "October"

        Nov ->
            "November"

        Dec ->
            "December"
