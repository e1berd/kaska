<script setup lang="ts">
import { computed } from 'vue'
import type { User } from '@/stores/auth'

const props = withDefaults(
  defineProps<{
    users: User[]
    label: string
    size?: 'sm' | 'md'
    maxVisible?: number
  }>(),
  {
    size: 'md',
    maxVisible: 6,
  },
)

const visibleUsers = computed(() => props.users.slice(0, props.maxVisible))
const hiddenCount = computed(() => Math.max(0, props.users.length - visibleUsers.value.length))
const avatarSize = computed(() => (props.size === 'sm' ? 22 : 26))
</script>

<template>
  <div v-if="users.length" class="ks-presence" :class="`ks-presence--${size}`">
    <span class="ks-presence__label md-label-small">{{ label }}</span>
    <div class="ks-presence__rail">
      <v-tooltip
        v-for="user in visibleUsers"
        :key="user.id"
        :text="user.display_name || user.email"
        location="bottom"
      >
        <template #activator="{ props: tipProps }">
          <span v-bind="tipProps" class="ks-presence__item">
            <v-avatar :size="avatarSize" color="primary" class="ks-presence__avatar">
              <img
                v-if="user.avatar_url"
                :src="user.avatar_url"
                alt=""
                width="22"
                height="22"
              />
              <span v-else>{{ (user.display_name || user.email || '?').slice(0, 1).toUpperCase() }}</span>
            </v-avatar>
          </span>
        </template>
      </v-tooltip>
      <span v-if="hiddenCount > 0" class="ks-presence__more">+{{ hiddenCount }}</span>
    </div>
  </div>
</template>

<style scoped>
.ks-presence {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 4px 10px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-surface-container));
  border: 1px solid rgba(var(--v-theme-outline), 0.24);
}
.ks-presence__label {
  color: rgba(var(--v-theme-on-surface), 0.72);
  white-space: nowrap;
}
.ks-presence__rail {
  display: inline-flex;
  align-items: center;
}
.ks-presence__item {
  display: inline-flex;
}
.ks-presence__avatar {
  margin-left: -7px;
  border: 2px solid rgb(var(--v-theme-surface-container));
  box-shadow: var(--md-elev-1);
}
.ks-presence__item:first-child .ks-presence__avatar {
  margin-left: 0;
}
.ks-presence__more {
  margin-left: 6px;
  font-size: 11px;
  font-weight: 600;
  color: rgba(var(--v-theme-on-surface), 0.74);
}
.ks-presence--sm {
  padding: 3px 8px;
  gap: 6px;
}
</style>
