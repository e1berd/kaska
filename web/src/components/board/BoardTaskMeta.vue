<script setup lang="ts">
import { computed } from 'vue'
import { useBoardStore, type TaskType } from '@/stores/board'
import type { User } from '@/stores/auth'
import { eachDayOfInterval, format, isValid, parse } from 'date-fns'
import { PhFloppyDisk } from '@phosphor-icons/vue'
import PresenceGroup from '@/components/PresenceGroup.vue'

const props = defineProps<{
  canWrite: boolean
  mobile: boolean
  taskSaving: boolean
  shortTaskId: string
  taskViewers: User[]
  taskStartDate: string | null
  taskEndDate: string | null
  taskType: string | null
  taskAssignee: string | null
  metaOpen: boolean
}>()

const emit = defineEmits<{
  'update:metaOpen': [value: boolean]
  'update:taskStartDate': [value: string | null]
  'update:taskEndDate': [value: string | null]
  'update:taskType': [value: string | null]
  'update:taskAssignee': [value: string | null]
  'openTaskPage': []
  'copyTaskLink': []
  'copyTaskId': []
  'deleteTask': []
  'close': []
}>()

const board = useBoardStore()

const taskDateRangeModel = computed<Date[]>({
  get: () => {
    const start = parseIsoDate(props.taskStartDate)
    const end = parseIsoDate(props.taskEndDate)
    if (start && end) return buildDateRange(start, end)
    if (start) return [start]
    if (end) return [end]
    return []
  },
  set: (value) => {
    if (!value || value.length === 0) {
      emit('update:taskStartDate', null)
      emit('update:taskEndDate', null)
      return
    }
    const sorted = [...value].sort((a, b) => a.getTime() - b.getTime())
    emit('update:taskStartDate', formatIsoDate(sorted[0]))
    emit('update:taskEndDate', formatIsoDate(sorted[sorted.length - 1]))
  },
})

function parseIsoDate(value: string | null): Date | null {
  if (!value) return null
  const parsed = parse(value, 'yyyy-MM-dd', new Date())
  return isValid(parsed) ? parsed : null
}

function formatIsoDate(date: Date): string {
  return format(date, 'yyyy-MM-dd')
}

function buildDateRange(start: Date, end: Date): Date[] {
  return eachDayOfInterval({ start, end })
}

function optionUser(item: unknown) {
  const candidate = item as { raw?: Record<string, unknown> } & Record<string, unknown>
  return (candidate.raw ?? candidate) as { display_name?: string; email?: string; avatar_url?: string }
}

function userLabel(item: unknown): string {
  const user = optionUser(item)
  return user.display_name || user.email || '—'
}

function userInitial(item: unknown): string {
  return userLabel(item).slice(0, 1).toUpperCase()
}

function userAvatar(item: unknown): string {
  return optionUser(item).avatar_url || ''
}
</script>

<template>
  <aside class="ks-task-meta">
    <header v-if="!mobile" class="ks-task-meta__bar">
      <v-tooltip text="Нажмите, чтобы скопировать ID" location="bottom">
        <template #activator="{ props: tipProps }">
          <span v-if="shortTaskId" v-bind="tipProps" class="ks-task-id md-label-large cursor-pointer" @click="emit('copyTaskId')">ID {{ shortTaskId }}</span>
        </template>
      </v-tooltip>
      <PresenceGroup
        v-if="taskViewers.length"
        :users="taskViewers"
        label="Сейчас в задаче"
        size="sm"
      />
      <v-spacer />
      <v-tooltip text="Открыть на странице" location="bottom">
        <template #activator="{ props: tooltipProps }">
          <v-btn v-bind="tooltipProps" icon="mdi-arrow-expand" variant="text" size="small" @click="emit('openTaskPage')" />
        </template>
      </v-tooltip>
      <v-tooltip text="Поделиться ссылкой" location="bottom">
        <template #activator="{ props: tooltipProps }">
          <v-btn v-bind="tooltipProps" icon="mdi-link-variant" variant="text" size="small" @click="emit('copyTaskLink')" />
        </template>
      </v-tooltip>
      <v-btn icon="mdi-close" variant="text" size="small" @click="emit('close')" />
    </header>

    <v-btn
      v-if="mobile"
      class="ks-task-meta__toggle"
      variant="text"
      block
      :append-icon="metaOpen ? 'mdi-chevron-up' : 'mdi-chevron-down'"
      @click="emit('update:metaOpen', !metaOpen)"
    >
      Свойства
    </v-btn>

    <div v-show="!mobile || metaOpen" class="ks-task-meta__body">
      <div class="ks-task-meta__group">
        <div class="ks-task-meta__title md-label-large">Свойства</div>
        <div class="ks-task-meta__fields">
          <v-date-input
            :model-value="taskDateRangeModel"
            multiple="range"
            label="Даты задачи"
            density="comfortable"
            clearable
            :readonly="!canWrite"
            prepend-icon=""
            prepend-inner-icon="mdi-calendar"
            @update:model-value="(v: Date[] | null) => taskDateRangeModel = v ?? []"
          />
          <v-select
            :model-value="taskType"
            :items="board.task_types"
            item-title="name"
            item-value="id"
            label="Тип задачи"
            variant="filled"
            density="comfortable"
            clearable
            :readonly="!canWrite"
            @update:model-value="emit('update:taskType', $event)"
          >
            <template #item="{ props: itemProps, item }">
              <v-list-item v-bind="itemProps">
                <template #prepend>
                  <v-icon :color="(item as TaskType).color">mdi-circle</v-icon>
                </template>
              </v-list-item>
            </template>
            <template #selection="{ item }">
              <v-chip
                :color="(item as TaskType).color"
                size="small"
                text-color="white"
                class="mr-2"
              >
                {{ (item as TaskType).name }}
              </v-chip>
            </template>
          </v-select>
          <v-select
            :model-value="taskAssignee"
            :items="board.users"
            item-title="display_name"
            item-value="id"
            label="Исполнитель"
            variant="filled"
            density="comfortable"
            clearable
            :readonly="!canWrite"
            @update:model-value="emit('update:taskAssignee', $event)"
          >
            <template #item="{ props: itemProps, item }">
              <v-list-item v-bind="itemProps" :title="userLabel(item)">
                <template #prepend>
                  <v-avatar size="24" class="mr-2" color="primary">
                    <v-img v-if="userAvatar(item)" :src="userAvatar(item)" cover alt="" />
                    <span v-else class="text-white text-caption">{{ userInitial(item) }}</span>
                  </v-avatar>
                </template>
              </v-list-item>
            </template>
            <template #selection="{ item }">
              <div class="ks-assignee-selection">
                <v-avatar size="20" class="mr-2" color="primary">
                  <v-img v-if="userAvatar(item)" :src="userAvatar(item)" cover alt="" />
                  <span v-else class="text-white" style="font-size: 10px">{{ userInitial(item) }}</span>
                </v-avatar>
                <span class="ks-assignee-selection__label">{{ userLabel(item) }}</span>
              </div>
            </template>
          </v-select>
        </div>
      </div>
    </div>

    <footer v-show="!mobile || metaOpen" class="ks-task-meta__foot">
      <v-btn
        v-if="canWrite"
        color="error"
        variant="text"
        rounded="pill"
        @click="emit('deleteTask')"
      >
        Удалить карточку
      </v-btn>
      <v-spacer />
      <div
        v-if="canWrite && taskSaving"
        class="save-icon flex items-center justify-center text-primary"
        style="height: 22px"
      >
        <PhFloppyDisk size="22" />
      </div>
    </footer>
  </aside>
</template>

<style scoped>
.save-icon {
  animation: opacityTransition .8s ease-in-out infinite reverse;
}

@keyframes opacityTransition {
  0% { opacity: 0; }
  50% { opacity: 1; }
  100% { opacity: 0; }
}

.ks-task-id {
  color: rgb(var(--v-theme-on-surface-variant));
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  white-space: nowrap;
}
.ks-task-meta {
  min-width: 0;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  background: rgb(var(--v-theme-surface-container-high));
  border-left: 1px solid rgba(var(--v-theme-outline-variant), 0.8);
}
.ks-task-meta__bar {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 8px 8px 8px 16px;
  min-height: 52px;
}
.ks-task-meta__toggle {
  justify-content: space-between;
}
.ks-task-meta__body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: 4px 20px 20px;
}
.ks-task-meta__foot {
  display: flex;
  align-items: center;
  padding: 10px 16px;
  border-top: 1px solid rgba(var(--v-theme-outline-variant), 0.6);
}
.ks-task-meta__group {
  display: flex;
  flex-direction: column;
}
.ks-task-meta__title {
  color: rgb(var(--v-theme-on-surface-variant));
  margin-bottom: 12px;
}
.ks-task-meta__fields {
  display: grid;
  gap: 8px;
}
.ks-task-meta__fields :deep(.v-field) {
  background: rgb(var(--v-theme-surface-container-highest));
}
.ks-assignee-selection {
  display: inline-flex;
  align-items: center;
  min-width: 0;
  max-width: 100%;
}
.ks-assignee-selection__label {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
