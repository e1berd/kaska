<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
const router = useRouter()

onMounted(() => {
  auth.fetchMe().catch(() => {
    /* token may be expired — bootstrap will recover */
  })
})

function logout() {
  auth.logout()
  router.push({ name: 'home' })
}
</script>

<template>
  <div class="hh-me">
    <v-card class="hh-me__card" rounded="xl" elevation="0">
      <header class="hh-me__head">
        <div class="hh-me__avatar">
          <v-icon size="32">mdi-account</v-icon>
        </div>
        <div>
          <h1 class="md-headline-small mb-0">{{ auth.user?.email }}</h1>
          <p class="md-body-small text-medium-emphasis mt-1 mb-0">
            Профиль пользователя
          </p>
        </div>
      </header>

      <v-divider class="my-4" />

      <ul v-if="auth.user" class="hh-me__list">
        <li class="hh-me__row">
          <v-icon class="hh-me__icon">mdi-shield-account-outline</v-icon>
          <div>
            <div class="md-label-medium text-medium-emphasis">Роль</div>
            <div class="md-body-large">{{ auth.user.role }}</div>
          </div>
        </li>
        <li class="hh-me__row">
          <v-icon class="hh-me__icon" :color="auth.user.confirmed_at ? 'primary' : undefined">
            {{ auth.user.confirmed_at ? 'mdi-check-decagram' : 'mdi-email-alert-outline' }}
          </v-icon>
          <div>
            <div class="md-label-medium text-medium-emphasis">Почта</div>
            <div class="md-body-large">
              {{ auth.user.confirmed_at ? 'Подтверждена' : 'Не подтверждена' }}
            </div>
          </div>
        </li>
      </ul>

      <v-divider class="my-4" />

      <div class="d-flex justify-end">
        <v-btn variant="text" color="error" rounded="pill" @click="logout">
          Выйти из аккаунта
        </v-btn>
      </div>
    </v-card>
  </div>
</template>

<style scoped>
.hh-me {
  max-width: 640px;
  margin: 32px auto;
  padding: 0 16px;
}
.hh-me__card {
  padding: 32px;
  background: rgb(var(--v-theme-surface-container-low)) !important;
}
.hh-me__head {
  display: flex;
  align-items: center;
  gap: 16px;
}
.hh-me__avatar {
  width: 56px;
  height: 56px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.hh-me__list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: grid;
  gap: 12px;
}
.hh-me__row {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 8px 4px;
}
.hh-me__icon {
  color: rgba(var(--v-theme-on-surface), 0.65);
}
</style>
