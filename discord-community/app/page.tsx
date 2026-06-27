'use client';

import { LoadingIndicator } from 'stream-chat-react';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import HomeWithClerk from './HomeWithClerk';

const hasClerk =
  !!process.env.CLERK_SECRET_KEY && !!process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;

function RedirectToScholaxia() {
  const router = useRouter();
  const basePath = process.env.NEXT_PUBLIC_BASE_PATH || '/discord-app';

  useEffect(() => {
    router.replace(`${basePath}/scholaxia?embed=1`);
  }, [router, basePath]);

  return (
    <div className='flex h-screen items-center justify-center'>
      <LoadingIndicator />
    </div>
  );
}

export default function Home() {
  if (!hasClerk) {
    return <RedirectToScholaxia />;
  }
  return <HomeWithClerk />;
}
