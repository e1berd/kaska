<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const props = defineProps<{ token: string }>()
const auth = useAuthStore()
const router = useRouter()

const password = ref('')
const loading = ref(false)
const error = ref<string | null>(null)
const success = ref(false)

async function submit() {
  error.value = null
  loading.value = true
  try {
    await auth.resetPassword(props.token, password.value)
    success.value = true
    setTimeout(() => router.push({ name: 'login' }), 1500)
  } catch (e: any) {
    error.value = e?.message ?? 'Не удалось сбросить пароль'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="hh-auth">
    <v-card class="hh-auth__card" rounded="xl" elevation="0">
      <h1 class="md-headline-medium mb-6">Новый пароль</h1>

      <template v-if="!success">
        <v-form @submit.prevent="submit">
          <v-text-field
            v-model="password"
            label="Новый пароль"
            type="password"
            variant="filled"
            density="comfortable"
            autocomplete="new-password"
            hint="Минимум 8 символов"
            persistent-hint
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
            Сохранить пароль
          </v-btn>
        </v-form>
      </template>

      <v-alert v-else type="success" variant="tonal" rounded="lg">
        Пароль обновлён. Перенаправляем на страницу входа…
      </v-alert>
    </v-card>
  </div>
</template>

<style scoped>
.hh-auth {
  min-height: calc(100vh - 64px);
  display: grid;
  place-items: center;
  padding: 32px 16px;
}
.hh-auth__card {
  width: 100%;
  max-width: 440px;
  padding: 32px;
  background: rgb(var(--v-theme-surface-container-low)) !important;
}
</style>
