<script setup lang="ts">
import { onMounted, onBeforeUnmount, ref, useTemplateRef } from 'vue'
import {
  draggable,
  dropTargetForElements,
} from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import { disableNativeDragPreview } from '@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview'
import {
  attachClosestEdge,
  extractClosestEdge,
  type Edge,
} from '@atlaskit/pragmatic-drag-and-drop-hitbox/closest-edge'
import { combine } from '@atlaskit/pragmatic-drag-and-drop/combine'
import { computed } from 'vue'
import { useBoardStore, type Task } from '@/stores/board'
import {
  computeTaskPlacement,
  resetTouchDrag,
  touchDrag,
  type DropEdge,
  type TaskPlacement,
} from '@/utils/boardDnd'
import { docPreview } from '@/utils/tiptap'
import { cssColorOr } from '@/utils/css'

const board = useBoardStore()

const props = defineProps<{ task: Task }>()
const emit = defineEmits<{ (e: 'open', task: Task): void }>()

const preview = computed(() => docPreview(props.task.body_doc, 220))
const attachmentCount = computed(() => board.attachmentsFor(props.task.id).length)
const firstImageUrl = computed(() => {
  const first = board.attachmentsFor(props.task.id).find((a) => a.kind === 'image')
  return first?.url ?? null
})

const startDate = computed(() => {
  if (!props.task.start_date) return null
  return new Date(props.task.start_date).toLocaleDateString()
})

const endDate = computed(() => {
  if (!props.task.end_date) return null
  return new Date(props.task.end_date).toLocaleDateString()
})

const taskType = computed(() => {
  if (!props.task.task_type_id) return null
  return board.task_types.find(t => t.id === props.task.task_type_id) || null
})

const taskTypeChipStyle = computed(() => ({
  backgroundColor: cssColorOr(taskType.value?.color, '#757575'),
  color: '#fff',
}))

const assignee = computed(() => {
  if (!props.task.assignee_id) return null
  return board.users.find(u => u.id === props.task.assignee_id) || null
})

const root = useTemplateRef<HTMLElement>('root')
const dragging = ref(false)
const closestEdge = ref<Edge | null>(null)

const showTopEdge = computed(
  () =>
    closestEdge.value === 'top' ||
    (touchDrag.active && touchDrag.overTaskId === props.task.id && touchDrag.edge === 'top'),
)
const showBottomEdge = computed(
  () =>
    closestEdge.value === 'bottom' ||
    (touchDrag.active && touchDrag.overTaskId === props.task.id && touchDrag.edge === 'bottom'),
)

let cleanup: (() => void) | null = null

let ghost: HTMLElement | null = null
let grabOffsetX = 0
let grabOffsetY = 0

function moveGhost(x: number, y: number) {
  if (!ghost) return
  ghost.style.transform = `translate3d(${x - grabOffsetX}px, ${y - grabOffsetY}px, 0) scale(var(--ks-pickup, 1))`
}

type LandingPoint = { left: number; top: number }

function landingRect(el: HTMLElement, isTask: boolean, edge: Edge | null): LandingPoint | null {
  if (isTask) {
    const rect = el.getBoundingClientRect()
    return { left: rect.left, top: edge === 'bottom' ? rect.bottom + 10 : rect.top }
  }
  const list = el.querySelector('.ks-col__cards') as HTMLElement | null
  const cards = list
    ? (Array.from(
        list.querySelectorAll('.ks-card:not(.ks-card--ghost):not(.ks-card--dragging)'),
      ) as HTMLElement[])
    : []
  if (cards.length) {
    const r = cards[cards.length - 1].getBoundingClientRect()
    return { left: r.left, top: r.bottom + 10 }
  }
  if (list) {
    const r = list.getBoundingClientRect()
    return { left: r.left + 4, top: r.top + 4 }
  }
  return null
}

let dragResetTimer: ReturnType<typeof setTimeout> | null = null

function scheduleDragReset() {
  if (dragResetTimer) clearTimeout(dragResetTimer)
  dragResetTimer = setTimeout(() => {
    dragging.value = false
    dragResetTimer = null
  }, 1500)
}

function finishGhost(point: LandingPoint | null) {
  const g = ghost
  ghost = null
  if (!g) return
  if (!point) {
    g.remove()
    return
  }
  g.classList.add('ks-card--landing')
  requestAnimationFrame(() => {
    g.style.transform = `translate3d(${point.left}px, ${point.top}px, 0) scale(1)`
  })
  const done = () => g.remove()
  g.addEventListener('transitionend', done, { once: true })
  setTimeout(done, 420)
}

type DropTargetRecord = { element: Element; data: Record<string, unknown> }

function crossColumnLandingPoint(target: DropTargetRecord | undefined): LandingPoint | null {
  if (!target) return null
  if (target.data.type === 'task') {
    const overTask = target.data.task as Task
    if (overTask.column_id === props.task.column_id) return null
    return landingRect(target.element as HTMLElement, true, extractClosestEdge(target.data))
  }
  if (target.data.type === 'column') {
    if ((target.data.columnId as string) === props.task.column_id) return null
    return landingRect(target.element as HTMLElement, false, null)
  }
  return null
}

function touchLandingPoint(): LandingPoint | null {
  if (touchDrag.overTaskId) {
    const overTask = board.taskById(touchDrag.overTaskId)
    if (!overTask || overTask.column_id === props.task.column_id) return null
    const el = document.querySelector(
      `[data-task-id="${touchDrag.overTaskId}"]`,
    ) as HTMLElement | null
    return el ? landingRect(el, true, touchDrag.edge === 'bottom' ? 'bottom' : 'top') : null
  }
  if (touchDrag.overColumnId && touchDrag.overColumnId !== props.task.column_id) {
    const el = document.querySelector(
      `.ks-col[data-column-id="${touchDrag.overColumnId}"]`,
    ) as HTMLElement | null
    return el ? landingRect(el, false, null) : null
  }
  return null
}

const LONG_PRESS_MS = 600
const SCROLL_CANCEL_PX = 10
const AUTOSCROLL_EDGE = 64
const AUTOSCROLL_SPEED = 16

let pressTimer: ReturnType<typeof setTimeout> | null = null
let touchDragging = false
let suppressClick = false
let startX = 0
let startY = 0
let pointerX = 0
let pointerY = 0
let scrollRAF = 0
let placement: TaskPlacement | null = null

function clearPressTimer() {
  if (pressTimer) {
    clearTimeout(pressTimer)
    pressTimer = null
  }
}

function clearTouchIndicators() {
  touchDrag.overTaskId = null
  touchDrag.edge = null
  touchDrag.overColumnId = null
}

function updateTouchTarget() {
  const el = document.elementFromPoint(pointerX, pointerY) as HTMLElement | null
  if (!el) {
    placement = null
    clearTouchIndicators()
    return
  }

  const overCard = el.closest('[data-task-id]') as HTMLElement | null
  if (overCard) {
    const overId = overCard.getAttribute('data-task-id')
    if (!overId || overId === props.task.id) {
      placement = null
      clearTouchIndicators()
      return
    }
    const overTask = board.taskById(overId)
    if (!overTask) {
      placement = null
      clearTouchIndicators()
      return
    }
    const rect = overCard.getBoundingClientRect()
    const edge: DropEdge = pointerY < rect.top + rect.height / 2 ? 'top' : 'bottom'
    placement = computeTaskPlacement(board.tasksFor, props.task, {
      kind: 'task',
      task: overTask,
      edge,
    })
    touchDrag.overTaskId = overId
    touchDrag.edge = edge
    touchDrag.overColumnId = overTask.column_id
    return
  }

  const overColumn = el.closest('.ks-col') as HTMLElement | null
  const columnId = overColumn?.getAttribute('data-column-id') ?? null
  if (columnId) {
    placement = computeTaskPlacement(board.tasksFor, props.task, { kind: 'column', columnId })
    touchDrag.overTaskId = null
    touchDrag.edge = null
    touchDrag.overColumnId = columnId
    return
  }

  placement = null
  clearTouchIndicators()
}

function autoScrollStep() {
  if (!touchDragging) return
  const cols = document.querySelector('.ks-board__cols') as HTMLElement | null
  if (cols) {
    const r = cols.getBoundingClientRect()
    if (pointerX < r.left + AUTOSCROLL_EDGE) cols.scrollLeft -= AUTOSCROLL_SPEED
    else if (pointerX > r.right - AUTOSCROLL_EDGE) cols.scrollLeft += AUTOSCROLL_SPEED
  }
  const under = document.elementFromPoint(pointerX, pointerY) as HTMLElement | null
  const list = under?.closest('.ks-col__cards') as HTMLElement | null
  if (list) {
    const r = list.getBoundingClientRect()
    if (pointerY < r.top + AUTOSCROLL_EDGE) list.scrollTop -= AUTOSCROLL_SPEED
    else if (pointerY > r.bottom - AUTOSCROLL_EDGE) list.scrollTop += AUTOSCROLL_SPEED
  }
  scrollRAF = requestAnimationFrame(autoScrollStep)
}

function activateTouchDrag() {
  if (!root.value) return
  pressTimer = null
  touchDragging = true
  dragging.value = true
  navigator.vibrate?.(12)
  document.body.classList.add('ks-dragging')
  touchDrag.active = true
  touchDrag.sourceTaskId = props.task.id

  const el = root.value
  const rect = el.getBoundingClientRect()
  grabOffsetX = pointerX - rect.left
  grabOffsetY = pointerY - rect.top

  const clone = el.cloneNode(true) as HTMLElement
  clone.classList.add('ks-card--ghost')
  clone.style.width = `${rect.width}px`
  clone.style.height = `${rect.height}px`
  clone.querySelectorAll('.ks-card__edge').forEach((node) => node.remove())
  document.body.appendChild(clone)
  ghost = clone

  moveGhost(pointerX, pointerY)
  updateTouchTarget()
  scrollRAF = requestAnimationFrame(autoScrollStep)
}

function endTouchDrag(commit: boolean) {
  clearPressTimer()
  if (scrollRAF) {
    cancelAnimationFrame(scrollRAF)
    scrollRAF = 0
  }
  if (touchDragging && commit && placement) {
    board
      .moveTask(props.task.id, placement.columnId, placement.beforeId, placement.afterId)
      .catch((e) => console.warn('[board] touch move failed', e))
  }
  const point = touchDragging && commit ? touchLandingPoint() : null
  if (touchDragging) suppressClick = true
  touchDragging = false
  placement = null
  document.body.classList.remove('ks-dragging')
  finishGhost(point)
  if (point) scheduleDragReset()
  else dragging.value = false
  resetTouchDrag()
}

function onTouchStart(e: TouchEvent) {
  if (!board.canWrite || e.touches.length !== 1) {
    clearPressTimer()
    return
  }
  const t = e.touches[0]
  startX = pointerX = t.clientX
  startY = pointerY = t.clientY
  clearPressTimer()
  pressTimer = setTimeout(activateTouchDrag, LONG_PRESS_MS)
}

function onTouchMove(e: TouchEvent) {
  const t = e.touches[0]
  if (!t) return
  pointerX = t.clientX
  pointerY = t.clientY

  if (!touchDragging) {
    if (Math.hypot(pointerX - startX, pointerY - startY) > SCROLL_CANCEL_PX) {
      clearPressTimer()
    }
    return
  }

  e.preventDefault()
  moveGhost(pointerX, pointerY)
  updateTouchTarget()
}

function onTouchEnd() {
  endTouchDrag(true)
}

function onTouchCancel() {
  endTouchDrag(false)
}

function onCardClick() {
  if (suppressClick) {
    suppressClick = false
    return
  }
  emit('open', props.task)
}

onMounted(() => {
  if (!root.value) return
  const el = root.value

  cleanup = combine(
    draggable({
      element: el,
      getInitialData: () => ({ type: 'task', task: props.task }),

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage })
      },

      onDragStart: ({ location }) => {
        dragging.value = true
        document.body.classList.add('ks-dragging')

        const rect = el.getBoundingClientRect()
        grabOffsetX = location.current.input.clientX - rect.left
        grabOffsetY = location.current.input.clientY - rect.top

        const clone = el.cloneNode(true) as HTMLElement
        clone.classList.add('ks-card--ghost')
        clone.style.width = `${rect.width}px`
        clone.style.height = `${rect.height}px`
        clone
          .querySelectorAll('.ks-card__edge')
          .forEach((node) => node.remove())
        document.body.appendChild(clone)
        ghost = clone

        moveGhost(location.current.input.clientX, location.current.input.clientY)
      },

      onDrag: ({ location }) => {
        moveGhost(location.current.input.clientX, location.current.input.clientY)
      },

      onDrop: ({ location }) => {
        document.body.classList.remove('ks-dragging')
        const point = crossColumnLandingPoint(location.current.dropTargets[0])
        finishGhost(point)
        if (point) scheduleDragReset()
        else dragging.value = false
      },
    }),
    dropTargetForElements({
      element: el,
      canDrop: ({ source }) => source.data.type === 'task',
      getData: ({ input, element }) =>
        attachClosestEdge(
          { type: 'task', task: props.task },
          { input, element, allowedEdges: ['top', 'bottom'] },
        ),
      getIsSticky: () => true,
      onDrag: ({ self, source }) => {
        const sourceTask = source.data.task as Task | undefined
        if (sourceTask?.id === props.task.id) {
          closestEdge.value = null
          return
        }
        closestEdge.value = extractClosestEdge(self.data)
      },
      onDragLeave: () => (closestEdge.value = null),
      onDrop: () => (closestEdge.value = null),
    }),
  )

  el.addEventListener('touchstart', onTouchStart, { passive: true })
  el.addEventListener('touchmove', onTouchMove, { passive: false })
  el.addEventListener('touchend', onTouchEnd, { passive: true })
  el.addEventListener('touchcancel', onTouchCancel, { passive: true })
})

onBeforeUnmount(() => {
  cleanup?.()
  if (dragResetTimer) clearTimeout(dragResetTimer)
  const el = root.value
  if (el) {
    el.removeEventListener('touchstart', onTouchStart)
    el.removeEventListener('touchmove', onTouchMove)
    el.removeEventListener('touchend', onTouchEnd)
    el.removeEventListener('touchcancel', onTouchCancel)
  }
  if (touchDragging) endTouchDrag(false)
})
</script>

<template>
  <div
    ref="root"
    class="ks-card md-state-layer"
    :class="{ 'ks-card--dragging': dragging }"
    :data-task-id="task.id"
    @click="onCardClick"
  >
    <div v-if="firstImageUrl" class="ks-card__cover">
      <img :src="firstImageUrl" :alt="task.title" class="pointer-events-none" />
    </div>
    <div class="ks-card__title md-body-large">{{ task.title }}</div>
    <div v-if="preview" class="ks-card__preview md-body-small">{{ preview }}</div>
    <div v-if="attachmentCount > 0 || startDate || endDate || taskType" class="ks-card__meta">
      <span v-if="taskType" class="ks-card__chip" :style="taskTypeChipStyle">
        {{ taskType.name }}
      </span>
      <span v-if="attachmentCount > 0" class="ks-card__chip">
        <v-icon size="14">mdi-paperclip</v-icon>
        {{ attachmentCount }}
      </span>
      <span v-if="startDate || endDate" class="ks-card__chip ks-card__dates">
        <v-icon size="14">mdi-calendar</v-icon>
        {{ startDate || '??' }} - {{ endDate || '??' }}
      </span>
    </div>

    <div v-if="assignee" class="ks-card__assignee mt-2 text-caption text-medium-emphasis d-flex align-center">
      <v-avatar size="20" class="mr-1 flex-shrink-0" color="primary">
        <v-img v-if="assignee.avatar_url" :src="assignee.avatar_url" cover alt="" />
        <span v-else class="text-white" style="font-size: 10px">{{ assignee.display_name?.slice(0, 1).toUpperCase() || assignee.email.slice(0, 1).toUpperCase() }}</span>
      </v-avatar>
      <span class="ks-card__assignee-label">{{ assignee.display_name || assignee.email }}</span>
    </div>

    <div class="ks-card__edge ks-card__edge--top" :class="{ 'is-on': showTopEdge }" />
    <div class="ks-card__edge ks-card__edge--bottom" :class="{ 'is-on': showBottomEdge }" />
  </div>
</template>

<style scoped>
.ks-card__assignee {
  min-width: 0;
}
.ks-card__assignee-label {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ks-card {
  position: relative;
  background: rgb(var(--v-theme-surface-container-lowest));
  color: rgb(var(--v-theme-on-surface));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.6);
  border-radius: var(--md-shape-m);
  & img {
    border-top-left-radius: var(--md-shape-m);
    border-top-right-radius: var(--md-shape-m);
  }
  padding: 12px 14px;
  cursor: grab;
  user-select: none;
  -webkit-touch-callout: none;
  --md-state-color: rgb(var(--v-theme-on-surface));
  transition:
    transform var(--md-duration-short4) var(--md-easing-standard),
    box-shadow var(--md-duration-short4) var(--md-easing-standard),
    opacity var(--md-duration-short3) var(--md-easing-standard);
  box-shadow: var(--md-elev-1);
}
.ks-card:hover {
  box-shadow: var(--md-elev-2);
}
.ks-card:active {
  cursor: grabbing;
}

.ks-card--dragging {
  background: transparent !important;
  border: 1.5px dashed rgba(var(--v-theme-primary), 0.5) !important;
  box-shadow: none !important;
}
.ks-card--dragging > *:not(.ks-card__edge) {
  visibility: hidden;
}

:global(.ks-card.ks-card--ghost) {
  position: fixed !important;
  left: 0;
  top: 0;
  z-index: 9999;
  pointer-events: none;
  background: rgb(var(--v-theme-surface-container-lowest));
  color: rgb(var(--v-theme-on-surface));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.7);
  border-radius: var(--md-shape-m);
  padding: 12px 14px;
  box-shadow: var(--md-elev-4);
  transition: none !important;
  transform-origin: 16px 16px;
  will-change: transform;
  animation: ks-dnd-pickup var(--md-duration-medium2) var(--md-easing-emphasized-decelerate) both;
}
:global(.ks-card.ks-card--landing) {
  transition: transform var(--md-duration-medium2) var(--md-easing-emphasized) !important;
  animation: none !important;
}
:global(.ks-card.ks-card--flying-clone) {
  opacity: 1 !important;
  animation: none !important;
  transition: none !important;
}
:global(.ks-card--ghost .md-state-layer::after) {
  display: none;
}

:global(body.ks-dragging),
:global(body.ks-dragging *) {
  cursor: grabbing !important;
  user-select: none !important;
}
.ks-card__title {
  font-weight: 500;
  line-height: 1.35;
  word-break: break-word;
}
.ks-card__preview {
  margin-top: 4px;
  color: rgba(var(--v-theme-on-surface), 0.7);
  line-height: 1.4;
  word-break: break-word;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.ks-card__edge {
  position: absolute;
  left: 4px;
  right: 4px;
  height: 3px;
  background: rgb(var(--v-theme-primary));
  border-radius: var(--md-shape-full);
  opacity: 0;
  transform: scaleX(0.6);
  transform-origin: left center;
  transition:
    opacity var(--md-duration-short3) var(--md-easing-standard),
    transform var(--md-duration-short3) var(--md-easing-standard);
  pointer-events: none;
}
.ks-card__edge::before {
  content: '';
  position: absolute;
  left: -3px;
  top: 50%;
  transform: translateY(-50%);
  width: 9px;
  height: 9px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-primary));
  box-shadow: 0 0 0 2px rgb(var(--v-theme-surface-container));
}
.ks-card__edge.is-on {
  opacity: 1;
  transform: scaleX(1);
}
.ks-card__edge--top {
  top: -7px;
}
.ks-card__edge--bottom {
  bottom: -7px;
}
.ks-card__cover {
  margin: -12px -14px 10px;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  background: rgb(var(--v-theme-surface-container-high));
}
.ks-card__cover img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}
.ks-card__meta {
  margin-top: 8px;
  display: flex;
  gap: 6px;
}
.ks-card__chip {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  padding: 2px 8px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-surface-container));
  color: rgba(var(--v-theme-on-surface), 0.78);
  font-size: 12px;
  font-weight: 500;
  &:not(.ks-card__dates) {
    max-height: 22px;
  }
}
</style>
