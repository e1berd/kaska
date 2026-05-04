<script setup lang="ts">
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
</script>

<template>
  <v-container class="py-12">
    <v-row justify="center">
      <v-col cols="12" md="8" lg="6">
        <h1 class="text-h3 mb-4">HardHat</h1>
        <p class="text-body-large mb-8 text-medium-emphasis">
          Открытый трекер задач. Любой может смотреть проекты и обсуждения. Создавать задачи могут
          только зарегистрированные пользователи.
        </p>

        <div class="d-flex ga-3 flex-wrap">
          <v-btn color="primary" variant="flat" :to="{ name: 'projects' }">К проектам</v-btn>
          <v-btn v-if="!auth.isAuthed" variant="tonal" :to="{ name: 'register' }">
            Создать аккаунт
          </v-btn>
          <v-btn v-if="!auth.isAuthed" variant="text" :to="{ name: 'login' }">Войти</v-btn>
          <v-btn v-else variant="tonal" :to="{ name: 'me' }">Мой профиль</v-btn>
        </div>
      </v-col>
    </v-row>
  </v-container>
</template>
