import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5173,
    host: '0.0.0.0',
    strictPort: true,
    hmr: {
      clientPort: 5173,
      overlay: false,
    },
    warmup: {
      clientFiles: [
        './src/main.ts',
        './src/stores/socket.ts',
        './src/stores/auth.ts',
        './src/stores/projects.ts',
        './src/App.vue',
        './src/views/ProjectsView.vue',
      ],
    },
  },
})
