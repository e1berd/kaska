<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useProjectsStore } from '../stores/projects'
import { useAuthStore } from '../stores/auth'

const projects = useProjectsStore()
const auth = useAuthStore()

const dialog = ref(false)
const slug = ref('')
const name = ref('')
const description = ref('')
const submitting = ref(false)
const error = ref<string | null>(null)

onMounted(() => {
  projects.joinLobby().catch((e) => {
    console.warn('[projects] join failed', e)
  })
})

function openDialog() {
  slug.value = ''
  name.value = ''
  description.value = ''
  error.value = null
  dialog.value = true
}

async function submit() {
  submitting.value = true
  error.value = null
  try {
    await projects.createProject({
      slug: slug.value.trim(),
      name: name.value.trim(),
      description: description.value.trim() || undefined,
    })
    dialog.value = false
  } catch (e) {
    const msg = (e as { errors?: Record<string, string[]>; message?: string })
    if (msg.errors) {
      error.value = Object.entries(msg.errors)
        .map(([k, v]) => `${k}: ${v.join(', ')}`)
        .join('; ')
    } else {
      error.value = msg.message ?? 'не удалось создать проект'
    }
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <v-container class="py-8">
    <div class="d-flex align-center justify-space-between mb-6">
      <h1 class="text-h4">Проекты</h1>
      <v-btn
        v-if="auth.isAuthed"
        color="primary"
        variant="flat"
        prepend-icon="mdi-plus"
        @click="openDialog"
      >
        Новый проект
      </v-btn>
    </div>

    <p
      v-if="!auth.isAuthed"
      class="text-medium-emphasis mb-6"
    >
      Войдите, чтобы создать проект. Просматривать можно без аккаунта.
    </p>

    <div v-if="projects.list.length === 0" class="text-medium-emphasis py-12 text-center">
      Пока ни одного проекта. {{ auth.isAuthed ? 'Создайте первый.' : '' }}
    </div>

    <v-row v-else>
      <v-col v-for="p in projects.list" :key="p.id" cols="12" sm="6" md="4">
        <v-card
          :to="{ name: 'board', params: { slug: p.slug } }"
          variant="tonal"
          class="h-100"
        >
          <v-card-title>{{ p.name }}</v-card-title>
          <v-card-subtitle class="text-medium-emphasis">/{{ p.slug }}</v-card-subtitle>
          <v-card-text v-if="p.description">{{ p.description }}</v-card-text>
        </v-card>
      </v-col>
    </v-row>

    <v-dialog v-model="dialog" max-width="520" persistent>
      <v-card>
        <v-card-title>Новый проект</v-card-title>
        <v-card-text>
          <v-text-field
            v-model="slug"
            label="slug"
            hint="латиница, цифры и дефис, например my-project"
            persistent-hint
            density="comfortable"
          />
          <v-text-field v-model="name" label="название" density="comfortable" class="mt-2" />
          <v-textarea
            v-model="description"
            label="описание (опционально)"
            rows="3"
            density="comfortable"
            class="mt-2"
          />
          <v-alert v-if="error" type="error" variant="tonal" class="mt-4">{{ error }}</v-alert>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" :disabled="submitting" @click="dialog = false">Отмена</v-btn>
          <v-btn color="primary" variant="flat" :loading="submitting" @click="submit">
            Создать
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </v-container>
</template>
