-- Regional modules (coaching platform program, chunk E4, decision D5) ----------------------

-- Two parts, both additive.
--
-- 1. The athlete's country. `user_accounts.country_code` is optional (null until the athlete
--    chooses one in Account). The library search showed regional sources by guessing: the country
--    in the account locale (which the app never sets, so it stays 'en') and IN for an Indian time
--    zone. A stored country now decides, and an account with none behaves exactly as before.
--      * 'ZZ' is the athlete's choice "another country": ISO 3166 reserves it for user
--        assignment, no source carries it, so the athlete sees global sources only. It is kept
--        apart from null on purpose: an athlete who answered must not be guessed back into a
--        region from the time zone.
--      * The app reads and writes the country only through get_my_country_v1 and
--        set_my_country_v1 (schema_version 1.1). The column is not writable by clients directly,
--        like `timezone`. Both answers carry `effective_regions`: the regions the library search
--        will use for the athlete right now (always 'global', plus the stored country or, with none,
--        the guess from locale and time zone). The app shows it so that "Not set" is never described
--        as global-only on an account whose time zone still selects India.
--      * set_my_country_v1 accepts only the countries the app offers (AU, IN, GB, US) and ZZ; a
--        new region adds its code here in a later migration, with its sources.
--      * The row is exported by privacy-export (select *) and removed with the account.
--    private.library_regions_for_account (the one function search_library_v2 and v3 call) is
--    redefined with the same signature and grants.
--
-- 2. Eight regional and body-measure sources for the UK, the United States, Australia and one
--    global WHO report, loaded by the existing private.library_replace_source. They load without
--    embeddings; the library-embed worker fills them after the deploy.

alter table public.user_accounts
  add column country_code text check (country_code ~ '^[A-Z]{2}$');

comment on column public.user_accounts.country_code is
  'Optional ISO 3166-1 alpha-2 country the athlete chose in Account; ZZ means another country. '
  'Picks the regional research-library sources. Null falls back to the locale and time zone.';

-- The answer both functions give: the stored country and the regions in effect (sorted).
create function private.my_country_answer(target_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'schema_version', '1.1',
    'country_code', (select a.country_code from public.user_accounts a where a.id = target_user_id),
    'effective_regions', (
      select to_jsonb(array_agg(r order by r collate "C"))
      from unnest(private.library_regions_for_account(target_user_id)) r
    )
  )
$$;
revoke all on function private.my_country_answer(uuid)
  from public, anon, authenticated, service_role;

create function public.get_my_country_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  return private.my_country_answer(auth.uid());
end $$;
revoke all on function public.get_my_country_v1() from public, anon;
grant execute on function public.get_my_country_v1() to authenticated;

-- A null or blank code clears the choice. Otherwise the code must be one the app offers (AU, IN,
-- GB, US, or ZZ for another country); it is stored upper-case, so "in" and "IN" are the same.
create function public.set_my_country_v1(p_country_code text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  code text := nullif(upper(btrim(p_country_code)), '');
  previous text;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if code is not null and code <> all (array['AU', 'IN', 'GB', 'US', 'ZZ']) then
    raise exception 'unknown country' using errcode = '22023';
  end if;
  select a.country_code into previous from public.user_accounts a
    where a.id = auth.uid() and a.account_status = 'active' for update;
  if not found then
    raise exception 'active account required' using errcode = '42501';
  end if;
  -- The country is restricted account data: an actual change leaves an audit event (old and new
  -- code); setting the value already stored, or clearing an unset country, leaves none.
  if previous is distinct from code then
    update public.user_accounts set country_code = code where id = auth.uid();
    insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
    values (auth.uid(), 'account.country.changed', 'user_account', auth.uid(), 'succeeded',
      jsonb_build_object('schema_version', '1.0', 'from', previous, 'to', code));
  end if;
  return private.my_country_answer(auth.uid());
end $$;
revoke all on function public.set_my_country_v1(text) from public, anon;
grant execute on function public.set_my_country_v1(text) to authenticated;

-- The regions an athlete's account maps to: always 'global'. With a stored country, that country
-- (the athlete's answer decides, so a Spanish time zone or an en-IN locale cannot add another).
-- Without one, the country in the locale ('en-IN', 'en_GB') and 'IN' for an Indian time zone, as
-- before. A missing account is just 'global'.
create or replace function private.library_regions_for_account(target_user_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select array(
        select distinct r.region
        from unnest(
          case when a.country_code is not null then array['global', a.country_code]
          else array[
            'global',
            upper(substring(a.locale from '[-_]([A-Za-z]{2})$')),
            case when a.timezone in ('Asia/Kolkata', 'Asia/Calcutta') then 'IN' end
          ] end
        ) as r(region)
        where r.region is not null
      )
      from public.user_accounts a
      where a.id = target_user_id
    ),
    array['global']
  )
$$;
revoke all on function private.library_regions_for_account(uuid)
  from public, anon, authenticated, service_role;

-- Content ----------------------------------------------------------------------------------
-- Generated by supabase/functions/_shared/library/build_migration.ts from supabase/library.

-- library-source: nhs_2026_overweight_obesity_adults sha256:f7c1e7bcbf1354fe291e96706528b72065f5eefb9c371f9306d5ab70d3f56612
select private.library_replace_source(
$lib${"slug":"nhs_2026_overweight_obesity_adults","title":"Overweight and obesity in adults","authors":["NHS"],"year":2026,"doi":null,"url":"https://www.nhs.uk/conditions/obesity/","licence":"proprietary","region":["GB"],"topics":["bmi","waist","body-composition","fat-loss","guidelines","united-kingdom","ethnicity"],"evidence_level":"national health service patient guidance","kind":"guideline"}$lib$::jsonb,
$lib$[{"ordinal":0,"section":"BMI points","header":"Source: NHS 2026 (Overweight and obesity in adults), Overweight and obesity in adults. Section: BMI points.","body":"Two scales are given for adults. The general one calls a BMI of 25 up to 30 overweight and 30 or higher obese. A lower scale is offered to adults whose family background is South Asian, Chinese, other Asian, Middle Eastern, Black African or African-Caribbean, because the page says health risk starts to rise at a somewhat lower BMI for them: overweight begins at 23 (running to 27.4) and obese at 27.5.\n\nThe page also warns that its BMI tool does not separate muscle from fat, so a very muscular person can be put in a higher band without carrying much fat.","token_count":167},{"ordinal":1,"section":"Waist and when to see a GP","header":"Source: NHS 2026 (Overweight and obesity in adults), Overweight and obesity in adults. Section: Waist and when to see a GP.","body":"For a BMI under 35 the page uses waist-to-height ratio as a check on fat around the middle, and the aim it gives is a waist smaller than half of height. A video on the page shows how to take the measurement.\n\nIt lists reasons to talk to a GP for someone in the overweight or obese range: wanting help to lose weight, a waist over half of height, an existing condition such as pre-diabetes, diabetes, high blood pressure, high cholesterol, joint pain, sleep apnoea or cardiovascular disease, a family history of obesity, or a suspected eating disorder.","token_count":169},{"ordinal":2,"section":"Losing weight","header":"Source: NHS 2026 (Overweight and obesity in adults), Overweight and obesity in adults. Section: Losing weight.","body":"The weight-loss advice is to take in fewer calories than the body burns while moving more. The page suggests losing about 0.5 to 1 kg a week, being active for 45 to 60 minutes daily (in shorter blocks if easier), drinking less alcohol because it adds calories, and choosing realistic goals. It puts typical daily energy use at about 2,000 calories for women and 2,500 for men, and says that even a 5 to 10 percent drop in body weight can benefit health.","token_count":141},{"ordinal":3,"section":"Practical reading and limits","header":"Source: NHS 2026 (Overweight and obesity in adults), Overweight and obesity in adults. Section: Practical reading and limits.","body":"These are group-level points for reading BMI, not a diagnosis, and Coach never calls an athlete overweight or obese. For a lifter the muscle warning is the key one: a high BMI alongside a small waist-to-height ratio is not evidence of excess fat, and the waist-to-height check is not meant for a BMI of 35 or above. The weekly loss and daily activity figures are for the general public; the library's fat-loss sources and the plan's rules set the pace for someone who trains. This page is patient guidance, not the NICE guideline behind it.","token_count":167}]$lib$::jsonb
);

-- library-source: phe_2018_quick_guide_healthy_eating sha256:f233bf23fe21648f624734590f6e07474707c6bdd525c83b52fab779c4cb9915
select private.library_replace_source(
$lib${"slug":"phe_2018_quick_guide_healthy_eating","title":"A Quick Guide to the Government's Healthy Eating Recommendations","authors":["Public Health England"],"year":2018,"doi":null,"url":"https://assets.publishing.service.gov.uk/media/5ba8a087e5274a55c3407c38/A_quick_guide_to_govt_healthy_eating_update.pdf","licence":"OGL-UK-3.0","region":["GB"],"topics":["nutrition","guidelines","energy-balance","hydration","supplements","united-kingdom"],"evidence_level":"national dietary guideline summary (Eatwell Guide)","kind":"guideline"}$lib$::jsonb,
$lib$[{"ordinal":0,"section":"The five food groups","header":"Source: PHE 2018 (Quick Guide to healthy eating), A Quick Guide to the Government's Healthy Eating Recommendations. Section: The five food groups.","body":"The Eatwell Guide is a picture of how a typical day or week of eating should be divided among food groups, rather than a rule for each meal. More than a third should be fruit and vegetables, at least five 80 g portions daily. Starchy foods such as potatoes, bread, rice and pasta form the base of meals, wholegrain where possible. Dairy or dairy alternatives have a place, in lower-fat and lower-sugar forms, and a plant drink should be unsweetened and fortified with calcium.","token_count":156},{"ordinal":1,"section":"Proteins, fats and fluid","header":"Source: PHE 2018 (Quick Guide to healthy eating), A Quick Guide to the Government's Healthy Eating Recommendations. Section: Proteins, fats and fluid.","body":"The protein group covers beans, pulses, fish, eggs, meat and similar foods. The guide asks for fish twice a week at 140 g a portion, with one of the two oily, and puts a ceiling of about 70 g a day on red and processed meat. Pulses are presented as a fibre-rich, low-fat swap for meat. Oils and spreads should be unsaturated and used sparingly, and fatty, salty or sugary foods kept occasional and small.\n\nFor drinks it points to roughly six to eight glasses of fluid daily, which can include water, lower-fat milk and sugar-free drinks such as tea and coffee, while fruit juice and smoothies together should stay at or under 150 ml a day.","token_count":198},{"ordinal":2,"section":"Energy and vitamin D","header":"Source: PHE 2018 (Quick Guide to healthy eating), A Quick Guide to the Government's Healthy Eating Recommendations. Section: Energy and vitamin D.","body":"It gives the average daily energy need as 2,500 kcal for men and 2,000 for women, and notes that individual need varies with things like activity. For a 2,000 kcal day, the usual split is about 400 kcal at breakfast, 600 at lunch, 600 at the evening meal and 400 from snacks and drinks.\n\nOn supplements, the advice is that everyone from age five should consider 10 micrograms of vitamin D a day through the autumn and winter months (October to March). People with little sun exposure, including people with dark skin of African, African-Caribbean or South Asian origin, should consider it all year. Women trying for a pregnancy are advised to take folic acid.","token_count":202},{"ordinal":3,"section":"Practical reading and limits","header":"Source: PHE 2018 (Quick Guide to healthy eating), A Quick Guide to the Government's Healthy Eating Recommendations. Section: Practical reading and limits.","body":"This is general population advice. The 2,500 and 2,000 kcal figures are averages; a heavy trainer needs more, and the plan's rules set the athlete's calories and protein. The guide gives no protein target in grams; the Government Dietary Recommendations entry has one. Coach states the vitamin D advice as the official UK advice and never pushes a supplement. The document is Crown copyright under the Open Government Licence v3.0, so short quotation with attribution is allowed; the Eatwell Guide image is not summarised.","token_count":170}]$lib$::jsonb
);

-- library-source: phe_2016_government_dietary_recommendations sha256:14e9a63ef8abd45b78a7666ca6c474d3af43a0c7221730b91c1848dcdf393b81
select private.library_replace_source(
$lib${"slug":"phe_2016_government_dietary_recommendations","title":"Government Dietary Recommendations: government recommendations for energy and nutrients for males and females aged 1 to 18 years and 19+ years","authors":["Public Health England"],"year":2016,"doi":null,"url":"https://assets.publishing.service.gov.uk/media/5a749fece5274a44083b82d8/government_dietary_recommendations.pdf","licence":"OGL-UK-3.0","region":["GB"],"topics":["nutrition","protein","energy-balance","guidelines","united-kingdom"],"evidence_level":"national dietary reference values","kind":"guideline"}$lib$::jsonb,
$lib$[{"ordinal":0,"section":"Adult figures","header":"Source: PHE 2016 (Government Dietary Recommendations), Government Dietary Recommendations: government recommendations for energy and nutrients for males and females aged 1 to 18 years and 19+ years. Section: Adult figures.","body":"The tables set daily targets for adults aged 19 to 64, men first and women second. Energy: 2,500 and 2,000 kcal. Protein: 55.5 and 45 g. Fat: less than 97 and 78 g, of which saturated fat less than 31 and 24 g. Carbohydrate: at least 333 and 267 g. Free sugars: less than 33 and 27 g. Salt: under 6 g for both. Fibre: 30 g for both.\n\nBeyond age 65 energy and protein figures are a little lower; men aged 65 and over have 53.3 g of protein and women 46.5 g.","token_count":170},{"ordinal":1,"section":"Where the numbers come from","header":"Source: PHE 2016 (Government Dietary Recommendations), Government Dietary Recommendations: government recommendations for energy and nutrients for males and females aged 1 to 18 years and 19+ years. Section: Where the numbers come from.","body":"The figures restate older expert advice from COMA and the Scientific Advisory Committee on Nutrition. Adult energy is capped at 2,500 and 2,000 kcal on purpose, to help tackle overweight and obesity, and the document says these are general-population figures and that real needs differ. Carbohydrate is taken as half of energy and free sugars as 5 percent of energy, both from SACN's 2015 carbohydrate report, which also supplies the fibre figure. Salt targets are described as goals that populations can realistically reach, not ideals. Protein comes from the 1991 UK dietary reference values.","token_count":208},{"ordinal":2,"section":"Practical reading and limits","header":"Source: PHE 2016 (Government Dietary Recommendations), Government Dietary Recommendations: government recommendations for energy and nutrients for males and females aged 1 to 18 years and 19+ years. Section: Practical reading and limits.","body":"These are population recommendations for people with no medical condition (the document tells anyone with a condition to see a GP or dietitian), and they are not targets for a lifter. Its protein figure is a minimum for health; the sports-nutrition range in the Jäger 2017 entry and the plan's rules are higher and are what Coach uses for the athlete's own number. The energy figures are deliberately capped and do not describe a heavy training load. Free sugars, salt and fibre are fine to cite as the UK recommendation. The document is under the Open Government Licence v3.0, so a short quotation with attribution is allowed.","token_count":217}]$lib$::jsonb
);

-- library-source: nhlbi_2000_practical_guide_obesity sha256:ff89e904e295ded24e07ca004af6c779d5d8a71098f9993418e962ae838648ca
select private.library_replace_source(
$lib${"slug":"nhlbi_2000_practical_guide_obesity","title":"The Practical Guide: Identification, Evaluation, and Treatment of Overweight and Obesity in Adults","authors":["NHLBI Obesity Education Initiative Expert Panel","North American Association for the Study of Obesity"],"year":2000,"doi":null,"url":"https://www.nhlbi.nih.gov/files/docs/guidelines/prctgd_c.pdf","licence":"proprietary","region":["US"],"topics":["bmi","waist","body-composition","fat-loss","guidelines","united-states","ethnicity"],"evidence_level":"federal clinical guideline (expert panel, 1998; practical guide 2000)","kind":"guideline"}$lib$::jsonb,
$lib$[{"ordinal":0,"section":"BMI classes and waist lines","header":"Source: NHLBI and NAASO 2000 (Practical Guide), The Practical Guide: Identification, Evaluation, and Treatment of Overweight and Obesity in Adults. Section: BMI classes and waist lines.","body":"The guide treats BMI as the main yardstick for adults. Under 18.5 is underweight and 18.5 to 24.9 normal. From 25 to 29.9 is overweight, and obesity runs in three classes: 30 to 34.9, 35 to 39.9 and 40 or more. It stresses that these bands describe average risk in groups; the amount of disease that goes with a given BMI differs between individuals and between populations.\n\nWaist size adds information for adults with a BMI from 25 to 34.9. Beyond 102 cm (40 inches) for a man or 88 cm (35 inches) for a woman, the odds of type 2 diabetes, abnormal blood fats, high blood pressure and cardiovascular disease climb, and the guide says to place that person one risk step above where BMI alone would. From a BMI of 35 the waist figure is no longer worth taking, since it adds almost no predictive value.","token_count":247},{"ordinal":1,"section":"Taking the measurement","header":"Source: NHLBI and NAASO 2000 (Practical Guide), The Practical Guide: Identification, Evaluation, and Treatment of Overweight and Obesity in Adults. Section: Taking the measurement.","body":"For the waist, the guide describes passing a tape around the middle at the level of the upper edge of the hip bone (the iliac crest). The tape lies flat and parallel to the floor, touches the skin without pressing in, and is read once the person has breathed out normally. BMI is weight divided by height squared; with pounds and inches, weight is first multiplied by 703.","token_count":139},{"ordinal":2,"section":"Muscle, ethnicity and age","header":"Source: NHLBI and NAASO 2000 (Practical Guide), The Practical Guide: Identification, Evaluation, and Treatment of Overweight and Obesity in Adults. Section: Muscle, ethnicity and age.","body":"The guide is open about BMI being a blunt tool. In a very muscular person it makes fat look greater than it is, and in someone who has lost muscle, as many older people have, it makes them look leaner than they are, so clinical judgement is needed. How BMI relates to body fat also moves with age, sex and perhaps ethnicity. For some groups, Asian Americans among them, the waist tells more about relative risk than BMI does. The guide does not give separate BMI bands for any group.","token_count":167},{"ordinal":3,"section":"Practical reading and limits","header":"Source: NHLBI and NAASO 2000 (Practical Guide), The Practical Guide: Identification, Evaluation, and Treatment of Overweight and Obesity in Adults. Section: Practical reading and limits.","body":"A muscular lifter can sit in the overweight band with a waist well under the lines, so Coach reads BMI and waist together and never presents a band as a verdict. Other countries' guidance sets lower BMI points for people of Asian origin, and this guide does not. The waist lines here are for risk in groups, not a target. The guide's treatment chapters (drugs, surgery) are outside Tracend's scope and are not summarised.","token_count":152}]$lib$::jsonb
);

-- library-source: nhmrc_2013_australian_dietary_guidelines sha256:314ed4ad1a4234a4f833bfe1bfb979fe7794ba177d259d443298b9f578fd64d4
select private.library_replace_source(
$lib${"slug":"nhmrc_2013_australian_dietary_guidelines","title":"Australian Dietary Guidelines","authors":["National Health and Medical Research Council"],"year":2013,"doi":null,"url":"https://www.eatforhealth.gov.au/guidelines/australian-dietary-guidelines-1-5","licence":"proprietary","region":["AU"],"topics":["nutrition","bmi","waist","body-composition","protein","guidelines","australia","ethnicity","energy-balance"],"evidence_level":"national dietary guideline (systematic evidence review)","kind":"guideline"}$lib$::jsonb,
$lib$[{"ordinal":0,"section":"The five guidelines","header":"Source: NHMRC 2013 (Australian Dietary Guidelines), Australian Dietary Guidelines. Section: The five guidelines.","body":"The guidelines rest on five messages. The first is to reach and hold a healthy weight by being active and by matching food and drink to energy needs; older people are told to eat well and stay active to keep their muscle strength. The second is to eat widely from five food groups every day and to drink water: vegetables and legumes; fruit; grain foods, mostly wholegrain; lean meat, poultry, fish, eggs, tofu, nuts, seeds and legumes; and milk, yoghurt, cheese or alternatives, mostly in reduced-fat form. The third asks people to restrict saturated fat, added salt, added sugars and alcohol. The remaining two deal with breastfeeding and the safe handling of food.","token_count":195},{"ordinal":1,"section":"Serves for adults","header":"Source: NHMRC 2013 (Australian Dietary Guidelines), Australian Dietary Guidelines. Section: Serves for adults.","body":"The group that holds lean meat, poultry, fish, eggs, tofu, nuts, seeds and legumes has a daily minimum that depends on age and sex: 3 serves for men aged 19 to 50 and 2.5 for women of that age, then 2.5 for men and 2 for women from age 51. Example serves are about 65 g of cooked lean red meat, 80 g of cooked poultry, 100 g of cooked fish, two large eggs, 150 g (a cup) of cooked beans, lentils or chickpeas, or 170 g of tofu. Adults who are tall or active are told they may take extra serves to meet higher energy needs, provided they watch their weight or waist so that intake does not outrun use.","token_count":178},{"ordinal":2,"section":"BMI and waist","header":"Source: NHMRC 2013 (Australian Dietary Guidelines), Australian Dietary Guidelines. Section: BMI and waist.","body":"Weight status is graded by BMI: under 18.5 underweight, 18.5 to 24.9 healthy, 25 to 29.9 overweight and 30 or more obese. The guidelines caution that the bands do not suit everyone. People of Asian origin may face the same risk at a lower BMI and people of Polynesian origin at a higher one, and after age 70 a somewhat higher BMI can be acceptable. For Australians of Asian origin it explains that the WHO bands were built mostly on European populations and may therefore understate body fat and risk.\n\nFor waist, women are at increased risk from 80 cm and high risk from 88 cm, and men from 94 cm and 102 cm, again with a warning that other ethnic groups may need different numbers. It advises checking weight and waist every two to three months.","token_count":214},{"ordinal":3,"section":"Practical reading and limits","header":"Source: NHMRC 2013 (Australian Dietary Guidelines), Australian Dietary Guidelines. Section: Practical reading and limits.","body":"The serves are a minimum pattern for the general public, not a protein target for a lifter; the Australian protein reference values entry gives the grams per kilo, and the plan's rules set the athlete's number. The guidelines predate sports-nutrition work and say nothing specific to people who train. The waist lines are the same as the WHO figures commonly quoted. NHMRC has said it is reviewing the 2013 edition, so the guidance may change. The weight chapter also covers children, pregnancy and eating disorders; this summary does not, and Coach never diagnoses.","token_count":172}]$lib$::jsonb
);

-- library-source: nhmrc_nz_2006_nrv_protein sha256:e2241ae5ac3207f1807e635e2231afa69ab0fbe5c5ae7f926bb5a01215910645
select private.library_replace_source(
$lib${"slug":"nhmrc_nz_2006_nrv_protein","title":"Nutrient Reference Values for Australia and New Zealand: Protein","authors":["National Health and Medical Research Council","Australian Government Department of Health and Ageing","New Zealand Ministry of Health"],"year":2006,"doi":null,"url":"https://www.eatforhealth.gov.au/nutrient-reference-values/nutrients/protein","licence":"proprietary","region":["AU"],"topics":["nutrition","protein","guidelines","australia","plant-protein"],"evidence_level":"national nutrient reference values","kind":"guideline"}$lib$::jsonb,
$lib$[{"ordinal":0,"section":"Adult values","header":"Source: NHMRC and NZ Ministry of Health 2006 (protein), Nutrient Reference Values for Australia and New Zealand: Protein. Section: Adult values.","body":"For healthy adults aged 19 to 70 the page sets the average requirement at 0.68 g of protein per kg of body weight a day for men and 0.60 g for women. The recommended dietary intake, meant to cover nearly everyone, is 0.84 g per kg for men and 0.75 g for women, which works out at 64 g and 46 g a day. For people over 70 both figures are raised: the requirement was increased by a quarter (0.86 g per kg for men, 0.75 for women) and the recommended intake is 1.07 and 0.94 g per kg, though the page concedes that the evidence behind the rise is limited.","token_count":175},{"ordinal":1,"section":"Upper level and sources","header":"Source: NHMRC and NZ Ministry of Health 2006 (protein), Nutrient Reference Values for Australia and New Zealand: Protein. Section: Upper level and sources.","body":"The page sets no upper limit in grams per day, because the data are too thin. Instead it recommends capping protein at 25 percent of energy, and judges the risk from protein eaten in ordinary food to be very low, while advising care with supplements of single amino acids. It adds that animal and plant foods both supply protein and that plants alone can provide every essential amino acid. In Australia and New Zealand about a third of intake comes from meat, poultry and fish and about a quarter from cereals.","token_count":167},{"ordinal":2,"section":"Practical reading and limits","header":"Source: NHMRC and NZ Ministry of Health 2006 (protein), Nutrient Reference Values for Australia and New Zealand: Protein. Section: Practical reading and limits.","body":"These values are the amount that meets the needs of healthy people at rest, estimated by a factorial method for healthy people, not the amount that best supports hard training. The sports-nutrition range in the Jäger 2017 and Morton 2018 entries is higher for people who lift, and the plan's rules set the athlete's own number; the library does not read the Australian value as a ceiling. The page has no section on athletes. Protein for pregnancy and breastfeeding is on the page and is not summarised here.","token_count":168}]$lib$::jsonb
);

-- library-source: au_health_2021_adult_activity_guidelines sha256:60dade4f61d2d8999ca35eac8804ab906ea78e51c3e817a979489e5e1bb61d73
select private.library_replace_source(
$lib${"slug":"au_health_2021_adult_activity_guidelines","title":"Physical activity and exercise guidelines for all Australians: for adults (18 to 64 years)","authors":["Australian Government Department of Health, Disability and Ageing"],"year":2021,"doi":null,"url":"https://www.health.gov.au/topics/physical-activity-and-exercise/physical-activity-and-exercise-guidelines-for-all-australians/for-adults-18-to-64-years","licence":"proprietary","region":["AU"],"topics":["activity","cardio","strength","guidelines","sedentary","australia"],"evidence_level":"national public health guideline","kind":"guideline"}$lib$::jsonb,
$lib$[{"ordinal":0,"section":"What adults should do","header":"Source: Australian Department of Health 2021 (adult activity guidelines), Physical activity and exercise guidelines for all Australians: for adults (18 to 64 years). Section: What adults should do.","body":"The weekly target for adults is either 2.5 to 5 hours of moderate activity (for example brisk walking, golf, mowing the lawn or swimming) or 1.25 to 2.5 hours of vigorous activity (such as jogging, aerobics, fast cycling or soccer), or a mix that adds up to the same. Activity should happen on most days, ideally all of them.\n\nOn at least two days a week the activity should include strength work. Named examples are push-ups, pull-ups, squats, lunges, weight lifting, and chores involving lifting, carrying or digging. The page adds that some activity beats none and that someone starting from zero should begin small and build up.","token_count":208},{"ordinal":1,"section":"Sitting and benefits","header":"Source: Australian Department of Health 2021 (adult activity guidelines), Physical activity and exercise guidelines for all Australians: for adults (18 to 64 years). Section: Sitting and benefits.","body":"The page says that long spells of sitting can cancel out some of the good done by exercise, so adults are encouraged to sit less and to interrupt sitting, for instance with walking meetings, a standing desk or a lunchtime walk. Benefits it names for regular activity are a lower risk of type 2 diabetes, cardiovascular disease and some cancers; healthier blood pressure, cholesterol and blood sugar; less weight gain; stronger muscles and bones; and better wellbeing and social contact.","token_count":171},{"ordinal":2,"section":"Practical reading and limits","header":"Source: Australian Department of Health 2021 (adult activity guidelines), Physical activity and exercise guidelines for all Australians: for adults (18 to 64 years). Section: Practical reading and limits.","body":"This is a floor for health, and a lifter's plan usually exceeds it, so Coach presents it as the minimum that already pays off. It agrees broadly with the WHO 2020 and UK 2026 entries, and its upper bounds (5 hours moderate, 2.5 hours vigorous) are a range of benefit, not a limit. The page does not set repetitions, loads or a time for the strength days, and its pregnancy and older-adult pages are separate and not summarised.","token_count":158}]$lib$::jsonb
);

-- library-source: who_2011_waist_circumference_report sha256:ee18db7a5753676192401de2a270ff690fcafa8e5605541dd1592be50d7f4c7c
select private.library_replace_source(
$lib${"slug":"who_2011_waist_circumference_report","title":"Waist circumference and waist-hip ratio: report of a WHO expert consultation","authors":["World Health Organization"],"year":2011,"doi":null,"url":"https://www.who.int/publications/i/item/9789241501491","licence":"proprietary","region":["global"],"topics":["waist","bmi","body-composition","guidelines","ethnicity","health"],"evidence_level":"expert consultation (evidence review)","kind":"guideline"}$lib$::jsonb,
$lib$[{"ordinal":0,"section":"What the consultation found","header":"Source: WHO 2011 (waist circumference and waist-hip ratio), Waist circumference and waist-hip ratio: report of a WHO expert consultation. Section: What the consultation found.","body":"The panel concluded with confidence that a bigger waist, and a higher waist-to-hip ratio, go with more disease risk across many populations, although most of the evidence came from people of European descent. The two measures overlap with BMI without duplicating it. The report leans towards waist circumference rather than waist-to-hip ratio because it is easier to take, recommends getting a BMI too where possible and weighing the two together, and says the evidence for waist-to-height ratio was too thin at the time to rank it.","token_count":177},{"ordinal":1,"section":"Differences between populations","header":"Source: WHO 2011 (waist circumference and waist-hip ratio), Waist circumference and waist-hip ratio: report of a WHO expert consultation. Section: Differences between populations.","body":"The report finds clear differences by sex and age and some by ethnicity. Asian populations hold more fat deep in the abdomen than Europeans at the same size, so a given waist may carry more risk and lower thresholds may be warranted; for African populations, and possibly Pacific Islanders, the reverse may hold. The panel's view is that one set of BMI and waist cut-offs cannot be right for the whole world. It set no new cut-offs itself and left that to a later WHO process.","token_count":164},{"ordinal":2,"section":"Cut-offs and how to measure","header":"Source: WHO 2011 (waist circumference and waist-hip ratio), Waist circumference and waist-hip ratio: report of a WHO expert consultation. Section: Cut-offs and how to measure.","body":"An annex lists the cut-offs in use. The figures often credited to WHO are 94 cm for men and 80 cm for women (increased risk) and 102 cm and 88 cm (substantially increased risk); they come from WHO publications of 1999 and 2000, and the 2000 report gave them only as an example from a Dutch sample, not as a WHO recommendation. The International Diabetes Federation uses 94 and 80 cm for people of European origin and 90 and 80 cm for South Asian, Chinese and Japanese people. The US cholesterol programme uses 102 and 88 cm for everyone.\n\nMeasurement sites differ too: the WHO STEPS method takes the waist halfway between the lowest palpable rib and the top of the hip bone, while the US methods use the top of the hip bone.","token_count":225},{"ordinal":3,"section":"Practical reading and limits","header":"Source: WHO 2011 (waist circumference and waist-hip ratio), Waist circumference and waist-hip ratio: report of a WHO expert consultation. Section: Practical reading and limits.","body":"Coach uses this report to explain why the lines in an athlete's country may differ from another country's, and never to apply a line of its own. Waist lines are group screening points, not a diagnosis or a target, and a lean, muscular lifter can have a waist that reads high or low for reasons the lines do not capture. The report predates the waist-to-height ratio guidance in the UK entry. The measuring point matters: a figure from one method should not be compared with a line set for another.","token_count":169}]$lib$::jsonb
);

