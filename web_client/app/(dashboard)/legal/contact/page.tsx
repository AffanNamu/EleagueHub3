'use client';

import { useState } from 'react';
import Link from 'next/link';
import { ArrowLeft, Mail, Phone, Copy, LifeBuoy, Check } from 'lucide-react';

// Mirrors lib/features/legal/contact_screen.dart.
const SUPPORT_EMAIL = 'NASSARACORETECHVENTURES@GMAIL.COM';
const WHATSAPP_PHONE = '+2347066900063';

const MAILTO_HREF = `mailto:${SUPPORT_EMAIL}?subject=${encodeURIComponent('esportlyic Support Request')}&body=${encodeURIComponent(
  'Hello Support,\n\nPlease describe your issue and include:\n- What you were trying to do\n- Any error message you saw\n- Your device model and OS version\n\nThanks,\n',
)}`;

export default function ContactPage() {
  const [copied, setCopied] = useState(false);

  const handleCopyEmail = async () => {
    try {
      await navigator.clipboard.writeText(SUPPORT_EMAIL);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {}
  };

  return (
    <div className="max-w-2xl mx-auto pb-20 px-4 sm:px-6">
      <Link href="/settings" className="inline-flex items-center gap-2 text-sm font-bold text-gray-400 hover:text-white mb-6 transition-colors">
        <ArrowLeft className="w-4 h-4" /> Back to Settings
      </Link>

      <h1 className="text-2xl font-black text-white">Support</h1>
      <p className="text-sm text-gray-400 mt-2 leading-relaxed">
        If you need help with your account, leagues, payments, or marketplace links, contact us and we&apos;ll respond
        as soon as possible.
      </p>

      <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-4 mt-5">
        <div className="flex items-center gap-3">
          <Mail className="w-5 h-5 text-[#BEF264] shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-black text-white">Email</p>
            <p className="text-xs font-semibold text-gray-500 truncate">{SUPPORT_EMAIL}</p>
          </div>
          <button onClick={handleCopyEmail} className="p-2 text-gray-500 hover:text-white transition-colors" title="Copy">
            {copied ? <Check className="w-4 h-4 text-[#BEF264]" /> : <Copy className="w-4 h-4" />}
          </button>
        </div>
        <div className="h-px bg-[#1E293B] my-3" />
        <div className="flex items-center gap-3">
          <Phone className="w-5 h-5 text-[#BEF264] shrink-0" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-black text-white">WhatsApp Phone No</p>
            <p className="text-xs font-semibold text-gray-500">{WHATSAPP_PHONE}</p>
          </div>
        </div>
      </div>

      <a
        href={MAILTO_HREF}
        className="mt-5 w-full py-3 bg-[#BEF264] text-[#0F172A] font-black rounded-xl hover:brightness-110 transition-all flex items-center justify-center gap-2"
      >
        <LifeBuoy className="w-5 h-5" /> Contact Support
      </a>

      <p className="text-xs text-gray-500 mt-3 leading-relaxed">
        Tip: For faster support, include screenshots and the steps to reproduce the issue.
      </p>
    </div>
  );
}
