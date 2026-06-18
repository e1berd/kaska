<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useProjectsStore, type Project } from '@/stores/projects'
import { useAuthStore } from '@/stores/auth'
import { cssUrlImageOr } from '@/utils/css'

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

const editDialog = ref(false)
const editing = ref<Project | null>(null)
const editName = ref('')
const editDescription = ref('')
const editError = ref<string | null>(null)
const editSubmitting = ref(false)
const avatarUploading = ref(false)
const backgroundUploading = ref(false)
const deleteConfirm = ref(false)
const deleteSubmitting = ref(false)
const avatarInput = ref<HTMLInputElement | null>(null)
const backgroundInput = ref<HTMLInputElement | null>(null)

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

const editCoverStyle = computed(() =>
  editing.value?.background_url
    ? { backgroundImage: cssUrlImageOr(editing.value.background_url) }
    : null,
)

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

function openEdit(p: Project) {
  editing.value = p
  editName.value = p.name
  editDescription.value = p.description ?? ''
  editError.value = null
  editDialog.value = true
}

function closeEdit() {
  editDialog.value = false
  editing.value = null
}

async function submitEdit() {
  if (!editing.value) return
  editSubmitting.value = true
  editError.value = null
  try {
    await projects.updateProject({
      id: editing.value.id,
      name: editName.value.trim(),
      description: editDescription.value.trim(),
    })
    closeEdit()
  } catch (e) {
    const msg = e as { errors?: Record<string, string[]>; message?: string }
    if (msg.errors) {
      editError.value = Object.entries(msg.errors)
        .map(([k, v]) => `${k}: ${v.join(', ')}`)
        .join('; ')
    } else {
      editError.value = msg.message ?? 'не удалось обновить проект'
    }
  } finally {
    editSubmitting.value = false
  }
}

async function pickMedia(kind: 'avatar' | 'background') {
  const input = kind === 'avatar' ? avatarInput.value : backgroundInput.value
  input?.click()
}

async function onMediaPicked(kind: 'avatar' | 'background', e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file || !editing.value) return

  const flag = kind === 'avatar' ? avatarUploading : backgroundUploading
  flag.value = true
  editError.value = null
  try {
    const updated = await projects.uploadProjectMedia(kind, editing.value.id, file)
    editing.value = updated
  } catch (err) {
    editError.value = (err as { message?: string }).message ?? 'не удалось загрузить файл'
  } finally {
    flag.value = false
  }
}

async function clearMedia(kind: 'avatar' | 'background') {
  if (!editing.value) return
  const flag = kind === 'avatar' ? avatarUploading : backgroundUploading
  flag.value = true
  editError.value = null
  try {
    const updated = await projects.clearProjectMedia(kind, editing.value.id)
    editing.value = updated
  } catch (err) {
    editError.value = (err as { message?: string }).message ?? 'не удалось убрать файл'
  } finally {
    flag.value = false
  }
}

async function confirmDelete() {
  if (!editing.value) return
  deleteSubmitting.value = true
  editError.value = null
  try {
    await projects.deleteProject(editing.value.id)
    deleteConfirm.value = false
    closeEdit()
  } catch (err) {
    editError.value = (err as { message?: string }).message ?? 'не удалось удалить проект'
  } finally {
    deleteSubmitting.value = false
  }
}
</script>

<template>
  <div class="ks-projects">
    <header class="ks-projects__hero">
      <div class="ks-projects__intro">
        <span class="ks-projects__eyebrow md-label-large">Workspace</span>
        <h1 class="md-display-small">Проекты</h1>
        <p class="md-body-large text-medium-emphasis mt-2 mb-0">
          Выберите проект, чтобы перейти к доске задач, или создайте новый.
        </p>
        <p v-if="!auth.isAuthed" class="md-body-medium text-medium-emphasis mt-3 mb-0">
          Войдите, чтобы видеть свои проекты и создавать новые.
        </p>
      </div>
      <div class="ks-projects__panel">
        <div class="ks-projects__meta">
          <div class="ks-projects__meta-item">
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
          class="ks-projects__filter"
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

    <div v-if="loading" class="ks-projects__grid">
      <div v-for="i in 6" :key="i" class="ks-project-skeleton">
        <div class="ks-project-skeleton__head">
          <div class="ks-skeleton ks-project-skeleton__avatar" />
          <div class="ks-project-skeleton__title">
            <div class="ks-skeleton ks-project-skeleton__name" />
            <div class="ks-skeleton ks-project-skeleton__slug" />
          </div>
        </div>
        <div class="ks-skeleton ks-project-skeleton__desc" />
        <div class="ks-skeleton ks-project-skeleton__desc ks-project-skeleton__desc--short" />
      </div>
    </div>

    <div v-else-if="projects.list.length === 0" class="ks-projects__empty">
      <div class="ks-projects__empty-icon">
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
      class="ks-projects__empty ks-projects__empty--soft"
    >
      <div class="ks-projects__empty-icon">
        <v-icon size="36">mdi-magnify</v-icon>
      </div>
      <h2 class="md-title-medium mt-4">Ничего не найдено</h2>
      <p class="md-body-medium text-medium-emphasis mt-1">
        Попробуйте другой запрос или очистите поиск.
      </p>
    </div>

    <div v-else class="ks-projects__grid">
      <router-link
        v-for="p in filtered"
        :key="p.id"
        :to="{ name: 'board', params: { slug: p.slug } }"
        class="ks-project md-state-layer"
      >
        <v-btn
          v-if="auth.isAuthed"
          icon="mdi-pencil-outline"
          size="x-small"
          variant="text"
          density="comfortable"
          rounded="pill"
          class="ks-project__edit"
          aria-label="Редактировать проект"
          @click.stop.prevent="openEdit(p)"
        />
        <div class="ks-project__head">
          <v-avatar
            :color="p.avatar_url ? undefined : accent(p.id)"
            size="48"
            rounded="lg"
            class="ks-project__badge"
          >
            <v-img v-if="p.avatar_url" :src="p.avatar_url" cover alt="" />
            <span v-else class="text-white md-title-medium">
              {{ p.name.slice(0, 1).toUpperCase() }}
            </span>
          </v-avatar>
          <div class="ks-project__title">
            <span class="md-title-medium">{{ p.name }}</span>
            <code class="ks-project__slug md-label-medium">/{{ p.slug }}</code>
          </div>
        </div>
        <p v-if="p.description" class="ks-project__desc md-body-medium">
          {{ p.description }}
        </p>
        <div class="ks-project__cta">
          <span class="md-label-large">Открыть</span>
          <v-icon size="18">mdi-arrow-right</v-icon>
        </div>
      </router-link>
    </div>

    <input
      ref="avatarInput"
      type="file"
      accept="image/*"
      hidden
      @change="onMediaPicked('avatar', $event)"
    />
    <input
      ref="backgroundInput"
      type="file"
      accept="image/*"
      hidden
      @change="onMediaPicked('background', $event)"
    />

    <v-dialog v-model="editDialog" max-width="640" @after-leave="editing = null">
      <v-card v-if="editing" rounded="xl">
        <div
          class="ks-edit__cover"
          :style="editCoverStyle"
        >
          <div class="ks-edit__cover-actions">
            <v-btn
              size="small"
              variant="flat"
              color="surface"
              prepend-icon="mdi-image-edit-outline"
              :loading="backgroundUploading"
              @click="pickMedia('background')"
            >
              {{ editing.background_url ? 'Заменить фон' : 'Загрузить фон' }}
            </v-btn>
            <v-btn
              v-if="editing.background_url"
              size="small"
              variant="text"
              color="surface"
              icon="mdi-close"
              :loading="backgroundUploading"
              @click="clearMedia('background')"
            />
          </div>
          <div class="ks-edit__avatar-wrap">
            <v-avatar
              :color="editing.avatar_url ? undefined : accent(editing.id)"
              size="80"
              rounded="lg"
              class="ks-edit__avatar"
            >
              <v-img v-if="editing.avatar_url" :src="editing.avatar_url" cover alt="" />
              <span v-else class="text-white md-headline-small">
                {{ editing.name.slice(0, 1).toUpperCase() }}
              </span>
            </v-avatar>
            <div class="ks-edit__avatar-buttons">
              <v-btn
                size="x-small"
                variant="flat"
                color="surface"
                icon="mdi-camera-outline"
                :loading="avatarUploading"
                aria-label="Загрузить аватар"
                @click="pickMedia('avatar')"
              />
              <v-btn
                v-if="editing.avatar_url"
                size="x-small"
                variant="flat"
                color="surface"
                icon="mdi-close"
                :loading="avatarUploading"
                aria-label="Убрать аватар"
                @click="clearMedia('avatar')"
              />
            </div>
          </div>
        </div>
        <v-card-title class="md-headline-small px-6 pt-6">
          Редактирование проекта
        </v-card-title>
        <v-card-text class="px-6 pt-2">
          <v-text-field
            v-model="editName"
            label="название"
            variant="filled"
            density="comfortable"
          />
          <v-textarea
            v-model="editDescription"
            label="описание"
            hint="оставьте пустым, чтобы убрать"
            persistent-hint
            variant="filled"
            rows="3"
            density="comfortable"
            class="mt-3"
          />
          <v-alert v-if="editError" type="error" variant="tonal" class="mt-4" rounded="lg">
            {{ editError }}
          </v-alert>
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-btn
            color="error"
            variant="text"
            rounded="pill"
            :disabled="editSubmitting || deleteSubmitting"
            @click="deleteConfirm = true"
          >
            Удалить проект
          </v-btn>
          <v-spacer />
          <v-btn
            variant="text"
            rounded="pill"
            :disabled="editSubmitting"
            @click="closeEdit"
          >
            Отмена
          </v-btn>
          <v-btn
            color="primary"
            variant="flat"
            rounded="pill"
            :loading="editSubmitting"
            @click="submitEdit"
          >
            Сохранить
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="deleteConfirm" max-width="420" persistent>
      <v-card rounded="xl">
        <v-card-title class="md-headline-small px-6 pt-6">Удалить проект?</v-card-title>
        <v-card-text class="px-6 pt-2 md-body-medium">
          Действие необратимо. Все колонки, задачи и комментарии будут удалены.
        </v-card-text>
        <v-card-actions class="px-6 pb-6">
          <v-spacer />
          <v-btn
            variant="text"
            rounded="pill"
            :disabled="deleteSubmitting"
            @click="deleteConfirm = false"
          >
            Отмена
          </v-btn>
          <v-btn
            color="error"
            variant="flat"
            rounded="pill"
            :loading="deleteSubmitting"
            @click="confirmDelete"
          >
            Удалить
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

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
.ks-projects {
  max-width: 1320px;
  margin: 0 auto;
  padding: 36px 24px 80px;
}
.ks-projects__hero {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(320px, 0.8fr);
  align-items: stretch;
  gap: 20px;
  margin-bottom: 32px;
}
.ks-projects__intro {
  padding: 28px 32px;
  border-radius: var(--md-shape-xl);
  background:
    radial-gradient(circle at 20% 15%, rgba(var(--v-theme-primary), 0.14), transparent 58%),
    rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.55);
}
.ks-projects__intro h1 {
  letter-spacing: -0.02em;
  margin-bottom: 0;
}
.ks-projects__eyebrow {
  display: inline-block;
  text-transform: uppercase;
  color: rgb(var(--v-theme-primary));
  letter-spacing: 0.08em;
  margin-bottom: 10px;
}
.ks-projects__panel {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 20px;
  border-radius: var(--md-shape-xl);
  background: rgb(var(--v-theme-surface-container));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.6);
}
.ks-projects__meta {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}
.ks-projects__meta-item {
  border-radius: var(--md-shape-l);
  background: rgba(var(--v-theme-primary), 0.08);
  border: 1px solid rgba(var(--v-theme-primary), 0.2);
  padding: 12px;
}
.ks-projects__meta-item strong {
  display: block;
  margin-top: 4px;
}
.ks-projects__actions {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.ks-projects__filter {
  min-width: 0;
  width: 100%;
}

@media (max-width: 1024px) {
  .ks-projects__hero {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 680px) {
  .ks-projects {
    padding: 24px 16px 64px;
  }
  .ks-projects__intro {
    padding: 20px;
  }
  .ks-projects__intro h1 {
    font-size: var(--md-type-headline-medium);
    line-height: 36px;
  }
  .ks-projects__panel {
    padding: 14px;
  }
  .ks-projects__meta {
    grid-template-columns: 1fr 1fr;
  }
  .ks-projects__actions {
    width: 100%;
  }
  .ks-projects__filter {
    min-width: 0;
    width: 100%;
  }
}
.ks-projects__filter :deep(.v-field) {
  background: rgb(var(--v-theme-surface-container));
}

.ks-projects__empty {
  text-align: center;
  padding: 96px 24px;
  border-radius: var(--md-shape-xl);
  background: rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
}
.ks-projects__empty--soft {
  padding: 56px 24px;
}
.ks-projects__empty-icon {
  width: 80px;
  height: 80px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.ks-projects__grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 18px;
}

.ks-project {
  --md-state-color: rgb(var(--v-theme-primary));
  position: relative;
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
.ks-project__edit {
  position: absolute;
  top: 8px;
  right: 8px;
  z-index: 2;
  opacity: 0;
  transition: opacity var(--md-duration-short3) var(--md-easing-standard);
}
.ks-project:hover .ks-project__edit,
.ks-project:focus-within .ks-project__edit {
  opacity: 1;
}
.ks-project:hover {
  transform: translateY(-2px);
  box-shadow: var(--md-elev-2);
  border-color: rgba(var(--v-theme-primary), 0.4);
}
.ks-project:focus-visible {
  outline: none;
  border-color: rgb(var(--v-theme-primary));
}

.ks-project__head {
  display: flex;
  align-items: center;
  gap: 14px;
}
.ks-project__badge {
  flex-shrink: 0;
}
.ks-project__title {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.ks-project__title > span:first-child {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.ks-project__slug {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  color: rgba(var(--v-theme-on-surface), 0.55);
}

.ks-project__desc {
  color: rgba(var(--v-theme-on-surface), 0.78);
  display: -webkit-box;
  -webkit-line-clamp: 3;
  -webkit-box-orient: vertical;
  overflow: hidden;
  margin: 0;
  flex: 1;
}

.ks-project__cta {
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
.ks-project:hover .ks-project__cta,
.ks-project:focus-visible .ks-project__cta {
  opacity: 1;
  transform: translateX(0);
}

@keyframes ks-shimmer {
  from { background-position: -400px 0; }
  to   { background-position:  400px 0; }
}

.ks-skeleton {
  border-radius: var(--md-shape-s);
  background:
    linear-gradient(
      90deg,
      rgb(var(--v-theme-surface-container)) 25%,
      rgb(var(--v-theme-surface-container-high)) 50%,
      rgb(var(--v-theme-surface-container)) 75%
    );
  background-size: 800px 100%;
  animation: ks-shimmer 1.4s ease-in-out infinite;
}

.ks-project-skeleton {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 20px;
  background: rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
  border-radius: var(--md-shape-l);
}

.ks-project-skeleton__head {
  display: flex;
  align-items: center;
  gap: 14px;
}

.ks-project-skeleton__avatar {
  width: 48px;
  height: 48px;
  border-radius: var(--md-shape-s);
  flex-shrink: 0;
}

.ks-project-skeleton__title {
  display: flex;
  flex-direction: column;
  gap: 8px;
  flex: 1;
  min-width: 0;
}

.ks-project-skeleton__name {
  height: 16px;
  width: 60%;
}

.ks-project-skeleton__slug {
  height: 11px;
  width: 40%;
}

.ks-project-skeleton__desc {
  height: 14px;
  width: 100%;
}

.ks-project-skeleton__desc--short {
  width: 70%;
}

.ks-edit__cover {
  position: relative;
  height: 160px;
  margin-bottom: 40px;
  background:
    linear-gradient(
      135deg,
      rgb(var(--v-theme-primary-container)),
      rgb(var(--v-theme-tertiary-container))
    );
  background-size: cover;
  background-position: center;
  border-top-left-radius: var(--md-shape-xl);
  border-top-right-radius: var(--md-shape-xl);
}
.ks-edit__cover::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(180deg, transparent 0%, rgba(0, 0, 0, 0.35) 100%);
  pointer-events: none;
}
.ks-edit__cover-actions {
  position: absolute;
  top: 12px;
  right: 12px;
  display: inline-flex;
  gap: 6px;
  z-index: 2;
}
.ks-edit__avatar-wrap {
  position: absolute;
  left: 24px;
  bottom: -32px;
  display: inline-flex;
  align-items: flex-end;
  gap: 8px;
  z-index: 2;
}
.ks-edit__avatar {
  border: 4px solid rgb(var(--v-theme-surface));
  box-shadow: var(--md-elev-2);
}
.ks-edit__avatar-buttons {
  display: inline-flex;
  flex-direction: column;
  gap: 4px;
}
</style>
