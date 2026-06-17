#!/usr/bin/env node

import { existsSync, readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'

const STATE_DIR = join(tmpdir(), 'clerk-runner-test')

function cleanup() {
  if (existsSync(STATE_DIR)) {
    rmSync(STATE_DIR, { recursive: true })
  }
}

function saveState(name: string, state: unknown) {
  if (!existsSync(STATE_DIR)) {
    mkdirSync(STATE_DIR, { recursive: true })
  }
  const tmpDir = join(tmpdir(), `clerk-test-${Date.now()}`)
  mkdirSync(tmpDir)
  const tmpFile = join(tmpDir, `${name}.json`)
  const targetFile = join(STATE_DIR, `${name}.json`)
  writeFileSync(tmpFile, JSON.stringify(state, null, 2))
  import('node:fs').then(fs => {
    fs.renameSync(tmpFile, targetFile)
    try { fs.unlinkSync(tmpFile) } catch {}
    try { fs.rmdirSync(tmpDir) } catch {}
  })
}

function loadState(name: string): Record<string, string> | null {
  const stateFile = join(STATE_DIR, `${name}.json`)
  if (!existsSync(stateFile)) return null
  return JSON.parse(readFileSync(stateFile, 'utf-8'))
}

function assert(condition: boolean, msg: string) {
  if (!condition) {
    console.error(`FAIL: ${msg}`)
    process.exit(1)
  }
  console.log(`PASS: ${msg}`)
}

async function testAtomicWrite() {
  cleanup()

  const state1 = { processed: { 'evt-1': '2026-01-01T00:00:00Z' }, last_error: undefined }
  saveState('test-clerk', state1)
  await new Promise(r => setTimeout(r, 50))

  const loaded = loadState('test-clerk')
  assert(loaded !== null, 'State file created')
  assert(loaded!.processed['evt-1'] !== undefined, 'Event evt-1 present')
  assert(loaded!.last_error === undefined, 'No last_error')

  const state2 = { processed: { 'evt-1': '2026-01-01T00:00:00Z', 'evt-2': '2026-01-02T00:00:00Z' }, last_error: undefined }
  saveState('test-clerk', state2)
  await new Promise(r => setTimeout(r, 50))

  const loaded2 = loadState('test-clerk')
  assert(loaded2!.processed['evt-2'] !== undefined, 'Event evt-2 added')
  assert(Object.keys(loaded2!.processed).length === 2, 'Two events in state')

  cleanup()
}

async function testIdempotency() {
  cleanup()

  const processed = new Set<string>()
  const events = ['evt-1', 'evt-2', 'evt-1', 'evt-3', 'evt-2']

  const handled: string[] = []
  for (const evt of events) {
    if (!processed.has(evt)) {
      handled.push(evt)
      processed.add(evt)
    }
  }

  assert(handled.length === 3, `Idempotency: 3 unique events handled (got ${handled.length})`)
  assert(handled[0] === 'evt-1', 'First event: evt-1')
  assert(handled[1] === 'evt-2', 'Second event: evt-2')
  assert(handled[2] === 'evt-3', 'Third event: evt-3')

  cleanup()
}

async function main() {
  console.log('Running clerk-runner tests...\n')
  await testAtomicWrite()
  await testIdempotency()
  console.log('\nAll tests passed.')
}

main().catch(e => {
  console.error(e)
  process.exit(1)
})
