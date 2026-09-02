CLASS zcl_mdg_0g_pctr_wrapper DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : End-to-end inbound Profit Center handling.
*           map_to_staging()     : proxy payload -> 0G staging tables
*                                  via ZCL_MDG_0G_SRV_MAPPER_* (CL_ABAP_CORRESPONDING)
*           create_follow_up_cr(): staged data   -> Change Request (ZCL_MDG_0G_CR_WRITER)
*           process()            : both, in order
************************************************************************

  PUBLIC SECTION.

    TYPES ty_t_staging TYPE zcl_mdg_0g_cr_writer=>ty_t_staging.

    CONSTANTS c_entity_pctr TYPE usmd_entity VALUE 'PCTR' ##NO_TEXT.

    "! Map the inbound Profit Center payload to 0G staging tables (one entry per entity).
    METHODS map_to_staging
      IMPORTING is_request       TYPE any
                iv_edition       TYPE usmd_edition OPTIONAL
      RETURNING VALUE(rt_staging) TYPE ty_t_staging.

    "! Create the follow-up CR from staged data and fire it.
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
                iv_commit    TYPE abap_bool DEFAULT abap_false
      EXPORTING ev_crequest  TYPE usmd_crequest
                et_message   TYPE usmd_t_message.

  PRIVATE SECTION.

    CONSTANTS c_default_cr_type TYPE usmd_crequest_type VALUE 'ZP_PCTR01' ##NO_TEXT.   " TODO decision 5

    METHODS resolve_cr_type
      IMPORTING it_staging    TYPE ty_t_staging
      RETURNING VALUE(rv_type) TYPE usmd_crequest_type.

    METHODS resolve_description
      IMPORTING iv_source_cr  TYPE usmd_crequest
      RETURNING VALUE(rv_text) TYPE usmd_txtlg.

ENDCLASS.



CLASS zcl_mdg_0g_pctr_wrapper IMPLEMENTATION.


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

    NEW zcl_mdg_0g_cr_writer( )->create_and_fire(
      EXPORTING it_staging       = it_staging
                iv_crequest_type = resolve_cr_type( it_staging )
                iv_description   = resolve_description( iv_source_cr )
                iv_source_cr     = iv_source_cr
                iv_commit        = iv_commit
      IMPORTING ev_crequest      = ev_crequest
                et_message       = et_message ).

  ENDMETHOD.


  METHOD map_to_staging.

    DATA lt_targets TYPE zif_mdg_0g_srv_mapper=>tt_target.

    TRY.
        zcl_mdg_0g_srv_mapper_factory=>get( c_entity_pctr )->map(
          EXPORTING is_message = is_request
                    iv_edition = iv_edition
          IMPORTING et_targets = lt_targets ).
      CATCH zcx_mdg_0g_srv_mapper.
        RETURN.                                       " TODO decision 7: logging
    ENDTRY.

*   ZIF_MDG_0G_SRV_MAPPER~TS_TARGET (entity + recs) -> CR writer staging (entity + data)
    LOOP AT lt_targets ASSIGNING FIELD-SYMBOL(<ls_target>).
      APPEND VALUE #( entity = <ls_target>-entity
                      data   = <ls_target>-recs ) TO rt_staging.
    ENDLOOP.

  ENDMETHOD.


  METHOD resolve_cr_type.
    " TODO (decision 5): fixed / from Customizing / derived (segment, CoA, ...).
    rv_type = c_default_cr_type.
  ENDMETHOD.


  METHOD resolve_description.
    " TODO: mirror create_crequest_acc_company -> "<source text> / <creator> / <tag>".
    rv_text = |Profit Center inbound { sy-datum } { sy-uzeit }|.
  ENDMETHOD.


ENDCLASS.
