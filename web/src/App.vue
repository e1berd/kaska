<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, type RouteLocationRaw } from 'vue-router'
import { useDisplay } from 'vuetify'
import { useAuthStore } from './stores/auth'

const auth = useAuthStore()
const route = useRoute()
const { mobile } = useDisplay()

const showSidebar = ref(route.name !== 'home')
watch(() => route.name, (name) => { showSidebar.value = name !== 'home' })

const drawer = ref(!mobile.value)
watch(mobile, (m) => {
  drawer.value = !m
})

const currentSlug = computed(() => (route.params.slug as string | undefined) ?? null)

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
            <router-link
              :to="{ name: 'me' }"
              class="hh-bar__profile md-state-layer"
              :title="auth.user?.email"
            >
              <span class="hh-bar__avatar">
                <img
                  v-if="auth.user?.avatar_url"
                  :src="auth.user.avatar_url"
                  alt=""
                />
                <span v-else>{{
                  (auth.user?.display_name || auth.user?.email || '?').slice(0, 1).toUpperCase()
                }}</span>
              </span>
              <span class="hh-bar__profile-name">
                {{ auth.user?.display_name || auth.user?.email?.split('@')[0] }}
              </span>
            </router-link>
            <v-btn
              variant="text"
              class="hh-bar__link ml-1"
              rounded="pill"
              :icon="mobile"
              @click="logout"
            >
              <v-icon v-if="mobile">mdi-logout</v-icon>
              <template v-else>Выйти</template>
            </v-btn>
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
        <router-view v-slot="{ Component }">
          <transition name="page" mode="out-in">
            <component :is="Component" />
          </transition>
        </router-view>
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
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 4px 12px 4px 4px;
  border-radius: var(--md-shape-full);
  text-decoration: none;
  color: inherit;
  --md-state-color: rgb(var(--v-theme-on-surface));
}
.hh-bar__avatar {
  width: 32px;
  height: 32px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
  overflow: hidden;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 14px;
}
.hh-bar__avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.hh-bar__profile-name {
  font-weight: 500;
  font-size: 14px;
  max-width: 160px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

@media (max-width: 600px) {
  .hh-brand__name {
    display: none;
  }
  .hh-bar__profile-name {
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
