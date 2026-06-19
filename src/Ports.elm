port module Ports exposing (setLang, setTheme)

{-| The two thin outbound effects that have to touch the document root (which
lives outside the Elm-controlled `#app` node): persisting/applying the theme and
setting the `<html lang>` attribute. The JS side (`main.ts`) is the only place
that writes to `localStorage` or `documentElement`.
-}


{-| Apply `data-theme` to `<html>` and persist it to localStorage.
-}
port setTheme : String -> Cmd msg


{-| Set the `<html lang>` attribute.
-}
port setLang : String -> Cmd msg
