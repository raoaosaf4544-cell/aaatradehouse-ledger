import { useSyncExternalStore } from 'react'

/**
 * Offline support for reading. The last answer to each read is remembered in this browser, per signed-in
 * login, and shown read-only when there is no signal. Never used for saving, never for logged-out
 * users: the cache has an owner (the signed-in auth user id) and is wiped on sign-out.
 */
const PREFIX = 'ledger-cache:'
/** Everything this login remembers lives under ONE storage key, capped in entries and size. */
export const MAX_ENTRIES = 60
export const MAX_CHARS = 1_500_000 // phone browsers allow ~5 MB per site; stay far below it
let owner: string | null = null
let usingCache = false
const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())

type Entry = { t: number; s: string } // t = last written (order), s = the value as JSON text
let store: Record<string, Entry> | null = null // in-memory copy of this owner's storage key
let clock = 0

const storeKey = () => `${PREFIX}v3:${owner}`

/** Old copies (v1/v2 one-key-per-read, other logins) are deleted as soon as a login is known. */
export function setCacheOwner(authUserId: string | null) {
  owner = authUserId
  store = null
  if (!owner) return
  try {
    for (const k of Object.keys(localStorage)) if (k.startsWith(PREFIX) && k !== storeKey()) localStorage.removeItem(k)
  } catch {
    // storage unavailable: nothing to tidy
  }
}

export function clearOfflineCache() {
  try {
    for (const k of Object.keys(localStorage)) if (k.startsWith(PREFIX)) localStorage.removeItem(k)
  } catch {
    // storage unavailable: nothing was cached
  }
  owner = null
  store = null
  markUsingCache(false)
}

// Maps are stored as tagged entry lists (plain JSON turns a Map into {}).
const MAP_TAG = '__map__'
const toJson = (_: string, v: unknown) => (v instanceof Map ? { [MAP_TAG]: [...v] } : v)
const fromJson = (_: string, v: unknown) =>
  v && typeof v === 'object' && MAP_TAG in v ? new Map((v as Record<string, [unknown, unknown][]>)[MAP_TAG]) : v

function load(): Record<string, Entry> {
  if (store) return store
  try {
    const raw = localStorage.getItem(storeKey())
    store = raw ? (JSON.parse(raw) as Record<string, Entry>) : {}
  } catch {
    store = {}
  }
  for (const e of Object.values(store)) clock = Math.max(clock, e.t)
  return store
}

/** Drop the oldest entries until the cache fits both caps. */
function prune(s: Record<string, Entry>) {
  const names = Object.keys(s).sort((a, b) => s[a].t - s[b].t)
  let chars = names.reduce((n, k) => n + k.length + s[k].s.length, 0)
  while (names.length > 0 && (names.length > MAX_ENTRIES || chars > MAX_CHARS)) {
    const k = names.shift()!
    chars -= k.length + s[k].s.length
    delete s[k]
  }
}

function persist(s: Record<string, Entry>) {
  try {
    localStorage.setItem(storeKey(), JSON.stringify(s))
  } catch {
    // storage full: keep the newest half, and if even that fails keep nothing (never grow without limit)
    const names = Object.keys(s).sort((a, b) => s[a].t - s[b].t)
    for (const k of names.slice(0, Math.ceil(names.length / 2))) delete s[k]
    try {
      localStorage.setItem(storeKey(), JSON.stringify(s))
    } catch {
      for (const k of Object.keys(s)) delete s[k]
      try {
        localStorage.removeItem(storeKey())
      } catch {
        // storage unavailable
      }
    }
  }
}

export function remember(name: string, value: unknown) {
  if (!owner) return
  let text: string
  try {
    text = JSON.stringify(value, toJson)
  } catch {
    return
  }
  if (text === undefined || text.length > MAX_CHARS) return // too big to keep: show it live only
  const s = load()
  s[name] = { t: ++clock, s: text }
  prune(s)
  persist(s)
}

export function recall<T>(name: string): T | undefined {
  if (!owner) return undefined
  const e = load()[name]
  if (!e) return undefined
  try {
    return JSON.parse(e.s, fromJson) as T
  } catch {
    return undefined
  }
}

export function markUsingCache(v: boolean) {
  if (usingCache !== v) {
    usingCache = v
    emit()
  }
}

function subscribe(cb: () => void) {
  listeners.add(cb)
  window.addEventListener('online', cb)
  window.addEventListener('offline', cb)
  return () => {
    listeners.delete(cb)
    window.removeEventListener('online', cb)
    window.removeEventListener('offline', cb)
  }
}

/** true when the phone says it is offline, or the screen is showing remembered (not live) data. */
export function useOffline(): boolean {
  return useSyncExternalStore(subscribe, () => !navigator.onLine || usingCache)
}
