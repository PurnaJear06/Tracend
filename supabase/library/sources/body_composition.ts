import type { LibrarySource } from "../../functions/_shared/library/types.ts";

// Body composition nutrition: energy surplus and bulking, recomposition, rate of fat loss, energy
// deficits and muscle, protein dose per meal, and plant-based and vegetarian protein. Summaries
// are written in Tracend's own words from each source's full text where it is open access, or
// from its abstract; no source text is copied.

export const bodyCompositionSources: readonly LibrarySource[] = [
  {
    slug: "trommelen_2023_protein_dose",
    label: "Trommelen et al. 2023",
    title:
      "The anabolic response to protein ingestion during recovery from exercise has no upper limit in magnitude and duration in vivo in humans",
    authors: [
      "Trommelen J",
      "van Lieshout GAA",
      "Nyakayiru J",
      "Holwerda AM",
      "Smeets JSJ",
      "Hendriks FK",
    ],
    year: 2023,
    doi: "10.1016/j.xcrm.2023.101324",
    url: "https://doi.org/10.1016/j.xcrm.2023.101324",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "protein", "timing", "hypertrophy"],
    evidenceLevel: "randomised controlled trial, acute tracer study (36 young men)",
    kind: "paper",
    chosenBecause:
      "Tests directly whether protein beyond about 25 g in one sitting is wasted, a question lifters ask about big meals and narrow eating windows. Summarised from the full text.",
    sections: [
      {
        title: "What the study did",
        body:
          `Thirty-six healthy, recreationally active young men did one whole-body resistance session and then drank 0, 25 or 100 g of milk protein (12 per group, assigned at random). The protein carried stable isotope labels, so the researchers could follow where its amino acids went, and they sampled blood and thigh muscle for 12 hours. Earlier dose studies had mostly tested 45 g at most and measured for 6 hours or less.`,
      },
      {
        title: "Findings",
        body:
          `Muscle protein building over the 12 hours rose with the dose: 100 g beat 25 g, which beat none. Compared with 25 g, the 100 g dose raised myofibrillar protein synthesis by about 20 percent in the first 4 hours and about 40 percent from hour 4 to 12, so the large serving worked mainly by lasting longer. After 100 g, protein was still being absorbed at 12 hours. Amino acid burning rose only slightly next to the rise in protein building, and body protein breakdown barely changed. About 18 percent of the 25 g serving and about 13 percent of the 100 g serving (about 13 g) was built into muscle over the 12 hours.`,
      },
      {
        title: "How it fits with other entries (Tracend's reading)",
        body:
          `The Schoenfeld and Aragon 2018 entry in this library, and the digest's guide of about 0.25 to 0.4 g per kg per meal over 3 to 4 meals, lean on studies in which muscle building levelled off near 20 to 25 g. This trial suggests that ceiling partly reflects measuring for too short a time: a large serving keeps working for longer rather than being burned off. The two are not fully at odds, because spreading protein still gives several rises across the day, but the idea that extra protein in one meal is simply wasted is not supported here.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This was one session and one drink in a laboratory, in young men, using milk protein after whole-body lifting. It did not measure muscle growth over weeks, and the authors note the body might adapt to repeated large meals. Tracend's reading: the daily total matters most, and spreading protein over 3 to 4 meals remains a sensible guide, but someone who prefers fewer, larger protein meals need not fear the extra is lost. One author works for a dairy company, which did not fund the study.`,
      },
    ],
  },
  {
    slug: "iraki_2019_offseason_bodybuilding",
    label: "Iraki et al. 2019",
    title: "Nutrition Recommendations for Bodybuilders in the Off-Season: A Narrative Review",
    authors: ["Iraki J", "Fitschen P", "Espinar S", "Helms E"],
    year: 2019,
    doi: "10.3390/sports7070154",
    url: "https://doi.org/10.3390/sports7070154",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "energy-surplus", "bulking", "protein", "hypertrophy", "supplements"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "The main evidence-based guide to eating for muscle gain in natural lifters, for anyone asking how big a surplus to run and how fast to gain. Summarised from the full text.",
    sections: [
      {
        title: "Surplus and rate of gain",
        body:
          `The review argues that the right surplus depends on training experience. Untrained people can gain mostly lean mass on large surpluses, but trained lifters are closer to their ceiling, so a big surplus mainly adds fat, which then lengthens the next diet. In one study of elite athletes it cites, eating about 600 kcal a day more gave slightly more lean mass (1.7 against 1.2 kg, not significant) but clearly more fat (1.1 against 0.2 kg). The authors suggest eating about 10 to 20 percent above maintenance and gaining about 0.25 to 0.5 percent of body weight a week, with advanced lifters at the low end or below, judged from weekly average weights.`,
      },
      {
        title: "Macronutrients and meals",
        body:
          `Protein of 1.6 to 2.2 g per kg a day is suggested, split into 3 to 6 meals of about 0.40 to 0.55 g per kg, with one meal within 1 to 2 hours of training. Fat of about 0.5 to 1.5 g per kg a day (20 to 35 percent of energy) avoids very low intakes, and the rest of the energy comes from carbohydrate, ideally at least 3 to 5 g per kg a day; ketogenic diets have gone with poorer muscle gain in trained people. The authors note that long-term studies often fail to confirm timing tricks that look useful in short laboratory studies.`,
      },
      {
        title: "Supplements",
        body:
          `Creatine monohydrate (3 g a day, no loading needed) and caffeine (5 to 6 mg per kg before training) are presented as likely to help; beta-alanine (3 to 5 g a day, for high-repetition phases) and citrulline malate (8 g before training) as possible. A low-dose multivitamin and fish oil are suggested only as a safety net for diet gaps or general health, not for muscle.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This is expert opinion built on mostly short studies; the authors say large, long trials in off-season bodybuilders are lacking. Its protein per meal sits above the digest's 0.25 to 0.4 g per kg, and its caffeine dose at the top of the Guest 2021 entry's range. Tracend's reading: a small surplus with slow, steady weight gain is the guide, the plan's rules set the numbers, and none of the supplements is needed to make progress.`,
      },
    ],
  },
  {
    slug: "slater_2019_energy_surplus",
    label: "Slater et al. 2019",
    title:
      "Is an Energy Surplus Required to Maximize Skeletal Muscle Hypertrophy Associated With Resistance Training",
    authors: ["Slater GJ", "Dieter BP", "Marsh DJ", "Helms ER", "Shaw G", "Iraki J"],
    year: 2019,
    doi: "10.3389/fnut.2019.00131",
    url: "https://doi.org/10.3389/fnut.2019.00131",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "energy-surplus", "bulking", "hypertrophy", "energy-balance"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "Explains why nobody can say exactly how many extra calories muscle gain needs, so Coach can set expectations about bulking honestly. Summarised from the full text.",
    sections: [
      {
        title: "What the review asked",
        body:
          `The authors examined whether eating more than you burn is needed to build muscle with lifting, how big any surplus should be, where the extra energy should come from and when to eat it. They found no well-controlled long-term trials that set out to test a surplus directly in lifters, so they drew on overfeeding studies, short trials and physiology.`,
      },
      {
        title: "Main points",
        body:
          `A surplus does push the body towards gaining lean mass, even without training, but overfeeding alone mostly adds fat: in one classic study, men gained about 2 kg of fat for each kg of lean mass. Textbook figures for the cost of building a kilogram of muscle ignore the energy used to make new protein and the body's own adjustments to overeating (more fidgeting, more heat from digestion), and people vary widely, so no single figure is supported. Muscle can also grow in a deficit, most clearly in untrained people or those with more body fat. As long as minimum intakes of protein (the review cites 1.6 to 2.2 g per kg a day for lifters), carbohydrate and fat are met, the source of the extra energy seems not to matter much. Drinks and more frequent snacks can help people who struggle to eat more.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The authors advise starting with a modest surplus of about 1,500 to 2,000 kJ a day (roughly 360 to 480 kcal) and adjusting from changes in body composition and strength. This is reasoned advice, not a tested prescription, and the review predates the Helms 2023 trial in this library, which found larger surpluses mostly added fat in trained lifters. Tracend's reading: a small surplus checked against weekly trends is the guide, and newer lifters can usually grow on less extra food than they expect.`,
      },
    ],
  },
  {
    slug: "helms_2023_energy_surplus",
    label: "Helms et al. 2023",
    title:
      "Effect of Small and Large Energy Surpluses on Strength, Muscle, and Skinfold Thickness in Resistance-Trained Individuals: A Parallel Groups Design",
    authors: ["Helms ER", "Spence AJ", "Sousa C", "Kreiger J", "Taylor S", "Oranchuk DJ"],
    year: 2023,
    doi: "10.1186/s40798-023-00651-y",
    url: "https://doi.org/10.1186/s40798-023-00651-y",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: [
      "nutrition",
      "energy-surplus",
      "bulking",
      "hypertrophy",
      "strength",
      "body-composition",
    ],
    evidenceLevel: "randomised trial (17 resistance-trained adults completed)",
    kind: "paper",
    chosenBecause:
      "One of very few trials comparing surplus sizes in trained lifters, the people most likely to ask how hard to bulk. Summarised from the full text.",
    sections: [
      {
        title: "What the trial did",
        body:
          `Twenty-one resistance-trained lifters with at least a year of experience were assigned to eat at maintenance, about 5 percent above it, or about 15 percent above it for 8 weeks while doing the same supervised full-body programme three times a week. Protein was at least 1.8 g per kg a day for everyone. COVID-19 disruption left 17 completers (2 of them women), so the authors also analysed how weight change related to each outcome across all participants.`,
      },
      {
        title: "Findings",
        body:
          `Thigh and triceps muscle thickness and squat strength changed similarly in all groups. The 15 percent group gained more bench press strength in the group comparison, but bench gains were not linked to how much weight people gained. The clearest result was that weight gain strongly predicted gains in skinfold thickness (a measure of fat). Only the biceps, the most heavily trained muscle in the programme, showed a weak link between more weight gain and more growth. The 5 and 15 percent groups ended up eating similar surpluses in practice, which suggests a very small surplus is hard to hold.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The authors recommend conservative surpluses of about 5 to 20 percent above maintenance, or gaining about 0.25 to 0.5 percent of body weight a week, smaller and slower for more experienced lifters. The sample was small, mostly male and mixed in experience, the programme was moderate in volume, and it lasted only 8 weeks. Tracend's reading: faster gain mainly adds fat, so a small surplus is the default, while someone who cares more about size than leanness may choose faster gain knowingly.`,
      },
    ],
  },
  {
    slug: "murphy_2022_energy_deficiency_lean_mass",
    label: "Murphy and Koehler 2022",
    title:
      "Energy deficiency impairs resistance training gains in lean mass but not strength: A meta-analysis and meta-regression",
    authors: ["Murphy C", "Koehler K"],
    year: 2022,
    doi: "10.1111/sms.14075",
    url: "https://doi.org/10.1111/sms.14075",
    licence: "CC-BY-NC-ND-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "energy-balance", "fat-loss", "recomposition", "hypertrophy", "strength"],
    evidenceLevel: "systematic review, meta-analysis and meta-regression of randomised trials",
    kind: "paper",
    chosenBecause:
      "Answers whether someone can keep building muscle and strength while dieting, and how big a deficit starts to cost muscle. Summarised from the abstract only.",
    sections: [
      {
        title: "What the review did",
        body:
          `The authors searched for randomised trials in which people did resistance training while eating less than they burned for at least 3 weeks. In one analysis they pooled trials that had a comparison group training without a deficit. In a second they matched deficit trials without such a group to similar trials of training without a deficit. They then combined both sets to look at how the size of the deficit related to lean mass change.`,
      },
      {
        title: "Findings",
        body:
          `Training in a deficit gave smaller lean mass gains than training without one (effect size about minus 0.57 in the main analysis), while strength gains were similar (about minus 0.31, not significant). The matched comparison agreed: lean mass fell slightly in the deficit trials and rose in the trials without a deficit, but strength rose about equally in both. In the combined analysis, a deficit of roughly 500 kcal a day was enough to prevent lean mass gains. The authors advise people training to build muscle to avoid long deficits, and people training to keep muscle while losing weight to avoid deficits larger than 500 kcal a day.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This explains a common experience: strength can keep rising during a diet even when muscle size stalls. The 500 kcal figure is an average from a regression across mixed studies, not a hard line for every person, and this summary is written from the abstract only, so participant details and study count are not given here. It fits the digest's advice to lose about 0.5 to 1 percent of body weight a week and the Garthe 2011 entry. Tracend's reading: moderate deficits, with lifting and protein kept up, are the guide.`,
      },
    ],
  },
  {
    slug: "garthe_2011_weight_loss_rate",
    label: "Garthe et al. 2011",
    title:
      "Effect of Two Different Weight-Loss Rates on Body Composition and Strength and Power-Related Performance in Elite Athletes",
    authors: ["Garthe I", "Raastad T", "Refsnes PE", "Koivisto A", "Sundgot-Borgen J"],
    year: 2011,
    doi: "10.1123/ijsnem.21.2.97",
    url: "https://doi.org/10.1123/ijsnem.21.2.97",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "fat-loss", "energy-balance", "body-composition", "strength"],
    evidenceLevel: "randomised controlled trial (24 elite athletes)",
    kind: "paper",
    chosenBecause:
      "The trial behind the advice to lose weight slowly to keep muscle, for anyone asking how fast to cut. Summarised from the abstract only.",
    sections: [
      {
        title: "What the trial did",
        body:
          `Twenty-four elite athletes who needed to lose weight were randomly assigned to a slow target of about 0.7 percent of body weight a week (13 athletes) or a fast target of about 1.4 percent a week (11 athletes). Both groups followed energy-restricted diets and kept four resistance training sessions a week within their usual training. They were measured with DEXA scans, one-repetition maximum tests, a 40 metre sprint and a jump test.`,
      },
      {
        title: "Findings",
        body:
          `The slow group dieted for about 8.5 weeks and the fast group for about 5.3. Energy intake was cut by about 19 percent and 30 percent. Both groups lost about 5.5 percent of body weight; in practice the weekly losses were about 0.7 and 1.0 percent. Fat mass fell by about 31 percent in the slow group and 21 percent in the fast group. Lean mass rose by about 2.1 percent in the slow group and did not change in the fast group, a significant difference. The authors concluded that athletes who want to gain lean mass and strength while losing weight should aim for about 0.7 percent of body weight a week.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `This supports the digest's guide of about 0.5 to 1 percent of body weight a week, with slower loss for leaner people. The groups were small, the athletes were elite and lifting regularly, and the slow group also dieted for longer. This summary is from the abstract only, so details such as the split of men and women are not given here. Tracend's reading: a slower cut is the safer default when keeping muscle and strength matters, and the plan's rules set the target.`,
      },
    ],
  },
  {
    slug: "barakat_2020_recomposition",
    label: "Barakat et al. 2020",
    title:
      "Body Recomposition: Can Trained Individuals Build Muscle and Lose Fat at the Same Time?",
    authors: ["Barakat C", "Pearson J", "Escalante G", "Campbell B", "De Souza EO"],
    year: 2020,
    doi: "10.1519/SSC.0000000000000584",
    url: "https://doi.org/10.1519/SSC.0000000000000584",
    licence: "CC-BY-NC-ND-4.0",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "recomposition", "body-composition", "protein", "sleep", "training"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "Answers whether someone who already trains can gain muscle and lose fat at the same time, the goal many lifters state. Summarised from the full text.",
    sections: [
      {
        title: "What the review found",
        body:
          `The authors gathered randomised trials in resistance-trained people in which fat-free mass rose while fat mass fell over 4 to 10 weeks. This happened in powerlifters, recreational lifters, team-sport athletes and aspiring physique athletes, on a range of programmes. In several trials, high protein intakes (above 2 g per kg a day) went with more fat loss alongside muscle gain, even when the extra protein added calories. Starting with more body fat, returning after a break, and being newer to training made recomposition larger. Case studies of natural bodybuilders preparing for a contest mostly did not show it, probably because of the very large and long energy deficit.`,
      },
      {
        title: "Sleep and measurement",
        body:
          `Short sleep is linked with losing more lean mass during weight loss and with worse training, and one small trial in untrained people found that sleep coaching helped fat loss. The review warns that body composition methods have errors of a size similar to many of the reported changes (DEXA has a typical error of about 1.6 percent body fat against MRI), so small recomposition results should be read with caution.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The authors suggest progressive lifting at least three times a week, high protein (2.6 to 3.5 g per kg of fat-free mass a day), protein supplements if useful and good sleep. That protein range is per kg of fat-free mass and is above the digest's 1.4 to 2.0 g per kg of body weight; it rests on a few small trials. Tracend's reading: recomposition is realistic for trained people near maintenance, slower for lean, experienced lifters, and best judged by strength and measurements over months, not week-to-week scale changes.`,
      },
    ],
  },
  {
    slug: "pinckaers_2021_plant_protein",
    label: "Pinckaers et al. 2021",
    title: "The Anabolic Response to Plant-Based Protein Ingestion",
    authors: ["Pinckaers PJM", "Trommelen J", "Snijders T", "van Loon LJC"],
    year: 2021,
    doi: "10.1007/s40279-021-01540-8",
    url: "https://doi.org/10.1007/s40279-021-01540-8",
    licence: "CC-BY-4.0",
    verbatimAllowed: true,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "protein", "plant-protein", "vegetarian", "hypertrophy"],
    evidenceLevel: "narrative review",
    kind: "paper",
    chosenBecause:
      "Explains how plant proteins differ from animal proteins for muscle and how vegetarian and vegan lifters can make up the gap. Summarised from the full text.",
    sections: [
      {
        title: "Why plant protein can be weaker",
        body:
          `Whole plant foods are digested less completely than animal foods: about 50 to 75 percent of the protein in chickpeas, mung beans and peas is absorbed, against about 85 to 95 percent for eggs and chicken, largely because of fibre and other compounds in the food. Isolated plant proteins (powders) absorb about as well as animal proteins. Most plant proteins also have less of the essential amino acids, especially leucine, and are often short of lysine or methionine. In the few direct comparisons, soy or wheat protein usually raised muscle protein building less than the same amount of whey or milk protein, though not in every study.`,
      },
      {
        title: "How to close the gap",
        body:
          `Plant proteins vary widely: potato, corn, pea, canola and brown rice protein are relatively rich in essential amino acids or leucine. Three ways to compensate are eating more of the plant protein (for example, about 38 g of pea or 40 g of soy protein supplies the 2.7 g of leucine in about 25 g of whey), blending sources whose gaps cancel out (such as rice with pea or soy), and adding the missing amino acid. Training studies already show that supplementing soy, pea, rice or potato protein supports muscle gain.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `Most people who train eat enough protein that small quality differences matter little; the authors see the greater risk when energy and protein intake are low, as in a diet. Much of the evidence is short laboratory work with single proteins, not whole meals. Tracend's reading: a plant-based lifter does fine with a slightly higher protein target, varied sources and, if useful, a pea or soy powder, especially when cutting. Two authors have received funding from food companies, and the paper appeared in an industry-supported journal supplement.`,
      },
    ],
  },
  {
    slug: "hevia_larrain_2021_vegan_protein",
    label: "Hevia-Larraín et al. 2021",
    title:
      "High-Protein Plant-Based Diet Versus a Protein-Matched Omnivorous Diet to Support Resistance Training Adaptations: A Comparison Between Habitual Vegans and Omnivores",
    authors: ["Hevia-Larraín V", "Gualano B", "Longobardi I", "Gil S", "Fernandes AL", "Costa LAR"],
    year: 2021,
    doi: "10.1007/s40279-021-01434-9",
    url: "https://doi.org/10.1007/s40279-021-01434-9",
    licence: "proprietary",
    verbatimAllowed: false,
    lastReviewed: "2026-10-18",
    region: ["global"],
    topics: ["nutrition", "protein", "plant-protein", "vegetarian", "hypertrophy", "strength"],
    evidenceLevel:
      "non-randomised controlled trial (38 untrained young men, 19 vegan, 19 omnivore)",
    kind: "paper",
    chosenBecause:
      "The best direct test of whether a vegan diet holds back muscle and strength gains when protein is matched, a frequent worry for plant-based lifters. Summarised from the abstract only.",
    sections: [
      {
        title: "What the study did",
        body:
          `Nineteen young men who were habitual vegans and 19 who were omnivores, all healthy and of similar size, did 12 weeks of supervised resistance training twice a week. Each man's protein intake was brought up to about 1.6 g per kg a day with a supplement: soy protein for the vegans, whey for the omnivores. Diets were checked every four weeks. Leg lean mass, thigh muscle and muscle fibre size, and leg press strength were measured before and after.`,
      },
      {
        title: "Findings",
        body:
          `Both groups improved on every measure: leg lean mass rose by about 1.2 kg in each group, thigh muscle cross-sectional area and fibre size grew, and leg press strength rose by about 97 kg in the vegans and 117 kg in the omnivores. None of the differences between the groups were statistically significant. The authors concluded that, with enough protein, the source (plant foods plus soy, or mixed foods plus whey) did not change muscle or strength gains in untrained young men.`,
      },
      {
        title: "Practical reading and limits",
        body:
          `The men were untrained, so they would gain readily on almost any sensible plan, and they ate a fairly high protein intake that included a soy isolate. The groups were not randomised (they were defined by existing diet), the study was small, and no women took part. This summary is from the abstract only. It agrees with the Pinckaers 2021 entry that enough total protein covers most of the difference. Tracend's reading: a vegan lifter who reaches the plan's protein target can expect similar progress; the plan's rules set the number.`,
      },
    ],
  },
];
