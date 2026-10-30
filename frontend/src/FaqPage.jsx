import { useEffect, useMemo, useState } from 'react'
import { api } from './api'
import FaqBot from './FaqBot'
import Link from './Link'

// DOM id for a question, so source links from the bot can scroll to it.
const faqElementId = (key) => `faq-${key.replace(':', '-')}`

export default function FaqPage() {
  const [sections, setSections] = useState(null)
  const [error, setError] = useState(null)
  const [search, setSearch] = useState('')
  // Keys ("section:index", from the server) of the questions toggled open. Searching opens every match instead.
  const [open, setOpen] = useState(() => new Set())

  useEffect(() => {
    api.faqs().then(setSections).catch((e) => setError(e.message))
  }, [])

  const term = search.trim().toLowerCase()
  const visible = useMemo(() => {
    if (!sections || !term) return sections
    return sections.map((section) => ({
      ...section,
      items: section.items.filter((item) => `${item.q} ${item.a}`.toLowerCase().includes(term)),
    })).filter((section) => section.items.length > 0)
  }, [sections, term])

  if (!sections) return error ? <p className="error">{error}</p> : <p className="muted">Loading FAQ…</p>

  const allKeys = sections.flatMap((section) => section.items.map((item) => item.key))
  const matches = visible.reduce((sum, section) => sum + section.items.length, 0)

  function toggle(key, isOpen) {
    setOpen((prev) => {
      const next = new Set(prev)
      if (isOpen) next.add(key)
      else next.delete(key)
      return next
    })
  }

  // Opens one question and scrolls to it (used by the bot's source links).
  function reveal(key) {
    setSearch('')
    setOpen((prev) => new Set(prev).add(key))
    requestAnimationFrame(() => {
      const element = document.getElementById(faqElementId(key))
      if (!element) return
      element.scrollIntoView({ behavior: 'smooth', block: 'center' })
      element.classList.add('flash')
      setTimeout(() => element.classList.remove('flash'), 1600)
    })
  }

  return (
    <section className="faq">
      <Link to="/" className="back">← Back to applicants</Link>

      <div className="faq-intro">
        <h2>Frequently asked questions</h2>
        <p className="muted">
          {allKeys.length} answers about applicants, rules, evaluation, AI drafting and the API.
          Can’t find yours? Ask the assistant in the corner.
        </p>
      </div>

      <div className="toolbar">
        <div className="filters">
          <input
            type="search"
            className="search"
            placeholder="Search questions and answers"
            aria-label="Search the FAQ"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          {term && <span className="muted">{matches} {matches === 1 ? 'match' : 'matches'}</span>}
        </div>
        {!term && (
          <div className="actions">
            <button onClick={() => setOpen(new Set(allKeys))}>Expand all</button>
            <button onClick={() => setOpen(new Set())}>Collapse all</button>
          </div>
        )}
      </div>

      {!term && (
        <nav className="faq-toc" aria-label="FAQ sections">
          {sections.map((section) => (
            <a key={section.id} href={`#${section.id}`}>{section.title}</a>
          ))}
        </nav>
      )}

      {visible.map((section) => (
        <div key={section.id} id={section.id} className="faq-section">
          <h3>{section.title}</h3>
          <div className="card faq-list">
            {section.items.map((item) => (
              <details
                key={item.key}
                id={faqElementId(item.key)}
                open={Boolean(term) || open.has(item.key)}
                onToggle={(e) => !term && toggle(item.key, e.currentTarget.open)}
              >
                <summary>{item.q}</summary>
                {item.a.split('\n\n').map((paragraph, i) => <p key={i}>{paragraph}</p>)}
              </details>
            ))}
          </div>
        </div>
      ))}

      {term && matches === 0 && (
        <p className="muted center">No questions match “{search.trim()}”.</p>
      )}

      <FaqBot onSourceClick={reveal} />
    </section>
  )
}
