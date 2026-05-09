import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { Presence, type Channel } from 'phoenix'
import { pushAsync, useSocketStore } from './socket'
import type { Project } from './projects'
import type { User } from './auth'
import { uploadToPresignedUrl } from '../utils/upload'

export interface Column {
  id: string
  project_id: string
  name: string
  rank: string
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
  assignee_id: string | null
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
}

export interface Attachment {
  id: string
  task_id: string
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
  body: string
  author_id: string | null
  guest_name: string | null
  author_display_name: string | null
  author_email: string | null
  author_avatar_url: string | null
  author_role: User['role'] | null
  inserted_at?: string
  updated_at?: string
}

export interface BoardSettings {
  allow_guest_comments: boolean
}

export interface BoardSnapshot {
  project: Project
  columns: Column[]
  tasks: Task[]
  task_types: TaskType[]
  task_comments: TaskComment[]
  settings?: BoardSettings
  users: User[]
  attachments: Attachment[]
}

type PresenceMeta = {
  online_at?: string
  active_task_id?: string | null
  editing_description?: boolean
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
  const users = ref<User[]>([])
  const attachments = ref<Attachment[]>([])
  const taskComments = ref<TaskComment[]>([])
  const settings = ref<BoardSettings>({ allow_guest_comments: false })
  const presences = ref<PresenceState>({})
  const lastTaskDeleted = ref<TaskDeletedEvent | null>(null)
  const channel = ref<Channel | null>(null)
  const topic = ref<string | null>(null)

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

  function viewersForTask(taskId: string): User[] {
    const ids = Object.entries(presences.value)
      .filter(([, entry]) =>
        entry.metas.some((meta) => meta.active_task_id === taskId),
      )
      .map(([id]) => id)
    return users.value.filter((user) => ids.includes(user.id))
  }

  function editorsForTask(taskId: string): User[] {
    const ids = Object.entries(presences.value)
      .filter(([, entry]) =>
        entry.metas.some(
          (meta) => meta.active_task_id === taskId && meta.editing_description === true,
        ),
      )
      .map(([id]) => id)
    return users.value.filter((user) => ids.includes(user.id))
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
    columns.value = reply.columns.slice()
    tasks.value = reply.tasks.slice()
    if (reply.task_types) task_types.value = reply.task_types.slice()
    taskComments.value = (reply.task_comments ?? []).slice()
    settings.value = reply.settings ?? { allow_guest_comments: false }
    if (reply.users) users.value = reply.users.slice()
    attachments.value = (reply.attachments ?? []).slice()

    ch.on('column_created', (c: Column) => upsertColumn(c))
    ch.on('column_updated', (c: Column) => upsertColumn(c))
    ch.on('column_moved', (c: Column) => upsertColumn(c))
    ch.on('column_deleted', ({ id }: { id: string }) => removeColumn(id))

    ch.on('task_created', (t: Task) => upsertTask(t))
    ch.on('task_updated', (t: Task) => upsertTask(t))
    ch.on('task_moved', (t: Task) => upsertTask(t))
    ch.on('task_deleted', (payload: TaskDeletedEvent) => {
      removeTask(payload.id)
      lastTaskDeleted.value = payload
    })

    ch.on('task_attachment_added', (a: Attachment) => upsertAttachment(a))
    ch.on('task_attachment_removed', ({ id }: { id: string }) => removeAttachment(id))
    ch.on('task_comment_created', (c: TaskComment) => upsertTaskComment(c))
    ch.on('task_comment_deleted', ({ id }: { id: string }) => removeTaskComment(id))

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
    attachments.value = []
    taskComments.value = []
    settings.value = { allow_guest_comments: false }
    presences.value = {}
    lastTaskDeleted.value = null
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

  function createColumn(name: string) {
    return pushAsync<Column>(ch(), 'create_column', { name })
  }

  function renameColumn(id: string, name: string) {
    return pushAsync<Column>(ch(), 'rename_column', { id, name })
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

  function createTask(columnId: string, input: { title: string; description?: string; start_date?: string; end_date?: string; assignee_id?: string | null; task_type_id?: string | null }) {
    return pushAsync<Task>(ch(), 'create_task', { column_id: columnId, ...input })
  }

  function updateTask(
    id: string,
    input: { title?: string; body_doc?: TiptapDoc; start_date?: string | null; end_date?: string | null; assignee_id?: string | null; task_type_id?: string | null },
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

  function createTaskComment(taskId: string, body: string, guestName?: string | null) {
    return pushAsync<TaskComment>(ch(), 'create_task_comment', {
      task_id: taskId,
      body,
      guest_name: guestName ?? null,
    })
  }

  function deleteTaskComment(id: string) {
    return pushAsync(ch(), 'delete_task_comment', { id })
  }

  function moveTask(
    id: string,
    columnId: string,
    beforeId: string | null,
    afterId: string | null,
  ) {
    return pushAsync<Task>(ch(), 'move_task', {
      id,
      column_id: columnId,
      before_id: beforeId,
      after_id: afterId,
    })
  }

  function createTaskType(input: { name: string; description?: string | null; color: string }) {
    return pushAsync<TaskType>(ch(), 'create_task_type', input)
  }

  function updateTaskType(id: string, input: { name?: string; description?: string | null; color?: string }) {
    return pushAsync<TaskType>(ch(), 'update_task_type', { id, ...input })
  }

  function deleteTaskType(id: string) {
    return pushAsync(ch(), 'delete_task_type', { id })
  }

  function setActiveTask(taskId: string | null, editingDescription = false) {
    if (!channel.value) {
      return Promise.resolve({ task_id: taskId, editing_description: editingDescription })
    }
    return pushAsync(ch(), 'set_active_task', {
      task_id: taskId,
      editing_description: editingDescription,
    })
  }

  return {
    project,
    columns,
    tasks,
    task_types,
    users,
    attachments,
    taskComments,
    settings,
    lastTaskDeleted,
    orderedColumns,
    activeViewerIds,
    viewersForTask,
    editorsForTask,
    tasksFor,
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
    createTaskType,
    updateTaskType,
    deleteTaskType,
    setActiveTask,
    uploadTaskAttachment,
    deleteTaskAttachment,
  }
})
