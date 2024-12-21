CREATE OR REPLACE PACKAGE BODY APPS.XXFASCOR_SO_API
AS
    /*****************************************************************************
    Program Name:      XXFASCOR_SO_API
    Program Type:      Data base procedure
    Program file:      XXFASCOR_SO_API.sql
    Author:            Thrinadh Potupureddi
    Program Description: This package will send SO from Oracle EBS to FASCOR
    Change History:
    -----------------------------------------------------------------------------
    Date               Name                     Version         Change Description
    -----------------------------------------------------------------------------
    22-Aug-2019       Thrinadh Potupureddi        1.0            Initial Version
    11-Oct-2019       K.Venkatesh                 1.1            Added Additional information in Log Files
    08-Nov-2019       K.Venkatesh                 1.2            Changes Order Status from OKAY to HOLD
                                                                 Insert new header record with mode status U and order status OKAY in xxfascor_wms_utils
    21-NOV-2019       K,Venkatesh                 1.3            Disabled call to send SO communication to FASCOR
    03-DEC-2019       K.Venkatesh                 1.4            Sending new fields to Fascor for Order Number, End Cust PO and Residential in PO Additional table  BS #010940
    15-May-2020       K.Venkatesh                 1.5            Added E/U Phone and E/U Contact in Additional DFF - BS #014356
    06-Aug-2020       K.Venkatesh                 1.6            MissingSOAdditionalInfoforhavingBSLAWarehouseatHeader- BS #015651
    27-Jan-2021       K.Venkatesh                 1.7            Add Packing Instructions to 1330 Messages BSLA - BS #018268
    14-Jun-2022       Santosh SRISYS              1.8            4569-BSI-BPS-PDB-OM-AddingErrorTableInFASCORSOOutboundProgram-230614  -- BS #033236
    07-Aug-2023       Santosh SRISYS              1.9            4591[#033849]-BSI-BPS-PDB-OM-FascorInterface-OutboundOrdersNegativeSellPriceInsuranceCalc-230803
    10-Apr-2024       Surya SRISYS                2.0            4775[#038026]-BSI-BPS-PDB-FASCOR-SalesPersonDataToFascor-240410
    31-May-2024       Surya SRISYS                2.1            4812[#038839]-BSI-BPS-PDB-FASCOR-AllGoodToday5/22NoDelays-240528
    24-Oct-2024       Santosh SRISYS              2.2            4598-[#033954]-BSI-BPS-PDB-OM-CreateTablesForFascorErrorsWhichAreNotInTheStagingTables 230811
    10-DEC-2024       SURYA SRISYS                2.3            4917[#042314]-BSI-BPS-PDB-OM-CanSalesPersonBeEmailedToAddressTheIssueIffailedToStageFascorData -241114
    ------------------------------------------------------------------------------
    *****************************************************************************/
    PROCEDURE MAIN (ERRBUF OUT VARCHAR2, RETCODE OUT NUMBER)
    AS
        l_hdr_insert               VARCHAR2 (5);
        l_line_insert              VARCHAR2 (5);
        l_header_id                NUMBER;
        l_instance_url             VARCHAR2 (1);
        l_email_status             VARCHAR2 (4000);
        l_so_chk                   VARCHAR2 (1);
        l_so_number                NUMBER;
        l_debug_level              NUMBER := 0;
        l_record_status            VARCHAR2 (1);
        l_order_type_upd           NUMBER;
        l_order_date_upd           NUMBER;
        l_ship_to_upd              NUMBER;
        l_line_chk                 VARCHAR2 (1);
        l_qty_upd                  NUMBER;
        l_soheader_cnt             NUMBER := 0;
        l_soline_cnt               NUMBER := 0;
        l_soheader_rec             XXFASCOR_SOHEADER_STG%ROWTYPE;
        l_soline_rec               XXFASCOR_SOLINES_STG%ROWTYPE;
        l_ord_obj_det_rec          XXFASCOR_SOADDTIONAL_INFO_STG%ROWTYPE;
        l_ord_obj_ln_rec           XXFASCOR_SOADDTIONAL_INFO_STG%ROWTYPE;
        l_fas_mv_rec               XXFASCOR_MOVEORDER_LINE_STG%ROWTYPE;
        x_return_status            VARCHAR2 (1);
        x_return_message           VARCHAR2 (2000);
        lv_request_id              PLS_INTEGER := fnd_global.conc_request_id;
        l_bill_party_name          VARCHAR2 (360);
        l_bill_address1            VARCHAR2 (240);
        l_bill_address2            VARCHAR2 (240);
        l_bill_address3            VARCHAR2 (240);
        l_bill_address4            VARCHAR2 (240);
        l_bill_city                VARCHAR2 (60);
        l_bill_state               VARCHAR2 (60);
        l_bill_postal_code         VARCHAR2 (60);
        l_bill_country             VARCHAR2 (60);
        l_bill_to_location         NUMBER;
        l_delivery_chk             VARCHAR2 (1);
        l_order_fill_control       VARCHAR2 (1);
        l_Order_Fill_Percentage    VARCHAR2 (8);
        l_Order_Fill_Calculation   VARCHAR2 (1);
        l_Order_Fill_Action        VARCHAR2 (4);
        l_obj_c                    NUMBER;
        l_object_id                VARCHAR2 (8);
        l_object_text              VARCHAR2 (278);
        l_delivery_id              NUMBER;
        l_signature                VARCHAR2 (240);
        l_err_msg                  VARCHAR2 (1000);
        l_retcode                  NUMBER;
        l_ship_set_cnt             NUMBER;
        l_error_flag               VARCHAR2 (1);
        l_order_number             VARCHAR2 (30);                       --V1.8
        l_del_id                   VARCHAR2 (30);                       --V1.8
        l_type                     VARCHAR2 (30);                       --V1.8
        l_error                    VARCHAR2(32767);                     --V1.8
        l_order_number_1           VARCHAR2 (30) := 'X';                --V1.8
        l_del_id_1                 VARCHAR2 (30) := 'Y';                --V1.8
        l_address_check            VARCHAR2 (1);                        --V1.8
        l_message_type             VARCHAR2(250);                       --V2.2
        l_detail_seq_nbr           NUMBER;                              --V2.2
        l_sku                      VARCHAR2(50);                        --V2.2
        
        mail_conn                  utl_smtp.connection;                 -- V2.3
        l_database_name            VARCHAR2(250) :=apps.xxbsi_util.where_am_i;  -- V2.3
        l_salesrep_name            VARCHAR2(250);                       -- V2.3
        l_salesrep_email           VARCHAR2(250);                       -- V2.3
        l_message_body             VARCHAR2(32767);                     -- V2.3
        l_error_message            VARCHAR2(32767);                     -- V2.3
        l_error_cnt                NUMBER := 0;                         -- V2.3
        l_from_email               VARCHAR2(250);                       -- V2.3
        l_email_dflt               VARCHAR2(250);                       -- V2.3
        mailhost                   VARCHAR2(250);                       -- V2.3
        l_default_email            VARCHAR2(250);                       -- V2.3
        p_error                    VARCHAR2(250);                       -- V2.3
        ---- 
        TYPE ErrMsgType IS TABLE OF VARCHAR2(500);                              -- V2.3
        --
        ErrMsgType_Tbl  ErrMsgType    := ErrMsgType();                          -- V2.3
        l_cnt                       NUMBER;                                     -- V2.3
        --
        CURSOR pick_header IS
            SELECT DISTINCT oha.order_number,oha.header_id,
                            wda.delivery_id,
                            flv.meaning     facility_nbr,
                            ood.organization_code
              FROM oe_order_headers_all          oha,
                   wsh_delivery_details          wdd,
                   wsh_delivery_assignments      wda,
                   oe_transaction_types_tl       ott,
                   org_organization_definitions  ood,
                   fnd_lookup_values_vl          flv
             WHERE     1 = 1
                   AND oha.header_id         = wdd.source_header_id
                   AND wdd.delivery_detail_id = wda.delivery_detail_id
                   AND oha.order_type_id     = ott.transaction_type_id
                   AND ott.LANGUAGE          = 'US'
                   AND wdd.organization_id   = ood.organization_id
                   AND NVL(WDD.LOCATOR_ID,1) = NVL(NULL,NVL(WDD.LOCATOR_ID,1))                              -- V2.1
                   AND ood.organization_code = flv.lookup_code
                   AND flv.lookup_type       = 'XXFASCOR_WAREHOUSE_LKUP'
                   AND flv.enabled_flag      = 'Y'
                   AND SYSDATE BETWEEN NVL (flv.start_date_active,SYSDATE - 1)AND NVL (flv.end_date_active, SYSDATE + 1)
                   AND wdd.batch_id IS NOT NULL
                   AND (   (    wdd.released_status = 'S'
                            AND oha.flow_status_code = 'BOOKED'
                            AND wda.delivery_id IS NOT NULL
--                            AND wdd.move_order_line_id NOT IN                                             --V2.1
                            AND NOT EXISTS      (SELECT 1  --xmvl.move_order_line_id                        --V2.1
                                                   FROM xxfascor_soheader_stg        xsh
                                                       ,xxfascor_solines_stg         xsl
                                                       ,xxfascor_moveorder_line_stg  xmvl
                                                  WHERE     xsh.order_id             = xsl.order_id
                                                        AND xsl.detail_seq_nbr       = xmvl.fascor_order_line
                                                        AND xmvl.move_order_line_id  = wdd.move_order_line_id
                                                        AND xmvl.fascor_facility_nbr = flv.meaning
                                                        AND xsl.mode_status          = 'A'))
                        OR (    wdd.released_status = 'D'
                            AND wdd.move_order_line_id IS NOT NULL
                            AND oha.flow_status_code IN
                                    ('CANCELLED', 'CLOSED')
--                            AND wdd.delivery_detail_id IN                                                     --V2.1
                            AND EXISTS (SELECT 1 -- xsl.delivery_detail_id                                      --V2.1
                                       FROM xxfascor_soheader_stg        xsh,
                                            xxfascor_solines_stg         xsl,
                                            xxfascor_moveorder_line_stg  xmvl
                                      WHERE     xsh.order_id = xsl.order_id
                                            AND xsl.detail_seq_nbr       = xmvl.fascor_order_line
                                            AND xmvl.move_order_line_id  = wdd.move_order_line_id
                                            AND xsl.delivery_detail_id   = wdd.delivery_detail_id                 --V2.1
                                            AND xmvl.fascor_facility_nbr = flv.meaning
                                            AND xsl.mode_status          = 'A')
--                            AND wdd.delivery_detail_id NOT IN                                                 --V2.1
                              AND NOT EXISTS    (SELECT 1      -- xsl.delivery_detail_id                        --V2.1
                                                   FROM xxfascor_soheader_stg        xsh,
                                                        xxfascor_solines_stg         xsl,
                                                        xxfascor_moveorder_line_stg  xmvl
                                                  WHERE     xsh.order_id = xsl.order_id
                                                        AND xsl.detail_seq_nbr       = xmvl.fascor_order_line
                                                        AND xmvl.move_order_line_id  = wdd.move_order_line_id
                                                        AND xsl.delivery_detail_id   = wdd.delivery_detail_id     --V2.1
                                                        AND xmvl.fascor_facility_nbr = flv.meaning
                                                        AND xsl.mode_status          = 'D')));
        --
        CURSOR pick_lines (p_order_number NUMBER,p_delivery_id NUMBER)          --V2.1
        IS
                SELECT  flv.meaning        facility_nbr
                ,         oh.order_number
                ,         wda.delivery_id
                ,         wdd.move_order_line_id
                ,         TO_CHAR (oh.ordered_date, 'yyyy-mm-dd"T"hh24:mi:ss"Z"')        order_date
                ,         oh.org_id
                ,         oh.order_type_id       order_type
                ,         oh.return_reason_code  order_reason_code
                ,         NVL (TO_CHAR (wps.detailing_date, 'yyyy-mm-dd"T"hh24:mi:ss"Z"'),SYSDATE)   order_ship_date
                ,         SUBSTR (TO_CHAR (ol.schedule_ship_date, 'DAY'), 1, 2)  order_ship_day
                --,       oh.freight_carrier_code carrier_id
                ,         oh.shipping_method_code    carrier_id
                --,       SUBSTR (oh.shipping_method_code, 1, 10) shipping_terms
                ,         oh.freight_terms_code       shipping_terms
                ,         oh.sold_to_org_id          sold_to_customer_id
                ,         oh.cust_po_number          sold_to_customer_po_ref
                ,         oh.ship_to_org_id          ship_to_customer_id
                ,         hcsu.location              ship_to_location
                ,         oh.invoice_to_org_id
                ,         hl.attribute20             address_check              -- V2.3
                ,         hp.party_name              ship_to_customer_name
                ,         hp.party_name              ship_to_customer_abbrev_name
                ,         hl.address1                ship_to_customer_addr1
                ,         hl.address2                ship_to_customer_addr2
                ,         hl.address3                ship_to_customer_addr3
                ,         hl.address4                ship_to_customer_addr4
                ,         hl.city                    ship_to_customer_city
                --     ,  NVL (hl.state, 'US') ship_to_customer_stat
                ,         DECODE (oh.org_id,121, NVL (hl.state, hl.province),124, NVL (hl.province, hl.state),NVL (hl.state, hl.province))   ship_to_customer_state
                ,         REGEXP_REPLACE (hl.postal_code, '-')       ship_to_customer_zip
                ,         hl.country                                 ship_to_customer_country_code
                ,         NVL (oh.partial_shipments_allowed, 'Y')    partial_shipment_control
                ,         ol.ordered_item                            sku
                --     ,  ol.ordered_quantity sku_original_qty
                ,         wdd.requested_quantity                     sku_original_qty
                --     ,  NVL (wdd.requested_quantity, 0) sku_ship_qty
                ,         wdd.requested_quantity                     sku_ship_qty
                ,         ol.order_quantity_uom                      sku_uom
                ,         oh.created_by
                ,         NVL (oh.cancelled_flag, 'N')               so_header_cancel
                ,         NVL (ol.cancelled_flag, 'N')               so_line_cancel
                ,         wdd.released_status
                ,         ol.flow_status_code
                ,         wdd.delivery_detail_id
                ,         ol.ship_set_id
                ,         ol.unit_selling_price                      sku_insure_value
                ,         wps.from_subinventory sku_class
                ,         DECODE (ol.shipping_instructions, NULL, NULL, 'TRUNCATED :' || SUBSTR (ol.shipping_instructions, 1, 78))       line_comments_1
                ,         DECODE (ol.packing_instructions, NULL, NULL, 'TRUNCATED :' || SUBSTR (ol.packing_instructions, 1, 78))         line_comments_2
                ,         ol.ship_to_org_id
                ,         oh.salesrep_id
                    FROM oe_order_headers_all        oh,
                         oe_order_lines_all          ol,
                         oe_transaction_types_tl     ott,
                         wsh_delivery_details        wdd,
                         wsh_pick_slip_v             wps,
                         wsh_delivery_assignments    wda,
                         mtl_system_items_b          msb,
                         oe_sets                     os,
                         org_organization_definitions ood,
                         fnd_lookup_values_vl        flv,
                         hz_parties                  hp,
                         hz_cust_accounts_all        hca,
                         hz_party_sites              hps,
                         hz_locations                hl,
                         hz_cust_acct_sites_all      hcsa,
                         hz_cust_site_uses_all       hcsu
                   WHERE     oh.header_id = ol.header_id
                       --AND  oh.flow_status_code IN ( 'BOOKED','CANCELLED')
                         AND oh.order_type_id = ott.transaction_type_id
                         AND ott.LANGUAGE           = 'US'
                         AND ol.flow_status_code IN ('AWAITING_SHIPPING', 'CANCELLED')
                         AND ol.line_id             = wdd.source_line_id
                         AND wdd.delivery_detail_id = wda.delivery_detail_id
                         AND wdd.move_order_line_id = wps.move_order_line_id(+)
                         AND wdd.released_status IN ('S', 'D')
                         AND wdd.move_order_line_id IS NOT NULL
                         AND msb.organization_id   = ol.ship_from_org_id
                         AND msb.inventory_item_id = ol.inventory_item_id
                         AND ol.ship_from_org_id   = ood.organization_id
                         AND ood.organization_code = flv.lookup_code
                         AND flv.lookup_type       = 'XXFASCOR_WAREHOUSE_LKUP'
                         AND flv.enabled_flag      = 'Y'
                         AND SYSDATE BETWEEN NVL (flv.start_date_active, SYSDATE - 1) AND NVL (flv.end_date_active, SYSDATE + 1)
                         AND hp.party_id            = hca.party_id
                         AND hp.party_id            = hps.party_id
                         AND hps.location_id        = hl.location_id
                         AND hca.cust_account_id    = oh.sold_to_org_id
                         AND hca.cust_account_id    = hcsa.cust_account_id
                         AND hcsa.party_site_id     = hps.party_site_id
                         AND hcsa.cust_acct_site_id = hcsu.cust_acct_site_id
                         AND oh.ship_to_org_id      = hcsu.site_use_id
                         AND os.set_id(+)           = ol.ship_set_id
                         AND oh.order_number        = p_order_number
                         AND wda.delivery_id        = p_delivery_id             -- V2.1
                ORDER BY oh.order_number;
        --additional info--
        CURSOR c_hdr_addl (p_header_id NUMBER)  -- V2.1
        IS
            SELECT DISTINCT object_id, object_text
--             ,facility_nbr              --V2.1
              FROM (SELECT
--              flv.meaning facility_nbr, --V2.1
                           ooh.attribute2,
                           hp.party_name,
                           hl.address1,
                           hl.address2,
                           hl.address3,
                           hl.address4,
                           hl.city,
                           DECODE (ooh.org_id,121, NVL (hl.state, hl.province),124, NVL (hl.province, hl.state),NVL (hl.state, hl.province)) state,
                           hl.postal_code,
                           hl.country,
                           ooh.attribute10,
                           TO_CHAR (ooh.order_number) order_number,             -- V1.4
                           DECODE (ooh.attribute5, 'RESIDENTIAL', 'Y', NULL) Res_addr,
                           ooh.attribute1,                             -- V1.4
                           ooh.attribute11,
                           ooh.attribute12,
                           SUBSTR (ooh.packing_instructions, 1, 240) packing_instructions,      -- V1.5 --V1.7
                            jre.resource_name                    --V2.0
                      FROM oe_order_headers_all           ooh
--                         ,oe_order_lines_all            ool                   -- V2.1
                           ,jtf_rs_salesreps              srep                  -- V2.0
                           ,jtf_rs_resource_extns_vl      jre                   -- V2.0
--                         ,wsh_delivery_assignments      wda                   -- V2.1
--                         ,wsh_delivery_details          wdd                   -- V2.1
                           ,hz_cust_accounts_all          hca
--                         ,org_organization_definitions  ood                   -- V2.1
--                         ,fnd_lookup_values_vl          flv                   -- V2.1
                           ,hz_parties                    hp
                           ,hz_cust_acct_sites_all        hcasa
                           ,hz_cust_site_uses_all         hcsu
                           ,hz_party_sites                hps
                           ,hz_locations                  hl
                     WHERE     1 = 1
--                         AND ooh.header_id    = ool.header_id                 -- V2.1
                           AND ooh.salesrep_id  = srep.SALESREP_ID              --V2.0
                           AND srep.RESOURCE_ID = jre.RESOURCE_ID               --V2.0
--                         AND ool.line_id   = wdd.source_line_id               -- V2.1
--                         AND ooh.header_id = wdd.source_header_id             -- V2.1
--                         AND wdd.delivery_detail_id = wda.delivery_detail_id  -- V2.1
                           AND ooh.end_customer_id = hca.cust_account_id
                           AND hca.party_id        = hp.party_id
                           AND hca.cust_account_id = hcasa.cust_account_id
                           AND hcasa.cust_acct_site_id = hcsu.cust_acct_site_id
                           AND hcsu.site_use_id    = ooh.end_customer_site_use_id
                           AND hcasa.party_site_id = hps.party_site_id
                           AND hps.party_id    = hp.party_id -- V2.1
                           AND hps.location_id = hl.location_id
--                         AND ool.ship_from_org_id  = ood.organization_id      -- V1.6     -- V2.1
--                         AND ood.organization_code = flv.lookup_code          -- V2.1
--                         AND flv.lookup_type  = 'XXFASCOR_WAREHOUSE_LKUP'     -- V2.1
--                         AND flv.enabled_flag = 'Y'
--                         AND wda.delivery_id  = p_delivery_id)    --740295620 -- V2.1
                           AND ooh.header_id    = p_header_id) -- V2.1
--                         AND wdd.delivery_detail_id=p_delivery_detail_id)
                   UNPIVOT (Object_Text
                           FOR (Object_id)
                           IN (attribute2 AS 'FRT_ACCT_NBR',
                              party_name  AS 'FRT_NAME',
                              address1    AS 'FRT_ADD1',
                              address2    AS 'FRT_ADD2',
                              address3    AS 'FRT_ADD3',
                              address4    AS 'FRT_ADD4',
                              city        AS 'FRT_CUST_CITY',
                              state       AS 'FRT_CUST_STATE',
                              postal_code AS 'FRT_CUST_ZIP',
                              country     AS 'FRT_CUST_CNTRY',
                              attribute10 AS 'RES_SIG',
                              order_number AS 'SO_NUM',                         -- V1.4
                              Res_addr    AS 'RES_ADDR',                        -- V1.4
                              attribute1  AS 'ULT_CUST_PO',                     -- V1.4
                              attribute11 AS 'E/U_PHONE',                       -- V1.5
                              ATTRIBUTE12 AS 'E/U_Contact',                     -- V1.5
                              PACKING_INSTRUCTIONS AS 'PKG_INS_HDR' ,           -- V1.7
                              resource_name        AS 'SALES_REP'               -- V2.0
                                                                   ));
        --
        CURSOR c_line_addl (p_delivery_id NUMBER,p_move_order_line_id   NUMBER)
        IS
            SELECT DISTINCT object_id, object_text --, facility_nbr             --V2.1
              FROM (SELECT --flv.meaning facility_nbr,                          --V2.1
                            os.set_name
                      FROM -- oe_order_headers_all          ooh,                --V2.1
                           oe_order_lines_all            ool,
                           wsh_delivery_assignments      wda,
                           wsh_delivery_details          wdd,
--                         org_organization_definitions  ood,                   --V2.1
--                         fnd_lookup_values_vl          flv,                   --V2.1
                           oe_sets                       os
                     WHERE     1 = 1
--                         AND ooh.header_id          = ool.header_id --V2.1
                           AND ool.line_id            = wdd.source_line_id
--                         AND ooh.header_id          = wdd.source_header_id --V2.1
                           AND wdd.delivery_detail_id = wda.delivery_detail_id
--                         AND ool.ship_from_org_id   = ood.organization_id -- V1.6 --V2.1
--                         AND ood.organization_code  = flv.lookup_code --V2.1
--                         AND flv.lookup_type        = 'XXFASCOR_WAREHOUSE_LKUP'
--                         AND flv.enabled_flag       = 'Y'
                           AND ool.ship_set_id        = os.set_id
                           AND ool.header_id          = os.header_id
                           AND wda.delivery_id        = p_delivery_id
                           AND wdd.move_order_line_id = p_move_order_line_id)
                   UNPIVOT (Object_Text
                           FOR (Object_id)
                           IN (set_name AS 'SHIP_SET'));
        --
        CURSOR SREP 
        IS SELECT DISTINCT oha.salesrep_id
             FROM oe_order_headers_all      oha,
                  wsh_delivery_details      wdd,
                  wsh_delivery_assignments  wda,
                  xxfascor_so_iface_errors  xsie
            WHERE     1                      = 1
                  AND oha.header_id          = wdd.source_header_id
                  AND wdd.delivery_detail_id = wda.delivery_detail_id
                  AND wda.delivery_id        = xsie.order_id
                  AND NOT EXISTS (SELECT 1 
                                    FROM XXFASCOR_SOHEADER_STG
                                    WHERE ORDER_ID = xsie.order_id
                                  )
                 ORDER BY oha.salesrep_id;
    --
    BEGIN
--        l_debug_level := xxbsi_debug.set_debug ('XXFASCOR_SO_API'); -- V2.1
--        xxbsi_debug.start_proc ('XXFASCOR_SO_API',l_debug_level,'- Start Approved SO'); -- V2.1
          xxbsi_debug.start_proc(routine_name=>'XXFASCOR_SO_API',debug_msg=>lv_request_id); -- V2.1
--        DBMS_OUTPUT.put_line ('Start Approved SO'); -- V2.1
        fnd_file.put_line (fnd_file.LOG,' ******************** Sales Order Outbound Program*********************');

        EXECUTE IMMEDIATE 'TRUNCATE TABLE XBSI.XXFASCOR_SO_ERRORS_STG';         --V1.8

        FOR i IN pick_header
        LOOP
            --
            IF i.delivery_id IS NULL
            THEN
                fnd_file.put_line (fnd_file.LOG,'Order Number :'|| i.order_number|| ' - Delivery/Line is cancelled/unassigned');
            END IF;
            --
--            IF l_debug_level >= 1 -- V2.1
--            THEN
                xxbsi_debug.debug_msg ('XXFASCOR_SO_API','- Order Number :' || i.order_number|| ' - Delivery Number : '|| i.delivery_id,2,2);
--            END IF;
            l_header_id := NULL;
            --
            FOR j IN pick_lines (i.order_number, i.delivery_id)                 --V2.1
            LOOP
                l_delivery_chk    := NULL;
                l_delivery_id     := NULL;
                l_hdr_insert      := NULL;
                l_line_insert     := NULL;
                l_record_status   := NULL;
                l_header_id       := NULL;
                l_bill_party_name := NULL;
                l_bill_address1   := NULL;
                l_bill_address2   := NULL;
                l_bill_address3   := NULL;
                l_bill_address4   := NULL;
                l_bill_city       := NULL;
                l_bill_state      := NULL;
                l_bill_postal_code := NULL;
                l_bill_country    := NULL;
                l_ship_set_cnt    := NULL;
                l_bill_to_location := NULL;
                l_error_flag      := 'N';
                l_order_number    := NULL;                              --V1.8
                l_del_id := NULL;                                       --V1.8
                l_type   := NULL;                                       --V1.8
                l_error  := NULL;                                       --V1.8
                l_message_body    := NULL;                              --V2.3
                l_error_message   := NULL;                              --V2.3
                l_cnt             := 0;                                 --V2.3  
                l_address_check   := NULL;                              --V1.8
                l_message_type    := NULL;                              --V2.2
                l_detail_seq_nbr  := NULL;                              --V2.2
                l_sku             := NULL;                              --V2.2
                ErrMsgType_Tbl.DELETE;
                --
                IF j.released_status = 'S'
                THEN
                    BEGIN
                        SELECT DISTINCT 'Y'
                          INTO l_delivery_chk
                          FROM xxfascor_soheader_stg        xsh,
                               xxfascor_solines_stg         xsl,
                               xxfascor_moveorder_line_stg  xmvl
                         WHERE     xsh.order_id             = xsl.order_id
                               AND xsl.order_id             = j.delivery_id
                               AND xsl.detail_seq_nbr       = xmvl.fascor_order_line
                               AND xmvl.move_order_line_id  = j.move_order_line_id
                               AND xmvl.fascor_facility_nbr = j.facility_nbr
                               AND xsl.mode_status          = 'A'; --DECODE(i.released_status,'S','A','C');
                    EXCEPTION
                        WHEN OTHERS
                        THEN
                            l_delivery_chk := 'N';
                            l_delivery_id  := j.delivery_id;
                            --
--                            IF l_debug_level >= 1     -- V2.1
--                            THEN
                                xxbsi_debug.debug_msg ('XXFASCOR_SO_API','- Delivery Not Exist #' || j.delivery_id,2,2);
--                            END IF;
                    END;
                --
                ELSIF j.released_status = 'D'
                THEN
                    BEGIN
                        SELECT DISTINCT 'Y', xsh.order_id, xsh.header_id
                          INTO l_delivery_chk, l_delivery_id, l_header_id
                          FROM xxfascor_soheader_stg        xsh,
                               xxfascor_solines_stg         xsl,
                               xxfascor_moveorder_line_stg  xmvl
                         WHERE     xsh.order_id             = xsl.order_id
                               AND xsl.detail_seq_nbr       = xmvl.fascor_order_line
                               AND xmvl.move_order_line_id  = j.move_order_line_id
                               AND xmvl.fascor_facility_nbr = j.facility_nbr
                               AND xsh.mode_status          = 'A'
                               AND xsl.mode_status          = 'A'; --DECODE(i.released_status,'S','A','C');
                    EXCEPTION
                        WHEN NO_DATA_FOUND
                        THEN
                            l_delivery_chk := 'N';
                            --
                            fnd_file.put_line (fnd_file.LOG,'Order #'|| i.order_number|| ' - Delivery #'|| i.delivery_id|| ' is not found in staging table');  -- V1.1
                            --
--                            IF l_debug_level >= 1     -- V2.1
--                            THEN
                                xxbsi_debug.debug_msg ('XXFASCOR_SO_API','- Delivery Not Exist #' || i.delivery_id,2,2);
--                            END IF;
                    END;
                    --
                    IF l_delivery_chk = 'Y'
                    THEN
                        BEGIN
                            SELECT DISTINCT 'Y'
                              INTO l_delivery_chk
                              FROM xxfascor_soheader_stg        xsh,
                                   xxfascor_solines_stg         xsl,
                                   xxfascor_moveorder_line_stg  xmvl
                             WHERE     xsh.order_id             = xsl.order_id
                                   AND xsl.detail_seq_nbr       = xmvl.fascor_order_line
                                   AND xsl.order_id             = l_delivery_id
                                   AND xmvl.move_order_line_id  = j.move_order_line_id
                                   AND xmvl.fascor_facility_nbr = j.facility_nbr
                                   AND xsh.mode_status          = 'D'
                                   AND xsl.mode_status          = 'D'; --DECODE(i.released_status,'S','A','C');
                        EXCEPTION
                            WHEN NO_DATA_FOUND
                            THEN
                                l_delivery_chk := 'N';
                                --
--                                IF l_debug_level >= 1  -- V2.1
--                                THEN
                                    xxbsi_debug.debug_msg ('XXFASCOR_SO_API','- Delivery Not Exist #'|| j.delivery_id,2,2);
--                                END IF;
                        END;
                    ELSE
                        l_delivery_chk := 'Y';
                    END IF;
                END IF;
--                IF l_debug_level >= 2     -- V2.1
--                THEN
                    xxbsi_debug.debug_msg ('XXFASCOR_SO_API','- Delivery Detail Id #' || j.delivery_detail_id,2,2); -- V2.1
                    xxbsi_debug.debug_msg ('XXFASCOR_SO_API','- Move Order Line Id #' || j.move_order_line_id,2,2); -- V2.1
--                END IF;
                --
                IF l_delivery_chk = 'N'
                THEN
                    IF j.so_header_cancel = 'Y'
                    THEN
                        l_hdr_insert    := 'True';
                        l_line_insert   := 'True';                    --'False';
                        l_record_status := 'D';
                    ELSIF j.so_header_cancel = 'N'
                    THEN
                        IF j.so_line_cancel = 'Y'
                        THEN
                            l_hdr_insert      := 'False';
                            l_line_insert     := 'True';
                            l_record_status   := 'D';
                        ELSIF j.so_line_cancel  = 'N'
                        THEN
                            IF  j.flow_status_code = 'AWAITING_SHIPPING' AND j.released_status = 'S'
                            THEN
                                l_hdr_insert    := 'True';
                                l_line_insert   := 'True';
                                l_record_status := 'A';
                            END IF;
                        END IF;
                    END IF;
                END IF;
                --
                IF l_hdr_insert = 'True'
                THEN
                    --
                    BEGIN
                        SELECT DISTINCT 'Y', header_id
                          INTO l_so_chk, l_header_id
                          FROM xxfascor_soheader_stg xshs
                         WHERE     xshs.order_id     = l_delivery_id --j.order_number
                               AND xshs.facility_nbr = j.facility_nbr
                               AND xshs.mode_status  = l_record_status;
                        --
                        l_hdr_insert := 'False';
                    --
                    EXCEPTION
                        WHEN NO_DATA_FOUND
                        THEN
                            l_so_chk := 'N';
                            SELECT xxfascor_so_hdr_s.NEXTVAL
                              INTO l_header_id
                              FROM DUAL;
                            l_hdr_insert := 'True';
                        WHEN OTHERS
                        THEN
                            l_so_chk := 'Y';
                            l_hdr_insert := 'False';
                            fnd_file.put_line (fnd_file.LOG,'Order #'|| j.order_number|| '- Delivery #'|| j.delivery_id);
                            fnd_file.put_line (fnd_file.LOG,'Error Message While Checking Delivery:'|| SQLERRM);             -- V1.1
                            retcode := 1;
                    END;
                    --
--                    IF l_debug_level >= 2     -- V2.1
--                    THEN
                        xxbsi_debug.debug_msg ('XXFASCOR_SO_API','- Delivery Exist or Not :' || l_so_chk,2,2); -- V2.1
--                    END IF;
                END IF;
                --
                --fnd_file.put_line(fnd_file.log,'Header Id :'||l_header_id);
                IF l_line_insert = 'True'
                THEN
                    BEGIN
                        SELECT 'Y'
                          INTO l_line_chk
                          FROM xxfascor_solines_stg         xsl,
                               xxfascor_moveorder_line_stg  xmvl
                         WHERE     xsl.order_id             = l_delivery_id --i.order_number
                               AND xsl.detail_seq_nbr       = xmvl.fascor_order_line
                               AND xmvl.move_order_line_id  = j.move_order_line_id
                               AND xmvl.fascor_facility_nbr = j.facility_nbr
                               --AND detail_seq_nbr = j.delivery_detail_id
                               AND mode_status              = l_record_status;
                        --
                        l_line_insert := 'False';
                    EXCEPTION
                        WHEN NO_DATA_FOUND
                        THEN
                            l_line_insert := 'True';
                            l_line_chk := 'N';
                        --
                        WHEN OTHERS
                        THEN
                            l_line_chk := 'Y';
                            l_line_insert := 'False';
                            fnd_file.put_line (fnd_file.LOG,'Order #'|| j.order_number|| '- Delivery #'|| j.delivery_id|| ' - Delivery Line #'|| j.delivery_detail_id);
                            fnd_file.put_line (fnd_file.LOG,'Error Message While Checking Delivery Line :'|| SQLERRM);                           -- V1.1
                            retcode := 1;
                    --
                    END;
                    --
                    --
--                    IF l_debug_level >= 2     -- V2.1
--                    THEN
                        xxbsi_debug.debug_msg ('XXFASCOR_SO_API','- Delivery Detail Exist or Not :' || l_line_chk,2,2); -- V2.1
--                    END IF;
                END IF;
                --
                --
                IF l_hdr_insert = 'True'
                THEN
                    BEGIN
                        IF j.ship_set_id IS NOT NULL
                        THEN
                            l_order_fill_control     := 'Y';
                            l_order_fill_percentage  := 100;
                            l_order_fill_calculation := 'B';
                            l_order_fill_action      := 'CANC';
                        --
                        ELSIF j.ship_set_id IS NULL
                        THEN
                            l_order_fill_control     := 'N';
                            l_order_fill_percentage  := NULL;
                            l_order_fill_calculation := NULL;
                            l_order_fill_action      := 'CANC';
                        END IF;
                    END;
                    --
                    BEGIN
                        SELECT hp.party_name,
                               hcsu.location,
                               hl.address1,
                               hl.address2,
                               hl.address3,
                               hl.address4,
                               hl.city,
                               DECODE (j.org_id,121, NVL (hl.state, hl.province),124, NVL (hl.province, hl.state),NVL (hl.state, hl.province)),
                               REGEXP_REPLACE (hl.postal_code, '-'),
                               hl.country
                          INTO l_bill_party_name,
                               l_bill_to_location,
                               l_bill_address1,
                               l_bill_address2,
                               l_bill_address3,
                               l_bill_address4,
                               l_bill_city,
                               l_bill_state,
                               l_bill_postal_code,
                               l_bill_country
                          FROM hz_parties          hp,
                               hz_cust_accounts    hca,
                               hz_party_sites      hps,
                               hz_locations        hl,
                               hz_cust_acct_sites  hcsa,
                               hz_cust_site_uses   hcsu
                         WHERE     1 = 1
                               AND hp.party_id            = hca.party_id
                               AND hp.party_id            = hps.party_id
                               AND hps.location_id        = hl.location_id
                               AND hca.cust_account_id    = hcsa.cust_account_id
                               AND hcsa.party_site_id     = hps.party_site_id
                               AND hcsa.cust_acct_site_id = hcsu.cust_acct_site_id
                               AND hcsu.site_use_id       = j.invoice_to_org_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND
                        THEN
                            fnd_file.put_line (fnd_file.LOG,'Order #'|| j.order_number|| '- Delivery #'|| j.delivery_id);
                            fnd_file.put_line (fnd_file.LOG,'Bill To Org Id is Not found #'|| j.invoice_to_org_id);               -- V1.1
                            retcode := 1;
                        WHEN OTHERS
                        THEN
                            fnd_file.put_line (fnd_file.LOG,'Order #'|| j.order_number|| '- Delivery #'|| j.delivery_id);
                            fnd_file.put_line (fnd_file.LOG,'Error While Retriving Bill TO Address Information :'|| SQLERRM);                           -- V1.1
                            retcode := 1;
                    --
                    END;
                    --
--                    IF l_debug_level >= 2     -- V2.1
--                    THEN
                        xxbsi_debug.debug_msg ('XXFASCOR_SO_API','- Bill to Org ID :' || j.invoice_to_org_id,2,2);  -- V2.1
--                    END IF;
                    -- Initializing Header Values
                    BEGIN
                        l_soheader_rec.header_id                   := l_header_id; --xxfascor_so_hdr_s.NEXTVAL;
                        l_soheader_rec.MESSAGE_TYPE                := xxfascor_wms_utils.get_message_type ('SO');
                        l_soheader_rec.mode_status                 := l_record_status;
                        l_soheader_rec.facility_nbr                := j.facility_nbr;
                        l_soheader_rec.order_number                := j.order_number;
                        l_soheader_rec.order_id                    := l_delivery_id; --j.delivery_id;
                        l_soheader_rec.order_date                  := j.order_date;
                        l_soheader_rec.order_type                  := j.order_type;
                        l_soheader_rec.order_priority              := xxfascor_wms_utils.get_default_value ('ORDER_PRIORITY');
                        l_soheader_rec.order_status                := 'HOLD'; --xxfascor_wms_utils.get_default_value ('ORDER_STATUS'); -- V1.2
                        l_soheader_rec.order_reason_code           := j.order_reason_code;
                        l_soheader_rec.order_reason_comments       := NULL;
                        l_soheader_rec.order_ship_date             := j.order_ship_date;
                        l_soheader_rec.order_ship_day              := j.order_ship_day;
                        l_soheader_rec.carrier_id                  := j.carrier_id;
                        l_soheader_rec.shipping_terms              := j.shipping_terms;
                        l_soheader_rec.ship_wog_control            := xxfascor_wms_utils.get_default_value ('SHIP_WOG_CONTROL');
                        l_soheader_rec.asn_control                 := xxfascor_wms_utils.get_default_value ('ASN_CONTROL');
                        l_soheader_rec.route_id                    := NULL;
                        l_soheader_rec.stop_id                     := NULL;
                        l_soheader_rec.sold_to_customer_id         := l_bill_to_location;         --j.invoice_to_org_id;
                        l_soheader_rec.sold_to_customer_name       := l_bill_party_name;
                        l_soheader_rec.sold_to_customer_abbrev_name := l_bill_party_name;
                        l_soheader_rec.sold_to_customer_addr1      := l_bill_address1;
                        l_soheader_rec.sold_to_customer_addr2      := l_bill_address2;
                        l_soheader_rec.sold_to_customer_addr3      := l_bill_address3;
                        l_soheader_rec.sold_to_customer_addr4      := l_bill_address4;
                        l_soheader_rec.sold_to_customer_city       := l_bill_city;
                        l_soheader_rec.sold_to_customer_state      := l_bill_state;
                        l_soheader_rec.sold_to_customer_zip        := l_bill_postal_code;
                        l_soheader_rec.sold_to_customer_country_code := l_bill_country;
                        l_soheader_rec.sold_to_customer_po_ref     := j.sold_to_customer_po_ref;
                        l_soheader_rec.sold_to_customer_po_date    := NULL;
                        l_soheader_rec.ship_to_customer_id         := j.ship_to_location;       --j.ship_to_customer_id;
                        l_soheader_rec.ship_to_customer_name       := j.ship_to_customer_name;
                        l_soheader_rec.ship_to_customer_abbrev_name := j.ship_to_customer_abbrev_name;
                        l_soheader_rec.ship_to_customer_addr1      := j.ship_to_customer_addr1;
                        l_soheader_rec.ship_to_customer_addr2      := j.ship_to_customer_addr2;
                        l_soheader_rec.ship_to_customer_addr3      := j.ship_to_customer_addr3;
                        l_soheader_rec.ship_to_customer_addr4      := j.ship_to_customer_addr4;
                        l_soheader_rec.ship_to_customer_city       := j.ship_to_customer_city;
                        l_soheader_rec.ship_to_customer_state      := j.ship_to_customer_state;
                        l_soheader_rec.ship_to_customer_zip        := j.ship_to_customer_zip;
                        l_soheader_rec.ship_to_customer_country_code := j.ship_to_customer_country_code;
                        l_soheader_rec.tote_control                := xxfascor_wms_utils.get_default_value ('TOTE_CONTROL');
                        l_soheader_rec.tote_type                   := NULL;
                        l_soheader_rec.child_type                  := NULL;
                        l_soheader_rec.pallet_control              := xxfascor_wms_utils.get_default_value ('PALLET_CONTROL');
                        l_soheader_rec.pallet_type                 := NULL;
                        l_soheader_rec.order_fill_control          := l_order_fill_control;
                        l_soheader_rec.order_fill_percentage       := l_order_fill_percentage;
                        l_soheader_rec.order_fill_calculation      := l_order_fill_calculation;
                        l_soheader_rec.order_fill_action           := l_order_fill_action;
                        l_soheader_rec.partial_shipment_control    := j.partial_shipment_control;
                        l_soheader_rec.partial_shipment_suffix     := xxfascor_wms_utils.get_default_value ('PARTIAL_SHIPMENT_SUFFIX');
                        l_soheader_rec.substitute_control          := xxfascor_wms_utils.get_default_value ('SUBSTITUTE_CONTROL');
                        l_soheader_rec.substitute_suffix           := xxfascor_wms_utils.get_default_value ('SUBSTITUTE_SUFFIX');
                        l_soheader_rec.print_packlist_control      := xxfascor_wms_utils.get_default_value ('PRINT_PACKLIST_CONTROL');
                        l_soheader_rec.print_packlist_object       := NULL;
                        l_soheader_rec.print_shipping_label_control := xxfascor_wms_utils.get_default_value ('PRINT_SHIPPING_LABEL_CONTROL');
                        l_soheader_rec.print_shipping_label_object := NULL;
                        l_soheader_rec.print_price_label_control   := xxfascor_wms_utils.get_default_value ('PRINT_PRICE_LABEL_CONTROL');
                        l_soheader_rec.print_price_label_object    := NULL;
                        l_soheader_rec.print_other_doc_control     := xxfascor_wms_utils.get_default_value ('PRINT_OTHER_DOC_CONTROL');
                        l_soheader_rec.print_other_doc_object      := NULL;
                        l_soheader_rec.cod_invoice_amount          := NULL;
                        l_soheader_rec.declared_value              := NULL;
                        l_soheader_rec.post_pick_process_1_control := xxfascor_wms_utils.get_default_value ('POST_PICK_PROCESS_1_CONTROL');
                        l_soheader_rec.post_pick_process_1_profile := NULL;
                        l_soheader_rec.post_pick_process_2_control := xxfascor_wms_utils.get_default_value ('POST_PICK_PROCESS_2_CONTROL');
                        l_soheader_rec.post_pick_process_2_profile := NULL;
                        l_soheader_rec.post_pick_process_3_control := xxfascor_wms_utils.get_default_value ('POST_PICK_PROCESS_3_CONTROL');
                        l_soheader_rec.post_pick_process_3_profile := NULL;
                        l_soheader_rec.order_comments              := NULL;
                        l_soheader_rec.ERROR_CODE                  := NULL;
                        l_soheader_rec.error_message               := NULL;
                        l_soheader_rec.created_by                  := fnd_global.user_id;
                        l_soheader_rec.creation_date               := SYSDATE;
                        l_soheader_rec.last_update_date            := SYSDATE;
                        l_soheader_rec.last_updated_by             := fnd_global.user_id;
                        l_soheader_rec.processed_flag              := 'N';
                        --
                        INSERT INTO xxfascor_soheader_stg
                                     VALUES l_soheader_rec;
                        --
                        l_soheader_cnt := l_soheader_cnt + 1;
                    --
                    EXCEPTION
                        WHEN OTHERS
                        THEN
                            l_error_flag := 'Y';
                            fnd_file.put_line (fnd_file.LOG,'Order #' || j.order_number || '- Delivery #' || j.delivery_id);
                            fnd_file.put_line (fnd_file.LOG,'Error While Inserting Header Data into Stagging Table :' || SQLERRM); -- V1.1
                            retcode      := 1;

--                            l_address_check  := address_check(j.order_number);              --V2.2
                            l_address_check  := j.address_check;                              --V2.3
                            l_message_type   := xxfascor_wms_utils.get_message_type ('SO');   --V2.2
                            l_detail_seq_nbr := NULL;    --l_soline_rec.detail_seq_nbr;       --V2.2
                            l_sku            := j.sku;                                        --V2.2
                            l_order_number   := j.order_number;                               --V1.8
                            l_del_id         := j.delivery_id;                                --V1.8
                            l_type           := 'Header';                                     --V1.8
                            l_error          := SUBSTR (SQLERRM, 1, 3900);                    --V1.8
                            l_cnt            := l_cnt + 1;                                    --V2.3

                            --                                                  --V2.3 START
                            IF j.ship_to_location IS NULL
                            THEN
                                l_error_cnt     := l_error_cnt + 1;
                                l_error_message := l_error_message || ' Missing: "SHIP_TO_LOCATION", ';
                                ErrMsgType_Tbl.EXTEND;
                                ErrMsgType_Tbl (l_cnt) := TRIM (SUBSTR (l_error_message, 1, 500));
                            END IF;
                            --
                            IF j.ship_to_customer_addr1 IS NULL
                            THEN
                                l_error_cnt     := l_error_cnt + 1;
                                l_error_message := l_error_message || ' Missing: "SHIP_TO_CUSTOMER_ADDR1", ';
                                ErrMsgType_Tbl.EXTEND;
                                ErrMsgType_Tbl (l_cnt) := TRIM (SUBSTR (l_error_message, 1, 500));
                            END IF;
                            --
                            IF j.ship_to_customer_city IS NULL
                            THEN
                                l_error_cnt     := l_error_cnt + 1;
                                l_error_message := l_error_message || ' Missing: "SHIP_TO_CUSTOMER_CITY", ';
                                ErrMsgType_Tbl.EXTEND;
                                ErrMsgType_Tbl (l_cnt) := TRIM (SUBSTR (l_error_message, 1, 500));
                            END IF;
                            --
                            IF j.ship_to_customer_state IS NULL
                            THEN
                                l_error_cnt     := l_error_cnt + 1;
                                l_error_message := l_error_message || ' Missing: "SHIP_TO_CUSTOMER_STATE", ';
                                ErrMsgType_Tbl.EXTEND;
                                ErrMsgType_Tbl (l_cnt) := TRIM (SUBSTR (l_error_message, 1, 500));
                            END IF;
                            --
                            IF j.ship_to_customer_zip IS NULL
                            THEN
                                l_error_cnt     := l_error_cnt + 1;
                                l_error_message := l_error_message || ' Missing: "SHIP_TO_CUSTOMER_ZIP", ';
                                ErrMsgType_Tbl.EXTEND;
                                ErrMsgType_Tbl (l_cnt) := TRIM (SUBSTR (l_error_message, 1, 500));
                            END IF;
                            --
                            IF j.ship_to_customer_country_code IS NULL
                            THEN
                                l_error_cnt     := l_error_cnt + 1;
                                l_error_message := l_error_message || ' Missing: "SHIP_TO_CUSTOMER_COUNTRY_CODE"';
                                ErrMsgType_Tbl.EXTEND;
                                ErrMsgType_Tbl (l_cnt) := TRIM (SUBSTR (l_error_message, 1, 500)); -- V2.3
                            END IF;                                             
                            --
                            IF l_error_message IS NULL
                            THEN
                                l_error_message := l_error_message || ' Missing: '||SUBSTR(l_error,INSTR(l_error, '.', -1) + 1,INSTR(l_error, ')', 1, 1) - INSTR(l_error, '.', -1) - 1);
                                l_cnt           := l_cnt + 1;
                                ErrMsgType_Tbl.EXTEND;
                                ErrMsgType_Tbl(l_cnt) := trim(substr(l_error_message,1,500));
                                fnd_file.put_line (fnd_file.LOG,'l_sku :'||l_sku||', '||'l_error :'||l_error);
                            END IF;
                            fnd_file.put_line (fnd_file.LOG,'Order #'|| j.order_number|| '- Delivery #'|| j.delivery_id|| ', '|| l_error_message);--V2.3 END
                    END;
                    --
                    IF NVL (l_error_flag, 'N') = 'N'
                    THEN
                        --additional Header info
                        BEGIN
                            SELECT COUNT (*)
                              INTO l_obj_c
                              FROM xxfascor_soaddtional_info_stg
                             WHERE     order_id       = j.delivery_id
                                   AND detail_seq_nbr = 0;
                        EXCEPTION
                            WHEN OTHERS
                            THEN
                                NULL;
                        END;
                        --
                        IF l_obj_c = 0
                        THEN
                            FOR k IN c_hdr_addl (i.header_id)   --V2.1
                            LOOP
                                l_object_id := 'SHIPINFO';
                                l_error_message     := NULL;
                                --
                                BEGIN
                                    l_ord_obj_det_rec.header_id        := l_header_id;
                                    l_ord_obj_det_rec.addl_info_line_id := xxfascor_so_addl_s.NEXTVAL;
                                    l_ord_obj_det_rec.MESSAGE_TYPE     := xxfascor_wms_utils.get_message_type ('ORDER_OBJ_DET');
                                    l_ord_obj_det_rec.mode_status      := l_record_status;                --'A';
                                    l_ord_obj_det_rec.facility_nbr     := i.facility_nbr;                --'01'; --V2.1
                                    l_ord_obj_det_rec.order_id         := l_delivery_id;
                                    l_ord_obj_det_rec.detail_seq_nbr   := 0; --i.delivery_detail_id;
                                    l_ord_obj_det_rec.object_id        := l_object_id;
                                    l_ord_obj_det_rec.object_text      := k.object_id|| '=['|| k.object_text|| ']';
                                    l_ord_obj_det_rec.ERROR_CODE       := NULL;
                                    l_ord_obj_det_rec.error_message    := NULL;
                                    l_ord_obj_det_rec.created_by       := fnd_global.user_id;
                                    l_ord_obj_det_rec.creation_date    := SYSDATE;
                                    l_ord_obj_det_rec.last_update_date := SYSDATE;
                                    l_ord_obj_det_rec.last_updated_by  := fnd_global.user_id;
                                    l_ord_obj_det_rec.processed_flag   := 'N';
                                    --
                                    INSERT INTO xxfascor_soaddtional_info_stg
                                         VALUES l_ord_obj_det_rec;
                                EXCEPTION
                                    WHEN OTHERS
                                    THEN
                                        l_error_flag := 'Y';
                                        fnd_file.put_line (fnd_file.LOG,'Order #'|| j.order_number|| '- Delivery #'|| j.delivery_id);
                                        fnd_file.put_line (fnd_file.LOG,'Error While Inserting Additional Info Data into Stagging Table :'|| SQLERRM);               -- V1.1
                                        retcode := 1;

--                                        l_address_check  := address_check(j.order_number);                        --V2.2
                                        l_address_check  := j.address_check;                --V2.3 
                                        l_message_type   := xxfascor_wms_utils.get_message_type('ORDER_OBJ_DET'); --V2.2
                                        l_detail_seq_nbr := NULL;--l_soline_rec.detail_seq_nbr;                   --V2.2
                                        l_sku            := j.sku;                                                --V2.2
                                        l_order_number   := j.order_number;            --V1.8
                                        l_del_id         := j.delivery_id;             --V1.8
                                        l_type           := 'Additional Info';         --V1.8
                                        l_error          := SUBSTR (SQLERRM, 1, 3900); --V1.8
                                        --
                                        l_error_cnt     := l_error_cnt +1;
                                        l_error_message := l_error_message || 'Missing: '||SUBSTR(l_error,INSTR(l_error, '.', -1) + 1,INSTR(l_error, ')', 1, 1) - INSTR(l_error, '.', -1) - 1); -- V2.3
                                        l_cnt          := l_cnt + 1;            -- V2.3
                                        ErrMsgType_Tbl.EXTEND;                  -- V2.3
                                        ErrMsgType_Tbl(l_cnt) := trim(substr(l_error_message,1,500)); -- V2.3
                                        fnd_file.put_line (fnd_file.LOG,'l_sku :'||l_sku||', '||'l_error :'||l_error);
                                END;
                            END LOOP;
                        END IF;
                    END IF;
                --
                END IF;
                --
                IF NVL (l_error_flag, 'N') = 'N'
                THEN
                    IF l_line_insert = 'True'
                    THEN
                        --
                        BEGIN
                            l_soline_rec.header_id    := l_header_id; --xxfascor_so_hdr_s.CURRVAL;
                            l_soline_rec.line_id      := xxfascor_so_line_s.NEXTVAL;
                            l_soline_rec.MESSAGE_TYPE := xxfascor_wms_utils.get_message_type ('SO LINE');
                            l_soline_rec.mode_status  := l_record_status;
                            l_soline_rec.facility_nbr := j.facility_nbr;
                            l_soline_rec.order_id     := l_delivery_id; --j.delivery_id;
                            --
                            IF l_record_status = 'A'
                            THEN
                                --IF j.facility_nbr = '01' -- FLO
                                --THEN
                                l_soline_rec.detail_seq_nbr := xxfascor_mv_order_line_s.NEXTVAL; --j.move_order_line_id;
                            --END IF;
                            ELSIF l_record_status = 'D'
                            THEN
                                BEGIN
                                    SELECT fascor_order_line
                                      INTO l_soline_rec.detail_seq_nbr
                                      FROM xxfascor_moveorder_line_stg
                                     WHERE     move_order_line_id  = j.move_order_line_id
                                           AND fascor_facility_nbr = j.facility_nbr;
                                EXCEPTION
                                    WHEN OTHERS
                                    THEN
                                        l_error_flag := 'Y';
                                        fnd_file.put_line (fnd_file.LOG,'Order #'|| j.order_number|| '- Delivery #'|| j.delivery_id|| ' - Delivery Line #'|| j.delivery_detail_id);
                                        fnd_file.put_line (fnd_file.LOG,'Exception While retriving fascor move order line nbr #'|| j.move_order_line_id);  -- V1.1
                                        retcode := 1;
                                END;
                            END IF;
                            --
                            l_soline_rec.sku              := j.sku;
                            l_soline_rec.sku_original_qty := j.sku_original_qty;
                            l_soline_rec.sku_ship_qty     := j.sku_ship_qty;
                            l_soline_rec.sku_use_reserve_qty := NULL;
                            l_soline_rec.sku_class        := j.sku_class;
                            l_soline_rec.sku_uom          := j.sku_uom;
                            --
                            IF NVL (l_ship_set_cnt, 0) > 1
                            THEN
                                l_soline_rec.sku_allocation_control   := 'L';
                                l_soline_rec.partial_shipment_control := 'N';
                                l_soline_rec.sku_fill_percentage      := 100;
                            ELSE
                                l_soline_rec.sku_allocation_control   := xxfascor_wms_utils.get_default_value ('SKU_ALLOCATION_CONTROL');
                                l_soline_rec.partial_shipment_control := NULL;
                                l_soline_rec.sku_fill_percentage      := NULL;
                            END IF;
                            --
                            l_soline_rec.sku_substitution_control  := xxfascor_wms_utils.get_default_value ('SKU_SUBSTITUTION_CONTROL');
                            l_soline_rec.sku_substitution_mix      := xxfascor_wms_utils.get_default_value ('SKU_SUBSTITUTION_MIX');
                            l_soline_rec.full_case_only            := NULL;
                            l_soline_rec.sku_abbrev_description    := NULL;
                            l_soline_rec.print_line_only           := NULL;
                            l_soline_rec.print_comments_crtl_pack_list := '0';
                            l_soline_rec.print_comments_crtl_bol   := '0';
                            l_soline_rec.line_comments_1           := j.line_comments_1;
                            l_soline_rec.line_comments_2           := j.line_comments_2;
                            l_soline_rec.line_comments_3           := NULL;
                            l_soline_rec.class_of_goods_major      := xxfascor_wms_utils.get_default_value ('CLASS_OF_GOODS_MAJOR');
                            l_soline_rec.class_of_goods_minor      := xxfascor_wms_utils.get_default_value ('CLASS_OF_GOODS_MINOR');
                            l_soline_rec.sku_insure_value          := ABS (j.sku_insure_value);               --V1.9
                            l_soline_rec.customer_sku_id           := NULL;
                            l_soline_rec.customer_sku_description1 := NULL;
                            l_soline_rec.customer_sku_description2 := NULL;
                            l_soline_rec.retail_unit_of_measure    := NULL;
                            l_soline_rec.sku_catalog_page          := NULL;
                            l_soline_rec.sku_assortment_nbr        := NULL;
                            l_soline_rec.sku_retail_price          := NULL;
                            l_soline_rec.sku_retail_upc_code       := NULL;
                            l_soline_rec.quantity_of_stickers      := NULL;
                            l_soline_rec.price_sticker_object      := NULL;
                            l_soline_rec.lot_mix                   := xxfascor_wms_utils.get_default_value ('LOT_MIX');
                            l_soline_rec.lot_id                    := xxfascor_wms_utils.get_default_value ('LOT_ID');
                            l_soline_rec.lot_mfg_age               := xxfascor_wms_utils.get_default_value ('LOT_MFG_AGE');
                            l_soline_rec.lot_mfg_date              := TO_CHAR (SYSDATE,'yyyy-mm-dd"T"hh24:mi:ss"Z"');
                            l_soline_rec.lot_mfg_date_range        := '0';
                            l_soline_rec.lot_exp_age               := xxfascor_wms_utils.get_default_value ('LOT_EXP_AGE');
                            l_soline_rec.lot_exp_date              := TO_CHAR (SYSDATE,'yyyy-mm-dd"T"hh24:mi:ss"Z"');
                            l_soline_rec.lot_exp_date_range        := '0';
                            l_soline_rec.lot_distribution_rule_id  := '1234';
                            l_soline_rec.ERROR_CODE                := NULL;
                            l_soline_rec.error_message             := NULL;
                            l_soline_rec.created_by                := fnd_global.user_id;
                            l_soline_rec.creation_date             := SYSDATE;
                            l_soline_rec.last_update_date          := SYSDATE;
                            l_soline_rec.last_updated_by           := fnd_global.user_id;
                            l_soline_rec.processed_flag            := 'N';
                            l_soline_rec.delivery_detail_id        := j.delivery_detail_id;
                            --
                            INSERT INTO xxfascor_solines_stg
                                 VALUES l_soline_rec;
                            --
                            l_soline_cnt := l_soline_cnt + 1;
                            --
                            IF NVL (l_error_flag, 'N') = 'N'
                            THEN
                                IF l_record_status = 'A'
                                THEN
                                    l_fas_mv_rec.move_order_line_id  := j.move_order_line_id;
                                    l_fas_mv_rec.organization_code   := i.organization_code;
                                    l_fas_mv_rec.fascor_facility_nbr := j.facility_nbr;
                                    l_fas_mv_rec.fascor_order_line   := xxfascor_mv_order_line_s.CURRVAL;
                                    --
                                    INSERT INTO xxfascor_moveorder_line_stg
                                         VALUES l_fas_mv_rec;
                                END IF;
                                --
                                --additional line info
                                BEGIN
                                    SELECT COUNT (*)
                                      INTO l_obj_c
                                      FROM xxfascor_soaddtional_info_stg
                                     WHERE     order_id       = j.delivery_id
                                           AND detail_seq_nbr = l_soline_rec.detail_seq_nbr;
                                EXCEPTION
                                    WHEN OTHERS
                                    THEN
                                        NULL;
                                END;
                                --
                                IF l_obj_c = 0
                                THEN
                                    FOR k
                                        IN c_line_addl (l_delivery_id,j.move_order_line_id)
                                    LOOP
                                        l_object_id   := 'SHIP_SET';
                                        l_object_text :='SHIPSET'|| '=['|| k.object_text|| ']';
                                        l_error_message := NULL;
                                        --
                                        BEGIN
                                            l_ord_obj_ln_rec.header_id         := l_header_id;
                                            l_ord_obj_ln_rec.addl_info_line_id := xxfascor_so_addl_s.NEXTVAL;
                                            l_ord_obj_ln_rec.MESSAGE_TYPE      := xxfascor_wms_utils.get_message_type ('ORDER_OBJ_DET');
                                            l_ord_obj_ln_rec.mode_status       :=l_record_status;        --'A';
                                            l_ord_obj_ln_rec.facility_nbr      :=i.facility_nbr;        --'01'; --V2.1
                                            l_ord_obj_ln_rec.order_id          := l_delivery_id;
                                            l_ord_obj_ln_rec.detail_seq_nbr    := l_soline_rec.detail_seq_nbr;
                                            l_ord_obj_ln_rec.object_id         := l_object_id;
                                            l_ord_obj_ln_rec.object_text       := l_object_text;
                                            l_ord_obj_ln_rec.ERROR_CODE        := NULL;
                                            l_ord_obj_ln_rec.error_message     := NULL;
                                            l_ord_obj_ln_rec.created_by        := fnd_global.user_id;
                                            l_ord_obj_ln_rec.creation_date     := SYSDATE;
                                            l_ord_obj_ln_rec.last_update_date  := SYSDATE;
                                            l_ord_obj_ln_rec.last_updated_by   := fnd_global.user_id;
                                            l_ord_obj_ln_rec.processed_flag    := 'N';
                                            --
                                            INSERT INTO xxfascor_soaddtional_info_stg
                                                 VALUES l_ord_obj_ln_rec;
                                        EXCEPTION
                                            WHEN OTHERS
                                            THEN
                                                l_error_flag := 'Y';
                                                fnd_file.put_line (fnd_file.LOG,'Order #'|| j.order_number|| '- Delivery #'|| j.delivery_id|| ' - Delivery Line #'|| j.delivery_detail_id);
                                                fnd_file.put_line (fnd_file.LOG,'Error While Inserting Line Additional Info Data into Stagging Table :'|| SQLERRM);       -- V1.1
                                                retcode := 1;
                                                --
--                                                l_address_check  := address_check(j.order_number);                        --V2.2
                                                l_address_check  := j.address_check;                --V2.3 
                                                l_message_type   := xxfascor_wms_utils.get_message_type('ORDER_OBJ_DET'); --V2.2
                                                l_detail_seq_nbr := l_soline_rec.detail_seq_nbr;                          --V2.2
                                                l_sku            := j.sku;                                                --V2.2
                                                l_order_number   := j.order_number;           --V1.8
                                                l_del_id         := j.delivery_id;            --V1.8
                                                l_type           := 'Additional Line Info';   --V1.8
                                                l_error          := SUBSTR (SQLERRM, 1, 3900);--V1.8
                                                --
                                                l_error_cnt     := l_error_cnt +1;
                                                l_error_message := l_error_message || 'Missing: '||SUBSTR(l_error,INSTR(l_error, '.', -1) + 1,INSTR(l_error, ')', 1, 1) - INSTR(l_error, '.', -1) - 1); -- V2.3
                                                l_cnt          := l_cnt + 1;    -- V2.3
                                                ErrMsgType_Tbl.EXTEND;          -- V2.3
                                                ErrMsgType_Tbl(l_cnt) := trim(substr(l_error_message,1,500)); -- V2.3
                                        END;
                                    END LOOP;
                                END IF;
                            END IF;
                        EXCEPTION
                            WHEN OTHERS
                            THEN
                                l_error_flag := 'Y';
                                fnd_file.put_line (fnd_file.LOG,'Order #'|| j.order_number|| '- Delivery #'|| j.delivery_id|| ' - Delivery Line #'|| j.delivery_detail_id);
                                fnd_file.put_line (fnd_file.LOG,'Error While Inserting Line Data into Stagging Table :'|| SQLERRM);                       -- V1.1
                                retcode := 1;
                                --
--                                l_address_check  := address_check(j.order_number);                    --V2.2
                                l_address_check  := j.address_check;            --V2.3
                                l_message_type   := xxfascor_wms_utils.get_message_type('SO LINE');   --V2.2
                                l_detail_seq_nbr := l_soline_rec.detail_seq_nbr;                      --V2.2
                                l_sku            := j.sku;                      --V2.2
                                l_order_number   := j.order_number;             --V1.8
                                l_del_id         := j.delivery_id;              --V1.8
                                l_type           := 'Line';                     --V1.8
                                l_error          := SUBSTR (SQLERRM, 1, 3900);  --V1.8
                                --
                                l_error_cnt     := l_error_cnt +1;
                                l_error_message := l_error_message || 'Missing: '||SUBSTR(l_error,INSTR(l_error, '.', -1) + 1,INSTR(l_error, ')', 1, 1) - INSTR(l_error, '.', -1) - 1); -- V2.3
                                l_cnt           := l_cnt + 1;                   -- V2.3
                                ErrMsgType_Tbl.EXTEND;                          -- V2.3
                                ErrMsgType_Tbl(l_cnt) := trim(substr(l_error_message,1,500)); -- V2.3
                        END;
                    --
                    END IF;
                END IF;
                --
                IF NVL (l_error_flag, 'N') = 'N'
                THEN
                    COMMIT;
                ELSE
                    ROLLBACK;
                END IF;
                --
                IF l_order_number IS NOT NULL                   --Start --V1.8
                THEN
                    IF     l_order_number <> l_order_number_1
                       AND l_del_id <> l_del_id_1   -- Checking duplicate rows
                    THEN
                        /*INSERT INTO xxfascor_so_errors_stg
                             VALUES (l_order_number,
                                     l_del_id,
                                     l_type,
                                     l_error,
                                     l_address_check);*/            --V2.2
                        
                        BEGIN                                                   -- V2.3  START
                             -- Deleting past error's to insert new error's for delivery_id
                             DELETE FROM xxfascor_so_iface_errors  WHERE order_id = j.delivery_id;
                             COMMIT;
                        END;
                        --
                        FOR Err_i IN 1..l_cnt
                        LOOP
                            INSERT INTO xxfascor_so_iface_errors
                                     VALUES (l_message_type,
                                             l_type,
                                             j.facility_nbr,
                                             j.delivery_id,
                                             l_detail_seq_nbr,
                                             l_sku,
                                             ErrMsgType_Tbl(Err_i),
                                             SYSDATE,
                                             l_address_check);
                        END LOOP;
                        
                        COMMIT;
                        --
                        l_order_number_1 := l_order_number;
                        l_del_id_1 := l_del_id;
                    END IF;
                /*ELSE
                    DELETE FROM xxfascor_so_iface_errors WHERE order_id = j.delivery_id;*/ -- V2.3
                END IF;                                                         -- V2.3 END
--                COMMIT; --End --V1.8
            END LOOP;
        --COMMIT;
        END LOOP;
        --
        -- Send mail to Salesrep                                                -- V2.3 START
        IF l_error_cnt > 0
        THEN
            BEGIN
                --
                FOR l IN SREP
                LOOP
                    l_salesrep_name := NULL;
                    l_salesrep_email := NULL;
                    BEGIN
                        SELECT pap.last_name||' '||first_name name, fu.email_address
                          INTO l_salesrep_name,l_salesrep_email
                          FROM fnd_user fu, jtf_rs_salesreps srep, jtf_rs_resource_extns_vl jre,  per_all_people_f pap
                         WHERE     1                = 1
                               AND fu.user_id       = jre.user_id
                               AND jre.resource_id  = srep.resource_id
                               AND srep.person_id   = pap.person_id
                               AND srep.salesrep_id = l.salesrep_id;
                    EXCEPTION
                        WHEN NO_DATA_FOUND
                        THEN
                            fnd_file.put_line (fnd_file.LOG, 'Inavlid Salesrep:'||l.salesrep_id ||' '|| SQLERRM);
                        WHEN OTHERS
                        THEN
                            fnd_file.put_line (fnd_file.LOG, 'Got error at salesrep:' || SQLERRM);
                    END;
                    --
                    IF l_salesrep_email IS NOT NULL
                    THEN
                        l_message_body := RPAD('Order Number', 20) ||RPAD('Interface Type', 20) || RPAD('Order ID/SKU', 20) ||  'Error Message' || CHR(10);
                        l_message_body := l_message_body || RPAD('-', 150, '-') || CHR(10);
                        --
                        FOR err IN (SELECT DISTINCT oha.order_number,xsie.interface_type,DECODE (xsie.interface_type,'Line',RPAD(' ',3)||xsie.SKU,xsie.order_id) order_id ,DECODE (xsie.interface_type,'Line',RPAD(' ',5)||xsie.error_message,xsie.error_message) error_message
                                      FROM oe_order_headers_all oha,
                                           wsh_delivery_details wdd,
                                           wsh_delivery_assignments wda,
                                           xxfascor_so_iface_errors xsie
                                     WHERE 1                      = 1
                                       AND oha.header_id          = wdd.source_header_id
                                       AND wdd.delivery_detail_id = wda.delivery_detail_id
                                       AND wda.delivery_id        = xsie.order_id
                                       AND oha.salesrep_id        = l.salesrep_id
                                       AND NOT EXISTS (SELECT 1 
                                                         FROM XXFASCOR_SOHEADER_STG
                                                         WHERE ORDER_ID = xsie.order_id
                                                       )
                                      ORDER BY ORDER_ID
                                   )
                        LOOP
                            l_message_body := l_message_body || RPAD(' ',08)||RPAD(err.order_number, 20)      || 
                                                                RPAD(err.interface_type, 20)    || 
                                                                RPAD(TO_CHAR(err.order_id), 20) || 
                                                                RPAD(err.error_message, 100)    || 
                                                                CHR(10) || CHR(10);
                        END LOOP;
                        --
                        l_message_body := 'Hello ' || l_salesrep_name ||','|| CHR(10) || CHR(10) || 
                                      'The following orders failed to send to IntraOne. Please fix them to process in the next run of the Job:' || CHR(10) || CHR(10) || 
                                      l_message_body;
                        --
                        XXBSI_MAIL_ALERT    (p_request_id        => lv_request_id,
                                             p_file_name         => NULL,
                                             p_file_path         => NULL,
                                             p_subject           => 'FASCOR SO ALERT',
                                             p_recpmail          => l_salesrep_email,
                                             p_message_body      => l_message_body,
                                             p_source            => 'FASDEF', -- Use FASDEF as the default in NON-PROD for testing
                                             p_out               => p_error
                                            );
                    END IF;
                END LOOP;
            EXCEPTION
               WHEN OTHERS
               THEN
                   fnd_file.put_line (fnd_file.LOG,'Got execption while sending mail :'||SQLERRM);
            END;
        END IF;                                                                 -- V2.3 END
        --
        fnd_file.put_line (fnd_file.LOG,' **********************************************************************');
        /*   BEGIN  ---V1.3
             -- Sending data to Fascor
             xxfascor_wms_utils.so_outbound(l_err_msg,
                                            l_retcode);
           END;

           IF l_retcode in (1,2)
           THEN
             retcode := l_retcode;
             fnd_file.put_line(fnd_file.log, 'Errors While Sending Data to Fascor');
           END IF;
           -- */
        fnd_file.put_line (fnd_file.LOG,'Total Number of Headers Processed :' || l_soheader_cnt);
        fnd_file.put_line (fnd_file.LOG,'Total Number of Lines Processed :' || l_soline_cnt);
        --
        xxbsi_debug.end_proc ('XXFASCOR_SKU_API',l_debug_level,lv_request_id);
    EXCEPTION
        WHEN OTHERS
        THEN
            fnd_file.put_line (fnd_file.LOG, 'Exception ' || SQLERRM);
--            IF l_debug_level >= 1    -- V2.1
--            THEN
                xxbsi_debug.debug_msg ('XXFASCOR_SO_API',lv_request_id || 'Exception ' || SQLERRM,2,2);
--            END IF;
            retcode := 1;
    END MAIN;
--
FUNCTION  address_check (l_order_number NUMBER)   --V2.0
  RETURN VARCHAR2
  IS
l_address_check VARCHAR2(1);
BEGIN
   SELECT loc.attribute20
     INTO l_address_check
     FROM apps.hz_locations loc,
          apps.hz_party_sites hps,
          apps.hz_cust_acct_sites_all hcas,
          apps.hz_cust_site_uses_all hcsua,
          apps.oe_order_headers_all ooha
    WHERE ooha.order_number = l_order_number
      AND hcsua.site_use_id = ooha.ship_to_org_id
      AND hcsua.cust_acct_site_id = hcas.cust_acct_site_id
      AND hcas.party_site_id = hps.party_site_id
      AND hps.location_id = loc.location_id;

    RETURN l_address_check;
EXCEPTION
WHEN OTHERS
THEN
    l_address_check := 'N';
    RETURN l_address_check;
END;
--
PROCEDURE XXBSI_MAIL_ALERT    (p_request_id         NUMBER,                     -- V2.3 Added procedure
                               p_file_name          VARCHAR2,
                               p_file_path          VARCHAR2,
                               p_subject            VARCHAR2,
                               p_recpmail           VARCHAR2,
                               p_message_body       VARCHAR2,
                               p_source             VARCHAR2,
                               p_out            OUT VARCHAR)
IS
    l_sender          VARCHAR2 (150);
    subject           VARCHAR2 (150);
    message1          VARCHAR2 (150);
    l_mailhost        VARCHAR2 (100);
    mailhost_dflt     VARCHAR2 (100) := 'oramx.bluestarinc.com';
    mail_conn         UTL_SMTP.connection;
    crlf              VARCHAR2 (2) := CHR (13) || CHR (10);
    mail_subj         VARCHAR2 (4000);
    mail_subj1        VARCHAR2 (4000);
    l_default_email   VARCHAR2 (4000);
    l_recipient       VARCHAR2 (150);
    l_database_name   VARCHAR2 (30);
    l_status          VARCHAR2 (30);
    p_attach_mime     VARCHAR2 (3000) := NULL;
    l_boundary        VARCHAR2 (50) := '----=*#abc1234321cba#*=';
    l_step            PLS_INTEGER := 12000; -- make sure you set a multiple of 3 not higher than 24573
    v_file_handle     UTL_FILE.file_type;
    attachment_text   VARCHAR2 (32767);
    add_date          VARCHAR2 (20):= TO_CHAR (SYSDATE, 'ddmmrr' || '_' || 'hh24:mi:ss');
    l_output          VARCHAR2 (4000);
    RECORD_NUMBER     NUMBER (30);
    CUST_PO           VARCHAR2 (100);
    l_rcpt_code       VARCHAR2 (20);
    l_meaning         VARCHAR2 (40);
    l_signature       VARCHAR2 (50);

    --
    CURSOR C1 (l_rec VARCHAR2)
    IS
            SELECT LEVEL                    AS l_id,
                   REGEXP_SUBSTR (l_rec,'[^;,]+',1,LEVEL)    AS l_email_name
              FROM DUAL
        CONNECT BY REGEXP_SUBSTR (l_rec,'[^;,]+',1,LEVEL) IS NOT NULL;
BEGIN
    ------------------------------------------------------------------
    -- Getting the Database name to check whether it is PROD or not
    -------------------------------------------------------------------
    IF apps.xxbsi_is_production = 'Y'
    THEN
        l_database_name := 'Production';
    ELSE
        l_database_name := apps.xxbsi_util.where_am_i;
    END IF;

    --

    BEGIN
        SELECT wf.parameter_value
          INTO l_mailhost
          FROM apps.fnd_svc_comp_param_vals wf
         WHERE wf.component_parameter_id = 10079;
    EXCEPTION
        WHEN OTHERS
        THEN
            p_out := 'Error while getting mail host from Workflow';
    --l_mailhost := 'oramx.bluestarinc.com';
    END;

    attachment_text := attachment_text || p_Message_body || UTL_TCP.crlf;

    -------------------------------------------------------------------------------------
    -- Get Sender Email Address
    -------------------------------------------------------------------------------------
    BEGIN
        SELECT description
          INTO l_sender
          FROM apps.fnd_lookup_values_vl
         WHERE     lookup_type = 'XXBSI_EDI_EMAIL_DFLT'
               AND enabled_flag = 'Y'
               AND lookup_code = 'SC_EMAIL';
    EXCEPTION
        WHEN OTHERS
        THEN
            l_sender := 'it@bluestarinc.com';
    END;

    -------------------------------------------------------------------------------------
    -- Get Signature
    -------------------------------------------------------------------------------------
    BEGIN
        SELECT description
          INTO l_signature
          FROM apps.fnd_lookup_values_vl
         WHERE     lookup_type = 'XXBSI_EDI_EMAIL_DFLT'
               AND enabled_flag = 'Y'
               AND lookup_code = 'SC_SIGNATURE';
    EXCEPTION
        WHEN OTHERS
        THEN
            l_signature := 'Bluestar IT Team';
    END;

    -------------------------------------------------------------------------------------
    -- Get Recipient Email Address
    -------------------------------------------------------------------------------------
    BEGIN
        SELECT description
          INTO l_default_email
          FROM apps.fnd_lookup_values_vl
         WHERE     lookup_type = 'XXBSI_EDI_EMAIL_DFLT'
               AND enabled_flag = 'Y'
               AND lookup_code = p_source;
    EXCEPTION
        WHEN OTHERS
        THEN
            l_default_email := NULL;
    END;

    --
    --------------------------------------------------------------------------------------------
    -- Checking whether the Instance is PROD or not. If Instance is PROD we should send an email
    -- to Sales rep, otherwise it sends an email to given E-mail ID defined in loopkups
    --------------------------------------------------------------------------------------------
    IF l_database_name = 'Production'
    THEN
        l_recipient := p_recpmail;
    ELSE
        l_recipient := l_default_email;
    END IF;

    mail_conn := UTL_SMTP.open_connection (l_mailhost);
    UTL_SMTP.helo (mail_conn, l_mailhost);
    UTL_SMTP.mail (mail_conn, l_sender);                             -- sender

    --
    FOR i IN c1 (l_recipient)
    LOOP
        UTL_SMTP.rcpt (mail_conn, i.l_email_name);                -- recipient
    END LOOP;

    --
    UTL_SMTP.open_data (mail_conn);
    UTL_SMTP.write_data (mail_conn, 'From' || ': ' || l_sender || CRLF);

    --
    FOR i IN c1 (l_recipient)
    LOOP
        UTL_SMTP.write_data (mail_conn,'To' || ': ' || i.l_email_name || CRLF);
    END LOOP;

    --
    IF l_database_name = 'Production'
    THEN
        UTL_SMTP.write_data (mail_conn,'Subject' || ': ' || p_subject || CRLF);
    ELSE
        UTL_SMTP.write_data (mail_conn,'Subject'|| ': '|| p_subject|| ' - '|| l_database_name|| CRLF);
    END IF;

    --
    UTL_SMTP.write_data (mail_conn, 'Date: '|| TO_CHAR (SYSTIMESTAMP,'Dy "," DD Mon YYYY HH24:MI:SS TZHTZM','NLS_DATE_LANGUAGE=ENGLISH')|| UTL_TCP.crlf);
    UTL_SMTP.write_data (mail_conn, 'X-Priority: ' || '1' || CRLF);
    UTL_SMTP.write_data (mail_conn, 'MIME-Version: ' || '1.0' || UTL_TCP.CRLF);
    UTL_SMTP.write_data (mail_conn, 'Content-Type: multipart/mixed; boundary="'|| l_boundary|| '"'|| UTL_TCP.crlf|| UTL_TCP.crlf);

    --
    IF p_request_id IS NOT NULL
    THEN
        UTL_SMTP.write_data (mail_conn, '--' || l_boundary || UTL_TCP.crlf);
        UTL_SMTP.write_data (mail_conn, 'Content-Type: text/plain; charset="iso-8859-1"'|| UTL_TCP.crlf|| UTL_TCP.crlf);
        UTL_SMTP.write_data (mail_conn, UTL_TCP.CRLF || P_Message_body);
        UTL_SMTP.write_data (mail_conn, 'Thanks' || UTL_TCP.crlf);
        UTL_SMTP.write_data (mail_conn, l_signature || UTL_TCP.crlf);
    END IF;

    --
    IF p_file_name IS NOT NULL
    THEN
        UTL_SMTP.write_data (mail_conn, '--' || l_boundary || UTL_TCP.crlf);
        UTL_SMTP.write_data (mail_conn,'Content-Type: '|| p_attach_mime|| '; name="'|| p_file_name|| '"'|| UTL_TCP.crlf);
        UTL_SMTP.write_data (mail_conn,'Content-Disposition: attachment; filename="'|| p_file_name|| '"'|| UTL_TCP.crlf|| UTL_TCP.crlf);

        FOR i IN 0 ..TRUNC ((DBMS_LOB.getlength (attachment_text) - 1) / l_step)
        LOOP
            UTL_SMTP.write_data (mail_conn,DBMS_LOB.SUBSTR (attachment_text, l_step, i * l_step + 1));
        END LOOP;

        UTL_SMTP.write_data (mail_conn, UTL_TCP.crlf || UTL_TCP.crlf);
    END IF;

    --
    UTL_SMTP.write_data (mail_conn,'--' || l_boundary || '--' || UTL_TCP.crlf);
    UTL_SMTP.close_data (mail_conn);
    UTL_SMTP.quit (mail_conn);
EXCEPTION
    WHEN UTL_SMTP.transient_error OR UTL_SMTP.permanent_error
    THEN
        BEGIN
            UTL_SMTP.quit (mail_conn);
        EXCEPTION
            WHEN UTL_SMTP.TRANSIENT_ERROR OR UTL_SMTP.PERMANENT_ERROR
            THEN
                NULL; -- When the SMTP server is down or unavailable, we don't have
                      -- a connection to the server. The QUIT call will raise an
                      -- exception that we can ignore.
        END;
    WHEN OTHERS
    THEN
        fnd_file.put_line (fnd_file.LOG, 'Exception ' || SQLERRM);
END XXBSI_MAIL_ALERT;
--
END XXFASCOR_SO_API;
/
