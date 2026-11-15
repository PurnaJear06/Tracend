/* One example day for a synthetic athlete ("Sam"). Every value is an example and is
   consistent with docs/ALGORITHMS.md: the recovery score below comes from the same
   logistic composite the demo uses (see demo.js). */
window.TRACEND_DAY = {
  athlete: 'Sam, example athlete',
  monday: {
    workout: {
      kicker: 'Leg day · Set 5 of 5',
      name: 'Back squat',
      target: '5 × 5 at 120 kg',
      session: 'Leg day', timer: '38:12', index: 'Exercise 1 of 5', rx: '5 sets of 5 · effort 8 to 9', muscles: 'Quads, glutes',
      last: '117.5 kg × 5', best: '120 kg × 4',
      sets: [
        { kg: 120, reps: 5, rpe: 7, done: true },
        { kg: 120, reps: 5, rpe: 7.5, done: true },
        { kg: 120, reps: 5, rpe: 8, done: true },
        { kg: 120, reps: 5, rpe: 8.5, done: true },
        { kg: 120, reps: 5, rpe: 9, done: true, best: true }
      ]
    },
    meal: {
      /* the day's totals before and after dinner, and the target */
      totals: { kcal: [1380, 2140, 2600], protein: [96, 148, 160], carbs: [142, 238, 260], fat: [45, 64, 75] }
    }
  },
  night: {
    sleep: {
      when: 'Tuesday 06:45',
      window: '23:10 to 05:22',
      score: 58,
      band: 'Disrupted',
      subs: [['Duration', 52], ['Efficiency', 86], ['Consistency', 74], ['Restorative', 57]],
      debt: '1 h 08 m less than you need'
    }
  },
  morning: {
    date: 'Tuesday 14 October',
    verdict: 'Under-recovered',
    reason: 'Sleep less than usual, recent training higher than usual. Everything else is normal for you.',
    score: 36,
    band: 'Low',
    change: '−14 from yesterday',
    hrv: 52, hrvNote: 'Normal for you',
    rhr: 58, rhrNote: 'Normal for you',
    chips: [['HRV', 'lime'], ['Resting HR', 'lime'], ['Sleep short', 'amber'], ['Training heavy', 'amber'], ['Breathing', 'lime']],
    /* RecoveryTickRing segments: weight = the component's share of the composite */
    segments: [
      { color: '#C8F05A', weight: 55 },
      { color: '#C8F05A', weight: 20 },
      { color: '#F2B544', weight: 15 },
      { color: '#C8F05A', weight: 5 },
      { color: '#F2B544', weight: 5 }
    ],
    session: {
      kicker: 'Tuesday · Workout',
      title: 'Pull day',
      exercises: [['Deadlift', 3], ['Pull-up', 3], ['Row', 3], ['Curl', 3]],
      meta: '4 exercises · 12 sets · about 45 min',
      note: 'Go lighter today: deadlift <b>3 × 3 at 140 kg</b> instead of <s>5 × 3 at 160 kg</s>, effort 7 at most. You slept 1 h 08 m less than you need after a heavy leg day.'
    }
  },
  /* Sam's plan, from onboarding (week 1) */
  plan: {
    name: 'Lean down, keep strength', weeks: 20, week: 12, days: 4, start: 80.6, now: 77.3, goal: 75,
    kcal: '2,600', protein: 160
  },
  /* The story: one day in week 12, from Monday's session to Tuesday's adjusted plan.
     sb: the time on the phone's status bar when it differs (the sleep report is read in the morning). */
  beats: [
    { id: 'train', day: 'Monday', time: '18:40', tab: 'train', scr: 'workout', title: 'You train hard.', line: 'Back squat, 5 sets of 5 at 120 kg. The last set is a new best.' },
    { id: 'sleep', day: 'Monday', time: '23:10', sb: '06:45', tab: 'today', scr: 'sleep', title: 'You sleep short.', line: '6 h 12 m on your watch, about an hour less than you need.' },
    { id: 'read', day: 'Tuesday', time: '06:45', tab: 'today', scr: 'today', title: 'Your body answers.', line: 'Recovery 36. Under-recovered, after a short night and a heavy day.' },
    { id: 'plan', day: 'Tuesday', time: '07:02', tab: 'today', scr: 'session', title: 'Today, adjusted.', line: 'Deadlift 3 × 3 at 140 kg, not 5 × 3 at 160. The week still moves Sam toward 75 kg.' }
  ],
  /* How a plan starts: the three onboarding moments, shown in "Start in three steps". */
  start: [
    { id: 'goal', time: '21:14', scr: 'goal' },
    { id: 'learn', time: '21:19', scr: 'intake' },
    { id: 'approve', time: '21:23', scr: 'proposal' }
  ]
};
