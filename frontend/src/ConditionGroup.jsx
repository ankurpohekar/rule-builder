import { LIST, OPERATOR_LABELS, VALUELESS, newCondition, newGroup } from './operators'

// Renders one AND/OR group; nested groups render recursively.
export default function ConditionGroup({ group, schema, onChange, onRemove, depth = 0 }) {
  const updateChild = (index, child) =>
    onChange({ ...group, conditions: group.conditions.map((c, i) => (i === index ? child : c)) })
  const removeChild = (index) => onChange({ ...group, conditions: group.conditions.filter((_, i) => i !== index) })
  const add = (node) => onChange({ ...group, conditions: [...group.conditions, node] })

  return (
    <div className={`group depth-${depth % 3}`}>
      <div className="group-header">
        <span>Match</span>
        <select value={group.combinator} onChange={(e) => onChange({ ...group, combinator: e.target.value })}>
          <option value="all">ALL</option>
          <option value="any">ANY</option>
        </select>
        <span>of the following</span>
        {onRemove && <button type="button" className="danger small" onClick={onRemove}>Remove group</button>}
      </div>

      {group.conditions.map((node, i) =>
        node.combinator ? (
          <ConditionGroup
            key={i}
            group={node}
            schema={schema}
            depth={depth + 1}
            onChange={(child) => updateChild(i, child)}
            onRemove={() => removeChild(i)}
          />
        ) : (
          <ConditionRow key={i} condition={node} schema={schema} onChange={(c) => updateChild(i, c)} onRemove={() => removeChild(i)} />
        ),
      )}

      <div className="group-actions">
        <button type="button" className="small" onClick={() => add(newCondition(schema))}>+ Condition</button>
        <button type="button" className="small" onClick={() => add(newGroup(schema))}>+ Group</button>
      </div>
    </div>
  )
}

function ConditionRow({ condition, schema, onChange, onRemove }) {
  const field = schema.fields.find((f) => f.key === condition.field) ?? schema.fields[0]

  function changeField(key) {
    const next = schema.fields.find((f) => f.key === key)
    onChange({ field: key, operator: next.operators[0], value: '' })
  }

  function changeOperator(operator) {
    // Switching between single and list operators changes the value's shape.
    const wasList = LIST.includes(condition.operator)
    const isList = LIST.includes(operator)
    const value = wasList === isList ? condition.value : isList ? [] : ''
    onChange({ ...condition, operator, value: VALUELESS.includes(operator) ? undefined : value })
  }

  return (
    <div className="condition">
      <select value={condition.field} onChange={(e) => changeField(e.target.value)}>
        {schema.fields.map((f) => <option key={f.key} value={f.key}>{f.label}</option>)}
      </select>
      <select value={condition.operator} onChange={(e) => changeOperator(e.target.value)}>
        {field.operators.map((op) => <option key={op} value={op}>{OPERATOR_LABELS[op]}</option>)}
      </select>
      <ValueInput field={field} condition={condition} onChange={(value) => onChange({ ...condition, value })} />
      <button type="button" className="danger small" onClick={onRemove} aria-label="Remove condition">✕</button>
    </div>
  )
}

function ValueInput({ field, condition, onChange }) {
  const { operator, value } = condition
  if (VALUELESS.includes(operator)) return <span className="value-placeholder" />

  if (LIST.includes(operator)) {
    const list = Array.isArray(value) ? value : []
    if (field.type === 'enum') {
      return (
        <div className="checks">
          {field.options.map((o) => (
            <label key={o}>
              <input
                type="checkbox"
                checked={list.includes(o)}
                onChange={(e) => onChange(e.target.checked ? [...list, o] : list.filter((v) => v !== o))}
              />
              {o.replace('_', ' ')}
            </label>
          ))}
        </div>
      )
    }
    return (
      <input
        placeholder="comma, separated, values"
        value={list.join(', ')}
        onChange={(e) => onChange(e.target.value.split(',').map((v) => v.trim()).filter(Boolean))}
      />
    )
  }

  if (field.type === 'enum') {
    return (
      <select value={value ?? ''} onChange={(e) => onChange(e.target.value)}>
        <option value="">Choose…</option>
        {field.options.map((o) => <option key={o} value={o}>{o.replace('_', ' ')}</option>)}
      </select>
    )
  }

  if (field.type === 'number') {
    return (
      <input
        type="number"
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value === '' ? '' : Number(e.target.value))}
      />
    )
  }

  return <input value={value ?? ''} onChange={(e) => onChange(e.target.value)} />
}
