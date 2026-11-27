/* App replicas: markup builders for the Tracend app screens, matched to the shipped app.
   Every number is the example athlete's (window.TRACEND_DAY), never real data. */
(function () {
  'use strict';
  var D = window.TRACEND_DAY;
  var NS = 'http://www.w3.org/2000/svg';

  var ICON = {
    today: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4"/></svg>',
    train: '<svg viewBox="0 0 24 24"><path d="M5.5 14.5l4 4M14.5 5.5l4 4M3.5 16.5l4 4M16.5 3.5l4 4M8 16l8-8"/></svg>',
    coach: '<svg viewBox="0 0 24 24"><path d="M4 6.5C4 5.1 5.1 4 6.5 4h11C18.9 4 20 5.1 20 6.5v8c0 1.4-1.1 2.5-2.5 2.5H11l-4.5 3.5V17C5.1 17 4 15.9 4 14.5z"/></svg>',
    food: '<svg viewBox="0 0 24 24"><path d="M7 3.5v7M4.8 3.5v4.8c0 1.2 1 2.2 2.2 2.2s2.2-1 2.2-2.2V3.5M7 10.5v10M16.6 20.5V3.5c-2 1-3.2 3.4-3.2 6.2 0 1.8.8 3 2.2 3.2h1"/></svg>',
    progress: '<svg viewBox="0 0 24 24"><path d="M3.5 17.5l5.5-6 4 3.5 7.5-8.5M15.5 6.5h5v5"/></svg>',
    check: '<svg viewBox="0 0 16 16"><path d="M3.2 8.4l3 3 6.6-6.8"/></svg>',
    chev: '<svg viewBox="0 0 16 16"><path d="M6 3.5L10.5 8 6 12.5"/></svg>',
    down: '<svg viewBox="0 0 24 24"><path d="M6 9l6 6 6-6"/></svg>',
    person: '<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-4 3.6-6.5 8-6.5s8 2.5 8 6.5z"/></svg>',
    spark: '<svg viewBox="0 0 12 12"><path fill="#C8F05A" d="M6 .8l1.3 3.4 3.5.4-2.7 2.3.9 3.5L6 8.5 3 10.4l.9-3.5L1.2 4.6l3.5-.4z"/></svg>'
  };
  function statusBar(time) {
    return '<div class="statusbar" aria-hidden="true"><span class="sb-time" data-sbtime>' + time + '</span><span class="sb-ind">' +
      '<svg viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx=".8"/><rect x="5" y="5.5" width="3" height="6.5" rx=".8"/><rect x="10" y="3" width="3" height="9" rx=".8"/><rect x="15" y="0" width="3" height="12" rx=".8"/></svg>' +
      '<svg viewBox="0 0 16 12"><path d="M8 2.4c2.3 0 4.4.9 6 2.4l1.2-1.3C13.3 1.6 10.8.6 8 .6S2.7 1.6.8 3.5L2 4.8c1.6-1.5 3.7-2.4 6-2.4zm0 3.6c1.3 0 2.5.5 3.4 1.3l1.2-1.3C11.4 4.9 9.8 4.2 8 4.2s-3.4.7-4.6 1.8l1.2 1.3C5.5 6.5 6.7 6 8 6zm0 3.4c.5 0 1 .2 1.3.5L8 11.4 6.7 9.9c.3-.3.8-.5 1.3-.5z"/></svg>' +
      '<svg viewBox="0 0 27 12"><rect x=".5" y=".5" width="22" height="11" rx="3" fill="none" stroke="#F4F4F1" stroke-opacity=".4"/><rect x="2" y="2" width="16" height="8" rx="1.6"/><rect x="24" y="4" width="2" height="4" rx="1" fill-opacity=".45"/></svg>' +
      '</span></div>';
  }
  function tabBar(active) {
    var tabs = [['today', 'Today'], ['train', 'Train'], ['coach', 'Coach'], ['food', 'Nutrition'], ['progress', 'Progress']];
    return '<div class="tabbar" aria-hidden="true">' + tabs.map(function (t) {
      return '<span class="tab' + (t[0] === active ? ' on' : '') + '" data-tab="' + t[0] + '">' + ICON[t[0]] + t[1] + '</span>';
    }).join('') + '</div>';
  }
  function head(title, sub, avatar) {
    return '<div class="a-head"><h3>' + title + '<span class="sub">' + sub + '</span></h3>' + (avatar ? '<span class="avatar">' + ICON.person + '</span>' : '') + '</div>';
  }

  /* ---------- Screens ---------- */
  function scrWorkout() {
    var w = D.monday.workout, last = w.sets.length;
    var sets = w.sets.map(function (s, i) {
      return '<li class="set' + (s.done ? ' done' : '') + '"><span class="ck">' + (i + 1) + ICON.check + '</span></li>';
    }).join('');
    return '<section class="scr" data-scr="workout">' +
      '<div class="lg-top"><span class="chev">' + ICON.down + '</span><span class="mid">' + w.session + '<b>' + w.timer + '</b></span><span class="fin">Finish</span></div>' +
      '<div class="lg-dash"><i class="d"></i><i class="c"></i><i></i><i></i><i></i><span class="saved">Saved</span></div>' +
      '<div class="lg-ex"><p class="k">' + w.index + '</p><h4>' + w.name + '</h4><p class="rx">' + w.rx + '</p><p class="rx" style="margin-top:2px;font-size:14px">' + w.muscles + '</p></div>' +
      '<ol class="lg-sets">' + sets + '</ol>' +
      '<div class="lg-card"><p class="row"><b>Set ' + last + ' of ' + last + '</b><span>Rest 3:00 after</span></p>' +
      '<div class="lg-nums"><span><span class="v">' + w.sets[last - 1].kg + '</span><span class="u">kg</span></span><span class="x">&times;</span><span><span class="v">' + w.sets[last - 1].reps + '</span><span class="u">reps</span></span></div>' +
      '<div class="lg-best"><span class="best" data-best>New best</span></div>' +
      '<p class="lg-foot"><span>Last time <b>' + w.last + '</b></span><span>Your best <b>' + w.best + '</b></span></p></div>' +
      '<span class="a-pill lg-done" data-done>Done set ' + last + '</span>' +
      '</section>';
  }
  function scrSleep() {
    var s = D.night.sleep;
    var hyp = [1, 2, 3, 3, 2, 1, 2, 4, 2, 3, 3, 1, 2, 4, 4, 2, 1, 0, 2, 4, 4, 1, 2, 4, 4, 0, 2, 4];
    var cls = ['awake', '', 'deep', 'deep', 'rem'];
    return '<section class="scr" data-scr="sleep">' + head('Today', s.when, true) +
      '<p class="sec-label">Sleep</p>' +
      '<div class="a-card"><p class="a-kicker">Last night, ' + s.window + '</p>' +
      '<div class="sq-top"><span class="sq-score a-num" data-count="' + s.score + '">' + s.score + '</span><span class="a-band" style="margin-bottom:6px">' + s.band + '</span></div>' +
      '<div class="hyp" aria-hidden="true">' + hyp.map(function (v) { return '<i class="' + cls[v] + '" style="height:' + [30, 55, 100, 100, 75][v] + '%"></i>'; }).join('') + '</div>' +
      '<div class="subs">' + s.subs.map(function (r) {
        return '<div class="sub-row"><p class="lab"><span>' + r[0] + '</span><span>' + r[1] + '</span></p><div class="bar' + (r[1] < 60 ? ' lo' : '') + '"><i style="--v:' + (r[1] / 100) + '" data-bar="' + (r[1] / 100) + '"></i></div></div>';
      }).join('') + '</div>' +
      '<p class="debt"><span class="a-chip amber"><i></i><span>' + s.debt + '</span></span></p></div>' +
      '</section>';
  }
  /* the Daily check-in sheet (lib/features/today/check_in_sheet.dart): one titled row of answers per
     scale with the stored default (OK) chosen, the pain question, the availability switch, Save. The
     markup is the finished state; the animation starts from the defaults. */
  function scrCheckin() {
    var c = D.checkin;
    function opts(labels, on, pick, was) {
      return '<div class="ci-row">' + labels.map(function (l, i) {
        return '<span class="ci-o' + (i === on ? ' on' : '') + '"' + (i === pick ? ' data-pick' : '') + (i === was ? ' data-was' : '') + '>' + l + (i === pick ? TAP : '') + '</span>';
      }).join('') + '</div>';
    }
    return '<section class="scr" data-scr="checkin">' +
      '<i class="ci-grab"></i><div class="ci-head"><b>Daily check-in</b><span class="ci-x"><svg viewBox="0 0 24 24"><path d="M7 7l10 10M17 7L7 17"/></svg></span></div>' +
      '<p class="ci-intro">' + c.intro + '</p>' +
      c.questions.map(function (q) {
        var moved = q.from !== q.to;
        return '<div class="ci-q"><p class="ci-t">' + q.title + '</p>' + opts(q.labels, q.to, moved ? q.to : -1, moved ? q.from : -1) + '</div>';
      }).join('') +
      '<div class="ci-q"><p class="ci-t">Pain</p>' + opts(c.pain, 0, -1, -1) + '</div>' +
      '<div class="ci-avail"><span>Available to train today</span><i class="ci-sw"></i></div>' +
      '<span class="a-pill lime ci-save" data-save>Save check-in' + TAP + '</span>' +
      '<span class="ci-toast">Check-in saved</span>' +
      '</section>';
  }
  function scrToday(id) {
    var t = D.morning;
    return '<section class="scr" data-scr="' + (id || 'today') + '">' + head('Good morning', t.date, true) +
      '<p class="verdict">' + t.verdict + '</p><p class="reason">' + t.reason + '</p>' +
      '<div class="ringbox"><svg data-ring aria-hidden="true"></svg><div class="ring-c"><span class="rl">Recovery</span><span class="sc a-num" data-score>' + t.score + '</span><span class="a-band">' + t.band + '</span></div></div>' +
      '<p class="metric"><b>' + t.rhr + '<small>bpm</small></b><span>Resting HR &middot; normal for you</span></p>' +
      '<div class="chips">' + t.chips.map(function (c) { return '<span class="a-chip ' + c[1] + '"><i></i><span>' + c[0] + '</span></span>'; }).join('') + '</div>' +
      '<div class="today-plan"><p><span>' + D.plan.name + '</span><b>Week ' + D.plan.week + ' of ' + D.plan.weeks + '</b></p><div class="bar"><i style="--v:' + (D.plan.week / D.plan.weeks).toFixed(2) + '"></i></div></div>' +
      '</section>';
  }
  function sessionCard() {
    var s = D.morning.session;
    var strip = '<div class="strip">' + s.exercises.map(function (e) {
      var b = ''; for (var i = 0; i < e[1]; i++) b += '<i></i>';
      return '<span class="ex" style="--n:' + e[1] + '">' + b + '</span>';
    }).join('') + '</div><div class="strip-names">' + s.exercises.map(function (e) { return '<span style="--n:' + e[1] + '">' + e[0] + '</span>'; }).join('') + '</div>';
    return '<div class="a-card sess"><p class="a-kicker">' + s.kicker + '</p><p class="a-title">' + s.title + '</p>' + strip +
      '<p class="sess-meta">' + s.meta + '</p>' +
      '<div class="coach-note"><p class="who"><i>' + ICON.spark + '</i>Coach</p><p data-note>' + s.note + '</p></div>' +
      '<p class="open-row"><span>Open in Train</span>' + ICON.chev + '</p></div>';
  }
  function scrSession() {
    return '<section class="scr" data-scr="session">' + head('Today', D.morning.date, true) +
      '<p class="sec-label">Today&rsquo;s session</p>' + sessionCard() + '</section>';
  }

  function scrCoach() {
    return '<section class="scr" data-scr="coach" style="padding-bottom:104px">' +
      '<div class="ch-top">Coach<span class="new"><svg viewBox="0 0 24 24"><path d="M4 6.5C4 5.1 5.1 4 6.5 4h11C18.9 4 20 5.1 20 6.5v8c0 1.4-1.1 2.5-2.5 2.5H11l-4.5 3.5V17C5.1 17 4 15.9 4 14.5z"/></svg></span></div>' +
      '<div class="thread" data-thread></div>' +
      '<div class="ask"><span>Ask your Coach</span><i><svg viewBox="0 0 24 24"><path d="M12 19V5M6 11l6-6 6 6"/></svg></i></div>' +
      '</section>';
  }

  /* A complete phone. screens: list of builder keys ('today-hero' is a second Today that never animates). */
  /* ---------- Onboarding: goal, intake, proposal (the app's 2026-10 flow) ---------- */
  function obTop(text, n, of) {
    var seg = ''; for (var k = 1; k <= of; k++) seg += '<i' + (k < n ? ' class="d"' : k === n ? ' class="c"' : '') + '></i>';
    return '<p class="gp-top"><svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></svg>' + text + '</p><div class="gp-seg">' + seg + '</div>';
  }
  var TAP = '<i class="gp-t"></i>';
  function scrGoal() {
    var goals = [['Lose fat', 'Drop body fat and keep your strength.'], ['Build muscle', 'Add size with a small surplus.'], ['Recomposition', 'Lose fat and build muscle, slowly.'], ['Get stronger', 'Lift more on the big lifts.']];
    return '<section class="scr" data-scr="goal">' + obTop('Your goal', 4, 15) +
      '<h4 class="gp-h">What&rsquo;s your goal?</h4><p class="gp-sub">Your whole plan is built around it.</p><div class="gp-cards">' +
      goals.map(function (g, k) { return '<div class="gp-card"' + (k === 0 ? ' data-pick' : '') + '><div><b>' + g[0] + '</b><span>' + g[1] + '</span></div><i class="gp-ck">' + ICON.check + '</i>' + (k === 0 ? TAP : '') + '</div>'; }).join('') +
      '</div><div class="gp-cta"><span class="a-pill lime" data-cont>Continue' + TAP + '</span></div></section>';
  }
  function scrIntake() {
    return '<section class="scr" data-scr="intake">' + obTop('Coach questions', 15, 15) +
      '<div class="a-card gp-hk"><p class="a-kicker"><i><svg viewBox="0 0 12 12"><path d="M6 10.6S1.2 7.6 1.2 4.4C1.2 2.8 2.4 1.6 3.9 1.6c.9 0 1.7.5 2.1 1.2.4-.7 1.2-1.2 2.1-1.2 1.5 0 2.7 1.2 2.7 2.8C10.8 7.6 6 10.6 6 10.6z"/></svg></i>From Apple Health, your usual months</p>' +
      '<p class="gp-row"><span>Strength</span><b>3.8&times; a week usually</b></p><p class="gp-row"><span>Sleep</span><b>7 h 05 m usually</b></p><p class="gp-row"><span>Weight</span><b>80.6 kg, 2 days ago</b></p></div>' +
      '<p class="gp-who"><i>' + ICON.spark + '</i>Coach</p><p class="gp-qt">You squat 115 kg for 5 now. Keep heavy squats twice a week while you lean down?</p>' +
      '<div class="gp-ans"><span data-yes>Yes, keep them heavy' + TAP + '</span><span>Once a week is enough</span></div></section>';
  }
  function scrProposal() {
    var p = D.plan, days = [['Mon', 'Legs', 'Back squat 5 &times; 5', 'RPE 8, about 2 reps left &middot; <em>Start at 110 kg</em>'], ['Tue', 'Pull', 'Deadlift 3 &times; 3', 'RPE 7.5 &middot; <em>Start at 140 kg</em>'], ['Thu', 'Push', 'Bench press 4 &times; 6', 'RPE 8 &middot; <em>Start at 82.5 kg</em>'], ['Sat', 'Arms', 'Hammer curl 3 &times; 10', 'RPE 8 &middot; 90 s rest']];
    return '<section class="scr gp-d" data-scr="proposal"><span class="gp-prov">' + ICON.spark + 'Proposed by AI &middot; checked by Tracend</span>' +
      '<h4 class="gp-h">' + p.name + '</h4><p class="gp-meta">' + p.weeks + ' weeks &middot; ' + p.days + ' days a week &middot; goal ' + p.goal + ' kg</p>' +
      '<p class="gp-sec">Training</p><div class="gp-card2">' + days.map(function (d) { return '<div class="gp-day"><b>' + d[0] + '<br>' + d[1] + '</b><p>' + d[2] + '<small>' + d[3] + '</small></p></div>'; }).join('') + '</div>' +
      '<p class="gp-sec">Nutrition</p><div class="gp-card2"><div class="gp-nut"><b>' + p.kcal + ' kcal</b><span>' + p.protein + ' g protein a day</span></div></div>' +
      '<div class="gp-act"><span class="a-pill lime" data-appr>Approve plan' + TAP + '</span><span class="rq">Request changes</span></div>' +
      '<div class="gp-set"><h5>You&rsquo;re set.</h5><p class="gp-row"><span>Next session</span><b>Legs, Monday</b></p><p class="gp-row"><span>Every day</span><b>' + p.kcal + ' kcal &middot; ' + p.protein + ' g protein</b></p><p class="gp-row"><span>Apple Health</span><b>Connected</b></p><span class="a-pill">Go to Today</span></div></section>';
  }

  var BUILD = { goal: scrGoal, intake: scrIntake, proposal: scrProposal, coach: scrCoach, workout: scrWorkout, sleep: scrSleep, today: function () { return scrToday(); }, 'today-hero': function () { return scrToday('today-hero'); }, session: scrSession, checkin: scrCheckin };
  function phone(opts) {
    opts = opts || {};
    var list = opts.screens || ['workout', 'sleep', 'today', 'session'];
    return '<div class="phone app' + (opts.cls ? ' ' + opts.cls : '') + '"' + (opts.id ? ' id="' + opts.id + '"' : '') + ' aria-hidden="true"><i class="rim"></i><i class="btns"></i><div class="screen">' +
      '<span class="island"></span>' + statusBar(opts.time || '18:40') +
      '<div class="screens">' + list.map(function (k) { return BUILD[k](); }).join('') + '</div>' +
      (opts.tab === null ? '' : tabBar(opts.tab || 'train')) + '<span class="homebar"></span></div></div>';
  }

  /* ---------- Recovery tick ring (RecoveryTickRing, 112 ticks) ---------- */
  function ring(svg, opt) {
    var TICKS = 112, C = 128, OUTER = 120;
    svg.setAttribute('viewBox', '-8 -8 272 272');
    svg.innerHTML = '';
    var lines = [];
    for (var i = 0; i < TICKS; i++) {
      var l = document.createElementNS(NS, 'line');
      l.setAttribute('stroke-linecap', 'round');
      svg.appendChild(l); lines.push(l);
    }
    var dot = document.createElementNS(NS, 'circle');
    dot.setAttribute('r', 3.6); dot.setAttribute('fill', '#F4F4F1');
    svg.appendChild(dot);
    var st = { score: opt.score, segments: opt.segments, track: opt.track || '#2E2F33', mono: opt.mono };
    function owners(lit) {
      var tot = st.segments.reduce(function (a, s) { return a + s.weight; }, 0), o = [];
      st.segments.forEach(function (s, k) {
        var n = tot <= 0 ? 0 : Math.round(lit * s.weight / tot);
        for (var j = 0; j < n && o.length < lit; j++) o.push(k);
      });
      while (o.length < lit) o.push(st.segments.length - 1);
      return o;
    }
    function draw(p) {
      var lit = Math.round(TICKS * Math.max(0, Math.min(100, st.score)) / 100);
      var shown = Math.floor(lit * p), own = owners(lit);
      for (var i = 0; i < TICKS; i++) {
        var a = -Math.PI / 2 + i * 2 * Math.PI / TICKS, dx = Math.cos(a), dy = Math.sin(a);
        var isLit = i < shown, owner = i < lit ? own[i] : -1;
        var gap = i > 0 && i < lit && own[i - 1] !== owner;
        var headT = isLit && i === shown - 1, len, col, op = 1;
        if (gap) { lines[i].setAttribute('stroke-opacity', 0); continue; }
        if (isLit) {
          len = headT ? 34 : 22 + 8 * Math.sin(Math.PI * i / Math.max(1, lit));
          col = st.mono || st.segments[owner].color; op = 0.38 + 0.62 * (i / Math.max(1, lit));
        } else { len = 12; col = st.track; }
        lines[i].setAttribute('x1', C + dx * (OUTER - len)); lines[i].setAttribute('y1', C + dy * (OUTER - len));
        lines[i].setAttribute('x2', C + dx * OUTER); lines[i].setAttribute('y2', C + dy * OUTER);
        lines[i].setAttribute('stroke', col); lines[i].setAttribute('stroke-opacity', op);
        lines[i].setAttribute('stroke-width', headT ? 4.4 : 3.2);
        if (headT) { dot.setAttribute('cx', C + dx * (OUTER - 41)); dot.setAttribute('cy', C + dy * (OUTER - 41)); }
      }
      dot.setAttribute('opacity', shown > 0 ? 1 : 0);
    }
    function set(score, segments) { st.score = score; if (segments) st.segments = segments; }
    draw(opt.progress == null ? 1 : opt.progress);
    return { draw: draw, set: set };
  }

  /* ---------- Brand mark (lib/shared/brand/tracend_mark.dart) ---------- */
  function mark(opts) {
    opts = opts || {};
    return '<svg class="mark" viewBox="200 200 700 700" aria-hidden="true"><path fill="' + (opts.letter || '#F4F4F1') + '" d="M252 348L308 240H812L630 348H580L527 497L368 621L441 383L530 350Z"/>' +
      '<path fill="' + (opts.arc || '#C8F05A') + '" d="M272 783Q500 480 803 323Q560 520 440 783Z"/><circle fill="' + (opts.arc || '#C8F05A') + '" cx="623" cy="472" r="36"/></svg>';
  }

  window.TracendApp = { phone: phone, screen: function (k) { return BUILD[k](); }, ring: ring, icon: ICON, statusBar: statusBar, tabBar: tabBar, mark: mark };
})();
