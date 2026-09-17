<script setup lang="ts">
import { computed } from 'vue'

export type AvatarUser = {
  display_name?: string | null
  email?: string | null
  avatar_url?: string | null
}

defineOptions({ inheritAttrs: false })

const props = withDefaults(
  defineProps<{
    user: AvatarUser
    size?: number
    tooltip?: string
  }>(),
  { size: 24, tooltip: undefined },
)

const name = computed(() => props.user.display_name || props.user.email || '?')
const initial = computed(() => name.value.slice(0, 1).toUpperCase())
const initialFontSize = computed(() => `${Math.round(props.size * 0.45)}px`)
</script>

<template>
  <v-tooltip :text="tooltip ?? name" location="bottom" :disabled="tooltip === ''">
    <template #activator="{ props: tipProps }">
      <v-avatar v-bind="{ ...tipProps, ...$attrs }" :size="size" color="primary" class="ks-user-avatar">
        <v-img v-if="user.avatar_url" :src="user.avatar_url" cover :alt="name" />
        <span v-else class="ks-user-avatar__initial" :style="{ fontSize: initialFontSize }">{{ initial }}</span>
      </v-avatar>
    </template>
  </v-tooltip>
</template>

<style scoped>
.ks-user-avatar__initial {
  font-weight: 500;
  color: rgb(var(--v-theme-on-primary));
}
</style>
