import { defineStore } from 'pinia'
import { computed, ref, watch } from 'vue'
import { useAuthStore } from '@/stores/auth'

export type PinnedProject = {
  id: string
  slug: string
  name: string
  avatar_url: string | null
}

const KEY_PREFIX = 'kaska.sidebar.pinned_projects'

function storageKey(userId: string | null | undefined): string {
  return `${KEY_PREFIX}:${userId ?? 'guest'}`
}

function loadFor(userId: string | null | undefined): PinnedProject[] {
  try {
    const raw = localStorage.getItem(storageKey(userId))
    if (!raw) return []
    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    return parsed.filter(
      (p): p is PinnedProject =>
        !!p && typeof p.id === 'string' && typeof p.slug === 'string' && typeof p.name === 'string',
    )
  } catch {
    return []
  }
}

function saveFor(userId: string | null | undefined, items: PinnedProject[]) {
  try {
    localStorage.setItem(storageKey(userId), JSON.stringify(items))
  } catch {
    void 0
  }
}

export const usePinnedProjectsStore = defineStore('pinnedProjects', () => {
  const auth = useAuthStore()
  const items = ref<PinnedProject[]>(loadFor(auth.user?.id))

  watch(
    () => auth.user?.id ?? null,
    (id) => {
      items.value = loadFor(id)
    },
  )

  function persist() {
    saveFor(auth.user?.id, items.value)
  }

  function add(project: PinnedProject) {
    const existing = items.value.findIndex((p) => p.id === project.id)
    if (existing >= 0) {
      items.value[existing] = { ...items.value[existing], ...project }
    } else {
      items.value = [...items.value, project]
    }
    persist()
  }

  function remove(id: string) {
    items.value = items.value.filter((p) => p.id !== id)
    persist()
  }

  const list = computed(() => items.value)

  return { list, add, remove }
})
