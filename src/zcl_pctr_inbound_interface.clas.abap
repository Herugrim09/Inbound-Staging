class ZCL_PCTR_INBOUND_INTERFACE definition
  public
  final
  create public .

  public section.
    interfaces if_badi_interface .
    interfaces if_ke1_se_prctrrplctnbulkrq .
  protected section.
  private section.
ENDCLASS.



CLASS ZCL_PCTR_INBOUND_INTERFACE IMPLEMENTATION.


  method if_ke1_se_prctrrplctnbulkrq~inbound_processing.

*   Entry point of the Profit Center replication inbound service.
*   Delegates to the wrapper: proxy payload -> 0G staging -> Change Request.

    data lt_message type usmd_t_message.

    new zcl_mdg_0g_pctr_wrapper( )->process(
      exporting is_request  = in-profit_centre       " SAPPLCO_PRCTR_RQ_PRCTR node
      importing ev_crequest = data(lv_crequest)
                et_message  = lt_message ).

*   TODO: populate OUT (KE1_SX_PRCTR_RPLCTN_WS) - confirmation / FEH bulk
*         message + header, mirroring the KE1 input_mapping FEH pattern.
*   TODO: check SAPPLCO_ vs MDGF_ component names used by the mapper paths
*         (same ESR message, a few truncations differ).

*   error / abort messages -> let SOA Forward Error Handling take over
    loop at lt_message transporting no fields
         where msgty = 'E' or msgty = 'A' or msgty = 'X'.
      raise exception type cx_bs_soa_badi_processing.
    endloop.

  endmethod.


  method if_ke1_se_prctrrplctnbulkrq~outbound_processing.
  endmethod.
ENDCLASS.
