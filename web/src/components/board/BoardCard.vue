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
    class="board-card"
    :class="{ 'board-card--dragging': dragging }"
    :data-task-id="task.id"
    @click="$emit('open', task)"
  >
    <div class="board-card__title">{{ task.title }}</div>
    <div v-if="task.description" class="board-card__desc">{{ task.description }}</div>
    <div v-if="closestEdge === 'top'" class="board-card__edge board-card__edge--top" />
    <div v-if="closestEdge === 'bottom'" class="board-card__edge board-card__edge--bottom" />
  </div>
</template>

<style scoped>
.board-card {
  position: relative;
  background: rgb(var(--v-theme-surface-container-high));
  color: rgb(var(--v-theme-on-surface));
  border-radius: 12px;
  padding: 12px 14px;
  cursor: grab;
  user-select: none;
  transition:
    transform 200ms cubic-bezier(0.2, 0, 0, 1),
    box-shadow 200ms cubic-bezier(0.2, 0, 0, 1),
    opacity 150ms linear;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.08);
}
.board-card:hover {
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.12);
}
.board-card--dragging {
  opacity: 0.4;
  cursor: grabbing;
}
.board-card__title {
  font-weight: 500;
  line-height: 1.35;
}
.board-card__desc {
  margin-top: 4px;
  font-size: 0.86rem;
  color: rgba(var(--v-theme-on-surface), 0.62);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.board-card__edge {
  position: absolute;
  left: 4px;
  right: 4px;
  height: 2px;
  background: rgb(var(--v-theme-primary));
  border-radius: 2px;
}
.board-card__edge--top {
  top: -3px;
}
.board-card__edge--bottom {
  bottom: -3px;
}
</style>
