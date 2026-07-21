import type { Metadata } from 'next';
import './globals.css';
import { ClientThemeProvider } from '@/components/providers/ClientThemeProvider';

export const metadata: Metadata = {
  title: 'eSportlyic Web',
  description: 'Manage your leagues like a pro.',
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
        <ClientThemeProvider>
          {children}
        </ClientThemeProvider>
      </body>
    </html>
  );
}
