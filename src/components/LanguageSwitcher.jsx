import { useState, useRef, useEffect } from 'react'
import { useTranslation } from 'react-i18next'
import { LANGUAGES } from '../i18n'

/**
 * LanguageSwitcher
 * Props:
 *   variant = 'dropdown' | 'list'
 *   onClose (optional) — called after selection, useful for closing modals
 */
export default function LanguageSwitcher({ variant = 'dropdown', onClose }) {
  const { i18n, t } = useTranslation()
  const [open, setOpen] = useState(false)
  const ref = useRef(null)

  const current = LANGUAGES.find(l => l.code === i18n.language) || LANGUAGES[0]

  useEffect(() => {
    const handleClick = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false)
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [])

  const select = (code) => {
    i18n.changeLanguage(code)
    setOpen(false)
    onClose?.()
  }

  // ── List variant (used inside Settings drawer) ──────────────────────────
  if (variant === 'list') {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        {LANGUAGES.map(lang => (
          <button
            key={lang.code}
            onClick={() => select(lang.code)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 12,
              padding: '11px 14px',
              borderRadius: 10,
              border: lang.code === i18n.language
                ? '1px solid var(--violet)'
                : '1px solid transparent',
              background: lang.code === i18n.language
                ? 'rgba(155,93,229,.1)'
                : 'transparent',
              cursor: 'pointer',
              textAlign: 'left',
              transition: 'all .15s',
            }}
          >
            <span style={{ fontSize: 22, lineHeight: 1, flexShrink: 0 }}>{lang.flag}</span>
            <span style={{
              flex: 1,
              fontSize: 14,
              fontWeight: lang.code === i18n.language ? 700 : 500,
              color: lang.code === i18n.language ? 'var(--violet2)' : 'var(--text)',
            }}>
              {lang.nativeLabel}
            </span>
            <span style={{ fontSize: 12, color: 'var(--muted)' }}>{lang.label}</span>
            {lang.code === i18n.language && (
              <span style={{ color: 'var(--violet2)', fontSize: 16, flexShrink: 0 }}>✓</span>
            )}
          </button>
        ))}
      </div>
    )
  }

  // ── Dropdown variant (used on auth screen) ───────────────────────────────
  return (
    <div ref={ref} style={{ position: 'relative', display: 'inline-block' }}>
      <button
        onClick={() => setOpen(o => !o)}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 6,
          padding: '6px 12px',
          borderRadius: 20,
          border: '1px solid var(--border)',
          background: 'var(--s2)',
          color: 'var(--muted2)',
          cursor: 'pointer',
          fontSize: 13,
          fontWeight: 600,
        }}
      >
        <span style={{ fontSize: 18 }}>{current.flag}</span>
        <span>{current.nativeLabel}</span>
        <span style={{ fontSize: 10, opacity: 0.6 }}>{open ? '▲' : '▼'}</span>
      </button>

      {open && (
        <div style={{
          position: 'absolute',
          top: 'calc(100% + 6px)',
          right: 0,
          background: 'var(--surface)',
          border: '1px solid var(--border)',
          borderRadius: 14,
          boxShadow: '0 8px 32px rgba(0,0,0,.3)',
          zIndex: 1000,
          minWidth: 200,
          overflow: 'hidden',
          padding: 6,
        }}>
          {LANGUAGES.map(lang => (
            <button
              key={lang.code}
              onClick={() => select(lang.code)}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                width: '100%',
                padding: '9px 12px',
                borderRadius: 8,
                border: 'none',
                background: lang.code === i18n.language ? 'rgba(155,93,229,.1)' : 'transparent',
                cursor: 'pointer',
                textAlign: 'left',
              }}
            >
              <span style={{ fontSize: 20, lineHeight: 1 }}>{lang.flag}</span>
              <span style={{
                flex: 1,
                fontSize: 13,
                fontWeight: lang.code === i18n.language ? 700 : 500,
                color: lang.code === i18n.language ? 'var(--violet2)' : 'var(--text)',
              }}>
                {lang.nativeLabel}
              </span>
              {lang.code === i18n.language && (
                <span style={{ color: 'var(--violet2)', fontSize: 14 }}>✓</span>
              )}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
