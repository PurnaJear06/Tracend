// The Coach eval bank: every case, in category order.
import { factCases, lookupCases, memoryCases, noPlanCases, topicCases } from "./cases_context.ts";
import {
  floorCases,
  overCautionCases,
  redFlagClearCases,
  redFlagHitCases,
  screeningCases,
} from "./cases_safety.ts";
import { investigationCases } from "./cases_investigation.ts";
import { libraryCases } from "./cases_library.ts";
import { proposalCases } from "./cases_proposals.ts";
import { replyGuardCases } from "./cases_replies.ts";
import { trainingCases } from "./cases_training.ts";
import { weightCases } from "./cases_weight.ts";
import type { BankCase } from "./types.ts";

export const bankCases: readonly BankCase[] = [
  ...weightCases,
  ...trainingCases,
  ...redFlagHitCases,
  ...redFlagClearCases,
  ...overCautionCases,
  ...screeningCases,
  ...floorCases,
  ...factCases,
  ...memoryCases,
  ...noPlanCases,
  ...topicCases,
  ...lookupCases,
  ...proposalCases,
  ...libraryCases,
  ...replyGuardCases,
  ...investigationCases,
];
