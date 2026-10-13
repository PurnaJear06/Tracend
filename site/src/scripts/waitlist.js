/* The waitlist on the page: join, the invite link, and the calls the confirm and
   unsubscribe pages make. Talks to the waitlist-* Edge Functions; a Cloudflare
   Turnstile check runs only when someone submits. */
import { WAITLIST_API, TURNSTILE_SITE_KEY, CONSENT_VERSION } from '../config';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const REF = /^[0-9A-HJKMNP-TV-Z]{8}$/;

function remember(key, value) { try { sessionStorage.setItem(key, value); } catch (e) { /* storage blocked: attribution is optional */ } }
function recall(key) { try { return sessionStorage.getItem(key); } catch (e) { return null; } }

/* ?ref=CODE and utm_* tags from the link that brought the visitor in */
export function captureAttribution() {
  const q = new URLSearchParams(location.search);
  const ref = (q.get('ref') || '').toUpperCase();
  if (REF.test(ref)) remember('tracend.ref', ref);
  const utm = {};
  ['source', 'medium', 'campaign', 'content'].forEach((k) => { const v = q.get('utm_' + k); if (v) utm[k] = v.slice(0, 100); });
  if (Object.keys(utm).length) remember('tracend.utm', JSON.stringify(utm));
}

export async function call(name, payload) {
  const res = await fetch(`${WAITLIST_API}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  let body = {};
  try { body = await res.json(); } catch (e) { /* an empty or non-JSON body reads as a server error */ }
  return { ok: res.ok, status: res.status, body };
}

/* ---------- Turnstile, loaded on first use ---------- */
let loading = null;
function turnstile() {
  if (!loading) {
    loading = new Promise((resolve, reject) => {
      window.__tracendTurnstile = () => resolve(window.turnstile);
      const s = document.createElement('script');
      s.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=__tracendTurnstile';
      s.async = true;
      s.onerror = () => { loading = null; s.remove(); reject(new Error('turnstile_unavailable')); };
      document.head.appendChild(s);
    });
  }
  return loading;
}

function widget(form) {
  if (!form._widget) {
    form._widget = turnstile().then((ts) => {
      const w = { ts, id: null, pending: null };
      const settle = (fn, arg) => { if (w.pending) { const p = w.pending; w.pending = null; clearTimeout(p.timer); p[fn](arg); } };
      w.id = ts.render(form.querySelector('[data-ts]'), {
        sitekey: TURNSTILE_SITE_KEY,
        action: 'waitlist',
        execution: 'execute',
        appearance: 'interaction-only',
        theme: 'dark',
        callback: (token) => settle('resolve', token),
        'error-callback': () => { settle('reject', new Error('turnstile_failed')); return true; },
        'timeout-callback': () => settle('reject', new Error('turnstile_failed')),
      });
      return w;
    });
    form._widget.catch(() => { form._widget = null; });
  }
  return form._widget;
}

async function verify(form) {
  const w = await widget(form);
  return new Promise((resolve, reject) => {
    w.pending = { resolve, reject, timer: setTimeout(() => { w.pending = null; reject(new Error('turnstile_failed')); }, 60000) };
    w.ts.reset(w.id);
    w.ts.execute(w.id);
  });
}

/* ---------- The invite link ---------- */
export function showShare(box, code) {
  if (!box || !REF.test(code || '')) return;
  const link = `${location.origin}/?ref=${code}`;
  const input = box.querySelector('[data-ref-link]');
  const copy = box.querySelector('[data-copy]');
  const share = box.querySelector('[data-native-share]');
  input.value = link;
  box.hidden = false;
  copy.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(link); copy.textContent = 'Copied'; }
    catch (e) { input.focus(); input.select(); copy.textContent = 'Press copy'; }
    setTimeout(() => { copy.textContent = 'Copy'; }, 2200);
  });
  if (navigator.share) {
    share.hidden = false;
    share.addEventListener('click', () => {
      navigator.share({ title: 'Tracend', text: 'Join me on the Tracend beta: a plan made for your goal, read against your recovery.', url: link }).catch(() => {});
    });
  }
}

/* ---------- The form ---------- */
const MESSAGES = {
  invalid_email: 'That email looks incomplete. Check it and try again.',
  disposable_email: 'Use an email you check. Throwaway addresses can’t join.',
  verification_failed: 'We couldn’t confirm this browser. Try again.',
  rate_limited: 'Too many tries from this network. Try again in an hour.',
  stale_page: 'This page is out of date. Reload it and try again.',
  email_failed: 'We couldn’t send your confirmation email just now. Try again in a minute.',
};

function mount(wrap) {
  const form = wrap.querySelector('form');
  const input = form.querySelector('input[type=email]');
  const err = form.querySelector('.join-err');
  const btn = form.querySelector('.join-btn');
  const label = btn.querySelector('.join-btn-t');
  const ok = wrap.querySelector('.join-ok');
  let busy = false;

  const fail = (text) => {
    err.textContent = text;
    err.hidden = false;
    input.setAttribute('aria-invalid', 'true');
  };
  const setBusy = (on) => {
    busy = on;
    btn.disabled = on;
    btn.setAttribute('aria-busy', String(on));
    label.textContent = on ? 'Joining' : 'Join the beta';
  };

  /* warm up the check while the visitor types, so submit feels instant */
  input.addEventListener('focus', () => { widget(form).catch(() => {}); }, { once: true });
  input.addEventListener('input', () => {
    if (input.getAttribute('aria-invalid')) { input.removeAttribute('aria-invalid'); err.hidden = true; }
  });

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (busy) return;
    const email = (input.value || '').trim();
    if (!EMAIL.test(email)) {
      fail(email ? MESSAGES.invalid_email : 'Enter your email to join the beta.');
      input.focus();
      return;
    }
    err.hidden = true;
    input.removeAttribute('aria-invalid');
    setBusy(true);
    try {
      let token;
      try { token = await verify(form); }
      catch (x) { fail('We couldn’t run the quick bot check. Reload the page and try again.'); return; }
      let utm = null;
      try { utm = JSON.parse(recall('tracend.utm') || 'null'); } catch (x) { utm = null; }
      const res = await call('waitlist-join', {
        email,
        turnstile_token: token,
        consent_version: CONSENT_VERSION,
        ref: recall('tracend.ref'),
        time_zone: Intl.DateTimeFormat().resolvedOptions().timeZone || null,
        utm,
      });
      if (res.ok) {
        ok.querySelector('[data-ok-email]').textContent = email;
        form.hidden = true;
        ok.hidden = false;
        showShare(ok.querySelector('[data-share]'), res.body.referral_code);
        ok.focus();
        const G = window.gsap;
        if (G && !document.documentElement.classList.contains('rm')) G.from(ok.children, { y: 12, autoAlpha: 0, stagger: 0.06, duration: 0.42, ease: 'power3.out' });
        return;
      }
      fail(MESSAGES[res.body.error] || 'Something went wrong on our side. Try again in a minute.');
    } catch (x) {
      fail('We couldn’t reach Tracend. Check your connection and try again.');
    } finally {
      setBusy(false);
    }
  });
}

export function setupJoin() {
  captureAttribution();
  document.querySelectorAll('[data-join]').forEach(mount);
}
