import React from 'react';
import { AppData } from '../types';

interface Props {
  data: AppData;
}

export default function Financials({ data }: Props) {
  const formatPKR = (num: number) => 
    new Intl.NumberFormat('en-PK', { style: 'currency', currency: 'PKR', maximumFractionDigits: 0 }).format(num);

  // Revenue: Only count orders that are processing, dispatched, or delivered
  const totalRevenue = data.orders
    .filter(o => o.status !== 'Cancelled' && o.status !== 'Pending')
    .reduce((sum, o) => sum + o.totalAmount, 0);

  // Investment / Costs
  // 1. Landed Cost (Material + Inbound Freight) from salt batches
  const totalLandedCost = data.saltBatches.reduce((sum, b) => sum + (b.materialCost || 0) + (b.freightCost || 0), 0);
  
  // 2. Operating Expenses
  const totalOperatingExpenses = data.expenses.reduce((sum, e) => sum + e.amount, 0);
  
  const totalInvestment = totalLandedCost + totalOperatingExpenses;
  const netProfit = totalRevenue - totalInvestment;
  
  // ROI Calculation: (Net Profit / Total Investment) * 100
  const roi = totalInvestment > 0 ? (netProfit / totalInvestment) * 100 : 0;
  const netMargin = totalRevenue > 0 ? (netProfit / totalRevenue) * 100 : 0;

  return (
    <div className="max-w-4xl mx-auto space-y-6">
      <div className="bg-white p-6 sm:p-8 rounded-2xl shadow-sm border border-slate-100">
        <h2 className="text-xl font-bold text-slate-800 mb-6">Financial Summary (P&L & ROI)</h2>
        
        <div className="space-y-4">
          <div className="flex justify-between items-center py-3 border-b border-slate-100">
            <span className="text-slate-600 font-medium">Active Booked Revenue <span className="text-xs text-slate-400 font-normal">(Excl. Pending/Cancelled)</span></span>
            <span className="font-semibold text-slate-900">{formatPKR(totalRevenue)}</span>
          </div>
          
          <div className="flex justify-between items-center py-3 border-b border-slate-100 pl-4">
            <span className="text-slate-500 text-sm">Less: Total Landed Cost (Material + Freight)</span>
            <span className="text-rose-600 text-sm">-{formatPKR(totalLandedCost)}</span>
          </div>
          
          <div className="flex justify-between items-center py-3 border-b border-slate-100 pl-4">
            <span className="text-slate-500 text-sm">Less: Total Operating Expenses</span>
            <span className="text-rose-600 text-sm">-{formatPKR(totalOperatingExpenses)}</span>
          </div>

          <div className="flex justify-between items-center py-3 bg-slate-50 px-4 rounded-lg mt-2">
            <span className="font-bold text-slate-900">Net Profit</span>
            <span className={`font-bold text-lg ${netProfit >= 0 ? 'text-emerald-600' : 'text-rose-600'}`}>
              {formatPKR(netProfit)}
            </span>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-4 mt-8">
          <div className="p-4 bg-indigo-50 rounded-xl border border-indigo-100 text-center">
            <p className="text-sm font-semibold text-indigo-800 mb-1">Return on Investment (ROI)</p>
            <p className={`text-3xl font-bold ${roi >= 0 ? 'text-emerald-600' : 'text-rose-600'}`}>
              {roi > 0 ? '+' : ''}{roi.toFixed(1)}%
            </p>
            <p className="text-[10px] text-indigo-600 mt-2 uppercase tracking-wide">Net Profit / Total Investment</p>
          </div>
          <div className="p-4 bg-slate-50 rounded-xl border border-slate-100 text-center">
            <p className="text-sm font-semibold text-slate-600 mb-1">Net Margin</p>
            <p className={`text-3xl font-bold ${netMargin >= 0 ? 'text-emerald-600' : 'text-rose-600'}`}>
              {netMargin.toFixed(1)}%
            </p>
            <p className="text-[10px] text-slate-500 mt-2 uppercase tracking-wide">Net Profit / Revenue</p>
          </div>
        </div>
      </div>
    </div>
  );
}
