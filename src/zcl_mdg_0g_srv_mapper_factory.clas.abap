CLASS zcl_mdg_0g_srv_mapper_factory DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

************************************************************************
* Project : Inbound-Staging
* Purpose : Return the ZIF_MDG_0G_SRV_MAPPER implementation for an entity.
*           The BAdI / wrapper only ever sees the interface.
************************************************************************

  PUBLIC SECTION.

    CLASS-METHODS get
      IMPORTING iv_entity     TYPE usmd_entity
      RETURNING VALUE(ro_map) TYPE REF TO zif_mdg_0g_srv_mapper
      RAISING   zcx_mdg_0g_srv_mapper.

ENDCLASS.



CLASS zcl_mdg_0g_srv_mapper_factory IMPLEMENTATION.


  METHOD get.

    CASE iv_entity.
      WHEN 'PCTR'.
        ro_map = NEW zcl_mdg_0g_srv_mapper_pctr( ).
      WHEN 'ACCOUNT'.
*       confirmed: entity type of the outbound SMT mapping
*       USMDZ6_0G_ACCOUNT. Keep in sync with
*       ZCL_MDG_0G_SRV_MAPPER_ACC=>C_ENTITY_MAIN.
        ro_map = NEW zcl_mdg_0g_srv_mapper_acc( ).
*     WHEN 'CCTR'.
*       ro_map = NEW zcl_mdg_0g_srv_mapper_cctr( ).
      WHEN OTHERS.
        RAISE EXCEPTION NEW zcx_mdg_0g_srv_mapper(
          iv_text = |No service mapper for entity { iv_entity }| ).
    ENDCASE.

  ENDMETHOD.


ENDCLASS.
