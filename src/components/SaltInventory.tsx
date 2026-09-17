import React, { useState } from 'react';
import { Plus, Boxes, Trash2 } from 'lucide-react';
import { AppData, SaltBatch, ProcessingLog, LedgerTransaction } from '../types';

interface Props {
  data: AppData;
  updateData: (newData: Partial<AppData>) => void;
}

export default function SaltInventory({ data, updateData }: Props) {
  const [showInboundForm, setShowInboundForm] = useState(false);
  const [showProcessForm, setShowProcessForm] = useState(false);
  
  const [inboundData, setInboundData] = useState<Partial<SaltBatch>>({
    date: new Date().toISOString().split('T')[0],
    batchRef: '',
    type: 'Raw',
    quantityIn: 0,
    source: '',
    materialCost: 0,
    freightCost: 0
  });

  const [processData, setProcessData] = useState<Partial<ProcessingLog>>({
    date: new Date().toISOString().split('T')[0],
    batchRef: '',
    rawConsumedTons: 0,
    processedYieldTons: 0,
  });

  const handleAddInbound = (e: React.FormEvent) => {
    e.preventDefault();
    const newBatch: SaltBatch = {
      id: `BATCH-${Date.now()}`,
      date: inboundData.date!,
      batchRef: inboundData.batchRef || `B-${Math.floor(Math.random() * 10000)}`,
      type: inboundData.type as 'Raw' | 'Processed',
      quantityIn: Number(inboundData.quantityIn),
      source: inboundData.source!,
      materialCost: Number(inboundData.materialCost || 0),
      freightCost: Number(inboundData.freightCost || 0)
    };
    
    // Total out of pocket
    const totalCost = (newBatch.materialCost || 0) + (newBatch.freightCost || 0);

    let newLedger = [...data.ledger];
    if (totalCost > 0) {
      newLedger.push({
        id: `TXN-PURCHASE-${Date.now()}`,
        date: newBatch.date,
        type: 'Out',
        category: 'Purchase',
        description: `Material + Freight for ${newBatch.batchRef} (${newBatch.quantityIn}t)`,
        amount: totalCost,
        partyName: newBatch.source
      });
    }

    updateData({ saltBatches: [...data.saltBatches, newBatch], ledger: newLedger });
    setShowInboundForm(false);
    setInboundData({ ...inboundData, quantityIn: 0, batchRef: '', source: '', materialCost: 0, freightCost: 0 });
  };

  const handleProcessBatch = (e: React.FormEvent) => {
    e.preventDefault();
    const consumed = Number(processData.rawConsumedTons);
    const yieldTons = Number(processData.processedYieldTons);
    
    const newLog: ProcessingLog = {
      id: `PROC-${Date.now()}`,
      date: processData.date!,
      batchRef: processData.batchRef!,
      rawConsumedTons: consumed,
      processedYieldTons: yieldTons,
      wastageTons: consumed - yieldTons,
    };
    
    updateData({ processingLogs: [...data.processingLogs, newLog] });
    setShowProcessForm(false);
    setProcessData({ ...processData, rawConsumedTons: 0, processedYieldTons: 0, batchRef: '' });
  };

  const deleteBatch = (id: string) => {
    if (!confirm('Delete this batch record?')) return;
    updateData({ saltBatches: data.saltBatches.filter(b => b.id !== id) });
  };

  const deleteProcessLog = (id: string) => {
    if (!confirm('Delete this processing log?')) return;
    updateData({ processingLogs: data.processingLogs.filter(p => p.id !== id) });
  };

  // Inventory Math
  const rawIn = data.saltBatches.filter(b => b.type === 'Raw').reduce((sum, b) => sum + b.quantityIn, 0);
  const processedIn = data.saltBatches.filter(b => b.type === 'Processed').reduce((sum, b) => sum + b.quantityIn, 0);
  const processedYield = data.processingLogs.reduce((sum, l) => sum + l.processedYieldTons, 0);
  const processingRawConsumed = data.processingLogs.reduce((sum, l) => sum + l.rawConsumedTons, 0);
  
  const dispatchedOrders = data.orders
    .filter(o => o.status === 'Dispatched' || o.status === 'Delivered')
    .reduce((sum, o) => sum + o.quantityTons, 0);

  const netRawSalt = data.openingBalances.rawSaltTons + rawIn - processingRawConsumed;
  const netProcessedSalt = data.openingBalances.processedSaltTons + processedYield + processedIn - dispatchedOrders;

  const formatPKR = (num: number) => new Intl.NumberFormat('en-PK', { style: 'currency', currency: 'PKR', maximumFractionDigits: 0 }).format(num);

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="bg-white p-6 rounded-2xl shadow-sm border border-slate-100 flex flex-col justify-between">
          <div>
            <p className="text-sm font-medium text-slate-500 mb-1">Raw Salt Stock</p>
            <h3 className="text-3xl font-bold text-slate-800">
              {netRawSalt.toLocaleString()} <span className="text-sm font-normal text-slate-500">Tons</span>
            </h3>
          </div>
          <div className="mt-4 pt-4 border-t border-slate-100 flex justify-between text-xs text-slate-500">
            <span>Opening: {data.openingBalances.rawSaltTons}t</span>
            <span>Consumed: {processingRawConsumed}t</span>
          </div>
        </div>
        
        <div className="bg-white p-6 rounded-2xl shadow-sm border border-slate-100 flex flex-col justify-between">
          <div>
            <p className="text-sm font-medium text-slate-500 mb-1">Processed Salt Stock</p>
            <h3 className="text-3xl font-bold text-slate-800">
              {netProcessedSalt.toLocaleString()} <span className="text-sm font-normal text-slate-500">Tons</span>
            </h3>
          </div>
          <div className="mt-4 pt-4 border-t border-slate-100 flex justify-between text-xs text-slate-500">
            <span>Opening: {data.openingBalances.processedSaltTons}t</span>
            <span>Dispatched: {dispatchedOrders}t</span>
          </div>
        </div>
      </div>

      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 bg-white p-4 sm:p-6 rounded-2xl shadow-sm border border-slate-100">
        <div>
          <h2 className="text-xl font-bold text-slate-800">Inventory Management</h2>
          <p className="text-slate-500 text-sm mt-1">Log inbound batches and processing yield</p>
        </div>
        <div className="flex gap-2 w-full sm:w-auto">
          <button 
            onClick={() => { setShowProcessForm(!showProcessForm); setShowInboundForm(false); }}
            className="flex-1 sm:flex-none bg-orange-100 text-orange-700 px-4 py-2 rounded-lg text-sm font-medium hover:bg-orange-200 transition flex items-center justify-center gap-2"
          >
            <Boxes className="w-4 h-4" />
            {showProcessForm ? 'Cancel' : 'Process Batch'}
          </button>
          <button 
            onClick={() => { setShowInboundForm(!showInboundForm); setShowProcessForm(false); }}
            className="flex-1 sm:flex-none bg-indigo-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-indigo-700 transition flex items-center justify-center gap-2"
          >
            <Plus className="w-4 h-4" />
            {showInboundForm ? 'Cancel' : 'Inbound Stock'}
          </button>
        </div>
      </div>

      {/* Modal overlays instead of inline forms */}
      {showProcessForm && (
        <div className="fixed inset-0 bg-slate-900/50 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
            <div className="p-6 border-b border-slate-100 flex justify-between items-center bg-orange-50 rounded-t-2xl">
              <h3 className="text-lg font-bold text-orange-800 flex items-center gap-2"><Boxes className="w-5 h-5"/> Process Raw Batch</h3>
              <button onClick={() => setShowProcessForm(false)} className="text-slate-500 hover:text-slate-700 font-bold">&times;</button>
            </div>
            <form onSubmit={handleProcessBatch} className="p-6 grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Date</label>
                <input type="date" required value={processData.date} onChange={e => setProcessData({...processData, date: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-orange-500" />
              </div>
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Batch Ref / Detail</label>
                <input type="text" required placeholder="e.g. BATCH-001" value={processData.batchRef} onChange={e => setProcessData({...processData, batchRef: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-orange-500" />
              </div>
              <div>
                <label className="block text-sm font-semibold text-rose-700 mb-1">Raw Consumed (Tons)</label>
                <input type="number" required min="1" value={processData.rawConsumedTons || ''} onChange={e => setProcessData({...processData, rawConsumedTons: Number(e.target.value)})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-rose-200 focus:outline-none focus:ring-2 focus:ring-rose-500" />
              </div>
              <div>
                <label className="block text-sm font-semibold text-emerald-700 mb-1">Processed Yield (Tons)</label>
                <input type="number" required min="0" value={processData.processedYieldTons || ''} onChange={e => setProcessData({...processData, processedYieldTons: Number(e.target.value)})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-emerald-200 focus:outline-none focus:ring-2 focus:ring-emerald-500" />
                <p className="text-sm text-orange-600 mt-2 font-semibold">
                  Wastage (Auto-calculated): {(Number(processData.rawConsumedTons) - Number(processData.processedYieldTons)) || 0} Tons
                </p>
              </div>
              <div className="md:col-span-2 flex justify-end mt-4 pt-4 border-t border-slate-100">
                <button type="submit" className="bg-orange-600 text-white px-6 py-2.5 rounded-lg font-medium hover:bg-orange-700 transition">Save Processing Log</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {showInboundForm && (
        <div className="fixed inset-0 bg-slate-900/50 z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl w-full max-w-3xl max-h-[90vh] overflow-y-auto">
            <div className="p-6 border-b border-slate-100 flex justify-between items-center bg-indigo-50 rounded-t-2xl">
              <h3 className="text-lg font-bold text-indigo-800 flex items-center gap-2"><Plus className="w-5 h-5"/> Receive Inbound Stock</h3>
              <button onClick={() => setShowInboundForm(false)} className="text-slate-500 hover:text-slate-700 font-bold">&times;</button>
            </div>
            <form onSubmit={handleAddInbound} className="p-6 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Date</label>
                <input type="date" required value={inboundData.date} onChange={e => setInboundData({...inboundData, date: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
              </div>
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Salt Type</label>
                <select value={inboundData.type} onChange={e => setInboundData({...inboundData, type: e.target.value as any})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500">
                  <option value="Raw">Raw Rock Salt</option>
                  <option value="Processed">Processed Salt</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Quantity (Tons)</label>
                <input type="number" required min="1" value={inboundData.quantityIn || ''} onChange={e => setInboundData({...inboundData, quantityIn: Number(e.target.value)})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-emerald-200 focus:outline-none focus:ring-2 focus:ring-emerald-500" />
              </div>
              
              <div className="md:col-span-2">
                <label className="block text-sm font-semibold text-slate-700 mb-1">Source / Mine Name</label>
                <input type="text" required placeholder="Supplier name or mine..." value={inboundData.source} onChange={e => setInboundData({...inboundData, source: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
              </div>
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Batch Ref</label>
                <input type="text" placeholder="B-1234 (Optional)" value={inboundData.batchRef} onChange={e => setInboundData({...inboundData, batchRef: e.target.value})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
              </div>

              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Material Cost (PKR)</label>
                <input type="number" min="0" value={inboundData.materialCost || ''} onChange={e => setInboundData({...inboundData, materialCost: Number(e.target.value)})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-indigo-200 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
              </div>
              <div>
                <label className="block text-sm font-semibold text-slate-700 mb-1">Freight Cost (PKR)</label>
                <input type="number" min="0" value={inboundData.freightCost || ''} onChange={e => setInboundData({...inboundData, freightCost: Number(e.target.value)})} className="w-full px-3 py-2 bg-slate-50 rounded-lg border border-indigo-200 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
              </div>
              
              <div className="flex flex-col justify-end">
                <div className="p-3 bg-slate-100 rounded-lg">
                  <p className="text-xs text-slate-500 mb-1">Landed Cost / Kg</p>
                  <p className="font-bold text-slate-800">
                    {inboundData.quantityIn 
                      ? formatPKR(((Number(inboundData.materialCost||0) + Number(inboundData.freightCost||0)) / (Number(inboundData.quantityIn) * 1000)))
                      : '0 PKR'}
                  </p>
                </div>
              </div>

              <div className="md:col-span-3 flex justify-end mt-4 pt-4 border-t border-slate-100">
                <button type="submit" className="bg-indigo-600 text-white px-6 py-2.5 rounded-lg font-medium hover:bg-indigo-700 transition">Save & Add to Inventory</button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Tables for Logs */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        
        {/* Inbound Batches Table */}
        <div className="bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="px-6 py-4 border-b border-slate-100 bg-slate-50">
            <h3 className="font-bold text-slate-800">Inbound Log</h3>
          </div>
          <div className="overflow-x-auto max-h-[400px]">
            <table className="w-full text-sm text-left">
              <thead className="text-xs text-slate-500 uppercase bg-white sticky top-0 border-b border-slate-100">
                <tr>
                  <th className="px-4 py-3 font-medium">Date</th>
                  <th className="px-4 py-3 font-medium">Ref / Source</th>
                  <th className="px-4 py-3 font-medium text-right">In (Tons)</th>
                  <th className="px-4 py-3 font-medium text-right">Cost/Kg</th>
                  <th className="px-2 py-3"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-50">
                {data.saltBatches.length === 0 && (
                  <tr><td colSpan={5} className="px-4 py-8 text-center text-slate-500">No inbound logs.</td></tr>
                )}
                {data.saltBatches.slice().reverse().map(b => (
                  <tr key={b.id} className="hover:bg-slate-50/50">
                    <td className="px-4 py-3 text-slate-600">{new Date(b.date).toLocaleDateString()}</td>
                    <td className="px-4 py-3">
                      <div className="font-medium text-slate-800">{b.batchRef} <span className="text-[10px] bg-slate-200 px-1.5 py-0.5 rounded ml-1">{b.type}</span></div>
                      <div className="text-xs text-slate-500">{b.source}</div>
                    </td>
                    <td className="px-4 py-3 text-right font-semibold text-emerald-600">
                      +{b.quantityIn}t
                    </td>
                    <td className="px-4 py-3 text-right text-slate-600 font-medium">
                      {formatPKR(((b.materialCost || 0) + (b.freightCost || 0)) / (b.quantityIn * 1000))}
                    </td>
                    <td className="px-2 py-3 text-right">
                      <button onClick={() => deleteBatch(b.id)} className="text-slate-400 hover:text-rose-600 transition"><Trash2 className="w-4 h-4"/></button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

        {/* Processing Logs Table */}
        <div className="bg-white rounded-2xl shadow-sm border border-slate-100 overflow-hidden">
          <div className="px-6 py-4 border-b border-slate-100 bg-slate-50">
            <h3 className="font-bold text-slate-800">Processing Yield Log</h3>
          </div>
          <div className="overflow-x-auto max-h-[400px]">
            <table className="w-full text-sm text-left">
              <thead className="text-xs text-slate-500 uppercase bg-white sticky top-0 border-b border-slate-100">
                <tr>
                  <th className="px-4 py-3 font-medium">Date</th>
                  <th className="px-4 py-3 font-medium">Batch</th>
                  <th className="px-4 py-3 font-medium text-right">Raw Used</th>
                  <th className="px-4 py-3 font-medium text-right">Yield</th>
                  <th className="px-2 py-3"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-50">
                {data.processingLogs.length === 0 && (
                  <tr><td colSpan={5} className="px-4 py-8 text-center text-slate-500">No processing logs.</td></tr>
                )}
                {data.processingLogs.slice().reverse().map(p => (
                  <tr key={p.id} className="hover:bg-slate-50/50">
                    <td className="px-4 py-3 text-slate-600">{new Date(p.date).toLocaleDateString()}</td>
                    <td className="px-4 py-3 font-medium text-slate-800">{p.batchRef}</td>
                    <td className="px-4 py-3 text-right font-medium text-rose-600">-{p.rawConsumedTons}t</td>
                    <td className="px-4 py-3 text-right font-medium text-emerald-600">+{p.processedYieldTons}t</td>
                    <td className="px-2 py-3 text-right">
                      <button onClick={() => deleteProcessLog(p.id)} className="text-slate-400 hover:text-rose-600 transition"><Trash2 className="w-4 h-4"/></button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>

      </div>
    </div>
  );
}
