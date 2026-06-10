<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useProjectsStore } from '@/stores/projects'

const props = defineProps<{ token: string }>()

const router = useRouter()
const projects = useProjectsStore()

const error = ref<string | null>(null)

onMounted(async () => {
  try {
    const { slug } = await projects.acceptInvite(props.token)
    await router.replace({ name: 'board', params: { slug } })
  } catch (e: unknown) {
    const reason = (e as { reason?: string })?.reason
    error.value =
      reason === 'expired'
        ? 'Срок действия приглашения истёк'
        : reason === 'invalid_invite'
          ? 'Приглашение недействительно'
          : 'Не удалось принять приглашение'
  }
})
</script>

<template>
  <div class="ks-invite">
    <template v-if="error">
      <v-icon size="48" color="error" class="mb-4">mdi-link-variant-off</v-icon>
      <h1 class="md-headline-small mb-2">Приглашение недоступно</h1>
      <p class="md-body-medium text-medium-emphasis mb-6">{{ error }}</p>
      <v-btn color="primary" rounded="pill" :to="{ name: 'projects' }">К проектам</v-btn>
    </template>
    <template v-else>
      <v-progress-circular indeterminate color="primary" size="48" class="mb-4" />
      <p class="md-body-medium text-medium-emphasis">Принимаем приглашение…</p>
    </template>
  </div>
</template>

<style scoped>
.ks-invite {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  min-height: 60vh;
  padding: 24px;
}
</style>
