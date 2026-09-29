export interface User {
  id: string
  email: string
  name: string
  role: 'subscriber' | 'support' | 'editor' | 'owner'
  confirmed: boolean
}

export interface Device {
  id: string
  name: string
  user_agent: string | null
  last_seen_at: string | null
  created_at: string
  current: boolean
}

export interface SessionResponse {
  access_token: string
  expires_in: number
  device_id: string
  user: User
}

/** Stable error envelope from the backend (PRD §10.4). */
export interface ErrorEnvelope {
  error: { code: string; message: string; details: Record<string, unknown> }
}

export type CollectionKind = 'series' | 'anime'
export type MediaKind = 'movie' | 'episode'

export interface Genre {
  slug: string
  name: string
}

export interface TitleMetadata {
  original_title?: string | null
  release_year?: number | null
  age_rating?: string | null
  genres?: Genre[]
  poster_url?: string | null
  backdrop_url?: string | null
}

export interface CatalogCard extends TitleMetadata {
  type: 'collection' | 'movie' | 'progress'
  id: string
  subtitle?: string | null
  position?: number
  kind: CollectionKind | MediaKind
  slug?: string
  title: string
  description: string | null
  thumbnail_url: string | null
  duration_seconds?: number | null
}

export interface CatalogRow {
  id: string
  title: string
  items: CatalogCard[]
}

export interface HomeResponse {
  continue_watching: CatalogCard[]
  my_list: CatalogCard[]
  rows: CatalogRow[]
}

export interface MediaItem {
  id: string
  kind: MediaKind
  position: number | null
  title: string
  synopsis: string | null
  thumbnail_url: string | null
  duration_seconds: number | null
  intro_end_seconds: number | null
  progress?: Progress | null
}

export interface TitleDetails extends TitleMetadata {
  cast: string[]
  creators: string[]
  in_my_list: boolean
}

export interface SearchResponse {
  query: string
  genre: Genre | null
  results: CatalogCard[]
}

export interface CollectionResponse {
  collection: TitleDetails & {
    id: string
    kind: CollectionKind
    slug: string
    title: string
    description: string | null
    thumbnail_url: string | null
  }
  seasons: { id: string; number: number; title: string | null; media: MediaItem[] }[]
}

export interface Progress {
  position: number
  completed: boolean
}

export interface PlayingMedia {
  id: string
  kind: MediaKind
  title: string
  position: number | null
  season_number: number | null
  collection: { title: string; slug: string } | null
  duration_seconds: number | null
  intro_end_seconds: number | null
  thumbnail_url: string | null
}

export interface PlaybackSession {
  session_id: string
  code: string
  expires: number
  source: { engine: string; url: string }
  watermark: { text: string }
  resume_position: number
  captions: { id: string; srclang: string; label: string }[]
  media: PlayingMedia
  next_media: PlayingMedia | null
}

export interface ActiveSession {
  id: string
  device_name: string | null
  media_title: string | null
  started_at: string
}

export interface Subscription {
  status: 'trialing' | 'active' | 'past_due' | 'canceled'
  current_period_end: string
  plan: { slug: string; name: string; max_streams: number }
}
