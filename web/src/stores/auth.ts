import { defineStore } from 'pinia'
import { computed, ref, watch } from 'vue'
import { pushAsync, useSocketStore } from './socket'
import { uploadToPresignedUrl } from '../utils/upload'

export interface User {
  id: string
  email: string
  role: 'user' | 'admin' | 'superadmin'
  confirmed_at: string | null
  display_name: string | null
  avatar_url: string | null
  last_seen?: string | null
  is_online?: boolean
}

interface TokensReply {
  access: string
  refresh: string
  user: User
}

interface RegisterReply {
  message: string
  user: User
  first_user_bootstrap?: boolean
}

const ACCESS_KEY = 'hardhat.access'
const REFRESH_KEY = 'hardhat.refresh'
const USER_KEY = 'hardhat.user'

function readUser(): User | null {
  const raw = localStorage.getItem(USER_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw) as User
  } catch {
    return null
  }
}

export const useAuthStore = defineStore('auth', () => {
  const access = ref<string | null>(localStorage.getItem(ACCESS_KEY))
  const refresh = ref<string | null>(localStorage.getItem(REFRESH_KEY))
  const user = ref<User | null>(readUser())

  const isAuthed = computed(() => !!access.value && !!user.value)

  watch(access, (v) =>
    v ? localStorage.setItem(ACCESS_KEY, v) : localStorage.removeItem(ACCESS_KEY),
  )
  watch(refresh, (v) =>
    v ? localStorage.setItem(REFRESH_KEY, v) : localStorage.removeItem(REFRESH_KEY),
  )
  watch(
    user,
    (v) =>
      v ? localStorage.setItem(USER_KEY, JSON.stringify(v)) : localStorage.removeItem(USER_KEY),
    { deep: true },
  )

  async function authChannel() {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('auth:lobby')
    return channel
  }

  async function register(email: string, password: string, invite_token?: string) {
    const ch = await authChannel()
    return pushAsync<RegisterReply>(ch, 'register', { email, password, invite_token })
  }

  async function login(email: string, password: string) {
    const sock = useSocketStore()
    const ch = await authChannel()
    const resp = await pushAsync<TokensReply>(ch, 'login', { email, password })
    access.value = resp.access
    refresh.value = resp.refresh
    user.value = resp.user
    sock.connect(resp.access)
    return resp
  }

  async function verifyEmail(token: string) {
    const ch = await authChannel()
    return pushAsync<{ message: string; user: User }>(ch, 'verify_email', { token })
  }

  async function forgotPassword(email: string) {
    const ch = await authChannel()
    return pushAsync<{ message: string }>(ch, 'forgot_password', { email })
  }

  async function resetPassword(token: string, password: string) {
    const ch = await authChannel()
    return pushAsync<{ message: string }>(ch, 'reset_password', { token, password })
  }

  async function refreshTokens() {
    if (!refresh.value) throw new Error('no refresh token')
    const ch = await authChannel()
    const resp = await pushAsync<TokensReply>(ch, 'refresh', { refresh: refresh.value })
    access.value = resp.access
    refresh.value = resp.refresh
    return resp
  }

  async function fetchMe() {
    if (!access.value || !user.value?.id) return null
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel(`user:${user.value.id}`)
    const me = await pushAsync<User>(channel, 'me', {})
    user.value = me
    return me
  }

  async function userChannel() {
    if (!user.value?.id) throw new Error('not authenticated')
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel(`user:${user.value.id}`)
    return channel
  }

  async function updateProfile(input: { display_name: string }) {
    const ch = await userChannel()
    const me = await pushAsync<User>(ch, 'update_profile', input)
    user.value = me
    return me
  }

  async function uploadAvatar(file: File, onProgress?: (f: number) => void) {
    const ch = await userChannel()
    const meta = await pushAsync<{ attachment_id: string; put_url: string }>(
      ch,
      'request_avatar_upload',
      {
        filename: file.name,
        mime: file.type || 'application/octet-stream',
        size: file.size,
      },
    )
    await uploadToPresignedUrl(meta.put_url, file, onProgress)
    const me = await pushAsync<User>(ch, 'confirm_avatar_upload', {
      attachment_id: meta.attachment_id,
    })
    user.value = me
    return me
  }

  function logout() {
    const sock = useSocketStore()
    access.value = null
    refresh.value = null
    user.value = null
    sock.connect(null)
  }

  function bootstrap() {
    const sock = useSocketStore()
    sock.connect(access.value)

    if (access.value && user.value) {
      void fetchMe().catch(async () => {
        if (refresh.value) {
          try {
            await refreshTokens()
            sock.connect(access.value)
            return
          } catch {}
        }
        access.value = null
        refresh.value = null
        user.value = null
      })
    }
  }

  return {
    access,
    refresh,
    user,
    isAuthed,
    bootstrap,
    register,
    login,
    verifyEmail,
    forgotPassword,
    resetPassword,
    refreshTokens,
    fetchMe,
    updateProfile,
    uploadAvatar,
    logout,
  }
})
