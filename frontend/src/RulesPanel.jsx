import { useCallback, useEffect, useState } from 'react'
import { api } from './api'
import ConditionGroup from './ConditionGroup'
import { describe, newGroup } from './operators'

export default function RulesPanel({ schema }) {
  const [rules, setRules] = useState(null)
  const [editing, setEditing] = useState(null)
  const [error, setError] = useState(null)
  const [prompt, setPrompt] = useState('')
  const [drafting, setDrafting] = useState(false)

  const load = useCallback(() => {
    api.rules().then(setRules).catch((e) => setError(e.message))
  }, [])

  useEffect(load, [load])

  if (!rules) return error ? <p className="error">{error}</p> : <p className="muted">Loading rules…</p>

  function startNew() {
    const nextPriority = rules.length ? Math.max(...rules.map((r) => r.priority)) + 10 : 10
    setEditing({ name: '', description: '', outcome: 'approved', priority: nextPriority, active: true, conditions: newGroup(schema) })
    setError(null)
  }

  // Claude drafts the rule; it opens in the editor unsaved so it can be checked first.
  async function draft(e) {
    e.preventDefault()
    setDrafting(true)
    setError(null)
    try {
      const rule = await api.draftRule(prompt)
      const nextPriority = rules.length ? Math.max(...rules.map((r) => r.priority)) + 10 : 10
      setEditing({ ...rule, priority: nextPriority, drafted: true })
      setPrompt('')
    } catch (err) {
      setError(err.message)
    } finally {
      setDrafting(false)
    }
  }

  async function save(e) {
    e.preventDefault()
    try {
      const { id, name, description, outcome, priority, active, conditions } = editing
      await api.saveRule({ id, name, description, outcome, priority, active, conditions })
      setEditing(null)
      setError(null)
      load()
    } catch (err) {
      setError(err.message)
    }
  }

  async function toggle(rule) {
    await api.saveRule({ id: rule.id, active: !rule.active })
    load()
  }

  async function remove(id) {
    if (!confirm('Delete this rule? Applicants will be re-evaluated.')) return
    await api.deleteRule(id)
    load()
  }

  const set = (key) => (e) => setEditing({ ...editing, [key]: e.target.value })

  return (
    <section>
      <div className="toolbar">
        <p className="muted">
          Rules run in priority order (lowest first). The first rule that matches sets the applicant’s status; if none
          match, the applicant stays <span className="badge pending">pending</span>.
        </p>
        <button className="primary" onClick={startNew}>Add rule</button>
      </div>

      {!editing && (
        <form className="card draft" onSubmit={draft}>
          <label className="wide">
            Describe a rule in plain English
            <textarea
              rows={2}
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              placeholder="e.g. Reject applicants under 18, or anyone with a credit score below 550 unless they earn over 150k"
              maxLength={2000}
              required
            />
          </label>
          <div className="form-actions">
            <button className="primary" type="submit" disabled={drafting || !prompt.trim()}>
              {drafting ? 'Drafting…' : 'Draft with AI'}
            </button>
          </div>
        </form>
      )}

      {error && !editing && <p className="error">{error}</p>}

      {editing && (
        <form className="card" onSubmit={save}>
          <h2>{editing.id ? 'Edit rule' : 'New rule'}</h2>
          {editing.drafted && <p className="muted">Review the AI draft before saving.</p>}
          <div className="form-grid">
            <label>Name<input value={editing.name} onChange={set('name')} required /></label>
            <label>
              Outcome
              <select value={editing.outcome} onChange={set('outcome')}>
                {schema.outcomes.map((o) => <option key={o} value={o}>{o}</option>)}
              </select>
            </label>
            <label>
              Priority
              <input type="number" value={editing.priority} onChange={(e) => setEditing({ ...editing, priority: Number(e.target.value) })} />
            </label>
            <label className="inline">
              <input type="checkbox" checked={editing.active} onChange={(e) => setEditing({ ...editing, active: e.target.checked })} />
              Active
            </label>
            <label className="wide">Description<input value={editing.description ?? ''} onChange={set('description')} /></label>
          </div>

          <h3>Conditions</h3>
          <ConditionGroup group={editing.conditions} schema={schema} onChange={(conditions) => setEditing({ ...editing, conditions })} />
          <p className="muted preview">{describe(editing.conditions, schema) || 'No conditions yet'}</p>

          {error && <p className="error">{error}</p>}
          <div className="form-actions">
            <button type="button" onClick={() => setEditing(null)}>Cancel</button>
            <button className="primary" type="submit">Save rule</button>
          </div>
        </form>
      )}

      <ol className="rules">
        {rules.map((rule) => (
          <li key={rule.id} className={rule.active ? 'card rule' : 'card rule inactive'}>
            <div className="rule-head">
              <span className="priority">#{rule.priority}</span>
              <strong>{rule.name}</strong>
              <span>→</span>
              <span className={`badge ${rule.outcome}`}>{rule.outcome}</span>
              {!rule.active && <span className="muted">(inactive)</span>}
              <div className="row-actions">
                <button onClick={() => toggle(rule)}>{rule.active ? 'Disable' : 'Enable'}</button>
                <button onClick={() => { setEditing(rule); setError(null) }}>Edit</button>
                <button className="danger" onClick={() => remove(rule.id)}>Delete</button>
              </div>
            </div>
            {rule.description && <p className="muted">{rule.description}</p>}
            <code>{describe(rule.conditions, schema)}</code>
          </li>
        ))}
        {rules.length === 0 && <p className="muted center">No rules yet.</p>}
      </ol>
    </section>
  )
}
