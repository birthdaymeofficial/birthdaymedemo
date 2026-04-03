import { Suspense, Component, useState, useEffect, useRef, useCallback } from 'react'
import { I18nextProvider } from 'react-i18next'
import i18n from './i18n'
import BirthdayMeApp from './BirthdayMe'

class ErrorBoundary extends Component {
  constructor(props) { super(props); this.state = { error: null }; }
  static getDerivedStateFromError(error) { return { error }; }
  render() {
    if (this.state.error) {
      return (
        <div style={{
          minHeight: '100vh', display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center',
          background: '#0c0b10', color: '#fff', padding: 24, fontFamily: 'monospace',
        }}>
          <div style={{ fontSize: 40, marginBottom: 16 }}>💥</div>
          <div style={{ fontSize: 16, fontWeight: 700, marginBottom: 8, color: '#ff5a5b' }}>Runtime Error</div>
          <pre style={{
            fontSize: 12, color: 'rgba(255,255,255,.6)', maxWidth: 600,
            whiteSpace: 'pre-wrap', wordBreak: 'break-word', textAlign: 'left',
            background: 'rgba(255,255,255,.05)', padding: 16, borderRadius: 10,
          }}>
            {this.state.error?.message}{'\n\n'}{this.state.error?.stack}
          </pre>
        </div>
      );
    }
    return this.props.children;
  }
}

function AppWithLanguageKey() {
  const [lang, setLang] = useState(i18n.language)

  // Auth state lives HERE — survives language remounts
  const authStateRef = useRef({
    screen: 'auth',
    authUser: null,
    profile: null,
    profileUrl: '',
    demoMode: false,
  })

  // BirthdayMeApp calls this whenever its auth state changes
  const onAuthStateChange = useCallback((state) => {
    authStateRef.current = { ...authStateRef.current, ...state }
  }, [])

  useEffect(() => {
    const handler = (lng) => setLang(lng)
    i18n.on('languageChanged', handler)
    return () => i18n.off('languageChanged', handler)
  }, [])

  const s = authStateRef.current

  return (
    <Suspense fallback={
      <div style={{
        minHeight: '100vh', display: 'flex', alignItems: 'center',
        justifyContent: 'center', background: '#0c0b10',
        color: 'rgba(255,255,255,.4)', fontSize: 32,
      }}>🎂</div>
    }>
      <BirthdayMeApp
        key={lang}
        _initialScreen={s.screen}
        _initialAuthUser={s.authUser}
        _initialProfile={s.profile}
        _initialProfileUrl={s.profileUrl}
        _initialDemoMode={s.demoMode}
        _onStateChange={onAuthStateChange}
      />
    </Suspense>
  )
}

export default function App() {
  return (
    <ErrorBoundary>
      <I18nextProvider i18n={i18n}>
        <AppWithLanguageKey />
      </I18nextProvider>
    </ErrorBoundary>
  )
}
