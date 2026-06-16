<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, shallowRef, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useDisplay } from 'vuetify'
import * as Y from 'yjs'
import { Awareness } from 'y-protocols/awareness'
import { Presence } from 'phoenix'
import { useAuthStore, type User } from '@/stores/auth'
import { useBoardStore, type Attachment, type Task, type TiptapDoc } from '@/stores/board'
import { useSocketStore, pushAsync } from '@/stores/socket'
import RichEditor from '@/components/RichEditor.vue'
import PresenceGroup from '@/components/PresenceGroup.vue'
import TaskCommentsSection from '@/components/TaskCommentsSection.vue'
import { eachDayOfInterval, format, isValid, parse } from 'date-fns'
import { PhoenixYProvider } from '@/utils/PhoenixYProvider'

import { collabUserColor, base64ToUint8 } from '@/utils/collab'

defineProps<{ slug?: string; taskId?: string }>()

const route = useRoute()
const router = useRouter()
const { mobile } = useDisplay()
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
const metaOpen = ref(false)
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
let taskDocTopic: string | null = null
const richEditorRef = ref<{ getJSON: () => TiptapDoc } | null>(null)

type PresenceState = Record<string, { metas: Array<Record<string, unknown>> }>
const taskDocPresences = shallowRef<PresenceState>({})

const collabUser = computed(() => {
  const u = auth.user
  if (!u) return null
  return {
    name: u.display_name || u.email?.split('@')[0] || 'Гость',
    color: collabUserColor(u.id),
  }
})

const currentTask = computed<Task | null>(() => board.tasks.find((t) => t.id === taskId.value) ?? null)
const shortTaskId = computed(() => currentTask.value?.id.slice(0, 8) ?? taskId.value.slice(0, 8))
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

const taskDateRangeModel = computed<Date[]>({
  get: () => {
    const start = parseIsoDate(taskStartDate.value)
    const end = parseIsoDate(taskEndDate.value)
    if (start && end) return buildDateRange(start, end)
    if (start) return [start]
    if (end) return [end]
    return []
  },
  set: (value) => {
    if (!value || value.length === 0) {
      taskStartDate.value = null
      taskEndDate.value = null
      return
    }
    const sorted = [...value].sort((a, b) => a.getTime() - b.getTime())
    taskStartDate.value = formatIsoDate(sorted[0])
    taskEndDate.value = formatIsoDate(sorted[sorted.length - 1])
  },
})

function parseIsoDate(value: string | null): Date | null {
  if (!value) return null
  const parsed = parse(value, 'yyyy-MM-dd', new Date())
  return isValid(parsed) ? parsed : null
}

function formatIsoDate(date: Date): string {
  return format(date, 'yyyy-MM-dd')
}

function buildDateRange(start: Date, end: Date): Date[] {
  return eachDayOfInterval({ start, end })
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
        Presence.syncDiff(taskDocPresences.value, diff)
        taskDocPresences.value = { ...taskDocPresences.value }
      },
    )

    taskYDoc.value = doc
    taskAwareness.value = aw
    taskProvider = provider
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
  if (taskSaveTimer) {
    clearTimeout(taskSaveTimer)
    taskSaveTimer = null
    if (auth.isAuthed && currentTask.value && !isFormSyncedWithTask(currentTask.value)) {
      void saveTask()
    }
  }
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
      sessionStorage.setItem('kaska.flash.task_deleted', `${actor} удалил задачу ${title}`)
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
  <div class="ks-task-page">
    <header class="ks-task-page__bar">
      <v-btn icon="mdi-arrow-left" variant="text" density="comfortable" @click="backToBoard" />
      <span class="md-title-large">Задача</span>
      <span class="ks-task-page__id md-label-large">ID {{ shortTaskId }}</span>
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

    <div v-if="loading" class="ks-task-page__state">
      <v-progress-circular indeterminate color="primary" />
    </div>
    <v-alert v-else-if="error" type="error" variant="tonal" class="ma-4">{{ error }}</v-alert>
    <div v-else class="ks-task-page__content">
      <div class="ks-task-page__main">
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
              v-if="auth.isAuthed"
              icon="mdi-close"
              variant="text"
              density="comfortable"
              size="small"
              class="ks-attach__remove"
              @click="removeAttachmentClick(a)"
            />
          </div>
        </div>
      </div>
      <aside class="ks-task-page__meta">
        <v-btn
          v-if="mobile"
          class="ks-task-page__toggle"
          variant="tonal"
          size="small"
          density="comfortable"
          block
          :append-icon="metaOpen ? 'mdi-chevron-up' : 'mdi-chevron-down'"
          @click="metaOpen = !metaOpen"
        >
          Свойства и комментарии
        </v-btn>
        <div v-show="!mobile || metaOpen" class="ks-task-page__meta-body">
        <div class="ks-task-page__group">
          <div class="ks-task-page__meta-title md-label-large">Свойства</div>
          <div class="ks-task-page__fields">
            <v-date-input
              v-model="taskDateRangeModel"
              multiple="range"
              label="Даты задачи"
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
          </div>
          <v-btn
            v-if="auth.isAuthed"
            color="error"
            variant="tonal"
            rounded="pill"
            size="small"
            prepend-icon="mdi-trash-can-outline"
            class="ks-task-page__delete align-self-start"
            @click="deleteCurrentTask"
          >
            Удалить карточку
          </v-btn>
        </div>
        <v-divider class="ks-task-page__divider" />
        <TaskCommentsSection
          v-if="currentTask"
          :task-id="currentTask.id"
          class="ks-task-page__comments"
        />
        </div>
      </aside>
    </div>
  </div>
</template>

<style scoped>
.ks-task-page {
  display: flex;
  flex-direction: column;
  min-height: calc(100vh - 64px);
}
.ks-task-page__bar {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 16px;
}
.ks-task-page__id {
  color: rgb(var(--v-theme-on-surface-variant));
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
}
.ks-task-page__state {
  display: flex;
  justify-content: center;
  padding: 80px 0;
}
.ks-task-page__content {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: minmax(0, 1fr) 360px;
}
.ks-task-page__main {
  min-width: 0;
  overflow-y: auto;
  padding: 8px 24px 24px;
}
.ks-attach__media {
  background: rgb(var(--v-theme-surface-container));
}
.ks-attach__remove {
  --ks-attach-remove-bg: rgba(var(--v-theme-surface), 0.7);
  --ks-attach-remove-color: currentColor;
}
.ks-task-page__meta {
  min-width: 0;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: 16px 20px 24px;
  background: rgb(var(--v-theme-surface-container-high));
  border-left: 1px solid rgba(var(--v-theme-outline-variant), 0.8);
}
.ks-task-page__meta-body {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.ks-task-page__toggle {
  justify-content: space-between;
}
.ks-task-page__group {
  display: flex;
  flex-direction: column;
}
.ks-task-page__delete {
  margin-top: 20px;
}
.ks-task-page__meta-title {
  color: rgb(var(--v-theme-on-surface-variant));
  margin-bottom: 12px;
}
.ks-task-page__fields {
  display: grid;
  gap: 8px;
}
.ks-task-page__meta :deep(.v-field) {
  background: rgb(var(--v-theme-surface-container-highest));
}
.ks-task-page__divider {
  opacity: 0.5;
}
@media (max-width: 959px) {
  .ks-task-page {
    min-height: 0;
  }
  .ks-task-page__content {
    grid-template-columns: 1fr;
    flex: initial;
  }
  .ks-task-page__main,
  .ks-task-page__meta {
    overflow-y: visible;
  }
  .ks-task-page__meta {
    border-left: none;
    border-top: 1px solid rgba(var(--v-theme-outline-variant), 0.8);
  }
}
</style>
