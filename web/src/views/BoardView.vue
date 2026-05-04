<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { monitorForElements } from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import { extractClosestEdge } from '@atlaskit/pragmatic-drag-and-drop-hitbox/closest-edge'
import { animate } from 'animejs'

import { useAuthStore } from '../stores/auth'
import { useBoardStore, type Column, type Task } from '../stores/board'
import { useProjectsStore } from '../stores/projects'
import BoardColumn from '../components/board/BoardColumn.vue'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const board = useBoardStore()
const projects = useProjectsStore()

const slug = computed(() => route.params.slug as string)
const loading = ref(true)
const error = ref<string | null>(null)
let monitorCleanup: (() => void) | null = null

// dialogs
const renameDialog = ref(false)
const renameTarget = ref<Column | null>(null)
const renameValue = ref('')

const deleteDialog = ref(false)
const deleteTarget = ref<Column | null>(null)

const taskDialog = ref(false)
const taskTarget = ref<Task | null>(null)
const taskTitle = ref('')
const taskDescription = ref('')

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

  monitorCleanup = monitorForElements({
    canMonitor: ({ source }) => source.data.type === 'task',
    onDrop: ({ source, location }) => {
      const target = location.current.dropTargets[0]
      if (!target) return

      const sourceTask = source.data.task as Task
      const positionsBefore = snapshotPositions()

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

      // skip true no-op (drop within same column at the exact same neighbours)
      const before = sourceTask.id
      void before

      board
        .moveTask(sourceTask.id, targetColumnId, beforeId, afterId)
        .then(async () => {
          await nextTick()
          flipAnimate(positionsBefore)
        })
        .catch((e) => {
          console.warn('[board] move failed', e)
        })
    },
  })
})

onBeforeUnmount(() => {
  monitorCleanup?.()
  board.leave()
})

watch(slug, () => {
  load()
})

function snapshotPositions(): Map<string, DOMRect> {
  const map = new Map<string, DOMRect>()
  document.querySelectorAll<HTMLElement>('[data-task-id]').forEach((el) => {
    const id = el.dataset.taskId
    if (id) map.set(id, el.getBoundingClientRect())
  })
  return map
}

function flipAnimate(before: Map<string, DOMRect>) {
  document.querySelectorAll<HTMLElement>('[data-task-id]').forEach((el) => {
    const id = el.dataset.taskId
    if (!id) return
    const prev = before.get(id)
    if (!prev) return
    const now = el.getBoundingClientRect()
    const dx = prev.left - now.left
    const dy = prev.top - now.top
    if (dx === 0 && dy === 0) return
    el.style.transform = `translate(${dx}px, ${dy}px)`
    el.style.transition = 'none'
    requestAnimationFrame(() => {
      el.style.removeProperty('transition')
      animate(el, {
        translateX: 0,
        translateY: 0,
        duration: 280,
        ease: 'cubicBezier(0.2, 0, 0, 1)',
      })
    })
  })
}

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
  taskDescription.value = task.description ?? ''
  taskDialog.value = true
}

async function saveTask() {
  if (!taskTarget.value) return
  try {
    await board.updateTask(taskTarget.value.id, {
      title: taskTitle.value.trim(),
      description: taskDescription.value.trim(),
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

    <div v-else class="hh-board__cols">
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

    <v-dialog v-model="taskDialog" max-width="640" persistent>
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
          <v-textarea
            v-model="taskDescription"
            label="описание"
            variant="filled"
            rows="5"
            auto-grow
            :readonly="!auth.isAuthed"
            density="comfortable"
            class="mt-3"
          />
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-btn
            v-if="auth.isAuthed"
            color="error"
            variant="text"
            rounded="pill"
            @click="deleteCurrentTask"
          >
            Удалить
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
</style>
