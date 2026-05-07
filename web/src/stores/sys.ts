import { defineStore } from 'pinia'
import { pushAsync, useSocketStore } from './socket'
import type { User } from './auth'

export const useSysStore = defineStore('sys', () => {

  async function getSettings() {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    return pushAsync<{ allow_registration: boolean }>(channel, 'get_settings', {})
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

  async function createInvite(input: { email?: string, expire_in_minutes?: number | null }) {
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
    getSettings,
    setSettings,
    getUsers,
    createInvite,
    changeUserRole,
    confirmUser,
    deleteUser
  }
})
