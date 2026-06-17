#!/usr/bin/env node

import { readFileSync, writeFileSync, existsSync, mkdirSync, renameSync, unlinkSync, rmdirSync, mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { parse as parseYaml } from 'yaml'
import { z } from 'zod'

const BASE = (process.env.KASKA_API_URL ?? 'https://app.kaska.space/api/v1').replace(/\/$/, '')
const CONFIG_PATH = process.env.CLERKS_CONFIG ?? join(process.cwd(), 'clerks.yml')
const STATE_DIR = process.env.STATE_DIR ?? join(process.cwd(), '.clerk-state')

function loadDotEnv(): void {
  const envPath = join(process.cwd(), '.env')
  if (!existsSync(envPath)) return

  const lines = readFileSync(envPath, 'utf-8').split('\n')
  for (const line of lines) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const eqIdx = trimmed.indexOf('=')
    if (eqIdx === -1) continue
    const key = trimmed.slice(0, eqIdx).trim()
    let value = trimmed.slice(eqIdx + 1).trim()
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1)
    }
    if (!process.env[key]) {
      process.env[key] = value
    }
  }
}

const ClerkConfigSchema = z.object({
  model: z.string(),
  system_prompt: z.string().optional(),
})

const TokensSchema = z.record(z.string())
const ClerksSchema = z.record(ClerkConfigSchema)

const ConfigSchema = z.object({
  tokens: TokensSchema.optional(),
  clerks: ClerksSchema,
})

type ClerkConfig = z.infer<typeof ClerkConfigSchema> & { token: string }

interface Config {
  tokens: Record<string, string>
  clerks: Record<string, z.infer<typeof ClerkConfigSchema>>
}

interface Event {
  id: string
  event_type: 'comment_reply' | 'comment_mention' | 'task_comment'
  payload: Record<string, unknown>
  project_id: string
  task_id: string | null
  comment_id: string | null
  inserted_at: string
}

interface Task {
  id: string
  title: string
  body: string
  body_format: string
  column: { id: string; name: string }
  assignee: { id: string; display_name: string } | null
  creator: { id: string; display_name: string } | null
  comments: Comment[]
}

interface Comment {
  id: string
  task_id: string
  parent_id: string | null
  body: string
  author: { id: string; display_name: string; is_agent: boolean } | null
  inserted_at: string
}

interface Project {
  id: string
  slug: string
  name: string
  description: string | null
  agent_instructions: string | null
}

const MAX_PROCESSED = 500
const RETENTION_MS = 7 * 24 * 60 * 60 * 1000

interface State {
  processed: Record<string, string>
  last_error?: { event_id: string; error: string; at: string }
}

async function apiRequest<T>(method: string, path: string, token: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })

  const text = await res.text()
  const data = text ? JSON.parse(text) : null

  if (!res.ok) {
    throw new Error(`Kaska API ${res.status} on ${method} ${path}: ${text}`)
  }

  return data as T
}

function loadConfig(): Record<string, ClerkConfig> {
  loadDotEnv()

  if (!existsSync(CONFIG_PATH)) {
    console.error(`Config not found: ${CONFIG_PATH}`)
    process.exit(1)
  }

  const raw = readFileSync(CONFIG_PATH, 'utf-8')
  const parsed = parseYaml(raw)
  const config = ConfigSchema.parse(parsed)

  const tokens = config.tokens ?? {}
  const result: Record<string, ClerkConfig> = {}

  for (const [name, clerkConfig] of Object.entries(config.clerks)) {
    const envKey = `KASKA_TOKEN_${name.toUpperCase().replace(/[^A-Z0-9]/g, '_')}`
    const token = tokens[name] ?? process.env[envKey] ?? ''

    if (!token) {
      console.warn(`[${name}] No token found in tokens map or env ${envKey}, skipping`)
      continue
    }

    result[name] = { ...clerkConfig, token }
  }

  return result
}

function loadState(clerkName: string): State {
  const stateFile = join(STATE_DIR, `${clerkName}.json`)
  if (existsSync(stateFile)) {
    const raw = JSON.parse(readFileSync(stateFile, 'utf-8'))
    if (Array.isArray(raw.processed)) {
      const converted: Record<string, string> = {}
      for (const id of raw.processed) {
        converted[id] = new Date().toISOString()
      }
      return { processed: converted, last_error: raw.last_error }
    }
    return raw
  }
  return { processed: {} }
}

function saveState(clerkName: string, state: State): void {
  if (!existsSync(STATE_DIR)) {
    mkdirSync(STATE_DIR, { recursive: true })
  }

  const now = Date.now()
  const entries = Object.entries(state.processed)
  const filtered = entries.filter(([, ts]) => now - new Date(ts).getTime() < RETENTION_MS)

  if (filtered.length > MAX_PROCESSED) {
    state.processed = Object.fromEntries(filtered.slice(filtered.length - MAX_PROCESSED))
  } else {
    state.processed = Object.fromEntries(filtered)
  }

  const stateFile = join(STATE_DIR, `${clerkName}.json`)
  const tmpDir = mkdtempSync(join(tmpdir(), 'clerk-state-'))
  const tmpFile = join(tmpDir, `${clerkName}.json`)

  try {
    writeFileSync(tmpFile, JSON.stringify(state, null, 2))
    renameSync(tmpFile, stateFile)
  } finally {
    try { unlinkSync(tmpFile) } catch { /* tmp file may not exist if rename succeeded */ }
    try { rmdirSync(tmpDir) } catch { /* dir may not be empty or already removed */ }
  }
}

function recordError(clerkName: string, state: State, eventId: string, error: unknown): void {
  state.last_error = {
    event_id: eventId,
    error: error instanceof Error ? error.message : String(error),
    at: new Date().toISOString(),
  }
  saveState(clerkName, state)
}

async function fetchProjectBySlug(token: string, projectId: string): Promise<Project | null> {
  const { projects } = await apiRequest<{ projects: { id: string; slug: string }[] }>('GET', '/projects', token)
  const project = projects.find((p) => p.id === projectId)
  if (!project) return null

  const { project: full } = await apiRequest<{ project: Project }>('GET', `/p/${project.slug}`, token)
  return full
}

async function fetchTaskContext(token: string, event: Event): Promise<{ project: Project; task: Task } | null> {
  if (!event.task_id) return null

  const project = await fetchProjectBySlug(token, event.project_id)
  if (!project) return null

  const { task } = await apiRequest<{ task: Task }>(
    'GET',
    `/p/${project.slug}/tasks/${event.task_id}`,
    token,
  )

  return { project, task }
}

function buildContextPrompt(event: Event, project: Project, task: Task): string {
  const lines: string[] = []

  lines.push(`Project: ${project.name} (${project.slug})`)
  if (project.agent_instructions) {
    lines.push(`\nAgent instructions:\n${project.agent_instructions}`)
  }

  lines.push(`\nTask: ${task.title}`)
  lines.push(`Status: ${task.column.name}`)
  if (task.assignee) {
    lines.push(`Assigned to: ${task.assignee.display_name}`)
  }

  if (task.comments.length > 0) {
    lines.push('\nComments thread:')
    for (const comment of task.comments.slice(-10)) {
      const author = comment.author?.display_name ?? 'Unknown'
      const agentTag = comment.author?.is_agent ? ' [agent]' : ''
      lines.push(`  ${author}${agentTag}: ${comment.body}`)
    }
  }

  const eventType = event.event_type
  if (eventType === 'comment_reply') {
    lines.push(`\n[Event: Someone replied to an agent comment]`)
    if (event.payload.reply_by_name) {
      lines.push(`Reply by: ${event.payload.reply_by_name}`)
    }
  } else if (eventType === 'comment_mention') {
    lines.push(`\n[Event: You were @mentioned]`)
    if (event.payload.mentioned_by_name) {
      lines.push(`Mentioned by: ${event.payload.mentioned_by_name}`)
    }
  } else if (eventType === 'task_comment') {
    lines.push(`\n[Event: New comment on your assigned task]`)
    if (event.payload.commented_by_name) {
      lines.push(`Comment by: ${event.payload.commented_by_name}`)
    }
  }

  return lines.join('\n')
}

async function callLLM(
  model: string,
  systemPrompt: string | undefined,
  contextPrompt: string,
): Promise<string> {
  const systemMessage = systemPrompt ?? 'You are a helpful assistant working on a software project. Respond concisely and helpfully. Write your response as a markdown comment. Only respond if the message requires your input — if the conversation does not need your reply, respond with an empty string.'

  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${process.env.OPENAI_API_KEY ?? ''}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: 'system', content: systemMessage },
        { role: 'user', content: contextPrompt },
      ],
    }),
  })

  if (!res.ok) {
    const text = await res.text()
    throw new Error(`LLM API ${res.status}: ${text}`)
  }

  const data = (await res.json()) as { choices: { message: { content: string } }[] }
  return data.choices[0].message.content
}

async function postComment(token: string, projectSlug: string, taskId: string, body: string): Promise<void> {
  await apiRequest('POST', `/p/${projectSlug}/tasks/${taskId}/comments`, token, { body })
}

async function ackEvent(token: string, eventId: string): Promise<void> {
  await apiRequest('POST', `/agent/events/${eventId}/ack`, token)
}

async function processEvent(
  name: string,
  clerk: ClerkConfig,
  event: Event,
  state: State,
): Promise<boolean> {
  if (state.processed[event.id]) {
    return false
  }

  const context = await fetchTaskContext(clerk.token, event)
  if (!context) {
    console.warn(`[${name}] Could not fetch context for event ${event.id}, skipping`)
    return false
  }

  const { project, task } = context
  const prompt = buildContextPrompt(event, project, task)

  try {
    const response = await callLLM(clerk.model, clerk.system_prompt, prompt)

    if (!response || response.trim().length === 0) {
      console.warn(`[${name}] Empty LLM response for event ${event.id}, acking without comment`)
      await ackEvent(clerk.token, event.id)
      state.processed[event.id] = new Date().toISOString()
      saveState(name, state)
      return true
    }

    await postComment(clerk.token, project.slug, task.id, response)
    await ackEvent(clerk.token, event.id)

    state.processed[event.id] = new Date().toISOString()
    state.last_error = undefined
    saveState(name, state)

    console.log(`[${name}] Processed event ${event.id} (${event.event_type})`)
    return true
  } catch (error) {
    console.error(`[${name}] Failed to process event ${event.id}:`, error)
    recordError(name, state, event.id, error)
    return false
  }
}

async function pollAndProcess(
  name: string,
  clerk: ClerkConfig,
  state: State,
): Promise<void> {
  let since: string | undefined
  let backoffMs = 1000
  const maxBackoffMs = 60_000

  while (true) {
    try {
      const { events } = await apiRequest<{ events: Event[]; cursor: string | null }>(
        'GET',
        `/agent/events?wait=true${since ? `&since=${since}` : ''}`,
        clerk.token,
      )

      backoffMs = 1000

      for (const event of events) {
        await processEvent(name, clerk, event, state)
      }

      if (events.length > 0) {
        since = events[events.length - 1].inserted_at
      }
    } catch (error) {
      console.error(`[${name}] Poll error:`, error)
      await sleep(backoffMs)
      backoffMs = Math.min(backoffMs * 2, maxBackoffMs)
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

async function main() {
  const config = loadConfig()

  console.log(`Starting clerk runner with ${Object.keys(config).length} clerks`)

  const runners = Object.entries(config).map(async ([name, clerk]) => {
    const state = loadState(name)
    console.log(`[${name}] Starting (model: ${clerk.model}, ${Object.keys(state.processed).length} previously processed events)`)
    return pollAndProcess(name, clerk, state)
  })

  await Promise.all(runners)
}

main().catch((error) => {
  console.error('Fatal error:', error)
  process.exit(1)
})
