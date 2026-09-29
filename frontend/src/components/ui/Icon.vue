<script setup lang="ts">
// Small inline SVG set (no icon dependency). Stroke follows currentColor.
const paths: Record<string, string> = {
  user: 'M20 21a8 8 0 0 0-16 0 M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8',
  devices: 'M3 5h11a1 1 0 0 1 1 1v9H2V6a1 1 0 0 1 1-1Z M18 9h3a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1h-3a1 1 0 0 1-1-1v-8a1 1 0 0 1 1-1Z M2 19h10',
  logout: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4 M16 17l5-5-5-5 M21 12H9',
  chevron: 'M6 9l6 6 6-6',
  shield: 'M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z',
  download: 'M12 3v12 M7 10l5 5 5-5 M5 21h14',
  search: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16Z M21 21l-4.3-4.3',
  home: 'M3 10.5 12 3l9 7.5 M5 9v11h14V9',
  menu: 'M3 6h18 M3 12h18 M3 18h18',
  close: 'M6 6l12 12 M18 6l-12 12',
  film: 'M3 4h18v16H3Z M7 4v16 M17 4v16 M3 9h4 M17 9h4 M3 15h4 M17 15h4',
  tv: 'M3 5h18v12H3Z M8 21h8 M12 17v4',
  spark: 'M12 3v4 M12 17v4 M3 12h4 M17 12h4 M6 6l2.5 2.5 M15.5 15.5 18 18 M18 6l-2.5 2.5 M8.5 15.5 6 18',
  list: 'M8 6h13 M8 12h13 M8 18h13 M3 6h.01 M3 12h.01 M3 18h.01',
}
defineProps<{ name: keyof typeof paths | string; size?: number }>()
</script>

<template>
  <svg
    :width="size ?? 16"
    :height="size ?? 16"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.7"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <path v-for="(d, i) in paths[name].split(' M')" :key="i" :d="i === 0 ? d : 'M' + d" />
  </svg>
</template>
