import type { TiptapDoc } from '../stores/board'

interface JSONNode {
  type?: string
  text?: string
  content?: JSONNode[]
}

/**
 * Returns a flat plain-text snippet of a tiptap doc, useful for card
 * previews and search. Joins block-level text with single spaces; trims
 * to `max` characters with an ellipsis if needed.
 */
export function docPreview(doc: TiptapDoc | null | undefined, max = 160): string {
  if (!doc) return ''
  const parts: string[] = []
  walk(doc as JSONNode, parts)
  let text = parts.join(' ').replace(/\s+/g, ' ').trim()
  if (text.length > max) text = text.slice(0, max - 1).trimEnd() + '…'
  return text
}

function walk(node: JSONNode, out: string[]) {
  if (node.text) out.push(node.text)
  if (Array.isArray(node.content)) for (const c of node.content) walk(c, out)
}
