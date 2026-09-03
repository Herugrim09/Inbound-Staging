# Inbound-Staging

Convert an inbound Profit Center payload into MDG staging format and raise a Change Request for it.

Target scenario: **MDG-F (SAP Master Data Governance for Financials)**, flex data model **`0G`**, entity **Profit Center (`PCTR`)** and its texts / hierarchy.

## What it does

A Profit Center replication message arrives at the **inbound BAdI**. The BAdI implementation delegates to this code, which:

1. Maps the inbound proxy structure to the `0G` **staging** structures (`/MDG/_SX_0G_PCTR`, `/MDG/_SX_0G_PCTR_TEXT`, `/MDG/_SX_0G_PCTRH`, …) using the **Service Mapping Tool (SMT)**.
2. Creates a **Change Request** through the **Governance API** (`IF_USMD_GOV_API`), writes the staged entity data into it, checks it, saves it and starts its workflow.

```
inbound proxy structure
        │
        ▼
┌──────────────────────────────────────────────┐
│ [A] Wrapper class  ZCL_MDG_0G_PCTR_WRAPPER    │
│  · map_to_staging()      CL_SMT_ENGINE +      │
│                          inbound mapping      │
│                          Z0G_PCTR_IN          │
│  · create_follow_up_cr() composes [B]         │
└──────────────────────────────────────────────┘
        │  uses
        ▼
┌──────────────────────────────────────────────┐
│ [B] Gov API / follow-up utility              │
│     ZCL_MDG_0G_CR_WRITER                      │
│  create → enqueue_cr → enqueue_entity(key) →  │
│  write_entity(key+attr) → dequeue_entity →    │
│  save(draft) → dequeue_cr → check →           │
│  start_workflow → COMMIT WORK AND WAIT        │
└──────────────────────────────────────────────┘
        │
        ▼
   Change Request + workflow
```

## Components

| Object (proposed name) | Responsibility |
|---|---|
| `ZCL_MDG_0G_PCTR_WRAPPER` | End-to-end inbound handling. `map_to_staging()` = proxy → `0G` staging via SMT. `create_follow_up_cr()` = compose `ZCL_MDG_0G_CR_WRITER` to create the CR, write the data, enqueue, save, check and fire it. |
| `ZCL_MDG_0G_TRANSFORM_IN` | Complex transformation methods referenced by the inbound SMT mapping `Z0G_PCTR_IN`. |
| `ZCL_MDG_0G_CR_WRITER` | Granular `IF_USMD_GOV_API` orchestration in one call (`create_and_fire`): create → enqueue → write per entity → save draft → check → `start_workflow`, plus optional predecessor-link / notes / attachment copy. No proxy-structure knowledge. |
| `ZCL_MDG_0G_PCTR_INB_BADI` | BAdI implementation class — no logic, delegates to the wrapper. The real BAdI interface is added once the inbound service is identified (open decision 2). |

The **inbound BAdI implementation class** holds no logic — it calls `ZCL_MDG_0G_PCTR_WRAPPER`.

The Governance API flow is modeled on the S4E method `create_crequest_acc_company` (extension `E00607`); see [CLAUDE.md](CLAUDE.md) for the full call sequence and confirmed signatures.

## SMT mapping setup

The delivered mapping `USMDZ6_0G_PCTR` maps **staging → replication request (outbound)** and cannot be run in reverse (its complex transformations are one-directional). A **separate inbound mapping** is required.

- **Mapping** `Z0G_PCTR_IN` — one **step per entity type**: `PCTR`, `PCTR_TEXT`, `PCTRH`, optionally `PCTR_CCODE`.
- Each step is a sequence of transformations: **field mappings** (1:1, ALPHA conversions) **+ complex transformations**.
- Inbound complex transformations: split concatenated CO-object `ID` into `COAREA` (offset 0, length 4) + `PCTR` (remainder), language ISO → `SPRAS`, external date → `DATS`, hierarchy parent-node resolution.
- Maintenance: transaction `SM34`, view cluster `VC_SMT_TRANSF`. Test / trace: transaction `MDG_ANALYSE_SMT`.
- Quick start: **Copy** `USMDZ6_0G_PCTR`, swap source/target, remove the directional complex transformations, re-enter the field mappings in the inbound direction.

## Prerequisites

- MDG-F configured for data model `0G` with Profit Center governance.
- `0G` data-model-specific structures generated (`/MDG/_SX_0G_*`).
- Inbound SOA service / BAdI for Profit Center replication active.
- The inbound SMT mapping `Z0G_PCTR_IN` created (see above).

## Repository

- abapGit repository — source under [`/src/`](src/), `FOLDER_LOGIC = PREFIX`, master language `E`.
- No build, lint or test tooling.

## Status

Skeletons in place under [`src/`](src/):

- `ZCL_MDG_0G_CR_WRITER` — `create_and_fire` implemented against the reference call sequence.
- `ZCL_MDG_0G_PCTR_WRAPPER` — `map_to_staging` / `create_follow_up_cr` / `process` implemented; `get_source_rows`, `resolve_cr_type`, `resolve_description` are stubs.
- `ZCL_MDG_0G_TRANSFORM_IN` — `split_co_object`, `lang_iso_to_spras`, `date_ext_to_internal` implemented.
- `ZCL_MDG_0G_PCTR_INB_BADI` — delegate stub; real BAdI interface not yet attached.

Not done: the inbound SMT mapping `Z0G_PCTR_IN`, the proxy-structure extraction in `get_source_rows`, and the open decisions (CR granularity, workflow/commit policy, create-vs-change detection, hierarchy handling, logging strategy, idempotency, CR type/description, parent-CR question) tracked in [CLAUDE.md](CLAUDE.md).
