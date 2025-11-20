const { defineConfig } = require('vite');
const { join } = require('path');
const vue = require('@vitejs/plugin-vue');

module.exports = defineConfig({
  plugins: [vue()],
  server: {
    port: 3002,
  },
  build: {
    chunkSizeWarningLimit: 600, // 设置警告阈值为600KiB
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules')) {
            return id
              .toString()
              .split('node_modules/')[1]
              .split('/')[0]
              .toString();
          }
        },
      },
    },
  },
  resolve: {
    alias: [
      { find: '@', replacement: join(__dirname, 'src') },
      { find: /^vue3-video-play$/, replacement: 'vue3-video-play/dist/index.mjs' },
    ],
  },
});
