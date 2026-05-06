<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from './stores/auth'

const auth = useAuthStore()
const route = useRoute()

const currentSlug = computed(() => (route.params.slug as string | undefined) ?? null)

function logout() {
  auth.logout()
}
</script>

<template>
  <v-app>
    <v-app-bar flat color="surface" class="hh-bar" height="64">
      <template #prepend>
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
            @click="logout"
          >
            Выйти
          </v-btn>
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
      permanent
      width="240"
      color="surface"
      class="hh-nav"
      :border="0"
    >
      <v-list nav class="hh-nav__list pa-3">
        <v-list-item
          :to="{ name: 'projects' }"
          prepend-icon="mdi-view-grid-outline"
          title="Проекты"
          rounded="pill"
          class="hh-nav__item md-label-large"
          color="primary"
        />
        <v-list-item
          v-if="currentSlug"
          :to="{ name: 'board_types', params: { slug: currentSlug } }"
          prepend-icon="mdi-tag-multiple-outline"
          title="Типы задач"
          rounded="pill"
          class="hh-nav__item md-label-large"
          color="primary"
        />
      </v-list>
    </v-navigation-drawer>

    <v-main>
      <router-view v-slot="{ Component }">
        <transition name="page" mode="out-in">
          <component :is="Component" />
        </transition>
      </router-view>
    </v-main>
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

/* M3 navigation drawer — surface-tinted, no border, items are pill-shaped
 * so the active state reads as a primary container chip. */
.hh-nav {
  background: rgb(var(--v-theme-surface)) !important;
}
.hh-nav__list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.hh-nav :deep(.hh-nav__item) {
  min-height: 56px;
  padding-inline: 16px;
}
.hh-nav :deep(.hh-nav__item.v-list-item--active) {
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
}
.hh-nav :deep(.hh-nav__item.v-list-item--active .v-icon) {
  color: rgb(var(--v-theme-on-secondary-container));
}
</style>
