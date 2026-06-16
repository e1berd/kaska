<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useBoardStore, type Task, type TaskComment } from '@/stores/board'
import { useProjectsStore } from '@/stores/projects'
import { docPreview } from '@/utils/tiptap'

defineProps<{ slug?: string }>()

type HistoryEntry = {
  id: string
  at: string
  title: string
  detail: string
  taskId?: string
}

const route = useRoute()
const router = useRouter()
const board = useBoardStore()
const projects = useProjectsStore()
const loading = ref(true)
const error = ref<string | null>(null)

const slug = computed(() => route.params.slug as string)

const columnNames = computed(() => {
  return new Map(board.columns.map((column) => [column.id, column.name]))
})

const entries = computed<HistoryEntry[]>(() => {
  const taskEntries = board.tasks.flatMap((task) => taskHistoryEntries(task))
  const commentEntries = board.taskComments.map(commentHistoryEntry)

  return [...taskEntries, ...commentEntries].sort((a, b) => {
    return Date.parse(b.at) - Date.parse(a.at)
  })
})

onMounted(async () => {
  try {
    await projects.joinLobby()
    await board.joinBySlug(slug.value)
  } catch (err: unknown) {
    const reason = (err as { reason?: string })?.reason
    if (reason === 'not_found') {
      router.replace({ name: 'not-found' })
      return
    }
    error.value = 'Не удалось открыть историю проекта'
  } finally {
    loading.value = false
  }
})

function taskHistoryEntries(task: Task): HistoryEntry[] {
  const result: HistoryEntry[] = []
  if (task.inserted_at) {
    result.push({
      id: `task-created-${task.id}`,
      at: task.inserted_at,
      title: 'Создана задача',
      detail: task.title,
      taskId: task.id,
    })
  }

  if (task.updated_at && task.updated_at !== task.inserted_at) {
    result.push({
      id: `task-updated-${task.id}`,
      at: task.updated_at,
      title: 'Обновлена задача',
      detail: `${task.title} · ${columnNames.value.get(task.column_id) ?? 'статус неизвестен'}`,
      taskId: task.id,
    })
  }

  return result
}

function commentHistoryEntry(comment: TaskComment): HistoryEntry {
  const task = board.tasks.find((candidate) => candidate.id === comment.task_id)
  const author = comment.author_display_name || comment.author_email || comment.guest_name || 'Гость'
  const text = comment.body_doc ? docPreview(comment.body_doc, 120) : comment.body

  return {
    id: `comment-${comment.id}`,
    at: comment.inserted_at ?? '',
    title: comment.parent_id ? 'Ответ в комментариях' : 'Комментарий',
    detail: `${author}: ${text || task?.title || 'без текста'}`,
    taskId: comment.task_id,
  }
}

function fmtDate(iso: string): string {
  if (!iso) return ''
  return new Date(iso).toLocaleString()
}

function openTask(entry: HistoryEntry) {
  if (!entry.taskId) return
  router.push({ name: 'task', params: { slug: slug.value, taskId: entry.taskId } })
}
</script>

<template>
  <div class="ks-history-wrapper">
    <main class="ks-history">
    <header class="ks-history__head">
      <div>
        <h1 class="md-headline-medium mb-1">История</h1>
        <p class="md-body-medium text-medium-emphasis ma-0">
          Журнал изменений и обсуждений проекта.
        </p>
      </div>
    </header>

    <div v-if="loading" class="ks-history__state">
      <v-progress-circular indeterminate color="primary" />
    </div>
    <v-alert v-else-if="error" type="error" variant="tonal" rounded="lg">
      {{ error }}
    </v-alert>
    <div v-else-if="!entries.length" class="ks-history__empty">
      <v-icon size="32">mdi-history</v-icon>
      <span class="md-body-medium">История пока пуста.</span>
    </div>
    <div v-else class="ks-history__list">
      <button
        v-for="entry in entries"
        :key="entry.id"
        type="button"
        class="ks-history__item md-state-layer"
        @click="openTask(entry)"
      >
        <span class="ks-history__dot" />
        <span class="ks-history__body">
          <span class="ks-history__title md-title-small">{{ entry.title }}</span>
          <span class="ks-history__detail md-body-medium">{{ entry.detail }}</span>
        </span>
        <time class="ks-history__time md-label-medium">{{ fmtDate(entry.at) }}</time>
      </button>
    </div>
    </main>
  </div>
</template>

<style scoped>
.ks-history-wrapper {
  flex: 1 1 0;
  min-height: 0;
  overflow-y: auto;
}

.ks-history {
  display: flex;
  flex-direction: column;
  gap: 20px;
  width: min(920px, 100%);
  max-width: 100%;
  min-width: 0;
  margin: 0 auto;
  padding: 24px;
  overflow-x: hidden;
}

.ks-history__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-width: 0;
}

.ks-history__state,
.ks-history__empty {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  min-height: 220px;
  color: rgb(var(--v-theme-on-surface-variant));
}

.ks-history__list {
  position: relative;
  display: grid;
  gap: 8px;
  min-width: 0;
  overflow: hidden;
}

.ks-history__list::before {
  content: '';
  position: absolute;
  left: 10px;
  top: 12px;
  bottom: 12px;
  width: 2px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-outline-variant));
}

.ks-history__item {
  --md-state-color: rgb(var(--v-theme-on-surface));
  position: relative;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: start;
  gap: 14px;
  width: 100%;
  min-width: 0;
  padding: 12px 14px 12px 0;
  border: 0;
  border-radius: var(--md-shape-m);
  background: transparent;
  color: rgb(var(--v-theme-on-surface));
  text-align: left;
  cursor: pointer;
}

.ks-history__dot {
  position: relative;
  z-index: 1;
  width: 22px;
  height: 22px;
  margin-top: 2px;
  border: 4px solid rgb(var(--v-theme-surface));
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-primary));
}

.ks-history__body {
  display: grid;
  gap: 3px;
  min-width: 0;
}

.ks-history__title,
.ks-history__detail {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ks-history__detail,
.ks-history__time {
  color: rgb(var(--v-theme-on-surface-variant));
}

.ks-history__time {
  white-space: nowrap;
}

@media (max-width: 720px) {
  .ks-history {
    padding: 16px;
  }

  .ks-history__item {
    grid-template-columns: auto minmax(0, 1fr);
  }

  .ks-history__time {
    grid-column: 2;
  }
}
</style>
