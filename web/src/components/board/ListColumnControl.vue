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
let cleanup: (() => void) | null = null

onMounted(() => {
  if (!root.value) return
  const element = root.value
  cleanup = combine(
    draggable({
      element,
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
})
</script>

<template>
  <div
    ref="root"
    class="ks-list-col"
    :class="{ 'ks-list-col--dragging': dragging, 'ks-list-col--over': over }"
  >
    <v-icon size="18" class="ks-list-col__grab">mdi-drag</v-icon>
    <span class="ks-list-col__title md-label-medium">{{ title }}</span>
    <span class="ks-list-col__width md-label-small">{{ width }}</span>
    <v-btn
      icon="mdi-minus"
      variant="text"
      density="compact"
      size="x-small"
      @click.stop="emit('resize', columnKey, -40)"
    />
    <v-btn
      icon="mdi-plus"
      variant="text"
      density="compact"
      size="x-small"
      @click.stop="emit('resize', columnKey, 40)"
    />
  </div>
</template>

<style scoped>
.ks-list-col {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-width: 0;
  height: 36px;
  padding: 0 6px 0 10px;
  border: 1px solid rgb(var(--v-theme-outline-variant));
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-surface-container-low));
  color: rgb(var(--v-theme-on-surface));
  cursor: grab;
  transition:
    background-color var(--md-duration-short3) var(--md-easing-standard),
    opacity var(--md-duration-short3) var(--md-easing-standard);
}

.ks-list-col--dragging {
  opacity: 0.55;
}

.ks-list-col--over {
  background: rgb(var(--v-theme-secondary-container));
}

.ks-list-col__grab,
.ks-list-col__width {
  color: rgb(var(--v-theme-on-surface-variant));
}

.ks-list-col__title {
  max-width: 120px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
