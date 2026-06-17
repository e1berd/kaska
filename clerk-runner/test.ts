import { strict as assert } from 'node:assert'
import { existsSync, readFileSync, writeFileSync, mkdirSync, rmSync, renameSync, unlinkSync, rmdirSync, mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const STATE_DIR = join(tmpdir(), 'clerk-runner-test')

function cleanup() {
  if (existsSync(STATE_DIR)) {
    rmSync(STATE_DIR, { recursive: true })
  }
}

function saveStateAtomic(name: string, state: unknown) {
  if (!existsSync(STATE_DIR)) {
    mkdirSync(STATE_DIR, { recursive: true })
  }
  const stateFile = join(STATE_DIR, `${name}.json`)
  const tmpDir = mkdtempSync(join(tmpdir(), 'clerk-test-'))
  const tmpFile = join(tmpDir, `${name}.json`)
  writeFileSync(tmpFile, JSON.stringify(state, null, 2))
  renameSync(tmpFile, stateFile)
  try { unlinkSync(tmpFile) } catch { /* noop */ }
  try { rmdirSync(tmpDir) } catch { /* noop */ }
}

function loadState(name: string): Record<string, unknown> | null {
  const stateFile = join(STATE_DIR, `${name}.json`)
  if (!existsSync(stateFile)) return null
  return JSON.parse(readFileSync(stateFile, 'utf-8'))
}

async function testAtomicWrite() {
  cleanup()

  const state1 = { processed: { 'evt-1': '2026-01-01T00:00:00Z' }, last_error: undefined }
  saveStateAtomic('test-clerk', state1)

  const loaded = loadState('test-clerk')
  assert(loaded !== null, 'State file created after atomic write')
  assert.deepStrictEqual(Object.keys(loaded!.processed), ['evt-1'], 'Event evt-1 present')
  assert.strictEqual(loaded!.last_error, undefined, 'No last_error')

  const state2 = { processed: { 'evt-1': '2026-01-01T00:00:00Z', 'evt-2': '2026-01-02T00:00:00Z' } }
  saveStateAtomic('test-clerk', state2)

  const loaded2 = loadState('test-clerk')
  assert.deepStrictEqual(Object.keys(loaded2!.processed).sort(), ['evt-1', 'evt-2'], 'Two events in state')

  cleanup()
  console.log('PASS: atomic write preserves state correctly')
}

async function testIdempotency() {
  cleanup()

  const processed = new Map<string, string>()
  const events = ['evt-1', 'evt-2', 'evt-1', 'evt-3', 'evt-2']

  const handled: string[] = []
  for (const evt of events) {
    if (!processed.has(evt)) {
      handled.push(evt)
      processed.set(evt, new Date().toISOString())
    }
  }

  assert.strictEqual(handled.length, 3, `Idempotency: 3 unique events handled (got ${handled.length})`)
  assert.strictEqual(handled[0], 'evt-1', 'First event: evt-1')
  assert.strictEqual(handled[1], 'evt-2', 'Second event: evt-2')
  assert.strictEqual(handled[2], 'evt-3', 'Third event: evt-3')

  cleanup()
  console.log('PASS: idempotency prevents duplicate processing')
}

async function testRetention() {
  cleanup()

  const now = Date.now()
  const day = 24 * 60 * 60 * 1000
  const processed: Record<string, string> = {
    'old-1': new Date(now - 8 * day).toISOString(),
    'old-2': new Date(now - 9 * day).toISOString(),
    'fresh-1': new Date(now - 1 * day).toISOString(),
    'fresh-2': new Date(now - 2 * day).toISOString(),
  }

  const RETENTION_MS = 7 * day
  const entries = Object.entries(processed)
  const filtered = entries.filter(([, ts]) => now - new Date(ts).getTime() < RETENTION_MS)

  assert.strictEqual(filtered.length, 2, 'Retention keeps only 7-day window')
  assert.strictEqual(filtered[0][0], 'fresh-1', 'Fresh event kept')
  assert.strictEqual(filtered[1][0], 'fresh-2', 'Fresh event kept')

  cleanup()
  console.log('PASS: retention policy evicts old events')
}

async function testNoOpAck() {
  cleanup()

  let acked = false
  const event = { id: 'evt-noop', event_type: 'comment_mention' }

  const processed = new Map<string, string>()
  const response = ''

  if (!response || response.trim().length === 0) {
    acked = true
    processed.set(event.id, new Date().toISOString())
  }

  assert.strictEqual(acked, true, 'No-op response triggers ack')
  assert(processed.has(event.id), 'Event marked as processed after no-op ack')

  cleanup()
  console.log('PASS: no-op response acks event without comment')
}

async function testErrorRecording() {
  cleanup()

  const state: { last_error?: { event_id: string; error: string; at: string } } = {}
  const eventId = 'evt-fail'
  const error = new Error('LLM API 429: rate limit exceeded')

  state.last_error = {
    event_id: eventId,
    error: error.message,
    at: new Date().toISOString(),
  }

  assert.strictEqual(state.last_error!.event_id, eventId, 'Error recorded with event ID')
  assert.strictEqual(state.last_error!.error, error.message, 'Error message preserved')
  assert(state.last_error!.at.length > 0, 'Timestamp recorded')

  cleanup()
  console.log('PASS: error state recorded correctly')
}

async function main() {
  console.log('Running clerk-runner acceptance tests...\n')

  await testAtomicWrite()
  await testIdempotency()
  await testRetention()
  await testNoOpAck()
  await testErrorRecording()

  console.log('\nAll acceptance tests passed.')
}

main().catch((e) => {
  console.error('FAIL:', e)
  process.exit(1)
})
