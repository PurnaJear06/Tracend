import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  namedShownPhrases,
  namedShownSources,
  studyMentions,
  unshownStudies,
  unshownStudyPhrases,
} from "./mentions.ts";

const shown = {
  maughan_2018_ioc_supplements: {
    label: "IOC consensus statement: dietary supplements and the high-performance athlete (2018)",
    text: "[source: maughan_2018_ioc_supplements] Creatine is the best studied.",
  },
  jager_2017_protein: {
    label: "International Society of Sports Nutrition position stand: protein and exercise (2017)",
    text: "[source: jager_2017_protein] Kerksick and colleagues note 1.4 to 2.0 g per kg.",
  },
  nih_ods_creatine_2022: {
    label: "Creatine: fact sheet for health professionals (2022)",
    text: "[source: nih_ods_creatine_2022] Creatine is made in the body.",
  },
};

Deno.test("studies are found by author and year, or by an institution's document, not from a list", () => {
  assertEquals(studyMentions("Maughan 2018 says so."), [{ authors: ["maughan"], year: 2018 }]);
  assertEquals(studyMentions("Schoenfeld et al. (2017) found more."), [
    { authors: ["schoenfeld"], year: 2017 },
  ]);
  assertEquals(studyMentions("Burke & Maughan, 2018 agree."), [
    { authors: ["burke", "maughan"], year: 2018 },
  ]);
  assertEquals(studyMentions("Jäger et al. 2017"), [{ authors: ["jager"], year: 2017 }]);
  assertEquals(studyMentions("the NIH fact sheet and ACSM position stand"), [
    { authors: ["nih"], year: null, initials: true },
    { authors: ["acsm"], year: null, initials: true },
  ]);
});

Deno.test("dates, seasons and training initials are not studies", () => {
  assertEquals(studyMentions("Since 2018 you trained. In March 2026 you began."), []);
  assertEquals(studyMentions("Spring 2026 and Oct 2026 and Week 2027"), []);
  assertEquals(studyMentions("The BMI guidelines and HIIT recommendations"), []);
});

Deno.test("a study named in the text matches the shown source by id, title, initials or excerpt", () => {
  assertEquals(namedShownSources("Maughan 2018 says creatine works.", shown), [
    "maughan_2018_ioc_supplements",
  ]);
  assertEquals(namedShownSources("The IOC consensus statement says so.", shown), [
    "maughan_2018_ioc_supplements",
  ]);
  assertEquals(namedShownSources("The ISSN position stand puts it at 1.4 to 2.0 g.", shown), [
    "jager_2017_protein",
  ]);
  assertEquals(namedShownSources("Jäger et al. 2017 agree.", shown), ["jager_2017_protein"]);
  assertEquals(namedShownSources("Kerksick 2017 notes a range.", shown), ["jager_2017_protein"]);
  assertEquals(namedShownSources("The NIH fact sheet says it is made in the body.", shown), [
    "nih_ods_creatine_2022",
  ]);
  assertEquals(namedShownSources("Nothing is named here.", shown), []);
});

Deno.test("a study that no shown source matches is unshown, and a wrong year does not match", () => {
  assertEquals(unshownStudies("Kreider 2017 found it helps.", shown), [
    { authors: ["kreider"], year: 2017 },
  ]);
  assertEquals(unshownStudies("Maughan 2021 found it helps.", shown), [
    { authors: ["maughan"], year: 2021 },
  ]);
  assertEquals(unshownStudies("The WHO guidelines say so.", shown), [
    { authors: ["who"], year: null, initials: true },
  ]);
  assertEquals(unshownStudies("Maughan 2018 says so.", shown), []);
  assertEquals(unshownStudies("Maughan 2018 says so.", {}), [
    { authors: ["maughan"], year: 2018 },
  ]);
});

Deno.test("an institution's initials never match a word in an excerpt", () => {
  const athletes = {
    maughan_2018_ioc_supplements: {
      label: "Dietary supplements and the high-performance athlete (2018)",
      text: "Athletes who train hard.",
    },
  };
  assertEquals(namedShownSources("The WHO guidelines say", athletes), []);
  assertEquals(
    namedShownSources(
      "The WHO guidelines say",
      {
        maughan_2018_ioc_supplements: { text: "Athletes who train hard." },
      } as unknown as typeof athletes,
    ),
    [],
  );
  assertEquals(unshownStudies("The WHO guidelines say", athletes), [
    { authors: ["who"], year: null, initials: true },
  ]);
  // The initials still match an id, a title's acronym or an all-capitals word in the title.
  assertEquals(
    namedShownSources("The IOC consensus statement", {
      maughan_2018_ioc_supplements: { label: "IOC consensus statement (2018)", text: "" },
    }),
    ["maughan_2018_ioc_supplements"],
  );
  assertEquals(namedShownSources("The who guidelines", athletes), []);
});

Deno.test("calorie and plan numbers are not years, so they name no study", () => {
  for (
    const text of [
      "BMR 1980 kcal and TDEE (2010 kcal).",
      "Eat 2000 kcal a day. Target 1990 kcal.",
      "Roughly 2005 calories, aim 1995 kcal, maintenance 2015 kcal, deficit 1985 kcal.",
      "Walk 2000 steps, 1999 g of rice, 2020 kg is not a weight.",
      "Your plan has a surplus of 2010 kcal.",
    ]
  ) assertEquals(unshownStudies(text, {}), [], text);
  // A year must end at a word boundary, and a real citation still counts.
  assertEquals(studyMentions("BMR 19800 is not a year."), []);
  assertEquals(unshownStudies("Smith 2019 found more.", {}), [{ authors: ["smith"], year: 2019 }]);
  assertEquals(unshownStudyPhrases("Smith 2019 found more.", {}).map((entry) => entry.phrase), [
    "Smith 2019",
  ]);
});

Deno.test("an author named without a year, with et al., names a study", () => {
  assertEquals(studyMentions("Grgic et al. found more strength."), [
    { authors: ["grgic"], year: null },
  ]);
  assertEquals(studyMentions("Schoenfeld et al. (2017) found more."), [
    { authors: ["schoenfeld"], year: 2017 },
  ]);
  const grgic = {
    grgic_2018_frequency_strength: {
      label: "Frequency and strength (2018)",
      text: "[source: grgic_2018_frequency_strength] Source: Grgic et al. 2018, frequency.",
    },
  };
  assertEquals(namedShownSources("Grgic et al. found more.", grgic), [
    "grgic_2018_frequency_strength",
  ]);
  assertEquals(unshownStudies("Smith et al. found more.", grgic).length, 1);
});

Deno.test("a shown source is named the way its own excerpt names it", () => {
  const sources = {
    acsm_2026_resistance_prescription: {
      label: "Resistance training prescription (2026)",
      text:
        "[source: acsm_2026_resistance_prescription] Source: Currier et al. 2026, Resistance training prescription.",
    },
  };
  assertEquals(
    namedShownPhrases("Currier et al. 2026 suggest this.", sources),
    [{ id: "acsm_2026_resistance_prescription", phrase: "Currier et al. 2026" }],
  );
  assertEquals(unshownStudies("Currier et al. 2026 suggest this.", sources), []);
});
