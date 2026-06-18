<script setup lang="ts">
defineProps<{
  src: string | null
  alt?: string
}>()

const visible = defineModel<boolean>({ default: false })

function close() {
  visible.value = false
}
</script>

<template>
  <v-overlay
    v-model="visible"
    class="ks-lightbox"
    :scrim-opacity="0.85"
    scroll-strategy="block"
  >
    <div class="ks-lightbox__wrap" @click.self="close">
      <v-btn
        icon="mdi-close"
        variant="text"
        size="small"
        class="ks-lightbox__close"
        @click="close"
      />
      <img
        v-if="src"
        :src="src"
        :alt="alt || ''"
        class="ks-lightbox__img"
      />
    </div>
  </v-overlay>
</template>

<style scoped>
.ks-lightbox :deep(.v-overlay__content) {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100vw;
  height: 100dvh;
  overflow: hidden;
  margin: 0;
  padding: 48px;
}

.ks-lightbox__wrap {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
  position: relative;
}

.ks-lightbox__img {
  max-width: 100%;
  max-height: 100%;
  width: auto;
  height: auto;
  object-fit: contain;
  border-radius: var(--md-shape-m);
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
  user-select: none;
}

.ks-lightbox__close {
  position: absolute;
  top: 8px;
  right: 8px;
  z-index: 1;
  background: rgba(var(--v-theme-surface), 0.7) !important;
  color: rgb(var(--v-theme-on-surface)) !important;
}
</style>
