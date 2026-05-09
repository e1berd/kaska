<script setup lang="ts">
import { computed, onMounted, ref, watch, watchEffect } from 'vue'
import { useRoute, type RouteLocationRaw } from 'vue-router'
import { useDisplay, useTheme } from 'vuetify'
import { useAuthStore } from './stores/auth'
import { useSocketStore } from './stores/socket'
import { useSysStore } from './stores/sys'
import { useBoardStore } from './stores/board'
import { useThemeStore } from './stores/theme'
import { PhUser, PhSignOut } from '@phosphor-icons/vue'
import PresenceGroup from './components/PresenceGroup.vue'
import { cssColorOr } from './utils/css'

const auth = useAuthStore()
const socket = useSocketStore()
const sys = useSysStore()
const board = useBoardStore()
const theme = useThemeStore()
const route = useRoute()
const { mobile } = useDisplay()
const vuetifyTheme = useTheme()

function hexToRgbTriplet(color: string): string | null {
  const safeColor = cssColorOr(color, '')
  if (!/^#?(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(safeColor)) return null
  const hex = safeColor.replace('#', '')
  if (!hex) return null
  const h = hex
  if (h.length === 3) {
    const r = parseInt(h[0] + h[0], 16)
    const g = parseInt(h[1] + h[1], 16)
    const b = parseInt(h[2] + h[2], 16)
    return `${r},${g},${b}`
  }
  if (h.length === 6) {
    return `${parseInt(h.slice(0, 2), 16)},${parseInt(h.slice(2, 4), 16)},${parseInt(h.slice(4, 6), 16)}`
  }
  return null
}

function paletteToCssBlock(selector: string, palette: Record<string, string>): string {
  const lines: string[] = [`${selector} {`]
  for (const [k, v] of Object.entries(palette)) {
    const rgb = hexToRgbTriplet(v)
    if (rgb) lines.push(`  --v-theme-${k}: ${rgb} !important;`)
  }
  lines.push('}')
  return lines.join('\n')
}

function ensureThemeStyleEl(): HTMLStyleElement {
  let el = document.getElementById('hh-theme-vars') as HTMLStyleElement | null
  if (!el) {
    el = document.createElement('style')
    el.id = 'hh-theme-vars'
  }
  document.head.appendChild(el)
  return el
}

watchEffect(() => {
  const palette = theme.effectivePalette
  const dark = theme.effectiveDark
  vuetifyTheme.global.name.value = dark ? 'hardhatDark' : 'hardhatLight'
  if (!palette) return
  const css = [
    paletteToCssBlock(
      '.v-theme--hardhatLight, .v-theme-provider--hardhatLight',
      palette.palette_light,
    ),
    paletteToCssBlock(
      '.v-theme--hardhatDark, .v-theme-provider--hardhatDark',
      palette.palette_dark,
    ),
  ].join('\n')
  const el = ensureThemeStyleEl()
  el.textContent = css
})

const showSidebar = ref(route.name !== 'home')
watch(() => route.name, (name) => { showSidebar.value = name !== 'home' })

const drawer = ref(!mobile.value)
watch(mobile, (m) => {
  drawer.value = !m
})

onMounted(() => {
  if (auth.isAuthed) {
    void sys.initPresence()
  }
  void theme.bootstrap()
})

watch(
  () => [auth.isAuthed, socket.connected] as const,
  ([isAuthed, connected]) => {
    if (isAuthed && connected) {
      void sys.initPresence()
    }
  },
  { immediate: true },
)

watch(
  () => route.name,
  (name) => {
    const inProjectScope = name === 'board' || name === 'task' || name === 'board_types'
    if (!inProjectScope && board.project) {
      board.leave()
    }
  },
)

const currentSlug = computed(() => (route.params.slug as string | undefined) ?? null)
const currentTaskId = computed(() => (route.params.taskId as string | undefined) ?? null)

const activeProjectUsers = computed(() => {
  if (!currentSlug.value || !board.project) return []
  return board.activeViewerIds
    .filter((id) => id !== auth.user?.id)
    .map((id) => board.users.find((u) => u.id === id))
    .filter((u): u is NonNullable<typeof u> => !!u)
})

const activeTaskUsers = computed(() => {
  if (!currentTaskId.value) return []
  return board
    .viewersForTask(currentTaskId.value)
    .filter((user) => user.id !== auth.user?.id)
})

const headerPresenceUsers = computed(() => {
  if (currentTaskId.value) return activeTaskUsers.value
  return activeProjectUsers.value
})

const headerPresenceLabel = computed(() =>
  currentTaskId.value ? 'Сейчас в задаче' : 'Сейчас в проекте',
)

interface NavItem {
  key: string
  label: string
  icon: string
  to: RouteLocationRaw
}

const navItems = computed<NavItem[]>(() => {
  const items: NavItem[] = [
    {
      key: 'projects',
      label: 'Проекты',
      icon: 'mdi-view-grid-outline',
      to: { name: 'projects' },
    },
  ]
  if (currentSlug.value) {
    items.push({
      key: 'types',
      label: 'Типы задач',
      icon: 'mdi-tag-multiple-outline',
      to: { name: 'board_types', params: { slug: currentSlug.value } },
    })
  }

  items.push({
    key: 'members',
    label: 'Участники',
    icon: 'mdi-account-multiple-outline',
    to: { name: 'members' }
  });

  if (auth.isAuthed) {
    items.push({
      key: 'settings',
      label: 'Настройки',
      icon: 'mdi-cog-outline',
      to: { name: 'settings' }
    });
  }

  return items
})

function logout() {
  auth.logout()
}
</script>

<template>
  <v-app>
    <template v-if="true">
      <v-app-bar flat color="surface" class="hh-bar" height="64">
        <template #prepend>
          <v-app-bar-nav-icon
            v-if="showSidebar && mobile"
            aria-label="Открыть меню"
            @click="drawer = !drawer"
          />
          <router-link
            :to="{ name: 'home' }"
            class="hh-brand md-state-layer"
            aria-label="HardHat"
          >
            <span class="hh-brand__logo">
              <v-icon size="22">mdi-hard-hat</v-icon>
            </span>
            <span class="hh-brand__name md-title-large">HardHat</span>
          </router-link>
        </template>

        <template #append>
          <template v-if="auth.isAuthed">
            <PresenceGroup
              v-if="headerPresenceUsers.length"
              class="mr-2"
              :users="headerPresenceUsers"
              :label="headerPresenceLabel"
              size="sm"
            />
            <v-menu v-if="auth.isAuthed">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  variant="text"
                  rounded="pill"
                  size="default"
                  density="comfortable"
                  class="hh-bar__profile"
                  :title="auth.user?.email"
                >
                  <template #prepend>
                    <v-avatar
                      size="32"
                      class="bg-primary-container text-on-primary-container"
                    >
                      <v-img
                        v-if="auth.user?.avatar_url"
                        :src="auth.user.avatar_url"
                        cover
                        alt=""
                      />
                      <span v-else class="md-label-large">{{
                        (auth.user?.display_name || auth.user?.email || '?')
                          .slice(0, 1)
                          .toUpperCase()
                      }}</span>
                    </v-avatar>
                  </template>
                  <span v-if="!mobile" class="hh-bar__profile-name md-label-large">
                    {{ auth.user?.display_name || auth.user?.email?.split('@')[0] }}
                  </span>
                </v-btn>
              </template>
              <v-list class="bg-surface elevation-3" :elevation="0" rounded="lg" density="compact">
                <v-list-item
                  :to="{ name: 'me' }"
                  class="md-state-layer"
                  base-color="on-surface"
                >
                  <template #prepend>
                    <ph-user :size="20" class="mr-3" weight="regular" />
                  </template>
                  <v-list-item-title>Мой профиль</v-list-item-title>
                </v-list-item>
                <v-divider class="my-1"></v-divider>
                <v-list-item
                  @click="logout"
                  class="md-state-layer text-error"
                  base-color="error"
                >
                  <template #prepend>
                    <ph-sign-out :size="20" class="mr-3" weight="regular" />
                  </template>
                  <v-list-item-title>Выйти</v-list-item-title>
                </v-list-item>
              </v-list>
            </v-menu>
          </template>
          <template v-else>
            <v-btn variant="text" :to="{ name: 'login' }" rounded="pill">Войти</v-btn>
            <v-btn
              v-if="!mobile"
              color="primary"
              variant="flat"
              :to="{ name: 'register' }"
              class="ml-2"
              rounded="pill"
            >
              Регистрация
            </v-btn>
          </template>
        </template>
      </v-app-bar>

      <v-navigation-drawer
        v-if="showSidebar"
        v-model="drawer"
        :permanent="!mobile"
        :temporary="mobile"
        rail
        :rail-width="96"
        color="surface"
        class="hh-nav"
        :border="0"
      >
        <nav class="hh-nav__list" v-auto-animate>
          <router-link
            v-for="item in navItems"
            :key="item.key"
            :to="item.to"
            class="hh-nav__item md-state-layer"
          >
            <span class="hh-nav__pill">
              <v-icon size="24">{{ item.icon }}</v-icon>
            </span>
            <span class="hh-nav__label md-label-medium">{{ item.label }}</span>
          </router-link>
        </nav>
      </v-navigation-drawer>

      <v-main>
        <router-view />
      </v-main>
    </template>
  </v-app>
</template>

<style scoped>
.hh-bar {
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.06);
  backdrop-filter: saturate(180%) blur(8px);
  background: rgba(var(--v-theme-surface), 0.85) !important;
  z-index: 1006;
}

.hh-brand {
  display: inline-flex;
  align-items: center;
  gap: 12px;
  text-decoration: none;
  color: inherit;
  padding: 6px 12px 6px 6px;
  margin-left: 8px;
  border-radius: var(--md-shape-full);
  --md-state-color: rgb(var(--v-theme-on-surface));
}
.hh-brand__logo {
  width: 36px;
  height: 36px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.hh-brand__name {
  font-family: 'Roboto Flex', 'Roboto', sans-serif;
  font-variation-settings: 'wght' 600;
  letter-spacing: -0.01em;
}

.hh-bar__link {
  font-weight: 500;
}

.hh-bar__profile {
  padding-inline-start: 4px !important;
  padding-inline-end: 16px !important;
}
.hh-bar__profile-name {
  max-width: 160px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

@media (max-width: 600px) {
  .hh-brand__name {
    display: none;
  }
}

.hh-nav {
  background: rgb(var(--v-theme-surface)) !important;
  border-right: 1px solid rgba(var(--v-theme-on-surface), 0.06);
}
.hh-nav__list {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 12px 4px;
}
.hh-nav__item {
  --md-state-color: rgb(var(--v-theme-on-surface));
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  width: 72px;
  height: 64px;
  padding: 4px 0 6px;
  border-radius: var(--md-shape-l);
  text-decoration: none;
  color: rgb(var(--v-theme-on-surface));
}
.hh-nav__pill {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 56px;
  height: 32px;
  border-radius: var(--md-shape-full);
  transition: background-color var(--md-duration-short4) var(--md-easing-emphasized);
}
.hh-nav__item.router-link-active .hh-nav__pill {
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
}
.hh-nav__item.router-link-active :deep(.v-icon) {
  color: rgb(var(--v-theme-on-secondary-container));
}
.hh-nav__label {
  text-align: center;
  font-size: 11px;
  line-height: 1.1;
  letter-spacing: 0.5px;
  white-space: nowrap;
  color: inherit;
}
</style>
