/* "Change the night": a simplified, labelled version of the recovery composite in
   docs/ALGORITHMS.md §1. Real Tracend compares each reading with your own rolling
   baseline and spread; here the example athlete's normals and spreads are fixed. */
(function () {
  'use strict';
  var NORMAL = { hrv: 54, rhr: 57, sleep: 440 };          /* ms, bpm, minutes */
  var SPREAD = { hrv: 0.25, rhr: 4, sleep: 60 };           /* ln-HRV, bpm, minutes */
  var STRAIN = { rest: -0.6, easy: 0, moderate: 0.5, heavy: 1.0 };
  var W = { hrv: 0.55, rhr: 0.20, sleep: 0.15, resp: 0.05, strain: 0.05 };

  function compute(inp) {
    var z = {
      hrv: Math.log(inp.hrv / NORMAL.hrv) / SPREAD.hrv,
      rhr: -(inp.rhr - NORMAL.rhr) / SPREAD.rhr,             /* negated: higher HR is worse */
      sleep: (inp.sleep - NORMAL.sleep) / SPREAD.sleep,
      resp: 0,
      strain: STRAIN[inp.session]
    };
    var comp = (W.hrv * z.hrv + W.rhr * z.rhr + W.sleep * z.sleep + W.resp * z.resp - W.strain * z.strain) /
      (W.hrv + W.rhr + W.sleep + W.resp + W.strain);
    var score = Math.round(100 / (1 + Math.exp(-1.6 * comp)));
    var drivers = [
      { key: 'hrv', chip: 'HRV', down: z.hrv <= -1, word: 'low', label: 'Heart rate variability lower than usual', weight: 55 },
      { key: 'rhr', chip: 'Resting HR', down: z.rhr <= -1, word: 'high', label: 'Resting heart rate higher than usual', weight: 20 },
      { key: 'sleep', chip: 'Sleep', down: z.sleep <= -1, word: 'short', label: 'Sleep less than usual', weight: 15 },
      { key: 'resp', chip: 'Breathing', down: false, word: 'high', label: 'Breathing rate higher than usual', weight: 5 },
      { key: 'strain', chip: 'Training', down: z.strain >= 1, word: 'heavy', label: 'Recent training higher than usual', weight: 5 }
    ];
    var down = drivers.filter(function (d) { return d.down; });
    var reason;
    if (!down.length) {
      reason = score < 50 ? 'Nothing is far off your normal, but more sits a little below it than above.'
        : 'Everything that counted today is normal for you.';
    } else {
      reason = down.map(function (d, i) { return i ? d.label.charAt(0).toLowerCase() + d.label.slice(1) : d.label; }).join(', ') +
        '. Everything else is normal for you.';
    }
    var verdict = score >= 80 ? 'Fully recovered' : score >= 65 ? 'Well recovered' : score >= 50 ? 'Partly recovered' : score >= 35 ? 'Under-recovered' : 'Very under-recovered';
    var band = score >= 80 ? 'Excellent' : score >= 65 ? 'Good' : score >= 50 ? 'Moderate' : score >= 35 ? 'Low' : 'Poor';
    var plan;
    if (score >= 65) plan = { head: 'Train as planned.', body: 'Deadlift 5 × 3 at 160 kg. You recovered well.', level: 0 };
    else if (score >= 50) plan = { head: 'Train as planned, with a cap.', body: 'Deadlift 5 × 3 at 160 kg, effort 8 at most.', level: 1 };
    else if (score >= 35) plan = { head: 'Go lighter today.', body: 'Deadlift 3 × 3 at 140 kg, effort 7 at most.', level: 2 };
    else plan = { head: 'Make it an easy day.', body: '30 minutes of walking and mobility. Heavy pulls can wait.', level: 3 };
    return {
      score: score, verdict: verdict, band: band, good: score >= 65, reason: reason, plan: plan,
      chips: drivers.map(function (d) { return { text: d.down ? d.chip + ' ' + d.word : d.chip, tone: d.down ? 'amber' : 'lime' }; }),
      segments: drivers.map(function (d) { return { color: d.down ? '#F2B544' : '#C8F05A', weight: d.weight }; })
    };
  }
  window.TracendDemo = { compute: compute, NORMAL: NORMAL, DEFAULT: { hrv: 52, rhr: 58, sleep: 372, session: 'heavy' } };
})();
