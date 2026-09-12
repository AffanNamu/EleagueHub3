import { Mail, ArrowLeft } from 'lucide-react';
import Link from 'next/link';

// Shared layout primitives for the legal pages, mirroring the _H/_SubH/_P/_B
// building blocks used by every screen in lib/features/legal/*.dart —
// same structure, same reading order, so the legal text renders with the
// same section hierarchy on both platforms.

export function LegalPage({ title, subtitle, children }: { title: string; subtitle: string; children: React.ReactNode }) {
  return (
    <div className="max-w-3xl mx-auto pb-20 px-4 sm:px-6">
      <Link href="/settings" className="inline-flex items-center gap-2 text-sm font-bold text-gray-400 hover:text-white mb-6 transition-colors">
        <ArrowLeft className="w-4 h-4" /> Back to Settings
      </Link>
      <div className="bg-[#0B1221] border border-[#1E293B] rounded-3xl p-6 sm:p-8 shadow-xl">
        <h1 className="text-2xl font-black text-white">{title}</h1>
        <p className="text-sm font-semibold text-gray-500 mt-1.5">{subtitle}</p>
        <div className="h-px bg-[#1E293B] my-5" />
        {children}
      </div>
    </div>
  );
}

export function H({ children }: { children: React.ReactNode }) {
  return <h2 className="text-base font-black text-[#BEF264] mt-6 mb-2 first:mt-0">{children}</h2>;
}

export function SubH({ children }: { children: React.ReactNode }) {
  return <h3 className="text-sm font-extrabold text-white mt-3 mb-1.5">{children}</h3>;
}

export function P({ children }: { children: React.ReactNode }) {
  return <p className="text-sm text-gray-300 leading-relaxed mb-2.5">{children}</p>;
}

export function B({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-start gap-2.5 mb-2 pl-1">
      <span className="w-1.5 h-1.5 rounded-full bg-[#BEF264] mt-2 shrink-0" />
      <span className="text-sm text-gray-300 leading-relaxed">{children}</span>
    </div>
  );
}

export function EmailLink({ email }: { email: string }) {
  return (
    <a href={`mailto:${email}`} className="inline-flex items-center gap-2 text-sm font-bold text-[#BEF264] hover:underline mb-2.5">
      <Mail className="w-4 h-4" /> {email}
    </a>
  );
}
