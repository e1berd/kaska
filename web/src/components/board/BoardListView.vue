<script setup lang="ts">
import { computed } from 'vue'
import { useBoardStore, type Task } from '@/stores/board'
import ListHeaderCell from '@/components/board/ListHeaderCell.vue'
import { cssColorOr } from '@/utils/css'

const props = defineProps<{
  filteredTasks: Task[]
  slug: string
}>()

defineEmits<{
  (e: 'open-task', task: Task): void
}>()

const board = useBoardStore()

const listColumnDefaults = [
  { title: 'Карточка', key: 'title', sortable: true, minWidth: 200 },
  { title: 'Тип', key: 'task_type_id', sortable: true, minWidth: 120 },
  { title: 'Статус', key: 'column_id', sortable: true, minWidth: 160 },
  { title: 'Исполнитель', key: 'assignee_id', sortable: true, minWidth: 160 },
  { title: 'Сроки', key: 'dates', sortable: true, minWidth: 200 },
] as const

const listColumnKeys = listColumnDefaults.map((column) => column.key)
const listColumnMap = computed(() => new Map(listColumnDefaults.map((column) => [column.key, column])))
const listHeaders = computed(() =>
  listColumnDefaults.map((column) => ({
    ...column,
    headerProps: { class: 'ks-list-th', 'data-column-key': column.key },
    cellProps: { class: 'ks-list-td', 'data-column-key': column.key },
  })),
)

function taskTypeFor(id: string | null | undefined) {
  if (!id) return null
  return board.task_types.find((t) => t.id === id) ?? null
}

function columnFor(id: string | null | undefined) {
  if (!id) return null
  return board.columns.find((column) => column.id === id) ?? null
}

function columnColorStyle(id: string | null | undefined) {
  return { '--ks-status-color': cssColorOr(columnFor(id)?.color, 'rgb(var(--v-theme-secondary-container))') }
}

function userFor(id: string | null | undefined) {
  if (!id) return null
  return board.users.find((u) => u.id === id) ?? null
}

function fmtDate(iso: string | null | undefined): string {
  if (!iso) return ''
  return new Date(iso).toLocaleDateString()
}

async function changeColumn(task: Task, newColumnId: unknown) {
  const targetId = typeof newColumnId === 'string' ? newColumnId : null
  if (!targetId || targetId === task.column_id) return
  const trailing = board.tasksFor(targetId).filter((t) => t.id !== task.id)
  const beforeId = trailing.length ? trailing[trailing.length - 1].id : null
  try {
    await board.moveTask(task.id, targetId, beforeId, null)
  } catch (e) {
    console.warn('[board] change column failed', e)
  }
}

function compareDates(a: Task, b: Task): number {
  const aDate = a.end_date ?? a.start_date ?? ''
  const bDate = b.end_date ?? b.start_date ?? ''
  if (!aDate && !bDate) return 0
  if (!aDate) return 1
  if (!bDate) return -1
  return aDate < bDate ? -1 : aDate > bDate ? 1 : 0
}
</script>

<template>
  <div class="ks-board__list">
    <v-card class="ks-board__table" rounded="lg" variant="elevated" :elevation="1">
      <v-data-table
        :headers="listHeaders"
        :items="filteredTasks"
        :items-per-page="-1"
        :custom-key-sort="{ dates: compareDates }"
        item-value="id"
        density="comfortable"
        hover
        fixed-header
        class="ks-table"
        @click:row="(_: unknown, ctx: { item: Task }) => $emit('open-task', ctx.item)"
      >
        <template #no-data>
          <div class="text-center text-medium-emphasis py-8">
            Карточек пока нет.
          </div>
        </template>

        <template #bottom />

        <template
          v-for="key in listColumnKeys"
          :key="key"
          #[`header.${key}`]="{ column, isSorted, toggleSort, getSortIcon }"
        >
          <ListHeaderCell
            :column-key="key"
            :title="listColumnMap.get(key)?.title ?? key"
            :sortable="column.sortable"
            :is-sorted="isSorted(column)"
            :sort-icon="getSortIcon(column)"
            @sort="toggleSort(column)"
          />
        </template>

        <template #item.title="{ item }">
          <span class="ks-table__title md-body-medium">{{ item.title }}</span>
        </template>

        <template #item.task_type_id="{ item }">
          <v-chip
            v-if="taskTypeFor(item.task_type_id)"
            :color="taskTypeFor(item.task_type_id)?.color || undefined"
            size="small"
            label
            text-color="white"
          >
            {{ taskTypeFor(item.task_type_id)?.name }}
          </v-chip>
          <span v-else class="text-medium-emphasis md-body-small">—</span>
        </template>

        <template #item.column_id="{ item }">
          <v-select
            :model-value="item.column_id"
            :items="board.orderedColumns"
            item-title="name"
            item-value="id"
            variant="solo-filled"
            density="compact"
            hide-details
            flat
            rounded="pill"
            :menu-props="{ closeOnContentClick: true }"
            :readonly="!board.canWrite"
            class="ks-table__col-select"
            :style="columnColorStyle(item.column_id)"
            @click.stop
            @update:model-value="(v: unknown) => changeColumn(item, v)"
          >
            <template #item="{ props: itemProps, item: option }">
              <v-list-item v-bind="itemProps">
                <template #prepend>
                  <span class="ks-status-dot" :style="columnColorStyle(option.id)" />
                </template>
              </v-list-item>
            </template>
            <template #selection="{ item: option }">
              <span class="ks-status-selection">
                <span class="ks-status-dot" :style="columnColorStyle(option.id)" />
                <span>{{ option.name }}</span>
              </span>
            </template>
          </v-select>
        </template>

        <template #item.assignee_id="{ item }">
          <div v-if="userFor(item.assignee_id)" class="ks-table__assignee">
            <v-avatar
              :image="userFor(item.assignee_id)?.avatar_url || ''"
              size="24"
              color="primary"
            >
              <span
                v-if="!userFor(item.assignee_id)?.avatar_url"
                class="text-white"
                style="font-size: 11px"
              >
                {{
                  (
                    userFor(item.assignee_id)?.display_name ||
                    userFor(item.assignee_id)?.email ||
                    '?'
                  )
                    .slice(0, 1)
                    .toUpperCase()
                }}
              </span>
            </v-avatar>
            <span class="md-body-small">
              {{ userFor(item.assignee_id)?.display_name || userFor(item.assignee_id)?.email }}
            </span>
          </div>
          <span v-else class="text-medium-emphasis md-body-small">—</span>
        </template>

        <template #item.dates="{ item }">
          <span v-if="item.start_date || item.end_date" class="ks-table__dates md-body-small">
            <v-icon size="14" class="mr-1">mdi-calendar</v-icon>
            {{ fmtDate(item.start_date) || '—' }} → {{ fmtDate(item.end_date) || '—' }}
          </span>
          <span v-else class="text-medium-emphasis md-body-small">—</span>
        </template>
      </v-data-table>
    </v-card>
  </div>
</template>

<style scoped>
.ks-board__list {
  flex: 1;
  padding: 8px 16px 20px;
  overflow: auto;
}
.ks-board__table {
  background: rgb(var(--v-theme-surface-container-low));
  overflow: hidden;
}
.ks-board__table :deep(.v-table__wrapper) {
  overflow-x: auto;
}
.ks-table :deep(th),
.ks-table :deep(td) {
  min-width: 120px;
}
.ks-table :deep(th[data-column-key="title"]),
.ks-table :deep(td[data-column-key="title"]) {
  min-width: 200px;
}
.ks-table :deep(th[data-column-key="column_id"]),
.ks-table :deep(td[data-column-key="column_id"]) {
  min-width: 160px;
}
.ks-table :deep(th[data-column-key="assignee_id"]),
.ks-table :deep(td[data-column-key="assignee_id"]) {
  min-width: 160px;
}
.ks-table :deep(th[data-column-key="dates"]),
.ks-table :deep(td[data-column-key="dates"]) {
  min-width: 200px;
}
.ks-table :deep(.ks-list-th) {
  background: rgb(var(--v-theme-surface-container));
  color: rgba(var(--v-theme-on-surface), 0.7);
  font-weight: 500;
  letter-spacing: 0;
  position: relative;
  padding: 0;
  border-bottom-color: rgb(var(--v-theme-outline-variant));
}
.ks-table :deep(.ks-list-td) {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 0;
  border-bottom-color: rgb(var(--v-theme-outline-variant));
}
.ks-table :deep(tbody tr) {
  transition: background-color var(--md-duration-short3) var(--md-easing-standard);
  cursor: pointer;
}
.ks-table__title {
  display: block;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: rgb(var(--v-theme-on-surface));
  font-weight: 500;
}
.ks-table__col-select {
  --ks-status-color: rgb(var(--v-theme-secondary-container));
  max-width: 180px;
}
.ks-table__col-select :deep(.v-field) {
  background: color-mix(
    in srgb,
    var(--ks-status-color) 28%,
    rgb(var(--v-theme-surface-container-high))
  );
  border-radius: var(--md-shape-full);
}
.ks-status-selection {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}
.ks-status-dot {
  --ks-status-color: rgb(var(--v-theme-secondary-container));
  width: 10px;
  height: 10px;
  border-radius: var(--md-shape-full);
  background: var(--ks-status-color);
  box-shadow: inset 0 0 0 1px rgba(var(--v-theme-outline), 0.24);
  flex: 0 0 auto;
  margin-right: 16px;
}
.ks-table__assignee {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.ks-table__dates {
  display: inline-flex;
  align-items: center;
  white-space: nowrap;
  color: rgba(var(--v-theme-on-surface), 0.78);
}
</style>
