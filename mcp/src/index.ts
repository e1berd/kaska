#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { z } from 'zod'

const BASE = (process.env.KASKA_API_URL ?? 'https://app.kaska.space/api/v1').replace(/\/$/, '')
const TOKEN = process.env.KASKA_TOKEN ?? ''

if (!TOKEN) {
  console.error('KASKA_TOKEN is required: a Kaska personal access token (kaska_pat_…).')
  process.exit(1)
}

type Json = Record<string, unknown> | unknown[] | null

async function request(method: string, path: string, body?: unknown): Promise<Json> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: {
      authorization: `Bearer ${TOKEN}`,
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })

  const text = await res.text()
  const data = text ? (JSON.parse(text) as Json) : null

  if (!res.ok) {
    throw new Error(`Kaska API ${res.status} on ${method} ${path}: ${text}`)
  }

  return data
}

function result(data: Json) {
  return { content: [{ type: 'text' as const, text: JSON.stringify(data, null, 2) }] }
}

const slug = z.string().describe('Project slug, e.g. "kaska".')
const taskId = z.string().describe('Task id (UUID).')
const format = z.enum(['md', 'json']).optional().describe('Task body format; defaults to md.')

const server = new McpServer({ name: 'kaska', version: '1.0.0' })

server.registerTool(
  'list_projects',
  {
    title: 'List projects',
    description: 'List the projects this token can access. Start here to discover a project slug.',
    inputSchema: {},
  },
  async () => result(await request('GET', '/projects')),
)

server.registerTool(
  'get_project',
  {
    title: 'Get project overview',
    description:
      'Project overview: agent_instructions plus columns with descriptions. Read the column ' +
      'descriptions to learn where to move a task as its state changes (e.g. Todo → In Progress).',
    inputSchema: { project_slug: slug },
  },
  async ({ project_slug }) => result(await request('GET', `/p/${project_slug}`)),
)

server.registerTool(
  'list_tasks',
  {
    title: 'List tasks',
    description:
      'List every task in a project with body, type, assignee, comments and attachments.',
    inputSchema: { project_slug: slug, task_format: format },
  },
  async ({ project_slug, task_format }) =>
    result(await request('GET', `/p/${project_slug}/tasks?task_format=${task_format ?? 'md'}`)),
)

server.registerTool(
  'get_task',
  {
    title: 'Get task',
    description: 'Fetch a single task by id.',
    inputSchema: { project_slug: slug, task_id: taskId, task_format: format },
  },
  async ({ project_slug, task_id, task_format }) =>
    result(
      await request('GET', `/p/${project_slug}/tasks/${task_id}?task_format=${task_format ?? 'md'}`),
    ),
)

server.registerTool(
  'update_task',
  {
    title: 'Update task',
    description: 'Update a task. Provide only the fields to change. body is Markdown.',
    inputSchema: {
      project_slug: slug,
      task_id: taskId,
      title: z.string().optional(),
      body: z.string().optional().describe('Markdown body.'),
      assignee_id: z.string().nullable().optional(),
      task_type_id: z.string().nullable().optional(),
      start_date: z.string().nullable().optional(),
      end_date: z.string().nullable().optional(),
    },
  },
  async ({ project_slug, task_id, ...fields }) =>
    result(await request('PATCH', `/p/${project_slug}/tasks/${task_id}`, fields)),
)

server.registerTool(
  'move_task',
  {
    title: 'Move task',
    description:
      'Move a task into a column (workflow stage). Without before_id/after_id it is appended ' +
      'to the end of the target column.',
    inputSchema: {
      project_slug: slug,
      task_id: taskId,
      column_id: z.string().describe('Target column id.'),
      before_id: z.string().optional(),
      after_id: z.string().optional(),
    },
  },
  async ({ project_slug, task_id, ...body }) =>
    result(await request('POST', `/p/${project_slug}/tasks/${task_id}/move`, body)),
)

server.registerTool(
  'list_comments',
  {
    title: 'List comments',
    description: "Read a task's comment thread.",
    inputSchema: { project_slug: slug, task_id: taskId },
  },
  async ({ project_slug, task_id }) =>
    result(await request('GET', `/p/${project_slug}/tasks/${task_id}/comments`)),
)

server.registerTool(
  'create_comment',
  {
    title: 'Create comment',
    description: 'Post a comment on a task — ask a question or report progress.',
    inputSchema: { project_slug: slug, task_id: taskId, body: z.string().describe('Comment text.') },
  },
  async ({ project_slug, task_id, body }) =>
    result(await request('POST', `/p/${project_slug}/tasks/${task_id}/comments`, { body })),
)

server.registerTool(
  'list_task_types',
  {
    title: 'List task types',
    description: "List the project's task types.",
    inputSchema: { project_slug: slug },
  },
  async ({ project_slug }) => result(await request('GET', `/p/${project_slug}/task_types`)),
)

server.registerTool(
  'list_members',
  {
    title: 'List members',
    description: "List the project's members (possible assignees).",
    inputSchema: { project_slug: slug },
  },
  async ({ project_slug }) => result(await request('GET', `/p/${project_slug}/members`)),
)

server.registerTool(
  'wait_for_reply',
  {
    title: 'Wait for reply',
    description:
      'Long-poll for events addressed to this agent: comment replies, @mentions, ' +
      'and new comments on assigned tasks. Returns pending events with a cursor. ' +
      'Pass the cursor as "since" on the next call to resume from where you left off. ' +
      'Events must be acknowledged via acknowledge_event.',
    inputSchema: {
      since: z.string().optional().describe('ISO-8601 cursor from a previous response.'),
      wait: z.boolean().optional().describe('Whether to long-poll (default true).'),
    },
  },
  async ({ since, wait }) => {
    const params = new URLSearchParams()
    if (since) params.set('since', since)
    if (wait === false) params.set('wait', 'false')
    const qs = params.toString()
    return result(await request('GET', `/agent/events${qs ? '?' + qs : ''}`))
  },
)

server.registerTool(
  'acknowledge_event',
  {
    title: 'Acknowledge event',
    description:
      'Acknowledge delivery of events up to and including the given event id. ' +
      'All events with inserted_at <= the target event will be marked as delivered.',
    inputSchema: {
      event_id: z.string().describe('The event id to acknowledge up to.'),
    },
  },
  async ({ event_id }) => result(await request('POST', `/agent/events/${event_id}/ack`)),
)

const transport = new StdioServerTransport()
await server.connect(transport)
