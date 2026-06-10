<script setup lang="ts">
import { computed, type Component } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useBoardStore } from '@/stores/board'
import { useProjectsStore } from '@/stores/projects'
import { PhListChecks, PhTag, PhUsers, PhGear } from '@phosphor-icons/vue'

const props = defineProps<{ slug: string }>()

const auth = useAuthStore()
const board = useBoardStore()
const projects = useProjectsStore()

const project = computed(
  () => projects.findBySlug(props.slug) ?? (board.project?.slug === props.slug ? board.project : null),
)

const isOwner = computed(
  () => !!project.value && !!auth.user && project.value.owner_id === auth.user.id,
)

interface NavItem {
  key: string
  label: string
  icon: Component
  to: RouteLocationRaw
}

const navItems = computed<NavItem[]>(() => {
  const slug = props.slug
  const items: NavItem[] = [
    { key: 'board', label: 'Задачи', icon: PhListChecks, to: { name: 'board', params: { slug } } },
    { key: 'types', label: 'Типы', icon: PhTag, to: { name: 'board_types', params: { slug } } },
    { key: 'members', label: 'Участники', icon: PhUsers, to: { name: 'board_members', params: { slug } } },
  ]

  if (isOwner.value) {
    items.push({
      key: 'settings',
      label: 'Настройки',
      icon: PhGear,
      to: { name: 'board_settings', params: { slug } },
    })
  }

  return items
})
</script>

<template>
  <nav class="ks-pnav" v-auto-animate>
    <div class="ks-pnav__head">
      <v-avatar size="40" color="primary-container">
        <v-img v-if="project?.avatar_url" :src="project.avatar_url" cover alt="" />
        <span v-else class="md-title-medium">
          {{ (project?.name || slug || '?').slice(0, 1).toUpperCase() }}
        </span>
      </v-avatar>
      <span class="ks-pnav__name md-label-medium">{{ project?.name || slug }}</span>
    </div>

    <v-divider class="ks-pnav__divider" />

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
.ks-pnav {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 12px 4px;
}
.ks-pnav__head {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 8px 0;
}
.ks-pnav__name {
  text-align: center;
  font-size: 11px;
  line-height: 1.1;
  letter-spacing: 0.5px;
  max-width: 80px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: rgb(var(--v-theme-on-surface-variant));
}
.ks-pnav__divider {
  width: 56px;
  margin: 4px 0 8px;
  opacity: 0.6;
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
