import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Channel } from 'phoenix'
import { pushAsync, useSocketStore } from '@/stores/socket'
import { useAuthStore } from '@/stores/auth'
import { isRunActive, type AgentRun } from '@/stores/board'
import { uploadToPresignedUrl } from '@/utils/upload'

export type ProviderKind = 'anthropic' | 'openai_compatible' | 'ollama_local'
export type AuthMethod = 'api_key' | 'subscription'
export type ConfigField = 'provider' | 'model' | 'base_url' | 'api_key'

export interface AgentConfig {
  provider_kind: ProviderKind | null
  provider_preset: string | null
  auth_method: AuthMethod
  base_url: string | null
  model: string | null
  api_key_set: boolean
  api_key_hint: string | null
  system_prompt: string | null
  ready: boolean
  missing: ConfigField[]
}

export interface AgentProject {
  id: string
  slug: string
  name: string
}

export interface AgentRunWithTask extends AgentRun {
  task_title: string | null
  project_slug: string | null
  project_name: string | null
}

export interface Agent {
  id: string
  display_name: string | null
  avatar_url: string | null
  config: AgentConfig
  projects: AgentProject[]
  active_runs: AgentRunWithTask[]
  inserted_at?: string
}

export interface ProviderPreset {
  slug: string
  provider_kind: ProviderKind
  base_url: string | null
}

export interface AgentLimits {
  max_active_runs_per_owner: number
  max_walltime_seconds: number
  max_turns: number
}

export interface AgentInput {
  display_name?: string
  provider_preset?: string | null
  auth_method?: AuthMethod
  base_url?: string | null
  model?: string | null
  api_key?: string
  system_prompt?: string | null
}

interface JoinReply {
  agents: Agent[]
  presets: ProviderPreset[]
  limits: AgentLimits
  active_runs: number
}

interface RunUpdate {
  run: AgentRunWithTask
  active_runs: number
}

export const useAgentsStore = defineStore('agents', () => {
  const list = ref<Agent[]>([])
  const presets = ref<ProviderPreset[]>([])
  const limits = ref<AgentLimits | null>(null)
  const activeRuns = ref(0)
  const runsByAgent = ref<Record<string, AgentRunWithTask[]>>({})
  const channel = ref<Channel | null>(null)

  function upsert(agent: Agent) {
    const idx = list.value.findIndex((a) => a.id === agent.id)
    if (idx === -1) list.value.push(agent)
    else list.value[idx] = agent
  }

  function remove(id: string) {
    list.value = list.value.filter((a) => a.id !== id)
  }

  function applyRunUpdate({ run, active_runs }: RunUpdate) {
    activeRuns.value = active_runs

    const agent = list.value.find((a) => a.id === run.agent_id)
    if (agent) {
      const others = agent.active_runs.filter((r) => r.id !== run.id)
      agent.active_runs = isRunActive(run) ? [run, ...others] : others
    }

    const cached = runsByAgent.value[run.agent_id]
    if (cached) {
      const rest = cached.filter((r) => r.id !== run.id)
      runsByAgent.value = { ...runsByAgent.value, [run.agent_id]: [run, ...rest] }
    }
  }

  async function join() {
    const auth = useAuthStore()
    const userId = auth.user?.id
    if (!userId) {
      list.value = []
      return null
    }

    if (channel.value && channel.value.state === 'joined') return channel.value

    const sock = useSocketStore()
    const { channel: ch, reply } = await sock.joinChannel<JoinReply>(`agents:user:${userId}`)
    if (reply.agents) {
      list.value = reply.agents.slice()
      presets.value = reply.presets
      limits.value = reply.limits
      activeRuns.value = reply.active_runs
    }
    ch.on('agent_run_updated', applyRunUpdate)
    channel.value = ch
    return ch
  }

  async function requireChannel() {
    const ch = await join()
    if (!ch) throw new Error('not authenticated')
    return ch
  }

  async function listProjects() {
    const ch = await requireChannel()
    const reply = await pushAsync<{ projects: AgentProject[] }>(ch, 'list_projects', {})
    return reply.projects
  }

  async function createAgent(input: AgentInput) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ agent: Agent }>(ch, 'create_agent', input)
    upsert(reply.agent)
    return reply.agent
  }

  async function updateAgent(id: string, input: AgentInput) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ agent: Agent }>(ch, 'update_agent', { id, ...input })
    upsert(reply.agent)
    return reply.agent
  }

  async function deleteAgent(id: string) {
    const ch = await requireChannel()
    await pushAsync<{ id: string }>(ch, 'delete_agent', { id })
    remove(id)
  }

  async function assignProject(id: string, projectId: string) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ agent: Agent }>(ch, 'assign_project', {
      id,
      project_id: projectId,
    })
    upsert(reply.agent)
  }

  async function unassignProject(id: string, projectId: string) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ agent: Agent }>(ch, 'unassign_project', {
      id,
      project_id: projectId,
    })
    upsert(reply.agent)
  }

  async function loadRuns(id: string) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ runs: AgentRunWithTask[] }>(ch, 'list_runs', { id })
    runsByAgent.value = { ...runsByAgent.value, [id]: reply.runs }
    return reply.runs
  }

  async function uploadAvatar(id: string, file: File) {
    const ch = await requireChannel()
    const meta = await pushAsync<{ attachment_id: string; put_url: string }>(
      ch,
      'request_avatar_upload',
      {
        id,
        filename: file.name,
        mime: file.type || 'application/octet-stream',
        size: file.size,
      },
    )
    await uploadToPresignedUrl(meta.put_url, file)
    const reply = await pushAsync<{ agent: Agent }>(ch, 'confirm_avatar_upload', {
      id,
      attachment_id: meta.attachment_id,
    })
    upsert(reply.agent)
  }

  return {
    list,
    presets,
    limits,
    activeRuns,
    runsByAgent,
    join,
    listProjects,
    createAgent,
    updateAgent,
    deleteAgent,
    assignProject,
    unassignProject,
    loadRuns,
    uploadAvatar,
  }
})
