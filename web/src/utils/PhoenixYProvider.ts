import * as Y from 'yjs'
import {
  Awareness,
  applyAwarenessUpdate,
  encodeAwarenessUpdate,
  removeAwarenessStates,
} from 'y-protocols/awareness'
import type { Channel } from 'phoenix'

const REMOTE_ORIGIN = '__phoenix_y_remote__'
const SETTLE_DELAY_MS = 1_500

type Options = {
  initialStateB64?: string
  onLocalSettle?: () => void
}

export class PhoenixYProvider {
  readonly doc: Y.Doc
  readonly awareness: Awareness
  readonly channel: Channel

  private destroyed = false
  private settleTimer: ReturnType<typeof setTimeout> | null = null
  private readonly onLocalSettle: (() => void) | null

  constructor(channel: Channel, doc: Y.Doc, awareness: Awareness, opts: Options = {}) {
    this.channel = channel
    this.doc = doc
    this.awareness = awareness
    this.onLocalSettle = opts.onLocalSettle ?? null

    if (opts.initialStateB64) {
      const bytes = base64ToUint8(opts.initialStateB64)
      if (bytes.byteLength > 0) {
        Y.applyUpdate(doc, bytes, this)
      }
    }

    doc.on('update', this.handleDocUpdate)
    awareness.on('update', this.handleAwarenessUpdate)
    channel.on('update', this.handleRemoteUpdate)
    channel.on('awareness', this.handleRemoteAwareness)
  }

  private handleDocUpdate = (update: Uint8Array, origin: unknown) => {
    if (this.destroyed) return
    if (origin === this) return
    this.channel.push('update', { u: uint8ToBase64(update) })
    this.scheduleSettle()
  }

  private handleRemoteUpdate = (payload: { u?: string }) => {
    if (!payload?.u) return
    const bytes = base64ToUint8(payload.u)
    Y.applyUpdate(this.doc, bytes, this)
  }

  private handleAwarenessUpdate = (
    {
      added,
      updated,
      removed,
    }: { added: number[]; updated: number[]; removed: number[] },
    origin: unknown,
  ) => {
    if (this.destroyed) return
    if (origin === REMOTE_ORIGIN) return
    const changed = added.concat(updated, removed)
    if (changed.length === 0) return
    const update = encodeAwarenessUpdate(this.awareness, changed)
    this.channel.push('awareness', { s: uint8ToBase64(update) })
  }

  private handleRemoteAwareness = (payload: { s?: string }) => {
    if (!payload?.s) return
    const bytes = base64ToUint8(payload.s)
    applyAwarenessUpdate(this.awareness, bytes, REMOTE_ORIGIN)
  }

  private scheduleSettle() {
    if (!this.onLocalSettle) return
    if (this.settleTimer) clearTimeout(this.settleTimer)
    this.settleTimer = setTimeout(() => {
      this.settleTimer = null
      if (this.destroyed) return
      try {
        this.onLocalSettle?.()
      } catch (err) {
        console.warn('[phoenix-y] onLocalSettle threw', err)
      }
    }, SETTLE_DELAY_MS)
  }

  flush() {
    if (this.destroyed) return
    if (!this.settleTimer) return
    clearTimeout(this.settleTimer)
    this.settleTimer = null
    try {
      this.onLocalSettle?.()
    } catch (err) {
      console.warn('[phoenix-y] onLocalSettle threw', err)
    }
  }

  destroy() {
    if (this.destroyed) return

    this.flush()
    this.destroyed = true

    removeAwarenessStates(this.awareness, [this.doc.clientID], 'local')

    this.doc.off('update', this.handleDocUpdate)
    this.awareness.off('update', this.handleAwarenessUpdate)
    this.channel.off('update', this.handleRemoteUpdate)
    this.channel.off('awareness', this.handleRemoteAwareness)
  }
}

function uint8ToBase64(bytes: Uint8Array): string {
  let binary = ''
  const len = bytes.byteLength
  for (let i = 0; i < len; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary)
}

function base64ToUint8(b64: string): Uint8Array {
  const binary = atob(b64)
  const len = binary.length
  const bytes = new Uint8Array(len)
  for (let i = 0; i < len; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}
