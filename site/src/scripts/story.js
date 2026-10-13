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
      when: 'Monday 20:31',
      name: 'Dinner',
      items: [['Grilled chicken thigh', '180 g'], ['Basmati rice', '220 g'], ['Broccolini', '90 g'], ['Tomato and cucumber salad', '120 g']],
      macros: [['Protein', 52, 'g'], ['Carbs', 96, 'g'], ['Calories', 760, '']],
      line: 'Chicken thigh, basmati rice, broccolini',
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
  /* The story in two acts: the evening Sam set the goal (week 1), then one day in week 12. */
  beats: [
    { id: 'goal', act: 1, day: 'Sunday', time: '21:14', tab: null, scr: 'goal', title: 'You set the goal.', line: 'Lose fat, keep strength: from 80.6 kg to 75. Then the days you can train, your equipment and anything to avoid.' },
    { id: 'learn', act: 1, day: 'Sunday', time: '21:19', tab: null, scr: 'intake', title: 'It gets to know you.', line: 'Your usual months from Apple Health, your current lifts, and up to three questions from the coach.' },
    { id: 'approve', act: 1, day: 'Sunday', time: '21:23', tab: null, scr: 'proposal', title: 'You approve the plan.', line: 'Twenty weeks, four days a week, starting loads, 2,600 kcal and 160 g protein a day, with the reasons. Nothing starts until you approve it.' },
    { id: 'train', act: 2, day: 'Monday', time: '18:40', tab: 'train', scr: 'workout', title: 'You train.', line: 'Back squat, 5 sets of 5 at 120 kg. Every set logged with its effort. The last one is a new best.' },
    { id: 'eat', act: 2, day: 'Monday', time: '20:30', tab: 'food', scr: 'meal', title: 'You eat.', line: 'One photo of dinner. Protein and calories, ready for you to check and confirm.' },
    { id: 'sleep', act: 2, day: 'Monday', time: '23:10', tab: 'today', scr: 'sleep', title: 'You sleep.', line: 'Your watch keeps reading. 6 h 12 m, about an hour less than you need.' },
    { id: 'read', act: 2, day: 'Tuesday', time: '06:45', tab: 'today', scr: 'today', title: 'Your body answers.', line: 'Short sleep after a heavy day. Recovery 36, under-recovered, with the reasons spelled out.' },
    { id: 'plan', act: 2, day: 'Tuesday', time: '07:02', tab: 'today', scr: 'session', title: 'Today, adjusted.', line: 'Lighter pulls today, so the week still moves Sam toward 75 kg without losing strength.' }
  ]
};
