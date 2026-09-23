import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts", "functions/test/**/*.test.ts"],
    // Tüm dosyalar aynı emülatörü paylaşır.
    fileParallelism: false,
    testTimeout: 20000,
    hookTimeout: 30000,
  },
});
