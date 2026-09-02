CLASS zcl_mdg_0g_cr_writer DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : Granular, reusable wrappers around IF_USMD_GOV_API for
*           creating, filling and firing a (follow-up) Change Request.
*           Call sequence modeled on S4E create_crequest_acc_company.
************************************************************************

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_s_staging,
        entity TYPE usmd_entity,
        data   TYPE REF TO data,          " table typed as /MDG/_SX_0G_<entity> (key + attributes)
      END OF ty_s_staging,
      ty_t_staging TYPE STANDARD TABLE OF ty_s_staging WITH DEFAULT KEY.

    CONSTANTS c_model_0g TYPE usmd_model VALUE '0G' ##NO_TEXT.

    METHODS constructor
      IMPORTING iv_model TYPE usmd_model DEFAULT c_model_0g.

    "! Create a CR, write the staged entity data into it, run the enqueue/dequeue
    "! sequence, save (draft, no check), check and start its workflow.
    "! No database commit unless iv_commit = abap_true.
    "! @parameter it_staging       | one entry per entity, data = key+attr table
    "! @parameter iv_source_cr     | parent CR to inherit edition/reason/notes/attachments from (optional)
    "! @parameter iv_commit        | COMMIT WORK AND WAIT after start_workflow
    METHODS create_and_fire
      IMPORTING
        it_staging       TYPE ty_t_staging
        iv_crequest_type TYPE usmd_crequest_type
        iv_description   TYPE usmd_txtlg
        iv_edition       TYPE usmd_edition OPTIONAL
        iv_source_cr     TYPE usmd_crequest OPTIONAL
        iv_commit        TYPE abap_bool DEFAULT abap_false
      EXPORTING
        ev_crequest      TYPE usmd_crequest
        et_message       TYPE usmd_t_message.

  PRIVATE SECTION.

    DATA mv_model TYPE usmd_model.
    DATA mi_api   TYPE REF TO if_usmd_gov_api.
    DATA mi_model TYPE REF TO if_usmd_model.

    METHODS get_api
      RETURNING VALUE(ri_api) TYPE REF TO if_usmd_gov_api
      RAISING   cx_usmd_gov_api.

    METHODS get_model
      RETURNING VALUE(ri_model) TYPE REF TO if_usmd_model.

    METHODS write_one_entity
      IMPORTING ii_api      TYPE REF TO if_usmd_gov_api
                iv_crequest TYPE usmd_crequest
                is_staging  TYPE ty_s_staging
      CHANGING  ct_message  TYPE usmd_t_message.

    METHODS link_predecessor
      IMPORTING iv_new_cr    TYPE usmd_crequest
                iv_source_cr TYPE usmd_crequest
      CHANGING  ct_message   TYPE usmd_t_message.

    METHODS copy_notes
      IMPORTING ii_api     TYPE REF TO if_usmd_gov_api
                iv_from_cr TYPE usmd_crequest
                iv_to_cr   TYPE usmd_crequest
      CHANGING  ct_message TYPE usmd_t_message.

    METHODS copy_attachments
      IMPORTING ii_api     TYPE REF TO if_usmd_gov_api
                iv_from_cr TYPE usmd_crequest
                iv_to_cr   TYPE usmd_crequest
      CHANGING  ct_message TYPE usmd_t_message.

    METHODS collect
      IMPORTING it_messages TYPE usmd_t_message OPTIONAL
                ix_error    TYPE REF TO cx_root OPTIONAL
      CHANGING  ct_message  TYPE usmd_t_message.

ENDCLASS.



CLASS zcl_mdg_0g_cr_writer IMPLEMENTATION.


  METHOD constructor.
    mv_model = iv_model.
  ENDMETHOD.


  METHOD create_and_fire.

    CLEAR: ev_crequest, et_message.

    IF it_staging IS INITIAL.
      RETURN.
    ENDIF.

    DATA li_api TYPE REF TO if_usmd_gov_api.
    TRY.
        li_api = get_api( ).
      CATCH cx_usmd_gov_api INTO DATA(lx_api).
        collect( EXPORTING it_messages = lx_api->mt_messages ix_error = lx_api
                 CHANGING  ct_message  = et_message ).
        RETURN.
    ENDTRY.

*   --- edition: caller value, else inherited from the source CR ----------
    DATA(lv_edition) = iv_edition.
    IF iv_source_cr IS NOT INITIAL.
      li_api->get_crequest_attributes(
        EXPORTING iv_crequest_id = iv_source_cr
        RECEIVING rs_crequest    = DATA(ls_src_attr) ).
      IF lv_edition IS INITIAL.
        lv_edition = ls_src_attr-usmd_edition.
      ENDIF.
    ENDIF.

*   --- create + lock the CR --------------------------------------------
    TRY.
        ev_crequest = li_api->create_crequest(
          iv_crequest_type = iv_crequest_type
          iv_description   = iv_description
          iv_edition       = lv_edition ).
      CATCH cx_usmd_gov_api INTO lx_api.
        collect( EXPORTING it_messages = lx_api->mt_messages ix_error = lx_api
                 CHANGING  ct_message  = et_message ).
        RETURN.
    ENDTRY.

    li_api->enqueue_crequest( EXPORTING iv_crequest_id = ev_crequest ).

*   --- write staged data, entity by entity ----------------------------
    LOOP AT it_staging INTO DATA(ls_staging).
      write_one_entity( EXPORTING ii_api      = li_api
                                  iv_crequest = ev_crequest
                                  is_staging  = ls_staging
                        CHANGING  ct_message  = et_message ).
    ENDLOOP.

*   --- inherit context from the source CR (follow-up scenario only) ---
    IF iv_source_cr IS NOT INITIAL.
      link_predecessor( EXPORTING iv_new_cr    = ev_crequest
                                  iv_source_cr = iv_source_cr
                        CHANGING  ct_message   = et_message ).
      copy_notes( EXPORTING ii_api     = li_api
                            iv_from_cr = iv_source_cr
                            iv_to_cr   = ev_crequest
                  CHANGING  ct_message = et_message ).
      copy_attachments( EXPORTING ii_api     = li_api
                                  iv_from_cr = iv_source_cr
                                  iv_to_cr   = ev_crequest
                        CHANGING  ct_message = et_message ).
    ENDIF.

*   --- save / check / fire -------------------------------------------
    li_api->save( i_mode = if_usmd_ui_services=>gc_save_mode_draft_no_check ).
    li_api->dequeue_crequest( EXPORTING iv_crequest_id = ev_crequest ).

    TRY.
        li_api->check_crequest_data( iv_crequest_id = ev_crequest ).
      CATCH cx_usmd_gov_api_core_error INTO DATA(lx_core).
        collect( EXPORTING it_messages = lx_core->mt_messages ix_error = lx_core
                 CHANGING  ct_message  = et_message ).
      CATCH cx_usmd_gov_api INTO lx_api.
        collect( EXPORTING it_messages = lx_api->mt_messages ix_error = lx_api
                 CHANGING  ct_message  = et_message ).
    ENDTRY.

    TRY.
        li_api->if_usmd_gov_api_process~start_workflow( EXPORTING iv_crequest_id = ev_crequest ).
      CATCH cx_usmd_gov_api_core_error INTO lx_core.
        collect( EXPORTING it_messages = lx_core->mt_messages ix_error = lx_core
                 CHANGING  ct_message  = et_message ).
    ENDTRY.

    IF iv_commit = abap_true.
      COMMIT WORK AND WAIT.
    ENDIF.

  ENDMETHOD.


  METHOD write_one_entity.

    FIELD-SYMBOLS <lt_src>     TYPE ANY TABLE.
    FIELD-SYMBOLS <lt_key>     TYPE ANY TABLE.
    FIELD-SYMBOLS <lt_keyattr> TYPE ANY TABLE.

    IF is_staging-data IS NOT BOUND.
      RETURN.
    ENDIF.
    ASSIGN is_staging-data->* TO <lt_src>.
    IF <lt_src> IS NOT ASSIGNED OR <lt_src> IS INITIAL.
      RETURN.
    ENDIF.

    ii_api->create_data_reference( EXPORTING iv_entity_name = is_staging-entity
                                             iv_struct      = ii_api->gc_struct_key
                                   IMPORTING er_table       = DATA(lr_key) ).
    ii_api->create_data_reference( EXPORTING iv_entity_name = is_staging-entity
                                             iv_struct      = ii_api->gc_struct_key_attr
                                   IMPORTING er_table       = DATA(lr_keyattr) ).

    ASSIGN lr_key->*     TO <lt_key>.
    ASSIGN lr_keyattr->* TO <lt_keyattr>.
    IF <lt_key> IS NOT ASSIGNED OR <lt_keyattr> IS NOT ASSIGNED.
      RETURN.
    ENDIF.

    MOVE-CORRESPONDING <lt_src> TO <lt_key>.
    MOVE-CORRESPONDING <lt_src> TO <lt_keyattr>.

    TRY.
        ii_api->enqueue_entity( EXPORTING iv_crequest_id = iv_crequest
                                          iv_entity_name = is_staging-entity
                                          it_data        = <lt_key> ).
      CATCH cx_usmd_gov_api_entity_lock INTO DATA(lx_lock).
        collect( EXPORTING it_messages = lx_lock->mt_messages ix_error = lx_lock
                 CHANGING  ct_message  = ct_message ).
        RETURN.
    ENDTRY.

    TRY.
        ii_api->write_entity( EXPORTING iv_crequest_id = iv_crequest
                                        iv_entity_name = is_staging-entity
                                        it_data        = <lt_keyattr> ).
      CATCH cx_usmd_gov_api_entity_write INTO DATA(lx_write).
        collect( EXPORTING it_messages = lx_write->mt_messages ix_error = lx_write
                 CHANGING  ct_message  = ct_message ).
    ENDTRY.

    ii_api->dequeue_entity( EXPORTING iv_crequest_id = iv_crequest
                                      iv_entity_name = is_staging-entity
                                      it_data        = <lt_key> ).

  ENDMETHOD.


  METHOD link_predecessor.

    DATA lt_cr     TYPE usmd_cr_ts_root.
    DATA lt_cr_old TYPE usmd_cr_ts_root.

    DATA(li_model) = get_model( ).
    IF li_model IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA(lt_sel) = VALUE usmd_ts_sel(
      ( fieldname = usmd0_cs_fld-crequest sign = usmd0_cs_ra-sign_i
        option    = usmd0_cs_ra-option_eq low = iv_new_cr ) ).
    li_model->read_char_value( EXPORTING i_fieldname = usmd0_cs_fld-crequest
                                         it_sel      = lt_sel
                               IMPORTING et_data     = lt_cr ).

    lt_sel = VALUE usmd_ts_sel(
      ( fieldname = usmd0_cs_fld-crequest sign = usmd0_cs_ra-sign_i
        option    = usmd0_cs_ra-option_eq low = iv_source_cr ) ).
    li_model->read_char_value( EXPORTING i_fieldname = usmd0_cs_fld-crequest
                                         it_sel      = lt_sel
                               IMPORTING et_data     = lt_cr_old ).

    ASSIGN lt_cr[ usmd_crequest = iv_new_cr ] TO FIELD-SYMBOL(<ls_cr>).
    IF sy-subrc = 0.
      <ls_cr>-usmd_crequest_re = iv_source_cr.
      IF lt_cr_old IS NOT INITIAL.
        <ls_cr>-usmd_reason = lt_cr_old[ 1 ]-usmd_reason.
      ENDIF.
      li_model->write_char_value( EXPORTING i_fieldname = usmd0_cs_fld-crequest
                                            it_data     = lt_cr ).
    ENDIF.

  ENDMETHOD.


  METHOD copy_notes.

    TRY.
        DATA(lt_notes) = ii_api->get_notes( iv_crequest_id = iv_from_cr ).
      CATCH cx_usmd_gov_api_core_error INTO DATA(lx_core).
        collect( EXPORTING it_messages = lx_core->mt_messages ix_error = lx_core
                 CHANGING  ct_message  = ct_message ).
        RETURN.
    ENDTRY.

    LOOP AT lt_notes ASSIGNING FIELD-SYMBOL(<ls_note>).
      TRY.
          ii_api->write_note( EXPORTING iv_crequest_id = iv_to_cr
                                        iv_note        = <ls_note>-usmd_note ).
        CATCH cx_usmd_gov_api_core_error INTO lx_core.
          collect( EXPORTING it_messages = lx_core->mt_messages ix_error = lx_core
                   CHANGING  ct_message  = ct_message ).
        CATCH cx_usmd_gov_api INTO DATA(lx_api).
          collect( EXPORTING it_messages = lx_api->mt_messages ix_error = lx_api
                   CHANGING  ct_message  = ct_message ).
      ENDTRY.
    ENDLOOP.

  ENDMETHOD.


  METHOD copy_attachments.

    TRY.
        DATA(lt_att) = ii_api->get_attachment_list( iv_crequest_id  = iv_from_cr
                                                    if_with_content = abap_true ).
      CATCH cx_usmd_gov_api_core_error INTO DATA(lx_core).
        collect( EXPORTING it_messages = lx_core->mt_messages ix_error = lx_core
                 CHANGING  ct_message  = ct_message ).
        RETURN.
    ENDTRY.

    LOOP AT lt_att ASSIGNING FIELD-SYMBOL(<ls_att>).
      TRY.
          ii_api->add_attachment( EXPORTING iv_crequest_id = iv_to_cr
                                            is_attachment  = <ls_att>-data ).
        CATCH cx_usmd_gov_api_core_error INTO lx_core.
          collect( EXPORTING it_messages = lx_core->mt_messages ix_error = lx_core
                   CHANGING  ct_message  = ct_message ).
        CATCH cx_usmd_gov_api INTO DATA(lx_api).
          collect( EXPORTING it_messages = lx_api->mt_messages ix_error = lx_api
                   CHANGING  ct_message  = ct_message ).
      ENDTRY.
    ENDLOOP.

  ENDMETHOD.


  METHOD get_api.
    IF mi_api IS NOT BOUND.
      mi_api = cl_usmd_gov_api=>get_instance( iv_model_name = mv_model ).
    ENDIF.
    ri_api = mi_api.
  ENDMETHOD.


  METHOD get_model.
    IF mi_model IS NOT BOUND.
      cl_usmd_model=>get_instance( EXPORTING i_usmd_model = mv_model
                                   IMPORTING eo_instance  = mi_model ).
    ENDIF.
    ri_model = mi_model.
  ENDMETHOD.


  METHOD collect.
    APPEND LINES OF it_messages TO ct_message.
    IF it_messages IS INITIAL AND ix_error IS BOUND.
      APPEND VALUE #( msgty = 'E'
                      msgid = '00'
                      msgno = '398'
                      msgv1 = ix_error->get_text( ) ) TO ct_message.
    ENDIF.
  ENDMETHOD.


ENDCLASS.
