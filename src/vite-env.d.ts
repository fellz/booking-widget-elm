/// <reference types="vite/client" />

// vite-plugin-elm exposes compiled modules as an `Elm` object. We keep the
// types loose here; the type safety that matters lives inside Elm.
declare module '*.elm' {
  export const Elm: {
    Main: {
      init(options: { node: HTMLElement | null; flags: unknown }): {
        ports: {
          setTheme: { subscribe(handler: (value: string) => void): void }
          setLang: { subscribe(handler: (value: string) => void): void }
        }
      }
    }
  }
}
