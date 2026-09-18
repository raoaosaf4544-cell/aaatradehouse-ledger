import { useState } from 'react'
import { FileSpreadsheet, Menu } from 'lucide-react'
import Sidebar from './components/Sidebar'
import Dashboard from './components/Dashboard'
import CashLedger from './components/CashLedger'
import SaltInventory from './components/SaltInventory'
import Financials from './components/Financials'
import ReviewQueue from './components/ReviewQueue'

function App() {
  const [activeTab, setActiveTab] = useState('dashboard')
  const [isSidebarOpen, setIsSidebarOpen] = useState(false)

  return (
    <div className="flex h-screen overflow-hidden bg-slate-50 font-sans text-slate-900">
      <Sidebar
        activeTab={activeTab}
        setActiveTab={(tab) => {
          setActiveTab(tab)
          setIsSidebarOpen(false)
        }}
        isOpen={isSidebarOpen}
        setIsOpen={setIsSidebarOpen}
      />

      <main className="relative flex min-w-0 w-full flex-1 flex-col">
        <div className="z-10 flex shrink-0 flex-col items-start justify-between gap-4 border-b border-slate-200 bg-white px-4 py-4 shadow-sm sm:flex-row sm:items-center md:px-8 md:py-5">
          <div className="flex w-full items-center justify-between gap-2 sm:w-auto sm:justify-start sm:gap-3">
            <div className="flex items-center gap-2 sm:gap-3">
              <button
                onClick={() => setIsSidebarOpen(true)}
                className="-ml-2 rounded-lg p-2 text-slate-600 hover:bg-slate-100 md:hidden"
              >
                <Menu className="h-6 h-6" />
              </button>
              <div className="hidden h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-slate-900 text-white sm:flex">
                <FileSpreadsheet className="h-5 w-5" />
              </div>
              <div className="min-w-0">
                <h1 className="truncate text-lg font-bold leading-tight text-slate-800 md:text-xl">
                  AAA Trade House
                </h1>
                <div className="truncate text-xs text-slate-500 md:text-sm">
                  Accounting &amp; Inventory Ledger — double-entry, audit-safe
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="flex-1 overflow-auto p-4 md:p-8">
          {activeTab === 'dashboard' && <Dashboard />}
          {activeTab === 'cash' && <CashLedger />}
          {activeTab === 'salt' && <SaltInventory />}
          {activeTab === 'financials' && <Financials />}
          {activeTab === 'review' && <ReviewQueue />}
        </div>
      </main>
    </div>
  )
}

export default App
