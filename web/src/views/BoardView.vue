<script setup lang="ts">
import { computed, nextTick, provide, ref, watch } from 'vue'
import { storeToRefs } from 'pinia'
import { useRoute, useRouter, type LocationQueryRaw } from 'vue-router'
import { useDisplay } from 'vuetify'
import { useCrossColumnFlight } from '@/utils/taskFlight'
import { useAuthStore } from '@/stores/auth'
import { useBoardStore, type Column, type Task } from '@/stores/board'
import { useProjectsStore } from '@/stores/projects'
import { useBoardDnd } from '@/composables/useBoardDnd'
import BoardColumn from '@/components/board/BoardColumn.vue'
import BoardFilters from '@/components/board/BoardFilters.vue'
import BoardTaskDialog from '@/components/board/BoardTaskDialog.vue'
import BoardListView from '@/components/board/BoardListView.vue'
import BoardColumnDialogs from '@/components/board/BoardColumnDialogs.vue'
import { cssUrlImageOr } from '@/utils/css'
import { docPreview } from '@/utils/tiptap'

defineProps<{ slug?: string }>()

const route = useRoute()
const router = useRouter()
const { mobile: _mobile } = useDisplay()
const auth = useAuthStore()
const board = useBoardStore()
const projects = useProjectsStore()
const { viewMode, filtersExpanded } = storeToRefs(board)

useCrossColumnFlight(board)

const slug = computed(() => route.params.slug as string)
const loading = ref(true)
const error = ref<string | null>(null)
const colsScroll = ref<HTMLElement | null>(null)

useBoardDnd(colsScroll)

const VIEW_MODE_KEY_PREFIX = 'kaska.board.view_mode'
const FILTERS_EXPANDED_KEY_PREFIX = 'kaska.board.filters_expanded'
const filterQuery = ref('')
const filterTaskType = ref<string | null>(null)
const filterAssignee = ref<string | null>(null)
const filterStartDate = ref<string | null>(null)
const filterEndDate = ref<string | null>(null)
const syncingFiltersFromRoute = ref(false)

const deleteSnackOpen = ref(false)
const deleteSnackText = ref('')

const taskDialogRef = ref<InstanceType<typeof BoardTaskDialog> | null>(null)
const columnDialogsRef = ref<InstanceType<typeof BoardColumnDialogs> | null>(null)

function openTask(task: Task) {
  taskDialogRef.value?.open(task)
}

function onTaskDeletedByOther(text: string) {
  deleteSnackText.value = text
  deleteSnackOpen.value = true
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

load().then(() => {
  const flash = sessionStorage.getItem('kaska.flash.task_deleted')
  if (flash) {
    deleteSnackText.value = flash
    deleteSnackOpen.value = true
    sessionStorage.removeItem('kaska.flash.task_deleted')
  }
})

watch(slug, () => {
  load()
})

watch(
  () => [auth.user?.id ?? 'guest', slug.value] as const,
  ([userId, currentSlug]) => {
    const saved = localStorage.getItem(`${VIEW_MODE_KEY_PREFIX}:${userId}:${currentSlug}`)
    if (saved === 'columns' || saved === 'list') {
      board.viewMode = saved
      return
    }
    board.viewMode = 'columns'
  },
  { immediate: true },
)

watch(
  () => [auth.user?.id ?? 'guest', slug.value] as const,
  ([userId, currentSlug]) => {
    const saved = localStorage.getItem(`${FILTERS_EXPANDED_KEY_PREFIX}:${userId}:${currentSlug}`)
    if (saved === '1') board.filtersExpanded = true
    else if (saved === '0') board.filtersExpanded = false
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
  () => board.viewMode,
  (mode) => {
    const userId = auth.user?.id ?? 'guest'
    localStorage.setItem(`${VIEW_MODE_KEY_PREFIX}:${userId}:${slug.value}`, mode)
  },
)

watch(
  () => board.filtersExpanded,
  (expanded) => {
    const userId = auth.user?.id ?? 'guest'
    localStorage.setItem(
      `${FILTERS_EXPANDED_KEY_PREFIX}:${userId}:${slug.value}`,
      expanded ? '1' : '0',
    )
  },
)

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

function clearFilters() {
  filterQuery.value = ''
  filterTaskType.value = null
  filterAssignee.value = null
  filterStartDate.value = null
  filterEndDate.value = null
}

function openNewTask() {
  columnDialogsRef.value?.openNewTask()
}

function scrollToTask(taskId: string) {
  nextTick(() => {
    const el = document.querySelector(`[data-task-id="${taskId}"]`)
    el?.scrollIntoView({ behavior: 'smooth', block: 'center' })
  })
}

function openNewColumn() {
  columnDialogsRef.value?.openNewColumn()
}

provide('boardControls', {
  viewMode,
  filtersExpanded,
  openNewTask,
  openNewColumn,
  canWrite: computed(() => board.canWrite),
})

const accents = ['primary', 'secondary', 'tertiary'] as const
function accentFor(idx: number): 'primary' | 'secondary' | 'tertiary' {
  return accents[idx % accents.length]
}

const boardBackgroundStyle = computed(() => ({
  backgroundImage: cssUrlImageOr(board.project?.background_url),
}))

board.registerBoardCallbacks({ openNewTask, openNewColumn })
</script>

<template>
  <div class="ks-board" :class="{ 'ks-board--bg': !!board.project?.background_url }">
    <div
      v-if="board.project?.background_url"
      class="ks-board__bg"
      :style="boardBackgroundStyle"
    />
    <div v-if="board.project?.background_url" class="ks-board__bg-scrim" />

    <div
      class="ks-board__filters-shell"
      :class="{ 'is-open': board.filtersExpanded }"
      :aria-hidden="!board.filtersExpanded"
      :inert="!board.filtersExpanded"
    >
      <BoardFilters
        v-model:filter-query="filterQuery"
        v-model:filter-task-type="filterTaskType"
        v-model:filter-assignee="filterAssignee"
        v-model:filter-start-date="filterStartDate"
        v-model:filter-end-date="filterEndDate"
        @clear="clearFilters"
      />
    </div>

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

    <div v-else-if="board.viewMode === 'columns'" ref="colsScroll" class="ks-board__cols">
      <TransitionGroup name="ks-col-move">
        <BoardColumn
          v-for="(column, idx) in board.orderedColumns"
          :key="column.id"
          :column="column"
          :tasks="filteredTasks.filter((t) => t.column_id === column.id)"
          :accent="accentFor(idx)"
          @open-task="openTask"
          @rename="(c: Column) => columnDialogsRef?.onRename(c)"
          @delete="(c: Column) => columnDialogsRef?.onDeleteColumn(c)"
          @task-created="scrollToTask"
        />
      </TransitionGroup>
    </div>

    <BoardListView
      v-else-if="board.viewMode === 'list'"
      :filtered-tasks="filteredTasks"
      :slug="slug"
      @open-task="openTask"
    />

    <BoardColumnDialogs ref="columnDialogsRef" @task-created="scrollToTask" />
    <BoardTaskDialog ref="taskDialogRef" @task-deleted-by-other="onTaskDeletedByOther" />
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
.ks-board__filters-shell {
  display: grid;
  grid-template-rows: 0fr;
  padding: 0 16px;
  opacity: 0;
  transform: translateY(-4px);
  overflow: hidden;
  pointer-events: none;
  transition:
    grid-template-rows var(--md-duration-medium2) var(--md-easing-emphasized),
    padding-block var(--md-duration-medium2) var(--md-easing-emphasized),
    opacity var(--md-duration-short4) var(--md-easing-standard),
    transform var(--md-duration-medium2) var(--md-easing-emphasized);
  will-change: grid-template-rows, opacity, transform;
}
.ks-board__filters-shell.is-open {
  grid-template-rows: 1fr;
  padding-block: 12px;
  opacity: 1;
  transform: translateY(0);
  pointer-events: auto;
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
.ks-board__cols .ks-col-move-move {
  transition: transform var(--md-duration-medium4) var(--md-easing-emphasized);
}
.ks-board__cols .ks-col-move-enter-active {
  transition:
    opacity var(--md-duration-medium2) var(--md-easing-emphasized-decelerate),
    transform var(--md-duration-medium2) var(--md-easing-emphasized-decelerate);
}
.ks-board__cols .ks-col-move-enter-from {
  opacity: 0;
  transform: scale(0.97) translateY(8px);
}

@media (max-width: 600px) {
  .ks-board__cols {
    padding: 8px 12px 16px;
  }
}
</style>
