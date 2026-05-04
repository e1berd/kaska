<script setup lang="ts"></script>

<template>
  <v-container class="py-16 text-center">
    <h1 class="text-h2 mb-4">404</h1>
    <p class="text-body-large mb-8 text-medium-emphasis">Страница не найдена.</p>
    <v-btn color="primary" variant="flat" :to="{ name: 'home' }">На главную</v-btn>
  </v-container>
</template>
