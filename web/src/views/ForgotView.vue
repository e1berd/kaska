<script setup lang="ts">
import { ref } from 'vue'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
const email = ref('')
const loading = ref(false)
const submitted = ref(false)

async function submit() {
  loading.value = true
  try {
    await auth.forgotPassword(email.value)
    submitted.value = true
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="hh-auth">
    <v-card class="hh-auth__card" rounded="xl" elevation="0">
      <h1 class="md-headline-medium mb-1">Восстановление пароля</h1>

      <template v-if="!submitted">
        <p class="md-body-medium text-medium-emphasis mb-6">
          Введите email — пришлём ссылку на сброс пароля, если такой аккаунт существует.
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
            Отправить ссылку
          </v-btn>
        </v-form>
      </template>

      <v-alert v-else type="info" variant="tonal" rounded="lg" class="mt-2">
        Если на <strong>{{ email }}</strong> зарегистрирован аккаунт — мы отправили
        ссылку для сброса пароля.
      </v-alert>

      <div class="hh-auth__links hh-auth__links--single">
        <router-link :to="{ name: 'login' }" class="hh-auth__link">
          Вернуться к входу
        </router-link>
      </div>
    </v-card>
  </div>
</template>
