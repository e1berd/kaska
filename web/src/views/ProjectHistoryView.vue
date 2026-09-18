<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  useBoardStore,
  type TaskComment,
  type TaskHistoryEvent,
  type TaskHistoryField,
} from '@/stores/board'
import { useProjectsStore } from '@/stores/projects'
import { docPreview } from '@/utils/tiptap'
import UserAvatar, { type AvatarUser } from '@/components/UserAvatar.vue'

defineProps<{ slug?: string }>()

type HistoryActor = { id: string | null; name: string; user: AvatarUser | null }

const UNKNOWN_ACTOR: HistoryActor = { id: null, name: 'Неизвестно', user: null }

type FieldDiff =
  | { kind: 'pair'; before: string; after: string }
  | { kind: 'assignees'; added: AvatarUser[]; removed: AvatarUser[] }
  | { kind: 'note'; text: string }

type HistoryEntry = {
  id: string
  at: string
  type: 'event'
  actor: HistoryActor
  taskId: string
  taskTitle: string
  title: string
  diff: FieldDiff | null
  regression: boolean
  revertedBy: TaskHistoryEvent | null
  event: TaskHistoryEvent
}

type CommentEntry = {
  id: string
  at: string
  type: 'comment'
  actor: HistoryActor
  taskId: string
  taskTitle: string
  title: string
  text: string
}

type Entry = HistoryEntry | CommentEntry

type Session = { actor: HistoryActor; entries: Entry[] }
type DayGroup = { key: string; label: string; sessions: Session[] }

const SESSION_GAP_MS = 5 * 60 * 1000
const PAGE_SIZE = 50

const FIELD_LABELS: Record<TaskHistoryField, string> = {
  title: 'Название изменено',
  body_doc: 'Описание изменено',
  task_type_id: 'Тип изменён',
  start_date: 'Дата начала изменена',
  end_date: 'Дата окончания изменена',
  assignee_ids: 'Исполнители изменены',
  column_id: 'Статус изменён',
}

const route = useRoute()
const router = useRouter()
const board = useBoardStore()
const projects = useProjectsStore()

const loading = ref(true)
const loadingMore = ref(false)
const hasMore = ref(true)
const error = ref<string | null>(null)

const slug = computed(() => route.params.slug as string)

const columnsById = computed(() => new Map(board.columns.map((c) => [c.id, c])))
const taskTypesById = computed(() => new Map(board.task_types.map((t) => [t.id, t])))

onMounted(async () => {
  try {
    await projects.joinLobby()
    await board.joinBySlug(slug.value)
    await loadMore()
  } catch (err: unknown) {
    const reason = (err as { reason?: string })?.reason
    if (reason === 'not_found') {
      router.replace({ name: 'not-found' })
      return
    }
    error.value = 'Не удалось открыть историю проекта'
  } finally {
    loading.value = false
  }
})

async function loadMore() {
  if (loadingMore.value || !hasMore.value) return
  loadingMore.value = true
  try {
    const oldest = board.taskHistoryEvents[board.taskHistoryEvents.length - 1]
    const events = await board.listTaskHistory(
      oldest ? { before: oldest.inserted_at, limit: PAGE_SIZE } : { limit: PAGE_SIZE },
    )
    if (events.length < PAGE_SIZE) hasMore.value = false
  } catch {
    error.value = 'Не удалось загрузить историю'
  } finally {
    loadingMore.value = false
  }
}

function memberActor(userId: string | null | undefined): HistoryActor {
  const user = board.userById(userId)
  return user ? { id: userId ?? null, name: user.display_name || user.email, user } : UNKNOWN_ACTOR
}

function commentActor(comment: TaskComment): HistoryActor {
  if (!comment.author_id) {
    const name = comment.guest_name || 'Гость'
    return { id: null, name, user: { display_name: name } }
  }
  const name = comment.author_display_name || comment.author_email || 'Неизвестно'
  return {
    id: comment.author_id,
    name,
    user: { display_name: name, email: comment.author_email, avatar_url: comment.author_avatar_url },
  }
}

function unwrap(value: { v: unknown } | null): unknown {
  return value ? value.v : null
}

function fmtDay(iso: string | null): string {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('ru-RU', { day: 'numeric', month: 'short', year: 'numeric' })
}

function taskTypeName(id: string | null): string {
  if (!id) return '—'
  return taskTypesById.value.get(id)?.name ?? 'удалённый тип'
}

function columnName(id: string | null): string {
  if (!id) return '—'
  return columnsById.value.get(id)?.name ?? 'удалённый статус'
}

function unwrapString(value: { v: unknown } | null): string | null {
  const v = unwrap(value)
  return typeof v === 'string' ? v : null
}

function unwrapStringArray(value: { v: unknown } | null): string[] {
  const v = unwrap(value)
  return Array.isArray(v) ? (v as string[]) : []
}

function buildDiff(event: TaskHistoryEvent): FieldDiff | null {
  switch (event.field) {
    case 'title':
      return {
        kind: 'pair',
        before: unwrapString(event.old_value) ?? '—',
        after: unwrapString(event.new_value) ?? '—',
      }
    case 'body_doc':
      return { kind: 'note', text: 'изменено' }
    case 'task_type_id':
      return {
        kind: 'pair',
        before: taskTypeName(unwrapString(event.old_value)),
        after: taskTypeName(unwrapString(event.new_value)),
      }
    case 'start_date':
    case 'end_date':
      return {
        kind: 'pair',
        before: fmtDay(unwrapString(event.old_value)),
        after: fmtDay(unwrapString(event.new_value)),
      }
    case 'column_id':
      return {
        kind: 'pair',
        before: columnName(unwrapString(event.old_value)),
        after: columnName(unwrapString(event.new_value)),
      }
    case 'assignee_ids': {
      const before = unwrapStringArray(event.old_value)
      const after = unwrapStringArray(event.new_value)
      const added = after.filter((id) => !before.includes(id))
      const removed = before.filter((id) => !after.includes(id))
      return {
        kind: 'assignees',
        added: added.map((id) => board.userById(id) ?? { display_name: 'бывший участник' }),
        removed: removed.map((id) => board.userById(id) ?? { display_name: 'бывший участник' }),
      }
    }
    default:
      return null
  }
}

function taskTitleFor(taskId: string): string {
  return board.taskById(taskId)?.title || 'задача удалена'
}

const revertedByMap = computed(() => {
  const map = new Map<string, TaskHistoryEvent>()
  for (const e of board.taskHistoryEvents) {
    if (e.reverts_event_id) map.set(e.reverts_event_id, e)
  }
  return map
})

function toEventEntry(event: TaskHistoryEvent): HistoryEntry {
  return {
    id: event.id,
    at: event.inserted_at,
    type: 'event',
    actor: memberActor(event.actor_id),
    taskId: event.task_id,
    taskTitle: taskTitleFor(event.task_id),
    title: event.kind === 'created' ? 'Создана задача' : FIELD_LABELS[event.field as TaskHistoryField],
    diff: event.kind === 'created' ? null : buildDiff(event),
    regression: event.regression,
    revertedBy: revertedByMap.value.get(event.id) ?? null,
    event,
  }
}

function commentEntry(comment: TaskComment): CommentEntry {
  const text = comment.body_doc ? docPreview(comment.body_doc, 140) : comment.body
  return {
    id: `comment-${comment.id}`,
    at: comment.inserted_at ?? '',
    type: 'comment',
    actor: commentActor(comment),
    taskId: comment.task_id,
    taskTitle: taskTitleFor(comment.task_id),
    title: comment.parent_id ? 'Ответ в комментариях' : 'Комментарий',
    text: text || '(без текста)',
  }
}

const entries = computed<Entry[]>(() => {
  const eventEntries = board.taskHistoryEvents.map(toEventEntry)
  const commentEntries = board.taskComments.map(commentEntry)
  return [...eventEntries, ...commentEntries].sort((a, b) => Date.parse(b.at) - Date.parse(a.at))
})

function dayKey(iso: string): string {
  const d = new Date(iso)
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
}

function dayLabel(iso: string): string {
  const d = new Date(iso)
  const today = new Date()
  const yesterday = new Date()
  yesterday.setDate(today.getDate() - 1)
  if (dayKey(iso) === dayKey(today.toISOString())) return 'Сегодня'
  if (dayKey(iso) === dayKey(yesterday.toISOString())) return 'Вчера'
  return d.toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', year: 'numeric' })
}

const dayGroups = computed<DayGroup[]>(() => {
  const groups: DayGroup[] = []
  let currentDay: DayGroup | null = null
  let currentSession: Session | null = null
  let prevAt = 0

  for (const entry of entries.value) {
    const key = dayKey(entry.at)
    if (!currentDay || currentDay.key !== key) {
      currentDay = { key, label: dayLabel(entry.at), sessions: [] }
      groups.push(currentDay)
      currentSession = null
    }

    const at = Date.parse(entry.at)
    const sameActor = currentSession?.actor.id === entry.actor.id && currentSession?.actor.name === entry.actor.name
    const withinGap = currentSession ? prevAt - at <= SESSION_GAP_MS : false

    if (!currentSession || !sameActor || !withinGap) {
      currentSession = { actor: entry.actor, entries: [] }
      currentDay.sessions.push(currentSession)
    }

    currentSession.entries.push(entry)
    prevAt = at
  }

  return groups
})

function fmtTime(iso: string): string {
  if (!iso) return ''
  return new Date(iso).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

function sessionTimeRange(session: Session): string {
  if (session.entries.length < 2) return fmtTime(session.entries[0]?.at)
  const last = session.entries[session.entries.length - 1]
  const first = session.entries[0]
  return `${fmtTime(last.at)} – ${fmtTime(first.at)}`
}

function openTask(entry: Entry) {
  if (!entry.taskId || !board.taskById(entry.taskId)) return
  router.push({ name: 'task', params: { slug: slug.value, taskId: entry.taskId } })
}

// --- revert / rollback actions -------------------------------------------

type PendingAction = { type: 'revert' | 'rollback'; entry: HistoryEntry }

const pendingAction = ref<PendingAction | null>(null)
const commentDraft = ref('')
const submitting = ref(false)

const affectedByRollback = computed(() => {
  if (!pendingAction.value || pendingAction.value.type !== 'rollback') return []
  const anchor = pendingAction.value.entry.event
  return board.taskHistoryEvents.filter(
    (e) => e.task_id === anchor.task_id && e.field && Date.parse(e.inserted_at) > Date.parse(anchor.inserted_at),
  )
})

function canRevert(entry: HistoryEntry): boolean {
  return entry.event.kind !== 'created' && entry.event.field !== 'body_doc'
}

function openRevertDialog(entry: HistoryEntry) {
  pendingAction.value = { type: 'revert', entry }
  commentDraft.value = ''
}

function openRollbackDialog(entry: HistoryEntry) {
  pendingAction.value = { type: 'rollback', entry }
  commentDraft.value = ''
}

function closeDialog() {
  pendingAction.value = null
  commentDraft.value = ''
}

async function confirmAction() {
  if (!pendingAction.value || submitting.value) return
  submitting.value = true
  try {
    const { type, entry } = pendingAction.value
    const comment = commentDraft.value.trim() || null
    if (type === 'revert') await board.revertTaskHistoryEvent(entry.event.id, comment)
    else await board.rollbackTaskHistoryEvent(entry.event.id, comment)
    closeDialog()
  } catch (err: any) {
    alert(err?.message || 'Не удалось выполнить действие')
  } finally {
    submitting.value = false
  }
}

// --- hover connector -------------------------------------------------------

const listRef = ref<HTMLElement | null>(null)
const markerEls = new Map<string, HTMLElement>()

function setMarker(id: string, el: Element | null) {
  if (el) markerEls.set(id, el as HTMLElement)
  else markerEls.delete(id)
}

const activeLinkPath = ref<string | null>(null)
let activeLink: { fromId: string; toId: string } | null = null

function recomputeLink() {
  if (!activeLink || !listRef.value) {
    activeLinkPath.value = null
    return
  }
  const container = listRef.value
  const fromEl = markerEls.get(activeLink.fromId)
  const toEl = markerEls.get(activeLink.toId)
  if (!fromEl || !toEl) {
    activeLinkPath.value = null
    return
  }

  const cRect = container.getBoundingClientRect()
  const fRect = fromEl.getBoundingClientRect()
  const tRect = toEl.getBoundingClientRect()
  const railX = Math.min(fRect.left, tRect.left) - cRect.left - 18
  const fromX = fRect.left - cRect.left
  const toX = tRect.left - cRect.left
  const fromY = fRect.top - cRect.top + fRect.height / 2
  const toY = tRect.top - cRect.top + tRect.height / 2

  activeLinkPath.value = `M ${fromX} ${fromY} L ${railX} ${fromY} L ${railX} ${toY} L ${toX} ${toY}`
}

function onScrollOrResize() {
  if (activeLink) recomputeLink()
}

function hoverLink(fromId: string, toId: string) {
  activeLink = { fromId, toId }
  recomputeLink()
}

function unhoverLink() {
  activeLink = null
  activeLinkPath.value = null
}

onMounted(() => {
  window.addEventListener('scroll', onScrollOrResize, true)
  window.addEventListener('resize', onScrollOrResize)
})

onBeforeUnmount(() => {
  window.removeEventListener('scroll', onScrollOrResize, true)
  window.removeEventListener('resize', onScrollOrResize)
})
</script>

<template>
  <div class="ks-history-wrapper">
    <main class="ks-history">
      <header class="ks-history__head">
        <div>
          <h1 class="md-headline-medium mb-1">История</h1>
          <p class="md-body-medium text-medium-emphasis ma-0">Журнал изменений и обсуждений проекта.</p>
        </div>
      </header>

      <div v-if="loading" class="ks-history__state">
        <v-progress-circular indeterminate color="primary" />
      </div>
      <v-alert v-else-if="error" type="error" variant="tonal" rounded="lg">{{ error }}</v-alert>
      <div v-else-if="!entries.length" class="ks-history__empty">
        <v-icon size="32">mdi-history</v-icon>
        <span class="md-body-medium">История пока пуста.</span>
      </div>

      <div v-else ref="listRef" class="ks-history__list">
        <svg v-if="activeLinkPath" class="ks-history__links" aria-hidden="true">
          <defs>
            <marker id="ks-history-arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M0 0L10 5L0 10z" fill="rgb(var(--v-theme-primary))" />
            </marker>
          </defs>
          <path :d="activeLinkPath" fill="none" stroke="rgb(var(--v-theme-primary))" stroke-width="1.75" opacity="0.7" marker-end="url(#ks-history-arrow)" />
        </svg>

        <template v-for="day in dayGroups" :key="day.key">
          <div class="ks-history__divider">
            <span class="ks-history__divider-line" />
            <span class="ks-history__divider-label md-label-medium">{{ day.label.toUpperCase() }}</span>
            <span class="ks-history__divider-line" />
          </div>

          <div
            v-for="(session, sIdx) in day.sessions"
            :key="`${day.key}-${sIdx}`"
            class="ks-history__session"
            :class="{ 'ks-history__session--grouped': session.entries.length > 1 }"
          >
            <div v-if="session.entries.length > 1" class="ks-history__session-head">
              <UserAvatar v-if="session.actor.user" :user="session.actor.user" :size="24" tooltip="" />
              <v-avatar v-else :size="24" color="surface-container-highest">
                <v-icon size="14">mdi-account-question-outline</v-icon>
              </v-avatar>
              <span class="md-label-large">{{ session.actor.name }}</span>
              <span class="ks-history__session-time md-label-medium">{{ sessionTimeRange(session) }}</span>
              <span class="ks-history__session-count md-label-medium">{{ session.entries.length }} изменения</span>
            </div>

            <button
              v-for="entry in session.entries"
              :key="entry.id"
              type="button"
              class="ks-history__item md-state-layer"
              @click="openTask(entry)"
            >
              <span :ref="(el) => setMarker(entry.id, el as Element | null)" class="ks-history__marker">
                <UserAvatar v-if="entry.actor.user" :user="entry.actor.user" :size="28" tooltip="" />
                <v-avatar v-else :size="28" color="surface-container-highest">
                  <v-icon size="16">mdi-account-question-outline</v-icon>
                </v-avatar>
              </span>

              <span class="ks-history__body">
                <span class="ks-history__head-line">
                  <span class="ks-history__title md-title-small">{{ entry.title }}</span>
                  <span v-if="entry.type === 'event' && entry.regression" class="ks-history__tag ks-history__tag--regression">
                    <v-icon size="12">mdi-arrow-bottom-left</v-icon>
                    регресс по этапам
                  </span>
                  <span v-if="entry.taskId" class="ks-history__task md-label-large" @click.stop="openTask(entry)">
                    {{ entry.taskTitle }}
                  </span>
                </span>

                <span v-if="entry.type === 'comment'" class="ks-history__detail md-body-medium">{{ entry.text }}</span>

                <template v-else-if="entry.diff">
                  <span v-if="entry.diff.kind === 'pair'" class="ks-history__detail md-body-medium ks-history__diff">
                    <span class="ks-chip ks-chip--outline">{{ entry.diff.before }}</span>
                    <v-icon size="14">mdi-arrow-right</v-icon>
                    <span class="ks-chip ks-chip--primary">{{ entry.diff.after }}</span>
                  </span>
                  <span v-else-if="entry.diff.kind === 'assignees'" class="ks-history__detail md-body-medium ks-history__diff">
                    <span v-for="u in entry.diff.removed" :key="`rm-${u.display_name}`" class="ks-chip ks-chip--ghost">
                      − {{ u.display_name || u.email }}
                    </span>
                    <span v-for="u in entry.diff.added" :key="`add-${u.display_name}`" class="ks-chip ks-chip--primary">
                      + {{ u.display_name || u.email }}
                    </span>
                  </span>
                  <span v-else class="ks-history__detail md-body-medium">{{ entry.diff.text }}</span>
                </template>

                <span v-if="entry.type === 'event' && entry.event.comment" class="ks-history__comment md-body-medium">
                  <v-icon size="14">mdi-comment-text-outline</v-icon>
                  «{{ entry.event.comment }}»
                </span>

                <span
                  v-if="entry.type === 'event' && entry.revertedBy"
                  class="ks-history__reverted-label"
                  @mouseenter="hoverLink(entry.revertedBy!.id, entry.id)"
                  @mouseleave="unhoverLink"
                >
                  отменено
                </span>
              </span>

              <time class="ks-history__time md-label-medium">{{ fmtTime(entry.at) }}</time>

              <v-menu v-if="entry.type === 'event' && entry.event.kind !== 'created' && board.canWrite">
                <template #activator="{ props: menuProps }">
                  <v-btn
                    v-bind="menuProps"
                    icon="mdi-dots-vertical"
                    variant="text"
                    density="comfortable"
                    size="small"
                    class="ks-history__menu-btn"
                    @click.stop
                  />
                </template>
                <v-list density="compact" rounded="lg">
                  <v-list-item v-if="canRevert(entry)" prepend-icon="mdi-undo" @click="openRevertDialog(entry)">
                    Отменить
                  </v-list-item>
                  <v-divider v-if="canRevert(entry)" />
                  <v-list-item prepend-icon="mdi-history" @click="openRollbackDialog(entry)">
                    Откатить до этого места
                  </v-list-item>
                </v-list>
              </v-menu>
            </button>
          </div>
        </template>

        <div v-if="hasMore" class="ks-history__more">
          <v-btn variant="text" :loading="loadingMore" @click="loadMore">Загрузить ещё</v-btn>
        </div>
      </div>
    </main>

    <v-dialog :model-value="!!pendingAction" max-width="480" @update:model-value="!$event && closeDialog()">
      <v-card v-if="pendingAction" rounded="xl">
        <v-card-title class="md-headline-small px-6 pt-6">
          {{ pendingAction.type === 'revert' ? 'Отменить изменение' : 'Откатить до этого места' }}
        </v-card-title>
        <v-card-text class="px-6 pt-2 flex flex-col gap-4">
          <template v-if="pendingAction.type === 'revert'">
            <div v-if="pendingAction.entry.diff?.kind === 'pair'" class="ks-history__detail ks-history__diff">
              <span class="ks-chip ks-chip--outline">{{ pendingAction.entry.diff.after }}</span>
              <v-icon size="14">mdi-arrow-right</v-icon>
              <span class="ks-chip ks-chip--primary">{{ pendingAction.entry.diff.before }}</span>
            </div>
          </template>
          <template v-else>
            <p class="md-body-medium text-medium-emphasis ma-0">
              Будут отменены {{ affectedByRollback.length }} более поздних изменения:
            </p>
            <ul class="ks-history__affected">
              <li v-for="e in affectedByRollback" :key="e.id" class="md-body-small">
                {{ e.kind === 'created' ? 'Создание' : FIELD_LABELS[e.field as TaskHistoryField] }}
              </li>
            </ul>
          </template>
          <v-textarea
            v-model="commentDraft"
            label="Комментарий (необязательно)"
            placeholder="Например: нашёл баги, нужно доработать"
            variant="filled"
            density="comfortable"
            rows="3"
            auto-grow
            hide-details
          />
          <p class="md-body-small text-medium-emphasis ma-0">
            Появится и в этой записи истории, и как комментарий в задаче.
          </p>
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="closeDialog">Отмена</v-btn>
          <v-btn color="primary" variant="flat" rounded="pill" :loading="submitting" @click="confirmAction">
            {{ pendingAction.type === 'revert' ? 'Отменить' : 'Откатить' }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.ks-history-wrapper {
  flex: 1 1 0;
  min-height: 0;
  overflow-y: auto;
}

.ks-history {
  display: flex;
  flex-direction: column;
  gap: 20px;
  width: min(920px, 100%);
  max-width: 100%;
  min-width: 0;
  margin: 0 auto;
  padding: 24px;
  overflow-x: hidden;
}

.ks-history__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-width: 0;
}

.ks-history__state,
.ks-history__empty {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  min-height: 220px;
  color: rgb(var(--v-theme-on-surface-variant));
}

.ks-history__list {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
}

.ks-history__links {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  pointer-events: none;
  overflow: visible;
  z-index: 2;
}

.ks-history__divider {
  display: flex;
  align-items: center;
  gap: 12px;
  margin: 8px 0 4px;
}

.ks-history__divider-line {
  flex: 1;
  height: 1px;
  background: rgb(var(--v-theme-outline-variant));
}

.ks-history__divider-label {
  color: rgb(var(--v-theme-on-surface-variant));
}

.ks-history__session {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.ks-history__session--grouped {
  background: rgb(var(--v-theme-surface-container-low));
  border-radius: var(--md-shape-l);
  padding: 8px 8px 4px;
}

.ks-history__session-head {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 4px 8px 8px;
}

.ks-history__session-time,
.ks-history__session-count {
  color: rgb(var(--v-theme-on-surface-variant));
}

.ks-history__session-count {
  margin-left: auto;
  padding: 2px 10px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-surface-container-high));
}

.ks-history__item {
  --md-state-color: rgb(var(--v-theme-on-surface));
  position: relative;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto auto;
  align-items: start;
  gap: 14px;
  width: 100%;
  min-width: 0;
  padding: 10px 8px 10px 0;
  border: 0;
  border-radius: var(--md-shape-m);
  background: transparent;
  color: rgb(var(--v-theme-on-surface));
  text-align: left;
  cursor: pointer;
}

.ks-history__marker {
  position: relative;
  z-index: 1;
  display: inline-flex;
  border-radius: var(--md-shape-full);
}

.ks-history__head-line {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  min-width: 0;
}

.ks-history__task {
  color: rgb(var(--v-theme-primary));
  cursor: pointer;
}

.ks-history__body {
  display: grid;
  gap: 4px;
  min-width: 0;
}

.ks-history__title {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ks-history__detail,
.ks-history__time {
  color: rgb(var(--v-theme-on-surface-variant));
}

.ks-history__diff {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}

.ks-chip {
  display: inline-flex;
  align-items: center;
  height: 22px;
  padding: 0 10px;
  border-radius: var(--md-shape-full);
  font-size: 12px;
  font-weight: 500;
  white-space: nowrap;
}

.ks-chip--outline {
  border: 1px solid rgb(var(--v-theme-outline-variant));
  color: rgb(var(--v-theme-on-surface-variant));
}

.ks-chip--primary {
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
}

.ks-chip--ghost {
  background: rgb(var(--v-theme-surface-container-high));
  color: rgb(var(--v-theme-on-surface-variant));
}

.ks-history__tag {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  height: 22px;
  padding: 0 8px;
  border-radius: var(--md-shape-full);
  font-size: 11px;
  font-weight: 600;
}

.ks-history__tag--regression {
  background: rgb(var(--v-theme-tertiary-container));
  color: rgb(var(--v-theme-on-tertiary-container));
}

.ks-history__comment {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  background: rgb(var(--v-theme-surface-container));
  border-radius: var(--md-shape-s);
  padding: 6px 10px;
  max-width: fit-content;
}

.ks-history__reverted-label {
  align-self: flex-start;
  font-size: 12px;
  color: rgb(var(--v-theme-on-surface-variant));
  border-bottom: 1px dotted rgb(var(--v-theme-on-surface-variant));
  cursor: default;
  width: fit-content;
}

.ks-history__time {
  white-space: nowrap;
}

.ks-history__menu-btn {
  margin-top: -6px;
}

.ks-history__more {
  display: flex;
  justify-content: center;
  padding: 12px 0;
}

.ks-history__affected {
  margin: 0;
  padding-left: 20px;
  color: rgb(var(--v-theme-on-surface-variant));
}

@media (max-width: 720px) {
  .ks-history {
    padding: 16px;
  }

  .ks-history__item {
    grid-template-columns: auto minmax(0, 1fr) auto;
  }

  .ks-history__time {
    grid-column: 3;
  }
}
</style>
