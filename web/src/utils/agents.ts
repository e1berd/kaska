import type { AgentRunStatus } from '@/stores/board'
import type { AuthMethod, ConfigField } from '@/stores/agents'

export interface PresetMeta {
  label: string
  modelPlaceholder: string
  experimental?: boolean
  needsKey: boolean
  supportsSubscription?: boolean
  editableBaseUrl: boolean
}

export const PRESET_ORDER = [
  'anthropic',
  'openai',
  'deepseek',
  'qwen_dashscope',
  'glm_zhipu',
  'xai_grok',
  'ollama',
  'lm_studio',
  'custom',
] as const

export const PRESETS: Record<string, PresetMeta> = {
  anthropic: {
    label: 'Claude',
    modelPlaceholder: 'claude-opus-5',
    needsKey: true,
    supportsSubscription: true,
    editableBaseUrl: false,
  },
  openai: { label: 'OpenAI', modelPlaceholder: 'идентификатор модели', needsKey: true, editableBaseUrl: false },
  deepseek: { label: 'DeepSeek', modelPlaceholder: 'deepseek-chat', needsKey: true, editableBaseUrl: false },
  qwen_dashscope: {
    label: 'Qwen · DashScope',
    modelPlaceholder: 'идентификатор модели',
    needsKey: true,
    editableBaseUrl: false,
  },
  glm_zhipu: {
    label: 'GLM · Zhipu',
    modelPlaceholder: 'идентификатор модели',
    needsKey: true,
    editableBaseUrl: false,
  },
  xai_grok: { label: 'Grok', modelPlaceholder: 'идентификатор модели', needsKey: true, editableBaseUrl: false },
  ollama: {
    label: 'Ollama на сервере',
    modelPlaceholder: 'qwen2.5-coder',
    experimental: true,
    needsKey: false,
    editableBaseUrl: false,
  },
  lm_studio: {
    label: 'LM Studio',
    modelPlaceholder: 'идентификатор модели',
    needsKey: false,
    editableBaseUrl: true,
  },
  custom: {
    label: 'Свой OpenAI-совместимый',
    modelPlaceholder: 'идентификатор модели',
    needsKey: true,
    editableBaseUrl: true,
  },
}

export function presetLabel(slug: string | null | undefined): string {
  return (slug && PRESETS[slug]?.label) || 'Провайдер не выбран'
}

export function modelLine(preset: string | null | undefined, model: string | null | undefined) {
  if (!preset && !model) return 'Модель не настроена'
  return [presetLabel(preset), model].filter(Boolean).join(' · ')
}

const MISSING_LABELS: Record<ConfigField, string> = {
  provider: 'провайдер',
  model: 'модель',
  base_url: 'адрес API',
  api_key: 'API-ключ',
}

export const CREDENTIAL_LABELS: Record<AuthMethod, string> = {
  api_key: 'API-ключ',
  subscription: 'токен подписки',
}

export function missingText(missing: ConfigField[], authMethod: AuthMethod = 'api_key'): string {
  const labels = { ...MISSING_LABELS, api_key: CREDENTIAL_LABELS[authMethod] }
  return `Не настроен: нет ${missing.map((m) => labels[m]).join(', ')}`
}

export interface RunStatusMeta {
  label: string
  color: string
  icon: string
}

export const RUN_STATUS: Record<AgentRunStatus, RunStatusMeta> = {
  pending: { label: 'Запускается', color: 'surface-container-highest', icon: 'mdi-progress-clock' },
  running: { label: 'Работает', color: 'primary-container', icon: 'mdi-circle-medium' },
  succeeded: { label: 'Успешно', color: 'secondary-container', icon: 'mdi-check' },
  failed: { label: 'Ошибка', color: 'error-container', icon: 'mdi-close' },
  timed_out: { label: 'Время вышло', color: 'error-container', icon: 'mdi-clock-alert-outline' },
  stopped: { label: 'Остановлен', color: 'surface-container-highest', icon: 'mdi-stop' },
}

export function formatDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds))
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  const rest = seconds % 60
  const mm = String(minutes).padStart(2, '0')
  const ss = String(rest).padStart(2, '0')
  return hours > 0 ? `${hours}:${mm}:${ss}` : `${mm}:${ss}`
}

export function runSeconds(
  run: { started_at: string | null; finished_at: string | null },
  now: number,
): number | null {
  if (!run.started_at) return null
  const end = run.finished_at ? Date.parse(run.finished_at) : now
  return (end - Date.parse(run.started_at)) / 1000
}

const START_ERRORS: Record<string, string> = {
  not_configured: 'Агент не настроен — проверьте провайдера, модель и ключ или токен подписки.',
  not_assigned: 'Назначьте агента исполнителем задачи.',
  not_assigned_to_agent: 'Исполнитель задачи — не агент.',
  not_member: 'Агент не состоит в проекте.',
  quota_exceeded: 'Достигнут лимит одновременных прогонов ваших агентов.',
  already_running: 'По задаче уже идёт прогон.',
  forbidden: 'Недостаточно прав.',
}

export function startErrorText(error: unknown): string {
  const message = (error as { message?: string })?.message
  return (message && START_ERRORS[message]) || 'Не удалось запустить агента.'
}
