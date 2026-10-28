async function request(method, path, body, headers = {}) {
  const res = await fetch(`/api${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...headers },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (res.status === 204) return null
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error((data.errors || [data.error || res.statusText]).join('\n'))
  return data
}

export const api = {
  schema: () => request('GET', '/schema'),

  applicants: ({ q, status } = {}) => {
    const params = new URLSearchParams()
    if (q) params.set('q', q)
    if (status) params.set('status', status)
    return request('GET', `/applicants${params.size ? `?${params}` : ''}`)
  },
  // Creates carry an Idempotency-Key so a retried request can't create a duplicate.
  saveApplicant: (applicant, { idempotencyKey } = {}) =>
    applicant.id
      ? request('PATCH', `/applicants/${applicant.id}`, { applicant })
      : request('POST', '/applicants', { applicant }, idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
  deleteApplicant: (id) => request('DELETE', `/applicants/${id}`),
  evaluateAll: () => request('POST', '/applicants/evaluate'),

  rules: () => request('GET', '/rules'),
  saveRule: (rule) =>
    rule.id ? request('PATCH', `/rules/${rule.id}`, { rule }) : request('POST', '/rules', { rule }),
  deleteRule: (id) => request('DELETE', `/rules/${id}`),
  draftRule: (description) => request('POST', '/rules/draft', { description }),
}
