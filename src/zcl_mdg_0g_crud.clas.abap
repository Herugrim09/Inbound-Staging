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
*           Entity locks are tracked in MT_LOCK (entity + the exact key
*           table handed to ENQUEUE_ENTITY) because FLUSH clears
*           MT_BUFFER before the dequeue is due. SAVE and CLEAR_BUFFERS
*           release whatever is still registered, so no lock outlives
*           the session even on an early RETURN or an error path.
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
  aliases DEQUEUE_ALL_ENTITIES
    for ZIF_MDG_0G_CU~DEQUEUE_ALL_ENTITIES .
  aliases DEQUEUE_ENTITY
    for ZIF_MDG_0G_CU~DEQUEUE_ENTITY .
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
  aliases GC_STRUCT
    for ZIF_MDG_0G_CU~GC_STRUCT .
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

    "! One granted entity lock: the entity plus the very key table that was
    "! handed to IF_USMD_GOV_API~ENQUEUE_ENTITY. Kept because FLUSH clears
    "! MT_BUFFER, so after the write the key rows cannot be re-derived from
    "! the buffer any more - a dequeue reading MT_BUFFER would release
    "! nothing.
  types:
    begin of TS_LOCK,
      ENTITY type USMD_ENTITY,
      R_KEYS type ref to DATA,
    end of TS_LOCK .
  types:
    TT_LOCK type standard table of TS_LOCK with default key .

  class-data GO_INSTANCE type ref to ZCL_MDG_0G_CRUD .
  data MV_MODEL type USMD_MODEL .
  data MV_CREQUEST type USMD_CREQUEST .
  data MV_EDITION type USMD_EDITION .
  data MT_BUFFER type ZIF_MDG_0G_CU=>TT_BUFFER .
    "! Lock registry - filled by ENQUEUE_ENTITY, emptied by RELEASE_LOCKS.
  data MT_LOCK type TT_LOCK .
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
  methods COLLECT
    importing
      !IT_MESSAGES type USMD_T_MESSAGE optional
      !IX_ERROR type ref to CX_ROOT optional .
    "! Release granted entity locks and forget them, so a second release is
    "! a no-op. The registry entries are dropped even when the Gov API is
    "! unreachable - otherwise every later release would retry forever.
    "! @parameter iv_entity | one entity; empty = release everything
  methods RELEASE_LOCKS
    importing
      !IV_ENTITY type USMD_ENTITY optional .
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

    clear_buffers( ).

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND.
      RETURN.
    ENDIF.

    " edition is mandatory - fall back to the always-open DUMMY edition.
    " kept in MV_EDITION so CREATE_REF can stamp it onto every generated row.
    DATA(lv_edition) = COND usmd_edition( WHEN iv_edition IS NOT INITIAL
                                          THEN iv_edition
                                          ELSE 'DUMMY' ).
    mv_edition = lv_edition.

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

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND.
      RETURN.
    ENDIF.

    TRY.
        li_api->create_data_reference( EXPORTING iv_entity_name = iv_entity
                                                 iv_struct      = iv_struct
                                                 iv_edition     = abap_true
                                       IMPORTING er_table       = rr_data ).
      CATCH cx_usmd_gov_api INTO DATA(lx).
        collect( it_messages = lx->mt_messages ix_error = lx ).
        CLEAR rr_data.
        RETURN.
    ENDTRY.

    IF it_data IS INITIAL.
      RETURN.
    ENDIF.

    FIELD-SYMBOLS <tab> TYPE ANY TABLE.
    ASSIGN rr_data->* TO <tab>.
    IF <tab> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    <tab> = CORRESPONDING #( it_data ).

*   stamp the CR edition onto every row (structure was generated with
*   IV_EDITION = ABAP_TRUE). Copy via work area - the reference table is a
*   sorted table and EDITION may be part of its key.
    IF mv_edition IS INITIAL.
      RETURN.
    ENDIF.

    DATA lr_tmp TYPE REF TO data.
    CREATE DATA lr_tmp LIKE <tab>.
    FIELD-SYMBOLS <tmp> TYPE ANY TABLE.
    ASSIGN lr_tmp->* TO <tmp>.

    DATA lr_wa TYPE REF TO data.
    CREATE DATA lr_wa LIKE LINE OF <tab>.
    FIELD-SYMBOLS <wa> TYPE any.
    ASSIGN lr_wa->* TO <wa>.

    LOOP AT <tab> ASSIGNING FIELD-SYMBOL(<row>).
      <wa> = <row>.
      ASSIGN COMPONENT usmd0_cs_fld-edition OF STRUCTURE <wa> TO FIELD-SYMBOL(<edi>).
      IF <edi> IS ASSIGNED.
        <edi> = mv_edition.
      ENDIF.
      INSERT <wa> INTO TABLE <tmp>.
    ENDLOOP.

    <tab> = <tmp>.

  ENDMETHOD.


  METHOD write_data.
    IF ir_data IS NOT BOUND.
      RETURN.
    ENDIF.
    APPEND VALUE #( entity    = iv_entity
                    struct    = iv_struct
                    data      = ir_data
                    attribute = it_attribute ) TO mt_buffer.
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
    FIELD-SYMBOLS <key> TYPE ANY TABLE.

    LOOP AT mt_buffer ASSIGNING FIELD-SYMBOL(<buf>) WHERE entity = iv_entity.

      IF <buf>-data IS NOT BOUND.
        CONTINUE.
      ENDIF.
      ASSIGN <buf>-data->* TO <src>.
      IF <src> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

      DATA lr_key TYPE REF TO data.
      TRY.
          li_api->create_data_reference( EXPORTING iv_entity_name = iv_entity
                                                   iv_struct      = li_api->gc_struct_key
                                         IMPORTING er_table       = lr_key ).
        CATCH cx_usmd_gov_api INTO DATA(lx_ref).
          collect( it_messages = lx_ref->mt_messages ix_error = lx_ref ).
          CONTINUE.
      ENDTRY.
      ASSIGN lr_key->* TO <key>.
      IF <key> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.
      <key> = CORRESPONDING #( <src> ).

      TRY.
          li_api->enqueue_entity( iv_crequest_id = mv_crequest
                                  iv_entity_name = iv_entity
                                  it_data        = <key> ).

*         lock granted -> remember exactly these key rows. LR_KEY points to
*         a fresh table per buffer row (CREATE_DATA_REFERENCE creates a new
*         object each time), so one registry entry per locked key table.
          APPEND VALUE #( entity = iv_entity
                          r_keys = lr_key ) TO mt_lock.

        CATCH cx_usmd_gov_api_entity_lock INTO DATA(lx_lock).
          collect( it_messages = lx_lock->mt_messages ix_error = lx_lock ).
        CATCH cx_usmd_gov_api INTO DATA(lx).
          collect( it_messages = lx->mt_messages ix_error = lx ).
      ENDTRY.

    ENDLOOP.

  ENDMETHOD.


  METHOD dequeue_entity.
    release_locks( iv_entity = iv_entity ).
  ENDMETHOD.


  METHOD dequeue_all_entities.
    release_locks( ).
  ENDMETHOD.


  METHOD release_locks.

*   Releases what ENQUEUE_ENTITY really locked (MT_LOCK), not what is left
*   in MT_BUFFER - FLUSH has cleared the buffer by the time the dequeue is
*   due, so a buffer-driven dequeue would silently release nothing.

    DATA(li_api) = api( ).

    IF li_api IS BOUND AND mv_crequest IS NOT INITIAL.

      FIELD-SYMBOLS <key> TYPE ANY TABLE.

      LOOP AT mt_lock ASSIGNING FIELD-SYMBOL(<lock>).

*       empty IV_ENTITY = release everything
        IF iv_entity IS NOT INITIAL AND <lock>-entity <> iv_entity.
          CONTINUE.
        ENDIF.

        IF <lock>-r_keys IS NOT BOUND.
          CONTINUE.
        ENDIF.
        ASSIGN <lock>-r_keys->* TO <key>.
        IF <key> IS NOT ASSIGNED.
          CONTINUE.
        ENDIF.

        TRY.
*           TODO verify in SE24: IF_USMD_GOV_API~DEQUEUE_ENTITY - parameter
*           names (IV_CREQUEST_ID / IV_ENTITY_NAME / IT_DATA, as documented
*           in CLAUDE.md and used for ENQUEUE_ENTITY) and which exceptions
*           it declares. If it declares none, both CATCH blocks below have
*           to go; if it declares only CX_USMD_GOV_API, drop the first one.
            li_api->dequeue_entity( iv_crequest_id = mv_crequest
                                    iv_entity_name = <lock>-entity
                                    it_data        = <key> ).
          CATCH cx_usmd_gov_api_entity_lock INTO DATA(lx_lock).
*           a failed unlock must never abort inbound processing
            collect( it_messages = lx_lock->mt_messages ix_error = lx_lock ).
          CATCH cx_usmd_gov_api INTO DATA(lx).
            collect( it_messages = lx->mt_messages ix_error = lx ).
        ENDTRY.

      ENDLOOP.

    ENDIF.

*   forget the entries in every case - releasing twice is then a no-op,
*   and an unreachable Gov API does not make later releases retry forever
    IF iv_entity IS INITIAL.
      CLEAR mt_lock.
    ELSE.
      DELETE mt_lock WHERE entity = iv_entity.
    ENDIF.

  ENDMETHOD.


  METHOD flush.

    DATA(li_api) = api( ).
    IF li_api IS NOT BOUND OR mv_crequest IS INITIAL.
      RETURN.
    ENDIF.

    FIELD-SYMBOLS <data> TYPE ANY TABLE.

    LOOP AT mt_buffer ASSIGNING FIELD-SYMBOL(<buf>).

      IF <buf>-data IS NOT BOUND.
        CONTINUE.
      ENDIF.
      ASSIGN <buf>-data->* TO <data>.
      IF <data> IS NOT ASSIGNED.
        CONTINUE.
      ENDIF.

*     DATA is already the create_data_reference table for <buf>-struct -
*     the framework reads its type and writes it accordingly
      TRY.
          li_api->write_entity( iv_crequest_id = mv_crequest
                                iv_entity_name = <buf>-entity
                                it_data        = <data>
                                it_attribute   = <buf>-attribute ).
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

*   safety net: per CLAUDE.md the entity locks are released before the
*   save. Callers that dequeued themselves leave nothing behind here (the
*   registry is already empty); callers that never dequeue - every caller
*   written before DEQUEUE_ENTITY existed - are covered by this line.
    release_locks( ).

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
*   last safety net: a caller that gives up half way (early RETURN after an
*   error) restarts with CREATE_CREQUEST, which calls CLEAR_BUFFERS. Release
*   before MV_CREQUEST is cleared - the dequeue needs the CR id.
    release_locks( ).
    CLEAR: mt_buffer, mt_message, mv_crequest, mv_edition.
  ENDMETHOD.


  METHOD get_messages.
    rt_message = mt_message.
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
