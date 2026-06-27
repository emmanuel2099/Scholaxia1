'use client';

import { useEmbedMode } from '@/contexts/EmbedModeContext';

/** Stay on /scholaxia when embedded — never navigate to Clerk home (/). */
export function useScholaxiaPath(query?: Record<string, string | undefined>) {
  const embedded = useEmbedMode();
  const basePath = process.env.NEXT_PUBLIC_BASE_PATH || '/discord-app';

  if (embedded && typeof window !== 'undefined') {
    const url = new URL(window.location.href);
    url.searchParams.set('embed', '1');
    [
      'createServer',
      'createChannel',
      'category',
      'isVoice',
      'serverName',
    ].forEach((key) => url.searchParams.delete(key));
    if (query) {
      Object.entries(query).forEach(([key, value]) => {
        if (value !== undefined) url.searchParams.set(key, value);
      });
    }
    return `${url.pathname}?${url.searchParams.toString()}`;
  }

  const params = new URLSearchParams();
  if (query) {
    Object.entries(query).forEach(([key, value]) => {
      if (value !== undefined) params.set(key, value);
    });
  }
  const qs = params.toString();
  return qs ? `${basePath}/?${qs}` : `${basePath}/`;
}
