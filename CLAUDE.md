# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Inbound-Staging** — convert an inbound SOA/BAdI **Profit Center** payload (MDG-F, flex data model `0G`) into MDG **staging** format and raise / fire a Change Request for it via the Governance API.

Runtime entry point is the **inbound BAdI** for Profit Center replication. The BAdI implementation holds no logic — it calls the wrapper class in this repository.

## Repository layout

- abapGit repository, `FOLDER_LOGIC = PREFIX`, master language `E`, source under `/src/`.
- No build / lint / test tooling. Objects move through abapGit + the ABAP system; there are no local commands.
- Package text: "Inbound to Staging Repo". Object name prefix: `Z` (final package/namespace TBD).

## Architecture

Data flow: `inbound proxy structure → [A] wrapper: map to 0G staging → [A] wrapper: create + fill + fire CR (via [B]) → Change Request → workflow`

### [A] Wrapper / SMT mapper class  (proposed: `ZCL_MDG_0G_PCTR_WRAPPER`)
Owns the end-to-end inbound handling. Two responsibilities, two method groups:
- **Mapping** — `map_to_staging( is_request ) RETURNING rt_staging` : inbound proxy structure → `0G` staging structures, driving `CL_SMT_ENGINE` with the inbound SMT mapping (see below). One engine per entity, cached. Output: table of `{ entity TYPE usmd_entity, data TYPE REF TO data }` where `data` is the matching `/MDG/_SX_0G_*` table.
- **Follow-up CR** — `create_follow_up_cr( it_staging [ iv_source_cr ] ) EXPORTING ev_crequest et_message` : composes the granular methods of `[B]` to create a CR, write the staged data into it, run the enqueue/dequeue dance, save, check and fire it. Modeled on the reference method below.

Target entities: `PCTR` (`/MDG/_SX_0G_PCTR`), `PCTR_TEXT`, `PCTRH` (hierarchy node + relationship), company-code assignment if governed.

### [B] Governance API / follow-up utility class  (proposed: `ZCL_MDG_0G_CR_WRITER`)
Granular, reusable wrappers around single `IF_USMD_GOV_API` calls, each with standardized exception handling / message collection. No proxy-structure knowledge. Proposed methods:
- `get_api( ) RETURNING ri_gov_api` — `cl_usmd_gov_api=>get_instance( iv_model_name = '0G' )`, cached.
- `read_cr_attributes( iv_crequest_id ) RETURNING rs_attr` — `get_crequest_attributes`; yields `usmd_edition / usmd_creq_type / usmd_creq_text / usmd_created_by / usmd_reason`.
- `build_refs( iv_entity_name ) EXPORTING er_key_tab er_key_attr_tab` — two `create_data_reference` calls (`gc_struct_key`, `gc_struct_key_attr`).
- `create( iv_crequest_type iv_description iv_edition ) RETURNING ev_crequest`.
- `enqueue_cr` / `dequeue_cr( iv_crequest_id )`.
- `write_entity_data( iv_crequest_id iv_entity_name it_key it_key_attr )` — `enqueue_entity` (key) → `write_entity` (key+attr) → `dequeue_entity` (key).
- `link_predecessor( iv_new iv_predecessor )` / `copy_notes( iv_from iv_to )` / `copy_attachments( iv_from iv_to )` — **only when a parent CR exists**; see open decision 3.
- `save_draft( iv_crequest_id )` — `save( i_mode = if_usmd_ui_services=>gc_save_mode_draft_no_check )`.
- `check( iv_crequest_id )` — `check_crequest_data`.
- `fire( iv_crequest_id )` — `if_usmd_gov_api_process~start_workflow`.
- Caller does `COMMIT WORK AND WAIT` once, after `fire`.

### Inbound BAdI implementation class
Delegates to `[A]`: `map_to_staging( )` then `create_follow_up_cr( )`. Returns `ev_crequest` + `et_message` to the BAdI signature.

## Follow-up CR creation — reference pattern

Model the `[B]` methods and `[A].create_follow_up_cr` on the S4E method **`create_crequest_acc_company`** (extension `E00607`, model `0G`, entity Accounting/CompanyCode `ACCCCDET`). It creates a follow-up CR from an existing CR and copies context into it. Canonical call sequence:

1. `cl_usmd_model=>get_instance( IMPORTING eo_instance = lri_model )` — model instance, needed for the CR-master predecessor link.
2. App context: `cl_usmd_app_context=>get_context( )`; if `mv_crequest_id` differs → `discard_context( )` then `init_context( iv_crequest_id = <source cr> )`.
3. Read staging of the source CR: `lri_context->mo_model->read_entity_data_all( EXPORTING i_fieldname = <entity> if_active = abap_false i_crequest = <source cr> IMPORTING et_data_entity = lt_data )`. Result keyed by `usmd_entity / usmd_entity_cont / struct`; payload at `-r_t_data->*`. Empty ⇒ nothing to do, `RETURN`.
4. `lri_gov_api = cl_usmd_gov_api=>get_instance( iv_model_name = '0G' )` — `CATCH cx_usmd_gov_api` (`lrcx->mt_messages`).
5. `lri_gov_api->get_crequest_attributes( EXPORTING iv_crequest_id = <source cr> RECEIVING rs_crequest = lwa_crequest )` — read `usmd_edition`, `usmd_creq_type`, `usmd_creq_text`, `usmd_created_by`.
6. `lri_gov_api->create_data_reference( EXPORTING iv_entity_name = <entity> iv_struct = lri_gov_api->gc_struct_key_attr IMPORTING er_structure = .. er_table = .. )` — and again with `gc_struct_key`.
7. Build the CR description, e.g. `<source text> / <creator name> / <segment tag>`.
8. Derive CR type (reference: from Chart of Accounts via `CASE`).
9. Per target CR:
   - `lfd_crequest_id = lri_gov_api->create_crequest( iv_crequest_type = .. iv_description = .. iv_edition = lwa_crequest-usmd_edition )` — `CATCH cx_usmd_gov_api`.
   - `lri_gov_api->enqueue_crequest( EXPORTING iv_crequest_id = lfd_crequest_id )`.
   - `MOVE-CORRESPONDING` staged rows into the **key** table → `lri_gov_api->enqueue_entity( EXPORTING iv_crequest_id = .. iv_entity_name = <entity> it_data = <key tab> )` — `CATCH cx_usmd_gov_api_entity_lock`.
   - `MOVE-CORRESPONDING` staged rows into the **key+attr** table → `lri_gov_api->write_entity( EXPORTING iv_crequest_id = .. iv_entity_name = <entity> it_data = <key+attr tab> )` — `CATCH cx_usmd_gov_api_entity_write`.
   - `lri_gov_api->dequeue_entity( iv_crequest_id = .. iv_entity_name = <entity> it_data = <key tab> )`.
   - **Predecessor link (parent-CR only):** `lri_model->read_char_value( EXPORTING i_fieldname = usmd0_cs_fld-crequest it_sel = <range on new cr> IMPORTING et_data = lt_cr )`; set `usmd_crequest_re = <source cr>` and `usmd_reason = <source reason>`; `lri_model->write_char_value( EXPORTING i_fieldname = usmd0_cs_fld-crequest it_data = lt_cr )`.
   - **Notes (parent-CR only):** `get_notes( iv_crequest_id = <source cr> )` → loop `write_note( iv_crequest_id = <new> iv_note = <..>-usmd_note )`.
   - **Attachments (parent-CR only):** `get_attachment_list( iv_crequest_id = <source cr> if_with_content = abap_true )` → loop `add_attachment( iv_crequest_id = <new> is_attachment = <..>-data )`.
   - `lri_gov_api->save( i_mode = if_usmd_ui_services=>gc_save_mode_draft_no_check )`.
   - `lri_gov_api->dequeue_crequest( EXPORTING iv_crequest_id = lfd_crequest_id )`.
   - `lri_gov_api->check_crequest_data( iv_crequest_id = lfd_crequest_id )` — `CATCH cx_usmd_gov_api_core_error`, `cx_usmd_gov_api`.
   - `lri_gov_api->if_usmd_gov_api_process~start_workflow( EXPORTING iv_crequest_id = lfd_crequest_id )` — `CATCH cx_usmd_gov_api_core_error`.
10. `COMMIT WORK AND WAIT.` after the loop.

**S4E-specific in the reference, likely NOT needed for our inbound case:** BRF-based approver selection (`/s4e/cl_p40_mdg_fi_agnt_select`), splitting one source CR into several follow-ups per approver group, and — if the inbound payload has no parent CR — the predecessor link / notes / attachment copy (step 9 sub-bullets marked *parent-CR only*). The S4E application logger (`/s4e/cl_p40_mdg_0g_logging`) is not in this repo; pick our own logging / message-return strategy (open decision 7).

## Key API signatures (confirmed from the reference; still spot-check in SE24)

`CL_SMT_ENGINE`
- `CONSTRUCTOR( i_mapping TYPE smt_map i_mapping_step TYPE smt_mapping_step )`.
- `execute( EXPORTING i_source TYPE any [ i_add1 i_add2 TYPE any ] CHANGING ch_target TYPE any )` — raises `cx_smt_customizing_error`, `cx_smt_no_class`, `cx_smt_no_entry`, `cx_smt_no_method`, `cx_smt_transformation_error`.

`IF_USMD_GOV_API` (implements `_CR_DATA`, `_CR_ACTION`, `_ENTITY`, `_PROCESS`, `_TRANS`, `_SERVICES`)
- `cl_usmd_gov_api=>get_instance( iv_classname = 'CL_USMD_GOV_API' iv_model_name = '0G' ) → ro_gov_api` — raises `cx_usmd_gov_api` (messages in `mt_messages`).
- `get_crequest_attributes( EXPORTING iv_crequest_id RECEIVING rs_crequest )` — `rs_crequest` carries `usmd_edition / usmd_creq_type / usmd_creq_text / usmd_created_by / usmd_reason`.
- `create_data_reference( EXPORTING iv_entity_name TYPE usmd_entity iv_struct IMPORTING er_structure TYPE REF TO data er_table TYPE REF TO data )`; `iv_struct` = `gc_struct_key` | `gc_struct_key_attr` (constants on the instance).
- `create_crequest( iv_crequest_type TYPE usmd_crequest_type iv_description TYPE usmd_txtlg iv_edition TYPE usmd_edition ) RETURNING rv_crequest_id TYPE usmd_crequest` — raises `cx_usmd_gov_api`.
- `enqueue_crequest( EXPORTING iv_crequest_id )` / `dequeue_crequest( EXPORTING iv_crequest_id )`.
- `enqueue_entity( EXPORTING iv_crequest_id iv_entity_name TYPE usmd_entity it_data TYPE ANY TABLE )` — raises `cx_usmd_gov_api_entity_lock`.
- `write_entity( EXPORTING iv_crequest_id iv_entity_name it_data [ it_attribute TYPE usmd_ts_fieldname ] )` — raises `cx_usmd_gov_api_entity_write`.
- `dequeue_entity( iv_crequest_id iv_entity_name it_data )`.
- `get_notes( iv_crequest_id ) → usmd_t_crequest_note` · `write_note( iv_crequest_id iv_note )`.
- `get_attachment_list( iv_crequest_id if_with_content ) → list` · `add_attachment( iv_crequest_id is_attachment )`.
- `check_crequest_data( iv_crequest_id )` — raises `cx_usmd_gov_api_core_error`, `cx_usmd_gov_api`.
- `save( i_mode )` — reference uses `if_usmd_ui_services=>gc_save_mode_draft_no_check`.
- `if_usmd_gov_api_process~start_workflow( EXPORTING iv_crequest_id )` — raises `cx_usmd_gov_api_core_error`.

`IF_USMD_MODEL` (for the CR-master predecessor link)
- `cl_usmd_model=>get_instance( IMPORTING eo_instance )`.
- `read_char_value( EXPORTING i_fieldname = usmd0_cs_fld-crequest it_sel TYPE usmd_ts_sel IMPORTING et_data )` · `write_char_value( EXPORTING i_fieldname = usmd0_cs_fld-crequest it_data )`. CR-master fields: `usmd_crequest_re` (predecessor), `usmd_reason`.

`CL_USMD_APP_CONTEXT` — `get_context( )` / `discard_context( )` / `init_context( iv_crequest_id )`.

Model constant: `if_usmdz_cons_general=>gc_model_default` = `'0G'`.

## SMT mapping (Customizing — must be created by us)

`USMDZ6_0G_PCTR` / step `PCTR` maps **staging → replication request (outbound)** and cannot be run in reverse — its complex transformations (`CL_USMDZ6_0G_TRANSFORMATIONS=>MAP_CO_OBJECT`) are one-directional.

Create a **separate inbound mapping** (proposed `Z0G_PCTR_IN`):
- **One mapping, one step per entity type** (`PCTR`, `PCTR_TEXT`, `PCTRH`, optionally `PCTR_CCODE`).
- Each step = ordered transformations: **field mappings** (1:1, ALPHA conversions — team) **+ complex transformations** (built jointly).
- Inbound complex transformations: split concatenated CO-object `ID` → `COAREA` (offset 0 len 4) + `PCTR` (remainder, ALPHA); language ISO → `SPRAS`; external/ISO date → `DATS`; hierarchy parent-node resolution + relationship type.
- Transformation class: mirror `CL_USMDZ6_0G_TRANSFORMATIONS` — plain class, no mandatory interface; `IMPORTING` params from source fields, `EXPORTING` params to target fields, `CHANGING ch_target` for the whole structure, `I_ADD1`/`I_ADD2` for extra context. Proposed: `ZCL_MDG_0G_TRANSFORM_IN`.
- Maintain via `SM34` → view cluster `VC_SMT_TRANSF`; test/trace via `MDG_ANALYSE_SMT`. Practical start: **Copy** `USMDZ6_0G_PCTR`, swap source/target, drop the directional complex transformations, keep field mappings reversed.

## Open design decisions (not yet fixed)

1. What the orchestration method does "directly" — pure delegate vs. bypass workflow / auto-activate.
2. Exact inbound service interface + enhancement spot for Profit Center; message type name.
3. **Parent CR?** The reference is a *follow-up of an existing CR* (inherits edition, reason, notes, attachments, predecessor link). An inbound-from-external payload may have **no** parent CR → decide edition sourcing (active edition lookup vs. blank) and drop the inherit steps.
4. CR granularity: one CR per inbound message vs. per Profit Center (the reference loops one CR per approver group — S4E-specific). *Current code:* the bulk framework calls the BAdI once per record; `ZCL_MDG_0G_PCTR_WRAPPER` (singleton) buffers all records into the `ZCL_MDG_0G_CRUD` session and fires **one CR per bulk** on the last call, where "last" = `process()` call count reaching the payload message count from `count_messages( )` (reads the inbound request via `if_wsprotocol=>payload`, flattens it with `SMUM_XML_PARSE`, counts `c_msg_node` rows; falls back to one CR per record when unreadable). `flush` / `save` / `start_workflow` / `COMMIT WORK AND WAIT` run once, on that last call (`iv_commit` defaults to `abap_true`) — so the per-record mid-stream commit that the BP inbound BAdI is faulted for does not apply here. `iv_commit` defaults to `abap_false` so the SOA framework's LUW owns the `COMMIT WORK`.
5. CR type: fixed, from Customizing, or derived (reference derives from Chart of Accounts).
6. Create vs. Change: existence check on `PRCTR` (active area / key mapping) before writing.
7. Logging / error strategy: own application-log object vs. returning `et_message` vs. raising `cx_bs_soa_badi_processing` on the confirmation. (`/s4e/cl_p40_mdg_0g_logging` is not available here.)
8. Whether hierarchy (`PCTRH`) goes into the same CR.
9. Idempotency on message redelivery.
10. Whether `start_workflow` alone is enough to fully approve/activate, or a follow-up `finalize_process_step` / auto-approval CR type config is required.

## Reference material

- **`create_crequest_acc_company`** (S4E `E00607`) — canonical follow-up CR creation via `IF_USMD_GOV_API` (see sequence above). Reuse the call order and exception handling; leave out the S4E BRF approver routing and the parent-CR inherit steps unless decision 3 keeps them.
- **`ZCL_MDG_SE_BP_BULK_REPLRQ_IN`** (Business Partner inbound BAdI) — pattern source for the `CL_SMT_ENGINE` wrapper and per-entity engine caching. Do **not** carry over its known issues: `gt_entity_diff` keyed only by entity (silent `INSERT` failure for multi-record entities), always using `gt_address_keys[ 1 ]`, dump-prone Gov API error handlers, `COMMIT WORK` inside SOA inbound processing.
