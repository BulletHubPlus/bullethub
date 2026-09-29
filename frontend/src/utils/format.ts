export function formatDuration(seconds: number | null | undefined): string {
  if (!seconds) return ''
  const h = Math.floor(seconds / 3600)
  const m = Math.round((seconds % 3600) / 60)
  return h > 0 ? `${h}h ${m.toString().padStart(2, '0')}min` : `${m} min`
}

export const kindLabel: Record<string, string> = {
  series: 'Série',
  anime: 'Anime',
  movie: 'Filme',
  episode: 'Episódio',
}

export const seasonLabel = (_kind: 'series' | 'anime') => 'Temporada'
