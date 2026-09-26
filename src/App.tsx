import { useState } from 'react'
import { FileSpreadsheet, Menu } from 'lucide-react'
import Sidebar from './components/Sidebar'
import Dashboard from './components/Dashboard'
import CashLedger from './components/CashLedger'
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

function App() {
  const [activeTab, setActiveTab] = useState('dashboard')
  const [isSidebarOpen, setIsSidebarOpen] = useState(false)
  const [dataVersion, setDataVersion] = useState(0)

  function go(tab: string) {
    setActiveTab(tab)
    setIsSidebarOpen(false)
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
          <div className="flex w-full items-center justify-between gap-2 sm:w-auto sm:justify-start sm:gap-3">
            <div className="flex items-center gap-2 sm:gap-3">
              <button
                onClick={() => setIsSidebarOpen(true)}
                className="-ml-2 rounded-lg p-2 text-slate-600 hover:bg-slate-100 md:hidden"
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
                <div className="truncate text-xs text-slate-500 md:text-sm">
                  Accounting &amp; Inventory Ledger — double-entry, audit-safe
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="flex-1 overflow-auto p-4 md:p-8">
          {activeTab === 'dashboard' && <Dashboard key={dataVersion} go={go} />}
          {activeTab === 'cash' && <CashLedger />}
          {activeTab === 'salt' && <SaltInventory key={dataVersion} />}
          {activeTab === 'financials' && <Financials />}
          {activeTab === 'review' && <ReviewQueue />}
          {activeTab === 'debtors' && <Debtors key={dataVersion} onPosted={onPosted} />}
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
