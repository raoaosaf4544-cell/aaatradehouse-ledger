export type OrderStatus = 'Pending' | 'Processing' | 'Dispatched' | 'Delivered' | 'Cancelled';

export interface Order {
  id: string;
  date: string;
  customerName: string;
  saltType: string;
  quantityTons: number;
  ratePerTon: number;
  totalAmount: number;
  advanceReceived: number;
  status: OrderStatus;
  notes?: string;
}

export interface SaltBatch {
  id: string;
  date: string;
  batchRef: string;
  type: 'Raw' | 'Processed';
  quantityIn: number; // Incoming raw salt, or processed yield
  source: string; // e.g., 'Plant Khanewal' or 'Supplier X'
  materialCost?: number;
  freightCost?: number;
}

export interface ProcessingLog {
  id: string;
  date: string;
  batchRef: string;
  rawConsumedTons: number;
  processedYieldTons: number;
  wastageTons: number; // Derived: rawConsumed - processedYield
}

export interface LedgerTransaction {
  id: string;
  date: string;
  type: 'In' | 'Out';
  category: 'Sales' | 'Purchase' | 'Expense' | 'Opening Balance' | 'Other';
  description: string;
  amount: number;
  partyName?: string; // For AR/AP linkage
}

export interface Expense {
  id: string;
  date: string;
  category: 'Logistics' | 'Plant Ops' | 'Salaries' | 'Utilities' | 'Marketing' | 'Other';
  description: string;
  amount: number;
}

export interface OpeningBalances {
  cashOnHand: number;
  rawSaltTons: number;
  processedSaltTons: number;
  lastUpdated: string;
}

export interface AppData {
  openingBalances: OpeningBalances;
  orders: Order[];
  saltBatches: SaltBatch[];
  processingLogs: ProcessingLog[];
  ledger: LedgerTransaction[];
  expenses: Expense[];
}

export const defaultAppData: AppData = {
  openingBalances: {
    cashOnHand: 500000,
    rawSaltTons: 0,
    processedSaltTons: 0,
    lastUpdated: '2026-08-23T00:00:00.000Z',
  },
  orders: [],
  saltBatches: [
    {
      id: 'BATCH-001',
      date: '2026-08-23',
      batchRef: 'BATCH-001',
      type: 'Raw',
      quantityIn: 15.21,
      source: 'Plant Khanewal',
      materialCost: 114270,
    }
  ],
  processingLogs: [],
  ledger: [
    {
      id: 'TXN-101',
      date: '2026-08-23',
      type: 'Out',
      category: 'Purchase',
      description: 'Salt Batch BATCH-001 Rock (crush in-house) - 15,210 Kg',
      amount: 114270,
    },
    { id: 'TXN-102', date: '2026-08-24', type: 'Out', category: 'Expense', description: 'Utilities', amount: 5000 },
    { id: 'TXN-103', date: '2026-08-24', type: 'Out', category: 'Expense', description: 'Site Meals', amount: 2000 },
    { id: 'TXN-104', date: '2026-08-24', type: 'Out', category: 'Expense', description: 'Travel', amount: 1500 },
    { id: 'TXN-105', date: '2026-08-24', type: 'Out', category: 'Expense', description: 'Vehicle CapEx (new bike purchase and permits)', amount: 65000 },
    { id: 'TXN-106', date: '2026-08-24', type: 'Out', category: 'Expense', description: 'Labour advance - Qasim', amount: 10000 },
    { id: 'TXN-107', date: '2026-08-24', type: 'Out', category: 'Expense', description: 'Labour advance - Rafiq', amount: 10000 },
    { id: 'TXN-108', date: '2026-08-24', type: 'Out', category: 'Expense', description: 'Packaging materials (700 bags)', amount: 14000 }
  ],
  expenses: [
    { id: 'EXP-102', date: '2026-08-24', category: 'Utilities', description: 'Utilities', amount: 5000 },
    { id: 'EXP-103', date: '2026-08-24', category: 'Plant Ops', description: 'Site Meals', amount: 2000 },
    { id: 'EXP-104', date: '2026-08-24', category: 'Logistics', description: 'Travel', amount: 1500 },
    { id: 'EXP-105', date: '2026-08-24', category: 'Logistics', description: 'Vehicle CapEx (new bike purchase and permits)', amount: 65000 },
    { id: 'EXP-106', date: '2026-08-24', category: 'Salaries', description: 'Labour advance - Qasim', amount: 10000 },
    { id: 'EXP-107', date: '2026-08-24', category: 'Salaries', description: 'Labour advance - Rafiq', amount: 10000 },
    { id: 'EXP-108', date: '2026-08-24', category: 'Plant Ops', description: 'Packaging materials (700 bags)', amount: 14000 }
  ],
};
