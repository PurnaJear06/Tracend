/* The landing page: hero film, the day story, sections and their motion. */
(function () {
  'use strict';
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var G = TK.G, D = window.TRACEND_DAY, A = window.TracendApp, Body = window.TracendBody;
  var motion = function () { return !!G && !TK.reduced(); };
  /* ambient light per moment: the evening gym, the night, first light, the morning */
  var AMB = [['#33291F', '#1B1F26'], ['#131A3C', '#0A0E24'], ['#3A2828', '#22304A'], ['#3A3524', '#1C2A22']];
  var BEATS = D.beats, R = 1.6, S = 1.4; /* timeline units. R: the rewind. S: one moment, its motion in the first unit, then a rest so it reads settled */
  var film = $('.film'), fdev = $('.f-dev'), live = $('[data-day-live]');
  /* wide: copy beside the phone. tall: copy above it (phones and upright tablets). Anything else
     (reduced motion, short or sideways screens) gets the static page. */
  var wide = matchMedia('(min-width: 1024px) and (min-height: 660px)').matches;
  var tall = matchMedia('(max-width: 1023.98px) and (min-height: 540px) and (orientation: portrait)').matches;
  var pinMode = motion() && (wide || tall);
  film.setAttribute('data-mode', pinMode ? 'pin' : 'flow');
  film.setAttribute('data-lay', wide ? 'wide' : 'tall');

  /* ---------- Static build ---------- */
  $('[data-mark]').outerHTML = A.mark();
  $('[data-phone-slot]').outerHTML = A.phone({ id: 'day-phone', time: '07:02', tab: 'today', screens: ['today-hero'].concat(BEATS.map(function (b) { return b.scr; })) });
  var ph = $('#day-phone');
  /* a real phone body: stacked layers behind the glass give it depth and a lit titanium edge */
  function deepen(phoneEl) {
    var w = document.createElement('div'), n = 16;
    w.className = 'deep';
    phoneEl.parentNode.insertBefore(w, phoneEl);
    for (var k = n; k >= 1; k--) { var l = document.createElement('i'); l.className = 'deep-l' + (k === n ? ' back' : ''); l.style.setProperty('--k', (k / n).toFixed(3)); w.appendChild(l); }
    w.appendChild(phoneEl);
    return w;
  }
  function setPwn(phoneEl, v) { phoneEl.style.setProperty('--pwn', v); if (phoneEl.parentNode.classList.contains('deep')) phoneEl.parentNode.style.setProperty('--pwn', v); }
  deepen(ph);
  if (!pinMode) $$('.beat .b-phone').forEach(function (slot, i) { slot.innerHTML = A.phone({ screens: [BEATS[i].scr], time: BEATS[i].time, tab: BEATS[i].tab }); });
  $$('[data-ring]').forEach(function (svg) { svg._ring = A.ring(svg, { score: D.morning.score, segments: D.morning.segments }); });
  var heroRing = $('[data-scr="today-hero"] [data-ring]')._ring;
  var hClock = TK.clock($('[data-hclock]'), '07:02');
  var hDay = TK.wordReel($('[data-hday]'), ['Monday', 'Tuesday']);
  TK.setWord(hDay, 'Tuesday', { instant: true });
  var dClock = TK.clock($('[data-dclock]'), BEATS[0].time);
  var dDay = TK.wordReel($('[data-dday]'), BEATS.map(function (b) { return b.day; }).filter(function (d, k, a) { return a.indexOf(d) === k; }));
  TK.setWord(dDay, BEATS[0].day, { instant: true });

  $$('[data-tile]').forEach(function (t) { t.innerHTML = A.tiles[t.getAttribute('data-tile')](); });
  A.ring($('[data-ring-tile]'), { score: D.morning.score, segments: D.morning.segments });
  (function () {
    var fig = $('[data-fig]'), svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    fig.appendChild(svg); Body.build(svg, 'front'); Body.paint(svg, { plan: ['quads', 'glutes', 'core'] });
  })();
  A.ring($('[data-ring-vs]'), { score: 36, segments: [{ color: '#6E6F6A', weight: 1 }], mono: '#6E6F6A', track: '#232427' });
  $('[data-vs-session]').innerHTML = A.sessionCard();

  /* tall: the phone sits under the hero copy, then rises to sit under the day's shorter copy */
  var fcopy = $('.f-copy'), fstory = $('.f-story');
  function lift() { return wide || !pinMode ? 0 : Math.min(0, fstory.offsetHeight - fcopy.offsetHeight); }
  /* phone size follows the viewport: fitted to the height when wide; when tall, to the width,
     and never so large that less than its top three fifths show under the day's copy */
  function sizePhone() {
    var pwn = !pinMode ? Math.round(Math.min(window.innerWidth * 0.64, 290))
      : wide ? Math.round(Math.min(window.innerHeight * 0.8, 790) * 390 / 844)
        : Math.round(Math.min(window.innerWidth * 0.66, 300, Math.max(window.innerWidth * 0.56, (window.innerHeight - fdev.offsetTop - lift()) / 1.3)));
    setPwn(ph, pwn);
    fdev.style.setProperty('--pw', pwn + 'px');
  }
  sizePhone();

  /* ---------- Hero film: the phone arrives; the copy is already there (CSS) ---------- */
  function heroFilm() {
    var tl = G.timeline({ defaults: { ease: TK.EASE.out } });
    var p = { v: 0 }; heroRing.draw(0);
    var ring = function (at) { tl.to(p, { v: 1, duration: 1.1, ease: 'power2.out', onUpdate: function () { heroRing.draw(p.v); } }, at); };
    tl.from('.dev-rise', { y: 70, autoAlpha: 0, rotationX: 10, duration: 1.2 }, 0)
      .from('.f-glow, .f-floor', { autoAlpha: 0, duration: 1.2 }, 0.2);
    if (!wide) {
      /* the score fills, then the Coach's call drops in like a notification */
      ring(0.35);
      tl.from('.fc-coach .fc-in', { y: -22, autoAlpha: 0, duration: 0.8 }, 0.8);
      return tl;
    }
    /* wide: the day compresses into two seconds. Inputs arrive in the order they happened, the clock runs with them */
    TK.setClock(hClock, '18:40', { instant: true }); TK.setWord(hDay, 'Monday', { instant: true });
    tl.from('.f-giant > *', { autoAlpha: 0, duration: 1 }, 0);
    var cards = ['.fc-train', '.fc-food', '.fc-sleep'], times = ['18:40', '20:30', '23:10'];
    cards.forEach(function (c, i) {
      var at = 0.4 + i * 0.32;
      if (i) TK.setClock(hClock, times[i], { tl: tl, at: at - 0.1, dur: 0.35 });
      tl.from(c + ' .fc-in', { x: -24, y: 16, autoAlpha: 0, filter: 'blur(8px)', duration: 0.7 }, at);
    });
    TK.setClock(hClock, '07:02', { tl: tl, at: 1.4, dur: 0.5 });
    TK.setWord(hDay, 'Tuesday', { tl: tl, at: 1.4, dur: 0.4 });
    ring(1.45);
    tl.from('.fc-coach .fc-in', { y: 24, autoAlpha: 0, filter: 'blur(10px)', duration: 0.8 }, 1.9);
    tl.set('.fc-in', { clearProps: 'filter' });
    return tl;
  }
  function pointerDepth() {
    if (!TK.desk.matches || !wide) return;
    var dev = $('.dev'), stage = $('.f-stage');
    var rx = G.quickTo(dev, 'rotationX', { duration: 1, ease: 'power3' }), ry = G.quickTo(dev, 'rotationY', { duration: 1, ease: 'power3' });
    var cards = $$('.fc').map(function (c) { return { x: G.quickTo(c, 'x', { duration: 1, ease: 'power3' }), y: G.quickTo(c, 'y', { duration: 1, ease: 'power3' }), d: c.classList.contains('fc-coach') ? 22 : 12 }; });
    stage.addEventListener('pointermove', function (e) {
      var nx = e.clientX / window.innerWidth - 0.5, ny = e.clientY / window.innerHeight - 0.5;
      rx(-ny * 5); ry(nx * 7);
      ph.style.setProperty('--gx', (18 + nx * 60).toFixed(1) + '%'); ph.style.setProperty('--gy', (4 + ny * 30).toFixed(1) + '%');
      cards.forEach(function (c) { c.x(nx * c.d); c.y(ny * c.d * 0.6); });
    });
  }

  /* ---------- PIN: the answer, the question, then the day that led to it ---------- */
  function strips(el, time) { var d = time.replace(':', '').split('').map(Number); return el._strips.map(function (s, i) { return { s: s, y: -d[i] * 10 }; }); }
  function reelFT(tl, el, from, to, at, dur) {
    var a = strips(el, from), b = strips(el, to);
    a.forEach(function (x, i) { tl.fromTo(x.s, { yPercent: x.y }, { yPercent: b[i].y, duration: dur, ease: TK.EASE.inOut, immediateRender: false }, at + i * 0.04); });
  }
  function setupPin(heroTL) {
    var scrs = $$('.scr', ph), beats = $$('.beat'), cos = $$('[data-co]'), rail = $$('.rail button');
    var sbTime = $('[data-sbtime]', ph), tabs = $$('.tab', ph), story = $$('.f-story > *'), bridge = $('.bridge');
    var tilt = $('.dev-tilt'), tabbar = $('.tabbar', ph), dn = $('[data-dn]');
    var T0 = wide ? { rotationY: -22, rotationX: 8, rotation: 2 } : { rotationY: -14, rotationX: 6, rotation: 1.5 };
    var T1 = wide ? { rotationY: -9, rotationX: 3, rotation: 0 } : { rotationY: 0, rotationX: 0, rotation: 0 };
    G.set(scrs.slice(1), { autoAlpha: 0 });
    G.set(beats.slice(1), { autoAlpha: 0 });
    G.set(cos, { autoAlpha: 0, x: -12 });
    G.set(story, { autoAlpha: 0 });
    G.set(bridge, { autoAlpha: 0 });
    G.set(tilt, T0);
    var tl = G.timeline({ defaults: { ease: TK.EASE.out } });
    var NI = { immediateRender: false };
    /* the answer steps aside, the question takes its place, the phone squares up */
    tl.fromTo(fcopy, { autoAlpha: 1, y: 0 }, Object.assign({ autoAlpha: 0, y: -40, duration: 0.4, ease: 'power1.inOut' }, NI), 0);
    $$('.fc').forEach(function (c, i) {
      var dir = +c.getAttribute('data-fc');
      tl.fromTo(c, { autoAlpha: 1, xPercent: 0, yPercent: 0, scale: 1 }, Object.assign({ autoAlpha: 0, xPercent: wide ? dir * 40 : 0, yPercent: wide ? -30 : -60, scale: 0.92, duration: wide ? 0.45 : 0.3, ease: 'power1.inOut' }, NI), 0.04 + i * 0.04);
    });
    tl.fromTo(tilt, T0, Object.assign({ duration: 1.05, ease: TK.EASE.inOut }, T1, NI), 0.1);
    if (wide) {
      reelFT(tl, hClock, '07:02', BEATS[0].time, 0.3, 0.8);
      tl.fromTo(hDay._strip, { yPercent: -50 }, Object.assign({ yPercent: 0, duration: 0.5, ease: TK.EASE.inOut }, NI), 0.45);
      tl.fromTo('.f-giant', { autoAlpha: 1 }, Object.assign({ autoAlpha: 0, duration: 0.3, ease: 'none' }, NI), 1.2);
    } else {
      tl.fromTo(fdev, { y: 0 }, Object.assign({ y: lift, duration: 0.9, ease: TK.EASE.inOut }, NI), 0.3);
    }
    tl.fromTo(film, { '--amb-a': AMB[AMB.length - 1][0], '--amb-b': AMB[AMB.length - 1][1] }, Object.assign({ '--amb-a': AMB[0][0], '--amb-b': AMB[0][1], duration: 0.9, ease: 'none' }, NI), 0.3);
    tl.fromTo(bridge, { autoAlpha: 0, y: 26 }, Object.assign({ autoAlpha: 1, y: 0, duration: 0.3 }, NI), 0.3)
      .fromTo(bridge, { autoAlpha: 1, y: 0 }, Object.assign({ autoAlpha: 0, y: -22, duration: 0.22, ease: 'power1.inOut' }, NI), R - 0.42);
    /* screens push up like iOS: the new one is opaque and slides over the old, so text never overlaps */
    tl.fromTo(scrs[0], { opacity: 1, scale: 1 }, Object.assign({ opacity: 0.2, scale: 0.94, duration: 0.42, ease: TK.EASE.inOut }, NI), R - 0.62);
    tl.fromTo(scrs[1], { autoAlpha: 1, yPercent: 100 }, Object.assign({ autoAlpha: 1, yPercent: 0, duration: 0.42, ease: TK.EASE.inOut }, NI), R - 0.62);
    tl.fromTo(story, { autoAlpha: 0, y: 24 }, { autoAlpha: 1, y: 0, duration: 0.3, stagger: 0.04 }, R - 0.2);
    /* the day */
    beatAnim(0, ph, tl, R);
    tl.fromTo(cos[0], { autoAlpha: 0, x: -12 }, { autoAlpha: 1, x: 0, duration: 0.25 }, R + 0.55);
    for (var i = 1; i < BEATS.length; i++) {
      var at = R + i * S - 0.15;
      TK.setClock(dClock, BEATS[i].time, { tl: tl, at: at, dur: 0.35 });
      if (BEATS[i].day !== BEATS[i - 1].day) TK.setWord(dDay, BEATS[i].day, { tl: tl, at: at, dur: 0.35 });
      tl.to(film, { '--amb-a': AMB[i][0], '--amb-b': AMB[i][1], duration: 0.5, ease: 'none' }, at);
      tl.to(beats[i - 1], { autoAlpha: 0, y: -18, filter: 'blur(6px)', duration: 0.2, ease: 'power1.inOut' }, at)
        .fromTo(beats[i], { autoAlpha: 0, y: 22, filter: 'blur(6px)' }, { autoAlpha: 1, y: 0, filter: 'blur(0px)', duration: 0.3 }, at + 0.15);
      tl.to(cos[i - 1], { autoAlpha: 0, x: 8, duration: 0.15, ease: 'power1.inOut' }, at)
        .fromTo(scrs[i], { autoAlpha: 1, scale: 1 }, Object.assign({ autoAlpha: 0.2, scale: 0.94, duration: 0.42, ease: TK.EASE.inOut }, NI), at)
        .fromTo(scrs[i + 1], { autoAlpha: 1, yPercent: 100 }, Object.assign({ autoAlpha: 1, yPercent: 0, duration: 0.42, ease: TK.EASE.inOut }, NI), at);
      beatAnim(i, ph, tl, R + i * S);
      tl.fromTo(cos[i], { autoAlpha: 0, x: -12 }, { autoAlpha: 1, x: 0, duration: 0.25 }, R + i * S + 0.55);
    }
    tl.to({}, { duration: R + BEATS.length * S + 0.3 - tl.duration() });
    var last = -2;
    function ui(t) {
      var s = (t - R) / S, idx = Math.max(0, Math.min(BEATS.length - 1, Math.floor(s + 0.04))), hero = t < R - 0.4;
      rail.forEach(function (b, k) {
        b.style.setProperty('--f', Math.max(0, Math.min(1, s - k)).toFixed(3));
        if (k === idx && !hero) b.setAttribute('aria-current', 'step'); else b.removeAttribute('aria-current');
      });
      scrs[0].style.visibility = t < R - 0.2 ? 'visible' : 'hidden';
      var key = hero ? -1 : idx;
      if (key !== last) {
        last = key;
        sbTime.textContent = hero ? '07:02' : BEATS[idx].time;
        dn.textContent = idx + 1;
        var tab = hero ? 'today' : BEATS[idx].tab;
        tabs.forEach(function (tb) { tb.classList.toggle('on', tb.getAttribute('data-tab') === tab); });
        tabbar.style.opacity = tab ? '' : '0';
        if (!hero) announce(idx);
      }
    }
    tl.eventCallback('onUpdate', function () { ui(tl.time()); });
    var trig = ScrollTrigger.create({
      trigger: '.f-stage', start: 'top top', end: function () { return '+=' + Math.round(window.innerHeight * 0.52 * tl.duration()); },
      pin: true, scrub: wide ? 0.8 : 0.5, animation: tl, invalidateOnRefresh: true,
      onUpdate: function (self) { if (heroTL.progress() < 1 && self.progress > 0.002) heroTL.progress(1); }
    });
    ui(0);
    function go(k) {
      var y = trig.start + (trig.end - trig.start) * (R + k * S + 1) / tl.duration();
      var sm = TK.smoother();
      if (sm) sm.scrollTo(y, true); else window.scrollTo({ top: y, behavior: 'smooth' });
    }
    rail.forEach(function (b) { b.addEventListener('click', function () { go(+b.getAttribute('data-go')); }); });
    $('[data-day-link]').addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); go(0); }, true);
  }
  function announce(i) { live.textContent = BEATS[i].day + ' ' + BEATS[i].time + '. ' + $('.beat[data-i="' + i + '"] h3').textContent + ' ' + BEATS[i].line; }

  /* ---------- FLOW: the moments stack, each with its own phone ---------- */
  function setupFlow() {
    var cur = -1;
    $$('.beat').forEach(function (b, i) {
      var tl = G ? G.timeline({ paused: true }) : null;
      if (tl) beatAnim(i, b, tl, 0);
      if (tl && !motion()) tl.progress(1);
      TK.whenVisible(b, function (on) { if (on && tl && motion() && !tl._played) { tl._played = true; tl.play(0); } }, { threshold: 0.35 });
      TK.whenVisible(b, function (on) {
        if (!on || cur === i) return;
        cur = i;
        film.style.setProperty('--amb-a', AMB[i][0]); film.style.setProperty('--amb-b', AMB[i][1]);
      }, { rootMargin: '-45% 0px -45% 0px' });
    });
  }
  var beatAnim = function (i, scope, tl, at) {
    TracendBeats.anim(BEATS[i].id, scope, tl, at);
    var beat = $('.beat[data-i="' + i + '"]'), s = $('.pf-was s', beat), n = $('.pf-now', beat);
    tl.fromTo(s, { '--s': '0%' }, { '--s': '100%', duration: 0.22, ease: 'power1.inOut' }, at + 0.3)
      .fromTo(n, { autoAlpha: 0, x: -8 }, { autoAlpha: 1, x: 0, duration: 0.22 }, at + 0.48);
  };

  /* ---------- The app assembles ---------- */
  function assemble() {
    var tiles = $$('.bento .tile'), was = $$('.bento .was s'), tags = $$('.bento .was');
    var ha = $('.cx-h .h-a'), hb = $('.cx-h .h-b');
    var tl = G.timeline({ scrollTrigger: { trigger: '.bento', start: 'top 92%', end: 'top 20%', scrub: 0.8 } });
    if (TK.desk.matches) {
      var from = [[-90, 120, -5], [0, 200, 0], [110, 140, 6], [-140, 40, 4], [140, 60, -4], [0, 160, 2]];
      tiles.forEach(function (t, i) {
        tl.fromTo(t, { x: from[i][0], y: from[i][1], rotation: from[i][2], scale: 0.9, autoAlpha: 0.3 }, { x: 0, y: 0, rotation: 0, scale: 1, autoAlpha: 1, duration: 0.7, ease: 'power2.out' }, 0);
      });
    } else {
      tl.fromTo(tiles, { y: 30, autoAlpha: 0.4 }, { y: 0, autoAlpha: 1, duration: 0.5, stagger: 0.05 }, 0);
    }
    tl.fromTo(was, { '--s': '0%' }, { '--s': '100%', duration: 0.15, stagger: 0.02, ease: 'none' }, 0.55)
      .fromTo(tags, { autoAlpha: 1, y: 0 }, { autoAlpha: 0, y: -8, duration: 0.15, stagger: 0.02 }, 0.78)
      .fromTo(ha, { autoAlpha: 1, y: 0 }, { autoAlpha: 0, y: -20, duration: 0.15 }, 0.62)
      .fromTo(hb, { autoAlpha: 0, y: 24 }, { autoAlpha: 1, y: 0, duration: 0.2 }, 0.72);
  }


  /* ---------- Body map: the week on the muscle map ---------- */
  var WEEK = [
    { day: 'Monday', state: 'done', name: 'Legs', rows: [['glutes', 'Glutes', 'Back squat, Romanian deadlift', 10], ['quads', 'Quads', 'Back squat, Leg press', 8], ['hamstrings', 'Hamstrings', 'Romanian deadlift, Leg curl', 8], ['calves', 'Calves', 'Calf raise', 4]] },
    { day: 'Tuesday', state: 'today, adjusted', name: 'Pull', rows: [['back', 'Back', 'Deadlift, Pull-up, Row', 9], ['biceps', 'Biceps', 'Pull-up, Curl', 6], ['hamstrings', 'Hamstrings', 'Deadlift', 3]] },
    { day: 'Thursday', state: 'planned', name: 'Push', rows: [['chest', 'Chest', 'Bench press, Incline press', 10], ['shoulders', 'Shoulders', 'Overhead press, Lateral raise', 8], ['triceps', 'Triceps', 'Dips, Pushdown', 6]] },
    { day: 'Saturday', state: 'planned', name: 'Arms and core', rows: [['biceps', 'Biceps', 'Hammer curl', 6], ['triceps', 'Triceps', 'Skull crusher', 6], ['core', 'Core', 'Plank, Cable crunch', 6]] }
  ];
  function setupBody() {
    var figs = $$('.bm-figs svg').map(function (s) { Body.build(s, s.getAttribute('data-v')); return s; });
    var tabs = $$('.wk button'), list = $('[data-bm-list]'), head = $('[data-bm-head]');
    var cur = -1, timer = null, auto = motion(), bar = null;
    function show(i, instant) {
      if (i === cur) return;
      var prev = cur >= 0 ? WEEK[cur].rows.map(function (r) { return r[0]; }) : [];
      var next = WEEK[i].rows.map(function (r) { return r[0]; });
      cur = i;
      tabs.forEach(function (t, k) { t.setAttribute('aria-selected', String(k === i)); });
      head.innerHTML = WEEK[i].day + ', ' + WEEK[i].state + '<b>' + WEEK[i].name + '</b>';
      list.innerHTML = WEEK[i].rows.map(function (r) { return '<li><i></i><span><b>' + r[1] + '</b><small>' + r[2] + '</small></span><em class="a-num"><span data-sets>' + r[3] + '</span> sets</em></li>'; }).join('');
      figs.forEach(function (s) {
        var off = prev.filter(function (g) { return next.indexOf(g) < 0; });
        var on = Body.groupEls(s, 'o-plan', next), glow = Body.groupEls(s, 'o-glow', next);
        if (instant || !motion()) { Body.paint(s, { plan: next }); return; }
        G.to(Body.groupEls(s, 'o-plan', off).concat(Body.groupEls(s, 'o-glow', off)), { attr: { opacity: 0 }, duration: 0.35, ease: 'power1.out', overwrite: true });
        G.to(on, { attr: { opacity: 1 }, duration: 0.5, stagger: 0.02, ease: TK.EASE.out, overwrite: true });
        G.to(glow, { attr: { opacity: 0.5 }, duration: 0.7, overwrite: true });
      });
      if (motion() && !instant) {
        G.from($$('li', list), { y: 12, autoAlpha: 0, duration: 0.45, stagger: 0.06 });
        $$('[data-sets]', list).forEach(function (el) { TK.countUp(el, +el.textContent, { dur: 0.7 }); });
      }
    }
    function cycle() {
      if (!auto) return;
      if (bar) bar.kill();
      var b = $('.prog i', tabs[cur]);
      bar = G.fromTo(b, { scaleX: 0 }, { scaleX: 1, duration: 3.2, ease: 'none', onComplete: function () { show((cur + 1) % WEEK.length); cycle(); } });
    }
    tabs.forEach(function (t, k) {
      t.addEventListener('click', function () { auto = false; if (bar) bar.kill(); G.set($$('.prog i'), { scaleX: 0 }); show(k); });
      t.addEventListener('keydown', function (e) {
        var d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return; e.preventDefault(); var n = (k + d + tabs.length) % tabs.length; tabs[n].focus(); tabs[n].click();
      });
    });
    show(0, true);
    if (motion()) TK.whenVisible($('.bm'), function (on) { if (on && auto && !bar) cycle(); else if (bar) bar.paused(!on); }, { threshold: 0.4 });
  }

  /* ---------- Coach chat: the answer streams in, then its evidence ---------- */
  var CHAT = [
    { q: 'Why lighter today?', a: 'You slept 6 h 12 m, about an hour under your normal, right after squats at effort 9. Your HRV and resting heart rate are normal, so it is not a rest day. Deadlift 3 \u00d7 3 at 140 kg keeps the pattern without digging the hole deeper.',
      ev: [['Sleep 6 h 12 m', 'amber'], ['Squat 5 \u00d7 5, effort 9', 'amber'], ['HRV 52 ms, normal', 'lime'], ['Resting HR 58, normal', 'lime']] },
    { q: 'How did I eat yesterday?', a: '148 of 160 g protein and 2,140 kcal, close to both targets. Dinner did the heavy lifting with 52 g of protein, from one photo you confirmed.',
      ev: [['Protein 148 of 160 g', 'lime'], ['2,140 of 2,600 kcal', 'lime'], ['Dinner, confirmed 20:30', 'lime']] },
    { q: 'Am I still losing weight?', a: 'Yes. Your 28-day trend is down about 0.3 kg a week, 3.3 kg since 21 July. That pace protects your strength, so nothing needs to change.',
      ev: [['Weight trend, 12 weeks', 'lime'], ['77.3 kg this morning', 'lime'], ['Gap: no weigh-in Sunday', 'mute']] }
  ];
  function setupCoach() {
    var slot = $('[data-cc-phone]');
    slot.innerHTML = A.phone({ screens: ['coach'], time: '07:10', tab: 'coach', cls: 'cc-phone' });
    var cph = slot.querySelector('.phone'); deepen(cph); setPwn(cph, Math.round(Math.min(330, window.innerWidth * 0.7)));
    var thread = $('[data-thread]', slot), btns = $$('.cq button'), live = $('[data-cc-live]'), tl = null, started = false;
    function render(i) {
      var c = CHAT[i];
      btns.forEach(function (b, k) { b.setAttribute('aria-pressed', String(k === i)); });
      thread.innerHTML = '<p class="q-bub">' + c.q + '</p><div class="typing"><i></i><i></i><i></i></div>' +
        '<p class="a-txt">' + c.a.split(' ').map(function (w) { return '<span class="w">' + w + '</span>'; }).join(' ') + '</p>' +
        '<div class="ev"><p>Evidence used and data gaps<svg viewBox="0 0 16 16"><path d="M4 6l4 4 4-4"/></svg></p><div class="chips">' +
        c.ev.map(function (e) { return '<span class="a-chip ' + e[1] + '"><i></i><span>' + e[0] + '</span></span>'; }).join('') + '</div></div>';
      live.textContent = c.q + ' ' + c.a;
      var words = $$('.w', thread), typing = $('.typing', thread), ev = $('.ev', thread);
      if (tl) tl.kill();
      if (!motion()) { G && G.set(words, { opacity: 1 }); typing.remove(); return; }
      tl = G.timeline();
      tl.from($('.q-bub', thread), { y: 16, autoAlpha: 0, scale: 0.96, transformOrigin: '100% 100%', duration: 0.4 })
        .fromTo(typing, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.2 }, 0.3)
        .to($$('i', typing), { y: -4, duration: 0.25, stagger: { each: 0.12, repeat: 3, yoyo: true }, ease: 'sine.inOut' }, 0.35)
        .to(typing, { autoAlpha: 0, height: 0, padding: 0, duration: 0.15 }, 1.3)
        .to(words, { opacity: 1, duration: 0.12, stagger: 0.035, ease: 'none' }, 1.35)
        .from(ev, { y: 14, autoAlpha: 0, duration: 0.45 }, '>-0.05')
        .from($$('.a-chip', ev), { y: 8, autoAlpha: 0, duration: 0.3, stagger: 0.06 }, '<0.15');
    }
    btns.forEach(function (b, k) { b.addEventListener('click', function () { started = true; render(k); }); });
    if (!motion()) { render(0); return; }
    TK.whenVisible($('.cc'), function (on) { if (on && !started) { started = true; render(0); } }, { threshold: 0.45 });
  }

  /* ---------- Progress: weight, strength, the weekly review, the physique check ---------- */
  function setupProgress() {
    var slot = $('[data-pg]'), I = A.icon, P = D.plan;
    var TAP = '<i class="gp-t"></i>';
    var head = '<div class="a-head"><h3>Progress<span class="sub">' + P.name + ' &middot; week ' + P.week + ' of ' + P.weeks + '</span></h3></div>';
    /* weekly weigh-ins, 12 weeks, from the plan's start to now */
    var W = [80.6, 80.3, 80.4, 79.9, 79.6, 79.7, 79.2, 78.8, 78.9, 78.4, 78.0, 77.6, 77.3];
    var x = function (k) { return 8 + k * (324 / (W.length - 1)); }, y = function (v) { return 10 + (81.2 - v) / 6.6 * 120; };
    var pts = W.map(function (v, k) { return x(k).toFixed(1) + ' ' + y(v).toFixed(1); });
    var chart = '<svg class="pg-chart" viewBox="0 0 340 140"><line x1="0" x2="340" y1="' + y(75) + '" y2="' + y(75) + '" stroke="#C8F05A" stroke-opacity=".5" stroke-dasharray="4 5"/>' +
      '<text x="340" y="' + (y(75) - 6) + '" text-anchor="end" fill="#C8F05A" font-size="12" font-weight="600">Goal 75 kg</text>' +
      '<path data-line d="M' + pts.join(' L') + '" fill="none" stroke="#F4F4F1" stroke-width="2.4" stroke-linejoin="round" stroke-linecap="round"/>' +
      W.map(function (v, k) { return '<circle cx="' + x(k).toFixed(1) + '" cy="' + y(v).toFixed(1) + '" r="' + (k === W.length - 1 ? 4.5 : 2.6) + '" fill="' + (k === W.length - 1 ? '#C8F05A' : '#6E6F6A') + '"/>'; }).join('') + '</svg>';
    var s0 = '<section class="scr" data-p="0">' + head + '<div class="pg-seg"><span>4W</span><span class="on">12W</span><span>6M</span></div>' +
      '<div class="a-card"><p class="a-kicker">Weight &middot; today</p><p class="pg-big"><span data-pw>80.6</span><small>kg</small></p>' +
      '<div class="pg-chips"><span class="a-chip fill">&darr; 3.3 kg, toward your goal</span><span class="a-chip">0.3 kg a week</span><span class="a-chip">Steady</span></div>' + chart + '</div>' +
      '<div class="pg-list"><p><span>Today</span><b>77.3 kg</b></p><p><span>Friday</span><b>77.6 kg</b></p><p><span>Waist, since week 1</span><b>&minus;4.2 cm</b></p></div></section>';
    var s1 = '<section class="scr" data-p="1">' + head + '<p class="sec-label">Strength</p>' +
      '<div class="a-card"><p class="a-kicker">Workouts, last 12 weeks</p><p class="pg-done"><span data-wd>0</span> of 48<small>done</small></p><div class="bar"><i data-wb style="--v:0"></i></div></div>' +
      '<p class="sec-label">Best lifts</p><div class="pg-list pg-lifts"><p><span>Back squat</span><b>120 kg &times; 5<em data-nb>New best</em></b></p><p><span>Deadlift</span><b>160 kg &times; 3</b></p><p><span>Bench press</span><b>85 kg &times; 6</b></p><p><span>Pull-up</span><b>+10 kg &times; 6</b></p></div></section>';
    var s2 = '<section class="scr" data-p="2"><div class="a-head"><h3>Week 12 review<span class="sub">6 to 12 October</span></h3></div>' +
      '<span class="pg-noai">Calculated from your logs. No AI.</span>' +
      '<div class="pg-list pg-rv"><p><span>Workouts</span><b>4 of 4</b></p><p><span>Protein target</span><b>6 of 7 days</b></p><p><span>Sleep</span><b>6 h 38 m, 42 m short</b></p><p><span>Weight</span><b>&minus;0.3 kg</b></p><p><span>Waist</span><b>&minus;0.4 cm</b></p><p><span>Unchanged</span><b>Plan and targets</b></p></div>' +
      '<div class="pg-focus"><p class="k">Next week&rsquo;s focus</p><p class="v">Protect sleep before Monday&rsquo;s legs. Keep protein at 160 g.</p></div>' +
      '<span class="pg-pill" data-rev><span>Mark reviewed</span><span>Reviewed</span>' + TAP + '</span></section>';
    var s3 = '<section class="scr" data-p="3"><div class="a-head"><h3>Physique check<span class="sub">Photo set, 12 October</span></h3></div>' +
      '<span class="pg-est">AI visual estimate, not a measurement</span>' +
      '<div class="pg-photos"><div class="pg-ph"><svg data-v="front"></svg><span>Front</span><i class="scan"></i></div><div class="pg-ph"><svg data-v="front" style="transform:scaleX(.62)"></svg><span>Side</span><i class="scan"></i></div><div class="pg-ph"><svg data-v="back"></svg><span>Back</span><i class="scan"></i></div></div>' +
      '<div class="pg-res"><p data-pick><i class="bx">' + I.check + '</i><span><b>Upper back</b><small>Bring up &middot; medium confidence</small></span></p><p data-pick><i class="bx">' + I.check + '</i><span><b>Calves</b><small>Bring up &middot; medium confidence</small></span></p><p><i class="bx">' + I.check + '</i><span><b>Shoulders</b><small>Well developed &middot; high confidence</small></span></p></div>' +
      '<span class="pg-pill" data-use>Use as my focus' + TAP + '</span>' +
      '<div class="pg-toast"><b>Focus: upper back and calves</b>The Coach uses it now, and your plan at its next review.</div></section>';
    slot.innerHTML = '<div class="phone app pg-phone"><i class="rim"></i><i class="btns"></i><div class="screen"><span class="island"></span>' + A.statusBar('19:05') +
      '<div class="screens">' + s0 + s1 + s2 + s3 + '</div>' + A.tabBar('progress') + '<span class="homebar"></span></div></div>';
    var pph = $('.pg-phone', slot);
    deepen(pph);
    function size() { setPwn(pph, Math.round(Math.min(330, window.innerWidth * 0.7))); }
    size(); window.addEventListener('resize', size);
    var figs = $$('.pg-ph svg', pph).map(function (s) { Body.build(s, s.getAttribute('data-v')); return s; });
    var scr = $$('.scr', pph), steps = $$('.pg-steps button'), live = $('[data-pg-live]');
    var LAB = [0, 4.2, 8.4, 12.6], END = 17.6;
    if (!G) return;
    var tl = G.timeline({ paused: true, repeat: -1, repeatDelay: 0.4, defaults: { ease: TK.EASE.out, immediateRender: false } });
    function tap(el, at) {
      var t = $('.gp-t', el);
      tl.fromTo(t, { scale: 0.6, autoAlpha: 0 }, { scale: 1, autoAlpha: 1, duration: 0.16 }, at).to(t, { scale: 1.3, autoAlpha: 0, duration: 0.3, ease: 'power1.out' }, at + 0.2)
        .fromTo(el, { scale: 1 }, { scale: 0.96, duration: 0.08, ease: 'power2.out' }, at + 0.02).to(el, { scale: 1, duration: 0.25, ease: TK.EASE.spring }, at + 0.11);
    }
    function push(i, at) {
      tl.fromTo(scr[i], { autoAlpha: 1, scale: 1 }, { autoAlpha: 0.2, scale: 0.94, duration: 0.45, ease: TK.EASE.inOut }, at)
        .fromTo(scr[i + 1], { autoAlpha: 1, yPercent: 100 }, { autoAlpha: 1, yPercent: 0, duration: 0.45, ease: TK.EASE.inOut }, at);
    }
    function count(el, from, to, at, dur, fmt) { var o = { v: from }; tl.fromTo(o, { v: from }, { v: to, duration: dur, ease: 'power2.out', onUpdate: function () { el.textContent = fmt(o.v); } }, at); }
    tl.set(scr.slice(1), { autoAlpha: 1, yPercent: 100 }, 0).set(scr[0], { autoAlpha: 1, scale: 1, yPercent: 0 }, 0);
    /* 01 weight */
    var line = $('[data-line]', scr[0]), L = line.getTotalLength();
    line.style.strokeDasharray = L;
    tl.fromTo(line, { strokeDashoffset: L }, { strokeDashoffset: 0, duration: 1.4, ease: 'power1.inOut' }, 0.3)
      .fromTo($$('.pg-chart circle', scr[0]), { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.2, stagger: 0.1 }, 0.3);
    count($('[data-pw]', scr[0]), 80.6, 77.3, 0.3, 1.4, function (v) { return v.toFixed(1); });
    tl.fromTo($$('.pg-chips .a-chip', scr[0]), { autoAlpha: 0, y: 6 }, { autoAlpha: 1, y: 0, duration: 0.3, stagger: 0.08 }, 1.6);
    /* 02 strength */
    push(0, 4.2);
    count($('[data-wd]', scr[1]), 0, 46, 4.7, 0.9, function (v) { return Math.round(v); });
    tl.fromTo($('[data-wb]', scr[1]), { '--v': 0 }, { '--v': 46 / 48, duration: 0.9, ease: 'power2.out' }, 4.7)
      .fromTo($$('.pg-lifts p', scr[1]), { autoAlpha: 0, x: -10 }, { autoAlpha: 1, x: 0, duration: 0.3, stagger: 0.09 }, 5.2)
      .fromTo($('[data-nb]', scr[1]), { autoAlpha: 0, scale: 0.8 }, { autoAlpha: 1, scale: 1, duration: 0.3, ease: TK.EASE.spring }, 6.0);
    /* 03 weekly review */
    push(1, 8.4);
    tl.fromTo($$('.pg-rv p', scr[2]), { autoAlpha: 0, x: -10 }, { autoAlpha: 1, x: 0, duration: 0.28, stagger: 0.08 }, 8.9)
      .fromTo($('.pg-focus', scr[2]), { autoAlpha: 0, y: 10 }, { autoAlpha: 1, y: 0, duration: 0.35 }, 9.5);
    var rev = $('[data-rev]', scr[2]);
    tap(rev, 10.8);
    tl.fromTo(rev.children[0], { autoAlpha: 1 }, { autoAlpha: 0, duration: 0.15 }, 10.9).fromTo(rev.children[1], { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.2 }, 11.0)
      .fromTo(rev, { backgroundColor: '#C8F05A', color: '#141A05' }, { backgroundColor: '#232427', color: '#F4F4F1', duration: 0.25 }, 10.95);
    /* 04 physique check: scan, suggest, choose the focus */
    push(2, 12.6);
    tl.fromTo($$('.pg-ph i.scan', scr[3]), { autoAlpha: 1, top: '0%' }, { autoAlpha: 1, top: '100%', duration: 1.0, ease: 'power1.inOut', stagger: 0.12 }, 13.0)
      .to($$('.pg-ph i.scan', scr[3]), { autoAlpha: 0, duration: 0.2 }, 14.2)
      .fromTo($$('.pg-res p', scr[3]), { autoAlpha: 0, y: 8 }, { autoAlpha: 1, y: 0, duration: 0.28, stagger: 0.09 }, 14.2);
    $$('[data-pick]', scr[3]).forEach(function (p, k) {
      var bx = $('.bx', p);
      tl.fromTo(bx, { backgroundColor: 'rgba(200,240,90,0)', boxShadow: 'inset 0 0 0 1.5px #2A2B2F' }, { backgroundColor: 'rgba(200,240,90,1)', boxShadow: 'inset 0 0 0 1.5px rgba(200,240,90,1)', duration: 0.15 }, 15.0 + k * 0.25)
        .fromTo($('svg', bx), { opacity: 0 }, { opacity: 1, duration: 0.15 }, 15.0 + k * 0.25);
    });
    figs.forEach(function (s) {
      tl.fromTo(Body.groupEls(s, 'o-plan', ['back', 'calves']), { attr: { opacity: 0 } }, { attr: { opacity: 1 }, duration: 0.4 }, 15.1);
    });
    tap($('[data-use]', scr[3]), 15.9);
    tl.fromTo($('.pg-toast', scr[3]), { autoAlpha: 0, y: 16 }, { autoAlpha: 1, y: 0, duration: 0.35 }, 16.2);
    tl.to({}, { duration: 0.01 }, END);
    var lastIdx = -1;
    tl.eventCallback('onUpdate', function () {
      var t = tl.time(), idx = t >= LAB[3] ? 3 : t >= LAB[2] ? 2 : t >= LAB[1] ? 1 : 0, end = idx < 3 ? LAB[idx + 1] : END;
      steps.forEach(function (bt, k) { $('.prog i', bt).style.transform = 'scaleX(' + (k === idx ? Math.min(1, (t - LAB[k]) / (end - LAB[k])).toFixed(3) : 0) + ')'; });
      if (idx !== lastIdx) { lastIdx = idx; steps.forEach(function (bt, k) { bt.setAttribute('aria-selected', String(k === idx)); }); }
    });
    steps.forEach(function (bt, k) {
      bt.addEventListener('click', function () {
        live.textContent = $('span', bt).textContent + ': ' + $('em', bt).textContent;
        if (motion()) tl.play(LAB[k] + 0.01); else tl.pause(k < 3 ? LAB[k + 1] - 0.05 : END, false);
      });
      bt.addEventListener('keydown', function (e) {
        var d = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return; e.preventDefault(); var n = (k + d + steps.length) % steps.length; steps[n].focus(); steps[n].click();
      });
    });
    if (!motion()) { tl.pause(END, false); return; }
    tl.pause(0);
    TK.whenVisible($('.pg'), function (on) { if (on) tl.play(); else tl.pause(); }, { threshold: 0.3 });
  }

  /* ---------- Made for you: two example athletes, one card that re-plans ---------- */
  var ATH = [
    { ini: 'K', name: 'Kabir, 22', sub: '2 years training, gym', tags: [['Build muscle', 'lime'], ['5 days, 75 min', '']], days: [0, 1, 2, 4, 5],
      rows: [['Mon', 'Bench press', '4 &times; 6 &middot; RPE 8.5'], ['Tue', 'Weighted pull-up', '4 &times; 6'], ['Wed', 'Back squat', '5 &times; 5 &middot; <em>Start at 100 kg</em>'], ['Fri', 'Incline press', '4 &times; 8'], ['Sat', 'Romanian deadlift', '4 &times; 8']],
      kcal: 3100, protein: 150, why: '<b>Recovers fast, ready for volume.</b> Five days, heavy compounds and a small surplus to build size.' },
    { ini: 'A', name: 'Anita, 45', sub: 'Back after a long break, home', tags: [['Lose fat', 'lime'], ['3 days, 45 min', ''], ['Avoid: deep squats, knee', 'warn']], days: [0, 2, 4],
      rows: [['Mon', 'Box squat to a bench', '3 &times; 10 &middot; RPE 7'], ['Wed', 'Dumbbell Romanian deadlift', '3 &times; 10'], ['Fri', 'Split squat, short range', '3 &times; 8 each']],
      kcal: 1750, protein: 120, why: '<b>Joints first.</b> No deep squats, a rest day between sessions, and high protein to keep muscle while losing fat.' }
  ];
  function setupPeople() {
    var card = $('[data-ys]'), sw = $('.ys-sw'), btns = $$('.ys-sw button'), cur = -1, timer = null, auto = motion();
    function html(a) {
      var wk = 'MTWTFSS'.split('').map(function (d, k) { return '<i' + (a.days.indexOf(k) >= 0 ? ' class="on"' : '') + '>' + d + '</i>'; }).join('');
      return '<div class="ys-in"><div class="ys-who"><span class="ys-av">' + a.ini + '</span><span class="ys-nm"><b>' + a.name + '</b><span>' + a.sub + '</span></span></div>' +
        '<div class="ys-tags">' + a.tags.map(function (t) { return '<span class="a-chip ' + t[1] + '"><i></i><span>' + t[0] + '</span></span>'; }).join('') + '</div>' +
        '<div class="ys-week" aria-label="Training days">' + wk + '</div>' +
        '<div class="ys-rows">' + a.rows.map(function (r) { return '<p><b>' + r[0] + '</b><span>' + r[1] + '</span><small>' + r[2] + '</small></p>'; }).join('') + '</div>' +
        '<div class="ys-nut"><div><span>Every day</span><b data-k>' + a.kcal.toLocaleString('en-US') + '</b> kcal</div><div><span>Protein</span><b data-pr>' + a.protein + '</b> g</div></div>' +
        '<p class="ys-why"><i>' + A.icon.spark + '</i><span>' + a.why + '</span></p></div>';
    }
    function show(i, user) {
      if (i === cur) return;
      var prev = cur >= 0 ? ATH[cur] : null; cur = i;
      sw.setAttribute('data-on', i);
      btns.forEach(function (b, k) { b.setAttribute('aria-selected', String(k === i)); });
      var swap = function () {
        card.innerHTML = html(ATH[i]);
        if (!motion() || !prev) return;
        var inn = $('.ys-in', card);
        G.from(inn.children, { y: 14, autoAlpha: 0, duration: 0.45, stagger: 0.05 });
        G.from($$('.ys-week i.on', card), { scale: 0.7, duration: 0.35, stagger: 0.04, ease: TK.EASE.spring });
        TK.countUp($('[data-k]', card), ATH[i].kcal, { from: prev.kcal, dur: 0.8, fmt: function (v) { return Math.round(v).toLocaleString('en-US'); } });
        TK.countUp($('[data-pr]', card), ATH[i].protein, { from: prev.protein, dur: 0.8 });
      };
      if (motion() && prev) G.to($('.ys-in', card).children, { y: -10, autoAlpha: 0, duration: 0.2, stagger: 0.02, ease: 'power1.in', onComplete: swap, overwrite: true });
      else swap();
    }
    function cycle() { clearTimeout(timer); if (auto) timer = setTimeout(function () { show(1 - cur); cycle(); }, 5200); }
    btns.forEach(function (b, k) {
      b.addEventListener('click', function () { auto = false; clearTimeout(timer); show(k, true); });
      b.addEventListener('keydown', function (e) {
        var d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return; e.preventDefault(); var n = (k + d + 2) % 2; btns[n].focus(); btns[n].click();
      });
    });
    show(0);
    if (motion()) TK.whenVisible($('.ys'), function (on) { if (on && auto) cycle(); else clearTimeout(timer); }, { threshold: 0.4 });
  }

  /* ---------- Start: goal, getting to know you, the approved plan, one looping film ---------- */
  function setupStart() {
    var slot = $('[data-st]'), S = D.start;
    slot.innerHTML = A.phone({ cls: 'st-phone', time: S[0].time, tab: null, screens: S.map(function (b) { return b.scr; }) });
    var sph = $('.st-phone', slot), scr = $$('.scr', sph), sbTime = $('[data-sbtime]', sph);
    var steps = $$('#start .nx-steps button'), live = $('[data-st-live]');
    deepen(sph);
    function size() { setPwn(sph, Math.round(Math.min(330, window.innerWidth * 0.7))); }
    size(); window.addEventListener('resize', size);
    if (!G) return;
    var STEP = 5.2, END = STEP * S.length, NI = { immediateRender: false };
    var tl = G.timeline({ paused: true, repeat: -1, repeatDelay: 0.4, defaults: { ease: TK.EASE.out } });
    tl.set(scr.slice(1), { autoAlpha: 1, yPercent: 100 }, 0).set(scr[0], { autoAlpha: 1, scale: 1, yPercent: 0 }, 0);
    S.forEach(function (b, k) {
      var at = k * STEP;
      /* the next screen is opaque and slides up over the old one, like iOS */
      if (k) {
        tl.fromTo(scr[k - 1], { autoAlpha: 1, scale: 1 }, Object.assign({ autoAlpha: 0.2, scale: 0.94, duration: 0.45, ease: TK.EASE.inOut }, NI), at)
          .fromTo(scr[k], { autoAlpha: 1, yPercent: 100 }, Object.assign({ autoAlpha: 1, yPercent: 0, duration: 0.45, ease: TK.EASE.inOut }, NI), at);
      }
      TracendBeats.anim(b.id, sph, tl, at + (k ? 0.3 : 0));
    });
    tl.to({}, { duration: 0.01 }, END);
    var lastIdx = -1;
    tl.eventCallback('onUpdate', function () {
      var t = tl.time(), idx = Math.min(S.length - 1, Math.floor(t / STEP));
      steps.forEach(function (bt, k) { $('.prog i', bt).style.transform = 'scaleX(' + (k === idx ? Math.min(1, (t - idx * STEP) / STEP).toFixed(3) : 0) + ')'; });
      if (idx !== lastIdx) {
        lastIdx = idx; sbTime.textContent = S[idx].time;
        steps.forEach(function (bt, k) { bt.setAttribute('aria-selected', String(k === idx)); });
      }
    });
    steps.forEach(function (bt, k) {
      bt.addEventListener('click', function () {
        live.textContent = $('span', bt).textContent + ': ' + $('em', bt).textContent;
        if (motion()) tl.play(k * STEP + 0.01); else tl.pause(k < S.length - 1 ? (k + 1) * STEP - 0.05 : END, false);
      });
      bt.addEventListener('keydown', function (e) {
        var d = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return; e.preventDefault(); var n = (k + d + steps.length) % steps.length; steps[n].focus(); steps[n].click();
      });
    });
    if (!motion()) { tl.pause(END, false); return; }
    tl.pause(0);
    TK.whenVisible($('#start .nx'), function (on) { if (on) tl.play(); else tl.pause(); }, { threshold: 0.3 });
  }

  /* ---------- Demo ---------- */
  function setupDemo() {
    var inp = { sleep: $('#d-sleep'), hrv: $('#d-hrv'), rhr: $('#d-rhr') }, seg = $('[data-seg]');
    $('.controls').addEventListener('submit', function (e) { e.preventDefault(); });
    var out = function (k) { return $('[data-o="' + k + '"]'); }, d = function (k) { return $('[data-d="' + k + '"]'); };
    var ring = A.ring($('[data-ring-demo]'), { score: D.morning.score, segments: D.morning.segments });
    var shown = { s: D.morning.score }, session = 'heavy', liveT = null, prev = null;
    function hm(m) { return Math.floor(m / 60) + ' h ' + String(m % 60).padStart(2, '0') + ' m'; }
    function fill(r) { r.style.setProperty('--p', ((r.value - r.min) / (r.max - r.min) * 100) + '%'); }
    function update(first) {
      var v = { sleep: +inp.sleep.value, hrv: +inp.hrv.value, rhr: +inp.rhr.value, session: session };
      Object.keys(inp).forEach(function (k) { fill(inp[k]); });
      out('sleep').textContent = hm(v.sleep); out('hrv').textContent = v.hrv + ' ms'; out('rhr').textContent = v.rhr + ' bpm';
      inp.sleep.setAttribute('aria-valuetext', hm(v.sleep));
      var r = TracendDemo.compute(v);
      d('verdict').textContent = r.verdict; d('reason').textContent = r.reason;
      d('band').textContent = r.band; d('band').classList.toggle('good', r.good);
      d('chips').innerHTML = r.chips.map(function (c) { return '<span class="a-chip ' + c.tone + '"><i></i><span>' + c.text + '</span></span>'; }).join('');
      if (!prev || prev.plan.head !== r.plan.head) {
        if (motion() && !first) G.fromTo([d('plan-head'), d('plan-body')], { autoAlpha: 0, y: 8 }, { autoAlpha: 1, y: 0, duration: TK.T.state, stagger: 0.04 });
        d('plan-head').textContent = r.plan.head; d('plan-body').textContent = r.plan.body;
      }
      $$('i', d('lvl')).forEach(function (bar, k) { bar.style.backgroundColor = k <= 3 - r.plan.level ? (r.plan.level >= 2 ? '#F2B544' : '#C8F05A') : ''; });
      ring.set(r.score, r.segments);
      if (motion() && !first) {
        G.to(shown, { s: r.score, duration: 0.5, ease: 'power2.out', overwrite: true, onUpdate: function () { ring.set(Math.round(shown.s)); ring.draw(1); d('score').textContent = Math.round(shown.s); } });
      } else { shown.s = r.score; ring.draw(1); d('score').textContent = r.score; }
      clearTimeout(liveT);
      liveT = setTimeout(function () { d('live').textContent = 'Recovery ' + r.score + ', ' + r.verdict + '. ' + r.plan.head + ' ' + r.plan.body; }, 500);
      prev = r;
    }
    Object.keys(inp).forEach(function (k) { inp[k].addEventListener('input', function () { update(false); }); });
    seg.addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return;
      session = b.getAttribute('data-v');
      $$('button', seg).forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
      update(false);
    });
    update(true);
  }

  /* ---------- One reveal per section heading ---------- */
  function reveals() {
    $$('.sec .sec-h:not(.cx-h)').forEach(function (h) {
      if (!window.SplitText) return;
      SplitText.create(h, { type: 'lines', mask: 'lines', autoSplit: true, onSplit: function (self) {
        /* the masks clip, so give descenders (g, y, p) room without moving the lines */
        self.masks.forEach(function (m) { m.style.paddingBottom = '0.16em'; m.style.marginBottom = '-0.16em'; });
        return G.from(self.lines, { yPercent: 108, duration: 1.15, stagger: 0.09, scrollTrigger: { trigger: h, start: 'top 88%', once: true } });
      } });
    });
    $$('.sec .sec-sub, .own, .soon-row, .demo-grid, .versus, .sec-cta').forEach(function (el) {
      G.from(el, { y: 28, autoAlpha: 0, duration: TK.T.focal, scrollTrigger: { trigger: el, start: 'top 90%', once: true } });
    });
    var vsRing = $('[data-ring-vs]');
    ScrollTrigger.create({ trigger: '.versus', start: 'top 75%', once: true, onEnter: function () {
      G.from('.versus .coach-note', { autoAlpha: 0, y: 12, duration: TK.T.focal, delay: 0.5 });
      void vsRing;
    } });
  }

  /* ---------- Boot ---------- */
  setupBody(); setupCoach(); setupProgress(); setupPeople(); setupStart();
  if (!motion()) {
    setupFlow(); setupDemo();
    return;
  }
  TK.smooth();
  var heroTL = heroFilm();
  if (pinMode) setupPin(heroTL); else setupFlow();
  if (window.scrollY > 8) heroTL.progress(1);
  pointerDepth();
  assemble();
  setupDemo();
  reveals();
  window.addEventListener('resize', sizePhone);
  /* copy heights settle when the fonts land; size the phone again before triggers measure */
  ScrollTrigger.addEventListener('refreshInit', sizePhone);
  TK.refreshOnFonts();
})();
