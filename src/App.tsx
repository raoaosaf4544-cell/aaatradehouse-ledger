import { useEffect, useRef, useState } from 'react'
import type { Session } from '@supabase/supabase-js'
import { FileSpreadsheet, LogOut, Menu } from 'lucide-react'
import { supabase } from './lib/supabase'
import { engine } from './lib/engine'
import { clearOfflineCache, markUsingCache, recall, remember, setCacheOwner, useOffline } from './lib/offline'
import Login from './components/Login'
import { Spinner } from './components/ui'
import Sidebar from './components/Sidebar'
import Dashboard from './components/Dashboard'
import CashLedger from './components/CashLedger'
import CashBook from './components/CashBook'
import SaltInventory from './components/SaltInventory'
import Financials from './components/Financials'
import ReviewQueue from './components/ReviewQueue'
import Record from './components/Record'
import CapitalInjectionForm from './components/CapitalInjectionForm'
import SaltPurchaseForm from './components/SaltPurchaseForm'
import CrushRunForm from './components/CrushRunForm'
import MoneyOutForm from './components/MoneyOutForm'
import SellSaltForm from './components/SellSaltForm'
import Debtors from './components/Debtors'

type AppUser = { id: string; name: string; role: string }

async function signOut() {
  clearOfflineCache() // remembered books never outlive the login
  engine.userId = null
  // local: this device only. Rao and his father share one login, so a global sign-out would log out the other phone.
  await supabase.auth.signOut({ scope: 'local' })
}

/** Gate: login screen until signed in; only accounts linked in app.users get the ledger. */
function App() {
  const [session, setSession] = useState<Session | null | undefined>(undefined)
  const [user, setUser] = useState<AppUser | null | undefined>(undefined)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data } = supabase.auth.onAuthStateChange((_event, s) => {
      if (!s) clearOfflineCache()
      setSession(s)
    })
    return () => data.subscription.unsubscribe()
  }, [])

  const authUserId = session?.user.id
  useEffect(() => {
    if (!authUserId) {
      engine.userId = null
      setCacheOwner(null)
      setUser(undefined)
      return
    }
    setCacheOwner(authUserId)
    supabase.rpc('current_app_user').then(({ data, error }) => {
      let u: AppUser | null
      if (!error) {
        u = (data as AppUser | null) ?? null
        if (u) remember('app-user', u)
      } else if (!/^(PGRST\d+|[0-9A-Z]{5})$/.test(error.code ?? '')) {
        // no signal: open read-only with the account this login had last time (if any)
        u = recall<AppUser>('app-user') ?? null
        if (u) markUsingCache(true)
      } else {
        u = null
      }
      engine.userId = u?.id ?? null
      setUser(u)
    })
  }, [authUserId])

  if (session === undefined) return <Spinner label="Loading…" />
  if (!session) return <Login />
  if (user === undefined) return <Spinner label="Checking your account…" />
  if (!user) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-50 px-4">
        <div className="w-full max-w-sm space-y-4 rounded-2xl border border-slate-200 bg-white p-6 text-center">
          <p className="text-lg font-semibold text-slate-800">This account is not authorised for the ledger.</p>
          <button onClick={signOut} className="w-full rounded-xl bg-slate-900 py-3.5 text-lg font-semibold text-white">
            Sign out
          </button>
        </div>
      </div>
    )
  }
  return <Ledger userName={user.name} />
}

const TABS = new Set([
  'dashboard', 'cashbook', 'cash', 'salt', 'financials', 'review', 'debtors', 'record',
  'record-capital', 'record-purchase', 'record-crush', 'record-moneyout', 'record-sale',
])
const tabFromHash = () => {
  const t = window.location.hash.slice(1)
  return TABS.has(t) ? t : 'dashboard'
}
/** Installed on the home screen: Back must never close the app (there is no browser around it). */
const isInstalledApp = () =>
  window.matchMedia?.('(display-mode: standalone)').matches || (navigator as { standalone?: boolean }).standalone === true

function Ledger({ userName }: { userName: string }) {
  const offline = useOffline()
  const [activeTab, setActiveTab] = useState(tabFromHash)
  const [isSidebarOpen, setIsSidebarOpen] = useState(false)
  const [dataVersion, setDataVersion] = useState(0)
  const tabRef = useRef(activeTab)
  const drawerRef = useRef(false)
  tabRef.current = activeTab
  drawerRef.current = isSidebarOpen

  // Phone Back button = previous screen. Each screen change is one history step (#tab in the address).
  useEffect(() => {
    const start = tabRef.current
    if (isInstalledApp()) {
      // a guard step under the first screen: Back on the Dashboard stays in the app
      window.history.replaceState({ tab: 'dashboard', guard: true }, '', '#dashboard')
      window.history.pushState({ tab: start }, '', `#${start}`)
    } else {
      window.history.replaceState({ tab: start }, '', `#${start}`)
    }
    const onPop = (e: PopStateEvent) => {
      const st = e.state as { tab?: string; guard?: boolean } | null
      if (drawerRef.current) {
        // Back with the menu open just closes the menu
        setIsSidebarOpen(false)
        window.history.pushState({ tab: tabRef.current }, '', `#${tabRef.current}`)
        return
      }
      if (st?.guard) {
        window.history.pushState({ tab: 'dashboard' }, '', '#dashboard')
        setActiveTab('dashboard')
        return
      }
      setActiveTab(st?.tab && TABS.has(st.tab) ? st.tab : tabFromHash())
    }
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])

  function go(tab: string) {
    if (tab !== tabRef.current) window.history.pushState({ tab }, '', `#${tab}`)
    setActiveTab(tab)
    setIsSidebarOpen(false)
    document.querySelector('main .overflow-auto')?.scrollTo(0, 0)
  }

  function onPosted() {
    setDataVersion((v) => v + 1)
  }

  return (
    <div className="flex h-screen overflow-hidden bg-slate-50 font-sans text-slate-900">
      <Sidebar
        activeTab={activeTab}
        setActiveTab={go}
        isOpen={isSidebarOpen}
        setIsOpen={setIsSidebarOpen}
      />

      <main className="relative flex min-w-0 w-full flex-1 flex-col">
        <div className="z-10 flex shrink-0 flex-col items-start justify-between gap-4 border-b border-slate-200 bg-white px-4 py-4 shadow-sm sm:flex-row sm:items-center md:px-8 md:py-5">
          <div className="flex w-full items-center justify-between gap-2 sm:gap-3">
            <div className="flex min-w-0 flex-1 items-center gap-2 sm:gap-3">
              <button
                onClick={() => setIsSidebarOpen(true)}
                aria-label="Open menu"
                className="-ml-2 flex min-h-11 min-w-11 shrink-0 items-center justify-center rounded-lg text-slate-600 hover:bg-slate-100 md:hidden"
              >
                <Menu className="h-6 w-6" />
              </button>
              <div className="hidden h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-slate-900 text-white sm:flex">
                <FileSpreadsheet className="h-5 w-5" />
              </div>
              <div className="min-w-0">
                <h1 className="truncate text-lg font-bold leading-tight text-slate-800 md:text-xl">
                  AAA Trade House
                </h1>
                <div className="hidden truncate text-xs text-slate-500 sm:block md:text-sm">
                  Accounting &amp; Inventory Ledger — double-entry, audit-safe
                </div>
              </div>
            </div>
            <button
              onClick={signOut}
              title={`Signed in as ${userName}`}
              className="flex min-h-11 shrink-0 items-center gap-2 rounded-lg border border-slate-200 px-3 text-sm font-medium text-slate-600 hover:bg-slate-100"
            >
              <LogOut className="h-4 w-4" />
              Sign out
            </button>
          </div>
        </div>

        {offline && (
          <div role="alert" className="shrink-0 bg-amber-100 px-4 py-2.5 text-center text-base font-bold text-amber-900">
            Offline — entries need signal. Showing the last loaded figures.
          </div>
        )}

        <div className="flex-1 overflow-auto p-4 md:p-8">
          {activeTab === 'dashboard' && <Dashboard key={dataVersion} go={go} />}
          {activeTab === 'cashbook' && <CashBook />}
          {activeTab === 'cash' && <CashLedger />}
          {activeTab === 'salt' && <SaltInventory key={dataVersion} />}
          {activeTab === 'financials' && <Financials />}
          {activeTab === 'review' && <ReviewQueue />}
          {activeTab === 'debtors' && <Debtors onPosted={onPosted} />}
          {activeTab === 'record' && <Record go={go} />}
          {activeTab === 'record-capital' && <CapitalInjectionForm onPosted={onPosted} />}
          {activeTab === 'record-purchase' && <SaltPurchaseForm onPosted={onPosted} />}
          {activeTab === 'record-crush' && <CrushRunForm onPosted={onPosted} />}
          {activeTab === 'record-moneyout' && <MoneyOutForm onPosted={onPosted} />}
          {activeTab === 'record-sale' && <SellSaltForm onPosted={onPosted} />}
        </div>
      </main>
    </div>
  )
}

export default App
