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
  <div class="hh-auth">
    <v-card class="hh-auth__card text-center" rounded="xl" elevation="0">
      <template v-if="status === 'pending'">
        <v-progress-circular indeterminate color="primary" size="48" class="mb-4" />
        <h2 class="md-title-large mb-1">Подтверждаем почту…</h2>
      </template>

      <template v-else-if="status === 'success'">
        <div class="hh-verify__icon hh-verify__icon--ok">
          <v-icon size="40">mdi-check</v-icon>
        </div>
        <h2 class="md-headline-small mt-4 mb-2">Почта подтверждена</h2>
        <p class="md-body-medium text-medium-emphasis mb-6">
          Теперь можно войти в аккаунт.
        </p>
        <v-btn
          color="primary"
          variant="flat"
          rounded="pill"
          size="large"
          :to="{ name: 'login' }"
        >
          Войти
        </v-btn>
      </template>

      <template v-else>
        <div class="hh-verify__icon hh-verify__icon--err">
          <v-icon size="40">mdi-alert-circle-outline</v-icon>
        </div>
        <h2 class="md-headline-small mt-4 mb-2">Ошибка</h2>
        <p class="md-body-medium text-medium-emphasis mb-6">{{ message }}</p>
        <v-btn variant="tonal" rounded="pill" :to="{ name: 'home' }">На главную</v-btn>
      </template>
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
  padding: 40px 32px;
  background: rgb(var(--v-theme-surface-container-low)) !important;
}
.hh-verify__icon {
  width: 72px;
  height: 72px;
  margin: 0 auto;
  border-radius: var(--md-shape-full);
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.hh-verify__icon--ok {
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
}
.hh-verify__icon--err {
  background: rgb(var(--v-theme-error-container));
  color: rgb(var(--v-theme-on-error-container));
}
</style>
