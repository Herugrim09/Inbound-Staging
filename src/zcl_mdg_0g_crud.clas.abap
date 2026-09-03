class ZCL_MDG_0G_CRUD definition
  public
  final
  create private .

************************************************************************
* Project : Inbound-Staging
* Purpose : ZIF_MDG_0G_CU implementation - a stateful singleton that
*           drives IF_USMD_GOV_API step by step over an internal buffer.
*           Get it with ZCL_MDG_0G_CRUD=>GET_INSTANCE( ); callers talk
*           to the ZIF_MDG_0G_CU interface only.
************************************************************************
public section.

  interfaces ZIF_MDG_0G_CU .

  aliases CLEAR_BUFFERS
    for ZIF_MDG_0G_CU~CLEAR_BUFFERS .
  aliases COMMIT
    for ZIF_MDG_0G_CU~COMMIT .
  aliases CREATE_CREQUEST
    for ZIF_MDG_0G_CU~CREATE_CREQUEST .
  aliases CREATE_REF
    for ZIF_MDG_0G_CU~CREATE_REF .
  aliases ENQUEUE_CR
    for ZIF_MDG_0G_CU~ENQUEUE_CR .
  aliases ENQUEUE_ENTITY
    for ZIF_MDG_0G_CU~ENQUEUE_ENTITY .
  aliases FLUSH
    for ZIF_MDG_0G_CU~FLUSH .
  aliases GET_MESSAGES
    for ZIF_MDG_0G_CU~GET_MESSAGES .
  aliases SAVE
    for ZIF_MDG_0G_CU~SAVE .
  aliases WRITE_DATA
    for ZIF_MDG_0G_CU~WRITE_DATA .
  aliases TS_BUFFER
    for ZIF_MDG_0G_CU~TS_BUFFER .
  aliases TT_BUFFER
    for ZIF_MDG_0G_CU~TT_BUFFER .

  class-methods GET_INSTANCE
    importing
      !IV_MODEL type USMD_MODEL default '0G'
    returning
      value(RO_INSTANCE) type ref to ZIF_MDG_0G_CU .
protected section.
private section.

  class-data GO_INSTANCE type ref to ZCL_MDG_0G_CRUD .
  data MV_MODEL type USMD_MODEL .
  data MV_CREQUEST type USMD_CREQUEST .
  data MT_BUFFER type ZIF_MDG_0G_CU=>TT_BUFFER .
  data MT_MESSAGE type USMD_T_MESSAGE .
  data MI_API type ref to IF_USMD_GOV_API .

  methods CONSTRUCTOR
    importing
      !IV_MODEL type USMD_MODEL .
    "! Cached Gov API instance. Returns unbound (and collects a message)
    "! when it cannot be obtained.
  methods API
    returning
      value(RI_API) type ref to IF_USMD_GOV_API .
    "! Build a Gov-API-typed table (key or key+attr) for an entity and
    "! MOVE-CORRESPONDING the buffered rows into it.
  methods TO_GOV_TABLE
    importing
      !IV_ENTITY type USMD_ENTITY
      !IV_WITH_ATTR type ABAP_BOOL
      !IT_SRC type ANY TABLE
    returning
      value(RR_TAB) type ref to DATA .
  methods COLLECT
    importing
      !IT_MESSAGES type USMD_T_MESSAGE optional
      !IX_ERROR type ref to CX_ROOT optional .
ENDCLASS.



CLASS ZCL_MDG_0G_CRUD IMPLEMENTATION.


  METHOD get_instance.
    IF go_instance IS NOT BOUND.
      go_instance = NEW #( iv_model ).
    ENDIF.
    ro_instance = go_instance.
  ENDMETHOD.


  METHOD constructor.
    mv_model = iv_model.
  ENDMETHOD.


  METHOD api.
    IF mi_api IS NOT BOUND.
      TRY.
          mi_api = cl_usmd_gov_api=>get_instance( iv_model_name = mv_model ).
        CATCH cx_usmd_gov_api INTO DATA(lx).
          collect( it_messages = lx->mt_messages ix_error = lx ).
      ENDTRY.
    ENDIF.
    ri_api = mi_api.
  ENDMETHOD.


  METHOD create_crequest.

    " keep MT_BUFFER: for a bulk it is already filled by write_data before the
    " CR exists. Callers that own the session reset it via clear_buffers( ).
    CLEAR: mt_message, mv_crequest.

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND.
      RETURN.
    ENDIF.

    " edition is mandatory - fall back to the always-open DUMMY edition
    DATA(lv_edition) = COND usmd_edition( WHEN iv_edition IS NOT INITIAL
                                          THEN iv_edition
                                          ELSE 'DUMMY' ).

    TRY.
        rv_crequest = li_api->create_crequest( iv_crequest_type = iv_crequest_type
                                               iv_description   = iv_description
                                               iv_edition       = lv_edition ).
        mv_crequest = rv_crequest.
      CATCH cx_usmd_gov_api INTO DATA(lx).
        collect( it_messages = lx->mt_messages ix_error = lx ).
    ENDTRY.

  ENDMETHOD.


  METHOD create_ref.

    DATA lr_tab TYPE REF TO data.
    CREATE DATA lr_tab TYPE STANDARD TABLE OF (iv_struct).

    FIELD-SYMBOLS <lt> TYPE STANDARD TABLE.
    ASSIGN lr_tab->* TO <lt>.
    IF <lt> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    <lt> = CORRESPONDING #( it_data ).

    write_data( iv_entity = iv_entity
                iv_struct = iv_struct
                ir_data   = lr_tab ).

  ENDMETHOD.


  METHOD write_data.
    IF ir_data IS NOT BOUND.
      RETURN.
    ENDIF.
    APPEND VALUE #( entity = iv_entity
                    struct = iv_struct
                    data   = ir_data ) TO mt_buffer.
  ENDMETHOD.


  METHOD enqueue_cr.

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND OR mv_crequest IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        li_api->enqueue_crequest( iv_crequest_id = mv_crequest ).
      CATCH cx_usmd_gov_api INTO DATA(lx).
        collect( it_messages = lx->mt_messages ix_error = lx ).
    ENDTRY.

  ENDMETHOD.


  METHOD enqueue_entity.

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND OR mv_crequest IS INITIAL.
      RETURN.
    ENDIF.

    FIELD-SYMBOLS <src> TYPE ANY TABLE.

    LOOP AT mt_buffer ASSIGNING FIELD-SYMBOL(<buf>) WHERE entity = iv_entity.

      IF <buf>-data IS NOT BOUND.
        CONTINUE.
      ENDIF.
      ASSIGN <buf>-data->* TO <src>.
      IF <src> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      DATA(lr_key) = to_gov_table( iv_entity    = iv_entity
                                   iv_with_attr = abap_false
                                   it_src       = <src> ).
      IF lr_key IS NOT BOUND.
        CONTINUE.
      ENDIF.
      ASSIGN lr_key->* TO FIELD-SYMBOL(<key>).
      IF <key> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      TRY.
          li_api->enqueue_entity( iv_crequest_id = mv_crequest
                                  iv_entity_name = iv_entity
                                  it_data        = <key> ).
        CATCH cx_usmd_gov_api_entity_lock INTO DATA(lx_lock).
          collect( it_messages = lx_lock->mt_messages ix_error = lx_lock ).
        CATCH cx_usmd_gov_api INTO DATA(lx).
          collect( it_messages = lx->mt_messages ix_error = lx ).
      ENDTRY.

    ENDLOOP.

  ENDMETHOD.


  METHOD flush.

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND OR mv_crequest IS INITIAL.
      RETURN.
    ENDIF.

    FIELD-SYMBOLS <src> TYPE ANY TABLE.

    LOOP AT mt_buffer ASSIGNING FIELD-SYMBOL(<buf>).

      IF <buf>-data IS NOT BOUND.
        CONTINUE.
      ENDIF.
      ASSIGN <buf>-data->* TO <src>.
      IF <src> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

*     TODO: text staging (e.g. /MDG/_ST_0G_ES_* - key incl. LANGU) is not an
*     ordinary write_entity target; route it via the text API when <buf>-struct
*     identifies a text structure.
      DATA(lr_ka) = to_gov_table( iv_entity    = <buf>-entity
                                  iv_with_attr = abap_true
                                  it_src       = <src> ).
      IF lr_ka IS NOT BOUND.
        CONTINUE.
      ENDIF.
      ASSIGN lr_ka->* TO FIELD-SYMBOL(<ka>).
      IF <ka> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      TRY.
          li_api->write_entity( iv_crequest_id = mv_crequest
                                iv_entity_name = <buf>-entity
                                it_data        = <ka> ).
        CATCH cx_usmd_gov_api_entity_write INTO DATA(lx_write).
          collect( it_messages = lx_write->mt_messages ix_error = lx_write ).
        CATCH cx_usmd_gov_api INTO DATA(lx).
          collect( it_messages = lx->mt_messages ix_error = lx ).
      ENDTRY.

    ENDLOOP.

*   internal buffer consumed - data now lives in the Gov API buffers
    CLEAR mt_buffer.

  ENDMETHOD.


  METHOD save.

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND OR mv_crequest IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        li_api->save( i_mode = if_usmd_ui_services=>gc_save_mode_draft_no_check ).
        li_api->dequeue_crequest( iv_crequest_id = mv_crequest ).
      CATCH cx_usmd_gov_api INTO DATA(lx).
        collect( it_messages = lx->mt_messages ix_error = lx ).
    ENDTRY.

  ENDMETHOD.


  METHOD commit.

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND OR mv_crequest IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        li_api->check_crequest_data( iv_crequest_id = mv_crequest ).
      CATCH cx_usmd_gov_api_core_error INTO DATA(lx_chk_c).
        collect( it_messages = lx_chk_c->mt_messages ix_error = lx_chk_c ).
      CATCH cx_usmd_gov_api INTO DATA(lx_chk).
        collect( it_messages = lx_chk->mt_messages ix_error = lx_chk ).
    ENDTRY.

    TRY.
        li_api->if_usmd_gov_api_process~start_workflow( iv_crequest_id = mv_crequest ).
      CATCH cx_usmd_gov_api_core_error INTO DATA(lx_wf_c).
        collect( it_messages = lx_wf_c->mt_messages ix_error = lx_wf_c ).
      CATCH cx_usmd_gov_api INTO DATA(lx_wf).
        collect( it_messages = lx_wf->mt_messages ix_error = lx_wf ).
    ENDTRY.

    IF iv_commit = abap_true.
      COMMIT WORK AND WAIT.
    ENDIF.

  ENDMETHOD.


  METHOD clear_buffers.
    CLEAR: mt_buffer, mt_message, mv_crequest.
  ENDMETHOD.


  METHOD get_messages.
    rt_message = mt_message.
  ENDMETHOD.


  METHOD to_gov_table.

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA lv_struct LIKE li_api->gc_struct_key.
    IF iv_with_attr = abap_true.
      lv_struct = li_api->gc_struct_key_attr.
    ELSE.
      lv_struct = li_api->gc_struct_key.
    ENDIF.

    DATA lr TYPE REF TO data.
    TRY.
        li_api->create_data_reference( EXPORTING iv_entity_name = iv_entity
                                                 iv_struct      = lv_struct
                                       IMPORTING er_table       = lr ).
      CATCH cx_usmd_gov_api INTO DATA(lx).
        collect( it_messages = lx->mt_messages ix_error = lx ).
        RETURN.
    ENDTRY.

    FIELD-SYMBOLS <tab> TYPE ANY TABLE.       " Gov API key / key+attr tables are keyed (hashed/sorted)
    ASSIGN lr->* TO <tab>.
    IF <tab> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    <tab> = CORRESPONDING #( it_src ).
    rr_tab = lr.

  ENDMETHOD.


  METHOD collect.
    APPEND LINES OF it_messages TO mt_message.
    IF it_messages IS INITIAL AND ix_error IS BOUND.
      APPEND VALUE #( msgty = 'E'
                      msgid = '00'
                      msgno = '398'
                      msgv1 = ix_error->get_text( ) ) TO mt_message.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
