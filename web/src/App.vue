<script setup lang="ts">
import { useAuthStore } from './stores/auth'

const auth = useAuthStore()

function logout() {
  auth.logout()
}
</script>

<template>
  <v-app>
    <v-app-bar elevation="0" color="surface-container" density="comfortable">
      <v-app-bar-title>
        <router-link
          :to="{ name: 'home' }"
          class="d-flex align-center text-decoration-none"
          style="color: inherit; gap: 8px"
        >
          <v-icon>mdi-hard-hat</v-icon>
          <span class="text-h6">HardHat</span>
        </router-link>
      </v-app-bar-title>

      <template #append>
        <v-btn variant="text" :to="{ name: 'projects' }" class="mr-2">Проекты</v-btn>
        <template v-if="auth.isAuthed">
          <v-btn variant="text" :to="{ name: 'me' }">{{ auth.user?.email }}</v-btn>
          <v-btn variant="text" @click="logout">Выйти</v-btn>
        </template>
        <template v-else>
          <v-btn variant="text" :to="{ name: 'login' }">Войти</v-btn>
          <v-btn variant="tonal" :to="{ name: 'register' }" class="ml-2">Регистрация</v-btn>
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
