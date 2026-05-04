<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
const router = useRouter()

onMounted(() => {
  auth.fetchMe().catch(() => {
    /* token may be expired — handle later via refresh */
  })
})

function logout() {
  auth.logout()
  router.push({ name: 'home' })
}
</script>

<template>
  <v-container class="py-12">
    <v-row justify="center">
      <v-col cols="12" sm="8" md="6">
        <v-card class="pa-6" elevation="2">
          <h2 class="text-h5 mb-6">Профиль</h2>

          <div v-if="auth.user">
            <v-list lines="one" class="bg-transparent">
              <v-list-item>
                <template #prepend>
                  <v-icon>mdi-email-outline</v-icon>
                </template>
                <v-list-item-title>{{ auth.user.email }}</v-list-item-title>
                <v-list-item-subtitle>Email</v-list-item-subtitle>
              </v-list-item>
              <v-list-item>
                <template #prepend>
                  <v-icon>mdi-shield-account-outline</v-icon>
                </template>
                <v-list-item-title>{{ auth.user.role }}</v-list-item-title>
                <v-list-item-subtitle>Роль</v-list-item-subtitle>
              </v-list-item>
              <v-list-item v-if="auth.user.confirmed_at">
                <template #prepend>
                  <v-icon color="primary">mdi-check-decagram</v-icon>
                </template>
                <v-list-item-title>Почта подтверждена</v-list-item-title>
                <v-list-item-subtitle>{{ auth.user.confirmed_at }}</v-list-item-subtitle>
              </v-list-item>
            </v-list>

            <v-divider class="my-4" />

            <v-btn variant="tonal" color="error" @click="logout">Выйти</v-btn>
          </div>
        </v-card>
      </v-col>
    </v-row>
  </v-container>
</template>
