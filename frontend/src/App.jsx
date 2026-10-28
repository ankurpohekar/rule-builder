import { useEffect, useState } from 'react'
import { api } from './api'
import ApplicantsPanel from './ApplicantsPanel'
import RulesPanel from './RulesPanel'

export default function App() {
  const [tab, setTab] = useState('applicants')
  const [schema, setSchema] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => {
    api.schema().then(setSchema).catch((e) => setError(e.message))
  }, [])

  if (error) return <p className="error">Could not reach the API: {error}</p>
  if (!schema) return <p className="muted">Loading…</p>

  return (
    <div className="app">
      <header>
        <h1>Rule Builder</h1>
        <nav>
          <button className={tab === 'applicants' ? 'tab active' : 'tab'} onClick={() => setTab('applicants')}>
            Applicants
          </button>
          <button className={tab === 'rules' ? 'tab active' : 'tab'} onClick={() => setTab('rules')}>
            Rules
          </button>
        </nav>
      </header>
      <main>{tab === 'applicants' ? <ApplicantsPanel schema={schema} /> : <RulesPanel schema={schema} />}</main>
    </div>
  )
}
