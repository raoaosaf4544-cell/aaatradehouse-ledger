import React, { useState } from 'react';
import { Plus, ArrowUpRight, ArrowDownRight } from 'lucide-react';
import { AppData, LedgerTransaction } from '../types';

interface Props {
  data: AppData;
  updateData: (newData: Partial<AppData>) => void;
}

export default function CashLedger({ data, updateData }: Props) {
  const [showForm, setShowForm] = useState(false);
  const [formData, setFormData] = useState<Partial<LedgerTransaction>>({
    date: new Date().toISOString().split('T')[0],
    type: 'In',
    category: 'Sales',
    description: '',
    amount: 0,
  });

  const handleAdd = (e: React.FormEvent) => {
    e.preventDefault();
    const newTxn: LedgerTransaction = {
      id: `TXN-${Date.now()}`,
      date: formData.date!,
      type: formData.type as 'In' | 'Out',
      category: formData.category as any,
      description: formData.description!,
      amount: Number(formData.amount),
    };
    
    updateData({ ledger: [...data.ledger, newTxn] });
    
    setFormData({
      ...formData,
      description: '',
      amount: 0,
    });
    setShowForm(false);
  };

  const formatPKR = (num: number) => 
    new Intl.NumberFormat('en-PK', { style: 'currency', currency: 'PKR', maximumFractionDigits: 0 }).format(num);

  const cashIn = data.ledger.filter(t => t.type === 'In').reduce((sum, t) => sum + t.amount, 0);
  const cashOut = data.ledger.filter(t => t.type === 'Out').reduce((sum, t) => sum + t.amount, 0);
  const netCash = data.openingBalances.cashOnHand + cashIn - cashOut;

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-4 sm:p-6 rounded-2xl shadow-sm border border-slate-100">
        <div>
          <h2 className="text-xl font-bold text-slate-800">Cash Ledger</h2>
          <p className="text-slate-500 text-sm mt-1">
            Running Balance: <span className="font-bold text-slate-800">{formatPKR(netCash)}</span>
          </p>
        </div>
        <button 
          onClick={() => setShowForm(!showForm)}
          className="w-full sm:w-auto bg-slate-900 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-slate-800 transition flex items-center justify-center gap-2"
        >
          <Plus className="w-4 h-4" />
          {showForm ? 'Cancel' : 'Log Transaction'}
        </button>
      </div>

      {showForm && (
        <form onSubmit={handleAdd} className="bg-slate-50 border border-slate-200 p-6 rounded-2xl shadow-sm grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Date</label>
            <input type="date" required value={formData.date} onChange={e => setFormData({...formData, date: e.target.value})} className="w-full px-3 py-2 bg-white rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-slate-400" />
          </div>
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Type</label>
            <select value={formData.type} onChange={e => setFormData({...formData, type: e.target.value as any})} className="w-full px-3 py-2 bg-white rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-slate-400">
              <option value="In">Money In (+)</option>
              <option value="Out">Money Out (-)</option>
            </select>
          </div>
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Category</label>
            <select value={formData.category} onChange={e => setFormData({...formData, category: e.target.value as any})} className="w-full px-3 py-2 bg-white rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-slate-400">
              <option value="Sales">Sales</option>
              <option value="Purchase">Purchase</option>
              <option value="Expense">Expense</option>
              <option value="Opening Balance">Opening Balance</option>
              <option value="Other">Other</option>
            </select>
          </div>
          <div className="lg:col-span-2">
            <label className="block text-xs font-semibold text-slate-700 mb-1">Description</label>
            <input type="text" required placeholder="Payment details..." value={formData.description} onChange={e => setFormData({...formData, description: e.target.value})} className="w-full px-3 py-2 bg-white rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-slate-400" />
          </div>
          <div className="lg:col-span-2">
            <label className={`block text-xs font-semibold mb-1 ${formData.type === 'In' ? 'text-emerald-700' : 'text-rose-700'}`}>Amount (PKR)</label>
            <input type="number" required min="1" value={formData.amount || ''} onChange={e => setFormData({...formData, amount: Number(e.target.value)})} className={`w-full px-3 py-2 bg-white rounded-lg border focus:outline-none focus:ring-2 ${formData.type === 'In' ? 'border-emerald-200 focus:ring-emerald-500' : 'border-rose-200 focus:ring-rose-500'}`} />
          </div>
          
          <div className="lg:col-span-3 flex justify-end items-end mt-2">
            <button type="submit" className="bg-slate-900 text-white px-6 py-2 rounded-lg text-sm font-medium hover:bg-slate-800 transition">Save Transaction</button>
          </div>
        </form>
      )}

      <div className="bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden">
        <div className="overflow-x-auto max-h-[600px]">
          <table className="w-full text-sm text-left">
            <thead className="text-xs text-slate-500 uppercase bg-slate-50 border-y border-slate-100 sticky top-0 z-10">
              <tr>
                <th className="px-6 py-4 font-medium">Date & ID</th>
                <th className="px-6 py-4 font-medium">Category</th>
                <th className="px-6 py-4 font-medium">Description</th>
                <th className="px-6 py-4 font-medium text-right">Money In</th>
                <th className="px-6 py-4 font-medium text-right">Money Out</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {data.ledger.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-6 py-8 text-center text-slate-500">No transactions recorded yet.</td>
                </tr>
              )}
              {data.ledger.slice().reverse().map((t) => (
                <tr key={t.id} className="hover:bg-slate-50/50 transition-colors">
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="font-medium text-slate-800">{new Date(t.date).toLocaleDateString()}</div>
                    <div className="text-xs text-slate-400">{t.id}</div>
                  </td>
                  <td className="px-6 py-4">
                    <span className="px-2.5 py-1 bg-slate-100 text-slate-600 rounded-md text-xs font-medium">{t.category}</span>
                  </td>
                  <td className="px-6 py-4 text-slate-700">{t.description}</td>
                  <td className="px-6 py-4 text-right font-semibold text-emerald-600">
                    {t.type === 'In' ? (
                      <div className="flex items-center justify-end gap-1">
                        <ArrowDownRight className="w-3 h-3" />
                        {formatPKR(t.amount)}
                      </div>
                    ) : '-'}
                  </td>
                  <td className="px-6 py-4 text-right font-semibold text-rose-600">
                    {t.type === 'Out' ? (
                      <div className="flex items-center justify-end gap-1">
                        <ArrowUpRight className="w-3 h-3" />
                        {formatPKR(t.amount)}
                      </div>
                    ) : '-'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
