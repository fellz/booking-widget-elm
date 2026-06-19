module Ui exposing
    ( ButtonVariant(..)
    , Direction(..)
    , Pad(..)
    , Step
    , SurfaceTag(..)
    , SurfaceTone(..)
    , Tone(..)
    , badge
    , block
    , button
    , column
    , row
    , segmented
    , skeleton
    , split
    , stack
    , stepper
    , steps
    , surface
    , surfaceMuted
    )

{-| The reusable UI kit, ported from `src/ui/*.vue` to plain `Html` helpers. Same
class names as the original so the shared stylesheet applies unchanged. Atoms
(`button`, `badge`, `surface`), molecules (`stepper`, `segmented`, `steps`) and
layout primitives (`stack`, `split`, `skeleton`) — organisms in `View` are built
almost entirely from these.
-}

import Html exposing (Attribute, Html, text)
import Html.Attributes exposing (attribute, class, classList, disabled, style, type_)
import Html.Events exposing (onClick)



-- BUTTON


type ButtonVariant
    = Primary
    | Ghost
    | Icon


button : ButtonVariant -> List (Attribute msg) -> List (Html msg) -> Html msg
button variant attrs children =
    Html.button
        (type_ "button"
            :: class "ui-button"
            :: class ("ui-button--" ++ buttonVariantClass variant)
            :: attrs
        )
        children


{-| Pass into a button's attribute list to make it fill its row.
-}
block : Attribute msg
block =
    class "ui-button--block"


buttonVariantClass : ButtonVariant -> String
buttonVariantClass variant =
    case variant of
        Primary ->
            "primary"

        Ghost ->
            "ghost"

        Icon ->
            "icon"



-- BADGE


type Tone
    = Muted
    | Danger
    | Accent


badge : Tone -> String -> Html msg
badge tone content =
    Html.span [ class "ui-badge", class ("ui-badge--" ++ toneClass tone) ] [ text content ]


toneClass : Tone -> String
toneClass tone =
    case tone of
        Muted ->
            "muted"

        Danger ->
            "danger"

        Accent ->
            "accent"



-- SURFACE


type SurfaceTag
    = SurfaceDiv
    | SurfaceButton


type SurfaceTone
    = ToneSurface
    | ToneMuted


type Pad
    = PadNone
    | PadSm
    | PadMd


surface :
    { tag : SurfaceTag
    , tone : SurfaceTone
    , pad : Pad
    , interactive : Bool
    , selected : Bool
    , attrs : List (Attribute msg)
    }
    -> List (Html msg)
    -> Html msg
surface config children =
    let
        element =
            case config.tag of
                SurfaceDiv ->
                    Html.div

                SurfaceButton ->
                    Html.button

        baseAttrs =
            [ class "ui-surface"
            , class ("ui-surface--" ++ surfaceToneClass config.tone)
            , class ("ui-surface--pad-" ++ padClass config.pad)
            , classList
                [ ( "ui-surface--interactive", config.interactive )
                , ( "ui-surface--selected", config.selected )
                ]
            ]
    in
    element (baseAttrs ++ config.attrs) children


{-| The common case: a static muted panel.
-}
surfaceMuted : List (Attribute msg) -> List (Html msg) -> Html msg
surfaceMuted attrs children =
    surface
        { tag = SurfaceDiv
        , tone = ToneMuted
        , pad = PadMd
        , interactive = False
        , selected = False
        , attrs = attrs
        }
        children


surfaceToneClass : SurfaceTone -> String
surfaceToneClass tone =
    case tone of
        ToneSurface ->
            "surface"

        ToneMuted ->
            "muted"


padClass : Pad -> String
padClass pad =
    case pad of
        PadNone ->
            "none"

        PadSm ->
            "sm"

        PadMd ->
            "md"



-- STACK / SPLIT


type Direction
    = Row
    | Column


{-| Flexbox layout primitive. `align`/`justify` take raw CSS values (or "" to
skip). Spacing uses the token scale via `--space-N`.
-}
stack :
    { direction : Direction
    , gap : Int
    , align : String
    , justify : String
    , attrs : List (Attribute msg)
    }
    -> List (Html msg)
    -> Html msg
stack config children =
    let
        directionValue =
            case config.direction of
                Row ->
                    "row"

                Column ->
                    "column"

        optional name value =
            if value == "" then
                []

            else
                [ style name value ]
    in
    Html.div
        (class "ui-stack"
            :: style "flex-direction" directionValue
            :: style "gap" ("var(--space-" ++ String.fromInt config.gap ++ ")")
            :: (optional "align-items" config.align
                    ++ optional "justify-content" config.justify
                    ++ config.attrs
               )
        )
        children


{-| A column stack with just a gap (the most common shape).
-}
column : Int -> List (Html msg) -> Html msg
column gap children =
    stack { direction = Column, gap = gap, align = "", justify = "", attrs = [] } children


{-| A row stack with just a gap.
-}
row : Int -> List (Html msg) -> Html msg
row gap children =
    stack { direction = Row, gap = gap, align = "", justify = "", attrs = [] } children


split : List (Html msg) -> Html msg
split children =
    Html.div [ class "ui-split" ] children



-- SKELETON


skeleton : Int -> Html msg
skeleton height =
    Html.div
        [ class "ui-skeleton"
        , style "height" (String.fromInt height ++ "px")
        , style "border-radius" "var(--radius-md)"
        , attribute "aria-hidden" "true"
        ]
        []



-- STEPPER


stepper :
    { value : Int, min : Int, max : Int, ariaLabel : String, onChange : Int -> msg }
    -> List (Html msg)
    -> Html msg
stepper config valueContent =
    let
        stepTo delta =
            clamp config.min config.max (config.value + delta)
    in
    Html.div [ class "ui-stepper", attribute "role" "group", attribute "aria-label" config.ariaLabel ]
        [ button Icon
            [ disabled (config.value <= config.min)
            , attribute "aria-label" "−"
            , onClick (config.onChange (stepTo -1))
            ]
            [ text "−" ]
        , Html.span [ class "ui-stepper__value", attribute "aria-live" "polite" ] valueContent
        , button Icon
            [ disabled (config.value >= config.max)
            , attribute "aria-label" "+"
            , onClick (config.onChange (stepTo 1))
            ]
            [ text "+" ]
        ]



-- SEGMENTED


segmented :
    { options : List { value : a, label : String }, selected : a, onSelect : a -> msg }
    -> Html msg
segmented config =
    Html.div [ class "ui-segmented", attribute "role" "group" ]
        (List.map
            (\option ->
                let
                    active =
                        option.value == config.selected
                in
                Html.button
                    [ type_ "button"
                    , class "ui-segmented__option"
                    , classList [ ( "ui-segmented__option--active", active ) ]
                    , attribute "aria-pressed" (boolString active)
                    , onClick (config.onSelect option.value)
                    ]
                    [ text option.label ]
            )
            config.options
        )



-- STEPS


{-| Each step carries its own optional back-action. A `Just msg` makes the node a
clickable button that emits `msg`; `Nothing` renders an inert label. Navigability
is thus a property of the step itself, decided by the caller from the flow state —
not a position the stepper re-derives (`onSelect : Int -> msg`) and the caller
re-checks with an `index == 0` guard (audit hole 7.2).
-}
type alias Step msg =
    { label : String, onBack : Maybe msg }


steps : { steps : List (Step msg), current : Int } -> Html msg
steps config =
    Html.ol [ class "steps" ]
        (List.indexedMap
            (\i { label, onBack } ->
                let
                    isDone =
                        i < config.current

                    nodeAttrs =
                        [ class "steps__node"
                        , attribute "aria-current"
                            (if i == config.current then
                                "step"

                             else
                                ""
                            )
                        ]

                    node =
                        case onBack of
                            Just msg ->
                                Html.button (type_ "button" :: onClick msg :: nodeAttrs)
                                    (stepNodeChildren i config.current label)

                            Nothing ->
                                Html.span nodeAttrs (stepNodeChildren i config.current label)
                in
                Html.li
                    [ class "steps__item"
                    , classList
                        [ ( "steps__item--active", i == config.current )
                        , ( "steps__item--done", isDone )
                        ]
                    ]
                    [ node ]
            )
            config.steps
        )


stepNodeChildren : Int -> Int -> String -> List (Html msg)
stepNodeChildren i current label =
    [ Html.span [ class "steps__marker" ]
        [ text
            (if i < current then
                "✓"

             else
                String.fromInt (i + 1)
            )
        ]
    , Html.span [ class "steps__label" ] [ text label ]
    ]


boolString : Bool -> String
boolString value =
    if value then
        "true"

    else
        "false"
