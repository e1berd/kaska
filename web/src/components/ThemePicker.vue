<script setup lang="ts">
import { onMounted, watch } from 'vue'
import { useThemeStore } from '@/stores/theme'
import { cssColorOr } from '@/utils/css'

const props = defineProps<{
  modelValue: string | null
  allowNull?: boolean
  nullLabel?: string
}>()

const emit = defineEmits<{ (e: 'update:modelValue', value: string | null): void }>()

const theme = useThemeStore()

function swatchStyle(color: string | null | undefined) {
  return { background: cssColorOr(color, 'transparent') }
}

function ensureAll() {
  for (const t of theme.themesIndex) void theme.ensurePalette(t.slug).catch(() => {})
}

onMounted(() => {
  void theme.loadIndex().catch(() => {})
  ensureAll()
})

watch(() => theme.themesIndex, ensureAll, { deep: true })
</script>

<template>
  <div class="ks-themes">
    <button
      v-if="allowNull"
      type="button"
      class="ks-theme ks-theme--null md-state-layer"
      :class="{ 'ks-theme--active': props.modelValue === null }"
      @click="emit('update:modelValue', null)"
    >
      <span class="ks-theme__name md-label-large">{{ nullLabel || 'По умолчанию' }}</span>
    </button>
    <button
      v-for="t in theme.themesIndex"
      :key="t.slug"
      type="button"
      class="ks-theme md-state-layer"
      :class="{ 'ks-theme--active': props.modelValue === t.slug }"
      @click="emit('update:modelValue', t.slug)"
    >
      <span class="ks-theme__swatch" :style="swatchStyle(theme.palettes[t.slug]?.palette_light?.primary)" />
      <span
        class="ks-theme__swatch"
        :style="swatchStyle(theme.palettes[t.slug]?.palette_light?.['secondary-container'])"
      />
      <span class="ks-theme__swatch" :style="swatchStyle(theme.palettes[t.slug]?.palette_light?.tertiary)" />
      <span class="ks-theme__name md-label-large">{{ t.name }}</span>
    </button>
  </div>
</template>

<style scoped>
.ks-themes {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(180px, 100%), 1fr));
  gap: 10px;
}
.ks-theme {
  --md-state-color: rgb(var(--v-theme-primary));
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  border-radius: var(--md-shape-l);
  border: 1px solid rgba(var(--v-theme-outline-variant), 0.6);
  background: rgb(var(--v-theme-surface-container-low));
  color: rgb(var(--v-theme-on-surface));
  cursor: pointer;
  transition:
    border-color var(--md-duration-short3) var(--md-easing-standard),
    background-color var(--md-duration-short3) var(--md-easing-standard);
}
.ks-theme:hover {
  border-color: rgb(var(--v-theme-primary));
}
.ks-theme--active {
  border-color: rgb(var(--v-theme-primary));
  background: rgba(var(--v-theme-primary), 0.08);
}
.ks-theme--null {
  justify-content: center;
}
.ks-theme__swatch {
  width: 18px;
  height: 18px;
  border-radius: var(--md-shape-full);
  flex-shrink: 0;
  box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.12);
}
.ks-theme__name {
  flex: 1;
  text-align: left;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
