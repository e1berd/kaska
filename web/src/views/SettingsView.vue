<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useSysStore } from '../stores/sys'

const sys = useSysStore()

const loading = ref(false)
const saving = ref(false)
const allowRegistration = ref(false)
const error = ref<string | null>(null)
const success = ref(false)

async function loadSettings() {
  loading.value = true
  error.value = null
  try {
    const s = await sys.getSettings()
    allowRegistration.value = s.allow_registration
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
    const s = await sys.setSettings({ allow_registration: allowRegistration.value })
    allowRegistration.value = s.allow_registration
    success.value = true
    setTimeout(() => { success.value = false }, 3000)
  } catch (e: any) {
    error.value = e?.message || 'Ошибка сохранения настроек'
  } finally {
    saving.value = false
  }
}

onMounted(() => {
  loadSettings()
})

</script>

<template>
  <div class="pa-4 pa-sm-6 pa-md-8 mx-auto" style="max-width: 800px;">
    <h1 class="md-headline-medium mb-6">Настройки</h1>

    <v-card variant="outlined" class="mb-4">
      <v-card-text>
        <v-progress-linear v-if="loading" indeterminate color="primary"></v-progress-linear>

        <template v-else>
          <div class="d-flex align-center justify-space-between mb-4">
            <div>
              <h2 class="text-h6 font-weight-regular">Регистрация</h2>
              <div class="text-body-2 text-medium-emphasis">Разрешить свободную регистрацию новых пользователей</div>
            </div>

            <v-switch
              v-model="allowRegistration"
              color="primary"
              hide-details
              inset
            ></v-switch>
          </div>

          <v-alert v-if="error" type="error" variant="tonal" class="mt-4">{{ error }}</v-alert>
          <v-alert v-if="success" type="success" variant="tonal" class="mt-4">Настройки сохранены</v-alert>

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
