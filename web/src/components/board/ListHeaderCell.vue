<script setup lang="ts">
import type { IconValue } from 'vuetify/lib/composables/icons.js'

defineProps<{
  columnKey: string
  title: string
  sortable?: boolean
  isSorted?: boolean
  sortIcon?: IconValue
}>()

defineEmits<{
  (e: 'sort'): void
}>()
</script>

<template>
  <div :data-column-key="columnKey" class="ks-list-header" @click.stop>
    <button
      type="button"
      class="ks-list-header__sort"
      :class="{ 'ks-list-header__sort--active': isSorted }"
      :disabled="!sortable"
      @click.stop="$emit('sort')"
    >
      <span class="ks-list-header__title">{{ title }}</span>
      <v-icon v-if="sortable && sortIcon" size="16">{{ sortIcon }}</v-icon>
    </button>
  </div>
</template>

<style scoped>
.ks-list-header {
  display: flex;
  align-items: center;
  width: 100%;
  min-width: 0;
  user-select: none;
}

.ks-list-header__sort {
  appearance: none;
  border: 0;
  background: transparent;
  color: inherit;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  min-width: 0;
  flex: 1;
  height: 44px;
  padding: 0 12px;
  font: inherit;
  text-align: left;
}

.ks-list-header__sort:disabled {
  cursor: default;
}

.ks-list-header__sort--active {
  color: rgb(var(--v-theme-on-surface));
}

.ks-list-header__title {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
