// End-to-end board smoke test for Kaska.
// 1) anonymous guest joins projects:lobby (must succeed without token)
// 2) registered+verified user logs in and creates a project
// 3) guest sees project_created broadcast
// 4) authed user joins board and creates a column + task
// 5) authed user moves task into another column
// 6) guest sees task_created and task_moved broadcasts on board:<id>
//
// Re-uses the IAM smoke flow's mailpit polling for verification.

import { Socket } from 'phoenix'

const SOCKET_URL = 'ws://localhost:4000/socket'
const MAILPIT_URL = 'http://localhost:8025'
const EMAIL = `board+${Date.now()}@kaska.local`
const PW = 'password-one-1'
const SLUG = `smoke-${Date.now()}`

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

async function fetchTokenFor(emailAddress, contextSnippet) {
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
  throw new Error(`mail not delivered: ${contextSnippet}`)
}

function expectEvent(channel, event, predicate, timeoutMs = 4000) {
  return new Promise((resolve, reject) => {
    const ref = channel.on(event, (payload) => {
      if (!predicate || predicate(payload)) {
        channel.off(event, ref)
        resolve(payload)
      }
    })
    setTimeout(() => {
      channel.off(event, ref)
      reject(new Error(`event '${event}' not received in ${timeoutMs}ms`))
    }, timeoutMs)
  })
}

async function main() {
  console.log('[1] guest connects and joins projects:lobby')
  const guestSock = await connectAsync()
  const guestProjects = guestSock.channel('projects:lobby', {})
  await joinAsync(guestProjects)

  console.log('[2] register + verify + login')
  const userSock = await connectAsync()
  const auth = userSock.channel('auth:lobby', {})
  await joinAsync(auth)
  await pushAsync(auth, 'register', { email: EMAIL, password: PW })
  const verify = await fetchTokenFor(EMAIL, 'подтвердите')
  await pushAsync(auth, 'verify_email', { token: verify })
  const login = await pushAsync(auth, 'login', { email: EMAIL, password: PW })
  console.log('   user.id', login.user.id)

  userSock.disconnect()
  const authedSock = await connectAsync(login.access)
  const authedProjects = authedSock.channel('projects:lobby', {})
  await joinAsync(authedProjects)

  console.log('[3] guest expects project_created broadcast')
  const projectCreated = expectEvent(
    guestProjects,
    'project_created',
    (p) => p.slug === SLUG,
    5000,
  )
  const project = await pushAsync(authedProjects, 'create_project', {
    slug: SLUG,
    name: 'Smoke Project',
    description: 'created by smoke_board.mjs',
  })
  console.log('   project.id', project.id)
  await projectCreated
  console.log('   guest saw project_created ✓')

  console.log('[4] both clients join board:' + project.id)
  const guestBoard = guestSock.channel(`board:${project.id}`, {})
  const guestSnap = await joinAsync(guestBoard)
  const authedBoard = authedSock.channel(`board:${project.id}`, {})
  const authedSnap = await joinAsync(authedBoard)
  if (authedSnap.columns.length !== 3) {
    throw new Error(`expected 3 default columns, got ${authedSnap.columns.length}`)
  }
  console.log('   default columns:', authedSnap.columns.map((c) => c.name).join(', '))
  console.log('   guest sees columns:', guestSnap.columns.length)

  console.log('[5] create column + task; guest sees broadcasts')
  const colCreated = expectEvent(guestBoard, 'column_created', (c) => c.name === 'Backlog', 5000)
  const newColumn = await pushAsync(authedBoard, 'create_column', { name: 'Backlog' })
  await colCreated
  console.log('   column_created ✓ id', newColumn.id)

  const todoColumn = authedSnap.columns.find((c) => c.name === 'Todo')
  const taskCreated = expectEvent(
    guestBoard,
    'task_created',
    (t) => t.title === 'first task',
    5000,
  )
  const task = await pushAsync(authedBoard, 'create_task', {
    column_id: todoColumn.id,
    title: 'first task',
    description: 'hello',
  })
  await taskCreated
  console.log('   task_created ✓ id', task.id, 'rank', task.rank)

  console.log('[6] move task to Backlog; guest sees task_moved with new column_id')
  const taskMoved = expectEvent(
    guestBoard,
    'task_moved',
    (t) => t.id === task.id && t.column_id === newColumn.id,
    5000,
  )
  const moved = await pushAsync(authedBoard, 'move_task', {
    id: task.id,
    column_id: newColumn.id,
    before_id: null,
    after_id: null,
  })
  if (moved.column_id !== newColumn.id) throw new Error('move_task did not return new column')
  await taskMoved
  console.log('   task_moved ✓ new rank', moved.rank)

  console.log('[7] guest must NOT be able to mutate (no token)')
  let denied = false
  try {
    await pushAsync(guestBoard, 'create_task', {
      column_id: todoColumn.id,
      title: 'should fail',
    })
  } catch (e) {
    denied = true
    if (e.code !== 'unauthorized') {
      throw new Error('expected unauthorized error, got: ' + JSON.stringify(e))
    }
  }
  if (!denied) throw new Error('guest mutation was not denied!')
  console.log('   guest mutation correctly denied ✓')

  guestSock.disconnect()
  authedSock.disconnect()
  console.log('\nALL GREEN ✔')
  process.exit(0)
}

main().catch((e) => {
  console.error('SMOKE FAILED:', e)
  process.exit(1)
})
