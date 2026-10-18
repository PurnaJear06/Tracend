import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// India: nutrient requirements, food composition, body-size cut-offs for Asian Indians and
// activity patterns. All are tagged region IN (a caller passes ["global", "IN"] to see them),
// like the ICMR-NIN 2024 dietary guidelines entry. The ICMR-NIN documents may not be reproduced
// in an electronic product without NIN's written permission, so only individual facts with a
// citation are stored, never their tables. Summaries are in Tracend's own words.

export const indiaSources: readonly LibrarySource[] = [
  {
    slug: "icmr_nin_2020_nutrient_requirements",
    label: "ICMR-NIN 2020 (RDA and EAR)",
    title:
      "Nutrient requirements for Indians: Recommended Dietary Allowances (RDA) and Estimated Average Requirements (EAR), 2020",
    authors: ["ICMR-NIN Expert Group on Nutrient Requirement for Indians"],
    year: 2020,
    doi: null,
    url: "https://www.nin.res.in/rdabook/brief_note.pdf",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["IN"],
    topics: ["nutrition", "protein", "energy-balance", "guidelines", "india", "vegetarian"],
    evidenceLevel: "national nutrient requirements (expert committee)",
    kind: "guideline",
    chosenBecause:
      "India's official nutrient requirements; Indian athletes meet its protein figure in school, on labels and from doctors, so Coach must explain how it relates to the higher sports-nutrition figures. Summarised from the official summary (NIN's brief note; the full report is sold in print and was not read).",
    sections: [
      {
        title: "What the 2020 report changed",
        body:
          `The 2020 expert group gives two values for each nutrient instead of one. The estimated average requirement (EAR) is the middle of the range of healthy people's needs; the recommended dietary allowance (RDA) sits near the top of that range, so it covers almost everyone. The group recommends using the EAR for planning diets, for individuals as well as populations, and keeping the RDA for addressing deficiency; EARs are typically about 80 percent of RDAs. Upper limits were added because more foods are now fortified.`,
      },
      {
        title: "Energy",
        body:
          `Energy need is worked out as basal metabolic rate multiplied by a physical activity level. Indian studies showed activities cost less energy than the Western figures assumed, so the activity factor for sedentary people was lowered from 1.53 to 1.40, and the basal rate predicted by international equations was cut by a further 5 percent for adults (this adds to the 2010 cut, so the total is 10 percent below the international equations). Adult energy needs therefore fell by about 3 to 8 kcal per kg a day compared with 2010. The reference adults weigh 65 kg (men) and 55 kg (women); for sedentary work the reference man needs about 2,110 kcal a day and the reference woman about 1,660. Visible fat such as cooking oil is advised at 20 to 50 g a day, depending on energy needs.`,
      },
      {
        title: "Protein",
        body:
          `For healthy adults (the same per-kg figure is given for sedentary, moderate and heavy work) the average requirement is 0.66 g of protein per kg a day and the allowance is 0.83 g per kg (lowered from 1 g per kg in 2010). For people whose diet is mostly cereal with low-quality protein, the requirement is given as 1 g per kg. The report adopts a newer protein-quality score based on digestibility of individual amino acids (DIAAS), and for good protein quality it suggests a cereal to legume to milk ratio of about 3 to 1 to 2.5 in the diet.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `These figures are the amounts that prevent deficiency in healthy, mostly sedentary adults, not targets for building muscle. People who train are given 1.4 to 2.0 g per kg in the Jäger 2017 entry, and the 2026 US guidelines give 1.2 to 1.6 g per kg for the general public; the plan's rules set the athlete's number. For an Indian vegetarian diet the report's point about quality matters: combining cereals with dal and milk or curd improves protein quality. This summary is from NIN's official brief note, not the full book.`,
      },
    ],
  },
  {
    slug: "longvah_2017_ifct",
    label: "Longvah et al. 2017 (IFCT)",
    title: "Indian Food Composition Tables 2017",
    authors: ["Longvah T", "Ananthan R", "Bhaskarachary K", "Venkaiah K"],
    year: 2017,
    doi: null,
    url: "https://nin.res.in/ebooks/IFCT2017.pdf",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["IN"],
    topics: ["nutrition", "food-composition", "protein", "india", "vegetarian"],
    evidenceLevel: "national food composition database (laboratory analysis)",
    kind: "summary",
    chosenBecause:
      "India's reference for what common foods contain, needed when Coach explains logged Indian meals; it also shows why raw and cooked weights must not be mixed. Summarised from the full document (front matter and methods; only a few single values are cited, never its tables).",
    sections: [
      {
        title: "What the tables are",
        body:
          `The National Institute of Nutrition's 2017 tables give values for 151 food components in 528 key foods. Key foods were chosen from a national rural diet survey as the foods supplying most of the population's nutrients. Samples were bought in 107 of India's then 630 districts, pooled within six regions, and analysed in the laboratory; for most foods the national value is the mean of the six regions (some foods were sampled in fewer), and no figures were borrowed from other databases. India's first food composition table dates from 1937.`,
      },
      {
        title: "How to read the values",
        body:
          `Values are per 100 g as analysed (raw, except the egg, which is boiled), for the edible portion. Energy is calculated with standard Atwater factors and reported in kilojoules. The authors warn that vitamins vary with processing and cooking, and that the tables are not a complete list of foods eaten in India: many regional and community dishes are missing.

A few single values show the scale. Per 100 g as analysed, red gram (toor) dal has about 22 g of protein, lentil (masoor) dal about 24 g and whole Bengal gram (chana) about 19 g; paneer has about 19 g, and a whole boiled egg about 13 g.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Because the values are for raw food, a cooked portion must be matched to its raw weight: weighing cooked dal, which has absorbed water, against the raw-dal figure would greatly overstate its protein and energy. Values are national averages, and a given batch or brand can differ. NIN's terms do not allow the tables to be reproduced in an electronic product without written permission, so Tracend stores only these individual facts with the citation.`,
      },
    ],
  },
  {
    slug: "who_2004_asian_bmi",
    label: "WHO expert consultation 2004",
    title:
      "Appropriate body-mass index for Asian populations and its implications for policy and intervention strategies",
    authors: ["WHO Expert Consultation"],
    year: 2004,
    doi: "10.1016/S0140-6736(03)15268-3",
    url: "https://doi.org/10.1016/S0140-6736(03)15268-3",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["IN"],
    topics: ["bmi", "body-composition", "health", "guidelines", "india"],
    evidenceLevel: "expert consultation (evidence review)",
    kind: "guideline",
    chosenBecause:
      "The origin of the lower BMI action points used for Asian populations, including India; it explains why a BMI that is normal by the international scale can carry more risk for an Indian athlete. Summarised from the abstract only.",
    sections: [
      {
        title: "What the consultation did",
        body:
          `WHO convened experts to settle whether the standard BMI cut-offs suit Asian people, who tend to carry more body fat, and more disease risk, at a given BMI than people of European origin.`,
      },
      {
        title: "Conclusions",
        body:
          `Many Asian adults already face raised diabetes and heart-disease risk below a BMI of 25. Where that risk starts differs between Asian groups (from about 22 to 25, with high risk from 26 to 31), so the experts set no single Asian cut-off. They kept the international categories and added extra points for public-health action at 23, 27.5, 32.5 and 37.5, leaving each country to decide where its own increased-risk range begins.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `For Indian adults, a BMI of 23 to 25 can already be a reason to look at waist size, activity and diet rather than a sign that all is well (the Misra 2025 entry gives India's current clinical criteria). BMI cannot tell muscle from fat, so a muscular lifter can sit above these points with little body fat. These are population screening points; Coach never diagnoses. This summary is from the abstract only, so the evidence behind each figure is not described here.`,
      },
    ],
  },
  {
    slug: "misra_2025_obesity_asian_indians",
    label: "Misra et al. 2025",
    title: "Revised definition of obesity in Asian Indians living in India",
    authors: ["Misra A", "Vikram NK", "Ghosh A", "Ranjan P", "Gulati S", "India Obesity Commission Members"],
    year: 2025,
    doi: "10.1016/j.dsx.2024.102989",
    url: "https://doi.org/10.1016/j.dsx.2024.102989",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["IN"],
    topics: ["bmi", "body-composition", "fat-loss", "activity", "guidelines", "india"],
    evidenceLevel: "expert consensus (Delphi, five rounds, 118 experts invited)",
    kind: "guideline",
    chosenBecause:
      "India's current clinical definition of obesity, which replaced the 2009 Asian Indian cut-offs; it gives the BMI, waist and body-fat points Indian users will hear about and its own activity advice. Summarised from the full text.",
    sections: [
      {
        title: "What the consensus did",
        body:
          `The 2009 Indian consensus had defined overweight as a BMI of 23 to 24.9, obesity as 25 or more, and abdominal obesity as a waist of 90 cm or more in men and 80 cm or more in women. This update, by an Indian obesity commission, used a five-round Delphi survey of experts (118 were invited) to move from BMI alone to a definition that also counts fat distribution, physical function and related disease. A statement needed agreement from at least two thirds of respondents.`,
      },
      {
        title: "The new definition",
        body:
          `Stage 1 obesity is a BMI above 23 with no effect on organ function or daily activities and no obesity-related disease. Stage 2 obesity needs a BMI above 23 plus excess waist size or waist-to-height ratio, together with limits in daily activities or an obesity-related disease. Body fat is named the gold standard where it can be measured (above 25.5 percent in men and 38 percent in women). The waist cut-offs remain 90 cm for men and 80 cm for women, a waist-to-height ratio above 0.5 counts as excess, and a normal BMI is 18.5 to 22.99 (its BMI grades place 23 to 24.9 in the first overweight grade).`,
      },
      {
        title: "Diet and activity advice",
        body:
          `For weight loss the paper suggests a daily deficit of roughly 500 kcal, and calls a loss of 0.5 to 1 kg a week safe (which needs a deficit of about 500 to 1,000 kcal a day), kept up long term. It recommends at least 60 minutes of activity a day for weight loss, notes that 45 to 60 minutes of moderate activity a day is linked with moving out of the overweight range, and asks for muscle-strengthening work on at least three days a week, increased gradually. People with heart, lung or nerve and muscle conditions should be assessed by a professional before starting.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This is a clinical definition for diagnosis by doctors; Coach never stages or diagnoses obesity. Its lower cut-offs fit the WHO 2004 entry. The paper calls measured body fat the gold standard but treats it as optional, and its rules let body fat override BMI only when BMI is below 23; it makes no exception for muscular people. A lifter can exceed a BMI of 23 with little fat, so for people who train, a BMI above 23 alone is not evidence of excess fat. Its rate of loss in kilograms is a general figure; for people who train, the library's fat-loss sources prefer about 0.5 to 1 percent of body weight a week. The drug and surgery sections are outside Tracend's scope and are not summarised.`,
      },
    ],
  },
  {
    slug: "anjana_2014_indiab_activity",
    label: "Anjana et al. 2014 (ICMR-INDIAB)",
    title:
      "Physical activity and inactivity patterns in India: results from the ICMR-INDIAB study (Phase-1) [ICMR-INDIAB-5]",
    authors: ["Anjana RM", "Pradeepa R", "Das AK", "Deepa M", "Bhansali A", "Joshi SR"],
    year: 2014,
    doi: "10.1186/1479-5868-11-26",
    url: "https://doi.org/10.1186/1479-5868-11-26",
    licence: "CC-BY-2.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["IN"],
    topics: ["activity", "india", "sedentary", "health", "behaviour-change"],
    evidenceLevel: "cross-sectional survey (14,227 adults, four regions)",
    kind: "paper",
    chosenBecause:
      "A large, representative survey of how active Indian adults are and where their activity comes from, which shows why leisure exercise has to be planned for most Indian users. Summarised from the full text.",
    sections: [
      {
        title: "What the study did",
        body:
          `As part of the Indian Council of Medical Research's diabetes study, researchers surveyed 14,227 adults aged 20 and over (about 4,200 urban and 10,000 rural) in Tamil Nadu, Maharashtra, Jharkhand and Chandigarh, chosen to represent the south, west, east and north of India. Activity was self-reported with the WHO Global Physical Activity Questionnaire, which covers work, travel and recreation.`,
      },
      {
        title: "Findings",
        body:
          `Just over half (54.4 percent) were inactive by the questionnaire's standard, 31.9 percent were active and 13.7 percent highly active. Inactivity was more common in towns than villages (65 against 50 percent) and in women than men (63 against 46 percent), and was highest in Chandigarh. Most moderate or vigorous activity came from work: those who had any active work averaged about 46 minutes a day (about a third of the sample), and those who reported active travel averaged about 14 minutes. More than 90 percent did no recreational activity at all, and the share with none rose with age.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `For many Indian adults, activity has come from work and getting around rather than from exercise, so as jobs and travel become less physical, deliberate exercise and steps have to fill the gap. Women and city dwellers were the least active groups. The data are self-reported, from four regions surveyed before 2014, and the questionnaire may not fit every local activity, so current national levels may differ.`,
      },
    ],
  },
];
