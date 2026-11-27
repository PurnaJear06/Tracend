/* Motion for "Nothing changes until you say yes" (#change) and "It handles the in-between" (#extras).
   The markup already holds every finished state, so with no script, or with reduced motion, nothing
   here runs and the page is complete. With motion, each mock is armed (hidden) and plays once, when
   it is mostly in view: transform and opacity only, ease-out, no loops. */
(function () {
  'use strict';
  var TK = window.TK;
  var G = TK && TK.G;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var moving = !!(TK && G && !TK.reduced());

  /* play fn once, the first time el is at least `amount` in view */
  function once(el, amount, fn) {
    var done = false;
    function go() { if (done) return; done = true; fn(); }
    if (!('IntersectionObserver' in window)) { go(); return; }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        io.disconnect();
        go();
      });
    }, { threshold: amount });
    io.observe(el);
  }

  /* a finger tap on a control: the ring grows from its middle and the control dips */
  function tap(tl, btn, ripple, at) {
    tl.fromTo(ripple, { scale: 0.2, autoAlpha: 0.7 }, { scale: 1.7, autoAlpha: 0, duration: 0.42, ease: 'power2.out' }, at)
      .to(btn, { scale: 0.97, duration: 0.08, ease: 'power2.out' }, at)
      .to(btn, { scale: 1, duration: 0.2, ease: 'power3.out' }, at + 0.08);
  }

  /* ---------- Change: bubble, typing, card, Approve, Applied ---------- */
  function change() {
    var chat = $('[data-ch-chat]');
    if (!chat || !moving) return;
    var q = $('[data-ch="q"]', chat);
    var typing = $('[data-ch="typing"]', chat);
    var card = $('[data-ch="card"]', chat);
    var status = $('[data-ch="status"]', chat);
    var line = $('[data-ch="line"]', chat);
    var acts = $('[data-ch="acts"]', chat);
    var approve = $('[data-ch="approve"]', chat);
    var ripple = $('[data-ch="ripple"]', chat);
    if (!q || !typing || !card || !status || !line || !acts || !approve || !ripple) return;
    var parts = $$('.ch-p', card);
    var dots = $$('i', typing);
    var statusA = $('.is-a', status), statusB = $('.is-b', status);
    var lineA = $('.is-a', line), lineB = $('.is-b', line);
    var actA = $('.ch-act.is-a', acts), actB = $('.ch-act.is-b', acts);
    var labA = $('.ch-lab.is-a', approve), labB = $('.ch-lab.is-b', approve);
    var all = [q, typing, card, statusA, statusB, lineA, lineB, actA, actB, labA, labB, approve, ripple].concat(parts, dots);

    G.set(q, { autoAlpha: 0, x: 26 });
    G.set(typing, { display: 'flex', autoAlpha: 0, y: 6 });
    G.set(card, { autoAlpha: 0, y: 16 });
    G.set(parts, { autoAlpha: 0, y: 10 });
    G.set([statusA, lineA, actA, labA], { autoAlpha: 1 });
    G.set([statusB, lineB, actB, labB], { autoAlpha: 0 });

    once(chat, 0.4, function () {
      var tl = G.timeline({ defaults: { ease: 'power3.out' }, onComplete: function () { G.set(all, { clearProps: 'all' }); } });
      tl.to(q, { autoAlpha: 1, x: 0, duration: 0.45 }, 0)
        .to(typing, { autoAlpha: 1, y: 0, duration: 0.25 }, 0.55)
        .to(dots, { y: -3, duration: 0.18, stagger: 0.1, repeat: 1, yoyo: true, ease: 'sine.inOut' }, 0.6)
        .to(typing, { autoAlpha: 0, duration: 0.2 }, 1.45)
        .to(card, { autoAlpha: 1, y: 0, duration: 0.45 }, 1.5)
        .to(parts, { autoAlpha: 1, y: 0, duration: 0.4, stagger: 0.07 }, 1.65);
      tap(tl, approve, ripple, 3.1);
      tl.to(labA, { autoAlpha: 0, y: -6, duration: 0.15 }, 3.2)
        .fromTo(labB, { autoAlpha: 0, y: 6 }, { autoAlpha: 1, y: 0, duration: 0.2 }, 3.25)
        .to([actA, statusA, lineA], { autoAlpha: 0, duration: 0.25 }, 3.85)
        .to([actB, statusB, lineB], { autoAlpha: 1, duration: 0.3 }, 3.9);
    });
  }

  /* ---------- Extras: one small play per card ---------- */
  var PLAY = {
    /* the rest runs out, the next set takes its place, and Log set takes the tap */
    lock: function (card) {
      var rest = $('[data-ex-rest]', card), set = $('[data-ex-set]', card), cd = $('[data-ex-cd]', card), log = $('[data-ex-log]', card);
      var ripple = log && $('.ex-ripple', log);
      if (!rest || !set || !cd || !log || !ripple) return null;
      cd.textContent = '0:03';
      G.set(rest, { autoAlpha: 1 });
      G.set(set, { autoAlpha: 0 });
      return function () {
        var o = { v: 3 };
        var tl = G.timeline({ defaults: { ease: 'power3.out' }, onComplete: function () { G.set([rest, set, log, ripple], { clearProps: 'all' }); } });
        tl.to(o, { v: 0, duration: 0.5, ease: 'none', onUpdate: function () { cd.textContent = '0:0' + Math.round(o.v); } }, 0)
          .to(rest, { autoAlpha: 0, duration: 0.18 }, 0.52)
          .to(set, { autoAlpha: 1, duration: 0.22 }, 0.56);
        tap(tl, log, ripple, 0.8);
      };
    },
    /* the next target rolls up by one step */
    prog: function (card) {
      var o = $('.ex-roll .o', card), n = $('.ex-roll .n', card), tile = $('[data-ex-tile]', card), why = $('[data-ex-why]', card);
      if (!o || !n || !tile || !why) return null;
      G.set(o, { autoAlpha: 1, y: 0 });
      G.set(n, { autoAlpha: 0, y: 9 });
      G.set(why, { autoAlpha: 0, y: 4 });
      return function () {
        var tl = G.timeline({ defaults: { ease: 'power3.out' }, onComplete: function () { G.set([o, n, tile, why], { clearProps: 'all' }); } });
        tl.to(o, { autoAlpha: 0, y: -9, duration: 0.3 }, 0.1)
          .to(n, { autoAlpha: 1, y: 0, duration: 0.35 }, 0.18)
          .to(tile, { scale: 1.04, duration: 0.18 }, 0.3)
          .to(tile, { scale: 1, duration: 0.3, ease: 'power2.out' }, 0.48)
          .to(why, { autoAlpha: 1, y: 0, duration: 0.35 }, 0.5);
      };
    },
    /* a scan line crosses the label, then the food it found settles in */
    label: function (card) {
      var photo = $('[data-ex-photo]', card), scan = $('[data-ex-scan]', card), cand = $('[data-ex-cand]', card), badge = $('[data-ex-badge]', card);
      if (!photo || !scan || !cand || !badge) return null;
      G.set(cand, { autoAlpha: 0, y: 12 });
      G.set(badge, { autoAlpha: 0, scale: 0.85 });
      return function () {
        var h = Math.max(0, photo.offsetHeight - 2);
        var tl = G.timeline({ defaults: { ease: 'power3.out' }, onComplete: function () { G.set([scan, cand, badge], { clearProps: 'all' }); } });
        tl.fromTo(scan, { y: 0, autoAlpha: 1 }, { y: h, duration: 0.5, ease: 'power1.inOut' }, 0)
          .to(scan, { autoAlpha: 0, duration: 0.12 }, 0.5)
          .to(cand, { autoAlpha: 1, y: 0, duration: 0.4 }, 0.45)
          .to(badge, { autoAlpha: 1, scale: 1, duration: 0.3, ease: 'back.out(1.6)' }, 0.75);
      };
    },
    /* the answers go in, then the swap lands: the old exercise is struck, the new one arrives */
    pain: function (card) {
      var ons = $$('.ex-pn-chips .on, .ex-pn-sev .on', card), res = $('[data-ex-res]', card);
      var old = $('.ex-pn-old', card), arrow = $('.ex-pn-l svg', card), nu = $('.ex-pn-new', card);
      if (!ons.length || !res || !old || !arrow || !nu) return null;
      var off = { backgroundColor: 'rgba(244,244,241,0)', color: '#9C9D98', boxShadow: 'inset 0 0 0 1.2px #2A2B2F' };
      var on = { backgroundColor: '#F4F4F1', color: '#0C0D0E', boxShadow: 'inset 0 0 0 1.2px rgba(244,244,241,0)', duration: 0.2 };
      G.set(ons, off);
      G.set(res, { autoAlpha: 0, y: 12 });
      G.set(old, { '--s': 0 });
      G.set(arrow, { autoAlpha: 0, x: -6 });
      G.set(nu, { autoAlpha: 0, x: -8 });
      return function () {
        var tl = G.timeline({ defaults: { ease: 'power3.out' }, onComplete: function () { G.set(ons.concat([res, old, arrow, nu]), { clearProps: 'all' }); } });
        tl.to(ons[0], on, 0.05)
          .to(ons[1] || ons[0], on, 0.3)
          .to(res, { autoAlpha: 1, y: 0, duration: 0.4 }, 0.5)
          .to(old, { '--s': 1, duration: 0.25 }, 0.72)
          .to(arrow, { autoAlpha: 1, x: 0, duration: 0.22 }, 0.8)
          .to(nu, { autoAlpha: 1, x: 0, duration: 0.3 }, 0.88);
      };
    },
    /* saved facts settle in, the one due for a check glows, and its question arrives */
    mem: function (card) {
      var facts = $$('[data-ex-fact]', card), ask = $('[data-ex-ask]', card), ic = $('.due .ex-ic', card);
      if (!facts.length || !ask) return null;
      G.set(facts, { autoAlpha: 0, y: 8 });
      G.set(ask, { autoAlpha: 0, y: 12 });
      return function () {
        var tl = G.timeline({ defaults: { ease: 'power3.out' }, onComplete: function () { G.set(facts.concat([ask, ic || ask]), { clearProps: 'all' }); } });
        tl.to(facts, { autoAlpha: 1, y: 0, duration: 0.3, stagger: 0.07 }, 0);
        if (ic) tl.to(ic, { scale: 1.3, duration: 0.15 }, 0.45).to(ic, { scale: 1, duration: 0.25, ease: 'power2.out' }, 0.6);
        tl.to(ask, { autoAlpha: 1, y: 0, duration: 0.4 }, 0.55);
      };
    }
  };

  function extras() {
    var rail = $('[data-ex-rail]');
    if (!rail) return;
    var cards = $$('.ex-card', rail);

    /* wide screens show a grid, not a scroller: it needs no tab stop */
    if (window.matchMedia) {
      var mq = window.matchMedia('(min-width: 1024px)');
      var sync = function () { if (mq.matches) rail.removeAttribute('tabindex'); else rail.setAttribute('tabindex', '0'); };
      sync();
      if (mq.addEventListener) mq.addEventListener('change', sync); else if (mq.addListener) mq.addListener(sync);
    }

    /* the dots follow whichever card is mostly in view */
    var dots = $$('[data-ex-dots] i');
    if (dots.length && 'IntersectionObserver' in window) {
      var seen = {};
      var dio = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { seen[cards.indexOf(e.target)] = e.intersectionRatio; });
        var best = 0, top = -1;
        cards.forEach(function (c, i) { if ((seen[i] || 0) > top) { top = seen[i] || 0; best = i; } });
        dots.forEach(function (d, i) { d.classList.toggle('on', i === best); });
      }, { root: rail, threshold: [0.25, 0.5, 0.75, 1] });
      cards.forEach(function (c) { dio.observe(c); });
    }

    if (!moving) return;
    cards.forEach(function (c) {
      var make = PLAY[c.getAttribute('data-ex')];
      var play = make ? make(c) : null;
      if (play) once(c, 0.6, play);
    });
  }

  change();
  extras();
})();
