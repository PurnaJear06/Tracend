/* Motion kit for the site.
   - Timing tokens and eases (one motion language for every world).
   - ScrollSmoother on desktop with a fine pointer only; phones keep native scroll.
   - Clock reels, count-ups and the join form. */
(function () {
  'use strict';
  var root = document.documentElement;
  var G = window.gsap;
  var forced = /reduce/.test(location.hash + location.search);
  var mqReduce = matchMedia('(prefers-reduced-motion: reduce)');
  var mqDesk = matchMedia('(min-width: 1024px) and (hover: hover) and (pointer: fine)');
  function reduced() { return forced || mqReduce.matches; }
  root.classList.toggle('rm', reduced());

  var T = { feedback: 0.14, state: 0.25, layout: 0.44, focal: 0.8 };
  var EASE = { out: 'tOut', inOut: 'tInOut', spring: 'tSpring' };

  if (G) {
    var plugs = ['ScrollTrigger', 'ScrollSmoother', 'SplitText', 'Flip', 'DrawSVGPlugin', 'MorphSVGPlugin', 'CustomEase'].map(function (n) { return window[n]; }).filter(Boolean);
    G.registerPlugin.apply(G, plugs);
    if (window.CustomEase) {
      CustomEase.create('tOut', '0.16,1,0.3,1');
      CustomEase.create('tInOut', '0.65,0,0.35,1');
      CustomEase.create('tSpring', 'M0,0 C0.12,0.62 0.22,1.06 0.42,1.04 0.6,1.02 0.76,0.997 1,1');
    } else { EASE = { out: 'expo.out', inOut: 'power3.inOut', spring: 'back.out(1.4)' }; }
    G.defaults({ ease: EASE.out, duration: T.layout });
    if (window.ScrollTrigger) ScrollTrigger.config({ ignoreMobileResize: true });
  }

  /* ---------- Smooth scroll (desktop only) ---------- */
  var smoother = null;
  function smooth() {
    if (!G || !window.ScrollSmoother || reduced() || !mqDesk.matches) return null;
    if (!document.getElementById('smooth-wrapper')) return null;
    smoother = ScrollSmoother.create({ wrapper: '#smooth-wrapper', content: '#smooth-content', smooth: 0.9, effects: true, smoothTouch: false });
    return smoother;
  }
  /* a section's heading lands the same distance under the floating nav on every section;
     section padding differs, so aiming at the section's own top lands lower each time */
  var NAV_GAP = 112;
  function scrollToEl(target) {
    if (!target) return;
    var label = target.getAttribute('aria-labelledby');
    var el = (label && document.getElementById(label)) || target.querySelector('h2') || target;
    if (smoother) { smoother.scrollTo(el, true, 'top ' + NAV_GAP + 'px'); return; }
    var y = el.getBoundingClientRect().top + window.pageYOffset - NAV_GAP;
    window.scrollTo({ top: Math.max(0, y), behavior: reduced() ? 'auto' : 'smooth' });
  }
  document.addEventListener('click', function (e) {
    var a = e.target.closest && e.target.closest('a[href^="#"]');
    if (!a) return;
    var id = a.getAttribute('href').slice(1);
    if (!id || /^h=|reduce/.test(id)) return;
    var t = document.getElementById(id);
    if (!t) return;
    e.preventDefault();
    scrollToEl(t);
    var f = t.querySelector('input,button,[tabindex]');
    if (f && a.hasAttribute('data-focus')) setTimeout(function () { f.focus({ preventScroll: true }); }, reduced() ? 0 : 700);
  });

  /* ---------- Reels (rolling digits) ---------- */
  function reelHTML(chars) {
    return '<span class="reel"><span class="reel-strip">' + chars.map(function (c) { return '<span>' + c + '</span>'; }).join('') + '</span></span>';
  }
  var DIG = '0123456789'.split('');
  /* clock(el): fills el with HH:MM reels. el gets data-time. */
  function clock(el, time) {
    el.innerHTML = reelHTML(DIG) + reelHTML(DIG) + '<span class="colon">:</span>' + reelHTML(DIG) + reelHTML(DIG);
    el._strips = Array.prototype.slice.call(el.querySelectorAll('.reel-strip'));
    setClock(el, time || '00:00');
    return el;
  }
  function digitsOf(time) { return time.replace(':', '').split('').map(Number); }
  /* setClock(el, 'HH:MM', opts): opts.tl + opts.at add tweens to a timeline (scrub-safe). */
  function setClock(el, time, opts) {
    opts = opts || {};
    var d = digitsOf(time);
    el.setAttribute('data-time', time);
    el._strips.forEach(function (s, i) {
      var y = -d[i] * 10;
      if (opts.tl) opts.tl.to(s, { yPercent: y, duration: opts.dur || 0.6, ease: EASE.inOut }, (opts.at || 0) + i * 0.04);
      else if (G && !opts.instant && !reduced()) G.to(s, { yPercent: y, duration: 0.7, ease: EASE.inOut, delay: i * 0.05, overwrite: true });
      else if (G) G.set(s, { yPercent: y });
      else s.style.transform = 'translateY(' + y + '%)';
    });
  }
  /* wordReel(el, words): a vertical reel of words (day names). */
  function wordReel(el, words) {
    el.innerHTML = reelHTML(words);
    el._strip = el.querySelector('.reel-strip');
    el._words = words;
    return el;
  }
  function setWord(el, word, opts) {
    opts = opts || {};
    var i = el._words.indexOf(word), y = -i * (100 / el._words.length);
    if (opts.tl) opts.tl.to(el._strip, { yPercent: y, duration: opts.dur || 0.6, ease: EASE.inOut }, opts.at || 0);
    else if (G && !opts.instant && !reduced()) G.to(el._strip, { yPercent: y, duration: 0.7, ease: EASE.inOut, overwrite: true });
    else if (G) G.set(el._strip, { yPercent: y });
  }

  /* ---------- Count-up ---------- */
  function countUp(el, to, opts) {
    opts = opts || {};
    var from = opts.from || 0, fmt = opts.fmt || function (v) { return Math.round(v); };
    var target = el.firstChild && el.firstChild.nodeType === 3 ? el.firstChild : el;
    function put(v) { if (target.nodeType === 3) target.nodeValue = fmt(v); else target.textContent = fmt(v); }
    if (!G || reduced()) { put(to); return null; }
    var o = { v: from };
    var tw = G.to(o, { v: to, duration: opts.dur || 1.1, ease: 'power2.out', onUpdate: function () { put(o.v); } });
    if (opts.tl) { tw.kill(); return opts.tl.fromTo(o, { v: from }, { v: to, duration: opts.dur || 1.1, ease: 'power2.out', onUpdate: function () { put(o.v); } }, opts.at || 0); }
    return tw;
  }

  /* ---------- Visibility helpers ---------- */
  function whenVisible(el, cb, opts) {
    if (!('IntersectionObserver' in window)) { cb(true); return; }
    var io = new IntersectionObserver(function (es) { es.forEach(function (e) { cb(e.isIntersecting, io); }); }, opts || { threshold: 0.15 });
    io.observe(el);
    return io;
  }

  function refreshOnFonts() {
    if (document.fonts && window.ScrollTrigger) document.fonts.ready.then(function () { ScrollTrigger.refresh(); });
  }

  window.TK = {
    G: G, T: T, EASE: EASE, reduced: reduced, desk: mqDesk, smooth: smooth, smoother: function () { return smoother; },
    scrollTo: scrollToEl, clock: clock, setClock: setClock, wordReel: wordReel, setWord: setWord,
    countUp: countUp, whenVisible: whenVisible, refreshOnFonts: refreshOnFonts
  };
})();
