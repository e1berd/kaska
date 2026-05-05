<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { monitorForElements } from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import { autoScrollForElements } from '@atlaskit/pragmatic-drag-and-drop-auto-scroll/element'
import { extractClosestEdge } from '@atlaskit/pragmatic-drag-and-drop-hitbox/closest-edge'

import { useAuthStore } from '../stores/auth'
import {
  useBoardStore,
  type Attachment,
  type Column,
  type Task,
  type TiptapDoc,
} from '../stores/board'
import { useProjectsStore } from '../stores/projects'
import BoardColumn from '../components/board/BoardColumn.vue'
import RichEditor from '../components/RichEditor.vue'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const board = useBoardStore()
const projects = useProjectsStore()

const slug = computed(() => route.params.slug as string)
const loading = ref(true)
const error = ref<string | null>(null)
const colsScroll = ref<HTMLElement | null>(null)
let monitorCleanup: (() => void) | null = null
let scrollCleanup: (() => void) | null = null

// dialogs
const renameDialog = ref(false)
const renameTarget = ref<Column | null>(null)
const renameValue = ref('')

const deleteDialog = ref(false)
const deleteTarget = ref<Column | null>(null)

const taskDialog = ref(false)
const taskTarget = ref<Task | null>(null)
const taskTitle = ref('')
const taskBody = ref<TiptapDoc>({ type: 'doc', content: [] })
const taskUploading = ref(false)
const taskUploadProgress = ref(0)
const fileInput = ref<HTMLInputElement | null>(null)

const taskAttachments = computed<Attachment[]>(() => {
  return taskTarget.value ? board.attachmentsFor(taskTarget.value.id) : []
})

const newColumnDialog = ref(false)
const newColumnName = ref('')

async function load() {
  loading.value = true
  error.value = null
  try {
    // ensure we know the project id; lobby snapshot is the cheapest source
    if (!projects.list.length) await projects.joinLobby()
    const project = projects.findBySlug(slug.value)
    if (!project) throw new Error('проект не найден')
    await board.join(project.id)
  } catch (e) {
    error.value = (e as { message?: string }).message ?? 'не удалось открыть доску'
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  await load()

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
})

onBeforeUnmount(() => {
  monitorCleanup?.()
  scrollCleanup?.()
  board.leave()
})

watch(slug, () => {
  load()
})

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

function openTask(task: Task) {
  taskTarget.value = task
  taskTitle.value = task.title
  taskBody.value = task.body_doc ?? { type: 'doc', content: [] }
  taskDialog.value = true
}

async function saveTask() {
  if (!taskTarget.value) return
  try {
    await board.updateTask(taskTarget.value.id, {
      title: taskTitle.value.trim(),
      body_doc: taskBody.value,
    })
    taskDialog.value = false
  } catch (e) {
    console.warn('[board] update task failed', e)
  }
}

async function deleteCurrentTask() {
  if (!taskTarget.value) return
  try {
    await board.deleteTask(taskTarget.value.id)
    taskDialog.value = false
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

const accents = ['primary', 'secondary', 'tertiary'] as const
function accentFor(idx: number): 'primary' | 'secondary' | 'tertiary' {
  return accents[idx % accents.length]
}
</script>

<template>
  <div class="hh-board">
    <header class="hh-board__bar">
      <v-btn
        icon="mdi-arrow-left"
        variant="text"
        density="comfortable"
        @click="backToProjects"
      />
      <div class="hh-board__title">
        <span class="md-title-large">{{ board.project?.name ?? '…' }}</span>
        <code v-if="board.project" class="hh-board__slug">/{{ board.project.slug }}</code>
      </div>
      <v-spacer />
      <v-btn
        v-if="auth.isAuthed"
        prepend-icon="mdi-plus"
        variant="tonal"
        rounded="pill"
        @click="openNewColumn"
      >
        Новая колонка
      </v-btn>
    </header>

    <div v-if="loading" class="hh-board__state">
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

    <div v-else ref="colsScroll" class="hh-board__cols">
      <BoardColumn
        v-for="(column, idx) in board.orderedColumns"
        :key="column.id"
        :column="column"
        :accent="accentFor(idx)"
        @open-task="openTask"
        @rename="onRename"
        @delete="onDeleteColumn"
      />
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

    <v-dialog v-model="taskDialog" max-width="760" persistent scrollable>
      <v-card v-if="taskTarget" rounded="xl">
        <v-card-title class="md-headline-small px-6 pt-6">Карточка</v-card-title>
        <v-card-text class="px-6 pt-2">
          <v-text-field
            v-model="taskTitle"
            label="название"
            variant="filled"
            density="comfortable"
            :readonly="!auth.isAuthed"
          />

          <div class="md-label-large mt-4 mb-2">Описание</div>
          <RichEditor
            v-model="taskBody"
            :readonly="!auth.isAuthed"
            placeholder="Опишите задачу — поддерживаются стили, списки, ссылки и блоки кода"
          />

          <div class="hh-attach__head mt-5 mb-2">
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
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-btn
            v-if="auth.isAuthed"
            color="error"
            variant="text"
            rounded="pill"
            @click="deleteCurrentTask"
          >
            Удалить карточку
          </v-btn>
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="taskDialog = false">Закрыть</v-btn>
          <v-btn
            v-if="auth.isAuthed"
            color="primary"
            variant="flat"
            rounded="pill"
            @click="saveTask"
          >
            Сохранить
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.hh-board {
  display: flex;
  flex-direction: column;
  height: calc(100vh - 64px);
  background:
    radial-gradient(1200px 600px at 0% 0%, rgba(var(--v-theme-primary), 0.05), transparent 60%),
    radial-gradient(1200px 600px at 100% 100%, rgba(var(--v-theme-tertiary), 0.05), transparent 60%),
    rgb(var(--v-theme-surface));
}
.hh-board__bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
}
.hh-board__title {
  display: inline-flex;
  align-items: baseline;
  gap: 10px;
  color: rgb(var(--v-theme-on-surface));
}
.hh-board__slug {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 13px;
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.hh-board__state {
  display: flex;
  justify-content: center;
  padding: 80px 0;
}
.hh-board__cols {
  flex: 1;
  display: flex;
  gap: 14px;
  padding: 8px 16px 20px;
  overflow-x: auto;
  overflow-y: hidden;
  align-items: stretch;
}

/* Attachments inside the task dialog */
.hh-attach__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.hh-attach__input {
  display: none;
}
.hh-attach__empty {
  padding: 16px;
  text-align: center;
  color: rgba(var(--v-theme-on-surface), 0.55);
  border: 1px dashed rgba(var(--v-theme-outline-variant), 0.7);
  border-radius: var(--md-shape-m);
}
.hh-attach__grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 10px;
}
.hh-attach {
  position: relative;
  background: rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.6);
  border-radius: var(--md-shape-m);
  overflow: hidden;
  display: flex;
  flex-direction: column;
}
.hh-attach__media {
  aspect-ratio: 16 / 10;
  background: rgb(var(--v-theme-surface-container-high));
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}
.hh-attach__media img,
.hh-attach__media video {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}
.hh-attach__file {
  color: rgba(var(--v-theme-on-surface), 0.6);
}
.hh-attach__meta {
  padding: 8px 10px 10px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.hh-attach__name {
  color: rgb(var(--v-theme-on-surface));
  text-decoration: none;
  font-weight: 500;
  white-space: nowrap;
  text-overflow: ellipsis;
  overflow: hidden;
}
.hh-attach__name:hover {
  color: rgb(var(--v-theme-primary));
}
.hh-attach__size {
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.hh-attach__remove {
  position: absolute;
  top: 4px;
  right: 4px;
  background: rgba(0, 0, 0, 0.45) !important;
  color: white !important;
}
</style>
