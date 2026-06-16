<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { PhArrowBendUpLeft, PhPaperclip, PhX, PhFile } from '@phosphor-icons/vue'
import { useAuthStore } from '@/stores/auth'
import { useBoardStore, type TaskComment, type TiptapDoc } from '@/stores/board'
import { isDocEmpty } from '@/utils/tiptap'
import RichEditor from '@/components/RichEditor.vue'
import CommentItem from '@/components/CommentItem.vue'

const props = defineProps<{
  taskId: string
}>()

const auth = useAuthStore()
const board = useBoardStore()

const emptyDoc: TiptapDoc = { type: 'doc', content: [] }

interface PendingFile {
  file: File
  preview: string | null
}

const draft = ref<TiptapDoc>(structuredClone(emptyDoc))
const guestBody = ref('')
const guestName = ref('')
const pendingFiles = ref<PendingFile[]>([])
const replyTo = ref<TaskComment | null>(null)
const sending = ref(false)
const uploading = ref(false)
const guestCooldownUntil = ref(0)
const nowTs = ref(Date.now())
const fileInput = ref<HTMLInputElement | null>(null)
let cooldownTimer: ReturnType<typeof setInterval> | null = null

const comments = computed(() => board.commentsFor(props.taskId))

const sortedAsc = computed(() => [...comments.value].sort((a, b) => sortKey(a) - sortKey(b)))

const rootComments = computed(() => sortedAsc.value.filter((c) => !c.parent_id))

const repliesByParent = computed(() => {
  const map = new Map<string, TaskComment[]>()
  for (const c of sortedAsc.value) {
    if (!c.parent_id) continue
    const list = map.get(c.parent_id) ?? []
    list.push(c)
    map.set(c.parent_id, list)
  }
  return map
})

function repliesOf(id: string): TaskComment[] {
  return repliesByParent.value.get(id) ?? []
}

function sortKey(c: TaskComment): number {
  return c.inserted_at ? Date.parse(c.inserted_at) : 0
}

function authorLabel(comment: TaskComment): string {
  if (comment.author_display_name) return comment.author_display_name
  if (comment.author_email) return comment.author_email.split('@')[0]
  return comment.guest_name?.trim() || 'Гость'
}

const canGuestComment = computed(() => board.settings.allow_guest_comments)
const canSend = computed(() => auth.isAuthed || canGuestComment.value)
const cooldownActive = computed(() => !auth.isAuthed && nowTs.value < guestCooldownUntil.value)
const cooldownSeconds = computed(() =>
  Math.max(0, Math.ceil((guestCooldownUntil.value - nowTs.value) / 1000)),
)

const hasContent = computed(() => {
  if (auth.isAuthed) return !isDocEmpty(draft.value) || pendingFiles.value.length > 0
  return guestBody.value.trim().length > 0
})

function startReply(comment: TaskComment) {
  replyTo.value = comment
}

function cancelReply() {
  replyTo.value = null
}

function pickFiles() {
  fileInput.value?.click()
}

function onFilesPicked(e: Event) {
  const input = e.target as HTMLInputElement
  const added: PendingFile[] = Array.from(input.files ?? []).map((file) => ({
    file,
    preview: file.type.startsWith('image/') ? URL.createObjectURL(file) : null,
  }))
  pendingFiles.value = [...pendingFiles.value, ...added]
  input.value = ''
}

function removePendingFile(index: number) {
  const item = pendingFiles.value[index]
  if (item?.preview) URL.revokeObjectURL(item.preview)
  pendingFiles.value = pendingFiles.value.filter((_, i) => i !== index)
}

function clearPending() {
  for (const item of pendingFiles.value) {
    if (item.preview) URL.revokeObjectURL(item.preview)
  }
  pendingFiles.value = []
}

function resetComposer() {
  draft.value = structuredClone(emptyDoc)
  guestBody.value = ''
  clearPending()
  replyTo.value = null
}

async function submitComment() {
  if (!canSend.value || !hasContent.value) return
  if (sending.value || cooldownActive.value) return

  const guestText = guestBody.value.trim()
  if (!auth.isAuthed && guestText.length > 255) return

  sending.value = true
  try {
    const created = await board.createTaskComment(props.taskId, {
      body_doc: auth.isAuthed ? draft.value : undefined,
      body: auth.isAuthed ? undefined : guestText,
      parentId: replyTo.value?.id ?? null,
      guestName: auth.isAuthed ? null : guestName.value.trim() || null,
    })

    const files = pendingFiles.value.map((p) => p.file)
    resetComposer()

    if (auth.isAuthed && files.length > 0) {
      uploading.value = true
      for (const file of files) {
        try {
          await board.uploadCommentAttachment(created.id, file)
        } catch (err) {
          console.warn('[comment] upload failed', err)
        }
      }
      uploading.value = false
    }

    if (!auth.isAuthed) guestCooldownUntil.value = Date.now() + 4000
  } catch (e: unknown) {
    const message = e instanceof Error ? e.message : 'Не удалось отправить комментарий'
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

onMounted(() => {
  cooldownTimer = setInterval(() => {
    nowTs.value = Date.now()
  }, 1000)
})

onBeforeUnmount(() => {
  if (cooldownTimer) clearInterval(cooldownTimer)
  clearPending()
})
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

      <div v-if="replyTo" class="ks-comments__reply-chip">
        <PhArrowBendUpLeft :size="15" />
        <span class="md-label-medium">Ответ для {{ authorLabel(replyTo) }}</span>
        <button type="button" class="ks-comments__chip-x" @click="cancelReply">
          <PhX :size="13" />
        </button>
      </div>

      <RichEditor
        v-if="auth.isAuthed"
        v-model="draft"
        :headings="false"
        compact
        bubble
        placeholder="Написать комментарий…"
      />
      <v-textarea
        v-else
        v-model="guestBody"
        label="Написать комментарий"
        density="comfortable"
        variant="filled"
        rows="3"
        hide-details
        auto-grow
        :maxlength="255"
        :readonly="!canSend"
        :hint="
          !canSend
            ? 'Только авторизованные пользователи могут оставлять комментарии'
            : `Для гостей: до 255 символов и пауза 4 сек. ${cooldownActive ? `Подождите ${cooldownSeconds} сек.` : ''}`
        "
        :persistent-hint="!canSend"
      />

      <div v-if="pendingFiles.length" class="ks-comments__pending">
        <div
          v-for="(item, i) in pendingFiles"
          :key="`${item.file.name}-${i}`"
          class="ks-comments__pending-item"
          :class="{ 'ks-comments__pending-item--image': item.preview }"
        >
          <img v-if="item.preview" :src="item.preview" :alt="item.file.name" />
          <template v-else>
            <PhFile :size="15" />
            <span class="ks-comments__pending-name md-label-medium">{{ item.file.name }}</span>
          </template>
          <button type="button" class="ks-comments__chip-x" @click="removePendingFile(i)">
            <PhX :size="12" />
          </button>
        </div>
      </div>

      <input
        ref="fileInput"
        type="file"
        multiple
        accept="image/*,video/*,.pdf,.zip,.txt,.md"
        class="ks-comments__file-input"
        @change="onFilesPicked"
      />

      <div class="ks-comments__actions">
        <v-btn v-if="auth.isAuthed" variant="text" size="small" rounded="pill" @click="pickFiles">
          <template #prepend><PhPaperclip :size="16" /></template>
          Файл
        </v-btn>
        <v-spacer />
        <v-btn
          color="primary"
          variant="flat"
          size="small"
          rounded="pill"
          :loading="sending || uploading"
          :disabled="!canSend || !hasContent || cooldownActive"
          @click="submitComment"
        >
          {{ replyTo ? 'Ответить' : 'Отправить' }}
        </v-btn>
      </div>
    </div>

    <div v-if="comments.length === 0" class="ks-comments__empty md-body-small">
      Пока комментариев нет.
    </div>
    <div v-else v-auto-animate class="ks-comments__list">
      <template v-for="root in rootComments" :key="root.id">
        <CommentItem :comment="root" @reply="startReply" />
        <CommentItem
          v-for="reply in repliesOf(root.id)"
          :key="reply.id"
          :comment="reply"
          reply
          @reply="startReply"
        />
      </template>
    </div>
  </section>
</template>

<style scoped>
.ks-comments {
  display: grid;
  gap: 12px;
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
.ks-comments__reply-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  align-self: flex-start;
  padding: 4px 6px 4px 12px;
  border-radius: var(--md-shape-full, 999px);
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
}
.ks-comments__pending {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.ks-comments__pending-item {
  position: relative;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 5px 6px 5px 10px;
  border-radius: var(--md-shape-m, 12px);
  background: rgb(var(--v-theme-surface-container-high));
  color: rgb(var(--v-theme-on-surface));
}
.ks-comments__pending-item--image {
  padding: 0;
  overflow: hidden;
}
.ks-comments__pending-item--image img {
  display: block;
  width: 64px;
  height: 64px;
  object-fit: cover;
}
.ks-comments__pending-name {
  max-width: 160px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ks-comments__chip-x {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: none;
  background: transparent;
  color: inherit;
  cursor: pointer;
  padding: 2px;
  border-radius: var(--md-shape-full, 999px);
}
.ks-comments__pending-item--image .ks-comments__chip-x {
  position: absolute;
  top: 3px;
  right: 3px;
  background: rgba(var(--v-theme-surface), 0.85);
}
.ks-comments__chip-x:hover {
  background: rgba(var(--v-theme-on-surface), 0.12);
}
.ks-comments__file-input {
  display: none;
}
.ks-comments__actions {
  display: flex;
  align-items: center;
  gap: 8px;
}
.ks-comments__empty {
  color: rgba(var(--v-theme-on-surface), 0.65);
  text-align: center;
  padding: 10px 0;
}
.ks-comments__list {
  display: grid;
  gap: 2px;
  overflow-y: auto;
  overscroll-behavior: contain;
  max-height: 48dvh;
}
</style>
