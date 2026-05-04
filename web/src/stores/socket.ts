import { defineStore } from 'pinia'
import { ref } from 'vue'
import { Socket, type Channel } from 'phoenix'

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

  function joinChannel<T = unknown>(
    topic: string,
    params: object = {},
  ): Promise<{ channel: Channel; reply: T }> {
    ensureConnected()
    const existing = channels.value.get(topic)
    if (existing && (existing.state === 'joined' || existing.state === 'joining')) {
      // No fresh reply when re-using a channel; surface an empty payload.
      return Promise.resolve({ channel: existing, reply: {} as T })
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
