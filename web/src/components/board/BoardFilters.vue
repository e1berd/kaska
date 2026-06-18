<script setup lang="ts">
import { computed } from 'vue'
import { useBoardStore } from '@/stores/board'
import type { User } from '@/stores/auth'
import { eachDayOfInterval, format, isValid, parse } from 'date-fns'

const props = defineProps<{
  filterQuery: string
  filterTaskType: string | null
  filterAssignee: string | null
  filterStartDate: string | null
  filterEndDate: string | null
}>()

const emit = defineEmits<{
  'update:filterQuery': [value: string]
  'update:filterTaskType': [value: string | null]
  'update:filterAssignee': [value: string | null]
  'update:filterStartDate': [value: string | null]
  'update:filterEndDate': [value: string | null]
  'clear': []
}>()

const board = useBoardStore()

const filterDateRangeModel = computed<Date[]>({
  get: () => {
    const start = parseIsoDate(props.filterStartDate)
    const end = parseIsoDate(props.filterEndDate)
    if (start && end) return buildDateRange(start, end)
    if (start) return [start]
    if (end) return [end]
    return []
  },
  set: (value) => {
    if (!value || value.length === 0) {
      emit('update:filterStartDate', null)
      emit('update:filterEndDate', null)
      return
    }
    const sorted = [...value].sort((a, b) => a.getTime() - b.getTime())
    emit('update:filterStartDate', formatIsoDate(sorted[0]))
    emit('update:filterEndDate', formatIsoDate(sorted[sorted.length - 1]))
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

function optionUser(item: unknown): User {
  const candidate = item as { raw?: User } & User
  return (candidate.raw ?? candidate) as User
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
  <div class="ks-board__filters">
    <v-text-field
      :model-value="filterQuery"
      label="Поиск по названию и описанию"
      prepend-inner-icon="mdi-magnify"
      variant="filled"
      density="comfortable"
      hide-details
      clearable
      @update:model-value="emit('update:filterQuery', $event)"
    />
    <v-select
      :model-value="filterTaskType"
      :items="board.task_types"
      item-title="name"
      item-value="id"
      label="Тип задачи"
      variant="filled"
      density="comfortable"
      hide-details
      clearable
      @update:model-value="emit('update:filterTaskType', $event)"
    />
    <v-select
      :model-value="filterAssignee"
      :items="board.users"
      :item-title="(u: User) => u.display_name || u.email"
      item-value="id"
      label="Исполнитель"
      variant="filled"
      density="comfortable"
      hide-details
      clearable
      @update:model-value="emit('update:filterAssignee', $event)"
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
        <div class="ks-filter-user">
          <v-avatar size="20" class="mr-2" color="primary">
            <v-img v-if="userAvatar(item)" :src="userAvatar(item)" cover alt="" />
            <span v-else class="text-white" style="font-size: 10px">{{ userInitial(item) }}</span>
          </v-avatar>
          <span class="ks-filter-user__label">
            {{ userLabel(item) }}
          </span>
        </div>
      </template>
    </v-select>
    <v-date-input
      :model-value="filterDateRangeModel"
      multiple="range"
      label="Период дат"
      density="comfortable"
      hide-details
      clearable
      prepend-icon=""
      prepend-inner-icon="mdi-calendar"
      @update:model-value="(v: Date[] | null) => filterDateRangeModel = v ?? []"
    />
    <v-btn
      class="justify-self-end self-center col-[-2/-1]"
      variant="text"
      rounded="pill"
      prepend-icon="mdi-filter-off-outline"
      @click="emit('clear')"
    >
      Сбросить
    </v-btn>
  </div>
</template>

<style scoped>
.ks-board__filters {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 10px;
  min-height: 0;
  overflow: hidden;
}
.ks-board__filters :deep(.v-input) {
  min-width: 0;
}
.ks-filter-user {
  display: inline-flex;
  align-items: center;
  min-width: 0;
  max-width: 100%;
}
.ks-filter-user__label {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
@media (max-width: 960px) {
  .ks-board__filters {
    grid-template-columns: 1fr 1fr;
  }
}
@media (max-width: 600px) {
  .ks-board__filters {
    grid-template-columns: 1fr;
  }
}
</style>
