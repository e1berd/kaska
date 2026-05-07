<script setup lang="ts">
import { onMounted, onBeforeUnmount, ref } from 'vue'
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
import { useBoardStore, type Task } from '../../stores/board'
import { docPreview } from '../../utils/tiptap'

const board = useBoardStore()

const props = defineProps<{ task: Task }>()
defineEmits<{ (e: 'open', task: Task): void }>()

const preview = computed(() => docPreview(props.task.body_doc, 140))
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

const assignee = computed(() => {
  if (!props.task.assignee_id) return null
  return board.users.find(u => u.id === props.task.assignee_id) || null
})

const root = ref<HTMLElement | null>(null)
const dragging = ref(false)
const closestEdge = ref<Edge | null>(null)

let cleanup: (() => void) | null = null

// We bypass the browser's rasterised drag image entirely (it always looks
// blurry on hi-DPI screens) and instead show a live cloned DOM node that
// follows the cursor via `dragover` events. Crisp text, real shadows,
// no canvas snapshots involved.
let ghost: HTMLElement | null = null
let grabOffsetX = 0
let grabOffsetY = 0

function moveGhost(x: number, y: number) {
  if (!ghost) return
  ghost.style.transform = `translate3d(${x - grabOffsetX}px, ${y - grabOffsetY}px, 0)`
}

onMounted(() => {
  if (!root.value) return
  const el = root.value

  cleanup = combine(
    draggable({
      element: el,
      getInitialData: () => ({ type: 'task', task: props.task }),

      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        // Make the native drag image transparent so only our DOM follower
        // is visible while dragging.
        disableNativeDragPreview({ nativeSetDragImage })
      },

      onDragStart: ({ location }) => {
        dragging.value = true
        document.body.classList.add('hh-dragging')

        const rect = el.getBoundingClientRect()
        grabOffsetX = location.current.input.clientX - rect.left
        grabOffsetY = location.current.input.clientY - rect.top

        const clone = el.cloneNode(true) as HTMLElement
        clone.classList.add('hh-card--ghost')
        clone.style.width = `${rect.width}px`
        clone.style.height = `${rect.height}px`
        clone
          .querySelectorAll('.hh-card__edge')
          .forEach((node) => node.remove())
        document.body.appendChild(clone)
        ghost = clone

        moveGhost(location.current.input.clientX, location.current.input.clientY)
      },

      onDrag: ({ location }) => {
        moveGhost(location.current.input.clientX, location.current.input.clientY)
      },

      onDrop: () => {
        dragging.value = false
        document.body.classList.remove('hh-dragging')
        ghost?.remove()
        ghost = null
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
})

onBeforeUnmount(() => {
  cleanup?.()
})
</script>

<template>
  <div
    ref="root"
    class="hh-card md-state-layer"
    :class="{ 'hh-card--dragging': dragging }"
    :data-task-id="task.id"
    @click="$emit('open', task)"
  >
    <div v-if="firstImageUrl" class="hh-card__cover">
      <img :src="firstImageUrl" :alt="task.title" class="pointer-events-none" />
    </div>
    <div class="hh-card__title md-body-large">{{ task.title }}</div>
    <div v-if="preview" class="hh-card__desc md-body-small">{{ preview }}</div>
    <div v-if="attachmentCount > 0 || startDate || endDate || taskType" class="hh-card__meta">
      <span v-if="taskType" class="hh-card__chip" :style="{ backgroundColor: taskType.color, color: '#fff' }">
        {{ taskType.name }}
      </span>
      <span v-if="attachmentCount > 0" class="hh-card__chip">
        <v-icon size="14">mdi-paperclip</v-icon>
        {{ attachmentCount }}
      </span>
      <span v-if="startDate || endDate" class="hh-card__chip hh-card__dates">
        <v-icon size="14">mdi-calendar</v-icon>
        {{ startDate || '??' }} - {{ endDate || '??' }}
      </span>
    </div>

    <div v-if="assignee" class="mt-2 text-caption text-medium-emphasis d-flex align-center">
      <v-avatar :image="assignee.avatar_url || ''" size="20" class="mr-1" color="primary">
        <span v-if="!assignee.avatar_url" class="text-white" style="font-size: 10px">{{ assignee.display_name?.slice(0, 1).toUpperCase() || assignee.email.slice(0, 1).toUpperCase() }}</span>
      </v-avatar>
      {{ assignee.display_name || assignee.email }}
    </div>

    <div class="hh-card__edge hh-card__edge--top" :class="{ 'is-on': closestEdge === 'top' }" />
    <div class="hh-card__edge hh-card__edge--bottom" :class="{ 'is-on': closestEdge === 'bottom' }" />
  </div>
</template>

<style scoped>
.hh-card {
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
  --md-state-color: rgb(var(--v-theme-on-surface));
  transition:
    transform var(--md-duration-short4) var(--md-easing-standard),
    box-shadow var(--md-duration-short4) var(--md-easing-standard),
    opacity var(--md-duration-short3) var(--md-easing-standard);
  box-shadow: var(--md-elev-1);
}
.hh-card:hover {
  box-shadow: var(--md-elev-2);
}
.hh-card:active {
  cursor: grabbing;
}

/* The card the user is currently carrying — leave a quiet placeholder
 * (dashed outline, hidden content, no shadow) instead of a ghost copy. */
.hh-card--dragging {
  background: transparent !important;
  border: 1.5px dashed rgba(var(--v-theme-primary), 0.5) !important;
  box-shadow: none !important;
}
.hh-card--dragging > *:not(.hh-card__edge) {
  visibility: hidden;
}

/* Live DOM follower that tracks the cursor. Lives directly on <body>
 * (`:global` is required because we move it out of the component tree). */
:global(.hh-card.hh-card--ghost) {
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
}
/* No edge bars or overlays on the floating copy. */
:global(.hh-card--ghost .md-state-layer::after) {
  display: none;
}

/* During an active drag, freeze the cursor across the whole app. */
:global(body.hh-dragging),
:global(body.hh-dragging *) {
  cursor: grabbing !important;
  user-select: none !important;
}
.hh-card__title {
  font-weight: 500;
  line-height: 1.35;
  word-break: break-word;
}
.hh-card__desc {
  margin-top: 6px;
  color: rgba(var(--v-theme-on-surface), 0.62);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
/* Drop indicator: a 3px primary line + a small terminal dot on the leading
 * edge. The line is hidden until the closest-edge resolver flips `is-on`. */
.hh-card__edge {
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
.hh-card__edge::before {
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
.hh-card__edge.is-on {
  opacity: 1;
  transform: scaleX(1);
}
.hh-card__edge--top {
  top: -7px;
}
.hh-card__edge--bottom {
  bottom: -7px;
}
.hh-card__cover {
  margin: -12px -14px 10px;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  background: rgb(var(--v-theme-surface-container-high));
}
.hh-card__cover img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}
.hh-card__meta {
  margin-top: 8px;
  display: flex;
  gap: 6px;
}
.hh-card__chip {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  padding: 2px 8px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-surface-container));
  color: rgba(var(--v-theme-on-surface), 0.78);
  font-size: 12px;
  font-weight: 500;
}
</style>
