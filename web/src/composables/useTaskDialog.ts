import { computed, nextTick, onBeforeUnmount, ref, watch, type Ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useDisplay } from 'vuetify'
import { useAuthStore } from '@/stores/auth'
import { useBoardStore, type Attachment, type Task, type TiptapDoc } from '@/stores/board'
import { useTaskCollab } from '@/composables/useTaskCollab'
import { collabUserColor } from '@/utils/collab'
import { clipboardImageFiles } from '@/utils/clipboard'
import { eachDayOfInterval, format, isValid, parse } from 'date-fns'

type TaskFormState = {
  title: string
  start_date: string | null
  end_date: string | null
  task_type_id: string | null
  assignee_id: string | null
}

export function useTaskDialog(opts: {
  fileInput: Ref<HTMLInputElement | null>
  richEditorRef: Ref<{ getJSON: () => TiptapDoc; focus: () => boolean } | null>
  onDeletedByOther: (text: string) => void
}) {
  const { fileInput, richEditorRef, onDeletedByOther } = opts
  const route = useRoute()
  const router = useRouter()
  const { mobile } = useDisplay()
  const auth = useAuthStore()
  const board = useBoardStore()

  const taskTargetId = ref<string | null>(null)

  const collab = useTaskCollab({
    taskTargetId,
    richEditorRef,
    onLocalSettle: () => beginSave(),
  })

  const taskDialog = ref(false)
  const taskTarget = ref<Task | null>(null)
  const taskTitle = ref('')
  const taskStartDate = ref<string | null>(null)
  const taskEndDate = ref<string | null>(null)
  const taskType = ref<string | null>(null)
  const taskAssignee = ref<string | null>(null)
  const taskColumn = ref<string | null>(null)
  let changeColumnTimer: ReturnType<typeof setTimeout> | null = null
  const taskUploading = ref(false)
  const taskUploadProgress = ref(0)
  const taskSaving = ref(false)
  const taskSyncing = ref(false)
  let taskSaveTimer: ReturnType<typeof setTimeout> | null = null
  let formSaving = false
  let taskSaveQueued = false
  let savingCount = 0
  let savingStartedAt = 0

  const editingDescription = ref(false)
  const metaOpen = ref(false)
  const copiedSnack = ref(false)

  const slug = computed(() => route.params.slug as string)

  const currentTask = computed<Task | null>(() => {
    if (!taskTargetId.value) return null
    return board.tasks.find((t) => t.id === taskTargetId.value) ?? null
  })

  const shortTaskId = computed(
    () => currentTask.value?.id.slice(0, 8) ?? taskTargetId.value?.slice(0, 8) ?? '',
  )

  const collabUser = computed(() => {
    const u = auth.user
    if (!u) return null
    return {
      name: u.display_name || u.email?.split('@')[0] || 'Гость',
      color: collabUserColor(u.id),
    }
  })

  const taskAttachments = computed<Attachment[]>(() => {
    return taskTarget.value ? board.attachmentsFor(taskTarget.value.id) : []
  })

  const taskViewers = computed(() => {
    const selfId = auth.user?.id
    return Object.keys(collab.taskDocPresences.value)
      .filter((id) => id !== selfId)
      .map((id) => board.users.find((u) => u.id === id))
      .filter((u): u is NonNullable<typeof u> => !!u)
  })

  const taskDateRangeModel = computed<Date[]>({
    get: () => {
      const start = parseIsoDate(taskStartDate.value)
      const end = parseIsoDate(taskEndDate.value)
      if (start && end) return buildDateRange(start, end)
      if (start) return [start]
      if (end) return [end]
      return []
    },
    set: (value) => {
      if (!value || value.length === 0) {
        taskStartDate.value = null
        taskEndDate.value = null
        return
      }
      const sorted = [...value].sort((a, b) => a.getTime() - b.getTime())
      taskStartDate.value = formatIsoDate(sorted[0])
      taskEndDate.value = formatIsoDate(sorted[sorted.length - 1])
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

  function getTaskFormState(): TaskFormState {
    return {
      title: taskTitle.value.trim(),
      start_date: taskStartDate.value,
      end_date: taskEndDate.value,
      task_type_id: taskType.value,
      assignee_id: taskAssignee.value,
    }
  }

  function getTaskServerState(task: Task): TaskFormState {
    return {
      title: task.title,
      start_date: task.start_date ?? null,
      end_date: task.end_date ?? null,
      task_type_id: task.task_type_id ?? null,
      assignee_id: task.assignee_id ?? null,
    }
  }

  function isFormSyncedWithTask(task: Task): boolean {
    const form = getTaskFormState()
    const server = getTaskServerState(task)
    return (
      form.title === server.title &&
      form.start_date === server.start_date &&
      form.end_date === server.end_date &&
      form.task_type_id === server.task_type_id &&
      form.assignee_id === server.assignee_id
    )
  }

  function beginSave() {
    if (savingCount === 0) savingStartedAt = Date.now()
    savingCount++
    taskSaving.value = true
  }

  async function endSave() {
    savingCount--
    if (savingCount > 0) return
    const elapsed = Date.now() - savingStartedAt
    const remaining = Math.max(0, 1600 - elapsed)
    if (remaining > 0) await new Promise((resolve) => setTimeout(resolve, remaining))
    if (savingCount === 0) taskSaving.value = false
  }

  async function saveTask() {
    if (!currentTask.value) return
    if (formSaving) {
      taskSaveQueued = true
      return
    }
    if (isFormSyncedWithTask(currentTask.value)) return

    const payload = getTaskFormState()
    formSaving = true
    beginSave()
    try {
      await board.updateTask(currentTask.value.id, {
        title: payload.title,
        start_date: payload.start_date,
        end_date: payload.end_date,
        task_type_id: payload.task_type_id,
        assignee_id: payload.assignee_id,
      })
    } catch (err: any) {
      alert(err?.message || 'Ошибка сохранения задачи')
    } finally {
      formSaving = false
      void endSave()
      if (taskSaveQueued) {
        taskSaveQueued = false
        if (taskDialog.value && currentTask.value && board.canWrite) {
          void saveTask()
        }
      }
    }
  }

  function changeColumn(newColumnId: string | null) {
    if (!currentTask.value || !newColumnId || newColumnId === currentTask.value.column_id) return
    if (changeColumnTimer) clearTimeout(changeColumnTimer)
    changeColumnTimer = setTimeout(() => {
      const colTasks = board.tasksFor(newColumnId)
      const lastId = colTasks.length ? colTasks[colTasks.length - 1].id : null
      board.moveTask(currentTask.value!.id, newColumnId, lastId, null).catch((e) => {
        console.warn('[task-dialog] move task failed', e)
      })
    }, 300)
  }

  async function openTask(task: Task) {
    taskTargetId.value = task.id
    const actualTask = board.tasks.find((t) => t.id === task.id) ?? task
    taskTarget.value = actualTask
    taskSyncing.value = true
    taskTitle.value = actualTask.title
    taskStartDate.value = actualTask.start_date ?? null
    taskEndDate.value = actualTask.end_date ?? null
    taskType.value = actualTask.task_type_id ?? null
    taskAssignee.value = actualTask.assignee_id ?? null
    editingDescription.value = false
    taskSyncing.value = false
    taskDialog.value = true

    await collab.setupCollab(actualTask.id)
  }

  function closeTaskDialog() {
    if (taskSaveTimer) {
      clearTimeout(taskSaveTimer)
      taskSaveTimer = null
    }
    taskDialog.value = false
    taskTargetId.value = null
    collab.tearDownCollab()
  }

  async function editDescription() {
    editingDescription.value = true
    await nextTick()
    richEditorRef.value?.focus()
  }

  function onDescriptionBlur() {
    collab.onDescriptionBlur()
  }

  function openTaskPage() {
    if (!taskTarget.value) return
    void router.push({ name: 'task', params: { slug: slug.value, taskId: taskTarget.value.id } })
  }

  async function copyTaskLink() {
    if (!taskTarget.value) return
    const href = `${window.location.origin}/p/${slug.value}/tasks/${taskTarget.value.id}`
    if (navigator && navigator.clipboard) {
      await navigator.clipboard.writeText(href)
    }
  }

  async function copyTaskId() {
    const id = currentTask.value?.id || taskTargetId.value
    if (id && navigator && navigator.clipboard) {
      await navigator.clipboard.writeText(id)
      copiedSnack.value = true
    }
  }

  async function deleteCurrentTask() {
    if (!taskTarget.value) return
    try {
      await board.deleteTask(taskTarget.value.id)
      closeTaskDialog()
    } catch (e) {
      console.warn('[board] delete task failed', e)
    }
  }

  async function pickAttachment() {
    fileInput.value?.click()
  }

  async function onAttachmentPicked(e: Event) {
    const input = e.target as HTMLInputElement
    const files = Array.from(input.files ?? [])
    input.value = ''
    if (!taskTarget.value) return
    await uploadTaskFiles(taskTarget.value.id, files)
  }

  async function uploadTaskFiles(taskId: string, files: File[]) {
    for (const file of files) {
      taskUploading.value = true
      taskUploadProgress.value = 0
      try {
        await board.uploadTaskAttachment(taskId, file, (f) => {
          taskUploadProgress.value = f
        })
      } catch (err) {
        console.warn('[board] upload failed', err)
      } finally {
        taskUploading.value = false
        taskUploadProgress.value = 0
      }
    }
  }

  async function onTaskPaste(e: ClipboardEvent) {
    if (!board.canWrite || !taskTarget.value) return
    const files = clipboardImageFiles(e)
    if (!files.length) return
    e.preventDefault()
    await uploadTaskFiles(taskTarget.value.id, files)
  }

  async function removeAttachmentClick(att: Attachment) {
    if (!confirm(`Удалить «${att.filename}»?`)) return
    try {
      await board.deleteTaskAttachment(att.id)
    } catch (e) {
      console.warn('[board] delete attachment failed', e)
    }
  }

  function fmtSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`
  }

  watch(taskDialog, (open) => {
    if (open) return
    if (!taskTargetId.value) return
    closeTaskDialog()
  })

  watch(
    () => board.lastTaskDeleted,
    (evt) => {
      if (!evt) return
      if (evt.deleted_by_id === auth.user?.id) return
      if (!taskDialog.value || !taskTargetId.value) return
      if (evt.id !== taskTargetId.value) return

      const actor = evt.deleted_by_display_name || evt.deleted_by_email?.split('@')[0] || 'Пользователь'
      const title = evt.title || 'без названия'
      onDeletedByOther(`${actor} удалил задачу ${title}`)
      closeTaskDialog()
    },
    { deep: true },
  )

  watch(
    () => currentTask.value,
    (task) => {
      if (!task || !taskDialog.value) return
      taskSyncing.value = true
      taskTarget.value = task
      taskTitle.value = task.title
      taskStartDate.value = task.start_date ?? null
      taskEndDate.value = task.end_date ?? null
      taskType.value = task.task_type_id ?? null
      taskAssignee.value = task.assignee_id ?? null
      taskColumn.value = task.column_id
      setTimeout(() => {
        taskSyncing.value = false
      }, 0)
    },
    { deep: true },
  )

  watch(
    () => [
      taskDialog.value,
      taskTargetId.value,
      taskTitle.value,
      taskStartDate.value,
      taskEndDate.value,
      taskType.value,
      taskAssignee.value,
    ],
    () => {
      if (!taskDialog.value || !currentTask.value || !board.canWrite) return
      if (taskSyncing.value) return
      if (isFormSyncedWithTask(currentTask.value)) return
      if (taskSaveTimer) clearTimeout(taskSaveTimer)
      taskSaveTimer = setTimeout(() => {
        void saveTask()
      }, 450)
    },
  )

  onBeforeUnmount(() => {
    collab.tearDownCollab()
    if (taskSaveTimer) clearTimeout(taskSaveTimer)
    if (changeColumnTimer) clearTimeout(changeColumnTimer)
  })

  return {
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
    taskYDoc: collab.taskYDoc,
    taskAwareness: collab.taskAwareness,
    editingDescription,
    metaOpen,
    copiedSnack,
    collabUser,
    taskAttachments,
    taskViewers,
    shortTaskId,
    taskDateRangeModel,
    mobile,
    board,
    auth,
    open: openTask,
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
  }
}
