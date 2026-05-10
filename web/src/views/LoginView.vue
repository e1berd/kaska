<script setup lang="ts">
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref<string | null>(null)
const errorCode = ref<string | null>(null)
const resending = ref(false)
const resendNotice = ref<string | null>(null)

async function submit() {
  error.value = null
  errorCode.value = null
  resendNotice.value = null
  loading.value = true
  try {
    await auth.login(email.value, password.value)
    const next = (route.query.next as string) || '/projects'
    router.push(next)
  } catch (e: any) {
    error.value = e?.message ?? 'Не удалось войти'
    errorCode.value = e?.code ?? null
  } finally {
    loading.value = false
  }
}

async function resendVerification() {
  if (!email.value || resending.value) return
  resending.value = true
  resendNotice.value = null
  try {
    await auth.resendVerification(email.value)
    resendNotice.value = 'Письмо отправлено. Проверьте почту.'
  } catch (e: any) {
    resendNotice.value = e?.message ?? 'Не удалось отправить письмо'
  } finally {
    resending.value = false
  }
}
</script>

<template>
  <div class="ks-auth">
    <v-card class="ks-auth__card" rounded="xl" elevation="0">
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
        >
          <div>{{ error }}</div>
          <div v-if="errorCode === 'email_not_verified'" class="mt-2">
            <v-btn
              size="small"
              variant="tonal"
              rounded="pill"
              :loading="resending"
              :disabled="!email"
              @click="resendVerification"
            >
              Отправить письмо ещё раз
            </v-btn>
          </div>
        </v-alert>

        <v-alert
          v-if="resendNotice"
          type="info"
          variant="tonal"
          rounded="lg"
          class="mt-3"
          :text="resendNotice"
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

      <div class="ks-auth__links">
        <router-link :to="{ name: 'forgot' }" class="ks-auth__link">
          Забыли пароль?
        </router-link>
        <router-link :to="{ name: 'register' }" class="ks-auth__link">
          Создать аккаунт
        </router-link>
      </div>
    </v-card>
  </div>
</template>
