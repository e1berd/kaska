<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useBoardStore, type TaskType } from '@/stores/board'
import { useProjectsStore } from '@/stores/projects'
import { cssColorOr } from '@/utils/css'
import ColorPicker from '@/components/ColorPicker.vue'

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
const typeTextColor = ref('#FFFFFF')
const submitting = ref(false)

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

function openNewTaskType() {
  editTarget.value = null
  typeName.value = ''
  typeDescription.value = ''
  typeColor.value = '#4CAF50'
  typeTextColor.value = '#FFFFFF'
  dialog.value = true
}

function openEditTaskType(type: TaskType) {
  editTarget.value = type
  typeName.value = type.name
  typeDescription.value = type.description ?? ''
  typeColor.value = type.color || '#4CAF50'
  typeTextColor.value = type.text_color || '#FFFFFF'
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
      text_color: typeTextColor.value,
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

const previewStyle = computed(() => ({
  background: cssColorOr(typeColor.value, '#E0E0E0'),
  color: cssColorOr(typeTextColor.value, '#FFFFFF'),
}))

async function deleteTaskType(type: TaskType) {
  if (!confirm(`Удалить тип "${type.name}"?`)) return
  try {
    await board.deleteTaskType(type.id)
  } catch (err: any) {
    alert(err?.message || 'Ошибка удаления типа')
  }
}

</script>

<template>
  <div class="ks-types">
    <header class="ks-types__bar">
      <div>
        <div class="md-headline-small">Типы задач</div>
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

    <div v-if="loading" class="ks-types__state">
      <v-progress-circular indeterminate color="primary" />
    </div>

    <v-alert v-else-if="error" type="error" variant="tonal" class="mx-4">{{ error }}</v-alert>

    <div v-else-if="board.task_types.length === 0" class="ks-types__empty">
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

    <section v-else class="ks-types__grid">
      <article v-for="type in board.task_types" :key="type.id" class="ks-type-card">
        <div class="ks-type-card__head">
          <span
            class="ks-type-card__chip"
            :style="{ background: cssColorOr(type.color, '#E0E0E0'), color: cssColorOr(type.text_color, '#FFFFFF') }"
          >{{ type.name }}</span>
          <div class="ks-type-card__title-wrap">
            <p v-if="type.description" class="ks-type-card__desc">{{ type.description }}</p>
            <p v-else class="ks-type-card__desc ks-type-card__desc--muted">Описание не указано</p>
          </div>
        </div>
        <div v-if="auth.isAuthed" class="ks-type-card__actions">
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

          <ColorPicker v-model="typeColor" label="Цвет фона" class="mb-4" />
          <ColorPicker
            v-model="typeTextColor"
            label="Цвет текста"
            class="mb-4"
            :presets="['#FFFFFF', '#000000', '#21005D', '#1D192B', '#31111D', '#410E0B']"
          />

          <div class="md-label-large mb-2">Превью</div>
          <span class="ks-type-preview" :style="previewStyle">
            {{ typeName.trim() || 'Тип задачи' }}
          </span>
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
.ks-types {
  display: flex;
  flex-direction: column;
  min-height: 0;
}
.ks-types__bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-bottom: 1px solid rgba(var(--v-theme-outline), 0.2);
}
.ks-types__state {
  display: flex;
  justify-content: center;
  padding: 80px 0;
}
.ks-types__empty {
  margin: 20px 16px;
  padding: 32px;
  border-radius: var(--md-shape-l);
  border: 1px dashed rgba(var(--v-theme-outline-variant), 0.8);
  text-align: center;
  background: rgb(var(--v-theme-surface-container-low));
}
.ks-types__grid {
  padding: 16px;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 12px;
}
.ks-type-card {
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.65);
  border-radius: var(--md-shape-l);
  background: rgb(var(--v-theme-surface-container-low));
  padding: 14px;
  display: grid;
  gap: 10px;
}
.ks-type-card__head {
  display: flex;
  align-items: flex-start;
  gap: 10px;
}
.ks-type-card__chip {
  display: inline-flex;
  align-items: center;
  padding: 4px 10px;
  border-radius: var(--md-shape-s);
  font-size: 13px;
  font-weight: 500;
  flex: 0 0 auto;
  white-space: nowrap;
}
.ks-type-preview {
  display: inline-flex;
  align-items: center;
  padding: 6px 14px;
  border-radius: var(--md-shape-s);
  font-size: 14px;
  font-weight: 500;
}
.ks-type-card__title-wrap {
  min-width: 0;
}
.ks-type-card__title {
  margin: 0;
  font-size: 16px;
  line-height: 1.35;
}
.ks-type-card__desc {
  margin: 4px 0 0;
  font-size: 13px;
  line-height: 1.45;
  color: rgba(var(--v-theme-on-surface), 0.75);
  white-space: pre-wrap;
}
.ks-type-card__desc--muted {
  color: rgba(var(--v-theme-on-surface), 0.52);
}
.ks-type-card__actions {
  display: flex;
  justify-content: flex-end;
  gap: 6px;
}
.ks-colors {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.ks-colors__item {
  width: 24px;
  height: 24px;
  border-radius: 999px;
  border: 2px solid transparent;
  cursor: pointer;
}
.ks-colors__item.is-active {
  box-shadow: 0 0 0 2px rgb(var(--v-theme-primary));
}
.ks-color-input {
  width: 44px;
  height: 32px;
  padding: 0;
  border: none;
  background: transparent;
  cursor: pointer;
}
</style>
