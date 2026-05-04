<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
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
const filter = ref('')

const filtered = computed(() => {
  const q = filter.value.trim().toLowerCase()
  if (!q) return projects.list
  return projects.list.filter(
    (p) =>
      p.name.toLowerCase().includes(q) ||
      p.slug.toLowerCase().includes(q) ||
      (p.description ?? '').toLowerCase().includes(q),
  )
})

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
    const msg = e as { errors?: Record<string, string[]>; message?: string }
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

// Stable accent per project for the leading initial — keeps the grid lively
// without random colours that flicker on re-render.
function accent(id: string): 'primary' | 'secondary' | 'tertiary' {
  const sum = [...id].reduce((s, c) => s + c.charCodeAt(0), 0)
  return (['primary', 'secondary', 'tertiary'] as const)[sum % 3]
}
</script>

<template>
  <div class="hh-projects">
    <header class="hh-projects__head">
      <div>
        <h1 class="md-headline-large">Проекты</h1>
        <p v-if="!auth.isAuthed" class="md-body-medium text-medium-emphasis mt-2 mb-0">
          Войдите, чтобы создать проект. Просматривать можно без аккаунта.
        </p>
      </div>
      <div class="hh-projects__actions">
        <v-text-field
          v-model="filter"
          variant="solo-filled"
          flat
          rounded="pill"
          hide-details
          density="comfortable"
          prepend-inner-icon="mdi-magnify"
          placeholder="Поиск"
          class="hh-projects__filter"
        />
        <v-btn
          v-if="auth.isAuthed"
          color="primary"
          variant="flat"
          rounded="pill"
          size="large"
          prepend-icon="mdi-plus"
          @click="openDialog"
        >
          Новый проект
        </v-btn>
      </div>
    </header>

    <div v-if="projects.list.length === 0" class="hh-projects__empty">
      <div class="hh-projects__empty-icon">
        <v-icon size="40">mdi-folder-open-outline</v-icon>
      </div>
      <h2 class="md-title-large mt-4">Пока ни одного проекта</h2>
      <p class="md-body-medium text-medium-emphasis mt-1 mb-4">
        {{ auth.isAuthed ? 'Создайте первый — это займёт пару секунд.' : 'Зайдите под аккаунтом, чтобы создать первый проект.' }}
      </p>
      <v-btn
        v-if="auth.isAuthed"
        color="primary"
        variant="flat"
        rounded="pill"
        prepend-icon="mdi-plus"
        @click="openDialog"
      >
        Новый проект
      </v-btn>
    </div>

    <div v-else class="hh-projects__grid">
      <router-link
        v-for="p in filtered"
        :key="p.id"
        :to="{ name: 'board', params: { slug: p.slug } }"
        class="hh-project md-state-layer"
      >
        <div class="hh-project__avatar" :data-accent="accent(p.id)">
          {{ p.name.slice(0, 1).toUpperCase() }}
        </div>
        <div class="hh-project__body">
          <h3 class="hh-project__name md-title-medium">{{ p.name }}</h3>
          <code class="hh-project__slug">/{{ p.slug }}</code>
          <p v-if="p.description" class="hh-project__desc md-body-small">
            {{ p.description }}
          </p>
        </div>
        <v-icon class="hh-project__chev" size="20">mdi-chevron-right</v-icon>
      </router-link>
    </div>

    <v-dialog v-model="dialog" max-width="560" persistent>
      <v-card rounded="xl">
        <v-card-title class="md-headline-small px-6 pt-6">Новый проект</v-card-title>
        <v-card-text class="px-6 pt-2">
          <v-text-field
            v-model="slug"
            label="slug"
            variant="filled"
            density="comfortable"
            hint="латиница, цифры и дефис, например my-project"
            persistent-hint
          />
          <v-text-field
            v-model="name"
            label="название"
            variant="filled"
            density="comfortable"
            class="mt-3"
          />
          <v-textarea
            v-model="description"
            label="описание (опционально)"
            variant="filled"
            rows="3"
            density="comfortable"
            class="mt-3"
          />
          <v-alert v-if="error" type="error" variant="tonal" class="mt-4" rounded="lg">
            {{ error }}
          </v-alert>
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-spacer />
          <v-btn
            variant="text"
            rounded="pill"
            :disabled="submitting"
            @click="dialog = false"
          >
            Отмена
          </v-btn>
          <v-btn
            color="primary"
            variant="flat"
            rounded="pill"
            :loading="submitting"
            @click="submit"
          >
            Создать
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<style scoped>
.hh-projects {
  max-width: 1120px;
  margin: 0 auto;
  padding: 32px 24px 64px;
}
.hh-projects__head {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 24px;
  flex-wrap: wrap;
  margin-bottom: 28px;
}
.hh-projects__actions {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.hh-projects__filter {
  min-width: 280px;
}

.hh-projects__empty {
  text-align: center;
  padding: 80px 24px;
  border-radius: var(--md-shape-xl);
  background: rgb(var(--v-theme-surface-container-low));
}
.hh-projects__empty-icon {
  width: 72px;
  height: 72px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.hh-projects__grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 12px;
}

.hh-project {
  display: grid;
  grid-template-columns: 48px 1fr 24px;
  gap: 16px;
  align-items: center;
  padding: 16px;
  background: rgb(var(--v-theme-surface-container-low));
  color: rgb(var(--v-theme-on-surface));
  text-decoration: none;
  border-radius: var(--md-shape-l);
  transition:
    background-color var(--md-duration-short3) var(--md-easing-standard),
    transform var(--md-duration-short4) var(--md-easing-standard);
  --md-state-color: rgb(var(--v-theme-on-surface));
}
.hh-project:hover {
  background: rgb(var(--v-theme-surface-container));
}
.hh-project:active {
  transform: scale(0.997);
}

.hh-project__avatar {
  width: 48px;
  height: 48px;
  border-radius: var(--md-shape-m);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 18px;
}
.hh-project__avatar[data-accent='primary'] {
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
}
.hh-project__avatar[data-accent='secondary'] {
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
}
.hh-project__avatar[data-accent='tertiary'] {
  background: rgb(var(--v-theme-tertiary-container));
  color: rgb(var(--v-theme-on-tertiary-container));
}

.hh-project__body {
  min-width: 0;
}
.hh-project__name {
  margin: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.hh-project__slug {
  display: inline-block;
  margin-top: 2px;
  font-family: 'Roboto Mono', ui-monospace, monospace;
  font-size: 12px;
  color: rgba(var(--v-theme-on-surface), 0.6);
}
.hh-project__desc {
  margin: 6px 0 0;
  color: rgba(var(--v-theme-on-surface), 0.72);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.hh-project__chev {
  color: rgba(var(--v-theme-on-surface), 0.45);
  transition: transform var(--md-duration-short3) var(--md-easing-standard);
}
.hh-project:hover .hh-project__chev {
  transform: translateX(2px);
  color: rgb(var(--v-theme-primary));
}
</style>
