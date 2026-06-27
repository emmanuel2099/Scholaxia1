'use client';

import { User } from 'stream-chat';
import { LoadingIndicator } from 'stream-chat-react';
import { useClerk } from '@clerk/nextjs';
import { useCallback, useEffect, useState } from 'react';
import MyChat from '@/components/MyChat';
import type { Homestate } from '@/types/discord';

const apiKey = process.env.STREAM_API_KEY || '7cu55d72xtjs';

export default function HomeWithClerk() {
  const [myState, setMyState] = useState<Homestate | undefined>(undefined);
  const { user: myUser } = useClerk();

  const registerUser = useCallback(
    async function registerUser() {
      const userId = myUser?.id;
      const mail = myUser?.primaryEmailAddress?.emailAddress;
      if (userId && mail) {
        const streamResponse = await fetch('/api/register-user', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            userId: userId,
            email: mail,
          }),
        });
        const responseBody = await streamResponse.json();
        return responseBody;
      }
    },
    [myUser]
  );

  useEffect(() => {
    if (
      myUser?.id &&
      myUser?.primaryEmailAddress?.emailAddress &&
      !myUser?.publicMetadata.streamRegistered
    ) {
      registerUser().then(() => {
        getUserToken(
          myUser.id,
          myUser?.primaryEmailAddress?.emailAddress || 'Unknown'
        );
      });
    } else if (myUser?.id) {
      getUserToken(
        myUser?.id || 'Unknown',
        myUser?.primaryEmailAddress?.emailAddress || 'Unknown'
      );
    }
  }, [registerUser, myUser]);

  if (!myState) {
    return <LoadingIndicator />;
  }

  return <MyChat {...myState} />;

  async function getUserToken(userId: string, userName: string) {
    const response = await fetch('/api/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        userId: userId,
      }),
    });
    const responseBody = await response.json();
    const token = responseBody.token;

    if (!token) {
      console.error("Couldn't retrieve token.");
      return;
    }

    const user: User = {
      id: userId,
      name: userName,
      image: `https://getstream.io/random_png/?id=${userId}&name=${userName}`,
    };
    setMyState({
      apiKey: apiKey,
      user: user,
      token: token,
    });
  }
}
