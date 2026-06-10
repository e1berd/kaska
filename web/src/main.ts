import { createApp } from 'vue'
import { createPinia } from 'pinia'

import '@/styles/main.scss'
import '@/styles/tailwind.css'

import App from '@/App.vue'
import router from '@/router'
import vuetify from '@/plugins/vuetify'
import { useAuthStore } from '@/stores/auth'
import { autoAnimatePlugin } from '@formkit/auto-animate/vue'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
.use(router)
.use(vuetify).use(autoAnimatePlugin)

// Open the WebSocket — anonymous if no stored token, authed otherwise.
useAuthStore().bootstrap()

app.mount('#app')
