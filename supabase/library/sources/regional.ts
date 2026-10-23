import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Regional modules (E4, decision D5): national food, activity and body-measure guidance for the
// regions the app serves beyond India (whose six sources are in india.ts, energy_balance.ts and
// guidelines.ts): the United Kingdom, the United States and Australia, plus one global WHO report
// that explains why the body-measure thresholds differ between regions. Each region has a nutrition
// source and a body-measure source (BMI and waist, with the points that differ for people of Asian
// origin); Coach reaches a regional source only for an athlete in that country (the search's region
// filter). Summaries are in Tracend's own words, written from the documents named in each entry.
// Only the two UK documents carry a licence that allows short quotation (Open Government Licence
// v3.0); every other entry here is `proprietary` (no open licence found, or one that could not be
// read), so it is a summary with a link. Everything here is guidance for the general adult
// population: the plan's rules set the athlete's numbers, and Coach never diagnoses.

export const regionalSources: readonly LibrarySource[] = [
  {
    slug: "nhs_2026_overweight_obesity_adults",
    label: "NHS 2026 (Overweight and obesity in adults)",
    title: "Overweight and obesity in adults",
    authors: ["NHS"],
    year: 2026,
    doi: null,
    url: "https://www.nhs.uk/conditions/obesity/",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-23",
    region: ["GB"],
    topics: [
      "bmi",
      "waist",
      "body-composition",
      "fat-loss",
      "guidelines",
      "united-kingdom",
      "ethnicity",
    ],
    evidenceLevel: "national health service patient guidance",
    kind: "guideline",
    chosenBecause:
      "The UK health service's own public guidance on how to read BMI and waist size, with lower BMI points for people of South Asian, Chinese, other Asian, Middle Eastern, Black African or African-Caribbean background; it is what a UK athlete will be told by their GP. The page was last reviewed on 29 April 2026. The NICE guideline behind it could not be read here, so this page stands in for it. Summarised from the full text.",
    sections: [
      {
        title: "BMI points",
        body:
          `The page gives two sets of BMI points for adults. For most adults, a BMI from 25 to 29.9 is overweight and 30 or more is obese. For people from a South Asian, Chinese, other Asian, Middle Eastern, Black African or African-Caribbean background, who it says are at risk of health problems at a somewhat lower BMI, the points are lower: 23 to 27.4 is overweight and 27.5 or more is obese.

It also states that a BMI calculator cannot tell muscle from fat, so someone with a lot of muscle may be placed in the overweight or obese band without much body fat.`,
      },
      {
        title: "Waist and when to see a GP",
        body:
          `For adults with a BMI under 35 the page suggests the waist-to-height ratio as a check on fat carried around the middle, and advises keeping the waist under half of height. It points to a video on how to measure the waist.

A GP visit is advised for someone in the overweight or obese band who wants help to lose weight, whose waist is more than half their height, who has pre-diabetes, diabetes, high blood pressure, joint pain, high cholesterol, sleep apnoea or cardiovascular disease, who has a family history of obesity, or who has or may have an eating disorder such as binge eating.`,
      },
      {
        title: "Losing weight",
        body:
          `The advice for losing weight is to eat and drink fewer calories than the body uses and to be more active. It suggests a steady loss of 0.5 to 1 kg a week, 45 to 60 minutes of activity a day (which can be split into shorter sessions), cutting down on alcohol because it is high in calories, and setting realistic goals. It says an average woman uses about 2,000 calories a day and an average man about 2,500, and that losing 5 to 10 percent of body weight can improve health.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `These are population points for reading BMI, not a diagnosis, and Coach never labels an athlete overweight or obese. For a lifter the page's own muscle caveat matters most: a high BMI with a small waist-to-height ratio is not evidence of excess fat, and the waist-to-height ratio does not apply at a BMI of 35 or more. The 0.5 to 1 kg a week and 45 to 60 minutes are the general public's figures; the library's fat-loss sources and the plan's rules set the pace for someone who trains. The lower points for people of Asian origin are the public-health action points WHO set out in 2004. This page is patient guidance, not the NICE guideline itself.`,
      },
    ],
  },
  {
    slug: "phe_2018_quick_guide_healthy_eating",
    label: "PHE 2018 (Quick Guide to healthy eating)",
    title: "A Quick Guide to the Government's Healthy Eating Recommendations",
    authors: ["Public Health England"],
    year: 2018,
    doi: null,
    url:
      "https://assets.publishing.service.gov.uk/media/5ba8a087e5274a55c3407c38/A_quick_guide_to_govt_healthy_eating_update.pdf",
    licence: "OGL-UK-3.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-23",
    region: ["GB"],
    topics: [
      "nutrition",
      "guidelines",
      "energy-balance",
      "hydration",
      "supplements",
      "united-kingdom",
    ],
    evidenceLevel: "national dietary guideline summary (Eatwell Guide)",
    kind: "guideline",
    chosenBecause:
      "The UK's official food guide in words: what the Eatwell Guide asks for in each food group, the fluid and fish advice and the vitamin D advice; it is how UK health professionals and dietitians describe a balanced diet. The gov.uk page for the guide was last updated in January 2024 and the guide itself dates from 2016. Summarised from the full document.",
    sections: [
      {
        title: "The five food groups",
        body:
          `The Eatwell Guide shows what share of a day's food should come from each group, over a day or a week rather than at every meal. Over a third should be fruit and vegetables, at least 5 portions of 80 g a day. Meals should be based on potatoes, bread, rice, pasta or other starchy carbohydrate, wholegrain where possible. Some dairy or alternatives should be included, choosing lower fat and lower sugar versions, and unsweetened calcium-fortified drinks if swapping to a plant drink.`,
      },
      {
        title: "Proteins, fats and fluid",
        body:
          `Beans, pulses, fish, eggs, meat and other proteins come next. The guide asks for two portions (140 g each) of fish a week, one of them oily, and no more than 70 g a day of red and processed meat on average. Pulses are named as a low-fat, high-fibre alternative to meat. Unsaturated oils and spreads should be used in small amounts, and foods high in fat, salt and sugar eaten less often and in small amounts.

It advises 6 to 8 glasses of fluid a day, counting water, lower-fat milk and sugar-free drinks including tea and coffee, and limits fruit juice and smoothies to a combined 150 ml a day.`,
      },
      {
        title: "Energy and vitamin D",
        body:
          `The average energy requirement is given as 2,500 kcal a day for a man and 2,000 for a woman, and the guide says the amount a person needs depends on factors such as how active they are. By convention, on a 2,000 kcal day, about 400 kcal comes at breakfast, 600 at lunch, 600 in the evening and 400 as snacks and drinks.

For vitamin D, it recommends that everyone aged five and over consider a 10 microgram supplement each day from October to March, and all year round for people with little sun exposure, including people from minority ethnic groups with dark skin such as African, African-Caribbean and South Asian origin. Folic acid advice for women planning a pregnancy is also given.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This is general population advice. The 2,500 and 2,000 kcal figures are averages; a heavy trainer needs more, and the plan's rules set the athlete's calories and protein. The guide gives no protein target in grams; the Government Dietary Recommendations entry has one. Coach states the vitamin D advice as the official UK advice and never pushes a supplement. The document is Crown copyright under the Open Government Licence v3.0, so short quotation with attribution is allowed; the Eatwell Guide image is not summarised.`,
      },
    ],
  },
  {
    slug: "phe_2016_government_dietary_recommendations",
    label: "PHE 2016 (Government Dietary Recommendations)",
    title:
      "Government Dietary Recommendations: government recommendations for energy and nutrients for males and females aged 1 to 18 years and 19+ years",
    authors: ["Public Health England"],
    year: 2016,
    doi: null,
    url:
      "https://assets.publishing.service.gov.uk/media/5a749fece5274a44083b82d8/government_dietary_recommendations.pdf",
    licence: "OGL-UK-3.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-23",
    region: ["GB"],
    topics: ["nutrition", "protein", "energy-balance", "guidelines", "united-kingdom"],
    evidenceLevel: "national dietary reference values",
    kind: "guideline",
    chosenBecause:
      "The numbers behind the UK's healthy eating advice for adults: daily energy, protein, fat, carbohydrate, free sugars, salt and fibre. A UK athlete asking what the official daily protein or fibre figure is gets it from here, and Coach can explain how it differs from the sports-nutrition range. Summarised from the full document.",
    sections: [
      {
        title: "Adult figures",
        body:
          `For adults aged 19 to 64 the government's daily recommendations are, for men and women respectively: energy 2,500 and 2,000 kcal, protein 55.5 and 45 g, fat under 97 and 78 g, saturated fat under 31 and 24 g, carbohydrate at least 333 and 267 g, free sugars under 33 and 27 g, salt under 6 g and fibre 30 g.

Older age bands have lower energy and slightly lower protein figures (men aged 65 and over 53.3 g, women 46.5 g).`,
      },
      {
        title: "Where the numbers come from",
        body:
          `The tables are a summary of earlier expert advice (COMA and the Scientific Advisory Committee on Nutrition). The energy figures are capped at 2,500 and 2,000 kcal for adults to help address overweight and obesity, and the document says they relate to the general population and individual needs vary. Carbohydrate is set at 50 percent and free sugars at 5 percent of energy, from the 2015 SACN carbohydrate report, and the fibre figure comes from the same report. Salt figures are described as achievable population goals, not ideal intakes. Protein figures come from the 1991 dietary reference values.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `These are population recommendations for people with no medical condition (the document tells anyone with a condition to see a GP or dietitian), and they are not targets for a lifter. Its protein figure is a minimum for health; the sports-nutrition range in the Jäger 2017 entry and the plan's rules are higher and are what Coach uses for the athlete's own number. The energy figures are deliberately capped and do not describe a heavy training load. Free sugars, salt and fibre are fine to cite as the UK recommendation. The document is under the Open Government Licence v3.0, so a short quotation with attribution is allowed.`,
      },
    ],
  },
  {
    slug: "nhlbi_2000_practical_guide_obesity",
    label: "NHLBI and NAASO 2000 (Practical Guide)",
    title:
      "The Practical Guide: Identification, Evaluation, and Treatment of Overweight and Obesity in Adults",
    authors: [
      "NHLBI Obesity Education Initiative Expert Panel",
      "North American Association for the Study of Obesity",
    ],
    year: 2000,
    doi: null,
    url: "https://www.nhlbi.nih.gov/files/docs/guidelines/prctgd_c.pdf",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-23",
    region: ["US"],
    topics: [
      "bmi",
      "waist",
      "body-composition",
      "fat-loss",
      "guidelines",
      "united-states",
      "ethnicity",
    ],
    evidenceLevel: "federal clinical guideline (expert panel, 1998; practical guide 2000)",
    kind: "guideline",
    chosenBecause:
      "The US federal guide to BMI classes and waist size: BMI bands, the 40 inch (102 cm) and 35 inch (88 cm) waist lines, how to take a waist measurement, and the warning that BMI overestimates fat in very muscular people. It is a National Institutes of Health publication with a non-government co-sponsor and no rights notice in its text, so it is treated as a summary only. It dates from 2000, and the CDC's current BMI page could not be opened from here to check for newer wording. Summarised from the full document.",
    sections: [
      {
        title: "BMI classes and waist lines",
        body:
          `The guide classes adult BMI as under 18.5 underweight, 18.5 to 24.9 normal, 25 to 29.9 overweight, 30 to 34.9 class I obesity, 35 to 39.9 class II and 40 or more class III. It adds that these relate BMI to disease risk in groups and that the link between BMI and risk varies between individuals and populations.

A waist over 40 inches (102 cm) for men or over 35 inches (88 cm) for women adds to the risk of type 2 diabetes, high cholesterol and blood fats, high blood pressure and cardiovascular disease in people with a BMI from 25 to 34.9. A waist over those values moves a person up one risk category. Waist adds little above a BMI of 35.`,
      },
      {
        title: "Taking the measurement",
        body:
          `The waist is measured around the abdomen at the level of the top of the hip bone (the iliac crest), with the tape snug but not pressing into the skin, parallel to the floor, at the end of a normal breath out. BMI is weight in pounds times 703 divided by height in inches squared (or kilograms over metres squared).`,
      },
      {
        title: "Muscle, ethnicity and age",
        body:
          `The guide says BMI can overestimate body fat in very muscular people and underestimate it in people who have lost muscle, such as many older adults, and that clinical judgement is needed with a very muscular patient. It notes that body fat for a given BMI varies with age, sex and possibly ethnicity, and that in some groups, for example Asian Americans, waist circumference is a better indicator of relative disease risk than BMI. It does not give separate BMI points for Asian Americans.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `A muscular lifter can sit in the overweight band with a waist well under the lines, so Coach reads BMI and waist together and never presents a band as a verdict. Other countries' guidance sets lower BMI points for people of Asian origin, and this guide does not. The waist lines here are for risk in groups, not a target. The guide's treatment chapters (drugs, surgery) are outside Tracend's scope and are not summarised.`,
      },
    ],
  },
  {
    slug: "nhmrc_2013_australian_dietary_guidelines",
    label: "NHMRC 2013 (Australian Dietary Guidelines)",
    title: "Australian Dietary Guidelines",
    authors: ["National Health and Medical Research Council"],
    year: 2013,
    doi: null,
    url: "https://www.eatforhealth.gov.au/guidelines/australian-dietary-guidelines-1-5",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-23",
    region: ["AU"],
    topics: [
      "nutrition",
      "bmi",
      "waist",
      "body-composition",
      "protein",
      "guidelines",
      "australia",
      "ethnicity",
      "energy-balance",
    ],
    evidenceLevel: "national dietary guideline (systematic evidence review)",
    kind: "guideline",
    chosenBecause:
      "Australia's official food guidance, still current in 2026 while NHMRC reviews it: the five guidelines, the daily serves for adults and, in its chapter on healthy weight, the BMI bands, the waist lines and the notes on people of Asian origin and of Polynesian origin. It was read from the copy of the 2013 edition that WHO hosts, whose copyright notice allows only personal and internal non-commercial use, so it is treated as a summary only. Summarised from the full document.",
    sections: [
      {
        title: "The five guidelines",
        body:
          `The first guideline is to reach and keep a healthy weight, be physically active and choose amounts of nutritious food that fit energy needs; older people are asked to keep eating well and stay active to keep muscle strength. The second is to enjoy a wide variety of foods from five groups every day, with water: vegetables and legumes; fruit; grain foods, mostly wholegrain; lean meat, poultry, fish, eggs, tofu, nuts, seeds and legumes; and milk, yoghurt, cheese or alternatives, mostly reduced fat.

The third limits saturated fat, added salt, added sugars and alcohol. The fourth supports breastfeeding and the fifth is food safety.`,
      },
      {
        title: "Serves for adults",
        body:
          `For the lean meat, poultry, fish, eggs, tofu, nuts, seeds and legumes group the minimum is 3 serves a day for men aged 19 to 50 and 2.5 for women aged 19 to 50, falling to 2.5 and 2 from 51. A serve is, for example, 65 g of cooked lean red meat, 80 g of cooked poultry, 100 g of cooked fish, 2 large eggs, 1 cup (150 g) of cooked legumes or 170 g of tofu. The guidelines say taller or more active people can add serves from the groups to meet higher energy needs, and should then watch weight or waist so intake does not exceed use.`,
      },
      {
        title: "BMI and waist",
        body:
          `Healthy weight is judged by BMI: under 18.5 underweight, 18.5 to 24.9 healthy, 25 to 29.9 overweight and 30 or more obese. The guidelines say these bands may not suit every group: people of Asian origin may carry equivalent risk at a lower BMI, people of Polynesian origin at a higher one, and a higher BMI range may be desirable over age 70. For Australians of Asian origin it adds that the WHO bands, which were derived mainly from people of European origin, may underestimate body fat and risk.

For waist, risk is increased at 80 cm or more and high at 88 cm or more for women, and increased at 94 cm or more and high at 102 cm or more for men, with the caution that thresholds for other ethnic groups may differ. It suggests measuring weight and waist regularly, for example every two to three months.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The serves are a minimum pattern for the general public, not a protein target for a lifter; the Australian protein reference values entry gives the grams per kilo, and the plan's rules set the athlete's number. The guidelines predate sports-nutrition work and say nothing specific to people who train. The waist lines are the same as the WHO figures commonly quoted. NHMRC has said it is reviewing the 2013 edition, so the guidance may change. The weight chapter also covers children, pregnancy and eating disorders; this summary does not, and Coach never diagnoses.`,
      },
    ],
  },
  {
    slug: "nhmrc_nz_2006_nrv_protein",
    label: "NHMRC and NZ Ministry of Health 2006 (protein)",
    title: "Nutrient Reference Values for Australia and New Zealand: Protein",
    authors: [
      "National Health and Medical Research Council",
      "Australian Government Department of Health and Ageing",
      "New Zealand Ministry of Health",
    ],
    year: 2006,
    doi: null,
    url: "https://www.eatforhealth.gov.au/nutrient-reference-values/nutrients/protein",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-23",
    region: ["AU"],
    topics: ["nutrition", "protein", "guidelines", "australia", "plant-protein"],
    evidenceLevel: "national nutrient reference values",
    kind: "guideline",
    chosenBecause:
      "Australia's official daily protein values per kilogram of body weight for adults, which an Australian athlete will see quoted and which sit well below the sports-nutrition range; Coach needs to explain the difference. The protein page was last updated on 9 April 2014. Read from the site's archived copy of 3 November 2022, because the live site could not be opened from here. Summarised from the full text.",
    sections: [
      {
        title: "Adult values",
        body:
          `For adults aged 19 to 70 the page gives an estimated average requirement of 0.68 g per kg of body weight a day for men and 0.60 g for women, and a recommended dietary intake (enough for nearly everyone) of 0.84 g per kg for men and 0.75 g for women. For men that is 64 g a day and for women 46 g. Over age 70 the values are raised by 25 percent (men 0.86 and 1.07 g per kg, women 0.75 and 0.94 g per kg), though the page says the evidence for that increase is limited.`,
      },
      {
        title: "Upper level and sources",
        body:
          `No upper limit in grams a day was set because the data are insufficient. The page recommends an upper level of 25 percent of energy from protein, and says the risk of harm from protein in everyday foods is very low, though it advises caution with supplements of individual amino acids. It notes protein comes from animal and plant foods, that all the essential amino acids can be had from plant sources, and that in Australia and New Zealand meat, poultry and fish give about a third and cereals about a quarter of intake.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `These values are the amount that meets the needs of healthy people at rest, estimated by a factorial method for healthy people, not the amount that best supports hard training. The sports-nutrition range in the Jäger 2017 and Morton 2018 entries is higher for people who lift, and the plan's rules set the athlete's own number; the library does not read the Australian value as a ceiling. The page has no section on athletes. Protein for pregnancy and breastfeeding is on the page and is not summarised here. `,
      },
    ],
  },
  {
    slug: "au_health_2021_adult_activity_guidelines",
    label: "Australian Department of Health 2021 (adult activity guidelines)",
    title:
      "Physical activity and exercise guidelines for all Australians: for adults (18 to 64 years)",
    authors: ["Australian Government Department of Health, Disability and Ageing"],
    year: 2021,
    doi: null,
    url:
      "https://www.health.gov.au/topics/physical-activity-and-exercise/physical-activity-and-exercise-guidelines-for-all-australians/for-adults-18-to-64-years",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-23",
    region: ["AU"],
    topics: ["activity", "cardio", "strength", "guidelines", "sedentary", "australia"],
    evidenceLevel: "national public health guideline",
    kind: "guideline",
    chosenBecause:
      "Australia's official weekly activity advice for adults, with its muscle-strengthening line and examples that include lifting weights; it is the Australian counterpart of the WHO, US and UK entries. The department's page was last updated on 10 May 2021 and was read from the archived copy of March 2026, because the live site could not be opened from here. Summarised from the full text.",
    sections: [
      {
        title: "What adults should do",
        body:
          `Adults should be active most days, preferably every day. Each week they should do either 2.5 to 5 hours of moderate activity such as brisk walking, golf, mowing or swimming, or 1.25 to 2.5 hours of vigorous activity such as jogging, aerobics, fast cycling or soccer, or an equivalent mix.

Muscle-strengthening activities should be included on at least 2 days each week. The page lists push-ups, pull-ups, squats or lunges, lifting weights and household tasks that involve lifting, carrying or digging. Any activity is better than none, and an inactive person should start with some and build up slowly.`,
      },
      {
        title: "Sitting and benefits",
        body:
          `Long periods of sitting can offset the benefits of being active, so the page suggests reducing sitting and breaking it up, for example by walking meetings, a standing desk or a walk at lunch. It lists benefits for adults: lower risk of type 2 diabetes, cardiovascular disease and some cancers, better blood pressure, cholesterol and blood sugar, less unhealthy weight gain, stronger muscles and bones, and better wellbeing.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This is a floor for health, and a lifter's plan usually exceeds it, so Coach presents it as the minimum that already pays off. It agrees broadly with the WHO 2020 and UK 2026 entries, and its upper bounds (5 hours moderate, 2.5 hours vigorous) are a range of benefit, not a limit. The page does not set repetitions, loads or a time for the strength days, and its pregnancy and older-adult pages are separate and not summarised.`,
      },
    ],
  },
  {
    slug: "who_2011_waist_circumference_report",
    label: "WHO 2011 (waist circumference and waist-hip ratio)",
    title: "Waist circumference and waist-hip ratio: report of a WHO expert consultation",
    authors: ["World Health Organization"],
    year: 2011,
    doi: null,
    url: "https://www.who.int/publications/i/item/9789241501491",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-23",
    region: ["global"],
    topics: ["waist", "bmi", "body-composition", "guidelines", "ethnicity", "health"],
    evidenceLevel: "expert consultation (evidence review)",
    kind: "guideline",
    chosenBecause:
      "The international reference for why waist-size thresholds are not the same everywhere: it reviews how waist and waist-to-hip ratio predict disease, how to measure them, and which cut-offs countries use. It is the base for the regional waist lines in the UK, US, Australian and Indian entries. The consultation met in December 2008 and WHO published the report on 16 May 2011. It was read from the archived copy of WHO's library file, because WHO's current site returned only an error page to the download. Summarised from the full document.",
    sections: [
      {
        title: "What the consultation found",
        body:
          `The experts found convincing evidence that a larger waist and a larger waist-to-hip ratio go with more disease risk in many populations, though most of the data came from people of European descent. The measures are related to BMI but do not carry the same information, and the report favours waist circumference over waist-to-hip ratio because it is easier to take. It advises obtaining a BMI where possible and considering the two together, and found too little data to give the waist-to-height ratio priority at the time.`,
      },
      {
        title: "Differences between populations",
        body:
          `The report finds substantial differences by sex and age and some by ethnicity. Compared with people of European descent, Asian populations carry more visceral fat, and in Asian populations a given waist can go with more risk, so lower thresholds may be needed; for African populations and possibly Pacific Islanders, higher ones may be needed. The experts conclude that one set of BMI and waist cut-offs is not suitable worldwide, but they did not set new cut-offs: that was left to a later WHO process.`,
      },
      {
        title: "Cut-offs and how to measure",
        body:
          `The report lists the cut-offs in common use. WHO publications from 1999 and 2000 are the source of 94 cm (men) and 80 cm (women) for increased risk and 102 cm and 88 cm for substantially increased risk, though the second report gave them only as an example from a Dutch sample, not as WHO recommendations. The International Diabetes Federation uses 94 cm and 80 cm for Europeans and 90 cm and 80 cm for South Asians, Chinese and Japanese, and the US cholesterol programme uses 102 cm and 88 cm.

Protocols differ on where to measure: the WHO STEPS method is at the midpoint between the lowest palpable rib and the top of the hip bone, the US methods at the top of the hip bone.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Coach uses this report to explain why the lines in an athlete's country may differ from another country's, and never to apply a line of its own. Waist lines are group screening points, not a diagnosis or a target, and a lean, muscular lifter can have a waist that reads high or low for reasons the lines do not capture. The report predates the waist-to-height ratio guidance in the UK entry. The measuring point matters: a figure from one method should not be compared with a line set for another.`,
      },
    ],
  },
];
