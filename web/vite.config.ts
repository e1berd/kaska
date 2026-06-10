import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
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
