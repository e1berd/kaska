import { defineStore } from 'pinia'
import { ref, watch } from 'vue'
import { Socket, type Channel } from 'phoenix'

// The browser connects directly to the Phoenix API on port 4000 (published to
// the host in docker-compose). VITE_API_WS_URL is injected by the Vite dev
// server from the container environment at request time.
const SOCKET_URL = import.meta.env.VITE_API_WS_URL ?? 'ws://localhost:4000/socket'

/**
 * Push a single channel event and resolve with the server reply.
 * Reject on `error` reply or timeout.
 */
export function pushAsync<T = unknown>(
  channel: Channel,
  event: string,
  payload: object = {},
  timeoutMs = 10_000,
): Promise<T> {
  return new Promise((resolve, reject) => {
    channel
      .push(event, payload, timeoutMs)
      .receive('ok', (resp) => resolve(resp as T))
      .receive('error', (resp) => reject(resp))
      .receive('timeout', () => reject({ message: 'timeout' }))
  })
}

export const useSocketStore = defineStore('socket', () => {
  const socket = ref<Socket | null>(null)
  const channels = ref<Map<string, Channel>>(new Map())
  const connected = ref(false)

  function connect(token?: string | null) {
    disconnect()

    const params = token ? { token } : {}
    const s = new Socket(SOCKET_URL, { params })
    const id = Math.random().toString(36).slice(2, 6)

    s.onOpen(() => {
      console.debug(`[socket:${id}] onOpen — isConnected=${s.isConnected()}`)
      connected.value = true
    })
    s.onClose(() => {
      console.debug(`[socket:${id}] onClose`)
      connected.value = false
    })
    s.onError((err) => {
      console.warn(`[socket:${id}] onError`, err)
    })

    // Assign before connect() so that any code running synchronously after
    // connect() (e.g. ensureConnected() called from a parallel async chain)
    // sees the socket immediately and does NOT create a second one.
    socket.value = s
    s.connect()
  }

  function disconnect() {
    channels.value.forEach((ch) => ch.leave())
    channels.value.clear()
    if (socket.value) {
      socket.value.disconnect()
      socket.value = null
    }
    connected.value = false
  }

  function ensureConnected() {
    if (!socket.value) connect(null)
  }

  /**
   * Resolve once ANY current or future socket is open.
   *
   * Uses Vue's `watch` on `socket` (reactive ref) so it automatically
   * follows socket replacements — e.g. when Vite HMR reloads the module
   * and bootstrap() creates a brand-new Socket instance while we are
   * still waiting for the previous one to open.
   */
  function waitForSocketOpen(timeoutMs = 60_000): Promise<void> {
    return new Promise((resolve, reject) => {
      // Already open — nothing to wait for.
      if (socket.value?.isConnected()) {
        console.debug('[socket] waitForSocketOpen: already connected')
        return resolve()
      }
      console.debug('[socket] waitForSocketOpen: waiting...')

      let done = false
      let openRef: string | null = null
      let stopWatch: (() => void) | null = null

      const timer = setTimeout(() => {
        if (done) return
        done = true
        stopWatch?.()
        if (openRef !== null) socket.value?.off([openRef])
        console.debug('[socket] waitForSocketOpen: rejected via timeout')
        reject({ message: 'socket connect timeout' })
      }, timeoutMs)

      function attachToSocket(s: Socket | null) {
        // Clean up listener on the previous socket instance.
        if (openRef !== null) {
          // s here is the *new* socket; the old ref belongs to the previous one —
          // we can't easily unregister it, but it will be GC'd with the old socket.
          openRef = null
        }
        if (!s) return

        if (s.isConnected()) {
          if (done) return
          done = true
          clearTimeout(timer)
          stopWatch?.()
          console.debug('[socket] waitForSocketOpen: resolved (socket already open on attach)')
          resolve()
          return
        }

        openRef = s.onOpen(() => {
          if (done) return
          done = true
          clearTimeout(timer)
          stopWatch?.()
          s.off([openRef!])
          console.debug('[socket] waitForSocketOpen: resolved via onOpen')
          resolve()
        })
      }

      // Watch for socket replacements (e.g. HMR reload or token refresh).
      stopWatch = watch(socket, (newSocket) => {
        console.debug('[socket] waitForSocketOpen: socket replaced, re-attaching')
        attachToSocket(newSocket)
      })

      // Attach to the current socket immediately.
      attachToSocket(socket.value)
    })
  }

  async function joinChannel<T = unknown>(
    topic: string,
    params: object = {},
  ): Promise<{ channel: Channel; reply: T }> {
    ensureConnected()
    const existing = channels.value.get(topic)
    if (existing && (existing.state === 'joined' || existing.state === 'joining')) {
      // No fresh reply when re-using a channel; surface an empty payload.
      return { channel: existing, reply: {} as T }
    }

    // waitForSocketOpen watches socket (reactive ref) so it will follow any
    // socket replacement that happens while we are waiting (e.g. HMR reload
    // or a token-refresh reconnect in bootstrap).
    await waitForSocketOpen()

    return new Promise((resolve, reject) => {
      const ch = socket.value!.channel(topic, params)
      channels.value.set(topic, ch)
      ch.join()
        .receive('ok', (reply) => resolve({ channel: ch, reply: reply as T }))
        .receive('error', (resp) => {
          channels.value.delete(topic)
          reject(resp)
        })
        .receive('timeout', () => {
          channels.value.delete(topic)
          reject({ message: 'join timeout' })
        })
    })
  }

  function leaveChannel(topic: string) {
    const ch = channels.value.get(topic)
    if (ch) {
      ch.leave()
      channels.value.delete(topic)
    }
  }

  return {
    socket,
    connected,
    connect,
    disconnect,
    joinChannel,
    leaveChannel,
  }
})
