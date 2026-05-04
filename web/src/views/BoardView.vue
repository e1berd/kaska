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
</script>

<template>
  <div class="board-view">
    <header class="board-view__bar">
      <v-btn icon="mdi-arrow-left" variant="text" @click="backToProjects" />
      <div class="board-view__title">
        <span class="text-h6">{{ board.project?.name ?? '…' }}</span>
        <span v-if="board.project" class="text-medium-emphasis">/{{ board.project.slug }}</span>
      </div>
      <v-spacer />
      <v-btn
        v-if="auth.isAuthed"
        prepend-icon="mdi-plus"
        variant="tonal"
        @click="openNewColumn"
      >
        Колонка
      </v-btn>
    </header>

    <div v-if="loading" class="pa-12 text-center text-medium-emphasis">Загрузка…</div>
    <v-alert v-else-if="error" type="error" variant="tonal" class="ma-4">{{ error }}</v-alert>

    <div v-else class="board-view__columns">
      <BoardColumn
        v-for="column in board.orderedColumns"
        :key="column.id"
        :column="column"
        @open-task="openTask"
        @rename="onRename"
        @delete="onDeleteColumn"
      />
    </div>

    <v-dialog v-model="renameDialog" max-width="420">
      <v-card>
        <v-card-title>Переименовать колонку</v-card-title>
        <v-card-text>
          <v-text-field v-model="renameValue" autofocus density="comfortable" />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="renameDialog = false">Отмена</v-btn>
          <v-btn color="primary" variant="flat" @click="commitRename">Сохранить</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="deleteDialog" max-width="420">
      <v-card>
        <v-card-title>Удалить колонку?</v-card-title>
        <v-card-text>
          Все её карточки тоже исчезнут. Действие нельзя отменить.
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="deleteDialog = false">Отмена</v-btn>
          <v-btn color="error" variant="flat" @click="commitDelete">Удалить</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="newColumnDialog" max-width="420">
      <v-card>
        <v-card-title>Новая колонка</v-card-title>
        <v-card-text>
          <v-text-field
            v-model="newColumnName"
            autofocus
            density="comfortable"
            label="название"
            @keydown.enter.exact.prevent="commitNewColumn"
          />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="newColumnDialog = false">Отмена</v-btn>
          <v-btn color="primary" variant="flat" @click="commitNewColumn">Создать</v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="taskDialog" max-width="600" persistent>
      <v-card v-if="taskTarget">
        <v-card-title>Карточка</v-card-title>
        <v-card-text>
          <v-text-field
            v-model="taskTitle"
            label="название"
            :readonly="!auth.isAuthed"
            density="comfortable"
          />
          <v-textarea
            v-model="taskDescription"
            label="описание"
            rows="5"
            auto-grow
            :readonly="!auth.isAuthed"
            density="comfortable"
            class="mt-2"
          />
        </v-card-text>
        <v-card-actions>
          <v-btn
            v-if="auth.isAuthed"
            color="error"
            variant="text"
            @click="deleteCurrentTask"
          >
            Удалить
          </v-btn>
          <v-spacer />
          <v-btn variant="text" @click="taskDialog = false">Закрыть</v-btn>
          <v-btn
            v-if="auth.isAuthed"
            color="primary"
            variant="flat"
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
.board-view {
  display: flex;
  flex-direction: column;
  height: calc(100vh - 64px);
}
.board-view__bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 16px;
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.08);
}
.board-view__title {
  display: inline-flex;
  align-items: baseline;
  gap: 8px;
}
.board-view__columns {
  flex: 1;
  display: flex;
  gap: 12px;
  padding: 16px;
  overflow-x: auto;
  overflow-y: hidden;
  align-items: stretch;
}
</style>
