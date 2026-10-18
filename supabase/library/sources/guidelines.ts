import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// National guidelines whose licence allows short verbatim quotation with attribution: two US
// federal works (public domain) and the UK Chief Medical Officers' guidelines (Open Government
// Licence v3.0). Summaries are still written in Tracend's own words, from the full documents;
// a quotation, where one is used, is marked and attributed.

export const guidelineSources: readonly LibrarySource[] = [
  {
    slug: "hhs_2018_physical_activity_guidelines",
    label: "HHS 2018 (Physical Activity Guidelines for Americans)",
    title: "Physical Activity Guidelines for Americans, 2nd edition",
    authors: ["US Department of Health and Human Services"],
    year: 2018,
    doi: null,
    url:
      "https://odphp.health.gov/sites/default/files/2019-09/Physical_Activity_Guidelines_2nd_edition.pdf",
    licence: "public-domain-us-gov",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["US"],
    topics: [
      "activity",
      "cardio",
      "strength",
      "guidelines",
      "progression",
      "older-adults",
      "safety",
      "sedentary",
    ],
    evidenceLevel: "national public health guideline (2018 Advisory Committee evidence review)",
    kind: "guideline",
    chosenBecause:
      "The full US guideline behind the JAMA summary already in the library; it adds how to build up safely, what counts as muscle strengthening, and the extra advice for older adults. Summarised from the full document.",
    sections: [
      {
        title: "How much adults need",
        body:
          `For substantial health benefit, adults are advised to get 150 to 300 minutes a week of moderate aerobic activity, or 75 to 150 minutes of vigorous activity, or a mix of the two, ideally spread across the week. Going beyond the equivalent of 300 moderate minutes brings further benefit. On top of that, adults should do muscle-strengthening work of at least moderate intensity that covers all the major muscle groups on two or more days a week.

The guideline also tells adults to move more and sit less, because any amount of moderate or vigorous activity helps. The 2008 rule that activity only counted in bouts of at least 10 minutes was dropped: bouts of any length now count towards the weekly total.`,
      },
      {
        title: "Strength work and building up",
        body:
          `No set time is given for strength work. Each exercise should be taken to the point where another repetition would be hard. For strength, one set of 8 to 12 repetitions per exercise works, and 2 or 3 sets may work better.

The guideline's phrase for beginners is "start low and go slow". An inactive person starts with light or moderate activity in short sessions spread over the week (its example is walking 5 minutes several times a day, building towards 10 minutes three times a day) and strength work on one day a week, rising to two or more. It notes that injury risk grows with the gap between a person's usual activity and the new level, and that healthy adults planning gradual increases do not need to see a clinician first. The largest health gain comes from going from no activity to about 60 minutes a week.`,
      },
      {
        title: "Older adults and safety",
        body:
          `Older adults follow the adult guidelines and add multicomponent activity: balance training together with aerobic and strength work. They should judge effort relative to their own fitness, understand how any chronic condition affects safe activity, and stay as active as they can when 150 minutes is out of reach. Stretching improves flexibility, but its health benefits are unknown and it does not count towards the aerobic or strength targets.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This is a public health floor for health, not a programme for maximum muscle or performance, so a lifter's plan usually goes well beyond it. It agrees closely with the WHO 2020 entry; the Piercy 2018 entry is its journal summary. The document is a US federal work in the public domain, so a short quotation with attribution (as above) is allowed. Its pregnancy guidance is outside Tracend's scope.`,
      },
    ],
  },
  {
    slug: "usda_hhs_2026_dietary_guidelines",
    label: "USDA and HHS 2026 (Dietary Guidelines for Americans)",
    title: "Dietary Guidelines for Americans, 2025-2030",
    authors: ["US Department of Agriculture", "US Department of Health and Human Services"],
    year: 2026,
    doi: null,
    url: "https://cdn.realfood.gov/DGA.pdf",
    licence: "public-domain-us-gov",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["US"],
    topics: [
      "nutrition",
      "protein",
      "guidelines",
      "energy-balance",
      "vegetarian",
      "alcohol",
      "hydration",
      "older-adults",
    ],
    evidenceLevel: "national dietary guideline",
    kind: "guideline",
    chosenBecause:
      "The current US federal food guidance, released in January 2026; its protein goal is far higher than earlier editions and than India's allowance, a difference Coach must be able to explain. Summarised from the full document.",
    sections: [
      {
        title: "What this edition says",
        body:
          `The 10th edition, from the US Departments of Agriculture and of Health and Human Services, is a short document built around eating whole, nutrient-dense food and sharply cutting highly processed food, added sugars and refined carbohydrate. The two secretaries describe it as a major reset of federal nutrition advice.

Calorie needs depend on age, sex, height, weight and activity, and portion size deserves attention. Protein foods, animal and plant, should come first at every meal, with a goal of 1.2 to 1.6 g of protein per kg of body weight a day, adjusted to calorie needs. For a 2,000-calorie pattern it suggests 3 servings of dairy (including full-fat dairy with no added sugars), 3 of vegetables, 2 of fruit and 2 to 4 of whole grains.`,
      },
      {
        title: "Limits, drinks and salt",
        body:
          `Saturated fat should generally stay at or below 10 percent of daily calories. No amount of added sugar is recommended, and a single meal should carry no more than 10 g of it. Water and unsweetened drinks are the default. Sodium should stay under 2,300 mg a day from age 14, though the document notes that very active people may benefit from more to cover sweat losses. On alcohol, drinking less is better for health.`,
      },
      {
        title: "Vegetarians and older adults",
        body:
          `Vegetarian diets often fall short on vitamins D and E, choline and iron, and vegan diets on a wider list that includes vitamin B12, calcium, zinc and protein. The advice is to vary plant protein sources, limit highly processed vegetarian foods, and check iron, vitamin B12, vitamin D, calcium and iodine status from time to time. Older adults may need fewer calories but the same or more protein, vitamin B12, vitamin D and calcium.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The protein goal sits close to the sports-nutrition range in the Jäger 2017 entry and well above India's allowance of 0.83 g per kg (the ICMR-NIN 2020 entry). They answer different questions: an allowance is the least that covers nearly every healthy person, while these goals aim higher. The plan's rules set the athlete's number. This summary covers the guideline document only, not the evidence review behind it; it is a US federal work in the public domain, so short quotation with attribution is allowed. That covers the text only: the PDF also contains Shutterstock images, which that public-domain status does not cover.`,
      },
    ],
  },
  {
    slug: "uk_cmo_2026_activity_guidelines",
    label: "UK CMOs 2026",
    title: "UK Chief Medical Officers' physical activity guidelines",
    authors: ["UK Chief Medical Officers", "Department of Health and Social Care"],
    year: 2026,
    doi: null,
    url:
      "https://www.gov.uk/government/publications/physical-activity-guidelines-uk-chief-medical-officers-report/uk-chief-medical-officers-physical-activity-guidelines",
    licence: "OGL-UK-3.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["GB"],
    topics: [
      "activity",
      "cardio",
      "strength",
      "guidelines",
      "older-adults",
      "sedentary",
      "minimal-dose",
    ],
    evidenceLevel: "national public health guideline (first issued 2011, revised 2019, evidence updated 2026)",
    kind: "guideline",
    chosenBecause:
      "The UK's official activity guidance, first issued in 2011, revised in 2019, with the evidence updated in July 2026 without changing the guidance; it states plainly how little strength work already pays off and that weekly minutes can come in one or two sessions. Summarised from the full document.",
    sections: [
      {
        title: "What adults are advised to do",
        body:
          `Adults aged 19 to 64 should aim to be active every day, and any activity is better than none. They should do activities that build or keep strength in the major muscle groups on at least two days a week. Each week they should accumulate at least 150 minutes of moderate activity such as brisk walking or cycling, or 75 minutes of vigorous activity such as running, or even shorter spells of very vigorous activity such as sprinting or stair climbing, or a mix. Long spells of sitting should be broken up with at least light activity. In the guidelines' own words, "some is good, more is better".`,
      },
      {
        title: "What the evidence behind it says",
        body:
          `The 150 minutes can come in bouts of any length, or in one or two sessions a week, and still bring benefit. Benefit rises steeply up to about 150 minutes and more slowly after that, and the largest gain comes from moving from inactive to fairly active, even below the target.

Strength work is described as being as important as the aerobic minutes. The evidence supports sessions once or twice a week, with measurable health benefit from more than 30 and up to 120 minutes a week, but not enough evidence to set a duration. Bodyweight, free weights, machines, bands and daily lifting and carrying all count. For weight loss, more than 150 minutes together with eating less may be needed, and no exact amount can be given. Total sitting above 6 to 8 hours a day was linked with higher mortality, but no sitting limit is set.`,
      },
      {
        title: "Older adults",
        body:
          `People aged 65 and over should be active daily, work on strength, balance and flexibility on at least two days a week, and build up gradually towards 150 minutes of moderate activity (or 75 vigorous minutes if already active). They should break up sitting with light activity or at least standing. The evidence on high-intensity interval training in older people is described as very limited.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The UK advice matches the WHO 2020 and US 2018 entries on aerobic minutes and twice-weekly strength work, and it is the clearest of the three that a little strength training already helps. These are health minimums, not targets for muscle growth, and the plan's rules set the actual work. The page is under the Open Government Licence v3.0, so short quotation with attribution is allowed. The next update is planned with the World Health Organization for 2030.`,
      },
    ],
  },
];
