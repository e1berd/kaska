import { defineStore } from 'pinia'
import { ref, watch } from 'vue'
import { Socket, type Channel } from 'phoenix'

const SOCKET_URL = import.meta.env.VITE_API_WS_URL ?? 'ws://localhost:4000/socket'

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
    s.onOpen(() => { connected.value = true })
    s.onClose(() => { connected.value = false })
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
  }

  function ensureConnected() {
    if (!socket.value) connect(null)
  }

  function waitForSocketOpen(): Promise<void> {
    return new Promise((resolve) => {
      if (socket.value?.isConnected()) return resolve()

      let done = false
      let openRef: string | null = null
      let stopWatch: (() => void) | null = null

      function finish() {
        if (done) return
        done = true
        stopWatch?.()
        resolve()
      }

      function attachToSocket(s: Socket | null) {
        openRef = null
        if (!s) return
        if (s.isConnected()) { finish(); return }

        openRef = s.onOpen(() => {
          s.off([openRef!])
          finish()
        })
      }

      stopWatch = watch(socket, (newSocket) => attachToSocket(newSocket))
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
