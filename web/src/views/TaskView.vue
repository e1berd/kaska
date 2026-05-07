<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore, type User } from '../stores/auth'
import { useBoardStore, type Task, type TiptapDoc } from '../stores/board'
import { docToHtml, isDocEmpty } from '../utils/tiptap'
import RichEditor from '../components/RichEditor.vue'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const board = useBoardStore()

const slug = computed(() => route.params.slug as string)
const taskId = computed(() => route.params.taskId as string)

const loading = ref(true)
const error = ref<string | null>(null)

const taskTitle = ref('')
const taskBody = ref<TiptapDoc>({ type: 'doc', content: [] })
const taskStartDate = ref<string | null>(null)
const taskEndDate = ref<string | null>(null)
const taskType = ref<string | null>(null)
const taskAssignee = ref<string | null>(null)
const editingDescription = ref(false)
const taskSaving = ref(false)
const taskSyncing = ref(false)
let taskSaveTimer: ReturnType<typeof setTimeout> | null = null

const currentTask = computed<Task | null>(() => board.tasks.find((t) => t.id === taskId.value) ?? null)
const descriptionHtml = computed(() => docToHtml(taskBody.value))
const descriptionEmpty = computed(() => isDocEmpty(taskBody.value))
const taskViewers = computed(() =>
  board.viewersForTask(taskId.value).filter((user) => user.id !== auth.user?.id),
)
const taskEditors = computed(() =>
  board.editorsForTask(taskId.value).filter((user) => user.id !== auth.user?.id),
)

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
  taskBody.value = task.body_doc ?? { type: 'doc', content: [] }
  taskStartDate.value = task.start_date ?? null
  taskEndDate.value = task.end_date ?? null
  taskType.value = task.task_type_id ?? null
  taskAssignee.value = task.assignee_id ?? null
  taskSyncing.value = false
}

async function load() {
  loading.value = true
  error.value = null
  try {
    await board.joinBySlug(slug.value)
    const task = currentTask.value
    if (!task) {
      error.value = 'Задача не найдена'
      return
    }
    syncFormFromTask(task)
    if (auth.isAuthed) {
      await board.setActiveTask(task.id, editingDescription.value)
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
  if (auth.isAuthed) {
    void board.setActiveTask(null, false).catch(() => {})
  }
  if (taskSaveTimer) clearTimeout(taskSaveTimer)
  board.leave()
})

function backToBoard() {
  router.push({ name: 'board', params: { slug: slug.value } })
}

async function saveTask() {
  if (!currentTask.value) return
  taskSaving.value = true
  try {
    await board.updateTask(currentTask.value.id, {
      title: taskTitle.value.trim(),
      body_doc: taskBody.value,
      start_date: taskStartDate.value,
      end_date: taskEndDate.value,
      task_type_id: taskType.value,
      assignee_id: taskAssignee.value,
    })
  } catch (err: any) {
    alert(err.message || 'Ошибка сохранения')
  } finally {
    taskSaving.value = false
  }
}

async function copyTaskLink() {
  const href = `${window.location.origin}/p/${slug.value}/tasks/${taskId.value}`
  if (navigator && navigator.clipboard) {
    await navigator.clipboard.writeText(href)
  }
}

watch(
  () => editingDescription.value,
  (editing) => {
    if (!auth.isAuthed || !currentTask.value) return
    void board.setActiveTask(currentTask.value.id, editing).catch(() => {})
  },
)

watch(
  () => currentTask.value,
  (task) => {
    if (!task) return
    syncFormFromTask(task)
  },
  { deep: true },
)

watch(
  () => [
    currentTask.value?.id,
    taskTitle.value,
    JSON.stringify(taskBody.value),
    taskStartDate.value,
    taskEndDate.value,
    taskType.value,
    taskAssignee.value,
  ],
  () => {
    if (!auth.isAuthed || !currentTask.value) return
    if (taskSyncing.value) return
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
      <div v-if="taskViewers.length" class="hh-task-page__presence ml-2">
        <span class="hh-task-page__presence-label md-label-small">Сейчас в задаче</span>
        <v-tooltip
          v-for="user in taskViewers"
          :key="user.id"
          :text="user.display_name || user.email"
          location="bottom"
        >
          <template #activator="{ props }">
            <span v-bind="props" class="hh-task-page__presence-item">
              <v-avatar size="24" color="primary" class="hh-task-page__presence-avatar">
                <img v-if="user.avatar_url" :src="user.avatar_url" alt="" />
                <span v-else>{{ (user.display_name || user.email || '?').slice(0, 1).toUpperCase() }}</span>
              </v-avatar>
            </span>
          </template>
        </v-tooltip>
      </div>
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
            v-if="auth.isAuthed && !editingDescription && !descriptionEmpty"
            variant="text"
            size="small"
            rounded="pill"
            prepend-icon="mdi-pencil-outline"
            @click="editingDescription = true"
          >
            Редактировать
          </v-btn>
          <v-btn
            v-else-if="auth.isAuthed && editingDescription && !descriptionEmpty"
            variant="text"
            size="small"
            rounded="pill"
            prepend-icon="mdi-eye-outline"
            @click="editingDescription = false"
          >
            Просмотр
          </v-btn>
        </div>
        <div
          v-if="!editingDescription && taskEditors.length"
          class="hh-task-page__editing-note md-body-small mb-2"
        >
          {{ (taskEditors[0].display_name || taskEditors[0].email) }} редактирует...
        </div>
        <RichEditor
          v-if="editingDescription"
          v-model="taskBody"
          :readonly="!auth.isAuthed"
          placeholder="Опишите задачу"
        />
        <div
          v-else-if="!descriptionEmpty"
          class="hh-task-page__description"
          v-html="descriptionHtml"
        />
        <div v-else class="hh-task-page__description-empty md-body-medium">
          Описание не заполнено.
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
        </v-card>
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
.hh-task-page__presence {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.hh-task-page__presence-label {
  color: rgba(var(--v-theme-on-surface), 0.7);
  white-space: nowrap;
}
.hh-task-page__presence-item {
  display: inline-flex;
}
.hh-task-page__presence-avatar {
  margin-left: -6px;
  border: 2px solid rgb(var(--v-theme-surface));
}
.hh-task-page__presence-item:first-child .hh-task-page__presence-avatar {
  margin-left: 0;
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
.hh-task-page__editing-note {
  color: rgba(var(--v-theme-on-surface), 0.65);
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
@media (max-width: 900px) {
  .hh-task-page__content {
    grid-template-columns: 1fr;
  }
}
</style>
