<script setup lang="ts">
import { ref } from 'vue'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()

const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref<string | null>(null)
const success = ref(false)

async function submit() {
  error.value = null
  loading.value = true
  try {
    await auth.register(email.value, password.value)
    success.value = true
  } catch (e: any) {
    const errs = e?.errors
    if (errs && typeof errs === 'object') {
      const first = Object.values(errs).flat()[0]
      error.value = (first as string) ?? 'Не удалось зарегистрироваться'
    } else {
      error.value = e?.message ?? 'Не удалось зарегистрироваться'
    }
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="hh-auth">
    <v-card class="hh-auth__card" rounded="xl" elevation="0">
      <h1 class="md-headline-medium mb-1">Создать аккаунт</h1>
      <p class="md-body-medium text-medium-emphasis mb-6">
        После регистрации придёт письмо с подтверждением.
      </p>

      <template v-if="!success">
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
            Зарегистрироваться
          </v-btn>
        </v-form>

        <div class="hh-auth__links hh-auth__links--single">
          <router-link :to="{ name: 'login' }" class="hh-auth__link">
            Уже есть аккаунт? Войти
          </router-link>
        </div>
      </template>

      <v-alert v-else type="success" variant="tonal" rounded="lg">
        <p class="font-weight-medium mb-1">Почти готово!</p>
        <p class="mb-0">
          На <strong>{{ email }}</strong> отправлена ссылка для подтверждения почты.
          Откройте её, чтобы активировать аккаунт.
        </p>
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
.hh-auth__links {
  display: flex;
  justify-content: space-between;
  margin-top: 20px;
}
.hh-auth__links--single {
  justify-content: center;
}
.hh-auth__link {
  color: rgb(var(--v-theme-primary));
  text-decoration: none;
  font-weight: 500;
  font-size: 14px;
}
.hh-auth__link:hover {
  text-decoration: underline;
}
</style>
