<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useClerksStore, type Clerk, type ClerkProject } from '@/stores/clerks'
import {
  PhRobot,
  PhPlus,
  PhPencilSimple,
  PhArrowsClockwise,
  PhTrash,
  PhCopy,
  PhFolderPlus,
  PhBookOpen,
} from '@phosphor-icons/vue'

const clerks = useClerksStore()
const loading = ref(true)
const error = ref<string | null>(null)
const ownerProjects = ref<ClerkProject[]>([])

const clerkList = computed(() => clerks.list)

const dialog = ref(false)
const editing = ref<Clerk | null>(null)
const form = ref({ display_name: '', agent_role: '', agent_description: '' })
const saving = ref(false)
const formError = ref<string | null>(null)
const revealedToken = ref('')
const agentsInstruction = `## Kaska Tracker

This project uses Kaska as the task tracker.

Before starting any implementation work:

1. Read the Kaska clerk briefing: https://app.kaska.space/clerk-briefing.md
2. Load tracker settings and credentials from the local clerk.yml file, if it exists. The public briefing must not contain secrets; tokens should come from clerk.yml, environment variables, or local secret files referenced by clerk.yml.
3. If the user provided a Kaska task URL or task id, read that task before editing files.
4. Read the project metadata from Kaska before moving tasks. Column names and workflow steps are project-specific, so do not assume fixed names like todo, in progress, ready to prod, or done. Use column descriptions, project instructions, or workflow metadata returned by Kaska to identify the correct columns.
5. When you begin work on a task, move it to the project's currently-being-worked-on column and add a short comment saying what you are starting.
6. When the implementation and relevant checks are complete, move the task to the project's ready-for-review or ready-for-production column and add a short comment summarizing what changed and what was verified.
7. Never move a task to the final completed/done column unless the user explicitly asks you to. Final acceptance belongs to the user.
8. If the task already appears to be actively worked on by another agent, do not take it over unless the user explicitly instructed you to do so.

Prefer the Kaska MCP server or a project-provided Kaska CLI when available. Use the REST API described in the clerk briefing as the fallback.`

const uploadingId = ref<string | null>(null)
const avatarTargetId = ref<string | null>(null)
const fileInput = ref<HTMLInputElement | null>(null)

onMounted(async () => {
  try {
    await clerks.join()
    ownerProjects.value = await clerks.listProjects()
  } catch {
    error.value = 'Не удалось загрузить клерков'
  } finally {
    loading.value = false
  }
})

function initial(s: Clerk) {
  return (s.display_name ?? 'A').slice(0, 1).toUpperCase()
}

function openCreate() {
  editing.value = null
  form.value = { display_name: '', agent_role: '', agent_description: '' }
  formError.value = null
  revealedToken.value = ''
  dialog.value = true
}

function openEdit(s: Clerk) {
  editing.value = s
  form.value = {
    display_name: s.display_name ?? '',
    agent_role: s.agent_role ?? '',
    agent_description: s.agent_description ?? '',
  }
  formError.value = null
  revealedToken.value = ''
  dialog.value = true
}

async function submit() {
  const name = form.value.display_name.trim()
  if (!name) return
  saving.value = true
  formError.value = null
  try {
    const payload = {
      display_name: name,
      agent_role: form.value.agent_role.trim() || null,
      agent_description: form.value.agent_description.trim() || null,
    }
    if (editing.value) {
      await clerks.updateClerk(editing.value.id, payload)
      dialog.value = false
    } else {
      const { token } = await clerks.createClerk(payload)
      revealedToken.value = token
    }
  } catch (e: unknown) {
    formError.value = (e as { message?: string })?.message || 'Не удалось сохранить'
  } finally {
    saving.value = false
  }
}

async function regenerate(s: Clerk) {
  if (!confirm(`Новый токен для «${s.display_name}»? Старый перестанет работать.`)) return
  const token = await clerks.regenerateToken(s.id)
  editing.value = s
  form.value = {
    display_name: s.display_name ?? '',
    agent_role: s.agent_role ?? '',
    agent_description: s.agent_description ?? '',
  }
  revealedToken.value = token
  dialog.value = true
}

async function removeClerk(s: Clerk) {
  if (!confirm(`Удалить клерка «${s.display_name}»? Он покинет все проекты, токены отзовутся.`))
    return
  await clerks.deleteClerk(s.id)
}

function pickAvatar(s: Clerk) {
  avatarTargetId.value = s.id
  fileInput.value?.click()
}

async function onAvatarPicked(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  const id = avatarTargetId.value
  input.value = ''
  if (!file || !id) return
  uploadingId.value = id
  try {
    await clerks.uploadAvatar(id, file)
  } catch {
    error.value = 'Не удалось загрузить аватар'
  } finally {
    uploadingId.value = null
  }
}

function availableProjects(s: Clerk) {
  const assigned = new Set(s.projects.map((p) => p.id))
  return ownerProjects.value.filter((p) => !assigned.has(p.id))
}

function copy(text: string) {
  if (navigator?.clipboard) void navigator.clipboard.writeText(text)
}
</script>

<template>
  <div class="pa-4 pa-sm-6 pa-md-8 mx-auto" style="max-width: 1100px">
    <div class="d-flex align-center justify-space-between mb-2">
      <h1 class="md-headline-medium d-flex align-center">
        <ph-robot :size="28" weight="regular" class="mr-3" />
        Клерки
      </h1>
      <v-btn color="primary" @click="openCreate">
        <template #prepend><ph-plus :size="20" weight="bold" /></template>
        Создать клерка
      </v-btn>
    </div>

    <p class="md-body-medium text-medium-emphasis mb-6">
      Клерк — твой агент-бот с позывным, характеристикой и токеном для REST/MCP. Назначай клерков в
      проекты; их комментарии и действия видны от их лица.
    </p>

    <v-expansion-panels variant="accordion" class="mb-6">
      <v-expansion-panel rounded="lg">
        <v-expansion-panel-title>
          <div class="d-flex align-center" style="gap: 12px">
            <ph-book-open :size="22" weight="regular" />
            <span class="md-title-medium">Как подключить агентов к Kaska</span>
          </div>
        </v-expansion-panel-title>
        <v-expansion-panel-text>
          <div class="md-body-medium text-medium-emphasis mb-4">
            Создай клерка, назначь его в нужные проекты и передай токен агенту через локальный
            `clerk.yml`, переменную окружения или секретный файл. В `AGENTS.md`, `CLAUDE.md` или
            аналогичный файл проекта добавь этот блок, чтобы агент сам читал инструкцию, брал задачу
            в работу и возвращал её на проверку.
          </div>
          <v-textarea
            :model-value="agentsInstruction"
            readonly
            variant="filled"
            density="compact"
            rows="14"
            auto-grow
            hide-details
            class="ks-instruction-textarea"
          >
            <template #append-inner>
              <v-btn
                variant="text"
                size="small"
                :icon="true"
                title="Скопировать"
                @click="copy(agentsInstruction)"
              >
                <ph-copy :size="18" weight="bold" />
              </v-btn>
            </template>
          </v-textarea>
        </v-expansion-panel-text>
      </v-expansion-panel>
    </v-expansion-panels>

    <v-alert v-if="error" type="error" variant="tonal" class="mb-4">{{ error }}</v-alert>

    <div v-if="loading" class="d-flex justify-center py-12">
      <v-progress-circular indeterminate color="primary" />
    </div>

    <v-card
      v-else-if="!clerkList.length"
      variant="outlined"
      class="text-center py-12 md-body-medium text-medium-emphasis"
    >
      Пока нет клерков. Создай первого — он получит токен для подключения по MCP.
    </v-card>

    <div
      v-else
      class="grid gap-4"
      style="grid-template-columns: repeat(auto-fill, minmax(320px, 1fr))"
    >
      <v-card v-for="s in clerkList" :key="s.id" variant="outlined" rounded="xl" class="pa-4">
        <div class="d-flex align-start" style="gap: 16px">
          <button
            type="button"
            class="ks-avatar-btn"
            :title="'Сменить аватар'"
            @click="pickAvatar(s)"
          >
            <v-avatar size="56" color="secondary">
              <img v-if="s.avatar_url" :src="s.avatar_url" width="56" height="56" />
              <span v-else class="text-white md-title-medium">{{ initial(s) }}</span>
            </v-avatar>
            <span v-if="uploadingId === s.id" class="ks-avatar-loading">
              <v-progress-circular indeterminate size="22" width="2" color="on-secondary" />
            </span>
          </button>

          <div class="flex-grow-1" style="min-width: 0">
            <div class="md-title-medium text-truncate">
              {{ s.display_name }}
            </div>
            <v-chip v-if="s.agent_role" size="x-small" color="tertiary" class="mt-1">
              {{ s.agent_role }}
            </v-chip>
            <p v-if="s.agent_description" class="md-body-small text-medium-emphasis mt-2 mb-0">
              {{ s.agent_description }}
            </p>
          </div>
        </div>

        <div class="d-flex flex-wrap align-center mt-4" style="gap: 8px">
          <v-chip
            v-for="p in s.projects"
            :key="p.id"
            size="small"
            closable
            @click:close="clerks.unassignProject(s.id, p.id)"
          >
            {{ p.name }}
          </v-chip>
          <v-menu v-if="availableProjects(s).length">
            <template #activator="{ props }">
              <v-chip v-bind="props" size="small" variant="outlined">
                <ph-folder-plus :size="14" weight="bold" class="mr-1" />
                проект
              </v-chip>
            </template>
            <v-list density="compact" rounded="lg">
              <v-list-item
                v-for="p in availableProjects(s)"
                :key="p.id"
                :title="p.name"
                @click="clerks.assignProject(s.id, p.id)"
              />
            </v-list>
          </v-menu>
          <span
            v-if="!s.projects.length && !availableProjects(s).length"
            class="md-body-small text-medium-emphasis"
          >
            нет доступных проектов
          </span>
        </div>

        <div class="d-flex justify-end mt-3" style="gap: 4px">
          <v-btn variant="text" size="small" :icon="true" title="Профиль" @click="openEdit(s)">
            <ph-pencil-simple :size="18" weight="regular" />
          </v-btn>
          <v-btn
            variant="text"
            size="small"
            :icon="true"
            title="Новый токен"
            @click="regenerate(s)"
          >
            <ph-arrows-clockwise :size="18" weight="regular" />
          </v-btn>
          <v-btn
            variant="text"
            size="small"
            :icon="true"
            color="error"
            title="Удалить"
            @click="removeClerk(s)"
          >
            <ph-trash :size="18" weight="regular" />
          </v-btn>
        </div>
      </v-card>
    </div>

    <input ref="fileInput" type="file" accept="image/*" hidden @change="onAvatarPicked" />

    <v-dialog v-model="dialog" max-width="520">
      <v-card rounded="xl">
        <v-card-title class="md-headline-small px-6 pt-6">
          {{ editing ? 'Клерк' : 'Новый клерк' }}
        </v-card-title>
        <v-card-text class="px-6 pt-2 flex flex-col gap-4">
          <v-text-field
            v-model="form.display_name"
            label="Позывной"
            placeholder="например, Клод"
            variant="filled"
            density="comfortable"
            autofocus
            hide-details
            @keydown.enter.exact.prevent="submit"
          />
          <v-text-field
            v-model="form.agent_role"
            label="Характеристика"
            placeholder="например, ответственный за качество"
            variant="filled"
            density="comfortable"
            hide-details
          />
          <v-textarea
            v-model="form.agent_description"
            label="Описание"
            placeholder="Чем занимается этот клерк"
            variant="filled"
            density="comfortable"
            rows="3"
            auto-grow
            hide-details
          />
          <template v-if="revealedToken">
            <v-alert type="warning" variant="tonal" class="md-body-small">
              Токен показывается один раз — скопируй его сейчас.
            </v-alert>
            <v-text-field
              :model-value="revealedToken"
              readonly
              variant="filled"
              density="comfortable"
              hide-details
            >
              <template #append-inner>
                <v-btn variant="text" size="small" :icon="true" @click="copy(revealedToken)">
                  <ph-copy :size="18" weight="bold" />
                </v-btn>
              </template>
            </v-text-field>
          </template>
          <v-alert v-if="formError" type="error" variant="tonal">{{ formError }}</v-alert>
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-spacer />
          <v-btn variant="text" rounded="pill" @click="dialog = false">Закрыть</v-btn>
          <v-btn
            color="primary"
            variant="flat"
            rounded="pill"
            :loading="saving"
            :disabled="!form.display_name.trim()"
            @click="submit"
          >
            {{ editing ? 'Сохранить' : 'Создать' }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.ks-avatar-btn {
  position: relative;
  border: none;
  background: none;
  padding: 0;
  cursor: pointer;
  border-radius: var(--md-shape-full);
}
.ks-avatar-loading {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-scrim) / 0.45);
}
.ks-instruction-textarea :deep(textarea) {
  font-family:
    ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New",
    monospace;
  font-size: 0.8125rem;
  line-height: 1.45;
}
</style>
