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
  <v-container class="py-12">
    <v-row justify="center">
      <v-col cols="12" sm="8" md="5">
        <v-card class="pa-6" elevation="2">
          <h2 class="text-h5 mb-6">Восстановление пароля</h2>

          <template v-if="!submitted">
            <p class="mb-4 text-medium-emphasis">
              Введи email — пришлём ссылку на сброс пароля, если такой аккаунт существует.
            </p>
            <v-form @submit.prevent="submit">
              <v-text-field
                v-model="email"
                label="Email"
                type="email"
                autocomplete="email"
                required
                class="mb-2"
              />
              <v-btn
                type="submit"
                color="primary"
                variant="flat"
                block
                size="large"
                :loading="loading"
              >
                Отправить ссылку
              </v-btn>
            </v-form>
          </template>

          <v-alert v-else type="info" variant="tonal">
            Если на <strong>{{ email }}</strong> зарегистрирован аккаунт — мы отправили ссылку для
            сброса пароля.
          </v-alert>

          <v-divider class="my-6" />
          <v-btn variant="text" :to="{ name: 'login' }" block>Вернуться к входу</v-btn>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>
