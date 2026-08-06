# Codex task templates for INSTAHAM

Use one task per coherent change. Avoid combining UI redesign, schema design, ML integration, and backend work in one prompt.

## Focused UI change

```text
Update only [screen/widget paths] to match [specific reference path or screenshot].

In scope:
- [concrete visual or interaction changes]
- [responsive/accessibility criteria]

Out of scope:
- Database schema changes
- Navigation changes outside these screens
- ML service changes
- Refactors of unrelated widgets

Acceptance criteria:
- [observable behavior 1]
- [observable behavior 2]
- Existing tests still pass

Run dart format on changed files, flutter analyze, and the closest targeted widget tests.
```

## Focused Drift change

```text
Implement only the local persistence needed for [specific entity/use case].

In scope:
- [table/column/query]
- DAO or repository method
- Migration and database tests

Out of scope:
- UI redesign
- Backend synchronization
- Speculative tables for future features
- ML pipeline changes

Acceptance criteria:
- schemaVersion incremented when required
- explicit migration included
- generated Drift output refreshed
- targeted tests prove create/read/update/delete behavior
```

## UI-to-database integration

```text
Connect [one screen/flow] to the existing database API.
Do not redesign other screens or change the schema unless a listed acceptance criterion requires it.

Acceptance criteria:
- [write event]
- [read/update event]
- cancellation and failure behavior
- no abandoned draft records
- loading/error state is recoverable
- targeted widget and database tests pass
```

## Review-only task

```text
Review [specific commit/diff/files] for correctness. Do not edit files.
Prioritize functional bugs, data loss, privacy, calibration math, architecture violations, and missing tests.
Return findings with file and line references, then a minimal repair order.
```
