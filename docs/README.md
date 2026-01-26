# Documentation

This repository’s documentation is split into four “useful” buckets plus two “historical” buckets:

## Structure

```
docs/
├── guides/          # “How do I…?” step-by-step procedures (golden paths)
├── reference/       # Contracts + facts about the system (stable, linkable)
├── runbooks/        # Operational playbooks (release, clean build, recovery)
├── troubleshooting/ # Symptoms → diagnosis → fixes
├── rfcs/            # Pre-decision exploration (field notes, options, trade-offs)
└── decisions/       # ADRs: decisions we’ve made and now live with
```

## Start here

- **Quickstart:** `guides/01-quickstart.md`
- **Build image:** `guides/02-build-image.md`
- **Flash image safely (SYSTEM vs DATA):** `guides/04-flash-system-nvme.md`
- **First boot checklist:** `guides/05-first-boot-checklist.md`
- **Contracts (what the image guarantees):** `reference/contracts.md`
- **Tooling reference:** `reference/tooling.md`

## When to use what

- **Guides**: “do these steps in this order”
- **Reference**: “what is the contract / what is this file / what does this script do”
- **Runbooks**: “operationally, what do we do when X happens”
- **Troubleshooting**: “I saw an error message; what now”

### RFCs vs ADRs

- **RFCs (`rfcs/`)** — pre-decisional exploration and field notes. Good for capturing messy reality.
- **ADRs (`decisions/`)** — decisions that are now part of the project’s long-term constraints.

Conventions:

- Numbering + slugs:
  - `RFC-0001-descriptive-slug.md`
  - `ADR-0001-descriptive-slug.md`
- Status:
  - RFC: `Draft | Discussion | Accepted | Rejected | Withdrawn`
  - ADR: `Proposed | Accepted | Deprecated | Superseded`
