'use client';

import { useEffect } from 'react';
import { useChatContext } from 'stream-chat-react';
import { useDiscordContext } from '@/contexts/DiscordContext';
import { SCHOLAXIA_SERVER_NAME } from '@/types/discord';

/** Select the Scholaxia server + first channel when embedded in the student app. */
export default function ScholaxiaBoot() {
  const { client } = useChatContext();
  const { changeServer } = useDiscordContext();

  useEffect(() => {
    if (!client?.userID) return;

    changeServer(
      {
        name: SCHOLAXIA_SERVER_NAME,
        image: 'https://getstream.io/random_png/?name=Scholaxia',
      },
      client
    );
  }, [client, changeServer]);

  return null;
}
