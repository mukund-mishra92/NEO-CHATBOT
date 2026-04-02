/* Procedure structure for procedure `wm_PutPalletWaveWmsDataArchiveAndRemove` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveWmsDataArchiveAndRemove` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPalletWaveWmsDataArchiveAndRemove`(IN p_waveId CHAR(200), IN p_state VARCHAR(200))
BEGIN
  DECLARE v_waveMasterId JSON;
    
    INSERT IGNORE INTO put_wave_wms_data_archive (
        WAVE_MASTER_ID, WAVE_ID, STORAGE_REQUEST_ID, STATION_ID, STATUS, STORAGE_ID, SKU_ID, BATCH_ID, 
        QUANTITY, LEFT_OVER, STOCK_ADJUSTMENT_PAYLOAD_ID, 
        INSERTED_TIMESTAMP, INSERTED_BY, UPDATED_TIMESTAMP, UPDATED_BY, ARCHIVE_REASON
    )
    SELECT 
        WAVE_MASTER_ID, WAVE_ID, STORAGE_REQUEST_ID, STATION_ID, STATUS, STORAGE_ID, SKU_ID, BATCH_ID, 
        QUANTITY, LEFT_OVER, STOCK_ADJUSTMENT_PAYLOAD_ID, 
        INSERTED_TIMESTAMP, INSERTED_BY, UPDATED_TIMESTAMP, UPDATED_BY, p_state
    FROM put_wave_wms_data
    WHERE WAVE_ID = p_waveId;
    
    SELECT JSON_ARRAYAGG(`WAVE_MASTER_ID`) FROM `put_wave_wms_data` WHERE WAVE_ID = p_waveId INTO v_waveMasterId;

    
    DELETE P FROM put_wave_wms_data P
    INNER JOIN JSON_TABLE(v_waveMasterId,'$[*]' COLUMNS( waveMasterId INT PATH '$')) jt
    ON P.`WAVE_MASTER_ID`=jt.waveMasterId;
    
    
    SELECT JSON_ARRAYAGG(`ID`) FROM `pick_wave_wms_data_dsb_upload_validation` WHERE WAVE_ID = p_waveId  INTO v_waveMasterId;

    DELETE P FROM put_wave_wms_data_dsb_upload_validation P
    INNER JOIN JSON_TABLE(v_waveMasterId,'$[*]' COLUMNS( ID INT PATH '$')) jt
    ON P.`ID`=jt.ID;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPending_Order_allocation_V3` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPending_Order_allocation_V3` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPending_Order_allocation_V3`(
    IN P_StorageRequestId VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StorageId        VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_SkuId            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_BatchId          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StationId        INT,
    IN P_ForProcessing    INT          
)
proc_main:BEGIN
    

    
    DECLARE V_TopUpJson               JSON;
    DECLARE V_TargetJson              JSON;
    DECLARE V_RemJson                 JSON;
    DECLARE V_FinalPreviewJson        JSON;

    DECLARE V_PendingQty              BIGINT DEFAULT 0;
    DECLARE V_AllocSum                BIGINT DEFAULT 0;

    DECLARE V_MaxBinWeightGrams       BIGINT DEFAULT 0;

    
    DECLARE V_MaxQtyPerBin            INT DEFAULT 0;     
    DECLARE V_SkuUnitWeightGrams      INT DEFAULT 0;
    DECLARE V_MinSegmentSize          INT DEFAULT 1;
    DECLARE V_SkuCategory             INT DEFAULT 0;
    DECLARE V_SkuROS                  DECIMAL(10,2) DEFAULT 0.00;

    
    DECLARE V_ROS_ThresholdPct        DECIMAL(10,2) DEFAULT 60.00;
    DECLARE V_BinCapacityThresholdPct DECIMAL(10,2) DEFAULT 50.00;
    DECLARE V_TopUpMinRemainingSpacePct DECIMAL(10,2) DEFAULT 70.00;

    
    DECLARE V_TargetQty               BIGINT DEFAULT 0;    
    DECLARE V_TargetAlloc             BIGINT DEFAULT 0;    
    DECLARE V_TotalCandidates         INT DEFAULT 8000;

    
    DECLARE V_CapPerSeg6              INT DEFAULT 0;
    DECLARE V_CapPerSeg4              INT DEFAULT 0;
    DECLARE V_CapPerSeg2              INT DEFAULT 0;
    DECLARE V_CapPerSeg1              INT DEFAULT 0;

    DECLARE V_EPS                     DECIMAL(10,6) DEFAULT 0.000100;

    
    DECLARE v_wms_data_total_qty      BIGINT DEFAULT 0;
    DECLARE v_order_master_total_expected BIGINT DEFAULT 0;

    
    DECLARE v_lock_name               VARCHAR(256);
    DECLARE v_lock_ok                 INT DEFAULT 1;

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF P_ForProcessing = 1 THEN
            ROLLBACK;
            DO RELEASE_LOCK(v_lock_name);
        END IF;
        SET SESSION cte_max_recursion_depth = 1000;
        RESIGNAL;
    END;

    
    SELECT CAST(KEY_VALUE AS SIGNED)
      INTO V_MaxBinWeightGrams
      FROM master_config
     WHERE KEY_NAME = 'MAX_WEIGHT_ALLOWED_ON_BOT_GRAMS'
     LIMIT 1;

    SET V_MaxBinWeightGrams = COALESCE(V_MaxBinWeightGrams, 2147483647);

    SELECT
        COALESCE(MAX(CASE WHEN KEY_NAME='ROS_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_ROS_ThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='BIN_CAPACITY_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_BinCapacityThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='TOPUP_MIN_REMAINING_SPACE_PCT' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_TopUpMinRemainingSpacePct)
    INTO
        V_ROS_ThresholdPct,
        V_BinCapacityThresholdPct,
        V_TopUpMinRemainingSpacePct
    FROM master_config
    WHERE KEY_NAME IN ('ROS_THRESHOLD','BIN_CAPACITY_THRESHOLD','TOPUP_MIN_REMAINING_SPACE_PCT');

    SET SESSION cte_max_recursion_depth = 10000;
    SET SESSION group_concat_max_len = 65535;

    
    SELECT
        MAX_QUANTITY_PER_SEGMENT,
        WEIGHT_OF_EACH_SKU,
        MIN_SEGMENT_SIZE,
        category,
        COALESCE(ROS,0)
    INTO
        V_MaxQtyPerBin,
        V_SkuUnitWeightGrams,
        V_MinSegmentSize,
        V_SkuCategory,
        V_SkuROS
    FROM sku_master
    WHERE SKU_ID = P_SkuId
    LIMIT 1;

    IF V_MaxQtyPerBin IS NULL OR V_MaxQtyPerBin <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'MAX_QTY_PER_BIN missing/invalid (sku_master.MAX_QUANTITY_PER_SEGMENT)';
    END IF;

    SET V_SkuUnitWeightGrams = COALESCE(V_SkuUnitWeightGrams,0);
    SET V_MinSegmentSize = GREATEST(1, COALESCE(V_MinSegmentSize,1));

    
    SET V_CapPerSeg6 = FLOOR(V_MaxQtyPerBin / 6);
    SET V_CapPerSeg4 = FLOOR(V_MaxQtyPerBin / 4);
    SET V_CapPerSeg2 = FLOOR(V_MaxQtyPerBin / 2);
    SET V_CapPerSeg1 = FLOOR(V_MaxQtyPerBin / 1);

    
    SET V_TargetQty = CEIL( COALESCE(V_SkuROS,0) * (COALESCE(V_ROS_ThresholdPct,60.0)/100.0) );

    
    IF P_ForProcessing = 1 THEN
        SET v_lock_name = CONCAT('PUTALLOC|',P_StorageRequestId,'|',P_StorageId,'|',P_SkuId,'|',P_BatchId);
        SELECT GET_LOCK(v_lock_name, 5) INTO v_lock_ok;
        IF v_lock_ok <> 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='PUT_ALLOC_LOCK_TIMEOUT';
        END IF;

        START TRANSACTION;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest;
    CREATE TEMPORARY TABLE Tmp_StorageRequest (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          BIGINT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID),
        INDEX (WAVE_ID)
    ) ENGINE=MEMORY;

    INSERT INTO Tmp_StorageRequest (WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index)
    SELECT
        PW.WAVE_ID,
        P_StorageRequestId,
        PW.STORAGE_ID,
        P_SkuId,
        P_BatchId,
        SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
        ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
    FROM (
        SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
        FROM put_wave_wms_data
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY WAVE_ID, STORAGE_ID
    ) PW
    LEFT JOIN (
        SELECT
            WAVE_ID,
            STORAGE_ID,
            SUM(
                CASE
                    WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                    ELSE EXPECTED_QUANTITY
                END
            ) AS EXPECTED_QUANTITY
        FROM put_wave_order_master
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY WAVE_ID, STORAGE_ID
    ) PWO
      ON PWO.STORAGE_ID = PW.STORAGE_ID
     AND PWO.WAVE_ID    = PW.WAVE_ID
    GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

    SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
    FROM Tmp_StorageRequest;

    
    SET V_TopUpJson = NULL;

    IF V_PendingQty > 0
       AND EXISTS (
           SELECT 1
           FROM live_inventory_master
           WHERE ARTICLE_ID = P_SkuId
             AND BATCH_ID   = P_BatchId
       )
    THEN
        DROP TEMPORARY TABLE IF EXISTS Tmp_Req_A;
        DROP TEMPORARY TABLE IF EXISTS Tmp_Req_B;

        CREATE TEMPORARY TABLE Tmp_Req_A LIKE Tmp_StorageRequest;
        INSERT INTO Tmp_Req_A SELECT * FROM Tmp_StorageRequest;

        CREATE TEMPORARY TABLE Tmp_Req_B LIKE Tmp_StorageRequest;
        INSERT INTO Tmp_Req_B SELECT * FROM Tmp_StorageRequest;

        WITH RECURSIVE
        AisleCost AS (
            SELECT Aisle_Number, MIN(Cost) AS Cost
            FROM station_to_aisle_cost
            WHERE Station_ID = P_StationId
            GROUP BY Aisle_Number
        ),
        SegWeight AS (
            
            SELECT
                L0.BIN_ID,
                L0.SEGMENT_NO,
                SUM( (L0.QUANTITY + L0.VIRTUAL_QUANTITY_TO_PUT) * COALESCE(SM0.WEIGHT_OF_EACH_SKU,0) ) AS CurrentWeightSegGrams
            FROM live_inventory_master L0
            LEFT JOIN sku_master SM0 ON SM0.SKU_ID = L0.ARTICLE_ID
            WHERE IFNULL(L0.remark,'na') NOT IN ('no_space','audit_marked')
            GROUP BY L0.BIN_ID, L0.SEGMENT_NO
        ),
        Phase1Candidates AS (
            SELECT
                L.BIN_ID,
                L.SEGMENT_NO,
                BIM.BIN_SEGMENTS,
                COALESCE(AC.Cost, 9999) AS Cost,
                (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT) AS QtyInSeg,

                
                CASE
                    WHEN BIM.BIN_SEGMENTS=6 THEN GREATEST(V_CapPerSeg6,1)
                    WHEN BIM.BIN_SEGMENTS=4 THEN GREATEST(V_CapPerSeg4,1)
                    WHEN BIM.BIN_SEGMENTS=2 THEN GREATEST(V_CapPerSeg2,1)
                    ELSE GREATEST(V_CapPerSeg1,1)
                END AS QtyCapPerSeg,

                COALESCE(SW.CurrentWeightSegGrams,0) AS CurrentWeightSegGrams,

                
                FLOOR(V_MaxBinWeightGrams / BIM.BIN_SEGMENTS) AS SegMaxWeightGrams
            FROM live_inventory_master L
            INNER JOIN bin_info_master BIM ON BIM.BIN_ID = L.BIN_ID
            INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
            INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
            LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
            LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
            LEFT JOIN SegWeight SW ON SW.BIN_ID = L.BIN_ID AND SW.SEGMENT_NO = L.SEGMENT_NO
            WHERE L.ARTICLE_ID = P_SkuId
              AND L.BATCH_ID   = P_BatchId
              AND IFNULL(L.remark,'na') NOT IN ('no_space','audit_marked')
              AND LBM.LOCATION_ID IS NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master P
                  WHERE P.BIN_ID         = L.BIN_ID
                    AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                    AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              )
        ),
        Phase1Scored AS (
            SELECT
                C.*,
                GREATEST(C.QtyCapPerSeg - C.QtyInSeg, 0) AS BalanceSegQty,

                
                CASE
                    WHEN V_SkuUnitWeightGrams <= 0 THEN 999999999
                    ELSE FLOOR( GREATEST(C.SegMaxWeightGrams - C.CurrentWeightSegGrams,0) / V_SkuUnitWeightGrams )
                END AS BalanceWeightQty,

                CASE
                    WHEN C.QtyCapPerSeg <= 0 THEN 0
                    ELSE (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) / C.QtyCapPerSeg) * 100.0
                END AS BalanceSegFreePct,

                ROW_NUMBER() OVER (
                    PARTITION BY C.BIN_ID
                    ORDER BY GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) DESC, C.SEGMENT_NO
                ) AS rn_in_bin
            FROM Phase1Candidates C
            WHERE C.QtyCapPerSeg > 0
        ),
        Phase1BinsOrdered AS (
            SELECT
                B.BIN_ID,
                B.SEGMENT_NO,
                LEAST(B.BalanceSegQty, B.BalanceWeightQty) AS SegmentCapacity,
                ROW_NUMBER() OVER (
                    ORDER BY
                        CASE WHEN B.BIN_SEGMENTS=6 THEN 1 WHEN B.BIN_SEGMENTS=4 THEN 2 WHEN B.BIN_SEGMENTS=2 THEN 3 WHEN B.BIN_SEGMENTS=1 THEN 4 ELSE 9 END,
                        B.Cost,
                        B.BIN_ID,
                        B.SEGMENT_NO
                ) AS bin_index
            FROM Phase1Scored B
            WHERE B.rn_in_bin = 1
              AND B.BalanceSegFreePct >= (V_TopUpMinRemainingSpacePct - V_EPS)
              AND LEAST(B.BalanceSegQty, B.BalanceWeightQty) >= V_MinSegmentSize
        ),
        alloc1 AS (
            SELECT
                ob.BIN_ID,
                ob.SEGMENT_NO,
                ob.SegmentCapacity,
                r.STORAGE_ID,
                P_SkuId   AS SKU_ID,
                P_BatchId AS BATCH_ID,
                r.WAVE_ID,
                CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS AllocatedQty,
                r.RequestQty - CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS RemQty,
                ob.bin_index,
                r.req_index
            FROM Phase1BinsOrdered ob
            JOIN Tmp_Req_A r
              ON r.req_index = 1
             AND ob.bin_index = 1
            WHERE r.RequestQty > 0

            UNION ALL

            SELECT
                b.BIN_ID,
                b.SEGMENT_NO,
                b.SegmentCapacity,
                CASE WHEN a.RemQty = 0 THEN r2.STORAGE_ID ELSE a.STORAGE_ID END,
                P_SkuId,
                P_BatchId,
                CASE WHEN a.RemQty = 0 THEN r2.WAVE_ID ELSE a.WAVE_ID END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                    ELSE
                        CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        r2.RequestQty - CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                    ELSE
                        a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                b.bin_index,
                CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
            FROM Phase1BinsOrdered b
            JOIN alloc1 a
              ON b.bin_index = a.bin_index + 1
            LEFT JOIN Tmp_Req_B r2
              ON r2.req_index = a.req_index + 1
            WHERE (a.RemQty > 0) OR (r2.req_index IS NOT NULL AND r2.RequestQty > 0)
        )
        SELECT JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'PHASE',       'TOPUP',
                       'WAVE_ID',      WAVE_ID,
                       'STORAGE_ID',   STORAGE_ID,
                       'BIN_ID',       BIN_ID,
                       'SEGMENT_NO',   SEGMENT_NO,
                       'SKU_ID',       P_SkuId,
                       'BATCH_ID',     P_BatchId,
                       'AllocatedQty', AllocatedQty
                   )
               )
        INTO V_TopUpJson
        FROM alloc1
        WHERE AllocatedQty > 0;

        
        SET V_AllocSum = 0;
        IF V_TopUpJson IS NOT NULL THEN
            SELECT COALESCE(SUM(jt.AllocatedQty),0)
              INTO V_AllocSum
            FROM JSON_TABLE(V_TopUpJson, '$[*]' COLUMNS (AllocatedQty BIGINT PATH '$.AllocatedQty')) jt;
        END IF;

        IF V_AllocSum > V_PendingQty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PHASE1_OVER_ALLOCATION: JSON allocation exceeds pending qty';
        END IF;

        
        IF V_TopUpJson IS NOT NULL THEN
            UPDATE Tmp_StorageRequest R
            JOIN (
                SELECT
                    jt.WAVE_ID,
                    jt.STORAGE_ID,
                    SUM(jt.AllocatedQty) AS alloc_qty
                FROM JSON_TABLE(
                    V_TopUpJson, '$[*]' COLUMNS (
                        WAVE_ID      VARCHAR(64) PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) PATH '$.STORAGE_ID',
                        AllocatedQty BIGINT      PATH '$.AllocatedQty'
                    )
                ) jt
                GROUP BY jt.WAVE_ID, jt.STORAGE_ID
            ) A
              ON A.WAVE_ID = R.WAVE_ID AND A.STORAGE_ID = R.STORAGE_ID
            SET R.RequestQty = GREATEST(R.RequestQty - A.alloc_qty, 0);
        END IF;

        SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
        FROM Tmp_StorageRequest;

        
        IF P_ForProcessing = 1 AND V_TopUpJson IS NOT NULL THEN

            INSERT INTO order_bin_mapping (BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP)
            SELECT DISTINCT jt.BIN_ID, P_StationId, 'RACK_PICK', 'PENDING', 0, NOW()
            FROM JSON_TABLE(V_TopUpJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
            LEFT JOIN order_bin_mapping obm_ok
                ON  obm_ok.BIN_ID     = jt.BIN_ID
                AND obm_ok.STATION_ID = P_StationId
                AND obm_ok.TYPE       = 'RACK_PICK'
                AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION','ON_STATION')
            WHERE obm_ok.ORDER_BIN_ID IS NULL;

            INSERT INTO put_wave_order_master (
                PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
            )
            SELECT
                UUID(),
                P_StationId,
                jt.WAVE_ID,
                P_StorageRequestId,
                jt.STORAGE_ID,
                COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING',
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty
            FROM JSON_TABLE(
                V_TopUpJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) PATH '$.STORAGE_ID',
                    BIN_ID       INT         PATH '$.BIN_ID',
                    SEGMENT_NO   INT         PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) PATH '$.BATCH_ID',
                    AllocatedQty BIGINT      PATH '$.AllocatedQty'
                )
            ) jt
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK'
                  AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION','ON_STATION')
                GROUP BY BIN_ID, STATION_ID
            ) obm_reuse
              ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                GROUP BY BIN_ID, STATION_ID
            ) obm_new
              ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
            WHERE jt.AllocatedQty > 0
              AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master p
                  WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                    AND p.STORAGE_ID         = jt.STORAGE_ID
                    AND p.BIN_ID             = jt.BIN_ID
                    AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                    AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              );

            
            UPDATE live_inventory_master L
            INNER JOIN put_wave_order_master PWO
                ON PWO.SKU_ID         = L.ARTICLE_ID
               AND PWO.BATCH_ID       = L.BATCH_ID
               AND PWO.BIN_ID         = L.BIN_ID
               AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
            SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY
            WHERE L.ARTICLE_ID   = P_SkuId
              AND L.BATCH_ID     = P_BatchId
              AND PWO.STORAGE_ID = P_StorageId
              AND PWO.STATUS     = 'PENDING';

        END IF;
    END IF;

    
    SET V_TargetJson = NULL;
    SET V_RemJson = NULL;

    IF V_PendingQty > 0 THEN

        
        SET V_TotalCandidates = LEAST(
            20000,
            GREATEST(3000, CEIL(V_PendingQty / GREATEST(1, LEAST(V_CapPerSeg6,V_CapPerSeg4,V_CapPerSeg2,V_CapPerSeg1,1))) * 12)
        );

        
        SET V_TargetAlloc = LEAST(V_PendingQty, GREATEST(V_TargetQty,0));

        IF V_TargetAlloc > 0 THEN

            
            DROP TEMPORARY TABLE IF EXISTS Tmp_TargetReq;
            CREATE TEMPORARY TABLE Tmp_TargetReq LIKE Tmp_StorageRequest;

            INSERT INTO Tmp_TargetReq (WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index)
            SELECT
                t.WAVE_ID, t.STORAGE_REQUEST_ID, t.STORAGE_ID, t.SKU_ID, t.BATCH_ID,
                GREATEST(0, LEAST(t.RequestQty, V_TargetAlloc - t.cum_before)) AS RequestQtyTarget,
                t.req_index
            FROM (
                SELECT
                    R.*,
                    COALESCE(
                        SUM(R.RequestQty) OVER (
                            ORDER BY R.req_index
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                        ),
                        0
                    ) AS cum_before
                FROM Tmp_StorageRequest R
                WHERE R.RequestQty > 0
            ) t
            WHERE (V_TargetAlloc - t.cum_before) > 0
              AND GREATEST(0, LEAST(t.RequestQty, V_TargetAlloc - t.cum_before)) > 0;

            DROP TEMPORARY TABLE IF EXISTS Tmp_TargetReq_A;
            DROP TEMPORARY TABLE IF EXISTS Tmp_TargetReq_B;

            CREATE TEMPORARY TABLE Tmp_TargetReq_A LIKE Tmp_TargetReq;
            INSERT INTO Tmp_TargetReq_A SELECT * FROM Tmp_TargetReq;

            CREATE TEMPORARY TABLE Tmp_TargetReq_B LIKE Tmp_TargetReq;
            INSERT INTO Tmp_TargetReq_B SELECT * FROM Tmp_TargetReq;

            WITH RECURSIVE
            AisleCost AS (
                SELECT Aisle_Number, MIN(Cost) AS Cost
                FROM station_to_aisle_cost
                WHERE Station_ID = P_StationId
                GROUP BY Aisle_Number
            ),
            FreeBins AS (
                SELECT DISTINCT
                    BIM.BIN_ID,
                    BIM.BIN_SEGMENTS,
                    COALESCE(AC.Cost, 9999) AS Cost,
                    STBM.LOCATION_ID
                FROM bin_info_master BIM
                INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
                INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
                LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
                WHERE LBM.LOCATION_ID IS NULL
            ),
            ReservedSegs AS (
                SELECT DISTINCT
                    P.BIN_ID,
                    P.BIN_SEGMENT_NO AS SEGMENT_NO
                FROM put_wave_order_master P
                WHERE P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
            ),
            BaseSegs AS (
                SELECT
                    L.BIN_ID,
                    L.SEGMENT_NO,
                    L.ARTICLE_ID,
                    L.BATCH_ID,
                    L.QUANTITY,
                    L.VIRTUAL_QUANTITY_TO_PUT,
                    IFNULL(L.remark,'na') AS remark,
                    FB.BIN_SEGMENTS,
                    FB.Cost
                FROM live_inventory_master L
                INNER JOIN FreeBins FB ON FB.BIN_ID = L.BIN_ID
                WHERE IFNULL(L.remark,'na') = 'na'
            ),
            EmptySegs AS (
                SELECT
                    B.*
                FROM BaseSegs B
                LEFT JOIN ReservedSegs R
                  ON R.BIN_ID = B.BIN_ID AND R.SEGMENT_NO = B.SEGMENT_NO
                WHERE R.BIN_ID IS NULL
                  AND (
                        B.ARTICLE_ID = 'no-sku'
                     OR (B.QUANTITY + B.VIRTUAL_QUANTITY_TO_PUT) = 0
                  )
            ),
            BinProximity AS (
                SELECT
                    B.BIN_ID,
                    COALESCE(MAX(AP.PROXIMITY_SCORE),0) AS ProximityScore
                FROM BaseSegs B
                LEFT JOIN article_proximity_score AP
                  ON AP.PARENT_ARTICLE_ID = P_SkuId
                 AND AP.CHILD_ARTICLE_ID  = B.ARTICLE_ID
                WHERE (B.QUANTITY + B.VIRTUAL_QUANTITY_TO_PUT) > 0
                  AND B.ARTICLE_ID <> 'no-sku'
                GROUP BY B.BIN_ID
            ),
            HasSameSkuBin AS (
                SELECT BIN_ID, 1 AS HasSameSku
                FROM BaseSegs
                WHERE ARTICLE_ID = P_SkuId
                  AND BATCH_ID   = P_BatchId
                  AND (QUANTITY + VIRTUAL_QUANTITY_TO_PUT) > 0
                GROUP BY BIN_ID
            ),
            BinOBM AS (
                
                SELECT BIN_ID, BOT_ID, STATUS, TYPE, STATION_ID
                FROM (
                    SELECT
                        obm.*,
                        ROW_NUMBER() OVER (
                            PARTITION BY obm.BIN_ID
                            ORDER BY
                                CASE WHEN obm.STATION_ID = P_StationId THEN 0 ELSE 1 END,
                                CASE obm.STATUS
                                    WHEN 'PENDING'        THEN 1
                                    WHEN 'TASK_ALLOCATED' THEN 2
                                    WHEN 'BIN_PICKED'     THEN 3
                                    WHEN 'PRE_ON_STATION' THEN 4
                                    WHEN 'ON_STATION'     THEN 5
                                    ELSE 9
                                END,
                                obm.ORDER_BIN_ID DESC
                        ) AS rn
                    FROM order_bin_mapping obm
                    WHERE obm.TYPE = 'RACK_PICK'
                      AND obm.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED')
                ) x
                WHERE x.rn = 1
            ),
            BinAgg AS (
                SELECT
                    FB.BIN_ID,
                    FB.BIN_SEGMENTS,
                    FB.Cost,
                    COALESCE(BP.ProximityScore,0) AS ProximityScore,
                    COALESCE(HS.HasSameSku,0) AS HasSameSku,

                    SUM(CASE WHEN (BS.QUANTITY + BS.VIRTUAL_QUANTITY_TO_PUT) > 0 AND BS.ARTICLE_ID <> 'no-sku' THEN 1 ELSE 0 END) AS OccupiedSegments,
                    COUNT(ES.BIN_ID) AS EmptySegmentsAvail,

                    CASE
                        WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED') THEN 1
                        WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('BIN_PICKED','PRE_ON_STATION','ON_STATION') THEN 2
                        WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATION_ID = P_StationId THEN 3
                        WHEN OBM.TYPE = 'RACK_PICK'
                         AND (OBM.STATION_ID IS NULL OR OBM.STATION_ID <> P_StationId) THEN 4
                        ELSE 5
                    END AS StationPriority,

                    CASE
                        WHEN FB.BIN_SEGMENTS=6 THEN GREATEST(V_CapPerSeg6,1)
                        WHEN FB.BIN_SEGMENTS=4 THEN GREATEST(V_CapPerSeg4,1)
                        WHEN FB.BIN_SEGMENTS=2 THEN GREATEST(V_CapPerSeg2,1)
                        ELSE GREATEST(V_CapPerSeg1,1)
                    END AS QtyCapPerSeg,

                    
                    CASE
                        WHEN V_SkuUnitWeightGrams <= 0 THEN 999999999
                        ELSE FLOOR( FLOOR(V_MaxBinWeightGrams / FB.BIN_SEGMENTS) / V_SkuUnitWeightGrams )
                    END AS WeightCapPerSegEmpty
                FROM FreeBins FB
                LEFT JOIN BaseSegs BS ON BS.BIN_ID = FB.BIN_ID
                LEFT JOIN EmptySegs ES ON ES.BIN_ID = FB.BIN_ID
                LEFT JOIN BinProximity BP ON BP.BIN_ID = FB.BIN_ID
                LEFT JOIN HasSameSkuBin HS ON HS.BIN_ID = FB.BIN_ID
                LEFT JOIN BinOBM OBM ON OBM.BIN_ID = FB.BIN_ID
                GROUP BY
                    FB.BIN_ID, FB.BIN_SEGMENTS, FB.Cost,
                    BP.ProximityScore, HS.HasSameSku,
                    OBM.STATION_ID, OBM.STATUS, OBM.TYPE
                HAVING EmptySegmentsAvail > 0
            ),
            BinScored AS (
                SELECT
                    BA.*,
                    LEAST(BA.QtyCapPerSeg, BA.WeightCapPerSegEmpty) AS SegmentCapEmpty,

                    
                    LEAST(
                        BA.EmptySegmentsAvail,
                        BA.BIN_SEGMENTS,
                        GREATEST(
                            1,
                            CEIL( LEAST(V_TargetAlloc, (LEAST(BA.QtyCapPerSeg, BA.WeightCapPerSegEmpty) * BA.EmptySegmentsAvail)) / GREATEST(LEAST(BA.QtyCapPerSeg, BA.WeightCapPerSegEmpty), 1) )
                        )
                    ) AS SegsForTarget
                FROM BinAgg BA
                WHERE LEAST(BA.QtyCapPerSeg, BA.WeightCapPerSegEmpty) >= V_MinSegmentSize
            ),
            BinRanked AS (
                SELECT
                    BS.*,
                    (BS.SegsForTarget / BS.BIN_SEGMENTS) * 100.0 AS UtilPct,

                    
                    CASE
                        WHEN (BS.SegsForTarget / BS.BIN_SEGMENTS) * 100.0 > (V_BinCapacityThresholdPct + V_EPS)
                        THEN CASE BS.BIN_SEGMENTS WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 4 THEN 3 WHEN 6 THEN 4 ELSE 9 END
                        ELSE 9
                    END AS CascadeRank,

                    (BS.SegmentCapEmpty * BS.SegsForTarget) AS TargetCap,

                    ROW_NUMBER() OVER (
                        ORDER BY
                            BS.StationPriority,
                            CASE WHEN (BS.SegmentCapEmpty * BS.SegsForTarget) >= V_TargetAlloc THEN 1 ELSE 0 END DESC,
                            
                            CASE
                                WHEN (BS.SegsForTarget / BS.BIN_SEGMENTS) * 100.0 > (V_BinCapacityThresholdPct + V_EPS)
                                THEN CASE BS.BIN_SEGMENTS WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 4 THEN 3 WHEN 6 THEN 4 ELSE 9 END
                                ELSE 9
                            END,
                            BS.SegsForTarget ASC,
                            BS.Cost,
                            BS.ProximityScore DESC,
                            BS.HasSameSku DESC,
                            BS.BIN_ID
                    ) AS BinRank
                FROM BinScored BS
            ),
            PickedBin AS (
                SELECT * FROM BinRanked WHERE BinRank = 1
            ),
            SegCandidates AS (
                SELECT
                    ES.BIN_ID,
                    ES.SEGMENT_NO,
                    PB.BIN_SEGMENTS,
                    PB.Cost,
                    PB.BinRank,
                    PB.SegsForTarget AS SegsWanted,
                    PB.SegmentCapEmpty AS SegmentCapacity,
                    BSR.RANKING
                FROM EmptySegs ES
                INNER JOIN PickedBin PB ON PB.BIN_ID = ES.BIN_ID
                INNER JOIN bin_segment_ranking BSR
                  ON BSR.BIN_SEGMENT_COUNT = PB.BIN_SEGMENTS
                 AND BSR.SEGMENT_ID        = ES.SEGMENT_NO
            ),
            SegPicked AS (
                SELECT
                    S.*,
                    ROW_NUMBER() OVER (PARTITION BY S.BIN_ID ORDER BY S.RANKING, S.SEGMENT_NO) AS rn_in_bin
                FROM SegCandidates S
            ),
            OrderedSegments AS (
                SELECT
                    P.*,
                    ROW_NUMBER() OVER (ORDER BY P.RANKING, P.SEGMENT_NO) AS seg_index
                FROM SegPicked P
                WHERE P.rn_in_bin <= P.SegsWanted
                  AND P.SegmentCapacity >= V_MinSegmentSize
            ),
            alloc AS (
                SELECT
                    ob.BIN_ID,
                    ob.SEGMENT_NO,
                    ob.SegmentCapacity,
                    sr.STORAGE_ID,
                    sr.WAVE_ID,
                    CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS AllocatedQty,
                    sr.RequestQty - CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS RemQty,
                    ob.seg_index,
                    sr.req_index
                FROM OrderedSegments ob
                JOIN Tmp_TargetReq_A sr
                  ON sr.req_index = 1
                 AND ob.seg_index = 1
                WHERE sr.RequestQty > 0

                UNION ALL

                SELECT
                    b.BIN_ID,
                    b.SEGMENT_NO,
                    b.SegmentCapacity,
                    CASE WHEN a.RemQty = 0 THEN s2.STORAGE_ID ELSE a.STORAGE_ID END,
                    CASE WHEN a.RemQty = 0 THEN s2.WAVE_ID    ELSE a.WAVE_ID    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                        ELSE
                            CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            s2.RequestQty - CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                        ELSE
                            a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    b.seg_index,
                    CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
                FROM OrderedSegments b
                JOIN alloc a
                  ON b.seg_index = a.seg_index + 1
                LEFT JOIN Tmp_TargetReq_B s2
                  ON s2.req_index = a.req_index + 1
                WHERE (a.RemQty > 0) OR (s2.req_index IS NOT NULL AND s2.RequestQty > 0)
            )
            SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'PHASE',       'TARGET',
                           'WAVE_ID',      WAVE_ID,
                           'STORAGE_ID',   STORAGE_ID,
                           'BIN_ID',       BIN_ID,
                           'SEGMENT_NO',   SEGMENT_NO,
                           'SKU_ID',       P_SkuId,
                           'BATCH_ID',     P_BatchId,
                           'AllocatedQty', AllocatedQty
                       )
                   )
            INTO V_TargetJson
            FROM alloc
            WHERE AllocatedQty > 0;

            
            IF V_TargetJson IS NOT NULL THEN
                UPDATE Tmp_StorageRequest R
                JOIN (
                    SELECT
                        jt.WAVE_ID,
                        jt.STORAGE_ID,
                        SUM(jt.AllocatedQty) AS alloc_qty
                    FROM JSON_TABLE(
                        V_TargetJson, '$[*]' COLUMNS (
                            WAVE_ID      VARCHAR(64) PATH '$.WAVE_ID',
                            STORAGE_ID   VARCHAR(64) PATH '$.STORAGE_ID',
                            AllocatedQty BIGINT      PATH '$.AllocatedQty'
                        )
                    ) jt
                    GROUP BY jt.WAVE_ID, jt.STORAGE_ID
                ) A
                  ON A.WAVE_ID = R.WAVE_ID AND A.STORAGE_ID = R.STORAGE_ID
                SET R.RequestQty = GREATEST(R.RequestQty - A.alloc_qty, 0);
            END IF;

            SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
            FROM Tmp_StorageRequest;

        END IF; 

        
        IF V_PendingQty > 0 THEN

            DROP TEMPORARY TABLE IF EXISTS Tmp_RemReq_A;
            DROP TEMPORARY TABLE IF EXISTS Tmp_RemReq_B;

            CREATE TEMPORARY TABLE Tmp_RemReq_A LIKE Tmp_StorageRequest;
            INSERT INTO Tmp_RemReq_A SELECT * FROM Tmp_StorageRequest;

            CREATE TEMPORARY TABLE Tmp_RemReq_B LIKE Tmp_StorageRequest;
            INSERT INTO Tmp_RemReq_B SELECT * FROM Tmp_StorageRequest;

            WITH RECURSIVE
            AisleCost AS (
                SELECT Aisle_Number, MIN(Cost) AS Cost
                FROM station_to_aisle_cost
                WHERE Station_ID = P_StationId
                GROUP BY Aisle_Number
            ),
            FreeBins AS (
                SELECT DISTINCT
                    BIM.BIN_ID,
                    BIM.BIN_SEGMENTS,
                    COALESCE(AC.Cost, 9999) AS Cost,
                    STBM.LOCATION_ID
                FROM bin_info_master BIM
                INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
                INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
                LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
                WHERE LBM.LOCATION_ID IS NULL
            ),
            ReservedSegs AS (
                SELECT DISTINCT
                    P.BIN_ID,
                    P.BIN_SEGMENT_NO AS SEGMENT_NO
                FROM put_wave_order_master P
                WHERE P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
            ),
            BaseSegs AS (
                SELECT
                    L.BIN_ID,
                    L.SEGMENT_NO,
                    L.ARTICLE_ID,
                    L.BATCH_ID,
                    L.QUANTITY,
                    L.VIRTUAL_QUANTITY_TO_PUT,
                    IFNULL(L.remark,'na') AS remark,
                    FB.BIN_SEGMENTS,
                    FB.Cost
                FROM live_inventory_master L
                INNER JOIN FreeBins FB ON FB.BIN_ID = L.BIN_ID
                WHERE IFNULL(L.remark,'na') = 'na'
            ),
            EmptySegs AS (
                SELECT
                    B.*
                FROM BaseSegs B
                LEFT JOIN ReservedSegs R
                  ON R.BIN_ID = B.BIN_ID AND R.SEGMENT_NO = B.SEGMENT_NO
                WHERE R.BIN_ID IS NULL
                  AND (
                        B.ARTICLE_ID = 'no-sku'
                     OR (B.QUANTITY + B.VIRTUAL_QUANTITY_TO_PUT) = 0
                  )
            ),
            BinProximity AS (
                SELECT
                    B.BIN_ID,
                    COALESCE(MAX(AP.PROXIMITY_SCORE),0) AS ProximityScore
                FROM BaseSegs B
                LEFT JOIN article_proximity_score AP
                  ON AP.PARENT_ARTICLE_ID = P_SkuId
                 AND AP.CHILD_ARTICLE_ID  = B.ARTICLE_ID
                WHERE (B.QUANTITY + B.VIRTUAL_QUANTITY_TO_PUT) > 0
                  AND B.ARTICLE_ID <> 'no-sku'
                GROUP BY B.BIN_ID
            ),
            HasSameSkuBin AS (
                SELECT BIN_ID, 1 AS HasSameSku
                FROM BaseSegs
                WHERE ARTICLE_ID = P_SkuId
                  AND BATCH_ID   = P_BatchId
                  AND (QUANTITY + VIRTUAL_QUANTITY_TO_PUT) > 0
                GROUP BY BIN_ID
            ),
            BinOBM AS (
                SELECT BIN_ID, BOT_ID, STATUS, TYPE, STATION_ID
                FROM (
                    SELECT
                        obm.*,
                        ROW_NUMBER() OVER (
                            PARTITION BY obm.BIN_ID
                            ORDER BY
                                CASE WHEN obm.STATION_ID = P_StationId THEN 0 ELSE 1 END,
                                CASE obm.STATUS
                                    WHEN 'PENDING'        THEN 1
                                    WHEN 'TASK_ALLOCATED' THEN 2
                                    WHEN 'BIN_PICKED'     THEN 3
                                    WHEN 'PRE_ON_STATION' THEN 4
                                    WHEN 'ON_STATION'     THEN 5
                                    ELSE 9
                                END,
                                obm.ORDER_BIN_ID DESC
                        ) AS rn
                    FROM order_bin_mapping obm
                    WHERE obm.TYPE = 'RACK_PICK'
                      AND obm.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED')
                ) x
                WHERE x.rn = 1
            ),
            BinAgg AS (
                SELECT
                    FB.BIN_ID,
                    FB.BIN_SEGMENTS,
                    FB.Cost,
                    COALESCE(BP.ProximityScore,0) AS ProximityScore,
                    COALESCE(HS.HasSameSku,0) AS HasSameSku,

                    SUM(CASE WHEN (BS.QUANTITY + BS.VIRTUAL_QUANTITY_TO_PUT) > 0 AND BS.ARTICLE_ID <> 'no-sku' THEN 1 ELSE 0 END) AS OccupiedSegments,
                    COUNT(ES.BIN_ID) AS EmptySegmentsAvail,

                    CASE
                        WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED') THEN 1
                        WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('BIN_PICKED','PRE_ON_STATION','ON_STATION') THEN 2
                        WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATION_ID = P_StationId THEN 3
                        WHEN OBM.TYPE = 'RACK_PICK'
                         AND (OBM.STATION_ID IS NULL OR OBM.STATION_ID <> P_StationId) THEN 4
                        ELSE 5
                    END AS StationPriority,

                    CASE
                        WHEN FB.BIN_SEGMENTS=6 THEN GREATEST(V_CapPerSeg6,1)
                        WHEN FB.BIN_SEGMENTS=4 THEN GREATEST(V_CapPerSeg4,1)
                        WHEN FB.BIN_SEGMENTS=2 THEN GREATEST(V_CapPerSeg2,1)
                        ELSE GREATEST(V_CapPerSeg1,1)
                    END AS QtyCapPerSeg,

                    CASE
                        WHEN V_SkuUnitWeightGrams <= 0 THEN 999999999
                        ELSE FLOOR( FLOOR(V_MaxBinWeightGrams / FB.BIN_SEGMENTS) / V_SkuUnitWeightGrams )
                    END AS WeightCapPerSegEmpty
                FROM FreeBins FB
                LEFT JOIN BaseSegs BS ON BS.BIN_ID = FB.BIN_ID
                LEFT JOIN EmptySegs ES ON ES.BIN_ID = FB.BIN_ID
                LEFT JOIN BinProximity BP ON BP.BIN_ID = FB.BIN_ID
                LEFT JOIN HasSameSkuBin HS ON HS.BIN_ID = FB.BIN_ID
                LEFT JOIN BinOBM OBM ON OBM.BIN_ID = FB.BIN_ID
                GROUP BY
                    FB.BIN_ID, FB.BIN_SEGMENTS, FB.Cost,
                    BP.ProximityScore, HS.HasSameSku,
                    OBM.STATION_ID, OBM.STATUS, OBM.TYPE
                HAVING EmptySegmentsAvail > 0
            ),
            BinScored AS (
                SELECT
                    BA.*,
                    LEAST(BA.QtyCapPerSeg, BA.WeightCapPerSegEmpty) AS SegmentCapEmpty,

                    
                    LEAST(
                        BA.EmptySegmentsAvail,
                        BA.BIN_SEGMENTS,
                        GREATEST(
                            1,
                            CEIL( LEAST(V_PendingQty, (LEAST(BA.QtyCapPerSeg, BA.WeightCapPerSegEmpty) * BA.EmptySegmentsAvail)) / GREATEST(LEAST(BA.QtyCapPerSeg, BA.WeightCapPerSegEmpty), 1) )
                        )
                    ) AS SegsWanted
                FROM BinAgg BA
                WHERE LEAST(BA.QtyCapPerSeg, BA.WeightCapPerSegEmpty) >= V_MinSegmentSize
            ),
            BinRanked AS (
                SELECT
                    BS.*,
                    (BS.SegmentCapEmpty * BS.SegsWanted) AS BinTotalCap,
                    CASE WHEN (BS.SegmentCapEmpty * BS.SegsWanted) >= V_PendingQty THEN 1 ELSE 0 END AS CanFinishAll,
                    ROW_NUMBER() OVER (
                        ORDER BY
                            BS.StationPriority,
                            CASE WHEN (BS.SegmentCapEmpty * BS.SegsWanted) >= V_PendingQty THEN 1 ELSE 0 END DESC,
                            (BS.SegmentCapEmpty * BS.SegsWanted) DESC,
                            BS.SegsWanted ASC,
                            
                            CASE
                                WHEN (BS.SegsWanted / BS.BIN_SEGMENTS) * 100.0 > (V_BinCapacityThresholdPct + V_EPS)
                                THEN CASE BS.BIN_SEGMENTS WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 4 THEN 3 WHEN 6 THEN 4 ELSE 9 END
                                ELSE 9
                            END,
                            BS.Cost,
                            BS.ProximityScore DESC,
                            BS.HasSameSku DESC,
                            BS.BIN_ID
                    ) AS BinRank
                FROM BinScored BS
            ),
            SegCandidates AS (
                SELECT
                    ES.BIN_ID,
                    ES.SEGMENT_NO,
                    BR.BIN_SEGMENTS,
                    BR.Cost,
                    BR.BinRank,
                    BR.SegsWanted,
                    BR.SegmentCapEmpty AS SegmentCapacity,
                    BSR.RANKING
                FROM EmptySegs ES
                INNER JOIN BinRanked BR ON BR.BIN_ID = ES.BIN_ID
                INNER JOIN bin_segment_ranking BSR
                  ON BSR.BIN_SEGMENT_COUNT = BR.BIN_SEGMENTS
                 AND BSR.SEGMENT_ID        = ES.SEGMENT_NO
            ),
            SegPicked AS (
                SELECT
                    S.*,
                    ROW_NUMBER() OVER (PARTITION BY S.BIN_ID ORDER BY S.RANKING, S.SEGMENT_NO) AS rn_in_bin
                FROM SegCandidates S
            ),
            OrderedSegments AS (
                SELECT
                    P.*,
                    ROW_NUMBER() OVER (ORDER BY P.BinRank, P.RANKING, P.SEGMENT_NO) AS seg_index
                FROM SegPicked P
                WHERE P.rn_in_bin <= P.SegsWanted
                  AND P.SegmentCapacity >= V_MinSegmentSize
                LIMIT V_TotalCandidates
            ),
            alloc AS (
                SELECT
                    ob.BIN_ID,
                    ob.SEGMENT_NO,
                    ob.SegmentCapacity,
                    sr.STORAGE_ID,
                    sr.WAVE_ID,
                    CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS AllocatedQty,
                    sr.RequestQty - CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS RemQty,
                    ob.seg_index,
                    sr.req_index
                FROM OrderedSegments ob
                JOIN Tmp_RemReq_A sr
                  ON sr.req_index = 1
                 AND ob.seg_index = 1
                WHERE sr.RequestQty > 0

                UNION ALL

                SELECT
                    b.BIN_ID,
                    b.SEGMENT_NO,
                    b.SegmentCapacity,
                    CASE WHEN a.RemQty = 0 THEN s2.STORAGE_ID ELSE a.STORAGE_ID END,
                    CASE WHEN a.RemQty = 0 THEN s2.WAVE_ID    ELSE a.WAVE_ID    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                        ELSE
                            CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            s2.RequestQty - CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                        ELSE
                            a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    b.seg_index,
                    CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
                FROM OrderedSegments b
                JOIN alloc a
                  ON b.seg_index = a.seg_index + 1
                LEFT JOIN Tmp_RemReq_B s2
                  ON s2.req_index = a.req_index + 1
                WHERE (a.RemQty > 0) OR (s2.req_index IS NOT NULL AND s2.RequestQty > 0)
            )
            SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'PHASE',       'REMAINDER',
                           'WAVE_ID',      WAVE_ID,
                           'STORAGE_ID',   STORAGE_ID,
                           'BIN_ID',       BIN_ID,
                           'SEGMENT_NO',   SEGMENT_NO,
                           'SKU_ID',       P_SkuId,
                           'BATCH_ID',     P_BatchId,
                           'AllocatedQty', AllocatedQty
                       )
                   )
            INTO V_RemJson
            FROM alloc
            WHERE AllocatedQty > 0;

        END IF; 

        

        IF P_ForProcessing = 1 THEN
            
            SET @empty_json = JSON_MERGE_PRESERVE(COALESCE(V_TargetJson, JSON_ARRAY()), COALESCE(V_RemJson, JSON_ARRAY()));

            IF @empty_json IS NOT NULL THEN
                
                INSERT INTO order_bin_mapping (BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP)
                SELECT DISTINCT jt.BIN_ID, P_StationId, 'RACK_PICK', 'PENDING', 0, NOW()
                FROM JSON_TABLE(@empty_json, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
                LEFT JOIN order_bin_mapping obm_ok
                    ON  obm_ok.BIN_ID     = jt.BIN_ID
                    AND obm_ok.STATION_ID = P_StationId
                    AND obm_ok.TYPE       = 'RACK_PICK'
                    AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION','ON_STATION')
                WHERE obm_ok.ORDER_BIN_ID IS NULL;

                
                INSERT INTO put_wave_order_master (
                    PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                    ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
                )
                SELECT
                    UUID(),
                    P_StationId,
                    jt.WAVE_ID,
                    P_StorageRequestId,
                    jt.STORAGE_ID,
                    COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING',
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty
                FROM JSON_TABLE(
                    @empty_json,
                    '$[*]' COLUMNS (
                        WAVE_ID      VARCHAR(64) PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) PATH '$.STORAGE_ID',
                        BIN_ID       INT         PATH '$.BIN_ID',
                        SEGMENT_NO   INT         PATH '$.SEGMENT_NO',
                        SKU_ID       VARCHAR(64) PATH '$.SKU_ID',
                        BATCH_ID     VARCHAR(64) PATH '$.BATCH_ID',
                        AllocatedQty BIGINT      PATH '$.AllocatedQty'
                    )
                ) jt
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK'
                      AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION','ON_STATION')
                    GROUP BY BIN_ID, STATION_ID
                ) obm_reuse
                  ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                    GROUP BY BIN_ID, STATION_ID
                ) obm_new
                  ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
                WHERE jt.AllocatedQty > 0
                  AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master p
                      WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                        AND p.STORAGE_ID         = jt.STORAGE_ID
                        AND p.BIN_ID             = jt.BIN_ID
                        AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                        AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  );

                
                UPDATE live_inventory_master L
                INNER JOIN put_wave_order_master PWO
                    ON PWO.BIN_ID         = L.BIN_ID
                   AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
                SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY,
                    L.ARTICLE_ID              = PWO.SKU_ID,
                    L.BATCH_ID                = PWO.BATCH_ID
                WHERE (L.ARTICLE_ID = 'no-sku' OR (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT)=0)
                  AND PWO.STORAGE_ID = P_StorageId
                  AND PWO.STATUS     = 'PENDING';
            END IF;

        ELSE
            
            SET V_FinalPreviewJson = JSON_MERGE_PRESERVE(
                COALESCE(V_TopUpJson, JSON_ARRAY()),
                COALESCE(V_TargetJson, JSON_ARRAY()),
                COALESCE(V_RemJson, JSON_ARRAY())
            );

            IF V_FinalPreviewJson IS NOT NULL THEN
                SELECT
                    jt.PHASE,
                    UUID()             AS PUT_ORDER_ID,
                    P_StationId        AS STATION_ID,
                    jt.WAVE_ID         AS WAVE_ID,
                    P_StorageRequestId AS STORAGE_REQUEST_ID,
                    jt.STORAGE_ID      AS STORAGE_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING'          AS STATUS,
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty    AS EXPECTED_QUANTITY
                FROM JSON_TABLE(
                    V_FinalPreviewJson,
                    '$[*]' COLUMNS (
                        PHASE        VARCHAR(20) PATH '$.PHASE',
                        WAVE_ID      VARCHAR(64) PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) PATH '$.STORAGE_ID',
                        BIN_ID       INT         PATH '$.BIN_ID',
                        SEGMENT_NO   INT         PATH '$.SEGMENT_NO',
                        SKU_ID       VARCHAR(64) PATH '$.SKU_ID',
                        BATCH_ID     VARCHAR(64) PATH '$.BATCH_ID',
                        AllocatedQty BIGINT      PATH '$.AllocatedQty'
                    )
                ) jt
                WHERE jt.AllocatedQty > 0
                ORDER BY
                    FIELD(jt.PHASE,'TOPUP','TARGET','REMAINDER'),
                    jt.WAVE_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO;
            END IF;
        END IF;

    END IF; 

    
    IF P_ForProcessing = 1 THEN

        
        SELECT COALESCE(SUM(QUANTITY),0)
        INTO   v_wms_data_total_qty
        FROM   put_wave_wms_data
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        
        SELECT COALESCE(
                   SUM(
                       CASE
                           WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                           ELSE EXPECTED_QUANTITY
                       END
                   ),
                   0
               )
        INTO   v_order_master_total_expected
        FROM   put_wave_order_master
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        IF v_order_master_total_expected > v_wms_data_total_qty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'OVER_ALLOCATION: expected exceeds WMS qty';
        END IF;

        
        UPDATE put_wave_wms_data PW
        JOIN (
            SELECT
                w.WAVE_ID,
                w.STORAGE_ID,
                SUM(w.QUANTITY) AS wms_qty,
                COALESCE(SUM(p.expected_done),0) AS exp_qty,
                (SUM(w.QUANTITY) - COALESCE(SUM(p.expected_done),0)) AS leftover
            FROM put_wave_wms_data w
            LEFT JOIN (
                SELECT
                    WAVE_ID,
                    STORAGE_ID,
                    SUM(
                        CASE
                            WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                            ELSE EXPECTED_QUANTITY
                        END
                    ) AS expected_done
                FROM put_wave_order_master
                WHERE SKU_ID             = P_SkuId
                  AND BATCH_ID           = P_BatchId
                  AND STORAGE_REQUEST_ID = P_StorageRequestId
                  AND STORAGE_ID         = P_StorageId
                GROUP BY WAVE_ID, STORAGE_ID
            ) p
              ON p.WAVE_ID = w.WAVE_ID AND p.STORAGE_ID = w.STORAGE_ID
            WHERE w.SKU_ID             = P_SkuId
              AND w.BATCH_ID           = P_BatchId
              AND w.STORAGE_REQUEST_ID = P_StorageRequestId
              AND w.STORAGE_ID         = P_StorageId
            GROUP BY w.WAVE_ID, w.STORAGE_ID
        ) X
          ON X.WAVE_ID = PW.WAVE_ID AND X.STORAGE_ID = PW.STORAGE_ID
        SET PW.STATUS    = 'COMPLETED',
            PW.LEFT_OVER = X.leftover
        WHERE PW.SKU_ID             = P_SkuId
          AND PW.BATCH_ID           = P_BatchId
          AND PW.STATUS             = 'PENDING'
          AND PW.STORAGE_REQUEST_ID = P_StorageRequestId
          AND PW.STORAGE_ID         = P_StorageId;

        COMMIT;
        DO RELEASE_LOCK(v_lock_name);
    END IF;

    SET SESSION cte_max_recursion_depth = 1000;

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPending_Order_allocation_V3_02022026` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPending_Order_allocation_V3_02022026` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPending_Order_allocation_V3_02022026`(
    IN P_StorageRequestId VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StorageId        VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_SkuId            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_BatchId          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StationId        INT,
    IN P_ForProcessing    INT          
)
proc_main:BEGIN
    

    
    DECLARE V_StorageJson                 JSON;
    DECLARE V_PendingQty                  INT DEFAULT 0;
    DECLARE V_MaxBinWeight                BIGINT DEFAULT 0;

    
    DECLARE V_MaxQtyPerBin                INT DEFAULT 0;     
    DECLARE V_SkuUnitWeight               INT DEFAULT 0;
    DECLARE V_MinSegmentSize              INT DEFAULT 1;
    DECLARE V_SkuCategory                 INT DEFAULT 0;
    DECLARE V_SkuROS                      DECIMAL(10,2) DEFAULT 0.00;

    
    DECLARE V_ROS_ThresholdPct            DECIMAL(10,2) DEFAULT 60.00;
    DECLARE V_BinCapacityThresholdPct     DECIMAL(10,2) DEFAULT 50.00;

    
    DECLARE V_TopUpMinRemainingSpacePct   DECIMAL(10,2) DEFAULT 70.00;

    
    DECLARE V_TargetQty                   INT DEFAULT 0;

    DECLARE V_CapPerSeg6                  INT DEFAULT 0;
    DECLARE V_CapPerSeg4                  INT DEFAULT 0;
    DECLARE V_CapPerSeg2                  INT DEFAULT 0;
    DECLARE V_CapPerSeg1                  INT DEFAULT 0;

    DECLARE V_need6                       INT DEFAULT 1;
    DECLARE V_need4                       INT DEFAULT 1;
    DECLARE V_need2                       INT DEFAULT 1;

    DECLARE V_PrefBinSegments             INT DEFAULT 6;  

    DECLARE V_TotalCandidates             INT DEFAULT 800;
    DECLARE V_PrefSegCap                  INT DEFAULT 1;

    DECLARE v_wms_data_total_qty          INT DEFAULT 0;
    DECLARE v_order_master_total_expected INT DEFAULT 0;
    DECLARE V_left_over_calc              INT DEFAULT 0;

    DECLARE V_EPS                         DECIMAL(10,6) DEFAULT 0.000100;
    DECLARE V_AllocSum                    BIGINT DEFAULT 0;

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF P_ForProcessing = 1 THEN
            ROLLBACK;
        END IF;
        SET SESSION cte_max_recursion_depth = 1000;
        RESIGNAL;
    END;

    
    SELECT CAST(KEY_VALUE AS SIGNED)
      INTO V_MaxBinWeight
      FROM master_config
     WHERE KEY_NAME = 'MAX_WEIGHT_ALLOWED_ON_BOT_GRAMS'
     LIMIT 1;

    SET V_MaxBinWeight = COALESCE(V_MaxBinWeight, 2147483647);

    SELECT
        COALESCE(MAX(CASE WHEN KEY_NAME='ROS_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_ROS_ThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='BIN_CAPACITY_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_BinCapacityThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='TOPUP_MIN_REMAINING_SPACE_PCT' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_TopUpMinRemainingSpacePct)
    INTO
        V_ROS_ThresholdPct,
        V_BinCapacityThresholdPct,
        V_TopUpMinRemainingSpacePct
    FROM master_config
    WHERE KEY_NAME IN ('ROS_THRESHOLD','BIN_CAPACITY_THRESHOLD','TOPUP_MIN_REMAINING_SPACE_PCT');

    SET SESSION cte_max_recursion_depth = 10000;
    SET SESSION group_concat_max_len = 65535;

    
    SELECT
        MAX_QUANTITY_PER_SEGMENT,
        WEIGHT_OF_EACH_SKU,
        MIN_SEGMENT_SIZE,
        category,
        COALESCE(ROS,0)
    INTO
        V_MaxQtyPerBin,
        V_SkuUnitWeight,
        V_MinSegmentSize,
        V_SkuCategory,
        V_SkuROS
    FROM sku_master
    WHERE SKU_ID = P_SkuId
    LIMIT 1;

    IF V_MaxQtyPerBin IS NULL OR V_MaxQtyPerBin <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'MAX_QTY_PER_BIN missing/invalid (sku_master.MAX_QUANTITY_PER_SEGMENT)';
    END IF;

    SET V_SkuUnitWeight  = COALESCE(V_SkuUnitWeight,0);
    SET V_MinSegmentSize = GREATEST(1, COALESCE(V_MinSegmentSize,1));

    
    SET V_CapPerSeg6 = FLOOR(V_MaxQtyPerBin / 6);
    SET V_CapPerSeg4 = FLOOR(V_MaxQtyPerBin / 4);
    SET V_CapPerSeg2 = FLOOR(V_MaxQtyPerBin / 2);
    SET V_CapPerSeg1 = FLOOR(V_MaxQtyPerBin / 1);

    
    SET V_TargetQty = CEIL( COALESCE(V_SkuROS,0) * (COALESCE(V_ROS_ThresholdPct,60.0)/100.0) );

    
    IF V_TargetQty <= 0 THEN
        SET V_need6 = 1;
        SET V_need4 = 1;
        SET V_need2 = 1;
        SET V_PrefBinSegments = 6;
    ELSE
        SET V_need6 = CASE
                        WHEN V_CapPerSeg6 > 0 THEN LEAST(6, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg6)))
                        ELSE 6
                      END;

        SET V_need4 = CASE
                        WHEN V_CapPerSeg4 > 0 THEN LEAST(4, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg4)))
                        ELSE 4
                      END;

        SET V_need2 = CASE
                        WHEN V_CapPerSeg2 > 0 THEN LEAST(2, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg2)))
                        ELSE 2
                      END;

        
        SET V_PrefBinSegments = 6;

        IF ((V_need6 / 6.0) * 100.0) >= (V_BinCapacityThresholdPct - V_EPS) THEN
            SET V_PrefBinSegments = 4;
        END IF;

        IF V_PrefBinSegments = 4
           AND ((V_need4 / 4.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 2;
        END IF;

        IF V_PrefBinSegments = 2
           AND ((V_need2 / 2.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 1;
        END IF;
    END IF;

    SET V_PrefSegCap = CASE V_PrefBinSegments
                         WHEN 6 THEN GREATEST(V_CapPerSeg6, 1)
                         WHEN 4 THEN GREATEST(V_CapPerSeg4, 1)
                         WHEN 2 THEN GREATEST(V_CapPerSeg2, 1)
                         ELSE GREATEST(V_CapPerSeg1, 1)
                       END;

    IF P_ForProcessing = 1 THEN
        START TRANSACTION;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold;

    CREATE TEMPORARY TABLE Tmp_StorageRequestold (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    IF EXISTS (
        SELECT 1
        FROM live_inventory_master
        WHERE ARTICLE_ID = P_SkuId
          AND BATCH_ID   = P_BatchId
    ) THEN

        INSERT INTO Tmp_StorageRequestold (
            WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
        )
        SELECT
            PW.WAVE_ID,
            P_StorageRequestId,
            PW.STORAGE_ID,
            P_SkuId,
            P_BatchId,
            SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
            ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
        FROM (
            SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
            FROM put_wave_wms_data
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PW
        LEFT JOIN (
            SELECT
                WAVE_ID,
                STORAGE_ID,
                SUM(
                    CASE
                        WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                        ELSE EXPECTED_QUANTITY
                    END
                ) AS EXPECTED_QUANTITY
            FROM put_wave_order_master
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PWO
          ON PWO.STORAGE_ID = PW.STORAGE_ID
         AND PWO.WAVE_ID    = PW.WAVE_ID
        WHERE PW.QUANTITY > 0
        GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

        SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
        FROM Tmp_StorageRequestold;

        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_A;
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_B;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_A LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_A SELECT * FROM Tmp_StorageRequestold;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_B LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_B SELECT * FROM Tmp_StorageRequestold;

        IF V_PendingQty > 0 THEN

            WITH RECURSIVE
            AisleCost AS (
                SELECT Aisle_Number, MIN(Cost) AS Cost
                FROM station_to_aisle_cost
                WHERE Station_ID = P_StationId
                GROUP BY Aisle_Number
            ),
            BinWeight AS (
                SELECT
                    L0.BIN_ID,
                    SUM(
                        (L0.QUANTITY + L0.VIRTUAL_QUANTITY_TO_PUT) * COALESCE(SM0.WEIGHT_OF_EACH_SKU,0)
                    ) AS CurrentWeightInBin
                FROM live_inventory_master L0
                LEFT JOIN sku_master SM0 ON SM0.SKU_ID = L0.ARTICLE_ID
                WHERE IFNULL(L0.remark,'na') NOT IN ('no_space','audit_marked')
                GROUP BY L0.BIN_ID
            ),
            Phase1Candidates AS (
                SELECT
                    L.BIN_ID,
                    L.SEGMENT_NO,
                    BIM.BIN_SEGMENTS,
                    COALESCE(AC.Cost, 9999) AS Cost,
                    (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT) AS QtyInSeg,
                    COALESCE(BW.CurrentWeightInBin,0) AS CurrentWeightInBin,
                    CASE
                        WHEN BIM.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                        WHEN BIM.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                        WHEN BIM.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                        WHEN BIM.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                        ELSE 0
                    END AS QtyCapPerSeg
                FROM live_inventory_master L
                INNER JOIN bin_info_master BIM ON BIM.BIN_ID = L.BIN_ID
                INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
                INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
                LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN BinWeight BW ON BW.BIN_ID = L.BIN_ID
                WHERE L.ARTICLE_ID = P_SkuId
                  AND L.BATCH_ID   = P_BatchId
                  AND IFNULL(L.remark,'na') NOT IN ('no_space','audit_marked')
                  AND LBM.LOCATION_ID IS NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master P
                      WHERE P.BIN_ID         = L.BIN_ID
                        AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                        AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  )
            ),
            Phase1BestPerBin AS (
                SELECT
                    C.*,
                    GREATEST(C.QtyCapPerSeg - C.QtyInSeg, 0) AS BalanceSegQty,
                    CASE
                        WHEN V_SkuUnitWeight <= 0 THEN 999999
                        ELSE FLOOR( GREATEST(V_MaxBinWeight - C.CurrentWeightInBin,0) / V_SkuUnitWeight )
                    END AS BalanceWeightQty,
                    CASE
                        WHEN C.QtyCapPerSeg <= 0 THEN 0
                        ELSE (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) / C.QtyCapPerSeg) * 100.0
                    END AS BalanceSegFreePct,
                    ROW_NUMBER() OVER (
                        PARTITION BY C.BIN_ID
                        ORDER BY (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0)) DESC, C.SEGMENT_NO
                    ) AS rn_in_bin
                FROM Phase1Candidates C
                WHERE C.QtyCapPerSeg > 0
                  AND C.CurrentWeightInBin < V_MaxBinWeight
                  AND (
                        CASE
                            WHEN C.QtyCapPerSeg <= 0 THEN 0
                            ELSE (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) / C.QtyCapPerSeg) * 100.0
                        END
                      ) >= (V_TopUpMinRemainingSpacePct - V_EPS)
            ),
            Phase1BinsOrdered AS (
                SELECT
                    B.BIN_ID,
                    B.SEGMENT_NO,
                    LEAST(B.BalanceSegQty, B.BalanceWeightQty) AS SegmentCapacity,
                    ROW_NUMBER() OVER (
                        ORDER BY
                            CASE WHEN B.BIN_SEGMENTS=6 THEN 1 WHEN B.BIN_SEGMENTS=4 THEN 2 WHEN B.BIN_SEGMENTS=2 THEN 3 WHEN B.BIN_SEGMENTS=1 THEN 4 ELSE 9 END,
                            B.Cost,
                            B.BIN_ID,
                            B.SEGMENT_NO
                    ) AS bin_index
                FROM Phase1BestPerBin B
                WHERE B.rn_in_bin = 1
                  AND LEAST(B.BalanceSegQty, B.BalanceWeightQty) >= V_MinSegmentSize
            ),
            alloc1 AS (
                SELECT
                    ob.BIN_ID,
                    ob.SEGMENT_NO,
                    ob.SegmentCapacity,
                    r.STORAGE_ID,
                    P_SkuId   AS SKU_ID,
                    P_BatchId AS BATCH_ID,
                    r.WAVE_ID,
                    CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS AllocatedQty,
                    r.RequestQty - CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS RemQty,
                    ob.bin_index,
                    r.req_index
                FROM Phase1BinsOrdered ob
                JOIN Tmp_StorageRequestold_A r
                  ON r.req_index = 1
                 AND ob.bin_index = 1
                WHERE r.RequestQty > 0

                UNION ALL

                SELECT
                    b.BIN_ID,
                    b.SEGMENT_NO,
                    b.SegmentCapacity,
                    CASE WHEN a.RemQty = 0 THEN r2.STORAGE_ID ELSE a.STORAGE_ID END,
                    P_SkuId,
                    P_BatchId,
                    CASE WHEN a.RemQty = 0 THEN r2.WAVE_ID ELSE a.WAVE_ID END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            r2.RequestQty - CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    b.bin_index,
                    CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
                FROM Phase1BinsOrdered b
                JOIN alloc1 a
                  ON b.bin_index = a.bin_index + 1
                LEFT JOIN Tmp_StorageRequestold_B r2
                  ON r2.req_index = a.req_index + 1
                WHERE (a.RemQty > 0) OR (r2.req_index IS NOT NULL AND r2.RequestQty > 0)
            )
            SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'WAVE_ID',      WAVE_ID,
                           'STORAGE_ID',   STORAGE_ID,
                           'BIN_ID',       BIN_ID,
                           'SEGMENT_NO',   SEGMENT_NO,
                           'SKU_ID',       P_SkuId,
                           'BATCH_ID',     P_BatchId,
                           'AllocatedQty', AllocatedQty
                       )
                   )
            INTO V_StorageJson
            FROM alloc1
            WHERE AllocatedQty > 0;

            SET V_AllocSum = 0;
            IF V_StorageJson IS NOT NULL THEN
                SELECT COALESCE(SUM(jt.AllocatedQty),0)
                  INTO V_AllocSum
                FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS (AllocatedQty INT PATH '$.AllocatedQty')) jt;
            END IF;

            IF V_AllocSum > V_PendingQty THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'PHASE1_OVER_ALLOCATION: JSON allocation exceeds pending qty';
            END IF;

            IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

                INSERT INTO order_bin_mapping (BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP)
                SELECT DISTINCT jt.BIN_ID, P_StationId, 'RACK_PICK', 'PENDING', 0, NOW()
                FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
                LEFT JOIN order_bin_mapping obm_ok
                    ON  obm_ok.BIN_ID     = jt.BIN_ID
                    AND obm_ok.STATION_ID = P_StationId
                    AND obm_ok.TYPE       = 'RACK_PICK'
                    AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                WHERE obm_ok.ORDER_BIN_ID IS NULL;

                INSERT INTO put_wave_order_master (
                    PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                    ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
                )
                SELECT
                    UUID(),
                    P_StationId,
                    jt.WAVE_ID,
                    P_StorageRequestId,
                    jt.STORAGE_ID,
                    COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING',
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty
                FROM JSON_TABLE(
                        V_StorageJson,
                        '$[*]' COLUMNS (
                            WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                            STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                            BIN_ID       INT PATH '$.BIN_ID',
                            SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                            SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                            BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                            AllocatedQty INT PATH '$.AllocatedQty'
                        )
                     ) jt
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK'
                      AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                    GROUP BY BIN_ID, STATION_ID
                ) obm_reuse
                  ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                    GROUP BY BIN_ID, STATION_ID
                ) obm_new
                  ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
                WHERE jt.AllocatedQty > 0
                  AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master p
                      WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                        AND p.STORAGE_ID         = jt.STORAGE_ID
                        AND p.BIN_ID             = jt.BIN_ID
                        AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                        AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  );

                UPDATE live_inventory_master L
                INNER JOIN put_wave_order_master PWO
                    ON PWO.SKU_ID         = L.ARTICLE_ID
                   AND PWO.BATCH_ID       = L.BATCH_ID
                   AND PWO.BIN_ID         = L.BIN_ID
                   AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
                SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY
                WHERE L.ARTICLE_ID   = P_SkuId
                  AND L.BATCH_ID     = P_BatchId
                  AND PWO.STORAGE_ID = P_StorageId
                  AND PWO.STATUS     = 'PENDING';

            ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN
                SELECT
                    UUID() AS PUT_ORDER_ID,
                    P_StationId AS STATION_ID,
                    jt.WAVE_ID,
                    P_StorageRequestId AS STORAGE_REQUEST_ID,
                    jt.STORAGE_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING' AS STATUS,
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty AS EXPECTED_QUANTITY
                FROM JSON_TABLE(
                    V_StorageJson,
                    '$[*]' COLUMNS (
                        WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                        BIN_ID       INT PATH '$.BIN_ID',
                        SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                        SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                        BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                        AllocatedQty INT PATH '$.AllocatedQty'
                    )
                ) jt
                WHERE jt.AllocatedQty > 0;
            END IF;

        END IF;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    INSERT INTO Tmp_StorageRequest (WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index)
    SELECT
        PW.WAVE_ID,
        P_StorageRequestId,
        PW.STORAGE_ID,
        P_SkuId,
        P_BatchId,
        SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
        ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
    FROM (
        SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
        FROM put_wave_wms_data
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY STORAGE_ID, WAVE_ID
    ) PW
    LEFT JOIN (
        SELECT
            WAVE_ID,
            STORAGE_ID,
            SUM(
                CASE
                    WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                    ELSE EXPECTED_QUANTITY
                END
            ) AS EXPECTED_QUANTITY
        FROM put_wave_order_master
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY WAVE_ID, STORAGE_ID
    ) PWO
      ON PWO.STORAGE_ID = PW.STORAGE_ID
     AND PWO.WAVE_ID    = PW.WAVE_ID
    GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

    SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
    FROM Tmp_StorageRequest;

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_A;
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_B;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_A LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_A SELECT * FROM Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_B LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_B SELECT * FROM Tmp_StorageRequest;

    IF V_PendingQty > 0 THEN

        SET V_TotalCandidates = LEAST(
            20000,
            GREATEST(
                3000,
                CEIL(V_PendingQty / GREATEST(1, V_PrefSegCap)) * 12
            )
        );

        WITH RECURSIVE
        AisleCost AS (
            SELECT Aisle_Number, MIN(Cost) AS Cost
            FROM station_to_aisle_cost
            WHERE Station_ID = P_StationId
            GROUP BY Aisle_Number
        ),
        FreeBins AS (
            SELECT DISTINCT
                BIM.BIN_ID,
                BIM.BIN_SEGMENTS,
                COALESCE(AC.Cost, 9999) AS Cost,
                STBM.LOCATION_ID
            FROM bin_info_master BIM
            INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
            INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
            LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
            LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
            WHERE LBM.LOCATION_ID IS NULL
        ),
        ReservedSegs AS (
            SELECT DISTINCT
                P.BIN_ID,
                P.BIN_SEGMENT_NO AS SEGMENT_NO
            FROM put_wave_order_master P
            WHERE P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
        ),
        BaseSegs AS (
            SELECT
                L.BIN_ID,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                IFNULL(L.remark,'na') AS remark,
                FB.BIN_SEGMENTS,
                FB.Cost
            FROM live_inventory_master L
            INNER JOIN FreeBins FB ON FB.BIN_ID = L.BIN_ID
            WHERE IFNULL(L.remark,'na') = 'na'
        ),
        EmptySegs AS (
            SELECT
                B.*
            FROM BaseSegs B
            LEFT JOIN ReservedSegs R
              ON R.BIN_ID = B.BIN_ID
             AND R.SEGMENT_NO = B.SEGMENT_NO
            WHERE R.BIN_ID IS NULL
              AND (
                    B.ARTICLE_ID = 'no-sku'
                 OR (B.QUANTITY + B.VIRTUAL_QUANTITY_TO_PUT) = 0
              )
        ),
        BinWeight AS (
            SELECT
                L0.BIN_ID,
                SUM(
                    (L0.QUANTITY + L0.VIRTUAL_QUANTITY_TO_PUT) * COALESCE(SM0.WEIGHT_OF_EACH_SKU,0)
                ) AS CurrentWeightInBin
            FROM live_inventory_master L0
            LEFT JOIN sku_master SM0 ON SM0.SKU_ID = L0.ARTICLE_ID
            WHERE IFNULL(L0.remark,'na') NOT IN ('no_space','audit_marked')
            GROUP BY L0.BIN_ID
        ),
        BinProximity AS (
            
            SELECT
                B.BIN_ID,
                COALESCE(MAX(AP.PROXIMITY_SCORE),0) AS ProximityScore
            FROM BaseSegs B
            LEFT JOIN article_proximity_score AP
              ON AP.PARENT_ARTICLE_ID = P_SkuId
             AND AP.CHILD_ARTICLE_ID  = B.ARTICLE_ID
            WHERE (B.QUANTITY + B.VIRTUAL_QUANTITY_TO_PUT) > 0
              AND B.ARTICLE_ID <> 'no-sku'
            GROUP BY B.BIN_ID
        ),
        HasSameSkuBin AS (
            SELECT BIN_ID, 1 AS HasSameSku
            FROM BaseSegs
            WHERE ARTICLE_ID = P_SkuId
              AND BATCH_ID   = P_BatchId
              AND (QUANTITY + VIRTUAL_QUANTITY_TO_PUT) > 0
            GROUP BY BIN_ID
        ),
        BinOBM AS (
            
            SELECT
                BIN_ID,
                MAX(BOT_ID) AS BOT_ID,
                MAX(STATUS) AS STATUS,
                MAX(TYPE)   AS TYPE,
                MAX(STATION_ID) AS STATION_ID
            FROM order_bin_mapping
            WHERE TYPE = 'RACK_PICK'
            GROUP BY BIN_ID
        ),
        BinAgg AS (
            SELECT
                FB.BIN_ID,
                FB.BIN_SEGMENTS,
                FB.Cost,
                COALESCE(BW.CurrentWeightInBin,0) AS CurrentWeightInBin,
                COALESCE(BP.ProximityScore,0) AS ProximityScore,
                COALESCE(HS.HasSameSku,0) AS HasSameSku,

                SUM(CASE WHEN (BS.QUANTITY + BS.VIRTUAL_QUANTITY_TO_PUT) > 0 AND BS.ARTICLE_ID <> 'no-sku' THEN 1 ELSE 0 END) AS OccupiedSegments,
                COUNT(ES.BIN_ID) AS EmptySegmentsAvail,

                
                CASE
                    WHEN OBM.TYPE = 'RACK_PICK'
                     AND OBM.STATION_ID = P_StationId
                     AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED') THEN 1
                    WHEN OBM.TYPE = 'RACK_PICK'
                     AND OBM.STATION_ID = P_StationId
                     AND OBM.STATUS IN ('BIN_PICKED','PRE_ON_STATION','ON_STATION') THEN 2
                    WHEN OBM.TYPE = 'RACK_PICK'
                     AND OBM.STATION_ID = P_StationId
                     AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 3
                    WHEN OBM.TYPE = 'RACK_PICK'
                     AND (OBM.STATION_ID IS NULL OR OBM.STATION_ID <> P_StationId)
                     AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 4
                    ELSE 5
                END AS StationPriority,

                CASE
                    WHEN FB.BIN_SEGMENTS=6 THEN GREATEST(V_CapPerSeg6,1)
                    WHEN FB.BIN_SEGMENTS=4 THEN GREATEST(V_CapPerSeg4,1)
                    WHEN FB.BIN_SEGMENTS=2 THEN GREATEST(V_CapPerSeg2,1)
                    ELSE GREATEST(V_CapPerSeg1,1)
                END AS QtyCapPerSeg,

                CASE
                    WHEN FB.BIN_SEGMENTS=6 THEN V_need6
                    WHEN FB.BIN_SEGMENTS=4 THEN V_need4
                    WHEN FB.BIN_SEGMENTS=2 THEN V_need2
                    ELSE 1
                END AS MinPlanSegs,

                CASE
                    WHEN V_PrefBinSegments=6 THEN
                        CASE WHEN FB.BIN_SEGMENTS=6 THEN 1 WHEN FB.BIN_SEGMENTS=4 THEN 2 WHEN FB.BIN_SEGMENTS=2 THEN 3 WHEN FB.BIN_SEGMENTS=1 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=4 THEN
                        CASE WHEN FB.BIN_SEGMENTS=4 THEN 1 WHEN FB.BIN_SEGMENTS=2 THEN 2 WHEN FB.BIN_SEGMENTS=1 THEN 3 WHEN FB.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=2 THEN
                        CASE WHEN FB.BIN_SEGMENTS=2 THEN 1 WHEN FB.BIN_SEGMENTS=1 THEN 2 WHEN FB.BIN_SEGMENTS=4 THEN 3 WHEN FB.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    ELSE
                        CASE WHEN FB.BIN_SEGMENTS=1 THEN 1 WHEN FB.BIN_SEGMENTS=2 THEN 2 WHEN FB.BIN_SEGMENTS=4 THEN 3 WHEN FB.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                END AS BinTypeRank,

                
                CASE
                    WHEN V_SkuUnitWeight <= 0 THEN 999999999
                    ELSE FLOOR( GREATEST(V_MaxBinWeight - COALESCE(BW.CurrentWeightInBin,0),0) / V_SkuUnitWeight )
                END AS WeightCapTotal
            FROM FreeBins FB
            LEFT JOIN BaseSegs BS ON BS.BIN_ID = FB.BIN_ID
            LEFT JOIN EmptySegs ES ON ES.BIN_ID = FB.BIN_ID
            LEFT JOIN BinWeight BW ON BW.BIN_ID = FB.BIN_ID
            LEFT JOIN BinProximity BP ON BP.BIN_ID = FB.BIN_ID
            LEFT JOIN HasSameSkuBin HS ON HS.BIN_ID = FB.BIN_ID
            LEFT JOIN BinOBM OBM ON OBM.BIN_ID = FB.BIN_ID
            GROUP BY
                FB.BIN_ID, FB.BIN_SEGMENTS, FB.Cost,
                BW.CurrentWeightInBin, BP.ProximityScore, HS.HasSameSku,
                OBM.STATION_ID, OBM.STATUS, OBM.TYPE
            HAVING EmptySegmentsAvail > 0
        ),
        BinScored AS (
            SELECT
                BA.*,

                
                (BA.QtyCapPerSeg * LEAST(BA.EmptySegmentsAvail, BA.BIN_SEGMENTS)) AS VolCapTotal,

                
                LEAST(
                    (BA.QtyCapPerSeg * LEAST(BA.EmptySegmentsAvail, BA.BIN_SEGMENTS)),
                    BA.WeightCapTotal
                ) AS BinTotalCap,

                CASE
                    WHEN LEAST(
                          (BA.QtyCapPerSeg * LEAST(BA.EmptySegmentsAvail, BA.BIN_SEGMENTS)),
                          BA.WeightCapTotal
                    ) >= V_PendingQty
                    THEN 1 ELSE 0
                END AS CanFinishAll,

                CASE
                    WHEN BA.EmptySegmentsAvail >= BA.MinPlanSegs THEN 1 ELSE 0
                END AS MeetsPlan,

                
                CASE
                    WHEN V_SkuUnitWeight <= 0 THEN
                        LEAST(
                            BA.EmptySegmentsAvail,
                            BA.BIN_SEGMENTS,
                            GREATEST(
                                BA.MinPlanSegs,
                                CEIL( LEAST(V_PendingQty, LEAST((BA.QtyCapPerSeg * LEAST(BA.EmptySegmentsAvail, BA.BIN_SEGMENTS)), BA.WeightCapTotal)) / BA.QtyCapPerSeg )
                            )
                        )
                    ELSE
                        LEAST(
                            BA.EmptySegmentsAvail,
                            BA.BIN_SEGMENTS,
                            BA.WeightCapTotal,
                            GREATEST(
                                BA.MinPlanSegs,
                                CEIL( LEAST(V_PendingQty, LEAST((BA.QtyCapPerSeg * LEAST(BA.EmptySegmentsAvail, BA.BIN_SEGMENTS)), BA.WeightCapTotal)) / BA.QtyCapPerSeg )
                            )
                        )
                END AS SegsWanted
            FROM BinAgg BA
            WHERE BA.QtyCapPerSeg > 0
              AND BA.WeightCapTotal > 0
        ),
        BinRanked AS (
            SELECT
                BS.*,
                ROW_NUMBER() OVER (
                    ORDER BY
                        BS.StationPriority,
                        BS.CanFinishAll DESC,
                        BS.BinTotalCap DESC,
                        BS.MeetsPlan DESC,
                        BS.BinTypeRank,
                        BS.OccupiedSegments DESC,
                        BS.Cost,
                        BS.ProximityScore DESC,
                        BS.HasSameSku DESC,
                        BS.BIN_ID
                ) AS BinRank
            FROM BinScored BS
            WHERE BS.SegsWanted >= 1
              AND BS.BinTotalCap >= V_MinSegmentSize
        ),
        SegCandidates AS (
            SELECT
                ES.BIN_ID,
                ES.SEGMENT_NO,
                BR.BIN_SEGMENTS,
                BR.Cost,
                BR.BinRank,
                BR.SegsWanted,
                BR.QtyCapPerSeg,
                BR.WeightCapTotal,

                
                CASE
                    WHEN V_SkuUnitWeight <= 0 THEN 999999999
                    ELSE FLOOR(BR.WeightCapTotal / BR.SegsWanted)
                END AS WeightCapPerSeg,

                BSR.RANKING
            FROM EmptySegs ES
            INNER JOIN BinRanked BR ON BR.BIN_ID = ES.BIN_ID
            INNER JOIN bin_segment_ranking BSR
              ON BSR.BIN_SEGMENT_COUNT = BR.BIN_SEGMENTS
             AND BSR.SEGMENT_ID        = ES.SEGMENT_NO
        ),
        SegPicked AS (
            SELECT
                S.*,
                ROW_NUMBER() OVER (PARTITION BY S.BIN_ID ORDER BY S.RANKING, S.SEGMENT_NO) AS rn_in_bin,
                LEAST(S.QtyCapPerSeg, S.WeightCapPerSeg) AS SegmentCapacity
            FROM SegCandidates S
        ),
        OrderedSegments AS (
            SELECT
                P.*,
                ROW_NUMBER() OVER (ORDER BY P.BinRank, P.RANKING, P.SEGMENT_NO) AS seg_index
            FROM SegPicked P
            WHERE P.rn_in_bin <= P.SegsWanted
              AND P.SegmentCapacity >= V_MinSegmentSize
            LIMIT V_TotalCandidates
        ),
        alloc AS (
            SELECT
                ob.BIN_ID,
                ob.SEGMENT_NO,
                ob.SegmentCapacity,
                sr.STORAGE_ID,
                sr.WAVE_ID,
                CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS AllocatedQty,
                sr.RequestQty - CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS RemQty,
                ob.seg_index,
                sr.req_index
            FROM OrderedSegments ob
            JOIN Tmp_StorageRequest_A sr
              ON sr.req_index = 1
             AND ob.seg_index = 1
            WHERE sr.RequestQty > 0

            UNION ALL

            SELECT
                b.BIN_ID,
                b.SEGMENT_NO,
                b.SegmentCapacity,
                CASE WHEN a.RemQty = 0 THEN s2.STORAGE_ID ELSE a.STORAGE_ID END,
                CASE WHEN a.RemQty = 0 THEN s2.WAVE_ID    ELSE a.WAVE_ID    END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        s2.RequestQty - CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                b.seg_index,
                CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
            FROM OrderedSegments b
            JOIN alloc a
              ON b.seg_index = a.seg_index + 1
            LEFT JOIN Tmp_StorageRequest_B s2
              ON s2.req_index = a.req_index + 1
            WHERE (a.RemQty > 0) OR (s2.req_index IS NOT NULL AND s2.RequestQty > 0)
        )
        SELECT JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'WAVE_ID',      WAVE_ID,
                       'STORAGE_ID',   STORAGE_ID,
                       'BIN_ID',       BIN_ID,
                       'SEGMENT_NO',   SEGMENT_NO,
                       'SKU_ID',       P_SkuId,
                       'BATCH_ID',     P_BatchId,
                       'AllocatedQty', AllocatedQty
                   )
               )
        INTO V_StorageJson
        FROM alloc
        WHERE AllocatedQty > 0;

        
        SET V_AllocSum = 0;
        IF V_StorageJson IS NOT NULL THEN
            SELECT COALESCE(SUM(jt.AllocatedQty),0)
              INTO V_AllocSum
            FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS (AllocatedQty INT PATH '$.AllocatedQty')) jt;
        END IF;

        IF V_AllocSum > V_PendingQty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PHASE2_OVER_ALLOCATION: JSON allocation exceeds pending qty';
        END IF;

        IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

            INSERT INTO order_bin_mapping (BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP)
            SELECT DISTINCT jt.BIN_ID, P_StationId, 'RACK_PICK', 'PENDING', 0, NOW()
            FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
            LEFT JOIN order_bin_mapping obm_ok
                ON  obm_ok.BIN_ID     = jt.BIN_ID
                AND obm_ok.STATION_ID = P_StationId
                AND obm_ok.TYPE       = 'RACK_PICK'
                AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
            WHERE obm_ok.ORDER_BIN_ID IS NULL;

            INSERT INTO put_wave_order_master (
                PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
            )
            SELECT
                UUID(),
                P_StationId,
                jt.WAVE_ID,
                P_StorageRequestId,
                jt.STORAGE_ID,
                COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING',
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK'
                  AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                GROUP BY BIN_ID, STATION_ID
            ) obm_reuse
              ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                GROUP BY BIN_ID, STATION_ID
            ) obm_new
              ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
            WHERE jt.AllocatedQty > 0
              AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master p
                  WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                    AND p.STORAGE_ID         = jt.STORAGE_ID
                    AND p.BIN_ID             = jt.BIN_ID
                    AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                    AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              );

            UPDATE live_inventory_master L
            INNER JOIN put_wave_order_master PWO
                ON PWO.BIN_ID         = L.BIN_ID
               AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
            SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY,
                L.ARTICLE_ID              = PWO.SKU_ID,
                L.BATCH_ID                = PWO.BATCH_ID
            WHERE (L.ARTICLE_ID = 'no-sku' OR (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT)=0)
              AND PWO.STORAGE_ID = P_StorageId
              AND PWO.STATUS     = 'PENDING';

        ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

            SELECT
                UUID()             AS PUT_ORDER_ID,
                P_StationId        AS STATION_ID,
                jt.WAVE_ID         AS WAVE_ID,
                P_StorageRequestId AS STORAGE_REQUEST_ID,
                jt.STORAGE_ID,
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING'          AS STATUS,
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty    AS EXPECTED_QUANTITY
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            WHERE jt.AllocatedQty > 0;

        END IF;

    END IF;

    
    IF P_ForProcessing = 1 THEN

        SELECT COALESCE(SUM(QUANTITY),0)
        INTO   v_wms_data_total_qty
        FROM   put_wave_wms_data
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        SELECT COALESCE(
                   SUM(
                       CASE
                           WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                           ELSE EXPECTED_QUANTITY
                       END
                   ),
                   0
               )
        INTO   v_order_master_total_expected
        FROM   put_wave_order_master
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        IF v_order_master_total_expected > v_wms_data_total_qty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'OVER_ALLOCATION: expected exceeds WMS qty';
        END IF;

        SET V_left_over_calc = v_wms_data_total_qty - v_order_master_total_expected;

        UPDATE put_wave_wms_data PW
        SET    PW.STATUS    = 'COMPLETED',
               PW.LEFT_OVER = V_left_over_calc
        WHERE  PW.SKU_ID             = P_SkuId
          AND  PW.BATCH_ID           = P_BatchId
          AND  PW.STATUS             = 'PENDING'
          AND  PW.STORAGE_REQUEST_ID = P_StorageRequestId
          AND  PW.STORAGE_ID         = P_StorageId;

        COMMIT;
    END IF;

    SET SESSION cte_max_recursion_depth = 1000;

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPending_Order_allocation_V3_07012026` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPending_Order_allocation_V3_07012026` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPending_Order_allocation_V3_07012026`(
    IN P_StorageRequestId VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StorageId        VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_SkuId            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_BatchId          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StationId        INT,
    IN P_ForProcessing    INT          
)
proc_main:BEGIN
    

    
    DECLARE V_StorageJson                 JSON;
    DECLARE V_StoredSKUBinsList           TEXT;

    DECLARE V_PendingQty                  INT DEFAULT 0;

    DECLARE V_MaxBinWeight                BIGINT DEFAULT 0;

    
    DECLARE V_MaxQtyPerBin                INT DEFAULT 0;     
    DECLARE V_SkuUnitWeight               INT DEFAULT 0;
    DECLARE V_MinSegmentSize              INT DEFAULT 1;
    DECLARE V_SkuCategory                 INT DEFAULT 0;
    DECLARE V_SkuROS                      DECIMAL(10,2) DEFAULT 0.00;

    
    DECLARE V_ROS_ThresholdPct            DECIMAL(10,2) DEFAULT 60.00;
    DECLARE V_BinCapacityThresholdPct     DECIMAL(10,2) DEFAULT 50.00;

    
    DECLARE V_TargetQty                   INT DEFAULT 0;

    DECLARE V_CapPerSeg6                  INT DEFAULT 0;
    DECLARE V_CapPerSeg4                  INT DEFAULT 0;
    DECLARE V_CapPerSeg2                  INT DEFAULT 0;
    DECLARE V_CapPerSeg1                  INT DEFAULT 0;

    DECLARE V_need6                       INT DEFAULT 1;
    DECLARE V_need4                       INT DEFAULT 1;
    DECLARE V_need2                       INT DEFAULT 1;

    DECLARE V_PrefBinSegments             INT DEFAULT 6;  

    DECLARE V_TotalCandidates             INT DEFAULT 800;

    
    DECLARE V_PrefSegCap                 INT DEFAULT 1;

    DECLARE v_wms_data_total_qty          INT DEFAULT 0;
    DECLARE v_order_master_total_expected INT DEFAULT 0;
    DECLARE V_left_over_calc              INT DEFAULT 0;

    
    DECLARE V_OneSegEarlyQuota            INT DEFAULT 999999;

    
    DECLARE V_EPS                         DECIMAL(10,6) DEFAULT 0.000100;

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF P_ForProcessing = 1 THEN
            ROLLBACK;
        END IF;
        SET SESSION cte_max_recursion_depth = 1000;
        RESIGNAL;
    END;

    
    SELECT CAST(KEY_VALUE AS SIGNED)
      INTO V_MaxBinWeight
      FROM master_config
     WHERE KEY_NAME = 'MAX_WEIGHT_ALLOWED_ON_BOT_GRAMS'
     LIMIT 1;

    SET V_MaxBinWeight = COALESCE(V_MaxBinWeight, 2147483647);

    SELECT
        COALESCE(MAX(CASE WHEN KEY_NAME='ROS_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_ROS_ThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='BIN_CAPACITY_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_BinCapacityThresholdPct)
    INTO
        V_ROS_ThresholdPct,
        V_BinCapacityThresholdPct
    FROM master_config
    WHERE KEY_NAME IN ('ROS_THRESHOLD','BIN_CAPACITY_THRESHOLD');

    SET SESSION cte_max_recursion_depth = 10000;
    SET SESSION group_concat_max_len = 65535;

    
    SELECT
        MAX_QUANTITY_PER_SEGMENT,
        WEIGHT_OF_EACH_SKU,
        MIN_SEGMENT_SIZE,
        category,
        COALESCE(ROS,0)
    INTO
        V_MaxQtyPerBin,
        V_SkuUnitWeight,
        V_MinSegmentSize,
        V_SkuCategory,
        V_SkuROS
    FROM sku_master
    WHERE SKU_ID = P_SkuId
    LIMIT 1;

    IF V_MaxQtyPerBin IS NULL OR V_MaxQtyPerBin <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'MAX_QTY_PER_BIN missing/invalid (sku_master.MAX_QUANTITY_PER_SEGMENT)';
    END IF;

    SET V_SkuUnitWeight  = COALESCE(V_SkuUnitWeight,0);
    SET V_MinSegmentSize = GREATEST(1, COALESCE(V_MinSegmentSize,1));

    
    SET V_CapPerSeg6 = FLOOR(V_MaxQtyPerBin / 6);
    SET V_CapPerSeg4 = FLOOR(V_MaxQtyPerBin / 4);
    SET V_CapPerSeg2 = FLOOR(V_MaxQtyPerBin / 2);
    SET V_CapPerSeg1 = FLOOR(V_MaxQtyPerBin / 1);

    
    SET V_TargetQty = CEIL( COALESCE(V_SkuROS,0) * (COALESCE(V_ROS_ThresholdPct,60.0)/100.0) );

    
    IF V_TargetQty <= 0 THEN
        SET V_need6 = 1;
        SET V_need4 = 1;
        SET V_need2 = 1;
        SET V_PrefBinSegments = 6;
    ELSE
        SET V_need6 = CASE
                        WHEN V_CapPerSeg6 > 0 THEN LEAST(6, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg6)))
                        ELSE 6
                      END;

        SET V_need4 = CASE
                        WHEN V_CapPerSeg4 > 0 THEN LEAST(4, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg4)))
                        ELSE 4
                      END;

        SET V_need2 = CASE
                        WHEN V_CapPerSeg2 > 0 THEN LEAST(2, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg2)))
                        ELSE 2
                      END;

        
        SET V_PrefBinSegments = 6;

        IF ((V_need6 / 6.0) * 100.0) >= (V_BinCapacityThresholdPct - V_EPS) THEN
            SET V_PrefBinSegments = 4;
        END IF;

        IF V_PrefBinSegments = 4
           AND ((V_need4 / 4.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 2;
        END IF;

        IF V_PrefBinSegments = 2
           AND ((V_need2 / 2.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 1;
        END IF;
    END IF;

    
    SET V_PrefSegCap = CASE V_PrefBinSegments
                         WHEN 6 THEN GREATEST(V_CapPerSeg6, 1)
                         WHEN 4 THEN GREATEST(V_CapPerSeg4, 1)
                         WHEN 2 THEN GREATEST(V_CapPerSeg2, 1)
                         ELSE GREATEST(V_CapPerSeg1, 1)
                       END;

    
    SELECT GROUP_CONCAT(BIN_ID)
      INTO V_StoredSKUBinsList
      FROM (
          SELECT DISTINCT BIN_ID
          FROM live_inventory_master
          WHERE ARTICLE_ID = P_SkuId
            AND BATCH_ID   = P_BatchId
      ) b;

    SET V_StoredSKUBinsList = CONCAT(',', IFNULL(V_StoredSKUBinsList,''), ',');

    IF P_ForProcessing = 1 THEN
        START TRANSACTION;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold;

    CREATE TEMPORARY TABLE Tmp_StorageRequestold (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    IF EXISTS (
        SELECT 1
        FROM live_inventory_master
        WHERE ARTICLE_ID = P_SkuId
          AND BATCH_ID   = P_BatchId
    ) THEN

        INSERT INTO Tmp_StorageRequestold (
            WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
        )
        SELECT
            PW.WAVE_ID,
            P_StorageRequestId,
            PW.STORAGE_ID,
            P_SkuId,
            P_BatchId,
            SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
            ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
        FROM (
            SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
            FROM put_wave_wms_data
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PW
        LEFT JOIN (
            SELECT
                WAVE_ID,
                STORAGE_ID,
                SUM(
                    CASE
                        WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                        ELSE EXPECTED_QUANTITY
                    END
                ) AS EXPECTED_QUANTITY
            FROM put_wave_order_master
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PWO
          ON PWO.STORAGE_ID = PW.STORAGE_ID
         AND PWO.WAVE_ID    = PW.WAVE_ID
        WHERE PW.QUANTITY > 0
        GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

        SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
        FROM Tmp_StorageRequestold;

        
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_A;
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_B;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_A LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_A SELECT * FROM Tmp_StorageRequestold;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_B LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_B SELECT * FROM Tmp_StorageRequestold;

        IF V_PendingQty > 0 THEN

            WITH RECURSIVE
            AisleCost AS (
                SELECT Aisle_Number, MIN(Cost) AS Cost
                FROM station_to_aisle_cost
                WHERE Station_ID = P_StationId
                GROUP BY Aisle_Number
            ),
            BinWeight AS (
                
                SELECT
                    L0.BIN_ID,
                    SUM(
                        (L0.QUANTITY + L0.VIRTUAL_QUANTITY_TO_PUT) * COALESCE(SM0.WEIGHT_OF_EACH_SKU,0)
                    ) AS CurrentWeightInBin
                FROM live_inventory_master L0
                LEFT JOIN sku_master SM0 ON SM0.SKU_ID = L0.ARTICLE_ID
                WHERE IFNULL(L0.remark,'na') NOT IN ('no_space','audit_marked')
                GROUP BY L0.BIN_ID
            ),
            Phase1Candidates AS (
                SELECT
                    L.BIN_ID,
                    L.SEGMENT_NO,
                    BIM.BIN_SEGMENTS,
                    COALESCE(AC.Cost, 9999) AS Cost,
                    (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT) AS QtyInSeg,
                    COALESCE(BW.CurrentWeightInBin,0) AS CurrentWeightInBin,
                    CASE
                        WHEN BIM.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                        WHEN BIM.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                        WHEN BIM.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                        WHEN BIM.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                        ELSE 0
                    END AS QtyCapPerSeg
                FROM live_inventory_master L
                INNER JOIN bin_info_master BIM ON BIM.BIN_ID = L.BIN_ID
                INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
                INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
                LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN BinWeight BW ON BW.BIN_ID = L.BIN_ID
                WHERE L.ARTICLE_ID = P_SkuId
                  AND L.BATCH_ID   = P_BatchId
                  AND IFNULL(L.remark,'na') NOT IN ('no_space','audit_marked')
                  AND LBM.LOCATION_ID IS NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master P
                      WHERE P.BIN_ID         = L.BIN_ID
                        AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                        AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  )
            ),
            Phase1BestPerBin AS (
                SELECT
                    C.*,
                    GREATEST(C.QtyCapPerSeg - C.QtyInSeg, 0) AS BalanceSegQty,
                    CASE
                        WHEN V_SkuUnitWeight <= 0 THEN 999999
                        ELSE FLOOR( GREATEST(V_MaxBinWeight - C.CurrentWeightInBin,0) / V_SkuUnitWeight )
                    END AS BalanceWeightQty,
                    ROW_NUMBER() OVER (
                        PARTITION BY C.BIN_ID
                        ORDER BY (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0)) DESC, C.SEGMENT_NO
                    ) AS rn_in_bin
                FROM Phase1Candidates C
                WHERE C.QtyCapPerSeg > 0
                  AND C.CurrentWeightInBin < V_MaxBinWeight
            ),
            Phase1BinsOrdered AS (
                SELECT
                    B.BIN_ID,
                    B.SEGMENT_NO,
                    LEAST(B.BalanceSegQty, B.BalanceWeightQty) AS SegmentCapacity,
                    ROW_NUMBER() OVER (
                        ORDER BY
                            CASE WHEN B.BIN_SEGMENTS=6 THEN 1 WHEN B.BIN_SEGMENTS=4 THEN 2 WHEN B.BIN_SEGMENTS=2 THEN 3 WHEN B.BIN_SEGMENTS=1 THEN 4 ELSE 9 END,
                            B.Cost,
                            B.BIN_ID,
                            B.SEGMENT_NO
                    ) AS bin_index
                FROM Phase1BestPerBin B
                WHERE B.rn_in_bin = 1
                  AND LEAST(B.BalanceSegQty, B.BalanceWeightQty) > 0
            ),
            alloc1 AS (
                SELECT
                    ob.BIN_ID,
                    ob.SEGMENT_NO,
                    ob.SegmentCapacity,
                    r.STORAGE_ID,
                    P_SkuId   AS SKU_ID,
                    P_BatchId AS BATCH_ID,
                    r.WAVE_ID,
                    CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS AllocatedQty,
                    r.RequestQty - CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS RemQty,
                    ob.bin_index,
                    r.req_index
                FROM Phase1BinsOrdered ob
                JOIN Tmp_StorageRequestold_A r
                  ON r.req_index = 1
                 AND ob.bin_index = 1
                WHERE r.RequestQty > 0

                UNION ALL

                SELECT
                    b.BIN_ID,
                    b.SEGMENT_NO,
                    b.SegmentCapacity,
                    CASE WHEN a.RemQty = 0 THEN r2.STORAGE_ID ELSE a.STORAGE_ID END,
                    P_SkuId,
                    P_BatchId,
                    CASE WHEN a.RemQty = 0 THEN r2.WAVE_ID ELSE a.WAVE_ID END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            r2.RequestQty - CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    b.bin_index,
                    CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
                FROM Phase1BinsOrdered b
                JOIN alloc1 a
                  ON b.bin_index = a.bin_index + 1
                LEFT JOIN Tmp_StorageRequestold_B r2
                  ON r2.req_index = a.req_index + 1
                WHERE (a.RemQty > 0) OR (r2.req_index IS NOT NULL AND r2.RequestQty > 0)
            )
            SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'WAVE_ID',      WAVE_ID,
                           'STORAGE_ID',   STORAGE_ID,
                           'BIN_ID',       BIN_ID,
                           'SEGMENT_NO',   SEGMENT_NO,
                           'SKU_ID',       P_SkuId,
                           'BATCH_ID',     P_BatchId,
                           'AllocatedQty', AllocatedQty
                       )
                   )
            INTO V_StorageJson
            FROM alloc1
            WHERE AllocatedQty > 0;

            IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

                INSERT INTO order_bin_mapping (
                    BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
                )
                SELECT DISTINCT
                    jt.BIN_ID,
                    P_StationId,
                    'RACK_PICK',
                    'PENDING',
                    0,
                    NOW()
                FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
                LEFT JOIN order_bin_mapping obm_ok
                    ON  obm_ok.BIN_ID     = jt.BIN_ID
                    AND obm_ok.STATION_ID = P_StationId
                    AND obm_ok.TYPE       = 'RACK_PICK'
                    AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                WHERE obm_ok.ORDER_BIN_ID IS NULL;

                INSERT INTO put_wave_order_master (
                    PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                    ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
                )
                SELECT
                    UUID(),
                    P_StationId,
                    jt.WAVE_ID,
                    P_StorageRequestId,
                    jt.STORAGE_ID,
                    COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING',
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty
                FROM JSON_TABLE(
                        V_StorageJson,
                        '$[*]' COLUMNS (
                            WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                            STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                            BIN_ID       INT PATH '$.BIN_ID',
                            SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                            SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                            BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                            AllocatedQty INT PATH '$.AllocatedQty'
                        )
                     ) jt
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK'
                      AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                    GROUP BY BIN_ID, STATION_ID
                ) obm_reuse
                  ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                    GROUP BY BIN_ID, STATION_ID
                ) obm_new
                  ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
                WHERE jt.AllocatedQty > 0
                  AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master p
                      WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                        AND p.STORAGE_ID         = jt.STORAGE_ID
                        AND p.BIN_ID             = jt.BIN_ID
                        AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                        AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  );

                UPDATE live_inventory_master L
                INNER JOIN put_wave_order_master PWO
                    ON PWO.SKU_ID         = L.ARTICLE_ID
                   AND PWO.BATCH_ID       = L.BATCH_ID
                   AND PWO.BIN_ID         = L.BIN_ID
                   AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
                SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY
                WHERE L.ARTICLE_ID   = P_SkuId
                  AND L.BATCH_ID     = P_BatchId
                  AND PWO.STORAGE_ID = P_StorageId
                  AND PWO.STATUS     = 'PENDING';

            ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

                SELECT
                    UUID() AS PUT_ORDER_ID,
                    P_StationId AS STATION_ID,
                    jt.WAVE_ID,
                    P_StorageRequestId AS STORAGE_REQUEST_ID,
                    jt.STORAGE_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING' AS STATUS,
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty AS EXPECTED_QUANTITY
                FROM JSON_TABLE(
                    V_StorageJson,
                    '$[*]' COLUMNS (
                        WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                        BIN_ID       INT PATH '$.BIN_ID',
                        SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                        SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                        BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                        AllocatedQty INT PATH '$.AllocatedQty'
                    )
                ) jt
                WHERE jt.AllocatedQty > 0;

            END IF;

        END IF;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    INSERT INTO Tmp_StorageRequest (
        WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
    )
    SELECT
        PW.WAVE_ID,
        P_StorageRequestId,
        PW.STORAGE_ID,
        P_SkuId,
        P_BatchId,
        SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
        ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
    FROM (
        SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
        FROM put_wave_wms_data
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY STORAGE_ID, WAVE_ID
    ) PW
    LEFT JOIN (
        SELECT
            WAVE_ID,
            STORAGE_ID,
            SUM(
                CASE
                    WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                    ELSE EXPECTED_QUANTITY
                END
            ) AS EXPECTED_QUANTITY
        FROM put_wave_order_master
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY WAVE_ID, STORAGE_ID
    ) PWO
      ON PWO.STORAGE_ID = PW.STORAGE_ID
     AND PWO.WAVE_ID    = PW.WAVE_ID
    GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

    SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
    FROM Tmp_StorageRequest;

    
    IF V_PrefBinSegments = 1 THEN
        SET V_OneSegEarlyQuota =
            CASE
                WHEN V_PendingQty > GREATEST(V_CapPerSeg1, 1) THEN 1
                ELSE 999999
            END;
    ELSE
        SET V_OneSegEarlyQuota = 999999;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_A;
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_B;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_A LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_A SELECT * FROM Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_B LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_B SELECT * FROM Tmp_StorageRequest;

    IF V_PendingQty > 0 THEN

        SET V_TotalCandidates = LEAST(
            20000,
            GREATEST(
                3000,
                CEIL(V_PendingQty / GREATEST(1, V_PrefSegCap)) * 12
            )
        );
WITH RECURSIVE
        ArticleWithProximity AS (
            SELECT
                AP.CHILD_ARTICLE_ID,
                ROW_NUMBER() OVER (
                    PARTITION BY AP.PARENT_ARTICLE_ID
                    ORDER BY AP.PROXIMITY_SCORE DESC
                ) AS rn
            FROM article_proximity_score AP
            WHERE AP.PARENT_ARTICLE_ID = P_SkuId
        ),
        FinalProximity AS (
            SELECT IFNULL(AWP.CHILD_ARTICLE_ID, P_SkuId) AS CHILD_ARTICLE_ID,
                   IFNULL(AWP.rn, 1) AS rn
            FROM (SELECT 1 AS dummy) D
            LEFT JOIN ArticleWithProximity AWP ON TRUE
        ),
        AisleCost AS (
            SELECT Aisle_Number, MIN(Cost) AS Cost
            FROM station_to_aisle_cost
            WHERE Station_ID = P_StationId
            GROUP BY Aisle_Number
        ),
        FreeBins AS (
            SELECT DISTINCT
                BIM.BIN_ID,
                BIM.BIN_SEGMENTS,
                COALESCE(AC.Cost, 9999) AS Cost,
                STBM.LOCATION_ID
            FROM bin_info_master BIM
            INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
            INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
            LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
            LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
            WHERE LBM.LOCATION_ID IS NULL
        ),
        LiveFree AS (
            SELECT
                L.BIN_ID,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                IFNULL(L.remark,'na') AS remark,
                FB.BIN_SEGMENTS,
                FB.Cost
            FROM live_inventory_master L
            INNER JOIN FreeBins FB ON FB.BIN_ID = L.BIN_ID
            WHERE IFNULL(L.remark,'na') = 'na'
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master P
                  WHERE P.BIN_ID         = L.BIN_ID
                    AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                    AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              )
        ),
        RankedBins AS (
            SELECT
                L.BIN_ID,
                L.Cost,
                L.BIN_SEGMENTS,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                SM.WEIGHT_OF_EACH_SKU,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                OBM.BOT_ID,
                SM.category,
                OBM.STATUS,
                OBM.TYPE,
                FP.rn,
                CASE
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.TYPE   = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED') THEN 1
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('BIN_PICKED','PRE_ON_STATION','ON_STATION') THEN 2
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 3
                    WHEN OBM.STATION_ID <> P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 4
                    ELSE 5
                END AS row_rank
            FROM LiveFree L
            INNER JOIN sku_master SM ON SM.SKU_ID = L.ARTICLE_ID
            LEFT JOIN FinalProximity FP ON L.ARTICLE_ID = FP.CHILD_ARTICLE_ID
            LEFT JOIN (
                SELECT BIN_ID, MAX(BOT_ID) AS BOT_ID, MAX(STATUS) AS STATUS, MAX(TYPE) AS TYPE, MAX(STATION_ID) AS STATION_ID
                FROM order_bin_mapping
                GROUP BY BIN_ID
            ) OBM ON OBM.BIN_ID = L.BIN_ID
        ),
        Tmp_Bins AS (
            SELECT
                CASE
                    WHEN LOCATE(CONCAT(',', RB.BIN_ID, ','), V_StoredSKUBinsList) > 0 THEN 100000
                    ELSE IFNULL(RB.rn, 1000)
                END AS rn,
                RB.row_rank,
                RB.BIN_ID,
                RB.Cost,
                RB.BIN_SEGMENTS,
                RB.SEGMENT_NO,
                RB.ARTICLE_ID AS SKU_ID,
                RB.BATCH_ID,
                CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS WEIGHT_OF_EACH_SKU,
                RB.QUANTITY,
                RB.VIRTUAL_QUANTITY_TO_PUT,
                (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS CurrentWeightInSegment,
                SUM(
                    (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END
                ) OVER (PARTITION BY RB.BIN_ID) AS CurrentWeightInBin,
                BSR.RANKING
            FROM RankedBins RB
            INNER JOIN bin_segment_ranking BSR
                ON BSR.BIN_SEGMENT_COUNT = RB.BIN_SEGMENTS
               AND RB.SEGMENT_NO          = BSR.SEGMENT_ID
        ),
        SegCandidates AS (
            SELECT
                T.*,
                (V_MaxBinWeight - T.CurrentWeightInBin) AS BalanceWeightInBin,
                SUM(CASE WHEN (T.QUANTITY + T.VIRTUAL_QUANTITY_TO_PUT)=0 THEN 1 ELSE 0 END)
                    OVER (PARTITION BY T.BIN_ID) AS EmptySegments,
                CASE
                    WHEN T.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                    WHEN T.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                    WHEN T.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                    WHEN T.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                    ELSE 0
                END AS QtyCapPerSegment
            FROM Tmp_Bins T
            WHERE (T.SKU_ID='no-sku' OR (T.QUANTITY + T.VIRTUAL_QUANTITY_TO_PUT)=0)
        ),
        ScoredCandidates AS (
            SELECT
                C.*,

                
                CASE
                    WHEN C.BIN_SEGMENTS=6 THEN V_need6
                    WHEN C.BIN_SEGMENTS=4 THEN V_need4
                    WHEN C.BIN_SEGMENTS=2 THEN V_need2
                    ELSE 1
                END AS PlanSegsForThisBinType,

                LEAST(
                    CASE
                        WHEN C.BIN_SEGMENTS=6 THEN V_need6
                        WHEN C.BIN_SEGMENTS=4 THEN V_need4
                        WHEN C.BIN_SEGMENTS=2 THEN V_need2
                        ELSE 1
                    END,
                    GREATEST(C.EmptySegments,1)
                ) AS AllowedSegsInThisBin,

                CASE
                    WHEN V_SkuUnitWeight <= 0 THEN 999999
                    ELSE FLOOR(
                        GREATEST(C.BalanceWeightInBin,0)
                        /
                        (V_SkuUnitWeight * LEAST(
                            CASE
                                WHEN C.BIN_SEGMENTS=6 THEN V_need6
                                WHEN C.BIN_SEGMENTS=4 THEN V_need4
                                WHEN C.BIN_SEGMENTS=2 THEN V_need2
                                ELSE 1
                            END,
                            GREATEST(C.EmptySegments,1)
                        ))
                    )
                END AS WeightCapPerSegment,

                
                CASE
                    WHEN V_PrefBinSegments=6 THEN
                        CASE WHEN C.BIN_SEGMENTS=6 THEN 1 WHEN C.BIN_SEGMENTS=4 THEN 2 WHEN C.BIN_SEGMENTS=2 THEN 3 WHEN C.BIN_SEGMENTS=1 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=4 THEN
                        CASE WHEN C.BIN_SEGMENTS=4 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=1 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=2 THEN
                        CASE WHEN C.BIN_SEGMENTS=2 THEN 1 WHEN C.BIN_SEGMENTS=1 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    ELSE
                        CASE WHEN C.BIN_SEGMENTS=1 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                END AS BinTypeRank

            FROM SegCandidates C
            WHERE C.QtyCapPerSegment > 0
              AND C.BalanceWeightInBin > 0
        ),
        CapacityFinal AS (
            SELECT
                S.*,
                LEAST(S.QtyCapPerSegment, S.WeightCapPerSegment) AS SegmentCapacity
            FROM ScoredCandidates S
        ),
        PickSegments AS (
            SELECT
                X.*,
                ROW_NUMBER() OVER (
                    PARTITION BY X.BIN_ID
                    ORDER BY X.RANKING, X.SEGMENT_NO
                ) AS rn_in_bin
            FROM CapacityFinal X
            WHERE X.SegmentCapacity > 0
        ),
        BinsRanked AS (
            SELECT
                P.*,
                ROW_NUMBER() OVER (
                    PARTITION BY P.BIN_SEGMENTS
                    ORDER BY
                        P.rn,
                        P.row_rank,
                        P.Cost,
                        P.BIN_ID,
                        P.RANKING,
                        P.SEGMENT_NO
                ) AS TypeSeq
            FROM PickSegments P
            WHERE P.rn_in_bin <= P.AllowedSegsInThisBin
        ),
        BinswithLowcost AS (
            SELECT
                BR.*,
                CASE
                    WHEN V_PrefBinSegments = 1
                     AND BR.BIN_SEGMENTS   = 1
                     AND BR.TypeSeq        > V_OneSegEarlyQuota
                    THEN 5
                    ELSE BR.BinTypeRank
                END AS EffBinTypeRank,

                ROW_NUMBER() OVER (
                    ORDER BY
                        CASE
                            WHEN V_PrefBinSegments = 1
                             AND BR.BIN_SEGMENTS   = 1
                             AND BR.TypeSeq        > V_OneSegEarlyQuota
                            THEN 5
                            ELSE BR.BinTypeRank
                        END,
                        BR.rn,
                        BR.row_rank,
                        BR.Cost,
                        BR.BIN_ID,
                        BR.RANKING,
                        BR.SEGMENT_NO
                ) AS bin_index
            FROM BinsRanked BR
            LIMIT V_TotalCandidates
        ),
        alloc AS (
            SELECT
                ob.BIN_ID,
                ob.SEGMENT_NO,
                ob.SegmentCapacity,
                sr.STORAGE_ID,
                sr.WAVE_ID,
                CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS AllocatedQty,
                sr.RequestQty - CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS RemQty,
                ob.bin_index,
                sr.req_index
            FROM BinswithLowcost ob
            JOIN Tmp_StorageRequest_A sr
              ON sr.req_index = 1
             AND ob.bin_index = 1
            WHERE sr.RequestQty > 0

            UNION ALL

            SELECT
                b.BIN_ID,
                b.SEGMENT_NO,
                b.SegmentCapacity,
                CASE WHEN a.RemQty = 0 THEN s2.STORAGE_ID ELSE a.STORAGE_ID END,
                CASE WHEN a.RemQty = 0 THEN s2.WAVE_ID    ELSE a.WAVE_ID    END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        s2.RequestQty - CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                b.bin_index,
                CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
            FROM BinswithLowcost b
            JOIN alloc a
              ON b.bin_index = a.bin_index + 1
            LEFT JOIN Tmp_StorageRequest_B s2
              ON s2.req_index = a.req_index + 1
            WHERE (a.RemQty > 0) OR (s2.req_index IS NOT NULL AND s2.RequestQty > 0)
        )
        SELECT JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'WAVE_ID',      WAVE_ID,
                       'STORAGE_ID',   STORAGE_ID,
                       'BIN_ID',       BIN_ID,
                       'SEGMENT_NO',   SEGMENT_NO,
                       'SKU_ID',       P_SkuId,
                       'BATCH_ID',     P_BatchId,
                       'AllocatedQty', AllocatedQty
                   )
               )
        INTO V_StorageJson
        FROM alloc
        WHERE AllocatedQty > 0;

        IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

            INSERT INTO order_bin_mapping (
                BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
            )
            SELECT DISTINCT
                jt.BIN_ID,
                P_StationId,
                'RACK_PICK',
                'PENDING',
                0,
                NOW()
            FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
            LEFT JOIN order_bin_mapping obm_ok
                ON  obm_ok.BIN_ID     = jt.BIN_ID
                AND obm_ok.STATION_ID = P_StationId
                AND obm_ok.TYPE       = 'RACK_PICK'
                AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
            WHERE obm_ok.ORDER_BIN_ID IS NULL;

            INSERT INTO put_wave_order_master (
                PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
            )
            SELECT
                UUID(),
                P_StationId,
                jt.WAVE_ID,
                P_StorageRequestId,
                jt.STORAGE_ID,
                COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING',
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK'
                  AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                GROUP BY BIN_ID, STATION_ID
            ) obm_reuse
              ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                GROUP BY BIN_ID, STATION_ID
            ) obm_new
              ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
            WHERE jt.AllocatedQty > 0
              AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master p
                  WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                    AND p.STORAGE_ID         = jt.STORAGE_ID
                    AND p.BIN_ID             = jt.BIN_ID
                    AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                    AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              );

            UPDATE live_inventory_master L
            INNER JOIN put_wave_order_master PWO
                ON PWO.BIN_ID         = L.BIN_ID
               AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
            SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY,
                L.ARTICLE_ID              = PWO.SKU_ID,
                L.BATCH_ID                = PWO.BATCH_ID
            WHERE (L.ARTICLE_ID = 'no-sku' OR (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT)=0)
              AND PWO.STORAGE_ID = P_StorageId
              AND PWO.STATUS     = 'PENDING';

        ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

            SELECT
                UUID()             AS PUT_ORDER_ID,
                P_StationId        AS STATION_ID,
                jt.WAVE_ID         AS WAVE_ID,
                P_StorageRequestId AS STORAGE_REQUEST_ID,
                jt.STORAGE_ID,
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING'          AS STATUS,
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty    AS EXPECTED_QUANTITY
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            WHERE jt.AllocatedQty > 0;

        END IF;

    END IF;

    
    IF P_ForProcessing = 1 THEN

        SELECT COALESCE(SUM(QUANTITY),0)
        INTO   v_wms_data_total_qty
        FROM   put_wave_wms_data
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        SELECT COALESCE(
                   SUM(
                       CASE
                           WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                           ELSE EXPECTED_QUANTITY
                       END
                   ),
                   0
               )
        INTO   v_order_master_total_expected
        FROM   put_wave_order_master
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        IF v_order_master_total_expected > v_wms_data_total_qty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'OVER_ALLOCATION: expected exceeds WMS qty';
        END IF;

        SET V_left_over_calc = v_wms_data_total_qty - v_order_master_total_expected;

        UPDATE put_wave_wms_data PW
        SET    PW.STATUS    = 'COMPLETED',
               PW.LEFT_OVER = V_left_over_calc
        WHERE  PW.SKU_ID             = P_SkuId
          AND  PW.BATCH_ID           = P_BatchId
          AND  PW.STATUS             = 'PENDING'
          AND  PW.STORAGE_REQUEST_ID = P_StorageRequestId
          AND  PW.STORAGE_ID         = P_StorageId;

        COMMIT;
    END IF;

    SET SESSION cte_max_recursion_depth = 1000;

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPending_Order_allocation_V3_09012026` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPending_Order_allocation_V3_09012026` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPending_Order_allocation_V3_09012026`(
    IN P_StorageRequestId VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StorageId        VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_SkuId            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_BatchId          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StationId        INT,
    IN P_ForProcessing    INT          
)
proc_main:BEGIN
    

    
    DECLARE V_StorageJson                 JSON;
    DECLARE V_StoredSKUBinsList           TEXT;

    DECLARE V_PendingQty                  INT DEFAULT 0;

    DECLARE V_MaxBinWeight                BIGINT DEFAULT 0;

    
    DECLARE V_MaxQtyPerBin                INT DEFAULT 0;     
    DECLARE V_SkuUnitWeight               INT DEFAULT 0;
    DECLARE V_MinSegmentSize              INT DEFAULT 1;
    DECLARE V_SkuCategory                 INT DEFAULT 0;
    DECLARE V_SkuROS                      DECIMAL(10,2) DEFAULT 0.00;

    
    DECLARE V_ROS_ThresholdPct            DECIMAL(10,2) DEFAULT 60.00;
    DECLARE V_BinCapacityThresholdPct     DECIMAL(10,2) DEFAULT 50.00;

    
    DECLARE V_TopUpMinRemainingSpacePct   DECIMAL(10,2) DEFAULT 70.00;

    
    DECLARE V_TargetQty                   INT DEFAULT 0;

    DECLARE V_CapPerSeg6                  INT DEFAULT 0;
    DECLARE V_CapPerSeg4                  INT DEFAULT 0;
    DECLARE V_CapPerSeg2                  INT DEFAULT 0;
    DECLARE V_CapPerSeg1                  INT DEFAULT 0;

    DECLARE V_need6                       INT DEFAULT 1;
    DECLARE V_need4                       INT DEFAULT 1;
    DECLARE V_need2                       INT DEFAULT 1;

    DECLARE V_PrefBinSegments             INT DEFAULT 6;  

    DECLARE V_TotalCandidates             INT DEFAULT 800;

    
    DECLARE V_PrefSegCap                 INT DEFAULT 1;

    DECLARE v_wms_data_total_qty          INT DEFAULT 0;
    DECLARE v_order_master_total_expected INT DEFAULT 0;
    DECLARE V_left_over_calc              INT DEFAULT 0;

    
    DECLARE V_OneSegEarlyQuota            INT DEFAULT 999999;

    
    DECLARE V_EPS                         DECIMAL(10,6) DEFAULT 0.000100;

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF P_ForProcessing = 1 THEN
            ROLLBACK;
        END IF;
        SET SESSION cte_max_recursion_depth = 1000;
        RESIGNAL;
    END;

    
    SELECT CAST(KEY_VALUE AS SIGNED)
      INTO V_MaxBinWeight
      FROM master_config
     WHERE KEY_NAME = 'MAX_WEIGHT_ALLOWED_ON_BOT_GRAMS'
     LIMIT 1;

    SET V_MaxBinWeight = COALESCE(V_MaxBinWeight, 2147483647);

    SELECT
        COALESCE(MAX(CASE WHEN KEY_NAME='ROS_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_ROS_ThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='BIN_CAPACITY_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_BinCapacityThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='TOPUP_MIN_REMAINING_SPACE_PCT' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_TopUpMinRemainingSpacePct)
    INTO
        V_ROS_ThresholdPct,
        V_BinCapacityThresholdPct,
        V_TopUpMinRemainingSpacePct
    FROM master_config
    WHERE KEY_NAME IN ('ROS_THRESHOLD','BIN_CAPACITY_THRESHOLD','TOPUP_MIN_REMAINING_SPACE_PCT');

    SET SESSION cte_max_recursion_depth = 10000;
    SET SESSION group_concat_max_len = 65535;

    
    SELECT
        MAX_QUANTITY_PER_SEGMENT,
        WEIGHT_OF_EACH_SKU,
        MIN_SEGMENT_SIZE,
        category,
        COALESCE(ROS,0)
    INTO
        V_MaxQtyPerBin,
        V_SkuUnitWeight,
        V_MinSegmentSize,
        V_SkuCategory,
        V_SkuROS
    FROM sku_master
    WHERE SKU_ID = P_SkuId
    LIMIT 1;

    IF V_MaxQtyPerBin IS NULL OR V_MaxQtyPerBin <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'MAX_QTY_PER_BIN missing/invalid (sku_master.MAX_QUANTITY_PER_SEGMENT)';
    END IF;

    SET V_SkuUnitWeight  = COALESCE(V_SkuUnitWeight,0);
    SET V_MinSegmentSize = GREATEST(1, COALESCE(V_MinSegmentSize,1));

    
    SET V_CapPerSeg6 = FLOOR(V_MaxQtyPerBin / 6);
    SET V_CapPerSeg4 = FLOOR(V_MaxQtyPerBin / 4);
    SET V_CapPerSeg2 = FLOOR(V_MaxQtyPerBin / 2);
    SET V_CapPerSeg1 = FLOOR(V_MaxQtyPerBin / 1);

    
    SET V_TargetQty = CEIL( COALESCE(V_SkuROS,0) * (COALESCE(V_ROS_ThresholdPct,60.0)/100.0) );

    
    IF V_TargetQty <= 0 THEN
        SET V_need6 = 1;
        SET V_need4 = 1;
        SET V_need2 = 1;
        SET V_PrefBinSegments = 6;
    ELSE
        SET V_need6 = CASE
                        WHEN V_CapPerSeg6 > 0 THEN LEAST(6, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg6)))
                        ELSE 6
                      END;

        SET V_need4 = CASE
                        WHEN V_CapPerSeg4 > 0 THEN LEAST(4, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg4)))
                        ELSE 4
                      END;

        SET V_need2 = CASE
                        WHEN V_CapPerSeg2 > 0 THEN LEAST(2, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg2)))
                        ELSE 2
                      END;

        
        SET V_PrefBinSegments = 6;

        IF ((V_need6 / 6.0) * 100.0) >= (V_BinCapacityThresholdPct - V_EPS) THEN
            SET V_PrefBinSegments = 4;
        END IF;

        IF V_PrefBinSegments = 4
           AND ((V_need4 / 4.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 2;
        END IF;

        IF V_PrefBinSegments = 2
           AND ((V_need2 / 2.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 1;
        END IF;
    END IF;

    
    SET V_PrefSegCap = CASE V_PrefBinSegments
                         WHEN 6 THEN GREATEST(V_CapPerSeg6, 1)
                         WHEN 4 THEN GREATEST(V_CapPerSeg4, 1)
                         WHEN 2 THEN GREATEST(V_CapPerSeg2, 1)
                         ELSE GREATEST(V_CapPerSeg1, 1)
                       END;

    
    SELECT GROUP_CONCAT(BIN_ID)
      INTO V_StoredSKUBinsList
      FROM (
          SELECT DISTINCT BIN_ID
          FROM live_inventory_master
          WHERE ARTICLE_ID = P_SkuId
            AND BATCH_ID   = P_BatchId
      ) b;

    SET V_StoredSKUBinsList = CONCAT(',', IFNULL(V_StoredSKUBinsList,''), ',');

    IF P_ForProcessing = 1 THEN
        START TRANSACTION;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold;

    CREATE TEMPORARY TABLE Tmp_StorageRequestold (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    IF EXISTS (
        SELECT 1
        FROM live_inventory_master
        WHERE ARTICLE_ID = P_SkuId
          AND BATCH_ID   = P_BatchId
    ) THEN

        INSERT INTO Tmp_StorageRequestold (
            WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
        )
        SELECT
            PW.WAVE_ID,
            P_StorageRequestId,
            PW.STORAGE_ID,
            P_SkuId,
            P_BatchId,
            SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
            ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
        FROM (
            SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
            FROM put_wave_wms_data
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PW
        LEFT JOIN (
            SELECT
                WAVE_ID,
                STORAGE_ID,
                SUM(
                    CASE
                        WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                        ELSE EXPECTED_QUANTITY
                    END
                ) AS EXPECTED_QUANTITY
            FROM put_wave_order_master
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PWO
          ON PWO.STORAGE_ID = PW.STORAGE_ID
         AND PWO.WAVE_ID    = PW.WAVE_ID
        WHERE PW.QUANTITY > 0
        GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

        SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
        FROM Tmp_StorageRequestold;

        
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_A;
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_B;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_A LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_A SELECT * FROM Tmp_StorageRequestold;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_B LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_B SELECT * FROM Tmp_StorageRequestold;

        IF V_PendingQty > 0 THEN

            WITH RECURSIVE
            AisleCost AS (
                SELECT Aisle_Number, MIN(Cost) AS Cost
                FROM station_to_aisle_cost
                WHERE Station_ID = P_StationId
                GROUP BY Aisle_Number
            ),
            BinWeight AS (
                
                SELECT
                    L0.BIN_ID,
                    SUM(
                        (L0.QUANTITY + L0.VIRTUAL_QUANTITY_TO_PUT) * COALESCE(SM0.WEIGHT_OF_EACH_SKU,0)
                    ) AS CurrentWeightInBin
                FROM live_inventory_master L0
                LEFT JOIN sku_master SM0 ON SM0.SKU_ID = L0.ARTICLE_ID
                WHERE IFNULL(L0.remark,'na') NOT IN ('no_space','audit_marked')
                GROUP BY L0.BIN_ID
            ),
            Phase1Candidates AS (
                SELECT
                    L.BIN_ID,
                    L.SEGMENT_NO,
                    BIM.BIN_SEGMENTS,
                    COALESCE(AC.Cost, 9999) AS Cost,
                    (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT) AS QtyInSeg,
                    COALESCE(BW.CurrentWeightInBin,0) AS CurrentWeightInBin,
                    CASE
                        WHEN BIM.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                        WHEN BIM.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                        WHEN BIM.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                        WHEN BIM.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                        ELSE 0
                    END AS QtyCapPerSeg
                FROM live_inventory_master L
                INNER JOIN bin_info_master BIM ON BIM.BIN_ID = L.BIN_ID
                INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
                INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
                LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN BinWeight BW ON BW.BIN_ID = L.BIN_ID
                WHERE L.ARTICLE_ID = P_SkuId
                  AND L.BATCH_ID   = P_BatchId
                  AND IFNULL(L.remark,'na') NOT IN ('no_space','audit_marked')
                  AND LBM.LOCATION_ID IS NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master P
                      WHERE P.BIN_ID         = L.BIN_ID
                        AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                        AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  )
            ),
            Phase1BestPerBin AS (
                SELECT
                    C.*,
                    GREATEST(C.QtyCapPerSeg - C.QtyInSeg, 0) AS BalanceSegQty,
                    CASE
                        WHEN V_SkuUnitWeight <= 0 THEN 999999
                        ELSE FLOOR( GREATEST(V_MaxBinWeight - C.CurrentWeightInBin,0) / V_SkuUnitWeight )
                    END AS BalanceWeightQty,
                    
                    CASE
                        WHEN C.QtyCapPerSeg <= 0 THEN 0
                        ELSE (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) / C.QtyCapPerSeg) * 100.0
                    END AS BalanceSegFreePct,
                    ROW_NUMBER() OVER (
                        PARTITION BY C.BIN_ID
                        ORDER BY (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0)) DESC, C.SEGMENT_NO
                    ) AS rn_in_bin
                FROM Phase1Candidates C
                WHERE C.QtyCapPerSeg > 0
                  AND C.CurrentWeightInBin < V_MaxBinWeight
                  
                  AND (
                        CASE
                            WHEN C.QtyCapPerSeg <= 0 THEN 0
                            ELSE (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) / C.QtyCapPerSeg) * 100.0
                        END
                      ) >= (V_TopUpMinRemainingSpacePct - V_EPS)
            ),
            Phase1BinsOrdered AS (
                SELECT
                    B.BIN_ID,
                    B.SEGMENT_NO,
                    LEAST(B.BalanceSegQty, B.BalanceWeightQty) AS SegmentCapacity,
                    ROW_NUMBER() OVER (
                        ORDER BY
                            CASE WHEN B.BIN_SEGMENTS=6 THEN 1 WHEN B.BIN_SEGMENTS=4 THEN 2 WHEN B.BIN_SEGMENTS=2 THEN 3 WHEN B.BIN_SEGMENTS=1 THEN 4 ELSE 9 END,
                            B.Cost,
                            B.BIN_ID,
                            B.SEGMENT_NO
                    ) AS bin_index
                FROM Phase1BestPerBin B
                WHERE B.rn_in_bin = 1
                  AND LEAST(B.BalanceSegQty, B.BalanceWeightQty) > 0
            ),
            alloc1 AS (
                SELECT
                    ob.BIN_ID,
                    ob.SEGMENT_NO,
                    ob.SegmentCapacity,
                    r.STORAGE_ID,
                    P_SkuId   AS SKU_ID,
                    P_BatchId AS BATCH_ID,
                    r.WAVE_ID,
                    CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS AllocatedQty,
                    r.RequestQty - CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS RemQty,
                    ob.bin_index,
                    r.req_index
                FROM Phase1BinsOrdered ob
                JOIN Tmp_StorageRequestold_A r
                  ON r.req_index = 1
                 AND ob.bin_index = 1
                WHERE r.RequestQty > 0

                UNION ALL

                SELECT
                    b.BIN_ID,
                    b.SEGMENT_NO,
                    b.SegmentCapacity,
                    CASE WHEN a.RemQty = 0 THEN r2.STORAGE_ID ELSE a.STORAGE_ID END,
                    P_SkuId,
                    P_BatchId,
                    CASE WHEN a.RemQty = 0 THEN r2.WAVE_ID ELSE a.WAVE_ID END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            r2.RequestQty - CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    b.bin_index,
                    CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
                FROM Phase1BinsOrdered b
                JOIN alloc1 a
                  ON b.bin_index = a.bin_index + 1
                LEFT JOIN Tmp_StorageRequestold_B r2
                  ON r2.req_index = a.req_index + 1
                WHERE (a.RemQty > 0) OR (r2.req_index IS NOT NULL AND r2.RequestQty > 0)
            )
            SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'WAVE_ID',      WAVE_ID,
                           'STORAGE_ID',   STORAGE_ID,
                           'BIN_ID',       BIN_ID,
                           'SEGMENT_NO',   SEGMENT_NO,
                           'SKU_ID',       P_SkuId,
                           'BATCH_ID',     P_BatchId,
                           'AllocatedQty', AllocatedQty
                       )
                   )
            INTO V_StorageJson
            FROM alloc1
            WHERE AllocatedQty > 0;

            IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

                INSERT INTO order_bin_mapping (
                    BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
                )
                SELECT DISTINCT
                    jt.BIN_ID,
                    P_StationId,
                    'RACK_PICK',
                    'PENDING',
                    0,
                    NOW()
                FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
                LEFT JOIN order_bin_mapping obm_ok
                    ON  obm_ok.BIN_ID     = jt.BIN_ID
                    AND obm_ok.STATION_ID = P_StationId
                    AND obm_ok.TYPE       = 'RACK_PICK'
                    AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                WHERE obm_ok.ORDER_BIN_ID IS NULL;

                INSERT INTO put_wave_order_master (
                    PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                    ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
                )
                SELECT
                    UUID(),
                    P_StationId,
                    jt.WAVE_ID,
                    P_StorageRequestId,
                    jt.STORAGE_ID,
                    COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING',
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty
                FROM JSON_TABLE(
                        V_StorageJson,
                        '$[*]' COLUMNS (
                            WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                            STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                            BIN_ID       INT PATH '$.BIN_ID',
                            SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                            SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                            BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                            AllocatedQty INT PATH '$.AllocatedQty'
                        )
                     ) jt
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK'
                      AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                    GROUP BY BIN_ID, STATION_ID
                ) obm_reuse
                  ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                    GROUP BY BIN_ID, STATION_ID
                ) obm_new
                  ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
                WHERE jt.AllocatedQty > 0
                  AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master p
                      WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                        AND p.STORAGE_ID         = jt.STORAGE_ID
                        AND p.BIN_ID             = jt.BIN_ID
                        AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                        AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  );

                UPDATE live_inventory_master L
                INNER JOIN put_wave_order_master PWO
                    ON PWO.SKU_ID         = L.ARTICLE_ID
                   AND PWO.BATCH_ID       = L.BATCH_ID
                   AND PWO.BIN_ID         = L.BIN_ID
                   AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
                SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY
                WHERE L.ARTICLE_ID   = P_SkuId
                  AND L.BATCH_ID     = P_BatchId
                  AND PWO.STORAGE_ID = P_StorageId
                  AND PWO.STATUS     = 'PENDING';

            ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

                SELECT
                    UUID() AS PUT_ORDER_ID,
                    P_StationId AS STATION_ID,
                    jt.WAVE_ID,
                    P_StorageRequestId AS STORAGE_REQUEST_ID,
                    jt.STORAGE_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING' AS STATUS,
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty AS EXPECTED_QUANTITY
                FROM JSON_TABLE(
                    V_StorageJson,
                    '$[*]' COLUMNS (
                        WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                        BIN_ID       INT PATH '$.BIN_ID',
                        SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                        SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                        BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                        AllocatedQty INT PATH '$.AllocatedQty'
                    )
                ) jt
                WHERE jt.AllocatedQty > 0;

            END IF;

        END IF;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    INSERT INTO Tmp_StorageRequest (
        WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
    )
    SELECT
        PW.WAVE_ID,
        P_StorageRequestId,
        PW.STORAGE_ID,
        P_SkuId,
        P_BatchId,
        SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
        ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
    FROM (
        SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
        FROM put_wave_wms_data
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY STORAGE_ID, WAVE_ID
    ) PW
    LEFT JOIN (
        SELECT
            WAVE_ID,
            STORAGE_ID,
            SUM(
                CASE
                    WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                    ELSE EXPECTED_QUANTITY
                END
            ) AS EXPECTED_QUANTITY
        FROM put_wave_order_master
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY WAVE_ID, STORAGE_ID
    ) PWO
      ON PWO.STORAGE_ID = PW.STORAGE_ID
     AND PWO.WAVE_ID    = PW.WAVE_ID
    GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

    SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
    FROM Tmp_StorageRequest;

    
    IF V_PrefBinSegments = 1 THEN
        SET V_OneSegEarlyQuota =
            CASE
                WHEN V_PendingQty > GREATEST(V_CapPerSeg1, 1) THEN 1
                ELSE 999999
            END;
    ELSE
        SET V_OneSegEarlyQuota = 999999;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_A;
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_B;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_A LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_A SELECT * FROM Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_B LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_B SELECT * FROM Tmp_StorageRequest;

    IF V_PendingQty > 0 THEN

        SET V_TotalCandidates = LEAST(
            20000,
            GREATEST(
                3000,
                CEIL(V_PendingQty / GREATEST(1, V_PrefSegCap)) * 12
            )
        );

        WITH RECURSIVE
        ArticleWithProximity AS (
            SELECT
                AP.CHILD_ARTICLE_ID,
                ROW_NUMBER() OVER (
                    PARTITION BY AP.PARENT_ARTICLE_ID
                    ORDER BY AP.PROXIMITY_SCORE DESC
                ) AS rn
            FROM article_proximity_score AP
            WHERE AP.PARENT_ARTICLE_ID = P_SkuId
        ),
        FinalProximity AS (
            SELECT IFNULL(AWP.CHILD_ARTICLE_ID, P_SkuId) AS CHILD_ARTICLE_ID,
                   IFNULL(AWP.rn, 1) AS rn
            FROM (SELECT 1 AS dummy) D
            LEFT JOIN ArticleWithProximity AWP ON TRUE
        ),
        AisleCost AS (
            SELECT Aisle_Number, MIN(Cost) AS Cost
            FROM station_to_aisle_cost
            WHERE Station_ID = P_StationId
            GROUP BY Aisle_Number
        ),
        FreeBins AS (
            SELECT DISTINCT
                BIM.BIN_ID,
                BIM.BIN_SEGMENTS,
                COALESCE(AC.Cost, 9999) AS Cost,
                STBM.LOCATION_ID
            FROM bin_info_master BIM
            INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
            INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
            LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
            LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
            WHERE LBM.LOCATION_ID IS NULL
        ),
        LiveFree AS (
            SELECT
                L.BIN_ID,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                IFNULL(L.remark,'na') AS remark,
                FB.BIN_SEGMENTS,
                FB.Cost
            FROM live_inventory_master L
            INNER JOIN FreeBins FB ON FB.BIN_ID = L.BIN_ID
            WHERE IFNULL(L.remark,'na') = 'na'
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master P
                  WHERE P.BIN_ID         = L.BIN_ID
                    AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                    AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              )
        ),
        RankedBins AS (
            SELECT
                L.BIN_ID,
                L.Cost,
                L.BIN_SEGMENTS,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                SM.WEIGHT_OF_EACH_SKU,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                OBM.BOT_ID,
                SM.category,
                OBM.STATUS,
                OBM.TYPE,
                FP.rn,
                CASE
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.TYPE   = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED') THEN 1
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('BIN_PICKED','PRE_ON_STATION','ON_STATION') THEN 2
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 3
                    WHEN OBM.STATION_ID <> P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 4
                    ELSE 5
                END AS row_rank
            FROM LiveFree L
            INNER JOIN sku_master SM ON SM.SKU_ID = L.ARTICLE_ID
            LEFT JOIN FinalProximity FP ON L.ARTICLE_ID = FP.CHILD_ARTICLE_ID
            LEFT JOIN (
                SELECT BIN_ID, MAX(BOT_ID) AS BOT_ID, MAX(STATUS) AS STATUS, MAX(TYPE) AS TYPE, MAX(STATION_ID) AS STATION_ID
                FROM order_bin_mapping
                GROUP BY BIN_ID
            ) OBM ON OBM.BIN_ID = L.BIN_ID
        ),
        Tmp_Bins AS (
            SELECT
                CASE
                    WHEN LOCATE(CONCAT(',', RB.BIN_ID, ','), V_StoredSKUBinsList) > 0 THEN 100000
                    ELSE IFNULL(RB.rn, 1000)
                END AS rn,
                RB.row_rank,
                RB.BIN_ID,
                RB.Cost,
                RB.BIN_SEGMENTS,
                RB.SEGMENT_NO,
                RB.ARTICLE_ID AS SKU_ID,
                RB.BATCH_ID,
                CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS WEIGHT_OF_EACH_SKU,
                RB.QUANTITY,
                RB.VIRTUAL_QUANTITY_TO_PUT,
                (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS CurrentWeightInSegment,
                SUM(
                    (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END
                ) OVER (PARTITION BY RB.BIN_ID) AS CurrentWeightInBin,
                BSR.RANKING
            FROM RankedBins RB
            INNER JOIN bin_segment_ranking BSR
                ON BSR.BIN_SEGMENT_COUNT = RB.BIN_SEGMENTS
               AND RB.SEGMENT_NO          = BSR.SEGMENT_ID
        ),
        SegCandidates AS (
            SELECT
                T.*,
                (V_MaxBinWeight - T.CurrentWeightInBin) AS BalanceWeightInBin,
                SUM(CASE WHEN (T.QUANTITY + T.VIRTUAL_QUANTITY_TO_PUT)=0 THEN 1 ELSE 0 END)
                    OVER (PARTITION BY T.BIN_ID) AS EmptySegments,
                CASE
                    WHEN T.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                    WHEN T.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                    WHEN T.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                    WHEN T.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                    ELSE 0
                END AS QtyCapPerSegment
            FROM Tmp_Bins T
            WHERE (T.SKU_ID='no-sku' OR (T.QUANTITY + T.VIRTUAL_QUANTITY_TO_PUT)=0)
        ),
        ScoredCandidates AS (
            SELECT
                C.*,

                
                CASE
                    WHEN C.BIN_SEGMENTS=6 THEN V_need6
                    WHEN C.BIN_SEGMENTS=4 THEN V_need4
                    WHEN C.BIN_SEGMENTS=2 THEN V_need2
                    ELSE 1
                END AS PlanSegsForThisBinType,

                LEAST(
                    CASE
                        WHEN C.BIN_SEGMENTS=6 THEN V_need6
                        WHEN C.BIN_SEGMENTS=4 THEN V_need4
                        WHEN C.BIN_SEGMENTS=2 THEN V_need2
                        ELSE 1
                    END,
                    GREATEST(C.EmptySegments,1)
                ) AS AllowedSegsInThisBin,

                CASE
                    WHEN V_SkuUnitWeight <= 0 THEN 999999
                    ELSE FLOOR(
                        GREATEST(C.BalanceWeightInBin,0)
                        /
                        (V_SkuUnitWeight * LEAST(
                            CASE
                                WHEN C.BIN_SEGMENTS=6 THEN V_need6
                                WHEN C.BIN_SEGMENTS=4 THEN V_need4
                                WHEN C.BIN_SEGMENTS=2 THEN V_need2
                                ELSE 1
                            END,
                            GREATEST(C.EmptySegments,1)
                        ))
                    )
                END AS WeightCapPerSegment,

                
                CASE
                    WHEN V_PrefBinSegments=6 THEN
                        CASE WHEN C.BIN_SEGMENTS=6 THEN 1 WHEN C.BIN_SEGMENTS=4 THEN 2 WHEN C.BIN_SEGMENTS=2 THEN 3 WHEN C.BIN_SEGMENTS=1 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=4 THEN
                        CASE WHEN C.BIN_SEGMENTS=4 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=1 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=2 THEN
                        CASE WHEN C.BIN_SEGMENTS=2 THEN 1 WHEN C.BIN_SEGMENTS=1 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    ELSE
                        CASE WHEN C.BIN_SEGMENTS=1 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                END AS BinTypeRank

            FROM SegCandidates C
            WHERE C.QtyCapPerSegment > 0
              AND C.BalanceWeightInBin > 0
        ),
        CapacityFinal AS (
            SELECT
                S.*,
                LEAST(S.QtyCapPerSegment, S.WeightCapPerSegment) AS SegmentCapacity
            FROM ScoredCandidates S
        ),
        PickSegments AS (
            SELECT
                X.*,
                ROW_NUMBER() OVER (
                    PARTITION BY X.BIN_ID
                    ORDER BY X.RANKING, X.SEGMENT_NO
                ) AS rn_in_bin
            FROM CapacityFinal X
            WHERE X.SegmentCapacity > 0
        ),
        BinsRanked AS (
            SELECT
                P.*,
                ROW_NUMBER() OVER (
                    PARTITION BY P.BIN_SEGMENTS
                    ORDER BY
                        P.rn,
                        P.row_rank,
                        P.Cost,
                        P.BIN_ID,
                        P.RANKING,
                        P.SEGMENT_NO
                ) AS TypeSeq
            FROM PickSegments P
            WHERE P.rn_in_bin <= P.AllowedSegsInThisBin
        ),
        BinswithLowcost AS (
            SELECT
                BR.*,
                CASE
                    WHEN V_PrefBinSegments = 1
                     AND BR.BIN_SEGMENTS   = 1
                     AND BR.TypeSeq        > V_OneSegEarlyQuota
                    THEN 5
                    ELSE BR.BinTypeRank
                END AS EffBinTypeRank,

                ROW_NUMBER() OVER (
                    ORDER BY
                        CASE
                            WHEN V_PrefBinSegments = 1
                             AND BR.BIN_SEGMENTS   = 1
                             AND BR.TypeSeq        > V_OneSegEarlyQuota
                            THEN 5
                            ELSE BR.BinTypeRank
                        END,
                        BR.rn,
                        BR.row_rank,
                        BR.Cost,
                        BR.BIN_ID,
                        BR.RANKING,
                        BR.SEGMENT_NO
                ) AS bin_index
            FROM BinsRanked BR
            LIMIT V_TotalCandidates
        ),
        alloc AS (
            SELECT
                ob.BIN_ID,
                ob.SEGMENT_NO,
                ob.SegmentCapacity,
                sr.STORAGE_ID,
                sr.WAVE_ID,
                CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS AllocatedQty,
                sr.RequestQty - CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS RemQty,
                ob.bin_index,
                sr.req_index
            FROM BinswithLowcost ob
            JOIN Tmp_StorageRequest_A sr
              ON sr.req_index = 1
             AND ob.bin_index = 1
            WHERE sr.RequestQty > 0

            UNION ALL

            SELECT
                b.BIN_ID,
                b.SEGMENT_NO,
                b.SegmentCapacity,
                CASE WHEN a.RemQty = 0 THEN s2.STORAGE_ID ELSE a.STORAGE_ID END,
                CASE WHEN a.RemQty = 0 THEN s2.WAVE_ID    ELSE a.WAVE_ID    END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        s2.RequestQty - CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                b.bin_index,
                CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
            FROM BinswithLowcost b
            JOIN alloc a
              ON b.bin_index = a.bin_index + 1
            LEFT JOIN Tmp_StorageRequest_B s2
              ON s2.req_index = a.req_index + 1
            WHERE (a.RemQty > 0) OR (s2.req_index IS NOT NULL AND s2.RequestQty > 0)
        )
        SELECT JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'WAVE_ID',      WAVE_ID,
                       'STORAGE_ID',   STORAGE_ID,
                       'BIN_ID',       BIN_ID,
                       'SEGMENT_NO',   SEGMENT_NO,
                       'SKU_ID',       P_SkuId,
                       'BATCH_ID',     P_BatchId,
                       'AllocatedQty', AllocatedQty
                   )
               )
        INTO V_StorageJson
        FROM alloc
        WHERE AllocatedQty > 0;

        IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

            INSERT INTO order_bin_mapping (
                BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
            )
            SELECT DISTINCT
                jt.BIN_ID,
                P_StationId,
                'RACK_PICK',
                'PENDING',
                0,
                NOW()
            FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
            LEFT JOIN order_bin_mapping obm_ok
                ON  obm_ok.BIN_ID     = jt.BIN_ID
                AND obm_ok.STATION_ID = P_StationId
                AND obm_ok.TYPE       = 'RACK_PICK'
                AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
            WHERE obm_ok.ORDER_BIN_ID IS NULL;

            INSERT INTO put_wave_order_master (
                PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
            )
            SELECT
                UUID(),
                P_StationId,
                jt.WAVE_ID,
                P_StorageRequestId,
                jt.STORAGE_ID,
                COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING',
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK'
                  AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                GROUP BY BIN_ID, STATION_ID
            ) obm_reuse
              ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                GROUP BY BIN_ID, STATION_ID
            ) obm_new
              ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
            WHERE jt.AllocatedQty > 0
              AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master p
                  WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                    AND p.STORAGE_ID         = jt.STORAGE_ID
                    AND p.BIN_ID             = jt.BIN_ID
                    AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                    AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              );

            UPDATE live_inventory_master L
            INNER JOIN put_wave_order_master PWO
                ON PWO.BIN_ID         = L.BIN_ID
               AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
            SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY,
                L.ARTICLE_ID              = PWO.SKU_ID,
                L.BATCH_ID                = PWO.BATCH_ID
            WHERE (L.ARTICLE_ID = 'no-sku' OR (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT)=0)
              AND PWO.STORAGE_ID = P_StorageId
              AND PWO.STATUS     = 'PENDING';

        ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

            SELECT
                UUID()             AS PUT_ORDER_ID,
                P_StationId        AS STATION_ID,
                jt.WAVE_ID         AS WAVE_ID,
                P_StorageRequestId AS STORAGE_REQUEST_ID,
                jt.STORAGE_ID,
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING'          AS STATUS,
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty    AS EXPECTED_QUANTITY
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            WHERE jt.AllocatedQty > 0;

        END IF;

    END IF;

    
    IF P_ForProcessing = 1 THEN

        SELECT COALESCE(SUM(QUANTITY),0)
        INTO   v_wms_data_total_qty
        FROM   put_wave_wms_data
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        SELECT COALESCE(
                   SUM(
                       CASE
                           WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                           ELSE EXPECTED_QUANTITY
                       END
                   ),
                   0
               )
        INTO   v_order_master_total_expected
        FROM   put_wave_order_master
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        IF v_order_master_total_expected > v_wms_data_total_qty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'OVER_ALLOCATION: expected exceeds WMS qty';
        END IF;

        SET V_left_over_calc = v_wms_data_total_qty - v_order_master_total_expected;

        UPDATE put_wave_wms_data PW
        SET    PW.STATUS    = 'COMPLETED',
               PW.LEFT_OVER = V_left_over_calc
        WHERE  PW.SKU_ID             = P_SkuId
          AND  PW.BATCH_ID           = P_BatchId
          AND  PW.STATUS             = 'PENDING'
          AND  PW.STORAGE_REQUEST_ID = P_StorageRequestId
          AND  PW.STORAGE_ID         = P_StorageId;

        COMMIT;
    END IF;

    SET SESSION cte_max_recursion_depth = 1000;

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPending_Order_allocation_V3_12012026` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPending_Order_allocation_V3_12012026` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPending_Order_allocation_V3_12012026`(
    IN P_StorageRequestId VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StorageId        VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_SkuId            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_BatchId          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StationId        INT,
    IN P_ForProcessing    INT          
)
proc_main:BEGIN
    

    
    DECLARE V_StorageJson                 JSON;
    DECLARE V_StoredSKUBinsList           TEXT;

    DECLARE V_PendingQty                  INT DEFAULT 0;

    DECLARE V_MaxBinWeight                BIGINT DEFAULT 0;

    
    DECLARE V_MaxQtyPerBin                INT DEFAULT 0;     
    DECLARE V_SkuUnitWeight               INT DEFAULT 0;
    DECLARE V_MinSegmentSize              INT DEFAULT 1;
    DECLARE V_SkuCategory                 INT DEFAULT 0;
    DECLARE V_SkuROS                      DECIMAL(10,2) DEFAULT 0.00;

    
    DECLARE V_ROS_ThresholdPct            DECIMAL(10,2) DEFAULT 60.00;
    DECLARE V_BinCapacityThresholdPct     DECIMAL(10,2) DEFAULT 50.00;

    
    DECLARE V_TopUpMinRemainingSpacePct   DECIMAL(10,2) DEFAULT 70.00;

    
    DECLARE V_TargetQty                   INT DEFAULT 0;

    DECLARE V_CapPerSeg6                  INT DEFAULT 0;
    DECLARE V_CapPerSeg4                  INT DEFAULT 0;
    DECLARE V_CapPerSeg2                  INT DEFAULT 0;
    DECLARE V_CapPerSeg1                  INT DEFAULT 0;

    DECLARE V_need6                       INT DEFAULT 1;
    DECLARE V_need4                       INT DEFAULT 1;
    DECLARE V_need2                       INT DEFAULT 1;

    DECLARE V_PrefBinSegments             INT DEFAULT 6;  

    DECLARE V_TotalCandidates             INT DEFAULT 800;

    
    DECLARE V_PrefSegCap                 INT DEFAULT 1;

    DECLARE v_wms_data_total_qty          INT DEFAULT 0;
    DECLARE v_order_master_total_expected INT DEFAULT 0;
    DECLARE V_left_over_calc              INT DEFAULT 0;

    
    DECLARE V_OneSegEarlyQuota            INT DEFAULT 999999;

    
    DECLARE V_EPS                         DECIMAL(10,6) DEFAULT 0.000100;

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF P_ForProcessing = 1 THEN
            ROLLBACK;
        END IF;
        SET SESSION cte_max_recursion_depth = 1000;
        RESIGNAL;
    END;

    
    SELECT CAST(KEY_VALUE AS SIGNED)
      INTO V_MaxBinWeight
      FROM master_config
     WHERE KEY_NAME = 'MAX_WEIGHT_ALLOWED_ON_BOT_GRAMS'
     LIMIT 1;

    SET V_MaxBinWeight = COALESCE(V_MaxBinWeight, 2147483647);

    SELECT
        COALESCE(MAX(CASE WHEN KEY_NAME='ROS_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_ROS_ThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='BIN_CAPACITY_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_BinCapacityThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='TOPUP_MIN_REMAINING_SPACE_PCT' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_TopUpMinRemainingSpacePct)
    INTO
        V_ROS_ThresholdPct,
        V_BinCapacityThresholdPct,
        V_TopUpMinRemainingSpacePct
    FROM master_config
    WHERE KEY_NAME IN ('ROS_THRESHOLD','BIN_CAPACITY_THRESHOLD','TOPUP_MIN_REMAINING_SPACE_PCT');

    SET SESSION cte_max_recursion_depth = 10000;
    SET SESSION group_concat_max_len = 65535;

    
    SELECT
        MAX_QUANTITY_PER_SEGMENT,
        WEIGHT_OF_EACH_SKU,
        MIN_SEGMENT_SIZE,
        category,
        COALESCE(ROS,0)
    INTO
        V_MaxQtyPerBin,
        V_SkuUnitWeight,
        V_MinSegmentSize,
        V_SkuCategory,
        V_SkuROS
    FROM sku_master
    WHERE SKU_ID = P_SkuId
    LIMIT 1;

    IF V_MaxQtyPerBin IS NULL OR V_MaxQtyPerBin <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'MAX_QTY_PER_BIN missing/invalid (sku_master.MAX_QUANTITY_PER_SEGMENT)';
    END IF;

    SET V_SkuUnitWeight  = COALESCE(V_SkuUnitWeight,0);
    SET V_MinSegmentSize = GREATEST(1, COALESCE(V_MinSegmentSize,1));

    
    SET V_CapPerSeg6 = FLOOR(V_MaxQtyPerBin / 6);
    SET V_CapPerSeg4 = FLOOR(V_MaxQtyPerBin / 4);
    SET V_CapPerSeg2 = FLOOR(V_MaxQtyPerBin / 2);
    SET V_CapPerSeg1 = FLOOR(V_MaxQtyPerBin / 1);

    
    SET V_TargetQty = CEIL( COALESCE(V_SkuROS,0) * (COALESCE(V_ROS_ThresholdPct,60.0)/100.0) );

    
    IF V_TargetQty <= 0 THEN
        SET V_need6 = 1;
        SET V_need4 = 1;
        SET V_need2 = 1;
        SET V_PrefBinSegments = 6;
    ELSE
        SET V_need6 = CASE
                        WHEN V_CapPerSeg6 > 0 THEN LEAST(6, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg6)))
                        ELSE 6
                      END;

        SET V_need4 = CASE
                        WHEN V_CapPerSeg4 > 0 THEN LEAST(4, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg4)))
                        ELSE 4
                      END;

        SET V_need2 = CASE
                        WHEN V_CapPerSeg2 > 0 THEN LEAST(2, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg2)))
                        ELSE 2
                      END;

        
        SET V_PrefBinSegments = 6;

        IF ((V_need6 / 6.0) * 100.0) >= (V_BinCapacityThresholdPct - V_EPS) THEN
            SET V_PrefBinSegments = 4;
        END IF;

        IF V_PrefBinSegments = 4
           AND ((V_need4 / 4.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 2;
        END IF;

        IF V_PrefBinSegments = 2
           AND ((V_need2 / 2.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 1;
        END IF;
    END IF;

    
    SET V_PrefSegCap = CASE V_PrefBinSegments
                         WHEN 6 THEN GREATEST(V_CapPerSeg6, 1)
                         WHEN 4 THEN GREATEST(V_CapPerSeg4, 1)
                         WHEN 2 THEN GREATEST(V_CapPerSeg2, 1)
                         ELSE GREATEST(V_CapPerSeg1, 1)
                       END;

    
    SELECT GROUP_CONCAT(BIN_ID)
      INTO V_StoredSKUBinsList
      FROM (
          SELECT DISTINCT BIN_ID
          FROM live_inventory_master
          WHERE ARTICLE_ID = P_SkuId
            AND BATCH_ID   = P_BatchId
      ) b;

    SET V_StoredSKUBinsList = CONCAT(',', IFNULL(V_StoredSKUBinsList,''), ',');

    IF P_ForProcessing = 1 THEN
        START TRANSACTION;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold;

    CREATE TEMPORARY TABLE Tmp_StorageRequestold (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    IF EXISTS (
        SELECT 1
        FROM live_inventory_master
        WHERE ARTICLE_ID = P_SkuId
          AND BATCH_ID   = P_BatchId
    ) THEN

        INSERT INTO Tmp_StorageRequestold (
            WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
        )
        SELECT
            PW.WAVE_ID,
            P_StorageRequestId,
            PW.STORAGE_ID,
            P_SkuId,
            P_BatchId,
            SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
            ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
        FROM (
            SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
            FROM put_wave_wms_data
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PW
        LEFT JOIN (
            SELECT
                WAVE_ID,
                STORAGE_ID,
                SUM(
                    CASE
                        WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                        ELSE EXPECTED_QUANTITY
                    END
                ) AS EXPECTED_QUANTITY
            FROM put_wave_order_master
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PWO
          ON PWO.STORAGE_ID = PW.STORAGE_ID
         AND PWO.WAVE_ID    = PW.WAVE_ID
        WHERE PW.QUANTITY > 0
        GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

        SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
        FROM Tmp_StorageRequestold;

        
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_A;
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_B;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_A LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_A SELECT * FROM Tmp_StorageRequestold;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_B LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_B SELECT * FROM Tmp_StorageRequestold;

        IF V_PendingQty > 0 THEN

            WITH RECURSIVE
            AisleCost AS (
                SELECT Aisle_Number, MIN(Cost) AS Cost
                FROM station_to_aisle_cost
                WHERE Station_ID = P_StationId
                GROUP BY Aisle_Number
            ),
            BinWeight AS (
                
                SELECT
                    L0.BIN_ID,
                    SUM(
                        (L0.QUANTITY + L0.VIRTUAL_QUANTITY_TO_PUT) * COALESCE(SM0.WEIGHT_OF_EACH_SKU,0)
                    ) AS CurrentWeightInBin
                FROM live_inventory_master L0
                LEFT JOIN sku_master SM0 ON SM0.SKU_ID = L0.ARTICLE_ID
                WHERE IFNULL(L0.remark,'na') NOT IN ('no_space','audit_marked')
                GROUP BY L0.BIN_ID
            ),
            Phase1Candidates AS (
                SELECT
                    L.BIN_ID,
                    L.SEGMENT_NO,
                    BIM.BIN_SEGMENTS,
                    COALESCE(AC.Cost, 9999) AS Cost,
                    (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT) AS QtyInSeg,
                    COALESCE(BW.CurrentWeightInBin,0) AS CurrentWeightInBin,
                    CASE
                        WHEN BIM.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                        WHEN BIM.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                        WHEN BIM.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                        WHEN BIM.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                        ELSE 0
                    END AS QtyCapPerSeg
                FROM live_inventory_master L
                INNER JOIN bin_info_master BIM ON BIM.BIN_ID = L.BIN_ID
                INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
                INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
                LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN BinWeight BW ON BW.BIN_ID = L.BIN_ID
                WHERE L.ARTICLE_ID = P_SkuId
                  AND L.BATCH_ID   = P_BatchId
                  AND IFNULL(L.remark,'na') NOT IN ('no_space','audit_marked')
                  AND LBM.LOCATION_ID IS NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master P
                      WHERE P.BIN_ID         = L.BIN_ID
                        AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                        AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  )
            ),
            Phase1BestPerBin AS (
                SELECT
                    C.*,
                    GREATEST(C.QtyCapPerSeg - C.QtyInSeg, 0) AS BalanceSegQty,
                    CASE
                        WHEN V_SkuUnitWeight <= 0 THEN 999999
                        ELSE FLOOR( GREATEST(V_MaxBinWeight - C.CurrentWeightInBin,0) / V_SkuUnitWeight )
                    END AS BalanceWeightQty,
                    
                    CASE
                        WHEN C.QtyCapPerSeg <= 0 THEN 0
                        ELSE (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) / C.QtyCapPerSeg) * 100.0
                    END AS BalanceSegFreePct,
                    ROW_NUMBER() OVER (
                        PARTITION BY C.BIN_ID
                        ORDER BY (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0)) DESC, C.SEGMENT_NO
                    ) AS rn_in_bin
                FROM Phase1Candidates C
                WHERE C.QtyCapPerSeg > 0
                  AND C.CurrentWeightInBin < V_MaxBinWeight
                  
                  AND (
                        CASE
                            WHEN C.QtyCapPerSeg <= 0 THEN 0
                            ELSE (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) / C.QtyCapPerSeg) * 100.0
                        END
                      ) >= (V_TopUpMinRemainingSpacePct - V_EPS)
            ),
            Phase1BinsOrdered AS (
                SELECT
                    B.BIN_ID,
                    B.SEGMENT_NO,
                    LEAST(B.BalanceSegQty, B.BalanceWeightQty) AS SegmentCapacity,
                    ROW_NUMBER() OVER (
                        ORDER BY
                            CASE WHEN B.BIN_SEGMENTS=6 THEN 1 WHEN B.BIN_SEGMENTS=4 THEN 2 WHEN B.BIN_SEGMENTS=2 THEN 3 WHEN B.BIN_SEGMENTS=1 THEN 4 ELSE 9 END,
                            B.Cost,
                            B.BIN_ID,
                            B.SEGMENT_NO
                    ) AS bin_index
                FROM Phase1BestPerBin B
                WHERE B.rn_in_bin = 1
                  AND LEAST(B.BalanceSegQty, B.BalanceWeightQty) > 0
            ),
            alloc1 AS (
                SELECT
                    ob.BIN_ID,
                    ob.SEGMENT_NO,
                    ob.SegmentCapacity,
                    r.STORAGE_ID,
                    P_SkuId   AS SKU_ID,
                    P_BatchId AS BATCH_ID,
                    r.WAVE_ID,
                    CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS AllocatedQty,
                    r.RequestQty - CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS RemQty,
                    ob.bin_index,
                    r.req_index
                FROM Phase1BinsOrdered ob
                JOIN Tmp_StorageRequestold_A r
                  ON r.req_index = 1
                 AND ob.bin_index = 1
                WHERE r.RequestQty > 0

                UNION ALL

                SELECT
                    b.BIN_ID,
                    b.SEGMENT_NO,
                    b.SegmentCapacity,
                    CASE WHEN a.RemQty = 0 THEN r2.STORAGE_ID ELSE a.STORAGE_ID END,
                    P_SkuId,
                    P_BatchId,
                    CASE WHEN a.RemQty = 0 THEN r2.WAVE_ID ELSE a.WAVE_ID END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            r2.RequestQty - CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    b.bin_index,
                    CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
                FROM Phase1BinsOrdered b
                JOIN alloc1 a
                  ON b.bin_index = a.bin_index + 1
                LEFT JOIN Tmp_StorageRequestold_B r2
                  ON r2.req_index = a.req_index + 1
                WHERE (a.RemQty > 0) OR (r2.req_index IS NOT NULL AND r2.RequestQty > 0)
            )
            SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'WAVE_ID',      WAVE_ID,
                           'STORAGE_ID',   STORAGE_ID,
                           'BIN_ID',       BIN_ID,
                           'SEGMENT_NO',   SEGMENT_NO,
                           'SKU_ID',       P_SkuId,
                           'BATCH_ID',     P_BatchId,
                           'AllocatedQty', AllocatedQty
                       )
                   )
            INTO V_StorageJson
            FROM alloc1
            WHERE AllocatedQty > 0;

            IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

                INSERT INTO order_bin_mapping (
                    BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
                )
                SELECT DISTINCT
                    jt.BIN_ID,
                    P_StationId,
                    'RACK_PICK',
                    'PENDING',
                    0,
                    NOW()
                FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
                LEFT JOIN order_bin_mapping obm_ok
                    ON  obm_ok.BIN_ID     = jt.BIN_ID
                    AND obm_ok.STATION_ID = P_StationId
                    AND obm_ok.TYPE       = 'RACK_PICK'
                    AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                WHERE obm_ok.ORDER_BIN_ID IS NULL;

                INSERT INTO put_wave_order_master (
                    PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                    ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
                )
                SELECT
                    UUID(),
                    P_StationId,
                    jt.WAVE_ID,
                    P_StorageRequestId,
                    jt.STORAGE_ID,
                    COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING',
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty
                FROM JSON_TABLE(
                        V_StorageJson,
                        '$[*]' COLUMNS (
                            WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                            STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                            BIN_ID       INT PATH '$.BIN_ID',
                            SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                            SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                            BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                            AllocatedQty INT PATH '$.AllocatedQty'
                        )
                     ) jt
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK'
                      AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                    GROUP BY BIN_ID, STATION_ID
                ) obm_reuse
                  ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                    GROUP BY BIN_ID, STATION_ID
                ) obm_new
                  ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
                WHERE jt.AllocatedQty > 0
                  AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master p
                      WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                        AND p.STORAGE_ID         = jt.STORAGE_ID
                        AND p.BIN_ID             = jt.BIN_ID
                        AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                        AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  );

                UPDATE live_inventory_master L
                INNER JOIN put_wave_order_master PWO
                    ON PWO.SKU_ID         = L.ARTICLE_ID
                   AND PWO.BATCH_ID       = L.BATCH_ID
                   AND PWO.BIN_ID         = L.BIN_ID
                   AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
                SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY
                WHERE L.ARTICLE_ID   = P_SkuId
                  AND L.BATCH_ID     = P_BatchId
                  AND PWO.STORAGE_ID = P_StorageId
                  AND PWO.STATUS     = 'PENDING';

            ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

                SELECT
                    UUID() AS PUT_ORDER_ID,
                    P_StationId AS STATION_ID,
                    jt.WAVE_ID,
                    P_StorageRequestId AS STORAGE_REQUEST_ID,
                    jt.STORAGE_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING' AS STATUS,
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty AS EXPECTED_QUANTITY
                FROM JSON_TABLE(
                    V_StorageJson,
                    '$[*]' COLUMNS (
                        WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                        BIN_ID       INT PATH '$.BIN_ID',
                        SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                        SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                        BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                        AllocatedQty INT PATH '$.AllocatedQty'
                    )
                ) jt
                WHERE jt.AllocatedQty > 0;

            END IF;

        END IF;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    INSERT INTO Tmp_StorageRequest (
        WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
    )
    SELECT
        PW.WAVE_ID,
        P_StorageRequestId,
        PW.STORAGE_ID,
        P_SkuId,
        P_BatchId,
        SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
        ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
    FROM (
        SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
        FROM put_wave_wms_data
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY STORAGE_ID, WAVE_ID
    ) PW
    LEFT JOIN (
        SELECT
            WAVE_ID,
            STORAGE_ID,
            SUM(
                CASE
                    WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                    ELSE EXPECTED_QUANTITY
                END
            ) AS EXPECTED_QUANTITY
        FROM put_wave_order_master
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY WAVE_ID, STORAGE_ID
    ) PWO
      ON PWO.STORAGE_ID = PW.STORAGE_ID
     AND PWO.WAVE_ID    = PW.WAVE_ID
    GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

    SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
    FROM Tmp_StorageRequest;

    
    IF V_PrefBinSegments = 1 THEN
        SET V_OneSegEarlyQuota =
            CASE
                WHEN V_PendingQty > GREATEST(V_CapPerSeg1, 1) THEN 1
                ELSE 999999
            END;
    ELSE
        SET V_OneSegEarlyQuota = 999999;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_A;
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_B;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_A LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_A SELECT * FROM Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_B LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_B SELECT * FROM Tmp_StorageRequest;

    IF V_PendingQty > 0 THEN

        SET V_TotalCandidates = LEAST(
            20000,
            GREATEST(
                3000,
                CEIL(V_PendingQty / GREATEST(1, V_PrefSegCap)) * 12
            )
        );

        WITH RECURSIVE
        ArticleWithProximity AS (
            SELECT
                AP.CHILD_ARTICLE_ID,
                ROW_NUMBER() OVER (
                    PARTITION BY AP.PARENT_ARTICLE_ID
                    ORDER BY AP.PROXIMITY_SCORE DESC
                ) AS rn
            FROM article_proximity_score AP
            WHERE AP.PARENT_ARTICLE_ID = P_SkuId
        ),
        FinalProximity AS (
            SELECT IFNULL(AWP.CHILD_ARTICLE_ID, P_SkuId) AS CHILD_ARTICLE_ID,
                   IFNULL(AWP.rn, 1) AS rn
            FROM (SELECT 1 AS dummy) D
            LEFT JOIN ArticleWithProximity AWP ON TRUE
        ),
        AisleCost AS (
            SELECT Aisle_Number, MIN(Cost) AS Cost
            FROM station_to_aisle_cost
            WHERE Station_ID = P_StationId
            GROUP BY Aisle_Number
        ),
        FreeBins AS (
            SELECT DISTINCT
                BIM.BIN_ID,
                BIM.BIN_SEGMENTS,
                COALESCE(AC.Cost, 9999) AS Cost,
                STBM.LOCATION_ID
            FROM bin_info_master BIM
            INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
            INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
            LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
            LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
            WHERE LBM.LOCATION_ID IS NULL
        ),
        LiveFree AS (
            SELECT
                L.BIN_ID,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                IFNULL(L.remark,'na') AS remark,
                FB.BIN_SEGMENTS,
                FB.Cost
            FROM live_inventory_master L
            INNER JOIN FreeBins FB ON FB.BIN_ID = L.BIN_ID
            WHERE IFNULL(L.remark,'na') = 'na'
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master P
                  WHERE P.BIN_ID         = L.BIN_ID
                    AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                    AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              )
        ),
        RankedBins AS (
            SELECT
                L.BIN_ID,
                L.Cost,
                L.BIN_SEGMENTS,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                SM.WEIGHT_OF_EACH_SKU,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                OBM.BOT_ID,
                SM.category,
                OBM.STATUS,
                OBM.TYPE,
                FP.rn,
                CASE
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.TYPE   = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED') THEN 1
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('BIN_PICKED','PRE_ON_STATION','ON_STATION') THEN 2
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 3
                    WHEN OBM.STATION_ID <> P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 4
                    ELSE 5
                END AS row_rank
            FROM LiveFree L
            INNER JOIN sku_master SM ON SM.SKU_ID = L.ARTICLE_ID
            LEFT JOIN FinalProximity FP ON L.ARTICLE_ID = FP.CHILD_ARTICLE_ID
            LEFT JOIN (
                SELECT BIN_ID, MAX(BOT_ID) AS BOT_ID, MAX(STATUS) AS STATUS, MAX(TYPE) AS TYPE, MAX(STATION_ID) AS STATION_ID
                FROM order_bin_mapping
                GROUP BY BIN_ID
            ) OBM ON OBM.BIN_ID = L.BIN_ID
        ),
        Tmp_Bins AS (
            SELECT
                CASE
                    WHEN LOCATE(CONCAT(',', RB.BIN_ID, ','), V_StoredSKUBinsList) > 0 THEN 100000
                    ELSE IFNULL(RB.rn, 1000)
                END AS rn,
                RB.row_rank,
                RB.BIN_ID,
                RB.Cost,
                RB.BIN_SEGMENTS,
                RB.SEGMENT_NO,
                RB.ARTICLE_ID AS SKU_ID,
                RB.BATCH_ID,
                CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS WEIGHT_OF_EACH_SKU,
                RB.QUANTITY,
                RB.VIRTUAL_QUANTITY_TO_PUT,
                (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS CurrentWeightInSegment,
                SUM(
                    (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END
                ) OVER (PARTITION BY RB.BIN_ID) AS CurrentWeightInBin,

                
                SUM(
                    CASE WHEN (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT)=0 THEN 1 ELSE 0 END
                ) OVER (PARTITION BY RB.BIN_ID) AS EmptySegments,
                SUM(
                    CASE
                        WHEN (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) > 0
                         AND RB.ARTICLE_ID <> 'no-sku'
                        THEN 1 ELSE 0
                    END
                ) OVER (PARTITION BY RB.BIN_ID) AS OccupiedSegments,

                BSR.RANKING
            FROM RankedBins RB
            INNER JOIN bin_segment_ranking BSR
                ON BSR.BIN_SEGMENT_COUNT = RB.BIN_SEGMENTS
               AND RB.SEGMENT_NO          = BSR.SEGMENT_ID
        ),
        SegCandidates AS (
            SELECT
                T.*,
                (V_MaxBinWeight - T.CurrentWeightInBin) AS BalanceWeightInBin,
                CASE
                    WHEN T.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                    WHEN T.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                    WHEN T.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                    WHEN T.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                    ELSE 0
                END AS QtyCapPerSegment
            FROM Tmp_Bins T
            WHERE (T.SKU_ID='no-sku' OR (T.QUANTITY + T.VIRTUAL_QUANTITY_TO_PUT)=0)
        ),
        ScoredCandidates AS (
            SELECT
                C.*,

                
                CASE
                    WHEN C.BIN_SEGMENTS=6 THEN V_need6
                    WHEN C.BIN_SEGMENTS=4 THEN V_need4
                    WHEN C.BIN_SEGMENTS=2 THEN V_need2
                    ELSE 1
                END AS PlanSegsForThisBinType,

                LEAST(
                    CASE
                        WHEN C.BIN_SEGMENTS=6 THEN V_need6
                        WHEN C.BIN_SEGMENTS=4 THEN V_need4
                        WHEN C.BIN_SEGMENTS=2 THEN V_need2
                        ELSE 1
                    END,
                    GREATEST(C.EmptySegments,1)
                ) AS AllowedSegsInThisBin,

                CASE
                    WHEN V_SkuUnitWeight <= 0 THEN 999999
                    ELSE FLOOR(
                        GREATEST(C.BalanceWeightInBin,0)
                        /
                        (V_SkuUnitWeight * LEAST(
                            CASE
                                WHEN C.BIN_SEGMENTS=6 THEN V_need6
                                WHEN C.BIN_SEGMENTS=4 THEN V_need4
                                WHEN C.BIN_SEGMENTS=2 THEN V_need2
                                ELSE 1
                            END,
                            GREATEST(C.EmptySegments,1)
                        ))
                    )
                END AS WeightCapPerSegment,

                
                CASE
                    WHEN V_PrefBinSegments=6 THEN
                        CASE WHEN C.BIN_SEGMENTS=6 THEN 1 WHEN C.BIN_SEGMENTS=4 THEN 2 WHEN C.BIN_SEGMENTS=2 THEN 3 WHEN C.BIN_SEGMENTS=1 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=4 THEN
                        CASE WHEN C.BIN_SEGMENTS=4 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=1 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=2 THEN
                        CASE WHEN C.BIN_SEGMENTS=2 THEN 1 WHEN C.BIN_SEGMENTS=1 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    ELSE
                        CASE WHEN C.BIN_SEGMENTS=1 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                END AS BinTypeRank

            FROM SegCandidates C
            WHERE C.QtyCapPerSegment > 0
              AND C.BalanceWeightInBin > 0
        ),
        CapacityFinal AS (
            SELECT
                S.*,
                LEAST(S.QtyCapPerSegment, S.WeightCapPerSegment) AS SegmentCapacity
            FROM ScoredCandidates S
        ),
        PickSegments AS (
            SELECT
                X.*,
                ROW_NUMBER() OVER (
                    PARTITION BY X.BIN_ID
                    ORDER BY X.RANKING, X.SEGMENT_NO
                ) AS rn_in_bin
            FROM CapacityFinal X
            WHERE X.SegmentCapacity > 0
        ),
        BinsRanked AS (
            SELECT
                P.*,
                ROW_NUMBER() OVER (
                    PARTITION BY P.BIN_SEGMENTS
                    ORDER BY
                        P.rn,
                        P.row_rank,
                        P.Cost,
                        P.BIN_ID,
                        P.RANKING,
                        P.SEGMENT_NO
                ) AS TypeSeq
            FROM PickSegments P
            WHERE P.rn_in_bin <= P.AllowedSegsInThisBin
        ),
        BinswithLowcost AS (
            SELECT
                BR.*,
                CASE
                    WHEN V_PrefBinSegments = 1
                     AND BR.BIN_SEGMENTS   = 1
                     AND BR.TypeSeq        > V_OneSegEarlyQuota
                    THEN 5
                    ELSE BR.BinTypeRank
                END AS EffBinTypeRank,

                ROW_NUMBER() OVER (
                    ORDER BY
                        CASE
                            WHEN V_PrefBinSegments = 1
                             AND BR.BIN_SEGMENTS   = 1
                             AND BR.TypeSeq        > V_OneSegEarlyQuota
                            THEN 5
                            ELSE BR.BinTypeRank
                        END,

                        
                        BR.OccupiedSegments DESC,
                        BR.EmptySegments    DESC,

                        BR.rn,
                        BR.row_rank,
                        BR.Cost,
                        BR.BIN_ID,
                        BR.RANKING,
                        BR.SEGMENT_NO
                ) AS bin_index
            FROM BinsRanked BR
            LIMIT V_TotalCandidates
        ),
        alloc AS (
            SELECT
                ob.BIN_ID,
                ob.SEGMENT_NO,
                ob.SegmentCapacity,
                sr.STORAGE_ID,
                sr.WAVE_ID,
                CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS AllocatedQty,
                sr.RequestQty - CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS RemQty,
                ob.bin_index,
                sr.req_index
            FROM BinswithLowcost ob
            JOIN Tmp_StorageRequest_A sr
              ON sr.req_index = 1
             AND ob.bin_index = 1
            WHERE sr.RequestQty > 0

            UNION ALL

            SELECT
                b.BIN_ID,
                b.SEGMENT_NO,
                b.SegmentCapacity,
                CASE WHEN a.RemQty = 0 THEN s2.STORAGE_ID ELSE a.STORAGE_ID END,
                CASE WHEN a.RemQty = 0 THEN s2.WAVE_ID    ELSE a.WAVE_ID    END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        s2.RequestQty - CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                b.bin_index,
                CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
            FROM BinswithLowcost b
            JOIN alloc a
              ON b.bin_index = a.bin_index + 1
            LEFT JOIN Tmp_StorageRequest_B s2
              ON s2.req_index = a.req_index + 1
            WHERE (a.RemQty > 0) OR (s2.req_index IS NOT NULL AND s2.RequestQty > 0)
        )
        SELECT JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'WAVE_ID',      WAVE_ID,
                       'STORAGE_ID',   STORAGE_ID,
                       'BIN_ID',       BIN_ID,
                       'SEGMENT_NO',   SEGMENT_NO,
                       'SKU_ID',       P_SkuId,
                       'BATCH_ID',     P_BatchId,
                       'AllocatedQty', AllocatedQty
                   )
               )
        INTO V_StorageJson
        FROM alloc
        WHERE AllocatedQty > 0;

        IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

            INSERT INTO order_bin_mapping (
                BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
            )
            SELECT DISTINCT
                jt.BIN_ID,
                P_StationId,
                'RACK_PICK',
                'PENDING',
                0,
                NOW()
            FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
            LEFT JOIN order_bin_mapping obm_ok
                ON  obm_ok.BIN_ID     = jt.BIN_ID
                AND obm_ok.STATION_ID = P_StationId
                AND obm_ok.TYPE       = 'RACK_PICK'
                AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
            WHERE obm_ok.ORDER_BIN_ID IS NULL;

            INSERT INTO put_wave_order_master (
                PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
            )
            SELECT
                UUID(),
                P_StationId,
                jt.WAVE_ID,
                P_StorageRequestId,
                jt.STORAGE_ID,
                COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING',
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK'
                  AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                GROUP BY BIN_ID, STATION_ID
            ) obm_reuse
              ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                GROUP BY BIN_ID, STATION_ID
            ) obm_new
              ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
            WHERE jt.AllocatedQty > 0
              AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master p
                  WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                    AND p.STORAGE_ID         = jt.STORAGE_ID
                    AND p.BIN_ID             = jt.BIN_ID
                    AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                    AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              );

            UPDATE live_inventory_master L
            INNER JOIN put_wave_order_master PWO
                ON PWO.BIN_ID         = L.BIN_ID
               AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
            SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY,
                L.ARTICLE_ID              = PWO.SKU_ID,
                L.BATCH_ID                = PWO.BATCH_ID
            WHERE (L.ARTICLE_ID = 'no-sku' OR (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT)=0)
              AND PWO.STORAGE_ID = P_StorageId
              AND PWO.STATUS     = 'PENDING';

        ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

            SELECT
                UUID()             AS PUT_ORDER_ID,
                P_StationId        AS STATION_ID,
                jt.WAVE_ID         AS WAVE_ID,
                P_StorageRequestId AS STORAGE_REQUEST_ID,
                jt.STORAGE_ID,
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING'          AS STATUS,
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty    AS EXPECTED_QUANTITY
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            WHERE jt.AllocatedQty > 0;

        END IF;

    END IF;

    
    IF P_ForProcessing = 1 THEN

        SELECT COALESCE(SUM(QUANTITY),0)
        INTO   v_wms_data_total_qty
        FROM   put_wave_wms_data
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        SELECT COALESCE(
                   SUM(
                       CASE
                           WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                           ELSE EXPECTED_QUANTITY
                       END
                   ),
                   0
               )
        INTO   v_order_master_total_expected
        FROM   put_wave_order_master
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        IF v_order_master_total_expected > v_wms_data_total_qty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'OVER_ALLOCATION: expected exceeds WMS qty';
        END IF;

        SET V_left_over_calc = v_wms_data_total_qty - v_order_master_total_expected;

        UPDATE put_wave_wms_data PW
        SET    PW.STATUS    = 'COMPLETED',
               PW.LEFT_OVER = V_left_over_calc
        WHERE  PW.SKU_ID             = P_SkuId
          AND  PW.BATCH_ID           = P_BatchId
          AND  PW.STATUS             = 'PENDING'
          AND  PW.STORAGE_REQUEST_ID = P_StorageRequestId
          AND  PW.STORAGE_ID         = P_StorageId;

        COMMIT;
    END IF;

    SET SESSION cte_max_recursion_depth = 1000;

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPending_Order_allocation_V3_13012026` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPending_Order_allocation_V3_13012026` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPending_Order_allocation_V3_13012026`(
    IN P_StorageRequestId VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StorageId        VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_SkuId            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_BatchId          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StationId        INT,
    IN P_ForProcessing    INT          
)
proc_main:BEGIN
    

    
    DECLARE V_StorageJson                 JSON;
    DECLARE V_StoredSKUBinsList           TEXT;

    DECLARE V_PendingQty                  INT DEFAULT 0;

    DECLARE V_MaxBinWeight                BIGINT DEFAULT 0;

    
    DECLARE V_MaxQtyPerBin                INT DEFAULT 0;     
    DECLARE V_SkuUnitWeight               INT DEFAULT 0;
    DECLARE V_MinSegmentSize              INT DEFAULT 1;
    DECLARE V_SkuCategory                 INT DEFAULT 0;
    DECLARE V_SkuROS                      DECIMAL(10,2) DEFAULT 0.00;

    
    DECLARE V_ROS_ThresholdPct            DECIMAL(10,2) DEFAULT 60.00;
    DECLARE V_BinCapacityThresholdPct     DECIMAL(10,2) DEFAULT 50.00;

    
    DECLARE V_TopUpMinRemainingSpacePct   DECIMAL(10,2) DEFAULT 70.00;

    
    DECLARE V_TargetQty                   INT DEFAULT 0;

    DECLARE V_CapPerSeg6                  INT DEFAULT 0;
    DECLARE V_CapPerSeg4                  INT DEFAULT 0;
    DECLARE V_CapPerSeg2                  INT DEFAULT 0;
    DECLARE V_CapPerSeg1                  INT DEFAULT 0;

    DECLARE V_need6                       INT DEFAULT 1;
    DECLARE V_need4                       INT DEFAULT 1;
    DECLARE V_need2                       INT DEFAULT 1;

    DECLARE V_PrefBinSegments             INT DEFAULT 6;  

    DECLARE V_TotalCandidates             INT DEFAULT 800;

    
    DECLARE V_PrefSegCap                  INT DEFAULT 1;

    DECLARE v_wms_data_total_qty          INT DEFAULT 0;
    DECLARE v_order_master_total_expected INT DEFAULT 0;
    DECLARE V_left_over_calc              INT DEFAULT 0;

    
    DECLARE V_OneSegEarlyQuota            INT DEFAULT 999999;

    
    DECLARE V_EPS                         DECIMAL(10,6) DEFAULT 0.000100;

    
    DECLARE V_AllocSum                    BIGINT DEFAULT 0;

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF P_ForProcessing = 1 THEN
            ROLLBACK;
        END IF;
        SET SESSION cte_max_recursion_depth = 1000;
        RESIGNAL;
    END;

    
    SELECT CAST(KEY_VALUE AS SIGNED)
      INTO V_MaxBinWeight
      FROM master_config
     WHERE KEY_NAME = 'MAX_WEIGHT_ALLOWED_ON_BOT_GRAMS'
     LIMIT 1;

    SET V_MaxBinWeight = COALESCE(V_MaxBinWeight, 2147483647);

    SELECT
        COALESCE(MAX(CASE WHEN KEY_NAME='ROS_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_ROS_ThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='BIN_CAPACITY_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_BinCapacityThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='TOPUP_MIN_REMAINING_SPACE_PCT' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_TopUpMinRemainingSpacePct)
    INTO
        V_ROS_ThresholdPct,
        V_BinCapacityThresholdPct,
        V_TopUpMinRemainingSpacePct
    FROM master_config
    WHERE KEY_NAME IN ('ROS_THRESHOLD','BIN_CAPACITY_THRESHOLD','TOPUP_MIN_REMAINING_SPACE_PCT');

    SET SESSION cte_max_recursion_depth = 10000;
    SET SESSION group_concat_max_len = 65535;

    
    SELECT
        MAX_QUANTITY_PER_SEGMENT,
        WEIGHT_OF_EACH_SKU,
        MIN_SEGMENT_SIZE,
        category,
        COALESCE(ROS,0)
    INTO
        V_MaxQtyPerBin,
        V_SkuUnitWeight,
        V_MinSegmentSize,
        V_SkuCategory,
        V_SkuROS
    FROM sku_master
    WHERE SKU_ID = P_SkuId
    LIMIT 1;

    IF V_MaxQtyPerBin IS NULL OR V_MaxQtyPerBin <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'MAX_QTY_PER_BIN missing/invalid (sku_master.MAX_QUANTITY_PER_SEGMENT)';
    END IF;

    SET V_SkuUnitWeight  = COALESCE(V_SkuUnitWeight,0);
    SET V_MinSegmentSize = GREATEST(1, COALESCE(V_MinSegmentSize,1));

    
    SET V_CapPerSeg6 = FLOOR(V_MaxQtyPerBin / 6);
    SET V_CapPerSeg4 = FLOOR(V_MaxQtyPerBin / 4);
    SET V_CapPerSeg2 = FLOOR(V_MaxQtyPerBin / 2);
    SET V_CapPerSeg1 = FLOOR(V_MaxQtyPerBin / 1);

    
    SET V_TargetQty = CEIL( COALESCE(V_SkuROS,0) * (COALESCE(V_ROS_ThresholdPct,60.0)/100.0) );

    
    IF V_TargetQty <= 0 THEN
        SET V_need6 = 1;
        SET V_need4 = 1;
        SET V_need2 = 1;
        SET V_PrefBinSegments = 6;
    ELSE
        SET V_need6 = CASE
                        WHEN V_CapPerSeg6 > 0 THEN LEAST(6, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg6)))
                        ELSE 6
                      END;

        SET V_need4 = CASE
                        WHEN V_CapPerSeg4 > 0 THEN LEAST(4, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg4)))
                        ELSE 4
                      END;

        SET V_need2 = CASE
                        WHEN V_CapPerSeg2 > 0 THEN LEAST(2, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg2)))
                        ELSE 2
                      END;

        
        SET V_PrefBinSegments = 6;

        IF ((V_need6 / 6.0) * 100.0) >= (V_BinCapacityThresholdPct - V_EPS) THEN
            SET V_PrefBinSegments = 4;
        END IF;

        IF V_PrefBinSegments = 4
           AND ((V_need4 / 4.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 2;
        END IF;

        IF V_PrefBinSegments = 2
           AND ((V_need2 / 2.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 1;
        END IF;
    END IF;

    
    SET V_PrefSegCap = CASE V_PrefBinSegments
                         WHEN 6 THEN GREATEST(V_CapPerSeg6, 1)
                         WHEN 4 THEN GREATEST(V_CapPerSeg4, 1)
                         WHEN 2 THEN GREATEST(V_CapPerSeg2, 1)
                         ELSE GREATEST(V_CapPerSeg1, 1)
                       END;

    
    SELECT GROUP_CONCAT(BIN_ID)
      INTO V_StoredSKUBinsList
      FROM (
          SELECT DISTINCT BIN_ID
          FROM live_inventory_master
          WHERE ARTICLE_ID = P_SkuId
            AND BATCH_ID   = P_BatchId
      ) b;

    SET V_StoredSKUBinsList = CONCAT(',', IFNULL(V_StoredSKUBinsList,''), ',');

    IF P_ForProcessing = 1 THEN
        START TRANSACTION;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold;

    CREATE TEMPORARY TABLE Tmp_StorageRequestold (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    IF EXISTS (
        SELECT 1
        FROM live_inventory_master
        WHERE ARTICLE_ID = P_SkuId
          AND BATCH_ID   = P_BatchId
    ) THEN

        INSERT INTO Tmp_StorageRequestold (
            WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
        )
        SELECT
            PW.WAVE_ID,
            P_StorageRequestId,
            PW.STORAGE_ID,
            P_SkuId,
            P_BatchId,
            SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
            ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
        FROM (
            SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
            FROM put_wave_wms_data
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PW
        LEFT JOIN (
            SELECT
                WAVE_ID,
                STORAGE_ID,
                SUM(
                    CASE
                        WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                        ELSE EXPECTED_QUANTITY
                    END
                ) AS EXPECTED_QUANTITY
            FROM put_wave_order_master
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PWO
          ON PWO.STORAGE_ID = PW.STORAGE_ID
         AND PWO.WAVE_ID    = PW.WAVE_ID
        WHERE PW.QUANTITY > 0
        GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

        SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
        FROM Tmp_StorageRequestold;

        
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_A;
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_B;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_A LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_A SELECT * FROM Tmp_StorageRequestold;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_B LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_B SELECT * FROM Tmp_StorageRequestold;

        IF V_PendingQty > 0 THEN

            WITH RECURSIVE
            AisleCost AS (
                SELECT Aisle_Number, MIN(Cost) AS Cost
                FROM station_to_aisle_cost
                WHERE Station_ID = P_StationId
                GROUP BY Aisle_Number
            ),
            BinWeight AS (
                
                SELECT
                    L0.BIN_ID,
                    SUM(
                        (L0.QUANTITY + L0.VIRTUAL_QUANTITY_TO_PUT) * COALESCE(SM0.WEIGHT_OF_EACH_SKU,0)
                    ) AS CurrentWeightInBin
                FROM live_inventory_master L0
                LEFT JOIN sku_master SM0 ON SM0.SKU_ID = L0.ARTICLE_ID
                WHERE IFNULL(L0.remark,'na') NOT IN ('no_space','audit_marked')
                GROUP BY L0.BIN_ID
            ),
            Phase1Candidates AS (
                SELECT
                    L.BIN_ID,
                    L.SEGMENT_NO,
                    BIM.BIN_SEGMENTS,
                    COALESCE(AC.Cost, 9999) AS Cost,
                    (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT) AS QtyInSeg,
                    COALESCE(BW.CurrentWeightInBin,0) AS CurrentWeightInBin,
                    CASE
                        WHEN BIM.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                        WHEN BIM.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                        WHEN BIM.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                        WHEN BIM.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                        ELSE 0
                    END AS QtyCapPerSeg
                FROM live_inventory_master L
                INNER JOIN bin_info_master BIM ON BIM.BIN_ID = L.BIN_ID
                INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
                INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
                LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN BinWeight BW ON BW.BIN_ID = L.BIN_ID
                WHERE L.ARTICLE_ID = P_SkuId
                  AND L.BATCH_ID   = P_BatchId
                  AND IFNULL(L.remark,'na') NOT IN ('no_space','audit_marked')
                  AND LBM.LOCATION_ID IS NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master P
                      WHERE P.BIN_ID         = L.BIN_ID
                        AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                        AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  )
            ),
            Phase1BestPerBin AS (
                SELECT
                    C.*,
                    GREATEST(C.QtyCapPerSeg - C.QtyInSeg, 0) AS BalanceSegQty,
                    CASE
                        WHEN V_SkuUnitWeight <= 0 THEN 999999
                        ELSE FLOOR( GREATEST(V_MaxBinWeight - C.CurrentWeightInBin,0) / V_SkuUnitWeight )
                    END AS BalanceWeightQty,
                    
                    CASE
                        WHEN C.QtyCapPerSeg <= 0 THEN 0
                        ELSE (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) / C.QtyCapPerSeg) * 100.0
                    END AS BalanceSegFreePct,
                    ROW_NUMBER() OVER (
                        PARTITION BY C.BIN_ID
                        ORDER BY (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0)) DESC, C.SEGMENT_NO
                    ) AS rn_in_bin
                FROM Phase1Candidates C
                WHERE C.QtyCapPerSeg > 0
                  AND C.CurrentWeightInBin < V_MaxBinWeight
                  
                  AND (
                        CASE
                            WHEN C.QtyCapPerSeg <= 0 THEN 0
                            ELSE (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0) / C.QtyCapPerSeg) * 100.0
                        END
                      ) >= (V_TopUpMinRemainingSpacePct - V_EPS)
            ),
            Phase1BinsOrdered AS (
                SELECT
                    B.BIN_ID,
                    B.SEGMENT_NO,
                    LEAST(B.BalanceSegQty, B.BalanceWeightQty) AS SegmentCapacity,
                    ROW_NUMBER() OVER (
                        ORDER BY
                            CASE WHEN B.BIN_SEGMENTS=6 THEN 1 WHEN B.BIN_SEGMENTS=4 THEN 2 WHEN B.BIN_SEGMENTS=2 THEN 3 WHEN B.BIN_SEGMENTS=1 THEN 4 ELSE 9 END,
                            B.Cost,
                            B.BIN_ID,
                            B.SEGMENT_NO
                    ) AS bin_index
                FROM Phase1BestPerBin B
                WHERE B.rn_in_bin = 1
                  AND LEAST(B.BalanceSegQty, B.BalanceWeightQty) > 0
            ),
            alloc1 AS (
                SELECT
                    ob.BIN_ID,
                    ob.SEGMENT_NO,
                    ob.SegmentCapacity,
                    r.STORAGE_ID,
                    P_SkuId   AS SKU_ID,
                    P_BatchId AS BATCH_ID,
                    r.WAVE_ID,
                    CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS AllocatedQty,
                    r.RequestQty - CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS RemQty,
                    ob.bin_index,
                    r.req_index
                FROM Phase1BinsOrdered ob
                JOIN Tmp_StorageRequestold_A r
                  ON r.req_index = 1
                 AND ob.bin_index = 1
                WHERE r.RequestQty > 0

                UNION ALL

                SELECT
                    b.BIN_ID,
                    b.SEGMENT_NO,
                    b.SegmentCapacity,
                    CASE WHEN a.RemQty = 0 THEN r2.STORAGE_ID ELSE a.STORAGE_ID END,
                    P_SkuId,
                    P_BatchId,
                    CASE WHEN a.RemQty = 0 THEN r2.WAVE_ID ELSE a.WAVE_ID END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            r2.RequestQty - CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    b.bin_index,
                    CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
                FROM Phase1BinsOrdered b
                JOIN alloc1 a
                  ON b.bin_index = a.bin_index + 1
                LEFT JOIN Tmp_StorageRequestold_B r2
                  ON r2.req_index = a.req_index + 1
                WHERE (a.RemQty > 0) OR (r2.req_index IS NOT NULL AND r2.RequestQty > 0)
            )
            SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'WAVE_ID',      WAVE_ID,
                           'STORAGE_ID',   STORAGE_ID,
                           'BIN_ID',       BIN_ID,
                           'SEGMENT_NO',   SEGMENT_NO,
                           'SKU_ID',       P_SkuId,
                           'BATCH_ID',     P_BatchId,
                           'AllocatedQty', AllocatedQty
                       )
                   )
            INTO V_StorageJson
            FROM alloc1
            WHERE AllocatedQty > 0;

            
            SET V_AllocSum = 0;
            IF V_StorageJson IS NOT NULL THEN
                SELECT COALESCE(SUM(jt.AllocatedQty),0)
                  INTO V_AllocSum
                FROM JSON_TABLE(
                    V_StorageJson, '$[*]'
                    COLUMNS (AllocatedQty INT PATH '$.AllocatedQty')
                ) jt;
            END IF;

            IF V_AllocSum > V_PendingQty THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'PHASE1_OVER_ALLOCATION: JSON allocation exceeds pending qty';
            END IF;

            IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

                INSERT INTO order_bin_mapping (
                    BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
                )
                SELECT DISTINCT
                    jt.BIN_ID,
                    P_StationId,
                    'RACK_PICK',
                    'PENDING',
                    0,
                    NOW()
                FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
                LEFT JOIN order_bin_mapping obm_ok
                    ON  obm_ok.BIN_ID     = jt.BIN_ID
                    AND obm_ok.STATION_ID = P_StationId
                    AND obm_ok.TYPE       = 'RACK_PICK'
                    AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                WHERE obm_ok.ORDER_BIN_ID IS NULL;

                INSERT INTO put_wave_order_master (
                    PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                    ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
                )
                SELECT
                    UUID(),
                    P_StationId,
                    jt.WAVE_ID,
                    P_StorageRequestId,
                    jt.STORAGE_ID,
                    COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING',
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty
                FROM JSON_TABLE(
                        V_StorageJson,
                        '$[*]' COLUMNS (
                            WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                            STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                            BIN_ID       INT PATH '$.BIN_ID',
                            SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                            SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                            BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                            AllocatedQty INT PATH '$.AllocatedQty'
                        )
                     ) jt
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK'
                      AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                    GROUP BY BIN_ID, STATION_ID
                ) obm_reuse
                  ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                    GROUP BY BIN_ID, STATION_ID
                ) obm_new
                  ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
                WHERE jt.AllocatedQty > 0
                  AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master p
                      WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                        AND p.STORAGE_ID         = jt.STORAGE_ID
                        AND p.BIN_ID             = jt.BIN_ID
                        AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                        AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  );

                UPDATE live_inventory_master L
                INNER JOIN put_wave_order_master PWO
                    ON PWO.SKU_ID         = L.ARTICLE_ID
                   AND PWO.BATCH_ID       = L.BATCH_ID
                   AND PWO.BIN_ID         = L.BIN_ID
                   AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
                SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY
                WHERE L.ARTICLE_ID   = P_SkuId
                  AND L.BATCH_ID     = P_BatchId
                  AND PWO.STORAGE_ID = P_StorageId
                  AND PWO.STATUS     = 'PENDING';

            ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

                SELECT
                    UUID() AS PUT_ORDER_ID,
                    P_StationId AS STATION_ID,
                    jt.WAVE_ID,
                    P_StorageRequestId AS STORAGE_REQUEST_ID,
                    jt.STORAGE_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING' AS STATUS,
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty AS EXPECTED_QUANTITY
                FROM JSON_TABLE(
                    V_StorageJson,
                    '$[*]' COLUMNS (
                        WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                        BIN_ID       INT PATH '$.BIN_ID',
                        SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                        SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                        BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                        AllocatedQty INT PATH '$.AllocatedQty'
                    )
                ) jt
                WHERE jt.AllocatedQty > 0;

            END IF;

        END IF;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    INSERT INTO Tmp_StorageRequest (
        WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
    )
    SELECT
        PW.WAVE_ID,
        P_StorageRequestId,
        PW.STORAGE_ID,
        P_SkuId,
        P_BatchId,
        SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
        ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
    FROM (
        SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
        FROM put_wave_wms_data
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY STORAGE_ID, WAVE_ID
    ) PW
    LEFT JOIN (
        SELECT
            WAVE_ID,
            STORAGE_ID,
            SUM(
                CASE
                    WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                    ELSE EXPECTED_QUANTITY
                END
            ) AS EXPECTED_QUANTITY
        FROM put_wave_order_master
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY WAVE_ID, STORAGE_ID
    ) PWO
      ON PWO.STORAGE_ID = PW.STORAGE_ID
     AND PWO.WAVE_ID    = PW.WAVE_ID
    GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

    SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
    FROM Tmp_StorageRequest;

    
    IF V_PrefBinSegments = 1 THEN
        SET V_OneSegEarlyQuota =
            CASE
                WHEN V_PendingQty > GREATEST(V_CapPerSeg1, 1) THEN 1
                ELSE 999999
            END;
    ELSE
        SET V_OneSegEarlyQuota = 999999;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_A;
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_B;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_A LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_A SELECT * FROM Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_B LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_B SELECT * FROM Tmp_StorageRequest;

    IF V_PendingQty > 0 THEN

        SET V_TotalCandidates = LEAST(
            20000,
            GREATEST(
                3000,
                CEIL(V_PendingQty / GREATEST(1, V_PrefSegCap)) * 12
            )
        );

        WITH RECURSIVE
        ArticleWithProximity AS (
            SELECT
                AP.CHILD_ARTICLE_ID,
                ROW_NUMBER() OVER (
                    PARTITION BY AP.PARENT_ARTICLE_ID
                    ORDER BY AP.PROXIMITY_SCORE DESC
                ) AS rn
            FROM article_proximity_score AP
            WHERE AP.PARENT_ARTICLE_ID = P_SkuId
        ),
        FinalProximity AS (
            SELECT IFNULL(AWP.CHILD_ARTICLE_ID, P_SkuId) AS CHILD_ARTICLE_ID,
                   IFNULL(AWP.rn, 1) AS rn
            FROM (SELECT 1 AS dummy) D
            LEFT JOIN ArticleWithProximity AWP ON TRUE
        ),
        AisleCost AS (
            SELECT Aisle_Number, MIN(Cost) AS Cost
            FROM station_to_aisle_cost
            WHERE Station_ID = P_StationId
            GROUP BY Aisle_Number
        ),
        FreeBins AS (
            SELECT DISTINCT
                BIM.BIN_ID,
                BIM.BIN_SEGMENTS,
                COALESCE(AC.Cost, 9999) AS Cost,
                STBM.LOCATION_ID
            FROM bin_info_master BIM
            INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
            INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
            LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
            LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
            WHERE LBM.LOCATION_ID IS NULL
        ),
        LiveFree AS (
            SELECT
                L.BIN_ID,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                IFNULL(L.remark,'na') AS remark,
                FB.BIN_SEGMENTS,
                FB.Cost
            FROM live_inventory_master L
            INNER JOIN FreeBins FB ON FB.BIN_ID = L.BIN_ID
            WHERE IFNULL(L.remark,'na') = 'na'
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master P
                  WHERE P.BIN_ID         = L.BIN_ID
                    AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                    AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              )
        ),
        RankedBins AS (
            SELECT
                L.BIN_ID,
                L.Cost,
                L.BIN_SEGMENTS,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                SM.WEIGHT_OF_EACH_SKU,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                OBM.BOT_ID,
                SM.category,
                OBM.STATUS,
                OBM.TYPE,
                FP.rn,
                CASE
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.TYPE   = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED') THEN 1
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('BIN_PICKED','PRE_ON_STATION','ON_STATION') THEN 2
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 3
                    WHEN OBM.STATION_ID <> P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 4
                    ELSE 5
                END AS row_rank
            FROM LiveFree L
            INNER JOIN sku_master SM ON SM.SKU_ID = L.ARTICLE_ID
            LEFT JOIN FinalProximity FP ON L.ARTICLE_ID = FP.CHILD_ARTICLE_ID
            LEFT JOIN (
                SELECT BIN_ID, MAX(BOT_ID) AS BOT_ID, MAX(STATUS) AS STATUS, MAX(TYPE) AS TYPE, MAX(STATION_ID) AS STATION_ID
                FROM order_bin_mapping
                GROUP BY BIN_ID
            ) OBM ON OBM.BIN_ID = L.BIN_ID
        ),
        Tmp_Bins AS (
            SELECT
                CASE
                    WHEN LOCATE(CONCAT(',', RB.BIN_ID, ','), V_StoredSKUBinsList) > 0 THEN 100000
                    ELSE IFNULL(RB.rn, 1000)
                END AS rn,
                RB.row_rank,
                RB.BIN_ID,
                RB.Cost,
                RB.BIN_SEGMENTS,
                RB.SEGMENT_NO,
                RB.ARTICLE_ID AS SKU_ID,
                RB.BATCH_ID,
                CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS WEIGHT_OF_EACH_SKU,
                RB.QUANTITY,
                RB.VIRTUAL_QUANTITY_TO_PUT,
                (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS CurrentWeightInSegment,
                SUM(
                    (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END
                ) OVER (PARTITION BY RB.BIN_ID) AS CurrentWeightInBin,

                
                SUM(
                    CASE WHEN (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT)=0 THEN 1 ELSE 0 END
                ) OVER (PARTITION BY RB.BIN_ID) AS EmptySegments,
                SUM(
                    CASE
                        WHEN (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) > 0
                         AND RB.ARTICLE_ID <> 'no-sku'
                        THEN 1 ELSE 0
                    END
                ) OVER (PARTITION BY RB.BIN_ID) AS OccupiedSegments,

                BSR.RANKING
            FROM RankedBins RB
            INNER JOIN bin_segment_ranking BSR
                ON BSR.BIN_SEGMENT_COUNT = RB.BIN_SEGMENTS
               AND RB.SEGMENT_NO          = BSR.SEGMENT_ID
        ),
        SegCandidates AS (
            SELECT
                T.*,
                (V_MaxBinWeight - T.CurrentWeightInBin) AS BalanceWeightInBin,
                CASE
                    WHEN T.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                    WHEN T.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                    WHEN T.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                    WHEN T.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                    ELSE 0
                END AS QtyCapPerSegment
            FROM Tmp_Bins T
            WHERE (T.SKU_ID='no-sku' OR (T.QUANTITY + T.VIRTUAL_QUANTITY_TO_PUT)=0)
        ),
        ScoredCandidates AS (
            SELECT
                C.*,

                CASE
                    WHEN C.BIN_SEGMENTS=6 THEN V_need6
                    WHEN C.BIN_SEGMENTS=4 THEN V_need4
                    WHEN C.BIN_SEGMENTS=2 THEN V_need2
                    ELSE 1
                END AS PlanSegsForThisBinType,

                LEAST(
                    CASE
                        WHEN C.BIN_SEGMENTS=6 THEN V_need6
                        WHEN C.BIN_SEGMENTS=4 THEN V_need4
                        WHEN C.BIN_SEGMENTS=2 THEN V_need2
                        ELSE 1
                    END,
                    GREATEST(C.EmptySegments,1)
                ) AS AllowedSegsInThisBin,

                CASE
                    WHEN V_SkuUnitWeight <= 0 THEN 999999
                    ELSE FLOOR(
                        GREATEST(C.BalanceWeightInBin,0)
                        /
                        (V_SkuUnitWeight * LEAST(
                            CASE
                                WHEN C.BIN_SEGMENTS=6 THEN V_need6
                                WHEN C.BIN_SEGMENTS=4 THEN V_need4
                                WHEN C.BIN_SEGMENTS=2 THEN V_need2
                                ELSE 1
                            END,
                            GREATEST(C.EmptySegments,1)
                        ))
                    )
                END AS WeightCapPerSegment,

                CASE
                    WHEN V_PrefBinSegments=6 THEN
                        CASE WHEN C.BIN_SEGMENTS=6 THEN 1 WHEN C.BIN_SEGMENTS=4 THEN 2 WHEN C.BIN_SEGMENTS=2 THEN 3 WHEN C.BIN_SEGMENTS=1 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=4 THEN
                        CASE WHEN C.BIN_SEGMENTS=4 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=1 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=2 THEN
                        CASE WHEN C.BIN_SEGMENTS=2 THEN 1 WHEN C.BIN_SEGMENTS=1 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    ELSE
                        CASE WHEN C.BIN_SEGMENTS=1 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                END AS BinTypeRank

            FROM SegCandidates C
            WHERE C.QtyCapPerSegment > 0
              AND C.BalanceWeightInBin > 0
        ),
        CapacityFinal AS (
            SELECT
                S.*,
                LEAST(S.QtyCapPerSegment, S.WeightCapPerSegment) AS SegmentCapacity
            FROM ScoredCandidates S
        ),
        PickSegments AS (
            SELECT
                X.*,
                ROW_NUMBER() OVER (
                    PARTITION BY X.BIN_ID
                    ORDER BY X.RANKING, X.SEGMENT_NO
                ) AS rn_in_bin
            FROM CapacityFinal X
            WHERE X.SegmentCapacity > 0
        ),

        

        BinAgg AS (
            SELECT
                PS.BIN_ID,
                MIN(PS.rn)          AS rn,
                MIN(PS.row_rank)    AS row_rank,
                MIN(PS.Cost)        AS Cost,
                MIN(PS.BIN_SEGMENTS) AS BIN_SEGMENTS,
                MAX(PS.OccupiedSegments) AS OccupiedSegments,
                MAX(PS.EmptySegments)    AS EmptySegments,
                MIN(PS.BinTypeRank)      AS BinTypeRank,
                MIN(PS.AllowedSegsInThisBin) AS AllowedSegsInThisBin,

                ROW_NUMBER() OVER (
                    PARTITION BY MIN(PS.BIN_SEGMENTS)
                    ORDER BY MIN(PS.rn), MIN(PS.row_rank), MIN(PS.Cost), PS.BIN_ID
                ) AS TypeSeqInType
            FROM PickSegments PS
            WHERE PS.rn_in_bin <= PS.AllowedSegsInThisBin
            GROUP BY PS.BIN_ID
        ),
        BinRanked AS (
            SELECT
                BA.*,
                CASE
                    WHEN V_PrefBinSegments = 1
                     AND BA.BIN_SEGMENTS   = 1
                     AND BA.TypeSeqInType  > V_OneSegEarlyQuota
                    THEN 5
                    ELSE BA.BinTypeRank
                END AS EffBinTypeRank,

                ROW_NUMBER() OVER (
                    ORDER BY
                        CASE
                            WHEN V_PrefBinSegments = 1
                             AND BA.BIN_SEGMENTS   = 1
                             AND BA.TypeSeqInType  > V_OneSegEarlyQuota
                            THEN 5
                            ELSE BA.BinTypeRank
                        END,

                        
                        BA.OccupiedSegments DESC,
                        BA.EmptySegments    DESC,

                        BA.rn,
                        BA.row_rank,
                        BA.Cost,
                        BA.BIN_ID
                ) AS BinRank
            FROM BinAgg BA
        ),
        SegmentsInBinOrder AS (
            SELECT
                PS.*,
                BR.BinRank
            FROM PickSegments PS
            JOIN BinRanked BR ON BR.BIN_ID = PS.BIN_ID
            WHERE PS.rn_in_bin <= PS.AllowedSegsInThisBin
        ),
        BinswithLowcost AS (
            SELECT
                S.*,
                ROW_NUMBER() OVER (
                    ORDER BY
                        S.BinRank,
                        S.RANKING,
                        S.SEGMENT_NO
                ) AS bin_index
            FROM SegmentsInBinOrder S
            LIMIT V_TotalCandidates
        ),

        alloc AS (
            SELECT
                ob.BIN_ID,
                ob.SEGMENT_NO,
                ob.SegmentCapacity,
                sr.STORAGE_ID,
                sr.WAVE_ID,
                CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS AllocatedQty,
                sr.RequestQty - CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS RemQty,
                ob.bin_index,
                sr.req_index
            FROM BinswithLowcost ob
            JOIN Tmp_StorageRequest_A sr
              ON sr.req_index = 1
             AND ob.bin_index = 1
            WHERE sr.RequestQty > 0

            UNION ALL

            SELECT
                b.BIN_ID,
                b.SEGMENT_NO,
                b.SegmentCapacity,
                CASE WHEN a.RemQty = 0 THEN s2.STORAGE_ID ELSE a.STORAGE_ID END,
                CASE WHEN a.RemQty = 0 THEN s2.WAVE_ID    ELSE a.WAVE_ID    END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        s2.RequestQty - CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                b.bin_index,
                CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
            FROM BinswithLowcost b
            JOIN alloc a
              ON b.bin_index = a.bin_index + 1
            LEFT JOIN Tmp_StorageRequest_B s2
              ON s2.req_index = a.req_index + 1
            WHERE (a.RemQty > 0) OR (s2.req_index IS NOT NULL AND s2.RequestQty > 0)
        )
        SELECT JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'WAVE_ID',      WAVE_ID,
                       'STORAGE_ID',   STORAGE_ID,
                       'BIN_ID',       BIN_ID,
                       'SEGMENT_NO',   SEGMENT_NO,
                       'SKU_ID',       P_SkuId,
                       'BATCH_ID',     P_BatchId,
                       'AllocatedQty', AllocatedQty
                   )
               )
        INTO V_StorageJson
        FROM alloc
        WHERE AllocatedQty > 0;

        
        SET V_AllocSum = 0;
        IF V_StorageJson IS NOT NULL THEN
            SELECT COALESCE(SUM(jt.AllocatedQty),0)
              INTO V_AllocSum
            FROM JSON_TABLE(
                V_StorageJson, '$[*]'
                COLUMNS (AllocatedQty INT PATH '$.AllocatedQty')
            ) jt;
        END IF;

        IF V_AllocSum > V_PendingQty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PHASE2_OVER_ALLOCATION: JSON allocation exceeds pending qty';
        END IF;

        IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

            INSERT INTO order_bin_mapping (
                BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
            )
            SELECT DISTINCT
                jt.BIN_ID,
                P_StationId,
                'RACK_PICK',
                'PENDING',
                0,
                NOW()
            FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
            LEFT JOIN order_bin_mapping obm_ok
                ON  obm_ok.BIN_ID     = jt.BIN_ID
                AND obm_ok.STATION_ID = P_StationId
                AND obm_ok.TYPE       = 'RACK_PICK'
                AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
            WHERE obm_ok.ORDER_BIN_ID IS NULL;

            INSERT INTO put_wave_order_master (
                PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
            )
            SELECT
                UUID(),
                P_StationId,
                jt.WAVE_ID,
                P_StorageRequestId,
                jt.STORAGE_ID,
                COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING',
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK'
                  AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                GROUP BY BIN_ID, STATION_ID
            ) obm_reuse
              ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                GROUP BY BIN_ID, STATION_ID
            ) obm_new
              ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
            WHERE jt.AllocatedQty > 0
              AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master p
                  WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                    AND p.STORAGE_ID         = jt.STORAGE_ID
                    AND p.BIN_ID             = jt.BIN_ID
                    AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                    AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              );

            UPDATE live_inventory_master L
            INNER JOIN put_wave_order_master PWO
                ON PWO.BIN_ID         = L.BIN_ID
               AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
            SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY,
                L.ARTICLE_ID              = PWO.SKU_ID,
                L.BATCH_ID                = PWO.BATCH_ID
            WHERE (L.ARTICLE_ID = 'no-sku' OR (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT)=0)
              AND PWO.STORAGE_ID = P_StorageId
              AND PWO.STATUS     = 'PENDING';

        ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

            SELECT
                UUID()             AS PUT_ORDER_ID,
                P_StationId        AS STATION_ID,
                jt.WAVE_ID         AS WAVE_ID,
                P_StorageRequestId AS STORAGE_REQUEST_ID,
                jt.STORAGE_ID,
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING'          AS STATUS,
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty    AS EXPECTED_QUANTITY
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            WHERE jt.AllocatedQty > 0;

        END IF;

    END IF;

    
    IF P_ForProcessing = 1 THEN

        SELECT COALESCE(SUM(QUANTITY),0)
        INTO   v_wms_data_total_qty
        FROM   put_wave_wms_data
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        SELECT COALESCE(
                   SUM(
                       CASE
                           WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                           ELSE EXPECTED_QUANTITY
                       END
                   ),
                   0
               )
        INTO   v_order_master_total_expected
        FROM   put_wave_order_master
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        IF v_order_master_total_expected > v_wms_data_total_qty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'OVER_ALLOCATION: expected exceeds WMS qty';
        END IF;

        SET V_left_over_calc = v_wms_data_total_qty - v_order_master_total_expected;

        UPDATE put_wave_wms_data PW
        SET    PW.STATUS    = 'COMPLETED',
               PW.LEFT_OVER = V_left_over_calc
        WHERE  PW.SKU_ID             = P_SkuId
          AND  PW.BATCH_ID           = P_BatchId
          AND  PW.STATUS             = 'PENDING'
          AND  PW.STORAGE_REQUEST_ID = P_StorageRequestId
          AND  PW.STORAGE_ID         = P_StorageId;

        COMMIT;
    END IF;

    SET SESSION cte_max_recursion_depth = 1000;

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPending_Order_allocation_V3_without_ROS` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPending_Order_allocation_V3_without_ROS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPending_Order_allocation_V3_without_ROS`(
    IN P_StorageRequestId VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StorageId        VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_SkuId            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_BatchId          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StationId        INT,
    IN P_ForProcessing    INT          
)
BEGIN
    
    DECLARE V_StorageJson                 JSON;
    DECLARE V_StoredSKUBinsList           TEXT;
    DECLARE V_PendingQty                  INT;
    DECLARE V_RowsInserted                INT;
    DECLARE V_MaxBinWeight                INT;
    DECLARE V_MaxBinQty                   INT;
    DECLARE V_SkuUnitWeight               INT;
    DECLARE V_MinSegmentSize              INT;
    DECLARE V_SkuCategory                 INT;
    DECLARE V_TotalBinRequired            INT;
    DECLARE v_wms_data_total_qty          INT DEFAULT 0;
    DECLARE v_order_master_total_expected INT DEFAULT 0;
    DECLARE V_left_over_calc              INT DEFAULT 0;

    
    
    

    
    SELECT KEY_VALUE
    INTO   V_MaxBinWeight
    FROM   master_config
    WHERE  KEY_NAME = 'MAX_WEIGHT_ALLOWED_ON_BOT_GRAMS';

    
    SET SESSION cte_max_recursion_depth = 10000;

    
    SELECT MAX_QUANTITY_PER_SEGMENT,
           WEIGHT_OF_EACH_SKU,
           MIN_SEGMENT_SIZE,
           category
    INTO   V_MaxBinQty,
           V_SkuUnitWeight,
           V_MinSegmentSize,
           V_SkuCategory
    FROM   sku_master
    WHERE  SKU_ID = P_SkuId;

    
    
    
    
    SELECT GROUP_CONCAT(BIN_ID)
    INTO   V_StoredSKUBinsList
    FROM (
        SELECT DISTINCT BIN_ID
        FROM   live_inventory_master
        WHERE  ARTICLE_ID = P_SkuId
          AND  BATCH_ID   = P_BatchId
    ) b;

    
    SET V_StoredSKUBinsList = CONCAT(',', V_StoredSKUBinsList, ',');

    
    
    
    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold;
    DROP TEMPORARY TABLE IF EXISTS Tmp_Binsold;

    CREATE TEMPORARY TABLE Tmp_StorageRequestold (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,   
        PRIMARY KEY (ID),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    
    CREATE TEMPORARY TABLE Tmp_Binsold (
        ID                     INT AUTO_INCREMENT NOT NULL,
        BIN_ID                 INT,
        BIN_SEGMENTS           INT,
        SEGMENT_NO             INT,
        SKU_ID                 VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID               VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        WEIGHT_OF_EACH_SKU     INT,
        QUANTITY               INT,
        VIRTUAL_QUANTITY_TO_PUT INT,
        CurrentWeightInSegment INT,
        CurrentBinLocation     VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        PRIMARY KEY (ID),
        INDEX (BIN_ID),
        INDEX (BIN_SEGMENTS),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    
    IF EXISTS (
        SELECT 1
        FROM   live_inventory_master L
        WHERE  L.ARTICLE_ID = P_SkuId
          AND  L.BATCH_ID   = P_BatchId
    ) THEN

        
        
        
        
        INSERT INTO Tmp_StorageRequestold (
            WAVE_ID,
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            SKU_ID,
            BATCH_ID,
            RequestQty
        )
        SELECT
            PW.WAVE_ID,
            P_StorageRequestId AS STORAGE_REQUEST_ID,
            PW.STORAGE_ID,
            P_SkuId            AS SKU_ID,
            P_BatchId          AS BATCH_ID,
            SUM(
                GREATEST(
                    PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0),
                    0
                )
            )                   AS RequestQty
        FROM (
            SELECT
                WAVE_ID,
                STORAGE_ID,
                SUM(QUANTITY) AS QUANTITY
            FROM put_wave_wms_data
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PW
        LEFT JOIN (
            SELECT
                WAVE_ID,
                STORAGE_ID,
                SUM(
                    CASE
                        WHEN STATUS = 'PUT_COMPLETED'
                            THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                        ELSE EXPECTED_QUANTITY
                    END
                ) AS EXPECTED_QUANTITY
            FROM put_wave_order_master
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PWO
          ON PWO.STORAGE_ID = PW.STORAGE_ID
         AND PWO.WAVE_ID    = PW.WAVE_ID
        WHERE PW.QUANTITY > 0
        GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

        
        SELECT SUM(RequestQty)
        INTO   V_PendingQty
        FROM   Tmp_StorageRequestold;

        IF IFNULL(V_PendingQty, 0) > 0 THEN

            
            
            
            
            WITH
            Tmp_LowCostAislesforStation AS (
                SELECT
                    MIN(Cost) AS Cost,
                    Aisle_Number
                FROM station_to_aisle_cost SAC
                WHERE SAC.Station_ID = P_StationId
                GROUP BY Aisle_Number
            ),
            Bins AS (
                SELECT
                    A.*,
                    (A.SegmentCapacity - A.QtyinSegment)                                     AS BalanceSegmentCapacity,
                    SUM(A.SegmentCapacity - A.QtyinSegment)
                        OVER (
                            ORDER BY A.BIN_SEGMENTS DESC,
                                     A.BIN_ID,
                                     A.segment_no DESC
                        )                                                                  AS RunningTotalBalanceToPut
                FROM (
                    SELECT DISTINCT
                        A.*,
                        BIM.BIN_SEGMENTS,
                        SAC.Cost,
                         ROW_NUMBER() OVER (
                        PARTITION BY A.BIN_ID
                        ORDER BY A.SEGMENT_NO           
                    ) AS rn_seg
                    FROM (
                        
                        
                        SELECT
                            LB.BIN_ID,
                            LB.SEGMENT_NO,
                            LB.ARTICLE_ID,
                            LB.BATCH_ID,
                            (LB.QUANTITY + LB.VIRTUAL_QUANTITY_TO_PUT)                     AS QtyinSegment,
                            (LB.QUANTITY + LB.VIRTUAL_QUANTITY_TO_PUT) * S.WEIGHT_OF_EACH_SKU
                                                                                           AS CurrentWeightInSegment,
                            SUM(
                                (LB.QUANTITY + LB.VIRTUAL_QUANTITY_TO_PUT)
                                * SB.WEIGHT_OF_EACH_SKU
                            ) OVER (PARTITION BY LB.BIN_ID)                                AS CurrentWeightInBin,
                            SB.MIN_SEGMENT_SIZE,
                            FLOOR(SB.MAX_QUANTITY_PER_SEGMENT / SB.MIN_SEGMENT_SIZE)       AS SegmentCapacity
                        FROM live_inventory_master L
                        INNER JOIN sku_master S
                            ON S.SKU_ID = L.ARTICLE_ID
                        INNER JOIN live_inventory_master LB
                            ON LB.BIN_ID = L.BIN_ID
                        INNER JOIN sku_master SB
                            ON SB.SKU_ID = LB.ARTICLE_ID
                        WHERE L.ARTICLE_ID = P_SkuId
                          AND L.BATCH_ID   = P_BatchId
                          AND IFNULL(LB.remark,'na') NOT IN ('no_space', 'audit_marked')
                    ) A
                    INNER JOIN bin_info_master BIM
                        ON BIM.BIN_ID = A.BIN_ID
                    INNER JOIN store_bin_master STBM
                        ON STBM.BIN_ID = BIM.BIN_ID
                    INNER JOIN location_master lm
                        ON lm.LOCATION_ID = STBM.LOCATION_ID
                    INNER JOIN Tmp_LowCostAislesforStation SAC
                        ON SAC.Aisle_Number = IFNULL(lm.aisle_number, 'A01')
                    LEFT JOIN order_bin_mapping OBM
                        ON OBM.BIN_ID     = A.BIN_ID
                       AND OBM.STATION_ID = P_StationId
                    LEFT JOIN location_block_master LBM
                        ON LBM.LOCATION_ID = STBM.LOCATION_ID
                    WHERE A.CurrentWeightInBin < V_MaxBinWeight
                      AND (A.SegmentCapacity - A.QtyinSegment) > 0
                      AND A.ARTICLE_ID = P_SkuId
                      AND A.BATCH_ID   = P_BatchId
                      AND LBM.LOCATION_ID IS NULL                     
                    ORDER BY
                        (A.SegmentCapacity - A.QtyinSegment) DESC,
                        BIM.BIN_SEGMENTS DESC,
                        A.BIN_ID,
                        A.segment_no DESC,
                        SAC.Cost
                ) A
                 WHERE A.rn_seg = 1
                ORDER BY
                    A.BIN_SEGMENTS DESC,
                    A.BIN_ID,
                    A.segment_no DESC
            ),
            Alloc AS (
                
                
                SELECT
                    S.WAVE_ID,
                    S.STORAGE_ID,
                    B.BIN_ID,
                    B.SEGMENT_NO,
                    B.BalanceSegmentCapacity,
                    SUM(B.BalanceSegmentCapacity)
                        OVER (ORDER BY B.BIN_ID, B.SEGMENT_NO)  AS RunningTotalQty,
                    CASE
                        WHEN B.RunningTotalBalanceToPut <= V_PendingQty
                            THEN B.BalanceSegmentCapacity
                        WHEN B.RunningTotalBalanceToPut - B.BalanceSegmentCapacity < V_PendingQty
                            THEN V_PendingQty - (B.RunningTotalBalanceToPut - B.BalanceSegmentCapacity)
                        ELSE 0
                    END AS AllocatedQty
                FROM Bins B
                INNER JOIN Tmp_StorageRequestold S
                    ON S.SKU_ID  = B.ARTICLE_ID
                   AND S.BATCH_ID = B.BATCH_ID
                CROSS JOIN (
                    SELECT @remaining := 0, @allocated := 0, @prev_storage := ''
                ) vars
                WHERE B.RunningTotalBalanceToPut - B.BalanceSegmentCapacity < V_PendingQty
                ORDER BY S.STORAGE_ID, B.SEGMENT_NO DESC
            )
            SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'WAVE_ID',      WAVE_ID,
                           'STORAGE_ID',   STORAGE_ID,
                           'BIN_ID',       BIN_ID,
                           'SEGMENT_NO',   SEGMENT_NO,
                           'SKU_ID',       P_SkuId,
                           'BATCH_ID',     P_BatchId,
                           'AllocatedQty', AllocatedQty
                       )
                   )
            INTO V_StorageJson
            FROM Alloc
            WHERE AllocatedQty > 0
            ORDER BY SEGMENT_NO, BIN_ID;

            
            
            
            
            
            
            IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

                
                INSERT INTO order_bin_mapping (
                    BIN_ID,
                    STATION_ID,
                    TYPE,
                    STATUS,
                    IS_SYNCED,
                    INSERTED_TIMESTAMP
                )
                SELECT DISTINCT
                    jt.BIN_ID,
                    P_StationId,
                    'RACK_PICK',
                    'PENDING',
                    0,
                    NOW()
                FROM JSON_TABLE(
                        V_StorageJson,
                        '$[*]' COLUMNS (
                            BIN_ID INT PATH '$.BIN_ID'
                        )
                     ) jt
                     
                    LEFT JOIN order_bin_mapping obm_ok
		    ON  obm_ok.BIN_ID     = jt.BIN_ID
		    AND obm_ok.STATION_ID = P_StationId
		    AND obm_ok.TYPE       = 'RACK_PICK'
		    AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
		WHERE obm_ok.ORDER_BIN_ID IS NULL;
		

  
    
      

                
                INSERT INTO put_wave_order_master (
                    PUT_ORDER_ID,
                    STATION_ID,
                    WAVE_ID,
                    STORAGE_REQUEST_ID,
                    STORAGE_ID,
                    ORDER_BIN_ID,
                    BIN_ID,
                    BIN_SEGMENT_NO,
                    STATUS,
                    SKU_ID,
                    BATCH_ID,
                    EXPECTED_QUANTITY
                )
                SELECT
                    UUID(),
                    P_StationId,
                    jt.WAVE_ID,
                    P_StorageRequestId,
                    jt.STORAGE_ID,
                    COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) AS ORDER_BIN_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING',
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty
                FROM JSON_TABLE(
                        V_StorageJson,
                        '$[*]' COLUMNS (
                            WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                            STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                            BIN_ID       INT PATH '$.BIN_ID',
                            SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                            SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                            BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                            AllocatedQty INT PATH '$.AllocatedQty'
                        )
                     ) jt
                     
                     		
		LEFT JOIN (
		    SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
		    FROM order_bin_mapping
		    WHERE TYPE='RACK_PICK'
		      AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
		    GROUP BY BIN_ID, STATION_ID
		) obm_reuse
		  ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId

		
		LEFT JOIN (
		    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
		    FROM order_bin_mapping
		    WHERE TYPE='RACK_PICK'
		      AND STATUS='PENDING'
		    GROUP BY BIN_ID, STATION_ID
		) obm_new
		  ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId

		WHERE jt.AllocatedQty > 0
  AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL;
              

                SELECT ROW_COUNT()
                INTO   V_RowsInserted;

                
                IF V_RowsInserted > 0 THEN
                    UPDATE live_inventory_master L
                    INNER JOIN put_wave_order_master PWO
                        ON PWO.SKU_ID       = L.ARTICLE_ID
                       AND PWO.BATCH_ID     = L.BATCH_ID
                       AND L.BIN_ID         = PWO.BIN_ID
                       AND L.SEGMENT_NO     = PWO.BIN_SEGMENT_NO
                    SET L.VIRTUAL_QUANTITY_TO_PUT =
                            L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY
                    WHERE L.ARTICLE_ID  = P_SkuId
                      AND L.BATCH_ID    = P_BatchId
                      AND PWO.STORAGE_ID = P_StorageId
                      AND PWO.STATUS     = 'PENDING';
                END IF;

            ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN
                
                SELECT
                    UUID()             AS PUT_ORDER_ID,
                    P_StationId        AS STATION_ID,
                    jt.WAVE_ID         AS WAVE_ID,
                    P_StorageRequestId AS STORAGE_REQUEST_ID,
                    jt.STORAGE_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING'          AS STATUS,
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty    AS EXPECTED_QUANTITY
                FROM JSON_TABLE(
                        V_StorageJson,
                        '$[*]' COLUMNS (
                            WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                            STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                            BIN_ID       INT PATH '$.BIN_ID',
                            SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                            SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                            BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                            AllocatedQty INT PATH '$.AllocatedQty'
                        )
                     ) jt
                WHERE jt.AllocatedQty > 0
                ORDER BY jt.SKU_ID, jt.BATCH_ID;
            END IF;
        END IF;
    END IF;  

    
    
    
    
    
    
    
    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    
    INSERT INTO Tmp_StorageRequest (
        WAVE_ID,
        STORAGE_REQUEST_ID,
        STORAGE_ID,
        SKU_ID,
        BATCH_ID,
        RequestQty,
        req_index
    )
    SELECT
        PW.WAVE_ID,
        P_StorageRequestId AS STORAGE_REQUEST_ID,
        PW.STORAGE_ID,
        P_SkuId            AS SKU_ID,
        P_BatchId          AS BATCH_ID,
        SUM(
            GREATEST(
                PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0),
                0
            )
        )                   AS RequestQty,
        ROW_NUMBER() OVER () AS req_index
    FROM (
        SELECT
            WAVE_ID,
            STORAGE_ID,
            SUM(QUANTITY) AS QUANTITY
        FROM put_wave_wms_data
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY STORAGE_ID, WAVE_ID
    ) PW
    LEFT JOIN (
        SELECT
            WAVE_ID,
            STORAGE_ID,
            SUM(
                CASE
                    WHEN STATUS = 'PUT_COMPLETED'
                        THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                    ELSE EXPECTED_QUANTITY
                END
            ) AS EXPECTED_QUANTITY
        FROM put_wave_order_master
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY WAVE_ID, STORAGE_ID
    ) PWO
      ON PWO.STORAGE_ID = PW.STORAGE_ID
     AND PWO.WAVE_ID    = PW.WAVE_ID
    GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

    SELECT SUM(RequestQty)
    INTO   V_PendingQty
    FROM   Tmp_StorageRequest;

    IF IFNULL(V_PendingQty, 0) > 0 THEN

        
        SET V_TotalBinRequired = CEIL(
            V_PendingQty / FLOOR(V_MaxBinQty / V_MinSegmentSize)
        )*3;

        WITH RECURSIVE
        StorageRequest AS (
            
            SELECT
                PW.WAVE_ID,
                PW.STORAGE_ID,
                P_SkuId  AS SKU_ID,
                P_BatchId AS BATCH_ID,
                SUM(
                    GREATEST(
                        PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0),
                        0
                    )
                )           AS RequestQty,
                ROW_NUMBER() OVER () AS req_index
            FROM (
                SELECT
                    WAVE_ID,
                    STORAGE_ID,
                    SUM(QUANTITY) AS QUANTITY
                FROM put_wave_wms_data
                WHERE SKU_ID             = P_SkuId
                  AND BATCH_ID           = P_BatchId
                  AND STORAGE_REQUEST_ID = P_StorageRequestId
                  AND STORAGE_ID         = P_StorageId
                GROUP BY STORAGE_ID, WAVE_ID
            ) PW
            LEFT JOIN (
                SELECT
                    WAVE_ID,
                    STORAGE_ID,
                    SUM(
                        CASE
                            WHEN STATUS = 'PUT_COMPLETED'
                                THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                            ELSE EXPECTED_QUANTITY
                        END
                    ) AS EXPECTED_QUANTITY
                FROM put_wave_order_master
                WHERE SKU_ID             = P_SkuId
                  AND BATCH_ID           = P_BatchId
                  AND STORAGE_REQUEST_ID = P_StorageRequestId
                  AND STORAGE_ID         = P_StorageId
                GROUP BY WAVE_ID, STORAGE_ID
            ) PWO
              ON PWO.STORAGE_ID = PW.STORAGE_ID
             AND PWO.WAVE_ID    = PW.WAVE_ID
            GROUP BY PW.WAVE_ID, PW.STORAGE_ID
        ),
        ArticleWithProximity AS (
            
            SELECT
                AP.CHILD_ARTICLE_ID,
                ROW_NUMBER() OVER (
                    PARTITION BY AP.PARENT_ARTICLE_ID
                    ORDER BY AP.PROXIMITY_SCORE DESC
                ) AS rn,
                P_SkuId  AS SKU_ID,
                P_BatchId AS BATCH_ID
            FROM article_proximity_score AP
            WHERE AP.PARENT_ARTICLE_ID = P_SkuId
        ),
        FinalProximity AS (
            
            SELECT
                IFNULL(AWP.CHILD_ARTICLE_ID, P_SkuId) AS CHILD_ARTICLE_ID,
                IFNULL(AWP.rn, 1)                     AS rn,
                P_SkuId                               AS SKU_ID,
                P_BatchId                             AS BATCH_ID
            FROM (SELECT 1 AS dummy) D
            LEFT JOIN ArticleWithProximity AWP
                   ON TRUE
        ),
        Tmp_LowCostAislesforStation AS (
            
            SELECT
                MIN(Cost) AS Cost,
                Aisle_Number
            FROM station_to_aisle_cost SAC
            WHERE SAC.Station_ID = P_StationId
            GROUP BY Aisle_Number
        ),
        Tmp_FreeBins AS (
            
            SELECT DISTINCT
                BIM.BIN_ID,
                SAC.Cost,
                BIM.BIN_SEGMENTS,
                LBM.LOCATION_ID
            FROM bin_info_master BIM
            INNER JOIN store_bin_master STBM
                ON STBM.BIN_ID = BIM.BIN_ID
            INNER JOIN location_master lm
                ON lm.LOCATION_ID = STBM.LOCATION_ID
            INNER JOIN Tmp_LowCostAislesforStation SAC
                ON SAC.Aisle_Number = IFNULL(lm.aisle_number, 'A01')
            LEFT JOIN location_block_master LBM
                ON LBM.LOCATION_ID = STBM.LOCATION_ID
            WHERE LBM.LOCATION_ID IS NULL
        ),
        Tmp_live_inventory_master AS (
            
            SELECT
                L.BIN_ID,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                IFNULL(L.remark,'na') AS remark,
                TB.BIN_SEGMENTS,
                TB.Cost
            FROM live_inventory_master L
            INNER JOIN Tmp_FreeBins TB
                ON TB.BIN_ID = L.BIN_ID
            WHERE IFNULL(L.remark,'na') = 'na'
            AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master P
                  WHERE P.BIN_ID         = L.BIN_ID
                    AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                    AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              )
        ),
        RankedBins AS (
            
            
            
            SELECT
                L.BIN_ID,
                L.Cost,
                L.BIN_SEGMENTS,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                SM.WEIGHT_OF_EACH_SKU,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                OBM.BOT_ID,
                SM.category,
                OBM.STATUS,
                OBM.TYPE,
                FP.rn,
                CASE
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.TYPE   = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED')
                        THEN 1
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('BIN_PICKED','PRE_ON_STATION','ON_STATION')
                        THEN 2
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED')
                        THEN 3
                    WHEN OBM.STATION_ID <> P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED')
                        THEN 4
                    ELSE 5
                END AS row_rank
            FROM Tmp_live_inventory_master L
            INNER JOIN sku_master SM
                ON SM.SKU_ID = L.ARTICLE_ID
            LEFT JOIN FinalProximity FP
                ON L.ARTICLE_ID = FP.CHILD_ARTICLE_ID
            LEFT JOIN order_bin_mapping OBM
                ON OBM.BIN_ID = L.BIN_ID
        ),
        Tmp_Bins AS (
            
            
            SELECT
                A.rn,
                A.BIN_ID,
                A.Cost,
                A.BIN_SEGMENTS,
                A.SEGMENT_NO,
                A.SKU_ID,
                A.BATCH_ID,
                A.WEIGHT_OF_EACH_SKU,
                A.QUANTITY,
                A.VIRTUAL_QUANTITY_TO_PUT,
                A.CurrentWeightInSegment,
                A.CurrentBinLocation,
                A.category,
                A.CurrentWeightInBin,
                BSR.RANKING
            FROM (
                SELECT
		    CASE
                    WHEN V_StoredSKUBinsList IS NOT NULL
                         AND LOCATE(CONCAT(',', L.BIN_ID, ','), V_StoredSKUBinsList) > 0
                        THEN 100000
                    ELSE IFNULL(L.rn, 1000)
                    END AS rn,
                   
                    L.row_rank,
                    L.BIN_ID,
                    L.Cost,
                    L.BIN_SEGMENTS,
                    L.SEGMENT_NO,
                    L.ARTICLE_ID AS SKU_ID,
                    L.BATCH_ID,
                    CASE
                        WHEN L.ARTICLE_ID = 'no-sku' THEN 0
                        ELSE L.WEIGHT_OF_EACH_SKU
                    END                      AS WEIGHT_OF_EACH_SKU,
                    L.QUANTITY,
                    L.VIRTUAL_QUANTITY_TO_PUT,
                    (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT)
                        * CASE
                              WHEN L.ARTICLE_ID = 'no-sku' THEN 0
                              ELSE L.WEIGHT_OF_EACH_SKU
                          END               AS CurrentWeightInSegment,
                    SUM(
                        (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT)
                        * CASE
                              WHEN L.ARTICLE_ID = 'no-sku' THEN 0
                              ELSE L.WEIGHT_OF_EACH_SKU
                          END
                    ) OVER (PARTITION BY L.BIN_ID)
                                           AS CurrentWeightInBin,
                    CASE
                        WHEN L.BOT_ID IS NOT NULL THEN 'BINALLOCATEDTOBOT'
                        WHEN L.BOT_ID IS NULL
                             AND L.STATUS NOT IN ('ON_STATION','OPERATION_COMPLETED')
                             AND L.TYPE   NOT IN ('STATION_PICK')
                            THEN 'BININQUEUE'
                        ELSE 'BINFROMRACK'
                    END                      AS CurrentBinLocation,
                    L.category
                FROM RankedBins L
            ) A
            INNER JOIN bin_segment_ranking BSR
                ON BSR.BIN_SEGMENT_COUNT = A.BIN_SEGMENTS
               AND A.SEGMENT_NO          = BSR.SEGMENT_ID
            ORDER BY
                A.rn,
                A.BIN_SEGMENTS DESC,
                A.row_rank,
                A.Cost,
                A.BIN_ID,                
                BSR.RANKING         
        ),
        BinswithLowcost AS (
            
            
            
            
            SELECT
                A.*,
                SUM(SegmentCapacity)
                    OVER (
                        ORDER BY A.BIN_SEGMENTS DESC,
                                 A.BIN_ID,
                                 A.RANKING
                    )            AS RunningTotalBalanceToPut,
                ROW_NUMBER() OVER () AS bin_index
            FROM (
                SELECT
                    A.*,
                    ROW_NUMBER() OVER (
                        PARTITION BY A.BIN_ID
                        ORDER BY A.RANKING, A.BIN_ID
                    ) AS rn_seg
                FROM (
                    SELECT
                        A.*,
                        (V_MaxBinWeight - CurrentWeightInBin) AS BalanceWeightinBin,
                        SUM(
                            CASE
                                WHEN (A.QUANTITY + A.VIRTUAL_QUANTITY_TO_PUT) = 0
                                    THEN 1
                                ELSE 0
                            END
                        ) OVER (PARTITION BY A.BIN_ID)        AS EmptySegments,
                        CASE
                            WHEN (A.QUANTITY + A.VIRTUAL_QUANTITY_TO_PUT) > 0
                                THEN 0
                            ELSE LEAST(
                                FLOOR(V_MaxBinQty / A.BIN_SEGMENTS),
                                FLOOR(
                                    (V_MaxBinWeight - SUM(CurrentWeightInSegment)
                                         OVER (PARTITION BY A.BIN_ID))
                                    / (
                                        SUM(
                                            CASE
                                                WHEN (A.QUANTITY + A.VIRTUAL_QUANTITY_TO_PUT) = 0
                                                    THEN 1
                                                ELSE 0
                                            END
                                        ) OVER (PARTITION BY A.BIN_ID) * V_SkuUnitWeight
                                      )
                                )
                            )
                        END AS SegmentCapacity
                    FROM Tmp_Bins A
                ) A
                WHERE A.BalanceWeightinBin > 0
                  AND (A.SKU_ID = 'no-sku'
                       OR (A.QUANTITY + A.VIRTUAL_QUANTITY_TO_PUT) = 0)
            ) A
            WHERE A.SegmentCapacity > 0
            AND A.rn_seg = 1 
            LIMIT V_TotalBinRequired
        ),
        alloc AS (
            
            SELECT
                ob.BIN_ID,
                ob.SEGMENT_NO,
                ob.SegmentCapacity,
                os.STORAGE_ID,
                os.SKU_ID,
                os.BATCH_ID,
                os.WAVE_ID,
                CASE
                    WHEN os.RequestQty >= ob.SegmentCapacity
                        THEN ob.SegmentCapacity
                    ELSE os.RequestQty
                END AS AllocatedQty,
                os.RequestQty - CASE
                    WHEN os.RequestQty >= ob.SegmentCapacity
                        THEN ob.SegmentCapacity
                    ELSE os.RequestQty
                END AS RemQty,
                ob.bin_index,
                os.req_index
            FROM BinswithLowcost ob
            JOIN StorageRequest os
              ON os.req_index = 1
             AND ob.bin_index = 1

            UNION ALL

            SELECT
                b.BIN_ID,
                b.SEGMENT_NO,
                b.SegmentCapacity,
                CASE
                    WHEN AL.RemQty = 0 THEN s.STORAGE_ID
                    ELSE AL.STORAGE_ID
                END AS STORAGE_ID,
                CASE
                    WHEN AL.RemQty = 0 THEN s.SKU_ID
                    ELSE AL.SKU_ID
                END AS SKU_ID,
                CASE
                    WHEN AL.RemQty = 0 THEN s.BATCH_ID
                    ELSE AL.BATCH_ID
                END AS BATCH_ID,
                CASE
                    WHEN AL.RemQty = 0 THEN s.WAVE_ID
                    ELSE AL.WAVE_ID
                END AS WAVE_ID,
                CASE
                    WHEN AL.RemQty = 0 THEN
                        CASE
                            WHEN s.RequestQty >= b.SegmentCapacity
                                THEN b.SegmentCapacity
                            ELSE s.RequestQty
                        END
                    ELSE
                        CASE
                            WHEN AL.RemQty >= b.SegmentCapacity
                                THEN b.SegmentCapacity
                            ELSE AL.RemQty
                        END
                END AS AllocatedQty,
                CASE
                    WHEN AL.RemQty = 0 THEN
                        s.RequestQty - CASE
                            WHEN s.RequestQty >= b.SegmentCapacity
                                THEN b.SegmentCapacity
                            ELSE s.RequestQty
                        END
                    ELSE
                        AL.RemQty - CASE
                            WHEN AL.RemQty >= b.SegmentCapacity
                                THEN b.SegmentCapacity
                            ELSE AL.RemQty
                        END
                END AS RemQty,
                b.bin_index,
                CASE
                    WHEN AL.RemQty = 0 THEN AL.req_index + 1
                    ELSE AL.req_index
                END AS req_index
            FROM BinswithLowcost b
            JOIN alloc AL
              ON b.bin_index = AL.bin_index + 1
            LEFT JOIN StorageRequest s
              ON s.req_index = AL.req_index + 1
            WHERE AL.RemQty > 0
               OR s.req_index IS NOT NULL
        )
        SELECT JSON_ARRAYAGG(dataalloc)
        INTO   V_StorageJson
        FROM (
            SELECT DISTINCT
                JSON_OBJECT(
                    'WAVE_ID',      WAVE_ID,
                    'STORAGE_ID',   STORAGE_ID,
                    'BIN_ID',       BIN_ID,
                    'SEGMENT_NO',   SEGMENT_NO,
                    'SKU_ID',       P_SkuId,
                    'BATCH_ID',     P_BatchId,
                    'AllocatedQty', AllocatedQty
                ) AS dataalloc
            FROM alloc
            WHERE AllocatedQty > 0
        ) A;

        
        
        
        IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

            
            
		INSERT INTO order_bin_mapping (
		    BIN_ID,
		    STATION_ID,
		    TYPE,
		    STATUS,
		    IS_SYNCED,
		    INSERTED_TIMESTAMP
		)
		SELECT DISTINCT
		    jt.BIN_ID,
		    P_StationId,
		    'RACK_PICK',
		    'PENDING',
		    0,
		    NOW()
		FROM JSON_TABLE(
			V_StorageJson,
			'$[*]' COLUMNS (
			    BIN_ID INT PATH '$.BIN_ID'
			)
		     ) jt
		LEFT JOIN order_bin_mapping obm_ok
		    ON  obm_ok.BIN_ID     = jt.BIN_ID
		    AND obm_ok.STATION_ID = P_StationId
		    AND obm_ok.TYPE       = 'RACK_PICK'
		    AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
		WHERE obm_ok.ORDER_BIN_ID IS NULL;

				INSERT INTO put_wave_order_master (
		    PUT_ORDER_ID,
		    STATION_ID,
		    WAVE_ID,
		    STORAGE_REQUEST_ID,
		    STORAGE_ID,
		    ORDER_BIN_ID,
		    BIN_ID,
		    BIN_SEGMENT_NO,
		    STATUS,
		    SKU_ID,
		    BATCH_ID,
		    EXPECTED_QUANTITY
		)
		SELECT
		    UUID(),
		    P_StationId,
		    jt.WAVE_ID,
		    P_StorageRequestId,
		    jt.STORAGE_ID,
		    COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) AS ORDER_BIN_ID,
		    jt.BIN_ID,
		    jt.SEGMENT_NO,
		    'PENDING',
		    jt.SKU_ID,
		    jt.BATCH_ID,
		    jt.AllocatedQty
		FROM JSON_TABLE(
			V_StorageJson,
			'$[*]' COLUMNS (
			    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
			    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
			    BIN_ID       INT PATH '$.BIN_ID',
			    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
			    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
			    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
			    AllocatedQty INT PATH '$.AllocatedQty'
			)
		     ) jt

		
		LEFT JOIN (
		    SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
		    FROM order_bin_mapping
		    WHERE TYPE='RACK_PICK'
		      AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
		    GROUP BY BIN_ID, STATION_ID
		) obm_reuse
		  ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId

		
		LEFT JOIN (
		    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
		    FROM order_bin_mapping
		    WHERE TYPE='RACK_PICK'
		      AND STATUS='PENDING'
		    GROUP BY BIN_ID, STATION_ID
		) obm_new
		  ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId

		WHERE jt.AllocatedQty > 0
  AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL;



            
            UPDATE live_inventory_master L
            INNER JOIN put_wave_order_master PWO
                ON PWO.BIN_ID         = L.BIN_ID
               AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
            SET L.VIRTUAL_QUANTITY_TO_PUT =
                    L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY,
                L.ARTICLE_ID          = PWO.SKU_ID,
                L.BATCH_ID            = PWO.BATCH_ID
            WHERE (L.ARTICLE_ID = 'no-sku'
                   OR (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT) = 0)
              AND PWO.STORAGE_ID = P_StorageId
              AND PWO.STATUS     = 'PENDING';

        ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

            
            SELECT
                UUID()             AS PUT_ORDER_ID,
                P_StationId        AS STATION_ID,
                jt.WAVE_ID         AS WAVE_ID,
                P_StorageRequestId AS STORAGE_REQUEST_ID,
                jt.STORAGE_ID,
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING'          AS STATUS,
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty    AS EXPECTED_QUANTITY
            FROM JSON_TABLE(
                    V_StorageJson,
                    '$[*]' COLUMNS (
                        WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                        BIN_ID       INT PATH '$.BIN_ID',
                        SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                        SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                        BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                        AllocatedQty INT PATH '$.AllocatedQty'
                    )
                 ) jt
            WHERE jt.AllocatedQty > 0;

        END IF;
    END IF;  

    
    
    
    IF P_ForProcessing = 1 THEN

        
        SELECT COALESCE(SUM(QUANTITY), 0)
        INTO   v_wms_data_total_qty
        FROM   put_wave_wms_data
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        
        SELECT COALESCE(
                   SUM(
                       CASE
                           WHEN STATUS = 'PUT_COMPLETED'
                               THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                           ELSE EXPECTED_QUANTITY
                       END
                   ),
                   0
               )
        INTO   v_order_master_total_expected
        FROM   put_wave_order_master
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        
        SET V_left_over_calc = v_wms_data_total_qty - v_order_master_total_expected;

        
        UPDATE put_wave_wms_data PW
        SET    PW.STATUS   = 'COMPLETED',
               PW.LEFT_OVER = V_left_over_calc
        WHERE  PW.SKU_ID             = P_SkuId
          AND  PW.BATCH_ID           = P_BatchId
          AND  PW.STATUS             = 'PENDING'
          AND  PW.STORAGE_REQUEST_ID = P_StorageRequestId
          AND  PW.STORAGE_ID         = P_StorageId;
    END IF;

    
    SET SESSION cte_max_recursion_depth = 1000;

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPending_Order_allocation_V3_with_ROS` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPending_Order_allocation_V3_with_ROS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPending_Order_allocation_V3_with_ROS`(
    IN P_StorageRequestId VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StorageId        VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_SkuId            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_BatchId          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN P_StationId        INT,
    IN P_ForProcessing    INT          
)
proc_main:BEGIN
    

    
    DECLARE V_StorageJson                 JSON;
    DECLARE V_StoredSKUBinsList           TEXT;

    DECLARE V_PendingQty                  INT DEFAULT 0;

    DECLARE V_MaxBinWeight                BIGINT DEFAULT 0;

    
    DECLARE V_MaxQtyPerBin                INT DEFAULT 0;     
    DECLARE V_SkuUnitWeight               INT DEFAULT 0;
    DECLARE V_MinSegmentSize              INT DEFAULT 1;
    DECLARE V_SkuCategory                 INT DEFAULT 0;
    DECLARE V_SkuROS                      DECIMAL(10,2) DEFAULT 0.00;

    
    DECLARE V_ROS_ThresholdPct            DECIMAL(10,2) DEFAULT 60.00;
    DECLARE V_BinCapacityThresholdPct     DECIMAL(10,2) DEFAULT 50.00;

    
    DECLARE V_TargetQty                   INT DEFAULT 0;

    DECLARE V_CapPerSeg6                  INT DEFAULT 0;
    DECLARE V_CapPerSeg4                  INT DEFAULT 0;
    DECLARE V_CapPerSeg2                  INT DEFAULT 0;
    DECLARE V_CapPerSeg1                  INT DEFAULT 0;

    DECLARE V_need6                       INT DEFAULT 1;
    DECLARE V_need4                       INT DEFAULT 1;
    DECLARE V_need2                       INT DEFAULT 1;

    DECLARE V_PrefBinSegments             INT DEFAULT 6;  

    DECLARE V_TotalCandidates             INT DEFAULT 800;

    
    DECLARE V_PrefSegCap                 INT DEFAULT 1;

    DECLARE v_wms_data_total_qty          INT DEFAULT 0;
    DECLARE v_order_master_total_expected INT DEFAULT 0;
    DECLARE V_left_over_calc              INT DEFAULT 0;

    
    DECLARE V_OneSegEarlyQuota            INT DEFAULT 999999;

    
    DECLARE V_EPS                         DECIMAL(10,6) DEFAULT 0.000100;

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        IF P_ForProcessing = 1 THEN
            ROLLBACK;
        END IF;
        SET SESSION cte_max_recursion_depth = 1000;
        RESIGNAL;
    END;

    
    SELECT CAST(KEY_VALUE AS SIGNED)
      INTO V_MaxBinWeight
      FROM master_config
     WHERE KEY_NAME = 'MAX_WEIGHT_ALLOWED_ON_BOT_GRAMS'
     LIMIT 1;

    SET V_MaxBinWeight = COALESCE(V_MaxBinWeight, 2147483647);

    SELECT
        COALESCE(MAX(CASE WHEN KEY_NAME='ROS_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_ROS_ThresholdPct),
        COALESCE(MAX(CASE WHEN KEY_NAME='BIN_CAPACITY_THRESHOLD' THEN CAST(KEY_VALUE AS DECIMAL(10,2)) END), V_BinCapacityThresholdPct)
    INTO
        V_ROS_ThresholdPct,
        V_BinCapacityThresholdPct
    FROM master_config
    WHERE KEY_NAME IN ('ROS_THRESHOLD','BIN_CAPACITY_THRESHOLD');

    SET SESSION cte_max_recursion_depth = 10000;
    SET SESSION group_concat_max_len = 65535;

    
    SELECT
        MAX_QUANTITY_PER_SEGMENT,
        WEIGHT_OF_EACH_SKU,
        MIN_SEGMENT_SIZE,
        category,
        COALESCE(ROS,0)
    INTO
        V_MaxQtyPerBin,
        V_SkuUnitWeight,
        V_MinSegmentSize,
        V_SkuCategory,
        V_SkuROS
    FROM sku_master
    WHERE SKU_ID = P_SkuId
    LIMIT 1;

    IF V_MaxQtyPerBin IS NULL OR V_MaxQtyPerBin <= 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'MAX_QTY_PER_BIN missing/invalid (sku_master.MAX_QUANTITY_PER_SEGMENT)';
    END IF;

    SET V_SkuUnitWeight  = COALESCE(V_SkuUnitWeight,0);
    SET V_MinSegmentSize = GREATEST(1, COALESCE(V_MinSegmentSize,1));

    
    SET V_CapPerSeg6 = FLOOR(V_MaxQtyPerBin / 6);
    SET V_CapPerSeg4 = FLOOR(V_MaxQtyPerBin / 4);
    SET V_CapPerSeg2 = FLOOR(V_MaxQtyPerBin / 2);
    SET V_CapPerSeg1 = FLOOR(V_MaxQtyPerBin / 1);

    
    SET V_TargetQty = CEIL( COALESCE(V_SkuROS,0) * (COALESCE(V_ROS_ThresholdPct,60.0)/100.0) );

    
    IF V_TargetQty <= 0 THEN
        SET V_need6 = 1;
        SET V_need4 = 1;
        SET V_need2 = 1;
        SET V_PrefBinSegments = 6;
    ELSE
        SET V_need6 = CASE
                        WHEN V_CapPerSeg6 > 0 THEN LEAST(6, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg6)))
                        ELSE 6
                      END;

        SET V_need4 = CASE
                        WHEN V_CapPerSeg4 > 0 THEN LEAST(4, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg4)))
                        ELSE 4
                      END;

        SET V_need2 = CASE
                        WHEN V_CapPerSeg2 > 0 THEN LEAST(2, GREATEST(1, CEIL(V_TargetQty / V_CapPerSeg2)))
                        ELSE 2
                      END;

        
        SET V_PrefBinSegments = 6;

        IF ((V_need6 / 6.0) * 100.0) >= (V_BinCapacityThresholdPct - V_EPS) THEN
            SET V_PrefBinSegments = 4;
        END IF;

        IF V_PrefBinSegments = 4
           AND ((V_need4 / 4.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 2;
        END IF;

        IF V_PrefBinSegments = 2
           AND ((V_need2 / 2.0) * 100.0) > (V_BinCapacityThresholdPct + V_EPS) THEN
            SET V_PrefBinSegments = 1;
        END IF;
    END IF;

    
    SET V_PrefSegCap = CASE V_PrefBinSegments
                         WHEN 6 THEN GREATEST(V_CapPerSeg6, 1)
                         WHEN 4 THEN GREATEST(V_CapPerSeg4, 1)
                         WHEN 2 THEN GREATEST(V_CapPerSeg2, 1)
                         ELSE GREATEST(V_CapPerSeg1, 1)
                       END;

    
    SELECT GROUP_CONCAT(BIN_ID)
      INTO V_StoredSKUBinsList
      FROM (
          SELECT DISTINCT BIN_ID
          FROM live_inventory_master
          WHERE ARTICLE_ID = P_SkuId
            AND BATCH_ID   = P_BatchId
      ) b;

    SET V_StoredSKUBinsList = CONCAT(',', IFNULL(V_StoredSKUBinsList,''), ',');

    IF P_ForProcessing = 1 THEN
        START TRANSACTION;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold;

    CREATE TEMPORARY TABLE Tmp_StorageRequestold (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    IF EXISTS (
        SELECT 1
        FROM live_inventory_master
        WHERE ARTICLE_ID = P_SkuId
          AND BATCH_ID   = P_BatchId
    ) THEN

        INSERT INTO Tmp_StorageRequestold (
            WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
        )
        SELECT
            PW.WAVE_ID,
            P_StorageRequestId,
            PW.STORAGE_ID,
            P_SkuId,
            P_BatchId,
            SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
            ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
        FROM (
            SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
            FROM put_wave_wms_data
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PW
        LEFT JOIN (
            SELECT
                WAVE_ID,
                STORAGE_ID,
                SUM(
                    CASE
                        WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                        ELSE EXPECTED_QUANTITY
                    END
                ) AS EXPECTED_QUANTITY
            FROM put_wave_order_master
            WHERE SKU_ID             = P_SkuId
              AND BATCH_ID           = P_BatchId
              AND STORAGE_REQUEST_ID = P_StorageRequestId
              AND STORAGE_ID         = P_StorageId
            GROUP BY WAVE_ID, STORAGE_ID
        ) PWO
          ON PWO.STORAGE_ID = PW.STORAGE_ID
         AND PWO.WAVE_ID    = PW.WAVE_ID
        WHERE PW.QUANTITY > 0
        GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

        SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
        FROM Tmp_StorageRequestold;

        
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_A;
        DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequestold_B;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_A LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_A SELECT * FROM Tmp_StorageRequestold;

        CREATE TEMPORARY TABLE Tmp_StorageRequestold_B LIKE Tmp_StorageRequestold;
        INSERT INTO Tmp_StorageRequestold_B SELECT * FROM Tmp_StorageRequestold;

        IF V_PendingQty > 0 THEN

            WITH RECURSIVE
            AisleCost AS (
                SELECT Aisle_Number, MIN(Cost) AS Cost
                FROM station_to_aisle_cost
                WHERE Station_ID = P_StationId
                GROUP BY Aisle_Number
            ),
            BinWeight AS (
                
                SELECT
                    L0.BIN_ID,
                    SUM(
                        (L0.QUANTITY + L0.VIRTUAL_QUANTITY_TO_PUT) * COALESCE(SM0.WEIGHT_OF_EACH_SKU,0)
                    ) AS CurrentWeightInBin
                FROM live_inventory_master L0
                LEFT JOIN sku_master SM0 ON SM0.SKU_ID = L0.ARTICLE_ID
                WHERE IFNULL(L0.remark,'na') NOT IN ('no_space','audit_marked')
                GROUP BY L0.BIN_ID
            ),
            Phase1Candidates AS (
                SELECT
                    L.BIN_ID,
                    L.SEGMENT_NO,
                    BIM.BIN_SEGMENTS,
                    COALESCE(AC.Cost, 9999) AS Cost,
                    (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT) AS QtyInSeg,
                    COALESCE(BW.CurrentWeightInBin,0) AS CurrentWeightInBin,
                    CASE
                        WHEN BIM.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                        WHEN BIM.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                        WHEN BIM.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                        WHEN BIM.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                        ELSE 0
                    END AS QtyCapPerSeg
                FROM live_inventory_master L
                INNER JOIN bin_info_master BIM ON BIM.BIN_ID = L.BIN_ID
                INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
                INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
                LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
                LEFT JOIN BinWeight BW ON BW.BIN_ID = L.BIN_ID
                WHERE L.ARTICLE_ID = P_SkuId
                  AND L.BATCH_ID   = P_BatchId
                  AND IFNULL(L.remark,'na') NOT IN ('no_space','audit_marked')
                  AND LBM.LOCATION_ID IS NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master P
                      WHERE P.BIN_ID         = L.BIN_ID
                        AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                        AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  )
            ),
            Phase1BestPerBin AS (
                SELECT
                    C.*,
                    GREATEST(C.QtyCapPerSeg - C.QtyInSeg, 0) AS BalanceSegQty,
                    CASE
                        WHEN V_SkuUnitWeight <= 0 THEN 999999
                        ELSE FLOOR( GREATEST(V_MaxBinWeight - C.CurrentWeightInBin,0) / V_SkuUnitWeight )
                    END AS BalanceWeightQty,
                    ROW_NUMBER() OVER (
                        PARTITION BY C.BIN_ID
                        ORDER BY (GREATEST(C.QtyCapPerSeg - C.QtyInSeg,0)) DESC, C.SEGMENT_NO
                    ) AS rn_in_bin
                FROM Phase1Candidates C
                WHERE C.QtyCapPerSeg > 0
                  AND C.CurrentWeightInBin < V_MaxBinWeight
            ),
            Phase1BinsOrdered AS (
                SELECT
                    B.BIN_ID,
                    B.SEGMENT_NO,
                    LEAST(B.BalanceSegQty, B.BalanceWeightQty) AS SegmentCapacity,
                    ROW_NUMBER() OVER (
                        ORDER BY
                            CASE WHEN B.BIN_SEGMENTS=6 THEN 1 WHEN B.BIN_SEGMENTS=4 THEN 2 WHEN B.BIN_SEGMENTS=2 THEN 3 WHEN B.BIN_SEGMENTS=1 THEN 4 ELSE 9 END,
                            B.Cost,
                            B.BIN_ID,
                            B.SEGMENT_NO
                    ) AS bin_index
                FROM Phase1BestPerBin B
                WHERE B.rn_in_bin = 1
                  AND LEAST(B.BalanceSegQty, B.BalanceWeightQty) > 0
            ),
            alloc1 AS (
                SELECT
                    ob.BIN_ID,
                    ob.SEGMENT_NO,
                    ob.SegmentCapacity,
                    r.STORAGE_ID,
                    P_SkuId   AS SKU_ID,
                    P_BatchId AS BATCH_ID,
                    r.WAVE_ID,
                    CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS AllocatedQty,
                    r.RequestQty - CASE WHEN r.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE r.RequestQty END AS RemQty,
                    ob.bin_index,
                    r.req_index
                FROM Phase1BinsOrdered ob
                JOIN Tmp_StorageRequestold_A r
                  ON r.req_index = 1
                 AND ob.bin_index = 1
                WHERE r.RequestQty > 0

                UNION ALL

                SELECT
                    b.BIN_ID,
                    b.SEGMENT_NO,
                    b.SegmentCapacity,
                    CASE WHEN a.RemQty = 0 THEN r2.STORAGE_ID ELSE a.STORAGE_ID END,
                    P_SkuId,
                    P_BatchId,
                    CASE WHEN a.RemQty = 0 THEN r2.WAVE_ID ELSE a.WAVE_ID END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    CASE
                        WHEN a.RemQty = 0 THEN
                            r2.RequestQty - CASE WHEN r2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE r2.RequestQty END
                        ELSE
                            a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                    END,
                    b.bin_index,
                    CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
                FROM Phase1BinsOrdered b
                JOIN alloc1 a
                  ON b.bin_index = a.bin_index + 1
                LEFT JOIN Tmp_StorageRequestold_B r2
                  ON r2.req_index = a.req_index + 1
                WHERE (a.RemQty > 0) OR (r2.req_index IS NOT NULL AND r2.RequestQty > 0)
            )
            SELECT JSON_ARRAYAGG(
                       JSON_OBJECT(
                           'WAVE_ID',      WAVE_ID,
                           'STORAGE_ID',   STORAGE_ID,
                           'BIN_ID',       BIN_ID,
                           'SEGMENT_NO',   SEGMENT_NO,
                           'SKU_ID',       P_SkuId,
                           'BATCH_ID',     P_BatchId,
                           'AllocatedQty', AllocatedQty
                       )
                   )
            INTO V_StorageJson
            FROM alloc1
            WHERE AllocatedQty > 0;

            IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

                INSERT INTO order_bin_mapping (
                    BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
                )
                SELECT DISTINCT
                    jt.BIN_ID,
                    P_StationId,
                    'RACK_PICK',
                    'PENDING',
                    0,
                    NOW()
                FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
                LEFT JOIN order_bin_mapping obm_ok
                    ON  obm_ok.BIN_ID     = jt.BIN_ID
                    AND obm_ok.STATION_ID = P_StationId
                    AND obm_ok.TYPE       = 'RACK_PICK'
                    AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                WHERE obm_ok.ORDER_BIN_ID IS NULL;

                INSERT INTO put_wave_order_master (
                    PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                    ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
                )
                SELECT
                    UUID(),
                    P_StationId,
                    jt.WAVE_ID,
                    P_StorageRequestId,
                    jt.STORAGE_ID,
                    COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING',
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty
                FROM JSON_TABLE(
                        V_StorageJson,
                        '$[*]' COLUMNS (
                            WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                            STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                            BIN_ID       INT PATH '$.BIN_ID',
                            SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                            SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                            BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                            AllocatedQty INT PATH '$.AllocatedQty'
                        )
                     ) jt
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK'
                      AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                    GROUP BY BIN_ID, STATION_ID
                ) obm_reuse
                  ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
                LEFT JOIN (
                    SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                    FROM order_bin_mapping
                    WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                    GROUP BY BIN_ID, STATION_ID
                ) obm_new
                  ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
                WHERE jt.AllocatedQty > 0
                  AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
                  AND NOT EXISTS (
                      SELECT 1
                      FROM put_wave_order_master p
                      WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                        AND p.STORAGE_ID         = jt.STORAGE_ID
                        AND p.BIN_ID             = jt.BIN_ID
                        AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                        AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
                  );

                UPDATE live_inventory_master L
                INNER JOIN put_wave_order_master PWO
                    ON PWO.SKU_ID         = L.ARTICLE_ID
                   AND PWO.BATCH_ID       = L.BATCH_ID
                   AND PWO.BIN_ID         = L.BIN_ID
                   AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
                SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY
                WHERE L.ARTICLE_ID   = P_SkuId
                  AND L.BATCH_ID     = P_BatchId
                  AND PWO.STORAGE_ID = P_StorageId
                  AND PWO.STATUS     = 'PENDING';

            ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

                SELECT
                    UUID() AS PUT_ORDER_ID,
                    P_StationId AS STATION_ID,
                    jt.WAVE_ID,
                    P_StorageRequestId AS STORAGE_REQUEST_ID,
                    jt.STORAGE_ID,
                    jt.BIN_ID,
                    jt.SEGMENT_NO,
                    'PENDING' AS STATUS,
                    jt.SKU_ID,
                    jt.BATCH_ID,
                    jt.AllocatedQty AS EXPECTED_QUANTITY
                FROM JSON_TABLE(
                    V_StorageJson,
                    '$[*]' COLUMNS (
                        WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                        STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                        BIN_ID       INT PATH '$.BIN_ID',
                        SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                        SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                        BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                        AllocatedQty INT PATH '$.AllocatedQty'
                    )
                ) jt
                WHERE jt.AllocatedQty > 0;

            END IF;

        END IF;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest (
        ID                  INT AUTO_INCREMENT NOT NULL,
        WAVE_ID             VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_REQUEST_ID  VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID          VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        SKU_ID              VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_ID            VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        RequestQty          INT,
        req_index           INT,
        PRIMARY KEY (ID),
        INDEX (req_index),
        INDEX (STORAGE_ID),
        INDEX (SKU_ID),
        INDEX (BATCH_ID)
    );

    INSERT INTO Tmp_StorageRequest (
        WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, RequestQty, req_index
    )
    SELECT
        PW.WAVE_ID,
        P_StorageRequestId,
        PW.STORAGE_ID,
        P_SkuId,
        P_BatchId,
        SUM(GREATEST(PW.QUANTITY - IFNULL(PWO.EXPECTED_QUANTITY, 0), 0)) AS RequestQty,
        ROW_NUMBER() OVER (ORDER BY PW.STORAGE_ID, PW.WAVE_ID) AS req_index
    FROM (
        SELECT WAVE_ID, STORAGE_ID, SUM(QUANTITY) AS QUANTITY
        FROM put_wave_wms_data
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY STORAGE_ID, WAVE_ID
    ) PW
    LEFT JOIN (
        SELECT
            WAVE_ID,
            STORAGE_ID,
            SUM(
                CASE
                    WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                    ELSE EXPECTED_QUANTITY
                END
            ) AS EXPECTED_QUANTITY
        FROM put_wave_order_master
        WHERE SKU_ID             = P_SkuId
          AND BATCH_ID           = P_BatchId
          AND STORAGE_REQUEST_ID = P_StorageRequestId
          AND STORAGE_ID         = P_StorageId
        GROUP BY WAVE_ID, STORAGE_ID
    ) PWO
      ON PWO.STORAGE_ID = PW.STORAGE_ID
     AND PWO.WAVE_ID    = PW.WAVE_ID
    GROUP BY PW.WAVE_ID, PW.STORAGE_ID;

    SELECT COALESCE(SUM(RequestQty),0) INTO V_PendingQty
    FROM Tmp_StorageRequest;

    
    IF V_PrefBinSegments = 1 THEN
        SET V_OneSegEarlyQuota =
            CASE
                WHEN V_PendingQty > GREATEST(V_CapPerSeg1, 1) THEN 1
                ELSE 999999
            END;
    ELSE
        SET V_OneSegEarlyQuota = 999999;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_A;
    DROP TEMPORARY TABLE IF EXISTS Tmp_StorageRequest_B;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_A LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_A SELECT * FROM Tmp_StorageRequest;

    CREATE TEMPORARY TABLE Tmp_StorageRequest_B LIKE Tmp_StorageRequest;
    INSERT INTO Tmp_StorageRequest_B SELECT * FROM Tmp_StorageRequest;

    IF V_PendingQty > 0 THEN

        SET V_TotalCandidates = LEAST(
            20000,
            GREATEST(
                3000,
                CEIL(V_PendingQty / GREATEST(1, V_PrefSegCap)) * 12
            )
        );
WITH RECURSIVE
        ArticleWithProximity AS (
            SELECT
                AP.CHILD_ARTICLE_ID,
                ROW_NUMBER() OVER (
                    PARTITION BY AP.PARENT_ARTICLE_ID
                    ORDER BY AP.PROXIMITY_SCORE DESC
                ) AS rn
            FROM article_proximity_score AP
            WHERE AP.PARENT_ARTICLE_ID = P_SkuId
        ),
        FinalProximity AS (
            SELECT IFNULL(AWP.CHILD_ARTICLE_ID, P_SkuId) AS CHILD_ARTICLE_ID,
                   IFNULL(AWP.rn, 1) AS rn
            FROM (SELECT 1 AS dummy) D
            LEFT JOIN ArticleWithProximity AWP ON TRUE
        ),
        AisleCost AS (
            SELECT Aisle_Number, MIN(Cost) AS Cost
            FROM station_to_aisle_cost
            WHERE Station_ID = P_StationId
            GROUP BY Aisle_Number
        ),
        FreeBins AS (
            SELECT DISTINCT
                BIM.BIN_ID,
                BIM.BIN_SEGMENTS,
                COALESCE(AC.Cost, 9999) AS Cost,
                STBM.LOCATION_ID
            FROM bin_info_master BIM
            INNER JOIN store_bin_master STBM ON STBM.BIN_ID = BIM.BIN_ID
            INNER JOIN location_master lm ON lm.LOCATION_ID = STBM.LOCATION_ID
            LEFT JOIN AisleCost AC ON AC.Aisle_Number = IFNULL(lm.aisle_number,'A01')
            LEFT JOIN location_block_master LBM ON LBM.LOCATION_ID = STBM.LOCATION_ID
            WHERE LBM.LOCATION_ID IS NULL
        ),
        LiveFree AS (
            SELECT
                L.BIN_ID,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                IFNULL(L.remark,'na') AS remark,
                FB.BIN_SEGMENTS,
                FB.Cost
            FROM live_inventory_master L
            INNER JOIN FreeBins FB ON FB.BIN_ID = L.BIN_ID
            WHERE IFNULL(L.remark,'na') = 'na'
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master P
                  WHERE P.BIN_ID         = L.BIN_ID
                    AND P.BIN_SEGMENT_NO = L.SEGMENT_NO
                    AND P.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              )
        ),
        RankedBins AS (
            SELECT
                L.BIN_ID,
                L.Cost,
                L.BIN_SEGMENTS,
                L.SEGMENT_NO,
                L.ARTICLE_ID,
                L.BATCH_ID,
                SM.WEIGHT_OF_EACH_SKU,
                L.QUANTITY,
                L.VIRTUAL_QUANTITY_TO_PUT,
                OBM.BOT_ID,
                SM.category,
                OBM.STATUS,
                OBM.TYPE,
                FP.rn,
                CASE
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.TYPE   = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED') THEN 1
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS IN ('BIN_PICKED','PRE_ON_STATION','ON_STATION') THEN 2
                    WHEN OBM.STATION_ID = P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 3
                    WHEN OBM.STATION_ID <> P_StationId
                         AND OBM.STATUS NOT IN ('TASK_COMPLETED','OPERATION_COMPLETED') THEN 4
                    ELSE 5
                END AS row_rank
            FROM LiveFree L
            INNER JOIN sku_master SM ON SM.SKU_ID = L.ARTICLE_ID
            LEFT JOIN FinalProximity FP ON L.ARTICLE_ID = FP.CHILD_ARTICLE_ID
            LEFT JOIN (
                SELECT BIN_ID, MAX(BOT_ID) AS BOT_ID, MAX(STATUS) AS STATUS, MAX(TYPE) AS TYPE, MAX(STATION_ID) AS STATION_ID
                FROM order_bin_mapping
                GROUP BY BIN_ID
            ) OBM ON OBM.BIN_ID = L.BIN_ID
        ),
        Tmp_Bins AS (
            SELECT
                CASE
                    WHEN LOCATE(CONCAT(',', RB.BIN_ID, ','), V_StoredSKUBinsList) > 0 THEN 100000
                    ELSE IFNULL(RB.rn, 1000)
                END AS rn,
                RB.row_rank,
                RB.BIN_ID,
                RB.Cost,
                RB.BIN_SEGMENTS,
                RB.SEGMENT_NO,
                RB.ARTICLE_ID AS SKU_ID,
                RB.BATCH_ID,
                CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS WEIGHT_OF_EACH_SKU,
                RB.QUANTITY,
                RB.VIRTUAL_QUANTITY_TO_PUT,
                (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END AS CurrentWeightInSegment,
                SUM(
                    (RB.QUANTITY + RB.VIRTUAL_QUANTITY_TO_PUT) *
                    CASE WHEN RB.ARTICLE_ID='no-sku' THEN 0 ELSE COALESCE(RB.WEIGHT_OF_EACH_SKU,0) END
                ) OVER (PARTITION BY RB.BIN_ID) AS CurrentWeightInBin,
                BSR.RANKING
            FROM RankedBins RB
            INNER JOIN bin_segment_ranking BSR
                ON BSR.BIN_SEGMENT_COUNT = RB.BIN_SEGMENTS
               AND RB.SEGMENT_NO          = BSR.SEGMENT_ID
        ),
        SegCandidates AS (
            SELECT
                T.*,
                (V_MaxBinWeight - T.CurrentWeightInBin) AS BalanceWeightInBin,
                SUM(CASE WHEN (T.QUANTITY + T.VIRTUAL_QUANTITY_TO_PUT)=0 THEN 1 ELSE 0 END)
                    OVER (PARTITION BY T.BIN_ID) AS EmptySegments,
                CASE
                    WHEN T.BIN_SEGMENTS=6 THEN FLOOR(V_MaxQtyPerBin/6)
                    WHEN T.BIN_SEGMENTS=4 THEN FLOOR(V_MaxQtyPerBin/4)
                    WHEN T.BIN_SEGMENTS=2 THEN FLOOR(V_MaxQtyPerBin/2)
                    WHEN T.BIN_SEGMENTS=1 THEN FLOOR(V_MaxQtyPerBin/1)
                    ELSE 0
                END AS QtyCapPerSegment
            FROM Tmp_Bins T
            WHERE (T.SKU_ID='no-sku' OR (T.QUANTITY + T.VIRTUAL_QUANTITY_TO_PUT)=0)
        ),
        ScoredCandidates AS (
            SELECT
                C.*,

                
                CASE
                    WHEN C.BIN_SEGMENTS=6 THEN V_need6
                    WHEN C.BIN_SEGMENTS=4 THEN V_need4
                    WHEN C.BIN_SEGMENTS=2 THEN V_need2
                    ELSE 1
                END AS PlanSegsForThisBinType,

                LEAST(
                    CASE
                        WHEN C.BIN_SEGMENTS=6 THEN V_need6
                        WHEN C.BIN_SEGMENTS=4 THEN V_need4
                        WHEN C.BIN_SEGMENTS=2 THEN V_need2
                        ELSE 1
                    END,
                    GREATEST(C.EmptySegments,1)
                ) AS AllowedSegsInThisBin,

                CASE
                    WHEN V_SkuUnitWeight <= 0 THEN 999999
                    ELSE FLOOR(
                        GREATEST(C.BalanceWeightInBin,0)
                        /
                        (V_SkuUnitWeight * LEAST(
                            CASE
                                WHEN C.BIN_SEGMENTS=6 THEN V_need6
                                WHEN C.BIN_SEGMENTS=4 THEN V_need4
                                WHEN C.BIN_SEGMENTS=2 THEN V_need2
                                ELSE 1
                            END,
                            GREATEST(C.EmptySegments,1)
                        ))
                    )
                END AS WeightCapPerSegment,

                
                CASE
                    WHEN V_PrefBinSegments=6 THEN
                        CASE WHEN C.BIN_SEGMENTS=6 THEN 1 WHEN C.BIN_SEGMENTS=4 THEN 2 WHEN C.BIN_SEGMENTS=2 THEN 3 WHEN C.BIN_SEGMENTS=1 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=4 THEN
                        CASE WHEN C.BIN_SEGMENTS=4 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=1 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    WHEN V_PrefBinSegments=2 THEN
                        CASE WHEN C.BIN_SEGMENTS=2 THEN 1 WHEN C.BIN_SEGMENTS=1 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                    ELSE
                        CASE WHEN C.BIN_SEGMENTS=1 THEN 1 WHEN C.BIN_SEGMENTS=2 THEN 2 WHEN C.BIN_SEGMENTS=4 THEN 3 WHEN C.BIN_SEGMENTS=6 THEN 4 ELSE 9 END
                END AS BinTypeRank

            FROM SegCandidates C
            WHERE C.QtyCapPerSegment > 0
              AND C.BalanceWeightInBin > 0
        ),
        CapacityFinal AS (
            SELECT
                S.*,
                LEAST(S.QtyCapPerSegment, S.WeightCapPerSegment) AS SegmentCapacity
            FROM ScoredCandidates S
        ),
        PickSegments AS (
            SELECT
                X.*,
                ROW_NUMBER() OVER (
                    PARTITION BY X.BIN_ID
                    ORDER BY X.RANKING, X.SEGMENT_NO
                ) AS rn_in_bin
            FROM CapacityFinal X
            WHERE X.SegmentCapacity > 0
        ),
        BinsRanked AS (
            SELECT
                P.*,
                ROW_NUMBER() OVER (
                    PARTITION BY P.BIN_SEGMENTS
                    ORDER BY
                        P.rn,
                        P.row_rank,
                        P.Cost,
                        P.BIN_ID,
                        P.RANKING,
                        P.SEGMENT_NO
                ) AS TypeSeq
            FROM PickSegments P
            WHERE P.rn_in_bin <= P.AllowedSegsInThisBin
        ),
        BinswithLowcost AS (
            SELECT
                BR.*,
                CASE
                    WHEN V_PrefBinSegments = 1
                     AND BR.BIN_SEGMENTS   = 1
                     AND BR.TypeSeq        > V_OneSegEarlyQuota
                    THEN 5
                    ELSE BR.BinTypeRank
                END AS EffBinTypeRank,

                ROW_NUMBER() OVER (
                    ORDER BY
                        CASE
                            WHEN V_PrefBinSegments = 1
                             AND BR.BIN_SEGMENTS   = 1
                             AND BR.TypeSeq        > V_OneSegEarlyQuota
                            THEN 5
                            ELSE BR.BinTypeRank
                        END,
                        BR.rn,
                        BR.row_rank,
                        BR.Cost,
                        BR.BIN_ID,
                        BR.RANKING,
                        BR.SEGMENT_NO
                ) AS bin_index
            FROM BinsRanked BR
            LIMIT V_TotalCandidates
        ),
        alloc AS (
            SELECT
                ob.BIN_ID,
                ob.SEGMENT_NO,
                ob.SegmentCapacity,
                sr.STORAGE_ID,
                sr.WAVE_ID,
                CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS AllocatedQty,
                sr.RequestQty - CASE WHEN sr.RequestQty >= ob.SegmentCapacity THEN ob.SegmentCapacity ELSE sr.RequestQty END AS RemQty,
                ob.bin_index,
                sr.req_index
            FROM BinswithLowcost ob
            JOIN Tmp_StorageRequest_A sr
              ON sr.req_index = 1
             AND ob.bin_index = 1
            WHERE sr.RequestQty > 0

            UNION ALL

            SELECT
                b.BIN_ID,
                b.SEGMENT_NO,
                b.SegmentCapacity,
                CASE WHEN a.RemQty = 0 THEN s2.STORAGE_ID ELSE a.STORAGE_ID END,
                CASE WHEN a.RemQty = 0 THEN s2.WAVE_ID    ELSE a.WAVE_ID    END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                CASE
                    WHEN a.RemQty = 0 THEN
                        s2.RequestQty - CASE WHEN s2.RequestQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE s2.RequestQty END
                    ELSE
                        a.RemQty - CASE WHEN a.RemQty >= b.SegmentCapacity THEN b.SegmentCapacity ELSE a.RemQty END
                END,
                b.bin_index,
                CASE WHEN a.RemQty = 0 THEN a.req_index + 1 ELSE a.req_index END
            FROM BinswithLowcost b
            JOIN alloc a
              ON b.bin_index = a.bin_index + 1
            LEFT JOIN Tmp_StorageRequest_B s2
              ON s2.req_index = a.req_index + 1
            WHERE (a.RemQty > 0) OR (s2.req_index IS NOT NULL AND s2.RequestQty > 0)
        )
        SELECT JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'WAVE_ID',      WAVE_ID,
                       'STORAGE_ID',   STORAGE_ID,
                       'BIN_ID',       BIN_ID,
                       'SEGMENT_NO',   SEGMENT_NO,
                       'SKU_ID',       P_SkuId,
                       'BATCH_ID',     P_BatchId,
                       'AllocatedQty', AllocatedQty
                   )
               )
        INTO V_StorageJson
        FROM alloc
        WHERE AllocatedQty > 0;

        IF P_ForProcessing = 1 AND V_StorageJson IS NOT NULL THEN

            INSERT INTO order_bin_mapping (
                BIN_ID, STATION_ID, TYPE, STATUS, IS_SYNCED, INSERTED_TIMESTAMP
            )
            SELECT DISTINCT
                jt.BIN_ID,
                P_StationId,
                'RACK_PICK',
                'PENDING',
                0,
                NOW()
            FROM JSON_TABLE(V_StorageJson, '$[*]' COLUMNS ( BIN_ID INT PATH '$.BIN_ID' )) jt
            LEFT JOIN order_bin_mapping obm_ok
                ON  obm_ok.BIN_ID     = jt.BIN_ID
                AND obm_ok.STATION_ID = P_StationId
                AND obm_ok.TYPE       = 'RACK_PICK'
                AND obm_ok.STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
            WHERE obm_ok.ORDER_BIN_ID IS NULL;

            INSERT INTO put_wave_order_master (
                PUT_ORDER_ID, STATION_ID, WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID,
                ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATUS, SKU_ID, BATCH_ID, EXPECTED_QUANTITY
            )
            SELECT
                UUID(),
                P_StationId,
                jt.WAVE_ID,
                P_StorageRequestId,
                jt.STORAGE_ID,
                COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID),
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING',
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MIN(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK'
                  AND STATUS IN ('PENDING','BIN_PICKED','TASK_ALLOCATED','PRE_ON_STATION')
                GROUP BY BIN_ID, STATION_ID
            ) obm_reuse
              ON obm_reuse.BIN_ID = jt.BIN_ID AND obm_reuse.STATION_ID = P_StationId
            LEFT JOIN (
                SELECT BIN_ID, STATION_ID, MAX(ORDER_BIN_ID) AS ORDER_BIN_ID
                FROM order_bin_mapping
                WHERE TYPE='RACK_PICK' AND STATUS='PENDING'
                GROUP BY BIN_ID, STATION_ID
            ) obm_new
              ON obm_new.BIN_ID = jt.BIN_ID AND obm_new.STATION_ID = P_StationId
            WHERE jt.AllocatedQty > 0
              AND COALESCE(obm_reuse.ORDER_BIN_ID, obm_new.ORDER_BIN_ID) IS NOT NULL
              AND NOT EXISTS (
                  SELECT 1
                  FROM put_wave_order_master p
                  WHERE p.STORAGE_REQUEST_ID = P_StorageRequestId
                    AND p.STORAGE_ID         = jt.STORAGE_ID
                    AND p.BIN_ID             = jt.BIN_ID
                    AND p.BIN_SEGMENT_NO     = jt.SEGMENT_NO
                    AND p.STATUS IN ('PENDING','TASK_ALLOCATED','PUT_STARTED','PUT_IN_PROGRESS')
              );

            UPDATE live_inventory_master L
            INNER JOIN put_wave_order_master PWO
                ON PWO.BIN_ID         = L.BIN_ID
               AND PWO.BIN_SEGMENT_NO = L.SEGMENT_NO
            SET L.VIRTUAL_QUANTITY_TO_PUT = L.VIRTUAL_QUANTITY_TO_PUT + PWO.EXPECTED_QUANTITY,
                L.ARTICLE_ID              = PWO.SKU_ID,
                L.BATCH_ID                = PWO.BATCH_ID
            WHERE (L.ARTICLE_ID = 'no-sku' OR (L.QUANTITY + L.VIRTUAL_QUANTITY_TO_PUT)=0)
              AND PWO.STORAGE_ID = P_StorageId
              AND PWO.STATUS     = 'PENDING';

        ELSEIF V_StorageJson IS NOT NULL AND P_ForProcessing = 0 THEN

            SELECT
                UUID()             AS PUT_ORDER_ID,
                P_StationId        AS STATION_ID,
                jt.WAVE_ID         AS WAVE_ID,
                P_StorageRequestId AS STORAGE_REQUEST_ID,
                jt.STORAGE_ID,
                jt.BIN_ID,
                jt.SEGMENT_NO,
                'PENDING'          AS STATUS,
                jt.SKU_ID,
                jt.BATCH_ID,
                jt.AllocatedQty    AS EXPECTED_QUANTITY
            FROM JSON_TABLE(
                V_StorageJson,
                '$[*]' COLUMNS (
                    WAVE_ID      VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.WAVE_ID',
                    STORAGE_ID   VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.STORAGE_ID',
                    BIN_ID       INT PATH '$.BIN_ID',
                    SEGMENT_NO   INT PATH '$.SEGMENT_NO',
                    SKU_ID       VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.SKU_ID',
                    BATCH_ID     VARCHAR(64) CHARACTER SET latin1 COLLATE latin1_swedish_ci PATH '$.BATCH_ID',
                    AllocatedQty INT PATH '$.AllocatedQty'
                )
            ) jt
            WHERE jt.AllocatedQty > 0;

        END IF;

    END IF;

    
    IF P_ForProcessing = 1 THEN

        SELECT COALESCE(SUM(QUANTITY),0)
        INTO   v_wms_data_total_qty
        FROM   put_wave_wms_data
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        SELECT COALESCE(
                   SUM(
                       CASE
                           WHEN STATUS='PUT_COMPLETED' THEN (PUT_QUANTITY + SHORT_PUT_QUANTITY)
                           ELSE EXPECTED_QUANTITY
                       END
                   ),
                   0
               )
        INTO   v_order_master_total_expected
        FROM   put_wave_order_master
        WHERE  SKU_ID             = P_SkuId
          AND  BATCH_ID           = P_BatchId
          AND  STORAGE_REQUEST_ID = P_StorageRequestId
          AND  STORAGE_ID         = P_StorageId;

        IF v_order_master_total_expected > v_wms_data_total_qty THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'OVER_ALLOCATION: expected exceeds WMS qty';
        END IF;

        SET V_left_over_calc = v_wms_data_total_qty - v_order_master_total_expected;

        UPDATE put_wave_wms_data PW
        SET    PW.STATUS    = 'COMPLETED',
               PW.LEFT_OVER = V_left_over_calc
        WHERE  PW.SKU_ID             = P_SkuId
          AND  PW.BATCH_ID           = P_BatchId
          AND  PW.STATUS             = 'PENDING'
          AND  PW.STORAGE_REQUEST_ID = P_StorageRequestId
          AND  PW.STORAGE_ID         = P_StorageId;

        COMMIT;
    END IF;

    SET SESSION cte_max_recursion_depth = 1000;

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveCheckIfNoSpaceShortPut` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveCheckIfNoSpaceShortPut` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveCheckIfNoSpaceShortPut`(in p_putOrderId varchar(200))
BEGIN
		select * from `short_put_wave_reason` spwr
		where spwr.`PUT_ORDER_ID` = p_putOrderId
		and `REASON` = 'NO_SPACE_IN_BIN';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveCheckIfWaveCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveCheckIfWaveCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveCheckIfWaveCompleted`(
    IN p_waveId VARCHAR(200)
)
BEGIN
	DECLARE v_countTotalPutWaveOrderMaster INT;
	DECLARE v_countCompletedPutWaveOrderMaster INT;
	
	
	
	
	SELECT IFNULL(SUM(`QUANTITY` - `LEFT_OVER`),0)
	INTO v_countTotalPutWaveOrderMaster
	FROM `put_wave_wms_data`
	WHERE `WAVE_ID` = p_waveId;    
	
	SELECT IFNULL(SUM(`PUT_QUANTITY` + `SHORT_PUT_QUANTITY`),0)
	INTO v_countCompletedPutWaveOrderMaster
	FROM `put_wave_order_master`
	WHERE `WAVE_ID` = p_waveId;
	
	UPDATE put_wave_order_master SET STATUS='PUT_COMPLETED' 
	WHERE STATUS ='PUT_STARTED'  
	AND `WAVE_ID` = p_waveId
	AND EXPECTED_QUANTITY=(`PUT_QUANTITY` + IFNULL(`SHORT_PUT_QUANTITY`,0));
	
	
	IF EXISTS (SELECT 1 FROM `put_wave_order_master`
	       WHERE `STATUS` NOT IN ('PUT_COMPLETED', 'INVENTORY_UPDATED')
	       AND `WAVE_ID` = p_waveId) THEN
	
		SELECT 1 AS 'COUNT';
	ELSEIF EXISTS (SELECT 1 FROM `order_bin_mapping`
		   WHERE `STATUS` IN ('PRE_ON_STATION', 'ON_STATION')
		   AND `ORDER_BIN_ID` IN (SELECT `ORDER_BIN_ID` 
					  FROM `put_wave_order_master`
					  WHERE `WAVE_ID` = p_waveId)) THEN
		SELECT 1 AS 'COUNT';
	ELSE
	
		SELECT (v_countTotalPutWaveOrderMaster - v_countCompletedPutWaveOrderMaster) AS 'COUNT';
	END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveCheckIfWaveStopFlagRaised` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveCheckIfWaveStopFlagRaised` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveCheckIfWaveStopFlagRaised`(IN p_waveId varchar(200))
BEGIN
	UPDATE `wms_to_wcs_storage_request_pallet_data` wwsrp
	JOIN (
	SELECT 
	STORAGE_REQUEST_ID,
	IFNULL(SUM(`QUANTITY` - `LEFT_OVER`), 0) AS EXPECTED_QUANTITY
	FROM `put_wave_wms_data`
	WHERE `WAVE_ID` = p_waveId
	GROUP BY STORAGE_REQUEST_ID
	) pwwd ON wwsrp.STORAGE_REQUEST_ID = pwwd.STORAGE_REQUEST_ID
	JOIN (
	SELECT 
	STORAGE_REQUEST_ID,
	IFNULL(SUM(`PUT_QUANTITY` + `SHORT_PUT_QUANTITY`), 0) AS PUT_QUANTITY
	FROM `put_wave_order_master`
	WHERE `WAVE_ID` = p_waveId
	GROUP BY STORAGE_REQUEST_ID
	) pwom ON wwsrp.STORAGE_REQUEST_ID = pwom.STORAGE_REQUEST_ID
	SET 
	wwsrp.`STORAGE_REQUEST_STATUS` = 'PALLET_COMPLETED',
	wwsrp.`PALLET_COMPLETION` = 1,
	wwsrp.`PALLET_COMPLETION_TIMESTAMP` = CURRENT_TIMESTAMP()
	WHERE 
	wwsrp.`STORAGE_REQUEST_STATUS` = 'PALLET_SCANNED'
	AND pwwd.EXPECTED_QUANTITY = pwom.PUT_QUANTITY;
		
	SELECT 'Wave Is No More Accepting New Pallets' FROM `wave_master`
	WHERE `WAVE_ID` = p_waveId
	and (`IS_STOPPED` = 1 or `IS_CANCELLED` = 1)
	LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveCheckLeftOverValidation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveCheckLeftOverValidation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveCheckLeftOverValidation`(
	in WAVE_ID VARCHAR(200)
    )
BEGIN
		SELECT `WAVE_MASTER_ID` FROM `put_wave_wms_data` WHERE `LEFT_OVER` > 0 AND `WAVE_ID`= WAVE_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetAllBinInfoMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetAllBinInfoMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetAllBinInfoMaster`()
BEGIN
    SELECT JSON_OBJECTAGG(`BIN_ID`, JSON_OBJECT(
                         'BinId', b.`BIN_ID`,
                         'SlotSize', b.`BIN_SEGMENTS`,
                         'SkusInBin', (SELECT JSON_ARRAYAGG(
        IF(
            EXISTS (
                SELECT 1 
                FROM live_inventory_master AS lim 
                WHERE lim.BIN_ID = b.`BIN_ID` AND lim.SEGMENT_NO = wsn.SNO
            ),
            (
                SELECT JSON_OBJECT(
                    'ArticleId', lim.ARTICLE_ID,
                    'BatchId', lim.BATCH_ID,
                    'Quantity', IFNULL(lim.QUANTITY, 0) + IFNULL(lim.VIRTUAL_QUANTITY_TO_PUT, 0),
                    'SegmentId', lim.SEGMENT_NO
                )
                FROM live_inventory_master AS lim
                WHERE lim.BIN_ID = b.`BIN_ID` AND lim.SEGMENT_NO = wsn.SNO
                LIMIT 1
            ),
            JSON_OBJECT(
                'ArticleId', NULL,
                'BatchId', NULL,
                'Quantity', 0,
                'SegmentId', wsn.SNO
            )
        )
    )
FROM wm_SequenceNo AS wsn
WHERE SNO <=  b.`BIN_SEGMENTS`)
                    )
        ) AS JSON_DATA
	FROM bin_info_master b;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetAllBinsAllocated` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetAllBinsAllocated` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetAllBinsAllocated`(IN p_waveId varchar(200))
BEGIN
    SELECT `BIN_ID` 
    FROM `put_wave_order_master`
    WHERE `WAVE_ID` = p_waveId
    group by `BIN_ID`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetAllSkuInformation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetAllSkuInformation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetAllSkuInformation`()
BEGIN
	SELECT JSON_OBJECTAGG(
           sr.`SKU_ID`, JSON_OBJECT(
                         'SkuName', sr.`SKU_NAME`,
                         'Category', sr.`CATEGORY`,
                         'MinSlotSize', sr.`MIN_SEGMENT_SIZE`,
                         'MaxBinQuantity', sr.`MAX_QUANTITY_PER_SEGMENT`,
                         'Velocity', sr.`VELOCITY`,
                         'WeightOfEachArticle', sr.`WEIGHT_OF_EACH_SKU`,
                         'TotalQuantityInInventory',IFNULL(LI.v_totalQuantity,0), 
                        'BatchInformation',BI.BatchInformation 
                    )
       ) AS JSON_DATA
	FROM `sku_master` AS sr 
	LEFT OUTER JOIN 
	(
		SELECT ARTICLE_ID,(IFNULL(SUM(IFNULL(IFNULL(`QUANTITY`,0)+IFNULL(`VIRTUAL_QUANTITY_TO_PUT`,0),0)),0)) 
		AS v_totalQuantity
		FROM `live_inventory_master` 
		GROUP BY ARTICLE_ID
        ) LI ON li.ARTICLE_ID=SR.SKU_ID
        LEFT  OUTER  JOIN  
        (
		SELECT sim.SKU_ID,JSON_OBJECTAGG(
		   sim.`BATCH_ID`, JSON_OBJECT(
				 'Mrp', sim.`MRP`,
				 'Expiry', sim.`EXPIRY_DATE`,
				 'Quantity',IFNULL(SBI.TotalQuantity,0) 
			    )
	       ) AS BatchInformation
	       FROM `sku_batch_master` AS sim
	       LEFT OUTER  JOIN (
			SELECT BATCH_ID,ARTICLE_ID,IFNULL(SUM(IFNULL(IFNULL(`QUANTITY`,0)+IFNULL(`VIRTUAL_QUANTITY_TO_PUT`,0),0)),0)
			TotalQuantity
			FROM `live_inventory_master` 
			GROUP BY BATCH_ID,ARTICLE_ID
		)SBI ON SBI.ARTICLE_ID=sim.SKU_ID AND  SBI.BATCH_ID=sim.BATCH_ID
	       GROUP BY sim.SKU_ID
       )BI  ON BI.SKU_ID=sr.SKU_ID;	
       END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetBinsWithNoSpace` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetBinsWithNoSpace` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetBinsWithNoSpace`(p_waveId varchar(200))
BEGIN
		SELECT `BIN_ID`, `SEGMENT_NO`
		FROM `live_inventory_master`
		WHERE `REMARK` = 'NO_SPACE'
		union
		select PWOM.`BIN_ID`, PWOM.`BIN_SEGMENT_NO`
		FROM `put_wave_order_master` PWOM
		JOIN `short_put_wave_reason` SPWR
		ON PWOM.`PUT_ORDER_ID` = SPWR.`PUT_ORDER_ID`
		WHERE SPWR.`REASON` = 'No Space in Bin'
		and PWOM.`WAVE_ID` = p_waveId;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetCurrentProximityScore` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetCurrentProximityScore` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetCurrentProximityScore`()
BEGIN
	DECLARE json_data JSON;
    SELECT 
            JSON_OBJECTAGG(`PARENT_ARTICLE_ID`,`wm_PutWaveGetCurrentProximityScoreInJson`(`PARENT_ARTICLE_ID`))
        INTO json_data
    FROM `article_proximity_score`;
	SELECT json_data as 'JSON_DATA';
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetLeftOverOrders` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetLeftOverOrders` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetLeftOverOrders`(
	IN p_waveId VARCHAR(200)
    )
BEGIN
		SELECT `WAVE_MASTER_ID`,`SKU_ID`,`BATCH_ID`,`QUANTITY`,`LEFT_OVER`
		FROM `put_wave_wms_data` 
		WHERE `LEFT_OVER` > 0 
		AND `WAVE_ID`= p_waveId
		order by QUANTITY desc;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetOrderBinIdByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetOrderBinIdByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetOrderBinIdByStationId`( in p_StationId int)
BEGIN
		select `ORDER_BIN_ID` 
		from `order_bin_mapping` 
		where `STATUS` = 'ON_STATION'
		and `STATION_ID` = p_StationId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetPendingOrders` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetPendingOrders` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetPendingOrders`(
	IN p_waveId VARCHAR(200)
    )
BEGIN
		SELECT `WAVE_MASTER_ID`,`SKU_ID`,`BATCH_ID`,`QUANTITY` 
		FROM `put_wave_wms_data` 
		WHERE `LEFT_OVER` < 0 
		AND `WAVE_ID`= p_waveId
		order by QUANTITY desc;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetPendingPutOrder` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetPendingPutOrder` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetPendingPutOrder`(
    in p_waveId varchar(200),
    in p_stationId int,
    in p_orderBinId int)
BEGIN
 declare v_putcount int;
 DECLARE v_actualputcount INT;
 
  select count(1)from `put_wave_order_master` 
		WHERE `WAVE_ID` = p_waveId
		AND `STATION_ID` = p_stationId
		AND `ORDER_BIN_ID` = p_orderBinId into v_putcount;
		
		
  SELECT COUNT(1)FROM `put_wave_order_master` 
		WHERE  `STATUS` in ('PUT_COMPLETED','INVENTORY_UPDATED')
		AND `WAVE_ID` = p_waveId
		AND `STATION_ID` = p_stationId
		AND `ORDER_BIN_ID` = p_orderBinId INTO v_actualputcount;
		
		select ifnull(v_putcount,0)-IFNULL(v_actualputcount,0);
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetProcessingOrders` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetProcessingOrders` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetProcessingOrders`(
	IN p_waveId VARCHAR(200)
    )
BEGIN
		SELECT `WAVE_MASTER_ID`,`SKU_ID`,`BATCH_ID`,`QUANTITY`,STORAGE_ID 
		FROM `put_wave_wms_data` 
		WHERE `LEFT_OVER` >= 0 
		AND `WAVE_ID`= p_waveId
		order by QUANTITY desc;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetPutCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetPutCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetPutCompleted`(IN p_stationId INT)
BEGIN
    SELECT * 
FROM `put_wave_order_master` pwo
JOIN `order_bin_mapping` obm
on pwo.`ORDER_BIN_ID` = obm.`ORDER_BIN_ID`
WHERE pwo.`STATUS` = 'PUT_COMPLETED'
  AND pwo.`STATION_ID` = p_stationId
  AND NOT EXISTS (
    SELECT 1 
    FROM `put_wave_order_master` pwo2
    WHERE pwo2.`STATUS` in ('PUT_STARTED')
      AND pwo2.`STATION_ID` = pwo.`STATION_ID`
      and pwo2.ORDER_BIN_ID = pwo.`ORDER_BIN_ID`
  )
  and obm.`STATUS` = 'ON_STATION'
  order by pwo.`UPDATED_TIMESTAMP` desc
  limit 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetPutStartedByOrderBinIdSegmentNumber` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetPutStartedByOrderBinIdSegmentNumber` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetPutStartedByOrderBinIdSegmentNumber`(IN p_stationId INT, IN p_skuBarcode VARCHAR(200))
BEGIN
    SELECT * 
    FROM `put_wave_order_master` pwo
    JOIN `sku_ean_mapping` sem ON pwo.`SKU_ID` = sem.`SKU_ID`
    WHERE pwo.`STATUS` = 'PUT_STARTED'
    AND sem.`EAN_ID` = p_skuBarcode
    AND pwo.`STATION_ID` = p_stationId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetQuantityAllocatedBySkuIdBatchIdWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetQuantityAllocatedBySkuIdBatchIdWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetQuantityAllocatedBySkuIdBatchIdWaveId`(
	IN p_waveId VARCHAR(200), in p_skuId varchar(200), in p_batchId varchar(200)
    )
BEGIN
		SELECT IFNULL(SUM(IFNULL(`EXPECTED_QUANTITY`, 0)), 0)
		FROM `put_wave_order_master` 
		WHERE `SKU_ID` = p_skuId
		AND `WAVE_ID`= p_waveId
		and BATCH_ID = p_batchId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetQuantityAllocatedBySkuIdBatchIdWaveIdStorageId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetQuantityAllocatedBySkuIdBatchIdWaveIdStorageId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetQuantityAllocatedBySkuIdBatchIdWaveIdStorageId`(
	IN p_waveId VARCHAR(200), in p_skuId varchar(200), in p_batchId varchar(200), in p_storageId varchar(200)
    )
BEGIN
		SELECT IFNULL(SUM(IFNULL(`EXPECTED_QUANTITY`, 0)), 0)
		FROM `put_wave_order_master` 
		WHERE `SKU_ID` = p_skuId
		AND `WAVE_ID`= p_waveId
		and BATCH_ID = p_batchId
		and STORAGE_ID = p_storageId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetQuantityAllocatedBySkuIdWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetQuantityAllocatedBySkuIdWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetQuantityAllocatedBySkuIdWaveId`(
	IN p_waveId VARCHAR(200), in p_skuId varchar(200)
    )
BEGIN
		SELECT IFNULL(SUM(IFNULL(`EXPECTED_QUANTITY`, 0)), 0)
		FROM `put_wave_order_master` 
		WHERE `SKU_ID` = p_skuId
		AND `WAVE_ID`= p_waveId
		and `STATUS` != 'PUT_COMPLETED';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetQuantityByOrderBinIdBarcode` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetQuantityByOrderBinIdBarcode` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetQuantityByOrderBinIdBarcode`(in p_OrderBinId int, in p_BarcodeScanned varchar(200))
BEGIN
	select pwo.`QUANTITY` 
	from `put_wave_order_master` as pwo
	join ean_article_mapping as eam
	WHERE pwo.`ORDER_BIN_ID`= p_OrderBinId
	and pwo.`STATUS` = 'PUT_STARTED'
	and eam.`EAN` = p_BarcodeScanned
	and pwo.`ARTICLE_ID` = eam.`ARTICLE_ID`
	order by pwo.`SEGMENT` ASC LIMIT 1;
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetRemainingOrderBinByWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetRemainingOrderBinByWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetRemainingOrderBinByWaveId`(
	IN p_waveId VARCHAR(50)
)
BEGIN
	select * FROM `order_bin_mapping`
	WHERE `ORDER_BIN_ID` IN (
		SELECT `ORDER_BIN_ID` 
		FROM `put_wave_order_master` 
		WHERE `WAVE_ID` = p_waveId
	);
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetSkuCategoryMatrix` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetSkuCategoryMatrix` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetSkuCategoryMatrix`()
BEGIN
		SELECT JSON_OBJECTAGG(
        cm.`PARENT_CATEGORY_ID`,
        (SELECT JSON_ARRAYAGG(ccm.`CHILD_CATEGORY_ID`)
         FROM `category_matrix` AS ccm
         WHERE cm.`PARENT_CATEGORY_ID` = ccm.`PARENT_CATEGORY_ID`)
    ) AS JSON_DATA
    FROM `category_matrix` AS cm;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetSkuInformationBySkuId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetSkuInformationBySkuId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetSkuInformationBySkuId`(in p_skuId varchar(200))
BEGIN
	SELECT JSON_OBJECTAGG(
           sr.`SKU_ID`, JSON_OBJECT(
                         'SkuName', sr.`SKU_NAME`,
                         'Category', sr.`CATEGORY`,
                         'MinSlotSize', sr.`MIN_SEGMENT_SIZE`,
                         'MaxBinQuantity', sr.`MAX_QUANTITY_PER_SEGMENT`,
                         'Velocity', sr.`VELOCITY`,
                         'WeightOfEachArticle', sr.`WEIGHT_OF_EACH_SKU`,
                         'TotalQuantityInInventory',IFNULL(LI.v_totalQuantity,0), 
                        'BatchInformation',BI.BatchInformation 
                    )
       ) AS JSON_DATA
	FROM `sku_master` AS sr 
	LEFT OUTER JOIN 
	(
		SELECT ARTICLE_ID,(IFNULL(SUM(IFNULL(IFNULL(`QUANTITY`,0)+IFNULL(`VIRTUAL_QUANTITY_TO_PUT`,0),0)),0)) 
		AS v_totalQuantity
		FROM `live_inventory_master` 
		GROUP BY ARTICLE_ID
        ) LI ON li.ARTICLE_ID=SR.SKU_ID
        LEFT  OUTER  JOIN  
        (
		SELECT sim.SKU_ID,JSON_OBJECTAGG(
		   sim.`BATCH_ID`, JSON_OBJECT(
				 'Mrp', sim.`MRP`,
				 'Expiry', sim.`EXPIRY_DATE`,
				 'Quantity',IFNULL(SBI.TotalQuantity,0) 
			    )
	       ) AS BatchInformation
	       FROM `sku_batch_master` AS sim
	       LEFT OUTER  JOIN (
			SELECT BATCH_ID,ARTICLE_ID,IFNULL(SUM(IFNULL(IFNULL(`QUANTITY`,0)+IFNULL(`VIRTUAL_QUANTITY_TO_PUT`,0),0)),0)
			TotalQuantity
			FROM `live_inventory_master` 
			GROUP BY BATCH_ID,ARTICLE_ID
		)SBI ON SBI.ARTICLE_ID=sim.SKU_ID AND  SBI.BATCH_ID=sim.BATCH_ID
	       GROUP BY sim.SKU_ID
       )BI  ON BI.SKU_ID=sr.SKU_ID
       where sr.`SKU_ID` = p_skuId;	
       END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetStorageRequestDataByPalletId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetStorageRequestDataByPalletId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetStorageRequestDataByPalletId`(
    IN p_waveId VARCHAR(200),
    IN p_palletBarcode VARCHAR(200)
)
BEGIN
    DECLARE v_storageRequestStatus VARCHAR(100);
    DECLARE v_storageRequestId VARCHAR(36);
    DECLARE v_errorMessage TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;
        
        ROLLBACK;
        
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errorMessage;
    END;
    
    START TRANSACTION;
    
    SELECT `STORAGE_REQUEST_STATUS`, `STORAGE_REQUEST_ID`
    INTO v_storageRequestStatus, v_storageRequestId
    FROM `wms_to_wcs_storage_request_pallet_data`
    WHERE `PALLET_ID` = p_palletBarcode
    LIMIT 1;
    
    IF v_storageRequestStatus IS NULL THEN
        SELECT 'Pallet Data Is Not Available' AS Message, 0 AS Status;
    ELSEIF v_storageRequestStatus = 'PENDING' THEN
        SELECT 'Pallet SKU Successfully Added To The Wave' AS Message, 1 AS Status;
        
        INSERT INTO put_wave_wms_data (
            WAVE_ID,
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            SKU_ID,
            BATCH_ID,
            QUANTITY,
            INSERTED_BY,
            UPDATED_BY,
            `LEFT_OVER`
        )
        SELECT 
            p_waveId,
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            ARTICLE_ID AS SKU_ID,
            BATCH_ID,
            QUANTITY,
            INSERTED_BY,
            UPDATED_BY,
            0
        FROM wms_to_wcs_storage_request_data
        WHERE STORAGE_REQUEST_ID = v_storageRequestId;
        
        UPDATE wms_to_wcs_storage_request_pallet_data
        SET 
            `STORAGE_REQUEST_STATUS` = 'PALLET_SCANNED',
            `PALLET_SCANNED_TIMESTAMP` = CURRENT_TIMESTAMP(3),
            `PALLET_SCANNED` = 1
        WHERE `PALLET_ID` = p_palletBarcode;
    ELSEIF v_storageRequestStatus = 'PALLET_SCANNED' THEN
        SELECT 'Pallet SKU Already Added To The Wave' AS Message, 0 AS Status;
    ELSE
        SELECT 'Pallet Data Is Not Available' AS Message, 0 AS Status;
    END IF;
    
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetTotalQuantityInInventoryBySkuId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetTotalQuantityInInventoryBySkuId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetTotalQuantityInInventoryBySkuId`(in p_skuId varchar(200))
BEGIN
		SELECT `wm_PutWaveTotalQuantityBySkuId`(p_skuId);
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveGetWaveDetailsForProximity` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveGetWaveDetailsForProximity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveGetWaveDetailsForProximity`()
BEGIN
		
		Declare v_waveId varchar(200);
		Set v_waveId = '58cce480-bf09-11ef-bb86-d404e6479d98';
		SELECT wm_PutWaveGetWaveDetailsForProximityInJson(v_waveId) as JSON_DATA;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveInsertInPutWaveOrderMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveInsertInPutWaveOrderMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveInsertInPutWaveOrderMaster`(
    IN p_waveId VARCHAR(200),
    IN p_skuId VARCHAR(200),
    IN p_batchId VARCHAR(200),
    IN p_quantity INT,
    IN p_binId INT,
    IN p_segmentNumber INT,
    IN p_stationId INT,
    IN p_orderBinId INT
)
BEGIN
    DECLARE v_putOrderId CHAR(36);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Some Error occurred';
    END;
    
    START TRANSACTION;
    
    IF EXISTS (
        SELECT 1
        FROM `put_wave_order_master`
        WHERE `WAVE_ID` = p_waveId
          AND `SKU_ID` = p_skuId
          AND `BATCH_ID` = p_batchId
          AND `ORDER_BIN_ID` = p_orderBinId
          AND `BIN_ID` = p_binId
          AND `BIN_SEGMENT_NO` = p_segmentNumber
          AND `STATION_ID` = p_stationId
          AND `STATUS` = 'PENDING'
    ) THEN
        
        UPDATE `put_wave_order_master`
        SET `EXPECTED_QUANTITY` = EXPECTED_QUANTITY + p_quantity
        WHERE `WAVE_ID` = p_waveId
          AND `SKU_ID` = p_skuId
          AND `BATCH_ID` = p_batchId
          AND `ORDER_BIN_ID` = p_orderBinId
          AND `BIN_ID` = p_binId
          AND `BIN_SEGMENT_NO` = p_segmentNumber
          AND `STATION_ID` = p_stationId
          AND `STATUS` = 'PENDING';
    ELSE
        
        SELECT UUID() INTO v_putOrderId;
        
        INSERT INTO `put_wave_order_master`
            (`PUT_ORDER_ID`, `WAVE_ID`, `SKU_ID`, 
            `BATCH_ID`, `EXPECTED_QUANTITY`, `ORDER_BIN_ID`, 
            `BIN_ID`, `BIN_SEGMENT_NO`, `STATION_ID`, `STATUS`)
        VALUES
            (v_putOrderId, p_waveId, p_skuId, p_batchId, p_quantity, p_orderBinId, p_binId, p_segmentNumber, p_stationId, 'PENDING');
    END IF;
    
    UPDATE `hw_station_master`
    SET `STATION_UTILISATION` = `STATION_UTILISATION` + p_quantity + 1
    WHERE `STATION_ID` = p_stationId;
    
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveInsertInPutWaveWmsData` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveInsertInPutWaveWmsData` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveInsertInPutWaveWmsData`(
	IN p_waveId VARCHAR(200),
	IN p_skuId VARCHAR(200),
	in p_batchId varchar(200),
	IN p_quantity INT
    )
BEGIN
	INSERT INTO put_wave_wms_data (`WAVE_ID`, `SKU_ID`, `BATCH_ID`, `QUANTITY`)
VALUES (p_waveId, p_skuId, p_batchId, p_quantity)
ON DUPLICATE KEY UPDATE
QUANTITY = QUANTITY + p_quantity;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveInsertProximityScoresFromJson` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveInsertProximityScoresFromJson` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveInsertProximityScoresFromJson`(IN json_data JSON)
BEGIN
    DECLARE parent_key VARCHAR(255);
    DECLARE child_key VARCHAR(255);
    DECLARE proximity_score DECIMAL(10,8);
    DECLARE i INT DEFAULT 0;
    DECLARE j INT DEFAULT 0;
    DECLARE num_parents INT;
    DECLARE num_children INT;
    
    SET num_parents = JSON_LENGTH(json_data);
    
    WHILE i < num_parents DO
        
        SET parent_key = JSON_UNQUOTE(JSON_EXTRACT(JSON_KEYS(json_data), CONCAT('$[', i, ']')));
        
        SET num_children = JSON_LENGTH(JSON_EXTRACT(json_data, CONCAT('$."', parent_key, '"')));
        
        WHILE j < num_children DO
            
            SET child_key = JSON_UNQUOTE(JSON_EXTRACT(JSON_KEYS(JSON_EXTRACT(json_data, CONCAT('$."', parent_key, '"'))), CONCAT('$[', j, ']')));
            
            SET proximity_score = JSON_UNQUOTE(JSON_EXTRACT(JSON_EXTRACT(json_data, CONCAT('$."', parent_key, '"')), CONCAT('$."', child_key, '"')));
            
            INSERT INTO article_proximity_score (PARENT_ARTICLE_ID, CHILD_ARTICLE_ID, PROXIMITY_SCORE)
            VALUES (parent_key, child_key, proximity_score)
            ON DUPLICATE KEY UPDATE PROXIMITY_SCORE = VALUES(PROXIMITY_SCORE);
            
            SET j = j + 1;
        END WHILE;
        
        SET j = 0;
        
        SET i = i + 1;
    END WHILE;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveInsertUpdateLiveInventory` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveInsertUpdateLiveInventory` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveInsertUpdateLiveInventory`(
    IN p_virtualQuantity INT,
    IN p_binId INT,
    IN p_segmentNumber INT,
    IN p_articleId VARCHAR(200),
    IN p_batchId VARCHAR(200)
)
BEGIN
    DECLARE v_existingCount INT;
    DECLARE v_binArticleId CHAR(36);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Some Error occurred';
    END;
    
    START TRANSACTION;
    
    SELECT COUNT(*) INTO v_existingCount
    FROM live_inventory_master
    WHERE BIN_ID = p_binId AND SEGMENT_NO = p_segmentNumber;
    
    IF v_existingCount > 0 THEN
        
        UPDATE live_inventory_master
        SET VIRTUAL_QUANTITY_TO_PUT = p_virtualQuantity + VIRTUAL_QUANTITY_TO_PUT,
            ARTICLE_ID = p_articleId, BATCH_ID = p_batchId 
        WHERE BIN_ID = p_binId AND SEGMENT_NO = p_segmentNumber;
    ELSE
        
        SELECT UUID() INTO v_binArticleId;
        
        
        INSERT INTO live_inventory_master (`BIN_ARTICLE_ID`, BIN_ID, SEGMENT_NO, ARTICLE_ID, `BATCH_ID`, VIRTUAL_QUANTITY_TO_PUT)
        VALUES (v_binArticleId, p_binId, p_segmentNumber, p_articleId, p_batchId, p_virtualQuantity);
    END IF;
    
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveOrderGetPendingOrders` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveOrderGetPendingOrders` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveOrderGetPendingOrders`(
	in WAVE_ID VARCHAR(200)
)
BEGIN
	SELECT wpd.`ARTICLE_ID`
	FROM `put_wave_wms_data` wpd
	WHERE wpd.`STATUS` = 'PENDING' AND wpd.`WAVE_ID` = WAVE_ID AND `LEFT_OVER`= -1 AND wpd.`start_timestamp` IS NULL
	ORDER BY wpd.`QUANTITY` DESC ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveOrderGetProcessingOrders` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveOrderGetProcessingOrders` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveOrderGetProcessingOrders`(
	IN WAVE_ID VARCHAR(200)
)
BEGIN
	SELECT wpd.`ARTICLE_ID`
	FROM `put_wave_wms_data` wpd
	WHERE wpd.`STATUS` = 'PROCESSING' AND wpd.`WAVE_ID` = WAVE_ID AND wpd.`start_timestamp` IS NULL
	ORDER BY wpd.`QUANTITY` DESC ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveOrderMasterArchiveAndRemove` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveOrderMasterArchiveAndRemove` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveOrderMasterArchiveAndRemove`(IN p_waveId CHAR(200), IN p_state varchar(200))
BEGIN
    
    
    INSERT IGNORE INTO `put_wave_order_master_archive` (`PUT_ORDER_ID`,
        WAVE_ID, ORDER_BIN_ID, STATION_ID, BIN_ID, SKU_ID, BIN_SEGMENT_NO, BATCH_ID, EAN_NO,
        EXPECTED_QUANTITY, PUT_QUANTITY, SHORT_PUT_QUANTITY, `STATUS`, PUT_TIMESTAMP, PUT_BY, 
        INSERTED_TIMESTAMP, INSERTED_BY, UPDATED_TIMESTAMP, UPDATED_BY, ARCHIVE_REASON,PUT_START_TIMESTAMP
    )
    SELECT 
        `PUT_ORDER_ID`,WAVE_ID, ORDER_BIN_ID, STATION_ID, BIN_ID, SKU_ID, BIN_SEGMENT_NO, BATCH_ID, EAN_NO,
        EXPECTED_QUANTITY, PUT_QUANTITY, SHORT_PUT_QUANTITY, `STATUS`, PUT_TIMESTAMP, PUT_BY, 
        INSERTED_TIMESTAMP, INSERTED_BY, UPDATED_TIMESTAMP, UPDATED_BY,p_state,PUT_START_TIMESTAMP
    FROM `put_wave_order_master`
    WHERE WAVE_ID = p_waveId;
    
    DELETE FROM put_wave_order_master
    WHERE WAVE_ID = p_waveId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveOrderMasterResetVirtualQuantity` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveOrderMasterResetVirtualQuantity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveOrderMasterResetVirtualQuantity`(IN p_waveId CHAR(200))
BEGIN
    SELECT
	`PUT_ORDER_ID`,
	STORAGE_REQUEST_ID,
	STORAGE_ID,
	BIN_ID, 
	BIN_SEGMENT_NO,
	EXPECTED_QUANTITY
    FROM `put_wave_order_master`
    WHERE WAVE_ID = p_waveId
    AND `STATUS` = 'PENDING';
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveRemoveOrderBinTaskMasterByWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveRemoveOrderBinTaskMasterByWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveRemoveOrderBinTaskMasterByWaveId`(
	IN p_waveId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
	
	CREATE TEMPORARY TABLE IF NOT EXISTS temp_order_bin_ids (
		ORDER_BIN_ID INT NOT NULL,
		index(ORDER_BIN_ID)
	);
	
	INSERT INTO temp_order_bin_ids (ORDER_BIN_ID)
	SELECT `ORDER_BIN_ID` 
	FROM `put_wave_order_master` 
	WHERE `WAVE_ID` = p_waveId;
	
	
	DELETE A  FROM `order_bin_task_master` A
	INNER JOIN temp_order_bin_ids B  ON A.ORDER_BIN_ID=B.ORDER_BIN_ID;
	
	
	
	
	DELETE A  FROM `order_bin_mapping` A
	INNER JOIN temp_order_bin_ids B  ON A.ORDER_BIN_ID=B.ORDER_BIN_ID
	
	WHERE A.`STATUS` ='TASK_COMPLETED';
	
	DELETE A FROM `order_bin_mapping` A
	INNER JOIN temp_order_bin_ids B  ON A.ORDER_BIN_ID=B.ORDER_BIN_ID
	
	WHERE  A.`STATUS` = 'PENDING' AND A.`BOT_ID` IS NULL;
	
	DROP TEMPORARY TABLE IF EXISTS temp_order_bin_ids;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveResetLeftOver` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveResetLeftOver` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveResetLeftOver`(in p_waveId varchar(200))
BEGIN
		UPDATE `put_wave_wms_data` SET `LEFT_OVER` = -1
		WHERE WAVE_ID = p_waveId;
		UPDATE `wave_master` SET `WAVE_STATUS` = 'PENDING'
		WHERE WAVE_ID = p_waveId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveSelectArticlesInCluster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveSelectArticlesInCluster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveSelectArticlesInCluster`(p_waveId VARCHAR(200))
BEGIN
    DECLARE v_clusterId VARCHAR(200);
    DECLARE v_clusterIndex INT DEFAULT 0;
    DECLARE v_articlesLeft INT DEFAULT 1;
    DECLARE p_clusterCount INT DEFAULT 4;
    DECLARE v_relevantLimit INT;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_articles;
    DROP TEMPORARY TABLE IF EXISTS temp_cluster_results;
    DROP TEMPORARY TABLE IF EXISTS temp_processed_skus;
    
    CREATE TEMPORARY TABLE temp_selected_articles (
        SKU_ID VARCHAR(200),
        QUANTITY INT
    );
    
    CREATE TEMPORARY TABLE temp_cluster_results (
        CLUSTER_ID VARCHAR(200),
        SKU_ID VARCHAR(200),
        QUANTITY INT
    );
    
    CREATE TEMPORARY TABLE temp_processed_skus (
        SKU_ID VARCHAR(200) PRIMARY KEY
    );
    
    WHILE v_clusterIndex < p_clusterCount AND v_articlesLeft > 0 DO
        SET v_clusterId = UUID();
        
        
        INSERT INTO temp_selected_articles (SKU_ID, QUANTITY)
        SELECT 
            pwwd.`SKU_ID`, 
            pwwd.`QUANTITY` - IFNULL((SELECT SUM(pwom.`QUANTITY`)
                                      FROM `put_wave_order_master` pwom
                                      WHERE pwom.`SKU_ID` = pwwd.`SKU_ID`), 0) AS `QUANTITY`
        FROM `put_wave_wms_data` AS pwwd
        WHERE pwwd.`WAVE_ID` = p_waveId
            AND `LEFT_OVER` < 0
            AND pwwd.`SKU_ID` NOT IN (SELECT `SKU_ID` FROM temp_processed_skus)
        LIMIT 6;
        
        SET v_articlesLeft = (SELECT COUNT(*) FROM temp_selected_articles);
        
        IF v_articlesLeft > 0 THEN
            INSERT INTO temp_cluster_results (CLUSTER_ID, SKU_ID, QUANTITY)
            SELECT 
                v_clusterId AS CLUSTER_ID, 
                SKU_ID,
                QUANTITY
            FROM 
                temp_selected_articles;
            
            INSERT IGNORE INTO temp_processed_skus (SKU_ID)
            SELECT SKU_ID FROM temp_selected_articles;
            
            SET v_relevantLimit = 6 - v_articlesLeft;
            
            IF v_relevantLimit > 0 THEN
                INSERT INTO temp_cluster_results (CLUSTER_ID, SKU_ID, QUANTITY)
                SELECT 
                    v_clusterId AS CLUSTER_ID,
                    aps.`CHILD_SKU_ID` AS `SKU_ID`,
                    NULL AS `QUANTITY`
                FROM 
                    temp_selected_articles tsa
                JOIN 
                    `article_proximity_score` aps
                ON 
                    tsa.`SKU_ID` = aps.`PARENT_SKU_ID`
                WHERE aps.`CHILD_SKU_ID` NOT IN (SELECT `SKU_ID` FROM temp_processed_skus)
                LIMIT v_relevantLimit;
                
                
                INSERT IGNORE INTO temp_processed_skus (SKU_ID)
                SELECT `CHILD_SKU_ID` FROM `article_proximity_score`
                WHERE `PARENT_SKU_ID` IN (SELECT `SKU_ID` FROM temp_selected_articles)
                LIMIT v_relevantLimit;
            END IF;
        END IF;
        
        DELETE FROM temp_selected_articles;
        
        SET v_clusterIndex = v_clusterIndex + 1;
    END WHILE;
    
    SELECT CLUSTER_ID, SKU_ID, COALESCE(QUANTITY, 0) AS QUANTITY FROM temp_cluster_results WHERE QUANTITY>0;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_articles;
    DROP TEMPORARY TABLE IF EXISTS temp_cluster_results;
    DROP TEMPORARY TABLE IF EXISTS temp_processed_skus;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWavesToReleaseObjects` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWavesToReleaseObjects` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWavesToReleaseObjects`(
	IN inserted_time_ TIMESTAMP
    )
BEGIN
		SELECT * FROM `wave_master` 
		WHERE `WAVE_STATUS` IN ('PENDING','UPLOADED','STATION_SELECTED','PROCESSING') 
		AND `INSERTED_TIMESTAMP` > inserted_time_
		AND `WAVE_TYPE` IN ('PUT', 'PUT_STORAGE_REQUEST');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveUpdateLeftOverByArticleId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveUpdateLeftOverByArticleId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveUpdateLeftOverByArticleId`( in p_articleId varchar(200), IN p_batchId VARCHAR(200), in p_leftOverQuantity INT, IN p_waveId varchar(200))
BEGIN
		UPDATE put_wave_wms_data 
		SET LEFT_OVER = p_leftOverQuantity  
		WHERE `SKU_ID` = p_articleId
		and `BATCH_ID` = p_batchId
		and `WAVE_ID` = p_waveId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveUpdateLeftoverStatusInWaveMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveUpdateLeftoverStatusInWaveMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveUpdateLeftoverStatusInWaveMaster`(IN p_waveId VARCHAR(200))
BEGIN
		DECLARE v_leftoverCount INT;
		SELECT COUNT(*)
		INTO v_leftoverCount
		FROM `put_wave_wms_data`
		WHERE `LEFT_OVER` > 0
		AND `WAVE_ID` = p_waveId;
		
		IF v_leftoverCount > 0 THEN
		UPDATE wave_master
		SET LEFT_OVER_STATUS = 'IS_LEFT_OVER'
		WHERE WAVE_ID = p_waveId;
		ELSE
		UPDATE wave_master
		SET LEFT_OVER_STATUS = 'NO_LEFT_OVER'
		WHERE WAVE_ID = p_waveId;
		END IF;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveUpdateLiveInventoryQuantity` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveUpdateLiveInventoryQuantity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveUpdateLiveInventoryQuantity`(
    IN p_quantity INT,
    IN p_binId INT,
    IN p_segmentNumber INT,
    IN p_articleId VARCHAR(200),
    IN p_batchId VARCHAR(200),
    IN p_waveId VARCHAR(200),
    in p_shortPutQuantity int,
    in p_remark varchar(200)
)
BEGIN
    DECLARE v_existingCount INT;
    DECLARE v_binArticleId CHAR(36);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Some Error occurred';
    END;
    
    START TRANSACTION;
    SET @global_v_waveId = p_waveId;
    
    SELECT COUNT(*) INTO v_existingCount
    FROM live_inventory_master
    WHERE BIN_ID = p_binId AND SEGMENT_NO = p_segmentNumber;
    IF v_existingCount > 0 THEN
	INSERT INTO query_rollback_error_log (error_number, error_message)
	SELECT 'multi_live_entry', 
	       (VIRTUAL_QUANTITY_TO_PUT - (p_quantity + p_shortPutQuantity))
	FROM live_inventory_master
	WHERE (VIRTUAL_QUANTITY_TO_PUT - (p_quantity + p_shortPutQuantity)) < 0
	and `BIN_ID` = p_binId and `SEGMENT_NO` = p_segmentNumber;
        
        UPDATE live_inventory_master
        SET `QUANTITY` = p_quantity + `QUANTITY`,
            ARTICLE_ID = p_articleId, BATCH_ID = p_batchId,
            `VIRTUAL_QUANTITY_TO_PUT` = `VIRTUAL_QUANTITY_TO_PUT` - (p_quantity + p_shortPutQuantity),
            REMARK = p_remark
        WHERE BIN_ID = p_binId AND SEGMENT_NO = p_segmentNumber
        and (`VIRTUAL_QUANTITY_TO_PUT` - (p_quantity + p_shortPutQuantity))>=0;
        
    ELSE
        
        SELECT UUID() INTO v_binArticleId;
        
        INSERT INTO live_inventory_master (`BIN_ARTICLE_ID`, BIN_ID, SEGMENT_NO, ARTICLE_ID, `BATCH_ID`, QUANTITY)
        VALUES (v_binArticleId, p_binId, p_segmentNumber, p_articleId, p_batchId, p_quantity);
    END IF;
    
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveUpdatePutStarted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveUpdatePutStarted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveUpdatePutStarted`(
    IN p_waveId VARCHAR(200),
    IN p_stationId INT,
    IN p_orderBinId INT)
BEGIN
   DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Some Error occurred';
    END;
    
    IF NOT EXISTS (
        SELECT 1
        FROM `put_wave_order_master`
        WHERE `STATUS` = 'PUT_STARTED'
        AND `WAVE_ID` = p_waveId
        AND `STATION_ID` = p_stationId
        AND `ORDER_BIN_ID` = p_orderBinId
    ) THEN
       
    START TRANSACTION;
        
        UPDATE `put_wave_order_master` 
        SET `STATUS` = 'PUT_STARTED', PUT_START_TIMESTAMP = CURRENT_TIMESTAMP(3)
        WHERE `WAVE_ID` = p_waveId
        AND `STATION_ID` = p_stationId
        AND `ORDER_BIN_ID` = p_orderBinId
        AND `STATUS` = 'PENDING'
        ORDER BY `BIN_SEGMENT_NO` ASC
        LIMIT 1;
     COMMIT;
    END IF;
    
    SELECT * FROM `put_wave_order_master` 
    WHERE `STATUS` = 'PUT_STARTED'
    AND `WAVE_ID` = p_waveId
    AND `STATION_ID` = p_stationId
    AND `ORDER_BIN_ID` = p_orderBinId;
     
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveUpdateVirtualQuantityUponCancellation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveUpdateVirtualQuantityUponCancellation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveUpdateVirtualQuantityUponCancellation`(
    IN p_binId INT,
    IN p_segmentNumber INT,
    IN p_virtualQuantity INT,
    IN p_putOrderId varchar(50)
)
BEGIN
    DECLARE v_errorMessage TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;
        ROLLBACK;
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errorMessage;
    END;
    START TRANSACTION;
    IF (
        IFNULL(
            (SELECT VIRTUAL_QUANTITY_TO_PUT 
             FROM live_inventory_master 
             WHERE BIN_ID = p_binId AND SEGMENT_NO = p_segmentNumber),
        0) - p_virtualQuantity < 0
    ) THEN
        UPDATE live_inventory_master
        SET VIRTUAL_QUANTITY_TO_PUT = 0
        WHERE BIN_ID = p_binId AND SEGMENT_NO = p_segmentNumber;
    ELSE
        UPDATE live_inventory_master
        SET VIRTUAL_QUANTITY_TO_PUT = VIRTUAL_QUANTITY_TO_PUT - p_virtualQuantity
        WHERE BIN_ID = p_binId AND SEGMENT_NO = p_segmentNumber;
    END IF;
    
    update `put_wave_order_master`
    set `STATUS` = 'PUT_SUSPENDED'
    WHERE `PUT_ORDER_ID` = p_putOrderId;
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutWaveWmsDataArchiveAndRemove` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutWaveWmsDataArchiveAndRemove` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutWaveWmsDataArchiveAndRemove`(IN p_waveId CHAR(200), IN p_state varchar(200))
BEGIN
    
    INSERT IGNORE INTO `put_wave_wms_data_archive` (
        `WAVE_MASTER_ID`,`WAVE_ID`,SKU_ID, BATCH_ID, QUANTITY, MRP, EXPIRY_DATE, LEFT_OVER, LEFT_OVER_JSON_FLAG,
        INSERTED_TIMESTAMP, INSERTED_BY, UPDATED_TIMESTAMP, UPDATED_BY,`ARCHIVE_REASON`
    )
    SELECT 
        `WAVE_MASTER_ID`,WAVE_ID,SKU_ID, BATCH_ID, QUANTITY, MRP, EXPIRY_DATE, LEFT_OVER, LEFT_OVER_JSON_FLAG,
        INSERTED_TIMESTAMP, INSERTED_BY, UPDATED_TIMESTAMP, UPDATED_BY,p_state
    FROM put_wave_wms_data
    WHERE WAVE_ID = p_waveId;
    
    DELETE FROM put_wave_wms_data
    WHERE WAVE_ID = p_waveId;
   
    DELETE FROM `put_wave_wms_data_dsb_upload_validation`
    WHERE WAVE_ID = p_waveId;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ReleaseStationUponWaveCompletion` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ReleaseStationUponWaveCompletion` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ReleaseStationUponWaveCompletion`(IN p_waveId VARCHAR(200))
BEGIN
	
    UPDATE `wave_station_rule_mapping`
    SET `BOT_COUNT_CURRENT` = BOT_COUNT_CURRENT,
    `WAVE_ID` = NULL
    WHERE `STATION_ID` in (select `STATION_ID` 
    from hw_station_master 
    where `WAVE_ID` = p_waveId);
    
    
    UPDATE `hw_station_master` 
    SET `WAVE_ID` = NULL,
        `WAVE_STATUS` = 'NO_WAVE', 
        `STATION_UTILISATION` = 0,
        `LOGGED_IN_USER_ID` = null
    WHERE `WAVE_ID` = p_waveId;
    
    UPDATE `wave_master`
    SET `COMPLETED_TIMESTAMP` = CURRENT_TIMESTAMP(3)
    WHERE `WAVE_ID` = p_waveId;
    
    CALL `wm_ArchiveAndDeleteWaveMaster`(p_waveId);
    
    
    DELETE FROM `order_bin_mapping` WHERE `STATUS` = 'TASK_COMPLETED';
     
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectAllArticleMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectAllArticleMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectAllArticleMaster`()
BEGIN
		SELECT * FROM `article_info_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectAllBinInfoMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectAllBinInfoMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectAllBinInfoMaster`()
BEGIN
		SELECT * FROM `bin_info_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectAllBinsByMinSlotSizeAndVelocity` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectAllBinsByMinSlotSizeAndVelocity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectAllBinsByMinSlotSizeAndVelocity`(
	IN p_minSlotSize INT, IN p_velocity INT
)
BEGIN
		SELECT BIM.`BIN_ID`
		FROM `bin_info_master` BIM
		LEFT JOIN (SELECT DISTINCT(`BIN_ID`), `VELOCITY`, COST FROM `store_bin_master` WHERE NOT ISNULL(BIN_ID)
		UNION 
		SELECT DISTINCT(`PREV_BIN_ID`), `VELOCITY`,COST FROM `store_bin_master` WHERE NOT ISNULL(PREV_BIN_ID)) SBM
		ON BIM.BIN_ID = SBM.BIN_ID
		WHERE BIM.`BIN_SEGMENTS` = p_minSlotSize
		    AND SBM.`VELOCITY` = p_velocity 
		    AND SBM.`COST` > 0;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectAllWaves` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectAllWaves` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectAllWaves`(
	
    )
BEGIN
		select * from `wave_master` 
		where `WAVE_STATUS` NOT IN ('COMPLETED');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectArticleInBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectArticleInBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectArticleInBin`(
	IN BIN_ID INT
    )
BEGIN
		SELECT * FROM `live_inventory_master` WHERE `BIN_ID`= BIN_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectAssignedStations` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectAssignedStations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectAssignedStations`(
       in p_waveId VARCHAR(200)
    )
BEGIN 
		SELECT `STATION_ID`, `STATUS`, `WAVE_STATUS`
		FROM `hw_station_master` 
		WHERE `WAVE_ID`= p_waveId;
		
		update `hw_station_master`
		set `STATION_UTILISATION` = 0
		where `WAVE_ID` = p_waveId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectBinRecallPendingBins` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectBinRecallPendingBins` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectBinRecallPendingBins`(
	in whereStatus varchar(200)
    )
BEGIN
		select * from `bin_recall_wave_order_master` where status = whereStatus;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectBinRecallWMSBins` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectBinRecallWMSBins` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectBinRecallWMSBins`(
	in waveID varchar(200),
	in whereStatus varchar(200)
    )
BEGIN
		select * from `bin_recall_wave_wms_data` where `WAVE_ID` = waveID AND status = whereStatus;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectBinsAllocatedToBotList` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectBinsAllocatedToBotList` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectBinsAllocatedToBotList`(
	IN p_minSlotSize INT, IN p_velocity INT
    )
BEGIN
		SELECT OBM.`ORDER_BIN_ID`,OBM.`STATION_ID`,OBM.`BIN_ID`
		FROM `order_bin_mapping` OBM
		LEFT JOIN `bin_info_master` BIM 
		ON BIM.`BIN_ID` = OBM.`BIN_ID` 
		WHERE BIM.`BIN_SEGMENTS` = p_minSlotSize
		and OBM.BOT_ID is not null;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectBinsFromRack` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectBinsFromRack` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectBinsFromRack`(
	IN p_minSlotSize INT, IN p_velocity INT
)
BEGIN
		SELECT BIM.`BIN_ID` 
		FROM `bin_info_master` BIM
		JOIN `store_bin_master` SBM 
		ON BIM.`BIN_ID` = SBM.`BIN_ID` 
		WHERE BIM.`BIN_SEGMENTS` = p_minSlotSize
		AND SBM.VELOCITY = p_velocity 
		AND SBM.`COST` > 0
		and BIM.`BIN_TYPE` = 'SEGMENT'
		and SBM.`LOCATION_ID` not in (select `LOCATION_ID` from `location_block_master`)
		ORDER BY SBM.`COST`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectBinsInQueue` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectBinsInQueue` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectBinsInQueue`(
	IN p_minSlotSize INT, IN p_velocity INT
    )
BEGIN
		SELECT OBM.`ORDER_BIN_ID`,OBM.`STATION_ID`,OBM.`BIN_ID` 
		FROM `order_bin_mapping` OBM
		LEFT JOIN `bin_info_master` BIM 
		ON BIM.`BIN_ID` = OBM.`BIN_ID` 
		WHERE BIM.`BIN_SEGMENTS` = p_minSlotSize
		and OBM.BOT_ID is NULL
		and OBM.`STATUS` NOT IN ('ON_STATION','OPERATION_COMPLETED');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectBinStationWithStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectBinStationWithStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectBinStationWithStationId`(
	IN stationID INT,
	in whereStatus varchar(200)
    )
BEGIN
		SELECT `STATUS`,`ORDER_BIN_ID`,`BOT_ID`, `STATION_ID`, `BIN_ID` FROM `order_bin_mapping` WHERE STATUS = whereStatus and `STATION_ID`= stationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectBinStatusOnBot` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectBinStatusOnBot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectBinStatusOnBot`(
	IN botID VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in whereStatus varchar(200)
    )
BEGIN
		SELECT `STATUS`,`ORDER_BIN_ID`,BIN_ID FROM 
		`order_bin_mapping` 
		WHERE `BOT_ID` = botID 
		and STATUS = whereStatus;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectBinWithNotInStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectBinWithNotInStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectBinWithNotInStatus`(
    IN whereStatusList VARCHAR(200) 
)
BEGIN
    SET @query = CONCAT('SELECT `STATUS`,`ORDER_BIN_ID`,`BOT_ID` FROM `order_bin_mapping` WHERE `STATUS` NOT IN (', whereStatusList, ')');
    PREPARE stmt FROM @query;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectBotAllocatedBinList` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectBotAllocatedBinList` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectBotAllocatedBinList`(
	in p_minSlotSize int, IN p_velocity INT
)
BEGIN
		SELECT OBM.`ORDER_BIN_ID`,OBM.`STATION_ID`,OBM.`BIN_ID` from `order_bin_mapping` OBM
		LEFT JOIN `bin_info_master` BIM on BIM.`BIN_ID` = OBM.`BIN_ID` 
		where BOT_ID is not null AND BIM.`BIN_SEGMENTS` <= p_minSlotSize;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectCountOfBinRecallBins` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectCountOfBinRecallBins` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectCountOfBinRecallBins`(
	in waveID varchar(200)
    )
BEGIN
		SELECT count(`BIN_RECALL_ORDER_ID`) from `bin_recall_wave_wms_data` where `WAVE_ID` = waveID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectOrderBinFromBinAndStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectOrderBinFromBinAndStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectOrderBinFromBinAndStation`(
	in binID int,
	in stationID int,
	in whereStatus varchar(50)
    )
BEGIN
		select * from `order_bin_mapping` 
		where `BIN_ID` = binID 
		and `STATION_ID` = stationID 
		AND `STATUS` = whereStatus;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectOrderBinIDWithBinStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectOrderBinIDWithBinStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_SelectOrderBinIDWithBinStation`(
    IN binID INT,
    IN stationID INT,
    IN whereType VARCHAR(50)
)
BEGIN
    
    IF EXISTS (
        SELECT 1 FROM store_bin_master WHERE bin_id = binID
    ) THEN
    update store_bin_master set bin_id = null,
    `AUDIT` = 1 where bin_id  = binID;
        

    
    ELSEIF EXISTS (
        SELECT 1 FROM order_bin_mapping 
        WHERE `TYPE` = whereType 
          AND `STATION_ID` = stationID 
          AND `STATUS` = 'PENDING'
    ) THEN
        SELECT * FROM order_bin_mapping 
        WHERE `TYPE` = whereType 
          AND `STATION_ID` = stationID 
          AND `STATUS` = 'PENDING';

    
    ELSEIF EXISTS (
        SELECT 1 FROM order_bin_mapping 
        WHERE `TYPE` = whereType 
          AND `STATION_ID` = stationID 
          AND bin_id = binID
          AND `STATUS` = 'TASK_ALLOCATED'
    ) THEN
        SELECT * FROM order_bin_mapping 
        WHERE `TYPE` = whereType 
          AND `STATION_ID` = stationID 
          AND bin_id = binID
          AND `STATUS` = 'TASK_ALLOCATED';

    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectPutStartedRowsOnStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectPutStartedRowsOnStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectPutStartedRowsOnStation`(
	in WAVE_ID VARCHAR(200),
	IN STATION_ID INT
    )
BEGIN
	SELECT `WAVE_MASTER_ID` FROM `put_wave_order_master` WHERE `STATION_ID`=STATION_ID AND `WAVE_ID`= WAVE_ID AND `STATUS`= 'PUT_STARTED';
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectWaveCanceled` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectWaveCanceled` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectWaveCanceled`(
	in waveID varchar(200)
    )
BEGIN
		select `IS_CANCELED` from `wave_master` where wave_id = waveID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectWaveCancelled` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectWaveCancelled` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectWaveCancelled`(
	IN waveID VARCHAR(200)
    )
BEGIN
		SELECT `IS_CANCELLED` FROM `wave_master` WHERE wave_id = waveID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_SelectWavesToReleaseObjects` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_SelectWavesToReleaseObjects` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_SelectWavesToReleaseObjects`(
	IN inserted_time_ TIMESTAMP
    )
BEGIN
		SELECT * FROM `wave_master` 
		WHERE `WAVE_STATUS` IN ('PENDING','UPLOADED','STATION_SELECTED') 
		AND `INSERTED_TIMESTAMP` > inserted_time_;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_A01_to_A23` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_A01_to_A23` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_A01_to_A23`(
    IN p_total_bins INT
)
BEGIN
    DECLARE aisle_idx INT DEFAULT 1;  
    DECLARE total_aisles INT DEFAULT 23;  
    DECLARE bin_count INT;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE target_bin_count INT;
    DECLARE aisle_name VARCHAR(10);
    DECLARE tower INT;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10),
        z INT
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / total_aisles);
    SET extra_bins = p_total_bins MOD total_aisles;
    WHILE aisle_idx <= total_aisles DO
        SET aisle_name = CONCAT('A', LPAD(aisle_idx, 2, '0'));
        IF (aisle_idx - 1) < extra_bins THEN
            SET target_bin_count = bins_per_aisle + 1;
        ELSE
            SET target_bin_count = bins_per_aisle;
        END IF;
        SET bin_count = 0;
        SET tower = 1;
        WHILE bin_count < target_bin_count DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number, z)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number, lm.z
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
              AND CAST(sbm.bin_id AS UNSIGNED) NOT BETWEEN 5600 AND 5900
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET bin_count = bin_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_idx = aisle_idx + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_A01_to_A24` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_A01_to_A24` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_A01_to_A24`(
    IN p_total_bins INT
)
BEGIN
    DECLARE aisle_idx INT DEFAULT 1;
    DECLARE total_aisles INT DEFAULT 24;
    DECLARE bin_count INT;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE target_bin_count INT;
    DECLARE aisle_name VARCHAR(10);
    DECLARE tower INT;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10)
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / total_aisles);
    SET extra_bins = p_total_bins MOD total_aisles;
    WHILE aisle_idx <= 24 DO
        SET aisle_name = CONCAT('A', LPAD(aisle_idx, 2, '0'));
        IF (aisle_idx - 1) < extra_bins THEN
            SET target_bin_count = bins_per_aisle + 1;
        ELSE
            SET target_bin_count = bins_per_aisle;
        END IF;
        SET bin_count = 0;
        SET tower = 1;
        WHILE bin_count < target_bin_count DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET bin_count = bin_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_idx = aisle_idx + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_A02_to_A23` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_A02_to_A23` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_A02_to_A23`(
    IN p_total_bins INT
)
BEGIN
    DECLARE aisle_idx INT DEFAULT 2;
    DECLARE total_aisles INT DEFAULT 22;
    DECLARE bin_count INT;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE target_bin_count INT;
    DECLARE aisle_name VARCHAR(10);
    DECLARE tower INT;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10),
        z int
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / total_aisles);
    SET extra_bins = p_total_bins MOD total_aisles;
    WHILE aisle_idx <= 23 DO
        SET aisle_name = CONCAT('A', LPAD(aisle_idx, 2, '0'));
        IF (aisle_idx - 1) < extra_bins THEN
            SET target_bin_count = bins_per_aisle + 1;
        ELSE
            SET target_bin_count = bins_per_aisle;
        END IF;
        SET bin_count = 0;
        SET tower = 1;
        WHILE bin_count < target_bin_count DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number, z)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number, lm.z
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET bin_count = bin_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_idx = aisle_idx + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_A02_to_A23_pareto` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_A02_to_A23_pareto` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_A02_to_A23_pareto`(
    IN p_total_bins INT
)
BEGIN
    DECLARE aisle_idx INT DEFAULT 2;
    DECLARE total_aisles INT DEFAULT 22;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE target_bin_count INT;
    DECLARE aisle_name VARCHAR(10);
    DECLARE tower INT;
    DECLARE target_low_z_bin_count INT;
    DECLARE target_high_z_bin_count INT;
    DECLARE bin_low_z INT;
    DECLARE bin_high_z INT;
    DECLARE v_bin_id VARCHAR(50);
    DECLARE v_location_id INT;
    DECLARE v_aisle_number VARCHAR(10);
    DECLARE v_tower_number VARCHAR(10);
    DECLARE v_z INT;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10),
        z_level INT
    );
    SET bins_per_aisle = FLOOR(p_total_bins / total_aisles);
    SET extra_bins = p_total_bins MOD total_aisles;
    WHILE aisle_idx <= 23 DO
        SET aisle_name = CONCAT('A', LPAD(aisle_idx, 2, '0'));
        IF (aisle_idx - 1) < extra_bins THEN
            SET target_bin_count = bins_per_aisle + 1;
        ELSE
            SET target_bin_count = bins_per_aisle;
        END IF;
        SET target_low_z_bin_count = FLOOR(target_bin_count * 0.7);
        SET target_high_z_bin_count = target_bin_count - target_low_z_bin_count;
        SET bin_low_z = 0;
        SET bin_high_z = 0;
        SET tower = 1;
        
        WHILE bin_low_z < target_low_z_bin_count DO
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number, lm.z
            INTO v_bin_id, v_location_id, v_aisle_number, v_tower_number, v_z
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND lm.z BETWEEN 0 AND 10
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
              AND sbm.bin_id NOT IN (
                  SELECT bin_id FROM (SELECT bin_id FROM temp_selected_bins) AS t
              )
            ORDER BY RAND()
            LIMIT 1;
            IF v_bin_id IS NOT NULL THEN
                INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number, z_level)
                VALUES (v_bin_id, v_location_id, v_aisle_number, v_tower_number, v_z);
                SET bin_low_z = bin_low_z + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        
        WHILE bin_high_z < target_high_z_bin_count DO
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number, lm.z
            INTO v_bin_id, v_location_id, v_aisle_number, v_tower_number, v_z
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND lm.z BETWEEN 11 AND 21
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
              AND sbm.bin_id NOT IN (
                  SELECT bin_id FROM (SELECT bin_id FROM temp_selected_bins) AS t
              )
            ORDER BY RAND()
            LIMIT 1;
            IF v_bin_id IS NOT NULL THEN
                INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number, z_level)
                VALUES (v_bin_id, v_location_id, v_aisle_number, v_tower_number, v_z);
                SET bin_high_z = bin_high_z + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_idx = aisle_idx + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins ORDER BY aisle_number, tower_number, z_level;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_from_6_aisles` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_from_6_aisles` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_from_6_aisles`(IN p_total_bins INT)
BEGIN
    DECLARE aisle_index INT DEFAULT 1;
    DECLARE tower INT;
    DECLARE bin_count INT;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE total_bins_for_aisle INT;
    
    DECLARE v_aisle VARCHAR(10);
    DECLARE aisles_array JSON;
    SET aisles_array = JSON_ARRAY('A01', 'A02', 'A03', 'A04', 'A05', 'A06');
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10)
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / 6);
    SET extra_bins = p_total_bins MOD 6;
    WHILE aisle_index <= 6 DO
        
        SET v_aisle = JSON_UNQUOTE(JSON_EXTRACT(aisles_array, CONCAT('$[', aisle_index - 1, ']')));
        IF aisle_index <= extra_bins THEN
            SET total_bins_for_aisle = bins_per_aisle + 1;
        ELSE
            SET total_bins_for_aisle = bins_per_aisle;
        END IF;
        SET bin_count = 0;
        SET tower = 1;
        WHILE bin_count < total_bins_for_aisle DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = v_aisle
              AND lm.tower_number = tower
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET bin_count = bin_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_index = aisle_index + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins LIMIT p_total_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_from_7_aisles` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_from_7_aisles` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_from_7_aisles`(
    IN p_total_bins INT
)
BEGIN
    DECLARE aisle_index INT DEFAULT 1;
    DECLARE tower INT;
    DECLARE bin_count INT;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE total_bins_for_aisle INT;
    
    DECLARE v_aisle VARCHAR(10);
    DECLARE aisles_array JSON;
    SET aisles_array = JSON_ARRAY('A01', 'A02', 'A03', 'A04', 'A05', 'A06', 'A07');
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10)
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / 7);
    SET extra_bins = p_total_bins MOD 7;
    WHILE aisle_index <= 7 DO
        
        SET v_aisle = JSON_UNQUOTE(JSON_EXTRACT(aisles_array, CONCAT('$[', aisle_index - 1, ']')));
        IF aisle_index <= extra_bins THEN
            SET total_bins_for_aisle = bins_per_aisle + 1;
        ELSE
            SET total_bins_for_aisle = bins_per_aisle;
        END IF;
        SET bin_count = 0;
        SET tower = 1;
        WHILE bin_count < total_bins_for_aisle DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = v_aisle
              AND lm.tower_number = tower
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET bin_count = bin_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_index = aisle_index + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_from_A01_to_A09` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_from_A01_to_A09` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_from_A01_to_A09`(IN p_total_bins INT)
BEGIN
    DECLARE aisle_idx INT DEFAULT 1;
    DECLARE tower INT;
    DECLARE bin_count INT;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE target_bin_count INT;
    DECLARE aisle_name VARCHAR(10);
    DECLARE total_aisles INT DEFAULT 9;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10)
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / total_aisles);
    SET extra_bins = p_total_bins MOD total_aisles;
    WHILE aisle_idx <= total_aisles DO
        SET aisle_name = CONCAT('A', LPAD(aisle_idx, 2, '0'));
        
        IF aisle_idx <= extra_bins THEN
            SET target_bin_count = bins_per_aisle + 1;
        ELSE
            SET target_bin_count = bins_per_aisle;
        END IF;
        SET bin_count = 0;
        SET tower = 1;
        
        WHILE bin_count < target_bin_count DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET bin_count = bin_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_idx = aisle_idx + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_from_A01_to_A11` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_from_A01_to_A11` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_from_A01_to_A11`(IN p_total_bins INT)
BEGIN
    DECLARE aisle_idx INT DEFAULT 1;
    DECLARE tower INT;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE target_bin_count INT;
    DECLARE aisle_name VARCHAR(10);
    DECLARE total_aisles INT DEFAULT 11;
    DECLARE low_z_bin_target INT;
    DECLARE high_z_bin_target INT;
    DECLARE low_z_count INT;
    DECLARE high_z_count INT;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10)
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / total_aisles);
    SET extra_bins = p_total_bins MOD total_aisles;
    WHILE aisle_idx <= total_aisles DO
        SET aisle_name = CONCAT('A', LPAD(aisle_idx, 2, '0'));
        
        IF aisle_idx <= extra_bins THEN
            SET target_bin_count = bins_per_aisle + 1;
        ELSE
            SET target_bin_count = bins_per_aisle;
        END IF;
        SET low_z_bin_target = FLOOR(target_bin_count * 0.7);
        SET high_z_bin_target = target_bin_count - low_z_bin_target;
        SET low_z_count = 0;
        SET high_z_count = 0;
        SET tower = 1;
        
        WHILE low_z_count < low_z_bin_target DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND lm.z BETWEEN 0 AND 11
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET low_z_count = low_z_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET tower = 1;
        
        WHILE high_z_count < high_z_bin_target DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND lm.z BETWEEN 12 AND 21
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET high_z_count = high_z_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_idx = aisle_idx + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_from_A01_to_A12` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_from_A01_to_A12` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_from_A01_to_A12`(IN p_total_bins INT)
BEGIN
    DECLARE aisle_idx INT DEFAULT 1;
    DECLARE tower INT;
    DECLARE bin_count INT;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE target_bin_count INT;
    DECLARE aisle_name VARCHAR(10);
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10)
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / 12);
    SET extra_bins = p_total_bins MOD 12;
    WHILE aisle_idx <= 12 DO
        SET aisle_name = CONCAT('A', LPAD(aisle_idx, 2, '0'));
        IF aisle_idx <= extra_bins THEN
            SET target_bin_count = bins_per_aisle + 1;
        ELSE
            SET target_bin_count = bins_per_aisle;
        END IF;
        SET bin_count = 0;
        SET tower = 1;
        WHILE bin_count < target_bin_count DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET bin_count = bin_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_idx = aisle_idx + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_from_A01_to_A12_perito` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_from_A01_to_A12_perito` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_from_A01_to_A12_perito`(IN p_total_bins INT)
BEGIN
    DECLARE aisle_idx INT DEFAULT 1;
    DECLARE tower INT;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE target_bin_count INT;
    DECLARE aisle_name VARCHAR(10);
    DECLARE total_aisles INT DEFAULT 12;  
    DECLARE low_z_bin_target INT;
    DECLARE high_z_bin_target INT;
    DECLARE low_z_count INT;
    DECLARE high_z_count INT;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10)
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / total_aisles);
    SET extra_bins = p_total_bins MOD total_aisles;
    WHILE aisle_idx <= total_aisles DO
        SET aisle_name = CONCAT('A', LPAD(aisle_idx, 2, '0'));
        
        IF aisle_idx <= extra_bins THEN
            SET target_bin_count = bins_per_aisle + 1;
        ELSE
            SET target_bin_count = bins_per_aisle;
        END IF;
        SET low_z_bin_target = FLOOR(target_bin_count * 0.7);
        SET high_z_bin_target = target_bin_count - low_z_bin_target;
        SET low_z_count = 0;
        SET high_z_count = 0;
        SET tower = 1;
        
        WHILE low_z_count < low_z_bin_target DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND lm.z BETWEEN 0 AND 11
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET low_z_count = low_z_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET tower = 1;
        
        WHILE high_z_count < high_z_bin_target DO
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle_name
              AND lm.tower_number = tower
              AND lm.z BETWEEN 12 AND 21
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            IF ROW_COUNT() > 0 THEN
                SET high_z_count = high_z_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1;
            END IF;
        END WHILE;
        SET aisle_idx = aisle_idx + 1;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_bins_from_three_aisles` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_bins_from_three_aisles` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_bins_from_three_aisles`()
BEGIN
    DECLARE aisle VARCHAR(10);
    DECLARE tower INT;
    DECLARE bin_count INT;
    DECLARE target_bin_count INT;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10)
    );
    
    
    
    SET aisle = 'A09';
    SET target_bin_count = 20;
    SET bin_count = 0;
    SET tower = 1;
    WHILE bin_count < target_bin_count DO
        INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
        SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
        FROM store_bin_master sbm
        JOIN location_master lm ON sbm.location_id = lm.location_id
        WHERE lm.aisle_number = aisle
          AND lm.tower_number = tower
          AND sbm.bin_id IS NOT NULL
          AND sbm.audit = 0
        ORDER BY RAND()
        LIMIT 1;
        IF ROW_COUNT() > 0 THEN
            SET bin_count = bin_count + 1;
        END IF;
        SET tower = tower + 1;
        IF tower > 10 THEN
            SET tower = 1;
        END IF;
    END WHILE;
    
    
    
    SET aisle = 'A10';
    SET target_bin_count = 40;
    SET bin_count = 0;
    SET tower = 1;
    WHILE bin_count < target_bin_count DO
        INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
        SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
        FROM store_bin_master sbm
        JOIN location_master lm ON sbm.location_id = lm.location_id
        WHERE lm.aisle_number = aisle
          AND lm.tower_number = tower
          AND sbm.bin_id IS NOT NULL
          AND sbm.audit = 0
        ORDER BY RAND()
        LIMIT 1;
        IF ROW_COUNT() > 0 THEN
            SET bin_count = bin_count + 1;
        END IF;
        SET tower = tower + 1;
        IF tower > 10 THEN
            SET tower = 1;
        END IF;
    END WHILE;
    
    
    
    SET aisle = 'A11';
    SET target_bin_count = 20;
    SET bin_count = 0;
    SET tower = 1;
    WHILE bin_count < target_bin_count DO
        INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
        SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
        FROM store_bin_master sbm
        JOIN location_master lm ON sbm.location_id = lm.location_id
        WHERE lm.aisle_number = aisle
          AND lm.tower_number = tower
          AND sbm.bin_id IS NOT NULL
          AND sbm.audit = 0
        ORDER BY RAND()
        LIMIT 1;
        IF ROW_COUNT() > 0 THEN
            SET bin_count = bin_count + 1;
        END IF;
        SET tower = tower + 1;
        IF tower > 10 THEN
            SET tower = 1;
        END IF;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_custom_aisles` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_custom_aisles` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_custom_aisles`(
    IN p_total_bins INT,
    IN p_aisle_1 VARCHAR(10),
    IN p_aisle_2 VARCHAR(10),
    IN p_aisle_3 VARCHAR(10)
)
BEGIN
    DECLARE tower INT;
    DECLARE bin_count INT;
    DECLARE bins_aisle1 INT;
    DECLARE bins_aisle2 INT;
    DECLARE bins_aisle3 INT;
    DECLARE bins_per_aisle INT;
    DECLARE total_bins_for_aisle INT;
    
    SET bins_aisle2 = FLOOR(p_total_bins / 2);  
    SET bins_aisle1 = FLOOR(p_total_bins / 4);  
    SET bins_aisle3 = p_total_bins - bins_aisle1 - bins_aisle2; 
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(10),
        tower_number VARCHAR(10)
    );
    
    
    
    SET bin_count = 0;
    SET tower = 1;
    WHILE bin_count < bins_aisle1 DO
        INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
        SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
        FROM store_bin_master sbm
        JOIN location_master lm ON sbm.location_id = lm.location_id
        WHERE lm.aisle_number = p_aisle_1
          AND lm.tower_number = tower
          AND sbm.bin_id IS NOT NULL
          AND sbm.audit = 0
        ORDER BY RAND()
        LIMIT 1;
        IF ROW_COUNT() > 0 THEN
            SET bin_count = bin_count + 1;
        END IF;
        SET tower = tower + 1;
        IF tower > 10 THEN
            SET tower = 1;
        END IF;
    END WHILE;
    
    SET bin_count = 0;
    SET tower = 1;
    WHILE bin_count < bins_aisle2 DO
        INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
        SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
        FROM store_bin_master sbm
        JOIN location_master lm ON sbm.location_id = lm.location_id
        WHERE lm.aisle_number = p_aisle_2
          AND lm.tower_number = tower
          AND sbm.bin_id IS NOT NULL
          AND sbm.audit = 0
        ORDER BY RAND()
        LIMIT 1;
        IF ROW_COUNT() > 0 THEN
            SET bin_count = bin_count + 1;
        END IF;
        SET tower = tower + 1;
        IF tower > 10 THEN
            SET tower = 1;
        END IF;
    END WHILE;
    
    SET bin_count = 0;
    SET tower = 1;
    WHILE bin_count < bins_aisle3 DO
        INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
        SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
        FROM store_bin_master sbm
        JOIN location_master lm ON sbm.location_id = lm.location_id
        WHERE lm.aisle_number = p_aisle_3
          AND lm.tower_number = tower
          AND sbm.bin_id IS NOT NULL
          AND sbm.audit = 0
        ORDER BY RAND()
        LIMIT 1;
        IF ROW_COUNT() > 0 THEN
            SET bin_count = bin_count + 1;
        END IF;
        SET tower = tower + 1;
        IF tower > 10 THEN
            SET tower = 1;
        END IF;
    END WHILE;
    
    SELECT * FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_uniform_random_bins` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_uniform_random_bins` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_uniform_random_bins`(IN p_total_bins INT)
BEGIN
    DECLARE aisle INT DEFAULT 1;
    DECLARE tower INT;
    DECLARE bin_count INT;
    DECLARE total_aisles INT DEFAULT 24;
    DECLARE bins_per_aisle INT;
    DECLARE extra_bins INT;
    DECLARE total_bins_for_aisle INT;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins (
        bin_id VARCHAR(50) PRIMARY KEY,
        location_id INT,
        aisle_number VARCHAR(3),
        tower_number VARCHAR(3)
    );
    
    SET bins_per_aisle = FLOOR(p_total_bins / total_aisles);
    SET extra_bins = p_total_bins MOD total_aisles;
    WHILE aisle <= total_aisles DO
        IF aisle <= extra_bins THEN
            SET total_bins_for_aisle = bins_per_aisle + 1;
        ELSE
            SET total_bins_for_aisle = bins_per_aisle;
        END IF;
        SET bin_count = 0;
        SET tower = 1;
        WHILE bin_count < total_bins_for_aisle DO
            
            INSERT IGNORE INTO temp_selected_bins (bin_id, location_id, aisle_number, tower_number)
            SELECT sbm.bin_id, lm.location_id, lm.aisle_number, lm.tower_number
            FROM store_bin_master sbm
            JOIN location_master lm ON sbm.location_id = lm.location_id
            WHERE lm.aisle_number = aisle
              AND lm.tower_number = tower
              AND sbm.bin_id IS NOT NULL
              AND sbm.audit = 0
            ORDER BY RAND()
            LIMIT 1;
            
            IF ROW_COUNT() > 0 THEN
                SET bin_count = bin_count + 1;
            END IF;
            SET tower = tower + 1;
            IF tower > 10 THEN
                SET tower = 1; 
            END IF;
        END WHILE;
        SET aisle = aisle + 1;
    END WHILE;
 
 
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_select_uniform_random_bins_generic` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_select_uniform_random_bins_generic` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_select_uniform_random_bins_generic`(IN p_total_bins INT)
BEGIN
    DECLARE total_towers INT;
    DECLARE bins_per_tower INT;
    DECLARE extra_bins INT;
    
    DROP TEMPORARY TABLE IF EXISTS aisle_tower_map;
    CREATE TEMPORARY TABLE aisle_tower_map AS
    SELECT DISTINCT
        aisle_number,
        tower_number
    FROM location_master
    ORDER BY aisle_number, tower_number;
    
    SELECT COUNT(*) INTO total_towers FROM aisle_tower_map;
    
    SET bins_per_tower = FLOOR(p_total_bins / total_towers);
    SET extra_bins = p_total_bins MOD total_towers;
    
    DROP TEMPORARY TABLE IF EXISTS tower_bin_quota;
    CREATE TEMPORARY TABLE tower_bin_quota AS
    SELECT 
        atm.aisle_number,
        atm.tower_number,
        ROW_NUMBER() OVER (ORDER BY atm.aisle_number, atm.tower_number) AS row_num,
        CASE 
            WHEN ROW_NUMBER() OVER (ORDER BY atm.aisle_number, atm.tower_number) <= extra_bins 
            THEN bins_per_tower + 1
            ELSE bins_per_tower
        END AS quota
    FROM aisle_tower_map atm;
    
    DROP TEMPORARY TABLE IF EXISTS random_bin_pool;
    CREATE TEMPORARY TABLE random_bin_pool AS
    SELECT 
        sbm.bin_id,
        sbm.location_id,
        lm.aisle_number,
        lm.tower_number,
        RAND() AS r
    FROM store_bin_master sbm
    JOIN location_master lm ON sbm.location_id = lm.location_id
    WHERE sbm.bin_id IS NOT NULL
      AND sbm.audit = 0;
    
    DROP TEMPORARY TABLE IF EXISTS ranked_bins;
    CREATE TEMPORARY TABLE ranked_bins AS
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY aisle_number, tower_number
            ORDER BY r
        ) AS rank_within_tower
    FROM random_bin_pool;
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    CREATE TEMPORARY TABLE temp_selected_bins AS
    SELECT rb.*
    FROM ranked_bins rb
    JOIN tower_bin_quota tq
      ON rb.aisle_number = tq.aisle_number
     AND rb.tower_number = tq.tower_number
    WHERE rb.rank_within_tower <= tq.quota
    LIMIT p_total_bins;
    
    SELECT bin_id FROM temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditCheckIfWaveCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditCheckIfWaveCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditCheckIfWaveCompleted`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    DECLARE v_countTotalStockAuditWaveWMS INT;
    DECLARE v_countCompletedStockAuditOrderMaster INT;
    
    
    SELECT COUNT(DISTINCT `BIN_ID`, `BIN_SEGMENT_NO`)
    INTO v_countTotalStockAuditWaveWMS
    FROM `stock_audit_wave_wms_data`
    WHERE `WAVE_ID`= p_waveId;
    
    
    SELECT COUNT(DISTINCT `BIN_ID`, `BIN_SEGMENT_NO`)
    INTO v_countCompletedStockAuditOrderMaster
    FROM `stock_audit_wave_order_master`
    WHERE `STATUS` = 'AUDIT_COMPLETED' 
    AND `WAVE_ID`= p_waveId;
    
    IF EXISTS (SELECT 1 FROM `order_bin_mapping`
                   WHERE `STATUS` IN ('PRE_ON_STATION', 'ON_STATION')
                   AND `ORDER_BIN_ID` IN (SELECT `ORDER_BIN_ID` 
                                          FROM `stock_audit_wave_order_master`
                                          WHERE `WAVE_ID` = p_waveId)) THEN
        SELECT 1 AS 'COUNT';
    ELSE
         
	SELECT (v_countTotalStockAuditWaveWMS - v_countCompletedStockAuditOrderMaster) AS 'COUNT';
    END IF;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditGetAisleEntryLocationIdByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditGetAisleEntryLocationIdByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditGetAisleEntryLocationIdByBinId`(
    IN p_binId INT
)
BEGIN
    WITH aisle_map AS (
        SELECT 
            CONCAT('A', LPAD(ROW_NUMBER() OVER (ORDER BY Y), 2, '0')) AS AISLE_NUMBER,
            LOCATION_ID,
            Y
        FROM location_master
        WHERE TYPE = 'aisle_entry'
    ),
    bin_location AS (
        SELECT 
            sb.BIN_ID,
            sb.LOCATION_ID,
            lm.`AISLE_NUMBER`
        FROM store_bin_master sb
        JOIN location_master lm ON sb.LOCATION_ID = lm.LOCATION_ID
        WHERE sb.BIN_ID = p_binId
    )
    SELECT 
        am.LOCATION_ID AS AISLE_ENTRY_LOCATION_ID
    FROM bin_location bl
    JOIN aisle_map am ON bl.AISLE_NUMBER = am.AISLE_NUMBER;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditGetAlreadyAllocatedStationIdByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditGetAlreadyAllocatedStationIdByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditGetAlreadyAllocatedStationIdByBinId`(in p_binId int, in p_waveId varchar(200))
BEGIN
		select `STATION_ID` 
		from `stock_audit_wave_order_master`
		where `BIN_ID` = p_binId
		and `WAVE_ID` = p_waveId
		and `STATUS` in ('PENDING')
		limit 1;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditProcessLeftOver` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditProcessLeftOver` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditProcessLeftOver`(in p_waveId varchar(200))
BEGIN
		update `stock_audit_wave_wms_data` 
		set `LEFT_OVER` = 0
		where `WAVE_ID` = p_waveId;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditRemoveOrderBinTaskMasterByWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditRemoveOrderBinTaskMasterByWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditRemoveOrderBinTaskMasterByWaveId`(
	IN p_waveId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
	
	CREATE TEMPORARY TABLE IF NOT EXISTS temp_order_bin_ids (
		ORDER_BIN_ID INT NOT NULL,
		index(ORDER_BIN_ID)
	) Engine=memory;
	
	INSERT INTO temp_order_bin_ids (ORDER_BIN_ID)
	SELECT `ORDER_BIN_ID` 
	FROM `stock_audit_wave_order_master`
	WHERE `WAVE_ID` = p_waveId;
	
	DELETE A  FROM `order_bin_task_master` A
	INNER JOIN temp_order_bin_ids B  ON A.ORDER_BIN_ID=B.ORDER_BIN_ID;
	
	
	
	
	DELETE A  FROM `order_bin_mapping` A
	INNER JOIN temp_order_bin_ids B  ON A.ORDER_BIN_ID=B.ORDER_BIN_ID
	
	where A.`STATUS` ='TASK_COMPLETED';
	
	DELETE A FROM `order_bin_mapping` A
	inner Join temp_order_bin_ids B  on A.ORDER_BIN_ID=B.ORDER_BIN_ID
	
	where  A.`STATUS` = 'PENDING' AND A.`BOT_ID` Is NULL;
	
	DROP TEMPORARY TABLE IF EXISTS temp_order_bin_ids;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveCancelTaskByOrderBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveCancelTaskByOrderBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveCancelTaskByOrderBinId`(
	IN p_orderBinId INT, 
	IN p_waveId VARCHAR(200)
)
BEGIN
	DECLARE v_totalRowCount INT DEFAULT 0;
	DECLARE v_deletedRowCount INT DEFAULT 0;
	DECLARE v_errorMessage TEXT;
	
	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
		
		GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;
		
		ROLLBACK;
		
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errorMessage;
	END;
	START TRANSACTION;
	
	SELECT COUNT(*) INTO v_totalRowCount 
	FROM stock_audit_wave_order_master
	WHERE `ORDER_BIN_ID` = p_orderBinId
	  AND `STATUS` = 'PENDING'
	  AND `WAVE_ID` = p_waveId;
	
	DELETE FROM stock_audit_wave_order_master
	WHERE `ORDER_BIN_ID` = p_orderBinId
	  AND `STATUS` = 'PENDING'
	  AND `WAVE_ID` = p_waveId;
	
	SET v_deletedRowCount = ROW_COUNT();
	
	COMMIT;
	
	SELECT 
		IFNULL(v_totalRowCount, 0) AS TOTAL_ROWS, 
		IFNULL(v_deletedRowCount, 0) AS DELETED_ROWS;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveCheckIfLocationBlockedByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveCheckIfLocationBlockedByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveCheckIfLocationBlockedByBinId`(
	IN p_binId INT
)
BEGIN
	select BIN_ID
	FROM `store_bin_master`
	WHERE `LOCATION_ID` IN (SELECT `LOCATION_ID` FROM `location_block_master`)
	AND BIN_ID = p_binId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveGetAllBinInfoMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveGetAllBinInfoMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveGetAllBinInfoMaster`()
BEGIN
		
    SELECT JSON_OBJECTAGG(`BIN_ID`, JSON_OBJECT(
                         'BinId', b.`BIN_ID`,
                         'SlotSize', b.`BIN_SEGMENTS`,
                         'SkusInBin', (SELECT JSON_ARRAYAGG(
        IF(
            EXISTS (
                SELECT 1 
                FROM live_inventory_master AS lim 
                WHERE lim.BIN_ID = b.`BIN_ID` AND lim.SEGMENT_NO = wsn.SNO
            ),
            (
                SELECT JSON_OBJECT(
                    'ArticleId', lim.ARTICLE_ID,
                    'BatchId', lim.BATCH_ID,
                    'Quantity', IFNULL(lim.QUANTITY, 0),
                    'SegmentId', lim.SEGMENT_NO
                )
                FROM live_inventory_master AS lim
                WHERE lim.BIN_ID = b.`BIN_ID` AND lim.SEGMENT_NO = wsn.SNO
                LIMIT 1
            ),
            JSON_OBJECT(
                'ArticleId', NULL,
                'BatchId', NULL,
                'Quantity', 0,
                'SegmentId', wsn.SNO
            )
        )
    )
FROM wm_SequenceNo AS wsn
WHERE SNO <=  b.`BIN_SEGMENTS`)
                    )
        ) AS JSON_DATA
	FROM bin_info_master b;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveGetAllPendingOrders` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveGetAllPendingOrders` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveGetAllPendingOrders`(in p_waveId varchar(200))
BEGIN
		select * from `stock_audit_wave_wms_data`
		where `WAVE_ID` = p_waveId
		and `IS_PROCESSED` = 0;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveGetAuditCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveGetAuditCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveGetAuditCompleted`(IN p_stationId INT)
BEGIN
    SELECT * 
FROM `stock_audit_wave_order_master` swo
JOIN `order_bin_mapping` obm
on swo.`ORDER_BIN_ID` = obm.`ORDER_BIN_ID`
WHERE swo.`STATUS` = 'AUDIT_COMPLETED'
  AND swo.`STATION_ID` = p_stationId
  AND NOT EXISTS (
    SELECT 1 
    FROM `stock_audit_wave_order_master` swo2
    WHERE swo2.`STATUS` = 'AUDIT_STARTED'
      AND swo2.`STATION_ID` = swo.`STATION_ID`
  )
  and obm.`STATUS` = 'ON_STATION'
  order by swo.`UPDATED_TIMESTAMP` desc 
  limit 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveGetAuditStarted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveGetAuditStarted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveGetAuditStarted`(in p_binId int, in p_orderBinId int)
BEGIN
		select * 
		from `stock_audit_wave_order_master`
		where `BIN_ID` = p_binId
		and `ORDER_BIN_ID` = p_orderBinId
		and `STATUS` in ('AUDIT_STARTED')
		order by `BIN_SEGMENT_NO`
		limit 1;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveGetAuditStartedByOrderBinIdSegmentNumber` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveGetAuditStartedByOrderBinIdSegmentNumber` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveGetAuditStartedByOrderBinIdSegmentNumber`(
    IN p_stationId INT, 
    IN p_skuBarcode VARCHAR(200)
)
BEGIN
    IF EXISTS (
        SELECT 1
        FROM `stock_audit_wave_order_master` pwo
        JOIN `sku_ean_mapping` sem ON pwo.`SKU_ID` = sem.`SKU_ID`
        WHERE pwo.`STATUS` = 'AUDIT_STARTED'
        AND sem.`EAN_ID` = p_skuBarcode
        AND pwo.`STATION_ID` = p_stationId
    ) THEN
        SELECT pwo.*, sm.SKU_NAME, 1 AS 'BARCODE_VALIDITY'
        FROM `stock_audit_wave_order_master` pwo
        JOIN `sku_ean_mapping` sem ON pwo.`SKU_ID` = sem.`SKU_ID`
        JOIN `sku_master` sm ON pwo.`SKU_ID` = sm.`SKU_ID`
        WHERE pwo.`STATUS` = 'AUDIT_STARTED'
        AND sem.`EAN_ID` = p_skuBarcode
        AND pwo.`STATION_ID` = p_stationId;
    ELSE
        SELECT sem.*, sm.SKU_NAME, 2 AS 'BARCODE_VALIDITY'
        FROM `sku_ean_mapping` sem
        JOIN `sku_master` sm ON sem.`SKU_ID` = sm.`SKU_ID`
        WHERE sem.`EAN_ID` = p_skuBarcode;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveGetDataForProcessing` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveGetDataForProcessing` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveGetDataForProcessing`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    SELECT `WAVE_MASTER_ID`, `BIN_ID`, `BIN_SEGMENT_NO` 
    FROM `stock_audit_wave_wms_data` 
    WHERE `LEFT_OVER` = 0 
    AND `WAVE_ID` = p_waveId
    AND NOT EXISTS (
        SELECT 1 
        FROM `stock_audit_wave_order_master` 
        WHERE `stock_audit_wave_order_master`.`BIN_ID` = `stock_audit_wave_wms_data`.`BIN_ID`
        AND `stock_audit_wave_order_master`.`BIN_SEGMENT_NO` = `stock_audit_wave_wms_data`.`BIN_SEGMENT_NO`
        and `stock_audit_wave_order_master`.`WAVE_ID` = p_waveId
    )
    GROUP BY `BIN_ID`, `BIN_SEGMENT_NO`
    limit 500;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveGetPendingPutOrder` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveGetPendingPutOrder` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveGetPendingPutOrder`(
    in p_waveId varchar(200),
    in p_stationId int,
    in p_orderBinId int)
BEGIN
		select * from `stock_audit_wave_order_master` 
		where `STATUS` = 'PENDING'
		and `WAVE_ID` = p_waveId
		AND `STATION_ID` = p_stationId
		AND `ORDER_BIN_ID` = p_orderBinId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveGetRemainingOrderBinByWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveGetRemainingOrderBinByWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveGetRemainingOrderBinByWaveId`(
	IN p_waveId VARCHAR(50)
)
BEGIN
	SELECT * FROM `order_bin_mapping`
	WHERE `ORDER_BIN_ID` IN (
		SELECT `ORDER_BIN_ID` 
		FROM `stock_audit_wave_order_master` 
		WHERE `WAVE_ID` = p_waveId
	);
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveGetSegmentAssingnedByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveGetSegmentAssingnedByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveGetSegmentAssingnedByBinId`(IN p_binId INT, IN p_orderBinId INT)
BEGIN
		select * 
		from `stock_audit_wave_order_master`
		where `BIN_ID` = p_binId
		and `ORDER_BIN_ID` = p_orderBinId
		and `STATUS` Not in ('PICK_COMPLETED','ORDER_COMPLETED')
		order by `BIN_SEGMENT_NO`
		limit 1;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveInsertInStockAuditOrderMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveInsertInStockAuditOrderMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveInsertInStockAuditOrderMaster`(
	IN p_waveId VARCHAR(200),
	IN p_skuId VARCHAR(200),
	in p_batchId varchar(200),
	IN p_quantity INT,
	IN p_binId INT,
	IN p_segmentNumber INT,
	IN p_stationId INT
    )
BEGIN
    DECLARE v_orderBinId INT;
    declare v_stockAuditOrderId char(36);
    
    SELECT `ORDER_BIN_ID` INTO v_orderBinId
    FROM `order_bin_mapping`
    WHERE BIN_ID = p_binId 
    AND STATION_ID = p_stationId 
    AND STATUS = 'PENDING'
    and `TYPE` = 'RACK_PICK'
    LIMIT 1;
    
    
    IF v_orderBinId IS NULL THEN
        
        INSERT INTO order_bin_mapping (`BIN_ID`, `STATION_ID`, `STATUS`, `TYPE`)
        VALUES (p_binId, p_stationId, 'PENDING','RACK_PICK');
        
        SET v_orderBinId = LAST_INSERT_ID();
    END IF;
		select uuid() into v_stockAuditOrderId;
		INSERT INTO `stock_audit_wave_order_master`
		(`STOCK_AUDIT_ORDER_ID`,`WAVE_ID`,`SKU_ID`,`BATCH_ID`,`EXPECTED_QUANTITY`,`ORDER_BIN_ID`,`BIN_ID`,`BIN_SEGMENT_NO`,`STATION_ID`,`UPDATED_SKU_ID`,`UPDATED_BATCH_ID`,`UPDATED_QUANTITY`)
		VALUES(v_stockAuditOrderId,p_waveId, p_skuId, p_batchId, p_quantity, v_orderBinId, p_binId, p_segmentNumber, p_stationId,p_skuId, p_batchId, p_quantity);
		update `hw_station_master`
		set `STATION_UTILISATION` = `STATION_UTILISATION` + p_quantity + 1
		where `STATION_ID` = p_stationId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveInsertInStockAuditWaveOrderMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveInsertInStockAuditWaveOrderMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveInsertInStockAuditWaveOrderMaster`(
	IN p_waveId VARCHAR(200),
	IN p_binId INT,
	IN p_segmentNumber INT,
	IN p_stationId INT
    )
BEGIN
    DECLARE v_orderBinId INT;
    declare v_stockAuditOrderId char(36);
    declare v_skuId varchar(200);
    declare v_batchId varchar(200);
    declare v_expectedQuantity int;
    
    select `QUANTITY`,`ARTICLE_ID`,`BATCH_ID` into v_expectedQuantity, v_skuId, v_batchId
    from `live_inventory_master`
    where `BIN_ID` = p_binId
    and `SEGMENT_NO` = p_segmentNumber;
    
    IF v_expectedQuantity <= 0 THEN
        SET v_skuId = 'no-sku';
        SET v_batchId = 'no-sku';
    END IF;
    
    
    SELECT `ORDER_BIN_ID` INTO v_orderBinId
    FROM order_bin_mapping
    WHERE BIN_ID = p_binId 
    AND STATION_ID = p_stationId 
    AND `STATUS` NOT IN ('OPERATION_COMPLETED','TASK_COMPLETED','POST_ON_STATION')
    AND `TYPE` = 'RACK_PICK';
    
    
    IF v_orderBinId IS NULL THEN
        
        INSERT INTO order_bin_mapping (`BIN_ID`, `STATION_ID`, `STATUS`,`TYPE`)
        VALUES (p_binId, p_stationId, 'PENDING','RACK_PICK');
        
        SET v_orderBinId = LAST_INSERT_ID();
    END IF;
		select uuid() into v_stockAuditOrderId;
		INSERT INTO `stock_audit_wave_order_master`
		(`STOCK_AUDIT_ORDER_ID`,`WAVE_ID`,`SKU_ID`,`BATCH_ID`,`EXPECTED_QUANTITY`,`ORDER_BIN_ID`,`BIN_ID`,`BIN_SEGMENT_NO`,`STATION_ID`,`STATUS`,`UPDATED_SKU_ID`,`UPDATED_BATCH_ID`,`UPDATED_QUANTITY`)
		VALUES(v_stockAuditOrderId,p_waveId, v_skuId, v_batchId, v_expectedQuantity, v_orderBinId, p_binId, p_segmentNumber, p_stationId,'PENDING',v_skuId, v_batchId, v_expectedQuantity);
		update `hw_station_master`
		set `STATION_UTILISATION` = `STATION_UTILISATION` + v_expectedQuantity + 1
		where `STATION_ID` = p_stationId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveInsertUpdateLiveInventory` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveInsertUpdateLiveInventory` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveInsertUpdateLiveInventory`(
    IN p_quantity INT,
    IN p_binId INT,
    IN p_segmentNumber INT,
    IN p_skuId VARCHAR(200),
    IN p_batchId VARCHAR(200),
    IN p_waveid VARCHAR(200)
)
BEGIN
	DECLARE v_articleBinId CHAR(36);
	
	SET v_articleBinId = UUID();
	SET @global_v_waveId = p_waveId;
	    
	    INSERT INTO live_inventory_master (`BIN_ARTICLE_ID`, BIN_ID, SEGMENT_NO, QUANTITY, ARTICLE_ID, BATCH_ID)
		VALUES (v_articleBinId, p_binId, p_segmentNumber, p_quantity, p_skuId, p_batchId)
		ON DUPLICATE KEY UPDATE
		QUANTITY = VALUES(QUANTITY),
		ARTICLE_ID = if(VALUES(ARTICLE_ID) is null, 'no-sku', VALUES(ARTICLE_ID)),
		BATCH_ID = if(VALUES(BATCH_ID) is null, 'no-sku',VALUES(BATCH_ID)),
		REMARK = CASE WHEN REMARK = 'NO_SPACE' THEN 'NO_SPACE' ELSE NULL end;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveOrderMasterArchiveAndRemove` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveOrderMasterArchiveAndRemove` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveOrderMasterArchiveAndRemove`(IN p_waveId CHAR(200), IN p_state ENUM('ARCHIVED', 'CANCELLED'))
BEGIN
    
    INSERT IGNORE INTO `stock_audit_wave_order_master_archive` (`STOCK_AUDIT_ORDER_ID`, WAVE_ID, ORDER_BIN_ID, BIN_ID, 
        BIN_SEGMENT_NO, `STATUS`, STATION_ID, SKU_ID, BATCH_ID, AUDIT_BY, EXPECTED_QUANTITY, 
        ACTUAL_QUANTITY, UPDATED_SKU_ID, UPDATED_BATCH_ID, UPDATED_QUANTITY, 
        INSERTED_TIMESTAMP, UPDATED_TIMESTAMP, ARCHIVE_REASON
    )
    SELECT 
        `STOCK_AUDIT_ORDER_ID`, WAVE_ID, ORDER_BIN_ID, BIN_ID, 
        BIN_SEGMENT_NO, `STATUS`, STATION_ID, SKU_ID, BATCH_ID, 
        AUDIT_BY, EXPECTED_QUANTITY, ACTUAL_QUANTITY, 
        UPDATED_SKU_ID, UPDATED_BATCH_ID, UPDATED_QUANTITY, 
        INSERTED_TIMESTAMP, UPDATED_TIMESTAMP, p_state
    FROM `stock_audit_wave_order_master`
    WHERE WAVE_ID = p_waveId;
    
    DELETE FROM stock_audit_wave_order_master
    WHERE WAVE_ID = p_waveId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWavesToReleaseObjects` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWavesToReleaseObjects` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWavesToReleaseObjects`(
	IN inserted_time_ TIMESTAMP
    )
BEGIN
		SELECT * FROM `wave_master` 
		WHERE `WAVE_STATUS` IN ('PENDING','UPLOADED','LEFT_OVER','STATION_SELECTED','PROCESSING') 
		AND `INSERTED_TIMESTAMP` > inserted_time_
		AND `WAVE_TYPE` IN ('STOCK_AUDIT', 'LOOP_AUDIT','LOCATION_AUDIT', 'THROUGHPUT_WAVE');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveUpdateAuditStarted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveUpdateAuditStarted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveUpdateAuditStarted`(
    IN p_waveId VARCHAR(200),
    IN p_stationId INT,
    IN p_orderBinId INT)
BEGIN
    
    IF NOT EXISTS (
        SELECT 1
        FROM `stock_audit_wave_order_master`
        WHERE `STATUS` = 'AUDIT_STARTED'
        AND `WAVE_ID` = p_waveId
        AND `STATION_ID` = p_stationId
        AND `ORDER_BIN_ID` = p_orderBinId
    ) THEN
        
        UPDATE `stock_audit_wave_order_master` 
        SET `STATUS` = 'AUDIT_STARTED'
        WHERE `WAVE_ID` = p_waveId
        AND `STATION_ID` = p_stationId
        AND `ORDER_BIN_ID` = p_orderBinId
        AND `STATUS` = 'PENDING'
        ORDER BY `BIN_SEGMENT_NO` ASC
        LIMIT 1;
    END IF;
    
    
    SELECT * FROM `stock_audit_wave_order_master` 
    WHERE `STATUS` = 'AUDIT_STARTED'
    AND `WAVE_ID` = p_waveId
    AND `STATION_ID` = p_stationId
    AND `ORDER_BIN_ID` = p_orderBinId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_StockAuditWaveWmsDataArchiveAndRemove` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_StockAuditWaveWmsDataArchiveAndRemove` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_StockAuditWaveWmsDataArchiveAndRemove`(IN p_waveId CHAR(200), IN p_state VARCHAR(200))
BEGIN
    
    INSERT IGNORE INTO `stock_audit_wave_wms_data_archive` (
        `WAVE_MASTER_ID`, WAVE_ID, BIN_ID, BIN_SEGMENT_NO, SKU_ID, BATCH_ID, LEFT_OVER, ARCHIVE_REASON
    )
    SELECT 
        `WAVE_MASTER_ID`, WAVE_ID, BIN_ID, BIN_SEGMENT_NO, SKU_ID, BATCH_ID, LEFT_OVER, p_state
    FROM stock_audit_wave_wms_data
    WHERE WAVE_ID = p_waveId;
    
    DELETE FROM stock_audit_wave_wms_data
    WHERE WAVE_ID = p_waveId;

    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughputGetAlreadyAllocatedStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughputGetAlreadyAllocatedStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughputGetAlreadyAllocatedStation`(
    IN p_binId INT, 
    IN p_waveId VARCHAR(200),
    IN p_stationId INT
)
BEGIN
    SELECT `STATION_ID` 
    FROM `stock_audit_wave_order_master`
    WHERE `BIN_ID` = p_binId
    AND `WAVE_ID` = p_waveId
    AND `STATUS` IN ('PENDING')
    AND `STATION_ID` != p_stationId
    LIMIT 1;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughputStockAuditWaveGetDataForProcessing` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughputStockAuditWaveGetDataForProcessing` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughputStockAuditWaveGetDataForProcessing`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    SELECT `WAVE_MASTER_ID`, `BIN_ID`, `BIN_SEGMENT_NO` 
    FROM `stock_audit_wave_wms_data` 
    WHERE `LEFT_OVER` = 0 
    AND `WAVE_ID` = p_waveId
    And BIN_SEGMENT_NO = 1
    AND NOT EXISTS (
        SELECT 1 
        FROM `stock_audit_wave_order_master` 
        WHERE `stock_audit_wave_order_master`.`BIN_ID` = `stock_audit_wave_wms_data`.`BIN_ID`
        AND `stock_audit_wave_order_master`.`BIN_SEGMENT_NO` = `stock_audit_wave_wms_data`.`BIN_SEGMENT_NO`
        and `stock_audit_wave_order_master`.`WAVE_ID` = p_waveId
    )
    GROUP BY `BIN_ID`, `BIN_SEGMENT_NO`
    limit 500;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughputwaveCheckCountofBininwmsordermaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughputwaveCheckCountofBininwmsordermaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughputwaveCheckCountofBininwmsordermaster`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    DECLARE wms_data_count INT DEFAULT 0;
    DECLARE order_master_count INT DEFAULT 0;
    DECLARE result INT DEFAULT 0;
    
    
    SELECT COUNT(DISTINCT(`BIN_ID`)) 
    INTO wms_data_count
    FROM `stock_audit_wave_wms_data`
    WHERE `WAVE_ID` = p_waveId;
    
    
    SELECT COUNT(DISTINCT(`BIN_ID`)) 
    INTO order_master_count
    FROM `stock_audit_wave_order_master`
    WHERE `WAVE_ID` = p_waveId;
    
    
    IF wms_data_count = order_master_count THEN
        SET result = 1;
    ELSE
        SET result = 0;
    END IF;
    
    
    SELECT result AS COUNT_MATCH_RESULT;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughputwaveCheckIfWaveCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughputwaveCheckIfWaveCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughputwaveCheckIfWaveCompleted`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    DECLARE v_countTotalOrders INT;
    DECLARE v_countCompletedOrders INT;
    
    
    SELECT COUNT(DISTINCT `BIN_ID`, `BIN_SEGMENT_NO`)
    INTO v_countTotalOrders
    FROM `stock_audit_wave_order_master`
    WHERE `WAVE_ID` = p_waveId;
    
    
    SELECT COUNT(DISTINCT `BIN_ID`, `BIN_SEGMENT_NO`)
    INTO v_countCompletedOrders
    FROM `stock_audit_wave_order_master`
    WHERE `STATUS` = 'AUDIT_COMPLETED' 
    AND `WAVE_ID` = p_waveId;
    
    
    IF EXISTS (SELECT 1 FROM `order_bin_mapping`
               WHERE `STATUS` IN ('PRE_ON_STATION', 'ON_STATION')
               AND `ORDER_BIN_ID` IN (SELECT `ORDER_BIN_ID` 
                                      FROM `stock_audit_wave_order_master`
                                      WHERE `WAVE_ID` = p_waveId)) THEN
        SELECT 1 AS 'COUNT';
    ELSE
        
        SELECT (v_countTotalOrders - v_countCompletedOrders) AS 'COUNT';
    END IF;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughputWaveGetBinOnStationWithStationID` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughputWaveGetBinOnStationWithStationID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughputWaveGetBinOnStationWithStationID`(
    
    IN p_stationId INT
)
BEGIN
    SELECT `BIN_ID`, `UPDATED_TIMESTAMP` 
                                    FROM `order_bin_mapping` 
                                    WHERE `STATION_ID` = p_stationId
                                    AND `STATUS` = 'ON_STATION';
                                END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughputWaveGetDataForProcessing` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughputWaveGetDataForProcessing` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughputWaveGetDataForProcessing`(
    IN p_waveId VARCHAR(200),
    IN p_percentage DECIMAL(5,2)
)
BEGIN
    DECLARE v_totalBinCount INT;
    DECLARE v_distinctStationCount INT;
    DECLARE v_targetTotalBins INT;
    DECLARE v_binsPerStation INT;
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
    
    
    SELECT COUNT(DISTINCT STATION_ID) 
    INTO v_distinctStationCount
    FROM stock_audit_wave_order_master 
    WHERE WAVE_ID = p_waveId;
    
    
    SELECT COUNT(DISTINCT BIN_ID)
    INTO v_totalBinCount
    FROM stock_audit_wave_order_master
    WHERE WAVE_ID = p_waveId;
    
    SET v_targetTotalBins = CEIL(v_totalBinCount * p_percentage / 100);
    
    
    SET v_binsPerStation = CEIL(v_targetTotalBins / v_distinctStationCount);
    
    
    CREATE TEMPORARY TABLE temp_selected_bins AS
    WITH ranked_bins AS (
        SELECT 
            BIN_ID,
            STATION_ID,
            ROW_NUMBER() OVER (PARTITION BY STATION_ID ORDER BY RAND()) as rn
        FROM (
            SELECT DISTINCT BIN_ID, STATION_ID
            FROM stock_audit_wave_order_master 
            WHERE WAVE_ID = p_waveId
        ) distinct_bins
    )
    SELECT BIN_ID
    FROM ranked_bins
    WHERE rn <= v_binsPerStation
    LIMIT v_targetTotalBins;
    
    
    SELECT 
        om.`WAVE_ID`,
        om.BIN_ID,
        om.BIN_SEGMENT_NO,
        om.STATION_ID
    FROM stock_audit_wave_order_master om
    INNER JOIN temp_selected_bins sb ON om.BIN_ID = sb.BIN_ID
    WHERE om.WAVE_ID = p_waveId
    GROUP BY om.`WAVE_ID`, om.BIN_ID, om.BIN_SEGMENT_NO, om.STATION_ID
    ORDER BY om.STATION_ID, om.BIN_ID;
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_selected_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughputWaveGetDuplicateBinsCount` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughputWaveGetDuplicateBinsCount` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughputWaveGetDuplicateBinsCount`(
    IN p_waveId CHAR(200)
)
BEGIN
    
    SELECT COUNT(DISTINCT BIN_ID) AS DUPLICATE_BINS_COUNT
    FROM (
        SELECT BIN_ID, COUNT(*) as entry_count
        FROM `stock_audit_wave_order_master`
        WHERE WAVE_ID = p_waveId
          AND BIN_ID IS NOT NULL
        GROUP BY BIN_ID
        HAVING COUNT(*) > 1
    ) duplicate_bins;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughputWaveInsertInStockAuditWaveOrderMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughputWaveInsertInStockAuditWaveOrderMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughputWaveInsertInStockAuditWaveOrderMaster`(
	IN p_waveId VARCHAR(200),
	IN p_binId INT,
	IN p_segmentNumber INT,
	IN p_stationId INT
    )
BEGIN
    DECLARE v_orderBinId INT;
    DECLARE v_stockAuditOrderId CHAR(36);
    DECLARE v_skuId VARCHAR(200);
    DECLARE v_batchId VARCHAR(200);
    DECLARE v_expectedQuantity INT;
    DECLARE v_existingRecord INT DEFAULT 0;
    
    
    SELECT COUNT(*) INTO v_existingRecord
    FROM `stock_audit_wave_order_master`
    WHERE `BIN_ID` = p_binId 
    AND `STATION_ID` = p_stationId
    AND `STATUS` NOT IN ('OPERATION_COMPLETED','TASK_COMPLETED','POST_ON_STATION');
    
    
    IF v_existingRecord = 0 THEN
        
        SET p_segmentNumber = 1;
        
        SELECT `QUANTITY`,`ARTICLE_ID`,`BATCH_ID` INTO v_expectedQuantity, v_skuId, v_batchId
        FROM `live_inventory_master`
        WHERE `BIN_ID` = p_binId
        AND `SEGMENT_NO` = p_segmentNumber;
        
        IF v_expectedQuantity <= 0 THEN
            SET v_skuId = 'no-sku';
            SET v_batchId = 'no-sku';
        END IF;
        
        
        SELECT `ORDER_BIN_ID` INTO v_orderBinId
        FROM order_bin_mapping
        WHERE BIN_ID = p_binId 
        AND STATION_ID = p_stationId 
        AND `STATUS` NOT IN ('OPERATION_COMPLETED','TASK_COMPLETED','POST_ON_STATION')
        AND `TYPE` = 'RACK_PICK';
        
        
        IF v_orderBinId IS NULL THEN
            
            INSERT INTO order_bin_mapping (`BIN_ID`, `STATION_ID`, `STATUS`)
            VALUES (p_binId, p_stationId, 'PENDING');
            
            SET v_orderBinId = LAST_INSERT_ID();
        END IF;
        
        SELECT UUID() INTO v_stockAuditOrderId;
        INSERT INTO `stock_audit_wave_order_master`
        (`STOCK_AUDIT_ORDER_ID`,`WAVE_ID`,`SKU_ID`,`BATCH_ID`,`EXPECTED_QUANTITY`,`ORDER_BIN_ID`,`BIN_ID`,`BIN_SEGMENT_NO`,`STATION_ID`,`STATUS`,`UPDATED_SKU_ID`,`UPDATED_BATCH_ID`,`UPDATED_QUANTITY`)
        VALUES(v_stockAuditOrderId,p_waveId, v_skuId, v_batchId, v_expectedQuantity, v_orderBinId, p_binId, p_segmentNumber, p_stationId,'PENDING',v_skuId, v_batchId, v_expectedQuantity);
        
        UPDATE `hw_station_master`
        SET `STATION_UTILISATION` = `STATION_UTILISATION` + v_expectedQuantity + 1
        WHERE `STATION_ID` = p_stationId;
    END IF;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughputWaveUpdateBinStatusinOrderMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughputWaveUpdateBinStatusinOrderMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughputWaveUpdateBinStatusinOrderMaster`(
    IN p_binId INT,
    IN p_stationId INT
)
BEGIN
    UPDATE `stock_audit_wave_order_master` 
    SET `STATUS` = 'AUDIT_COMPLETED' 
    WHERE `BIN_ID` = p_binId 
    AND `STATION_ID` = p_stationId;     
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ThroughtputWaveGetAllocationStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ThroughtputWaveGetAllocationStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ThroughtputWaveGetAllocationStatus`(
    IN p_stationId INT,
    IN p_percentage INT,
    IN p_aisleId INT 
)
BEGIN
    DECLARE totalBinsInAisle INT DEFAULT 0;
    DECLARE allocatedBinsCount INT DEFAULT 0;
    DECLARE requiredBinsCount INT DEFAULT 0;
    DECLARE allocationPercentage DECIMAL(5,2) DEFAULT 0;
    DECLARE isAllocationMet BOOLEAN DEFAULT FALSE;
    
    
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_aisle_map AS
    SELECT 
        CONCAT('A', LPAD(ROW_NUMBER() OVER (ORDER BY Y), 2, '0')) AS AISLE_NUMBER,
        LOCATION_ID,
        Y
    FROM location_master
    WHERE TYPE = 'aisle_entry';
    
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_bin_location AS
    SELECT 
        sb.BIN_ID,
        sb.LOCATION_ID,
        lm.`AISLE_NUMBER`
    FROM store_bin_master sb
    JOIN location_master lm ON sb.LOCATION_ID = lm.LOCATION_ID;
    
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_total_bin AS
    SELECT DISTINCT bin_id FROM `stock_audit_wave_wms_data`;
    
    
    SELECT 
        COUNT(*) INTO totalBinsInAisle
    FROM temp_bin_location bl
    JOIN temp_aisle_map am ON bl.AISLE_NUMBER = am.AISLE_NUMBER
    JOIN temp_total_bin tb ON tb.bin_id = bl.bin_id
    WHERE am.location_id = p_aisleId;
    
    
    SELECT 
        COUNT(DISTINCT sawo.BIN_ID) INTO allocatedBinsCount
    FROM stock_audit_wave_order_master sawo
    JOIN temp_bin_location bl ON sawo.BIN_ID = bl.BIN_ID
    JOIN temp_aisle_map am ON bl.AISLE_NUMBER = am.AISLE_NUMBER
    WHERE am.location_id = p_aisleId 
    AND sawo.STATION_ID = p_stationId;
    
    
    SET requiredBinsCount = CEIL((totalBinsInAisle * p_percentage) / 100);
    
    
    IF totalBinsInAisle > 0 THEN
        SET allocationPercentage = (allocatedBinsCount * 100.0) / totalBinsInAisle;
    END IF;
    
    
    SET isAllocationMet = (allocatedBinsCount >= requiredBinsCount);
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_aisle_map;
    DROP TEMPORARY TABLE IF EXISTS temp_bin_location;
    DROP TEMPORARY TABLE IF EXISTS temp_total_bin;
    
    
    IF isAllocationMet THEN
        SELECT 1 AS allocation_status;
    ELSE
        SELECT 0 AS allocation_status;
    END IF;
        
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_UpdateBinRecallMasterOrderStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_UpdateBinRecallMasterOrderStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_UpdateBinRecallMasterOrderStatus`(
	in binID int,
	in stationID int, 
	in whereStatus varchar(50),
	in setStatus varchar(50)
    )
BEGIN
		update `bin_recall_wave_order_master` set `STATUS` = setStatus where `BIN_ID` = binID and `STATION_ID` = stationID and status = whereStatus;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_UpdateBinRecallStationAndOrderBinID` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_UpdateBinRecallStationAndOrderBinID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_UpdateBinRecallStationAndOrderBinID`(
	in binRecallID int,
	in staitonID int,
	in orderBinID int
    )
BEGIN
		update `bin_recall_wave_order_master` set `STATION_ID` = staitonID, `ORDER_BIN_ID` = orderBinID, status = 'TASK_CREATED'
		WHERE `BIN_RECALL_ORDER_ID` = binRecallID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_UpdateBinStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_UpdateBinStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_UpdateBinStatus`(
    IN botID VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN stationID INT,
    IN whereStatus VARCHAR(200),
    IN setStatus VARCHAR(200),
    IN binId INT
)
BEGIN
    
    IF botID = 'NULL' THEN
        UPDATE `order_bin_mapping` 
        SET `STATUS` = setStatus 
        WHERE `STATUS` = whereStatus 
        AND `STATION_ID` = stationID
        AND `BIN_ID` = binId
        AND `BOT_ID` IS NULL;  
    ELSE
        UPDATE `order_bin_mapping` 
        SET `STATUS` = setStatus 
        WHERE `BOT_ID` = botID
        AND `STATUS` = whereStatus 
        AND `STATION_ID` = stationID
        AND `BIN_ID` = binId;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_UpdateConveyorOnStationBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_UpdateConveyorOnStationBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_UpdateConveyorOnStationBinId`(
	IN p_stationId INT,
	IN p_onStationBin INT
    )
BEGIN
		UPDATE `hw_conveyor_master` 
		SET `BIN_ON_STATION` = p_onStationBin
		WHERE `PARENT_ID` = p_stationId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_UpdateOrderLineStatusToCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_UpdateOrderLineStatusToCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_UpdateOrderLineStatusToCompleted`(
    IN p_orderId VARCHAR(100),
    IN p_orderLineId VARCHAR(36)
)
BEGIN
    UPDATE wms_to_wcs_order_line_request_data 
    SET 
        ORDER_LINE_PROCESS_STATUS = 'ORDERLINE_COMPLETED',
        UPDATED_TIMESTAMP = NOW(3),
        UPDATED_BY = 'SYSTEM'
    WHERE 
        ORDER_ID = p_orderId 
        AND ORDER_LINE_ID = p_orderLineId
        AND ORDER_LINE_PROCESS_STATUS IN ('PENDING', 'ORDERLINETAKEN');
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_UpdatePickStarted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_UpdatePickStarted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_UpdatePickStarted`(
	IN STATION_ID INT,
	IN ORDER_BIN_ID INT
    )
BEGIN
		UPDATE `put_wave_order_master` set `STATUS` = 'PUT_STARTED'
		 WHERE `ORDER_BIN_ID`= ORDER_BIN_ID AND `STATION_ID`=STATION_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_UpdateStationWaveStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_UpdateStationWaveStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_UpdateStationWaveStatus`(in p_stationId int, in p_status varchar(100))
BEGIN
		update `hw_station_master` 
		set `WAVE_STATUS` = p_status
		where `STATION_ID` = p_stationId;
		
		UPDATE `hw_station_master` 
		SET `STATION_UTILISATION` = 0
		WHERE `STATION_ID` = p_stationId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_UpdateStoreBinMasterNullByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_UpdateStoreBinMasterNullByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_UpdateStoreBinMasterNullByBinId`(
	in p_binId int
    )
BEGIN
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_UpdateWaveMasterStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_UpdateWaveMasterStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_UpdateWaveMasterStatus`(
	in waveID varchar(100),
	IN setStatus VARCHAR(100)
    )
BEGIN
		UPDATE `wave_master` 
		set `WAVE_STATUS` = setStatus 
		WHERE `WAVE_ID` = waveID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_WaveManagerHealthCheck` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_WaveManagerHealthCheck` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_WaveManagerHealthCheck`()
BEGIN
	DECLARE cnt INT;
	
	SELECT COUNT(*) INTO cnt
	FROM `dashboard_config`
	WHERE `KEY_NAME` = 'FMS_RUNNING';
	
	IF cnt > 0 THEN
		UPDATE `dashboard_config`
		SET `KEY_VALUE` = 1
		WHERE `KEY_NAME` = 'FMS_RUNNING';
	
	ELSE
		INSERT INTO `dashboard_config` (`KEY_NAME`, `KEY_VALUE`)
		VALUES ('FMS_RUNNING', 1);
	END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_WmsToWcsGetAllOrderInformationFromOrderLineRequestData` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_WmsToWcsGetAllOrderInformationFromOrderLineRequestData` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_WmsToWcsGetAllOrderInformationFromOrderLineRequestData`(
    IN p_orderIds TEXT
)
BEGIN
    
    SET p_orderIds = REPLACE(p_orderIds, ' ', '');
    
    
    SELECT JSON_OBJECTAGG(
               W.`ORDER_ID`, B.json_data
           ) AS JSON_DATA
    FROM `wms_to_wcs_order_line_request_data` W 
    LEFT OUTER JOIN (
        SELECT W.ORDER_ID, JSON_OBJECTAGG(
                   W.`ARTICLE_ID`, B.json_data
               ) AS json_data
        FROM `wms_to_wcs_order_line_request_data` W
        LEFT OUTER JOIN (
            SELECT ORDER_ID, ARTICLE_ID, JSON_OBJECTAGG(
                       `BATCH_ID`, SUM_QUANTITY
                   ) json_data
            FROM (
                SELECT ORDER_ID, ARTICLE_ID, BATCH_ID,
                       SUM(QUANTITY) AS SUM_QUANTITY
                FROM wms_to_wcs_order_line_request_data
                WHERE ORDER_LINE_PROCESS_STATUS = 'PENDING'
                  AND FIND_IN_SET(ORDER_ID, p_orderIds) > 0
                GROUP BY ORDER_ID, ARTICLE_ID, BATCH_ID
            ) BI 
            GROUP BY ORDER_ID, ARTICLE_ID
        ) B ON B.ORDER_ID = W.ORDER_ID AND W.ARTICLE_ID = B.ARTICLE_ID
        WHERE W.ORDER_LINE_PROCESS_STATUS = 'PENDING'
          AND FIND_IN_SET(W.ORDER_ID, p_orderIds) > 0
        GROUP BY ORDER_ID
    ) B ON B.ORDER_ID = W.ORDER_ID
    WHERE W.`ORDER_LINE_PROCESS_STATUS` = 'PENDING'
      AND FIND_IN_SET(W.ORDER_ID, p_orderIds) > 0;
END */$$
DELIMITER ;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
