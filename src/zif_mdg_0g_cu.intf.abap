INTERFACE zif_mdg_0g_cu
  PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : Stepwise Create / Update session against IF_USMD_GOV_API.
*           The implementation (ZCL_MDG_0G_CRUD) is a stateful singleton
*           that keeps an internal buffer of staged entity data:
*
*             create_crequest -> create_ref / write_data (x N)
*                             -> enqueue_cr -> enqueue_entity (x N)
*                             -> flush  (buffer -> Gov API buffers, buffer cleared)
*                             -> save   (draft, no check)
*                             -> commit (start_workflow [+ COMMIT WORK])
************************************************************************

  TYPES:
    "! One buffered entity payload
    BEGIN OF ts_buffer,
      entity TYPE usmd_entity,
      struct TYPE string,          " DDIC name of the line type behind DATA
      data   TYPE REF TO data,     " REF TO standard table of <struct>
    END OF ts_buffer,
    tt_buffer TYPE STANDARD TABLE OF ts_buffer WITH DEFAULT KEY.

  "! Create the change request (also resets the internal buffer / messages).
  METHODS create_crequest
    IMPORTING iv_crequest_type  TYPE usmd_crequest_type
              iv_description    TYPE usmd_txtlg
              iv_edition        TYPE usmd_edition OPTIONAL
    RETURNING VALUE(rv_crequest) TYPE usmd_crequest.

  "! Wrap a typed table in a data reference and put it into the internal
  "! buffer (convenience around write_data).
  METHODS create_ref
    IMPORTING iv_entity TYPE usmd_entity
              iv_struct TYPE string
              it_data   TYPE ANY TABLE.

  "! Put an entity data reference straight into the internal buffer.
  METHODS write_data
    IMPORTING iv_entity TYPE usmd_entity
              iv_struct TYPE string
              ir_data   TYPE REF TO data.

  "! Lock the change request.
  METHODS enqueue_cr.

  "! Lock one entity (key rows taken from the internal buffer).
  METHODS enqueue_entity
    IMPORTING iv_entity TYPE usmd_entity.

  "! Push the internal buffer into the Gov API buffers via write_entity,
  "! then clear the internal buffer.
  METHODS flush.

  "! Save the change request (draft, no check) and unlock it.
  METHODS save.

  "! Check, start the workflow and - if iv_commit - COMMIT WORK AND WAIT.
  METHODS commit
    IMPORTING iv_commit TYPE abap_bool DEFAULT abap_false.

  "! Drop the internal buffer, the collected messages and the CR id.
  METHODS clear_buffers.

  "! Messages collected across all calls since the last create_crequest / clear.
  METHODS get_messages
    RETURNING VALUE(rt_message) TYPE usmd_t_message.

ENDINTERFACE.
