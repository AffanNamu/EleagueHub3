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
    <html lang="en" suppressHydrationWarning>
      <body className="font-sans antialiased text-white">
        <ClientThemeProvider>
          {children}
        </ClientThemeProvider>
      </body>
    </html>
  );
}
