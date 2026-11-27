/* The landing page: hero film, the day story, sections and their motion. */
(function () {
  'use strict';
  function recover(err) {
    try {
      var sm = window.TK && TK.smoother && TK.smoother();
      if (sm) sm.kill();
      if (window.ScrollTrigger) ScrollTrigger.getAll().forEach(function (t) { t.kill(true); });
      if (window.gsap) gsap.globalTimeline.clear();
      var f = document.querySelector('.film');
      if (f) f.setAttribute('data-mode', 'flow');
      Array.prototype.forEach.call(document.querySelectorAll('#main *'), function (el) { el.style.opacity = ''; el.style.visibility = ''; el.style.transform = ''; });
    } catch (e) { /* nothing more to undo */ }
    if (window.console) console.error(err);
  }
  try {
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var G = TK.G, D = window.TRACEND_DAY, A = window.TracendApp, Body = window.TracendBody;
  var motion = function () { return !!G && !TK.reduced(); };
  /* ambient light per moment: the evening gym, the night, first light, the morning */
  var AMB = [['#33291F', '#1B1F26'], ['#131A3C', '#0A0E24'], ['#2A2638', '#141B30'], ['#3A2828', '#22304A'], ['#3A3524', '#1C2A22']];
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
  if (!pinMode) $$('.beat .b-phone').forEach(function (slot, i) { slot.innerHTML = A.phone({ screens: [BEATS[i].scr], time: BEATS[i].sb || BEATS[i].time, tab: BEATS[i].tab }); });
  $$('[data-ring]').forEach(function (svg) { svg._ring = A.ring(svg, { score: D.morning.score, segments: D.morning.segments }); });
  var heroRing = $('[data-scr="today-hero"] [data-ring]')._ring;
  var dClock = TK.clock($('[data-dclock]'), BEATS[0].time);
  var dDay = TK.wordReel($('[data-dday]'), BEATS.map(function (b) { return b.day; }).filter(function (d, k, a) { return a.indexOf(d) === k; }));
  TK.setWord(dDay, BEATS[0].day, { instant: true });

  var fcopy = $('.f-copy-in'), stage = $('.f-stage');
  /* phone size follows the viewport: fitted to the height when wide; when tall, to the width,
     and never so large that less than its top three fifths show under the day's copy */
  function sizePhone() {
    var pwn = !pinMode ? Math.round(Math.min(window.innerWidth * 0.64, 290))
      : wide ? Math.round(Math.min(window.innerHeight * 0.8, 790) * 390 / 844)
        : Math.round(Math.min(window.innerWidth * 0.66, 300, Math.max(window.innerWidth * 0.56, (window.innerHeight - fdev.offsetTop) / 1.3)));
    setPwn(ph, pwn);
    fdev.style.setProperty('--pw', pwn + 'px');
    fdev.style.setProperty('--pu', (pwn / 259).toFixed(4)); /* unitless, for the banner that scales with the phone */
    /* the cards beside the phone scale with it and give way to the window: they never run into the copy
       on the left or off the right edge. 0.89 and 0.95 are the tilt's foreshortening on each side. */
    var base = Math.max(0.84, Math.min(1.1, pwn / 333)), fs = base, solo = false, hang = 14.5;
    if (window.innerWidth >= 1024) {
      var box = fdev.getBoundingClientRect(), cx = box.left + box.width / 2;
      var room = cx - (wide && pinMode ? fcopy.getBoundingClientRect().right + 28 : 16);
      var fit = ((room + 30) / 0.89 - pwn / 2) / 254;
      if (fit < base) { if (fit >= 0.8) fs = fit; else solo = true; }
      hang = Math.max(7, Math.min(14.5, ((window.innerWidth - 16 - cx) / 0.95 - pwn / 2) / fs / 16));
    }
    fdev.style.setProperty('--fs', fs.toFixed(4));
    fdev.style.setProperty('--hang', hang.toFixed(3));
    fdev.classList.toggle('fc-solo', solo);
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
    /* wide: what it read arrives in the order it happened, then the score, then its call */
    ['.fc-train', '.fc-sleep', '.fc-check'].forEach(function (c, i) {
      tl.from(c + ' .fc-in', { x: -24, y: 16, autoAlpha: 0, filter: 'blur(8px)', duration: 0.7 }, 0.35 + i * 0.22);
    });
    ring(1.0);
    tl.from('.fc-coach .fc-in', { y: 24, autoAlpha: 0, filter: 'blur(10px)', duration: 0.8 }, 1.45);
    tl.set('.fc-in', { clearProps: 'filter' });
    return tl;
  }
  function pointerDepth() {
    if (!TK.desk.matches || !wide) return;
    var dev = $('.dev'), stage = $('.f-stage');
    var rx = G.quickTo(dev, 'rotationX', { duration: 1, ease: 'power3' }), ry = G.quickTo(dev, 'rotationY', { duration: 1, ease: 'power3' });
    stage.addEventListener('pointermove', function (e) {
      var nx = e.clientX / window.innerWidth - 0.5, ny = e.clientY / window.innerHeight - 0.5;
      rx(-ny * 5); ry(nx * 7);
      ph.style.setProperty('--gx', (18 + nx * 60).toFixed(1) + '%'); ph.style.setProperty('--gy', (4 + ny * 30).toFixed(1) + '%');
    });
  }

  /* ---------- PIN: the answer, the question, then the day that led to it ---------- */
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
    if (!wide) {
      /* the phone peeks out under the form, rises a little slower than the page, and lands where the
         day's copy leaves it room just as the stage pins */
      G.fromTo(fdev, { y: function () { return -Math.max(0, fdev.offsetTop - 14); } }, { y: 0, ease: 'none',
        scrollTrigger: { trigger: stage, start: 0, end: 'top top', scrub: true, invalidateOnRefresh: true } });
    }
    var tl = G.timeline({ defaults: { ease: TK.EASE.out } });
    var NI = { immediateRender: false };
    /* the answer steps aside, the question takes its place, the phone squares up. On a laptop the copy
       fades as it scrolls off; on a phone it only scrolls, so a form someone is typing in never fades */
    if (wide) tl.fromTo(fcopy, { autoAlpha: 1, y: 0 }, Object.assign({ autoAlpha: 0, y: -40, duration: 0.4, ease: 'power1.inOut' }, NI), 0);
    $$('.fc').forEach(function (c, i) {
      var dir = +c.getAttribute('data-fc');
      /* opacity, not autoAlpha: the cards sit inside the phone's wrapper, which is still hidden when this is first measured */
      tl.fromTo(c, { opacity: 1, xPercent: 0, yPercent: 0, scale: 1 }, Object.assign({ opacity: 0, xPercent: wide ? dir * 40 : 0, yPercent: wide ? -30 : -60, scale: 0.92, duration: wide ? 0.45 : 0.3, ease: 'power1.inOut' }, NI), 0.04 + i * 0.04);
    });
    tl.fromTo(tilt, T0, Object.assign({ duration: 1.05, ease: TK.EASE.inOut }, T1, NI), 0.1);
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
        sbTime.textContent = hero ? '07:02' : BEATS[idx].sb || BEATS[idx].time;
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

  /* ---------- Coach chat: the answer streams in, then its evidence ---------- */
  var CHAT = [
    { q: 'Why lighter today?', a: 'You slept 6 h 12 m, about an hour under your normal, right after squats at effort 9. Your HRV and resting heart rate are normal, so it is not a rest day. Deadlift 3 \u00d7 3 at 140 kg keeps the pattern without digging the hole deeper.',
      ev: [['Sleep 6 h 12 m', 'amber'], ['Squat 5 \u00d7 5, effort 9', 'amber'], ['HRV 52 ms, normal', 'lime'], ['Resting HR 58, normal', 'lime']] },
    { q: 'How is my bench since August?', a: 'Up 5 kg. You pressed 80 kg \u00d7 6 on 4 August and 85 kg \u00d7 6 last Thursday. It held for two weeks in September, the same two weeks your sleep ran short.',
      ev: [['Bench press, 14 sessions', 'lime'], ['Best: 85 kg \u00d7 6', 'lime'], ['Sleep, 8 to 21 Sep', 'amber'], ['Gap: no log 2 Oct', 'mute']] },
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
    var LAB = [0, 4.2, 8.4, 12.6], END = 17.6, held = false;
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
      if (idx !== lastIdx) { lastIdx = idx; steps.forEach(function (bt, k) { bt.setAttribute('aria-pressed', String(k === idx)); }); }
    });
    steps.forEach(function (bt, k) {
      bt.addEventListener('click', function () {
        live.textContent = $('span', bt).textContent + ': ' + $('em', bt).textContent;
        /* a chosen step plays once and holds: the loop stops for good */
        held = true;
        var to = k < 3 ? LAB[k + 1] - 0.05 : END;
        if (motion()) tl.tweenFromTo(LAB[k] + 0.01, to, { ease: 'none' }); else tl.pause(to, false);
      });
      bt.addEventListener('keydown', function (e) {
        var d = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return; e.preventDefault(); var n = (k + d + steps.length) % steps.length; steps[n].focus(); steps[n].click();
      });
    });
    if (!motion()) { tl.pause(END, false); return; }
    tl.pause(0);
    TK.whenVisible($('.pg'), function (on) { if (held) return; if (on) tl.play(); else tl.pause(); }, { threshold: 0.3 });
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
    var STEP = 5.2, END = STEP * S.length, NI = { immediateRender: false }, held = false;
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
        steps.forEach(function (bt, k) { bt.setAttribute('aria-pressed', String(k === idx)); });
      }
    });
    steps.forEach(function (bt, k) {
      bt.addEventListener('click', function () {
        live.textContent = $('span', bt).textContent + ': ' + $('em', bt).textContent;
        held = true;
        var to = k < S.length - 1 ? (k + 1) * STEP - 0.05 : END;
        if (motion()) tl.tweenFromTo(k * STEP + 0.01, to, { ease: 'none' }); else tl.pause(to, false);
      });
      bt.addEventListener('keydown', function (e) {
        var d = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
        if (!d) return; e.preventDefault(); var n = (k + d + steps.length) % steps.length; steps[n].focus(); steps[n].click();
      });
    });
    if (!motion()) { tl.pause(END, false); return; }
    tl.pause(0);
    TK.whenVisible($('#start .nx'), function (on) { if (held) return; if (on) tl.play(); else tl.pause(); }, { threshold: 0.3 });
  }

  /* ---------- Phones: one Join button in thumb reach once the hero form has scrolled away ---------- */
  function dockCta() {
    var btn = $('.dock-cta'), hero = $('.f-copy .join-wrap'), close = $('#join');
    if (!btn || !hero || !close || !('IntersectionObserver' in window)) return;
    var seen = { hero: true, close: false }, typing = false;
    function set() {
      var on = !seen.hero && !seen.close && !typing;
      btn.classList.toggle('on', on);
      document.documentElement.classList.toggle('docked', on);
      btn.setAttribute('aria-hidden', String(!on));
      btn.tabIndex = on ? 0 : -1;
    }
    TK.whenVisible(hero, function (on) { seen.hero = on; set(); });
    TK.whenVisible(close, function (on) { seen.close = on; set(); }, { rootMargin: '0px 0px -12% 0px' });
    /* the keyboard is up: keep the bottom of the screen clear */
    document.addEventListener('focusin', function (e) { typing = !!(e.target.closest && e.target.closest('input, textarea')); set(); });
    document.addEventListener('focusout', function () { typing = false; set(); });
  }

  /* ---------- Demo ---------- */
  function setupDemo() {
    var inp = { sleep: $('#d-sleep'), hrv: $('#d-hrv'), rhr: $('#d-rhr') }, seg = $('[data-seg]');
    $('.controls').addEventListener('submit', function (e) { e.preventDefault(); });
    var out = function (k) { return $('[data-o="' + k + '"]'); }, d = function (k) { return $('[data-d="' + k + '"]'); };
    /* on a phone the result sits a screen below the sliders: a live readout docks under the menu
       while the sliders are on screen and the result itself is not */
    var mini = function (k) { return $('[data-m="' + k + '"]'); };
    var dockEl = $('.demo-mini'), seen = { ctl: false, res: false };
    function dock() { dockEl.classList.toggle('on', seen.ctl && !seen.res); }
    TK.whenVisible($('.controls-in'), function (on) { seen.ctl = on; dock(); }, { rootMargin: '-150px 0px -40% 0px' });
    TK.whenVisible($('.demo-today .ringbox'), function (on) { seen.res = on; dock(); }, { rootMargin: '-120px 0px -110px 0px' });
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
      mini('band').textContent = r.band; mini('band').classList.toggle('good', r.good); mini('plan').textContent = r.plan.head;
      d('chips').innerHTML = r.chips.map(function (c) { return '<span class="a-chip ' + c.tone + '"><i></i><span>' + c.text + '</span></span>'; }).join('');
      if (!prev || prev.plan.head !== r.plan.head) {
        if (motion() && !first) G.fromTo([d('plan-head'), d('plan-body')], { autoAlpha: 0, y: 8 }, { autoAlpha: 1, y: 0, duration: TK.T.state, stagger: 0.04 });
        d('plan-head').textContent = r.plan.head; d('plan-body').textContent = r.plan.body;
      }
      $$('i', d('lvl')).forEach(function (bar, k) { bar.style.backgroundColor = k <= 3 - r.plan.level ? (r.plan.level >= 2 ? '#F2B544' : '#C8F05A') : ''; });
      ring.set(r.score, r.segments);
      if (motion() && !first) {
        G.to(shown, { s: r.score, duration: 0.5, ease: 'power2.out', overwrite: true, onUpdate: function () { ring.set(Math.round(shown.s)); ring.draw(1); d('score').textContent = mini('score').textContent = Math.round(shown.s); } });
      } else { shown.s = r.score; ring.draw(1); d('score').textContent = mini('score').textContent = r.score; }
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
    $$('.sec .sec-h').forEach(function (h) {
      if (!window.SplitText) return;
      SplitText.create(h, { type: 'lines', mask: 'lines', autoSplit: true, onSplit: function (self) {
        /* the masks clip, so give descenders (g, y, p) room without moving the lines */
        self.masks.forEach(function (m) { m.style.paddingBottom = '0.16em'; m.style.marginBottom = '-0.16em'; });
        return G.from(self.lines, { yPercent: 108, duration: 1.15, stagger: 0.09, scrollTrigger: { trigger: h, start: 'top 88%', once: true } });
      } });
    });
    /* each piece arrives as it comes into view. Pieces that enter together (side by side on a laptop) are staggered;
       on a phone they are stacked, so each gets its own moment instead of one fade for a two-screen block */
    var items = $$('.sec .sec-sub, .controls, .demo-out > .a-card, .demo-note, .cq, .cc-dev, .nx-steps, .pg-dev, .nx-dev, .close .join-wrap, .trust, .ch-stage, .ch-note, .ex-rail');
    G.set(items, { y: 28, autoAlpha: 0 });
    ScrollTrigger.batch(items, { start: 'top 90%', once: true, onEnter: function (batch) {
      G.to(batch, { y: 0, autoAlpha: 1, duration: TK.T.focal, ease: TK.EASE.out, stagger: 0.08, overwrite: true, clearProps: 'transform' });
    } });
  }

  /* ---------- Boot ---------- */
  setupCoach(); setupProgress(); setupStart(); dockCta();
  if (!motion()) {
    setupFlow(); setupDemo();
    return;
  }
  TK.smooth();
  var heroTL = heroFilm();
  if (pinMode) setupPin(heroTL); else setupFlow();
  if (window.scrollY > 8) heroTL.progress(1);
  pointerDepth();
  setupDemo();
  reveals();
  window.addEventListener('resize', sizePhone);
  /* copy heights settle when the fonts land; size the phone again before triggers measure */
  ScrollTrigger.addEventListener('refreshInit', sizePhone);
  TK.refreshOnFonts();
  } catch (err) { recover(err); }
})();
