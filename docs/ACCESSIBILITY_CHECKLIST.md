# Manual accessibility checklist

**Status: NOT performed. Manual UAT is REQUIRED before PROD.** Automated checks (axe-core in `tests/e2e/ui-smoke.mjs`: contrast, labels, headings, overflow) pass, but they do not replace the items below. Mark each item only after a person has done it; record tester, date, browser, assistive technology.

| # | Check | How | Result | Tester / date |
|---|---|---|---|---|
| 1 | Keyboard-only: every page reachable and operable (nav, filters, forms, buttons, pager) | Tab/Shift+Tab/Enter/Space/Esc only | ☐ | |
| 2 | Visible focus on every interactive element, logical focus order (matches reading order) | Tab through each screen | ☐ | |
| 3 | Modals/dialogs trap focus, Esc closes, focus returns to trigger | Confirm dialogs, reason prompts, export | ☐ | |
| 4 | Screen-reader names for icon buttons, inputs, selects, tabs (NVDA+Firefox/Chrome, VoiceOver+Safari) | Listen to each control | ☐ | |
| 5 | Tables: header association, row/column navigation, sortable headers announced, pagination state announced | Register, Exceptions, Reports | ☐ | |
| 6 | Validation errors and save/failure messages announced (live region) and tied to the field | Submit empty/invalid forms | ☐ | |
| 7 | Status not conveyed by colour alone (risk/status chips) | Greyscale / forced-colours view | ☐ | |
| 8 | 200% zoom and 390 px width: no clipped content or horizontal page scroll | Browser zoom, device mode | ☐ | |
| 9 | Skip link / landmark navigation (main, nav) works | Screen-reader landmarks | ☐ | |
| 10 | Charts/dashboard tiles have text equivalents | Management Dashboard | ☐ | |
