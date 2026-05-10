<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useProjectsStore, type Project } from '@/stores/projects'
import { usePinnedProjectsStore } from '@/stores/pinnedProjects'

const auth = useAuthStore()
const projects = useProjectsStore()
const pinned = usePinnedProjectsStore()

const loading = ref(true)

onMounted(() => {
  projects
    .joinLobby()
    .catch((e) => {
      console.warn('[home] projects lobby join failed', e)
    })
    .finally(() => {
      loading.value = false
    })
})

const greeting = computed(() => {
  const h = new Date().getHours()
  if (h < 5) return 'Доброй ночи'
  if (h < 12) return 'Доброе утро'
  if (h < 18) return 'Добрый день'
  return 'Добрый вечер'
})

const displayedName = computed(() => {
  const u = auth.user
  if (!u) return null
  return u.display_name?.trim() || u.email?.split('@')[0] || null
})

const avatarUrl = computed(() => auth.user?.avatar_url ?? null)
const initial = computed(() => (displayedName.value ?? '?').slice(0, 1).toUpperCase())

const projectCount = computed(() => projects.list.length)

const pinnedProject = computed<Project | null>(() => {
  const first = pinned.list[0]
  if (!first) return null
  return projects.list.find((p) => p.id === first.id) ?? null
})

function ts(p: Project): number {
  return Date.parse(p.updated_at ?? p.inserted_at ?? '') || 0
}

const recent = computed(() => {
  return [...projects.list].sort((a, b) => ts(b) - ts(a)).slice(0, 6)
})

function accent(id: string): 'primary' | 'secondary' | 'tertiary' {
  const sum = [...id].reduce((s, c) => s + c.charCodeAt(0), 0)
  return (['primary', 'secondary', 'tertiary'] as const)[sum % 3]
}

function relTime(iso?: string): string {
  if (!iso) return ''
  const t = Date.parse(iso)
  if (!Number.isFinite(t)) return ''
  const diff = (Date.now() - t) / 1000
  if (diff < 60) return 'только что'
  if (diff < 3600) return `${Math.floor(diff / 60)} мин назад`
  if (diff < 86400) return `${Math.floor(diff / 3600)} ч назад`
  if (diff < 86400 * 7) return `${Math.floor(diff / 86400)} дн назад`
  if (diff < 86400 * 30) return `${Math.floor(diff / (86400 * 7))} нед назад`
  return new Date(t).toLocaleDateString('ru-RU', { day: 'numeric', month: 'short' })
}
</script>

<template>
  <div class="ks-home">
    <header class="ks-greet">
      <div class="ks-greet__main">
        <span class="ks-greet__eyebrow md-label-large">Главная</span>
        <h1 class="ks-greet__title">
          <template v-if="displayedName">
            {{ greeting }}, <span class="ks-greet__name">{{ displayedName }}</span>
          </template>
          <template v-else>
            {{ greeting }}
          </template>
        </h1>
        <p class="md-body-large ks-greet__lede">
          <template v-if="auth.isAuthed">
            Вернитесь к работе или начните новый проект.
          </template>
          <template v-else>
            Просматривать проекты и доски можно без аккаунта. Чтобы создавать
            и менять задачи — войдите или зарегистрируйтесь.
          </template>
        </p>

        <div class="ks-greet__actions">
          <v-btn
            color="primary"
            variant="flat"
            size="large"
            rounded="pill"
            :to="{ name: 'projects' }"
            prepend-icon="mdi-view-dashboard-outline"
          >
            К проектам
          </v-btn>
          <v-btn
            v-if="auth.isAuthed"
            variant="tonal"
            size="large"
            rounded="pill"
            :to="{ name: 'projects' }"
            prepend-icon="mdi-plus"
          >
            Новый проект
          </v-btn>
          <template v-else>
            <v-btn
              variant="tonal"
              size="large"
              rounded="pill"
              :to="{ name: 'register' }"
            >
              Создать аккаунт
            </v-btn>
            <v-btn
              variant="text"
              size="large"
              rounded="pill"
              :to="{ name: 'login' }"
            >
              Войти
            </v-btn>
          </template>
        </div>
      </div>

      <aside v-if="auth.isAuthed" class="ks-greet__user">
        <router-link :to="{ name: 'me' }" class="ks-greet__user-link md-state-layer">
          <v-avatar
            :color="avatarUrl ? undefined : 'primary'"
            size="56"
            class="ks-greet__avatar"
          >
            <v-img v-if="avatarUrl" :src="avatarUrl" cover alt="" />
            <span v-else class="md-headline-small text-white">{{ initial }}</span>
          </v-avatar>
          <div class="ks-greet__user-meta">
            <strong class="md-title-medium">{{ displayedName }}</strong>
            <span class="md-label-medium text-medium-emphasis">{{ auth.user?.email }}</span>
          </div>
          <v-icon class="ks-greet__user-arrow" size="20">mdi-arrow-right</v-icon>
        </router-link>
      </aside>
    </header>


    <section v-if="pinnedProject" class="ks-section">
      <header class="ks-section__head">
        <h2 class="md-title-large ks-section__title">
          <v-icon size="20" class="mr-2">mdi-pin</v-icon>
          Закреплённый проект
        </h2>
      </header>
      <router-link
        :to="{ name: 'board', params: { slug: pinnedProject.slug } }"
        class="ks-pin md-state-layer"
      >
        <v-avatar
          :color="pinnedProject.avatar_url ? undefined : accent(pinnedProject.id)"
          size="64"
          rounded="lg"
          class="ks-pin__avatar"
        >
          <v-img
            v-if="pinnedProject.avatar_url"
            :src="pinnedProject.avatar_url"
            cover
            alt=""
          />
          <span v-else class="text-white md-headline-small">
            {{ pinnedProject.name.slice(0, 1).toUpperCase() }}
          </span>
        </v-avatar>
        <div class="ks-pin__body">
          <div class="ks-pin__title">
            <span class="md-title-large">{{ pinnedProject.name }}</span>
            <code class="ks-pin__slug md-label-medium">/{{ pinnedProject.slug }}</code>
          </div>
          <p
            v-if="pinnedProject.description"
            class="ks-pin__desc md-body-medium text-medium-emphasis"
          >
            {{ pinnedProject.description }}
          </p>
          <span class="ks-pin__cta md-label-large">
            Продолжить
            <v-icon size="16">mdi-arrow-right</v-icon>
          </span>
        </div>
      </router-link>
    </section>

    <section class="ks-section">
      <header class="ks-section__head">
        <h2 class="md-title-large ks-section__title">
          <v-icon size="20" class="mr-2">mdi-history</v-icon>
          Недавние проекты
        </h2>
        <router-link :to="{ name: 'projects' }" class="ks-section__more md-label-large">
          Все проекты
          <v-icon size="16">mdi-arrow-right</v-icon>
        </router-link>
      </header>

      <div v-if="loading" class="ks-grid">
        <div v-for="i in 3" :key="i" class="ks-card ks-card--skeleton">
          <div class="ks-skeleton ks-skeleton--avatar" />
          <div class="ks-card__title">
            <div class="ks-skeleton ks-skeleton--line ks-skeleton--w60" />
            <div class="ks-skeleton ks-skeleton--line ks-skeleton--w40" />
          </div>
        </div>
      </div>

      <div v-else-if="recent.length === 0" class="ks-empty">
        <div class="ks-empty__icon">
          <v-icon size="32">mdi-folder-open-outline</v-icon>
        </div>
        <h3 class="md-title-medium mt-3">Здесь пока пусто</h3>
        <p class="md-body-medium text-medium-emphasis mt-1 mb-4">
          {{ auth.isAuthed
            ? 'Создайте первый проект, чтобы начать работу.'
            : 'Войдите, чтобы создать проект.' }}
        </p>
        <v-btn
          v-if="auth.isAuthed"
          color="primary"
          variant="flat"
          rounded="pill"
          prepend-icon="mdi-plus"
          :to="{ name: 'projects' }"
        >
          К проектам
        </v-btn>
        <v-btn
          v-else
          color="primary"
          variant="flat"
          rounded="pill"
          :to="{ name: 'login' }"
        >
          Войти
        </v-btn>
      </div>

      <div v-else class="ks-grid">
        <router-link
          v-for="p in recent"
          :key="p.id"
          :to="{ name: 'board', params: { slug: p.slug } }"
          class="ks-card md-state-layer"
        >
          <v-avatar
            :color="p.avatar_url ? undefined : accent(p.id)"
            size="44"
            rounded="lg"
          >
            <v-img v-if="p.avatar_url" :src="p.avatar_url" cover alt="" />
            <span v-else class="text-white md-title-medium">
              {{ p.name.slice(0, 1).toUpperCase() }}
            </span>
          </v-avatar>
          <div class="ks-card__title">
            <span class="md-title-medium">{{ p.name }}</span>
            <span class="ks-card__meta md-label-medium">
              {{ relTime(p.updated_at ?? p.inserted_at) || `/${p.slug}` }}
            </span>
          </div>
          <v-icon size="18" class="ks-card__arrow">mdi-arrow-right</v-icon>
        </router-link>
      </div>
    </section>
  </div>
</template>

<style scoped>
.ks-home {
  max-width: 1200px;
  margin: 0 auto;
  padding: 32px 24px 80px;
  display: grid;
  gap: 28px;
}

.ks-greet {
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(0, 0.8fr);
  gap: 20px;
  align-items: stretch;
}
@media (max-width: 1100px) {
  .ks-greet {
    grid-template-columns: 1fr;
  }
}

.ks-greet__main {
  padding: 32px;
  border-radius: var(--md-shape-xl);
  background:
    radial-gradient(circle at 12% 18%, rgba(var(--v-theme-primary), 0.16), transparent 60%),
    radial-gradient(circle at 88% 92%, rgba(var(--v-theme-tertiary), 0.12), transparent 55%),
    rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.55);
}

.ks-greet__eyebrow {
  display: inline-block;
  text-transform: uppercase;
  color: rgb(var(--v-theme-primary));
  letter-spacing: 0.08em;
  margin-bottom: 12px;
}

.ks-greet__title {
  font-family: 'Roboto Flex', sans-serif;
  font-size: clamp(28px, 4.4vw, 44px);
  line-height: 1.1;
  letter-spacing: -0.02em;
  font-weight: 500;
  margin: 0 0 12px;
  color: rgb(var(--v-theme-on-surface));
}
.ks-greet__name {
  color: rgb(var(--v-theme-primary));
}

.ks-greet__lede {
  margin: 0 0 24px;
  color: rgba(var(--v-theme-on-surface), 0.72);
  max-width: 60ch;
}

.ks-greet__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.ks-greet__user {
  min-width: 0;
  border-radius: var(--md-shape-xl);
  background: rgb(var(--v-theme-surface-container));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.6);
  padding: 12px;
  display: flex;
  align-items: stretch;
}
.ks-greet__user-link {
  --md-state-color: rgb(var(--v-theme-primary));
  flex: 1;
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 12px 14px;
  border-radius: var(--md-shape-l);
  text-decoration: none;
  color: rgb(var(--v-theme-on-surface));
  position: relative;
  transition: background-color var(--md-duration-short3) var(--md-easing-standard);
}
.ks-greet__avatar {
  flex-shrink: 0;
}
.ks-greet__user-meta {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
  flex: 1;
}
.ks-greet__user-meta strong,
.ks-greet__user-meta span {
  display: block;
  min-width: 0;
  max-width: 100%;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.ks-greet__user-arrow {
  flex-shrink: 0;
}
.ks-greet__user-arrow {
  color: rgba(var(--v-theme-on-surface), 0.55);
  transition: transform var(--md-duration-short4) var(--md-easing-emphasized);
}
.ks-greet__user-link:hover .ks-greet__user-arrow {
  transform: translateX(2px);
  color: rgb(var(--v-theme-primary));
}


.ks-section {
  display: grid;
  gap: 14px;
}
.ks-section__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}
.ks-section__title {
  display: inline-flex;
  align-items: center;
  margin: 0;
  color: rgb(var(--v-theme-on-surface));
}
.ks-section__more {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  text-decoration: none;
  color: rgb(var(--v-theme-primary));
  padding: 6px 12px;
  border-radius: var(--md-shape-full);
  transition: background-color var(--md-duration-short3) var(--md-easing-standard);
}
.ks-section__more:hover {
  background: rgba(var(--v-theme-primary), 0.08);
}

.ks-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 14px;
}

.ks-pin {
  --md-state-color: rgb(var(--v-theme-primary));
  position: relative;
  display: flex;
  gap: 20px;
  align-items: flex-start;
  padding: 24px;
  text-decoration: none;
  color: rgb(var(--v-theme-on-surface));
  background:
    radial-gradient(circle at 90% 10%, rgba(var(--v-theme-primary), 0.10), transparent 55%),
    rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
  border-radius: var(--md-shape-l);
  transition:
    transform var(--md-duration-short4) var(--md-easing-emphasized),
    box-shadow var(--md-duration-short4) var(--md-easing-emphasized),
    border-color var(--md-duration-short4) var(--md-easing-emphasized);
}
.ks-pin:hover {
  transform: translateY(-2px);
  box-shadow: var(--md-elev-2);
  border-color: rgba(var(--v-theme-primary), 0.4);
}
.ks-pin:focus-visible {
  outline: none;
  border-color: rgb(var(--v-theme-primary));
}
.ks-pin__avatar {
  flex-shrink: 0;
}
.ks-pin__body {
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-width: 0;
  flex: 1;
}
.ks-pin__title {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 4px 12px;
  min-width: 0;
}
.ks-pin__title > span:first-child {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ks-pin__slug {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.ks-pin__desc {
  margin: 0;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.ks-pin__cta {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-top: 4px;
  color: rgb(var(--v-theme-primary));
  transition: transform var(--md-duration-short4) var(--md-easing-emphasized);
}
.ks-pin:hover .ks-pin__cta {
  transform: translateX(2px);
}

.ks-card {
  --md-state-color: rgb(var(--v-theme-primary));
  position: relative;
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 16px 18px;
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
.ks-card:hover {
  transform: translateY(-2px);
  box-shadow: var(--md-elev-2);
  border-color: rgba(var(--v-theme-primary), 0.4);
}
.ks-card:focus-visible {
  outline: none;
  border-color: rgb(var(--v-theme-primary));
}
.ks-card__title {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
  flex: 1;
}
.ks-card__title > span:first-child {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.ks-card__slug {
  font-family: 'Roboto Mono', ui-monospace, monospace;
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.ks-card__meta {
  color: rgba(var(--v-theme-on-surface), 0.55);
}
.ks-card__arrow {
  color: rgba(var(--v-theme-on-surface), 0.4);
  transition:
    transform var(--md-duration-short4) var(--md-easing-emphasized),
    color var(--md-duration-short4) var(--md-easing-emphasized);
}
.ks-card:hover .ks-card__arrow {
  transform: translateX(2px);
  color: rgb(var(--v-theme-primary));
}

.ks-empty {
  text-align: center;
  padding: 56px 24px;
  border-radius: var(--md-shape-l);
  background: rgb(var(--v-theme-surface-container-low));
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.5);
}
.ks-empty__icon {
  width: 64px;
  height: 64px;
  margin: 0 auto;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

@keyframes ks-shimmer {
  from { background-position: -400px 0; }
  to   { background-position:  400px 0; }
}
.ks-skeleton {
  background:
    linear-gradient(
      90deg,
      rgb(var(--v-theme-surface-container)) 25%,
      rgb(var(--v-theme-surface-container-high)) 50%,
      rgb(var(--v-theme-surface-container)) 75%
    );
  background-size: 800px 100%;
  animation: ks-shimmer 1.4s ease-in-out infinite;
  border-radius: var(--md-shape-s);
}
.ks-skeleton--avatar {
  width: 44px;
  height: 44px;
  border-radius: var(--md-shape-m);
  flex-shrink: 0;
}
.ks-skeleton--line {
  height: 12px;
}
.ks-skeleton--w60 { width: 60%; }
.ks-skeleton--w40 { width: 40%; }
.ks-card--skeleton {
  pointer-events: none;
}
.ks-card--skeleton .ks-card__title {
  gap: 8px;
}

@media (max-width: 680px) {
  .ks-home {
    padding: 24px 16px 64px;
    gap: 20px;
  }
  .ks-greet__main {
    padding: 24px 20px;
  }
}
</style>
