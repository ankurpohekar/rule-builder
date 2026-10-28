import { useCallback, useEffect, useRef, useState } from 'react'
import { api } from './api'

const EMPTY = { name: '', email: '', age: '', credit_score: '', annual_income: '', employment_status: '', country: '' }

// Filters live in the URL so a refresh or shared link keeps them.
const initialParams = new URLSearchParams(window.location.search)

export default function ApplicantsPanel({ schema }) {
  const [applicants, setApplicants] = useState(null)
  const [search, setSearch] = useState(initialParams.get('q') ?? '')
  const [query, setQuery] = useState(search)
  const [status, setStatus] = useState(initialParams.get('status') ?? '')
  const [editing, setEditing] = useState(null)
  const [error, setError] = useState(null)
  const [reevaluating, setReevaluating] = useState(false)

  // Wait for a pause in typing before hitting the API.
  useEffect(() => {
    const timer = setTimeout(() => setQuery(search.trim()), 300)
    return () => clearTimeout(timer)
  }, [search])

  // Only the newest request may update the list, so a slow older response can't overwrite it.
  const latestRequest = useRef(0)
  // The last create attempt: { body, key }. Retrying the same body reuses the key.
  const createAttempt = useRef(null)
  const load = useCallback(() => {
    const requestId = ++latestRequest.current
    api
      .applicants({ q: query, status })
      .then((data) => requestId === latestRequest.current && setApplicants(data))
      .catch((e) => setError(e.message))
  }, [query, status])

  useEffect(load, [load])

  useEffect(() => {
    const params = new URLSearchParams()
    if (query) params.set('q', query)
    if (status) params.set('status', status)
    window.history.replaceState(null, '', params.size ? `?${params}` : window.location.pathname)
  }, [query, status])

  if (!applicants) return error ? <p className="error">{error}</p> : <p className="muted">Loading applicants…</p>

  const filtered = query !== '' || status !== ''
  const employment = schema.fields.find((f) => f.key === 'employment_status').options

  async function save(e) {
    e.preventDefault()
    try {
      // Empty inputs mean "unknown", which the API stores as null.
      const payload = { id: editing.id }
      for (const key of Object.keys(EMPTY)) payload[key] = editing[key] === '' ? null : editing[key]
      await api.saveApplicant(payload, { idempotencyKey: payload.id ? undefined : idempotencyKeyFor(payload) })
      createAttempt.current = null
      setEditing(null)
      setError(null)
      load()
    } catch (err) {
      setError(err.message)
    }
  }

  // One key per distinct submission: a double-click or a retry after a network error sends
  // the same body and the same key (the server replays the first result); editing the form
  // changes the body, which needs a new key.
  function idempotencyKeyFor(payload) {
    const body = JSON.stringify(payload)
    if (createAttempt.current?.body !== body) createAttempt.current = { body, key: crypto.randomUUID() }
    return createAttempt.current.key
  }

  async function remove(id) {
    if (!confirm('Delete this applicant?')) return
    await api.deleteApplicant(id)
    load()
  }

  // The API only queues a background job, so give it a moment before reloading.
  async function reevaluate() {
    setReevaluating(true)
    try {
      await api.evaluateAll()
      await new Promise((resolve) => setTimeout(resolve, 1000))
      load()
    } catch (err) {
      setError(err.message)
    } finally {
      setReevaluating(false)
    }
  }

  const set = (key) => (e) => setEditing({ ...editing, [key]: e.target.value })

  return (
    <section>
      <div className="toolbar">
        <div className="filters">
          <input
            type="search"
            className="search"
            placeholder="Search name or email"
            aria-label="Search applicants by name or email"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <select aria-label="Filter by status" value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">All statuses</option>
            {schema.statuses.map((s) => (
              <option key={s} value={s}>{s[0].toUpperCase() + s.slice(1)}</option>
            ))}
          </select>
          {filtered && (
            <button onClick={() => { setSearch(''); setQuery(''); setStatus('') }}>Clear</button>
          )}
          <span className="muted">{applicants.length} {applicants.length === 1 ? 'applicant' : 'applicants'}</span>
        </div>
        <div className="actions">
          <button onClick={reevaluate} disabled={reevaluating}>
            {reevaluating ? 'Re-evaluating…' : 'Re-evaluate all'}
          </button>
          <button className="primary" onClick={() => setEditing(EMPTY)}>
            Add applicant
          </button>
        </div>
      </div>

      {error && <p className="error">{error}</p>}

      {editing && (
        <form className="card form-grid" onSubmit={save}>
          <h2>{editing.id ? 'Edit applicant' : 'New applicant'}</h2>
          <label>Name<input value={editing.name} onChange={set('name')} required /></label>
          <label>Email<input type="email" value={editing.email} onChange={set('email')} required /></label>
          <label>Age<input type="number" value={editing.age ?? ''} onChange={set('age')} /></label>
          <label>Credit score<input type="number" value={editing.credit_score ?? ''} onChange={set('credit_score')} /></label>
          <label>Annual income<input type="number" step="0.01" value={editing.annual_income ?? ''} onChange={set('annual_income')} /></label>
          <label>
            Employment status
            <select value={editing.employment_status ?? ''} onChange={set('employment_status')}>
              <option value="">—</option>
              {employment.map((o) => <option key={o} value={o}>{o.replace('_', ' ')}</option>)}
            </select>
          </label>
          <label>Country<input value={editing.country ?? ''} onChange={set('country')} placeholder="e.g. US" /></label>
          <div className="form-actions">
            <button type="button" onClick={() => setEditing(null)}>Cancel</button>
            <button className="primary" type="submit">Save</button>
          </div>
        </form>
      )}

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Name</th><th>Age</th><th>Credit</th><th>Income</th><th>Employment</th><th>Country</th>
              <th>Status</th><th>Decided by</th><th></th>
            </tr>
          </thead>
          <tbody>
            {applicants.map((a) => (
              <tr key={a.id}>
                <td><strong>{a.name}</strong><div className="muted">{a.email}</div></td>
                <td>{a.age ?? '—'}</td>
                <td>{a.credit_score ?? '—'}</td>
                <td>{a.annual_income != null ? Number(a.annual_income).toLocaleString() : '—'}</td>
                <td>{a.employment_status?.replace('_', ' ') ?? '—'}</td>
                <td>{a.country ?? '—'}</td>
                <td><span className={`badge ${a.status}`}>{a.status}</span></td>
                <td className="muted">{a.matched_rule?.name ?? 'No rule matched'}</td>
                <td className="row-actions">
                  <button onClick={() => setEditing(a)}>Edit</button>
                  <button className="danger" onClick={() => remove(a.id)}>Delete</button>
                </td>
              </tr>
            ))}
            {applicants.length === 0 && (
              <tr><td colSpan="9" className="muted center">{filtered ? 'No applicants match these filters.' : 'No applicants.'}</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </section>
  )
}
