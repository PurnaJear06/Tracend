import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Long diets and keeping weight off: diet breaks, metabolic adaptation, low energy availability,
// weight-loss maintenance, alcohol, and the Indian national dietary guidelines (E2.1).

export const energyBalanceSources: readonly LibrarySource[] = [
  {
    slug: "byrne_2018_matador",
    label: "Byrne et al. 2018 (MATADOR)",
    title: "Intermittent energy restriction improves weight loss efficiency in obese men: the MATADOR study",
    authors: ["Byrne NM", "Sainsbury A", "King NA", "Hills AP", "Wood RE"],
    year: 2018,
    doi: "10.1038/ijo.2017.206",
    url: "https://doi.org/10.1038/ijo.2017.206",
    licence: "CC-BY-NC-ND-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "energy-balance", "fat-loss", "diet-break", "metabolic-adaptation"],
    evidenceLevel: "randomised controlled trial (51 men with obesity)",
    kind: "paper",
    chosenBecause:
      "The best-known trial of planned breaks from dieting, so Coach can explain what a diet break is and what the evidence for it does and does not show. Summarised from the abstract only.",
    sections: [
      {
        title: "What the trial did",
        body: `Fifty-one men with obesity were randomly placed on one of two diets. Both groups ate 67 percent of what they needed to hold their weight for 16 weeks in total. One group did this continuously. The other did it as eight blocks of two weeks, with a two-week block of eating at maintenance between them, so their diet lasted 30 weeks from start to finish. Forty-seven men began the diet phase, and the main results below are for the 19 continuous and 17 intermittent dieters who finished as planned.`,
      },
      {
        title: "Results",
        body: `The intermittent group lost more weight (14.1 against 9.1 kg) and more fat (12.3 against 8.0 kg). Loss of fat-free mass was similar in the two groups (1.8 against 1.2 kg). Body weight barely moved during the seven maintenance blocks. The fall in resting energy expenditure was not different between groups, but once it was adjusted for changes in body composition the fall was smaller in the intermittent group. The authors read this as the maintenance blocks reducing the body's compensatory slowdown, which made the diet more efficient.`,
      },
      {
        title: "Practical reading and limits",
        body: `The participants were men with obesity (average weight about 110 kg), so the result is not proof for a lean, trained person. The intermittent group took 30 weeks to complete the same amount of dieting, so extra time passed, and the main analysis covered only the people who completed the protocol. A later trial in trained adults (the ICECAP trial) did not find extra fat loss from breaks. Coach should present a planned break as a reasonable option that helps some people stay on track and may help a little with efficiency, not as a requirement.`,
      },
    ],
  },
  {
    slug: "peos_2021_icecap",
    label: "Peos et al. 2021 (ICECAP)",
    title:
      "Continuous versus intermittent dieting for fat loss and fat-free mass retention in resistance-trained adults: the ICECAP trial",
    authors: ["Peos JJ", "Helms ER", "Fournier PA", "Ong J", "Hall C", "Krieger J"],
    year: 2021,
    doi: "10.1249/mss.0000000000002636",
    url: "https://doi.org/10.1249/mss.0000000000002636",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "energy-balance", "fat-loss", "diet-break", "training", "hunger"],
    evidenceLevel: "randomised controlled trial (61 resistance-trained adults)",
    kind: "paper",
    chosenBecause:
      "The only trial of diet breaks in resistance-trained men and women, and it did not reproduce the extra fat loss seen in earlier work, which keeps Coach honest about breaks. Summarised from the abstract only.",
    sections: [
      {
        title: "What the trial did",
        body: `Sixty-one resistance-trained adults (32 of them women, average age about 29, about 25 percent body fat) were randomly assigned to a moderate calorie deficit in one of two patterns. One group dieted for 12 weeks without a break. The other dieted in four blocks of three weeks, each followed by a week of eating at maintenance, which made 15 weeks in total. All results were analysed according to the group each person was assigned to.`,
      },
      {
        title: "Results",
        body: `After the deficit, the groups did not differ in fat mass, fat-free mass or body weight, and there was no difference in muscle strength or endurance, resting energy expenditure, the hormones measured (leptin, testosterone, thyroid hormone, IGF-1, ghrelin), sleep, or eating-disorder-related behaviours. The group that took breaks reported lower hunger and less desire to eat, and greater satisfaction with the diet.`,
      },
      {
        title: "Practical reading and limits",
        body: `For a trained person, breaks did not speed up fat loss or protect muscle better in this trial, but they made dieting feel easier. That is a good reason to offer a break to someone who is tired of dieting, and a poor reason to promise faster results. The trial lasted 12 weeks of deficit, so it does not say what happens over a very long diet.`,
      },
    ],
  },
  {
    slug: "trexler_2014_metabolic_adaptation",
    label: "Trexler et al. 2014",
    title: "Metabolic adaptation to weight loss: implications for the athlete",
    authors: ["Trexler ET", "Smith-Ryan AE", "Norton LE"],
    year: 2014,
    doi: "10.1186/1550-2783-11-7",
    url: "https://doi.org/10.1186/1550-2783-11-7",
    licence: "CC-BY-2.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: [
      "nutrition",
      "energy-balance",
      "fat-loss",
      "metabolic-adaptation",
      "diet-break",
      "weight-maintenance",
    ],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "Explains why fat loss slows and hunger rises on a long diet, the situation of anyone who has already lost a lot of weight and still wants to lose more. Summarised from the full text.",
    sections: [
      {
        title: "What happens in a long deficit",
        body: `Eating less is followed by changes in several hormones: leptin, insulin, testosterone and thyroid hormones tend to fall, while ghrelin (which raises hunger) and cortisol tend to rise. Total daily energy expenditure falls, and the fall is often bigger than the lost body mass alone would predict. This extra drop is called adaptive thermogenesis. The energy spent on exercise and on everyday movement outside exercise (fidgeting, walking about) also falls. Some of these changes persist after the diet, even in people who have kept the lower weight for more than a year.`,
      },
      {
        title: "What the authors recommend",
        body: `The size of the adaptation is probably in proportion to the size of the deficit, so the review advises using the smallest deficit that still gives appreciable weight loss, treating weight loss as a series of steps, and adjusting food or activity when progress flattens to open the deficit again. Large deficits cost more lean mass and hurt performance and recovery. A structured resistance training programme and enough protein help protect lean mass, and diets high in protein are linked with more fullness and more heat production from food.`,
      },
      {
        title: "Refeeds, reverse dieting and regaining",
        body: `Refeeds are short spells of eating slightly above maintenance, mostly extra carbohydrate, used in physique sports to lift leptin. Leptin does respond in the short term, but the measured rise in energy expenditure was modest, and the authors say there is not enough evidence that refeeds help a long diet. Reverse dieting (raising calories in small steps after a diet) is also unproven. After a diet, regained weight comes back mostly as fat, and leaner people can overshoot their old body fat. Repeated cycles of loss and regain are linked with long-term weight gain in weight-class athletes.`,
      },
      {
        title: "Practical reading and limits",
        body: `This is the explanation for a plateau or a rising appetite after a big loss: it is expected biology, not weak willpower, and the answer is patience, smaller deficits and keeping training and protein up. Most of the underlying research is on animals or on people with overweight who do not train, so how strongly it applies to a lean, trained person is uncertain. Refeeds and reverse dieting should be described as popular but unproven.`,
      },
    ],
  },
  {
    slug: "mountjoy_2023_reds",
    label: "Mountjoy et al. 2023 (IOC)",
    title:
      "2023 International Olympic Committee's (IOC) consensus statement on Relative Energy Deficiency in Sport (REDs)",
    authors: [
      "Mountjoy M",
      "Ackerman KE",
      "Bailey DM",
      "Burke LM",
      "Constantini N",
      "Hackney AC",
    ],
    year: 2023,
    doi: "10.1136/bjsports-2023-106994",
    url: "https://doi.org/10.1136/bjsports-2023-106994",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "energy-balance", "low-energy-availability", "recovery", "safety", "fat-loss"],
    evidenceLevel: "expert consensus statement",
    kind: "guideline",
    chosenBecause:
      "The leading authority on the health risk of eating too little for the training done, which Coach needs for anyone cutting hard while training. Summarised from the abstract only.",
    sections: [
      {
        title: "What REDs is",
        body: `Relative Energy Deficiency in Sport (REDs) is a syndrome of harmful health and performance effects seen in female and male athletes who are exposed to low energy availability, meaning they take in too little energy for the energy their exercise uses. The panel first described it in 2014 and updated it in 2023, after more than 170 new original studies since the 2018 statement.`,
      },
      {
        title: "What has changed",
        body: `The 2023 statement adds evidence on the part played by low carbohydrate availability and by mental health, and more data on low energy availability in males. It updates the health and performance models and introduces a physiological model that shows how a problematic or an adaptable period of low energy availability, together with personal factors, leads to different outcomes.`,
      },
      {
        title: "Assessment, prevention and treatment",
        body: `The statement sets out safe and effective ways to assess body composition to help prevent REDs, and introduces the REDs Clinical Assessment Tool version 2, which clinicians use to detect and diagnose REDs from the accumulated severity and risk level, with matching advice on training and competition. It also covers principles of prevention and treatment for sports organisations and clinicians.`,
      },
      {
        title: "Practical reading and limits",
        body: `This summary is written from the abstract, because the full text could not be fetched, so it does not list individual signs or thresholds. Detection and diagnosis belong to clinicians using the assessment tool, and Coach must never diagnose. The sensible use is to treat steady, large deficits combined with a lot of training as a reason to ask how the person feels, favour smaller deficits and enough food, and suggest a clinician when the picture looks worrying. The statement is aimed at athletes, so applying it to a recreational lifter is an extrapolation.`,
      },
    ],
  },
  {
    slug: "varkevisser_2019_weight_loss_maintenance",
    label: "Varkevisser et al. 2019",
    title: "Determinants of weight loss maintenance: a systematic review",
    authors: ["Varkevisser RDM", "van Stralen MM", "Kroeze W", "Ket JCF", "Steenhuis IHM"],
    year: 2019,
    doi: "10.1111/obr.12772",
    url: "https://doi.org/10.1111/obr.12772",
    licence: "CC-BY-NC-ND-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "weight-maintenance", "fat-loss", "behaviour-change", "adherence"],
    evidenceLevel: "systematic review (67 studies)",
    kind: "paper",
    chosenBecause:
      "The most careful review of what predicts keeping weight off, which tells Coach where to put attention once someone has lost a lot of weight. Summarised from the full text.",
    sections: [
      {
        title: "What the review did",
        body: `The reviewers searched for prospective studies of adults with overweight or obesity who lost weight without surgery or medication. From 8,222 articles they selected 67, which together tested 124 possible determinants of keeping weight off: 5 demographic, 59 behavioural, 51 psychological or cognitive and 9 social or environmental. They scored study quality and summarised each determinant by the strength of evidence.`,
      },
      {
        title: "What predicted success",
        body: `Age, gender and socioeconomic status did not predict who kept weight off. Strong evidence supported these as helpful: weighing oneself regularly, monitoring what one eats, increasing physical activity, controlling portions, cutting unhealthy foods, eating less overall, eating more fruit and vegetables and drinking fewer sugary drinks. Self-monitoring of exercise and confidence in one's ability to manage weight and to exercise (self-efficacy) were also positive. Problematic eating predicted regaining, and stress on its own was not a clear predictor.`,
      },
      {
        title: "Practical reading and limits",
        body: `Maintenance is a skill built from ordinary habits: keep tracking weight and food, stay active and stay confident, and it works in both sexes and at all ages. The review is of people with overweight or obesity, so it is only a rough guide for someone who is now at a healthy weight. The social and environmental evidence was thin, and the findings are associations, not proof of cause.`,
      },
    ],
  },
  {
    slug: "icmr_nin_2024_dietary_guidelines",
    label: "ICMR-NIN 2024",
    title: "Dietary Guidelines for Indians 2024",
    authors: ["ICMR-NIN Expert Committee"],
    year: 2024,
    doi: null,
    url: "https://www.nin.res.in/dietaryguidelines/pdfjs/locale/DGI_2024.pdf",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["IN"],
    topics: ["nutrition", "protein", "fat-loss", "energy-balance", "activity", "guidelines", "india"],
    evidenceLevel: "national dietary guidelines",
    kind: "guideline",
    chosenBecause:
      "India's official food-based guidance, needed for users in India, and it differs from the sports-nutrition papers on BMI and protein powders in ways Coach must explain. Summarised from the full document (guidelines 8, 9 and 10).",
    sections: [
      {
        title: "Body weight and weight loss",
        body: `The guidelines apply Asian BMI cut-offs because Asians tend to carry more body fat at a given BMI: a healthy range is 18.5 to 23, overweight is above 23 up to 27.5 and obesity is above 27.5. They also use waist circumference, which is linked to higher risk above 90 cm in men and above 80 cm in women. Weight loss should be gradual, with half a kilogram a week called safe. A weight-loss diet should not go below 1,000 kcal a day and should be nutritionally complete, and the guidelines advise against deficits above 40 percent of daily energy needs. Rapid loss and anti-obesity drugs should be avoided.`,
      },
      {
        title: "Protein",
        body: `The guidelines give 0.83 g of protein per kg a day as the recommended allowance for healthy men and women, with protein supplying 10 to 15 percent of energy, and say a varied diet meets this, including a vegetarian one. They advise getting protein from food rather than protein powders, and warn that very high intakes from powders over long periods are not advisable. They accept that a higher share, 15 percent of energy, may help keep muscle during a calorie deficit. They note that protein only builds muscle with enough energy from carbohydrate and fat and with resistance exercise, and that intakes above about 1.6 g per kg a day add no further muscle in resistance training.`,
      },
      {
        title: "Food pattern and activity",
        body: `The guidelines are food-based: a variety of whole grains and millets, pulses, vegetables, fruit, milk or curd, and nuts, with cereals and pulses combined (about 3 to 1 by raw weight) for better protein quality. They advise limiting sugar, salt, refined oil and ultra-processed foods, and avoiding soft drinks and alcohol. For activity, they recommend a combination of aerobic, strength, balance and flexibility work, including yoga, with muscle-strengthening at least two days a week for adults, and sleep of 6 to 8 hours a day.`,
      },
      {
        title: "Practical reading and limits",
        body: `For Indian users, use these foods and cut-offs alongside the sports papers: a person at a BMI of 23 is at the top of the Asian healthy range, not comfortably inside the usual 18.5 to 25. Where the guidelines and the sports-nutrition papers disagree, such as protein powders and the daily protein target for lifters, Coach should say the two sources differ and let the athlete's own needs and goals decide, with Tracend's rules setting the numbers. The guidelines are for the general population, not for athletes, and are not a basis for medical diets.`,
      },
    ],
  },
  {
    slug: "vella_2010_alcohol_recovery",
    label: "Vella and Cameron-Smith 2010",
    title: "Alcohol, athletic performance and recovery",
    authors: ["Vella LD", "Cameron-Smith D"],
    year: 2010,
    doi: "10.3390/nu2080781",
    url: "https://doi.org/10.3390/nu2080781",
    licence: "CC-BY-3.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["alcohol", "recovery", "nutrition", "sleep", "hydration", "performance"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "A free review of what alcohol does to exercise performance and recovery, for the common question of whether drinking undoes training. Summarised from the full text.",
    sections: [
      {
        title: "Effects on the body",
        body: `Alcohol acts as a diuretic, widens blood vessels, interferes with the body's temperature control and lowers work tolerance in both hot and cold conditions. It impairs the liver's glucose output and can reduce how much glucose muscle takes up and stores. It slows reaction time, balance and fine motor control in proportion to the dose, and it lowers sleep depth and shortens REM sleep.`,
      },
      {
        title: "Performance",
        body: `Evidence on endurance is mixed, with harm once blood alcohol is high enough. For strength and power the review found most studies did not show a clear effect of alcohol taken just before testing, though one sprint study did. The review stresses that few clinical trials exist.`,
      },
      {
        title: "Recovery",
        body: `Results on muscle-damage markers and on rebuilding energy stores after exercise were inconclusive, and glycogen replenished within 24 hours in one study even after alcohol. Alcohol lowers muscle protein synthesis in a dose-dependent way when no exercise is done, but how that applies after a hard lifting session has not been tested properly in humans. The clearest functional finding came from one research group: after hard eccentric exercise, drinking about 1 g of alcohol per kg of body weight made the loss of muscle force at 36 hours worse.`,
      },
      {
        title: "Practical reading and limits",
        body: `Drinking is unlikely to cancel out a training programme in one night, but it can make the next sessions worse through poorer sleep, dehydration and slower recovery from damaging exercise, and replacing food with alcohol cuts the carbohydrate and protein the muscles need. The review is from 2010 and includes few human trials, so Coach should speak in terms of "may" and not give precise limits. Coach should not encourage drinking, nor lecture an adult about it.`,
      },
    ],
  },
];
