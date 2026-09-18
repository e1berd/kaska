import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { Presence, type Channel } from 'phoenix'
import { pushAsync, useSocketStore } from '@/stores/socket'
import type { Project } from '@/stores/projects'
import type { User } from '@/stores/auth'
import { uploadToPresignedUrl } from '@/utils/upload'

export interface Column {
  id: string
  project_id: string
  name: string
  rank: string
  description?: string | null
  color: string
}

import type { JSONContent } from '@tiptap/vue-3'
export type TiptapDoc = JSONContent & { type: 'doc' }

export interface Task {
  id: string
  project_id: string
  column_id: string
  title: string
  body_doc: TiptapDoc
  rank: string
  creator_id: string | null
  updated_by_id: string | null
  assignee_ids: string[]
  task_type_id: string | null
  start_date?: string
  end_date?: string
  inserted_at?: string
  updated_at?: string
}

export interface TaskType {
  id: string
  project_id: string
  name: string
  description?: string | null
  color: string
  text_color: string
}

export interface Attachment {
  id: string
  task_id: string
  comment_id?: string
  kind: 'image' | 'video' | 'file'
  filename: string
  mime: string
  size: number
  url: string | null
  creator_id: string | null
  inserted_at?: string
}

export interface TaskDeletedEvent {
  id: string
  title?: string
  deleted_by_id?: string
  deleted_by_display_name?: string | null
  deleted_by_email?: string | null
}

export interface TaskComment {
  id: string
  task_id: string
  project_id: string
  parent_id: string | null
  body: string
  body_doc: TiptapDoc | null
  author_id: string | null
  guest_name: string | null
  author_display_name: string | null
  author_email: string | null
  author_avatar_url: string | null
  author_role: User['role'] | null
  attachments: Attachment[]
  inserted_at?: string
  updated_at?: string
}

export interface BoardSettings {
  allow_guest_comments: boolean
}

export interface ProjectMember {
  user_id: string
  role: 'owner' | 'member'
  email: string | null
  display_name: string | null
  avatar_url: string | null
  is_agent?: boolean | null
  inserted_at?: string
}

export type AgentRunStatus = 'pending' | 'running' | 'succeeded' | 'failed' | 'stopped' | 'timed_out'

export interface AgentRun {
  id: string
  agent_id: string
  task_id: string | null
  project_id: string
  requested_by_id: string | null
  trigger: string
  status: AgentRunStatus
  started_at: string | null
  finished_at: string | null
  exit_code: number | null
  exit_reason: string | null
  inserted_at: string
}

export interface BoardAgentInfo {
  provider_preset: string | null
  model: string | null
  ready: boolean
}

export interface BoardUser extends User {
  is_agent?: boolean
  agent?: BoardAgentInfo | null
}

export const ACTIVE_RUN_STATUSES: AgentRunStatus[] = ['pending', 'running']

export function isRunActive(run: AgentRun | null | undefined): boolean {
  return !!run && ACTIVE_RUN_STATUSES.includes(run.status)
}

export type TaskHistoryEventKind = 'created' | 'field_changed' | 'column_moved'

export type TaskHistoryField =
  | 'title'
  | 'body_doc'
  | 'task_type_id'
  | 'start_date'
  | 'end_date'
  | 'assignee_ids'
  | 'column_id'

export interface TaskHistoryEvent {
  id: string
  task_id: string
  project_id: string
  actor_id: string | null
  batch_id: string
  kind: TaskHistoryEventKind
  field: TaskHistoryField | null
  old_value: { v: unknown } | null
  new_value: { v: unknown } | null
  regression: boolean
  reverts_event_id: string | null
  comment: string | null
  inserted_at: string
}

export interface ProjectInvite {
  id: string
  token: string
  email: string | null
  expires_at: string | null
  accepted_at: string | null
  inserted_at?: string
  url?: string
}

export interface BoardSnapshot {
  project: Project
  can_write?: boolean
  is_owner?: boolean
  my_theme_slug?: string | null
  columns: Column[]
  tasks: Task[]
  task_types: TaskType[]
  task_comments: TaskComment[]
  settings?: BoardSettings
  users: BoardUser[]
  attachments: Attachment[]
  agent_runs?: AgentRun[]
  agent_limits?: { max_walltime_seconds: number }
}

type PresenceMeta = {
  online_at?: string
}

type PresenceEntry = {
  metas: PresenceMeta[]
}

type PresenceState = Record<string, PresenceEntry>

export const useBoardStore = defineStore('board', () => {
  const project = ref<Project | null>(null)
  const columns = ref<Column[]>([])
  const tasks = ref<Task[]>([])
  const task_types = ref<TaskType[]>([])
  const users = ref<BoardUser[]>([])
  const latestRuns = ref<Record<string, AgentRun>>({})
  const agentWalltimeSeconds = ref<number | null>(null)
  const attachments = ref<Attachment[]>([])
  const taskComments = ref<TaskComment[]>([])
  const taskHistoryEvents = ref<TaskHistoryEvent[]>([])
  const settings = ref<BoardSettings>({ allow_guest_comments: false })
  const presences = ref<PresenceState>({})
  const lastTaskDeleted = ref<TaskDeletedEvent | null>(null)
  const channel = ref<Channel | null>(null)
  const topic = ref<string | null>(null)
  const canWrite = ref(false)
  const isOwner = ref(false)
  const myProjectThemeSlug = ref<string | null>(null)
  const viewMode = ref<'columns' | 'list'>('columns')
  const filtersExpanded = ref(false)
  let openNewTaskCallback: (() => void) | null = null
  let openNewColumnCallback: (() => void) | null = null

  function registerBoardCallbacks(callbacks: { openNewTask: () => void; openNewColumn: () => void }) {
    openNewTaskCallback = callbacks.openNewTask
    openNewColumnCallback = callbacks.openNewColumn
  }

  function unregisterBoardCallbacks() {
    openNewTaskCallback = null
    openNewColumnCallback = null
  }

  function triggerNewTask() {
    openNewTaskCallback?.()
  }

  function triggerNewColumn() {
    openNewColumnCallback?.()
  }

  const orderedColumns = computed(() =>
    [...columns.value].sort((a, b) => (a.rank < b.rank ? -1 : a.rank > b.rank ? 1 : 0)),
  )

  const activeViewerIds = computed(() =>
    Object.entries(presences.value)
      .filter(([, entry]) => !!entry && entry.metas.length > 0)
      .map(([id]) => id),
  )

  function tasksFor(columnId: string): Task[] {
    return tasks.value
      .filter((t) => t.column_id === columnId)
      .sort((a, b) => (a.rank < b.rank ? -1 : a.rank > b.rank ? 1 : 0))
  }

  function taskById(id: string): Task | null {
    return tasks.value.find((t) => t.id === id) ?? null
  }

  async function joinBySlug(slug: string) {
    return joinTopic(`board_slug:${slug}`)
  }

  async function join(projectId: string) {
    return joinTopic(`board:${projectId}`)
  }

  async function joinTopic(targetTopic: string) {
    if (topic.value === targetTopic && channel.value?.state === 'joined') return channel.value

    if (channel.value) {
      const sock = useSocketStore()
      sock.leaveChannel(topic.value!)
    }

    const sock = useSocketStore()
    const { channel: ch, reply } = await sock.joinChannel<BoardSnapshot>(targetTopic)

    project.value = reply.project
    canWrite.value = reply.can_write ?? false
    isOwner.value = reply.is_owner ?? false
    myProjectThemeSlug.value = reply.my_theme_slug ?? null
    columns.value = reply.columns.slice()
    tasks.value = reply.tasks.slice()
    if (reply.task_types) task_types.value = reply.task_types.slice()
    taskComments.value = (reply.task_comments ?? []).slice()
    settings.value = reply.settings ?? { allow_guest_comments: false }
    if (reply.users) users.value = reply.users.slice()
    attachments.value = (reply.attachments ?? []).slice()
    agentWalltimeSeconds.value = reply.agent_limits?.max_walltime_seconds ?? null
    latestRuns.value = Object.fromEntries(
      (reply.agent_runs ?? []).filter((r) => r.task_id).map((r) => [r.task_id!, r]),
    )

    ch.on('project_updated', (p: Project) => {
      project.value = p
    })

    ch.on('agent_run_updated', (run: AgentRun) => applyRun(run))
    ch.on('board_users', ({ users: list }: { users: BoardUser[] }) => {
      users.value = list.slice()
    })

    ch.on('column_created', (c: Column) => upsertColumn(c))
    ch.on('column_updated', (c: Column) => upsertColumn(c))
    ch.on('column_moved', (c: Column) => upsertColumn(c))
    ch.on('column_deleted', ({ id }: { id: string }) => removeColumn(id))

    ch.on('task_created', (t: Task) => upsertTask(t))
    ch.on('task_updated', (t: Task) => upsertTask(t))
    ch.on('task_moved', (t: Task) => applyTaskMove(t))
    ch.on('task_deleted', (payload: TaskDeletedEvent) => {
      removeTask(payload.id)
      lastTaskDeleted.value = payload
    })

    ch.on('task_attachment_added', (a: Attachment) => upsertAttachment(a))
    ch.on('task_attachment_removed', ({ id }: { id: string }) => removeAttachment(id))
    ch.on('task_comment_created', (c: TaskComment) => upsertTaskComment(c))
    ch.on('task_comment_deleted', ({ id }: { id: string }) => removeTaskComment(id))
    ch.on('comment_attachment_added', (a: Attachment) => upsertCommentAttachment(a))
    ch.on('comment_attachment_removed', (p: { id: string; comment_id: string }) =>
      removeCommentAttachment(p.comment_id, p.id),
    )

    ch.on('task_history_events_created', ({ events }: { events: TaskHistoryEvent[] }) =>
      upsertHistoryEvents(events),
    )

    ch.on('task_type_created', (tt: TaskType) => upsertTaskType(tt))
    ch.on('task_type_updated', (tt: TaskType) => upsertTaskType(tt))
    ch.on('task_type_deleted', ({ id }: { id: string }) => removeTaskType(id))
    ch.on('presence_state', (state: PresenceState) => {
      presences.value = Presence.syncState(presences.value, state)
    })
    ch.on('presence_diff', (diff: { joins: PresenceState; leaves: PresenceState }) => {
      presences.value = Presence.syncDiff(presences.value, diff)
    })

    channel.value = ch
    topic.value = targetTopic
    return ch
  }

  function leave() {
    const sock = useSocketStore()
    if (topic.value) sock.leaveChannel(topic.value)
    channel.value = null
    topic.value = null
    project.value = null
    columns.value = []
    tasks.value = []
    task_types.value = []
    users.value = []
    latestRuns.value = {}
    attachments.value = []
    taskComments.value = []
    taskHistoryEvents.value = []
    settings.value = { allow_guest_comments: false }
    presences.value = {}
    lastTaskDeleted.value = null
    canWrite.value = false
    isOwner.value = false
    myProjectThemeSlug.value = null
  }

  function attachmentsFor(taskId: string): Attachment[] {
    return attachments.value.filter((a) => a.task_id === taskId)
  }

  function upsertAttachment(a: Attachment) {
    const idx = attachments.value.findIndex((x) => x.id === a.id)
    if (idx === -1) attachments.value.push(a)
    else attachments.value[idx] = a
  }

  function commentsFor(taskId: string): TaskComment[] {
    return taskComments.value.filter((c) => c.task_id === taskId)
  }

  function upsertTaskComment(comment: TaskComment) {
    const idx = taskComments.value.findIndex((x) => x.id === comment.id)
    if (idx === -1) taskComments.value.push(comment)
    else taskComments.value[idx] = comment
    taskComments.value.sort((a, b) => {
      const ai = a.inserted_at ? Date.parse(a.inserted_at) : 0
      const bi = b.inserted_at ? Date.parse(b.inserted_at) : 0
      return ai - bi
    })
  }

  function removeTaskComment(id: string) {
    taskComments.value = taskComments.value.filter((c) => c.id !== id)
  }

  function upsertCommentAttachment(a: Attachment) {
    if (!a.comment_id) return
    const comment = taskComments.value.find((c) => c.id === a.comment_id)
    if (!comment) return
    const list = comment.attachments ?? []
    const idx = list.findIndex((x) => x.id === a.id)
    if (idx === -1) comment.attachments = [...list, a]
    else comment.attachments = list.map((x) => (x.id === a.id ? a : x))
  }

  function removeCommentAttachment(commentId: string, attachmentId: string) {
    const comment = taskComments.value.find((c) => c.id === commentId)
    if (!comment) return
    comment.attachments = (comment.attachments ?? []).filter((a) => a.id !== attachmentId)
  }

  function removeAttachment(id: string) {
    attachments.value = attachments.value.filter((a) => a.id !== id)
  }

  function upsertColumn(c: Column) {
    const idx = columns.value.findIndex((x) => x.id === c.id)
    if (idx === -1) columns.value.push(c)
    else columns.value[idx] = c
  }

  function removeColumn(id: string) {
    columns.value = columns.value.filter((c) => c.id !== id)
    tasks.value = tasks.value.filter((t) => t.column_id !== id)
  }

  function upsertTask(t: Task) {
    const idx = tasks.value.findIndex((x) => x.id === t.id)
    if (idx === -1) tasks.value.push(t)
    else tasks.value[idx] = t
  }

  function removeTask(id: string) {
    tasks.value = tasks.value.filter((t) => t.id !== id)
  }

  function upsertTaskType(tt: TaskType) {
    const idx = task_types.value.findIndex((x) => x.id === tt.id)
    if (idx === -1) task_types.value.push(tt)
    else task_types.value[idx] = tt
  }

  function removeTaskType(id: string) {
    task_types.value = task_types.value.filter((t) => t.id !== id)
  }

  function ch() {
    if (!channel.value) throw new Error('board channel is not joined')
    return channel.value
  }

  function createColumn(name: string, color?: string | null) {
    return pushAsync<Column>(ch(), 'create_column', { name, color })
  }

  function renameColumn(id: string, name: string, description?: string | null, color?: string | null) {
    const payload: { id: string; name: string; description?: string | null; color?: string | null } = { id, name }
    if (description !== undefined) payload.description = description
    if (color !== undefined) payload.color = color
    return pushAsync<Column>(ch(), 'rename_column', payload)
  }

  function deleteColumn(id: string) {
    return pushAsync(ch(), 'delete_column', { id })
  }

  function moveColumn(id: string, beforeId: string | null, afterId: string | null) {
    return pushAsync<Column>(ch(), 'move_column', {
      id,
      before_id: beforeId,
      after_id: afterId,
    })
  }

  function createTask(columnId: string, input: { title: string; description?: string; start_date?: string; end_date?: string; assignee_ids?: string[]; task_type_id?: string | null }) {
    return pushAsync<Task>(ch(), 'create_task', { column_id: columnId, ...input })
  }

  function updateTask(
    id: string,
    input: { title?: string; body_doc?: TiptapDoc; start_date?: string | null; end_date?: string | null; assignee_ids?: string[]; task_type_id?: string | null },
  ) {
    return pushAsync<Task>(ch(), 'update_task', { id, ...input })
  }

  async function uploadTaskAttachment(
    taskId: string,
    file: File,
    onProgress?: (fraction: number) => void,
  ): Promise<Attachment> {
    const meta = await pushAsync<{
      attachment_id: string
      put_url: string
      mime: string
    }>(ch(), 'request_task_attachment_upload', {
      task_id: taskId,
      filename: file.name,
      mime: file.type || 'application/octet-stream',
      size: file.size,
    })

    await uploadToPresignedUrl(meta.put_url, file, onProgress)

    return await pushAsync<Attachment>(ch(), 'confirm_task_attachment_upload', {
      attachment_id: meta.attachment_id,
    })
  }

  function deleteTaskAttachment(id: string) {
    return pushAsync(ch(), 'delete_task_attachment', { id })
  }

  function deleteTask(id: string) {
    return pushAsync(ch(), 'delete_task', { id })
  }

  function createTaskComment(
    taskId: string,
    input: {
      body_doc?: TiptapDoc
      body?: string
      parentId?: string | null
      guestName?: string | null
    },
  ) {
    return pushAsync<TaskComment>(ch(), 'create_task_comment', {
      task_id: taskId,
      body_doc: input.body_doc,
      body: input.body,
      parent_id: input.parentId ?? null,
      guest_name: input.guestName ?? null,
    })
  }

  function deleteTaskComment(id: string) {
    return pushAsync(ch(), 'delete_task_comment', { id })
  }

  function upsertHistoryEvents(events: TaskHistoryEvent[]) {
    for (const e of events) {
      const idx = taskHistoryEvents.value.findIndex((x) => x.id === e.id)
      if (idx === -1) taskHistoryEvents.value.push(e)
      else taskHistoryEvents.value[idx] = e
    }
    taskHistoryEvents.value.sort((a, b) => Date.parse(b.inserted_at) - Date.parse(a.inserted_at))
  }

  async function listTaskHistory(opts: { before?: string; limit?: number } = {}) {
    const { events } = await pushAsync<{ events: TaskHistoryEvent[] }>(ch(), 'list_task_history', opts)
    if (!opts.before) taskHistoryEvents.value = events.slice()
    else upsertHistoryEvents(events)
    return events
  }

  function revertTaskHistoryEvent(id: string, comment?: string | null) {
    return pushAsync<Task>(ch(), 'revert_task_history_event', { id, comment: comment ?? null })
  }

  function rollbackTaskHistoryEvent(id: string, comment?: string | null) {
    return pushAsync<Task>(ch(), 'rollback_task_history_event', { id, comment: comment ?? null })
  }

  async function uploadCommentAttachment(
    commentId: string,
    file: File,
    onProgress?: (fraction: number) => void,
  ): Promise<Attachment> {
    const meta = await pushAsync<{
      attachment_id: string
      put_url: string
      mime: string
    }>(ch(), 'request_comment_attachment_upload', {
      comment_id: commentId,
      filename: file.name,
      mime: file.type || 'application/octet-stream',
      size: file.size,
    })

    await uploadToPresignedUrl(meta.put_url, file, onProgress)

    return await pushAsync<Attachment>(ch(), 'confirm_comment_attachment_upload', {
      attachment_id: meta.attachment_id,
    })
  }

  function deleteCommentAttachment(id: string) {
    return pushAsync(ch(), 'delete_comment_attachment', { id })
  }

  const localMoves = new Map<string, number>()
  let taskMovingHandler: ((task: Task, prevColumnId: string) => void) | null = null

  function onTaskMoving(handler: ((task: Task, prevColumnId: string) => void) | null) {
    taskMovingHandler = handler
  }

  function applyTaskMove(t: Task) {
    const existing = tasks.value.find((x) => x.id === t.id)
    if (existing && existing.column_id !== t.column_id) {
      taskMovingHandler?.(t, existing.column_id)
    }
    upsertTask(t)
  }

  function noteLocalMove(id: string) {
    localMoves.set(id, Date.now())
  }

  function consumeLocalMove(id: string): boolean {
    const at = localMoves.get(id)
    if (at === undefined) return false
    localMoves.delete(id)
    return Date.now() - at < 5000
  }

  function moveTask(
    id: string,
    columnId: string,
    beforeId: string | null,
    afterId: string | null,
  ) {
    noteLocalMove(id)
    return pushAsync<Task>(ch(), 'move_task', {
      id,
      column_id: columnId,
      before_id: beforeId,
      after_id: afterId,
    })
  }

  function createTaskType(input: {
    name: string
    description?: string | null
    color: string
    text_color: string
  }) {
    return pushAsync<TaskType>(ch(), 'create_task_type', input)
  }

  function updateTaskType(
    id: string,
    input: {
      name?: string
      description?: string | null
      color?: string
      text_color?: string
    },
  ) {
    return pushAsync<TaskType>(ch(), 'update_task_type', { id, ...input })
  }

  function deleteTaskType(id: string) {
    return pushAsync(ch(), 'delete_task_type', { id })
  }

  async function listMembers() {
    const reply = await pushAsync<{ members: ProjectMember[] }>(ch(), 'list_members', {})
    return reply.members
  }

  async function listInvites() {
    const reply = await pushAsync<{ invites: ProjectInvite[] }>(ch(), 'list_invites', {})
    return reply.invites
  }

  function inviteMember(input: { email?: string | null; expires_in_minutes?: number | null }) {
    return pushAsync<ProjectInvite>(ch(), 'invite_member', {
      email: input.email ?? null,
      expires_in_minutes: input.expires_in_minutes ?? null,
    })
  }

  function revokeInvite(id: string) {
    return pushAsync<{ id: string }>(ch(), 'revoke_invite', { id })
  }

  function removeMember(userId: string) {
    return pushAsync<{ user_id: string }>(ch(), 'remove_member', { user_id: userId })
  }

  function applyRun(run: AgentRun) {
    if (!run.task_id) return
    const current = latestRuns.value[run.task_id]
    if (current && current.id !== run.id && current.inserted_at > run.inserted_at) return
    latestRuns.value = { ...latestRuns.value, [run.task_id]: run }
  }

  function latestRunFor(taskId: string): AgentRun | null {
    return latestRuns.value[taskId] ?? null
  }

  function userById(id: string | null | undefined): BoardUser | null {
    if (!id) return null
    return users.value.find((u) => u.id === id) ?? null
  }

  function usersByIds(ids: readonly string[]): BoardUser[] {
    return ids.map((id) => userById(id)).filter((user): user is BoardUser => !!user)
  }

  function startAgentRun(taskId: string, agentId: string) {
    return pushAsync<AgentRun>(ch(), 'start_agent_run', { task_id: taskId, agent_id: agentId })
  }

  function stopAgentRun(runId: string) {
    return pushAsync<AgentRun>(ch(), 'stop_agent_run', { id: runId })
  }

  async function listTaskRuns(taskId: string) {
    const reply = await pushAsync<{ runs: AgentRun[] }>(ch(), 'list_task_runs', { task_id: taskId })
    return reply.runs
  }

  function setPublicLink(value: boolean) {
    return pushAsync<Project>(ch(), 'set_public_link', { public_link: value })
  }

  function setProjectTheme(slug: string | null) {
    return pushAsync<Project>(ch(), 'set_project_theme', { theme_slug: slug })
  }

  async function setMyProjectTheme(slug: string | null) {
    const reply = await pushAsync<{ theme_slug: string | null }>(ch(), 'set_my_project_theme', {
      theme_slug: slug,
    })
    myProjectThemeSlug.value = reply.theme_slug ?? null
    return reply.theme_slug ?? null
  }

  return {
    project,
    columns,
    tasks,
    task_types,
    users,
    attachments,
    taskComments,
    taskHistoryEvents,
    listTaskHistory,
    revertTaskHistoryEvent,
    rollbackTaskHistoryEvent,
    settings,
    canWrite,
    isOwner,
    myProjectThemeSlug,
    lastTaskDeleted,
    orderedColumns,
    activeViewerIds,
    tasksFor,
    taskById,
    attachmentsFor,
    commentsFor,
    join,
    joinBySlug,
    leave,
    createColumn,
    renameColumn,
    deleteColumn,
    moveColumn,
    createTask,
    updateTask,
    deleteTask,
    createTaskComment,
    deleteTaskComment,
    moveTask,
    consumeLocalMove,
    onTaskMoving,
    createTaskType,
    updateTaskType,
    deleteTaskType,
    uploadTaskAttachment,
    deleteTaskAttachment,
    uploadCommentAttachment,
    deleteCommentAttachment,
    listMembers,
    listInvites,
    inviteMember,
    revokeInvite,
    removeMember,
    latestRunFor,
    agentWalltimeSeconds,
    userById,
    usersByIds,
    startAgentRun,
    stopAgentRun,
    listTaskRuns,
    setPublicLink,
    setProjectTheme,
    setMyProjectTheme,
    viewMode,
    filtersExpanded,
    registerBoardCallbacks,
    unregisterBoardCallbacks,
    triggerNewTask,
    triggerNewColumn,
  }
})
