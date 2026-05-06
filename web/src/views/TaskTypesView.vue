<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'

import { useAuthStore } from '../stores/auth'
import { useBoardStore, type TaskType } from '../stores/board'
import { useProjectsStore } from '../stores/projects'

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
const typeColor = ref('#grey') // Default generic name for arbitrary colours
const submitting = ref(false)

const predefinedColors = [
  { text: 'Серый', value: '#E0E0E0' },
  { text: 'Красный', value: '#F44336' },
  { text: 'Розовый', value: '#E91E63' },
  { text: 'Фиолетовый', value: '#9C27B0' },
  { text: 'Синий', value: '#2196F3' },
  { text: 'Голубой', value: '#03A9F4' },
  { text: 'Бирюзовый', value: '#00BCD4' },
  { text: 'Зеленый', value: '#4CAF50' },
  { text: 'Желтый', value: '#FFEB3B' },
  { text: 'Оранжевый', value: '#FF9800' }
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
    loading.value = false
  } catch (err: any) {
    if (err.reason === 'not_found' || err.message === 'проект не найден') {
      router.replace({ name: 'not-found' })
    } else {
      error.value = 'Не удалось подключиться к доске'
      loading.value = false
    }
  }
})

onBeforeUnmount(() => {
  board.leave()
})

function backToBoard() {
  router.push({ name: 'board', params: { slug: slug.value } })
}

function openNewTaskType() {
  editTarget.value = null
  typeName.value = ''
  typeColor.value = '#E0E0E0'
  dialog.value = true
}

function openEditTaskType(type: TaskType) {
  editTarget.value = type
  typeName.value = type.name
  typeColor.value = type.color
  dialog.value = true
}

async function saveTaskType() {
  const name = typeName.value.trim()
  if (!name) return

  submitting.value = true
  try {
    if (editTarget.value) {
      await board.updateTaskType(editTarget.value.id, { name, color: typeColor.value })
    } else {
      await board.createTaskType({ name, color: typeColor.value })
    }
    dialog.value = false
  } catch (err: any) {
    alert(err.message || 'Ошибка сохранения')
  } finally {
    submitting.value = false
  }
}

async function deleteTaskType(type: TaskType) {
  if (!confirm(`Удалить тип "${type.name}"?`)) return
  try {
    await board.deleteTaskType(type.id)
  } catch (err: any) {
    alert(err.message || 'Ошибка удаления')
  }
}
</script>

<template>
  <div class="hh-types-view">
    <header class="d-flex align-center px-4 py-3 border-b mb-6 bg-surface">
      <v-btn
        icon="mdi-arrow-left"
        variant="text"
        density="comfortable"
        class="mr-2"
        @click="backToBoard"
      />
      <div>
        <div class="md-headline-small">Типы задач</div>
        <div class="text-caption text-medium-emphasis">
          {{ board.project?.name ?? '…' }}
          <code v-if="board.project">/{{ board.project.slug }}</code>
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

    <div v-if="loading" class="d-flex justify-center align-center py-12">
      <v-progress-circular indeterminate color="primary" />
    </div>

    <v-alert
      v-else-if="error"
      type="error"
      variant="tonal"
      class="mx-4"
    >
      {{ error }}
    </v-alert>

    <div v-else class="px-4">
      <div v-if="board.task_types.length === 0" class="text-center py-12 bg-surface rounded-lg border">
        <v-icon size="48" color="medium-emphasis" class="mb-4">mdi-shape-outline</v-icon>
        <div class="md-title-medium mb-2">Нет типов задач</div>
        <div class="md-body-medium text-medium-emphasis mb-4">
          Создайте типы задач чтобы классифицировать работу вашей команды
        </div>
        <v-btn
          v-if="auth.isAuthed"
          color="primary"
          variant="tonal"
          rounded="pill"
          @click="openNewTaskType"
        >
          Создать тип
        </v-btn>
      </div>

      <v-row v-else>
        <v-col v-for="type in board.task_types" :key="type.id" cols="12" sm="6" md="4">
          <v-card variant="outlined" class="h-100">
            <v-card-item>
              <template v-slot:prepend>
                <v-avatar :color="type.color || '#E0E0E0'" size="36" class="mr-3" style="box-shadow: inset 0 0 0 1px rgba(0,0,0,0.1)">
                  <v-icon color="white">mdi-tag</v-icon>
                </v-avatar>
              </template>
              <v-card-title>{{ type.name }}</v-card-title>
            </v-card-item>
            
            <v-card-actions v-if="auth.isAuthed">
              <v-spacer />
              <v-btn
                variant="text"
                density="comfortable"
                size="small"
                @click="openEditTaskType(type)"
              >
                Редактировать
              </v-btn>
              <v-btn
                color="error"
                variant="text"
                density="comfortable"
                size="small"
                @click="deleteTaskType(type)"
              >
                Удалить
              </v-btn>
            </v-card-actions>
          </v-card>
        </v-col>
      </v-row>
    </div>

    <!-- Edit Dialog -->
    <v-dialog v-model="dialog" max-width="500">
      <v-card rounded="xl">
        <v-card-title class="md-headline-small px-6 pt-6">
          {{ editTarget ? 'Редактировать тип' : 'Новый тип задачи' }}
        </v-card-title>
        
        <v-card-text class="px-6 pt-4">
          <v-text-field
            v-model="typeName"
            label="Название типа"
            variant="outlined"
            density="comfortable"
            hide-details
            class="mb-6"
            autofocus
            @keyup.enter="saveTaskType"
          />
          
          <div class="text-subtitle-2 mb-2">Цвет</div>
          
          <div class="d-flex flex-wrap gap-2 mb-4">
            <v-chip
              v-for="color in predefinedColors"
              :key="color.value"
              :color="color.value"
              :variant="typeColor === color.value ? 'flat' : 'outlined'"
              link
              @click="typeColor = color.value"
              class="mb-2 mr-2"
              :style="typeColor === color.value ? 'border: 2px solid #000' : ''"
            >
              {{ color.text }}
            </v-chip>
          </div>
          
          <div class="d-flex align-center gap-3">
            <span class="text-body-2">Свой цвет:</span>
            <input 
              type="color" 
              v-model="typeColor" 
              style="width: 40px; height: 32px; padding: 0; border: none; border-radius: 4px; cursor: pointer"
            >
            <v-text-field
              v-model="typeColor"
              variant="outlined"
              density="compact"
              hide-details
              style="max-width: 120px"
              class="ml-2"
            />
          </div>
        </v-card-text>
        
        <v-card-actions class="px-6 pb-6">
          <v-spacer />
          <v-btn
            variant="text"
            rounded="pill"
            @click="dialog = false"
            :disabled="submitting"
          >
            Отмена
          </v-btn>
          <v-btn
            color="primary"
            variant="flat"
            rounded="pill"
            @click="saveTaskType"
            :loading="submitting"
            :disabled="!typeName.trim()"
          >
            Сохранить
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.hh-types-view {
  min-height: 100vh;
  background: rgb(var(--v-theme-background));
  max-width: 1200px;
  margin: 0 auto;
}
.gap-2 {
  gap: 8px;
}
.gap-3 {
  gap: 12px;
}

@media (max-width: 600px) {
  .hh-types-view :deep(.md-headline-small) {
    font-size: var(--md-type-title-large);
    line-height: 28px;
  }
}
</style>
