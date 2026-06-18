<script setup lang="ts">
import { ref } from 'vue'
import { useTaskDialog } from '@/composables/useTaskDialog'
import BoardTaskMeta from '@/components/board/BoardTaskMeta.vue'
import RichEditor from '@/components/RichEditor.vue'
import PresenceGroup from '@/components/PresenceGroup.vue'
import TaskCommentsSection from '@/components/TaskCommentsSection.vue'
import type { TiptapDoc } from '@/stores/board'

const emit = defineEmits<{ 'task-deleted-by-other': [text: string] }>()

const fileInput = ref<HTMLInputElement | null>(null)
const richEditorRef = ref<{ getJSON: () => TiptapDoc; focus: () => boolean } | null>(null)

const {
  taskDialog,
  taskTarget,
  taskTitle,
  taskStartDate,
  taskEndDate,
  taskType,
  taskAssignee,
  taskColumn,
  changeColumn,
  taskUploading,
  taskUploadProgress,
  taskSaving,
  taskYDoc,
  taskAwareness,
  editingDescription,
  metaOpen,
  copiedSnack,
  collabUser,
  taskAttachments,
  taskViewers,
  shortTaskId,
  mobile,
  board,
  open,
  closeTaskDialog,
  editDescription,
  onDescriptionBlur,
  openTaskPage,
  copyTaskLink,
  copyTaskId,
  pickAttachment,
  onAttachmentPicked,
  onTaskPaste,
  removeAttachmentClick,
  deleteCurrentTask,
  fmtSize,
} = useTaskDialog({ fileInput, richEditorRef, onDeletedByOther: (text) => emit('task-deleted-by-other', text) })

defineExpose({ open })
</script>

<template>
  <v-dialog
    v-model="taskDialog"
    max-width="1080"
    :fullscreen="mobile"
  >
    <v-card v-if="taskTarget" rounded="xl" class="ks-task-dialog">
      <header v-if="mobile" class="ks-task-mbar">
        <span class="md-title-large">Карточка</span>
        <v-tooltip text="Нажмите, чтобы скопировать ID" location="bottom">
          <template #activator="{ props: tipProps }">
            <span v-if="shortTaskId" v-bind="tipProps" class="ks-task-id md-label-large cursor-pointer" @click="copyTaskId">ID {{ shortTaskId }}</span>
          </template>
        </v-tooltip>
        <PresenceGroup
          v-if="taskViewers.length"
          class="ml-1"
          :users="taskViewers"
          label="Сейчас в задаче"
          size="sm"
        />
        <v-spacer />
        <v-btn icon="mdi-arrow-expand" variant="text" size="small" @click="openTaskPage" />
        <v-btn icon="mdi-link-variant" variant="text" size="small" @click="copyTaskLink" />
        <v-btn icon="mdi-close" variant="text" size="small" @click="closeTaskDialog" />
      </header>
      <div class="ks-task-split">
        <section class="ks-task-content" @paste.capture="onTaskPaste">
          <v-text-field
            v-model="taskTitle"
            label="Название"
            variant="filled"
            density="comfortable"
            :readonly="!board.canWrite"
          />

          <div class="ks-desc__head mt-2 mb-2">
            <div class="md-label-large">Описание</div>
            <v-btn
              v-if="board.canWrite && !editingDescription"
              variant="text"
              size="small"
              rounded="pill"
              prepend-icon="mdi-pencil-outline"
              @click="editDescription"
            >
              Редактировать
            </v-btn>
            <v-btn
              v-else-if="board.canWrite && editingDescription"
              variant="text"
              size="small"
              rounded="pill"
              prepend-icon="mdi-eye-outline"
              @click="editingDescription = false"
            >
              Просмотр
            </v-btn>
          </div>

          <RichEditor
            v-if="taskYDoc"
            ref="richEditorRef"
            :key="taskTarget.id ?? ''"
            :ydoc="taskYDoc"
            :awareness="taskAwareness"
            :user="collabUser"
            :editable="board.canWrite && editingDescription"
            placeholder="Опишите задачу — поддерживаются стили, списки, ссылки и блоки кода"
            @blur="onDescriptionBlur"
          />

          <div class="ks-attach__head mt-5 mb-2">
            <div class="md-label-large">Вложения</div>
            <v-btn
              v-if="board.canWrite"
              variant="tonal"
              rounded="pill"
              size="small"
              prepend-icon="mdi-paperclip"
              :loading="taskUploading"
              @click="pickAttachment"
            >
              Прикрепить файл
            </v-btn>
          </div>
          <v-progress-linear
            v-if="taskUploading"
            :model-value="taskUploadProgress * 100"
            color="primary"
            rounded
            height="6"
            class="mb-3"
          />
          <input
            ref="fileInput"
            type="file"
            multiple
            accept="image/*,video/*,.pdf,.zip,.txt,.md"
            class="ks-attach__input"
            @change="onAttachmentPicked"
          />

          <div v-if="taskAttachments.length === 0" class="ks-attach__empty md-body-small">
            Пока вложений нет.
          </div>

          <div v-else class="ks-attach__grid">
            <div
              v-for="a in taskAttachments"
              :key="a.id"
              class="ks-attach"
              :class="`ks-attach--${a.kind}`"
            >
              <div class="ks-attach__media">
                <img v-if="a.kind === 'image' && a.url" :src="a.url" :alt="a.filename" />
                <video
                  v-else-if="a.kind === 'video' && a.url"
                  :src="a.url"
                  controls
                  preload="metadata"
                />
                <div v-else class="ks-attach__file">
                  <v-icon size="32">mdi-file-outline</v-icon>
                </div>
              </div>
              <div class="ks-attach__meta">
                <a
                  v-if="a.url"
                  class="ks-attach__name md-body-medium"
                  :href="a.url"
                  target="_blank"
                  rel="noopener"
                >
                  {{ a.filename }}
                </a>
                <span v-else class="ks-attach__name md-body-medium">{{ a.filename }}</span>
                <span class="ks-attach__size md-label-medium">{{ fmtSize(a.size) }}</span>
              </div>
              <v-btn
                v-if="board.canWrite"
                icon="mdi-close"
                variant="text"
                density="comfortable"
                size="small"
                class="ks-attach__remove"
                @click="removeAttachmentClick(a)"
              />
            </div>
          </div>
          <TaskCommentsSection
            v-if="taskTarget"
            :task-id="taskTarget.id"
            class="ks-task-content__comments"
          />
        </section>

        <BoardTaskMeta
          :can-write="board.canWrite"
          :mobile="mobile"
          :task-saving="taskSaving"
          :short-task-id="shortTaskId"
          :task-viewers="taskViewers"
          :task-start-date="taskStartDate"
          :task-end-date="taskEndDate"
          :task-type="taskType"
          :task-assignee="taskAssignee"
          :task-column="taskColumn"
          :meta-open="metaOpen"
          @update:meta-open="metaOpen = $event"
          @update:task-start-date="taskStartDate = $event"
          @update:task-end-date="taskEndDate = $event"
          @update:task-type="taskType = $event"
          @update:task-assignee="taskAssignee = $event"
          @update:task-column="changeColumn($event)"
          @open-task-page="openTaskPage"
          @copy-task-link="copyTaskLink"
          @copy-task-id="copyTaskId"
          @delete-task="deleteCurrentTask"
          @close="closeTaskDialog"
        />
      </div>
    </v-card>
  </v-dialog>
  <v-snackbar v-model="copiedSnack" timeout="2000" location="bottom center" color="surface-container-high">
    UUID скопирован
  </v-snackbar>
</template>

<style scoped>
.ks-task-dialog {
  display: flex;
  flex-direction: column;
  height: 86vh;
  overflow: hidden;
}
.ks-task-split {
  flex: 1;
  min-height: 0;
  display: grid;
  grid-template-columns: minmax(0, 1fr) 360px;
}
.ks-task-content {
  min-width: 0;
  overflow-y: auto;
  padding: 16px 24px 24px;
}
.ks-task-content__comments {
  margin-top: 28px;
}
.ks-task-mbar {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 8px 10px 16px;
  border-bottom: 1px solid rgba(var(--v-theme-outline-variant), 0.6);
}
.ks-task-id {
  color: rgb(var(--v-theme-on-surface-variant));
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  white-space: nowrap;
}
.ks-desc__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.ks-attach__size {
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.ks-attach__input {
  display: none;
}

@media (max-width: 959px) {
  .ks-task-dialog {
    height: 100%;
  }
  .ks-task-split {
    grid-template-columns: 1fr;
    overflow-y: auto;
  }
  .ks-task-content {
    overflow-y: visible;
  }
}
</style>
