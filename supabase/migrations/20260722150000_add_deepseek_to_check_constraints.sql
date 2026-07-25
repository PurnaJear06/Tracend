alter table public.model_runs drop constraint model_runs_provider_check;
alter table public.model_runs add constraint model_runs_provider_check
  check (provider in ('mock','gemini','groq','deepseek'));

alter table public.ai_usage_events drop constraint ai_usage_events_provider_check;
alter table public.ai_usage_events add constraint ai_usage_events_provider_check
  check (provider in ('gemini','groq','deepseek'));

alter table public.ai_usage_events drop constraint ai_usage_events_model_check;
alter table public.ai_usage_events add constraint ai_usage_events_model_check
  check (model in ('gemini-3.5-flash','qwen/qwen3.6-27b','deepseek-v4-flash'));
