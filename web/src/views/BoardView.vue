<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { useRoute, useRouter, type LocationQueryRaw } from 'vue-router'
import { useDisplay } from 'vuetify'
import { monitorForElements } from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import { autoScrollForElements } from '@atlaskit/pragmatic-drag-and-drop-auto-scroll/element'
import { extractClosestEdge } from '@atlaskit/pragmatic-drag-and-drop-hitbox/closest-edge'
import { PhFloppyDisk } from '@phosphor-icons/vue'
import * as Y from 'yjs'
import { Awareness } from 'y-protocols/awareness'
import { Presence } from 'phoenix'
import { useAuthStore, type User } from '@/stores/auth'
import {
  useBoardStore,
  type Attachment,
  type Column,
  type Task,
  type TaskType,
  type TiptapDoc,
} from '@/stores/board'
import { useProjectsStore } from '@/stores/projects'
import { useSocketStore, pushAsync } from '@/stores/socket'
import BoardColumn from '@/components/board/BoardColumn.vue'
import RichEditor from '@/components/RichEditor.vue'
import PresenceGroup from '@/components/PresenceGroup.vue'
import TaskCommentsSection from '@/components/TaskCommentsSection.vue'
import { cssUrlImageOr } from '@/utils/css'
import { docPreview } from '@/utils/tiptap'
import { PhoenixYProvider } from '@/utils/PhoenixYProvider'

import { collabUserColor, base64ToUint8 } from '@/utils/collab'

defineProps<{ slug?: string }>()

const route = useRoute()
const router = useRouter()
const { mobile } = useDisplay()
const auth = useAuthStore()
const board = useBoardStore()
const projects = useProjectsStore()

const socket = useSocketStore()

const slug = computed(() => route.params.slug as string)
const loading = ref(true)
const error = ref<string | null>(null)
const colsScroll = ref<HTMLElement | null>(null)
let monitorCleanup: (() => void) | null = null
let columnsMonitorCleanup: (() => void) | null = null
let scrollCleanup: (() => void) | null = null

const viewMode = ref<'columns' | 'list'>('columns')
const VIEW_MODE_KEY_PREFIX = 'kaska.board.view_mode'
const FILTERS_EXPANDED_KEY_PREFIX = 'kaska.board.filters_expanded'
const filtersExpanded = ref(false)
const filterQuery = ref('')
const filterTaskType = ref<string | null>(null)
const filterAssignee = ref<string | null>(null)
const filterStartDate = ref<string | null>(null)
const filterEndDate = ref<string | null>(null)
const syncingFiltersFromRoute = ref(false)

const filterStartDateModel = computed<Date | null>({
  get: () => parseIsoDate(filterStartDate.value),
  set: (value) => {
    filterStartDate.value = value ? formatIsoDate(value) : null
  },
})

const filterEndDateModel = computed<Date | null>({
  get: () => parseIsoDate(filterEndDate.value),
  set: (value) => {
    filterEndDate.value = value ? formatIsoDate(value) : null
  },
})

const taskStartDateModel = computed<Date | null>({
  get: () => parseIsoDate(taskStartDate.value),
  set: (value) => {
    taskStartDate.value = value ? formatIsoDate(value) : null
  },
})

const taskEndDateModel = computed<Date | null>({
  get: () => parseIsoDate(taskEndDate.value),
  set: (value) => {
    taskEndDate.value = value ? formatIsoDate(value) : null
  },
})

const renameDialog = ref(false)
const renameTarget = ref<Column | null>(null)
const renameValue = ref('')

const deleteDialog = ref(false)
const deleteTarget = ref<Column | null>(null)

const taskDialog = ref(false)
const taskTarget = ref<Task | null>(null)
const taskTargetId = ref<string | null>(null)
const taskTitle = ref('')
const taskStartDate = ref<string | null>(null)
const taskEndDate = ref<string | null>(null)
const taskType = ref<string | null>(null)
const taskAssignee = ref<string | null>(null)
const taskUploading = ref(false)
const taskUploadProgress = ref(0)
const fileInput = ref<HTMLInputElement | null>(null)
const taskSaving = ref(false)
const taskSyncing = ref(false)
let taskSaveTimer: ReturnType<typeof setTimeout> | null = null
let formSaving = false
let taskSaveQueued = false
let savingCount = 0
let savingStartedAt = 0

function beginSave() {
  if (savingCount === 0) savingStartedAt = Date.now()
  savingCount++
  taskSaving.value = true
}

async function endSave() {
  savingCount--
  if (savingCount > 0) return
  const elapsed = Date.now() - savingStartedAt
  const remaining = Math.max(0, 1600 - elapsed)
  if (remaining > 0) await new Promise((resolve) => setTimeout(resolve, remaining))
  if (savingCount === 0) taskSaving.value = false
}

const taskYDoc = shallowRef<Y.Doc | null>(null)
const taskAwareness = shallowRef<Awareness | null>(null)
let taskProvider: PhoenixYProvider | null = null
let taskDocTopic: string | null = null
const richEditorRef = ref<{ getJSON: () => TiptapDoc } | null>(null)

type PresenceState = Record<string, { metas: Array<Record<string, unknown>> }>
const taskDocPresences = shallowRef<PresenceState>({})

const editingDescription = ref(false)
const deleteSnackOpen = ref(false)
const deleteSnackText = ref('')

const collabUser = computed(() => {
  const u = auth.user
  if (!u) return null
  return {
    name: u.display_name || u.email?.split('@')[0] || 'Гость',
    color: collabUserColor(u.id),
  }
})

const taskAttachments = computed<Attachment[]>(() => {
  return taskTarget.value ? board.attachmentsFor(taskTarget.value.id) : []
})
const taskViewers = computed(() => {
  const selfId = auth.user?.id
  return Object.keys(taskDocPresences.value)
    .filter((id) => id !== selfId)
    .map((id) => board.users.find((u) => u.id === id))
    .filter((u): u is NonNullable<typeof u> => !!u)
})
const currentTask = computed<Task | null>(() => {
  if (!taskTargetId.value) return null
  return board.tasks.find((t) => t.id === taskTargetId.value) ?? null
})

type TaskFormState = {
  title: string
  start_date: string | null
  end_date: string | null
  task_type_id: string | null
  assignee_id: string | null
}

function getTaskFormState(): TaskFormState {
  return {
    title: taskTitle.value.trim(),
    start_date: taskStartDate.value,
    end_date: taskEndDate.value,
    task_type_id: taskType.value,
    assignee_id: taskAssignee.value,
  }
}

function getTaskServerState(task: Task): TaskFormState {
  return {
    title: task.title,
    start_date: task.start_date ?? null,
    end_date: task.end_date ?? null,
    task_type_id: task.task_type_id ?? null,
    assignee_id: task.assignee_id ?? null,
  }
}

function isFormSyncedWithTask(task: Task): boolean {
  const form = getTaskFormState()
  const server = getTaskServerState(task)
  return (
    form.title === server.title &&
    form.start_date === server.start_date &&
    form.end_date === server.end_date &&
    form.task_type_id === server.task_type_id &&
    form.assignee_id === server.assignee_id
  )
}

const newColumnDialog = ref(false)
const newColumnName = ref('')

const orderedTasks = computed<Task[]>(() => {
  const colIndex = new Map(board.orderedColumns.map((c, i) => [c.id, i]))
  return [...board.tasks].sort((a, b) => {
    const ca = colIndex.get(a.column_id) ?? Number.MAX_SAFE_INTEGER
    const cb = colIndex.get(b.column_id) ?? Number.MAX_SAFE_INTEGER
    if (ca !== cb) return ca - cb
    return a.rank < b.rank ? -1 : a.rank > b.rank ? 1 : 0
  })
})

const filteredTasks = computed<Task[]>(() => {
  const byMeta = orderedTasks.value.filter((task) => {
    if (filterTaskType.value && task.task_type_id !== filterTaskType.value) return false
    if (filterAssignee.value && task.assignee_id !== filterAssignee.value) return false
    if (filterStartDate.value) {
      if (!task.start_date) return false
      if (task.start_date.slice(0, 10) < filterStartDate.value) return false
    }
    if (filterEndDate.value) {
      if (!task.end_date) return false
      if (task.end_date.slice(0, 10) > filterEndDate.value) return false
    }
    return true
  })

  const q = filterQuery.value.trim().toLowerCase()
  if (!q) return byMeta

  const titleMatches: Task[] = []
  const descriptionMatches: Task[] = []

  for (const task of byMeta) {
    const title = task.title.toLowerCase()
    if (title.includes(q)) {
      titleMatches.push(task)
      continue
    }
    const body = docPreview(task.body_doc ?? null, 5000).toLowerCase()
    if (body.includes(q)) descriptionMatches.push(task)
  }

  return [...titleMatches, ...descriptionMatches]
})

const listHeaders = computed(() => [
  { title: 'Карточка', key: 'title', sortable: true, minWidth: '260px' },
  { title: 'Тип', key: 'task_type_id', sortable: true, width: '180px' },
  { title: 'Колонка', key: 'column_id', sortable: false, width: '200px' },
  { title: 'Исполнитель', key: 'assignee_id', sortable: true, width: '200px' },
  { title: 'Сроки', key: 'dates', sortable: false, width: '200px' },
])

function taskTypeFor(id: string | null | undefined) {
  if (!id) return null
  return board.task_types.find((t) => t.id === id) ?? null
}

function userFor(id: string | null | undefined) {
  if (!id) return null
  return board.users.find((u) => u.id === id) ?? null
}

function optionUser(item: unknown): User {
  const candidate = item as { raw?: User } & User
  return (candidate.raw ?? candidate) as User
}

function userLabel(item: unknown): string {
  const user = optionUser(item)
  return user.display_name || user.email || '—'
}

function userInitial(item: unknown): string {
  return userLabel(item).slice(0, 1).toUpperCase()
}

function userAvatar(item: unknown): string {
  return optionUser(item).avatar_url || ''
}

function fmtDate(iso: string | null | undefined): string {
  if (!iso) return ''
  return new Date(iso).toLocaleDateString()
}

function parseIsoDate(value: string | null): Date | null {
  if (!value) return null
  const [y, m, d] = value.split('-').map((n) => Number(n))
  if (!y || !m || !d) return null
  return new Date(y, m - 1, d)
}

function formatIsoDate(date: Date): string {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

async function load() {
  loading.value = true
  error.value = null
  try {
    await Promise.all([
      board.joinBySlug(slug.value),
      projects.list.length ? Promise.resolve() : projects.joinLobby(),
    ])
    if (!board.project) throw new Error('проект не найден')
  } catch (e) {
    error.value = (e as { message?: string }).message ?? 'не удалось открыть доску'
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await load()
  const flash = sessionStorage.getItem('kaska.flash.task_deleted')
  if (flash) {
    deleteSnackText.value = flash
    deleteSnackOpen.value = true
    sessionStorage.removeItem('kaska.flash.task_deleted')
  }

  if (colsScroll.value) {
    scrollCleanup = autoScrollForElements({
      element: colsScroll.value,
      canScroll: ({ source }) => source.data.type === 'task',
    })
  }

  monitorCleanup = monitorForElements({
    canMonitor: ({ source }) => source.data.type === 'task',
    onDrop: ({ source, location }) => {
      const target = location.current.dropTargets[0]
      if (!target) return

      const sourceTask = source.data.task as Task
      const targetType = target.data.type as 'task' | 'column'
      let targetColumnId: string
      let beforeId: string | null = null
      let afterId: string | null = null

      if (targetType === 'task') {
        const overTask = target.data.task as Task
        if (overTask.id === sourceTask.id) return
        targetColumnId = overTask.column_id
        const edge = extractClosestEdge(target.data)
        const ordered = board.tasksFor(targetColumnId)
        const idx = ordered.findIndex((t) => t.id === overTask.id)
        if (edge === 'top') {
          beforeId = idx > 0 ? ordered[idx - 1].id : null
          afterId = overTask.id
        } else {
          beforeId = overTask.id
          afterId = idx + 1 < ordered.length ? ordered[idx + 1].id : null
        }
      } else {
        targetColumnId = target.data.columnId as string
        const ordered = board.tasksFor(targetColumnId).filter((t) => t.id !== sourceTask.id)
        beforeId = ordered.length ? ordered[ordered.length - 1].id : null
        afterId = null
      }

      board
        .moveTask(sourceTask.id, targetColumnId, beforeId, afterId)
        .catch((e) => {
          console.warn('[board] move failed', e)
        })
    },
  })

  columnsMonitorCleanup = monitorForElements({
    canMonitor: ({ source }) => source.data.type === 'column',
    onDrop: ({ source, location }) => {
      const target = location.current.dropTargets[0]
      if (!target || target.data.type !== 'column') return

      const sourceColumn = source.data.column as Column
      const overColumn = target.data.column as Column
      if (sourceColumn.id === overColumn.id) return

      const edge = extractClosestEdge(target.data)
      const ordered = board.orderedColumns.filter((c) => c.id !== sourceColumn.id)
      const idx = ordered.findIndex((c) => c.id === overColumn.id)
      if (idx < 0) return

      let beforeId: string | null = null
      let afterId: string | null = null

      if (edge === 'left') {
        beforeId = idx > 0 ? ordered[idx - 1].id : null
        afterId = overColumn.id
      } else {
        beforeId = overColumn.id
        afterId = idx + 1 < ordered.length ? ordered[idx + 1].id : null
      }

      board.moveColumn(sourceColumn.id, beforeId, afterId).catch((e) => {
        console.warn('[board] move column failed', e)
      })
    },
  })
})

onBeforeUnmount(() => {
  monitorCleanup?.()
  columnsMonitorCleanup?.()
  scrollCleanup?.()
  tearDownCollab()
  if (taskSaveTimer) clearTimeout(taskSaveTimer)
})

watch(slug, () => {
  load()
})

watch(taskDialog, (open) => {
  if (open) return
  if (!taskTargetId.value && !taskProvider) return
  closeTaskDialog()
})

watch(
  () => board.lastTaskDeleted,
  (evt) => {
    if (!evt) return
    if (evt.deleted_by_id === auth.user?.id) return
    if (!taskDialog.value || !taskTargetId.value) return
    if (evt.id !== taskTargetId.value) return

    const actor = evt.deleted_by_display_name || evt.deleted_by_email?.split('@')[0] || 'Пользователь'
    const title = evt.title || 'без названия'
    deleteSnackText.value = `${actor} удалил задачу ${title}`
    deleteSnackOpen.value = true
    closeTaskDialog()
  },
  { deep: true },
)

watch(
  () => [auth.user?.id ?? 'guest', slug.value] as const,
  ([userId, currentSlug]) => {
    const saved = localStorage.getItem(`${VIEW_MODE_KEY_PREFIX}:${userId}:${currentSlug}`)
    if (saved === 'columns' || saved === 'list') {
      viewMode.value = saved
      return
    }
    viewMode.value = 'columns'
  },
  { immediate: true },
)

watch(
  () => [auth.user?.id ?? 'guest', slug.value] as const,
  ([userId, currentSlug]) => {
    const saved = localStorage.getItem(`${FILTERS_EXPANDED_KEY_PREFIX}:${userId}:${currentSlug}`)
    if (saved === '1') filtersExpanded.value = true
    else if (saved === '0') filtersExpanded.value = false
  },
  { immediate: true },
)

watch(
  () => route.query,
  (query) => {
    syncingFiltersFromRoute.value = true
    filterQuery.value = typeof query.q === 'string' ? query.q : ''
    filterTaskType.value = typeof query.type === 'string' ? query.type : null
    filterAssignee.value = typeof query.assignee === 'string' ? query.assignee : null
    filterStartDate.value = typeof query.start === 'string' ? query.start : null
    filterEndDate.value = typeof query.end === 'string' ? query.end : null
    syncingFiltersFromRoute.value = false
  },
  { immediate: true },
)

watch(
  () => [
    filterQuery.value,
    filterTaskType.value,
    filterAssignee.value,
    filterStartDate.value,
    filterEndDate.value,
  ] as const,
  ([q, type, assignee, start, end]) => {
    if (syncingFiltersFromRoute.value) return

    const nextQuery: LocationQueryRaw = { ...route.query }
    if (q.trim()) nextQuery.q = q.trim()
    else delete nextQuery.q
    if (type) nextQuery.type = type
    else delete nextQuery.type
    if (assignee) nextQuery.assignee = assignee
    else delete nextQuery.assignee
    if (start) nextQuery.start = start
    else delete nextQuery.start
    if (end) nextQuery.end = end
    else delete nextQuery.end

    void router.replace({ query: nextQuery })
  },
)

watch(
  () => viewMode.value,
  (mode) => {
    const userId = auth.user?.id ?? 'guest'
    localStorage.setItem(`${VIEW_MODE_KEY_PREFIX}:${userId}:${slug.value}`, mode)
  },
)

watch(
  () => filtersExpanded.value,
  (expanded) => {
    const userId = auth.user?.id ?? 'guest'
    localStorage.setItem(
      `${FILTERS_EXPANDED_KEY_PREFIX}:${userId}:${slug.value}`,
      expanded ? '1' : '0',
    )
  },
)

watch(
  () => currentTask.value,
  (task) => {
    if (!task || !taskDialog.value) return
    taskSyncing.value = true
    taskTarget.value = task
    taskTitle.value = task.title
    taskStartDate.value = task.start_date ?? null
    taskEndDate.value = task.end_date ?? null
    taskType.value = task.task_type_id ?? null
    taskAssignee.value = task.assignee_id ?? null
    setTimeout(() => {
      taskSyncing.value = false
    }, 0)
  },
  { deep: true },
)

watch(
  () => [
    taskDialog.value,
    taskTargetId.value,
    taskTitle.value,
    taskStartDate.value,
    taskEndDate.value,
    taskType.value,
    taskAssignee.value,
  ],
  () => {
    if (!taskDialog.value || !currentTask.value || !board.canWrite) return
    if (taskSyncing.value) return
    if (isFormSyncedWithTask(currentTask.value)) return
    if (taskSaveTimer) clearTimeout(taskSaveTimer)
    taskSaveTimer = setTimeout(() => {
      void saveTask()
    }, 450)
  },
)

function onRename(column: Column) {
  renameTarget.value = column
  renameValue.value = column.name
  renameDialog.value = true
}

async function commitRename() {
  if (!renameTarget.value) return
  try {
    await board.renameColumn(renameTarget.value.id, renameValue.value.trim())
    renameDialog.value = false
  } catch (e) {
    console.warn('[board] rename failed', e)
  }
}

function onDeleteColumn(column: Column) {
  deleteTarget.value = column
  deleteDialog.value = true
}

async function commitDelete() {
  if (!deleteTarget.value) return
  try {
    await board.deleteColumn(deleteTarget.value.id)
    deleteDialog.value = false
  } catch (e) {
    console.warn('[board] delete failed', e)
  }
}

async function openTask(task: Task) {
  taskTargetId.value = task.id
  const actualTask = board.tasks.find((t) => t.id === task.id) ?? task
  taskTarget.value = actualTask
  taskSyncing.value = true
  taskTitle.value = actualTask.title
  taskStartDate.value = actualTask.start_date ?? null
  taskEndDate.value = actualTask.end_date ?? null
  taskType.value = actualTask.task_type_id ?? null
  taskAssignee.value = actualTask.assignee_id ?? null
  editingDescription.value = false
  taskSyncing.value = false
  taskDialog.value = true

  await setupCollab(actualTask.id)
}

async function setupCollab(taskId: string) {
  tearDownCollab()
  const topic = `task_doc:${taskId}`
  try {
    const { channel, reply } = await socket.joinChannel<{ state?: string }>(topic)
    if (taskTargetId.value !== taskId) {
      socket.leaveChannel(topic)
      return
    }
    const doc = new Y.Doc()
    if (reply.state) {
      const bytes = base64ToUint8(reply.state)
      if (bytes.byteLength > 0) Y.applyUpdate(doc, bytes)
    }
    const aw = new Awareness(doc)
    const provider = new PhoenixYProvider(channel, doc, aw, {
      onLocalSettle: () => {
        if (!board.canWrite) return
        const docJson = richEditorRef.value?.getJSON()
        if (!docJson) return
        beginSave()
        pushAsync(channel, 'materialize_body_doc', { doc: docJson })
          .catch((e) => console.warn('[board] materialize failed', e))
          .finally(() => {
            void endSave()
          })
      },
    })

    channel.on('presence_state', (state: PresenceState) => {
      taskDocPresences.value = Presence.syncState({}, state) as PresenceState
    })
    channel.on(
      'presence_diff',
      (diff: { joins: PresenceState; leaves: PresenceState }) => {
        Presence.syncDiff(taskDocPresences.value, diff)
        taskDocPresences.value = { ...taskDocPresences.value }
      },
    )

    taskYDoc.value = doc
    taskAwareness.value = aw
    taskProvider = provider
    taskDocTopic = topic
  } catch (e) {
    console.warn('[board] task_doc join failed', e)
  }
}

function tearDownCollab() {
  taskProvider?.destroy()
  taskProvider = null
  taskAwareness.value?.destroy()
  taskAwareness.value = null
  taskYDoc.value?.destroy()
  taskYDoc.value = null
  if (taskDocTopic) {
    socket.leaveChannel(taskDocTopic)
    taskDocTopic = null
  }
  taskDocPresences.value = {}
}

async function saveTask() {
  if (!currentTask.value) return
  if (formSaving) {
    taskSaveQueued = true
    return
  }
  if (isFormSyncedWithTask(currentTask.value)) return

  const payload = getTaskFormState()
  formSaving = true
  beginSave()
  try {
    await board.updateTask(currentTask.value.id, {
      title: payload.title,
      start_date: payload.start_date,
      end_date: payload.end_date,
      task_type_id: payload.task_type_id,
      assignee_id: payload.assignee_id,
    })
  } catch (err: any) {
    alert(err?.message || 'Ошибка сохранения задачи')
  } finally {
    formSaving = false
    void endSave()
    if (taskSaveQueued) {
      taskSaveQueued = false
      if (taskDialog.value && currentTask.value && board.canWrite) {
        void saveTask()
      }
    }
  }
}

async function deleteCurrentTask() {
  if (!taskTarget.value) return
  try {
    await board.deleteTask(taskTarget.value.id)
    closeTaskDialog()
  } catch (e) {
    console.warn('[board] delete task failed', e)
  }
}

async function pickAttachment() {
  fileInput.value?.click()
}

async function onAttachmentPicked(e: Event) {
  const input = e.target as HTMLInputElement
  const files = Array.from(input.files ?? [])
  input.value = ''
  if (!taskTarget.value) return

  for (const file of files) {
    taskUploading.value = true
    taskUploadProgress.value = 0
    try {
      await board.uploadTaskAttachment(taskTarget.value.id, file, (f) => {
        taskUploadProgress.value = f
      })
    } catch (err) {
      console.warn('[board] upload failed', err)
    } finally {
      taskUploading.value = false
      taskUploadProgress.value = 0
    }
  }
}

async function removeAttachmentClick(att: Attachment) {
  if (!confirm(`Удалить «${att.filename}»?`)) return
  try {
    await board.deleteTaskAttachment(att.id)
  } catch (e) {
    console.warn('[board] delete attachment failed', e)
  }
}

function fmtSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`
}

function openNewColumn() {
  newColumnName.value = ''
  newColumnDialog.value = true
}

async function commitNewColumn() {
  const name = newColumnName.value.trim()
  if (!name) return
  try {
    await board.createColumn(name)
    newColumnDialog.value = false
  } catch (e) {
    console.warn('[board] create column failed', e)
  }
}

function backToProjects() {
  router.push({ name: 'projects' })
}

function closeTaskDialog() {
  if (taskSaveTimer) {
    clearTimeout(taskSaveTimer)
    taskSaveTimer = null
  }
  taskDialog.value = false
  taskTargetId.value = null
  tearDownCollab()
}

function onDescriptionBlur() {
  taskProvider?.flush()
}

function openTaskPage() {
  if (!taskTarget.value) return
  void router.push({ name: 'task', params: { slug: slug.value, taskId: taskTarget.value.id } })
}

async function copyTaskLink() {
  if (!taskTarget.value) return
  const href = `${window.location.origin}/p/${slug.value}/tasks/${taskTarget.value.id}`
  if (navigator && navigator.clipboard) {
    await navigator.clipboard.writeText(href)
  }
}

function clearFilters() {
  filterQuery.value = ''
  filterTaskType.value = null
  filterAssignee.value = null
  filterStartDate.value = null
  filterEndDate.value = null
}

async function changeColumn(task: Task, newColumnId: unknown) {
  const targetId = typeof newColumnId === 'string' ? newColumnId : null
  if (!targetId || targetId === task.column_id) return
  const trailing = board.tasksFor(targetId).filter((t) => t.id !== task.id)
  const beforeId = trailing.length ? trailing[trailing.length - 1].id : null
  try {
    await board.moveTask(task.id, targetId, beforeId, null)
  } catch (e) {
    console.warn('[board] change column failed', e)
  }
}

const accents = ['primary', 'secondary', 'tertiary'] as const
function accentFor(idx: number): 'primary' | 'secondary' | 'tertiary' {
  return accents[idx % accents.length]
}

const boardBackgroundStyle = computed(() => ({
  backgroundImage: cssUrlImageOr(board.project?.background_url),
}))
</script>

<template>
  <div class="ks-board" :class="{ 'ks-board--bg': !!board.project?.background_url }">
    <div
      v-if="board.project?.background_url"
      class="ks-board__bg"
      :style="boardBackgroundStyle"
    />
    <div v-if="board.project?.background_url" class="ks-board__bg-scrim" />
    <header class="ks-board__bar">
      <v-btn
        icon="mdi-arrow-left"
        variant="text"
        density="comfortable"
        @click="backToProjects"
      />
      <div class="ks-board__title">
        <v-avatar
          v-if="board.project"
          size="32"
          class="ks-board__logo"
          color="primary-container"
        >
          <v-img
            v-if="board.project.avatar_url"
            :src="board.project.avatar_url"
            cover
            alt=""
          />
          <span v-else class="md-label-large">
            {{ (board.project.name || '?').slice(0, 1).toUpperCase() }}
          </span>
        </v-avatar>
        <span class="md-title-large">{{ board.project?.name ?? '…' }}</span>
        <code v-if="board.project" class="ks-board__slug">/{{ board.project.slug }}</code>
      </div>
      <v-spacer />
      <div class="ks-board__view-group mr-4" role="group" aria-label="Режим отображения доски">
        <v-tooltip text="Колонки" location="bottom">
          <template #activator="{ props }">
            <v-btn
              v-bind="props"
              :active="viewMode === 'columns'"
              :color="viewMode === 'columns' ? 'primary' : undefined"
              :variant="viewMode === 'columns' ? 'flat' : 'text'"
              icon="mdi-view-column-outline"
              size="small"
              rounded="pill"
              @click="viewMode = 'columns'"
            />
          </template>
        </v-tooltip>
        <v-tooltip text="Список" location="bottom">
          <template #activator="{ props }">
            <v-btn
              v-bind="props"
              :active="viewMode === 'list'"
              :color="viewMode === 'list' ? 'primary' : undefined"
              :variant="viewMode === 'list' ? 'flat' : 'text'"
              icon="mdi-format-list-bulleted"
              size="small"
              rounded="pill"
              @click="viewMode = 'list'"
            />
          </template>
        </v-tooltip>
      </div>
      <v-btn
        variant="text"
        rounded="pill"
        :prepend-icon="filtersExpanded ? 'mdi-filter-minus-outline' : 'mdi-filter-plus-outline'"
        @click="filtersExpanded = !filtersExpanded"
      >
        Фильтры
      </v-btn>
      <v-btn
        v-if="board.canWrite"
        prepend-icon="mdi-plus"
        key="board.canWrite"
        variant="tonal"
        rounded="pill"
        @click="openNewColumn"
      >
        Новая колонка
      </v-btn>
    </header>

    <v-expand-transition>
      <div v-if="filtersExpanded" class="ks-board__filters">
        <v-text-field
          v-model="filterQuery"
          label="Поиск по названию и описанию"
          prepend-inner-icon="mdi-magnify"
          variant="filled"
          density="comfortable"
          hide-details
          clearable
        />
        <v-select
          v-model="filterTaskType"
          :items="board.task_types"
          item-title="name"
          item-value="id"
          label="Тип задачи"
          variant="filled"
          density="comfortable"
          hide-details
          clearable
        />
        <v-select
          v-model="filterAssignee"
          :items="board.users"
          :item-title="(u: User) => u.display_name || u.email"
          item-value="id"
          label="Исполнитель"
          variant="filled"
          density="comfortable"
          hide-details
          clearable
        >
          <template #item="{ props: itemProps, item }">
            <v-list-item
              v-bind="itemProps"
              :title="userLabel(item)"
            >
              <template #prepend>
                <v-avatar
                  :image="userAvatar(item)"
                  size="24"
                  class="mr-2"
                  color="primary"
                >
                  <span
                    v-if="!userAvatar(item)"
                    class="text-white text-caption"
                  >
                    {{ userInitial(item) }}
                  </span>
                </v-avatar>
              </template>
            </v-list-item>
          </template>
          <template #selection="{ item }">
            <div class="ks-filter-user">
              <v-avatar
                :image="userAvatar(item)"
                size="20"
                class="mr-2"
                color="primary"
              >
                <span
                  v-if="!userAvatar(item)"
                  class="text-white"
                  style="font-size: 10px"
                >
                  {{ userInitial(item) }}
                </span>
              </v-avatar>
              <span class="ks-filter-user__label">
                {{ userLabel(item) }}
              </span>
            </div>
          </template>
        </v-select>
        <v-date-input
          v-model="filterStartDateModel"
          label="Дата начала от"
          density="comfortable"
          hide-details
          clearable
          prepend-icon=""
          prepend-inner-icon="mdi-calendar"
        />
        <v-date-input
          v-model="filterEndDateModel"
          label="Дата завершения до"
          density="comfortable"
          hide-details
          clearable
          prepend-icon=""
          prepend-inner-icon="mdi-calendar"
        />
        <v-btn variant="text" rounded="pill" prepend-icon="mdi-filter-off-outline" @click="clearFilters">
          Сбросить
        </v-btn>
      </div>
    </v-expand-transition>

    <div v-if="loading" class="ks-board__state">
      <v-progress-circular indeterminate color="primary" />
    </div>
    <v-alert
      v-else-if="error"
      type="error"
      variant="tonal"
      class="ma-4"
      rounded="lg"
    >
      {{ error }}
    </v-alert>

    <div v-else-if="viewMode === 'columns'" ref="colsScroll" class="ks-board__cols">
      <BoardColumn
        v-for="(column, idx) in board.orderedColumns"
        :key="column.id"
        :column="column"
        :tasks="filteredTasks.filter((t) => t.column_id === column.id)"
        :accent="accentFor(idx)"
        @open-task="openTask"
        @rename="onRename"
        @delete="onDeleteColumn"
      />
    </div>

    <div v-else-if="viewMode === 'list'" class="ks-board__list">
      <v-card class="ks-board__table" rounded="lg" variant="elevated" :elevation="1">
        <v-data-table
          :headers="listHeaders"
          :items="filteredTasks"
          :items-per-page="-1"
          item-value="id"
          density="comfortable"
          hover
          fixed-header
          class="ks-table"
          @click:row="(_: unknown, ctx: { item: Task }) => openTask(ctx.item)"
        >
          <template #no-data>
            <div class="text-center text-medium-emphasis py-8">
              Карточек пока нет.
            </div>
          </template>

          <template #bottom />

          <template #item.title="{ item }">
            <span class="ks-table__title md-body-medium">{{ item.title }}</span>
          </template>

          <template #item.task_type_id="{ item }">
            <v-chip
              v-if="taskTypeFor(item.task_type_id)"
              :color="taskTypeFor(item.task_type_id)?.color || undefined"
              size="small"
              label
              text-color="white"
            >
              {{ taskTypeFor(item.task_type_id)?.name }}
            </v-chip>
            <span v-else class="text-medium-emphasis md-body-small">—</span>
          </template>

          <template #item.column_id="{ item }">
            <v-select
              :model-value="item.column_id"
              :items="board.orderedColumns"
              item-title="name"
              item-value="id"
              variant="solo-filled"
              density="compact"
              hide-details
              flat
              rounded="pill"
              :menu-props="{ closeOnContentClick: true }"
              :readonly="!board.canWrite"
              class="ks-table__col-select"
              @click.stop
              @update:model-value="(v: unknown) => changeColumn(item, v)"
            />
          </template>

          <template #item.assignee_id="{ item }">
            <div v-if="userFor(item.assignee_id)" class="ks-table__assignee">
              <v-avatar
                :image="userFor(item.assignee_id)?.avatar_url || ''"
                size="24"
                color="primary"
              >
                <span
                  v-if="!userFor(item.assignee_id)?.avatar_url"
                  class="text-white"
                  style="font-size: 11px"
                >
                  {{
                    (
                      userFor(item.assignee_id)?.display_name ||
                      userFor(item.assignee_id)?.email ||
                      '?'
                    )
                      .slice(0, 1)
                      .toUpperCase()
                  }}
                </span>
              </v-avatar>
              <span class="md-body-small">
                {{ userFor(item.assignee_id)?.display_name || userFor(item.assignee_id)?.email }}
              </span>
            </div>
            <span v-else class="text-medium-emphasis md-body-small">—</span>
          </template>

          <template #item.dates="{ item }">
            <span v-if="item.start_date || item.end_date" class="ks-table__dates md-body-small">
              <v-icon size="14" class="mr-1">mdi-calendar</v-icon>
              {{ fmtDate(item.start_date) || '—' }} → {{ fmtDate(item.end_date) || '—' }}
            </span>
            <span v-else class="text-medium-emphasis md-body-small">—</span>
          </template>
        </v-data-table>
      </v-card>
    </div>

    <v-dialog v-model="renameDialog" max-width="460">
      <v-card rounded="xl">
        <v-card-title class="md-headline-small px-6 pt-6">Переименовать колонку</v-card-title>
        <v-card-text class="px-6 pt-2">
          <v-text-field
            v-model="renameValue"
            variant="filled"
            density="comfortable"
            autofocus
            hide-details
          />
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="renameDialog = false">Отмена</v-btn>
          <v-btn color="primary" variant="flat" rounded="pill" @click="commitRename">
            Сохранить
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="deleteDialog" max-width="460">
      <v-card rounded="xl">
        <v-card-title class="md-headline-small px-6 pt-6">Удалить колонку?</v-card-title>
        <v-card-text class="px-6 pt-2 md-body-medium text-medium-emphasis">
          Все её карточки тоже исчезнут. Действие нельзя отменить.
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="deleteDialog = false">Отмена</v-btn>
          <v-btn color="error" variant="flat" rounded="pill" @click="commitDelete">
            Удалить
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="newColumnDialog" max-width="460">
      <v-card rounded="xl">
        <v-card-title class="md-headline-small px-6 pt-6">Новая колонка</v-card-title>
        <v-card-text class="px-6 pt-2">
          <v-text-field
            v-model="newColumnName"
            label="название"
            variant="filled"
            density="comfortable"
            autofocus
            hide-details
            @keydown.enter.exact.prevent="commitNewColumn"
          />
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="newColumnDialog = false">Отмена</v-btn>
          <v-btn color="primary" variant="flat" rounded="pill" @click="commitNewColumn">
            Создать
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog
      v-model="taskDialog"
      max-width="1080"
      scrollable
      :fullscreen="mobile"
    >
      <v-card v-if="taskTarget" rounded="xl">
        <v-card-title class="px-6 pt-6 d-flex align-center ga-2">
          <span class="md-headline-small">Карточка</span>
          <PresenceGroup
            v-if="taskViewers.length"
            class="ml-2"
            :users="taskViewers"
            label="Сейчас в задаче"
            size="sm"
          />
          <v-spacer />
          <v-tooltip text="Открыть на странице" location="bottom">
            <template #activator="{ props }">
              <v-btn
                v-bind="props"
                icon="mdi-arrow-expand"
                variant="text"
                size="small"
                @click="openTaskPage"
              />
            </template>
          </v-tooltip>
          <v-tooltip text="Поделиться ссылкой" location="bottom">
            <template #activator="{ props }">
              <v-btn
                v-bind="props"
                icon="mdi-link-variant"
                variant="text"
                size="small"
                @click="copyTaskLink"
              />
            </template>
          </v-tooltip>
        </v-card-title>
        <v-card-text class="px-6 pt-2">
          <div class="ks-task-layout">
            <section class="ks-task-main">
              <v-text-field
                v-model="taskTitle"
                label="Название"
                variant="filled"
                density="comfortable"
                :readonly="!board.canWrite"
              />

              <div class="ks-desc__head mt-2 mb-2">
                <div class="md-label-large">Описание</div>
                <v-btn
                  v-if="board.canWrite && !editingDescription"
                  variant="text"
                  size="small"
                  rounded="pill"
                  prepend-icon="mdi-pencil-outline"
                  @click="editingDescription = true"
                >
                  Редактировать
                </v-btn>
                <v-btn
                  v-else-if="board.canWrite && editingDescription"
                  variant="text"
                  size="small"
                  rounded="pill"
                  prepend-icon="mdi-eye-outline"
                  @click="editingDescription = false"
                >
                  Просмотр
                </v-btn>
              </div>

              <RichEditor
                v-if="taskYDoc"
                ref="richEditorRef"
                :key="taskTargetId ?? ''"
                :ydoc="taskYDoc"
                :awareness="taskAwareness"
                :user="collabUser"
                :editable="board.canWrite && editingDescription"
                placeholder="Опишите задачу — поддерживаются стили, списки, ссылки и блоки кода"
                @blur="onDescriptionBlur"
              />

              <div class="ks-attach__head mt-5 mb-2">
                <div class="md-label-large">Вложения</div>
                <v-btn
                  v-if="board.canWrite"
                  variant="tonal"
                  rounded="pill"
                  size="small"
                  prepend-icon="mdi-paperclip"
                  :loading="taskUploading"
                  @click="pickAttachment"
                >
                  Прикрепить файл
                </v-btn>
              </div>
          <v-progress-linear
            v-if="taskUploading"
            :model-value="taskUploadProgress * 100"
            color="primary"
            rounded
            height="6"
            class="mb-3"
          />
          <input
            ref="fileInput"
            type="file"
            multiple
            accept="image/*,video/*,.pdf,.zip,.txt,.md"
            class="ks-attach__input"
            @change="onAttachmentPicked"
          />

          <div v-if="taskAttachments.length === 0" class="ks-attach__empty md-body-small">
            Пока вложений нет.
          </div>

          <div v-else class="ks-attach__grid">
            <div
              v-for="a in taskAttachments"
              :key="a.id"
              class="ks-attach"
              :class="`ks-attach--${a.kind}`"
            >
              <div class="ks-attach__media">
                <img v-if="a.kind === 'image' && a.url" :src="a.url" :alt="a.filename" />
                <video
                  v-else-if="a.kind === 'video' && a.url"
                  :src="a.url"
                  controls
                  preload="metadata"
                />
                <div v-else class="ks-attach__file">
                  <v-icon size="32">mdi-file-outline</v-icon>
                </div>
              </div>
              <div class="ks-attach__meta">
                <a
                  v-if="a.url"
                  class="ks-attach__name md-body-medium"
                  :href="a.url"
                  target="_blank"
                  rel="noopener"
                >
                  {{ a.filename }}
                </a>
                <span v-else class="ks-attach__name md-body-medium">{{ a.filename }}</span>
                <span class="ks-attach__size md-label-medium">{{ fmtSize(a.size) }}</span>
              </div>
              <v-btn
                v-if="board.canWrite"
                icon="mdi-close"
                variant="text"
                density="comfortable"
                size="small"
                class="ks-attach__remove"
                @click="removeAttachmentClick(a)"
              />
            </div>
          </div>
            </section>

            <aside class="ks-task-side">
              <v-card variant="flat" color="surface-container-high" rounded="lg" class="ks-task-meta-card">
                <div class="ks-task-meta-grid">
                  <v-date-input
                    v-model="taskStartDateModel"
                    label="Дата начала"
                    density="comfortable"
                    clearable
                    :readonly="!board.canWrite"
                    prepend-icon=""
                    prepend-inner-icon="mdi-calendar"
                  />
                  <v-date-input
                    v-model="taskEndDateModel"
                    label="Дата окончания"
                    density="comfortable"
                    clearable
                    :readonly="!board.canWrite"
                    prepend-icon=""
                    prepend-inner-icon="mdi-calendar"
                  />
                  <v-select
                    v-model="taskType"
                    :items="board.task_types"
                    item-title="name"
                    item-value="id"
                    label="Тип задачи"
                    variant="filled"
                    density="comfortable"
                    clearable
                    :readonly="!board.canWrite"
                  >
                    <template #item="{ props: itemProps, item }">
                      <v-list-item v-bind="itemProps">
                        <template #prepend>
                          <v-icon :color="(item as TaskType).color">mdi-circle</v-icon>
                        </template>
                      </v-list-item>
                    </template>
                    <template #selection="{ item }">
                      <v-chip
                        :color="(item as TaskType).color"
                        size="small"
                        text-color="white"
                        class="mr-2"
                      >
                        {{ (item as TaskType).name }}
                      </v-chip>
                    </template>
                  </v-select>
                  <v-select
                    v-model="taskAssignee"
                    :items="board.users"
                    item-title="display_name"
                    item-value="id"
                    label="Исполнитель"
                    variant="filled"
                    density="comfortable"
                    clearable
                    :readonly="!board.canWrite"
                  >
                    <template #item="{ props: itemProps, item }">
                      <v-list-item
                        v-bind="itemProps"
                        :title="(item as User).display_name || (item as User).email"
                      >
                        <template #prepend>
                          <v-avatar
                            :image="(item as User).avatar_url || ''"
                            size="24"
                            class="mr-2"
                            color="primary"
                          >
                            <span
                              v-if="!(item as User).avatar_url"
                              class="text-white text-caption"
                            >
                              {{
                                ((item as User).display_name || (item as User).email)
                                  .slice(0, 1)
                                  .toUpperCase()
                              }}
                            </span>
                          </v-avatar>
                        </template>
                      </v-list-item>
                    </template>
                    <template #selection="{ item }">
                      <div class="d-flex align-center">
                        <v-avatar
                          :image="(item as User).avatar_url || ''"
                          size="20"
                          class="mr-2"
                          color="primary"
                        >
                          <span
                            v-if="!(item as User).avatar_url"
                            class="text-white"
                            style="font-size: 10px"
                          >
                            {{
                              ((item as User).display_name || (item as User).email)
                                .slice(0, 1)
                                .toUpperCase()
                            }}
                          </span>
                        </v-avatar>
                        {{ (item as User).display_name || (item as User).email }}
                      </div>
                    </template>
                  </v-select>
                </div>
              </v-card>
              <TaskCommentsSection
                v-if="taskTarget"
                :task-id="taskTarget.id"
                class="ks-task-comments-side mt-3"
              />
            </aside>
          </div>
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-btn
            v-if="board.canWrite"
            color="error"
            variant="text"
            rounded="pill"
            @click="deleteCurrentTask"
          >
            Удалить карточку
          </v-btn>
          <v-spacer />
          <div
            key="save"
            class="save-icon flex items-center justify-center text-primary"
            v-if="board.canWrite && taskSaving"
            style="height: 24px"
          >
            <PhFloppyDisk size="24" />
          </div>
          <v-btn variant="text" rounded="pill" @click="closeTaskDialog">Закрыть</v-btn>

        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
  <v-snackbar
    v-model="deleteSnackOpen"
    timeout="5000"
    location="bottom right"
    color="surface-container-high"
  >
    {{ deleteSnackText }}
  </v-snackbar>
</template>

<style scoped>

.save-icon {
  animation: opacityTransition .8s ease-in-out infinite reverse;
}

@keyframes opacityTransition {
  0% {
    opacity: 0;
  }
  50% {
    opacity: 1;
  }
  100% {
    opacity: 0;
  }
}

.ks-board {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
  position: relative;
  isolation: isolate;
  overflow: hidden;
  background:
    radial-gradient(1200px 600px at 0% 0%, rgba(var(--v-theme-primary), 0.05), transparent 60%),
    radial-gradient(1200px 600px at 100% 100%, rgba(var(--v-theme-tertiary), 0.05), transparent 60%),
    rgb(var(--v-theme-surface));
}
.ks-board--bg {
  background: rgb(var(--v-theme-surface));
}
.ks-board__bg,
.ks-board__bg-scrim {
  position: absolute;
  inset: 0;
  pointer-events: none;
  z-index: 0;
}
.ks-board__bg {
  background-position: center;
  background-size: cover;
  filter: blur(20px) saturate(115%);
  transform: scale(1.08);
  opacity: 0.4;
}
.ks-board__bg-scrim {
  background: linear-gradient(
    180deg,
    rgba(var(--v-theme-surface), 0.55) 0%,
    rgba(var(--v-theme-surface), 0.85) 100%
  );
}
.ks-board > *:not(.ks-board__bg):not(.ks-board__bg-scrim) {
  position: relative;
  z-index: 1;
}
.ks-board__bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  flex-wrap: wrap;
}
.ks-board__title {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  color: rgb(var(--v-theme-on-surface));
}
.ks-board__logo {
  flex: 0 0 auto;
}
.ks-board__slug {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 13px;
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.ks-board__view-group {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-surface-container));
  border: 1px solid rgba(var(--v-theme-outline), 0.24);
}
.ks-board__filters {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 10px;
  padding: 0 16px 12px;
}
.ks-board__filters :deep(.v-input) {
  min-width: 0;
}
.ks-filter-user {
  display: inline-flex;
  align-items: center;
  min-width: 0;
  max-width: 100%;
}
.ks-filter-user__label {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ks-board__state {
  display: flex;
  justify-content: center;
  padding: 80px 0;
}
.ks-board__cols {
  flex: 1;
  min-height: 0;
  height: 0;
  display: flex;
  gap: 14px;
  padding: 8px 16px 20px;
  overflow-x: auto;
  overflow-y: hidden;
  align-items: stretch;
}

.ks-board__list {
  flex: 1;
  padding: 8px 16px 20px;
  overflow: auto;
}
.ks-board__table {
  background: rgb(var(--v-theme-surface-container-low));
  overflow: hidden;
}
.ks-board__table :deep(.v-table__wrapper) {
  overflow-x: auto;
}
.ks-table :deep(thead th) {
  background: rgb(var(--v-theme-surface-container)) !important;
  color: rgba(var(--v-theme-on-surface), 0.7);
  font-weight: 500;
  letter-spacing: 0.1px;
}
.ks-table :deep(tbody tr) {
  transition: background-color var(--md-duration-short3) var(--md-easing-standard);
}
.ks-table :deep(tbody tr:hover td) {
  background: rgba(var(--v-theme-on-surface), 0.04) !important;
}
.ks-table :deep(tbody tr) {
  cursor: pointer;
}
.ks-table__title {
  color: rgb(var(--v-theme-on-surface));
  font-weight: 500;
}
.ks-table__col-select {
  max-width: 180px;
}
.ks-table__col-select :deep(.v-field) {
  background: rgb(var(--v-theme-surface-container-high));
  border-radius: var(--md-shape-full);
}
.ks-table__assignee {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.ks-table__dates {
  display: inline-flex;
  align-items: center;
  white-space: nowrap;
  color: rgba(var(--v-theme-on-surface), 0.78);
}

.ks-task-layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 320px;
  gap: 16px;
  align-items: start;
}
.ks-task-main {
  min-width: 0;
}
.ks-task-side {
  min-width: 0;
  position: sticky;
  top: 0;
}
.ks-task-comments-side {
  border-radius: var(--md-shape-l);
}
.ks-task-meta-card {
  padding: 12px;
  border: 1px solid rgba(var(--v-theme-outline), 0.45);
  box-shadow: var(--md-elev-1);
}
.ks-task-meta-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 8px;
}
.ks-task-meta-grid :deep(.v-field) {
  background: rgb(var(--v-theme-surface-container-highest));
}
.ks-task__row {
  display: flex;
  gap: 16px;
  margin-top: 4px;
  flex-wrap: wrap;
}
.ks-task__row > * {
  flex: 1 1 220px;
  min-width: 0;
}

@media (max-width: 960px) {
  .ks-board__filters {
    grid-template-columns: 1fr 1fr;
  }
}

@media (max-width: 600px) {
  .ks-board__filters {
    grid-template-columns: 1fr;
  }
  .ks-task-layout {
    grid-template-columns: 1fr;
  }
  .ks-task-side {
    position: static;
  }
  .ks-board__cols {
    padding: 8px 12px 16px;
  }
}

.ks-desc__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.ks-desc__view {
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
  border-radius: var(--md-shape-m);
  padding: 12px 16px;
  background: rgb(var(--v-theme-surface-container-lowest));
  color: rgb(var(--v-theme-on-surface));
  min-height: 170px;
  font-family: 'Roboto Flex', 'Roboto', sans-serif;
}
.ks-desc__view :deep(p) {
  margin: 0 0 8px;
  line-height: 1.5;
}
.ks-desc__view :deep(p:last-child) {
  margin-bottom: 0;
}
.ks-desc__view :deep(h2) {
  font-size: var(--md-type-title-large);
  line-height: 1.25;
  font-weight: 500;
  margin: 16px 0 8px;
}
.ks-desc__view :deep(h3) {
  font-size: var(--md-type-title-medium);
  line-height: 1.3;
  font-weight: 500;
  margin: 12px 0 6px;
}
.ks-desc__view :deep(ul),
.ks-desc__view :deep(ol) {
  padding-left: 22px;
  margin: 4px 0;
}
.ks-desc__view :deep(blockquote) {
  border-left: 3px solid rgb(var(--v-theme-primary));
  padding: 2px 12px;
  margin: 8px 0;
  color: rgba(var(--v-theme-on-surface), 0.78);
}
.ks-desc__view :deep(pre) {
  background: rgb(var(--v-theme-surface-container-high));
  border-radius: var(--md-shape-s);
  padding: 10px 12px;
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 13px;
  overflow-x: auto;
}
.ks-desc__view :deep(code) {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 0.92em;
  background: rgb(var(--v-theme-surface-container-high));
  border-radius: 4px;
  padding: 1px 4px;
}
.ks-desc__view :deep(a) {
  color: rgb(var(--v-theme-primary));
  text-decoration: underline;
}
.ks-desc__empty {
  border: 1px dashed rgba(var(--v-theme-outline-variant), 0.6);
  border-radius: var(--md-shape-m);
  padding: 18px;
  text-align: center;
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.ks-desc__editing-note {
  color: rgba(var(--v-theme-on-surface), 0.65);
}
.ks-edit-lock-btn {
  opacity: 0.9;
}
.ks-attach__size {
  color: rgba(var(--v-theme-on-surface), 0.55);
}
</style>
