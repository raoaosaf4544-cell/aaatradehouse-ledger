import React, { useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { AppData, Expense } from '../types';

interface Props {
  data: AppData;
  updateData: (newData: Partial<AppData>) => void;
}

export default function AccountsPayable({ data, updateData }: Props) {
  const [showForm, setShowForm] = useState(false);
  
  const [formData, setFormData] = useState<Partial<Expense>>({
    date: new Date().toISOString().split('T')[0],
    category: 'Plant Ops',
    description: '',
    amount: 0,
  });

  const handleAdd = (e: React.FormEvent) => {
    e.preventDefault();
    
    const amt = Number(formData.amount);
    
    const newExpense: Expense = {
      id: `EXP-${Date.now()}`,
      date: formData.date!,
      category: formData.category as any,
      description: formData.description!,
      amount: amt,
    };
    
    // Automatically deduct from cash ledger
    const newLedger = [...data.ledger, {
      id: `TXN-EXP-${Date.now()}`,
      date: newExpense.date,
      type: 'Out' as const,
      category: 'Expense' as const,
      description: `Expense: ${newExpense.category} - ${newExpense.description}`,
      amount: amt,
    }];

    updateData({ expenses: [...data.expenses, newExpense], ledger: newLedger });
    setShowForm(false);
    
    setFormData({
      ...formData,
      description: '',
      amount: 0,
    });
  };

  const deleteExpense = (id: string) => {
    if (!confirm('Delete this expense?')) return;
    updateData({ expenses: data.expenses.filter(e => e.id !== id) });
  };

  const formatPKR = (num: number) => 
    new Intl.NumberFormat('en-PK', { style: 'currency', currency: 'PKR', maximumFractionDigits: 0 }).format(num);

  const totalExpenses = data.expenses.reduce((sum, e) => sum + e.amount, 0);

  // Group by category
  const expensesByCategory = data.expenses.reduce((acc, curr) => {
    acc[curr.category] = (acc[curr.category] || 0) + curr.amount;
    return acc;
  }, {} as Record<string, number>);

  return (
    <div className="space-y-6">
      
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4">
        <div className="col-span-2 md:col-span-4 lg:col-span-2 bg-white p-6 rounded-2xl shadow-sm border border-slate-100">
          <p className="text-sm font-medium text-slate-500 mb-1">Total Operating Spend</p>
          <h3 className="text-3xl font-bold text-slate-800">{formatPKR(totalExpenses)}</h3>
        </div>
        
        {Object.entries(expensesByCategory).map(([cat, amt]) => (
          <div key={cat} className="bg-slate-50 p-4 rounded-xl border border-slate-100 flex flex-col justify-center">
            <p className="text-xs font-semibold text-slate-500 mb-1 truncate">{cat}</p>
            <p className="font-bold text-slate-800">{formatPKR(amt)}</p>
          </div>
        ))}
      </div>

      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-4 sm:p-6 rounded-2xl shadow-sm border border-slate-100">
        <div>
          <h2 className="text-xl font-bold text-slate-800">Operating Expenses & Payables</h2>
          <p className="text-slate-500 text-sm mt-1">
            Log overheads without double counting raw material purchases.
          </p>
        </div>
        <button 
          onClick={() => setShowForm(true)}
          className="w-full sm:w-auto bg-rose-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-rose-700 transition flex items-center justify-center gap-2"
        >
          <Plus className="w-4 h-4" />
          Log Expense
        </button>
      </div>

      {showForm && (
        <div className="fixed inset-0 bg-slate-900/50 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
            <div className="p-6 border-b border-slate-100 flex justify-between items-center bg-rose-50 rounded-t-2xl">
              <h3 className="text-lg font-bold text-rose-800 flex items-center gap-2">Log Daily Expense</h3>
              <button onClick={() => setShowForm(false)} className="text-slate-500 hover:text-slate-700 font-bold">&times;</button>
            </div>
            <form onSubmit={handleAdd} className="p-6 grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Date</label>
                <input type="date" required value={formData.date} onChange={e => setFormData({...formData, date: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-rose-500" />
              </div>
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Expense Tier</label>
                <select value={formData.category} onChange={e => setFormData({...formData, category: e.target.value as any})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-rose-500">
                  <option value="Logistics">Logistics & Freight</option>
                  <option value="Plant Ops">Plant Ops & Maintenance</option>
                  <option value="Salaries">Wages & Salaries</option>
                  <option value="Utilities">Utilities & Fuel</option>
                  <option value="Marketing">Marketing & Comms</option>
                  <option value="Other">Other Overheads</option>
                </select>
              </div>
              <div className="md:col-span-2">
                <label className="block text-sm font-semibold text-slate-700 mb-1">Description</label>
                <input type="text" required placeholder="Electricity bill for Khanewal..." value={formData.description} onChange={e => setFormData({...formData, description: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-rose-500" />
              </div>
              
              <div>
                <label className="block text-sm font-semibold text-rose-700 mb-1">Amount (PKR)</label>
                <input type="number" required min="1" value={formData.amount || ''} onChange={e => setFormData({...formData, amount: Number(e.target.value)})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-rose-200 focus:outline-none focus:ring-2 focus:ring-rose-500" />
              </div>
              
              <div className="md:col-span-2 flex justify-end mt-4 pt-4 border-t border-slate-100">
                <button type="submit" className="bg-rose-600 text-white px-6 py-2.5 rounded-lg font-medium hover:bg-rose-700 transition">Save & Deduct Cash</button>
              </div>
            </form>
          </div>
        </div>
      )}

      <div className="bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden">
        <div className="overflow-x-auto min-h-[400px]">
          <table className="w-full text-sm text-left">
            <thead className="text-xs text-slate-500 uppercase bg-slate-50 border-y border-slate-100 sticky top-0 z-10">
              <tr>
                <th className="px-6 py-4 font-medium">Date</th>
                <th className="px-6 py-4 font-medium">Category</th>
                <th className="px-6 py-4 font-medium">Description</th>
                <th className="px-6 py-4 font-medium text-right">Amount (PKR)</th>
                <th className="px-6 py-4"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {data.expenses.length === 0 && (
                <tr>
                  <td colSpan={5} className="px-6 py-8 text-center text-slate-500">No expenses logged yet.</td>
                </tr>
              )}
              {data.expenses.slice().reverse().map((e) => (
                <tr key={e.id} className="hover:bg-slate-50/50 transition-colors">
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="font-medium text-slate-800">{new Date(e.date).toLocaleDateString()}</div>
                    <div className="text-xs text-slate-400">{e.id}</div>
                  </td>
                  <td className="px-6 py-4">
                    <span className="px-2.5 py-1 bg-slate-100 text-slate-600 rounded-md text-xs font-medium">{e.category}</span>
                  </td>
                  <td className="px-6 py-4 text-slate-700">{e.description}</td>
                  <td className="px-6 py-4 text-right font-semibold text-rose-600">
                    -{formatPKR(e.amount)}
                  </td>
                  <td className="px-6 py-4 text-right">
                    <button onClick={() => deleteExpense(e.id)} className="text-slate-400 hover:text-rose-600 transition"><Trash2 className="w-4 h-4"/></button>
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
