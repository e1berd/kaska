import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Channel } from 'phoenix'
import { pushAsync, useSocketStore } from '@/stores/socket'
import { useAuthStore } from '@/stores/auth'
import { uploadToPresignedUrl } from '@/utils/upload'

export interface Project {
  id: string
  slug: string
  name: string
  description: string | null
  owner_id: string
  public_link: boolean
  avatar_url: string | null
  background_url: string | null
  inserted_at?: string
  updated_at?: string
}

interface JoinReply {
  projects: Project[]
}

export const useProjectsStore = defineStore('projects', () => {
  const list = ref<Project[]>([])
  const channel = ref<Channel | null>(null)

  function upsert(p: Project) {
    const idx = list.value.findIndex((x) => x.id === p.id)
    if (idx === -1) list.value.push(p)
    else list.value[idx] = p
  }

  function remove(id: string) {
    list.value = list.value.filter((p) => p.id !== id)
  }

  async function joinLobby() {
    const auth = useAuthStore()
    const userId = auth.user?.id
    if (!userId) {
      list.value = []
      return null
    }

    if (channel.value && channel.value.state === 'joined') return channel.value

    const sock = useSocketStore()
    const { channel: ch, reply } = await sock.joinChannel<JoinReply>(`projects:user:${userId}`)

    list.value = (reply?.projects ?? []).slice()

    ch.on('project_created', (p: Project) => upsert(p))
    ch.on('project_updated', (p: Project) => upsert(p))
    ch.on('project_deleted', ({ id }: { id: string }) => remove(id))

    channel.value = ch
    return ch
  }

  async function requireChannel() {
    const ch = await joinLobby()
    if (!ch) throw new Error('not authenticated')
    return ch
  }

  async function acceptInvite(token: string) {
    const ch = await requireChannel()
    return pushAsync<{ slug: string }>(ch, 'accept_invite', { token })
  }

  async function createProject(input: { slug: string; name: string; description?: string }) {
    const ch = await requireChannel()
    return pushAsync<Project>(ch, 'create_project', input)
  }

  async function updateProject(input: { id: string; name?: string; description?: string | null }) {
    const ch = await requireChannel()
    const payload: Record<string, unknown> = { id: input.id }
    if (input.name !== undefined) payload.name = input.name
    if (input.description !== undefined) payload.description = input.description ?? ''
    return pushAsync<Project>(ch, 'update_project', payload)
  }

  async function deleteProject(id: string) {
    const ch = await requireChannel()
    return pushAsync<{ id: string }>(ch, 'delete_project', { id })
  }

  async function uploadProjectMedia(
    kind: 'avatar' | 'background',
    projectId: string,
    file: File,
    onProgress?: (f: number) => void,
  ) {
    const ch = await requireChannel()
    const requestEvent =
      kind === 'avatar' ? 'request_project_avatar_upload' : 'request_project_background_upload'
    const confirmEvent =
      kind === 'avatar' ? 'confirm_project_avatar_upload' : 'confirm_project_background_upload'

    const meta = await pushAsync<{ attachment_id: string; put_url: string }>(ch, requestEvent, {
      project_id: projectId,
      filename: file.name,
      mime: file.type || 'application/octet-stream',
      size: file.size,
    })
    await uploadToPresignedUrl(meta.put_url, file, onProgress)
    return pushAsync<Project>(ch, confirmEvent, {
      project_id: projectId,
      attachment_id: meta.attachment_id,
    })
  }

  async function clearProjectMedia(kind: 'avatar' | 'background', projectId: string) {
    const ch = await requireChannel()
    const event = kind === 'avatar' ? 'clear_project_avatar' : 'clear_project_background'
    return pushAsync<Project>(ch, event, { id: projectId })
  }

  async function refresh() {
    const ch = await joinLobby()
    if (!ch) return
    const reply = await pushAsync<JoinReply>(ch, 'list_projects', {})
    list.value = reply.projects.slice()
  }

  function findBySlug(slug: string) {
    return list.value.find((p) => p.slug === slug) ?? null
  }

  return {
    list,
    joinLobby,
    acceptInvite,
    createProject,
    updateProject,
    deleteProject,
    uploadProjectMedia,
    clearProjectMedia,
    refresh,
    findBySlug,
  }
})
