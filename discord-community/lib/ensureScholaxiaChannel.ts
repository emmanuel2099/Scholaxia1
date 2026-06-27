import { StreamChat } from 'stream-chat';
import {
  SCHOLAXIA_CHANNEL_ID,
  SCHOLAXIA_SERVER_NAME,
} from '@/types/discord';

export async function ensureScholaxiaChannel(
  serverClient: StreamChat,
  userId: string
) {
  const channel = serverClient.channel('messaging', SCHOLAXIA_CHANNEL_ID, {
    name: 'general',
    members: [userId],
    created_by_id: userId,
    data: {
      server: SCHOLAXIA_SERVER_NAME,
      category: 'Community',
      image: 'https://getstream.io/random_png/?name=Scholaxia',
    },
  });

  try {
    await channel.create();
  } catch {
    try {
      await channel.addMembers([userId]);
    } catch {
      /* channel may already include member */
    }
  }
}
