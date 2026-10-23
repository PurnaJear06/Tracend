// The goal phase review as text for Coach: figures Tracend calculated, with the reasons and the
// sources behind the outcome. It is reference data; the rules for how to speak about it live in
// the Coach chat instructions.
//
// The weights, dates, counts, rates and the athlete's own target are records, marked as such
// (`../../recorded_text.ts`). The windows ("the last 4 weeks", the newest readings Tracend reads)
// and the thresholds in a reason are Tracend's fixed wording and ground nothing.
import { plain, record } from "../../recorded_text.ts";
import { goalPhaseSources } from "./sources.ts";
import { maxInputReadings } from "./summary.ts";
import type { GoalPhaseReview, GoalPhaseSummary, GoalTarget } from "./types.ts";

function signed(value: number): string {
  return value > 0 ? `+${value}` : String(value);
}

export function describeGoalTarget(target: GoalTarget): string {
  return plain(describeGoalTargetMarked(target));
}

/** The target as `describeGoalTarget` says it, with its values marked. */
export function describeGoalTargetMarked(target: GoalTarget): string {
  const parts: string[] = [];
  if (target.weightKg !== null) parts.push(`weight ${record(target.weightKg)} kg`);
  if (target.bodyFatMinPct !== null || target.bodyFatMaxPct !== null) {
    parts.push(
      target.bodyFatMinPct !== null && target.bodyFatMaxPct !== null
        ? `body fat ${record(target.bodyFatMinPct)} to ${record(target.bodyFatMaxPct)}%`
        : `body fat ${record(target.bodyFatMinPct ?? target.bodyFatMaxPct ?? "")}%`,
    );
  }
  if (target.physique !== null) {
    const note = target.physiqueNote === null ? "" : ` ("${record(target.physiqueNote)}")`;
    parts.push(`physique ${target.physique.replaceAll("_", " ")}${note}`);
  }
  if (target.date !== null) parts.push(`by ${record(target.date)}`);
  return parts.join(", ");
}

/** What the current weight is: the median of its last readings, or the single reading. */
export function latestWeightBasis(summary: GoalPhaseSummary): string {
  return plain(latestWeightBasisMarked(summary));
}

/** `latestWeightBasis` with its date and its count of readings marked. */
export function latestWeightBasisMarked(summary: GoalPhaseSummary): string {
  return summary.currentReadingsUsed <= 1
    ? `reading on ${record(summary.currentDate ?? "")}`
    : `median of the last ${record(summary.currentReadingsUsed)} readings, up to ${
      record(summary.currentDate ?? "")
    }`;
}

/** Excluded readings listed one by one; the rest are counted. */
const maxExcludedListed = 3;

function ago(days: number | null): string {
  return days === null
    ? ""
    : days === 0
    ? "today"
    : days === 1
    ? `${record(1)} day ago`
    : `${record(days)} days ago`;
}

export function renderGoalPhase(
  summary: GoalPhaseSummary,
  review: GoalPhaseReview,
): string | null {
  const marked = renderGoalPhaseMarked(summary, review);
  return marked === null ? null : plain(marked);
}

/** The review as `renderGoalPhase` says it, with the values in it marked. */
export function renderGoalPhaseMarked(
  summary: GoalPhaseSummary,
  review: GoalPhaseReview,
): string | null {
  if (!summary.hasGoal) return null;
  const lines = [
    "Goal phase review, calculated by Tracend from the athlete's recorded weight readings (not " +
    "from the goal's saved weight):",
  ];
  // The outcome and its reasons come first: the host clips a block from its tail.
  lines.push(`- Review outcome: ${review.outcome}${review.needsTarget ? " (no target set)" : ""}.`);
  const cited = new Set<string>();
  for (const reason of review.reasons) {
    lines.push(`  - ${reason.marked}.`);
    reason.sources.forEach((id) => cited.add(id));
  }
  const labels = [...cited].map((id) =>
    goalPhaseSources[id as keyof typeof goalPhaseSources]?.label
  ).filter(Boolean);
  if (labels.length > 0) lines.push(`  - Basis: ${labels.join("; ")}.`);
  const goal = summary.goalType?.replaceAll("_", " ") ?? "unknown";
  lines.push(
    `- Goal: ${goal}. Phase start ${summary.phaseStart ? record(summary.phaseStart) : "unknown"}` +
      (summary.phaseStartSource === "first_reading" ? " (first reading)" : "") + ".",
  );
  if (summary.phaseStartSource === "goal_activation") {
    lines.push(
      `- The goal's saved notes were entered on ${
        record(summary.phaseStart ?? "")
      } and are not updated; ` +
        `weights in them are from that day, not today.`,
    );
  }
  const latest = `latest weight ${record(summary.currentWeightKg ?? "")} kg (${
    latestWeightBasisMarked(summary)
  }, ${ago(summary.latestReadingAgeDays)})`;
  const history = summary.history;
  const run = summary.continuousLoss;
  if (history !== null) {
    lines.push(
      `- Recorded history, ${
        history.capped
          ? `the newest ${maxInputReadings} readings, from ${
            record(history.startDate)
          } (older readings may exist)`
          : "all weight readings"
      }: ${record(history.startWeightKg)} kg on ${record(history.startDate)} ` +
        `(median of the first readings) to ${latest}: ` +
        `${record(signed(history.changeKg))} kg (${record(signed(history.changePct))}%) over ${
          record(history.weeks)
        } weeks, ${record(history.readingsUsed)} readings` +
        (history.sparse
          ? "; sparse readings, trend not confirmed."
          : run?.confirmed && run.startDate === history.startDate
          ? "; one continuous loss."
          : "."),
    );
  }
  if (run !== null && run.startDate !== history?.startDate) {
    lines.push(
      `- Continuous loss: from the high of ${record(run.startWeightKg)} kg on ${
        record(run.startDate)
      } to ` +
        `${latest}: ${record(signed(run.changeKg))} kg (${record(signed(run.changePct))}%) ` +
        `over ${record(run.weeks)} weeks` +
        (run.beganBeforeGoalPhase ? "" : "; the weight rose before it fell") +
        (run.confirmed ? "." : "; sparse readings, trend not confirmed."),
    );
  }
  if (summary.changeKg !== null && summary.changePct !== null && summary.weeks !== null) {
    lines.push(
      `- ${
        history !== null || run !== null
          ? `Goal phase (${goal}, since ${record(summary.phaseStart ?? "")}): `
          : ""
      }Start ${record(summary.startWeightKg ?? "")} kg (${
        record(summary.firstReadingDate ?? "")
      }, median of the first readings) ` +
        `to ${latest}: ` +
        `${record(signed(summary.changeKg))} kg (${record(signed(summary.changePct))}%) over ${
          record(summary.weeks)
        } weeks, ${record(summary.readingsUsed)} readings.`,
    );
    const recent = summary.recentRateKgPerWeek === null
      ? ""
      : `; last 4 weeks ${record(signed(summary.recentRateKgPerWeek))} kg a week`;
    const staleNote = summary.latestReadingStale
      ? ` These rates end at the latest reading, ${ago(summary.latestReadingAgeDays)}; they are ` +
        `not evidence of the present trend.`
      : "";
    lines.push(
      `- Average rate ${record(signed(summary.weeklyRateKg!))} kg a week (${
        record(signed(summary.weeklyRatePct!))
      }% of start weight)${recent}.${staleNote}`,
    );
  } else if (summary.currentWeightKg !== null) {
    lines.push(
      `- ${latest[0].toUpperCase()}${latest.slice(1)}; not enough readings ` +
        `since the goal began to show a change or a rate.`,
    );
  } else {
    lines.push("- No weight readings since the goal began.");
  }
  if (summary.bmi !== null) {
    lines.push(
      `- BMI ${record(summary.bmi)} at the latest weight (height ${
        record(summary.heightCm ?? "")
      } cm).`,
    );
  }
  lines.push(
    summary.hasTarget
      ? `- Target set by the athlete: ${describeGoalTargetMarked(summary.target)}.`
      : "- Target: none set. The athlete has not chosen a weight, body-fat range or physique goal.",
  );
  for (const item of summary.excluded.slice(0, maxExcludedListed)) {
    lines.push(
      `- Excluded reading (not physiologically plausible against its neighbours; do not use it): ` +
        `${record(item.kg)} kg on ${record(item.date)}.`,
    );
  }
  if (summary.excluded.length > maxExcludedListed) {
    lines.push(
      `- and ${
        record(summary.excluded.length - maxExcludedListed)
      } more excluded readings (same rule; ` +
        `do not use them).`,
    );
  }
  lines.push(
    `- Confidence: ${summary.confidence}${
      summary.notes.length > 0 ? ` (${summary.notes.join("; ")})` : ""
    }.`,
  );
  return lines.join("\n");
}
