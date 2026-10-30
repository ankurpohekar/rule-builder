import { useEffect, useState } from 'react'
import { api } from './api'
import ApplicantsPanel from './ApplicantsPanel'
import FaqPage from './FaqPage'
import RulesPanel from './RulesPanel'
import { navigate, usePath } from './router'

export default function App() {
  const [tab, setTab] = useState('applicants')
  const [schema, setSchema] = useState(null)
  const [error, setError] = useState(null)
  const path = usePath()
  const onFaq = path === '/faq'

  useEffect(() => {
    api.schema().then(setSchema).catch((e) => setError(e.message))
  }, [])

  // The FAQ is static, so it doesn't wait for the API.
  if (onFaq) {
    return (
      <div className="app">
        <header><h1>Rule Builder</h1></header>
        <main><FaqPage /></main>
      </div>
    )
  }

  // Tabs live on the home page; a tab click from anywhere else goes home first.
  function openTab(name) {
    setTab(name)
    navigate('/')
  }

  if (error) return <p className="error">Could not reach the API: {error}</p>
  if (!schema) return <p className="muted">Loading…</p>

  return (
    <div className="app">
      <header>
        <h1>Rule Builder</h1>
        <nav>
          <button className={tab === 'applicants' ? 'tab active' : 'tab'} onClick={() => openTab('applicants')}>
            Applicants
          </button>
          <button className={tab === 'rules' ? 'tab active' : 'tab'} onClick={() => openTab('rules')}>
            Rules
          </button>
        </nav>
      </header>
      <main>{tab === 'applicants' ? <ApplicantsPanel schema={schema} /> : <RulesPanel schema={schema} />}</main>
    </div>
  )
}
