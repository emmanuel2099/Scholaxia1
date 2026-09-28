/**
 * Scholaxia — school subdomain → Render router (Cloudflare Worker)
 * ================================================================
 * WHY: Render routes by Host header and only accepts registered custom
 * domains, so each school subdomain would need a manual Render step.
 * This Worker removes that step: Cloudflare terminates TLS for
 * *.scholaxia.com (free Universal SSL wildcard) and rewrites the request
 * to the path-based school routes that already exist on the backend:
 *
 *     https://divine-light.scholaxia.com/            →  https://scholaxia1.onrender.com/school/divine-light/
 *     https://divine-light.scholaxia.com/portal.html →  https://scholaxia1.onrender.com/school/divine-light/portal.html
 *     https://divine-light.scholaxia.com/api/v1/…    →  https://scholaxia1.onrender.com/api/v1/…   (API passes through)
 *
 * SETUP (one-time, see HOSTING-SCHOOL-LINKS.md):
 *   Cloudflare Dashboard → Workers & Pages → Create Worker → paste this
 *   file → Deploy → add a route:  *.scholaxia.com/*  (zone: scholaxia.com)
 *   The wildcard DNS record must be PROXIED (orange cloud) for the route
 *   to fire. Apex and www stay DNS-only (gray) so cPanel keeps serving
 *   the main site unchanged.
 */

const ORIGIN = "https://scholaxia1.onrender.com";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const host = (url.hostname || "").toLowerCase();

    // Only rewrite school subdomains (one label under scholaxia.com).
    if (!host.endsWith(".scholaxia.com") ||
        host === "scholaxia.com" ||
        host === "www.scholaxia.com") {
      return fetch(request); // shouldn't happen given the route, but be safe
    }

    const slug = host.slice(0, -".scholaxia.com".length).replace(/[^a-z0-9-]/g, "");
    if (!slug) {
      return fetch(request);
    }

    // API calls pass through untouched (same-origin from the page's view).
    if (url.pathname.startsWith("/api/") || url.pathname === "/health" ||
        url.pathname.startsWith("/ws/")) {
      return proxy(request, url.pathname + url.search);
    }

    // Everything else serves the school-branded student SPA.
    const target = "/school/" + slug + (url.pathname === "/" ? "/" : url.pathname);
    return proxy(request, target + url.search);
  },
};

function proxy(request, pathWithQuery) {
  const url = new URL(request.url);
  const originUrl = ORIGIN + pathWithQuery;
  const req = new Request(originUrl, request);
  // Mark the real visitor host so backend logs/debugging stay clear.
  req.headers.set("x-forwarded-host", url.hostname);
  return fetch(req);
}
