async function send(method, path, body, headers = {}) {
  const res = await fetch(`/api${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...headers },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (res.status === 204) return { res, data: null }
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error((data.errors || [data.error || res.statusText]).join('\n'))
  return { res, data }
}

async function request(...args) {
  return (await send(...args)).data
}

// The cursor for the next page, from a `Link: <...?after=CURSOR>; rel="next"` header.
function nextCursor(res) {
  const url = res.headers.get('Link')?.match(/<([^>]+)>;\s*rel="next"/)?.[1]
  return url ? new URL(url, window.location.origin).searchParams.get('after') : null
}

export const api = {
  schema: () => request('GET', '/schema'),

  // One page of applicants: { applicants, nextCursor }. Pass nextCursor as `after` for the next page.
  applicants: async ({ q, status, after } = {}) => {
    const params = new URLSearchParams()
    if (q) params.set('q', q)
    if (status) params.set('status', status)
    if (after) params.set('after', after)
    const { res, data } = await send('GET', `/applicants${params.size ? `?${params}` : ''}`)
    return { applicants: data, nextCursor: nextCursor(res) }
  },
  // Creates carry an Idempotency-Key so a retried request can't create a duplicate.
  saveApplicant: (applicant, { idempotencyKey } = {}) =>
    applicant.id
      ? request('PATCH', `/applicants/${applicant.id}`, { applicant })
      : request('POST', '/applicants', { applicant }, idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
  deleteApplicant: (id) => request('DELETE', `/applicants/${id}`),
  draftApplicant: (text) => request('POST', '/applicants/draft', { text }),
  evaluateAll: () => request('POST', '/applicants/evaluate'),

  faqs: () => request('GET', '/faqs'),
  askFaq: (question, history) => request('POST', '/faq/ask', { question, history }),
  rateFaqAnswer: (id, feedback) => request('PATCH', `/faq/questions/${id}`, { feedback }),

  rules: () => request('GET', '/rules'),
  saveRule: (rule) =>
    rule.id ? request('PATCH', `/rules/${rule.id}`, { rule }) : request('POST', '/rules', { rule }),
  deleteRule: (id) => request('DELETE', `/rules/${id}`),
  draftRule: (description) => request('POST', '/rules/draft', { description }),
}
