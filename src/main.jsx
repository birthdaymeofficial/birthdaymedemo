import React from 'react'
import ReactDOM from 'react-dom/client'
import './i18n' // must import before App so i18n is initialized
import App from './App'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
