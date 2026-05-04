<script setup lang="ts">
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
</script>

<template>
  <div class="hh-home">
    <section class="hh-hero">
      <div class="hh-hero__content">
        <span class="hh-hero__eyebrow md-label-large">Открытый трекер задач</span>
        <h1 class="hh-hero__title">
          Прозрачный канбан, доступный всем.
        </h1>
        <p class="hh-hero__lede md-body-large">
          Любой посетитель видит проекты, доски и обсуждения. Учётная запись нужна
          только чтобы создавать и менять задачи.
        </p>

        <div class="hh-hero__actions">
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
            v-if="!auth.isAuthed"
            variant="tonal"
            size="large"
            rounded="pill"
            :to="{ name: 'register' }"
          >
            Создать аккаунт
          </v-btn>
          <v-btn
            v-if="!auth.isAuthed"
            variant="text"
            size="large"
            rounded="pill"
            :to="{ name: 'login' }"
          >
            Войти
          </v-btn>
          <v-btn
            v-else
            variant="tonal"
            size="large"
            rounded="pill"
            :to="{ name: 'me' }"
          >
            Профиль
          </v-btn>
        </div>
      </div>

      <div class="hh-hero__art" aria-hidden="true">
        <div class="hh-hero__chip hh-hero__chip--a">
          <v-icon size="18" class="mr-1">mdi-format-list-bulleted</v-icon>
          Todo
        </div>
        <div class="hh-hero__chip hh-hero__chip--b">
          <v-icon size="18" class="mr-1">mdi-progress-clock</v-icon>
          In Progress
        </div>
        <div class="hh-hero__chip hh-hero__chip--c">
          <v-icon size="18" class="mr-1">mdi-check-circle-outline</v-icon>
          Done
        </div>
      </div>
    </section>

    <section class="hh-features">
      <article class="hh-feature">
        <div class="hh-feature__icon">
          <v-icon size="24">mdi-eye-outline</v-icon>
        </div>
        <h3 class="md-title-medium">Публичное чтение</h3>
        <p class="md-body-medium text-medium-emphasis">
          Гости видят проекты и карточки без регистрации. Никаких приватных стен
          вокруг открытой работы.
        </p>
      </article>
      <article class="hh-feature">
        <div class="hh-feature__icon">
          <v-icon size="24">mdi-flash-outline</v-icon>
        </div>
        <h3 class="md-title-medium">Realtime DnD</h3>
        <p class="md-body-medium text-medium-emphasis">
          Перетаскивание карточек синхронизируется у всех на доске мгновенно — даже
          у анонимных наблюдателей.
        </p>
      </article>
      <article class="hh-feature">
        <div class="hh-feature__icon">
          <v-icon size="24">mdi-shield-key-outline</v-icon>
        </div>
        <h3 class="md-title-medium">Запись только для своих</h3>
        <p class="md-body-medium text-medium-emphasis">
          Создавать и менять карточки могут только авторизованные пользователи —
          через защищённые WebSocket-каналы.
        </p>
      </article>
    </section>
  </div>
</template>

<style scoped>
.hh-home {
  max-width: 1120px;
  margin: 0 auto;
  padding: 48px 32px 80px;
}

.hh-hero {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr);
  gap: 64px;
  align-items: center;
  padding: 32px 0 64px;
}
@media (max-width: 880px) {
  .hh-hero {
    grid-template-columns: 1fr;
    gap: 32px;
  }
}

.hh-hero__eyebrow {
  display: inline-block;
  text-transform: uppercase;
  color: rgb(var(--v-theme-primary));
  letter-spacing: 0.08em;
  margin-bottom: 16px;
}

.hh-hero__title {
  font-family: 'Roboto Flex', sans-serif;
  font-size: clamp(40px, 6vw, 64px);
  line-height: 1.05;
  font-weight: 500;
  letter-spacing: -0.02em;
  margin: 0 0 20px;
  color: rgb(var(--v-theme-on-surface));
}

.hh-hero__lede {
  color: rgba(var(--v-theme-on-surface), 0.72);
  margin: 0 0 32px;
  max-width: 56ch;
}

.hh-hero__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}

.hh-hero__art {
  position: relative;
  height: 320px;
}
.hh-hero__chip {
  position: absolute;
  display: inline-flex;
  align-items: center;
  padding: 10px 16px;
  border-radius: var(--md-shape-full);
  font-weight: 500;
  font-size: 14px;
  box-shadow: var(--md-elev-2);
  white-space: nowrap;
}
.hh-hero__chip--a {
  top: 24px;
  left: 8%;
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
  transform: rotate(-4deg);
}
.hh-hero__chip--b {
  top: 130px;
  right: 14%;
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
  transform: rotate(2deg);
}
.hh-hero__chip--c {
  top: 240px;
  left: 22%;
  background: rgb(var(--v-theme-tertiary-container));
  color: rgb(var(--v-theme-on-tertiary-container));
  transform: rotate(-2deg);
}

.hh-features {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
  margin-top: 16px;
}
@media (max-width: 880px) {
  .hh-features {
    grid-template-columns: 1fr;
  }
}

.hh-feature {
  background: rgb(var(--v-theme-surface-container-low));
  border-radius: var(--md-shape-l);
  padding: 24px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  transition: background-color var(--md-duration-short3) var(--md-easing-standard);
}
.hh-feature:hover {
  background: rgb(var(--v-theme-surface-container));
}
.hh-feature__icon {
  width: 44px;
  height: 44px;
  border-radius: var(--md-shape-m);
  background: rgb(var(--v-theme-primary-container));
  color: rgb(var(--v-theme-on-primary-container));
  display: inline-flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 8px;
}
.hh-feature h3 {
  margin: 0;
  color: rgb(var(--v-theme-on-surface));
}
.hh-feature p {
  margin: 0;
}
</style>
