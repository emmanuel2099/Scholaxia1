'use client';

import { createContext, useContext } from 'react';

const EmbedModeContext = createContext(false);

export function EmbedModeProvider({
  embedded,
  children,
}: {
  embedded: boolean;
  children: React.ReactNode;
}) {
  return (
    <EmbedModeContext.Provider value={embedded}>{children}</EmbedModeContext.Provider>
  );
}

export function useEmbedMode() {
  return useContext(EmbedModeContext);
}
