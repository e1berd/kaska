<script setup lang="ts">
import { computed, onMounted, ref, watch, watchEffect } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useDisplay, useTheme } from 'vuetify'
import { useAuthStore } from '@/stores/auth'
import { useSocketStore } from '@/stores/socket'
import { useSysStore } from '@/stores/sys'
import { useBoardStore } from '@/stores/board'
import { useThemeStore } from '@/stores/theme'
import { PhUser, PhSignOut } from '@phosphor-icons/vue'
import PresenceGroup from '@/components/PresenceGroup.vue'
import HomeNav from '@/components/HomeNav.vue'
import ProjectNav from '@/components/ProjectNav.vue'
import { cssColorOr } from '@/utils/css'

const auth = useAuthStore()
const socket = useSocketStore()
const sys = useSysStore()
const board = useBoardStore()
const theme = useThemeStore()
const route = useRoute()
const router = useRouter()
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
    if (rgb) lines.push(`  --v-theme-${k}: ${rgb};`)
  }
  lines.push('}')
  return lines.join('\n')
}

function ensureThemeStyleEl(): HTMLStyleElement {
  let el = document.getElementById('ks-theme-vars') as HTMLStyleElement | null
  if (!el) {
    el = document.createElement('style')
    el.id = 'ks-theme-vars'
  }
  document.head.appendChild(el)
  return el
}

watchEffect(() => {
  const palette = theme.effectivePalette
  const dark = theme.effectiveDark
  vuetifyTheme.change(dark ? 'kaskaDark' : 'kaskaLight')
  if (!palette) return
  const css = [
    paletteToCssBlock(
      '.v-theme--kaskaLight, .v-theme-provider--kaskaLight',
      palette.palette_light,
    ),
    paletteToCssBlock(
      '.v-theme--kaskaDark, .v-theme-provider--kaskaDark',
      palette.palette_dark,
    ),
  ].join('\n')
  const el = ensureThemeStyleEl()
  el.textContent = css
})

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

const authScreen = computed(() => route.meta.authScreen === true)

const projectScopeRoutes = [
  'board',
  'task',
  'board_types',
  'board_members',
  'board_history',
  'board_settings',
]

const inProjectScope = computed(() => projectScopeRoutes.includes(route.name as string))
const isBoardView = computed(() => route.name === 'board')

watch(
  () => inProjectScope.value,
  (inScope) => {
    if (!inScope && board.project) {
      board.leave()
    }
  },
)

const currentSlug = computed(() => (route.params.slug as string | undefined) ?? null)

const headerPresenceUsers = computed(() => {
  if (!currentSlug.value || !board.project) return []
  return board.activeViewerIds
    .filter((id) => id !== auth.user?.id)
    .map((id) => board.users.find((u) => u.id === id))
    .filter((u): u is NonNullable<typeof u> => !!u)
})

const headerPresenceLabel = 'Сейчас в проекте'

function logout() {
  auth.logout()
}
</script>

<template>
  <v-app>
    <template v-if="!authScreen">
      <v-app-bar flat color="surface" class="ks-bar" height="64">
        <template #prepend>
          <v-app-bar-nav-icon
            v-if="mobile"
            aria-label="Открыть меню"
            @click="drawer = !drawer"
          />
          <template v-if="inProjectScope && board.project">
            <v-btn
              icon="mdi-arrow-left"
              variant="text"
              density="comfortable"
              @click="router.push({ name: 'projects' })"
            />
            <div class="ks-project-header">
              <v-avatar
                size="32"
                class="ks-project-header__avatar"
                color="primary-container"
              >
                <v-img
                  v-if="board.project.avatar_url"
                  :src="board.project.avatar_url"
                  cover
                  alt=""
                />
                <span v-else class="md-label-large">
                  {{ (board.project.name || '?').slice(0, 1).toUpperCase() }}
                </span>
              </v-avatar>
              <span class="md-title-large ks-project-header__name">{{ board.project.name }}</span>
            </div>
          </template>
          <router-link
            v-else
            :to="{ name: 'home' }"
            class="ks-brand md-state-layer"
            aria-label="Kaska"
          >
            <span class="ks-brand__logo">
              <v-icon size="22">mdi-hard-hat</v-icon>
            </span>
            <span class="ks-brand__name md-title-large">Kaska</span>
          </router-link>
        </template>

        <template #append>
          <template v-if="isBoardView">
            <div class="ks-board-controls" role="group" aria-label="Управление доской">
              <div class="ks-board-controls__view-group">
                <v-tooltip text="Колонки" location="bottom">
                  <template #activator="{ props }">
                    <v-btn
                      v-bind="props"
                      :active="board.viewMode === 'columns'"
                      :color="board.viewMode === 'columns' ? 'primary' : undefined"
                      :variant="board.viewMode === 'columns' ? 'flat' : 'text'"
                      icon="mdi-view-column-outline"
                      size="small"
                      rounded="pill"
                      @click="board.viewMode = 'columns'"
                    />
                  </template>
                </v-tooltip>
                <v-tooltip text="Список" location="bottom">
                  <template #activator="{ props }">
                    <v-btn
                      v-bind="props"
                      :active="board.viewMode === 'list'"
                      :color="board.viewMode === 'list' ? 'primary' : undefined"
                      :variant="board.viewMode === 'list' ? 'flat' : 'text'"
                      icon="mdi-format-list-bulleted"
                      size="small"
                      rounded="pill"
                      @click="board.viewMode = 'list'"
                    />
                  </template>
                </v-tooltip>
              </div>
              <v-btn
                variant="text"
                rounded="pill"
                size="small"
                :prepend-icon="board.filtersExpanded ? 'mdi-filter-minus-outline' : 'mdi-filter-plus-outline'"
                @click="board.filtersExpanded = !board.filtersExpanded"
              >
                Фильтры
              </v-btn>
              <v-btn
                v-if="board.canWrite"
                v-show="board.viewMode === 'list'"
                prepend-icon="mdi-plus"
                variant="tonal"
                rounded="pill"
                size="small"
                @click="board.triggerNewTask"
              >
                Новая задача
              </v-btn>
              <v-btn
                v-if="board.canWrite"
                prepend-icon="mdi-plus"
                variant="text"
                rounded="pill"
                size="small"
                @click="board.triggerNewColumn"
              >
                Новый статус
              </v-btn>
            </div>
          </template>
          <PresenceGroup
            v-if="headerPresenceUsers.length"
            class="mr-2"
            :users="headerPresenceUsers"
            :label="headerPresenceLabel"
            size="sm"
          />
          <template v-if="auth.isAuthed">
            <v-menu v-if="auth.isAuthed">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  variant="text"
                  rounded="pill"
                  size="default"
                  density="comfortable"
                  class="ks-bar__profile"
                  :title="auth.user?.email"
                >
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
        v-model="drawer"
        :permanent="!mobile"
        :temporary="mobile"
        rail
        :rail-width="96"
        color="surface"
        class="ks-nav"
        :border="0"
      >
        <ProjectNav v-if="inProjectScope && currentSlug" :slug="currentSlug" />
        <HomeNav v-else />
      </v-navigation-drawer>

      <v-main>
        <router-view />
      </v-main>
    </template>

    <template v-else>
      <v-main class="ks-authshell">
        <div class="ks-authshell__grid">
          <section class="ks-authshell__hero">
            <router-link :to="{ name: 'login' }" class="ks-authshell__brand md-state-layer">
              <span class="ks-brand__logo">
                <v-icon size="22">mdi-hard-hat</v-icon>
              </span>
              <span class="ks-brand__name md-title-large">Kaska</span>
            </router-link>
            <h1 class="ks-authshell__title">Канбан-доски для командной работы</h1>
            <p class="ks-authshell__lede md-body-large">
              Войдите, чтобы вернуться к своим проектам и доскам.
              Публичные доски доступны по прямой ссылке без аккаунта.
            </p>
          </section>

          <div class="ks-authshell__panel">
            <router-view />
          </div>
        </div>
      </v-main>
    </template>
  </v-app>
</template>

<style scoped>
.ks-bar {
  border-bottom: 1px solid rgba(var(--v-theme-on-surface), 0.06);
  backdrop-filter: saturate(180%) blur(8px);
  background: rgba(var(--v-theme-surface), 0.85);
  z-index: 1006;
}

.ks-brand {
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
.ks-brand__logo {
  width: 36px;
  height: 36px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.ks-brand__name {
  font-family: 'Roboto Flex', 'Roboto', sans-serif;
  font-variation-settings: 'wght' 600;
  letter-spacing: -0.01em;
}

.ks-project-header {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 6px 12px 6px 4px;
  margin-left: 4px;
  min-width: 0;
}
.ks-project-header__avatar {
  flex: 0 0 auto;
}
.ks-project-header__name {
  font-family: 'Roboto Flex', 'Roboto', sans-serif;
  font-variation-settings: 'wght' 600;
  letter-spacing: -0.01em;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 220px;
}
.ks-project-header__slug {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 13px;
  color: rgba(var(--v-theme-on-surface), 0.55);
}

.ks-board-controls {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-right: 8px;
}
.ks-board-controls__view-group {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-surface-container));
  border: 1px solid rgba(var(--v-theme-outline), 0.24);
}

.ks-bar__link {
  font-weight: 500;
}

.ks-bar__profile {
  padding: 4px;
}
.ks-bar__profile-name {
  max-width: 160px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

@media (max-width: 600px) {
  .ks-brand__name {
    display: none;
  }
  .ks-project-header__name {
    max-width: 120px;
  }
}

.ks-nav {
  background: rgb(var(--v-theme-surface));
  border-right: 1px solid rgba(var(--v-theme-on-surface), 0.06);
}

.ks-authshell {
  min-block-size: 100dvh;
  background:
    radial-gradient(circle at 0% 0%, rgba(var(--v-theme-primary), 0.16), transparent 55%),
    radial-gradient(circle at 100% 100%, rgba(var(--v-theme-tertiary), 0.12), transparent 55%),
    rgb(var(--v-theme-surface));
}
.ks-authshell__grid {
  min-block-size: 100dvh;
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
  align-items: center;
  gap: 48px;
  max-inline-size: 1100px;
  margin-inline: auto;
  padding: 48px 32px;
}
@media (max-width: 900px) {
  .ks-authshell__grid {
    grid-template-columns: minmax(0, 1fr);
    gap: 32px;
    padding: 32px 20px;
    align-content: center;
  }
}

.ks-authshell__hero {
  display: flex;
  flex-direction: column;
  gap: 20px;
  max-inline-size: 480px;
}
.ks-authshell__brand {
  align-self: flex-start;
  display: inline-flex;
  align-items: center;
  gap: 12px;
  text-decoration: none;
  color: rgb(var(--v-theme-on-surface));
  padding: 6px 14px 6px 6px;
  border-radius: var(--md-shape-full);
  --md-state-color: rgb(var(--v-theme-on-surface));
}
.ks-authshell__title {
  font-family: 'Roboto Flex', 'Roboto', sans-serif;
  font-size: clamp(28px, 4vw, 44px);
  line-height: 1.1;
  letter-spacing: -0.02em;
  font-weight: 500;
  margin: 0;
  color: rgb(var(--v-theme-on-surface));
}
.ks-authshell__lede {
  margin: 0;
  color: rgba(var(--v-theme-on-surface), 0.72);
}
@media (max-width: 900px) {
  .ks-authshell__hero {
    max-inline-size: none;
    text-align: center;
    align-items: center;
  }
}

.ks-authshell__panel {
  display: flex;
  justify-content: center;
}
</style>
