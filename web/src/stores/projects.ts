import { defineStore } from 'pinia'
import { ref } from 'vue'
import type { Channel } from 'phoenix'
import { pushAsync, useSocketStore } from './socket'

export interface Project {
  id: string
  slug: string
  name: string
  description: string | null
  owner_id: string
  inserted_at?: string
}

interface JoinReply {
  projects: Project[]
}

export const useProjectsStore = defineStore('projects', () => {
  const list = ref<Project[]>([])
  const channel = ref<Channel | null>(null)

  async function joinLobby() {
    if (channel.value && channel.value.state === 'joined') return channel.value

    const sock = useSocketStore()
    const { channel: ch, reply } = await sock.joinChannel<JoinReply>('projects:lobby')

    list.value = (reply?.projects ?? []).slice()

    ch.on('project_created', (p: Project) => {
      const idx = list.value.findIndex((x) => x.id === p.id)
      if (idx === -1) list.value.push(p)
      else list.value[idx] = p
    })

    channel.value = ch
    return ch
  }

  async function createProject(input: { slug: string; name: string; description?: string }) {
    const ch = await joinLobby()
    return pushAsync<Project>(ch, 'create_project', input)
  }

  async function refresh() {
    const ch = await joinLobby()
    const reply = await pushAsync<JoinReply>(ch, 'list_projects', {})
    list.value = reply.projects.slice()
  }

  function findBySlug(slug: string) {
    return list.value.find((p) => p.slug === slug) ?? null
  }

  return { list, joinLobby, createProject, refresh, findBySlug }
})
