import { generateHTML } from '@tiptap/vue-3'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import type { TiptapDoc } from '../stores/board'

interface JSONNode {
  type?: string
  text?: string
  content?: JSONNode[]
}

const renderExtensions = [
  StarterKit.configure({ heading: { levels: [2, 3] } }),
  Link.configure({
    openOnClick: false,
    autolink: true,
    HTMLAttributes: { rel: 'noopener noreferrer nofollow', target: '_blank' },
  }),
]

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

/**
 * `true` when a doc has no rendered content. We treat a doc as empty if it
 * has no child nodes or no extractable text — good enough for the read-only
 * StarterKit + Link schema used in cards.
 */
export function isDocEmpty(doc: TiptapDoc | null | undefined): boolean {
  if (!doc || !Array.isArray(doc.content) || doc.content.length === 0) return true
  return docPreview(doc, 1).length === 0
}

export function docToHtml(doc: TiptapDoc | null | undefined): string {
  if (!doc) return ''
  try {
    return generateHTML(doc, renderExtensions)
  } catch (err) {
    console.warn('[tiptap] generateHTML failed', err)
    return ''
  }
}

function walk(node: JSONNode, out: string[]) {
  if (node.text) out.push(node.text)
  if (Array.isArray(node.content)) for (const c of node.content) walk(c, out)
}
