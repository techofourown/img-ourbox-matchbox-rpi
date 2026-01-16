# Documentation

This repository uses a lightweight documentation structure focused on RFCs and ADRs.

## Structure

```
docs/
├── rfcs/          # Pre-decisional exploration and proposals
└── decisions/     # Architecture Decision Records (ADRs)
```

## When to use what

- **RFCs (`rfcs/`)** — explore ideas or proposals before deciding; capture options, trade-offs, and
  open questions.
- **ADRs (`decisions/`)** — record a decision that was made, with context, rationale, consequences,
  and links to any originating RFC.

## Flow

```
Problem or Idea
    ↓
RFC (exploration) → Discussion → Decision
    ↓                              ↓
Implementation               ADR (record)
```

## Conventions

- **Numbering + slugs**: `RFC-0001-descriptive-slug.md` and `ADR-0001-descriptive-slug.md`
  (zero-padded, short hyphenated slug).
- **Status**: RFCs use `Draft | Discussion | Accepted | Rejected | Withdrawn`; ADRs use
  `Proposed | Accepted | Deprecated | Superseded` (with backlinks).
- **Cross-links**: ADRs link to source RFCs/issues and any supersedes/superseded-by records; RFCs
  link to related ADRs when promoted.
- **Change control**: create/update RFCs and ADRs via PRs. Keep them concise; prefer follow-up ADRs
  to massive edits.
