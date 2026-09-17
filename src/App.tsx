import React, { useState } from 'react';
import { Menu, Download, Settings, FileSpreadsheet, Save, RotateCcw } from 'lucide-react';
import Sidebar from './components/Sidebar';
import Dashboard from './components/Dashboard';
import CashLedger from './components/CashLedger';
import SaltInventory from './components/SaltInventory';
import AccountsReceivable from './components/AccountsReceivable';
import AccountsPayable from './components/AccountsPayable';
import Financials from './components/Financials';
import OpeningBalancesModal from './components/OpeningBalancesModal';
import { useAppStore } from './lib/store';
import * as XLSX from 'xlsx';

function App() {
  const { data, updateData, updateOpeningBalances, resetData, isLoaded } = useAppStore();
  const [activeTab, setActiveTab] = useState('dashboard');
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [isBalancesModalOpen, setIsBalancesModalOpen] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  if (!isLoaded) return null;

  const handleSaveToExcel = () => {
    setIsSaving(true);
    setTimeout(() => {
      const newWb = XLSX.utils.book_new();
      
      const ledgerSheet = XLSX.utils.json_to_sheet(data.ledger);
      XLSX.utils.book_append_sheet(newWb, ledgerSheet, 'Cash Ledger');
      
      const saltBatchesSheet = XLSX.utils.json_to_sheet(data.saltBatches);
      XLSX.utils.book_append_sheet(newWb, saltBatchesSheet, 'Salt Batches');
      
      const processSheet = XLSX.utils.json_to_sheet(data.processingLogs);
      XLSX.utils.book_append_sheet(newWb, processSheet, 'Processing Logs');
      
      const ordersSheet = XLSX.utils.json_to_sheet(data.orders);
      XLSX.utils.book_append_sheet(newWb, ordersSheet, 'Orders');
      
      const expensesSheet = XLSX.utils.json_to_sheet(data.expenses);
      XLSX.utils.book_append_sheet(newWb, expensesSheet, 'Expenses');

      XLSX.writeFile(newWb, 'AAA_Trade_House_Master_Ledger.xlsx');
      setIsSaving(false);
    }, 500);
  };

  return (
    <div className="flex h-screen bg-slate-50 text-slate-900 font-sans overflow-hidden">
      <Sidebar 
        activeTab={activeTab} 
        setActiveTab={(tab) => { setActiveTab(tab); setIsSidebarOpen(false); }} 
        isOpen={isSidebarOpen} 
        setIsOpen={setIsSidebarOpen} 
      />

      <main className="flex-1 flex flex-col min-w-0 w-full relative">
        <div className="bg-white px-4 md:px-8 py-4 md:py-5 border-b border-slate-200 flex flex-col sm:flex-row sm:justify-between items-start sm:items-center gap-4 shrink-0 shadow-sm z-10 relative">
          <div className="flex items-center gap-2 sm:gap-3 w-full sm:w-auto justify-between sm:justify-start">
            <div className="flex items-center gap-2 sm:gap-3">
              <button onClick={() => setIsSidebarOpen(true)} className="md:hidden p-2 -ml-2 text-slate-600 hover:bg-slate-100 rounded-lg">
                <Menu className="w-6 h-6" />
              </button>
              <div className="w-10 h-10 bg-slate-900 text-white rounded-xl hidden sm:flex items-center justify-center shrink-0">
                <FileSpreadsheet className="w-5 h-5" />
              </div>
              <div className="min-w-0">
                <h1 className="text-lg md:text-xl font-bold text-slate-800 leading-tight truncate">AAA Trade House</h1>
                <div className="text-xs md:text-sm text-slate-500 truncate">
                  Master Local Distribution Ledger
                </div>
              </div>
            </div>
          </div>
          
          <div className="flex w-full sm:w-auto gap-2">
            <button 
              onClick={resetData}
              className="px-3 sm:px-4 py-2 sm:py-2.5 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 shrink-0 bg-rose-100 text-rose-700 hover:bg-rose-200 border border-rose-200"
            >
              <RotateCcw className="w-4 h-4 shrink-0" />
              <span className="hidden sm:inline">Reset Baseline</span>
            </button>
            <button 
              onClick={() => setIsBalancesModalOpen(true)}
              className="px-3 sm:px-4 py-2 sm:py-2.5 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 shrink-0 bg-slate-100 text-slate-700 hover:bg-slate-200 border border-slate-200"
            >
              <Settings className="w-4 h-4 shrink-0" />
              <span className="hidden sm:inline">Opening Balances</span>
            </button>
            <button 
              onClick={handleSaveToExcel}
              disabled={isSaving}
              className={`flex-1 sm:flex-none px-3 sm:px-5 py-2 sm:py-2.5 rounded-lg text-sm font-medium transition flex items-center justify-center gap-2 shrink-0 ${
                isSaving 
                  ? 'bg-slate-100 text-slate-400 cursor-not-allowed' 
                  : 'bg-emerald-600 text-white hover:bg-emerald-700 shadow-sm shadow-emerald-200'
              }`}
            >
              {isSaving ? <Save className="w-4 h-4 animate-pulse shrink-0" /> : <Download className="w-4 h-4 shrink-0" />}
              <span className="hidden sm:inline">{isSaving ? 'Saving...' : 'Export Excel'}</span>
            </button>
          </div>
        </div>

        <div className="flex-1 overflow-auto p-4 md:p-8">
          {activeTab === 'dashboard' && <Dashboard data={data} />}
          {activeTab === 'cash' && <CashLedger data={data} updateData={updateData} />}
          {activeTab === 'salt' && <SaltInventory data={data} updateData={updateData} />}
          {/* We will rewrite AR/AP/Financials soon */}
          {activeTab === 'ar' && <AccountsReceivable data={data} updateData={updateData} />}
          {activeTab === 'ap' && <AccountsPayable data={data} updateData={updateData} />}
          {activeTab === 'financials' && <Financials data={data} />}
        </div>
      </main>

      {isBalancesModalOpen && (
        <OpeningBalancesModal
          isOpen={isBalancesModalOpen}
          onClose={() => setIsBalancesModalOpen(false)}
          openingBalances={data.openingBalances}
          updateOpeningBalances={updateOpeningBalances}
        />
      )}
    </div>
  );
}

export default App;
// Cache bust Wed Sep 16 08:19:53 AM UTC 2026
