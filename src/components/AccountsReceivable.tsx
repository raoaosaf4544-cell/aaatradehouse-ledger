import React, { useState } from 'react';
import { Plus, Trash2, DollarSign } from 'lucide-react';
import { AppData, Order } from '../types';

interface Props {
  data: AppData;
  updateData: (newData: Partial<AppData>) => void;
}

export default function AccountsReceivable({ data, updateData }: Props) {
  const [showForm, setShowForm] = useState(false);
  
  const [formData, setFormData] = useState<Partial<Order>>({
    date: new Date().toISOString().split('T')[0],
    customerName: '',
    saltType: 'Pink Fine Salt',
    quantityTons: 0,
    ratePerTon: 0,
    advanceReceived: 0,
    status: 'Pending',
    notes: '',
  });

  const handleAdd = (e: React.FormEvent) => {
    e.preventDefault();
    
    const qty = Number(formData.quantityTons);
    const rate = Number(formData.ratePerTon);
    const advance = Number(formData.advanceReceived);
    
    const newOrder: Order = {
      id: `ORD-${Date.now()}`,
      date: formData.date!,
      customerName: formData.customerName!,
      saltType: formData.saltType!,
      quantityTons: qty,
      ratePerTon: rate,
      totalAmount: qty * rate,
      advanceReceived: advance,
      status: formData.status as any,
      notes: formData.notes,
    };
    
    const newOrders = [...data.orders, newOrder];
    
    // Automatically log advance payment to Cash Ledger
    let newLedger = [...data.ledger];
    if (advance > 0) {
      newLedger.push({
        id: `TXN-ADV-${Date.now()}`,
        date: newOrder.date,
        type: 'In',
        category: 'Sales',
        description: `Advance received for ${newOrder.id} - ${newOrder.customerName}`,
        amount: advance,
        partyName: newOrder.customerName
      });
    }

    updateData({ orders: newOrders, ledger: newLedger });
    setShowForm(false);
    
    setFormData({
      ...formData,
      customerName: '',
      quantityTons: 0,
      ratePerTon: 0,
      advanceReceived: 0,
      notes: ''
    });
  };

  const handleUpdateStatus = (orderId: string, newStatus: string) => {
    const newOrders = data.orders.map(o => o.id === orderId ? { ...o, status: newStatus as any } : o);
    updateData({ orders: newOrders });
  };

  const deleteOrder = (id: string) => {
    if (!confirm('Delete this order? Any payments received will remain in the ledger.')) return;
    updateData({ orders: data.orders.filter(o => o.id !== id) });
  };

  const receiveRemainingPayment = (order: Order) => {
    const balance = order.totalAmount - order.advanceReceived;
    if (balance <= 0) return alert('No balance due.');
    
    const amtToReceive = prompt(`Enter amount to receive (Balance: ${balance}):`, balance.toString());
    if (!amtToReceive) return;
    
    const numAmt = Number(amtToReceive);
    if (isNaN(numAmt) || numAmt <= 0) return alert('Invalid amount');

    // Update order advanceReceived
    const newOrders = data.orders.map(o => 
      o.id === order.id ? { ...o, advanceReceived: o.advanceReceived + numAmt } : o
    );

    // Update Ledger
    const newLedger = [...data.ledger, {
      id: `TXN-PMT-${Date.now()}`,
      date: new Date().toISOString().split('T')[0],
      type: 'In' as const,
      category: 'Sales' as const,
      description: `Payment received for ${order.id} - ${order.customerName}`,
      amount: numAmt,
      partyName: order.customerName
    }];

    updateData({ orders: newOrders, ledger: newLedger });
  };

  const formatPKR = (num: number) => 
    new Intl.NumberFormat('en-PK', { style: 'currency', currency: 'PKR', maximumFractionDigits: 0 }).format(num);

  const totalReceivables = data.orders.reduce((sum, o) => sum + (o.totalAmount - o.advanceReceived), 0);

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-4 sm:p-6 rounded-2xl shadow-sm border border-slate-100">
        <div>
          <h2 className="text-xl font-bold text-slate-800">Orders & Receivables (A/R)</h2>
          <p className="text-slate-500 text-sm mt-1">
            Total Outstanding: <span className="font-bold text-slate-800">{formatPKR(totalReceivables)}</span>
          </p>
        </div>
        <button 
          onClick={() => setShowForm(true)}
          className="w-full sm:w-auto bg-indigo-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-indigo-700 transition flex items-center justify-center gap-2"
        >
          <Plus className="w-4 h-4" />
          New Order
        </button>
      </div>

      {showForm && (
        <div className="fixed inset-0 bg-slate-900/50 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-3xl max-h-[90vh] overflow-y-auto">
            <div className="p-6 border-b border-slate-100 flex justify-between items-center bg-indigo-50 rounded-t-2xl">
              <h3 className="text-lg font-bold text-indigo-800 flex items-center gap-2">Create New Sales Order</h3>
              <button onClick={() => setShowForm(false)} className="text-slate-500 hover:text-slate-700 font-bold">&times;</button>
            </div>
            <form onSubmit={handleAdd} className="p-6 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Date</label>
                <input type="date" required value={formData.date} onChange={e => setFormData({...formData, date: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
              </div>
              <div className="md:col-span-2">
                <label className="block text-sm font-semibold text-slate-700 mb-1">Customer / Buyer</label>
                <input type="text" required placeholder="Name..." value={formData.customerName} onChange={e => setFormData({...formData, customerName: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
              </div>
              <div className="md:col-span-2">
                <label className="block text-sm font-semibold text-slate-700 mb-1">Salt Type / Grade</label>
                <input type="text" required placeholder="Pink Fine Salt..." value={formData.saltType} onChange={e => setFormData({...formData, saltType: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
              </div>
              
              <div>
                <label className="block text-sm font-semibold text-emerald-700 mb-1">Quantity (Tons)</label>
                <input type="number" required min="1" value={formData.quantityTons || ''} onChange={e => setFormData({...formData, quantityTons: Number(e.target.value)})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-emerald-200 focus:outline-none focus:ring-2 focus:ring-emerald-500" />
              </div>
              <div>
                <label className="block text-sm font-semibold text-emerald-700 mb-1">Rate per Ton (PKR)</label>
                <input type="number" required min="1" value={formData.ratePerTon || ''} onChange={e => setFormData({...formData, ratePerTon: Number(e.target.value)})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-emerald-200 focus:outline-none focus:ring-2 focus:ring-emerald-500" />
              </div>
              
              <div>
                <label className="block text-sm font-semibold text-indigo-700 mb-1">Advance Received (PKR)</label>
                <input type="number" required min="0" value={formData.advanceReceived || ''} onChange={e => setFormData({...formData, advanceReceived: Number(e.target.value)})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-indigo-200 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
              </div>
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Initial Status</label>
                <select value={formData.status} onChange={e => setFormData({...formData, status: e.target.value as any})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500">
                  <option value="Pending">Pending</option>
                  <option value="Processing">Processing</option>
                  <option value="Dispatched">Dispatched</option>
                  <option value="Delivered">Delivered</option>
                </select>
              </div>
              
              <div className="md:col-span-3 flex justify-between items-center mt-4 pt-4 border-t border-slate-100">
                <p className="text-lg font-bold text-slate-800">
                  Total Value: {formatPKR(Number(formData.quantityTons || 0) * Number(formData.ratePerTon || 0))}
                </p>
                <button type="submit" className="bg-indigo-600 text-white px-6 py-2.5 rounded-lg font-medium hover:bg-indigo-700 transition">Save Order</button>
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
                <th className="px-6 py-4 font-medium">Order Date</th>
                <th className="px-6 py-4 font-medium">Customer & Item</th>
                <th className="px-6 py-4 font-medium">Status</th>
                <th className="px-6 py-4 font-medium text-right">Order Value</th>
                <th className="px-6 py-4 font-medium text-right">Balance Due</th>
                <th className="px-6 py-4"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {data.orders.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-6 py-8 text-center text-slate-500">No orders placed yet.</td>
                </tr>
              )}
              {data.orders.slice().reverse().map((o) => (
                <tr key={o.id} className="hover:bg-slate-50/50 transition-colors">
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="font-medium text-slate-800">{new Date(o.date).toLocaleDateString()}</div>
                    <div className="text-xs text-slate-400">{o.id}</div>
                  </td>
                  <td className="px-6 py-4">
                    <div className="font-bold text-slate-800">{o.customerName}</div>
                    <div className="text-sm text-slate-600">{o.quantityTons}t &middot; {o.saltType}</div>
                  </td>
                  <td className="px-6 py-4">
                    <select 
                      value={o.status}
                      onChange={(e) => handleUpdateStatus(o.id, e.target.value)}
                      className={`px-2 py-1 rounded text-xs font-semibold uppercase tracking-wider border-0 cursor-pointer ${
                        o.status === 'Pending' ? 'bg-amber-100 text-amber-700' :
                        o.status === 'Processing' ? 'bg-blue-100 text-blue-700' :
                        o.status === 'Dispatched' ? 'bg-purple-100 text-purple-700' :
                        o.status === 'Delivered' ? 'bg-emerald-100 text-emerald-700' :
                        'bg-slate-100 text-slate-700'
                      }`}
                    >
                      <option value="Pending">Pending</option>
                      <option value="Processing">Processing</option>
                      <option value="Dispatched">Dispatched</option>
                      <option value="Delivered">Delivered</option>
                      <option value="Cancelled">Cancelled</option>
                    </select>
                  </td>
                  <td className="px-6 py-4 text-right">
                    <div className="font-semibold text-slate-800">{formatPKR(o.totalAmount)}</div>
                    <div className="text-xs text-emerald-600">Paid: {formatPKR(o.advanceReceived)}</div>
                  </td>
                  <td className="px-6 py-4 text-right font-bold text-rose-600">
                    {formatPKR(o.totalAmount - o.advanceReceived)}
                  </td>
                  <td className="px-6 py-4 flex items-center justify-end gap-2">
                    {o.totalAmount - o.advanceReceived > 0 && (
                      <button onClick={() => receiveRemainingPayment(o)} title="Receive Payment" className="text-emerald-600 hover:text-emerald-700 bg-emerald-50 hover:bg-emerald-100 p-1.5 rounded transition">
                        <DollarSign className="w-4 h-4"/>
                      </button>
                    )}
                    <button onClick={() => deleteOrder(o.id)} className="text-slate-400 hover:text-rose-600 p-1.5 rounded transition">
                      <Trash2 className="w-4 h-4"/>
                    </button>
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
