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
    const next = (route.query.next as string) || '/me'
    router.push(next)
  } catch (e: any) {
    error.value = e?.message ?? 'Не удалось войти'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <v-container class="py-12">
    <v-row justify="center">
      <v-col cols="12" sm="8" md="5">
        <v-card class="pa-6" elevation="2">
          <h2 class="text-h5 mb-6">Вход</h2>
          <v-form @submit.prevent="submit">
            <v-text-field
              v-model="email"
              label="Email"
              type="email"
              autocomplete="email"
              required
              class="mb-2"
            />
            <v-text-field
              v-model="password"
              label="Пароль"
              type="password"
              autocomplete="current-password"
              required
            />

            <v-alert v-if="error" type="error" variant="tonal" class="mb-4" :text="error" />

            <v-btn
              type="submit"
              color="primary"
              variant="flat"
              block
              size="large"
              :loading="loading"
            >
              Войти
            </v-btn>
          </v-form>

          <v-divider class="my-6" />

          <div class="d-flex flex-column ga-2">
            <v-btn variant="text" :to="{ name: 'register' }">Создать аккаунт</v-btn>
            <v-btn variant="text" :to="{ name: 'forgot' }">Забыли пароль?</v-btn>
          </div>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>
