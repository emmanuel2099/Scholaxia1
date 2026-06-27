import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { DiscordContextProvider } from '@/contexts/DiscordContext';
import { ClerkProvider } from '@clerk/nextjs';

const inter = Inter({ subsets: ['latin'] });

const hasClerk =
  !!process.env.CLERK_SECRET_KEY && !!process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;

export const metadata: Metadata = {
  title: 'Discord Clone',
  description: 'Powered by Stream Chat',
};

function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <html lang='en'>
      <DiscordContextProvider>
        <body className={inter.className}>{children}</body>
      </DiscordContextProvider>
    </html>
  );
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  if (!hasClerk) {
    return <AppShell>{children}</AppShell>;
  }

  return (
    <ClerkProvider>
      <AppShell>{children}</AppShell>
    </ClerkProvider>
  );
}
