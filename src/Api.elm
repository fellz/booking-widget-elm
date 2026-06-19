module Api exposing (create)

{-| The single place that chooses the data feed. A non-empty base URL (from
`VITE_API_URL`, passed in as a flag) selects the Schema-decoded HTTP adapter;
otherwise the widget runs against the in-memory mock. This is the only line that
changes when the real API arrives.
-}

import Api.Http
import Api.Mock
import Api.Types exposing (BookingApi)


create : Maybe String -> BookingApi msg
create maybeBaseUrl =
    case maybeBaseUrl of
        Just baseUrl ->
            Api.Http.api baseUrl

        Nothing ->
            Api.Mock.api
