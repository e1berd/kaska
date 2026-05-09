<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import * as Y from 'yjs'
import { Awareness } from 'y-protocols/awareness'
import { type Channel, Presence } from 'phoenix'
import { useAuthStore, type User } from '@/stores/auth'
import { useBoardStore, type Attachment, type Task, type TiptapDoc } from '@/stores/board'
import { useSocketStore, pushAsync } from '@/stores/socket'
import RichEditor from '@/components/RichEditor.vue'
import PresenceGroup from '@/components/PresenceGroup.vue'
import TaskCommentsSection from '@/components/TaskCommentsSection.vue'
import { PhoenixYProvider } from '@/utils/PhoenixYProvider'

const COLLAB_PALETTE = [
  '#ef4444', '#f97316', '#eab308', '#22c55e',
  '#06b6d4', '#3b82f6', '#8b5cf6', '#ec4899',
] as const
function colorFromId(id: string): string {
  let hash = 0
  for (let i = 0; i < id.length; i++) hash = id.charCodeAt(i) + ((hash << 5) - hash)
  return COLLAB_PALETTE[Math.abs(hash) % COLLAB_PALETTE.length]
}

function base64ToUint8(b64: string): Uint8Array {
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

defineProps<{ slug?: string; taskId?: string }>()

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const board = useBoardStore()
const socket = useSocketStore()

const slug = computed(() => route.params.slug as string)
const taskId = computed(() => route.params.taskId as string)

const loading = ref(true)
const error = ref<string | null>(null)

const taskTitle = ref('')
const taskStartDate = ref<string | null>(null)
const taskEndDate = ref<string | null>(null)
const taskType = ref<string | null>(null)
const taskAssignee = ref<string | null>(null)
const editingDescription = ref(false)
const taskSaving = ref(false)
const taskSyncing = ref(false)
const taskUploading = ref(false)
const taskUploadProgress = ref(0)
const fileInput = ref<HTMLInputElement | null>(null)
let taskSaveTimer: ReturnType<typeof setTimeout> | null = null
let taskSavingStartedAt = 0
let taskSaveQueued = false

const taskYDoc = shallowRef<Y.Doc | null>(null)
const taskAwareness = shallowRef<Awareness | null>(null)
let taskProvider: PhoenixYProvider | null = null
let taskDocChannel: Channel | null = null
let taskDocTopic: string | null = null
const richEditorRef = ref<{ getJSON: () => TiptapDoc } | null>(null)

type PresenceState = Record<string, { metas: Array<Record<string, unknown>> }>
const taskDocPresences = shallowRef<PresenceState>({})

const collabUser = computed(() => {
  const u = auth.user
  if (!u) return null
  return {
    name: u.display_name || u.email?.split('@')[0] || 'Гость',
    color: colorFromId(u.id),
  }
})

const currentTask = computed<Task | null>(() => board.tasks.find((t) => t.id === taskId.value) ?? null)
const taskAttachments = computed<Attachment[]>(() => {
  if (!currentTask.value) return []
  return board.attachmentsFor(currentTask.value.id)
})
const taskViewers = computed(() => {
  const selfId = auth.user?.id
  return Object.keys(taskDocPresences.value)
    .filter((id) => id !== selfId)
    .map((id) => board.users.find((u) => u.id === id))
    .filter((u): u is NonNullable<typeof u> => !!u)
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

function syncFormFromTask(task: Task) {
  taskSyncing.value = true
  taskTitle.value = task.title
  taskStartDate.value = task.start_date ?? null
  taskEndDate.value = task.end_date ?? null
  taskType.value = task.task_type_id ?? null
  taskAssignee.value = task.assignee_id ?? null
  setTimeout(() => {
    taskSyncing.value = false
  }, 0)
}

async function setupCollab(id: string) {
  tearDownCollab()
  const topic = `task_doc:${id}`
  try {
    const { channel, reply } = await socket.joinChannel<{ state?: string }>(topic)
    if (taskId.value !== id) {
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
        if (!auth.isAuthed) return
        const docJson = richEditorRef.value?.getJSON()
        if (!docJson) return
        pushAsync(channel, 'materialize_body_doc', { doc: docJson }).catch((e) => {
          console.warn('[task] materialize failed', e)
        })
      },
    })

    channel.on('presence_state', (state: PresenceState) => {
      taskDocPresences.value = Presence.syncState({}, state) as PresenceState
    })
    channel.on(
      'presence_diff',
      (diff: { joins: PresenceState; leaves: PresenceState }) => {
        taskDocPresences.value = Presence.syncDiff(
          taskDocPresences.value,
          diff,
        ) as PresenceState
      },
    )

    taskYDoc.value = doc
    taskAwareness.value = aw
    taskProvider = provider
    taskDocChannel = channel
    taskDocTopic = topic
  } catch (e) {
    console.warn('[task] task_doc join failed', e)
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
  taskDocChannel = null
  taskDocPresences.value = {}
}

async function load() {
  loading.value = true
  error.value = null
  try {
    await board.joinBySlug(slug.value)
    if (currentTask.value) {
      syncFormFromTask(currentTask.value)
      await setupCollab(currentTask.value.id)
    }
  } catch (e: any) {
    error.value = e?.message || 'Не удалось открыть задачу'
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  void load()
})

onBeforeUnmount(() => {
  tearDownCollab()
  if (taskSaveTimer) clearTimeout(taskSaveTimer)
})

function backToBoard() {
  router.push({ name: 'board', params: { slug: slug.value } })
}

async function saveTask() {
  if (!currentTask.value) return
  if (taskSaving.value) {
    taskSaveQueued = true
    return
  }
  if (isFormSyncedWithTask(currentTask.value)) return
  const payload = getTaskFormState()
  taskSaving.value = true
  taskSavingStartedAt = Date.now()
  try {
    await board.updateTask(currentTask.value.id, {
      title: payload.title,
      start_date: payload.start_date,
      end_date: payload.end_date,
      task_type_id: payload.task_type_id,
      assignee_id: payload.assignee_id,
    })
  } catch (err: any) {
    alert(err?.message || 'Ошибка сохранения')
  } finally {
    const elapsed = Date.now() - taskSavingStartedAt
    const remaining = Math.max(0, 1600 - elapsed)
    if (remaining > 0) await new Promise((resolve) => setTimeout(resolve, remaining))
    taskSaving.value = false
    if (taskSaveQueued) {
      taskSaveQueued = false
      if (currentTask.value && auth.isAuthed) void saveTask()
    }
  }
}

async function deleteCurrentTask() {
  if (!currentTask.value) return
  try {
    await board.deleteTask(currentTask.value.id)
    void router.push({ name: 'board', params: { slug: slug.value } })
  } catch (e) {
    console.warn('[task] delete failed', e)
  }
}

function fmtSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`
}

function pickAttachment() {
  fileInput.value?.click()
}

async function onAttachmentPicked(e: Event) {
  const input = e.target as HTMLInputElement
  const files = Array.from(input.files ?? [])
  input.value = ''
  if (!currentTask.value) return

  for (const file of files) {
    taskUploading.value = true
    taskUploadProgress.value = 0
    try {
      await board.uploadTaskAttachment(currentTask.value.id, file, (f) => {
        taskUploadProgress.value = f
      })
    } catch (err) {
      console.warn('[task] upload failed', err)
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
    console.warn('[task] delete attachment failed', e)
  }
}

async function copyTaskLink() {
  const href = `${window.location.origin}/p/${slug.value}/tasks/${taskId.value}`
  if (navigator && navigator.clipboard) {
    await navigator.clipboard.writeText(href)
  }
}

watch(
  () => currentTask.value,
  (task) => {
    if (!task) {
      if (!loading.value) error.value = 'Задача не найдена'
      return
    }
    if (error.value) error.value = null
    syncFormFromTask(task)
  },
  { deep: true },
)

watch(
  () => [currentTask.value?.id, currentTask.value?.updated_at] as const,
  () => {
    if (!currentTask.value) return
    if (error.value) error.value = null
    syncFormFromTask(currentTask.value)
  },
)

watch(
  () => [slug.value, taskId.value] as const,
  () => {
    void load()
  },
)

watch(
  () => board.lastTaskDeleted,
  (evt) => {
    if (!evt) return
    if (evt.id !== taskId.value) return

    const actor = evt.deleted_by_display_name || evt.deleted_by_email?.split('@')[0] || 'Пользователь'
    const title = evt.title || 'без названия'
    if (evt.deleted_by_id !== auth.user?.id) {
      sessionStorage.setItem('hardhat.flash.task_deleted', `${actor} удалил задачу ${title}`)
    }
    void router.push({ name: 'board', params: { slug: slug.value } })
  },
  { deep: true },
)

watch(
  () => [
    currentTask.value?.id,
    taskTitle.value,
    taskStartDate.value,
    taskEndDate.value,
    taskType.value,
    taskAssignee.value,
  ],
  () => {
    if (!auth.isAuthed || !currentTask.value) return
    if (taskSyncing.value) return
    if (isFormSyncedWithTask(currentTask.value)) return
    if (taskSaveTimer) clearTimeout(taskSaveTimer)
    taskSaveTimer = setTimeout(() => {
      void saveTask()
    }, 450)
  },
)
</script>

<template>
  <div class="hh-task-page">
    <header class="hh-task-page__bar">
      <v-btn icon="mdi-arrow-left" variant="text" density="comfortable" @click="backToBoard" />
      <span class="md-title-large">Задача</span>
      <PresenceGroup
        v-if="taskViewers.length"
        class="ml-2"
        :users="taskViewers"
        label="Сейчас в задаче"
        size="sm"
      />
      <v-spacer />
      <v-tooltip text="Поделиться ссылкой" location="bottom">
        <template #activator="{ props }">
          <v-btn v-bind="props" icon="mdi-link-variant" variant="text" @click="copyTaskLink" />
        </template>
      </v-tooltip>
      <v-progress-circular
        v-if="auth.isAuthed && taskSaving"
        indeterminate
        size="20"
        width="2"
        color="primary"
      />
    </header>

    <div v-if="loading" class="hh-task-page__state">
      <v-progress-circular indeterminate color="primary" />
    </div>
    <v-alert v-else-if="error" type="error" variant="tonal" class="ma-4">{{ error }}</v-alert>
    <div v-else class="hh-task-page__content">
      <div class="hh-task-page__main">
        <v-text-field
          v-model="taskTitle"
          label="Название"
          density="comfortable"
          :readonly="!auth.isAuthed"
        />
        <div class="d-flex align-center justify-space-between mb-2 mt-2">
          <div class="md-label-large">Описание</div>
          <v-btn
            v-if="auth.isAuthed && !editingDescription"
            variant="text"
            size="small"
            rounded="pill"
            prepend-icon="mdi-pencil-outline"
            @click="editingDescription = true"
          >
            Редактировать
          </v-btn>
          <v-btn
            v-else-if="auth.isAuthed && editingDescription"
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
          :key="taskId"
          :ydoc="taskYDoc"
          :awareness="taskAwareness"
          :user="collabUser"
          :editable="auth.isAuthed && editingDescription"
          placeholder="Опишите задачу"
        />
        <div class="d-flex align-center justify-space-between mt-5 mb-2">
          <div class="md-label-large">Вложения</div>
          <v-btn
            v-if="auth.isAuthed"
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
          class="hh-attach__input"
          @change="onAttachmentPicked"
        />
        <div v-if="taskAttachments.length === 0" class="hh-attach__empty md-body-small">
          Пока вложений нет.
        </div>
        <div v-else class="hh-attach__grid">
          <div
            v-for="a in taskAttachments"
            :key="a.id"
            class="hh-attach"
            :class="`hh-attach--${a.kind}`"
          >
            <div class="hh-attach__media">
              <img v-if="a.kind === 'image' && a.url" :src="a.url" :alt="a.filename" />
              <video
                v-else-if="a.kind === 'video' && a.url"
                :src="a.url"
                controls
                preload="metadata"
              />
              <div v-else class="hh-attach__file">
                <v-icon size="32">mdi-file-outline</v-icon>
              </div>
            </div>
            <div class="hh-attach__meta">
              <a
                v-if="a.url"
                class="hh-attach__name md-body-medium"
                :href="a.url"
                target="_blank"
                rel="noopener"
              >
                {{ a.filename }}
              </a>
              <span v-else class="hh-attach__name md-body-medium">{{ a.filename }}</span>
              <span class="hh-attach__size md-label-medium">{{ fmtSize(a.size) }}</span>
            </div>
            <v-btn
              v-if="auth.isAuthed"
              icon="mdi-close"
              variant="text"
              density="comfortable"
              size="small"
              class="hh-attach__remove"
              @click="removeAttachmentClick(a)"
            />
          </div>
        </div>
      </div>
      <aside class="hh-task-page__side">
        <v-card variant="flat" color="surface-container-high" class="hh-task-page__meta">
          <v-date-input
            v-model="taskStartDateModel"
            label="Дата начала"
            density="comfortable"
            clearable
            :readonly="!auth.isAuthed"
            prepend-icon=""
            prepend-inner-icon="mdi-calendar"
          />
          <v-date-input
            v-model="taskEndDateModel"
            label="Дата окончания"
            density="comfortable"
            clearable
            :readonly="!auth.isAuthed"
            prepend-icon=""
            prepend-inner-icon="mdi-calendar"
          />
          <v-select
            v-model="taskType"
            :items="board.task_types"
            item-title="name"
            item-value="id"
            label="Тип задачи"
            density="comfortable"
            clearable
            :readonly="!auth.isAuthed"
          />
          <v-select
            v-model="taskAssignee"
            :items="board.users"
            :item-title="(u: User) => u.display_name || u.email"
            item-value="id"
            label="Исполнитель"
            density="comfortable"
            clearable
            :readonly="!auth.isAuthed"
          />
          <v-btn
            v-if="auth.isAuthed"
            color="error"
            variant="text"
            rounded="pill"
            @click="deleteCurrentTask"
          >
            Удалить карточку
          </v-btn>
        </v-card>
        <TaskCommentsSection
          v-if="currentTask"
          :task-id="currentTask.id"
          class="hh-task-page__comments mt-3"
        />
      </aside>
    </div>
  </div>
</template>

<style scoped>
.hh-task-page {
  display: flex;
  flex-direction: column;
  min-height: 0;
}
.hh-task-page__bar {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 16px;
}
.hh-task-page__state {
  display: flex;
  justify-content: center;
  padding: 80px 0;
}
.hh-task-page__content {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 320px;
  gap: 16px;
  padding: 0 16px 16px;
}
.hh-task-page__description {
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
  border-radius: var(--md-shape-m);
  padding: 12px 16px;
  background: rgb(var(--v-theme-surface-container-lowest));
}
.hh-task-page__description-empty {
  border: 1px dashed rgba(var(--v-theme-outline-variant), 0.6);
  border-radius: var(--md-shape-m);
  padding: 18px;
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.hh-attach__media {
  background: rgb(var(--v-theme-surface-container));
}
.hh-attach__remove {
  --hh-attach-remove-bg: rgba(var(--v-theme-surface), 0.7);
  --hh-attach-remove-color: currentColor;
}
.hh-task-page__editing-note {
  color: rgba(var(--v-theme-on-surface), 0.65);
}
.hh-edit-lock-btn {
  opacity: 0.9;
}
.hh-task-page__meta {
  padding: 12px;
  border: 1px solid rgba(var(--v-theme-outline), 0.45);
  box-shadow: var(--md-elev-1);
  display: grid;
  gap: 8px;
}
.hh-task-page__meta :deep(.v-field) {
  background: rgb(var(--v-theme-surface-container-highest));
}
.hh-task-page__comments {
  border-radius: var(--md-shape-l);
}
@media (max-width: 900px) {
  .hh-task-page__content {
    grid-template-columns: 1fr;
  }
}
</style>
