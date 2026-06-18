<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { combine } from '@atlaskit/pragmatic-drag-and-drop/combine'
import {
  draggable,
  dropTargetForElements,
} from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import { disableNativeDragPreview } from '@atlaskit/pragmatic-drag-and-drop/element/disable-native-drag-preview'

const props = defineProps<{
  columnKey: string
  title: string
  width: number
}>()

const emit = defineEmits<{
  (e: 'move', sourceKey: string, targetKey: string): void
  (e: 'resize', key: string, delta: number): void
}>()

const root = ref<HTMLElement | null>(null)
const dragging = ref(false)
const over = ref(false)
const resizing = ref(false)
let cleanup: (() => void) | null = null
let startX = 0

function onResizeStart(e: MouseEvent) {
  e.preventDefault()
  e.stopPropagation()
  resizing.value = true
  startX = e.clientX
  document.addEventListener('mousemove', onResizeMove)
  document.addEventListener('mouseup', onResizeEnd)
}

function onResizeMove(e: MouseEvent) {
  if (!resizing.value) return
  const delta = e.clientX - startX
  emit('resize', props.columnKey, delta)
  startX = e.clientX
}

function onResizeEnd() {
  resizing.value = false
  document.removeEventListener('mousemove', onResizeMove)
  document.removeEventListener('mouseup', onResizeEnd)
}

onMounted(() => {
  if (!root.value) return
  const element = root.value
  cleanup = combine(
    draggable({
      element,
      canDrag: () => !resizing.value,
      getInitialData: () => ({ type: 'list-column', key: props.columnKey }),
      onGenerateDragPreview: ({ nativeSetDragImage }) => {
        disableNativeDragPreview({ nativeSetDragImage })
      },
      onDragStart: () => {
        dragging.value = true
      },
      onDrop: () => {
        dragging.value = false
      },
    }),
    dropTargetForElements({
      element,
      canDrop: ({ source }) =>
        source.data.type === 'list-column' && source.data.key !== props.columnKey,
      getData: () => ({ type: 'list-column-target', key: props.columnKey }),
      onDragEnter: () => {
        over.value = true
      },
      onDragLeave: () => {
        over.value = false
      },
      onDrop: ({ source }) => {
        over.value = false
        const sourceKey = source.data.key
        if (typeof sourceKey === 'string') emit('move', sourceKey, props.columnKey)
      },
    }),
  )
})

onBeforeUnmount(() => {
  cleanup?.()
  document.removeEventListener('mousemove', onResizeMove)
  document.removeEventListener('mouseup', onResizeEnd)
})
</script>

<template>
  <div
    ref="root"
    class="ks-list-header"
    :class="{
      'ks-list-header--dragging': dragging,
      'ks-list-header--over': over,
      'ks-list-header--resizing': resizing,
    }"
  >
    <v-icon size="14" class="ks-list-header__drag">mdi-drag</v-icon>
    <span class="ks-list-header__title">{{ title }}</span>
    <div class="ks-list-header__resize" @mousedown="onResizeStart" />
  </div>
</template>

<style scoped>
.ks-list-header {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 100%;
  height: 100%;
  cursor: grab;
  position: relative;
  user-select: none;
}

.ks-list-header--dragging {
  opacity: 0.5;
}

.ks-list-header--over {
  background: rgba(var(--v-theme-secondary-container), 0.4);
  border-radius: var(--md-shape-xs);
}

.ks-list-header--resizing {
  cursor: col-resize;
}

.ks-list-header__drag {
  color: rgba(var(--v-theme-on-surface), 0.38);
  flex-shrink: 0;
}

.ks-list-header__title {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ks-list-header__resize {
  position: absolute;
  right: -3px;
  top: -4px;
  bottom: -4px;
  width: 6px;
  cursor: col-resize;
  z-index: 1;
}

.ks-list-header__resize:hover {
  background: rgba(var(--v-theme-on-surface), 0.15);
  border-radius: var(--md-shape-xs);
}
</style>
