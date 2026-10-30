import { navigate } from './router'

// A normal <a> (so open-in-new-tab still works) that navigates in place on a plain click.
export default function Link({ to, ...props }) {
  function onClick(e) {
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    e.preventDefault()
    navigate(to)
  }
  return <a href={to} onClick={onClick} {...props} />
}
