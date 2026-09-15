import type { Metadata } from 'next';
import Script from 'next/script';
import './globals.css';
import { ClientThemeProvider } from '@/components/providers/ClientThemeProvider';

export const metadata: Metadata = {
  title: 'eSportlyic Web',
  description: 'Manage your leagues like a pro.',
  // AdSense site verification looks for this tag in the raw server-rendered
  // <head>. The adsbygoogle <Script> below uses strategy="afterInteractive",
  // which Next.js injects client-side AFTER hydration — it's never present
  // in the HTML a verification fetch sees. This meta tag is Next.js
  // Metadata API output, so it's always in the initial SSR'd HTML.
  other: {
    'google-adsense-account': 'ca-pub-9284565371998347',
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    // suppressHydrationWarning stops Next.js from complaining about the theme switch,
    // and className="dark" guarantees it loads in Dark Mode by default!
    <html lang="en" className="dark" suppressHydrationWarning>
      <body className="font-sans antialiased">
        <Script
          async
          src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=ca-pub-9284565371998347"
          crossOrigin="anonymous"
          strategy="afterInteractive"
        />
        <ClientThemeProvider>
          {children}
        </ClientThemeProvider>
      </body>
    </html>
  );
}
