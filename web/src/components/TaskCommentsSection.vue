<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { PhDetective } from '@phosphor-icons/vue'
import { format, isValid, parseISO } from 'date-fns'
import { ru } from 'date-fns/locale'
import { useAuthStore } from '@/stores/auth'
import { useBoardStore, type TaskComment } from '@/stores/board'

const props = defineProps<{
  taskId: string
}>()

const auth = useAuthStore()
const board = useBoardStore()

const body = ref('')
const guestName = ref('')
const sending = ref(false)
const guestCooldownUntil = ref(0)
const nowTs = ref(Date.now())
const visibleCount = ref(20)
let cooldownTimer: ReturnType<typeof setInterval> | null = null

const comments = computed(() =>
  [...board.commentsFor(props.taskId)].sort((a, b) => {
    const ai = a.inserted_at ? Date.parse(a.inserted_at) : 0
    const bi = b.inserted_at ? Date.parse(b.inserted_at) : 0
    return bi - ai
  }),
)
const visibleComments = computed(() => comments.value.slice(0, visibleCount.value))
const hasMoreComments = computed(() => visibleComments.value.length < comments.value.length)
const canGuestComment = computed(() => board.settings.allow_guest_comments)
const canSend = computed(() => {
  if (auth.isAuthed) return true
  return canGuestComment.value
})
const cooldownActive = computed(
  () => !auth.isAuthed && nowTs.value < guestCooldownUntil.value,
)
const cooldownSeconds = computed(() =>
  Math.max(0, Math.ceil((guestCooldownUntil.value - nowTs.value) / 1000)),
)

function roleRank(role: string | null | undefined): number {
  if (role === 'superadmin') return 3
  if (role === 'admin') return 2
  if (role === 'user') return 1
  return 0
}

function canDelete(comment: TaskComment): boolean {
  if (!auth.isAuthed || !auth.user) return false
  if (!comment.author_id) return true
  if (comment.author_id === auth.user.id) return true
  return roleRank(auth.user.role) > roleRank(comment.author_role)
}

function authorLabel(comment: TaskComment): string {
  if (comment.author_display_name) return comment.author_display_name
  if (comment.author_email) return comment.author_email.split('@')[0]
  return comment.guest_name?.trim() || 'Гость'
}

function authorInitial(comment: TaskComment): string {
  return authorLabel(comment).slice(0, 1).toUpperCase()
}

function isGuestComment(comment: TaskComment): boolean {
  return !comment.author_id
}

function formatCommentDate(iso: string | undefined): string {
  if (!iso) return ''
  const parsed = parseISO(iso)
  if (!isValid(parsed)) return ''
  return format(parsed, 'd MMM yyyy, HH:mm', { locale: ru })
}

function loadMoreComments() {
  if (!hasMoreComments.value) return
  visibleCount.value = Math.min(visibleCount.value + 20, comments.value.length)
}

function onCommentsScroll(e: Event) {
  const node = e.target as HTMLElement
  if (node.scrollTop + node.clientHeight >= node.scrollHeight - 28) {
    loadMoreComments()
  }
}

async function submitComment() {
  if (!canSend.value) return
  const text = body.value.trim()
  if (!text) return
  if (sending.value) return
  if (cooldownActive.value) return
  if (!auth.isAuthed && text.length > 255) return

  sending.value = true
  try {
    await board.createTaskComment(
      props.taskId,
      text,
      auth.isAuthed ? null : guestName.value.trim() || null,
    )
    body.value = ''
    if (!auth.isAuthed) guestCooldownUntil.value = Date.now() + 4000
  } catch (e: any) {
    const message = e?.message || 'Не удалось отправить комментарий'
    if (message === 'guest_comment_rate_limited') {
      guestCooldownUntil.value = Date.now() + 4000
      alert('Слишком часто. Попробуйте отправить комментарий через пару секунд.')
    } else if (message === 'guest_comment_too_long') {
      alert('Комментарий гостя не должен превышать 255 символов.')
    } else {
      alert(message)
    }
  } finally {
    sending.value = false
  }
}

async function removeComment(comment: TaskComment) {
  if (!canDelete(comment)) return
  try {
    await board.deleteTaskComment(comment.id)
  } catch (e: any) {
    alert(e?.message || 'Не удалось удалить комментарий')
  }
}

onMounted(() => {
  cooldownTimer = setInterval(() => {
    nowTs.value = Date.now()
  }, 1000)
})

onBeforeUnmount(() => {
  if (cooldownTimer) clearInterval(cooldownTimer)
})

watch(
  () => props.taskId,
  () => {
    visibleCount.value = 20
  },
)
</script>

<template>
  <section class="ks-comments">
    <header class="ks-comments__head">
      <h3 class="md-title-small">Комментарии</h3>
      <span class="md-label-medium text-medium-emphasis">{{ comments.length }}</span>
    </header>

    <div class="ks-comments__form">
      <v-text-field
        v-if="!auth.isAuthed && canGuestComment"
        v-model="guestName"
        label="Ваше имя (опционально)"
        density="comfortable"
        variant="filled"
        hide-details
      />
      <v-textarea
        v-model="body"
        label="Написать комментарий"
        density="comfortable"
        variant="filled"
        rows="3"
        hide-details
        auto-grow
        :maxlength="auth.isAuthed ? 5000 : 255"
        :readonly="!canSend"
        :hint="
          !canSend
            ? 'Только авторизованные пользователи могут оставлять комментарии'
            : !auth.isAuthed
              ? `Для гостей: до 255 символов и пауза 4 сек. ${cooldownActive ? `Подождите ${cooldownSeconds} сек.` : ''}`
              : undefined
        "
        :persistent-hint="!canSend || !auth.isAuthed"
      />
      <div class="ks-comments__actions">
        <v-btn
          color="primary"
          variant="flat"
          size="small"
          rounded="pill"
          :loading="sending"
          :disabled="!canSend || !body.trim() || cooldownActive"
          @click="submitComment"
        >
          Отправить
        </v-btn>
      </div>
    </div>

    <div v-if="comments.length === 0" class="ks-comments__empty md-body-small">
      Пока комментариев нет.
    </div>
    <div
      v-else
      v-auto-animate
      class="ks-comments__list"
      @scroll.passive="onCommentsScroll"
    >
      <article
        v-for="comment in visibleComments"
        :key="comment.id"
        class="ks-comments__item"
      >
        <v-avatar size="30" color="secondary-container" class="ks-comments__avatar">
          <PhDetective
            v-if="isGuestComment(comment)"
            :size="16"
            weight="duotone"
          />
          <img
            v-else-if="comment.author_avatar_url"
            :src="comment.author_avatar_url"
            :alt="authorLabel(comment)"
            width="30"
            height="30"
          />
          <span v-else class="md-label-medium">{{ authorInitial(comment) }}</span>
        </v-avatar>

        <div class="ks-comments__content">
          <div class="ks-comments__meta-row">
            <span class="ks-comments__author md-label-medium">{{ authorLabel(comment) }}</span>
            <time class="ks-comments__meta md-label-small">
              {{ formatCommentDate(comment.inserted_at) }}
            </time>
          </div>
          <p class="ks-comments__body md-body-small">
            {{ comment.body }}
          </p>
        </div>

        <v-btn
          v-if="canDelete(comment)"
          icon="mdi-delete-outline"
          variant="text"
          color="error"
          density="comfortable"
          size="x-small"
          class="ks-comments__delete"
          @click="removeComment(comment)"
        />
      </article>
      <div v-if="hasMoreComments" class="ks-comments__more md-label-small">
        Прокрутите вниз, чтобы загрузить ещё
      </div>
    </div>
  </section>
</template>

<style scoped>
.ks-comments {
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.55);
  border-radius: var(--md-shape-l);
  background: rgb(var(--v-theme-surface-container-low));
  padding: 12px;
  display: grid;
  gap: 10px;
  max-height: min(62vh, 740px);
}
.ks-comments__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.ks-comments__head h3 {
  margin: 0;
}
.ks-comments__form {
  display: grid;
  gap: 10px;
}
.ks-comments__actions {
  display: flex;
  justify-content: flex-end;
}
.ks-comments__empty {
  color: rgba(var(--v-theme-on-surface), 0.65);
  text-align: center;
  padding: 10px 0;
}
.ks-comments__list {
  background: rgb(var(--v-theme-surface-container-lowest));
  padding: 6px;
  border-radius: var(--md-shape-m);
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.45);
  overflow-y: auto;
  overscroll-behavior: contain;
  max-height: 31dvh;
}
.ks-comments__item {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  gap: 8px;
  align-items: flex-start;
  padding: 8px;
  border-radius: var(--md-shape-s);
}
.ks-comments__item + .ks-comments__item {
  margin-top: 4px;
}
.ks-comments__item:hover {
  background: rgba(var(--v-theme-primary), 0.04);
}
.ks-comments__avatar {
  margin-top: 2px;
}
.ks-comments__content {
  min-width: 0;
}
.ks-comments__meta-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;
}
.ks-comments__author {
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ks-comments__meta {
  color: rgba(var(--v-theme-on-surface), 0.62);
  flex-shrink: 0;
}
.ks-comments__body {
  margin: 4px 0 0;
  white-space: pre-wrap;
  color: rgba(var(--v-theme-on-surface), 0.88);
}
.ks-comments__delete {
  margin-top: 1px;
}
.ks-comments__more {
  padding: 6px 8px 4px;
  text-align: center;
  color: rgba(var(--v-theme-on-surface), 0.55);
}
</style>
