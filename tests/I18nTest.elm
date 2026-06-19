module I18nTest exposing (suite)

{-| Exact-string tests for the hand-rolled formatting. They double as
documentation of what the (Intl-free) i18n layer actually produces.
-}

import Date
import Domain.Types exposing (Locale(..))
import Expect
import I18n
import Test exposing (Test, describe, test)
import Time exposing (Month(..))


nbsp : String
nbsp =
    "\u{00A0}"


ru : I18n.Messages
ru =
    I18n.messages Ru


en : I18n.Messages
en =
    I18n.messages En


suite : Test
suite =
    describe "I18n"
        [ describe "formatPrice"
            [ test "ru groups thousands and suffixes the ruble sign" <|
                \_ -> I18n.formatPrice Ru 4500 |> Expect.equal ("4" ++ nbsp ++ "500" ++ nbsp ++ "₽")
            , test "ru handles six figures" <|
                \_ -> I18n.formatPrice Ru 99000 |> Expect.equal ("99" ++ nbsp ++ "000" ++ nbsp ++ "₽")
            , test "en prefixes the euro sign, no grouping needed" <|
                \_ -> I18n.formatPrice En 49 |> Expect.equal "€49"
            , test "en groups thousands with a comma" <|
                \_ -> I18n.formatPrice En 1090 |> Expect.equal "€1,090"
            ]
        , describe "Russian plurals (guests)"
            [ test "1 → гость" <|
                \_ -> ru.guest 1 |> Expect.equal "гость"
            , test "2 → гостя" <|
                \_ -> ru.guest 2 |> Expect.equal "гостя"
            , test "5 → гостей" <|
                \_ -> ru.guest 5 |> Expect.equal "гостей"
            , test "11 → гостей (teen exception)" <|
                \_ -> ru.guest 11 |> Expect.equal "гостей"
            , test "21 → гость" <|
                \_ -> ru.guest 21 |> Expect.equal "гость"
            ]
        , describe "nights"
            [ test "ru 1 night" <|
                \_ -> ru.nights 1 |> Expect.equal "1 ночь"
            , test "ru 2 nights" <|
                \_ -> ru.nights 2 |> Expect.equal "2 ночи"
            , test "ru 5 nights" <|
                \_ -> ru.nights 5 |> Expect.equal "5 ночей"
            , test "en 1 night" <|
                \_ -> en.nights 1 |> Expect.equal "1 night"
            , test "en 3 nights" <|
                \_ -> en.nights 3 |> Expect.equal "3 nights"
            ]
        , describe "dates"
            [ test "ru formatDate uses the genitive month" <|
                \_ -> I18n.formatDate Ru (Date.fromCalendarDate 2026 Jun 19) |> Expect.equal "19 июня"
            , test "en formatDate" <|
                \_ -> I18n.formatDate En (Date.fromCalendarDate 2026 Jun 19) |> Expect.equal "19 June"
            , test "ru monthLabel uses the nominative month" <|
                \_ -> I18n.monthLabel Ru (Date.fromCalendarDate 2026 Jun 1) |> Expect.equal "июнь 2026"
            , test "en monthLabel" <|
                \_ -> I18n.monthLabel En (Date.fromCalendarDate 2026 Jun 1) |> Expect.equal "June 2026"
            ]
        ]
