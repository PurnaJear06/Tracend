# Phase 8 Notification Privacy Slice

Phase 7 owner QA completed when the ready weekly review opened and persisted
acknowledgement on the installed iPhone build.

Phase 8 begins with an independently complete notification-privacy slice.
Account now reads real iOS authorization/pending-request state and offers daily
check-in and weekly-review reminders. Permission is requested only when an
enabled configuration is saved. Native scheduled content is deliberately
generic and contains no sensitive category or value.

Migration `20260703090000` adds forced-RLS notification preferences and a
validated owner RPC. The server retains only toggles, coarse authorization
state, and append-only `notifications-v1` grant/withdrawal evidence. Flutter
passes 51/51 with clean analysis; the ten-file database suite passes 210/210.
The local CLI database reset path intermittently timed out on the host port, so
the same forward migrations were applied to the repository-local database via
its SSD-backed container before the authoritative pgTAP runner passed. No
simulator or notification SDK was used. Hosted deployment and signed owner
device QA remain pending explicit approval.

Approval followed. The hosted dry-run listed only `20260703090000`; deployment
succeeded and migration histories match. The hosted-config signed 19 MB build
passed strict code-sign verification, installed on the paired iPhone 12, and
launched by CLI. Owner permission/toggle persistence QA remains.

Encrypted media-inclusive export is the next Phase 8 slice. Account deletion
will be tested end to end against a synthetic hosted account before the owner
control is enabled.

Owner reopen QA then showed the reminder controls reset. The client was loading
only iOS pending requests even though the forced-RLS server preference was the
durable record. Loading now reconciles that durable record back into iOS when
permission remains authorized, and deliberately does not reschedule after
permission denial. Flutter passes 53/53, analysis and formatting are clean, and
the unsigned 19 MB physical-device build passes. The first signing retry used
an obsolete Yahoo-associated team and failed. Local identity/profile inspection
identified the already-valid Gmail development identity and active team. The
hosted-config replacement then passed strict signing verification, installed,
and launched on the owner's iPhone without another login.

The replacement still reset after reopen. Pending `UNNotificationRequest`
objects were therefore incorrectly serving both as delivery state and local
preference storage. Native `UserDefaults` now persists only the two requested
booleans, authorized startup repairs missing requests from those values, and
schedule completion errors are returned instead of silently accepted. Flutter
remains 53/53 with clean analysis; the 19 MB unsigned physical-device build
passes. A new hosted-config signed install is required for final reopen QA.

The new hosted-config build passed strict signing verification, installed over
the existing bundle, and launched successfully on the paired iPhone. Final QA
is to save both toggles, force-close, reopen, and confirm both remain enabled.
