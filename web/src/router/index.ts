import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const routes: RouteRecordRaw[] = [
  { path: '/', name: 'home', component: () => import('@/views/HomeView.vue') },
  { path: '/projects', name: 'projects', component: () => import('@/views/ProjectsView.vue') },
  {
    path: '/p/:slug',
    name: 'board',
    component: () => import('@/views/BoardView.vue'),
    props: true,
    meta: { guest: true },
  },
  {
    path: '/p/:slug/types',
    name: 'board_types',
    component: () => import('@/views/TaskTypesView.vue'),
    props: true,
  },
  {
    path: '/p/:slug/members',
    name: 'board_members',
    component: () => import('@/views/ProjectMembersView.vue'),
    props: true,
  },
  {
    path: '/p/:slug/history',
    name: 'board_history',
    component: () => import('@/views/ProjectHistoryView.vue'),
    props: true,
  },
  {
    path: '/p/:slug/settings',
    name: 'board_settings',
    component: () => import('@/views/ProjectSettingsView.vue'),
    props: true,
  },
  {
    path: '/p/:slug/tasks/:taskId',
    name: 'task',
    component: () => import('@/views/TaskView.vue'),
    props: true,
    meta: { guest: true },
  },
  {
    path: '/invite/:token',
    name: 'invite',
    component: () => import('@/views/AcceptInviteView.vue'),
    props: true,
  },
  {
    path: '/login',
    name: 'login',
    component: () => import('@/views/LoginView.vue'),
    meta: { authScreen: true },
  },
  {
    path: '/register',
    name: 'register',
    component: () => import('@/views/RegisterView.vue'),
    meta: { authScreen: true },
  },
  {
    path: '/verify/:token',
    name: 'verify',
    component: () => import('@/views/VerifyView.vue'),
    props: true,
    meta: { authScreen: true },
  },
  {
    path: '/forgot',
    name: 'forgot',
    component: () => import('@/views/ForgotView.vue'),
    meta: { authScreen: true },
  },
  {
    path: '/reset/:token',
    name: 'reset',
    component: () => import('@/views/ResetView.vue'),
    props: true,
    meta: { authScreen: true },
  },
  {
    path: '/me',
    name: 'me',
    component: () => import('@/views/MeView.vue'),
  },
  {
    path: '/members',
    name: 'members',
    component: () => import('@/views/MembersView.vue'),
  },
  {
    path: '/clerks',
    name: 'clerks',
    component: () => import('@/views/ClerksView.vue'),
  },
  {
    path: '/settings',
    name: 'settings',
    component: () => import('@/views/SettingsView.vue'),
  },
  {
    path: '/:pathMatch(.*)*',
    name: 'not-found',
    component: () => import('@/views/NotFoundView.vue'),
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior() {
    return { top: 0 }
  },
})

router.beforeEach((to) => {
  const auth = useAuthStore()

  if (auth.isAuthed) {
    if (to.name === 'login' || to.name === 'register') {
      return { name: 'home' }
    }
    return
  }

  if (to.meta.authScreen === true || to.meta.guest === true) {
    return
  }

  return {
    name: 'login',
    query: to.fullPath === '/' ? {} : { next: to.fullPath },
  }
})

export default router
