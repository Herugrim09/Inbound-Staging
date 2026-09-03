class ZCL_MDG_0G_PCTR_WRAPPER definition
  public
  final
  create private .

************************************************************************
* Project : Inbound-Staging
* Purpose : End-to-end inbound Profit Center handling for a BULK message
*           that the framework splits into one BAdI call per record.
*
*           The wrapper is a singleton (GET_INSTANCE) so its state
*           survives across the BAdI calls of one bulk / one LUW:
*
*           process()            : one record. Maps it and writes the
*                                  rows straight into the ZCL_MDG_0G_CRUD
*                                  session buffer. On the LAST record of
*                                  the bulk it creates + fires ONE CR for
*                                  everything buffered.
*                                  "Last record" = when the number of
*                                  process() calls reaches the message
*                                  count read from the inbound payload
*                                  (count_messages). If that count cannot
*                                  be determined, every call falls back to
*                                  its own CR.
*           map_to_staging()     : proxy payload -> 0G staging tables via
*                                  ZCL_MDG_0G_SRV_MAPPER_* .
*           create_follow_up_cr(): buffer -> Change Request, driven step
*                                  by step through ZIF_MDG_0G_CU.
************************************************************************
public section.

  types TY_T_STAGING type ZIF_MDG_0G_CU=>TT_BUFFER .

  constants C_ENTITY_PCTR type USMD_ENTITY value 'PCTR' ##NO_TEXT.

    "! The one wrapper instance for the current session / bulk.
  class-methods GET_INSTANCE
    returning
      value(RO_INSTANCE) type ref to ZCL_MDG_0G_PCTR_WRAPPER .

    "! Map the inbound Profit Center payload to 0G staging tables (one entry per entity).
  methods MAP_TO_STAGING
    importing
      !IS_REQUEST type ANY
      !IV_EDITION type USMD_EDITION optional
    returning
      value(RT_STAGING) type TY_T_STAGING .
    "! Create the change request and fire it.
    "! IT_STAGING is written into a fresh session first when supplied
    "! (one-shot callers that own the whole session); the BAdI path leaves
    "! it empty and relies on the rows PROCESS( ) has already buffered.
  methods CREATE_FOLLOW_UP_CR
    importing
      !IT_STAGING type TY_T_STAGING optional
      !IV_SOURCE_CR type USMD_CREQUEST optional
      !IV_COMMIT type ABAP_BOOL default ABAP_FALSE
    exporting
      !EV_CREQUEST type USMD_CREQUEST
      !ET_MESSAGE type USMD_T_MESSAGE .
    "! One record of the bulk: buffer it, and on the last record create +
    "! fire one CR for the whole bulk. See class documentation.
    "! COMMIT WORK runs once per bulk - on the last record only, after
    "! save + start_workflow - so IV_COMMIT defaults to ABAP_TRUE.
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
    "! Local name of the repeating message data node in the bulk payload -
    "! one BAdI call per occurrence. Compared uppercased against SMUM_XML_PARSE
    "! output. Adjust if the ESR node name differs (SAPPLCO_ vs MDGF_); the
    "! message-wrapper element name (...REPLICATIONREQUESTMESSAGE) works too.
    CONSTANTS c_msg_node      TYPE string             VALUE 'PROFITCENTRE' ##NO_TEXT.

    CLASS-DATA go_instance TYPE REF TO zcl_mdg_0g_pctr_wrapper.

    "! messages in the current bulk (0 = unknown -> one CR per call)
    DATA mv_total     TYPE i.
    "! PROCESS( ) calls served so far in the current bulk
    DATA mv_seen      TYPE i.
    "! source CR carried from the first record of the bulk
    DATA mv_source_cr TYPE usmd_crequest.

    METHODS resolve_cr_type
      IMPORTING it_staging    TYPE ty_t_staging
      RETURNING VALUE(rv_type) TYPE usmd_crequest_type.

    METHODS resolve_description
      IMPORTING iv_source_cr  TYPE usmd_crequest
      RETURNING VALUE(rv_text) TYPE usmd_txtlg.

    "! Number of C_MSG_NODE elements in the inbound request payload, read
    "! via the payload-analysis protocol; 0 when it cannot be read.
    METHODS count_messages
      RETURNING VALUE(rv_count) TYPE i.

ENDCLASS.



CLASS ZCL_MDG_0G_PCTR_WRAPPER IMPLEMENTATION.


  METHOD get_instance.
    IF go_instance IS NOT BOUND.
      go_instance = NEW #( ).
    ENDIF.
    ro_instance = go_instance.
  ENDMETHOD.


  METHOD process.

    CLEAR: ev_crequest, et_message.

    DATA(lo_cu) = zcl_mdg_0g_crud=>get_instance( ).

*   --- first record of a new bulk: reset the session, size the bulk ---
    IF mv_seen = 0.
      lo_cu->clear_buffers( ).
      mv_source_cr = iv_source_cr.
      mv_total     = count_messages( ).
*     TODO decision 9: also key the reset on the bulk MESSAGE_HEADER-ID so a
*     dump mid-bulk cannot leak buffered rows into the next transmission.
    ENDIF.

*   --- map this record straight into the CR session buffer ---
    DATA(lt_staging) = map_to_staging( is_request ).
    LOOP AT lt_staging ASSIGNING FIELD-SYMBOL(<ls_stg>).
      lo_cu->write_data( iv_entity = <ls_stg>-entity
                         iv_struct = <ls_stg>-struct
                         ir_data   = <ls_stg>-data ).
    ENDLOOP.
    ADD 1 TO mv_seen.

*   --- more records of this bulk still to come ---
    IF mv_total > 0 AND mv_seen < mv_total.
      RETURN.
    ENDIF.

*   --- last record (or unknown count): one CR for everything buffered ---
    create_follow_up_cr( EXPORTING iv_source_cr = mv_source_cr
                                   iv_commit    = iv_commit
                         IMPORTING ev_crequest  = ev_crequest
                                   et_message   = et_message ).

*   --- ready for the next bulk in this session ---
    CLEAR: mv_seen, mv_total, mv_source_cr.

  ENDMETHOD.


  METHOD create_follow_up_cr.

    CLEAR: ev_crequest, et_message.

    DATA(lo_cu) = zcl_mdg_0g_crud=>get_instance( ).

*   one-shot callers hand the staged rows in here and own the whole session;
*   the BAdI path leaves IT_STAGING empty - PROCESS( ) has already buffered
*   the bulk into the session via write_data
    IF it_staging IS NOT INITIAL.
      lo_cu->clear_buffers( ).
      LOOP AT it_staging ASSIGNING FIELD-SYMBOL(<ls_stg>).
        lo_cu->write_data( iv_entity = <ls_stg>-entity
                           iv_struct = <ls_stg>-struct
                           ir_data   = <ls_stg>-data ).
      ENDLOOP.
    ENDIF.

    ev_crequest = lo_cu->create_crequest(
      iv_crequest_type = resolve_cr_type( it_staging )
      iv_description   = resolve_description( iv_source_cr ) ).
    IF ev_crequest IS INITIAL.
      et_message = lo_cu->get_messages( ).
      RETURN.
    ENDIF.

    lo_cu->enqueue_cr( ).

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


  METHOD count_messages.

*   Reads the whole inbound request payload (not just this record's node),
*   flattens it with SMUM_XML_PARSE and counts the C_MSG_NODE rows = number
*   of BAdI calls to expect. Any failure -> 0 -> PROCESS( ) falls back to
*   one CR per call.
    DATA lt_xml    TYPE STANDARD TABLE OF smum_xmltb.
    DATA lt_return TYPE STANDARD TABLE OF bapiret2.

    TRY.
        DATA(lo_pl) = CAST if_wsprotocol_payload(
          cl_proxy_access=>get_server_context( )->get_protocol( if_wsprotocol=>payload ) ).

        " provider side: the request as the sender sent it
        DATA(lv_xml) = lo_pl->get_sent_request_payload( )->get_xml_binary( ).
        IF lv_xml IS INITIAL.
          RETURN.
        ENDIF.

        CALL FUNCTION 'SMUM_XML_PARSE'
          EXPORTING
            xml_input = lv_xml
          IMPORTING
            xml_table = lt_xml
            return    = lt_return.

        LOOP AT lt_xml ASSIGNING FIELD-SYMBOL(<ls_xml>).
          IF to_upper( <ls_xml>-cname ) = c_msg_node.
            ADD 1 TO rv_count.
          ENDIF.
        ENDLOOP.

      CATCH cx_root.
        CLEAR rv_count.                                  " payload not readable -> unknown
    ENDTRY.

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
