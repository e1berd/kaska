<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useSysStore } from '@/stores/sys'

const auth = useAuthStore()
const sys = useSysStore()
const route = useRoute()

const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref<string | null>(null)
const success = ref(false)
const inviteToken = ref<string | undefined>(undefined)
const firstUserBootstrap = ref(false)
const bootstrapResult = ref(false)

const checkLoading = ref(true)
const registrationAllowed = ref(true)

async function checkRegistration() {
  checkLoading.value = true
  if (route.query.token) {
    inviteToken.value = route.query.token as string
    registrationAllowed.value = true
    checkLoading.value = false
    return
  }

  try {
    const s = await sys.getSettings()
    registrationAllowed.value = s.allow_registration
    firstUserBootstrap.value = s.first_user_bootstrap
  } catch (e: any) {
    error.value = e?.message || 'Не удалось проверить настройки регистрации'
    registrationAllowed.value = false
  } finally {
    checkLoading.value = false
  }
}

onMounted(checkRegistration)

async function submit() {
  if (!registrationAllowed.value && !inviteToken.value) {
    error.value = "Регистрация закрыта."
    return
  }

  error.value = null
  loading.value = true
  try {
    const res = await auth.register(email.value, password.value, inviteToken.value)
    bootstrapResult.value = !!res.first_user_bootstrap
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
      <div v-if="checkLoading" class="text-center pa-4">
        <v-progress-circular indeterminate color="primary"></v-progress-circular>
      </div>

      <template v-else>
        <h1 class="md-headline-medium mb-1">{{ firstUserBootstrap ? 'Инициализация владельца' : 'Создать аккаунт' }}</h1>
        <p class="md-body-medium text-medium-emphasis mb-6">
          <template v-if="firstUserBootstrap">
            Это первая регистрация в системе. Аккаунт будет сразу подтвержден и получит роль суперадмина.
          </template>
          <template v-else>
            После регистрации придёт письмо с подтверждением.
          </template>
        </p>

        <template v-if="!success">
          <v-form @submit.prevent="submit" :disabled="!registrationAllowed">
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
              v-if="!registrationAllowed && !inviteToken"
              type="warning"
              variant="tonal"
              rounded="lg"
              class="mt-4"
              text="Свободная регистрация в данный момент закрыта. Требуется приглашение."
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
              :disabled="!registrationAllowed && !inviteToken"
              class="mt-6"
            >
              {{ firstUserBootstrap ? 'Создать владельца' : 'Зарегистрироваться' }}
            </v-btn>
          </v-form>

          <div class="hh-auth__links hh-auth__links--single">
            <router-link :to="{ name: 'login' }" class="hh-auth__link">
              Уже есть аккаунт? Войти
            </router-link>
          </div>
        </template>

        <v-alert v-else type="success" variant="tonal" rounded="lg">
          <template v-if="bootstrapResult">
            <p class="font-weight-medium mb-1">Владелец создан</p>
            <p class="mb-0">
              Аккаунт <strong>{{ email }}</strong> сразу подтвержден и назначен суперадмином.
              Теперь можно войти и продолжить настройку системы.
            </p>
          </template>
          <template v-else>
            <p class="font-weight-medium mb-1">Почти готово!</p>
            <p class="mb-0">
              На <strong>{{ email }}</strong> отправлена ссылка для подтверждения почты.
              Откройте её, чтобы активировать аккаунт.
            </p>
          </template>
        </v-alert>
      </template>
    </v-card>
  </div>
</template>
