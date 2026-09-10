CLASS zcl_mdg_0g_srv_mapper_acc DEFINITION
  PUBLIC
  INHERITING FROM zcl_mdg_0g_srv_mapper
  FINAL
  CREATE PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : Inbound service mapper for G/L Account (0G entity ACCOUNT).
*           Counterpart of ZCL_MDG_0G_SRV_MAPPER_PCTR: supplies the
*           entity handshake and the field mapping rules only. The
*           engine (CL_ABAP_CORRESPONDING groups, RESOLVE_PATH,
*           SET_KEYS, RUN_GROUP, the corr cache) stays in the base class
*           ZCL_MDG_0G_SRV_MAPPER and is not repeated here.
*
*           Working structure: /MDG/_SX_0G_ACCOUNT - the source
*           structure of the outbound SMT mapping USMDZ6_0G_ACCOUNT.
*           The mapper does NOT build the Gov API structure itself:
*           ZIF_MDG_0G_CU~CREATE_REF calls
*           IF_USMD_GOV_API~CREATE_DATA_REFERENCE for the entity and
*           moves our rows in with CORRESPONDING #( it_data ) - checked
*           in ZCL_MDG_0G_CRUD->CREATE_REF, and that MOVE-CORRESPONDING
*           is the ONLY bridge between the two structures. Consequence:
*           a component only arrives in the change request when it is
*           named identically in /MDG/_SX_0G_ACCOUNT and in the
*           generated Gov API structure. Both are generated from the
*           same 0G model, so the names should line up - but a rename
*           on either side fails silently, without a message.
*
*           STATUS OF THE NAMES USED HERE
*           - CONFIRMED (read off the outbound SMT mapping
*             USMDZ6_0G_ACCOUNT, entity type ACCOUNT, package group
*             USMDZ6): the entity name, the working structure, the key
*             fields COA + ACCOUNT, the attributes ACCDEL / ACCBLCREA /
*             ACCGRPACC / FSIACC / ACCBLPLAN / ACCBLPOST / ACCPLTYP, the
*             text fields TXTLG / TXTSH / LANGU in the same structure,
*             and USMD_ACTIONCODE.
*           - NOT CONFIRMED: every path into the inbound proxy message
*             SAPPLCO_GLACCT_MSTR_RPLCTNRQ (single banner-marked block
*             below) and everything about the dependent entity
*             ACCCCDET. The outbound mapping targets FINBCO_* nodes,
*             the inbound BAdI delivers SAPPLCO_* - parallel, but NOT
*             the same names, and the outbound names are relative to a
*             sub-node rather than to the message root. They are used
*             below only as a starting guess, never as a fact.
************************************************************************

  PUBLIC SECTION.

    " interface methods keep their PUBLIC visibility from the base class
    METHODS:
      zif_mdg_0g_srv_mapper~get_main_entity  REDEFINITION,
      zif_mdg_0g_srv_mapper~get_main_struct  REDEFINITION,
      zif_mdg_0g_srv_mapper~get_corr_groups  REDEFINITION,
      zif_mdg_0g_srv_mapper~get_text_struct  REDEFINITION,
      zif_mdg_0g_srv_mapper~derive_keys      REDEFINITION,
      zif_mdg_0g_srv_mapper~map_sub_entities REDEFINITION.

  PROTECTED SECTION.

    METHODS finalize_main REDEFINITION.

    "! Redefined because the base builder targets TXTMI, which does not
    "! exist in /MDG/_SX_0G_ACCOUNT - the confirmed text fields are
    "! TXTLG / TXTSH / LANGU. The base class stays untouched.
    METHODS build_texts REDEFINITION.

  PRIVATE SECTION.

*   one indicator conversion: source path -> target flag component
    TYPES:
      BEGIN OF ts_ind_rule,
        src_path  TYPE string,
        dst_field TYPE fieldname,
      END OF ts_ind_rule,
      tt_ind_rule TYPE STANDARD TABLE OF ts_ind_rule WITH DEFAULT KEY.

*   ==================================================================
*   CONFIRMED - outbound SMT mapping USMDZ6_0G_ACCOUNT, entity ACCOUNT
*   ==================================================================
    CONSTANTS:
      c_entity_main TYPE usmd_entity VALUE 'ACCOUNT'              ##NO_TEXT,
      c_struct_main TYPE string      VALUE '/MDG/_SX_0G_ACCOUNT'  ##NO_TEXT.

*   keys: two separate fields, no concatenated CO-object-style key
    CONSTANTS:
      c_fld_coa     TYPE fieldname VALUE 'COA'     ##NO_TEXT,   " CHAR 4
      c_fld_account TYPE fieldname VALUE 'ACCOUNT' ##NO_TEXT.   " CHAR 10, ALPHA

*   attributes that need a conversion and are therefore addressed by name
    CONSTANTS:
      c_fld_fsiacc TYPE fieldname VALUE 'FSIACC' ##NO_TEXT,     " CHAR 10, ALPHA
      c_fld_txtlg  TYPE fieldname VALUE 'TXTLG'  ##NO_TEXT,     " CHAR 80
      c_fld_txtsh  TYPE fieldname VALUE 'TXTSH'  ##NO_TEXT,     " CHAR 80
      c_fld_langu  TYPE fieldname VALUE 'LANGU'  ##NO_TEXT.

*   ==================================================================
*   !! UNVERIFIED !!  PROXY PATHS - one SE11 session fixes them all
*   ==================================================================
*   TODO verify in SE11: SAPPLCO_GLACCT_MSTR_RPLCTNRQ
*   (the payload node of SAPPLCO_GLACCT_MSTR_RPLCTNRQMS, component
*   GENERAL_LEDGER_ACCOUNT_MASTER - see ZCL_ACCOUNT_INBOUND_INTERFACE).
*   The list this seed is based on came back flattened and INCOMPLETE:
*   it does not even contain the indicator fields that the outbound
*   mapping proves must exist. Every path here is a guess; the ones
*   marked "FINBCO" are borrowed from the OUTBOUND mapping's target
*   names, which belong to a different (FINBCO_*) structure family and
*   are relative to a sub-node - they are a starting point for the SE11
*   read, nothing more.
*   HAZARD: the base class (GET_CORR / RESOLVE_PATH) silently drops a
*   pair or a whole group whose source component does not exist. A wrong
*   path here loses a field WITHOUT any error - break in
*   ZCL_MDG_0G_SRV_MAPPER->RUN_GROUP on the first real payload.
    CONSTANTS:
*     reported by the flattened component list (root level)
      c_path_account   TYPE string VALUE 'ACCOUNT'                ##NO_TEXT, " struct, CONTENT C10
      c_path_coa       TYPE string VALUE 'CHART_OF_ACCOUNTS'      ##NO_TEXT, " CHAR 4
      c_path_coa_item  TYPE string VALUE 'CHART_OF_ACCOUNTS_ITEM' ##NO_TEXT, " struct, CONTENT C10
      c_path_ccdet     TYPE string VALUE 'COMPANY_DETAILS'        ##NO_TEXT, " table = B segment
*     NOT in the reported list - names borrowed from the FINBCO outbound side
      c_path_del       TYPE string VALUE 'DELETE_INDICATOR'           ##NO_TEXT,
      c_path_bl_crea   TYPE string VALUE 'CREATION_BLOCK_INDICATOR'   ##NO_TEXT,
      c_path_bl_plan   TYPE string VALUE 'PLANNING_BLOCK_INDICATOR'   ##NO_TEXT,
      c_path_bl_post   TYPE string VALUE 'POSTING_BLOCK_INDICATOR'    ##NO_TEXT,
*     no text node at all appeared in the reported list - this is a pure guess
      c_path_text_node TYPE string VALUE 'DESCRIPTION'    ##NO_TEXT, " table or structure
      c_path_txtlg     TYPE string VALUE 'CONTENT'        ##NO_TEXT,
      c_path_txtsh     TYPE string VALUE 'SHORT_CONTENT'  ##NO_TEXT,
      c_path_langu     TYPE string VALUE 'LANGUAGE_CODE'  ##NO_TEXT.

*   ==================================================================
*   !! UNVERIFIED !!  dependent entity ACCCCDET (B segment)
*   ==================================================================
*   TODO verify in SE11 / MDGIMG: ACCCCDET is documented in CLAUDE.md
*   (reference method create_crequest_acc_company, S4E E00607) as a
*   writable 0G entity, but NONE of its staging fields were supplied and
*   the row structure of COMPANY_DETAILS could not be retrieved. The
*   structure name below follows the confirmed /MDG/_SX_0G_* pattern of
*   the main entity and is otherwise a guess.
    CONSTANTS:
      c_entity_ccdet TYPE usmd_entity VALUE 'ACCCCDET'             ##NO_TEXT,
      c_struct_ccdet TYPE string      VALUE '/MDG/_SX_0G_ACCCCDET' ##NO_TEXT.

    "! Field mapping rules for ONE ACCCCDET row (source root = the row).
    "! Kept next to GET_CORR_GROUPS: all mapping rules in one place.
    METHODS get_ccdet_groups
      RETURNING VALUE(rt_groups) TYPE zif_mdg_0g_srv_mapper=>tt_group.

    "! The four confirmed C1 boolean attributes and their (guessed) paths.
    METHODS get_main_indicators
      RETURNING VALUE(rt_rules) TYPE tt_ind_rule.

    "! Run indicator rules against one target, via the base helpers
    "! RESOLVE_PATH and INDICATOR_TO_FLAG.
    METHODS apply_indicators
      IMPORTING is_root   TYPE any
                it_rules  TYPE tt_ind_rule
      CHANGING  cs_target TYPE any.

    "! Read one elementary value by path. When the path ends on a coded-ID
    "! sub-structure, its CONTENT component is taken (SAPPLCO layout).
    METHODS read_value
      IMPORTING is_root         TYPE any
                iv_path         TYPE string
      RETURNING VALUE(rv_value) TYPE usmd_value.

    "! Move one value from IV_PATH into component IV_FIELD, if both exist.
    "! An initial source value is skipped, so a blank in the message does
    "! not clear an existing text / attribute.
    METHODS move_value
      IMPORTING is_root   TYPE any
                iv_path   TYPE string
                iv_field  TYPE fieldname
      CHANGING  cs_target TYPE any.

    "! Build one text row (TXTLG / TXTSH / LANGU) from one text node.
    METHODS add_text_row
      IMPORTING is_node TYPE any
                it_keys TYPE zif_mdg_0g_srv_mapper=>tt_keyval
      CHANGING  ct_tab  TYPE STANDARD TABLE.

    "! ALPHA input conversion for the 10-character account-style keys
    "! (ACCOUNT, FSIACC).
    METHODS alpha_in
      IMPORTING iv_value        TYPE usmd_value
      RETURNING VALUE(rv_value) TYPE usmd_value.

ENDCLASS.



CLASS zcl_mdg_0g_srv_mapper_acc IMPLEMENTATION.


  METHOD zif_mdg_0g_srv_mapper~get_main_entity.
    rv_entity = c_entity_main.
  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~get_main_struct.
    rv_name = c_struct_main.
  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~get_text_struct.
*   texts live in the SAME structure as the attributes (TXTLG / TXTSH /
*   LANGU are components of /MDG/_SX_0G_ACCOUNT) - same arrangement as
*   PCTR, where both SMT steps share one staging structure. The base
*   template method therefore emits a second target row for the same
*   entity with STRUCT = KLTXT.
    rv_name = c_struct_main.
  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~derive_keys.

*   Two separate keys - COA (CHAR 4) and ACCOUNT (CHAR 10, ALPHA).
*   There is no concatenated CO-object-style key on the Account side, so
*   no SPLIT_COOBJ_ID fallback here (unlike PCTR).
*   READ_VALUE takes the CONTENT component when the path ends on a
*   SAPPLCO coded-ID structure, which is what ACCOUNT is reported to be.
    DATA(lv_coa)     = read_value( is_root = is_message iv_path = c_path_coa ).
    DATA(lv_account) = read_value( is_root = is_message iv_path = c_path_account ).

    IF lv_coa IS INITIAL AND lv_account IS INITIAL.
      RETURN.
    ENDIF.

    rt_keys = VALUE #( ( field = c_fld_coa     value = to_upper( lv_coa ) )
                       ( field = c_fld_account value = alpha_in( lv_account ) ) ).

  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~get_corr_groups.

*   ==================================================================
*   SINGLE PLACE TO EDIT the plain 1:1 field mapping of the main entity.
*   ==================================================================
*   DSTNAMEs are confirmed (/MDG/_SX_0G_ACCOUNT), SRCNAMEs are not - see
*   the proxy-path banner in the private section.
*   Fields that need a conversion are NOT here:
*     - ACCOUNT / COA        -> DERIVE_KEYS (ALPHA)
*     - FSIACC               -> FINALIZE_MAIN (ALPHA)
*     - ACCDEL / ACCBLCREA / ACCBLPLAN / ACCBLPOST
*                            -> FINALIZE_MAIN (indicator -> C1 flag)
*     - TXTLG / TXTSH / LANGU-> BUILD_TEXTS (ISO -> SPRAS)
    rt_groups = VALUE #(

      ( src_path = ``
        mapping  = VALUE #(

*         Confirmed TARGET fields whose SOURCE component is still unknown -
*         the reported (flattened, incomplete) component list of
*         SAPPLCO_GLACCT_MSTR_RPLCTNRQ contains no candidate. Fill in the
*         SRCNAME after the SE11 read and uncomment; do not guess a name
*         here, a wrong one is dropped silently.
*         ( level = 0 kind = 1 srcname = '' dstname = 'ACCGRPACC' )  " G/L account type / group, C6
*         ( level = 0 kind = 1 srcname = '' dstname = 'ACCPLTYP' )   " retained earnings / P&L type, C2

*         ACTION_CODE (C2) -> USMD_ACTIONCODE (C2), moved 1:1 for now.
*         TODO verify in SE24: the CL_USMD_CONVERSION_ACTION_* class family
*         is the intended converter between proxy action codes and MDG
*         action codes - exact class and method name unconfirmed, so no
*         call is coded here. A 1:1 move is only correct if both code
*         lists happen to be identical.
          ( level = 0 kind = 1 srcname = 'ACTION_CODE' dstname = 'USMD_ACTIONCODE' ) ) ) ).

*   NOTE: the proxy root also reports TRADING_PARTNER_COMPANY_ID,
*   FUNCTIONAL_AREA and LONG_EXPENSE_CLASSIFICATION_FU. The confirmed
*   attribute list of /MDG/_SX_0G_ACCOUNT has no counterpart for them,
*   so they are deliberately not mapped - decide with the data model
*   whether they belong to another 0G entity or to attributes that were
*   not part of the outbound mapping.

  ENDMETHOD.


  METHOD get_main_indicators.

*   Targets confirmed (C1 booleans), source paths guessed - see the
*   proxy-path banner.
    rt_rules = VALUE #(
      ( src_path = c_path_del     dst_field = 'ACCDEL' )      " delete indicator
      ( src_path = c_path_bl_crea dst_field = 'ACCBLCREA' )   " creation blocked
      ( src_path = c_path_bl_plan dst_field = 'ACCBLPLAN' )   " planning blocked
      ( src_path = c_path_bl_post dst_field = 'ACCBLPOST' ) ). " posting blocked

  ENDMETHOD.


  METHOD finalize_main.

*   SAPPLCO indicators ('true'/'false') -> MDG C1 flags ('X'/' ')
    apply_indicators( EXPORTING is_root   = is_message
                                it_rules  = get_main_indicators( )
                      CHANGING  cs_target = cs_main ).

*   FSIACC (group chart of accounts item, CHAR 10 ALPHA) - conversion, so
*   not part of a CORRESPONDING group. READ_VALUE unwraps CONTENT.
    DATA(lv_item) = read_value( is_root = is_message iv_path = c_path_coa_item ).
    IF lv_item IS NOT INITIAL.
      FIELD-SYMBOLS <fsi> TYPE any.
      ASSIGN COMPONENT c_fld_fsiacc OF STRUCTURE cs_main TO <fsi>.
      IF <fsi> IS ASSIGNED.
        <fsi> = alpha_in( lv_item ).
      ENDIF.
    ENDIF.

  ENDMETHOD.


  METHOD build_texts.

*   Redefinition: the base builder writes the long text into TXTMI, which
*   /MDG/_SX_0G_ACCOUNT does not have (confirmed text fields: TXTLG,
*   TXTSH, LANGU). Everything else follows the base pattern - one row per
*   language, keys stamped with SET_KEYS, ISO language via LANG_ISO_TO_SAP.
    DATA(lv_struc) = zif_mdg_0g_srv_mapper~get_text_struct( ).
    IF lv_struc IS INITIAL.
      RETURN.
    ENDIF.

*   dynamic type creation is guarded here - an inbound BAdI must not dump
*   on a mistyped structure name
    TRY.
        CREATE DATA rr_tab TYPE STANDARD TABLE OF (lv_struc).
      CATCH cx_sy_create_data_error.
        CLEAR rr_tab.
        RETURN.
    ENDTRY.

    FIELD-SYMBOLS <lt> TYPE STANDARD TABLE.
    ASSIGN rr_tab->* TO <lt>.
    IF <lt> IS NOT ASSIGNED.
      CLEAR rr_tab.
      RETURN.
    ENDIF.

    DATA(lr_node) = resolve_path( is_root = is_message iv_path = c_path_text_node ).
    IF lr_node IS NOT BOUND.
*     no text node under the guessed path -> no texts, no dump
      CLEAR rr_tab.
      RETURN.
    ENDIF.

*   the node may be a table (one row per language) or a single structure -
*   TODO verify in SE11 which of the two SAPPLCO_GLACCT_MSTR_RPLCTNRQ uses
    FIELD-SYMBOLS: <rows> TYPE ANY TABLE,
                   <one>  TYPE any.

    ASSIGN lr_node->* TO <rows>.
    IF <rows> IS ASSIGNED.
      LOOP AT <rows> ASSIGNING FIELD-SYMBOL(<row>).
        add_text_row( EXPORTING is_node = <row> it_keys = it_keys CHANGING ct_tab = <lt> ).
      ENDLOOP.
    ELSE.
      ASSIGN lr_node->* TO <one>.
      IF <one> IS ASSIGNED.
        add_text_row( EXPORTING is_node = <one> it_keys = it_keys CHANGING ct_tab = <lt> ).
      ENDIF.
    ENDIF.

    IF <lt> IS INITIAL.
      CLEAR rr_tab.
    ENDIF.

  ENDMETHOD.


  METHOD add_text_row.

    DATA(lv_struc) = zif_mdg_0g_srv_mapper~get_text_struct( ).

    DATA lr_line TYPE REF TO data.
    TRY.
        CREATE DATA lr_line TYPE (lv_struc).
      CATCH cx_sy_create_data_error.
        RETURN.
    ENDTRY.

    FIELD-SYMBOLS <ls> TYPE any.
    ASSIGN lr_line->* TO <ls>.
    IF <ls> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    set_keys( EXPORTING it_keys = it_keys CHANGING cs_target = <ls> ).

    move_value( EXPORTING is_root = is_node iv_path = c_path_txtlg iv_field = c_fld_txtlg
                CHANGING  cs_target = <ls> ).
    move_value( EXPORTING is_root = is_node iv_path = c_path_txtsh iv_field = c_fld_txtsh
                CHANGING  cs_target = <ls> ).

*   2-char ISO ('en') -> 1-char SAP language key ('E'); a plain move would
*   truncate it to 'e'
    DATA(lv_iso) = read_value( is_root = is_node iv_path = c_path_langu ).
    IF lv_iso IS NOT INITIAL.
      FIELD-SYMBOLS <langu> TYPE any.
      ASSIGN COMPONENT c_fld_langu OF STRUCTURE <ls> TO <langu>.
      IF <langu> IS ASSIGNED.
        <langu> = lang_iso_to_sap( lv_iso ).
      ENDIF.
    ENDIF.

    INSERT <ls> INTO TABLE ct_tab.

  ENDMETHOD.


  METHOD get_ccdet_groups.

*   ==================================================================
*   SINGLE PLACE TO EDIT the Account / company code (ACCCCDET) mapping.
*   ==================================================================
*   !! NOTHING HERE IS CONFIRMED - neither side !!
*   Source root is one row of COMPANY_DETAILS (its row structure could
*   not be retrieved), target is the assumed /MDG/_SX_0G_ACCCCDET (whose
*   field list was not supplied). The single seeded pair below is a
*   placeholder taken from the PCTR company-code mapping.
*   TODO verify in SE11: row type of COMPANY_DETAILS in
*   SAPPLCO_GLACCT_MSTR_RPLCTNRQ, and the ACCCCDET staging structure.
*   NOTE: the PCTR side derives its assignment flag from ACTION_CODE
*   ('03' = unassigned, '04' = assigned). That semantic is confirmed for
*   PCCCASS only - there is NO confirmed Account equivalent, so none is
*   implemented here. Do not copy it over on a hunch.
    rt_groups = VALUE #(

      ( src_path = ``
        mapping  = VALUE #(
          ( level = 0 kind = 1 srcname = 'COMPANY_ID' dstname = 'COMPCODE' ) ) ) ).

  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~map_sub_entities.

*   COMPANY_DETAILS[] (B segment) -> ACCCCDET staging rows
    DATA(lr_cc) = resolve_path( is_root = is_message iv_path = c_path_ccdet ).
    CHECK lr_cc IS BOUND.

    FIELD-SYMBOLS <cc> TYPE ANY TABLE.
    ASSIGN lr_cc->* TO <cc>.
    IF <cc> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    DATA: lr_tab  TYPE REF TO data,
          lr_line TYPE REF TO data.

*   C_STRUCT_CCDET is a guess - guard the dynamic creation so a wrong name
*   costs the company-code rows instead of dumping the inbound call
    TRY.
        CREATE DATA lr_tab  TYPE STANDARD TABLE OF (c_struct_ccdet).
        CREATE DATA lr_line TYPE (c_struct_ccdet).
      CATCH cx_sy_create_data_error.
        RETURN.
    ENDTRY.

    FIELD-SYMBOLS <lt> TYPE STANDARD TABLE.
    ASSIGN lr_tab->* TO <lt>.
    IF <lt> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    FIELD-SYMBOLS <ls> TYPE any.
    ASSIGN lr_line->* TO <ls>.
    IF <ls> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    DATA(lt_groups) = get_ccdet_groups( ).
    FIELD-SYMBOLS <src> TYPE any.

    LOOP AT <cc> ASSIGNING FIELD-SYMBOL(<row>).

      CLEAR <ls>.

*     COA / ACCOUNT come from the header keys, the company code from the row
      set_keys( EXPORTING it_keys = it_keys CHANGING cs_target = <ls> ).

      LOOP AT lt_groups ASSIGNING FIELD-SYMBOL(<group>).

        DATA(lr_src) = resolve_path( is_root = <row> iv_path = <group>-src_path ).
        IF lr_src IS NOT BOUND.
          CONTINUE.
        ENDIF.

        ASSIGN lr_src->* TO <src>.
        IF <src> IS NOT ASSIGNED.
          CONTINUE.
        ENDIF.

*       own cache-key namespace: the corr cache of the base class is keyed
*       by SRC_PATH alone and the destination type here is not the main one
        run_group( EXPORTING iv_key = |ACCCCDET-{ <group>-src_path }|
                             is_src = <src>
                             it_map = <group>-mapping
                   CHANGING  cs_dst = <ls> ).

      ENDLOOP.

      INSERT <ls> INTO TABLE <lt>.

    ENDLOOP.

    IF <lt> IS INITIAL.
      RETURN.
    ENDIF.

    INSERT VALUE #( entity = c_entity_ccdet
                    struct = zif_mdg_0g_cu=>gc_struct-kattr
                    recs   = lr_tab ) INTO TABLE ct_targets.

  ENDMETHOD.


  METHOD apply_indicators.

    FIELD-SYMBOLS: <src> TYPE any,
                   <dst> TYPE any.

    LOOP AT it_rules ASSIGNING FIELD-SYMBOL(<rule>).

      ASSIGN COMPONENT <rule>-dst_field OF STRUCTURE cs_target TO <dst>.
      IF <dst> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      DATA(lr_src) = resolve_path( is_root = is_root iv_path = <rule>-src_path ).
      IF lr_src IS NOT BOUND.
        CONTINUE.
      ENDIF.

      ASSIGN lr_src->* TO <src>.
      IF <src> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      <dst> = indicator_to_flag( <src> ).

    ENDLOOP.

  ENDMETHOD.


  METHOD move_value.

    DATA(lv_value) = read_value( is_root = is_root iv_path = iv_path ).
    IF lv_value IS INITIAL.
      RETURN.
    ENDIF.

    FIELD-SYMBOLS <dst> TYPE any.
    ASSIGN COMPONENT iv_field OF STRUCTURE cs_target TO <dst>.
    IF <dst> IS ASSIGNED.
      <dst> = lv_value.
    ENDIF.

  ENDMETHOD.


  METHOD read_value.

    CLEAR rv_value.

    DATA(lr_val) = resolve_path( is_root = is_root iv_path = iv_path ).
    IF lr_val IS NOT BOUND.
      RETURN.
    ENDIF.

    FIELD-SYMBOLS <val> TYPE any.
    ASSIGN lr_val->* TO <val>.
    IF <val> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    DATA(lo_type) = cl_abap_typedescr=>describe_by_data( <val> ).

*   coded IDs of the SAPPLCO messages are structures carrying CONTENT
    IF lo_type->kind = cl_abap_typedescr=>kind_struct.
      ASSIGN COMPONENT 'CONTENT' OF STRUCTURE <val> TO FIELD-SYMBOL(<content>).
      IF <content> IS ASSIGNED.
        rv_value = condense( CONV string( <content> ) ).
      ENDIF.
      RETURN.
    ENDIF.

    IF lo_type->kind = cl_abap_typedescr=>kind_elem.
      rv_value = condense( CONV string( <val> ) ).
    ENDIF.

  ENDMETHOD.


  METHOD alpha_in.

    rv_value = to_upper( iv_value ).
    IF rv_value IS INITIAL.
      RETURN.
    ENDIF.

*   ACCOUNT and FSIACC are both CHAR 10 with ALPHA conversion
    DATA lv_key TYPE c LENGTH 10.
    lv_key = rv_value.

    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        input  = lv_key
      IMPORTING
        output = lv_key.

    rv_value = lv_key.

  ENDMETHOD.


ENDCLASS.
