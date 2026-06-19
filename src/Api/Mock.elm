module Api.Mock exposing (api, withDelays)

{-| In-memory adapter standing in for a backend. `Domain.Rooms.rooms` is its
"database" and availability reuses the deterministic domain rule. Delays are
configurable so tests can run without waiting. It never fails, so every result
is an `Ok`.
-}

import Api.Types exposing (BookingApi, BookingRequest)
import Domain.Availability exposing (blockedDateKeys)
import Domain.Date exposing (toIsoKey)
import Domain.Rooms
import Domain.Types exposing (roomIdToString)
import Process
import Set
import Task


type alias Delays =
    { rooms : Float, calendar : Float, submit : Float }


defaultDelays : Delays
defaultDelays =
    { rooms = 900, calendar = 800, submit = 700 }


{-| The default mock adapter (900ms / 800ms simulated latency).
-}
api : BookingApi msg
api =
    withDelays defaultDelays


{-| A mock adapter with custom latencies — handy for tests (e.g. zero delay).
-}
withDelays : Delays -> BookingApi msg
withDelays delays =
    { getRooms =
        \toMsg ->
            after delays.rooms Domain.Rooms.rooms
                |> Task.perform (Ok >> toMsg)
    , getRoomCalendar =
        \roomId from to toMsg ->
            after delays.calendar (Set.toList (blockedDateKeys roomId from to))
                |> Task.perform (Ok >> toMsg)
    , cancelCalendar =
        -- Nothing to abort: the mock is a `Process.sleep` Task, not an HTTP
        -- tracker. The `calendarRequestId` guard still discards a stale reply.
        Cmd.none
    , submitBooking =
        \request toMsg ->
            after delays.submit (reference request)
                |> Task.perform (Ok >> toMsg)
    }


{-| A deterministic confirmation reference, e.g. "BK-20260623-STANDARD". Derived
from the booking (not a random/clock value) so the demo and tests are stable.
-}
reference : BookingRequest -> String
reference request =
    "BK-"
        ++ String.replace "-" "" (toIsoKey request.checkIn)
        ++ "-"
        ++ String.toUpper (roomIdToString request.roomId)


{-| Resolve to `value` after `ms` milliseconds, mimicking network latency.
-}
after : Float -> a -> Task.Task x a
after ms value =
    Process.sleep ms
        |> Task.andThen (\_ -> Task.succeed value)
