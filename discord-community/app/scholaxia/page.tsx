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
  const body = JSON.stringify({ userId, name: userName });

  const localRes = await fetch('/community/stream-token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body,
  });
  const localData = await localRes.json().catch(() => ({}));
  if (localRes.ok) return localData;

  throw new Error(
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
  const embedded = searchParams.get('embed') === '1';

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
      <div className={`flex flex-col bg-[#313338] text-white ${embedded ? 'h-full' : 'h-screen'}`}>
        {!embedded && (
          <div className='px-4 py-2 bg-[#1e1f22] border-b border-black/20'>
            <a href='/app.html' className='text-sm text-[#5865f2] hover:underline'>
              ← Back to Scholaxia
            </a>
          </div>
        )}
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
      <div className={`flex flex-col bg-[#313338] ${embedded ? 'h-full' : 'h-screen'}`}>
        {!embedded && (
          <div className='px-4 py-2 bg-[#1e1f22] border-b border-black/20'>
            <a href='/app.html' className='text-sm text-[#5865f2] hover:underline'>
              ← Back to Scholaxia
            </a>
          </div>
        )}
        <div className='flex flex-1 items-center justify-center'>
          <LoadingIndicator />
        </div>
      </div>
    );
  }

  return (
    <div className={`flex flex-col ${embedded ? 'h-full' : 'h-screen'}`}>
      {!embedded && (
        <div className='px-4 py-2 bg-[#1e1f22] border-b border-black/20 shrink-0'>
          <a href='/app.html' className='text-sm text-[#5865f2] hover:underline'>
            ← Back to Scholaxia
          </a>
        </div>
      )}
      <div className='flex-1 min-h-0'>
        <EmbedModeProvider embedded={embedded}>
          <MyChat {...state} embedded={embedded} />
        </EmbedModeProvider>
      </div>
    </div>
  );
}

export default function ScholaxiaEmbedPage() {
  return (
    <Suspense
      fallback={
        <div className='flex h-full min-h-[200px] items-center justify-center bg-[#313338]'>
          <LoadingIndicator />
        </div>
      }
    >
      <ScholaxiaEmbedInner />
    </Suspense>
  );
}
