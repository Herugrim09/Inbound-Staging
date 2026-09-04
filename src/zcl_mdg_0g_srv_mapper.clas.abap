CLASS zcl_mdg_0g_srv_mapper DEFINITION
  PUBLIC
  ABSTRACT
  CREATE PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : Abstract base for the inbound service mappers.
*           Holds the generic engine - CL_ABAP_CORRESPONDING groups,
*           path resolution, key handling, text builder - and the
*           template method ZIF_MDG_0G_SRV_MAPPER~MAP.
*           One concrete subclass per governed entity supplies the
*           handshake methods; callers use ZIF_MDG_0G_SRV_MAPPER only.
************************************************************************

  PUBLIC SECTION.

    INTERFACES zif_mdg_0g_srv_mapper
      ABSTRACT METHODS get_main_entity get_main_struct get_corr_groups
      FINAL METHODS map.

  PROTECTED SECTION.

    "! Hook for derived / cross-level target fields. Default: no-op.
    METHODS finalize_main
      IMPORTING is_message TYPE any
      CHANGING  cs_main    TYPE any.

    "! Run all CL_ABAP_CORRESPONDING groups against the flat target.
    METHODS apply_groups
      IMPORTING is_message TYPE any
                it_groups  TYPE zif_mdg_0g_srv_mapper=>tt_group
      CHANGING  cs_target  TYPE any.

    "! Build the text staging table from the message NAME[] table.
    METHODS build_texts
      IMPORTING is_message    TYPE any
                it_keys       TYPE zif_mdg_0g_srv_mapper=>tt_keyval
      RETURNING VALUE(rr_tab) TYPE REF TO data.

    "! Copy derived key values into a target structure by field name.
    METHODS set_keys
      IMPORTING it_keys   TYPE zif_mdg_0g_srv_mapper=>tt_keyval
      CHANGING  cs_target TYPE any.

    "! Resolve a '-' separated component path to a data reference
    "! ('' -> root; missing path -> unbound reference).
    METHODS resolve_path
      IMPORTING is_root       TYPE any
                iv_path       TYPE string
      RETURNING VALUE(rr_val) TYPE REF TO data.

    "! Inverse of CL_USMDZ6_0G_TRANSFORMATIONS=>ENCODE_COOBJ_ID.
    METHODS split_coobj_id
      IMPORTING iv_id     TYPE any
      EXPORTING ev_coarea TYPE char4
                ev_coobj  TYPE usmd_value.

    "! Get (cached) or create a CL_ABAP_CORRESPONDING instance for one group.
    METHODS get_corr
      IMPORTING iv_key    TYPE string
                is_src    TYPE any
                is_dst    TYPE any
                it_map    TYPE cl_abap_corresponding=>mapping_table
      RETURNING VALUE(ro) TYPE REF TO cl_abap_corresponding.

    "! get_corr + execute for one group, guarded against CX_CORR_DYN_ERROR
    "! (an invalid component mapping only skips that group).
    METHODS run_group
      IMPORTING iv_key TYPE string
                is_src TYPE any
                it_map TYPE cl_abap_corresponding=>mapping_table
      CHANGING  cs_dst TYPE any.

  PRIVATE SECTION.

    TYPES:
      BEGIN OF ts_corr_buf,
        corr_key TYPE string,
        obj      TYPE REF TO cl_abap_corresponding,
      END OF ts_corr_buf.

    "! CL_ABAP_CORRESPONDING instances are expensive to create -> cache them
    DATA mt_corr TYPE HASHED TABLE OF ts_corr_buf WITH UNIQUE KEY corr_key.

ENDCLASS.



CLASS zcl_mdg_0g_srv_mapper IMPLEMENTATION.


  METHOD zif_mdg_0g_srv_mapper~map.

    CLEAR et_targets.

    DATA(lt_keys)   = zif_mdg_0g_srv_mapper~derive_keys( is_message ).
    DATA(lv_struct) = zif_mdg_0g_srv_mapper~get_main_struct( ).

*   --- main entity record ---
    DATA lr_tab TYPE REF TO data.
    CREATE DATA lr_tab TYPE STANDARD TABLE OF (lv_struct).
    FIELD-SYMBOLS <lt_main> TYPE STANDARD TABLE.
    ASSIGN lr_tab->* TO <lt_main>.
    IF <lt_main> IS NOT ASSIGNED.
      RAISE EXCEPTION NEW zcx_mdg_0g_srv_mapper( iv_text = 'Main table type not created' ).
    ENDIF.

    DATA lr_row TYPE REF TO data.
    CREATE DATA lr_row TYPE (lv_struct).
    FIELD-SYMBOLS <ls_main> TYPE any.
    ASSIGN lr_row->* TO <ls_main>.
    IF <ls_main> IS NOT ASSIGNED.
      RAISE EXCEPTION NEW zcx_mdg_0g_srv_mapper( iv_text = 'Main line type not created' ).
    ENDIF.

    set_keys( EXPORTING it_keys = lt_keys CHANGING cs_target = <ls_main> ).
    apply_groups( EXPORTING is_message = is_message
                            it_groups  = zif_mdg_0g_srv_mapper~get_corr_groups( )
                  CHANGING  cs_target  = <ls_main> ).
    finalize_main( EXPORTING is_message = is_message CHANGING cs_main = <ls_main> ).

    INSERT <ls_main> INTO TABLE <lt_main>.
    INSERT VALUE #( entity = zif_mdg_0g_srv_mapper~get_main_entity( )
                    struct = zif_mdg_0g_cu=>gc_struct-kattr
                    recs   = lr_tab )
      INTO TABLE et_targets.

*   --- dependent sub-entities ---
    zif_mdg_0g_srv_mapper~map_sub_entities(
      EXPORTING is_message = is_message
                it_keys    = lt_keys
      CHANGING  ct_targets = et_targets ).

*   --- texts (same entity as main) ---
    IF zif_mdg_0g_srv_mapper~get_text_struct( ) IS NOT INITIAL.
      DATA(lr_txt) = build_texts( is_message = is_message it_keys = lt_keys ).
      IF lr_txt IS BOUND.
        INSERT VALUE #( entity = zif_mdg_0g_srv_mapper~get_main_entity( )
                        struct = zif_mdg_0g_cu=>gc_struct-kltxt
                        recs   = lr_txt )
          INTO TABLE et_targets.
      ENDIF.
    ENDIF.

  ENDMETHOD.


  METHOD apply_groups.

    FIELD-SYMBOLS <src> TYPE any.

    LOOP AT it_groups ASSIGNING FIELD-SYMBOL(<group>).

      DATA(lr_src) = resolve_path( is_root = is_message iv_path = <group>-src_path ).
      CHECK lr_src IS BOUND.

      ASSIGN lr_src->* TO <src>.
      IF <src> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      run_group( EXPORTING iv_key = <group>-src_path
                           is_src = <src>
                           it_map = <group>-mapping
                 CHANGING  cs_dst = cs_target ).

    ENDLOOP.

  ENDMETHOD.


  METHOD get_corr.

    ASSIGN mt_corr[ corr_key = iv_key ] TO FIELD-SYMBOL(<buf>).
    IF <buf> IS ASSIGNED.
      ro = <buf>-obj.
      RETURN.
    ENDIF.

*   keep only the pairs whose source (and target) component really exists,
*   so one wrong field name drops just that pair - not the whole group
    DATA lt_map TYPE cl_abap_corresponding=>mapping_table.
    FIELD-SYMBOLS: <c_src> TYPE any,
                   <c_dst> TYPE any.

    LOOP AT it_map ASSIGNING FIELD-SYMBOL(<rule>).

      IF <rule>-srcname IS NOT INITIAL.
        ASSIGN COMPONENT <rule>-srcname OF STRUCTURE is_src TO <c_src>.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
      ENDIF.

      IF <rule>-dstname IS NOT INITIAL.
        ASSIGN COMPONENT <rule>-dstname OF STRUCTURE is_dst TO <c_dst>.
        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.
      ENDIF.

      APPEND <rule> TO lt_map.

    ENDLOOP.

    IF lt_map IS INITIAL.
      RETURN.
    ENDIF.

*   EXCEPT_ALL: only the explicitly listed pairs are moved
    APPEND VALUE #( level = 0 kind = cl_abap_corresponding=>mapping_except_all ) TO lt_map.

    TRY.
        ro = cl_abap_corresponding=>create( source      = is_src
                                            destination = is_dst
                                            mapping     = lt_map ).
      CATCH cx_corr_dyn_error.
        CLEAR ro.
        RETURN.
    ENDTRY.

    INSERT VALUE #( corr_key = iv_key obj = ro ) INTO TABLE mt_corr.

  ENDMETHOD.


  METHOD run_group.

    TRY.
        DATA(lo_corr) = get_corr( iv_key = iv_key
                                  is_src = is_src
                                  is_dst = cs_dst
                                  it_map = it_map ).
        IF lo_corr IS BOUND.
          lo_corr->execute( EXPORTING source = is_src CHANGING destination = cs_dst ).
        ENDIF.
      CATCH cx_corr_dyn_error.
*       invalid component mapping for this group -> skip it
*       TODO: surface via a message channel once the mapper has one
    ENDTRY.

  ENDMETHOD.


  METHOD build_texts.

    DATA(lv_struc) = zif_mdg_0g_srv_mapper~get_text_struct( ).
    IF lv_struc IS INITIAL.
      RETURN.
    ENDIF.

    CREATE DATA rr_tab TYPE STANDARD TABLE OF (lv_struc).
    FIELD-SYMBOLS <lt> TYPE STANDARD TABLE.
    ASSIGN rr_tab->* TO <lt>.
    IF <lt> IS NOT ASSIGNED.
      CLEAR rr_tab.
      RETURN.
    ENDIF.

    DATA lr_line TYPE REF TO data.
    CREATE DATA lr_line TYPE (lv_struc).
    FIELD-SYMBOLS <ls> TYPE any.
    ASSIGN lr_line->* TO <ls>.
    IF <ls> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    DATA(lr_names) = resolve_path( is_root = is_message iv_path = 'NAME' ).
    CHECK lr_names IS BOUND.
    FIELD-SYMBOLS <names> TYPE ANY TABLE.
    ASSIGN lr_names->* TO <names>.
    IF <names> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

*   standard NAME row layout: DESCRIPTION-CONTENT/-LANGUAGE_CODE, NAME-CONTENT
    DATA(lt_desc_map) = VALUE cl_abap_corresponding=>mapping_table(
      ( level = 0 kind = 1 srcname = 'CONTENT'       dstname = 'TXTMI' )
      ( level = 0 kind = 1 srcname = 'LANGUAGE_CODE' dstname = 'LANGU' ) ).
    DATA(lt_name_map) = VALUE cl_abap_corresponding=>mapping_table(
      ( level = 0 kind = 1 srcname = 'CONTENT' dstname = 'TXTSH' ) ).

    FIELD-SYMBOLS: <desc> TYPE any,
                   <name> TYPE any.

    LOOP AT <names> ASSIGNING FIELD-SYMBOL(<row>).

      CLEAR <ls>.
      set_keys( EXPORTING it_keys = it_keys CHANGING cs_target = <ls> ).

      DATA(lr_desc) = resolve_path( is_root = <row> iv_path = 'DESCRIPTION' ).
      IF lr_desc IS BOUND.
        ASSIGN lr_desc->* TO <desc>.
        IF <desc> IS ASSIGNED.
          run_group( EXPORTING iv_key = 'TXT_DESCRIPTION' is_src = <desc> it_map = lt_desc_map
                     CHANGING  cs_dst = <ls> ).
        ENDIF.
      ENDIF.

      DATA(lr_name) = resolve_path( is_root = <row> iv_path = 'NAME' ).
      IF lr_name IS BOUND.
        ASSIGN lr_name->* TO <name>.
        IF <name> IS ASSIGNED.
          run_group( EXPORTING iv_key = 'TXT_NAME' is_src = <name> it_map = lt_name_map
                     CHANGING  cs_dst = <ls> ).
        ENDIF.
      ENDIF.

      INSERT <ls> INTO TABLE <lt>.

    ENDLOOP.

  ENDMETHOD.


  METHOD set_keys.

    FIELD-SYMBOLS <dst> TYPE any.

    LOOP AT it_keys ASSIGNING FIELD-SYMBOL(<key>).
      ASSIGN COMPONENT <key>-field OF STRUCTURE cs_target TO <dst>.
      IF <dst> IS ASSIGNED.
        <dst> = <key>-value.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.


  METHOD resolve_path.

    FIELD-SYMBOLS: <node> TYPE any,
                   <comp> TYPE any.

    ASSIGN is_root TO <node>.
    IF <node> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    IF iv_path IS NOT INITIAL.
      SPLIT iv_path AT '-' INTO TABLE DATA(lt_seg).
      LOOP AT lt_seg ASSIGNING FIELD-SYMBOL(<seg>).
        ASSIGN COMPONENT <seg> OF STRUCTURE <node> TO <comp>.
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.
        ASSIGN <comp> TO <node>.
        IF <node> IS NOT ASSIGNED.
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDIF.

    GET REFERENCE OF <node> INTO rr_val.

  ENDMETHOD.


  METHOD split_coobj_id.

    DATA lv_id TYPE c LENGTH 60.

    CLEAR: ev_coarea, ev_coobj.
    lv_id     = iv_id.
    ev_coarea = lv_id(4).
    CONDENSE ev_coarea.
    ev_coobj  = lv_id+4(10).

  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~get_text_struct.
    rv_name = ``.
  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~map_sub_entities.
    RETURN.
  ENDMETHOD.


  METHOD zif_mdg_0g_srv_mapper~derive_keys.

    FIELD-SYMBOLS <id> TYPE any.

    ASSIGN COMPONENT 'ID' OF STRUCTURE is_message TO <id>.
    IF <id> IS ASSIGNED.
      split_coobj_id( EXPORTING iv_id = <id> IMPORTING ev_coarea = DATA(lv_coarea) ).
      rt_keys = VALUE #( ( field = 'COAREA' value = lv_coarea ) ).
    ENDIF.

  ENDMETHOD.


  METHOD finalize_main.
    RETURN.
  ENDMETHOD.


ENDCLASS.
