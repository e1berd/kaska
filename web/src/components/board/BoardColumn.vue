<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue'
import {
  draggable,
  dropTargetForElements,
} from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import { disableNativeDragPreview } from '@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview'
import { autoScrollForElements } from '@atlaskit/pragmatic-drag-and-drop-auto-scroll/element'
import { combine } from '@atlaskit/pragmatic-drag-and-drop/combine'
import {
  attachClosestEdge,
  extractClosestEdge,
  type Edge,
} from '@atlaskit/pragmatic-drag-and-drop-hitbox/closest-edge'
import { useBoardStore, type Column, type Task } from '../../stores/board'
import { useAuthStore } from '../../stores/auth'
import BoardCard from './BoardCard.vue'
import { PhDotsSix } from '@phosphor-icons/vue'

const PAGE_SIZE = 20

const props = defineProps<{
  column: Column
  accent: 'primary' | 'secondary' | 'tertiary'
  tasks?: Task[]
}>()
defineEmits<{
  (e: 'open-task', task: Task): void
  (e: 'rename', column: Column): void
  (e: 'delete', column: Column): void
}>()

const board = useBoardStore()
const auth = useAuthStore()
const tasksInColumn = computed(() =>
  props.tasks
    ? props.tasks.slice().sort((a, b) => (a.rank < b.rank ? -1 : a.rank > b.rank ? 1 : 0))
    : board.tasksFor(props.column.id),
)

const visibleCount = ref(PAGE_SIZE)

const visibleTasks = computed(() => tasksInColumn.value.slice(0, visibleCount.value))
const hasMore = computed(() => visibleCount.value < tasksInColumn.value.length)

watch(
  () => tasksInColumn.value.length,
  (len) => {
    if (visibleCount.value < len && len <= PAGE_SIZE) {
      visibleCount.value = len
    }
  },
)

function loadMore() {
  visibleCount.value = Math.min(visibleCount.value + PAGE_SIZE, tasksInColumn.value.length)
}

const sentinel = ref<HTMLElement | null>(null)
let sentinelObserver: IntersectionObserver | null = null

function attachSentinel(el: HTMLElement) {
  sentinelObserver?.disconnect()
  sentinelObserver = new IntersectionObserver(
    (entries) => {
      if (entries[0]?.isIntersecting) loadMore()
    },
    { threshold: 0.1 },
  )
  sentinelObserver.observe(el)
}

watch(sentinel, (el) => {
  if (el) attachSentinel(el)
  else sentinelObserver?.disconnect()
})

const root = ref<HTMLElement | null>(null)
const handle = ref<HTMLElement | null>(null)
const cardsScroll = ref<HTMLElement | null>(null)
const isOver = ref(false)
const dragging = ref(false)
const closestEdge = ref<Edge | null>(null)
let dndCleanup: (() => void) | null = null
let ghost: HTMLElement | null = null
let grabOffsetX = 0
let grabOffsetY = 0

const adding = ref(false)
const newTitle = ref('')
const submitting = ref(false)

onMounted(() => {
  if (!root.value || !cardsScroll.value || !handle.value) return
  const rootEl = root.value
  const handleEl = handle.value

  dndCleanup = combine(
    draggable({
      element: handleEl,
      getInitialData: () => ({ type: 'column', column: props.column }),
      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage })
      },
      onDragStart: ({ location }) => {
        const rect = rootEl.getBoundingClientRect()
        dragging.value = true
        document.body.classList.add('hh-dragging-column')
        grabOffsetX = location.current.input.clientX - rect.left
        grabOffsetY = location.current.input.clientY - rect.top
        const clone = rootEl.cloneNode(true) as HTMLElement
        clone.classList.add('hh-col--ghost')
        clone.style.width = `${rect.width}px`
        clone.style.height = `${rect.height}px`
        clone.querySelectorAll('.hh-col__edge').forEach((node) => node.remove())
        document.body.appendChild(clone)
        ghost = clone
        ghost.style.transform = `translate3d(${location.current.input.clientX - grabOffsetX}px, ${location.current.input.clientY - grabOffsetY}px, 0)`
      },
      onDrag: ({ location }) => {
        if (!ghost) return
        ghost.style.transform = `translate3d(${location.current.input.clientX - grabOffsetX}px, ${location.current.input.clientY - grabOffsetY}px, 0)`
      },
      onDrop: () => {
        dragging.value = false
        document.body.classList.remove('hh-dragging-column')
        ghost?.remove()
        ghost = null
      },
    }),
    dropTargetForElements({
      element: rootEl,
      canDrop: ({ source }) => source.data.type === 'task' || source.data.type === 'column',
      getData: ({ source, input, element }) => {
        if (source.data.type === 'column') {
          return attachClosestEdge(
            { type: 'column', column: props.column },
            { input, element, allowedEdges: ['left', 'right'] },
          )
        }
        return { type: 'column', columnId: props.column.id }
      },
      getIsSticky: () => true,
      onDragEnter: () => (isOver.value = true),
      onDragLeave: () => {
        isOver.value = false
        closestEdge.value = null
      },
      onDrag: ({ self, source }) => {
        if (source.data.type !== 'column') {
          closestEdge.value = null
          return
        }
        const sourceColumn = source.data.column as Column | undefined
        if (sourceColumn?.id === props.column.id) {
          closestEdge.value = null
          return
        }
        closestEdge.value = extractClosestEdge(self.data)
      },
      onDrop: () => {
        isOver.value = false
        closestEdge.value = null
      },
    }),
    autoScrollForElements({
      element: cardsScroll.value,
      canScroll: ({ source }) => source.data.type === 'task',
    }),
  )
})

onBeforeUnmount(() => {
  dndCleanup?.()
  sentinelObserver?.disconnect()
  closestEdge.value = null
  isOver.value = false
  dragging.value = false
  document.body.classList.remove('hh-dragging-column')
  ghost?.remove()
  ghost = null
})

function startAdd() {
  adding.value = true
  newTitle.value = ''
}

async function commitAdd() {
  const title = newTitle.value.trim()
  if (!title) {
    adding.value = false
    return
  }
  submitting.value = true
  try {
    await board.createTask(props.column.id, { title })
    newTitle.value = ''
    visibleCount.value = Math.max(visibleCount.value, tasksInColumn.value.length)
  } catch (e) {
    console.warn('[board] create task failed', e)
  } finally {
    submitting.value = false
  }
}

function cancelAdd() {
  adding.value = false
  newTitle.value = ''
}
</script>

<template>
  <section
    ref="root"
    class="hh-col"
    :class="{ 'hh-col--over': isOver, 'hh-col--dragging': dragging }"
    :data-accent="accent"
  >
    <header class="hh-col__head">
      <div class="hh-col__title">
        <button ref="handle" class="hh-col__drag-handle md-state-layer" type="button" aria-label="Перетащить колонку">
          <PhDotsSix />
        </button>
        <span class="hh-col__dot" />
        <span class="md-title-medium">{{ column.name }}</span>
        <span class="hh-col__count md-label-medium">{{ tasksInColumn.length }}</span>
      </div>
      <v-menu v-if="auth.isAuthed">
        <template #activator="{ props: act }">
          <v-btn
            v-bind="act"
            icon="mdi-dots-vertical"
            variant="text"
            density="comfortable"
            size="small"
            class="hh-col__menu"
          />
        </template>
        <v-list density="compact" rounded="lg">
          <v-list-item @click="$emit('rename', column)" prepend-icon="mdi-pencil-outline">
            <v-list-item-title>Переименовать</v-list-item-title>
          </v-list-item>
          <v-list-item @click="$emit('delete', column)" prepend-icon="mdi-trash-can-outline">
            <v-list-item-title>Удалить</v-list-item-title>
          </v-list-item>
        </v-list>
      </v-menu>
    </header>

    <div ref="cardsScroll" class="hh-col__cards">
      <BoardCard
        v-for="task in visibleTasks"
        :key="task.id"
        :task="task"
        @open="$emit('open-task', $event)"
      />

      <div v-if="hasMore" ref="sentinel" class="hh-col__sentinel">
        <v-progress-circular indeterminate size="20" width="2" color="primary" />
      </div>

      <div v-if="!tasksInColumn.length" class="hh-col__empty md-body-small">
        Перетащите карточку сюда
      </div>
    </div>

    <div v-if="auth.isAuthed" class="hh-col__add">
      <template v-if="!adding">
        <button class="hh-col__addbtn md-state-layer" type="button" @click="startAdd">
          <v-icon size="18">mdi-plus</v-icon>
          <span class="md-label-large">Добавить карточку</span>
        </button>
      </template>
      <template v-else>
        <v-textarea
          v-model="newTitle"
          autofocus
          rows="2"
          auto-grow
          variant="outlined"
          density="comfortable"
          rounded="lg"
          :disabled="submitting"
          placeholder="Название карточки…"
          hide-details
          @keydown.enter.exact.prevent="commitAdd"
          @keydown.escape.prevent="cancelAdd"
        />
        <div class="d-flex ga-2 mt-2">
          <v-btn
            color="primary"
            variant="flat"
            density="comfortable"
            rounded="pill"
            :loading="submitting"
            @click="commitAdd"
          >
            Добавить
          </v-btn>
          <v-btn
            variant="text"
            density="comfortable"
            rounded="pill"
            :disabled="submitting"
            @click="cancelAdd"
          >
            Отмена
          </v-btn>
        </div>
      </template>
    </div>
    <div class="hh-col__edge hh-col__edge--left" :class="{ 'is-on': closestEdge === 'left' }" />
    <div class="hh-col__edge hh-col__edge--right" :class="{ 'is-on': closestEdge === 'right' }" />
  </section>
</template>

<style scoped>
.hh-col {
  --col-accent: var(--v-theme-primary);
  --col-accent-container: var(--v-theme-primary-container);
  --col-accent-on-container: var(--v-theme-on-primary-container);

  position: relative;
  display: flex;
  flex-direction: column;
  width: 296px;
  flex: 0 0 auto;
  height: 100%;
  background: rgb(var(--v-theme-surface-container));
  border-radius: var(--md-shape-l);
  padding: 12px;
  transition:
    background-color var(--md-duration-short4) var(--md-easing-standard),
    box-shadow var(--md-duration-short4) var(--md-easing-standard),
    opacity var(--md-duration-short3) var(--md-easing-standard);
}
.hh-col[data-accent='secondary'] {
  --col-accent: var(--v-theme-secondary);
  --col-accent-container: var(--v-theme-secondary-container);
  --col-accent-on-container: var(--v-theme-on-secondary-container);
}
.hh-col[data-accent='tertiary'] {
  --col-accent: var(--v-theme-tertiary);
  --col-accent-container: var(--v-theme-tertiary-container);
  --col-accent-on-container: var(--v-theme-on-tertiary-container);
}
.hh-col--over {
  background: rgb(var(--v-theme-surface-container-high));
  box-shadow: inset 0 0 0 1.5px rgba(var(--col-accent), 0.55);
}
.hh-col--dragging {
  opacity: 0.52;
}

.hh-col__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 4px 6px 8px;
  flex-shrink: 0;
}

.hh-col__title {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: rgb(var(--v-theme-on-surface));
}
.hh-col__drag-handle {
  width: 28px;
  height: 28px;
  border: none;
  border-radius: var(--md-shape-full);
  background: rgba(var(--v-theme-on-surface), 0.06);
  color: rgba(var(--v-theme-on-surface), 0.72);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: grab;
  flex: 0 0 auto;
  --md-state-color: rgb(var(--v-theme-on-surface));
  transition:
    background-color var(--md-duration-short3) var(--md-easing-standard),
    color var(--md-duration-short3) var(--md-easing-standard);
}
.hh-col__drag-handle:hover {
  background: rgba(var(--v-theme-on-surface), 0.12);
  color: rgb(var(--v-theme-on-surface));
}
.hh-col__drag-handle:active {
  cursor: grabbing;
}
.hh-col__dot {
  width: 10px;
  height: 10px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--col-accent));
}
.hh-col__count {
  margin-left: 6px;
  padding: 2px 8px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--col-accent-container));
  color: rgb(var(--col-accent-on-container));
}

.hh-col__cards {
  display: flex;
  flex-direction: column;
  gap: 10px;
  flex: 1 1 0;
  min-height: 0;
  overflow-y: auto;
  scrollbar-width: thin;
  scrollbar-color: rgba(var(--v-theme-on-surface), 0.18) transparent;
  padding: 4px 4px 8px;
}
.hh-col__cards::-webkit-scrollbar {
  width: 5px;
}
.hh-col__cards::-webkit-scrollbar-thumb {
  border-radius: 99px;
  background: rgba(var(--v-theme-on-surface), 0.18);
}

.hh-col__sentinel {
  display: flex;
  justify-content: center;
  padding: 8px 0 4px;
}

.hh-col__empty {
  text-align: center;
  padding: 24px 8px;
  color: rgba(var(--v-theme-on-surface), 0.45);
  border: 1.5px dashed rgba(var(--v-theme-outline-variant), 0.8);
  border-radius: var(--md-shape-m);
  transition:
    border-color var(--md-duration-short3) var(--md-easing-standard),
    background-color var(--md-duration-short3) var(--md-easing-standard),
    color var(--md-duration-short3) var(--md-easing-standard);
}
.hh-col--over .hh-col__empty {
  border-color: rgb(var(--col-accent));
  background: rgba(var(--col-accent), 0.08);
  color: rgba(var(--v-theme-on-surface), 0.7);
}

.hh-col__add {
  margin-top: 4px;
  flex-shrink: 0;
}
.hh-col__addbtn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  width: 100%;
  padding: 10px 12px;
  border: none;
  border-radius: var(--md-shape-m);
  background: transparent;
  color: rgb(var(--v-theme-on-surface));
  cursor: pointer;
  --md-state-color: rgb(var(--v-theme-on-surface));
  transition: background-color var(--md-duration-short3) var(--md-easing-standard);
}
.hh-col__addbtn:hover {
  background: rgba(var(--v-theme-on-surface), 0.04);
}
.hh-col__edge {
  position: absolute;
  top: 14px;
  bottom: 14px;
  width: 4px;
  border-radius: var(--md-shape-full);
  background: rgba(var(--v-theme-primary), 0.92);
  opacity: 0;
  transform: scaleY(0.6);
  transition:
    opacity var(--md-duration-short2) var(--md-easing-standard),
    transform var(--md-duration-short3) var(--md-easing-standard);
  pointer-events: none;
}
.hh-col__edge--left {
  left: -8px;
}
.hh-col__edge--right {
  right: -8px;
}
.hh-col__edge.is-on {
  opacity: 1;
  transform: scaleY(1);
}
:global(.hh-col.hh-col--ghost) {
  position: fixed !important;
  left: 0;
  top: 0;
  z-index: 9999;
  pointer-events: none;
  box-shadow: var(--md-elev-5);
  opacity: 0.96;
  transition: none !important;
  will-change: transform;
}
:global(body.hh-dragging-column) {
  cursor: grabbing;
}
</style>
