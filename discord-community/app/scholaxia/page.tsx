'use client';

import { Suspense, useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { User } from 'stream-chat';
import { EmbedModeProvider } from '@/contexts/EmbedModeContext';
import MyChat from '@/components/MyChat';
import { LoadingIndicator } from 'stream-chat-react';

const STREAM_API_KEY = '7cu55d72xtjs';

type Homestate = {
  apiKey: string;
  user: User;
  token: string;
};

async function fetchStreamToken(userId: string, userName: string) {
  const basePath = process.env.NEXT_PUBLIC_BASE_PATH || '/discord-app';
  const body = JSON.stringify({ userId, name: userName });

  const apiRes = await fetch(`${basePath}/api/scholaxia-token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  const apiData = await apiRes.json().catch(() => ({}));
  if (apiRes.ok) return apiData;

  const localRes = await fetch('/community/stream-token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  const localData = await localRes.json().catch(() => ({}));
  if (localRes.ok) return localData;

  throw new Error(
    apiData.error ||
      localData.error ||
      'Add STREAM_CHAT_SECRET to scholaxia-desktop/stream.env and restart Scholaxia.'
  );
}

function ScholaxiaEmbedInner() {
  const searchParams = useSearchParams();
  const [state, setState] = useState<Homestate | undefined>(undefined);
  const [error, setError] = useState<string | null>(null);

  const userId = searchParams.get('userId') || '';
  const userName = searchParams.get('name') || 'Student';

  useEffect(() => {
    if (!userId) {
      setError('Missing Scholaxia user id.');
      return;
    }

    fetchStreamToken(userId, userName)
      .then((data) => {
        if (!data.token) {
          throw new Error('No Stream token returned.');
        }
        const user: User = {
          id: userId,
          name: userName,
          image: `https://getstream.io/random_png/?id=${userId}&name=${encodeURIComponent(userName)}`,
        };
        setState({
          apiKey: data.apiKey || STREAM_API_KEY,
          user,
          token: data.token,
        });
      })
      .catch((err) => {
        setError(err.message || 'Connection failed.');
      });
  }, [userId, userName]);

  if (error) {
    return (
      <div className='flex h-full flex-col bg-[#313338] text-white'>
        <div className='flex flex-1 items-center justify-center p-6 text-center'>
          <div>
            <h1 className='text-lg font-bold mb-2'>Community unavailable</h1>
            <p className='text-gray-300 text-sm'>{error}</p>
            <p className='text-xs text-gray-400 mt-3'>
              Add STREAM_CHAT_SECRET to scholaxia-desktop/stream.env and restart Scholaxia.
            </p>
          </div>
        </div>
      </div>
    );
  }

  if (!state) {
    return (
      <div className='flex h-full flex-col bg-[#313338]'>
        <div className='flex flex-1 items-center justify-center'>
          <LoadingIndicator />
        </div>
      </div>
    );
  }

  return (
    <div className='flex h-full flex-col'>
      <div className='flex-1 min-h-0'>
        <MyChat {...state} embedded={true} />
      </div>
    </div>
  );
}

export default function ScholaxiaEmbedPage() {
  return (
    <EmbedModeProvider embedded={true}>
      <Suspense
        fallback={
          <div className='flex h-full min-h-[200px] items-center justify-center bg-[#313338]'>
            <LoadingIndicator />
          </div>
        }
      >
        <ScholaxiaEmbedInner />
      </Suspense>
    </EmbedModeProvider>
  );
}
