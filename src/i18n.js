import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import LanguageDetector from 'i18next-browser-languagedetector'

import en from './locales/en.json'
import es from './locales/es.json'
import zh from './locales/zh.json'
import fr from './locales/fr.json'
import pt from './locales/pt.json'
import ru from './locales/ru.json'
import de from './locales/de.json'
import it from './locales/it.json'
import ja from './locales/ja.json'
import ko from './locales/ko.json'
import hi from './locales/hi.json'

export const LANGUAGES = [
  { code: 'en', label: 'English',            flag: '🇺🇸', nativeLabel: 'English' },
  { code: 'es', label: 'Spanish',            flag: '🇪🇸', nativeLabel: 'Español' },
  { code: 'zh', label: 'Chinese',            flag: '🇨🇳', nativeLabel: '中文' },
  { code: 'fr', label: 'French',             flag: '🇫🇷', nativeLabel: 'Français' },
  { code: 'pt', label: 'Portuguese (BR)',    flag: '🇧🇷', nativeLabel: 'Português' },
  { code: 'ru', label: 'Russian',            flag: '🇷🇺', nativeLabel: 'Русский' },
  { code: 'de', label: 'German',             flag: '🇩🇪', nativeLabel: 'Deutsch' },
  { code: 'it', label: 'Italian',            flag: '🇮🇹', nativeLabel: 'Italiano' },
  { code: 'ja', label: 'Japanese',           flag: '🇯🇵', nativeLabel: '日本語' },
  { code: 'ko', label: 'Korean',             flag: '🇰🇷', nativeLabel: '한국어' },
  { code: 'hi', label: 'Hindi',              flag: '🇮🇳', nativeLabel: 'हिन्दी' },
]

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: { en, es, zh, fr, pt, ru, de, it, ja, ko, hi },
    fallbackLng: 'en',
    defaultNS: 'translation',
    detection: {
      order: ['localStorage', 'navigator'],
      cacheUserLanguage: true,
    },
    interpolation: {
      escapeValue: false,
    },
    // Ensure all components re-render on language change
    react: {
      useSuspense: false,
      bindI18n: 'languageChanged loaded',
      bindI18nStore: 'added removed',
      transEmptyNodeValue: '',
    },
  })

export default i18n
