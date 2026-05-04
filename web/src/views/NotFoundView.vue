<script setup lang="ts"></script>

<template>
  <div class="hh-404">
    <div class="hh-404__icon">
      <v-icon size="48">mdi-compass-off-outline</v-icon>
    </div>
    <div class="hh-404__code md-display-medium">404</div>
    <h1 class="md-headline-medium mt-2">Страница не найдена</h1>
    <p class="md-body-large text-medium-emphasis mt-2 mb-6">
      Возможно, она переехала или ссылка устарела.
    </p>
    <div class="hh-404__actions">
      <v-btn color="primary" variant="flat" rounded="pill" size="large" :to="{ name: 'home' }">
        На главную
      </v-btn>
      <v-btn variant="tonal" rounded="pill" size="large" :to="{ name: 'projects' }">
        К проектам
      </v-btn>
    </div>
  </div>
</template>

<style scoped>
.hh-404 {
  text-align: center;
  padding: 96px 24px;
  max-width: 640px;
  margin: 0 auto;
}
.hh-404__icon {
  width: 88px;
  height: 88px;
  margin: 0 auto;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.hh-404__code {
  margin-top: 24px;
  font-family: 'Roboto Flex', sans-serif;
  font-weight: 600;
  letter-spacing: -0.02em;
  color: rgb(var(--v-theme-primary));
}
.hh-404__actions {
  display: inline-flex;
  gap: 12px;
  flex-wrap: wrap;
  justify-content: center;
}
</style>
