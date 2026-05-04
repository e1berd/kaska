<script setup lang="ts">
import { onMounted, onBeforeUnmount, ref } from 'vue'
import {
  draggable,
  dropTargetForElements,
} from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import {
  attachClosestEdge,
  extractClosestEdge,
  type Edge,
} from '@atlaskit/pragmatic-drag-and-drop-hitbox/closest-edge'
import { combine } from '@atlaskit/pragmatic-drag-and-drop/combine'
import type { Task } from '../../stores/board'

const props = defineProps<{ task: Task }>()
defineEmits<{ (e: 'open', task: Task): void }>()

const root = ref<HTMLElement | null>(null)
const dragging = ref(false)
const closestEdge = ref<Edge | null>(null)

let cleanup: (() => void) | null = null

onMounted(() => {
  if (!root.value) return
  const el = root.value

  cleanup = combine(
    draggable({
      element: el,
      getInitialData: () => ({ type: 'task', task: props.task }),
      onDragStart: () => (dragging.value = true),
      onDrop: () => (dragging.value = false),
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
    <div class="hh-card__title md-body-large">{{ task.title }}</div>
    <div v-if="task.description" class="hh-card__desc md-body-small">
      {{ task.description }}
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
.hh-card--dragging {
  opacity: 0.4;
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
.hh-card__edge {
  position: absolute;
  left: 6px;
  right: 6px;
  height: 3px;
  background: rgb(var(--v-theme-primary));
  border-radius: var(--md-shape-full);
  opacity: 0;
  transform: scaleX(0.4);
  transition:
    opacity var(--md-duration-short3) var(--md-easing-standard),
    transform var(--md-duration-short3) var(--md-easing-standard);
  pointer-events: none;
}
.hh-card__edge.is-on {
  opacity: 1;
  transform: scaleX(1);
}
.hh-card__edge--top {
  top: -5px;
}
.hh-card__edge--bottom {
  bottom: -5px;
}
</style>
