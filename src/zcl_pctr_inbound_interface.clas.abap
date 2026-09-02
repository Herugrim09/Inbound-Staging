class ZCL_PCTR_INBOUND_INTERFACE definition
  public
  final
  create public .

public section.

  interfaces IF_BADI_INTERFACE .
  interfaces IF_KE1_SE_PRCTRRPLCTNBULKRQ .
protected section.
private section.
ENDCLASS.



CLASS ZCL_PCTR_INBOUND_INTERFACE IMPLEMENTATION.


  method IF_KE1_SE_PRCTRRPLCTNBULKRQ~INBOUND_PROCESSING.
  endmethod.


  method IF_KE1_SE_PRCTRRPLCTNBULKRQ~OUTBOUND_PROCESSING.
  endmethod.
ENDCLASS.
