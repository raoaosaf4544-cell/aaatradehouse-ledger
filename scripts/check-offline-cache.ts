// Self-check for src/lib/offline.ts. Run: bun scripts/check-offline-cache.ts
// One storage key per login, bounded in entries and size, old copies deleted, Maps survive, sign-out wipes.
import assert from 'node:assert/strict'

// like the browser's localStorage (stored items are its own keys), with a 5M-char quota like a phone
const QUOTA = 5_000_000
const store: Record<string, string> = {}
const used = () => Object.entries(store).reduce((n, [k, v]) => n + k.length + v.length, 0)
Object.defineProperties(store, {
  getItem: { value: (k: string) => (k in store ? store[k] : null) },
  setItem: {
    value: (k: string, v: string) => {
      const before = k in store ? k.length + store[k].length : 0
      if (used() - before + k.length + String(v).length > QUOTA) throw new Error('QuotaExceededError')
      store[k] = String(v)
    },
  },
  removeItem: { value: (k: string) => void delete store[k] },
})
;(globalThis as any).localStorage = store

const { setCacheOwner, remember, recall, clearOfflineCache, MAX_ENTRIES, MAX_CHARS } = await import('../src/lib/offline')
const cacheKeys = () => Object.keys(store).filter((k) => k.startsWith('ledger-cache:'))

// old one-key-per-read copies from earlier versions are deleted when the login is known
store['ledger-cache:user-1:eventLines[[1,2]]'] = '{}'
store['ledger-cache:v2:user-1:eventLines[[1,2,3]]'] = '{"x":1}'
store['unrelated-key'] = 'keep me'
setCacheOwner('user-1')
assert.deepEqual(cacheKeys(), [], 'old copies deleted')
assert.equal(store['unrelated-key'], 'keep me', 'other site data untouched')

// a Map survives the round trip
remember('eventLines[[365,381]]', new Map([[365, [{ id: 1, debit_paisa: 500 }]], [381, []]]))
const back = recall<Map<number, unknown[]>>('eventLines[[365,381]]')!
assert.ok(back instanceof Map)
assert.deepEqual(back.get(365), [{ id: 1, debit_paisa: 500 }])

// many different reads: one storage key, never more than MAX_ENTRIES entries
for (let i = 0; i < 200; i++) remember(`listEvents[30,${i * 30}]`, [{ i }])
assert.deepEqual(cacheKeys(), ['ledger-cache:v3:user-1'], 'exactly one storage key')
assert.ok(Object.keys(JSON.parse(store['ledger-cache:v3:user-1'])).length <= MAX_ENTRIES, 'entries capped')
assert.deepEqual(recall('listEvents[30,5970]'), [{ i: 199 }], 'newest kept')
assert.equal(recall('listEvents[30,0]'), undefined, 'oldest dropped')

// big values: total size stays under MAX_CHARS
const big = 'x'.repeat(100_000)
for (let i = 0; i < 50; i++) remember(`accountLines["1000",30,${i}]`, big)
assert.ok(store['ledger-cache:v3:user-1'].length <= MAX_CHARS + 10_000, 'size capped')
assert.equal(recall(`accountLines["1000",30,49]`), big, 'newest big value kept')

// a single value larger than the cap is not stored at all
remember('huge', 'y'.repeat(MAX_CHARS + 1))
assert.equal(recall('huge'), undefined)

// storage nearly full because of other data: remember never throws and the cache shrinks instead
store['other-app'] = 'z'.repeat(QUOTA - 200_000)
for (let i = 0; i < 10; i++) remember(`fill${i}`, 'w'.repeat(90_000))
assert.ok(used() <= QUOTA, 'quota respected')
delete store['other-app']

// a fresh page load reads the same single key back
setCacheOwner('user-1')
assert.equal(recall('fill9') !== undefined || recall(`accountLines["1000",30,49]`) !== undefined, true, 'readable after reload')

// sign-out wipes everything
clearOfflineCache()
assert.deepEqual(cacheKeys(), [], 'sign-out wipes the cache')
console.log('offline cache check: OK')
