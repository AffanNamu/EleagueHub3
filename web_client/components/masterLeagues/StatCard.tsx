'use client';

import { LucideIcon } from 'lucide-react';

export function StatCard({
  icon: Icon,
  label,
  value,
  tint = '#B8E928', // Defaults to your Brand Lime
}: {
  icon: LucideIcon;
  label: string;
  value: string | number;
  tint?: string;
}) {
  return (
    <div className="relative bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4 overflow-hidden group hover:border-[#2A3A52] transition-colors shadow-lg">
      <div
        className="absolute -top-8 -right-8 w-24 h-24 rounded-full blur-2xl opacity-[0.12] group-hover:opacity-20 transition-opacity"
        style={{ background: tint }}
      />
      <div className="relative flex items-center gap-3">
        <div
          className="w-11 h-11 rounded-xl flex items-center justify-center shrink-0 border"
          style={{
            background: `${tint}1A`,
            borderColor: `${tint}33`,
          }}
        >
          <Icon className="w-5 h-5" style={{ color: tint }} />
        </div>
        <div className="min-w-0">
          <p className="text-xl font-black text-white leading-tight truncate">{value}</p>
          <p className="text-[11px] font-bold uppercase tracking-wider text-gray-500 truncate">{label}</p>
        </div>
      </div>
    </div>
  );
}
