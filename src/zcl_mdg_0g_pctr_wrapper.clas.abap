class ZCL_MDG_0G_PCTR_WRAPPER definition
  public
  final
  create public .

************************************************************************
* Project : Inbound-Staging
* Purpose : End-to-end inbound Profit Center handling.
*           map_to_staging()     : proxy payload -> 0G staging tables
*                                  via ZCL_MDG_0G_SRV_MAPPER_* (CL_ABAP_CORRESPONDING)
*           create_follow_up_cr(): staged data   -> Change Request, driven
*                                  step by step through ZIF_MDG_0G_CU
*           process()            : both, in order
************************************************************************
public section.

  types TY_T_STAGING type ZIF_MDG_0G_CU=>TT_BUFFER .

  constants C_ENTITY_PCTR type USMD_ENTITY value 'PCTR' ##NO_TEXT.

    "! Map the inbound Profit Center payload to 0G staging tables (one entry per entity).
  methods MAP_TO_STAGING
    importing
      !IS_REQUEST type ANY
      !IV_EDITION type USMD_EDITION optional
    returning
      value(RT_STAGING) type TY_T_STAGING .
    "! Create the change request from staged data and fire it.
  methods CREATE_FOLLOW_UP_CR
    importing
      !IT_STAGING type TY_T_STAGING
      !IV_SOURCE_CR type USMD_CREQUEST optional
      !IV_COMMIT type ABAP_BOOL default ABAP_FALSE
    exporting
      !EV_CREQUEST type USMD_CREQUEST
      !ET_MESSAGE type USMD_T_MESSAGE .
    "! One shot: map_to_staging + create_follow_up_cr.
  methods PROCESS
    importing
      !IS_REQUEST type ANY
      !IV_SOURCE_CR type USMD_CREQUEST optional
      !IV_COMMIT type ABAP_BOOL default ABAP_TRUE
    exporting
      !EV_CREQUEST type USMD_CREQUEST
      !ET_MESSAGE type USMD_T_MESSAGE .
protected section.
  PRIVATE SECTION.

    CONSTANTS c_default_cr_type TYPE usmd_crequest_type VALUE 'ZPCTAP1' ##NO_TEXT.   " Profit Center inbound CR type

    METHODS resolve_cr_type
      IMPORTING it_staging    TYPE ty_t_staging
      RETURNING VALUE(rv_type) TYPE usmd_crequest_type.

    METHODS resolve_description
      IMPORTING iv_source_cr  TYPE usmd_crequest
      RETURNING VALUE(rv_text) TYPE usmd_txtlg.

ENDCLASS.



CLASS ZCL_MDG_0G_PCTR_WRAPPER IMPLEMENTATION.


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

    ev_crequest = lo_cu->create_crequest(
      iv_crequest_type = resolve_cr_type( it_staging )
      iv_description   = resolve_description( iv_source_cr ) ).
    IF ev_crequest IS INITIAL.
      et_message = lo_cu->get_messages( ).
      RETURN.
    ENDIF.

    lo_cu->enqueue_cr( ).

    LOOP AT it_staging ASSIGNING FIELD-SYMBOL(<ls_stg>).
      lo_cu->write_data( iv_entity = <ls_stg>-entity
                         iv_struct = <ls_stg>-struct
                         ir_data   = <ls_stg>-data ).
    ENDLOOP.

    " only the leading PCTR entity is locked; PCCCASS / texts ride along with it
    lo_cu->enqueue_entity( iv_entity = c_entity_pctr ).

    lo_cu->flush( ).
    lo_cu->save( ).
    lo_cu->commit( iv_commit = iv_commit ).

    et_message = lo_cu->get_messages( ).

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

*   mapper targets (entity + struct + recs) -> CR session buffer rows
    LOOP AT lt_targets ASSIGNING FIELD-SYMBOL(<ls_target>).
      APPEND VALUE #( entity = <ls_target>-entity
                      struct = <ls_target>-struct
                      data   = <ls_target>-recs ) TO rt_staging.
    ENDLOOP.

  ENDMETHOD.


  METHOD resolve_cr_type.
    " Fixed CR type for the inbound scenario (decision 5).
    rv_type = c_default_cr_type.
  ENDMETHOD.


  METHOD resolve_description.
    " TODO: mirror create_crequest_acc_company -> "<source text> / <creator> / <tag>".
    rv_text = |Profit Center inbound { sy-datum } { sy-uzeit }|.
  ENDMETHOD.
ENDCLASS.
