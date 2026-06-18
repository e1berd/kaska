<script setup lang="ts">
import { ref } from 'vue'
import { useBoardStore, type Column } from '@/stores/board'
import ColorPicker from '@/components/ColorPicker.vue'

const emit = defineEmits<{ (e: 'task-created', taskId: string): void }>()

const board = useBoardStore()

const renameDialog = ref(false)
const renameTarget = ref<Column | null>(null)
const renameValue = ref('')
const renameDescription = ref('')
const renameColor = ref('#E8DEF8')

const deleteDialog = ref(false)
const deleteTarget = ref<Column | null>(null)

const newColumnDialog = ref(false)
const newColumnName = ref('')
const newColumnColor = ref('#E8DEF8')
const newTaskDialog = ref(false)
const newTaskTitle = ref('')
const newTaskSubmitting = ref(false)

function onRename(column: Column) {
  renameTarget.value = column
  renameValue.value = column.name
  renameDescription.value = column.description ?? ''
  renameColor.value = column.color || '#E8DEF8'
  renameDialog.value = true
}

async function commitRename() {
  if (!renameTarget.value) return
  const name = renameValue.value.trim()
  if (!name) return
  try {
    await board.renameColumn(
      renameTarget.value.id,
      name,
      renameDescription.value.trim() || null,
      renameColor.value,
    )
    renameDialog.value = false
  } catch (e) {
    console.warn('[board] rename failed', e)
  }
}

function onDeleteColumn(column: Column) {
  deleteTarget.value = column
  deleteDialog.value = true
}

async function commitDelete() {
  if (!deleteTarget.value) return
  try {
    await board.deleteColumn(deleteTarget.value.id)
    deleteDialog.value = false
  } catch (e) {
    console.warn('[board] delete failed', e)
  }
}

function openNewColumn() {
  newColumnName.value = ''
  newColumnColor.value = '#E8DEF8'
  newColumnDialog.value = true
}

function openNewTask() {
  newTaskTitle.value = ''
  newTaskDialog.value = true
}

async function commitNewColumn() {
  const name = newColumnName.value.trim()
  if (!name) return
  try {
    await board.createColumn(name, newColumnColor.value)
    newColumnDialog.value = false
  } catch (e) {
    console.warn('[board] create column failed', e)
  }
}

async function commitNewTask() {
  const title = newTaskTitle.value.trim()
  const firstColumn = board.orderedColumns[0]
  if (!title || !firstColumn) return
  newTaskSubmitting.value = true
  try {
    const created = await board.createTask(firstColumn.id, { title })
    if (created) emit('task-created', created.id)
    newTaskTitle.value = ''
    newTaskDialog.value = false
  } catch (e) {
    console.warn('[board] create task failed', e)
  } finally {
    newTaskSubmitting.value = false
  }
}

defineExpose({ onRename, onDeleteColumn, openNewColumn, openNewTask })
</script>

<template>
  <v-dialog v-model="renameDialog" max-width="460">
    <v-card rounded="xl">
      <v-card-title class="md-headline-small px-6 pt-6">Переименовать статус</v-card-title>
      <v-card-text class="px-6 pt-2 flex flex-col gap-4">
        <v-text-field
          v-model="renameValue"
          label="название"
          variant="filled"
          density="comfortable"
          autofocus
          hide-details
          @keydown.enter.exact.prevent="commitRename"
          @keydown.escape.prevent="renameDialog = false"
        />
        <v-textarea
          v-model="renameDescription"
          label="описание"
          placeholder="Зачем этот статус и куда переносить задачу дальше — подсказка для агентов"
          variant="filled"
          density="comfortable"
          rows="3"
          auto-grow
          hide-details
        />
        <ColorPicker v-model="renameColor" label="цвет статуса" />
      </v-card-text>
      <v-card-actions class="px-6 pb-6">
        <v-spacer />
        <v-btn variant="text" rounded="pill" @click="renameDialog = false">Отмена</v-btn>
        <v-btn color="primary" variant="flat" rounded="pill" @click="commitRename">
          Сохранить
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>

  <v-dialog v-model="deleteDialog" max-width="460">
    <v-card rounded="xl">
      <v-card-title class="md-headline-small px-6 pt-6">Удалить статус?</v-card-title>
      <v-card-text class="px-6 pt-2 md-body-medium text-medium-emphasis">
        Все её карточки тоже исчезнут. Действие нельзя отменить.
      </v-card-text>
      <v-card-actions class="px-6 pb-6">
        <v-spacer />
        <v-btn variant="text" rounded="pill" @click="deleteDialog = false">Отмена</v-btn>
        <v-btn color="error" variant="flat" rounded="pill" @click="commitDelete">
          Удалить
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>

  <v-dialog v-model="newColumnDialog" max-width="460">
    <v-card rounded="xl">
      <v-card-title class="md-headline-small px-6 pt-6">Новый статус</v-card-title>
      <v-card-text class="px-6 pt-2">
        <v-text-field
          v-model="newColumnName"
          label="название"
          variant="filled"
          density="comfortable"
          autofocus
          hide-details
          @keydown.enter.exact.prevent="commitNewColumn"
        />
        <ColorPicker v-model="newColumnColor" label="цвет статуса" class="mt-4" />
      </v-card-text>
      <v-card-actions class="px-6 pb-6">
        <v-spacer />
        <v-btn variant="text" rounded="pill" @click="newColumnDialog = false">Отмена</v-btn>
        <v-btn color="primary" variant="flat" rounded="pill" @click="commitNewColumn">
          Создать
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>

  <v-dialog v-model="newTaskDialog" max-width="460">
    <v-card rounded="xl">
      <v-card-title class="md-headline-small px-6 pt-6">Новая задача</v-card-title>
      <v-card-text class="px-6 pt-2">
        <v-text-field
          v-model="newTaskTitle"
          label="название"
          variant="filled"
          density="comfortable"
          autofocus
          hide-details
          @keydown.enter.exact.prevent="commitNewTask"
        />
      </v-card-text>
      <v-card-actions class="px-6 pb-6">
        <v-spacer />
        <v-btn variant="text" rounded="pill" @click="newTaskDialog = false">Отмена</v-btn>
        <v-btn
          color="primary"
          variant="flat"
          rounded="pill"
          :loading="newTaskSubmitting"
          :disabled="!board.orderedColumns.length"
          @click="commitNewTask"
        >
          Создать
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>
