CLASS zcx_mdg_0g_srv_mapper DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  CREATE PUBLIC.

************************************************************************
* Project : Inbound-Staging
* Purpose : Exception raised by the inbound service mappers
*           (ZIF_MDG_0G_SRV_MAPPER and its implementations).
************************************************************************

  PUBLIC SECTION.

    DATA mv_text TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING textid   LIKE textid   OPTIONAL
                previous LIKE previous OPTIONAL
                iv_text  TYPE string   OPTIONAL.

ENDCLASS.



CLASS zcx_mdg_0g_srv_mapper IMPLEMENTATION.


  METHOD constructor.
    super->constructor( textid = textid previous = previous ).
    mv_text = iv_text.
  ENDMETHOD.


ENDCLASS.
