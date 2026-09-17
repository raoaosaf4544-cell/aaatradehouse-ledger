import { LayoutDashboard, Wallet, Boxes, Users, Calculator, FileText, Package, X } from 'lucide-react';

export default function Sidebar({ activeTab, setActiveTab, isOpen, setIsOpen }: { activeTab: string, setActiveTab: (tab: string) => void, isOpen: boolean, setIsOpen: (val: boolean) => void }) {
  const tabs = [
    { id: 'dashboard', name: 'Dashboard', icon: LayoutDashboard },
    { id: 'cash', name: 'Cash Ledger', icon: Wallet },
    { id: 'salt', name: 'Salt Inventory & Yield', icon: Boxes },
    { id: 'ar', name: 'Accounts Receivable', icon: Users },
    { id: 'ap', name: 'Accounts Payable', icon: Calculator },
    { id: 'financials', name: 'Financials & P&L', icon: FileText },
  ];

  return (
    <>
      {/* Mobile overlay */}
      {isOpen && (
        <div 
          className="fixed inset-0 bg-black/50 z-40 md:hidden transition-opacity" 
          onClick={() => setIsOpen(false)} 
        />
      )}

      <aside className={`fixed inset-y-0 left-0 z-50 w-64 bg-slate-900 text-slate-300 flex flex-col h-full border-r border-slate-800 shrink-0 transform transition-transform duration-300 md:relative md:translate-x-0 ${isOpen ? 'translate-x-0' : '-translate-x-full'}`}>
        <div className="p-6 border-b border-slate-800 flex justify-between items-center">
          <div>
            <h2 className="text-xl font-bold text-white tracking-wide">AAA Trade House</h2>
            <p className="text-xs text-slate-500 mt-1 uppercase tracking-widest">Master Ledger</p>
          </div>
          <button className="md:hidden text-slate-400 hover:text-white" onClick={() => setIsOpen(false)}>
            <X className="w-5 h-5" />
          </button>
        </div>
        <nav className="flex-1 overflow-y-auto py-4">
          <ul className="space-y-1 px-3">
            {tabs.map((tab) => (
              <li key={tab.id}>
                <button
                  onClick={() => setActiveTab(tab.id)}
                  className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors text-sm font-medium ${
                    activeTab === tab.id
                      ? 'bg-blue-600/10 text-blue-400'
                      : 'hover:bg-slate-800 hover:text-slate-100'
                  }`}
                >
                  <tab.icon className="w-4 h-4 shrink-0" />
                  <span className="truncate">{tab.name}</span>
                </button>
              </li>
            ))}
          </ul>
        </nav>
        <div className="p-4 border-t border-slate-800">
          <div className="bg-slate-800 rounded-lg p-4 text-xs text-slate-400">
            <p>Data is securely stored in your local browser cache.</p>
          </div>
        </div>
      </aside>
    </>
  );
}
