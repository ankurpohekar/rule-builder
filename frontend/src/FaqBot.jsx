import { useEffect, useRef, useState } from 'react'
import { api } from './api'

const SUGGESTIONS = [
  'Why is everyone still pending?',
  'Can I get a deleted applicant back?',
  'What does a 409 error mean?',
  'Does the AI make up applicant details?',
]

// Floating "Ask a question" assistant. Answers come from the FAQ (retrieval + Claude) and list the
// entries they used; clicking one opens it on the page via onSourceClick.
export default function FaqBot({ onSourceClick }) {
  const [open, setOpen] = useState(false)
  // { role: 'user' | 'assistant', content, id?, sources?, answered?, feedback? }
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [asking, setAsking] = useState(false)
  const [error, setError] = useState(null)
  const listRef = useRef(null)
  const inputRef = useRef(null)

  useEffect(() => {
    listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: 'smooth' })
  }, [messages, asking])

  useEffect(() => {
    if (open) inputRef.current?.focus()
  }, [open])

  async function ask(question) {
    question = question.trim()
    if (!question || asking) return
    // The server only needs the text of earlier turns to understand a follow-up.
    const history = messages.map(({ role, content }) => ({ role, content }))
    setMessages((prev) => [...prev, { role: 'user', content: question }])
    setInput('')
    setError(null)
    setAsking(true)
    try {
      const reply = await api.askFaq(question, history)
      setMessages((prev) => [
        ...prev,
        { role: 'assistant', content: reply.answer, id: reply.id, sources: reply.sources, answered: reply.answered },
      ])
    } catch (err) {
      // Put the question back so it can be retried as is.
      setMessages((prev) => prev.slice(0, -1))
      setInput(question)
      setError(err.message)
    } finally {
      setAsking(false)
    }
  }

  async function rate(message, feedback) {
    const value = message.feedback === feedback ? null : feedback
    setMessages((prev) => prev.map((m) => (m === message ? { ...m, feedback: value } : m)))
    if (value) api.rateFaqAnswer(message.id, value).catch(() => {})
  }

  if (!open) {
    return (
      <button className="primary bot-launcher" onClick={() => setOpen(true)}>
        Ask a question
      </button>
    )
  }

  return (
    <div className="bot-panel card" role="dialog" aria-label="FAQ assistant">
      <div className="bot-head">
        <div>
          <strong>FAQ assistant</strong>
          <div className="muted">Answers come from this FAQ.</div>
        </div>
        <div className="actions">
          {messages.length > 0 && <button className="small" onClick={() => { setMessages([]); setError(null) }}>New chat</button>}
          <button className="small" aria-label="Close assistant" onClick={() => setOpen(false)}>✕</button>
        </div>
      </div>

      <div className="bot-messages" ref={listRef} aria-live="polite">
        {messages.length === 0 && (
          <div className="bot-empty">
            <p className="muted">Ask about applicants, rules, evaluation, AI drafting or the API. Try:</p>
            {SUGGESTIONS.map((suggestion) => (
              <button key={suggestion} className="bot-suggestion" onClick={() => ask(suggestion)}>{suggestion}</button>
            ))}
          </div>
        )}

        {messages.map((message, i) => (
          <div key={i} className={`bot-message ${message.role}`}>
            {message.content.split('\n\n').map((paragraph, j) => <p key={j}>{paragraph}</p>)}
            {message.sources?.length > 0 && (
              <div className="bot-sources">
                <span className="muted">From the FAQ:</span>
                {message.sources.map((source) => (
                  <button key={source.key} className="link" onClick={() => onSourceClick(source.key)}>{source.question}</button>
                ))}
              </div>
            )}
            {message.role === 'assistant' && message.id && (
              <div className="bot-feedback">
                <button className={message.feedback === 1 ? 'small active' : 'small'} aria-label="Helpful" onClick={() => rate(message, 1)}>👍</button>
                <button className={message.feedback === -1 ? 'small active' : 'small'} aria-label="Not helpful" onClick={() => rate(message, -1)}>👎</button>
              </div>
            )}
          </div>
        ))}

        {asking && <div className="bot-message assistant muted">Searching the FAQ…</div>}
      </div>

      {error && <p className="error bot-error">{error}</p>}

      <form className="bot-input" onSubmit={(e) => { e.preventDefault(); ask(input) }}>
        <input
          ref={inputRef}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Ask a question…"
          aria-label="Your question"
          maxLength={500}
          disabled={asking}
        />
        <button className="primary" type="submit" disabled={asking || !input.trim()}>Ask</button>
      </form>
    </div>
  )
}
