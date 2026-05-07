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
const loading = ref(true)

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
  projects.joinLobby()
    .catch((e) => { console.warn('[projects] join failed', e) })
    .finally(() => { loading.value = false })
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

function accent(id: string): 'primary' | 'secondary' | 'tertiary' {
  const sum = [...id].reduce((s, c) => s + c.charCodeAt(0), 0)
  return (['primary', 'secondary', 'tertiary'] as const)[sum % 3]
}
</script>

<template>
  <div class="hh-projects">
    <header class="hh-projects__hero">
      <div class="hh-projects__intro">
        <span class="hh-projects__eyebrow md-label-large">Workspace</span>
        <h1 class="md-display-small">Проекты</h1>
        <p class="md-body-large text-medium-emphasis mt-2 mb-0">
          Выберите проект, чтобы перейти к доске задач, или создайте новый.
        </p>
        <p v-if="!auth.isAuthed" class="md-body-medium text-medium-emphasis mt-3 mb-0">
          Войдите, чтобы создавать проекты. Просматривать можно без аккаунта.
        </p>
      </div>
      <div class="hh-projects__panel">
        <div class="hh-projects__meta">
          <div class="hh-projects__meta-item">
            <span class="md-label-medium text-medium-emphasis">Всего проектов</span>
            <strong class="md-headline-small">{{ projects.list.length }}</strong>
          </div>
        </div>
        <v-text-field
          v-model="filter"
          variant="solo-filled"
          flat
          rounded="pill"
          hide-details
          density="comfortable"
          prepend-inner-icon="mdi-magnify"
          placeholder="Поиск"
          clearable
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

    <div v-if="loading" class="hh-projects__grid">
      <div v-for="i in 6" :key="i" class="hh-project-skeleton">
        <div class="hh-project-skeleton__head">
          <div class="hh-skeleton hh-project-skeleton__avatar" />
          <div class="hh-project-skeleton__title">
            <div class="hh-skeleton hh-project-skeleton__name" />
            <div class="hh-skeleton hh-project-skeleton__slug" />
          </div>
        </div>
        <div class="hh-skeleton hh-project-skeleton__desc" />
        <div class="hh-skeleton hh-project-skeleton__desc hh-project-skeleton__desc--short" />
      </div>
    </div>

    <div v-else-if="projects.list.length === 0" class="hh-projects__empty">
      <div class="hh-projects__empty-icon">
        <v-icon size="40">mdi-folder-open-outline</v-icon>
      </div>
      <h2 class="md-title-large mt-4">Пока ни одного проекта</h2>
      <p class="md-body-medium text-medium-emphasis mt-1 mb-4">
        {{
          auth.isAuthed
            ? 'Создайте первый — это займёт пару секунд.'
            : 'Зайдите под аккаунтом, чтобы создать первый проект.'
        }}
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

    <div
      v-else-if="filtered.length === 0"
      class="hh-projects__empty hh-projects__empty--soft"
    >
      <div class="hh-projects__empty-icon">
        <v-icon size="36">mdi-magnify</v-icon>
      </div>
      <h2 class="md-title-medium mt-4">Ничего не найдено</h2>
      <p class="md-body-medium text-medium-emphasis mt-1">
        Попробуйте другой запрос или очистите поиск.
      </p>
    </div>

    <div v-else class="hh-projects__grid">
      <router-link
        v-for="p in filtered"
        :key="p.id"
        :to="{ name: 'board', params: { slug: p.slug } }"
        class="hh-project md-state-layer"
      >
        <div class="hh-project__head">
          <v-avatar
            :color="accent(p.id)"
            size="48"
            rounded="lg"
            class="hh-project__badge"
          >
            <span class="text-white md-title-medium">
              {{ p.name.slice(0, 1).toUpperCase() }}
            </span>
          </v-avatar>
          <div class="hh-project__title">
            <span class="md-title-medium">{{ p.name }}</span>
            <code class="hh-project__slug md-label-medium">/{{ p.slug }}</code>
          </div>
        </div>
        <p v-if="p.description" class="hh-project__desc md-body-medium">
          {{ p.description }}
        </p>
        <div class="hh-project__cta">
          <span class="md-label-large">Открыть</span>
          <v-icon size="18">mdi-arrow-right</v-icon>
        </div>
      </router-link>
    </div>

    <v-dialog v-model="dialog" max-width="560">
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
  max-width: 1320px;
  margin: 0 auto;
  padding: 36px 24px 80px;
}
.hh-projects__hero {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(320px, 0.8fr);
  align-items: stretch;
  gap: 20px;
  margin-bottom: 32px;
}
.hh-projects__intro {
  padding: 28px 32px;
  border-radius: var(--md-shape-xl);
  background:
    radial-gradient(circle at 20% 15%, rgba(var(--v-theme-primary), 0.14), transparent 58%),
    rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.55);
}
.hh-projects__intro h1 {
  letter-spacing: -0.02em;
  margin-bottom: 0;
}
.hh-projects__eyebrow {
  display: inline-block;
  text-transform: uppercase;
  color: rgb(var(--v-theme-primary));
  letter-spacing: 0.08em;
  margin-bottom: 10px;
}
.hh-projects__panel {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 20px;
  border-radius: var(--md-shape-xl);
  background: rgb(var(--v-theme-surface-container));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.6);
}
.hh-projects__meta {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}
.hh-projects__meta-item {
  border-radius: var(--md-shape-l);
  background: rgba(var(--v-theme-primary), 0.08);
  border: 1px solid rgba(var(--v-theme-primary), 0.2);
  padding: 12px;
}
.hh-projects__meta-item strong {
  display: block;
  margin-top: 4px;
}
.hh-projects__actions {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.hh-projects__filter {
  min-width: 0;
  width: 100%;
}

@media (max-width: 1024px) {
  .hh-projects__hero {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 680px) {
  .hh-projects {
    padding: 24px 16px 64px;
  }
  .hh-projects__intro {
    padding: 20px;
  }
  .hh-projects__intro h1 {
    font-size: var(--md-type-headline-medium);
    line-height: 36px;
  }
  .hh-projects__panel {
    padding: 14px;
  }
  .hh-projects__meta {
    grid-template-columns: 1fr 1fr;
  }
  .hh-projects__actions {
    width: 100%;
  }
  .hh-projects__filter {
    min-width: 0;
    width: 100%;
  }
}
.hh-projects__filter :deep(.v-field) {
  background: rgb(var(--v-theme-surface-container)) !important;
}

.hh-projects__empty {
  text-align: center;
  padding: 96px 24px;
  border-radius: var(--md-shape-xl);
  background: rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
}
.hh-projects__empty--soft {
  padding: 56px 24px;
}
.hh-projects__empty-icon {
  width: 80px;
  height: 80px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.hh-projects__grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 18px;
}

/* M3 filled card with primary state-layer overlay on hover/focus. */
.hh-project {
  --md-state-color: rgb(var(--v-theme-primary));
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 20px;
  text-decoration: none;
  color: rgb(var(--v-theme-on-surface));
  background: rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
  border-radius: var(--md-shape-l);
  transition:
    transform var(--md-duration-short4) var(--md-easing-emphasized),
    box-shadow var(--md-duration-short4) var(--md-easing-emphasized),
    border-color var(--md-duration-short4) var(--md-easing-emphasized);
}
.hh-project:hover {
  transform: translateY(-2px);
  box-shadow: var(--md-elev-2);
  border-color: rgba(var(--v-theme-primary), 0.4);
}
.hh-project:focus-visible {
  outline: none;
  border-color: rgb(var(--v-theme-primary));
}

.hh-project__head {
  display: flex;
  align-items: center;
  gap: 14px;
}
.hh-project__badge {
  flex-shrink: 0;
}
.hh-project__title {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.hh-project__title > span:first-child {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.hh-project__slug {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  color: rgba(var(--v-theme-on-surface), 0.55);
}

.hh-project__desc {
  color: rgba(var(--v-theme-on-surface), 0.78);
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
  margin: 0;
  flex: 1;
}

.hh-project__cta {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: rgb(var(--v-theme-primary));
  margin-top: auto;
  opacity: 0;
  transform: translateX(-4px);
  transition:
    opacity var(--md-duration-short4) var(--md-easing-emphasized),
    transform var(--md-duration-short4) var(--md-easing-emphasized);
}
.hh-project:hover .hh-project__cta,
.hh-project:focus-visible .hh-project__cta {
  opacity: 1;
  transform: translateX(0);
}

@keyframes hh-shimmer {
  from { background-position: -400px 0; }
  to   { background-position:  400px 0; }
}

.hh-skeleton {
  border-radius: var(--md-shape-s);
  background:
    linear-gradient(
      90deg,
      rgb(var(--v-theme-surface-container)) 25%,
      rgb(var(--v-theme-surface-container-high)) 50%,
      rgb(var(--v-theme-surface-container)) 75%
    );
  background-size: 800px 100%;
  animation: hh-shimmer 1.4s ease-in-out infinite;
}

.hh-project-skeleton {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 20px;
  background: rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
  border-radius: var(--md-shape-l);
}

.hh-project-skeleton__head {
  display: flex;
  align-items: center;
  gap: 14px;
}

.hh-project-skeleton__avatar {
  width: 48px;
  height: 48px;
  border-radius: var(--md-shape-s);
  flex-shrink: 0;
}

.hh-project-skeleton__title {
  display: flex;
  flex-direction: column;
  gap: 8px;
  flex: 1;
  min-width: 0;
}

.hh-project-skeleton__name {
  height: 16px;
  width: 60%;
}

.hh-project-skeleton__slug {
  height: 11px;
  width: 40%;
}

.hh-project-skeleton__desc {
  height: 14px;
  width: 100%;
}

.hh-project-skeleton__desc--short {
  width: 70%;
}
</style>
