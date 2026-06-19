module Api.Types exposing (ApiError(..), BookingApi, BookingRequest, SubmitError(..))

{-| The port the widget depends on for its data (Dependency Inversion). The app
knows only this record of effect-producing functions — never where the rooms
actually come from. `Api.Mock` and `Api.Http` both build a `BookingApi`, and
`Api.create` picks one; tests inject a fake. The record is generic over `msg`
so this module stays free of any dependency on the app's `Msg`.
-}

import Date exposing (Date)
import Domain.Types exposing (Room, RoomId)


{-| The data the backend needs to place a reservation. Kept to primitive domain
types so this module stays independent of the app's `Model` (where `ValidBooking`
lives).
-}
type alias BookingRequest =
    { roomId : RoomId, checkIn : Date, checkOut : Date }


{-| A typed error channel. Unlike the original `catch {}` that collapsed every
failure into one `'error'` string, callers can pattern-match the cause. Decode
failures at the IO boundary surface here as `DecodeError`.
-}
type ApiError
    = NetworkError
    | BadStatus Int
    | DecodeError String


{-| The write side has its own failure modes, distinct from a read. Modelling
them as their own ADT lets the UI tell "the room was just taken" apart from "no
connection" or "server error" and render a different message for each — the
typed-error-channel idea, cheaply done in Elm.
-}
type SubmitError
    = SubmitNetwork
    | SubmitServer Int
    | RoomTaken


type alias BookingApi msg =
    { getRooms : (Result ApiError (List Room) -> msg) -> Cmd msg
    , getRoomCalendar : RoomId -> Date -> Date -> (Result ApiError (List String) -> msg) -> Cmd msg

    -- Abort any in-flight calendar request. The `requestId` guard already keeps
    -- a stale reply from being *applied* (audit hole 6.1, defense-in-depth);
    -- this additionally tears down the superseded connection instead of letting
    -- it run to completion. A stale response can't be forbidden by a type, so
    -- 6.1 stays "improved, not closed structurally". The mock has nothing to
    -- abort, so it returns `Cmd.none`.
    , cancelCalendar : Cmd msg

    -- The write side: place a reservation, returning a confirmation reference.
    -- Unlike the Vue `confirm()` (a local flag, no effect), this is a real
    -- effect that can fail through the typed `SubmitError` channel — closing
    -- hole 2.2, with each cause distinguishable.
    , submitBooking : BookingRequest -> (Result SubmitError String -> msg) -> Cmd msg
    }
