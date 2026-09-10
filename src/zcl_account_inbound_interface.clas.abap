class ZCL_ACCOUNT_INBOUND_INTERFACE definition
  public
  final
  create public .

public section.

  interfaces IF_BADI_INTERFACE .
  interfaces IF_EX_GLACCTMSTRRPLCTNRQ .
protected section.
private section.
ENDCLASS.



CLASS ZCL_ACCOUNT_INBOUND_INTERFACE IMPLEMENTATION.


  method IF_EX_GLACCTMSTRRPLCTNRQ~INBOUND_PROCESSING.
  endmethod.


  method IF_EX_GLACCTMSTRRPLCTNRQ~OUTBOUND_PROCESSING.
  endmethod.
ENDCLASS.
