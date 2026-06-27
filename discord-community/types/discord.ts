import type { User } from 'stream-chat';

export type DiscordServer = {
  name: string;
  image: string | undefined;
};

export type Homestate = {
  apiKey: string;
  user: User;
  token: string;
};

export const SCHOLAXIA_SERVER_NAME = 'Scholaxia';
export const SCHOLAXIA_CHANNEL_ID = 'scholaxia-community-general';
