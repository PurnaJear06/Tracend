// How Tracend rates the stress an exercise puts on the knee, the lower back and
// the shoulder (decision D6). The ratings choose joint-friendly swaps and range
// limits; they never diagnose, treat or rehabilitate, and they never decide
// whether someone may train. Rule data only; nothing reads it yet (B5).
import { sourced } from "./sources.ts";

export const joints = ["knee", "back", "shoulder"] as const;
export type Joint = typeof joints[number];

export const jointStressLevels = ["low", "moderate", "high"] as const;
export type JointStress = typeof jointStressLevels[number];

export const jointStressMethod = sourced<Readonly<Record<JointStress, string>>>(
  Object.freeze({
    low: "The joint barely moves under load, or the load is small and well supported.",
    moderate: "The joint works through a large range or under a meaningful load, and the " +
      "exercise is easy to scale down.",
    high: "Heavy load through a large range, or load near the end of the joint's range; the " +
      "first exercise to swap or shorten when that joint complains.",
  }),
  ["tracend_in_house"],
  "An in-house rating written in our own words for choosing swaps. It describes the " +
    "exercise as normally performed, not any person's joint, and is reviewed by hand for " +
    "every catalog exercise.",
);
