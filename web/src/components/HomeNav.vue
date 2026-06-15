<script setup lang="ts">
import { computed, type Component } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { PhSquaresFour, PhGear, PhRobot } from '@phosphor-icons/vue'

const auth = useAuthStore()

interface NavItem {
  key: string
  label: string
  icon: Component
  to: RouteLocationRaw
}

const navItems = computed<NavItem[]>(() => {
  const items: NavItem[] = [
    {
      key: 'projects',
      label: 'Проекты',
      icon: PhSquaresFour,
      to: { name: 'projects' },
    },
  ]

  if (auth.isAuthed) {
    items.push({
      key: 'scouts',
      label: 'Скауты',
      icon: PhRobot,
      to: { name: 'scouts' },
    })
    items.push({
      key: 'settings',
      label: 'Настройки',
      icon: PhGear,
      to: { name: 'settings' },
    })
  }

  return items
})
</script>

<template>
  <nav class="ks-nav__list" v-auto-animate>
    <router-link
      v-for="item in navItems"
      :key="item.key"
      :to="item.to"
      class="ks-nav__item md-state-layer"
    >
      <span class="ks-nav__pill">
        <component :is="item.icon" :size="24" weight="regular" />
      </span>
      <span class="ks-nav__label md-label-medium">{{ item.label }}</span>
    </router-link>
  </nav>
</template>

<style scoped>
.ks-nav__list {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 12px 4px;
}
.ks-nav__item {
  --md-state-color: rgb(var(--v-theme-on-surface));
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  width: 72px;
  height: 64px;
  padding: 4px 0 6px;
  border-radius: var(--md-shape-l);
  text-decoration: none;
  color: rgb(var(--v-theme-on-surface));
}
.ks-nav__pill {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 56px;
  height: 32px;
  border-radius: var(--md-shape-full);
  transition: background-color var(--md-duration-short4) var(--md-easing-emphasized);
}
.ks-nav__item.router-link-exact-active .ks-nav__pill {
  background: rgb(var(--v-theme-secondary-container));
  color: rgb(var(--v-theme-on-secondary-container));
}
.ks-nav__label {
  text-align: center;
  font-size: 11px;
  line-height: 1.1;
  letter-spacing: 0.5px;
  white-space: nowrap;
  color: inherit;
  max-width: 80px;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
