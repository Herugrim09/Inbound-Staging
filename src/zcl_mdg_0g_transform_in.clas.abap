CLASS zcl_mdg_0g_transform_in DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : SMT complex transformations for the inbound PCTR mapping
*           (proposed customizing: Z0G_PCTR_IN, step PCTR). Each method
*           is the inverse of one CL_USMDZ6_0G_TRANSFORMATIONS method
*           used by the outbound mapping USMDZ6_0G_PCTR:
*             - split_coobj_id          <- inverse of MAP_CO_OBJECT
*             - split_pc_cc_assignments <- inverse of MAP_PC_CC_ASSIGNMENTS
*           Signatures mirror the outbound methods so the SM34 complex
*           transformation config can wire IMPORTING/EXPORTING parameters
*           to source/target fields by Structure Path the same way.
************************************************************************

  PUBLIC SECTION.

    "! Inverse of CL_USMDZ6_0G_TRANSFORMATIONS=>MAP_CO_OBJECT
    "! (ENCODE_COOBJ_ID). Splits the concatenated CO-object ID into
    "! chart of accounts (offset 0, len 4) + profit center (remainder).
    CLASS-METHODS split_coobj_id
      IMPORTING iv_id     TYPE string
      EXPORTING ev_coarea TYPE char4
                ev_coobj  TYPE usmdz1_pctr
      RAISING   cx_smt_unsuccessful_trans
                cx_smt_fatal_method_error.

    "! Inverse of CL_USMDZ6_0G_TRANSFORMATIONS=>MAP_PC_CC_ASSIGNMENTS.
    "! Converts the proxy COMPANY_ASSIGNMENT[] rows into staging PCCCASS
    "! rows (COMPCODE + PCTRCCASS only - COAREA/PCTR keys are expected to
    "! be filled by a plain field-mapping entry in the same SMT step, not
    "! by this method, same as the outbound side does not set them here).
    "! Confirmed mapping: ACTION_CODE '03' -> PCTRCCASS = abap_false
    "! (unassigned), '04' -> abap_true (assigned).
    CLASS-METHODS split_pc_cc_assignments
      IMPORTING it_company_assignment TYPE mdgf_prft_ctr_rplctn_req_c_tab
      EXPORTING et_assignments        TYPE STANDARD TABLE OF /mdg/_s_0g_pp_pcccass
      RAISING   cx_smt_unsuccessful_trans
                cx_smt_fatal_method_error.

ENDCLASS.



CLASS zcl_mdg_0g_transform_in IMPLEMENTATION.


  METHOD split_coobj_id.

    CLEAR: ev_coarea, ev_coobj.

    " TODO: verify CX_SMT_UNSUCCESSFUL_TRANS constructor in SE24 - the
    " outbound methods build it via CL_USMDZ6_MSG=>ADD_000 + a protocol
    " helper; confirm whether a parameterless RAISE is valid here or a
    " message/protocol is mandatory.
    IF strlen( iv_id ) < 5.
      RAISE EXCEPTION NEW cx_smt_unsuccessful_trans( ).
    ENDIF.

    ev_coarea = iv_id(4).
    CONDENSE ev_coarea.
    ev_coobj  = iv_id+4.

  ENDMETHOD.


  METHOD split_pc_cc_assignments.

    CLEAR et_assignments.

    LOOP AT it_company_assignment ASSIGNING FIELD-SYMBOL(<row>).

      APPEND INITIAL LINE TO et_assignments ASSIGNING FIELD-SYMBOL(<assignment>).

      <assignment>-compcode  = <row>-company_id.
      <assignment>-pctrccass = COND #( WHEN <row>-action_code = '04' THEN abap_true
                                        ELSE abap_false ).

    ENDLOOP.

  ENDMETHOD.


ENDCLASS.
