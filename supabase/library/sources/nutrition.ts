import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Nutrition for training: protein, energy balance and body composition, timing, creatine,
// caffeine and hydration. General guidance for healthy adults, not medical nutrition.

export const nutritionSources: readonly LibrarySource[] = [
  {
    slug: "jager_2017_protein",
    label: "Jäger et al. 2017 (ISSN)",
    title: "International Society of Sports Nutrition position stand: protein and exercise",
    authors: ["Jäger R", "Kerksick CM", "Campbell BI", "Cribb PJ", "Wells SD", "Skwiat TM"],
    year: 2017,
    doi: "10.1186/s12970-017-0177-8",
    url: "https://doi.org/10.1186/s12970-017-0177-8",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["nutrition", "protein", "hypertrophy", "body-composition", "timing"],
    evidenceLevel: "position stand",
    kind: "position_stand",
    chosenBecause:
      "The standard open position on daily protein for people who train; it grounds the protein targets Coach explains. Summarised from the abstract only.",
    sections: [
      {
        title: "How much protein per day",
        body: `For most people who exercise, a daily intake of about 1.4 to 2.0 grams of protein per kilogram of body weight is enough to build or keep muscle. That range sits within the normal healthy-diet guidance for protein.

Higher intakes of about 2.3 to 3.1 grams per kilogram may help hold on to lean mass in resistance-trained people when they are eating below maintenance. There is newer, less settled evidence that intakes above 3 grams per kilogram might even help fat loss in trained people.`,
      },
      {
        title: "Dose per meal and spacing",
        body: `Advice on the best amount per serving is mixed and depends on age and recent training. As a general guide the position stand gives about 0.25 grams of high-quality protein per kilogram of body weight, or roughly 20 to 40 grams, spread fairly evenly through the day, around every three to four hours. A serving should contain a full set of the essential amino acids, with enough of the amino acid leucine.`,
      },
      {
        title: "Timing and food choice",
        body: `Eating protein before or after resistance training both help, and the muscle-building effect of a session lasts at least a day, so the exact timing is mostly a matter of what the person tolerates. Whole foods can supply all the protein needed; supplements are a convenient way to hit the numbers, especially with high training volumes. Casein (a slow-digesting milk protein) of 30 to 40 grams before sleep raises overnight muscle protein building without blunting fat burning. Endurance athletes should not neglect carbohydrate, and adding protein may help recovery.`,
      },
      {
        title: "Practical reading and limits",
        body: `These are general figures for healthy adults. They do not replace advice from a clinician or dietitian for kidney disease, pregnancy or other medical conditions, which Tracend does not cover. Protein targets work best alongside enough total energy and a sensible training plan.`,
      },
    ],
  },
  {
    slug: "kerksick_2017_nutrient_timing",
    label: "Kerksick et al. 2017 (ISSN)",
    title: "International Society of Sports Nutrition position stand: nutrient timing",
    authors: ["Kerksick CM", "Arent S", "Schoenfeld BJ", "Stout JR", "Campbell B", "Wilborn CD"],
    year: 2017,
    doi: "10.1186/s12970-017-0189-4",
    url: "https://doi.org/10.1186/s12970-017-0189-4",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["nutrition", "timing", "protein", "carbohydrate", "recovery"],
    evidenceLevel: "position stand",
    kind: "position_stand",
    chosenBecause:
      "Answers the very common 'does meal timing matter?' with a clear order of priorities; useful for keeping advice proportionate. Summarised from the abstract only.",
    sections: [
      {
        title: "What matters first",
        body: `Of everything about when to eat, the position stand puts the total daily protein intake first, ideally spread evenly with feedings about every three hours. A dose of roughly 20 to 40 grams of protein, or about 10 grams of essential amino acids, is enough to maximally stimulate muscle protein building in a single sitting. About 0.25 to 0.40 grams per kilogram of body weight every three to four hours was linked with the best muscle protein building and body composition results.`,
      },
      {
        title: "Around the workout",
        body: `Eating protein, or carbohydrate with protein, before or after a session can support strength and body composition. Protein within about two hours after training stimulates muscle protein building strongly, although the size and timing of the meal eaten before training affects how much that post-workout feeding matters. Taking in carbohydrate and protein during resistance training can also help muscle glycogen and limit muscle damage.`,
      },
      {
        title: "For heavy or long training",
        body: `People training very hard or for a long time need more attention to carbohydrate. Muscle glycogen stores are best filled with a high-carbohydrate diet of 8 to 12 grams per kilogram per day, and when a second hard session comes soon after the first, refuelling quickly with carbohydrate (and protein) matters. For efforts above about an hour at high intensity the stand suggests roughly 30 to 60 grams of carbohydrate per hour. Casein protein of about 30 to 40 grams before sleep can raise overnight muscle protein building.`,
      },
      {
        title: "Practical reading and limits",
        body: `For most recreational lifters, hitting daily protein and total energy needs matters far more than squeezing food into a narrow window. Timing becomes more useful for people training twice a day, doing long endurance work or trying to recover quickly. Meal frequency alone changes weight loss and body composition little. The numbers are general guidance for healthy adults, with the strongest evidence in trained people.`,
      },
    ],
  },
  {
    slug: "schoenfeld_2018_protein_per_meal",
    label: "Schoenfeld and Aragon 2018",
    title:
      "How much protein can the body use in a single meal for muscle-building? Implications for daily protein distribution",
    authors: ["Schoenfeld BJ", "Aragon AA"],
    year: 2018,
    doi: "10.1186/s12970-018-0215-1",
    url: "https://doi.org/10.1186/s12970-018-0215-1",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["nutrition", "protein", "timing", "hypertrophy"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "Corrects the myth that the body can only use about 25 grams of protein per meal, so Coach can give sensible meal-by-meal protein advice. Summarised from the abstract only.",
    sections: [
      {
        title: "The myth being tested",
        body: `Some people believe muscle protein building is maxed out at about 20 to 25 grams of protein in a meal and that anything beyond that is wasted. The authors point out that this idea comes from studies of quickly digested protein taken alone, and that protein eaten in a mixed meal or from slower sources is absorbed more gradually and so is likely used better.`,
      },
      {
        title: "What the evidence shows",
        body: `Larger servings (above 20 grams) do cause more of the amino acids to be burned for energy, but not all of the extra is lost; some of it goes into tissue building. The authors concluded that to maximise muscle building, a person should aim for about 0.4 grams per kilogram of body weight per meal across at least four meals, enough to reach a total of at least 1.6 grams per kilogram per day. If someone eats the upper daily intake from the literature, 2.2 grams per kilogram, over the same four meals, that is at most about 0.55 grams per kilogram per meal.`,
      },
      {
        title: "Practical reading and limits",
        body: `An 80 kg person aiming for the lower number would eat roughly 32 grams of protein at each of four meals. There is no need to panic about a meal with a bit more or less protein, but spreading intake sensibly through the day is better than saving it all for one sitting. It is a narrative review that sets a target by reasoning from the evidence, so it is not a rule that applies to every person.`,
      },
    ],
  },
  {
    slug: "morton_2018_protein_supplementation",
    label: "Morton et al. 2018",
    title:
      "A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength in healthy adults",
    authors: ["Morton RW", "Murphy KT", "McKellar SR", "Schoenfeld BJ", "Henselmans M", "Helms E"],
    year: 2018,
    doi: "10.1136/bjsports-2017-097608",
    url: "https://doi.org/10.1136/bjsports-2017-097608",
    licence: "CC-BY-NC-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["nutrition", "protein", "hypertrophy", "strength", "supplements"],
    evidenceLevel: "systematic review and meta-analysis (49 studies)",
    kind: "paper",
    chosenBecause:
      "The key evidence for the point where more protein stops adding muscle (about 1.6 g/kg/day), which sets a sensible ceiling for the advice. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body: `The authors pooled 49 randomised trials with 1,863 participants who followed a resistance training programme for at least six weeks and were given extra protein or not. They checked effects on strength and muscle size, and used a break-point analysis to find where extra protein stopped helping.`,
      },
      {
        title: "Findings",
        body: `Extra protein produced a significant, though modest, improvement in strength and in muscle size over prolonged training. The benefit was smaller with increasing age and larger in people who were already experienced lifters. Once total protein intake passed about 1.6 grams per kilogram of body weight per day, more protein no longer added gains in fat-free mass.`,
      },
      {
        title: "Practical reading and limits",
        body: `Around 1.6 grams per kilogram per day covers most of the muscle-building benefit of protein for healthy adults who lift; going far above it is not needed for growth (although other position stands note that higher intakes may help in a calorie deficit). Protein powder is a convenience, not a necessity, since the gain comes from the total daily amount. The 1.6 figure is where the average benefit levelled off, with some individual differences, so it is a guide rather than a hard limit.`,
      },
    ],
  },
  {
    slug: "aragon_2017_diets_body_composition",
    label: "Aragon et al. 2017 (ISSN)",
    title: "International society of sports nutrition position stand: diets and body composition",
    authors: ["Aragon AA", "Schoenfeld BJ", "Wildman R", "Kleiner S", "VanDusseldorp T", "Taylor L"],
    year: 2017,
    doi: "10.1186/s12970-017-0174-y",
    url: "https://doi.org/10.1186/s12970-017-0174-y",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["nutrition", "energy-balance", "body-composition", "protein", "fat-loss"],
    evidenceLevel: "position stand",
    kind: "position_stand",
    chosenBecause:
      "The best open statement on how energy balance and diet style change body composition, backing Tracend's focus on calories, protein and adherence over diet branding. Summarised from the abstract only.",
    sections: [
      {
        title: "Fat loss and muscle gain run on energy balance",
        body: `Diets aimed at fat loss work through a sustained calorie deficit. The more body fat a person starts with, the more aggressively the deficit can be set; leaner people hold on to more lean mass with slower rates of weight loss. Diets aimed at gaining lean mass run on a sustained surplus that supports the training load, and the size of the surplus and the person's training status affect what is gained.`,
      },
      {
        title: "Diet style matters less than people think",
        body: `A wide range of eating styles, from low-fat to low-carbohydrate and ketogenic, can improve body composition about equally well. Intermittent calorie restriction (such as alternate patterns) showed no significant advantage over restricting calories every day. Long-term success depends heavily on whether the person can stick with the approach, and on factors such as the body's adaptive reduction in energy use during dieting.`,
      },
      {
        title: "Protein",
        body: `Protein above the usual guidance for athletes may improve body composition. In lean, resistance-trained people eating below maintenance, intakes of about 2.3 to 3.1 grams per kilogram of fat-free mass may be needed to maximise muscle retention. Very high intakes above 3 grams per kilogram may add satiety and lean-mass protection, but the evidence is early.`,
      },
      {
        title: "Practical reading and limits",
        body: `Choose a diet the person can maintain, set calories for the goal, keep protein high, and expect slower loss to protect lean mass in lean people. The position stand notes little research on women and older adults, and that methods for measuring body composition each have limits, so single measurements deserve some caution. It is not guidance for eating disorders or medical diets, which Tracend does not cover.`,
      },
    ],
  },
  {
    slug: "helms_2014_contest_prep",
    label: "Helms et al. 2014",
    title:
      "Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation",
    authors: ["Helms ER", "Aragon AA", "Fitschen PJ"],
    year: 2014,
    doi: "10.1186/1550-2783-11-20",
    url: "https://doi.org/10.1186/1550-2783-11-20",
    licence: "CC-BY-2.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["nutrition", "energy-balance", "body-composition", "protein", "fat-loss", "supplements"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "The most practical open source on the rate of weight loss and diet make-up when a lean person wants to lose fat and keep muscle. Summarised from the abstract only.",
    sections: [
      {
        title: "Rate of loss and macronutrients",
        body: `This review was written for natural bodybuilders cutting down for a contest, which is an extreme case of getting lean, so its figures suit lean, trained people with a clear fat-loss goal. It recommends setting calories so body weight falls by about 0.5 to 1 percent per week to keep as much muscle as possible. Within that, most people will do best on 2.3 to 3.1 grams of protein per kilogram of lean body mass per day, 15 to 30 percent of calories from fat, and the rest from carbohydrate.`,
      },
      {
        title: "Meal pattern and supplements",
        body: `Eating three to six meals a day with a protein-containing meal (0.4 to 0.5 grams per kilogram of body weight) before and after resistance training probably captures any benefit of timing. But changes to meal timing and frequency made little difference to fat loss or lean mass retention. Of the popular supplements, creatine monohydrate, caffeine and beta-alanine looked helpful, while others did not or need more study.`,
      },
      {
        title: "Warnings",
        body: `The authors warn that deliberately dehydrating and manipulating electrolytes in the last days before a show can be dangerous and may not even improve appearance. They also stress that sports focused on appearance carry a raised risk of eating and body-image disorders, so athletes should be able to reach appropriate mental health professionals.`,
      },
      {
        title: "Practical reading and limits",
        body: `The rate of 0.5 to 1 percent of body weight per week is a useful ceiling for most people trying to lose fat while training, with the slower end suiting leaner people. These recommendations come from a review of the literature on a specialised group, so Tracend should not push people towards contest-style leanness. Anyone with a history of disordered eating is outside the product's scope.`,
      },
    ],
  },
  {
    slug: "kreider_2017_creatine",
    label: "Kreider et al. 2017 (ISSN)",
    title:
      "International Society of Sports Nutrition position stand: safety and efficacy of creatine supplementation in exercise, sport, and medicine",
    authors: ["Kreider RB", "Kalman DS", "Antonio J", "Ziegenfuss TN", "Wildman R", "Collins R"],
    year: 2017,
    doi: "10.1186/s12970-017-0173-z",
    url: "https://doi.org/10.1186/s12970-017-0173-z",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["nutrition", "creatine", "supplements", "strength", "safety"],
    evidenceLevel: "position stand",
    kind: "position_stand",
    chosenBecause:
      "Creatine is the best-supported training supplement; this open position stand covers both benefit and safety, which Coach needs for honest answers. Summarised from the full text.",
    sections: [
      {
        title: "What creatine does",
        body: `Taking creatine raises the creatine and phosphocreatine stored in muscle, which supports high-intensity effort and so helps people do more quality work in training and adapt better. The position stand also reports possible help with recovery after exercise, tolerating heavy training loads and some injury-related outcomes.`,
      },
      {
        title: "How much to take",
        body: `The quickest way to fill muscle stores is a loading phase of roughly 0.3 grams per kilogram of body weight per day (for example 5 grams four times a day) for 5 to 7 days, then 3 to 5 grams a day to maintain. Taking 3 to 5 grams a day without loading also raises stores, but more slowly, over about three to four weeks. Larger people may need up to 5 to 10 grams a day to maintain stores.`,
      },
      {
        title: "Safety",
        body: `Short- and long-term use, up to 30 grams a day for five years in the studies reviewed, was safe and well tolerated in healthy people, and in several patient groups from infants to older adults. Creatine is often taken with a meal or with carbohydrate and protein.`,
      },
      {
        title: "Practical reading and limits",
        body: `Creatine monohydrate at 3 to 5 grams a day is a low-cost, well-studied option for people who lift, and loading is optional. It is a supplement, not a requirement, and is not a substitute for training, sleep and food. Anyone with a medical condition, especially kidney problems, or who takes medication should check with a clinician first, since this position stand is aimed at healthy people. Coach should not push supplements and should be clear that results vary between individuals.`,
      },
    ],
  },
  {
    slug: "guest_2021_caffeine",
    label: "Guest et al. 2021 (ISSN)",
    title: "International society of sports nutrition position stand: caffeine and exercise performance",
    authors: ["Guest NS", "VanDusseldorp TA", "Nelson MT", "Grgic J", "Schoenfeld BJ", "Jenkins NDM"],
    year: 2021,
    doi: "10.1186/s12970-020-00383-4",
    url: "https://doi.org/10.1186/s12970-020-00383-4",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["nutrition", "caffeine", "supplements", "performance", "sleep"],
    evidenceLevel: "position stand",
    kind: "position_stand",
    chosenBecause:
      "Gives dose and timing guidance for the most widely used performance aid, plus the sleep and anxiety trade-offs Coach should mention. Summarised from the abstract only.",
    sections: [
      {
        title: "What caffeine does for training",
        body: `Caffeine has small to moderate benefits for muscular endurance, bar speed, strength, sprinting, jumping and many sport-specific actions, and it improves attention and vigilance in most people. The most consistent moderate-to-large benefits are for aerobic endurance. It helps both trained and untrained people, and may help thinking and physical performance when someone is sleep-deprived, although the size of the benefit differs between individuals.`,
      },
      {
        title: "Dose and timing",
        body: `Doses of 3 to 6 milligrams per kilogram of body weight reliably help performance, and the smallest effective dose may be as low as 2 milligrams per kilogram. Very high doses (about 9 milligrams per kilogram) bring many more side effects and are not needed. The most common timing is about 60 minutes before exercise; chewing gum may work faster than capsules. Coffee, gum, energy drinks, gels and pre-workout products containing caffeine can all raise performance.`,
      },
      {
        title: "Why responses differ",
        body: `Genetic differences in how caffeine is processed, habitual intake and other factors explain why some people feel a lot and others little, and why some get trouble sleeping or feel anxious after a dose.`,
      },
      {
        title: "Practical reading and limits",
        body: `A modest dose before training can help, but late-day caffeine can cost sleep, and poor sleep undermines recovery, so evening sessions are a reason to use less or none. People who are sensitive, anxious, pregnant or who have heart or blood pressure issues should be cautious and check with a clinician. Coach should present caffeine as optional and personal, never as something a person must use.`,
      },
    ],
  },
  {
    slug: "sawka_2007_fluid_replacement",
    label: "Sawka et al. 2007 (ACSM)",
    title: "American College of Sports Medicine position stand: exercise and fluid replacement",
    authors: ["Sawka MN", "Burke LM", "Eichner ER", "Maughan RJ", "Montain SJ", "Stachenfeld NS"],
    year: 2007,
    doi: "10.1249/mss.0b013e31802ca597",
    url: "https://doi.org/10.1249/mss.0b013e31802ca597",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-17",
    region: ["global"],
    topics: ["nutrition", "hydration", "performance", "safety"],
    evidenceLevel: "position stand",
    kind: "position_stand",
    chosenBecause:
      "The main professional position on drinking before, during and after exercise, with a practical way to measure personal needs. Summarised from the abstract only.",
    sections: [
      {
        title: "Before and during exercise",
        body: `The aim before exercise is to start well hydrated with normal blood salt levels. If needed, drink beverages alongside normal meals and fluids beginning at least several hours beforehand, which gives the body time to absorb the fluid and let urine output return to normal.

During exercise, the goal is to avoid losing more than about 2 percent of body weight as water, since larger losses and big shifts in blood salts can harm performance. Sweat rates and sweat salt content vary a great deal from person to person, so a personalised plan is better than a single rule.`,
      },
      {
        title: "How to find your own needs",
        body: `A simple way to estimate a personal sweat rate is to weigh yourself before and after a session. During longer exercise, drinks that contain electrolytes and carbohydrate can help more than plain water in some situations.`,
      },
      {
        title: "After exercise",
        body: `Afterwards the goal is to replace any fluid and salt deficit. How fast and how aggressively depends on how big the deficit is and how soon the next session is.`,
      },
      {
        title: "Practical reading and limits",
        body: `For most gym sessions of an hour or less, normal drinking to thirst and with meals is enough; careful fluid planning matters more for long, hot or repeated sessions. Overdrinking can be harmful too, so no one should be told to force fluids. The position stand is from 2007, and it is guidance for healthy people, not for medical conditions affecting fluid balance.`,
      },
    ],
  },
];
