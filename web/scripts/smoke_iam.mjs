// End-to-end IAM smoke test for HardHat.
// 1) anonymous socket  -> register
// 2) poll mailpit, extract verify token
// 3) verify_email      -> success
// 4) login             -> tokens
// 5) authed socket     -> join user:<id>, push "me"
// 6) forgot_password   -> poll mailpit for reset token
// 7) reset_password    -> success
// 8) login with new pw -> tokens

import { Socket } from 'phoenix'

const SOCKET_URL = 'ws://localhost:4000/socket'
const MAILPIT_URL = 'http://localhost:8025'
const EMAIL = `smoke+${Date.now()}@hardhat.local`
const PW1 = 'password-one-1'
const PW2 = 'password-two-2'

function pushAsync(channel, event, payload = {}) {
  return new Promise((resolve, reject) => {
    channel
      .push(event, payload)
      .receive('ok', resolve)
      .receive('error', reject)
      .receive('timeout', () => reject({ message: 'timeout' }))
  })
}

function joinAsync(channel) {
  return new Promise((resolve, reject) => {
    channel
      .join()
      .receive('ok', resolve)
      .receive('error', reject)
      .receive('timeout', () => reject({ message: 'timeout' }))
  })
}

function connectAsync(token) {
  return new Promise((resolve, reject) => {
    const params = token ? { token } : {}
    const sock = new Socket(SOCKET_URL, { params })
    sock.onOpen(() => resolve(sock))
    sock.onError((e) => reject(e))
    sock.connect()
  })
}

async function fetchVerifyTokenFor(emailAddress, contextSnippet) {
  // Poll mailpit until we see a fresh message for this address.
  for (let i = 0; i < 40; i++) {
    const res = await fetch(`${MAILPIT_URL}/api/v1/messages`)
    const data = await res.json()
    const hit = (data.messages || []).find(
      (m) =>
        m.To?.some((to) => to.Address === emailAddress) &&
        m.Subject?.toLowerCase().includes(contextSnippet.toLowerCase()),
    )
    if (hit) {
      const detail = await (await fetch(`${MAILPIT_URL}/api/v1/message/${hit.ID}`)).json()
      const body = detail.Text ?? ''
      const m = body.match(/https?:\/\/[^\s]+\/(verify|reset)\/([A-Za-z0-9_-]+)/)
      if (m) return m[2]
    }
    await new Promise((r) => setTimeout(r, 250))
  }
  throw new Error(`mail not delivered for ${contextSnippet}`)
}

async function main() {
  console.log('[1] anonymous connect + register', EMAIL)
  let sock = await connectAsync()
  let auth = sock.channel('auth:lobby', {})
  await joinAsync(auth)

  const reg = await pushAsync(auth, 'register', { email: EMAIL, password: PW1 })
  console.log('   ok:', reg.message)

  console.log('[2] wait for verify mail')
  const verifyToken = await fetchVerifyTokenFor(EMAIL, 'подтвердите')
  console.log('   verify token:', verifyToken.slice(0, 8) + '…')

  console.log('[3] verify_email')
  const ver = await pushAsync(auth, 'verify_email', { token: verifyToken })
  console.log('   ok:', ver.message)

  console.log('[4] login')
  const login = await pushAsync(auth, 'login', { email: EMAIL, password: PW1 })
  console.log('   tokens received, user.id:', login.user.id)

  console.log('[5] authed reconnect + join user channel')
  sock.disconnect()
  sock = await connectAsync(login.access)
  const userCh = sock.channel(`user:${login.user.id}`, {})
  await joinAsync(userCh)
  const me = await pushAsync(userCh, 'me', {})
  console.log('   me.email:', me.email, 'role:', me.role, 'confirmed_at:', me.confirmed_at)

  console.log('[6] forgot_password')
  // re-join lobby on the authed socket
  auth = sock.channel('auth:lobby', {})
  await joinAsync(auth)
  await pushAsync(auth, 'forgot_password', { email: EMAIL })
  const resetToken = await fetchVerifyTokenFor(EMAIL, 'сброс')
  console.log('   reset token:', resetToken.slice(0, 8) + '…')

  console.log('[7] reset_password')
  await pushAsync(auth, 'reset_password', { token: resetToken, password: PW2 })

  console.log('[8] login with new password')
  const login2 = await pushAsync(auth, 'login', { email: EMAIL, password: PW2 })
  console.log('   ok, new tokens received, same user.id?', login2.user.id === login.user.id)

  sock.disconnect()
  console.log('\nALL GREEN ✔')
  process.exit(0)
}

main().catch((e) => {
  console.error('SMOKE FAILED:', e)
  process.exit(1)
})
