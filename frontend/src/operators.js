export const OPERATOR_LABELS = {
  eq: 'equals',
  neq: 'does not equal',
  gt: '>',
  gte: '≥',
  lt: '<',
  lte: '≤',
  contains: 'contains',
  starts_with: 'starts with',
  in: 'is one of',
  not_in: 'is not one of',
  present: 'is present',
  blank: 'is blank',
}

export const VALUELESS = ['present', 'blank']
export const LIST = ['in', 'not_in']

export function newCondition(schema) {
  const field = schema.fields[0]
  return { field: field.key, operator: field.operators[0], value: '' }
}

export function newGroup(schema) {
  return { combinator: 'all', conditions: [newCondition(schema)] }
}

// Plain-English summary of a condition tree, e.g. "credit score ≥ 700 AND (age < 18 OR …)".
export function describe(node, schema, nested = false) {
  if (node.combinator) {
    const parts = (node.conditions || []).map((c) => describe(c, schema, true))
    const text = parts.join(node.combinator === 'any' ? ' OR ' : ' AND ')
    return nested && parts.length > 1 ? `(${text})` : text
  }
  const label = schema.fields.find((f) => f.key === node.field)?.label.toLowerCase() ?? node.field
  const op = OPERATOR_LABELS[node.operator] ?? node.operator
  if (VALUELESS.includes(node.operator)) return `${label} ${op}`
  const value = Array.isArray(node.value) ? node.value.join(', ') : node.value
  return `${label} ${op} ${value}`
}
