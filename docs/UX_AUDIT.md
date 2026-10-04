# UX hardening audit (2026-10-04)

Scope: the whole application as built (32 screens). No business logic was changed for UI reasons. Method: an automated audit in the headless-browser test (`tests/e2e/ui-smoke.mjs`, section 7; on by default, `UX_AUDIT=0` skips it locally) plus a code review of states, permissions and request behaviour.

## Automated audit (runs in CI on every push)
For every screen — dashboard, registers, calendar, notifications, reports, all master-data and administration screens, imports, users, roles, export history, jobs, system health — at **desktop 1360px, tablet 768px and phone 390px**:
- no horizontal page scroll, and no horizontal scroll inside the page content area (elements inside deliberately scrollable table regions are exempt);
- a page heading (`h1`) is present;
- no serious or critical **WCAG 2.x A/AA** violations (axe-core) at desktop and phone width;
- no script errors while visiting every screen.

### Findings and fixes
| Finding | Where | Fix |
|---|---|---|
| Text contrast below 4.5:1 for small muted text, success and warning text (e.g. table headers, badges) | design tokens | `muted` #55657a, `ok` #1a7560, `warn` #8f5c0f. Status colours stay semantic; ratios checked on white, the page canvas and their own 10% tints |
| Icon-only account menu button on phones had no accessible name | header | `aria-label="Account menu for <name>"` |
| Horizontally scrollable tables were not reachable by keyboard | reports, dashboard, calendar week view, import previews | scroll wrappers are focusable labelled regions |
| The page content area itself is a scroll container with no focusable content on some screens | layout | `main` is focusable with a visible focus ring and the label "Page content" |
| Inline link distinguished from surrounding text by colour only | Exception Settings | underlined |
| Settings form wider than a phone | Settings | `min-width: 0` on grid children |
| Management dashboard cards pushed the page area wider than a phone | Management view | cards shrinkable; single shrinkable grid column |
Headings and script errors: none found once the audit used the full-permission profile (an early false alarm was the audit running under a restricted test profile).

## Reviewed in code (no defect found unless noted)
| Area | Result |
|---|---|
| Loading / empty / error states | every data screen uses the shared skeleton, empty-state and error-state components; errors show the database message with a retry; the dashboard and reports explain empty scope instead of showing zeros as measured |
| Permission-denied behaviour | routes are guarded by permission (`RequirePermission`); a user without the permission sees the no-permission screen and no data request is made (browser-tested); menus hide entries the user cannot open; buttons for actions the user cannot perform are absent, and the database enforces the same permissions (RLS, role checks) |
| Destructive or hard-to-reverse actions | discard draft, deactivate master/decision, commit/cancel import and removing your own admin access ask for confirmation; disabling a user or job, changing roles/scope/permissions require a typed reason that is audited; exports are logged |
| URL and filter consistency | register and dashboard filters live in the URL (shareable, survive reload); drill-downs carry entity/location/department where the target register supports them; only whitelisted keys become filters |
| Request volume / stale data | queries are cached 30s by default (lookups 60s); polling only for the notification bell (60s), System Health (60s), dashboards (5 min); mutations invalidate the affected queries; the exports and reports read page by page (200 rows) up to 10,000 rows |
| Long tables | all registers are server-driven: page size, sort, search and filters are executed by the database; no screen loads a whole table. Not measured on production-sized data (see `docs/PRODUCTION_READINESS.md`, "can be completed now") |

## Not covered by this audit
- Real-device screen-reader and keyboard walk-through (automated WCAG rules catch roughly a third of issues; a human pass is recommended before go-live).
- Dark mode (not offered), print layouts, browsers other than Chromium.
- Colour-vision checks beyond contrast: statuses always carry a text label, never colour alone.
