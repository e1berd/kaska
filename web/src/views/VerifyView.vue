<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useAuthStore } from '../stores/auth'

const props = defineProps<{ token: string }>()
const auth = useAuthStore()

const status = ref<'pending' | 'success' | 'error'>('pending')
const message = ref<string>('')

onMounted(async () => {
  try {
    const resp = await auth.verifyEmail(props.token)
    status.value = 'success'
    message.value = resp.message
  } catch (e: any) {
    status.value = 'error'
    message.value = e?.message ?? 'Не удалось подтвердить почту'
  }
})
</script>

<template>
  <v-container class="py-12">
    <v-row justify="center">
      <v-col cols="12" sm="8" md="5">
        <v-card class="pa-6 text-center" elevation="2">
          <template v-if="status === 'pending'">
            <v-progress-circular indeterminate color="primary" size="48" class="mb-4" />
            <p>Подтверждаем почту…</p>
          </template>

          <template v-else-if="status === 'success'">
            <v-icon size="64" color="primary" class="mb-2">mdi-check-circle</v-icon>
            <h2 class="text-h5 mb-3">Почта подтверждена</h2>
            <p class="mb-6 text-medium-emphasis">Теперь можно войти в аккаунт.</p>
            <v-btn color="primary" variant="flat" :to="{ name: 'login' }" size="large">
              Войти
            </v-btn>
          </template>

          <template v-else>
            <v-icon size="64" color="error" class="mb-2">mdi-alert-circle</v-icon>
            <h2 class="text-h5 mb-3">Ошибка</h2>
            <p class="mb-6 text-medium-emphasis">{{ message }}</p>
            <v-btn variant="tonal" :to="{ name: 'home' }">На главную</v-btn>
          </template>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>
