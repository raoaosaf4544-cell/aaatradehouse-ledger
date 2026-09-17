import { useState, useEffect } from 'react';
import { AppData, defaultAppData } from '../types';

const STORAGE_KEY = 'aaa_trade_house_ledger';

export function useAppStore() {
  const [data, setData] = useState<AppData>(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        return JSON.parse(stored);
      }
    } catch (error) {
      console.error('Failed to parse local storage', error);
    }
    return defaultAppData;
  });

  const [isLoaded, setIsLoaded] = useState(false);

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  }, [data]);

  useEffect(() => {
    setIsLoaded(true);
  }, []);

  const updateData = (newData: Partial<AppData>) => {
    setData((prev) => ({ ...prev, ...newData }));
  };

  const updateOpeningBalances = (balances: Partial<AppData['openingBalances']>) => {
    setData((prev) => ({
      ...prev,
      openingBalances: { ...prev.openingBalances, ...balances, lastUpdated: new Date().toISOString() },
    }));
  };

  const resetData = () => {
    if (confirm("Are you sure you want to reset all data to the Master Ledger Baseline? All current unsaved work will be replaced.")) {
      setData(defaultAppData);
      localStorage.setItem(STORAGE_KEY, JSON.stringify(defaultAppData));
    }
  };

  return { data, updateData, updateOpeningBalances, resetData, isLoaded };
}
