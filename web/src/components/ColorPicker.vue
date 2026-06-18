<script setup lang="ts">
import { computed } from 'vue'
import { cssColorOr } from '@/utils/css'

const props = withDefaults(
  defineProps<{
    modelValue: string
    label?: string
    presets?: string[]
  }>(),
  {
    label: 'Цвет',
    presets: () => [
      '#EADDFF',
      '#D0E4FF',
      '#D7E3C0',
      '#FFD8E4',
      '#FCE1A8',
      '#D8E2DC',
      '#E7E0EC',
      '#DDE3EA',
      '#EBD8C3',
      '#CDE7E2',
      '#F4D8D8',
      '#B3261E',
      '#6750A4',
      '#006A6A',
      '#7D5260',
      '#625B71',
    ],
  },
)

const emit = defineEmits<{
  (e: 'update:modelValue', value: string): void
}>()

const normalized = computed({
  get: () => props.modelValue,
  set: (value: string) => emit('update:modelValue', value.trim()),
})

function colorStyle(color: string) {
  return { background: cssColorOr(color, '#E0E0E0') }
}
</script>

<template>
  <div class="ks-color-picker">
    <div class="md-label-large mb-2">{{ label }}</div>
    <div class="ks-color-picker__presets">
      <button
        v-for="color in presets"
        :key="color"
        type="button"
        class="ks-color-picker__item"
        :class="{ 'is-active': normalized.toLowerCase() === color.toLowerCase() }"
        :style="colorStyle(color)"
        @click="normalized = color"
      />
    </div>
    <div class="ks-color-picker__custom">
      <input v-model="normalized" type="color" class="ks-color-picker__input" />
      <v-text-field
        v-model="normalized"
        label="HEX"
        variant="filled"
        density="compact"
        hide-details
        class="ks-color-picker__hex"
      />
    </div>
  </div>
</template>

<style scoped>
.ks-color-picker {
  display: grid;
  gap: 10px;
}
.ks-color-picker__presets {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.ks-color-picker__item {
  width: 34px;
  height: 34px;
  border-radius: var(--md-shape-full);
  border: 2px solid rgba(var(--v-theme-outline), 0.32);
  cursor: pointer;
  transition:
    border-color var(--md-duration-short3) var(--md-easing-standard),
    transform var(--md-duration-short3) var(--md-easing-standard);
}
.ks-color-picker__item.is-active {
  border-color: rgb(var(--v-theme-primary));
  transform: scale(1.08);
}
.ks-color-picker__custom {
  display: flex;
  align-items: center;
  gap: 12px;
}
.ks-color-picker__input {
  width: 44px;
  height: 44px;
  border: 0;
  padding: 0;
  background: transparent;
}
.ks-color-picker__hex {
  max-width: 160px;
}
</style>
