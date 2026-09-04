CLASS zcl_mdg_0g_srv_mapper_pctr DEFINITION
  PUBLIC
  INHERITING FROM zcl_mdg_0g_srv_mapper
  FINAL
  CREATE PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : Inbound service mapper for Profit Center (0G entity PCTR).
*           Reverse of the standard outbound SMT mapping
*           (/MDG/_SX_0G_PCTR -> SAPPLCO_PRCTR_RQ_PRCTR).
*           Targets: /MDG/_S_0G_PP_PCTR, /MDG/_ST_0G_ES_PCTR,
*                    /MDG/_S_0G_PP_PCCCASS.
*           Value conversions are still 1:1 (x -> x); ALPHA / language /
*           date conversions to be added later (mapper conversion step).
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

  PRIVATE SECTION.

    CONSTANTS:
      c_entity_main  TYPE usmd_entity VALUE 'PCTR'                  ##NO_TEXT,
      c_entity_ccass TYPE usmd_entity VALUE 'PCCCASS'               ##NO_TEXT,
      c_struct_main  TYPE string      VALUE '/MDG/_S_0G_PP_PCTR'    ##NO_TEXT,
      c_struct_text  TYPE string      VALUE '/MDG/_ST_0G_ES_PCTR'   ##NO_TEXT,
      c_struct_ccass TYPE string      VALUE '/MDG/_S_0G_PP_PCCCASS' ##NO_TEXT.

ENDCLASS.



CLASS zcl_mdg_0g_srv_mapper_pctr IMPLEMENTATION.


  METHOD zif_mdg_0g_srv_mapper~get_main_entity.
    rv_entity = c_entity_main.
  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~get_main_struct.
    rv_name = c_struct_main.
  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~get_text_struct.
    rv_name = c_struct_text.
  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~derive_keys.

    FIELD-SYMBOLS <id> TYPE any.

    ASSIGN COMPONENT 'ID' OF STRUCTURE is_message TO <id>.
    IF <id> IS ASSIGNED.
      split_coobj_id( EXPORTING iv_id     = <id>
                      IMPORTING ev_coarea = DATA(lv_coarea)
                                ev_coobj  = DATA(lv_pctr) ).
      rt_keys = VALUE #( ( field = 'COAREA' value = lv_coarea )
                         ( field = 'PCTR'   value = lv_pctr ) ).
    ENDIF.

  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~get_corr_groups.

*   Reverse of the standard outbound SMT field mapping.
*   One group per source sub-structure; nested single fields get their own
*   group rooted one level deeper (CL_ABAP_CORRESPONDING maps same level only).
    rt_groups = VALUE #(

*     POSTING_USAGE_ALLOWED -> PCTRLKIND is an indicator ('true'/'false'):
*     converted in finalize_main, not by CORRESPONDING (which yields 'f').
      ( src_path = 'ATTRIBUTES'
        mapping  = VALUE #(
          ( level = 0 kind = 1 srcname = 'DEPARTMENT_NAME'         dstname = 'PCTRDEPT' )
          ( level = 0 kind = 1 srcname = 'HOME_BUSINESS_SYSTEM_ID' dstname = 'PCTRLSYS' ) ) )

      ( src_path = 'ATTRIBUTES-TAX_JURISDICTION_CODE'
        mapping  = VALUE #( ( level = 0 kind = 1 srcname = 'CONTENT' dstname = 'PCTRTXJCD' ) ) )

      ( src_path = 'ATTRIBUTES-PRINTER_CODE'
        mapping  = VALUE #( ( level = 0 kind = 1 srcname = 'CONTENT' dstname = 'PC_DRNAM' ) ) )

      ( src_path = 'RESPONSIBLE_MANAGER'
        mapping  = VALUE #( ( level = 0 kind = 1 srcname = 'FORMATTED_NAME' dstname = 'PCTRRESPP' ) ) )

      ( src_path = 'RESPONSIBLE_MANAGER-USER_ACCOUNT_ID'
        mapping  = VALUE #( ( level = 0 kind = 1 srcname = 'CONTENT' dstname = 'PCTRRESPU' ) ) )

      ( src_path = 'SEGMENT_ASSIGNMENT'
        mapping  = VALUE #( ( level = 0 kind = 1 srcname = 'SEGMENT_ID' dstname = 'PCTRSEG' ) ) )

      ( src_path = 'ADDRESS_INFORMATION-NAME'
        mapping  = VALUE #(
          ( level = 0 kind = 1 srcname = 'FORM_OF_ADDRESS_NAME' dstname = 'PC_ANRED' )
          ( level = 0 kind = 1 srcname = 'FIRST_LINE_NAME'      dstname = 'PC_NAME1' )
          ( level = 0 kind = 1 srcname = 'SECOND_LINE_NAME'     dstname = 'PC_NAME2' )
          ( level = 0 kind = 1 srcname = 'THIRD_LINE_NAME'      dstname = 'PC_NAME3' )
          ( level = 0 kind = 1 srcname = 'FOURTH_LINE_NAME'     dstname = 'PC_NAME4' ) ) )

      ( src_path = 'ADDRESS_INFORMATION-POSTAL_ADDRESS'
        mapping  = VALUE #(
          ( level = 0 kind = 1 srcname = 'CITY_NAME'          dstname = 'PC_ORT01' )
          ( level = 0 kind = 1 srcname = 'COUNTRY_CODE'       dstname = 'PC_LAND1' )
          ( level = 0 kind = 1 srcname = 'DISTRICT_NAME'      dstname = 'PC_ORT02' )
          ( level = 0 kind = 1 srcname = 'POBOX_ID'           dstname = 'PC_PFACH' )
          ( level = 0 kind = 1 srcname = 'POBOX_POSTAL_CODE'  dstname = 'PC_PSTL2' )
          ( level = 0 kind = 1 srcname = 'STREET_NAME'        dstname = 'PC_STRAS' )
          ( level = 0 kind = 1 srcname = 'STREET_POSTAL_CODE' dstname = 'PC_PSTLZ' ) ) )

      ( src_path = 'ADDRESS_INFORMATION-POSTAL_ADDRESS-REGION_CODE'
        mapping  = VALUE #( ( level = 0 kind = 1 srcname = 'CONTENT' dstname = 'PC_REGION' ) ) )

      ( src_path = 'ADDRESS_INFORMATION-COMMUNICATION'
        mapping  = VALUE #(
          ( level = 0 kind = 1 srcname = 'CORRESPONDENCE_LANGUAGE_CODE'   dstname = 'PC_SPRAS' )
          ( level = 0 kind = 1 srcname = 'DATA_COMMUNICATION_LINE_NUMBER' dstname = 'PC_DATLT' )
          ( level = 0 kind = 1 srcname = 'FACSIMILE_NUMBER_DESCRIPTION'   dstname = 'PC_TELFX' )
          ( level = 0 kind = 1 srcname = 'FIRST_TELEPHONE_NUMBER_DESCRIP' dstname = 'PC_TELF1' )
          ( level = 0 kind = 1 srcname = 'SECOND_TELEPHONE_NUMBER_DESCRI' dstname = 'PC_TELF2' )
          ( level = 0 kind = 1 srcname = 'TELEBOX_NUMBER_DESCRIPTION'     dstname = 'PC_TELBX' )
          ( level = 0 kind = 1 srcname = 'TELETEX_NUMBER_DESCRIPTION'     dstname = 'PC_TELTX' )
          ( level = 0 kind = 1 srcname = 'TELEX_NUMBER_DESCRIPTION'       dstname = 'PC_TELX1' ) ) ) ).

  ENDMETHOD.


  METHOD finalize_main.

    FIELD-SYMBOLS: <land1> TYPE any,
                   <regpc> TYPE any,
                   <lkind> TYPE any,
                   <ccall> TYPE any,
                   <ca>    TYPE ANY TABLE,
                   <cmpl>  TYPE any.

*   REGION_PC = address country key
    ASSIGN COMPONENT 'PC_LAND1'  OF STRUCTURE cs_main TO <land1>.
    ASSIGN COMPONENT 'REGION_PC' OF STRUCTURE cs_main TO <regpc>.
    IF <land1> IS ASSIGNED AND <regpc> IS ASSIGNED.
      <regpc> = <land1>.
    ENDIF.

*   PCTRLKIND (lock indicator) is the inverse of POSTING_USAGE_ALLOWED:
*   posting allowed -> not locked (' '), posting not allowed -> locked ('X')
    ASSIGN COMPONENT 'PCTRLKIND' OF STRUCTURE cs_main TO <lkind>.
    IF <lkind> IS ASSIGNED.
      DATA(lr_pua) = resolve_path( is_root = is_message
                                   iv_path = 'ATTRIBUTES-POSTING_USAGE_ALLOWED' ).
      IF lr_pua IS BOUND.
        ASSIGN lr_pua->* TO FIELD-SYMBOL(<pua>).
        IF <pua> IS ASSIGNED.
          <lkind> = COND xfeld( WHEN indicator_to_flag( <pua> ) = 'X' THEN space ELSE 'X' ).
        ENDIF.
      ENDIF.
    ENDIF.

*   PCTRCCALL: no individual assignments + list flagged complete => 'X'
    ASSIGN COMPONENT 'PCTRCCALL' OF STRUCTURE cs_main TO <ccall>.
    IF <ccall> IS ASSIGNED.
      DATA(lr_ca) = resolve_path( is_root = is_message iv_path = 'COMPANY_ASSIGNMENT' ).
      DATA(lr_cm) = resolve_path( is_root = is_message iv_path = 'COMPANY_ASSIGNMENT_CMPL' ).
      IF lr_ca IS BOUND AND lr_cm IS BOUND.
        ASSIGN lr_ca->* TO <ca>.
        ASSIGN lr_cm->* TO <cmpl>.
        IF <ca> IS ASSIGNED AND <cmpl> IS ASSIGNED.
          " SAPPLCO_INDICATOR is CHAR 5 ('true'/'false'/'X'/'1'/...) - treat
          " anything that is neither blank nor a false marker as "complete"
          IF <ca> IS INITIAL
             AND <cmpl> IS NOT INITIAL
             AND <cmpl> <> 'false' AND <cmpl> <> '0'.
            <ccall> = 'X'.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.

  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~map_sub_entities.

*   COMPANY_ASSIGNMENT[] -> /MDG/_S_0G_PP_PCCCASS[]
    DATA(lr_ca) = resolve_path( is_root = is_message iv_path = 'COMPANY_ASSIGNMENT' ).
    CHECK lr_ca IS BOUND.
    FIELD-SYMBOLS <ca> TYPE ANY TABLE.
    ASSIGN lr_ca->* TO <ca>.
    IF <ca> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    DATA lr_tab TYPE REF TO data.
    CREATE DATA lr_tab TYPE STANDARD TABLE OF (c_struct_ccass).
    FIELD-SYMBOLS <lt> TYPE STANDARD TABLE.
    ASSIGN lr_tab->* TO <lt>.
    IF <lt> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    DATA lr_line TYPE REF TO data.
    CREATE DATA lr_line TYPE (c_struct_ccass).
    FIELD-SYMBOLS <ls> TYPE any.
    ASSIGN lr_line->* TO <ls>.
    IF <ls> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    DATA(lt_map) = VALUE cl_abap_corresponding=>mapping_table(
      ( level = 0 kind = 1 srcname = 'COMPANY_ID' dstname = 'COMPCODE' ) ).

    FIELD-SYMBOLS <f> TYPE any.

    LOOP AT <ca> ASSIGNING FIELD-SYMBOL(<row>).

      CLEAR <ls>.
      set_keys( EXPORTING it_keys = it_keys CHANGING cs_target = <ls> ).

      run_group( EXPORTING iv_key = 'PCCCASS_ROW' is_src = <row> it_map = lt_map
                 CHANGING  cs_dst = <ls> ).

*     for now: every delivered row means "assigned"
      ASSIGN COMPONENT 'PCTRCCASS' OF STRUCTURE <ls> TO <f>.
      IF <f> IS ASSIGNED.
        <f> = 'X'.
      ENDIF.

      INSERT <ls> INTO TABLE <lt>.

    ENDLOOP.

    INSERT VALUE #( entity = c_entity_ccass
                    struct = zif_mdg_0g_cu=>gc_struct-kattr
                    recs   = lr_tab ) INTO TABLE ct_targets.

  ENDMETHOD.


ENDCLASS.
