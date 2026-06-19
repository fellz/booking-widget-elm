module Main exposing (main)

{-| Program wiring. Startup flags carry everything impure the pure core needs to
be deterministic: the current calendar day (`today`, resolved from the runtime's
clock + zone in JS), the initial `theme`, the configured API base URL, and the
asset base path. From there the core is a pure `Model`/`update`/`view`.
-}

import Api
import Browser
import Calendar exposing (firstOfMonth)
import Date exposing (Date)
import Domain.Types exposing (Locale(..), Selection(..))
import Json.Decode as Decode
import Model exposing (Model, Msg(..), Phase(..), RoomSelection(..), RoomsState(..), Theme(..))
import Time
import Update exposing (update)
import View exposing (view)


{-| Raw flags from JS. `today` is an ISO date string ("2026-06-19"); `theme` is
"dark"/"light"; `apiUrl` is "" when no backend is configured.
-}
type alias Flags =
    { today : String
    , theme : String
    , apiUrl : String
    , assetBase : String
    }


flagsDecoder : Decode.Decoder Flags
flagsDecoder =
    Decode.map4 Flags
        (Decode.field "today" Decode.string)
        (Decode.field "theme" Decode.string)
        (Decode.field "apiUrl" Decode.string)
        (Decode.field "assetBase" Decode.string)


main : Program Decode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }


init : Decode.Value -> ( Model, Cmd Msg )
init rawFlags =
    let
        flags =
            Decode.decodeValue flagsDecoder rawFlags
                |> Result.withDefault fallbackFlags

        today =
            Date.fromIsoString flags.today
                |> Result.withDefault fallbackToday

        baseUrl =
            if String.isEmpty flags.apiUrl then
                Nothing

            else
                Just flags.apiUrl

        model =
            { today = today
            , assetBase = flags.assetBase
            , locale = Ru
            , theme = themeFromString flags.theme
            , phase = Editing
            , selection = NoSelection
            , guests = 2
            , roomSelection = NoRoom
            , rooms = RoomsLoading
            , roomsRequestId = 0
            , calendarRequestId = 0
            , monthCursor = firstOfMonth today
            , api = Api.create baseUrl
            }
    in
    -- Kick off the catalogue load, mirroring the Vue `onMounted(loadRooms)`.
    update LoadRooms model


themeFromString : String -> Theme
themeFromString raw =
    if raw == "dark" then
        Dark

    else
        Light


fallbackFlags : Flags
fallbackFlags =
    { today = "2020-01-01", theme = "light", apiUrl = "", assetBase = "/" }


{-| Only used if both the flag and its parse fail — keeps the program total.
-}
fallbackToday : Date
fallbackToday =
    Date.fromCalendarDate 2020 Time.Jan 1
