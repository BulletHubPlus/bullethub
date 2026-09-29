import { defineStore } from 'pinia'
import { reactive } from 'vue'
import type { Progress } from '@/api/types'

/**
 * Live progress overrides pushed by other devices on `user:<id>` (RF03). Pages
 * read `get(id, fallbackFromApi)`; nothing here ever seeks a running player.
 */
export const useProgressStore = defineStore('progress', () => {
  const live = reactive(new Map<string, Progress>())

  function set(mediaId: string, progress: Progress) {
    live.set(mediaId, progress)
  }

  function get(mediaId: string, fallback?: Progress | null): Progress | null {
    return live.get(mediaId) ?? fallback ?? null
  }

  return { set, get }
})
