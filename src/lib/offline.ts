import { useSyncExternalStore } from 'react'

/**
 * Offline support for reading. The last answer to each read is remembered in this browser, per signed-in
 * login, and shown read-only when there is no signal. Never used for saving, never for logged-out
 * users: the cache has an owner (the signed-in auth user id) and is wiped on sign-out.
 */
const PREFIX = 'ledger-cache:'
let owner: string | null = null
let usingCache = false
const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())

export function setCacheOwner(authUserId: string | null) {
  owner = authUserId
}

export function clearOfflineCache() {
  try {
    for (const k of Object.keys(localStorage)) if (k.startsWith(PREFIX)) localStorage.removeItem(k)
  } catch {
    // storage unavailable: nothing was cached
  }
  owner = null
  markUsingCache(false)
}

// v2: Maps are stored as tagged entry lists (plain JSON turns a Map into {}). v1 keys are never read
// back, and clearOfflineCache still wipes them because they share PREFIX.
const key = (name: string) => `${PREFIX}v2:${owner}:${name}`
const MAP_TAG = '__map__'
const toJson = (_: string, v: unknown) => (v instanceof Map ? { [MAP_TAG]: [...v] } : v)
const fromJson = (_: string, v: unknown) =>
  v && typeof v === 'object' && MAP_TAG in v ? new Map((v as Record<string, [unknown, unknown][]>)[MAP_TAG]) : v

export function remember(name: string, value: unknown) {
  if (!owner) return
  try {
    localStorage.setItem(key(name), JSON.stringify(value, toJson))
  } catch {
    // storage full or blocked: offline view just has less to show
  }
}

export function recall<T>(name: string): T | undefined {
  if (!owner) return undefined
  try {
    const v = localStorage.getItem(key(name))
    return v === null ? undefined : (JSON.parse(v, fromJson) as T)
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
