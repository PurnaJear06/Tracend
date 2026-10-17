// The goal phase review as text for Coach: figures Tracend calculated, with the reasons and the
// sources behind the outcome. It is reference data; the rules for how to speak about it live in
// the Coach chat instructions.
import { goalPhaseSources } from "./sources.ts";
import { maxInputReadings } from "./summary.ts";
import type { GoalPhaseReview, GoalPhaseSummary, GoalTarget } from "./types.ts";

function signed(value: number): string {
  return value > 0 ? `+${value}` : String(value);
}

export function describeGoalTarget(target: GoalTarget): string {
  const parts: string[] = [];
  if (target.weightKg !== null) parts.push(`weight ${target.weightKg} kg`);
  if (target.bodyFatMinPct !== null || target.bodyFatMaxPct !== null) {
    parts.push(
      target.bodyFatMinPct !== null && target.bodyFatMaxPct !== null
        ? `body fat ${target.bodyFatMinPct} to ${target.bodyFatMaxPct}%`
        : `body fat ${target.bodyFatMinPct ?? target.bodyFatMaxPct}%`,
    );
  }
  if (target.physique !== null) {
    const note = target.physiqueNote === null ? "" : ` ("${target.physiqueNote}")`;
    parts.push(`physique ${target.physique.replaceAll("_", " ")}${note}`);
  }
  if (target.date !== null) parts.push(`by ${target.date}`);
  return parts.join(", ");
}

function ago(days: number | null): string {
  return days === null ? "" : days === 0 ? "today" : days === 1 ? "1 day ago" : `${days} days ago`;
}

export function renderGoalPhase(
  summary: GoalPhaseSummary,
  review: GoalPhaseReview,
): string | null {
  if (!summary.hasGoal) return null;
  const lines = [
    "Goal phase review, calculated by Tracend from the athlete's recorded weight readings (not " +
    "from the goal's saved weight):",
  ];
  const goal = summary.goalType?.replaceAll("_", " ") ?? "unknown";
  lines.push(
    `- Goal: ${goal}. Phase start ${summary.phaseStart ?? "unknown"}` +
      (summary.phaseStartSource === "first_reading" ? " (first reading)" : "") + ".",
  );
  if (summary.phaseStartSource === "goal_activation") {
    lines.push(
      `- The goal's saved notes were entered on ${summary.phaseStart} and are not updated; ` +
        `weights in them are from that day, not today.`,
    );
  }
  const latest = `latest recorded weight ${summary.currentWeightKg} kg (${summary.currentDate}, ${
    ago(summary.latestReadingAgeDays)
  })`;
  const history = summary.history;
  const run = summary.continuousLoss;
  if (history !== null) {
    lines.push(
      `- Recorded history, ${
        history.capped
          ? `the newest ${maxInputReadings} readings, from ${history.startDate} (older readings may exist)`
          : "all weight readings"
      }: ${history.startWeightKg} kg on ${history.startDate} ` +
        `(median of the first readings) to ${latest}: ` +
        `${signed(history.changeKg)} kg (${signed(history.changePct)}%) over ${history.weeks} ` +
        `weeks, ${history.readingsUsed} readings` +
        (history.sparse
          ? "; sparse readings, trend not confirmed."
          : run?.confirmed && run.startDate === history.startDate
          ? "; one continuous loss."
          : "."),
    );
  }
  if (run !== null && run.startDate !== history?.startDate) {
    lines.push(
      `- Continuous loss: from the high of ${run.startWeightKg} kg on ${run.startDate} to ` +
        `${latest}: ${signed(run.changeKg)} kg (${signed(run.changePct)}%) ` +
        `over ${run.weeks} weeks` +
        (run.beganBeforeGoalPhase ? "" : "; the weight rose before it fell") +
        (run.confirmed ? "." : "; sparse readings, trend not confirmed."),
    );
  }
  if (summary.changeKg !== null && summary.changePct !== null && summary.weeks !== null) {
    lines.push(
      `- ${
        history !== null || run !== null
          ? `Goal phase (${goal}, since ${summary.phaseStart}): `
          : ""
      }Start ${summary.startWeightKg} kg (${summary.firstReadingDate}, median of the first readings) ` +
        `to ${latest}: ` +
        `${signed(summary.changeKg)} kg (${signed(summary.changePct)}%) over ${summary.weeks} ` +
        `weeks, ${summary.readingsUsed} readings.`,
    );
    const recent = summary.recentRateKgPerWeek === null
      ? ""
      : `; last 4 weeks ${signed(summary.recentRateKgPerWeek)} kg a week`;
    const staleNote = summary.latestReadingStale
      ? ` These rates end at the latest reading, ${ago(summary.latestReadingAgeDays)}; they are ` +
        `not evidence of the present trend.`
      : "";
    lines.push(
      `- Average rate ${signed(summary.weeklyRateKg!)} kg a week (${
        signed(summary.weeklyRatePct!)
      }% of start weight)${recent}.${staleNote}`,
    );
  } else if (summary.currentWeightKg !== null) {
    lines.push(
      `- Latest recorded weight ${summary.currentWeightKg} kg (${summary.currentDate}, ${
        ago(summary.latestReadingAgeDays)
      }); not enough readings ` +
        `since the goal began to show a change or a rate.`,
    );
  } else {
    lines.push("- No weight readings since the goal began.");
  }
  if (summary.bmi !== null) {
    lines.push(
      `- BMI ${summary.bmi} at the latest recorded weight (height ${summary.heightCm} cm).`,
    );
  }
  lines.push(
    summary.hasTarget
      ? `- Target set by the athlete: ${describeGoalTarget(summary.target)}.`
      : "- Target: none set. The athlete has not chosen a weight, body-fat range or physique goal.",
  );
  for (const item of summary.excluded) {
    lines.push(
      `- Excluded reading (not physiologically plausible against its neighbours; do not use it): ` +
        `${item.kg} kg on ${item.date}.`,
    );
  }
  lines.push(`- Review outcome: ${review.outcome}${review.needsTarget ? " (no target set)" : ""}.`);
  const cited = new Set<string>();
  for (const reason of review.reasons) {
    lines.push(`  - ${reason.detail}.`);
    reason.sources.forEach((id) => cited.add(id));
  }
  const labels = [...cited].map((id) =>
    goalPhaseSources[id as keyof typeof goalPhaseSources]?.label
  ).filter(Boolean);
  if (labels.length > 0) lines.push(`  - Basis: ${labels.join("; ")}.`);
  lines.push(
    `- Confidence: ${summary.confidence}${
      summary.notes.length > 0 ? ` (${summary.notes.join("; ")})` : ""
    }.`,
  );
  return lines.join("\n");
}
