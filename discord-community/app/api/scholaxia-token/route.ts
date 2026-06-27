import { StreamChat } from 'stream-chat';
import { ensureScholaxiaChannel } from '@/lib/ensureScholaxiaChannel';

const STREAM_API_KEY = process.env.STREAM_API_KEY || '7cu55d72xtjs';

export async function POST(request: Request) {
  const secret = process.env.STREAM_CHAT_SECRET;
  if (!secret) {
    return Response.json(
      { error: 'STREAM_CHAT_SECRET is not set. Add it to scholaxia-desktop/stream.env' },
      { status: 503 }
    );
  }

  const body = await request.json();
  const userId = String(body?.userId || '').trim();
  const name = String(body?.name || 'Student').trim() || 'Student';

  if (!userId) {
    return Response.json({ error: 'userId required' }, { status: 400 });
  }

  const serverClient = StreamChat.getInstance(STREAM_API_KEY, secret);

  await serverClient.upsertUser({
    id: userId,
    name,
    role: 'user',
    image: `https://getstream.io/random_png/?id=${userId}&name=${encodeURIComponent(name)}`,
  });

  await ensureScholaxiaChannel(serverClient, userId);

  const token = serverClient.createToken(userId);

  return Response.json({ userId, token, apiKey: STREAM_API_KEY });
}
