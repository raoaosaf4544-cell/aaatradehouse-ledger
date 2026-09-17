import React, { useState } from 'react';
import { X, Save } from 'lucide-react';
import { OpeningBalances } from '../types';

interface Props {
  isOpen: boolean;
  onClose: () => void;
  openingBalances: OpeningBalances;
  updateOpeningBalances: (b: Partial<OpeningBalances>) => void;
}

export default function OpeningBalancesModal({ isOpen, onClose, openingBalances, updateOpeningBalances }: Props) {
  const [cash, setCash] = useState(openingBalances.cashOnHand.toString());
  const [rawSalt, setRawSalt] = useState(openingBalances.rawSaltTons.toString());
  const [processedSalt, setProcessedSalt] = useState(openingBalances.processedSaltTons.toString());

  if (!isOpen) return null;

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault();
    updateOpeningBalances({
      cashOnHand: Number(cash),
      rawSaltTons: Number(rawSalt),
      processedSaltTons: Number(processedSalt),
    });
    onClose();
  };

  return (
    <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-sm flex items-center justify-center p-4 z-50">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-md overflow-hidden">
        <div className="px-6 py-4 border-b border-slate-100 flex justify-between items-center bg-slate-50">
          <h2 className="text-lg font-bold text-slate-800">Set Opening Balances</h2>
          <button onClick={onClose} className="p-2 text-slate-400 hover:text-slate-600 hover:bg-slate-200 rounded-full transition">
            <X className="w-5 h-5" />
          </button>
        </div>
        <form onSubmit={handleSave} className="p-6 space-y-5">
          
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-slate-700 mb-1">Cash on Hand (PKR)</label>
              <input 
                type="number" 
                required 
                value={cash}
                onChange={e => setCash(e.target.value)}
                className="w-full px-4 py-2 bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 focus:bg-white transition"
              />
            </div>
            
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-1">Raw Salt Stock (Tons)</label>
                <input 
                  type="number" 
                  required 
                  value={rawSalt}
                  onChange={e => setRawSalt(e.target.value)}
                  className="w-full px-4 py-2 bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 focus:bg-white transition"
                />
              </div>
              
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-1">Processed Stock (Tons)</label>
                <input 
                  type="number" 
                  required 
                  value={processedSalt}
                  onChange={e => setProcessedSalt(e.target.value)}
                  className="w-full px-4 py-2 bg-slate-50 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-blue-500 focus:bg-white transition"
                />
              </div>
            </div>
          </div>

          <div className="pt-2">
            <button 
              type="submit" 
              className="w-full bg-slate-900 text-white py-3 rounded-xl font-medium hover:bg-slate-800 transition flex items-center justify-center gap-2"
            >
              <Save className="w-4 h-4" />
              Save Opening Balances
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
