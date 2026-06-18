<script setup lang="ts">
import { computed, ref } from 'vue'
import { PhDetective, PhFile } from '@phosphor-icons/vue'
import { format, isValid, parseISO } from 'date-fns'
import { ru } from 'date-fns/locale'
import { useAuthStore } from '@/stores/auth'
import { useBoardStore, type Attachment, type TaskComment } from '@/stores/board'
import { docPreview, docToHtml } from '@/utils/tiptap'

const props = defineProps<{
  comment: TaskComment
  reply?: boolean
}>()

const emit = defineEmits<{
  (e: 'reply', comment: TaskComment): void
}>()

const auth = useAuthStore()
const board = useBoardStore()

const expanded = ref(false)

const html = computed(() =>
  props.comment.body_doc ? docToHtml(props.comment.body_doc) : '',
)

const long = computed(() => {
  if (!props.comment.body_doc) return false
  return docPreview(props.comment.body_doc, 100000).length > 480
})

const images = computed(() =>
  (props.comment.attachments ?? []).filter((a) => a.kind === 'image' && a.url),
)
const files = computed(() =>
  (props.comment.attachments ?? []).filter((a) => a.kind !== 'image'),
)

function roleRank(role: string | null | undefined): number {
  if (role === 'superadmin') return 3
  if (role === 'admin') return 2
  if (role === 'user') return 1
  return 0
}

const canDelete = computed(() => {
  if (!auth.isAuthed || !auth.user) return false
  if (!props.comment.author_id) return true
  if (props.comment.author_id === auth.user.id) return true
  return roleRank(auth.user.role) > roleRank(props.comment.author_role)
})

const isGuest = computed(() => !props.comment.author_id)

const label = computed(() => {
  const c = props.comment
  if (c.author_display_name) return c.author_display_name
  if (c.author_email) return c.author_email.split('@')[0]
  return c.guest_name?.trim() || 'Гость'
})

const initial = computed(() => label.value.slice(0, 1).toUpperCase())

const dateLabel = computed(() => {
  const iso = props.comment.inserted_at
  if (!iso) return ''
  const parsed = parseISO(iso)
  return isValid(parsed) ? format(parsed, 'd MMM yyyy, HH:mm', { locale: ru }) : ''
})

const avatarSize = computed(() => (props.reply ? 26 : 30))

function fmtSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

async function remove() {
  if (!canDelete.value) return
  if (!confirm('Удалить комментарий?')) return
  try {
    await board.deleteTaskComment(props.comment.id)
  } catch (e: unknown) {
    alert(e instanceof Error ? e.message : 'Не удалось удалить комментарий')
  }
}

async function removeAttachment(att: Attachment) {
  if (!confirm(`Удалить «${att.filename}»?`)) return
  try {
    await board.deleteCommentAttachment(att.id)
  } catch (e) {
    console.warn('[comment] delete attachment failed', e)
  }
}
</script>

<template>
  <article class="ks-comment" :class="{ 'ks-comment--reply': reply }">
    <v-avatar :size="avatarSize" color="secondary-container" class="ks-comment__avatar">
      <PhDetective v-if="isGuest" :size="reply ? 14 : 16" weight="duotone" />
      <img
        v-else-if="comment.author_avatar_url"
        :src="comment.author_avatar_url"
        :alt="label"
        :width="avatarSize"
        :height="avatarSize"
      />
      <span v-else class="md-label-medium">{{ initial }}</span>
    </v-avatar>

    <div class="ks-comment__content">
      <div class="ks-comment__meta-row">
        <span class="ks-comment__author md-label-large">{{ label }}</span>
        <time class="ks-comment__time md-label-small">{{ dateLabel }}</time>
      </div>

      <div
        class="ks-comment__body md-body-medium"
        :class="{ 'ks-comment__body--clamped': long && !expanded }"
        v-html="html"
      />
      <button
        v-if="long"
        type="button"
        class="ks-comment__more md-label-small"
        @click="expanded = !expanded"
      >
        {{ expanded ? 'Свернуть' : 'Показать полностью' }}
      </button>

      <div v-if="images.length" class="ks-comment__images">
        <a
          v-for="a in images"
          :key="a.id"
          class="ks-comment__image"
          :href="a.url ?? undefined"
          target="_blank"
          rel="noopener"
        >
          <img :src="a.url ?? undefined" :alt="a.filename" loading="lazy" />
          <button
            v-if="auth.isAuthed"
            type="button"
            class="ks-comment__att-x"
            :title="`Удалить ${a.filename}`"
            @click.prevent="removeAttachment(a)"
          >
            ✕
          </button>
        </a>
      </div>

      <div v-if="files.length" class="ks-comment__files">
        <div v-for="a in files" :key="a.id" class="ks-comment__file">
          <PhFile :size="18" class="ks-comment__file-icon" />
          <a
            v-if="a.url"
            class="ks-comment__file-name"
            :href="a.url"
            target="_blank"
            rel="noopener"
            :download="a.filename"
          >
            {{ a.filename }}
          </a>
          <span v-else class="ks-comment__file-name">{{ a.filename }}</span>
          <span class="ks-comment__file-size md-label-small">{{ fmtSize(a.size) }}</span>
          <button
            v-if="auth.isAuthed"
            type="button"
            class="ks-comment__att-x ks-comment__att-x--inline"
            :title="`Удалить ${a.filename}`"
            @click="removeAttachment(a)"
          >
            ✕
          </button>
        </div>
      </div>

      <div class="ks-comment__actions">
        <button
          v-if="auth.isAuthed"
          type="button"
          class="ks-comment__action md-label-small"
          @click="emit('reply', comment)"
        >
          Ответить
        </button>
        <button
          v-if="canDelete"
          type="button"
          class="ks-comment__action ks-comment__action--danger md-label-small"
          @click="remove"
        >
          Удалить
        </button>
      </div>
    </div>
  </article>
</template>

<style scoped>
.ks-comment {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  gap: 10px;
  align-items: flex-start;
  padding: 10px 12px;
  border-radius: var(--md-shape-l, 16px);
  transition: background-color var(--md-duration-short3) var(--md-easing-standard);
}
.ks-comment:hover {
  background: rgb(var(--v-theme-surface-container-low));
}
.ks-comment--reply {
  padding-left: 10px;
}
.ks-comment__avatar {
  margin-top: 2px;
}
.ks-comment__content {
  min-width: 0;
}
.ks-comment__meta-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;
}
.ks-comment__author {
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ks-comment__time {
  color: rgba(var(--v-theme-on-surface), 0.55);
  flex-shrink: 0;
}
.ks-comment__body {
  margin-top: 4px;
  max-width: 70ch;
  color: rgb(var(--v-theme-on-surface));
}
.ks-comment__body--clamped {
  position: relative;
  max-height: 8.5rem;
  overflow: hidden;
}
.ks-comment__body--clamped::after {
  content: '';
  position: absolute;
  inset: auto 0 0 0;
  height: 2.5rem;
  background: linear-gradient(to bottom, transparent, rgb(var(--v-theme-surface)));
  pointer-events: none;
}
.ks-comment:hover .ks-comment__body--clamped::after {
  background: linear-gradient(to bottom, transparent, rgb(var(--v-theme-surface-container-low)));
}
.ks-comment__body :deep(p) {
  margin: 0 0 8px;
  line-height: 1.55;
}
.ks-comment__body :deep(p:last-child) {
  margin-bottom: 0;
}
.ks-comment__body :deep(ul),
.ks-comment__body :deep(ol) {
  padding-left: 20px;
  margin: 6px 0;
}
.ks-comment__body :deep(li) {
  margin: 2px 0;
}
.ks-comment__body :deep(blockquote) {
  border-left: 3px solid rgba(var(--v-theme-primary), 0.6);
  padding: 2px 12px;
  margin: 8px 0;
  color: rgba(var(--v-theme-on-surface), 0.78);
}
.ks-comment__body :deep(pre) {
  background: rgb(var(--v-theme-surface-container-high));
  border-radius: var(--md-shape-s);
  padding: 10px 12px;
  margin: 8px 0;
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 13px;
  line-height: 1.45;
  overflow-x: auto;
}
.ks-comment__body :deep(code) {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 0.9em;
  background: rgb(var(--v-theme-surface-container-high));
  border-radius: var(--md-shape-xs);
  padding: 1px 5px;
}
.ks-comment__body :deep(pre code) {
  background: transparent;
  padding: 0;
}
.ks-comment__body :deep(a) {
  color: rgb(var(--v-theme-primary));
  text-decoration: underline;
}
.ks-comment__more {
  margin-top: 4px;
  border: none;
  background: transparent;
  color: rgb(var(--v-theme-primary));
  cursor: pointer;
  padding: 2px 0;
}
.ks-comment__images {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 10px;
}
.ks-comment__image {
  position: relative;
  display: block;
  border-radius: var(--md-shape-m, 12px);
  overflow: hidden;
}
.ks-comment__image img {
  display: block;
  max-height: 160px;
  max-width: 240px;
  object-fit: cover;
}
.ks-comment__files {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-top: 10px;
}
.ks-comment__file {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  border-radius: var(--md-shape-m, 12px);
  background: rgb(var(--v-theme-surface-container-high));
}
.ks-comment__file-icon {
  color: rgb(var(--v-theme-on-surface-variant));
  flex-shrink: 0;
}
.ks-comment__file-name {
  color: rgb(var(--v-theme-on-surface));
  text-decoration: none;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
}
.ks-comment__file-name:hover {
  text-decoration: underline;
}
.ks-comment__file-size {
  color: rgba(var(--v-theme-on-surface), 0.55);
  flex-shrink: 0;
}
.ks-comment__att-x {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  border: none;
  border-radius: var(--md-shape-full, 999px);
  background: rgba(var(--v-theme-surface), 0.85);
  color: rgb(var(--v-theme-on-surface));
  cursor: pointer;
  font-size: 12px;
  line-height: 1;
}
.ks-comment__att-x:not(.ks-comment__att-x--inline) {
  position: absolute;
  top: 6px;
  right: 6px;
  opacity: 0;
  transition: opacity var(--md-duration-short3) var(--md-easing-standard);
}
.ks-comment__image:hover .ks-comment__att-x {
  opacity: 1;
}
.ks-comment__att-x--inline {
  background: transparent;
  flex-shrink: 0;
}
.ks-comment__att-x--inline:hover {
  background: rgba(var(--v-theme-on-surface), 0.1);
}
.ks-comment__actions {
  display: flex;
  gap: 14px;
  margin-top: 8px;
}
.ks-comment__action {
  border: none;
  background: transparent;
  color: rgba(var(--v-theme-on-surface), 0.65);
  cursor: pointer;
  padding: 0;
  transition: color var(--md-duration-short3) var(--md-easing-standard);
}
.ks-comment__action:hover {
  color: rgb(var(--v-theme-primary));
}
.ks-comment__action--danger:hover {
  color: rgb(var(--v-theme-error));
}
</style>
