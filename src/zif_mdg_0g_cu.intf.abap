INTERFACE zif_mdg_0g_cu
  PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : Stepwise Create / Update session against IF_USMD_GOV_API.
*           The implementation (ZCL_MDG_0G_CRUD) is a stateful singleton
*           that keeps an internal buffer of staged entity data:
*
*             create_crequest -> create_ref / write_data (x N)
*                             -> enqueue_cr
*                             -> enqueue_entity (x N)   locks the key rows
*                             -> flush  (buffer -> Gov API buffers via
*                                        write_entity, buffer cleared)
*                             -> dequeue_entity (x N)   releases those rows
*                             -> save   (draft, no check; dequeues the CR
*                                        and, as a safety net, every entity
*                                        lock still held)
*                             -> commit (start_workflow [+ COMMIT WORK])
*
*           Locking is symmetric per CLAUDE.md: enqueue_entity(key) ->
*           write_entity(key+attr) -> dequeue_entity(key). The DEQUEUE
*           must come AFTER flush( ), i.e. after write_entity; the
*           implementation therefore keeps its own lock registry instead
*           of re-deriving the key rows from the (by then cleared) buffer.
*           A caller that never dequeues is still safe: SAVE and
*           CLEAR_BUFFERS release everything that is still locked.
************************************************************************

  "! IF_USMD_GOV_API~CREATE_DATA_REFERENCE structure kinds (IV_STRUCT).
  CONSTANTS:
    BEGIN OF gc_struct,
      key   TYPE usmd_struct VALUE 'KEY',    "  keys only
      katta TYPE usmd_struct VALUE 'KATTA',  "  keys + USMD_S_ATTACHMENT
      kattw TYPE usmd_struct VALUE 'KATTW',  "  keys + USMD_S_ATTACHMENT_WO_CONTENT
      kattr TYPE usmd_struct VALUE 'KATTR',  "  keys + attributes (per IT_ATTRIBUTE)
      kfldp TYPE usmd_struct VALUE 'KFLDP',  "  data structure type
      kset  TYPE usmd_struct VALUE 'KSET',   "  key + SET
      ksets TYPE usmd_struct VALUE 'KSETS',  "  keys + SET (higher-level entity types)
      ktxt  TYPE usmd_struct VALUE 'KTXT',   "  keys + texts
      kltxt TYPE usmd_struct VALUE 'KLTXT',  "  keys + texts + LANGU
    END OF gc_struct.

  TYPES:
    "! One buffered entity payload - DATA is already a Gov-API-typed table
    "! (built by CREATE_REF for STRUCT), so FLUSH can hand it straight to
    "! write_entity.
    BEGIN OF ts_buffer,
      entity    TYPE usmd_entity,
      struct    TYPE usmd_struct,     " gc_struct-* kind DATA was created for
      data      TYPE REF TO data,     " REF TO the create_data_reference table
      attribute TYPE usmd_ts_fieldname, " attributes to write (KATTR, per FLUSH)
    END OF ts_buffer,
    tt_buffer TYPE STANDARD TABLE OF ts_buffer WITH DEFAULT KEY.

  "! Create the change request (also resets the internal buffer / messages).
  METHODS create_crequest
    IMPORTING iv_crequest_type  TYPE usmd_crequest_type
              iv_description    TYPE usmd_txtlg
              iv_edition        TYPE usmd_edition OPTIONAL
    RETURNING VALUE(rv_crequest) TYPE usmd_crequest.

  "! Create a Gov API reference table for IV_ENTITY / IV_STRUCT via
  "! IF_USMD_GOV_API~CREATE_DATA_REFERENCE. When IT_DATA is supplied its rows
  "! are MOVE-CORRESPONDING'd in. Does NOT buffer - fill it and hand it to
  "! WRITE_DATA (or pass your own already-typed table straight to WRITE_DATA).
  METHODS create_ref
    IMPORTING iv_entity      TYPE usmd_entity
              iv_struct      TYPE usmd_struct
              it_data        TYPE ANY TABLE OPTIONAL
    RETURNING VALUE(rr_data) TYPE REF TO data.

  "! Put an already Gov-API-typed table (see CREATE_REF) into the buffer.
  "! IT_ATTRIBUTE is passed on to WRITE_ENTITY at FLUSH time (KATTR writes).
  METHODS write_data
    IMPORTING iv_entity    TYPE usmd_entity
              iv_struct    TYPE usmd_struct
              ir_data      TYPE REF TO data
              it_attribute TYPE usmd_ts_fieldname OPTIONAL.

  "! Lock the change request.
  METHODS enqueue_cr.

  "! Lock one entity (key rows taken from the internal buffer). The key
  "! rows that were locked are remembered, so DEQUEUE_ENTITY can release
  "! exactly them after FLUSH has emptied the buffer.
  "! @parameter iv_entity | entity type to lock
  METHODS enqueue_entity
    IMPORTING iv_entity TYPE usmd_entity.

  "! Release the lock of ONE entity - call it after FLUSH, i.e. after the
  "! write_entity that the lock protects. Silent no-op (no dump, no
  "! message) when that entity is not locked, so calling it twice, or for
  "! an entity that was never enqueued, is harmless.
  "! @parameter iv_entity | entity type to unlock
  METHODS dequeue_entity
    IMPORTING iv_entity TYPE usmd_entity.

  "! Release EVERY entity lock still held by this session. Safety net for
  "! early RETURNs and error paths, where the caller does not know which
  "! entities got locked. No-op when nothing is locked.
  METHODS dequeue_all_entities.

  "! Push the internal buffer into the Gov API buffers via write_entity,
  "! then clear the internal buffer. Locks are NOT released here - that is
  "! DEQUEUE_ENTITY's job (or SAVE's safety net).
  METHODS flush.

  "! Release every entity lock still held, save the change request
  "! (draft, no check) and unlock the change request.
  METHODS save.

  "! Check, start the workflow and - if iv_commit - COMMIT WORK AND WAIT.
  METHODS commit
    IMPORTING iv_commit TYPE abap_bool DEFAULT abap_false.

  "! Release every entity lock still held, then drop the internal buffer,
  "! the collected messages and the CR id.
  METHODS clear_buffers.

  "! Messages collected across all calls since the last create_crequest / clear.
  METHODS get_messages
    RETURNING VALUE(rt_message) TYPE usmd_t_message.

ENDINTERFACE.
