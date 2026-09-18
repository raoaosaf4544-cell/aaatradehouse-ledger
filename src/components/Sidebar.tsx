import { Boxes, Flag, LayoutDashboard, Wallet, X, BarChart3 } from 'lucide-react'

export default function Sidebar({
  activeTab,
  setActiveTab,
  isOpen,
  setIsOpen,
}: {
  activeTab: string
  setActiveTab: (tab: string) => void
  isOpen: boolean
  setIsOpen: (val: boolean) => void
}) {
  const tabs = [
    { id: 'dashboard', name: 'Dashboard', icon: LayoutDashboard },
    { id: 'cash', name: 'Cash Ledger', icon: Wallet },
    { id: 'salt', name: 'Salt Inventory', icon: Boxes },
    { id: 'financials', name: 'Financials & Trial Balance', icon: BarChart3 },
    { id: 'review', name: 'Review Queue', icon: Flag },
  ]

  return (
    <>
      {isOpen && (
        <div
          className="fixed inset-0 z-40 bg-black/50 transition-opacity md:hidden"
          onClick={() => setIsOpen(false)}
        />
      )}

      <aside
        className={`fixed inset-y-0 left-0 z-50 flex h-full w-64 shrink-0 transform flex-col border-r border-slate-800 bg-slate-900 text-slate-300 transition-transform duration-300 md:relative md:translate-x-0 ${
          isOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        <div className="flex items-center justify-between border-b border-slate-800 p-6">
          <div>
            <h2 className="text-xl font-bold tracking-wide text-white">AAA Trade House</h2>
            <p className="mt-1 text-xs uppercase tracking-widest text-slate-500">Master Ledger</p>
          </div>
          <button className="text-slate-400 hover:text-white md:hidden" onClick={() => setIsOpen(false)}>
            <X className="h-5 w-5" />
          </button>
        </div>
        <nav className="flex-1 overflow-y-auto py-4">
          <ul className="space-y-1 px-3">
            {tabs.map((tab) => (
              <li key={tab.id}>
                <button
                  onClick={() => setActiveTab(tab.id)}
                  className={`w-full flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors ${
                    activeTab === tab.id
                      ? 'bg-blue-600/10 text-blue-400'
                      : 'hover:bg-slate-800 hover:text-slate-100'
                  }`}
                >
                  <tab.icon className="h-4 w-4 shrink-0" />
                  <span className="truncate">{tab.name}</span>
                </button>
              </li>
            ))}
          </ul>
        </nav>
        <div className="border-t border-slate-800 p-4">
          <div className="rounded-lg bg-slate-800 p-4 text-xs text-slate-400">
            Your books live in a secure cloud database with double-entry checks on every entry —
            not in this browser.
          </div>
        </div>
      </aside>
    </>
  )
}
