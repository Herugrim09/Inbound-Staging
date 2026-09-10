class ZCL_ACCOUNT_INBOUND_INTERFACE definition
  public
  final
  create public .

************************************************************************
* Project : Inbound-Staging
* Purpose : BAdI implementation class of ZMED_ACCOUNT_BULK_INBOUND_IMP
*           (spot FBS_SPOT_SE_GLACCTMSTRRPLCTNRQ, BAdI
*           FBS_SE_GLACCTMSTRRPLCTNRQ_ASYN) - the G/L Account twin of
*           ZCL_PCTR_INBOUND_INTERFACE. Holds NO logic: it hands the
*           payload node to ZCL_MDG_0G_ACC_WRAPPER and nothing else.
************************************************************************
public section.

  interfaces IF_BADI_INTERFACE .
  interfaces IF_EX_GLACCTMSTRRPLCTNRQ .
protected section.
private section.
ENDCLASS.



CLASS ZCL_ACCOUNT_INBOUND_INTERFACE IMPLEMENTATION.


  method IF_EX_GLACCTMSTRRPLCTNRQ~INBOUND_PROCESSING.

*   Entry point of the G/L Account replication inbound service.
*   Delegates to the wrapper: proxy payload -> 0G staging -> Change Request.
*
*   IS_INPUT_SINGLE (SAPPLCO_GLACCT_MSTR_RPLCTNRQMS) has three components:
*   CONTROLLER, MESSAGE_HEADER and the payload node
*   GENERAL_LEDGER_ACCOUNT_MASTER. Both the chart-of-accounts segment (A)
*   and the company code details (B) sit inside that one node, so the
*   mapper receives it whole.
*
*   TODO verify in SE24: IF_EX_GLACCTMSTRRPLCTNRQ~INBOUND_PROCESSING
*   parameter names - IS_INPUT_SINGLE / IO_FEH_REGISTRATION /
*   CS_WORK_STRUCTURE (TYPE FBS_SX_ACC_RPLCTN_WORK_STRUC).
*   CS_WORK_STRUCTURE is left untouched by this implementation.

    data lt_message type usmd_t_message.

*   IV_COMMIT = ABAP_TRUE: the change request is only persisted and its
*   workflow only started once the transaction is committed, so exactly
*   ONE "COMMIT WORK AND WAIT" is owed after FIRE (CLAUDE.md step 10).
*   It is issued in ZCL_MDG_0G_CRUD~COMMIT and nowhere else.
    new zcl_mdg_0g_acc_wrapper( )->process(
      exporting is_request  = is_input_single-general_ledger_account_master
                iv_commit   = abap_true
      importing ev_crequest = data(lv_crequest)
                et_message  = lt_message ).

*   TODO decision 7 (logging): LT_MESSAGE is currently only used to decide
*   whether to abort. The alternatives are an application log or
*   IO_FEH_REGISTRATION (Forward Error Handling); neither is wired up yet.

*   error / abort messages -> hand over to the proxy runtime, mirroring
*   ZCL_PCTR_INBOUND_INTERFACE. Note the CR is already committed at this
*   point, so the exception reports the failure - it does not undo it.
    loop at lt_message transporting no fields
         where msgty = 'E' or msgty = 'A' or msgty = 'X'.
      raise exception type cx_appl_proxy_badi_processing.
    endloop.

  endmethod.


  method IF_EX_GLACCTMSTRRPLCTNRQ~OUTBOUND_PROCESSING.
  endmethod.
ENDCLASS.
