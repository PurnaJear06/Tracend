// DeepSeek retired V4 Flash on 2026-09-10 and serves DeepSeek-V4.1-Flash as
// `deepseek-flash`. The legacy name `deepseek-v4-flash` is "temporarily routed"
// to the same model (https://api-docs.deepseek.com/updates), so both names are
// accepted until the DEEPSEEK_MODEL secret moves to the new one. Any other name
// keeps the live provider off.
export const approvedDeepseekModels = ["deepseek-flash", "deepseek-v4-flash"] as const;

export function isApprovedDeepseekModel(model: string | null | undefined): boolean {
  return (approvedDeepseekModels as readonly string[]).includes(model ?? "");
}

// DeepSeek-V4.1-Flash list prices in USD per 1M tokens from 04:00 UTC on
// 2026-09-10: peak (weekdays 01:00-04:00 and 06:00-10:00 UTC) input 0.30 on a
// cache miss, output 1.20; off-peak is half. Cost estimates use the peak
// cache-miss price, so the monthly budget guard never undercounts.
export const deepseekFlashPeakPricePerMillionUsd = Object.freeze({ input: 0.3, output: 1.2 });
