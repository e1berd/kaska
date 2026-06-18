<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()

const editingName = ref(false)
const nameDraft = ref('')
const nameSubmitting = ref(false)
const nameError = ref<string | null>(null)

const avatarInput = ref<HTMLInputElement | null>(null)
const avatarUploading = ref(false)
const avatarProgress = ref(0)
const avatarError = ref<string | null>(null)

const displayedName = computed(
  () => auth.user?.display_name?.trim() || auth.user?.email?.split('@')[0] || '—',
)
const initials = computed(() => {
  const src = auth.user?.display_name?.trim() || auth.user?.email || '?'
  return src.slice(0, 1).toUpperCase()
})

watch(
  () => auth.user,
  () => {
    if (!editingName.value) nameDraft.value = auth.user?.display_name ?? ''
  },
  { immediate: true },
)

onMounted(() => {
  void auth.fetchMe().catch(() => undefined)
})

function startEditName() {
  nameDraft.value = auth.user?.display_name ?? ''
  nameError.value = null
  editingName.value = true
}

async function commitName() {
  nameSubmitting.value = true
  nameError.value = null
  try {
    await auth.updateProfile({ display_name: nameDraft.value.trim() })
    editingName.value = false
  } catch (e) {
    const msg = e as { errors?: Record<string, string[]>; message?: string }
    nameError.value =
      (msg.errors && Object.values(msg.errors).flat()[0]) ||
      msg.message ||
      'не удалось сохранить'
  } finally {
    nameSubmitting.value = false
  }
}

function pickAvatar() {
  avatarInput.value?.click()
}

async function onAvatarPicked(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file) return

  avatarError.value = null
  avatarUploading.value = true
  avatarProgress.value = 0
  try {
    await auth.uploadAvatar(file, (f) => (avatarProgress.value = f))
  } catch (e) {
    avatarError.value = (e as { message?: string }).message ?? 'не удалось загрузить'
  } finally {
    avatarUploading.value = false
    avatarProgress.value = 0
  }
}

function logout() {
  auth.logout()
  router.push({ name: 'home' })
}
</script>

<template>
  <div class="ks-me">
    <v-card class="ks-me__card" rounded="xl" elevation="0">
      <header class="ks-me__head">
        <div class="ks-me__avatar-wrap">
          <div class="ks-me__avatar">
            <img v-if="auth.user?.avatar_url" :src="auth.user.avatar_url" alt="avatar" />
            <span v-else class="ks-me__initials">{{ initials }}</span>
          </div>
          <button
            type="button"
            class="ks-me__avatar-edit"
            :disabled="avatarUploading"
            title="Сменить аватар"
            @click="pickAvatar"
          >
            <v-icon size="18">mdi-camera-plus-outline</v-icon>
          </button>
          <input
            ref="avatarInput"
            type="file"
            accept="image/*"
            class="ks-me__file"
            @change="onAvatarPicked"
          />
        </div>

        <div class="ks-me__name-block">
          <template v-if="!editingName">
            <h1 class="md-headline-small mb-0 ks-me__name">
              {{ displayedName }}
              <v-btn
                icon="mdi-pencil-outline"
                variant="text"
                density="comfortable"
                size="small"
                @click="startEditName"
              />
            </h1>
          </template>
          <template v-else>
            <v-text-field
              v-model="nameDraft"
              label="Имя"
              variant="filled"
              density="comfortable"
              :disabled="nameSubmitting"
              autofocus
              hide-details
              @keydown.enter.exact.prevent="commitName"
              @keydown.escape.prevent="editingName = false"
            />
            <div class="d-flex ga-2 mt-2">
              <v-btn
                color="primary"
                variant="flat"
                rounded="pill"
                density="comfortable"
                :loading="nameSubmitting"
                @click="commitName"
              >
                Сохранить
              </v-btn>
              <v-btn
                variant="text"
                rounded="pill"
                density="comfortable"
                :disabled="nameSubmitting"
                @click="editingName = false"
              >
                Отмена
              </v-btn>
            </div>
          </template>
          <p class="md-body-small text-medium-emphasis mt-1 mb-0">
            {{ auth.user?.email }}
          </p>
        </div>
      </header>

      <v-progress-linear
        v-if="avatarUploading"
        :model-value="avatarProgress * 100"
        color="primary"
        rounded
        height="4"
        class="mt-2"
      />
      <v-alert
        v-if="avatarError"
        type="error"
        variant="tonal"
        rounded="lg"
        class="mt-3"
        :text="avatarError"
      />
      <v-alert
        v-if="nameError && !editingName"
        type="error"
        variant="tonal"
        rounded="lg"
        class="mt-3"
        :text="nameError"
      />

      <v-divider class="my-4" />

      <ul v-if="auth.user" class="ks-me__list">
        <li class="ks-me__row">
          <v-icon class="ks-me__icon">mdi-shield-account-outline</v-icon>
          <div>
            <div class="md-label-medium text-medium-emphasis">Роль</div>
            <div class="md-body-large">{{ auth.user.role }}</div>
          </div>
        </li>
        <li class="ks-me__row">
          <v-icon class="ks-me__icon" :color="auth.user.confirmed_at ? 'primary' : undefined">
            {{ auth.user.confirmed_at ? 'mdi-check-decagram' : 'mdi-email-alert-outline' }}
          </v-icon>
          <div>
            <div class="md-label-medium text-medium-emphasis">Почта</div>
            <div class="md-body-large">
              {{ auth.user.confirmed_at ? 'Подтверждена' : 'Не подтверждена' }}
            </div>
          </div>
        </li>
      </ul>

      <v-divider class="my-4" />

      <div class="d-flex justify-end">
        <v-btn variant="text" color="error" rounded="pill" @click="logout">
          Выйти из аккаунта
        </v-btn>
      </div>
    </v-card>
  </div>
</template>

<style scoped>
.ks-me {
  max-width: 640px;
  margin: 32px auto;
  padding: 0 16px;
}
.ks-me__card {
  padding: 32px;
  background: rgb(var(--v-theme-surface-container-low));
}
.ks-me__head {
  display: flex;
  align-items: center;
  gap: 20px;
}
.ks-me__avatar-wrap {
  position: relative;
}
.ks-me__avatar {
  width: 88px;
  height: 88px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 32px;
  font-weight: 500;
}
.ks-me__avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}
.ks-me__avatar-edit {
  position: absolute;
  right: -4px;
  bottom: -4px;
  width: 32px;
  height: 32px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-primary));
  color: rgb(var(--v-theme-on-primary));
  border: 2px solid rgb(var(--v-theme-surface-container-low));
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: transform var(--md-duration-short3) var(--md-easing-standard);
}
.ks-me__avatar-edit:hover:not(:disabled) {
  transform: scale(1.06);
}
.ks-me__avatar-edit:disabled {
  opacity: 0.5;
  cursor: progress;
}
.ks-me__file {
  display: none;
}
.ks-me__name-block {
  flex: 1;
  min-width: 0;
}
.ks-me__name {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.ks-me__list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: grid;
  gap: 12px;
}
.ks-me__row {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 8px 4px;
}
.ks-me__icon {
  color: rgba(var(--v-theme-on-surface), 0.65);
}
</style>
