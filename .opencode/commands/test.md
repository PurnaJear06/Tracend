---
description: Run the local quality gates (format, analyze, flutter tests, deno lint/test) and report failures
agent: build
---

Run the Tracend local quality gates in order, stopping at the first failure:

1. `./scripts/flutter.sh format --set-exit-if-changed lib test`
2. `./scripts/flutter.sh analyze`
3. `./scripts/flutter.sh test`
4. `./scripts/deno.sh fmt --check supabase/functions`
5. `./scripts/deno.sh lint supabase/functions`
6. `./scripts/deno.sh test supabase/functions`

Rules:
- Use ONLY the wrapper scripts above. Never invoke flutter/dart/deno directly.
- Do not fix anything yet. Report each gate as pass/fail.
- For failures, list the failing test/file with `file:line` and a one-line cause.
- End with a summary table and the exact command(s) to re-run the failing gate(s).
