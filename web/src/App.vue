<script setup lang="ts">
import { useAuthStore } from './stores/auth'

const auth = useAuthStore()

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
        <v-btn
          variant="text"
          :to="{ name: 'projects' }"
          class="hh-bar__link"
          rounded="pill"
        >
          Проекты
        </v-btn>
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
</style>
