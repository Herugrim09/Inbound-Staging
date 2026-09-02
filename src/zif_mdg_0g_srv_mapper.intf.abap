INTERFACE zif_mdg_0g_srv_mapper
  PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : Contract for an inbound "service mapper": convert one
*           replication-request node into 0G staging records
*           (main entity + texts + dependent sub-entities), driven by
*           CL_ABAP_CORRESPONDING groups instead of SMT.
*           One implementing class per governed entity; callers talk
*           to this interface only (via ZCL_MDG_0G_SRV_MAPPER_FACTORY).
************************************************************************

  TYPES:
    "! One result row: target entity + data reference to its staging table
    BEGIN OF ts_target,
      entity TYPE usmd_entity,
      recs   TYPE REF TO data,
    END OF ts_target,
    tt_target TYPE STANDARD TABLE OF ts_target WITH KEY entity,

    "! One derived key field / value (COAREA, PCTR, ...)
    BEGIN OF ts_keyval,
      field TYPE fieldname,
      value TYPE usmd_value,
    END OF ts_keyval,
    tt_keyval TYPE STANDARD TABLE OF ts_keyval WITH KEY field,

    "! One CL_ABAP_CORRESPONDING group: source sub-structure path + field pairs
    BEGIN OF ts_group,
      src_path TYPE string,
      mapping  TYPE cl_abap_corresponding=>mapping_table,
    END OF ts_group,
    tt_group TYPE STANDARD TABLE OF ts_group WITH DEFAULT KEY.

  "! External entry point - callers use ONLY this method.
  "! @parameter is_message | replication-request node (e.g. MDGF_PRFT_CTR_RPLCTN_REQ_PRFT)
  "! @parameter iv_edition | target edition (context, not a mapped field)
  "! @parameter et_targets | one row per target entity, data typed as its staging structure
  METHODS map
    IMPORTING is_message TYPE any
              iv_edition TYPE usmd_edition
    EXPORTING et_targets TYPE tt_target
    RAISING   zcx_mdg_0g_srv_mapper.

  "! Main entity name (also used as the text entity).
  METHODS get_main_entity
    RETURNING VALUE(rv_entity) TYPE usmd_entity.

  "! Name of the flat main staging structure, e.g. '/MDG/_S_0G_PP_PCTR'.
  METHODS get_main_struct
    RETURNING VALUE(rv_name) TYPE string.

  "! Field mapping rules as CL_ABAP_CORRESPONDING groups.
  METHODS get_corr_groups
    RETURNING VALUE(rt_groups) TYPE tt_group.

  "! Name of the text staging structure, or '' when the entity has no texts.
  METHODS get_text_struct
    RETURNING VALUE(rv_name) TYPE string.

  "! Derive the entity key values from the request message.
  METHODS derive_keys
    IMPORTING is_message     TYPE any
    RETURNING VALUE(rt_keys) TYPE tt_keyval.

  "! Map dependent sub-entities (assignments, ...) into the target list.
  METHODS map_sub_entities
    IMPORTING is_message TYPE any
              it_keys    TYPE tt_keyval
    CHANGING  ct_targets TYPE tt_target.

ENDINTERFACE.
