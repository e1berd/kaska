import { defineStore } from 'pinia'
import { ref } from 'vue'
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

    s.onOpen(() => {
      connected.value = true
    })
    s.onClose(() => {
      connected.value = false
    })
    s.onError((err) => {
      console.warn('[socket] error', err)
    })

    s.connect()
    socket.value = s
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
   * Resolve once the underlying ws is open. Without this the very first
   * `ch.join()` after a backend restart races the reconnect attempt and
   * times out at the default 10s `Push` timeout, surfacing as
   * `{ message: "join timeout" }` even though the server is reachable a
   * few moments later.
   */
  function waitForSocketOpen(timeoutMs = 8000): Promise<void> {
    return new Promise((resolve, reject) => {
      const s = socket.value
      if (!s) return reject({ message: 'socket not initialized' })
      if (s.isConnected()) return resolve()

      let timer: ReturnType<typeof setTimeout> | null = null
      const ref = s.onOpen(() => {
        if (timer) clearTimeout(timer)
        s.off([ref])
        resolve()
      })
      timer = setTimeout(() => {
        s.off([ref])
        reject({ message: 'socket connect timeout' })
      }, timeoutMs)
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

    if (!socket.value!.isConnected()) {
      await waitForSocketOpen()
    }

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
