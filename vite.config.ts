import { defineConfig } from 'vite'
import elmPlugin from 'vite-plugin-elm'

// GitHub Pages serves the project from a sub-path; mirror the sibling projects.
export default defineConfig({
  base: process.env.BASE_PATH ?? '/',
  plugins: [elmPlugin()],
})
