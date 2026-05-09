<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useBoardStore, type TaskType } from '@/stores/board'
import { useProjectsStore } from '@/stores/projects'
import { cssColorOr } from '@/utils/css'

defineProps<{ slug?: string }>()

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const board = useBoardStore()
const projects = useProjectsStore()

const slug = computed(() => route.params.slug as string)
const loading = ref(true)
const error = ref<string | null>(null)

const dialog = ref(false)
const editTarget = ref<TaskType | null>(null)
const typeName = ref('')
const typeDescription = ref('')
const typeColor = ref('#4CAF50')
const submitting = ref(false)

const predefinedColors = [
  '#E0E0E0', '#F44336', '#E91E63', '#9C27B0', '#3F51B5',
  '#2196F3', '#00BCD4', '#009688', '#4CAF50', '#FF9800',
]

onMounted(async () => {
  try {
    error.value = null
    if (!projects.list.length) await projects.joinLobby()
    const project = projects.findBySlug(slug.value)
    if (!project) {
      router.replace({ name: 'not-found' })
      return
    }
    await board.join(project.id)
  } catch (err: any) {
    if (err?.reason === 'not_found' || err?.message === 'проект не найден') {
      router.replace({ name: 'not-found' })
      return
    }
    error.value = 'Не удалось загрузить типы задач'
  } finally {
    loading.value = false
  }
})

function backToBoard() {
  void router.push({ name: 'board', params: { slug: slug.value } })
}

function openNewTaskType() {
  editTarget.value = null
  typeName.value = ''
  typeDescription.value = ''
  typeColor.value = '#4CAF50'
  dialog.value = true
}

function openEditTaskType(type: TaskType) {
  editTarget.value = type
  typeName.value = type.name
  typeDescription.value = type.description ?? ''
  typeColor.value = type.color || '#4CAF50'
  dialog.value = true
}

async function saveTaskType() {
  const name = typeName.value.trim()
  if (!name) return

  submitting.value = true
  try {
    const payload = {
      name,
      description: typeDescription.value.trim() || null,
      color: typeColor.value,
    }
    if (editTarget.value) {
      await board.updateTaskType(editTarget.value.id, payload)
    } else {
      await board.createTaskType(payload)
    }
    dialog.value = false
  } catch (err: any) {
    alert(err?.message || 'Ошибка сохранения типа')
  } finally {
    submitting.value = false
  }
}

async function deleteTaskType(type: TaskType) {
  if (!confirm(`Удалить тип "${type.name}"?`)) return
  try {
    await board.deleteTaskType(type.id)
  } catch (err: any) {
    alert(err?.message || 'Ошибка удаления типа')
  }
}

function colorStyle(hex: string) {
  return { background: cssColorOr(hex, '#E0E0E0') }
}
</script>

<template>
  <div class="hh-types">
    <header class="hh-types__bar">
      <v-btn icon="mdi-arrow-left" variant="text" density="comfortable" @click="backToBoard" />
      <div>
        <div class="md-headline-small">Типы задач</div>
        <div class="md-body-small text-medium-emphasis">
          {{ board.project?.name ?? '…' }}<code v-if="board.project">/{{ board.project.slug }}</code>
        </div>
      </div>
      <v-spacer />
      <v-btn
        v-if="auth.isAuthed"
        prepend-icon="mdi-plus"
        color="primary"
        variant="flat"
        rounded="pill"
        @click="openNewTaskType"
      >
        Новый тип
      </v-btn>
    </header>

    <div v-if="loading" class="hh-types__state">
      <v-progress-circular indeterminate color="primary" />
    </div>

    <v-alert v-else-if="error" type="error" variant="tonal" class="mx-4">{{ error }}</v-alert>

    <div v-else-if="board.task_types.length === 0" class="hh-types__empty">
      <v-icon size="44" color="medium-emphasis">mdi-tag-outline</v-icon>
      <div class="md-title-medium mt-3">Пока нет типов задач</div>
      <div class="md-body-medium text-medium-emphasis mt-1">Добавьте типы, чтобы удобнее фильтровать и различать задачи.</div>
      <v-btn
        v-if="auth.isAuthed"
        class="mt-4"
        color="primary"
        variant="tonal"
        rounded="pill"
        @click="openNewTaskType"
      >
        Создать первый тип
      </v-btn>
    </div>

    <section v-else class="hh-types__grid">
      <article v-for="type in board.task_types" :key="type.id" class="hh-type-card">
        <div class="hh-type-card__head">
          <span class="hh-type-card__dot" :style="colorStyle(type.color)" />
          <div class="hh-type-card__title-wrap">
            <h3 class="hh-type-card__title">{{ type.name }}</h3>
            <p v-if="type.description" class="hh-type-card__desc">{{ type.description }}</p>
            <p v-else class="hh-type-card__desc hh-type-card__desc--muted">Описание не указано</p>
          </div>
        </div>
        <div v-if="auth.isAuthed" class="hh-type-card__actions">
          <v-btn variant="text" size="small" rounded="pill" @click="openEditTaskType(type)">Редактировать</v-btn>
          <v-btn color="error" variant="text" size="small" rounded="pill" @click="deleteTaskType(type)">Удалить</v-btn>
        </div>
      </article>
    </section>

    <v-dialog v-model="dialog" max-width="640">
      <v-card rounded="xl">
        <v-card-title class="px-6 pt-6">
          <span class="md-headline-small">{{ editTarget ? 'Редактировать тип' : 'Новый тип задачи' }}</span>
        </v-card-title>
        <v-card-text class="px-6 pt-3">
          <v-text-field
            v-model="typeName"
            label="Название"
            variant="filled"
            density="comfortable"
            autofocus
          />
          <v-textarea
            v-model="typeDescription"
            label="Описание (опционально)"
            variant="filled"
            density="comfortable"
            rows="3"
            auto-grow
          />

          <div class="md-label-large mb-2">Цвет</div>
          <div class="hh-colors mb-3">
            <button
              v-for="color in predefinedColors"
              :key="color"
              type="button"
              class="hh-colors__item"
              :class="{ 'is-active': typeColor === color }"
              :style="colorStyle(color)"
              @click="typeColor = color"
            />
          </div>
          <div class="d-flex align-center ga-3">
            <input v-model="typeColor" type="color" class="hh-color-input" />
            <v-text-field v-model="typeColor" label="HEX" variant="filled" density="compact" style="max-width: 140px" />
          </div>
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="dialog = false">Отмена</v-btn>
          <v-btn
            color="primary"
            variant="flat"
            rounded="pill"
            :loading="submitting"
            :disabled="!typeName.trim()"
            @click="saveTaskType"
          >
            Сохранить
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.hh-types {
  display: flex;
  flex-direction: column;
  min-height: 0;
}
.hh-types__bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-bottom: 1px solid rgba(var(--v-theme-outline), 0.2);
}
.hh-types__state {
  display: flex;
  justify-content: center;
  padding: 80px 0;
}
.hh-types__empty {
  margin: 20px 16px;
  padding: 32px;
  border-radius: var(--md-shape-l);
  border: 1px dashed rgba(var(--v-theme-outline-variant), 0.8);
  text-align: center;
  background: rgb(var(--v-theme-surface-container-low));
}
.hh-types__grid {
  padding: 16px;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 12px;
}
.hh-type-card {
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.65);
  border-radius: var(--md-shape-l);
  background: rgb(var(--v-theme-surface-container-low));
  padding: 14px;
  display: grid;
  gap: 10px;
}
.hh-type-card__head {
  display: flex;
  align-items: flex-start;
  gap: 10px;
}
.hh-type-card__dot {
  width: 12px;
  height: 12px;
  border-radius: 999px;
  margin-top: 7px;
  flex: 0 0 auto;
}
.hh-type-card__title-wrap {
  min-width: 0;
}
.hh-type-card__title {
  margin: 0;
  font-size: 16px;
  line-height: 1.35;
}
.hh-type-card__desc {
  margin: 4px 0 0;
  font-size: 13px;
  line-height: 1.45;
  color: rgba(var(--v-theme-on-surface), 0.75);
  white-space: pre-wrap;
}
.hh-type-card__desc--muted {
  color: rgba(var(--v-theme-on-surface), 0.52);
}
.hh-type-card__actions {
  display: flex;
  justify-content: flex-end;
  gap: 6px;
}
.hh-colors {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.hh-colors__item {
  width: 24px;
  height: 24px;
  border-radius: 999px;
  border: 2px solid transparent;
  cursor: pointer;
}
.hh-colors__item.is-active {
  box-shadow: 0 0 0 2px rgb(var(--v-theme-primary));
}
.hh-color-input {
  width: 44px;
  height: 32px;
  padding: 0;
  border: none;
  background: transparent;
  cursor: pointer;
}
</style>
