// Phrases and figures the cases share.
import type { Phrase } from "./types.ts";

const phrase = (label: string, ...anyOf: RegExp[]): Phrase => ({ label, anyOf });

export const asksForTarget = phrase(
  "asks for a target",
  /\btarget\b/i,
  /\bgoal weight\b/i,
  /\bphysique\b/i,
  /\bbody[- ]fat range\b/i,
);
export const maintenanceOrBreak = phrase(
  "maintenance or diet break",
  /\bmaintenance\b/i,
  /\bdiet break\b/i,
  /\bhold (?:your|this) weight\b/i,
);
export const healthyFloor = phrase(
  "healthy-weight floor",
  /\bBMI\b/,
  /healthy (?:weight|range)/i,
  /\b59\.9\s*kg\b/,
);
export const wontProject = phrase(
  "says a trend is not a forecast",
  /\b(?:won'?t|can'?t|not|never)\b[^.]{0,40}\b(?:project|predict|forecast|extrapolate|give you a (?:date|weight|number))/i,
  /\btrend is (?:history|not)/i,
  /\bhistory,? not\b/i,
  /\bwhere you are,? not where\b/i,
);
export const noLongRun = phrase(
  "suggests a long run",
  /\blong runs?\b/i,
  /\b(?:5|10)\s?k\b/i,
  /\brun for (?:3|4|5)\d minutes\b/i,
);
export const seesDoctor = phrase(
  "points to a doctor or professional",
  /\bdoctor\b/i,
  /\bphysician\b/i,
  /\bphysio\w*\b/i,
  /\bqualified (?:exercise )?professional\b/i,
  /\bprofessional\b/i,
);
export const incompleteLogging = phrase(
  "says the log is incomplete",
  /\bincomplete\b/i,
  /\bpartial\w*\b/i,
  /\bnot (?:every|all) meals?\b/i,
  /\b(?:only|just) (?:one|a few|part|some)\b[^.]{0,30}\b(?:meal|logged)\b/i,
  /\b(?:didn'?t|haven'?t|did not|have not) log/i,
  /\bmissing (?:meals|entries)\b/i,
  /\bmore than (?:one|a) meal\b/i,
);
export const noData = phrase(
  "says there is no data",
  /\b(?:no|not enough|without|don'?t have|do not have|haven'?t got|nothing)\b[^.]{0,40}\b(?:data|readings?|logged|synced|recorded|history|record)/i,
  /\bno (?:sleep|watch|weigh)/i,
);
export const asksToWeighIn = phrase(
  "asks for a new weigh-in",
  /\bweigh[- ]?in\b/i,
  /\bweigh yourself\b/i,
  /\bnew (?:weight|reading|measurement)\b/i,
  /\blog (?:your|a) weight\b/i,
);
export const suggestsOnApp = phrase(
  "points to the app",
  /\bin the app\b/i,
  /\bon Progress\b/i,
  /\bProgress\b/,
  /\bSet your target\b/i,
  /\bplan screen\b/i,
  /\bsettings\b/i,
  /\byou can (?:set|change|update|edit|log|add)\b/i,
);

export const proposalWords = phrase(
  "says a proposal waits for the athlete's approval",
  /\bproposal\b/i,
  /\bapprove\b/i,
);
