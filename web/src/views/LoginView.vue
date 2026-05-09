<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref<string | null>(null)

async function submit() {
  error.value = null
  loading.value = true
  try {
    await auth.login(email.value, password.value)
    const next = (route.query.next as string) || '/projects'
    router.push(next)
  } catch (e: any) {
    error.value = e?.message ?? 'Не удалось войти'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="hh-auth">
    <v-card class="hh-auth__card" rounded="xl" elevation="0">
      <h1 class="md-headline-medium mb-1">С возвращением</h1>
      <p class="md-body-medium text-medium-emphasis mb-6">
        Войдите, чтобы создавать и менять задачи.
      </p>

      <v-form @submit.prevent="submit">
        <v-text-field
          v-model="email"
          label="Email"
          type="email"
          variant="filled"
          density="comfortable"
          autocomplete="email"
          required
          class="mb-3"
        />
        <v-text-field
          v-model="password"
          label="Пароль"
          type="password"
          variant="filled"
          density="comfortable"
          autocomplete="current-password"
          required
        />

        <v-alert
          v-if="error"
          type="error"
          variant="tonal"
          rounded="lg"
          class="mt-4"
          :text="error"
        />

        <v-btn
          type="submit"
          color="primary"
          variant="flat"
          rounded="pill"
          block
          size="large"
          :loading="loading"
          class="mt-6"
        >
          Войти
        </v-btn>
      </v-form>

      <div class="hh-auth__links">
        <router-link :to="{ name: 'forgot' }" class="hh-auth__link">
          Забыли пароль?
        </router-link>
        <router-link :to="{ name: 'register' }" class="hh-auth__link">
          Создать аккаунт
        </router-link>
      </div>
    </v-card>
  </div>
</template>
