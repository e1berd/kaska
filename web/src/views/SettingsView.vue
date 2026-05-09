<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useSysStore } from '../stores/sys'
import { useAuthStore } from '../stores/auth'
import { useThemeStore } from '../stores/theme'
import type { ThemeMode } from '../stores/auth'

const sys = useSysStore()
const auth = useAuthStore()
const theme = useThemeStore()

const loading = ref(false)
const saving = ref(false)
const allowRegistration = ref(false)
const allowGuestComments = ref(false)
const error = ref<string | null>(null)
const success = ref(false)

const isAdmin = computed(
  () => auth.user?.role === 'admin' || auth.user?.role === 'superadmin',
)

const userOverridesTheme = ref(!!auth.user?.theme_slug)
watch(
  () => auth.user?.theme_slug,
  (slug) => {
    userOverridesTheme.value = !!slug
  },
)

const userSelectedSlug = computed<string>({
  get: () => auth.user?.theme_slug ?? theme.globalSlug,
  set: (value) => {
    void theme.setUserTheme(value)
  },
})

const userMode = computed<ThemeMode>({
  get: () => auth.user?.theme_mode ?? 'system',
  set: (value) => {
    void theme.setUserMode(value)
  },
})

async function toggleUserOverride(value: boolean) {
  userOverridesTheme.value = value
  if (value) {
    await theme.setUserTheme(theme.effectiveSlug)
  } else {
    await theme.setUserTheme(null)
  }
}

const globalSlug = computed<string>({
  get: () => theme.globalSlug,
  set: (value) => {
    void theme.setGlobalTheme(value)
  },
})

const globalMode = computed<ThemeMode>({
  get: () => theme.globalMode,
  set: (value) => {
    void theme.setGlobalMode(value)
  },
})

async function loadSettings() {
  loading.value = true
  error.value = null
  try {
    const s = await sys.getSettings()
    allowRegistration.value = s.allow_registration
    allowGuestComments.value = s.allow_guest_comments
  } catch (e: any) {
    error.value = e?.message || 'Ошибка загрузки настроек'
  } finally {
    loading.value = false
  }
}

async function saveSettings() {
  saving.value = true
  error.value = null
  success.value = false
  try {
    const s = await sys.setSettings({
      allow_registration: allowRegistration.value,
      allow_guest_comments: allowGuestComments.value,
    })
    allowRegistration.value = s.allow_registration
    allowGuestComments.value = s.allow_guest_comments
    success.value = true
    setTimeout(() => { success.value = false }, 3000)
  } catch (e: any) {
    error.value = e?.message || 'Ошибка сохранения настроек'
  } finally {
    saving.value = false
  }
}

const modeOptions: { value: ThemeMode; label: string; icon: string }[] = [
  { value: 'light', label: 'Светлая', icon: 'mdi-white-balance-sunny' },
  { value: 'dark', label: 'Тёмная', icon: 'mdi-weather-night' },
  { value: 'system', label: 'Как в системе', icon: 'mdi-monitor' },
]

onMounted(() => {
  loadSettings()
  void theme.loadIndex().catch(() => {})
  for (const t of theme.themesIndex) {
    void theme.ensurePalette(t.slug).catch(() => {})
  }
})

watch(
  () => theme.themesIndex,
  (idx) => {
    for (const t of idx) {
      void theme.ensurePalette(t.slug).catch(() => {})
    }
  },
  { immediate: true, deep: true },
)
</script>

<template>
  <div class="pa-4 pa-sm-6 pa-md-8 mx-auto" style="max-width: 800px;">
    <h1 class="md-headline-medium mb-6">Настройки</h1>

    <v-card variant="outlined" class="mb-4">
      <v-card-text>
        <h2 class="md-title-medium mb-1">Моя тема</h2>
        <div class="text-body-2 text-medium-emphasis mb-3">
          Эти настройки применяются только к вам и не зависят от глобальной темы.
        </div>

        <div class="d-flex align-center justify-space-between mb-4 flex-wrap" style="gap: 12px;">
          <div>
            <div class="md-label-large">Использовать свою тему</div>
            <div class="text-body-2 text-medium-emphasis">
              Иначе применяется глобальная тема приложения.
            </div>
          </div>
          <v-switch
            :model-value="userOverridesTheme"
            color="primary"
            hide-details
            inset
            @update:model-value="toggleUserOverride($event === true)"
          />
        </div>

        <div v-if="userOverridesTheme" class="hh-themes mb-4">
          <button
            v-for="t in theme.themesIndex"
            :key="t.slug"
            type="button"
            class="hh-theme md-state-layer"
            :class="{ 'hh-theme--active': userSelectedSlug === t.slug }"
            @click="userSelectedSlug = t.slug"
          >
            <span
              class="hh-theme__swatch"
              :style="{
                background: theme.palettes[t.slug]?.palette_light?.primary ?? 'transparent',
              }"
            />
            <span
              class="hh-theme__swatch"
              :style="{
                background:
                  theme.palettes[t.slug]?.palette_light?.['secondary-container'] ?? 'transparent',
              }"
            />
            <span
              class="hh-theme__swatch"
              :style="{
                background: theme.palettes[t.slug]?.palette_light?.tertiary ?? 'transparent',
              }"
            />
            <span class="hh-theme__name md-label-large">{{ t.name }}</span>
          </button>
        </div>

        <div class="md-label-large mb-2">Режим</div>
        <v-btn-toggle
          v-model="userMode"
          mandatory
          rounded="pill"
          color="primary"
          density="comfortable"
          variant="outlined"
        >
          <v-btn
            v-for="opt in modeOptions"
            :key="opt.value"
            :value="opt.value"
            :prepend-icon="opt.icon"
          >
            {{ opt.label }}
          </v-btn>
        </v-btn-toggle>
      </v-card-text>
    </v-card>

    <v-card v-if="isAdmin" variant="outlined" class="mb-4">
      <v-card-text>
        <h2 class="md-title-medium mb-1">Глобальная тема</h2>
        <div class="text-body-2 text-medium-emphasis mb-3">
          Применяется ко всем, кроме пользователей с собственной темой.
          Меняется в реальном времени.
        </div>

        <div class="hh-themes mb-4">
          <button
            v-for="t in theme.themesIndex"
            :key="t.slug"
            type="button"
            class="hh-theme md-state-layer"
            :class="{ 'hh-theme--active': globalSlug === t.slug }"
            @click="globalSlug = t.slug"
          >
            <span
              class="hh-theme__swatch"
              :style="{
                background: theme.palettes[t.slug]?.palette_light?.primary ?? 'transparent',
              }"
            />
            <span
              class="hh-theme__swatch"
              :style="{
                background:
                  theme.palettes[t.slug]?.palette_light?.['secondary-container'] ?? 'transparent',
              }"
            />
            <span
              class="hh-theme__swatch"
              :style="{
                background: theme.palettes[t.slug]?.palette_light?.tertiary ?? 'transparent',
              }"
            />
            <span class="hh-theme__name md-label-large">{{ t.name }}</span>
          </button>
        </div>

        <div class="md-label-large mb-2">Режим по умолчанию</div>
        <v-btn-toggle
          v-model="globalMode"
          mandatory
          rounded="pill"
          color="primary"
          density="comfortable"
          variant="outlined"
        >
          <v-btn
            v-for="opt in modeOptions"
            :key="opt.value"
            :value="opt.value"
            :prepend-icon="opt.icon"
          >
            {{ opt.label }}
          </v-btn>
        </v-btn-toggle>
      </v-card-text>
    </v-card>

    <v-card v-if="isAdmin" variant="outlined" class="mb-4">
      <v-card-text>
        <h2 class="md-title-medium mb-3">Доступ</h2>
        <v-progress-linear v-if="loading" indeterminate color="primary"></v-progress-linear>

        <template v-else>
          <div class="d-flex align-center justify-space-between mb-4">
            <div>
              <div class="md-label-large">Регистрация</div>
              <div class="text-body-2 text-medium-emphasis">
                Разрешить свободную регистрацию новых пользователей
              </div>
            </div>

            <v-switch
              v-model="allowRegistration"
              color="primary"
              hide-details
              inset
            ></v-switch>
          </div>

          <div class="d-flex align-center justify-space-between mb-4">
            <div>
              <div class="md-label-large">Комментарии гостей</div>
              <div class="text-body-2 text-medium-emphasis">
                Разрешить неавторизованным пользователям оставлять комментарии к задачам
              </div>
            </div>

            <v-switch
              v-model="allowGuestComments"
              color="primary"
              hide-details
              inset
            ></v-switch>
          </div>

          <v-alert v-if="error" type="error" variant="tonal" class="mt-4">{{ error }}</v-alert>
          <v-alert v-if="success" type="success" variant="tonal" class="mt-4">
            Настройки сохранены
          </v-alert>

          <div class="d-flex justify-end mt-4">
            <v-btn color="primary" @click="saveSettings" :loading="saving" :disabled="loading">
              Сохранить
            </v-btn>
          </div>
        </template>
      </v-card-text>
    </v-card>
  </div>
</template>

<style scoped>
.hh-themes {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 10px;
}
.hh-theme {
  --md-state-color: rgb(var(--v-theme-primary));
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  border-radius: var(--md-shape-l);
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.6);
  background: rgb(var(--v-theme-surface-container-low));
  color: rgb(var(--v-theme-on-surface));
  cursor: pointer;
  transition:
    border-color var(--md-duration-short3) var(--md-easing-standard),
    background-color var(--md-duration-short3) var(--md-easing-standard);
}
.hh-theme:hover {
  border-color: rgb(var(--v-theme-primary));
}
.hh-theme--active {
  border-color: rgb(var(--v-theme-primary));
  background: rgba(var(--v-theme-primary), 0.08);
}
.hh-theme__swatch {
  width: 18px;
  height: 18px;
  border-radius: var(--md-shape-full);
  flex-shrink: 0;
  box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.12);
}
.hh-theme__name {
  flex: 1;
  text-align: left;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
