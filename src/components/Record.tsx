import { BookUser, Hammer, Landmark, ShoppingCart, PackageOpen, ArrowRight } from 'lucide-react'

export default function Record({ go }: { go: (tab: string) => void }) {
  const actions = [
    {
      id: 'record-capital',
      title: 'Add Investment Money',
      desc: 'You or your father put money into the business. Cash goes up, capital goes up.',
      icon: Landmark,
      tone: 'from-emerald-500 to-emerald-600',
    },
    {
      id: 'record-purchase',
      title: 'Buy Inventory',
      desc: 'New salt arrives at the plant. Creates a fresh batch, records cost, pays cash or on credit.',
      icon: ShoppingCart,
      tone: 'from-indigo-500 to-indigo-600',
    },
    {
      id: 'record-crush',
      title: 'Crush Salt',
      grades: true,
      desc: 'Raw salt in, graded salt out. Enter weights and wastage — the engine prices every grade itself.',
      icon: Hammer,
      tone: 'from-amber-500 to-orange-500',
    },
    {
      id: 'record-sale',
      title: 'Sell Salt / Dispatch',
      desc: 'Bill a customer — cash now or udhaar — and the salt leaves stock at its exact batch cost, in one step.',
      icon: PackageOpen,
      tone: 'from-teal-500 to-emerald-600',
    },
    {
      id: 'record-moneyout',
      title: 'Record Money Out',
      desc: 'Labour, fuel, bills, meals — with a live preview of the exact journal lines before saving.',
      icon: BookUser,
      tone: 'from-slate-600 to-slate-700',
    },
  ] as const

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-bold text-slate-800">Record what happened</h2>
        <p className="mt-1 text-slate-500">
          Pick what happened today. The engine does all the accounting — you just tell it the facts.
        </p>
      </div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {actions.map((a) => (
          <button
            key={a.id}
            onClick={() => go(a.id)}
            className="group rounded-2xl border border-slate-200 bg-white p-6 text-left shadow-sm transition hover:-translate-y-0.5 hover:border-blue-300 hover:shadow-lg"
          >
            <div className="flex items-start gap-4">
              <div className={`flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br ${a.tone} text-white shadow`}>
                <a.icon className="h-6 w-6" />
              </div>
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <h3 className="text-lg font-bold text-slate-800">{a.title}</h3>
                  <ArrowRight className="h-4 w-4 text-slate-300 transition group-hover:translate-x-0.5 group-hover:text-blue-500" />
                </div>
                <p className="mt-1 text-sm leading-relaxed text-slate-500">{a.desc}</p>
              </div>
            </div>
            {'grades' in a && a.grades && (
              <div className="mt-3 inline-flex items-center rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-semibold text-amber-700">
                Engine prices grades automatically
              </div>
            )}
          </button>
        ))}
      </div>
    </div>
  )
}
