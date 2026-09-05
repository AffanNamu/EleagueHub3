export function BreakdownCard({ title, rows }: { title: string; rows: { label: string; count: number }[] }) {
  const total = rows.reduce((sum, row) => sum + row.count, 0);

  return (
    <div className="panel p-5">
      <h2 className="mb-4 font-display text-sm font-semibold text-ink-primary">{title}</h2>
      <div className="space-y-2.5">
        {rows.map((row) => {
          const pct = total > 0 ? (row.count / total) * 100 : 0;
          return (
            <div key={row.label}>
              <div className="mb-1 flex items-center justify-between text-sm">
                <span className="text-ink-secondary">{row.label}</span>
                <span className="text-ink-primary">{row.count}</span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-base-raised">
                <div className="h-full rounded-full bg-brand" style={{ width: `${pct}%` }} />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
