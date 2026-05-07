import { defineStore } from 'pinia'
import { ref } from 'vue'
import { Socket, type Channel } from 'phoenix'

const SOCKET_URL = import.meta.env.VITE_API_WS_URL ?? 'ws://localhost:4000/socket'

const reconnectAfterMs = (tries: number) => [200, 500, 1000, 2000, 5000][Math.min(tries - 1, 4)]

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

  let openPromise: Promise<void> | null = null
  let openResolve: (() => void) | null = null

  function connect(token?: string | null) {
    disconnect()

    openPromise = new Promise<void>((resolve) => {
      openResolve = resolve
    })

    const s = new Socket(SOCKET_URL, {
      params: token ? { token } : {},
      reconnectAfterMs,
      logger: (kind, msg, data) => console.log(`${kind}: ${msg}`, data)
    })

    s.onOpen(() => {
      connected.value = true
      const resolve = openResolve
      openResolve = null
      openPromise = null
      resolve?.()
    })

    s.onClose(() => {
      connected.value = false
      if (!openResolve) {
        openPromise = new Promise<void>((resolve) => {
          openResolve = resolve
        })
      }
    })

    s.onError((err) => { console.warn('[socket] error', err) })

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
    openResolve = null
    openPromise = null
  }

  function ensureConnected() {
    if (!socket.value) connect(null)
  }

  function waitForSocketOpen(): Promise<void> {
    if (socket.value?.isConnected()) return Promise.resolve()
    if (openPromise) return openPromise
    return new Promise<void>((resolve) => {
      const id = setInterval(() => {
        if (socket.value?.isConnected()) {
          clearInterval(id)
          resolve()
        }
      }, 50)
    })
  }

  async function joinChannel<T = unknown>(
    topic: string,
    params: object = {},
  ): Promise<{ channel: Channel; reply: T }> {
    ensureConnected()
    const existing = channels.value.get(topic)
    if (existing && (existing.state === 'joined' || existing.state === 'joining')) {
      return { channel: existing, reply: {} as T }
    }

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
