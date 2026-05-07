import { defineStore } from 'pinia'
import { pushAsync, useSocketStore } from './socket'
import { ref } from 'vue'
import type { User } from './auth'
import { Presence } from 'phoenix'
import type { Channel } from 'phoenix'

type PresenceMeta = {
  online_at?: string
}

type PresenceEntry = {
  metas: PresenceMeta[]
}

type PresenceState = Record<string, PresenceEntry>

export const useSysStore = defineStore('sys', () => {
  const presences = ref<PresenceState>({})
  const presenceChannel = ref<Channel | null>(null)
  const listenersAttached = ref(false)

  async function initPresence() {
    if (presenceChannel.value?.state === 'joined' || presenceChannel.value?.state === 'joining') return
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    if (presenceChannel.value !== channel) {
      presenceChannel.value = channel
      listenersAttached.value = false
    }

    if (listenersAttached.value) return

    presenceChannel.value = channel
    channel.on('presence_state', (state: PresenceState) => {
      presences.value = Presence.syncState(presences.value, state)
    })
    channel.on('presence_diff', (diff: { joins: PresenceState; leaves: PresenceState }) => {
      presences.value = Presence.syncDiff(presences.value, diff)
    })
    listenersAttached.value = true
  }

  function isUserOnline(userId: string): boolean {
    const entry = presences.value[userId]
    return !!entry && entry.metas.length > 0
  }

  function userLastOnlineAt(userId: string): Date | null {
    const entry = presences.value[userId]
    if (!entry || entry.metas.length === 0) return null
    const ts = entry.metas
      .map((meta) => Number(meta.online_at))
      .filter((value) => Number.isFinite(value))
      .sort((a, b) => b - a)[0]
    if (!ts) return null
    return new Date(ts * 1000)
  }

  async function getSettings() {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    return pushAsync<{ allow_registration: boolean; first_user_bootstrap: boolean }>(
      channel,
      'get_settings',
      {},
    )
  }

  async function setSettings(input: { allow_registration: boolean }) {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    return pushAsync<{ allow_registration: boolean }>(channel, 'set_settings', input)
  }

  async function getUsers(query?: string) {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    return pushAsync<User[]>(channel, 'get_users', { query })
  }

  async function createInvite(input: { email?: string, expires_in_minutes?: number | null }) {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    return pushAsync<{ token: string, expires_at: string, email: string }>(channel, 'create_invite', input)
  }

  async function changeUserRole(userId: string, role: string) {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    return pushAsync<{ user: User }>(channel, 'change_user_role', { id: userId, role })
  }

  async function confirmUser(userId: string) {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    return pushAsync<{ user: User }>(channel, 'confirm_user', { id: userId })
  }

  async function deleteUser(userId: string) {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    return pushAsync<{ id: string }>(channel, 'delete_user', { id: userId })
  }

  return {
    presences,
    initPresence,
    isUserOnline,
    userLastOnlineAt,
    getSettings,
    setSettings,
    getUsers,
    createInvite,
    changeUserRole,
    confirmUser,
    deleteUser
  }
})
