// The coaching principles digest (decision D3): a compact, stable summary, in Tracend's own
// words, of what the library's sources say about good coaching. It is the part of the library
// that shapes every Coach reply, so it is fixed text with no athlete data. Ids in square
// brackets are library manifest keys; every one must exist in index.ts (a test checks).
//
// Changing this text changes the cached prompt prefix, so bump `version` with any edit.

export const coachingPrinciplesVersion = 1;

export const coachingPrinciplesText = `Coaching principles (Tracend library digest, version ${coachingPrinciplesVersion}). General guidance for healthy adults, summarised from the cited sources. Tracend's rules and the athlete's own data set every number in a plan; this digest only grounds how to explain and coach.

TRAINING
- Volume is the main lever for muscle size: more weekly hard sets per muscle tend to give more growth, with diminishing returns, and about 10 or more weekly sets per muscle is where size gains are best supported. A time-pressed person can still progress on as few as 4 weekly sets per muscle. [schoenfeld_2017_weekly_volume; pelland_2026_volume_frequency; acsm_2026_resistance_prescription; iversen_2021_time_efficient]
- Frequency: train each major muscle about twice a week when the plan allows it. Frequency mostly matters as a way to fit in volume; with volume equal it makes little difference to strength. [schoenfeld_2016_frequency_hypertrophy; grgic_2018_frequency_strength; pelland_2026_volume_frequency]
- Loads: muscle can be built across a wide range of loads, light to heavy, when sets are hard. Heavier loads give larger strength gains. Lighter loads taken close to failure are a fair choice when joints dislike heavy lifting. [schoenfeld_2021_loading_continuum; lopez_2021_load_network; acsm_2026_resistance_prescription]
- Effort is guided by repetitions in reserve (how many more the person could do). Strength does not need failure. Muscle growth is somewhat better when sets end closer to failure, but the effect is modest and uncertain. [zourdos_2016_rir_scale; robinson_2024_proximity_to_failure]
- Rest: 1 to 2 minutes between sets suits most muscle-building work, and gains plateau beyond about 90 seconds. Heavy strength work uses longer rests. [singer_2024_rest_intervals; acsm_2009_progression]
- Progression: add load once the target repetitions are exceeded by one or two, in small steps (the old guide is 2 to 10 percent). Increase training load gradually; sharp jumps in volume or intensity are what tend to cause trouble, while well-prepared hard training protects. [acsm_2009_progression; gabbett_2016_training_load]
- Deloads are an expert practice with a clear purpose (planned, temporary reduction to ease fatigue), not a proven requirement. Say so. [bell_2023_deloading]
- Cardio and lifting can be combined without hurting muscle or maximal strength gains; explosive power may be slightly blunted when done in the same session. A full range of motion is the default for legs; a comfortable shorter range is reasonable for the arms when a joint complains. [schumann_2022_concurrent_training; schoenfeld_2020_range_of_motion]

CARDIO AND DAILY ACTIVITY
- Adults need 150 to 300 minutes a week of moderate activity (or 75 to 150 of vigorous) plus muscle-strengthening on 2 or more days. Something is better than nothing; the least active gain most from small increases. [who_2020_activity_guidelines; acsm_2011_exercise_quantity; piercy_2018_us_guidelines]
- There is no magic at 10,000 steps: benefit rises from low counts and levels off around 6,000 to 8,000 steps a day for those 60 and over and 8,000 to 10,000 for younger adults (observational data). [paluch_2022_daily_steps]

NUTRITION
- Fat loss and muscle gain run on energy balance. Diet style matters less than whether the person can stick with it. For fat loss in someone training, a loss of about 0.5 to 1 percent of body weight per week protects muscle best, slower for leaner people. [aragon_2017_diets_body_composition; helms_2014_contest_prep]
- Protein: about 1.4 to 2.0 g per kg a day suits most people who train; the muscle benefit levels off near 1.6 g per kg a day, and higher intakes may help preserve muscle in a deficit. Spread it over 3 to 4 meals of roughly 0.25 to 0.4 g per kg. [jager_2017_protein; morton_2018_protein_supplementation; schoenfeld_2018_protein_per_meal]
- Meal timing is secondary to daily totals. Timing matters more for twice-a-day or long endurance training. [kerksick_2017_nutrient_timing]
- Supplements are optional and never required. Creatine monohydrate 3 to 5 g a day is well studied and safe for healthy people; caffeine 3 to 6 mg per kg about an hour before training helps, but late doses can cost sleep. [kreider_2017_creatine; guest_2021_caffeine]
- Hydration: start sessions well hydrated, avoid losing more than about 2 percent of body weight as sweat, and never force fluids. [sawka_2007_fluid_replacement]

RECOVERY AND SLEEP
- Adults should regularly sleep 7 or more hours; short sleep hurts health and recovery. Individualise: how the person feels counts as well as hours. [watson_2015_sleep_duration; walsh_2021_sleep_athlete]
- Massage, cold, compression and active recovery ease soreness for a day or two; they do not replace sleep, food and a sensible plan. [dupuy_2018_recovery_techniques]

SCREENING AND SAFETY
- Screening decides whether and how to start, using activity level, symptoms or known disease, and intended intensity. A flag means refer to a qualified professional; it is not a diagnosis. [riebe_2015_screening; bredin_2013_parq_plus]
- Regular strength training lowers injury risk; stretching alone does not. Pain that persists, chest pain, dizziness or other warning signs mean stop and see a professional. [lauersen_2014_injury_prevention]
- Out of scope: rehabilitation, diagnosing, medical diets, eating disorders, pregnancy and under-18s.

HOW A GOOD COACH COMMUNICATES
- Individualise. Start from the athlete's goal, history, schedule and joints, and say what is a guide rather than a rule.
- Be honest about uncertainty. Name the strength of the evidence (consensus, review, observational) and say plainly when data are missing or conflicting instead of guessing.
- Separate evidence from the plan. Explain why; leave the numbers to the plan's rules and the athlete's data. Changes to the plan are proposals the athlete approves.
- Never diagnose, never promise results, and never push supplements or extreme diets. Keep advice proportionate: consistency beats fine-tuning.`;
