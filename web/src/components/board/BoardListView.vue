<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useBoardStore, type Task } from '@/stores/board'
import ListColumnControl from '@/components/board/ListColumnControl.vue'
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
  { title: 'Карточка', key: 'title', sortable: true, minWidth: 260, width: 320 },
  { title: 'Тип', key: 'task_type_id', sortable: true, width: 180 },
  { title: 'Статус', key: 'column_id', sortable: false, width: 200 },
  { title: 'Исполнитель', key: 'assignee_id', sortable: true, width: 200 },
  { title: 'Сроки', key: 'dates', sortable: false, width: 200 },
] as const

type ListColumnKey = (typeof listColumnDefaults)[number]['key']

const listColumnOrder = ref<ListColumnKey[]>(listColumnDefaults.map((column) => column.key))
const listColumnWidths = ref<Record<ListColumnKey, number>>(
  Object.fromEntries(listColumnDefaults.map((column) => [column.key, column.width])) as Record<
    ListColumnKey,
    number
  >,
)

const listColumnMap = computed(() => new Map(listColumnDefaults.map((column) => [column.key, column])))

const listHeaders = computed(() =>
  listColumnOrder.value.flatMap((key) => {
    const column = listColumnMap.value.get(key)
    if (!column) return []
    const width = `${listColumnWidths.value[key]}px`
    return [{ ...column, width, minWidth: 'minWidth' in column ? `${column.minWidth}px` : width }]
  }),
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
  return { '--ks-status-color': cssColorOr(columnFor(id)?.color, '#E8DEF8') }
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

function clampListColumnWidth(value: number): number {
  return Math.min(520, Math.max(120, Math.round(value)))
}

function moveListColumn(sourceKey: string, targetKey: string) {
  if (sourceKey === targetKey) return
  const source = sourceKey as ListColumnKey
  const target = targetKey as ListColumnKey
  const order = listColumnOrder.value.filter((key) => key !== source)
  const targetIndex = order.indexOf(target)
  if (targetIndex === -1) return
  order.splice(targetIndex, 0, source)
  listColumnOrder.value = order
}

function resizeListColumn(key: string, delta: number) {
  const columnKey = key as ListColumnKey
  listColumnWidths.value = {
    ...listColumnWidths.value,
    [columnKey]: clampListColumnWidth((listColumnWidths.value[columnKey] ?? 180) + delta),
  }
}

const listPrefsKey = computed(() => `kaska.board.list_columns.${props.slug}`)

watch(
  listPrefsKey,
  (key) => {
    const raw = localStorage.getItem(key)
    if (!raw) return
    try {
      const parsed = JSON.parse(raw) as {
        order?: string[]
        widths?: Record<string, number>
      }
      const allowed = new Set(listColumnDefaults.map((column) => column.key))
      const order = (parsed.order ?? []).filter((value): value is ListColumnKey =>
        allowed.has(value as ListColumnKey),
      )
      if (order.length) {
        listColumnOrder.value = [
          ...order,
          ...listColumnDefaults
            .map((column) => column.key)
            .filter((key) => !order.includes(key)),
        ]
      }
      listColumnWidths.value = {
        ...listColumnWidths.value,
        ...Object.fromEntries(
          Object.entries(parsed.widths ?? {}).flatMap(([key, value]) => {
            if (!allowed.has(key as ListColumnKey) || typeof value !== 'number') return []
            return [[key, clampListColumnWidth(value)]]
          }),
        ),
      }
    } catch {
      localStorage.removeItem(key)
    }
  },
  { immediate: true },
)

watch(
  [listColumnOrder, listColumnWidths],
  () => {
    localStorage.setItem(
      listPrefsKey.value,
      JSON.stringify({ order: listColumnOrder.value, widths: listColumnWidths.value }),
    )
  },
  { deep: true },
)
</script>

<template>
  <div class="ks-board__list">
    <div class="ks-board__list-controls">
      <ListColumnControl
        v-for="key in listColumnOrder"
        :key="key"
        :column-key="key"
        :title="listColumnMap.get(key)?.title ?? key"
        :width="listColumnWidths[key]"
        @move="moveListColumn"
        @resize="resizeListColumn"
      />
    </div>
    <v-card class="ks-board__table" rounded="lg" variant="elevated" :elevation="1">
      <v-data-table
        :headers="listHeaders"
        :items="filteredTasks"
        :items-per-page="-1"
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
.ks-board__list-controls {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 10px;
}
.ks-board__table {
  background: rgb(var(--v-theme-surface-container-low));
  overflow: hidden;
}
.ks-board__table :deep(.v-table__wrapper) {
  overflow-x: auto;
}
.ks-table :deep(thead th) {
  background: rgb(var(--v-theme-surface-container)) !important;
  color: rgba(var(--v-theme-on-surface), 0.7);
  font-weight: 500;
  letter-spacing: 0.1px;
}
.ks-table :deep(tbody tr) {
  transition: background-color var(--md-duration-short3) var(--md-easing-standard);
}
.ks-table :deep(tbody tr:hover td) {
  background: rgba(var(--v-theme-on-surface), 0.04) !important;
}
.ks-table :deep(tbody tr) {
  cursor: pointer;
}
.ks-table__title {
  color: rgb(var(--v-theme-on-surface));
  font-weight: 500;
}
.ks-table__col-select {
  --ks-status-color: #e8def8;
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
  --ks-status-color: #e8def8;
  width: 10px;
  height: 10px;
  border-radius: var(--md-shape-full);
  background: var(--ks-status-color);
  box-shadow: inset 0 0 0 1px rgba(var(--v-theme-outline), 0.24);
  flex: 0 0 auto;
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
