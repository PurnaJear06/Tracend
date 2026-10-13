/* Public, build-time settings. Values come from site/.env.development locally and from the
   hosting build's environment in production (see site/.env.example). None of them is secret. */

/* Bump when the consent sentence by the join button changes; waitlist-join stores it. */
export const CONSENT_VERSION = 'waitlist-2026-10-13';

const env = import.meta.env;

export const WAITLIST_API: string = env.PUBLIC_WAITLIST_API ?? '';
export const TURNSTILE_SITE_KEY: string = env.PUBLIC_TURNSTILE_SITE_KEY ?? '';
export const CONTACT_EMAIL: string = env.PUBLIC_CONTACT_EMAIL ?? '';
/* The site's public address, for link previews (https://tracend.pages.dev, no trailing slash). */
export const SITE_URL: string = (env.PUBLIC_SITE_URL ?? '').replace(/\/+$/, '');

const missing = Object.entries({
  PUBLIC_WAITLIST_API: WAITLIST_API,
  PUBLIC_TURNSTILE_SITE_KEY: TURNSTILE_SITE_KEY,
  PUBLIC_CONTACT_EMAIL: CONTACT_EMAIL,
  PUBLIC_SITE_URL: SITE_URL,
}).filter(([, v]) => !v).map(([k]) => k);

if (missing.length) {
  throw new Error(`site: set ${missing.join(', ')} (see site/.env.example)`);
}
