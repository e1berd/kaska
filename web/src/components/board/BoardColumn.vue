<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref } from 'vue'
import { dropTargetForElements } from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import { useBoardStore, type Column, type Task } from '../../stores/board'
import { useAuthStore } from '../../stores/auth'
import BoardCard from './BoardCard.vue'

const props = defineProps<{ column: Column }>()
defineEmits<{
  (e: 'open-task', task: Task): void
  (e: 'rename', column: Column): void
  (e: 'delete', column: Column): void
}>()

const board = useBoardStore()
const auth = useAuthStore()
const tasksInColumn = computed(() => board.tasksFor(props.column.id))

const root = ref<HTMLElement | null>(null)
const isOver = ref(false)
let cleanup: (() => void) | null = null

const adding = ref(false)
const newTitle = ref('')
const submitting = ref(false)

onMounted(() => {
  if (!root.value) return
  cleanup = dropTargetForElements({
    element: root.value,
    canDrop: ({ source }) => source.data.type === 'task',
    getData: () => ({ type: 'column', columnId: props.column.id }),
    onDragEnter: () => (isOver.value = true),
    onDragLeave: () => (isOver.value = false),
    onDrop: () => (isOver.value = false),
  })
})

onBeforeUnmount(() => {
  cleanup?.()
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
  <section ref="root" class="board-column" :class="{ 'board-column--over': isOver }">
    <header class="board-column__header">
      <div class="board-column__title">
        {{ column.name }}
        <span class="board-column__count">{{ tasksInColumn.length }}</span>
      </div>
      <v-menu v-if="auth.isAuthed">
        <template #activator="{ props: act }">
          <v-btn
            v-bind="act"
            icon="mdi-dots-vertical"
            variant="text"
            density="comfortable"
            size="small"
          />
        </template>
        <v-list density="compact">
          <v-list-item @click="$emit('rename', column)">
            <v-list-item-title>Переименовать</v-list-item-title>
          </v-list-item>
          <v-list-item @click="$emit('delete', column)">
            <v-list-item-title>Удалить</v-list-item-title>
          </v-list-item>
        </v-list>
      </v-menu>
    </header>

    <div class="board-column__cards">
      <BoardCard
        v-for="task in tasksInColumn"
        :key="task.id"
        :task="task"
        @open="$emit('open-task', $event)"
      />
    </div>

    <div v-if="auth.isAuthed" class="board-column__add">
      <template v-if="!adding">
        <v-btn
          variant="tonal"
          block
          prepend-icon="mdi-plus"
          density="comfortable"
          @click="startAdd"
        >
          Добавить карточку
        </v-btn>
      </template>
      <template v-else>
        <v-textarea
          v-model="newTitle"
          autofocus
          rows="2"
          auto-grow
          variant="outlined"
          density="comfortable"
          :disabled="submitting"
          placeholder="Название карточки…"
          @keydown.enter.exact.prevent="commitAdd"
          @keydown.escape.prevent="cancelAdd"
        />
        <div class="d-flex ga-2 mt-2">
          <v-btn
            color="primary"
            variant="flat"
            density="comfortable"
            :loading="submitting"
            @click="commitAdd"
          >
            Добавить
          </v-btn>
          <v-btn variant="text" density="comfortable" :disabled="submitting" @click="cancelAdd">
            Отмена
          </v-btn>
        </div>
      </template>
    </div>
  </section>
</template>

<style scoped>
.board-column {
  display: flex;
  flex-direction: column;
  width: 280px;
  flex: 0 0 auto;
  background: rgb(var(--v-theme-surface-container));
  border-radius: 16px;
  padding: 12px;
  max-height: 100%;
  transition: background-color 200ms cubic-bezier(0.2, 0, 0, 1);
}
.board-column--over {
  background: rgb(var(--v-theme-surface-container-highest));
}
.board-column__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
  padding: 0 4px;
}
.board-column__title {
  font-weight: 600;
  letter-spacing: 0.01em;
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.board-column__count {
  font-weight: 400;
  font-size: 0.85rem;
  color: rgba(var(--v-theme-on-surface), 0.62);
}
.board-column__cards {
  display: flex;
  flex-direction: column;
  gap: 8px;
  overflow-y: auto;
  padding: 4px;
  min-height: 8px;
}
.board-column__add {
  margin-top: 8px;
}
</style>
