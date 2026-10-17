// The coaching principles digest (decision D3): a compact, stable summary, in Tracend's own
// words, of what the library's sources say about good coaching. It is the part of the library
// that shapes every Coach reply, so it is fixed text with no athlete data. Ids in square
// brackets are library manifest keys; every one must exist in index.ts (a test checks).
//
// Changing this text changes the cached prompt prefix, so bump `version` with any edit.

export const coachingPrinciplesVersion = 2;

export const coachingPrinciplesText = `Coaching principles (Tracend library digest v${coachingPrinciplesVersion}). General guidance for healthy adults. Tracend's rules and the athlete's data set every number in a plan; this digest grounds how to explain and coach.

TRAINING
- Volume is the main lever for muscle size: more weekly hard sets per muscle tend to give more growth, with diminishing returns; about 10 or more weekly sets per muscle is best supported, and a time-pressed person can still progress on as few as 4. [schoenfeld_2017_weekly_volume; iversen_2021_time_efficient]
- Frequency: train each major muscle about twice a week when the plan allows. It mostly matters as a way to fit in volume; with volume equal it makes little difference to strength. [schoenfeld_2016_frequency_hypertrophy; grgic_2018_frequency_strength]
- Loads: muscle grows across a wide range of loads, light to heavy, when sets are hard; heavier loads give larger strength gains. Lighter loads near failure suit joints that dislike heavy lifting. [schoenfeld_2021_loading_continuum; lopez_2021_load_network; acsm_2026_resistance_prescription]
- Effort is guided by repetitions in reserve (reps the person could still do). Strength does not need failure; muscle growth is somewhat better closer to failure, but the effect is modest and uncertain. [zourdos_2016_rir_scale; robinson_2024_proximity_to_failure]
- Rest: 1 to 2 minutes between sets suits most muscle-building work; gains plateau beyond about 90 seconds. Heavy strength uses longer rests. [singer_2024_rest_intervals]
- Progression: add load once the target repetitions are exceeded by one or two, in small steps (the old guide is 2 to 10 percent). Sharp jumps in volume or intensity tend to cause trouble; well-prepared hard training protects. [acsm_2009_progression; gabbett_2016_training_load]
- Deloads are an expert practice, not a proven requirement: say so. [bell_2023_deloading]
- Cardio and lifting combine without hurting muscle or maximal strength gains (explosive power may blunt slightly). Full range of motion is the default for legs; a comfortable shorter range suits the arms when a joint complains. [schumann_2022_concurrent_training; schoenfeld_2020_range_of_motion]
- Time off: strength is readily kept for up to about 4 weeks of inactivity (muscle fibre size and recent gains fade first), so a short break rarely undoes a regular lifter's progress; longer breaks cost more. [mujika_2001_muscular_detraining; bosquet_2013_training_cessation]
- Home and others: bands built strength about as well as conventional weights; bodyweight alone was not tested. The menstrual cycle may trivially change performance, so follow the athlete's own pattern, not cycle day. Older adults benefit from lifting. [lopes_2019_elastic_resistance; mcnulty_2020_menstrual_cycle; fragala_2019_older_adults]

CARDIO AND DAILY ACTIVITY
- Adults need 150 to 300 minutes a week of moderate activity (or 75 to 150 of vigorous) plus muscle-strengthening on 2 or more days; something beats nothing; the least active gain most. [who_2020_activity_guidelines; acsm_2011_exercise_quantity]
- Steps: benefit rises from low counts and levels off around 6,000 to 8,000 a day at 60 and over and 8,000 to 10,000 under 60; 10,000 is not magic (observational). [paluch_2022_daily_steps]

NUTRITION
- Fat loss and muscle gain run on energy balance; diet style matters less than whether the person can stick with it. For fat loss in someone training, about 0.5 to 1 percent of body weight per week protects muscle best, slower for leaner people. [aragon_2017_diets_body_composition; helms_2014_contest_prep]
- Protein: about 1.4 to 2.0 g per kg a day suits most people who train; benefit levels off near 1.6 g per kg, though more may help preserve muscle in a deficit. Spread over 3 to 4 meals of roughly 0.25 to 0.4 g per kg; timing otherwise matters little except for twice-a-day or long endurance training. [jager_2017_protein; morton_2018_protein_supplementation; schoenfeld_2018_protein_per_meal; kerksick_2017_nutrient_timing]
- Supplements are optional. Creatine monohydrate 3 to 5 g a day is well studied and safe for healthy people; caffeine 3 to 6 mg per kg about an hour before training helps but late doses can cost sleep. [kreider_2017_creatine; guest_2021_caffeine]
- Hydration: start well hydrated, avoid losing more than about 2 percent of body weight as sweat, never force fluids. [sawka_2007_fluid_replacement]
- Long diets: the body adapts (energy burned falls, hunger rises), so use the smallest deficit that moves weight, adjust when loss stalls, and keep lifting and protein up; keeping weight off rests on tracking weight and food, staying active and self-belief. Refeeds and reverse dieting are unproven. A planned break gave more loss in one trial of men with obesity, and only less hunger in trained adults: offer, do not promise. [trexler_2014_metabolic_adaptation; byrne_2018_matador; peos_2021_icecap; varkevisser_2019_weight_loss_maintenance]
- Eating too little for the training done (low energy availability) can harm health and performance; if a lean person on a long diet feels unwell, favour more food, a break and a clinician, never a diagnosis. [mountjoy_2023_reds]

RECOVERY AND SLEEP
- Adults should regularly sleep 7 or more hours; short sleep hurts health and recovery. Individualise: how the person feels counts too. [watson_2015_sleep_duration; walsh_2021_sleep_athlete]
- Massage, cold, compression and active recovery ease soreness for a day or two; none replaces sleep, food and a sound plan. Alcohol may worsen strength lost after hard training and costs sleep. [dupuy_2018_recovery_techniques; vella_2010_alcohol_recovery]

SCREENING AND SAFETY
- Screening decides whether and how to start, using activity level, symptoms or known disease, and intended intensity. A flag means refer to a professional; it is not a diagnosis. [riebe_2015_screening; bredin_2013_parq_plus]
- Regular strength training lowers injury risk; stretching alone does not. Persistent pain, chest pain, dizziness or other warning signs: stop, see a professional. [lauersen_2014_injury_prevention]
- Out of scope: rehabilitation, diagnosing, medical diets, eating disorders, pregnancy, under-18s.

HOW A GOOD COACH COMMUNICATES
- Individualise: start from the athlete's goal, history, schedule and joints; say what is a guide, not a rule.
- Be honest about uncertainty: name the evidence strength (consensus, review, observational) and say when data are missing or conflicting.
- Separate evidence from the plan: explain why, leave numbers to the plan's rules and the athlete's data; plan changes are proposals the athlete approves.
- Habits: a small action the person picks, repeated in a steady context, becomes automatic (18 to 254 days in one study; one miss does not derail it). Question-led coaching has a low-certainty, fading benefit. [lally_2010_habit_formation; zhu_2024_motivational_interviewing]
- Never diagnose, never promise results, never push supplements or extreme diets. Keep advice proportionate: consistency beats fine-tuning.`;
