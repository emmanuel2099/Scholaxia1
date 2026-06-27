import { NextResponse } from 'next/server';
import type { NextFetchEvent, NextRequest } from 'next/server';
import { authMiddleware } from '@clerk/nextjs';

const hasClerk =
  !!process.env.CLERK_SECRET_KEY && !!process.env.NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY;

function isScholaxiaRoute(pathname: string) {
  return (
    pathname.startsWith('/discord-app/scholaxia') ||
    pathname.startsWith('/discord-app/api/scholaxia-token') ||
    pathname.startsWith('/scholaxia') ||
    pathname.startsWith('/api/scholaxia-token')
  );
}

const clerkMiddleware = hasClerk
  ? authMiddleware({
      publicRoutes: ['/api/token(.*)'],
    })
  : null;

export default function middleware(req: NextRequest, event: NextFetchEvent) {
  if (isScholaxiaRoute(req.nextUrl.pathname)) {
    return NextResponse.next();
  }
  if (clerkMiddleware) {
    return clerkMiddleware(req, event);
  }
  return NextResponse.next();
}

export const config = {
  matcher: [
    '/((?!_next|[^?]*\\.(?:html?|css|js(?!on)|jpe?g|webp|png|gif|svg|ttf|woff2?|ico|csv|docx?|xlsx?|zip|webmanifest)).*)',
    '/(api|trpc)(.*)',
  ],
};
