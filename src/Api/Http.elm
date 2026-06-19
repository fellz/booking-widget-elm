module Api.Http exposing (api)

{-| Real backend adapter. Not used until a server exists — wiring it in is the
one-line `Api.create` decision (driven by `VITE_API_URL`).

This is where Elm closes the original's biggest hole. In the TS version the
boundary was `response.json() as RoomDto[]` and `dto.id as RoomId` — `as`
switches type-checking off, so an unknown id, a missing field, or a wrong
currency compiled fine and blew up later. Here every byte from the network goes
through a `Decoder`, and an unknown room id fails decoding (`roomIdDecoder`)
instead of producing a broken `RoomId`. Bad input cannot reach the domain.

-}

import Api.Types exposing (ApiError(..), BookingApi, BookingRequest, SubmitError(..))
import Date exposing (Date)
import Domain.Date exposing (toIsoKey)
import Domain.Types exposing (LocalizedPrice, LocalizedText, Room, RoomId, roomIdFromString, roomIdToString)
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


api : String -> BookingApi msg
api baseUrl =
    { getRooms =
        \toMsg ->
            Http.get
                { url = baseUrl ++ "/rooms"
                , expect = Http.expectJson (Result.mapError toApiError >> toMsg) (Decode.list roomDecoder)
                }
    , getRoomCalendar =
        \roomId from to toMsg ->
            -- `Http.request` (not `Http.get`) so the call carries a `tracker`,
            -- which `cancelCalendar` can later abort when a newer room is picked.
            Http.request
                { method = "GET"
                , headers = []
                , url = calendarUrl baseUrl roomId from to
                , body = Http.emptyBody
                , expect = Http.expectJson (Result.mapError toApiError >> toMsg) (Decode.list Decode.string)
                , timeout = Nothing
                , tracker = Just calendarTracker
                }
    , cancelCalendar =
        Http.cancel calendarTracker
    , submitBooking =
        \request toMsg ->
            Http.post
                { url = baseUrl ++ "/reservations"
                , body = Http.jsonBody (encodeRequest request)
                , expect = Http.expectJson (Result.mapError toSubmitError >> toMsg) referenceDecoder
                }
    }


{-| The tracker name shared by `getRoomCalendar` and `cancelCalendar` so an
in-flight calendar request can be aborted when it is superseded.
-}
calendarTracker : String
calendarTracker =
    "room-calendar"


{-| Map transport failures to the typed write-side channel. A 409 means the room
was taken between review and submit — its own variant, its own message.
-}
toSubmitError : Http.Error -> SubmitError
toSubmitError error =
    case error of
        Http.BadStatus 409 ->
            RoomTaken

        Http.BadStatus status ->
            SubmitServer status

        Http.BadBody _ ->
            SubmitServer 0

        Http.Timeout ->
            SubmitNetwork

        Http.NetworkError ->
            SubmitNetwork

        Http.BadUrl _ ->
            SubmitNetwork


encodeRequest : BookingRequest -> Encode.Value
encodeRequest request =
    Encode.object
        [ ( "roomId", Encode.string (roomIdToString request.roomId) )
        , ( "from", Encode.string (toIsoKey request.checkIn) )
        , ( "to", Encode.string (toIsoKey request.checkOut) )
        ]


referenceDecoder : Decoder String
referenceDecoder =
    Decode.field "reference" Decode.string


calendarUrl : String -> RoomId -> Date -> Date -> String
calendarUrl baseUrl roomId from to =
    -- ISO date keys ("2026-06-19") need no escaping, so a plain concat is safe.
    baseUrl
        ++ "/rooms/"
        ++ roomIdToString roomId
        ++ "/calendar?from="
        ++ toIsoKey from
        ++ "&to="
        ++ toIsoKey to


toApiError : Http.Error -> ApiError
toApiError error =
    case error of
        Http.BadStatus status ->
            BadStatus status

        Http.BadBody message ->
            DecodeError message

        Http.Timeout ->
            NetworkError

        Http.NetworkError ->
            NetworkError

        Http.BadUrl _ ->
            NetworkError



-- DECODERS (the anti-corruption boundary)


roomDecoder : Decoder Room
roomDecoder =
    Decode.map5 Room
        (Decode.field "id" roomIdDecoder)
        (Decode.field "capacity" Decode.int)
        (Decode.field "pricePerNight" localizedPriceDecoder)
        (Decode.field "name" localizedTextDecoder)
        (Decode.field "description" localizedTextDecoder)


{-| An unknown category fails decoding instead of being coerced with `as`.
-}
roomIdDecoder : Decoder RoomId
roomIdDecoder =
    Decode.string
        |> Decode.andThen
            (\raw ->
                case roomIdFromString raw of
                    Just id ->
                        Decode.succeed id

                    Nothing ->
                        Decode.fail ("Unknown room id: " ++ raw)
            )


localizedPriceDecoder : Decoder LocalizedPrice
localizedPriceDecoder =
    Decode.map2 LocalizedPrice
        (Decode.field "ru" Decode.int)
        (Decode.field "en" Decode.int)


localizedTextDecoder : Decoder LocalizedText
localizedTextDecoder =
    Decode.map2 LocalizedText
        (Decode.field "ru" Decode.string)
        (Decode.field "en" Decode.string)
