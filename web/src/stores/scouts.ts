import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Channel } from 'phoenix'
import { pushAsync, useSocketStore } from '@/stores/socket'
import { useAuthStore } from '@/stores/auth'
import { uploadToPresignedUrl } from '@/utils/upload'

export interface ScoutProject {
  id: string
  slug: string
  name: string
}

export interface Scout {
  id: string
  display_name: string | null
  email: string | null
  avatar_url: string | null
  agent_role: string | null
  agent_description: string | null
  projects: ScoutProject[]
  inserted_at?: string
}

interface JoinReply {
  scouts: Scout[]
}

export const useScoutsStore = defineStore('scouts', () => {
  const list = ref<Scout[]>([])
  const channel = ref<Channel | null>(null)

  function upsert(s: Scout) {
    const idx = list.value.findIndex((x) => x.id === s.id)
    if (idx === -1) list.value.push(s)
    else list.value[idx] = s
  }

  function remove(id: string) {
    list.value = list.value.filter((s) => s.id !== id)
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
    const { channel: ch, reply } = await sock.joinChannel<JoinReply>(`scouts:user:${userId}`)
    list.value = (reply?.scouts ?? []).slice()
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
    const reply = await pushAsync<{ projects: ScoutProject[] }>(ch, 'list_projects', {})
    return reply.projects
  }

  async function createScout(input: {
    display_name: string
    agent_role?: string | null
    agent_description?: string | null
  }) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ scout: Scout; token: string }>(ch, 'create_scout', input)
    upsert(reply.scout)
    return reply
  }

  async function updateScout(
    id: string,
    input: {
      display_name?: string
      agent_role?: string | null
      agent_description?: string | null
    },
  ) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ scout: Scout }>(ch, 'update_scout', {
      id,
      ...input,
    })
    upsert(reply.scout)
    return reply.scout
  }

  async function deleteScout(id: string) {
    const ch = await requireChannel()
    await pushAsync<{ id: string }>(ch, 'delete_scout', { id })
    remove(id)
  }

  async function regenerateToken(id: string) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ id: string; token: string }>(ch, 'regenerate_token', { id })
    return reply.token
  }

  async function assignProject(id: string, projectId: string) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ scout: Scout }>(ch, 'assign_project', {
      id,
      project_id: projectId,
    })
    upsert(reply.scout)
    return reply.scout
  }

  async function unassignProject(id: string, projectId: string) {
    const ch = await requireChannel()
    const reply = await pushAsync<{ scout: Scout }>(ch, 'unassign_project', {
      id,
      project_id: projectId,
    })
    upsert(reply.scout)
    return reply.scout
  }

  async function uploadAvatar(id: string, file: File, onProgress?: (f: number) => void) {
    const ch = await requireChannel()
    const meta = await pushAsync<{ attachment_id: string; put_url: string }>(
      ch,
      'request_scout_avatar_upload',
      {
        id,
        filename: file.name,
        mime: file.type || 'application/octet-stream',
        size: file.size,
      },
    )
    await uploadToPresignedUrl(meta.put_url, file, onProgress)
    const reply = await pushAsync<{ scout: Scout }>(ch, 'confirm_scout_avatar_upload', {
      id,
      attachment_id: meta.attachment_id,
    })
    upsert(reply.scout)
    return reply.scout
  }

  return {
    list,
    join,
    listProjects,
    createScout,
    updateScout,
    deleteScout,
    regenerateToken,
    assignProject,
    unassignProject,
    uploadAvatar,
  }
})
