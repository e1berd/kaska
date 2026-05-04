import { createApp } from 'vue'
import { createPinia } from 'pinia'

import './styles/main.scss'

import App from './App.vue'
import router from './router'
import vuetify from './plugins/vuetify'
import { useAuthStore } from './stores/auth'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)
app.use(vuetify)

// Open the WebSocket — anonymous if no stored token, authed otherwise.
useAuthStore().bootstrap()

app.mount('#app')
