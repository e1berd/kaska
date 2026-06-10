import { defineStore } from 'pinia'
import { computed, ref, watch } from 'vue'
import { pushAsync, useSocketStore } from '@/stores/socket'
import { useAuthStore } from '@/stores/auth'
import { useBoardStore } from '@/stores/board'
import type { ThemeMode } from '@/stores/auth'

export type PaletteColors = Record<string, string>

export interface ThemeIndexEntry {
  slug: string
  name: string
}

export interface ThemePalettes {
  slug: string
  name: string
  palette_light: PaletteColors
  palette_dark: PaletteColors
  updated_at: string
}

const PALETTE_CACHE_PREFIX = 'kaska.theme.palette.'
const DEFAULT_SLUG = 'kaska'

function readCachedPalette(slug: string): ThemePalettes | null {
  try {
    const raw = localStorage.getItem(PALETTE_CACHE_PREFIX + slug)
    if (!raw) return null
    return JSON.parse(raw) as ThemePalettes
  } catch {
    return null
  }
}

function writeCachedPalette(palette: ThemePalettes) {
  try {
    localStorage.setItem(PALETTE_CACHE_PREFIX + palette.slug, JSON.stringify(palette))
  } catch {}
}

export const useThemeStore = defineStore('theme', () => {
  const auth = useAuthStore()
  const board = useBoardStore()

  const themesIndex = ref<ThemeIndexEntry[]>([])
  const palettes = ref<Record<string, ThemePalettes>>({})

  const systemPrefersDark = ref<boolean>(
    typeof window !== 'undefined'
      ? window.matchMedia('(prefers-color-scheme: dark)').matches
      : false,
  )

  if (typeof window !== 'undefined') {
    const mq = window.matchMedia('(prefers-color-scheme: dark)')
    const onChange = (e: MediaQueryListEvent) => {
      systemPrefersDark.value = e.matches
    }
    if (mq.addEventListener) mq.addEventListener('change', onChange)
    else mq.addListener(onChange)
  }

  const effectiveSlug = computed<string>(
    () =>
      board.myProjectThemeSlug ||
      auth.user?.theme_slug ||
      board.project?.theme_slug ||
      DEFAULT_SLUG,
  )

  const effectiveMode = computed<ThemeMode>(() => auth.user?.theme_mode || 'system')

  const effectiveDark = computed<boolean>(() => {
    const m = effectiveMode.value
    if (m === 'dark') return true
    if (m === 'light') return false
    return systemPrefersDark.value
  })

  const effectivePalette = computed<ThemePalettes | null>(
    () => palettes.value[effectiveSlug.value] || null,
  )

  function rememberPalette(palette: ThemePalettes) {
    palettes.value = { ...palettes.value, [palette.slug]: palette }
    writeCachedPalette(palette)
  }

  function hydrateFromCache(slug: string) {
    const cached = readCachedPalette(slug)
    if (cached && !palettes.value[slug]) {
      palettes.value = { ...palettes.value, [slug]: cached }
    }
  }

  async function sysChannel() {
    const sock = useSocketStore()
    const { channel } = await sock.joinChannel('sys:lobby')
    return channel
  }

  async function loadIndex() {
    const ch = await sysChannel()
    const reply = await pushAsync<{ themes: ThemeIndexEntry[] }>(ch, 'list_themes', {})
    themesIndex.value = reply.themes
    return reply.themes
  }

  async function fetchPalette(slug: string): Promise<ThemePalettes> {
    const ch = await sysChannel()
    const reply = await pushAsync<ThemePalettes>(ch, 'get_theme', { slug })
    rememberPalette(reply)
    return reply
  }

  async function ensurePalette(slug: string): Promise<ThemePalettes> {
    if (palettes.value[slug]) return palettes.value[slug]
    hydrateFromCache(slug)
    const cached = palettes.value[slug]
    if (cached) {
      void fetchPalette(slug).catch(() => {})
      return cached
    }
    return await fetchPalette(slug)
  }

  let bootstrapped = false

  async function bootstrap() {
    if (bootstrapped) return
    bootstrapped = true

    hydrateFromCache(DEFAULT_SLUG)
    if (auth.user?.theme_slug) hydrateFromCache(auth.user.theme_slug)

    void ensurePalette(effectiveSlug.value).catch(() => {})
    void loadIndex().catch(() => {})

    watch(effectiveSlug, (slug) => {
      void ensurePalette(slug).catch(() => {})
    })
  }

  async function setUserTheme(slug: string | null) {
    await auth.setUserTheme({ theme_slug: slug, theme_mode: auth.user?.theme_mode ?? null })
    if (slug) await ensurePalette(slug)
  }

  async function setUserMode(mode: ThemeMode | null) {
    await auth.setUserTheme({ theme_slug: auth.user?.theme_slug ?? null, theme_mode: mode })
  }

  return {
    themesIndex,
    palettes,
    effectiveSlug,
    effectiveMode,
    effectiveDark,
    effectivePalette,
    bootstrap,
    loadIndex,
    ensurePalette,
    setUserTheme,
    setUserMode,
  }
})
