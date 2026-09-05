import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Nomad Operations Center',
  description: 'Internal operations platform for Nomad eSports.',
  robots: {
    index: false,
    follow: false,
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
