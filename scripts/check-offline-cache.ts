// Self-check for src/lib/offline.ts: a Map survives the offline copy, and sign-out wipes old and new keys.
// Run: bun scripts/check-offline-cache.ts
import assert from 'node:assert/strict'

// like the browser's localStorage: stored items are its own keys, the methods are not
const store: Record<string, string> = {}
Object.defineProperties(store, {
  getItem: { value: (k: string) => (k in store ? store[k] : null) },
  setItem: { value: (k: string, v: string) => void (store[k] = String(v)) },
  removeItem: { value: (k: string) => void delete store[k] },
})
;(globalThis as any).localStorage = store

const { setCacheOwner, remember, recall, clearOfflineCache } = await import('../src/lib/offline')

setCacheOwner('user-1')
const lines = new Map([[365, [{ id: 1, debit_paisa: 500 }]], [381, []]])
remember('eventLines[[365,381]]', lines)
remember('accountBalances[]', [{ code: '1000', balance_paisa: 51744500 }])

const back = recall<Map<number, unknown[]>>('eventLines[[365,381]]')!
assert.ok(back instanceof Map, 'Map restored as a Map')
assert.deepEqual(back.get(365), [{ id: 1, debit_paisa: 500 }])
assert.deepEqual(back.get(381), [])
assert.deepEqual(recall('accountBalances[]'), [{ code: '1000', balance_paisa: 51744500 }])

store['ledger-cache:user-1:eventLines[[365,381]]'] = '{}' // a broken v1 copy from before the fix
assert.ok(recall('eventLines[[365,381]]') instanceof Map, 'v1 copy is never read back')

clearOfflineCache()
assert.equal(Object.keys(store).filter((k) => k.startsWith('ledger-cache:')).length, 0, 'sign-out wipes v1 and v2')
console.log('offline cache check: OK')
