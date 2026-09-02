CLASS zcl_mdg_0g_crud DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

************************************************************************
* Project : Inbound-Staging
* Purpose : ZIF_MDG_0G_CU implementation - a stateful singleton that
*           drives IF_USMD_GOV_API step by step over an internal buffer.
*           Get it with ZCL_MDG_0G_CRUD=>GET_INSTANCE( ); callers talk
*           to the ZIF_MDG_0G_CU interface only.
************************************************************************

  PUBLIC SECTION.

    INTERFACES zif_mdg_0g_cu.

    CLASS-METHODS get_instance
      IMPORTING iv_model          TYPE usmd_model DEFAULT '0G'
      RETURNING VALUE(ro_instance) TYPE REF TO zif_mdg_0g_cu.

  PRIVATE SECTION.

    CLASS-DATA go_instance TYPE REF TO zcl_mdg_0g_crud.

    DATA mv_model    TYPE usmd_model.
    DATA mv_crequest TYPE usmd_crequest.
    DATA mt_buffer   TYPE zif_mdg_0g_cu=>tt_buffer.
    DATA mt_message  TYPE usmd_t_message.
    DATA mi_api      TYPE REF TO if_usmd_gov_api.

    METHODS constructor
      IMPORTING iv_model TYPE usmd_model.

    "! Cached Gov API instance. Returns unbound (and collects a message)
    "! when it cannot be obtained.
    METHODS api
      RETURNING VALUE(ri_api) TYPE REF TO if_usmd_gov_api.

    "! Build a Gov-API-typed table (key or key+attr) for an entity and
    "! MOVE-CORRESPONDING the buffered rows into it.
    METHODS to_gov_table
      IMPORTING iv_entity     TYPE usmd_entity
                iv_with_attr  TYPE abap_bool
                it_src        TYPE ANY TABLE
      RETURNING VALUE(rr_tab) TYPE REF TO data.

    METHODS collect
      IMPORTING it_messages TYPE usmd_t_message  OPTIONAL
                ix_error    TYPE REF TO cx_root  OPTIONAL.

ENDCLASS.



CLASS zcl_mdg_0g_crud IMPLEMENTATION.


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


  METHOD zif_mdg_0g_cu~create_crequest.

    zif_mdg_0g_cu~clear_buffers( ).

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND.
      RETURN.
    ENDIF.

    TRY.
        rv_crequest = li_api->create_crequest( iv_crequest_type = iv_crequest_type
                                               iv_description   = iv_description
                                               iv_edition       = iv_edition ).
        mv_crequest = rv_crequest.
      CATCH cx_usmd_gov_api INTO DATA(lx).
        collect( it_messages = lx->mt_messages ix_error = lx ).
    ENDTRY.

  ENDMETHOD.


  METHOD zif_mdg_0g_cu~create_ref.

    DATA lr_tab TYPE REF TO data.
    CREATE DATA lr_tab TYPE STANDARD TABLE OF (iv_struct).

    FIELD-SYMBOLS <lt> TYPE STANDARD TABLE.
    ASSIGN lr_tab->* TO <lt>.
    IF <lt> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    MOVE-CORRESPONDING it_data TO <lt>.

    zif_mdg_0g_cu~write_data( iv_entity = iv_entity
                             iv_struct = iv_struct
                             ir_data   = lr_tab ).

  ENDMETHOD.


  METHOD zif_mdg_0g_cu~write_data.
    IF ir_data IS NOT BOUND.
      RETURN.
    ENDIF.
    APPEND VALUE #( entity = iv_entity
                    struct = iv_struct
                    data   = ir_data ) TO mt_buffer.
  ENDMETHOD.


  METHOD zif_mdg_0g_cu~enqueue_cr.

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


  METHOD zif_mdg_0g_cu~enqueue_entity.

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


  METHOD zif_mdg_0g_cu~flush.

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


  METHOD zif_mdg_0g_cu~save.

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


  METHOD zif_mdg_0g_cu~commit.

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


  METHOD zif_mdg_0g_cu~clear_buffers.
    CLEAR: mt_buffer, mt_message, mv_crequest.
  ENDMETHOD.


  METHOD zif_mdg_0g_cu~get_messages.
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

    FIELD-SYMBOLS <tab> TYPE STANDARD TABLE.
    ASSIGN lr->* TO <tab>.
    IF <tab> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    MOVE-CORRESPONDING it_src TO <tab>.
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
