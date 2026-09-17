import React from 'react';
import { AppData } from '../types';
import { DollarSign, Package, TrendingUp, Users, ArrowUpRight, ArrowDownRight } from 'lucide-react';

interface Props {
  data: AppData;
}

export default function Dashboard({ data }: Props) {
  // Cash Calculation
  const cashIn = data.ledger.filter(t => t.type === 'In').reduce((sum, t) => sum + t.amount, 0);
  const cashOut = data.ledger.filter(t => t.type === 'Out').reduce((sum, t) => sum + t.amount, 0);
  const netCash = data.openingBalances.cashOnHand + cashIn - cashOut;

  // Inventory Calculation (The Zero Bug Fix)
  // Net Inventory = Opening + RawIn - ProcessingWastage - DispatchedOrders
  const rawIn = data.saltBatches.filter(b => b.type === 'Raw').reduce((sum, b) => sum + b.quantityIn, 0);
  const processedYield = data.processingLogs.reduce((sum, l) => sum + l.processedYieldTons, 0);
  const processingRawConsumed = data.processingLogs.reduce((sum, l) => sum + l.rawConsumedTons, 0);
  
  const dispatchedOrders = data.orders
    .filter(o => o.status === 'Dispatched' || o.status === 'Delivered')
    .reduce((sum, o) => sum + o.quantityTons, 0);

  const netRawSalt = data.openingBalances.rawSaltTons + rawIn - processingRawConsumed;
  const netProcessedSalt = data.openingBalances.processedSaltTons + processedYield - dispatchedOrders;
  const totalSalt = netRawSalt + netProcessedSalt;

  // Receivables / Payables Approximation
  // Note: For a real AR/AP we'd look at invoices, but let's derive it from orders/expenses for now if needed.
  // Actually, we can keep the AR/AP explicit or derive them from specific ledger entries.
  // For now, let's look at total order value vs advance received.
  const totalReceivables = data.orders.reduce((sum, o) => sum + (o.totalAmount - o.advanceReceived), 0);
  
  const formatPKR = (num: number) => 
    new Intl.NumberFormat('en-PK', { style: 'currency', currency: 'PKR', maximumFractionDigits: 0 }).format(num);

  return (
    <div className="space-y-6">
      {/* Overview Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        
        {/* Cash Card */}
        <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-100 flex flex-col justify-between">
          <div className="flex justify-between items-start">
            <div>
              <p className="text-sm font-medium text-slate-500 mb-1">Liquid Cash</p>
              <h3 className="text-2xl font-bold text-slate-800">{formatPKR(netCash)}</h3>
            </div>
            <div className="w-10 h-10 rounded-full bg-emerald-50 flex items-center justify-center text-emerald-600">
              <DollarSign className="w-5 h-5" />
            </div>
          </div>
          <div className="mt-4 flex items-center text-xs font-medium text-slate-500">
            <span>Opening: {formatPKR(data.openingBalances.cashOnHand)}</span>
          </div>
        </div>

        {/* Inventory Card */}
        <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-100 flex flex-col justify-between">
          <div className="flex justify-between items-start">
            <div>
              <p className="text-sm font-medium text-slate-500 mb-1">Total Salt Inventory</p>
              <h3 className="text-2xl font-bold text-slate-800">
                {totalSalt.toLocaleString()} <span className="text-sm font-medium text-slate-500">Tons</span>
              </h3>
            </div>
            <div className="w-10 h-10 rounded-full bg-blue-50 flex items-center justify-center text-blue-600">
              <Package className="w-5 h-5" />
            </div>
          </div>
          <div className="mt-4 flex items-center gap-4 text-xs font-medium text-slate-500">
            <span className="flex items-center gap-1">
              <span className="w-2 h-2 rounded-full bg-slate-300"></span>
              Raw: {netRawSalt.toLocaleString()}t
            </span>
            <span className="flex items-center gap-1">
              <span className="w-2 h-2 rounded-full bg-blue-400"></span>
              Proc: {netProcessedSalt.toLocaleString()}t
            </span>
          </div>
        </div>

        {/* Accounts Receivable */}
        <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-100 flex flex-col justify-between">
          <div className="flex justify-between items-start">
            <div>
              <p className="text-sm font-medium text-slate-500 mb-1">Active Receivables (A/R)</p>
              <h3 className="text-2xl font-bold text-slate-800">{formatPKR(totalReceivables)}</h3>
            </div>
            <div className="w-10 h-10 rounded-full bg-indigo-50 flex items-center justify-center text-indigo-600">
              <Users className="w-5 h-5" />
            </div>
          </div>
          <div className="mt-4 flex items-center text-xs font-medium text-slate-500">
            <span>Pending from orders</span>
          </div>
        </div>

        {/* Dispatches */}
        <div className="bg-white rounded-2xl p-6 shadow-sm border border-slate-100 flex flex-col justify-between">
          <div className="flex justify-between items-start">
            <div>
              <p className="text-sm font-medium text-slate-500 mb-1">Total Dispatched</p>
              <h3 className="text-2xl font-bold text-slate-800">
                {dispatchedOrders.toLocaleString()} <span className="text-sm font-medium text-slate-500">Tons</span>
              </h3>
            </div>
            <div className="w-10 h-10 rounded-full bg-orange-50 flex items-center justify-center text-orange-600">
              <TrendingUp className="w-5 h-5" />
            </div>
          </div>
          <div className="mt-4 flex items-center text-xs font-medium text-slate-500">
            <span>Lifetime fulfillment</span>
          </div>
        </div>

      </div>

      {/* Main Content Areas */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        
        {/* Recent Ledger Entries */}
        <div className="bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="px-6 py-5 border-b border-slate-100 flex justify-between items-center bg-slate-50/50">
            <h3 className="font-bold text-slate-800">Recent Cash Flow</h3>
          </div>
          <div className="p-0">
            {data.ledger.length === 0 ? (
              <div className="p-8 text-center text-sm text-slate-500">No transactions recorded yet.</div>
            ) : (
              <div className="divide-y divide-slate-100">
                {data.ledger.slice(-5).reverse().map(txn => (
                  <div key={txn.id} className="p-4 px-6 flex justify-between items-center hover:bg-slate-50 transition">
                    <div className="flex items-center gap-3">
                      <div className={`w-8 h-8 rounded-full flex items-center justify-center shrink-0 ${txn.type === 'In' ? 'bg-emerald-50 text-emerald-600' : 'bg-rose-50 text-rose-600'}`}>
                        {txn.type === 'In' ? <ArrowDownRight className="w-4 h-4" /> : <ArrowUpRight className="w-4 h-4" />}
                      </div>
                      <div>
                        <p className="font-medium text-slate-800 text-sm">{txn.description}</p>
                        <p className="text-xs text-slate-500">{new Date(txn.date).toLocaleDateString()} &middot; {txn.category}</p>
                      </div>
                    </div>
                    <div className={`font-semibold text-sm ${txn.type === 'In' ? 'text-emerald-600' : 'text-rose-600'}`}>
                      {txn.type === 'In' ? '+' : '-'}{formatPKR(txn.amount)}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Active Orders */}
        <div className="bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="px-6 py-5 border-b border-slate-100 flex justify-between items-center bg-slate-50/50">
            <h3 className="font-bold text-slate-800">Pending Orders</h3>
          </div>
          <div className="p-0">
            {data.orders.filter(o => o.status === 'Pending' || o.status === 'Processing').length === 0 ? (
              <div className="p-8 text-center text-sm text-slate-500">No pending orders.</div>
            ) : (
              <div className="divide-y divide-slate-100">
                {data.orders.filter(o => o.status === 'Pending' || o.status === 'Processing').slice(-5).reverse().map(order => (
                  <div key={order.id} className="p-4 px-6 flex justify-between items-center hover:bg-slate-50 transition">
                    <div>
                      <p className="font-medium text-slate-800 text-sm">{order.customerName}</p>
                      <p className="text-xs text-slate-500">{order.quantityTons} Tons &middot; {order.saltType}</p>
                    </div>
                    <div className="text-right">
                      <span className="inline-flex items-center px-2 py-1 rounded text-[10px] font-semibold bg-amber-100 text-amber-700 uppercase tracking-wider mb-1">
                        {order.status}
                      </span>
                      <p className="text-sm font-semibold text-slate-800">{formatPKR(order.totalAmount)}</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

      </div>
    </div>
  );
}
