import { Elm } from './Main.elm'
import './styles.css'

const STORAGE_KEY = 'booking-widget-theme'

/** Read the persisted theme, falling back to the OS preference. */
function initialTheme(): 'light' | 'dark' {
  const stored = localStorage.getItem(STORAGE_KEY)
  if (stored === 'light' || stored === 'dark') return stored
  return window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

/**
 * The single timezone boundary of the whole app: turn the runtime clock into a
 * calendar day in the user's local zone, as a `YYYY-MM-DD` string. Everything
 * downstream in Elm works with that calendar `Date`, never with a zone again.
 */
function todayIso(): string {
  const now = new Date()
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, '0')
  const d = String(now.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

const theme = initialTheme()

// Apply the initial theme/lang before Elm renders, to avoid a flash.
document.documentElement.dataset.theme = theme
document.documentElement.lang = 'ru'

const app = Elm.Main.init({
  node: document.getElementById('app'),
  flags: {
    today: todayIso(),
    theme,
    apiUrl: import.meta.env.VITE_API_URL ?? '',
    assetBase: import.meta.env.BASE_URL,
  },
})

// Outbound ports — the only writers of localStorage / documentElement at runtime.
app.ports.setTheme.subscribe((next: string) => {
  document.documentElement.dataset.theme = next
  localStorage.setItem(STORAGE_KEY, next)
})

app.ports.setLang.subscribe((lang: string) => {
  document.documentElement.lang = lang
})
