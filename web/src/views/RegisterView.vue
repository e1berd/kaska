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
  <v-container class="py-12">
    <v-row justify="center">
      <v-col cols="12" sm="8" md="5">
        <v-card class="pa-6" elevation="2">
          <h2 class="text-h5 mb-6">Регистрация</h2>

          <template v-if="!success">
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
                autocomplete="new-password"
                hint="Минимум 8 символов"
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
                Зарегистрироваться
              </v-btn>
            </v-form>

            <v-divider class="my-6" />

            <v-btn variant="text" :to="{ name: 'login' }" block>Уже есть аккаунт? Войти</v-btn>
          </template>

          <v-alert v-else type="success" variant="tonal">
            <p class="font-weight-medium mb-1">Почти готово!</p>
            <p>
              На <strong>{{ email }}</strong> отправлена ссылка для подтверждения почты. Открой её,
              чтобы активировать аккаунт.
            </p>
          </v-alert>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>
