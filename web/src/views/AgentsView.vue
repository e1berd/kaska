<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { PhRobot, PhPlus, PhFolderPlus, PhKey } from '@phosphor-icons/vue'
import {
  useAgentsStore,
  type Agent,
  type AgentProject,
  type AgentInput,
  type AuthMethod,
} from '@/stores/agents'
import { useNow } from '@/composables/useNow'
import {
  PRESETS,
  PRESET_ORDER,
  RUN_STATUS,
  formatDuration,
  missingText,
  modelLine,
  runSeconds,
} from '@/utils/agents'

const agents = useAgentsStore()
const now = useNow()

const loading = ref(true)
const error = ref<string | null>(null)
const ownerProjects = ref<AgentProject[]>([])

const dialog = ref(false)
const tab = ref<'settings' | 'runs'>('settings')
const editingId = ref<string | null>(null)
const saving = ref(false)
const formError = ref<string | null>(null)
const replacingKey = ref(false)
const showBaseUrl = ref(false)
const runsLoading = ref(false)
const form = ref({
  display_name: '',
  provider_preset: null as string | null,
  auth_method: 'api_key' as AuthMethod,
  base_url: '',
  model: '',
  api_key: '',
  system_prompt: '',
})

const uploadingId = ref<string | null>(null)
const avatarTargetId = ref<string | null>(null)
const fileInput = ref<HTMLInputElement | null>(null)

const editing = computed<Agent | null>(
  () => agents.list.find((a) => a.id === editingId.value) ?? null,
)
const presetItems = computed(() =>
  PRESET_ORDER.map((slug) => ({ value: slug, title: PRESETS[slug].label, meta: PRESETS[slug] })),
)
const presetMeta = computed(() =>
  form.value.provider_preset ? PRESETS[form.value.provider_preset] : null,
)
const presetBaseUrl = computed(
  () => agents.presets.find((p) => p.slug === form.value.provider_preset)?.base_url ?? null,
)
const subscriptionAvailable = computed(() => !!presetMeta.value?.supportsSubscription)
const authMethod = computed<AuthMethod>(() =>
  subscriptionAvailable.value ? form.value.auth_method : 'api_key',
)
const authMethodChanged = computed(
  () => !!editing.value && editing.value.config.auth_method !== authMethod.value,
)
const keyFieldVisible = computed(
  () =>
    presetMeta.value?.needsKey !== false &&
    (!editing.value?.config.api_key_set || replacingKey.value || authMethodChanged.value),
)
const credentialLabel = computed(() =>
  authMethod.value === 'subscription' ? 'OAuth-токен подписки' : 'API-ключ',
)
const credentialHint = computed(() =>
  authMethod.value === 'subscription'
    ? 'Выполните claude setup-token в терминале и вставьте токен. Хранится зашифрованным'
    : 'Хранится зашифрованным, в интерфейсе больше не показывается',
)
const agentRuns = computed(() => (editingId.value ? agents.runsByAgent[editingId.value] ?? [] : []))
const limitText = computed(() =>
  agents.limits
    ? `Активных прогонов: ${agents.activeRuns} из ${agents.limits.max_active_runs_per_owner}`
    : null,
)

onMounted(async () => {
  try {
    await agents.join()
    ownerProjects.value = await agents.listProjects()
  } catch (e: unknown) {
    console.error('agents load failed', e)
    error.value = 'Не удалось загрузить агентов'
  } finally {
    loading.value = false
  }
})

watch(tab, async (value) => {
  if (value !== 'runs' || !editingId.value) return
  runsLoading.value = true
  try {
    await agents.loadRuns(editingId.value)
  } catch (e: unknown) {
    console.error('agent runs load failed', e)
    formError.value = 'Не удалось загрузить прогоны'
  } finally {
    runsLoading.value = false
  }
})

function onPresetChange(preset: string | null) {
  form.value.provider_preset = preset
  form.value.base_url = presetBaseUrl.value ?? ''
  showBaseUrl.value = !!presetMeta.value?.editableBaseUrl
}

function initial(a: Agent) {
  return (a.display_name ?? 'A').slice(0, 1).toUpperCase()
}

function openCreate() {
  editingId.value = null
  form.value = {
    display_name: '',
    provider_preset: 'anthropic',
    auth_method: 'api_key',
    base_url: '',
    model: '',
    api_key: '',
    system_prompt: '',
  }
  resetDialogState()
  dialog.value = true
}

function openEdit(a: Agent) {
  editingId.value = a.id
  form.value = {
    display_name: a.display_name ?? '',
    provider_preset: a.config.provider_preset,
    auth_method: a.config.auth_method,
    base_url: a.config.base_url ?? '',
    model: a.config.model ?? '',
    api_key: '',
    system_prompt: a.config.system_prompt ?? '',
  }
  resetDialogState()
  showBaseUrl.value = !!presetMeta.value?.editableBaseUrl
  dialog.value = true
}

function resetDialogState() {
  tab.value = 'settings'
  formError.value = null
  replacingKey.value = false
  showBaseUrl.value = false
}

function payload(): AgentInput {
  const input: AgentInput = {
    display_name: form.value.display_name.trim(),
    provider_preset: form.value.provider_preset,
    auth_method: authMethod.value,
    model: form.value.model.trim() || null,
    system_prompt: form.value.system_prompt.trim() || null,
  }
  if (showBaseUrl.value) input.base_url = form.value.base_url.trim() || null
  if (form.value.api_key.trim()) input.api_key = form.value.api_key.trim()
  return input
}

async function submit() {
  if (!form.value.display_name.trim()) return
  saving.value = true
  formError.value = null
  try {
    if (editingId.value) {
      await agents.updateAgent(editingId.value, payload())
    } else {
      await agents.createAgent(payload())
    }
    dialog.value = false
  } catch (e: unknown) {
    console.error('agent save failed', e)
    formError.value = 'Не удалось сохранить агента'
  } finally {
    saving.value = false
  }
}

async function removeAgent() {
  const agent = editing.value
  if (!agent) return
  if (!confirm(`Удалить агента «${agent.display_name}»? Идущие прогоны будут остановлены.`)) return
  await agents.deleteAgent(agent.id)
  dialog.value = false
}

function pickAvatar(a: Agent) {
  avatarTargetId.value = a.id
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
    await agents.uploadAvatar(id, file)
  } catch (err: unknown) {
    console.error('avatar upload failed', err)
    error.value = 'Не удалось загрузить аватар'
  } finally {
    uploadingId.value = null
  }
}

function availableProjects(a: Agent) {
  const assigned = new Set(a.projects.map((p) => p.id))
  return ownerProjects.value.filter((p) => !assigned.has(p.id))
}

function runDuration(run: { started_at: string | null; finished_at: string | null }) {
  const seconds = runSeconds(run, now.value)
  return seconds === null ? null : formatDuration(seconds)
}

function runWhen(iso: string) {
  return new Date(iso).toLocaleString('ru-RU', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  })
}
</script>

<template>
  <div class="pa-4 pa-sm-6 pa-md-8 mx-auto" style="max-width: 1100px">
    <div class="d-flex align-center justify-space-between mb-2 gap-4">
      <h1 class="md-headline-medium d-flex align-center">
        <ph-robot :size="28" weight="regular" class="mr-3" />
        Агенты
      </h1>
      <v-btn color="primary" @click="openCreate">
        <template #prepend><ph-plus :size="20" weight="bold" /></template>
        Создать агента
      </v-btn>
    </div>

    <p class="md-body-medium text-medium-emphasis mb-4">
      Агент работает над задачами в изолированном контейнере на сервере Kaska — со своей моделью и
      вашим ключом провайдера. Назначьте его в проект, сделайте исполнителем задачи и запустите с
      карточки.
    </p>

    <v-chip v-if="limitText" variant="outlined" class="mb-6">
      <span class="ks-dot mr-2" :class="{ 'ks-dot--active': agents.activeRuns > 0 }" />
      {{ limitText }}
    </v-chip>

    <v-alert v-if="error" type="error" variant="tonal" class="mb-4">{{ error }}</v-alert>

    <div v-if="loading" class="d-flex justify-center py-12">
      <v-progress-circular indeterminate color="primary" />
    </div>

    <v-card
      v-else-if="!agents.list.length"
      variant="outlined"
      class="text-center py-12 md-body-medium text-medium-emphasis"
    >
      Пока нет агентов. Создайте первого — выберите провайдера, модель и укажите ключ.
    </v-card>

    <div v-else class="grid gap-4 [grid-template-columns:repeat(auto-fill,minmax(320px,1fr))]">
      <v-card
        v-for="a in agents.list"
        :key="a.id"
        variant="outlined"
        rounded="lg"
        class="pa-4 d-flex flex-column gap-3"
      >
        <div class="d-flex align-start gap-4">
          <button type="button" class="ks-avatar-btn" title="Сменить аватар" @click="pickAvatar(a)">
            <v-avatar size="56" color="secondary">
              <img v-if="a.avatar_url" :src="a.avatar_url" width="56" height="56" alt="" />
              <span v-else class="text-on-secondary md-title-medium">{{ initial(a) }}</span>
            </v-avatar>
            <span v-if="uploadingId === a.id" class="ks-avatar-loading">
              <v-progress-circular indeterminate size="22" width="2" color="on-secondary" />
            </span>
          </button>
          <button type="button" class="ks-card-title flex-grow-1 min-w-0" @click="openEdit(a)">
            <span class="md-title-medium d-block text-truncate">{{ a.display_name }}</span>
            <span class="md-body-small text-medium-emphasis d-block text-truncate">
              {{ modelLine(a.config.provider_preset, a.config.model) }}
            </span>
          </button>
        </div>

        <router-link
          v-for="run in a.active_runs"
          :key="run.id"
          class="ks-run-link md-body-medium"
          :to="{ name: 'task', params: { slug: run.project_slug ?? '', taskId: run.task_id ?? '' } }"
        >
          <span class="ks-dot ks-dot--active" />
          <span class="text-truncate">
            {{ RUN_STATUS[run.status].label }}: {{ run.task_title ?? 'задача удалена' }}
          </span>
        </router-link>

        <span
          v-if="!a.active_runs.length && !a.config.ready"
          class="md-body-medium text-error d-flex align-center gap-2"
        >
          <v-icon size="18">mdi-alert-circle-outline</v-icon>
          {{ missingText(a.config.missing, a.config.auth_method) }}
        </span>
        <span v-else-if="!a.active_runs.length" class="md-body-medium text-medium-emphasis">
          Свободен
        </span>

        <div class="d-flex flex-wrap align-center gap-2">
          <v-chip
            v-for="p in a.projects"
            :key="p.id"
            size="small"
            closable
            @click:close="agents.unassignProject(a.id, p.id)"
          >
            {{ p.name }}
          </v-chip>
          <v-menu v-if="availableProjects(a).length">
            <template #activator="{ props }">
              <v-chip v-bind="props" size="small" variant="outlined">
                <ph-folder-plus :size="14" weight="bold" class="mr-1" />
                проект
              </v-chip>
            </template>
            <v-list density="compact" rounded="lg">
              <v-list-item
                v-for="p in availableProjects(a)"
                :key="p.id"
                :title="p.name"
                @click="agents.assignProject(a.id, p.id)"
              />
            </v-list>
          </v-menu>
        </div>
      </v-card>
    </div>

    <input ref="fileInput" type="file" accept="image/*" hidden @change="onAvatarPicked" />

    <v-dialog v-model="dialog" max-width="560" scrollable>
      <v-card rounded="xl" color="surface-container-high">
        <v-card-title class="d-flex align-center gap-4 px-6 pt-6">
          <v-avatar size="48" color="secondary">
            <img v-if="editing?.avatar_url" :src="editing.avatar_url" width="48" height="48" alt="" />
            <span v-else class="text-on-secondary md-title-medium">
              {{ (form.display_name || 'A').slice(0, 1).toUpperCase() }}
            </span>
          </v-avatar>
          <span class="md-headline-small text-truncate">
            {{ editing ? editing.display_name : 'Новый агент' }}
          </span>
        </v-card-title>

        <v-tabs v-if="editing" v-model="tab" grow color="primary" class="mt-2">
          <v-tab value="settings">Настройки</v-tab>
          <v-tab value="runs">Прогоны</v-tab>
        </v-tabs>
        <v-divider />

        <v-card-text class="px-6 pt-5">
          <v-window v-model="tab">
            <v-window-item value="settings" class="flex flex-col gap-4">
              <v-text-field
                v-model="form.display_name"
                label="Имя"
                placeholder="например, Кодер"
                variant="filled"
                density="comfortable"
                hide-details
                autofocus
              />

              <div class="md-title-small mt-2">Модель</div>

              <v-select
                :model-value="form.provider_preset"
                :items="presetItems"
                label="Провайдер"
                variant="filled"
                density="comfortable"
                hide-details
                @update:model-value="onPresetChange"
              >
                <template #item="{ props: itemProps, item }">
                  <v-list-item v-bind="itemProps">
                    <template v-if="item.meta.experimental" #append>
                      <span class="md-label-small text-medium-emphasis">экспериментально</span>
                    </template>
                  </v-list-item>
                </template>
              </v-select>

              <v-text-field
                v-model="form.model"
                label="Модель"
                :placeholder="presetMeta?.modelPlaceholder"
                variant="filled"
                density="comfortable"
                hide-details
              />

              <template v-if="presetMeta?.needsKey !== false">
                <v-btn-toggle
                  v-if="subscriptionAvailable"
                  v-model="form.auth_method"
                  mandatory
                  divided
                  rounded="pill"
                  color="secondary-container"
                  density="comfortable"
                  variant="outlined"
                  class="self-start"
                >
                  <v-btn value="api_key">API-ключ</v-btn>
                  <v-btn value="subscription">Подписка Claude</v-btn>
                </v-btn-toggle>
                <v-text-field
                  v-if="keyFieldVisible"
                  v-model="form.api_key"
                  :label="credentialLabel"
                  type="password"
                  autocomplete="off"
                  variant="filled"
                  density="comfortable"
                  :hint="credentialHint"
                  persistent-hint
                >
                  <template #prepend-inner><ph-key :size="20" /></template>
                </v-text-field>
                <v-text-field
                  v-else
                  :model-value="`Сохранён${editing?.config.api_key_hint ? ` · …${editing.config.api_key_hint}` : ''}`"
                  :label="credentialLabel"
                  readonly
                  variant="filled"
                  density="comfortable"
                  hint="Хранится зашифрованным, в интерфейсе больше не показывается"
                  persistent-hint
                >
                  <template #prepend-inner><ph-key :size="20" /></template>
                  <template #append-inner>
                    <v-btn variant="text" size="small" @click="replacingKey = true">Заменить</v-btn>
                  </template>
                </v-text-field>
              </template>

              <v-text-field
                v-if="showBaseUrl"
                v-model="form.base_url"
                label="Base URL"
                placeholder="https://…/v1"
                variant="filled"
                density="comfortable"
                hide-details
              />
              <v-btn
                v-else-if="presetBaseUrl"
                variant="text"
                class="self-start"
                size="small"
                @click="showBaseUrl = true"
              >
                Base URL: {{ form.base_url || presetBaseUrl }}
              </v-btn>

              <v-textarea
                v-model="form.system_prompt"
                label="Инструкции агенту"
                placeholder="Роль, стиль работы, что проверять перед завершением"
                variant="filled"
                density="comfortable"
                rows="3"
                auto-grow
                hide-details
              />

              <v-switch
                disabled
                color="primary"
                density="comfortable"
                label="Запускать автоматически"
                hint="При назначении и переносе в работу · скоро"
                persistent-hint
              />

              <v-alert v-if="formError" type="error" variant="tonal">{{ formError }}</v-alert>
            </v-window-item>

            <v-window-item value="runs">
              <div v-if="runsLoading" class="d-flex justify-center py-8">
                <v-progress-circular indeterminate color="primary" />
              </div>
              <div
                v-else-if="!agentRuns.length"
                class="md-body-medium text-medium-emphasis text-center py-8"
              >
                Прогонов пока не было.
              </div>
              <v-list v-else bg-color="transparent" lines="two">
                <v-list-item
                  v-for="run in agentRuns"
                  :key="run.id"
                  :to="
                    run.task_id && run.project_slug
                      ? { name: 'task', params: { slug: run.project_slug, taskId: run.task_id } }
                      : undefined
                  "
                >
                  <template #prepend>
                    <v-avatar :color="RUN_STATUS[run.status].color" size="40">
                      <v-icon size="20">{{ RUN_STATUS[run.status].icon }}</v-icon>
                    </v-avatar>
                  </template>
                  <v-list-item-title>{{ run.task_title ?? 'Задача удалена' }}</v-list-item-title>
                  <v-list-item-subtitle>
                    {{ RUN_STATUS[run.status].label
                    }}{{ runDuration(run) ? ` · ${runDuration(run)}` : '' }}{{
                      run.project_name ? ` · ${run.project_name}` : ''
                    }}
                  </v-list-item-subtitle>
                  <template #append>
                    <span class="md-label-small text-medium-emphasis">{{ runWhen(run.inserted_at) }}</span>
                  </template>
                </v-list-item>
              </v-list>
            </v-window-item>
          </v-window>
        </v-card-text>

        <v-card-actions class="px-6 pb-6">
          <v-btn v-if="editing" variant="text" color="error" @click="removeAgent">Удалить</v-btn>
          <v-spacer />
          <v-btn variant="text" @click="dialog = false">Закрыть</v-btn>
          <v-btn
            v-if="tab === 'settings'"
            color="primary"
            variant="flat"
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
  background: rgba(var(--v-theme-scrim), 0.45);
}
.ks-card-title {
  border: none;
  background: none;
  padding: 0;
  text-align: start;
  color: inherit;
  cursor: pointer;
}
.ks-run-link {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  color: rgb(var(--v-theme-primary));
  text-decoration: none;
}
.ks-run-link:hover {
  text-decoration: underline;
}
.ks-dot {
  width: 8px;
  height: 8px;
  flex-shrink: 0;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-outline));
}
.ks-dot--active {
  background: rgb(var(--v-theme-primary));
  box-shadow: 0 0 0 4px rgba(var(--v-theme-primary), 0.18);
}
</style>
