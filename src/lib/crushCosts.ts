/** Rs per kg of crushed salt = (rock cost used + plant cost) / good kg out. */
export const costPerKg = (poolPaisa: number, outGrams: number) => (outGrams > 0 ? poolPaisa / 100 / (outGrams / 1000) : 0)
