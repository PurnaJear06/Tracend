/* Sub-animations for each beat's app screen.
   anim(i, scope, tl, at) adds beat i's tweens to timeline tl at time at; scope holds the phone.
   Every tween is a fromTo so a scrubbed timeline lands in the same state in both directions. */
(function () {
  'use strict';
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var D = window.TRACEND_DAY, BEATS = D.beats;

  /* a finger tap: the ring under the finger, and the control dips */
  function tap(tl, el, at) {
    var t = $('.gp-t', el);
    if (t) tl.fromTo(t, { scale: 0.6, autoAlpha: 0 }, { scale: 1, autoAlpha: 1, duration: 0.06 }, at).fromTo(t, { scale: 1, autoAlpha: 1 }, { scale: 1.3, autoAlpha: 0, duration: 0.12, ease: 'power1.out' }, at + 0.08);
    tl.fromTo(el, { scale: 1 }, { scale: 0.96, duration: 0.04, ease: 'power2.out' }, at).fromTo(el, { scale: 0.96 }, { scale: 1, duration: 0.1, ease: TK.EASE.spring }, at + 0.05);
  }

  var ANIM = {
    goal: function (scr, tl, at) {
      tl.fromTo($$('.gp-card', scr), { y: 16, autoAlpha: 0 }, { y: 0, autoAlpha: 1, duration: 0.18, stagger: 0.04 }, at + 0.04);
      var pick = $('[data-pick]', scr);
      tap(tl, pick, at + 0.32);
      tl.fromTo(pick, { backgroundColor: '#18191B', boxShadow: 'inset 0 0 0 1.5px rgba(200,240,90,0)' }, { backgroundColor: 'rgba(200,240,90,0.08)', boxShadow: 'inset 0 0 0 1.5px rgba(200,240,90,1)', duration: 0.1 }, at + 0.34)
        .fromTo($('.gp-ck', pick), { backgroundColor: 'rgba(200,240,90,0)' }, { backgroundColor: 'rgba(200,240,90,1)', duration: 0.08 }, at + 0.34)
        .fromTo($('.gp-ck svg', pick), { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.12, ease: TK.EASE.spring }, at + 0.36);
      tap(tl, $('[data-cont]', scr), at + 0.6);
    },
    learn: function (scr, tl, at) {
      tl.fromTo($$('.gp-hk .gp-row', scr), { autoAlpha: 0, x: -10 }, { autoAlpha: 1, x: 0, duration: 0.14, stagger: 0.06 }, at + 0.04)
        .fromTo([$('.gp-who', scr), $('.gp-qt', scr)], { autoAlpha: 0, y: 10 }, { autoAlpha: 1, y: 0, duration: 0.16, stagger: 0.05 }, at + 0.26)
        .fromTo($$('.gp-ans span', scr), { autoAlpha: 0, y: 10 }, { autoAlpha: 1, y: 0, duration: 0.14, stagger: 0.05 }, at + 0.4);
      var yes = $('[data-yes]', scr);
      tap(tl, yes, at + 0.6);
      tl.fromTo(yes, { backgroundColor: 'rgba(200,240,90,0)', color: '#F4F4F1' }, { backgroundColor: 'rgba(200,240,90,1)', color: '#141A05', duration: 0.08 }, at + 0.62);
    },
    approve: function (scr, tl, at) {
      tl.fromTo($$('.gp-day, .gp-nut', scr), { autoAlpha: 0, y: 12 }, { autoAlpha: 1, y: 0, duration: 0.14, stagger: 0.04 }, at + 0.04);
      tap(tl, $('[data-appr]', scr), at + 0.48);
      tl.fromTo($('.gp-set', scr), { yPercent: 102 }, { yPercent: 0, duration: 0.24, ease: TK.EASE.out }, at + 0.58);
    },
    train: function (scr, tl, at) {
      $$('.set', scr).forEach(function (s, k) {
        var ck = $('.ck', s), svg = $('svg', ck);
        tl.fromTo(ck, { backgroundColor: '#232427', color: '#9C9D98' }, { backgroundColor: '#C8F05A', color: 'rgba(0,0,0,0)', duration: 0.1, ease: 'none' }, at + 0.08 + k * 0.1);
        tl.fromTo(svg, { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.14, ease: TK.EASE.spring }, at + 0.1 + k * 0.1);
      });
      var done = $('[data-done]', scr);
      tl.fromTo(done, { scale: 1 }, { scale: 0.96, duration: 0.06, ease: 'power2.out' }, at + 0.5)
        .fromTo(done, { scale: 0.96 }, { scale: 1, duration: 0.12, ease: TK.EASE.out }, at + 0.56);
      tl.fromTo($('[data-best]', scr), { scale: 0.85, autoAlpha: 0, y: 6 }, { scale: 1, autoAlpha: 1, y: 0, duration: 0.22, ease: TK.EASE.spring }, at + 0.62);
    },
    eat: function (scr, tl, at) {
      var t = D.monday.meal.totals;
      tl.fromTo($('[data-meal]', scr), { autoAlpha: 0, y: 18 }, { autoAlpha: 1, y: 0, duration: 0.22 }, at + 0.06);
      tl.fromTo($('[data-scan]', scr), { xPercent: -100 }, { xPercent: 100, duration: 0.3, ease: 'none' }, at + 0.14);
      ['kcal', 'protein', 'carbs', 'fat'].forEach(function (k, n) {
        var el = $('[data-n="' + k + '"]', scr), bar = $('[data-nb="' + k + '"]', scr);
        TK.countUp(el, t[k][1], { tl: tl, at: at + 0.4, dur: 0.35, from: t[k][0], fmt: function (v) { return Math.round(v).toLocaleString('en-US'); } });
        tl.fromTo(bar, { '--v': t[k][0] / t[k][2] }, { '--v': Math.min(1, t[k][1] / t[k][2]), duration: 0.35 }, at + 0.4 + n * 0.03);
      });
      TK.countUp($('[data-pct]', scr), Math.round(t.kcal[1] / t.kcal[2] * 100), { tl: tl, at: at + 0.4, dur: 0.35, from: Math.round(t.kcal[0] / t.kcal[2] * 100), fmt: function (v) { return Math.round(v) + '%'; } });
      TK.countUp($('[data-left]', scr), t.protein[2] - t.protein[1], { tl: tl, at: at + 0.4, dur: 0.35, from: t.protein[2] - t.protein[0], fmt: function (v) { return Math.round(v) + 'g left'; } });
    },
    sleep: function (scr, tl, at) {
      TK.countUp($('.sq-score', scr), D.night.sleep.score, { tl: tl, at: at + 0.1, dur: 0.4 });
      tl.fromTo($$('.hyp i', scr), { scaleY: 0 }, { scaleY: 1, duration: 0.2, stagger: 0.012, transformOrigin: '50% 100%' }, at + 0.08);
      $$('.bar i', scr).forEach(function (b, k) { tl.fromTo(b, { '--v': 0 }, { '--v': b.getAttribute('data-bar'), duration: 0.3 }, at + 0.3 + k * 0.06); });
      tl.fromTo($('.debt', scr), { autoAlpha: 0, y: 8 }, { autoAlpha: 1, y: 0, duration: 0.2 }, at + 0.6);
    },
    read: function (scr, tl, at) {
      var svg = $('[data-ring]', scr), r = svg._ring, p = { v: 0 };
      tl.fromTo(p, { v: 0 }, { v: 1, duration: 0.6, ease: 'power2.out', onUpdate: function () { r.draw(p.v); } }, at + 0.1);
      TK.countUp($('[data-score]', scr), D.morning.score, { tl: tl, at: at + 0.1, dur: 0.6 });
      tl.fromTo($$('.a-chip', scr), { autoAlpha: 0, y: 6 }, { autoAlpha: 1, y: 0, duration: 0.14, stagger: 0.05 }, at + 0.6);
    },
    plan: function (scr, tl, at) {
      var note = $('[data-note]', scr), s = $('s', note), b = $('b', note);
      tl.fromTo($$('.strip .ex', scr), { scaleY: 0.4, autoAlpha: 0 }, { scaleY: 1, autoAlpha: 1, duration: 0.18, stagger: 0.05, transformOrigin: '50% 100%' }, at + 0.05);
      tl.fromTo(note, { autoAlpha: 0, y: 10 }, { autoAlpha: 1, y: 0, duration: 0.25 }, at + 0.1);
      if (s) tl.fromTo(s, { '--s': '0%' }, { '--s': '100%', duration: 0.25, ease: 'power2.inOut' }, at + 0.35);
      if (b) tl.fromTo(b, { backgroundColor: 'rgba(200,240,90,0)' }, { backgroundColor: 'rgba(200,240,90,.18)', duration: 0.2 }, at + 0.55);
    }
  };
  function beatAnim(i, scope, tl, at) {
    var scr = $('[data-scr="' + BEATS[i].scr + '"]', scope);
    if (scr && ANIM[BEATS[i].id]) ANIM[BEATS[i].id](scr, tl, at);
  }
  /* strike line drawn by background so it can animate */
  var st = document.createElement('style');
  st.textContent = '.coach-note p s{text-decoration:none;background:linear-gradient(currentColor,currentColor) 0 56%/var(--s,100%) 1.5px no-repeat}.coach-note p b{border-radius:4px;padding:0 3px;margin:0 -3px}';
  document.head.appendChild(st);

  window.TracendBeats = { anim: beatAnim };
})();
