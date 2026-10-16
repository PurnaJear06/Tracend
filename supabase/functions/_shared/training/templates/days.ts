// The sessions of every split. Each session lists its slots in priority order: the main lifts
// first, then supporting lifts, then accessories chosen for the athlete's goal (see `profile`).
import type { MovementPattern } from "../../onboarding/catalog.ts";
import type { Slot, SlotTier, TailProfile, TemplateDay } from "./types.ts";

const slot = (tier: SlotTier, ...patterns: MovementPattern[]): Slot => ({ patterns, tier });
const main = (...patterns: MovementPattern[]) => slot("main", ...patterns);
const support = (...patterns: MovementPattern[]) => slot("support", ...patterns);
const accessory = (...patterns: MovementPattern[]) => slot("accessory", ...patterns);
const rotating = (made: Slot): Slot => ({ ...made, rotate: true });

/** Trunk work rotates: no two sessions of a week use one exercise while another is free. */
const core = () => rotating(accessory("core"));

type Tails = Readonly<Record<string, readonly Slot[]>>;

// Accessories by goal. Strength keeps few, size and aesthetic add the muscles that show or limit
// the main lifts, and the lean goals (fat loss, recomposition) keep sessions compound-led with
// the trunk first. These orders are Tracend's own coaching choices (ALGORITHMS §9).
const fullBodyTails: Readonly<Record<TailProfile, Tails>> = {
  strength: {
    A: [core(), accessory("biceps")],
    B: [core(), accessory("triceps")],
    C: [core(), accessory("calves")],
  },
  size: {
    A: [accessory("lateral_raise"), accessory("biceps"), core(), accessory("calves")],
    B: [accessory("triceps"), accessory("rear_delts"), core(), accessory("calves")],
    C: [accessory("biceps"), accessory("lateral_raise"), core(), accessory("triceps")],
  },
  aesthetic: {
    A: [accessory("lateral_raise"), accessory("biceps"), accessory("rear_delts"), core()],
    B: [accessory("lateral_raise"), accessory("triceps"), accessory("rear_delts"), core()],
    C: [accessory("lateral_raise"), accessory("biceps"), accessory("triceps"), core()],
  },
  lean: {
    A: [core(), accessory("lateral_raise"), accessory("biceps")],
    B: [core(), accessory("triceps"), accessory("calves")],
    C: [core(), accessory("biceps"), accessory("lateral_raise")],
  },
};

export function fullBodyDay(letter: "A" | "B" | "C", profile: TailProfile): TemplateDay {
  const tail = fullBodyTails[profile][letter];
  if (letter === "A") {
    return {
      name: "Full body A",
      objective: "Squat, press and row patterns with a hinge, at a repeatable effort.",
      slots: [
        main("squat"),
        main("horizontal_push"),
        main("horizontal_pull", "vertical_pull"),
        support("hinge"),
        ...tail,
      ],
    };
  }
  if (letter === "B") {
    return {
      name: "Full body B",
      objective: "Hinge, overhead press and pulling, with single-leg work.",
      slots: [
        main("hinge"),
        main("vertical_push", "horizontal_push"),
        main("vertical_pull", "horizontal_pull"),
        support("lunge", "squat"),
        ...tail,
      ],
    };
  }
  return {
    name: "Full body C",
    objective: "A second squat and press day with a changed pull.",
    slots: [
      main("squat", "lunge"),
      main("horizontal_push"),
      rotating(main("vertical_pull", "horizontal_pull")),
      support("hinge"),
      ...tail,
    ],
  };
}

// No trunk work in the upper sessions: an athlete who avoids every upper-body movement gets no
// upper day (the answers are refused as infeasible), not a day of trunk work.
const upperTails: Readonly<Record<TailProfile, Readonly<Record<"A" | "B", readonly Slot[]>>>> = {
  strength: {
    A: [accessory("triceps"), accessory("biceps")],
    B: [accessory("biceps"), accessory("triceps")],
  },
  size: {
    A: [accessory("lateral_raise"), accessory("triceps"), accessory("biceps")],
    B: [accessory("rear_delts", "lateral_raise"), accessory("biceps"), accessory("triceps")],
  },
  aesthetic: {
    A: [
      accessory("lateral_raise"),
      accessory("rear_delts"),
      accessory("triceps"),
      accessory("biceps"),
    ],
    B: [
      accessory("lateral_raise"),
      accessory("biceps"),
      accessory("rear_delts"),
      accessory("triceps"),
    ],
  },
  lean: {
    A: [accessory("lateral_raise"), accessory("triceps")],
    B: [accessory("rear_delts", "lateral_raise"), accessory("biceps")],
  },
};

export function upperDay(letter: "A" | "B", profile: TailProfile): TemplateDay {
  const tail = upperTails[profile][letter];
  if (letter === "A") {
    return {
      name: "Upper A",
      objective: "Horizontal pressing and pulling first, then shoulders and arms.",
      slots: [
        main("horizontal_push"),
        main("horizontal_pull"),
        support("vertical_push"),
        support("vertical_pull", "horizontal_pull"),
        ...tail,
      ],
    };
  }
  return {
    name: "Upper B",
    objective: "Vertical pulling and pressing first, then upper-back and arm work.",
    slots: [
      rotating(main("vertical_pull", "horizontal_pull")),
      main("vertical_push", "horizontal_push"),
      support("horizontal_pull"),
      support("horizontal_push"),
      ...tail,
    ],
  };
}

const lowerTails: Readonly<Record<TailProfile, Readonly<Record<"A" | "B", readonly Slot[]>>>> = {
  strength: { A: [core(), accessory("calves")], B: [core(), accessory("calves")] },
  size: {
    A: [accessory("calves"), core(), accessory("quads_isolation")],
    B: [accessory("calves"), core(), accessory("hamstring_curl")],
  },
  aesthetic: {
    A: [accessory("calves"), core(), accessory("hamstring_curl")],
    B: [accessory("quads_isolation", "lunge"), accessory("calves"), core()],
  },
  lean: { A: [core(), accessory("calves")], B: [core(), accessory("calves")] },
};

export function lowerDay(letter: "A" | "B", profile: TailProfile): TemplateDay {
  const tail = lowerTails[profile][letter];
  if (letter === "A") {
    return {
      name: "Lower A",
      objective: "Squat-led lower body with a hinge and single-leg work.",
      slots: [
        main("squat"),
        main("hinge"),
        support("lunge"),
        support("hamstring_curl", "hinge"),
        ...tail,
      ],
    };
  }
  return {
    name: "Lower B",
    objective: "Hinge-led lower body with quad and hamstring accessories.",
    slots: [
      main("hinge"),
      main("squat", "lunge"),
      support("quads_isolation", "lunge"),
      support("hamstring_curl", "hinge"),
      ...tail,
    ],
  };
}

const pushTails: Readonly<Record<TailProfile, readonly Slot[]>> = {
  strength: [accessory("triceps"), core()],
  size: [accessory("lateral_raise"), accessory("triceps"), core()],
  aesthetic: [accessory("lateral_raise"), accessory("triceps"), accessory("rear_delts"), core()],
  lean: [accessory("lateral_raise"), accessory("triceps"), core()],
};

export function pushDay(second: boolean, profile: TailProfile): TemplateDay {
  const tail = pushTails[profile];
  return second
    ? {
      name: "Push 2",
      objective: "Overhead pressing first, then chest and triceps.",
      slots: [
        main("vertical_push", "horizontal_push"),
        main("horizontal_push"),
        support("chest_fly", "horizontal_push"),
        ...tail,
      ],
    }
    : {
      name: "Push",
      objective: "Chest, shoulders and triceps.",
      slots: [
        main("horizontal_push"),
        main("vertical_push"),
        support("chest_fly", "horizontal_push"),
        ...tail,
      ],
    };
}

const pullTails: Readonly<Record<TailProfile, readonly Slot[]>> = {
  strength: [accessory("biceps"), core()],
  size: [accessory("biceps"), accessory("rear_delts"), core()],
  aesthetic: [accessory("biceps"), accessory("rear_delts"), accessory("lateral_raise"), core()],
  lean: [accessory("biceps"), accessory("rear_delts"), core()],
};

export function pullDay(second: boolean, profile: TailProfile): TemplateDay {
  const tail = pullTails[profile];
  return second
    ? {
      name: "Pull 2",
      objective: "Rows first, then vertical pulling and arms.",
      slots: [
        main("horizontal_pull"),
        rotating(main("vertical_pull", "horizontal_pull")),
        support("rear_delts", "horizontal_pull"),
        ...tail,
      ],
    }
    : {
      name: "Pull",
      objective: "Back, rear shoulders and biceps.",
      slots: [
        main("vertical_pull", "horizontal_pull"),
        main("horizontal_pull"),
        support("rear_delts", "horizontal_pull"),
        ...tail,
      ],
    };
}

const legsTails: Readonly<Record<TailProfile, readonly Slot[]>> = {
  strength: [accessory("calves"), core()],
  size: [accessory("calves"), core(), accessory("quads_isolation")],
  aesthetic: [accessory("calves"), accessory("hamstring_curl"), core()],
  lean: [accessory("calves"), core()],
};

export function legsDay(second: boolean, profile: TailProfile): TemplateDay {
  const tail = legsTails[profile];
  return second
    ? {
      name: "Legs 2",
      objective: "Hinge-led legs with single-leg work and leg accessories.",
      slots: [
        main("hinge"),
        main("squat", "lunge"),
        support("lunge", "squat"),
        support("hamstring_curl", "hinge"),
        ...tail,
      ],
    }
    : {
      name: "Legs",
      objective: "Squat, hinge and single-leg work with leg accessories.",
      slots: [
        main("squat"),
        main("hinge"),
        support("lunge"),
        support("quads_isolation", "squat"),
        support("hamstring_curl", "hinge"),
        ...tail,
      ],
    };
}
