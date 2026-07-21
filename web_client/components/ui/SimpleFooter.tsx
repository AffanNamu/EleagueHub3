'use client';

import Link from 'next/link';
import { ShieldQuestion } from 'lucide-react';

export function SimpleFooter() {
  const year = new Date().getFullYear();
  
  return (
    <footer className="w-full py-8 px-6 border-t border-white/5 mt-20 relative z-10">
      <div className="max-w-7xl mx-auto flex flex-col md:flex-row items-center justify-between gap-4">
        <div className="flex items-center gap-2 text-slate-400 text-sm font-medium">
          <span className="text-brand-lime font-black tracking-tight">eSportlyic</span>
          <span>© {year}</span>
        </div>
        
        <div className="flex flex-wrap justify-center items-center gap-6 text-sm font-medium text-slate-500">
          <Link href="/privacy" className="hover:text-brand-lime transition-colors">Privacy</Link>
          <Link href="/terms" className="hover:text-brand-lime transition-colors">Terms</Link>
          <Link href="/contact" className="hover:text-brand-lime transition-colors">Contact</Link>
          <Link href="/support" className="flex items-center gap-1.5 hover:text-brand-lime transition-colors">
            <ShieldQuestion className="w-4 h-4" />
            Support
          </Link>
        </div>
      </div>
    </footer>
  );
}
