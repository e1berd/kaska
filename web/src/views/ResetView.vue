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
  <v-container class="py-12">
    <v-row justify="center">
      <v-col cols="12" sm="8" md="5">
        <v-card class="pa-6" elevation="2">
          <h2 class="text-h5 mb-6">Новый пароль</h2>

          <template v-if="!success">
            <v-form @submit.prevent="submit">
              <v-text-field
                v-model="password"
                label="Новый пароль"
                type="password"
                autocomplete="new-password"
                hint="Минимум 8 символов"
                required
                class="mb-2"
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
                Сохранить пароль
              </v-btn>
            </v-form>
          </template>

          <v-alert v-else type="success" variant="tonal">
            Пароль обновлён. Перенаправляем на страницу входа…
          </v-alert>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>
