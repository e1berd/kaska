<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref } from 'vue'
import { dropTargetForElements } from '@atlaskit/pragmatic-drag-and-drop/element/adapter'
import { useBoardStore, type Column, type Task } from '../../stores/board'
import { useAuthStore } from '../../stores/auth'
import BoardCard from './BoardCard.vue'

const props = defineProps<{ column: Column; accent: 'primary' | 'secondary' | 'tertiary' }>()
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
  <section
    ref="root"
    class="hh-col"
    :class="{ 'hh-col--over': isOver }"
    :data-accent="accent"
  >
    <header class="hh-col__head">
      <div class="hh-col__title">
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

    <div class="hh-col__cards">
      <BoardCard
        v-for="task in tasksInColumn"
        :key="task.id"
        :task="task"
        @open="$emit('open-task', $event)"
      />
      <div v-if="!tasksInColumn.length" class="hh-col__empty md-body-small">
        Нет карточек
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
  </section>
</template>

<style scoped>
.hh-col {
  --col-accent: var(--v-theme-primary);
  --col-accent-container: var(--v-theme-primary-container);
  --col-accent-on-container: var(--v-theme-on-primary-container);

  display: flex;
  flex-direction: column;
  width: 296px;
  flex: 0 0 auto;
  background: rgb(var(--v-theme-surface-container));
  border-radius: var(--md-shape-l);
  padding: 12px;
  max-height: 100%;
  transition: background-color var(--md-duration-short4) var(--md-easing-standard);
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
  outline: 2px dashed rgba(var(--col-accent), 0.5);
  outline-offset: -2px;
}

.hh-col__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 4px 6px 8px;
}
.hh-col__title {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: rgb(var(--v-theme-on-surface));
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
  overflow-y: auto;
  padding: 4px 4px 8px;
  min-height: 8px;
}
.hh-col__empty {
  text-align: center;
  padding: 16px 8px;
  color: rgba(var(--v-theme-on-surface), 0.45);
  border: 1px dashed rgba(var(--v-theme-outline-variant), 0.7);
  border-radius: var(--md-shape-m);
}

.hh-col__add {
  margin-top: 4px;
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
</style>
