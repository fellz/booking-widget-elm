module Domain.Types exposing
    ( BookingError(..)
    , Locale(..)
    , LocalizedPrice
    , LocalizedText
    , Room
    , RoomId(..)
    , Selection(..)
    , allRoomIds
    , localize
    , localizeInt
    , roomIdFromString
    , roomIdToString
    )

import Domain.BookableDate exposing (BookableDate)


{-| Supported UI locales. Each locale also drives the pricing currency.
-}
type Locale
    = Ru
    | En


{-| Identifier of a room category. A closed sum type, so an unknown id from the
network cannot even be constructed without going through `roomIdFromString`
(see `Api.Http`) — the "unknown id compiles, breaks at runtime" hole is gone.
-}
type RoomId
    = Standard
    | Comfort
    | Family


allRoomIds : List RoomId
allRoomIds =
    [ Standard, Comfort, Family ]


roomIdToString : RoomId -> String
roomIdToString id =
    case id of
        Standard ->
            "standard"

        Comfort ->
            "comfort"

        Family ->
            "family"


{-| The only door from a raw string into `RoomId`. Returns `Nothing` for an
unknown category, forcing every caller to handle the bad-input case.
-}
roomIdFromString : String -> Maybe RoomId
roomIdFromString raw =
    case raw of
        "standard" ->
            Just Standard

        "comfort" ->
            Just Comfort

        "family" ->
            Just Family

        _ ->
            Nothing


{-| Price per night, keyed by locale/currency (whole currency units).
-}
type alias LocalizedPrice =
    { ru : Int, en : Int }


{-| Localized free-text fields (name, description).
-}
type alias LocalizedText =
    { ru : String, en : String }


localize : Locale -> LocalizedText -> String
localize locale text =
    case locale of
        Ru ->
            text.ru

        En ->
            text.en


localizeInt : Locale -> LocalizedPrice -> Int
localizeInt locale price =
    case locale of
        Ru ->
            price.ru

        En ->
            price.en


type alias Room =
    { id : RoomId
    , capacity : Int
    , pricePerNight : LocalizedPrice
    , name : LocalizedText
    , description : LocalizedText
    }


{-| The check-in / check-out selection as a sum type. Unlike the original
`{ checkIn: Date | null, checkOut: Date | null }`, a check-out date cannot exist
without a check-in, and the `Range` constructor is only ever built with
`checkIn < checkOut` (see `Update.selectDate`). The dates are `BookableDate`, so a
past day can't be selected at all — three structurally-impossible states from the
TS version (orphan check-out, inverted range, past check-in) have no
representation here.
-}
type Selection
    = NoSelection
    | CheckIn BookableDate
    | Range BookableDate BookableDate


{-| Reasons a booking cannot be submitted, surfaced to the UI as i18n keys. There
is no `PastDates`: `Selection` carries `BookableDate`, so a past check-in cannot
be represented, let alone reported (audit hole 5.2, closed structurally).
-}
type BookingError
    = NoDates
    | NoCheckOut
    | InvalidRange
    | NoRoom
    | CapacityExceeded
    | DatesUnavailable
    | AvailabilityUnknown
