CLASS zcl_mdg_0g_acc_wrapper DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : End-to-end inbound G/L Account handling - the Account twin
*           of ZCL_MDG_0G_PCTR_WRAPPER.
*           map_to_staging()     : proxy payload -> 0G staging tables
*                                  via ZCL_MDG_0G_SRV_MAPPER_ACC
*                                  (CL_ABAP_CORRESPONDING, no SMT)
*           create_follow_up_cr(): staged data   -> Change Request,
*                                  driven step by step through
*                                  ZIF_MDG_0G_CU (no direct
*                                  IF_USMD_GOV_API call lives here)
*           process()            : both, in order
*
*           NO "COMMIT WORK" is issued in this class - the commit is a
*           parameter (IV_COMMIT) and is executed by ZIF_MDG_0G_CU~COMMIT
*           only when the caller asks for it. Inbound SOA / BAdI callers
*           must leave it ABAP_FALSE and let the SOA runtime commit.
*
*           Entity ACCOUNT is confirmed (outbound SMT mapping
*           USMDZ6_0G_ACCOUNT). The CR type and everything around the
*           dependent entity ACCCCDET are still UNVERIFIED - see the
*           constants below and the caveats in
*           ZCL_MDG_0G_SRV_MAPPER_ACC.
************************************************************************

  PUBLIC SECTION.

    TYPES ty_t_staging TYPE zif_mdg_0g_cu=>tt_buffer.

*   ACCOUNT: confirmed (entity type of the outbound SMT mapping
*   USMDZ6_0G_ACCOUNT). ACCCCDET: documented in CLAUDE.md via the
*   reference method create_crequest_acc_company, none of its staging
*   fields confirmed yet - TODO verify in SE11 / MDGIMG.
    CONSTANTS:
      c_entity_account TYPE usmd_entity VALUE 'ACCOUNT'  ##NO_TEXT,
      c_entity_ccdet   TYPE usmd_entity VALUE 'ACCCCDET' ##NO_TEXT.

    "! Map the inbound G/L Account payload to 0G staging tables (one entry per entity).
    "! @parameter is_request | one Account node of the replication request
    "! @parameter iv_edition | target edition; empty = the CU layer's fallback edition
    METHODS map_to_staging
      IMPORTING is_request        TYPE any
                iv_edition        TYPE usmd_edition OPTIONAL
      RETURNING VALUE(rt_staging) TYPE ty_t_staging.

    "! Create the change request from staged data and fire it.
    "! @parameter iv_source_cr | parent CR, when the payload has one (open decision 3)
    "! @parameter iv_commit    | ABAP_TRUE issues COMMIT WORK AND WAIT in the CU layer;
    "!                           MUST stay ABAP_FALSE inside SOA inbound processing
    METHODS create_follow_up_cr
      IMPORTING it_staging   TYPE ty_t_staging
                iv_source_cr TYPE usmd_crequest OPTIONAL
                iv_commit    TYPE abap_bool DEFAULT abap_false
      EXPORTING ev_crequest  TYPE usmd_crequest
                et_message   TYPE usmd_t_message.

    "! One shot: map_to_staging + create_follow_up_cr.
    METHODS process
      IMPORTING is_request   TYPE any
                iv_source_cr TYPE usmd_crequest OPTIONAL
                iv_commit    TYPE abap_bool DEFAULT abap_true
      EXPORTING ev_crequest  TYPE usmd_crequest
                et_message   TYPE usmd_t_message.

  PROTECTED SECTION.

  PRIVATE SECTION.

*   TODO decision 5: CR type fixed vs. Customizing vs. derived. The
*   reference method create_crequest_acc_company derives it from the
*   Chart of Accounts - that hook is RESOLVE_CR_TYPE below.
*   TODO verify in MDGIMG: Create Change Request Type - 'ZACCAP1' is a
*   placeholder mirroring the PCTR wrapper's 'ZPCTAP1', not a confirmed
*   Customizing entry.
    CONSTANTS c_default_cr_type TYPE usmd_crequest_type VALUE 'ZACCAP1' ##NO_TEXT.

    METHODS resolve_cr_type
      IMPORTING it_staging     TYPE ty_t_staging
      RETURNING VALUE(rv_type) TYPE usmd_crequest_type.

    METHODS resolve_description
      IMPORTING iv_source_cr   TYPE usmd_crequest
      RETURNING VALUE(rv_text) TYPE usmd_txtlg.

    "! Attributes to flag as changed on WRITE_ENTITY for one entity.
    METHODS resolve_attributes
      IMPORTING iv_entity        TYPE usmd_entity
      RETURNING VALUE(rt_attribute) TYPE usmd_ts_fieldname.

ENDCLASS.



CLASS zcl_mdg_0g_acc_wrapper IMPLEMENTATION.


  METHOD process.

    CLEAR: ev_crequest, et_message.

    DATA(lt_staging) = map_to_staging( is_request ).
    IF lt_staging IS INITIAL.
      RETURN.
    ENDIF.

    create_follow_up_cr( EXPORTING it_staging   = lt_staging
                                   iv_source_cr = iv_source_cr
                                   iv_commit    = iv_commit
                         IMPORTING ev_crequest  = ev_crequest
                                   et_message   = et_message ).

  ENDMETHOD.


  METHOD create_follow_up_cr.

    CLEAR: ev_crequest, et_message.

    IF it_staging IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lo_cu) = zcl_mdg_0g_crud=>get_instance( ).

*   TODO decision 3: no parent CR on an external inbound payload ->
*   IV_SOURCE_CR stays empty and the edition falls back inside the CU
*   layer; predecessor link / notes / attachments are not copied.
    ev_crequest = lo_cu->create_crequest(
      iv_crequest_type = resolve_cr_type( it_staging )
      iv_description   = resolve_description( iv_source_cr ) ).
    IF ev_crequest IS INITIAL.
      et_message = lo_cu->get_messages( ).
      RETURN.
    ENDIF.

    lo_cu->enqueue_cr( ).

*   move each mapped row into its Gov API structure (create_ref) and buffer it
    FIELD-SYMBOLS <lt_src> TYPE ANY TABLE.

    LOOP AT it_staging ASSIGNING FIELD-SYMBOL(<ls_stg>).

      IF <ls_stg>-data IS NOT BOUND.
        CONTINUE.
      ENDIF.
      ASSIGN <ls_stg>-data->* TO <lt_src>.
      IF <lt_src> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      DATA(lr_row) = lo_cu->create_ref( iv_entity = <ls_stg>-entity
                                        iv_struct = <ls_stg>-struct
                                        it_data   = <lt_src> ).

      lo_cu->write_data( iv_entity    = <ls_stg>-entity
                         iv_struct    = <ls_stg>-struct
                         ir_data      = lr_row
                         it_attribute = resolve_attributes( <ls_stg>-entity ) ).

    ENDLOOP.

*   only the leading ACCOUNT entity is locked; ACCCCDET / texts ride along
*   with it - same discipline as the PCTR wrapper
    lo_cu->enqueue_entity( iv_entity = c_entity_account ).

*   enqueue_entity(key) -> write_entity(key+attr) -> dequeue_entity(key):
*   FLUSH does the write_entity, so the dequeue belongs after it and
*   before SAVE. Keep this sequence identical in ZCL_MDG_0G_PCTR_WRAPPER.
    lo_cu->flush( ).
    lo_cu->dequeue_entity( iv_entity = c_entity_account ).

    lo_cu->save( ).
    lo_cu->commit( iv_commit = iv_commit ).

    et_message = lo_cu->get_messages( ).

  ENDMETHOD.


  METHOD map_to_staging.

    DATA lt_targets TYPE zif_mdg_0g_srv_mapper=>tt_target.

    TRY.
        zcl_mdg_0g_srv_mapper_factory=>get( c_entity_account )->map(
          EXPORTING is_message = is_request
                    iv_edition = iv_edition
          IMPORTING et_targets = lt_targets ).
      CATCH zcx_mdg_0g_srv_mapper.
        RETURN.                                       " TODO decision 7: logging
    ENDTRY.

*   mapper targets (entity + struct + recs) -> CR session buffer rows
    LOOP AT lt_targets ASSIGNING FIELD-SYMBOL(<ls_target>).
      APPEND VALUE #( entity = <ls_target>-entity
                      struct = <ls_target>-struct
                      data   = <ls_target>-recs ) TO rt_staging.
    ENDLOOP.

  ENDMETHOD.


  METHOD resolve_attributes.

    CLEAR rt_attribute.

*   The PCTR wrapper flags PCTRCCASS on the PCCCASS write so the
*   cross-entity derivation does not rebuild the company-code list and
*   drop the delivered assignments. The Account side very probably needs
*   the same for one or more ACCCCDET attributes.
*   TODO verify in SE11 / MDGIMG: which ACCCCDET attributes a 0G
*   derivation recomputes (MDGIMG -> Data Model 0G -> derivations /
*   BAdI USMD_RULE_SERVICE). Until that is known the list stays empty -
*   writing an unconfirmed field name here would silently mis-flag the
*   write. Add here, e.g.:
*     IF iv_entity = c_entity_ccdet.
*       INSERT '<ATTR>' INTO TABLE rt_attribute.
*     ENDIF.
    RETURN.

  ENDMETHOD.


  METHOD resolve_cr_type.

    " Fixed CR type for the inbound scenario (TODO decision 5).
    " The reference create_crequest_acc_company derives it from the Chart
    " of Accounts - do that here once the CR types are known.
    rv_type = c_default_cr_type.

  ENDMETHOD.


  METHOD resolve_description.

    " TODO: mirror create_crequest_acc_company -> "<source text> / <creator> / <tag>".
    rv_text = |G/L Account inbound { sy-datum } { sy-uzeit }|.

  ENDMETHOD.


ENDCLASS.
