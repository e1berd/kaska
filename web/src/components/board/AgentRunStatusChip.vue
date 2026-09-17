<script setup lang="ts">
import { computed } from 'vue'
import type { AgentRunStatus } from '@/stores/board'
import { RUN_STATUS } from '@/utils/agents'

const props = defineProps<{
  status: AgentRunStatus
  size?: 'x-small' | 'small' | 'default'
  label?: string
}>()

const meta = computed(() => RUN_STATUS[props.status])
const active = computed(() => props.status === 'running')
</script>

<template>
  <v-chip
    :color="meta.color"
    variant="flat"
    :size="size ?? 'default'"
    rounded="sm"
    class="ks-run-chip"
  >
    <span v-if="active" class="ks-run-chip__dot" />
    <v-progress-circular
      v-else-if="status === 'pending'"
      indeterminate
      size="14"
      width="2"
      color="primary"
      class="mr-2"
    />
    <v-icon v-else start :icon="meta.icon" />
    {{ label ?? meta.label }}
  </v-chip>
</template>

<style scoped>
.ks-run-chip__dot {
  width: 8px;
  height: 8px;
  margin-right: 8px;
  border-radius: var(--md-shape-full);
  background: rgb(var(--v-theme-primary));
  box-shadow: 0 0 0 4px rgba(var(--v-theme-primary), 0.18);
  animation: ks-run-pulse var(--md-duration-extra-long4) var(--md-easing-standard) infinite alternate;
}

@keyframes ks-run-pulse {
  from {
    box-shadow: 0 0 0 1px rgba(var(--v-theme-primary), 0.24);
  }
  to {
    box-shadow: 0 0 0 5px rgba(var(--v-theme-primary), 0.08);
  }
}

@media (prefers-reduced-motion: reduce) {
  .ks-run-chip__dot {
    animation: none;
  }
}
</style>
