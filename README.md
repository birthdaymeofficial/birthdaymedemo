# Birthday Me — Scaffolded React App

A properly structured Vite + React application with full i18n support, ready for Cloudflare Pages deployment.

---

## Getting Started

### 1. Install dependencies
```bash
npm install
```

### 2. Run in development
```bash
npm run dev
```
Opens at `http://localhost:5173`

### 3. Build for production
```bash
npm run build
```
Outputs to `/dist`

### 4. Preview production build locally
```bash
npm run preview
```

---

## Deploy to Cloudflare Pages

1. Push this project to a GitHub repository
2. Go to [Cloudflare Pages](https://pages.cloudflare.com)
3. Connect your GitHub repo
4. Set build settings:
   - **Build command:** `npm run build`
   - **Build output directory:** `dist`
5. Deploy

The `public/_redirects` file handles SPA routing automatically.

---

## Project Structure

```
src/
├── main.jsx              # React entry point
├── App.jsx               # i18n provider wrapper
├── BirthdayMe.jsx        # Full app (migrated from single-file demo)
├── i18n.js               # i18next configuration + language list
├── components/
│   └── LanguageSwitcher.jsx  # Reusable language selector component
└── locales/              # Translation files
    ├── en.json           # English (default)
    ├── es.json           # Spanish
    ├── zh.json           # Chinese (Simplified)
    ├── fr.json           # French
    ├── pt.json           # Portuguese (BR)
    ├── ru.json           # Russian
    ├── de.json           # German
    ├── it.json           # Italian
    ├── ja.json           # Japanese
    ├── ko.json           # Korean
    └── hi.json           # Hindi
```

---

## Language Switcher

The language switcher appears in two places:

1. **Auth/Landing screen** — top right corner, dropdown style  
   Users can select their language before signing up.

2. **Settings drawer** — under Preferences section, inline list  
   Logged-in users can change language anytime from Settings.

Language preference is stored in `localStorage` and auto-detected from the browser on first load via `i18next-browser-languagedetector`.

### Adding a new language

1. Create `src/locales/XX.json` (copy `en.json` as template)
2. Translate all values
3. Add to `src/i18n.js`:
   ```js
   import xx from './locales/xx.json'
   // add to resources: { ..., xx }
   // add to LANGUAGES array: { code: 'xx', label: 'Language', flag: '🏳️', nativeLabel: 'Native Name' }
   ```

---

## Environment Variables

No environment variables are required to run the app. 

For production, you may want to set:
- `VITE_ANTHROPIC_API_KEY` — if you move the AI support chat key to an env variable (currently handled by the artifact API proxy)

---

## Tech Stack

- **React 18** — UI framework
- **Vite 5** — Build tool & dev server
- **i18next + react-i18next** — Internationalization
- **i18next-browser-languagedetector** — Auto language detection
- **Cloudflare Pages** — Hosting & CDN
