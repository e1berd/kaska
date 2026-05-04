import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { Channel } from 'phoenix'
import { pushAsync, useSocketStore } from './socket'
import type { Project } from './projects'

export interface Column {
  id: string
  project_id: string
  name: string
  rank: string
}

export interface Task {
  id: string
  project_id: string
  column_id: string
  title: string
  description: string | null
  rank: string
  creator_id: string | null
  inserted_at?: string
  updated_at?: string
}

interface BoardSnapshot {
  project: Project
  columns: Column[]
  tasks: Task[]
}

export const useBoardStore = defineStore('board', () => {
  const project = ref<Project | null>(null)
  const columns = ref<Column[]>([])
  const tasks = ref<Task[]>([])
  const channel = ref<Channel | null>(null)
  const topic = ref<string | null>(null)

  // Sorted views — `rank` is lexicographic.
  const orderedColumns = computed(() =>
    [...columns.value].sort((a, b) => (a.rank < b.rank ? -1 : a.rank > b.rank ? 1 : 0)),
  )

  function tasksFor(columnId: string): Task[] {
    return tasks.value
      .filter((t) => t.column_id === columnId)
      .sort((a, b) => (a.rank < b.rank ? -1 : a.rank > b.rank ? 1 : 0))
  }

  async function join(projectId: string) {
    const targetTopic = `board:${projectId}`
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

    ch.on('column_created', (c: Column) => upsertColumn(c))
    ch.on('column_updated', (c: Column) => upsertColumn(c))
    ch.on('column_moved', (c: Column) => upsertColumn(c))
    ch.on('column_deleted', ({ id }: { id: string }) => removeColumn(id))

    ch.on('task_created', (t: Task) => upsertTask(t))
    ch.on('task_updated', (t: Task) => upsertTask(t))
    ch.on('task_moved', (t: Task) => upsertTask(t))
    ch.on('task_deleted', ({ id }: { id: string }) => removeTask(id))

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
  }

  function upsertColumn(c: Column) {
    const idx = columns.value.findIndex((x) => x.id === c.id)
    if (idx === -1) columns.value.push(c)
    else columns.value[idx] = c
  }

  function removeColumn(id: string) {
    columns.value = columns.value.filter((c) => c.id !== id)
    // tasks of the deleted column are removed by the DB cascade and broadcast,
    // but if the broadcast lost a race, drop them locally too:
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

  function ch() {
    if (!channel.value) throw new Error('board channel is not joined')
    return channel.value
  }

  // Mutations ─────────────────────────────────────────────────────────

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

  function createTask(columnId: string, input: { title: string; description?: string }) {
    return pushAsync<Task>(ch(), 'create_task', { column_id: columnId, ...input })
  }

  function updateTask(id: string, input: { title?: string; description?: string }) {
    return pushAsync<Task>(ch(), 'update_task', { id, ...input })
  }

  function deleteTask(id: string) {
    return pushAsync(ch(), 'delete_task', { id })
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

  return {
    project,
    columns,
    tasks,
    orderedColumns,
    tasksFor,
    join,
    leave,
    createColumn,
    renameColumn,
    deleteColumn,
    moveColumn,
    createTask,
    updateTask,
    deleteTask,
    moveTask,
  }
})
