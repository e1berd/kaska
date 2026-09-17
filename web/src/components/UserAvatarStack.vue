<script setup lang="ts">
import { computed } from 'vue'
import UserAvatar, { type AvatarUser } from '@/components/UserAvatar.vue'

const props = withDefaults(
  defineProps<{
    users: (AvatarUser & { id: string })[]
    size?: number
    maxVisible?: number
    tooltipPrefix?: string
  }>(),
  { size: 24, maxVisible: 3, tooltipPrefix: '' },
)

const visibleUsers = computed(() => props.users.slice(0, props.maxVisible))
const hiddenUsers = computed(() => props.users.slice(props.maxVisible))
const hiddenNames = computed(() =>
  hiddenUsers.value.map((user) => user.display_name || user.email).join(', '),
)
const overlap = computed(() => `-${Math.round(props.size * 0.3)}px`)

function tooltipFor(user: AvatarUser) {
  const name = user.display_name || user.email || '?'
  return props.tooltipPrefix ? `${props.tooltipPrefix}: ${name}` : name
}
</script>

<template>
  <div v-if="users.length" class="ks-avatar-stack" :style="{ '--ks-avatar-overlap': overlap }">
    <UserAvatar
      v-for="user in visibleUsers"
      :key="user.id"
      :user="user"
      :size="size"
      :tooltip="tooltipFor(user)"
      class="ks-avatar-stack__item"
    />
    <v-tooltip v-if="hiddenUsers.length" :text="hiddenNames" location="bottom">
      <template #activator="{ props: tipProps }">
        <v-avatar
          v-bind="tipProps"
          :size="size"
          color="secondary-container"
          class="ks-avatar-stack__item ks-avatar-stack__more md-label-small"
        >
          +{{ hiddenUsers.length }}
        </v-avatar>
      </template>
    </v-tooltip>
  </div>
</template>

<style scoped>
.ks-avatar-stack {
  display: inline-flex;
  align-items: center;
}
.ks-avatar-stack__item {
  box-shadow: 0 0 0 2px var(--ks-avatar-ring, rgb(var(--v-theme-surface)));
}
.ks-avatar-stack__item + .ks-avatar-stack__item {
  margin-left: var(--ks-avatar-overlap);
}
.ks-avatar-stack__more {
  color: rgb(var(--v-theme-on-secondary-container));
}
</style>
