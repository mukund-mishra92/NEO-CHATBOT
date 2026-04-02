
---------------------------------------------------------------------------------------------------------
/* Procedure structure for procedure `wm_PickWaveGetAllBinInfoMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetAllBinInfoMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetAllBinInfoMaster`()
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
                    'Quantity', IFNULL(lim.QUANTITY, 0) - IFNULL(lim.VIRTUAL_QUANTITY_TO_PICK, 0),
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

/* Procedure structure for procedure `wm_PickWaveGetAllOrderArticleQuantity` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetAllOrderArticleQuantity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetAllOrderArticleQuantity`(
	IN p_waveId VARCHAR(200)
)
BEGIN
	SELECT 
    pwwd.`SKU_ID`,
    pwwd.`BATCH_ID`,
    SUM(pwwd.`QUANTITY`) AS QUANTITY
FROM 
    `pick_wave_wms_data` pwwd
WHERE pwwd.`LEFT_OVER` = -1 
    AND pwwd.`WAVE_ID` = p_waveId
GROUP BY 
    pwwd.`SKU_ID`,
    pwwd.`BATCH_ID`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetAllOrderInformation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetAllOrderInformation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetAllOrderInformation`(IN p_waveId VARCHAR(200))
BEGIN
SELECT JSON_OBJECTAGG(
		   P.`ORDER_ID`,B.json_data) AS JSON_DATA
		FROM `pick_wave_wms_data` P 
		LEFT  OUTER  JOIN (
		SELECT P.ORDER_ID,P.WAVE_ID,JSON_OBJECTAGG(
			P.`SKU_ID`, B.json_data
		       )  AS json_data
			FROM `pick_wave_wms_data` P
			LEFT OUTER JOIN (
				SELECT ORDER_ID,SKU_ID,WAVE_ID,JSON_OBJECTAGG(
				   `BATCH_ID`, SUM_QUANTITY
			       ) json_data
			    FROM (
				SELECT ORDER_ID, SKU_ID, WAVE_ID, BATCH_ID,
			       SUM(QUANTITY - CASE WHEN LEFT_OVER <= 0 THEN 0 ELSE LEFT_OVER END) AS SUM_QUANTITY
			FROM pick_wave_wms_data
			GROUP BY ORDER_ID, SKU_ID, WAVE_ID, BATCH_ID
			    ) BI GROUP BY ORDER_ID,SKU_ID,WAVE_ID
			) B  ON B.ORDER_ID=P.ORDER_ID AND  P.WAVE_ID=B.WAVE_ID AND P.SKU_ID=B.SKU_ID
		   GROUP BY ORDER_ID,WAVE_ID
		)B  ON B.ORDER_ID=P.ORDER_ID AND  B.WAVE_ID=P.WAVE_ID
		
		WHERE P.`WAVE_ID` = p_waveId;
			END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetAllSkuInformation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetAllSkuInformation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetAllSkuInformation`()
BEGIN
	SELECT JSON_OBJECTAGG(
           sr.`SKU_ID`, JSON_OBJECT(
                         'SkuName', sr.`SKU_NAME`,
                         'Category', sr.`CATEGORY`,
                         'MinSlotSize', sr.`MIN_SEGMENT_SIZE`,
                         'MaxBinQuantity', sr.`MAX_QUANTITY_PER_SEGMENT`,
                         'MinSplitLocation', sr.`MIN_BIN_STORAGE`,
                         'MaxBin', sr.`MAX_BIN_STORAGE`,
                         'MaxStorageQuantity', sr.`MAX_QUANTITY_STORAGE`,
                         'Velocity', sr.`VELOCITY`,
                         'WeightOfEachArticle', sr.`WEIGHT_OF_EACH_SKU`,
                         'VolumeOfEachArticle', sr.`VOLUME_OF_EACH_SKU`,
                         'TotalQuantityInInventory',IFNULL(LI.v_totalQuantity,0), 
                        'BatchInformation',BI.BatchInformation 
                    )
       ) AS JSON_DATA
	FROM `sku_master` AS sr 
	LEFT OUTER JOIN 
	(
		SELECT ARTICLE_ID,(IFNULL(SUM(IFNULL(IFNULL(`QUANTITY`,0)-IFNULL(`VIRTUAL_QUANTITY_TO_PICK`,0),0)),0)) 
		AS v_totalQuantity
		FROM `live_inventory_master` 
		WHERE IFNULL(REMARK,'') NOT IN ('AUDIT_MARKED') 
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
			SELECT BATCH_ID,ARTICLE_ID,IFNULL(SUM(IFNULL(IFNULL(`QUANTITY`,0)-IFNULL(`VIRTUAL_QUANTITY_TO_PICK`,0),0)),0)
			TotalQuantity
			FROM `live_inventory_master`
			WHERE ifnull(REMARK,'') Not in ('AUDIT_MARKED') 
			GROUP BY BATCH_ID,ARTICLE_ID
		)SBI ON SBI.ARTICLE_ID=sim.SKU_ID AND SBI.BATCH_ID=sim.BATCH_ID
	       GROUP BY sim.SKU_ID
       )BI  ON BI.SKU_ID=sr.SKU_ID;	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetBinPoolForStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetBinPoolForStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetBinPoolForStation`(IN p_stationId int)
BEGIN
    SELECT `BIN_ID` 
    FROM `order_bin_mapping` AS obm
    WHERE obm.`STATION_ID` = p_stationId
    and obm.`STATUS` not in ('TASK_COMPLETED','OPERATION_COMPLETED') ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetBinsWithRemainingSkus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetBinsWithRemainingSkus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetBinsWithRemainingSkus`(IN p_binList TEXT)
BEGIN
     SELECT DISTINCT L.bin_id
FROM live_inventory_master L
INNER JOIN (
    SELECT DISTINCT bin_id
    FROM JSON_TABLE(
        CONCAT('[', p_binList, ']'),
        '$[*]' COLUMNS (bin_id INT PATH '$')
    ) AS A
) B ON B.bin_id = L.bin_id
LEFT JOIN store_bin_master s ON s.bin_id = L.bin_id
WHERE 
    (L.`QUANTITY` - IF(L.`VIRTUAL_QUANTITY_TO_PICK` <= 0, 0, L.`VIRTUAL_QUANTITY_TO_PICK`)) > 0
    AND (
        s.bin_id IS NULL  
        OR s.location_id NOT IN (SELECT location_id FROM location_block_master)  
    );
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetBinsWithRemainingSkus1` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetBinsWithRemainingSkus1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetBinsWithRemainingSkus1`(IN p_binList TEXT)
BEGIN
     SELECT DISTINCT L.bin_id
FROM live_inventory_master L
INNER JOIN (
    SELECT DISTINCT bin_id
    FROM JSON_TABLE(
        CONCAT('[', p_binList, ']'),
        '$[*]' COLUMNS (bin_id INT PATH '$')
    ) AS A
) B ON B.bin_id = L.bin_id
LEFT JOIN store_bin_master s ON s.bin_id = L.bin_id
WHERE 
    (L.`QUANTITY` - IF(L.`VIRTUAL_QUANTITY_TO_PICK` <= 0, 0, L.`VIRTUAL_QUANTITY_TO_PICK`)) > 0
    AND (
        s.bin_id IS NULL  
        OR s.location_id NOT IN (SELECT location_id FROM location_block_master)  
    );
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetLPNForPTL` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetLPNForPTL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetLPNForPTL`(IN p_ptlId varchar(4), in p_parentId int)
BEGIN
	DECLARE v_ID varchar(50);
	Select lm.LPN_ID from LPN_MASTER lm
	JOIN `hw_ptl_master` hw
	ON hw.`PTL_ID` = lm.`PTL_ID`
	WHERE lm.PTL_ID=p_ptlId
	and hw.`PARENT_ID` = p_parentId
	and lm.LPN_STATUS='LPN_OPEN';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetLpnRegex` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetLpnRegex` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetLpnRegex`()
BEGIN
		select `KEY_VALUE` from `master_config` where `KEY_NAME` = 'LPN_REGEX';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetOnStationOrderBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetOnStationOrderBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetOnStationOrderBinId`(
	in p_parentId int
    )
BEGIN
	SELECT `ORDER_BIN_ID`, `BIN_ID` 
	FROM `order_bin_mapping` 
	WHERE `STATION_ID` = p_parentId
	AND `STATUS` = 'ON_STATION';
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetOrderListWithMaxArticleVariety` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetOrderListWithMaxArticleVariety` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetOrderListWithMaxArticleVariety`(
	IN p_waveId varchar(200),
	IN p_orderCount int
    )
BEGIN
		SELECT `ORDER_ID`,
	       COUNT(DISTINCT CONCAT(`SKU_ID`, `BATCH_ID`)) AS SKU_COUNT
		FROM `pick_wave_wms_data` 
		WHERE `WAVE_ID` = p_waveId
		GROUP BY `ORDER_ID`
		ORDER BY SKU_COUNT DESC
		LIMIT p_orderCount;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetOrderListWithMaxArticleVarietyTest` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetOrderListWithMaxArticleVarietyTest` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetOrderListWithMaxArticleVarietyTest`(
    IN waveId VARCHAR(200),
    IN orderCount INT,
    IN articlePool TEXT
)
BEGIN
    
    SET @sql = CONCAT(
        'SELECT `ORDER_ID`, COUNT(DISTINCT `ARTICLE_ID`) AS ARTICLE_COUNT ',
        'FROM `pick_wave_wms_data` ',
        'WHERE `WAVE_ID` = "',waveId,'" ',
        'AND `STATUS` = "PENDING" ',
        'AND `ARTICLE_ID` IN (', articlePool, ') ',
        'GROUP BY `ORDER_ID` ',
        'ORDER BY ARTICLE_COUNT DESC ',
        'LIMIT ',orderCount
    );
    
    
    PREPARE stmt FROM @sql;
    EXECUTE stmt ;
    DEALLOCATE PREPARE stmt;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetPickStarted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetPickStarted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PickWaveGetPickStarted`(IN p_binId INT, IN p_orderBinId INT)
BEGIN
		SELECT * 
		FROM `pick_wave_order_master`
		WHERE `BIN_ID` = p_binId
		AND `ORDER_BIN_ID` = p_orderBinId
		AND `STATUS` IN ('PICK_STARTED','MID_WAVE_AUDIT_STARTED')
		ORDER BY `BIN_SEGMENT_NO`
		LIMIT 1;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetPickStartedArticlePtlIdQuantity` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetPickStartedArticlePtlIdQuantity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetPickStartedArticlePtlIdQuantity`(
    IN p_station_id INT,
    IN p_barcode VARCHAR(200)
)
BEGIN
    DECLARE v_article_id VARCHAR(200);
    
    SELECT pwo.SKU_ID
    INTO v_article_id
    FROM pick_wave_order_master pwo
    JOIN `sku_ean_mapping` aim ON pwo.SKU_ID = aim.SKU_ID
    WHERE pwo.STATUS = 'PICK_STARTED' AND pwo.STATION_ID = p_station_id
    AND aim.`EAN_ID` = p_barcode
    LIMIT 1;
    
    IF v_article_id IS NOT NULL THEN
        SELECT pwo.PTL_ID as PTL_ID, pwo.QUANTITY and QUANTITY
        FROM pick_wave_order_master pwo
        WHERE pwo.SKU_ID = v_article_id
        AND pwo.STATUS = 'PICK_STARTED'
        AND pwo.STATION_ID = p_station_id;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetPickStartedByOrderBinIdSegmentNumber` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetPickStartedByOrderBinIdSegmentNumber` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetPickStartedByOrderBinIdSegmentNumber`(IN p_stationId INT, IN p_skuBarcode VARCHAR(200))
BEGIN
    SELECT * 
    FROM `pick_wave_order_master` pwo
    JOIN `sku_ean_mapping` sem ON pwo.`SKU_ID` = sem.`SKU_ID`
    WHERE pwo.`STATUS` = 'PICK_STARTED'
    AND sem.`EAN_ID` = p_skuBarcode
    AND pwo.`STATION_ID` = p_stationId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetPtlCurrentStateByPtlId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetPtlCurrentStateByPtlId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetPtlCurrentStateByPtlId`(
IN p_ptlId INT
)
BEGIN    
select * from `ptl_current_state` 
where `PTL_ID` = p_ptlId
limit 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetRemainingOrderBinByWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetRemainingOrderBinByWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetRemainingOrderBinByWaveId`(
	IN p_waveId VARCHAR(50)
)
BEGIN
	select * FROM `order_bin_mapping`
	WHERE `ORDER_BIN_ID` IN (
		SELECT `ORDER_BIN_ID` 
		FROM `pick_wave_order_master` 
		WHERE `WAVE_ID` = p_waveId
	);
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetRemainingPtlsByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetRemainingPtlsByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetRemainingPtlsByStationId`(
    IN p_stationId INT,
    IN p_waveId VARCHAR(200))
BEGIN
    SELECT h.PTL_ID
FROM hw_ptl_master h
WHERE h.PARENT_ID = p_stationId
 and `STATUS` IN ('LPN_CLOSED','ENABLED')
  AND NOT EXISTS (
      SELECT 1
      FROM wms_to_wcs_order_request_data w
      WHERE w.ALLOCATED_PTL = h.PTL_ID
      and w.`ORDER_REQUEST_STATUS` in('ORDER_PICK_STARTED','PENDING')
  )
  AND NOT EXISTS (
      SELECT 1
      FROM lpn_master l
      WHERE l.PTL_ID = h.PTL_ID AND l.LPN_STATUS in ('LPN_OPEN')
  );
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetRemainingQuantityForAllocationByWaveIdOrderId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetRemainingQuantityForAllocationByWaveIdOrderId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetRemainingQuantityForAllocationByWaveIdOrderId`(in p_waveId varchar(200), 
    in p_orderId varchar(200))
BEGIN
		SELECT `SKU_ID`,`BATCH_ID`,SUM(`EXPECTED_QUANTITY`) as EXPECTED_QUANTITY
		FROM `pick_wave_order_master`
		WHERE `WAVE_ID` = p_waveId
		AND `ORDER_ID` = p_orderId
		GROUP BY `SKU_ID`,`BATCH_ID`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetSegmentAssingnedByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetSegmentAssingnedByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetSegmentAssingnedByBinId`(IN p_binId INT,in p_orderBinId int)
BEGIN
		select * 
		from `pick_wave_order_master`
		where `BIN_ID` = p_binId
		and `ORDER_BIN_ID` = p_orderBinId
		and `STATUS` Not in ('PICK_COMPLETED','ORDER_COMPLETED','MID_WAVE_AUDIT_COMPLETED')
		order by `BIN_SEGMENT_NO`
		limit 1;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetShortPickReason` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetShortPickReason` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetShortPickReason`(in p_ptlId int)
BEGIN
	select * from `short_pick_wave_reason` spwr
	join `pick_wave_order_master` pwom
	on spwr.`PICK_ORDER_ID` = pwom.`PICK_ORDER_ID`
	where pwom.`STATUS` = 'PICK_STARTED';
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetShortPickStarted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetShortPickStarted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetShortPickStarted`(in p_waveId varchar(200), in p_stationId int)
BEGIN
		select * from `pick_wave_order_master` 
		where `SHORT_PICK_QUANTITY` > 0
		and `WAVE_ID` =  p_waveId
		and `STATION_ID` = p_stationId
		and `STATUS` = 'PICK_STARTED';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetSkuBatchQuantityByBinIdSkuId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetSkuBatchQuantityByBinIdSkuId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetSkuBatchQuantityByBinIdSkuId`(in p_binId int, in p_segmentNumber int)
BEGIN
		select (`QUANTITY` - IF(`VIRTUAL_QUANTITY_TO_PICK` <= 0, 0, `VIRTUAL_QUANTITY_TO_PICK`))
		from `live_inventory_master`
		where `BIN_ID` = p_binId
		and `SEGMENT_NO` = p_segmentNumber;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetSkuBatchQuantityByBinList` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetSkuBatchQuantityByBinList` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetSkuBatchQuantityByBinList`(in p_binList text)
BEGIN
		SELECT 
		    `ARTICLE_ID`,
		    `BATCH_ID`,
		    CASE 
			WHEN `QUANTITY` - `VIRTUAL_QUANTITY_TO_PICK` < 0 THEN 0 
			ELSE `QUANTITY` - `VIRTUAL_QUANTITY_TO_PICK` 
		    END AS `AVAILABLE_QUANTITY`
		FROM 
		    `live_inventory_master` 
		WHERE 
		    `BIN_ID` IN (p_binList);
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetSkuInformationBySkuId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetSkuInformationBySkuId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetSkuInformationBySkuId`(IN p_skuId VARCHAR(200))
BEGIN
	SELECT JSON_OBJECTAGG(
           sr.`SKU_ID`, JSON_OBJECT(
                         'SkuName', sr.`SKU_NAME`,
                         'Category', sr.`CATEGORY`,
                         'MinSlotSize', sr.`MIN_SEGMENT_SIZE`,
                         'MaxBinQuantity', sr.`MAX_QUANTITY_PER_SEGMENT`,
                         'MinSplitLocation', sr.`MIN_BIN_STORAGE`,
                         'MaxBin', sr.`MAX_BIN_STORAGE`,
                         'MaxStorageQuantity', sr.`MAX_QUANTITY_STORAGE`,
                         'Velocity', sr.`VELOCITY`,
                         'WeightOfEachArticle', sr.`WEIGHT_OF_EACH_SKU`,
                         'VolumeOfEachArticle', sr.`VOLUME_OF_EACH_SKU`,
                         'TotalQuantityInInventory',IFNULL(LI.v_totalQuantity,0), 
                        'BatchInformation',BI.BatchInformation 
                    )
       ) AS JSON_DATA
	FROM `sku_master` AS sr 
	LEFT OUTER JOIN 
	(
		SELECT ARTICLE_ID,(IFNULL(SUM(IFNULL(IFNULL(`QUANTITY`,0)-IFNULL(`VIRTUAL_QUANTITY_TO_PICK`,0),0)),0)) 
		AS v_totalQuantity
		FROM `live_inventory_master` 
		WHERE IFNULL(REMARK,'') NOT IN ('AUDIT_MARKED') 
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
			SELECT BATCH_ID,ARTICLE_ID,IFNULL(SUM(IFNULL(IFNULL(`QUANTITY`,0)-IFNULL(`VIRTUAL_QUANTITY_TO_PICK`,0),0)),0)
			TotalQuantity
			FROM `live_inventory_master`
			WHERE ifnull(REMARK,'') Not in ('AUDIT_MARKED') 
			GROUP BY BATCH_ID,ARTICLE_ID
		)SBI ON SBI.ARTICLE_ID=sim.SKU_ID AND SBI.BATCH_ID=sim.BATCH_ID
	       GROUP BY sim.SKU_ID
       )BI  ON BI.SKU_ID=sr.SKU_ID
       where sr.SKU_ID = p_skuId;	
       END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveGetTotalQuantityInBinBySkuIdBatchId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveGetTotalQuantityInBinBySkuIdBatchId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveGetTotalQuantityInBinBySkuIdBatchId`(in p_binId int, in p_skuId varchar(200), in p_batchId varchar(200))
BEGIN
		SELECT IF(SUM(`QUANTITY` - IF(`VIRTUAL_QUANTITY_TO_PICK` <= 0, 0, `VIRTUAL_QUANTITY_TO_PICK`)) <= 0, 0, 
		SUM(`QUANTITY` - IF(`VIRTUAL_QUANTITY_TO_PICK` <= 0, 0, `VIRTUAL_QUANTITY_TO_PICK`))) as 'SUM' 
		FROM `live_inventory_master`
		WHERE `ARTICLE_ID` = p_skuId
		AND `BATCH_ID` = p_batchId
		AND `BIN_ID` = p_binId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveInsertInPickWaveOrderMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveInsertInPickWaveOrderMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PickWaveInsertInPickWaveOrderMaster`(
	IN p_waveId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN p_orderId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN p_orderLineId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN p_skuId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN p_batchId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN p_quantity INT,
	IN p_binId INT,
	IN p_segmentNumber INT,
	IN p_stationId INT,
	IN p_ptlId INT,
	IN p_orderBinId INT
    )
BEGIN
	
	DECLARE v_pickOrderId CHAR(36);
	DECLARE v_errorMessage TEXT;

	DECLARE EXIT HANDLER FOR SQLEXCEPTION
	BEGIN
	    
	    GET DIAGNOSTICS CONDITION 1
	    v_errorMessage = MESSAGE_TEXT;
	    
	    ROLLBACK;
	    
	    SIGNAL SQLSTATE '45000' 
	    SET MESSAGE_TEXT = v_errorMessage;
	END;
	
	START TRANSACTION;
    SET v_pickOrderId = UUID();

    
    INSERT INTO pick_wave_order_master (
        PICK_ORDER_ID, WAVE_ID, ORDER_ID, ORDER_LINE_ID, SKU_ID, BATCH_ID,
        EXPECTED_QUANTITY, STATUS, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO,
        STATION_ID, PTL_ID
    )
    SELECT v_pickOrderId, p_waveId, p_orderId, p_orderLineId, p_skuId, p_batchId,
           p_quantity, 'PENDING', p_orderBinId, p_binId, p_segmentNumber,
           p_stationId, p_ptlId
    FROM DUAL
    WHERE NOT EXISTS (
        SELECT 1
        FROM pick_wave_order_master
        WHERE ORDER_ID = p_orderId
          AND SKU_ID = p_skuId
          AND BATCH_ID = p_batchId
          AND ORDER_BIN_ID = p_orderBinId
          AND ORDER_LINE_ID = p_orderLineId
          AND PTL_ID = p_ptlId
          AND BIN_SEGMENT_NO = p_segmentNumber
    );

    
    IF ROW_COUNT() > 0 THEN
        UPDATE live_inventory_master
        SET 
            VIRTUAL_QUANTITY_TO_PICK = GREATEST(COALESCE(VIRTUAL_QUANTITY_TO_PICK, 0), 0) + p_quantity,
            ARTICLE_ID = p_skuId,
            BATCH_ID = p_batchId,
            REMARK = CASE 
                        WHEN REMARK = 'AUDIT_MARKED' THEN 'AUDIT_MARKED' 
                        ELSE NULL 
                     END
        WHERE BIN_ID = p_binId 
          AND SEGMENT_NO = p_segmentNumber;

    
    ELSE
        UPDATE pick_wave_order_master
        SET 
            EXPECTED_QUANTITY = EXPECTED_QUANTITY + p_quantity
        WHERE ORDER_ID = p_orderId
          AND SKU_ID = p_skuId
          AND BATCH_ID = p_batchId
          AND ORDER_BIN_ID = p_orderBinId
          AND ORDER_LINE_ID = p_orderLineId
          AND PTL_ID = p_ptlId
          AND BIN_SEGMENT_NO = p_segmentNumber;

        UPDATE live_inventory_master
        SET 
            VIRTUAL_QUANTITY_TO_PICK = GREATEST(COALESCE(VIRTUAL_QUANTITY_TO_PICK, 0), 0) + p_quantity,
            ARTICLE_ID = p_skuId,
            BATCH_ID = p_batchId,
            REMARK = CASE 
                        WHEN REMARK = 'AUDIT_MARKED' THEN 'AUDIT_MARKED' 
                        ELSE NULL 
                     END
        WHERE BIN_ID = p_binId 
          AND SEGMENT_NO = p_segmentNumber;
          
	END IF;
	
	COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveInsertIntoLpnPickWaveOrderMapping` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveInsertIntoLpnPickWaveOrderMapping` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveInsertIntoLpnPickWaveOrderMapping`(
    IN p_parentId INT, 
    IN p_ptlId INT, 
    IN p_quantity INT
)
BEGIN
    DECLARE v_pickOrderLpnMappingId CHAR(36);
    DECLARE v_pickOrderId CHAR(36);
    DECLARE v_lpnId CHAR(36);
    DECLARE v_loggedInUser VARCHAR(200);
	DECLARE v_skuId VARCHAR(200);
	DECLARE v_batchId VARCHAR(200);
	DECLARE v_binId INT;
	DECLARE v_segmentNo INT;    
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Some Error occurred';
    END;
    
    START TRANSACTION;
    SET v_pickOrderLpnMappingId = UUID();
    
    SELECT `LPN_ID` INTO v_lpnId 
    FROM `lpn_master`
    WHERE `PTL_ID` =  p_ptlId
    AND `LPN_STATUS` = 'LPN_OPEN';
    
    
    SELECT `PICK_ORDER_ID`, `BIN_ID`, `BIN_SEGMENT_NO`, `SKU_ID`, `BATCH_ID` INTO v_pickOrderId, v_binId, v_segmentNo, v_skuId, v_batchId
		FROM `pick_wave_order_master`
		WHERE `PTL_ID` = p_ptlId
		AND `STATUS` = 'PICK_STARTED' LIMIT 1;
    
    
    SELECT `LOGGED_IN_USER_ID` INTO v_loggedInUser
    FROM `hw_station_master` 
    WHERE `STATION_ID`= p_parentId ;
    
    INSERT INTO `lpn_pick_wave_order_mapping` 
    (`PICK_ORDER_LPN_MAPPING_ID`, `PICK_ORDER_ID`, `LPN_ID`, `PICKED_QUANTITY`, `USER_ID`)
    VALUES
    (v_pickOrderLpnMappingId,      
     v_pickOrderId,                
     v_lpnId,                      
     p_quantity,                   
     v_loggedInUser                
    );
    
    UPDATE `pick_wave_order_master` 
    SET `PICKED_QUANTITY` = `PICKED_QUANTITY` + p_quantity
    WHERE `PICK_ORDER_ID` = v_pickOrderId;
    
    
    CALL `wm_PickWaveInsertUpdateLiveInventory`(p_quantity,v_binId,v_segmentNo,v_skuId,v_batchId,0);
    COMMIT;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveInsertUpdateLiveInventory` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveInsertUpdateLiveInventory` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveInsertUpdateLiveInventory`(
    IN p_updateQuantity INT,
    IN p_binId INT,
    IN p_segmentNumber INT,
    IN p_articleId VARCHAR(200),
    IN p_batchId VARCHAR(200),
    IN p_isVirtualQuantity TINYINT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE error_message TEXT;
    DECLARE error_code INT;
    
    GET DIAGNOSTICS CONDITION 1 
        error_message = MESSAGE_TEXT,
        error_code = MYSQL_ERRNO;
    
    ROLLBACK;
    SIGNAL SQLSTATE '45000' 
    SET MESSAGE_TEXT =  error_message;    
    
    END;
    
    START TRANSACTION;
    IF p_isVirtualQuantity > 0 THEN
        UPDATE live_inventory_master
        SET VIRTUAL_QUANTITY_TO_PICK = VIRTUAL_QUANTITY_TO_PICK + p_updateQuantity,
            `ARTICLE_ID` = p_articleId,
            `BATCH_ID` = p_batchId,
	    REMARK = CASE WHEN REMARK = 'AUDIT_MARKED' THEN 'AUDIT_MARKED' ELSE NULL end
        WHERE BIN_ID = p_binId 
        AND SEGMENT_NO = p_segmentNumber;
    ELSE
        UPDATE live_inventory_master
        SET `QUANTITY` = `QUANTITY` - p_updateQuantity,
            VIRTUAL_QUANTITY_TO_PICK = VIRTUAL_QUANTITY_TO_PICK - p_updateQuantity,
            `ARTICLE_ID` = p_articleId,
            `BATCH_ID` = p_batchId,
	    REMARK = CASE WHEN REMARK = 'AUDIT_MARKED' THEN 'AUDIT_MARKED' ELSE NULL END
        WHERE BIN_ID = p_binId 
        AND SEGMENT_NO = p_segmentNumber;
    END IF;
    
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveLpnOrderMappingArchiveAndRemoveByWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveLpnOrderMappingArchiveAndRemoveByWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PickWaveLpnOrderMappingArchiveAndRemoveByWaveId`(
    IN p_waveId VARCHAR(200),
    IN p_state VARCHAR(200)
)
BEGIN
    
    INSERT IGNORE INTO `lpn_pick_wave_order_mapping_archive` (
        `ARCHIVE_ID`,`PICK_ORDER_LPN_MAPPING_ID`, `PICK_ORDER_ID`, `LPN_ID`, 
        `PICKED_QUANTITY`, `INSERTED_TIMESTAMP`, `USER_ID`, 
        `UPDATED_TIMESTAMP`, `UPDATED_BY`, `ARCHIVE_REASON`
    )
    SELECT 
        UUID(),lpom.`PICK_ORDER_LPN_MAPPING_ID`, lpom.`PICK_ORDER_ID`, lpom.`LPN_ID`, 
        lpom.`PICKED_QUANTITY`, lpom.`INSERTED_TIMESTAMP`, lpom.`USER_ID`, 
        lpom.`UPDATED_TIMESTAMP`, lpom.`UPDATED_BY`, p_state
    FROM `lpn_pick_wave_order_mapping` lpom
    INNER JOIN `pick_wave_order_master` pwom
    ON lpom.`PICK_ORDER_ID` = pwom.`PICK_ORDER_ID`
    WHERE pwom.`WAVE_ID` = p_waveId;
    
    DELETE lpom
    FROM `lpn_pick_wave_order_mapping` lpom
    INNER JOIN `pick_wave_order_master` pwom
    ON lpom.`PICK_ORDER_ID` = pwom.`PICK_ORDER_ID`
    WHERE pwom.`WAVE_ID` = p_waveId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveLpnValidation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveLpnValidation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveLpnValidation`(IN p_barcode VARCHAR(100))
BEGIN
    DECLARE v_isvalid BOOL DEFAULT FALSE;
    DECLARE v_regex VARCHAR(50);
    DECLARE v_lpnID VARCHAR(50);
 
    
    SELECT key_value INTO v_regex 
    FROM master_config 
    WHERE key_name = 'LPN_REGEX';
 
    
    SELECT lpn_id INTO v_lpnID 
    FROM lpn_master 
    WHERE lpn_barcode = p_barcode LIMIT 1;
 
    
    IF v_lpnID IS NULL THEN
        SELECT IF(p_barcode REGEXP v_regex, TRUE, FALSE) INTO v_isvalid;
    ELSE
        SET v_isvalid = FALSE;
    END IF;
 
    
    SELECT v_isvalid AS is_valid;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveOrderMasterArchiveAndRemove` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveOrderMasterArchiveAndRemove` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveOrderMasterArchiveAndRemove`(IN p_waveId VARCHAR(200), IN p_state ENUM('ARCHIVED', 'CANCELLED'))
BEGIN
    
    INSERT ignore INTO `pick_wave_order_master_archive` (`PICK_ORDER_ID`, WAVE_ID, ORDER_BIN_ID, ORDER_ID, 
        STATION_ID,`ORDER_LINE_ID`, PTL_ID, BIN_ID, STATUS, SKU_ID, BIN_SEGMENT_NO, BATCH_ID, 
        EXPECTED_QUANTITY, MRP, EXPIRY_DATE, PICKED_QUANTITY, SHORT_PICK_QUANTITY, 
        PICK_BY, PICK_TIMESTAMP, INSERTED_TIMESTAMP, INSERTED_BY, 
        UPDATED_TIMESTAMP, UPDATED_BY, ARCHIVE_REASON, PICK_START_TIMESTAMP
    )
    SELECT 
        `PICK_ORDER_ID`, WAVE_ID, ORDER_BIN_ID, ORDER_ID, 
        STATION_ID,`ORDER_LINE_ID`, PTL_ID, BIN_ID, STATUS, SKU_ID, 
        BIN_SEGMENT_NO, BATCH_ID, EXPECTED_QUANTITY, MRP, 
        EXPIRY_DATE, PICKED_QUANTITY, SHORT_PICK_QUANTITY, 
        PICK_BY, PICK_TIMESTAMP, INSERTED_TIMESTAMP, INSERTED_BY, 
        UPDATED_TIMESTAMP, UPDATED_BY, p_state,PICK_START_TIMESTAMP
    FROM `pick_wave_order_master`
    WHERE WAVE_ID = p_waveId;
    
    DELETE FROM pick_wave_order_master
    WHERE WAVE_ID = p_waveId;
    

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveOrderMasterQuantityRevert` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveOrderMasterQuantityRevert` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveOrderMasterQuantityRevert`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    SELECT 
        pwwd.ORDER_ID,
        pwwd.ORDER_LINE_ID,
        pwwd.total_quantity AS WMS_QUANTITY,
        IFNULL(picked.picked_quantity, 0) AS PICKED_QUANTITY,
        IFNULL(completed.pick_completed_quantity, 0) AS PICK_COMPLETED_QUANTITY,
        (pwwd.total_quantity - IFNULL(completed.pick_completed_quantity, 0)) AS REVERT_QUANTITY
    FROM (
        
        SELECT 
            ORDER_ID, 
            ORDER_LINE_ID, 
            SUM(QUANTITY) AS total_quantity
        FROM 
            pick_wave_wms_data
        WHERE 
            WAVE_ID = p_waveId
        GROUP BY 
            ORDER_ID, 
            ORDER_LINE_ID
    ) AS pwwd
    LEFT JOIN (
        
        SELECT 
            ORDER_ID, 
            ORDER_LINE_ID, 
            SUM(PICKED_QUANTITY) AS picked_quantity
        FROM 
            pick_wave_order_master
        WHERE 
            WAVE_ID = p_waveId
        GROUP BY 
            ORDER_ID, 
            ORDER_LINE_ID
    ) AS picked
    ON picked.ORDER_ID = pwwd.ORDER_ID 
       AND picked.ORDER_LINE_ID = pwwd.ORDER_LINE_ID
    LEFT JOIN (
        
        SELECT 
            ORDER_ID, 
            ORDER_LINE_ID, 
            SUM(PICKED_QUANTITY) AS pick_completed_quantity
        FROM 
            pick_wave_order_master
        WHERE 
            STATUS = 'PICK_COMPLETED'
            AND WAVE_ID = p_waveId
        GROUP BY 
            ORDER_ID, 
            ORDER_LINE_ID
    ) AS completed
    ON completed.ORDER_ID = pwwd.ORDER_ID 
       AND completed.ORDER_LINE_ID = pwwd.ORDER_LINE_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveOrderMasterResetVirtualQuantity` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveOrderMasterResetVirtualQuantity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveOrderMasterResetVirtualQuantity`(IN p_waveId CHAR(200))
BEGIN
    SELECT 
	ORDER_ID,
	ORDER_LINE_ID,
	BIN_ID, 
	BIN_SEGMENT_NO,
	EXPECTED_QUANTITY,
	PICKED_QUANTITY
    FROM `pick_wave_order_master`
    WHERE WAVE_ID = p_waveId
    AND `STATUS` = 'PENDING';
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePickCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePickCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePickCompleted`(in p_ptlId int, in p_waveId varchar(200))
BEGIN
		DECLARE v_orderCompleted char(36); 
		DECLARE v_loggedInUser VARCHAR(200);
		
		SELECT `LOGGED_IN_USER_ID` INTO v_loggedInUser
		FROM `hw_station_master`
		WHERE `STATION_ID` in (select `PARENT_ID` from `hw_ptl_master` where `PTL_ID` =  p_ptlId)
		limit 1;
		
		UPDATE `pick_wave_order_master` 
		SET `STATUS` = 'PICK_COMPLETED',
		`SHORT_PICK_QUANTITY` = (`EXPECTED_QUANTITY` - `PICKED_QUANTITY`),
		`PICK_TIMESTAMP` = CURRENT_TIMESTAMP(),
		`PICK_BY` = v_loggedInUser
		WHERE `PTL_ID` = p_ptlId
		AND `STATUS` = 'PICK_STARTED'
		AND WAVE_ID = p_waveId;
		
		select `PICK_ORDER_ID` into v_orderCompleted FROM pick_wave_order_master AS p1
		JOIN (
		    SELECT ORDER_ID
		    FROM pick_wave_order_master
		    WHERE WAVE_ID = p_waveId
		    GROUP BY ORDER_ID
		    HAVING COUNT(CASE WHEN STATUS != 'PICK_COMPLETED' THEN 1 END) = 0
		) AS p2
		WHERE p1.STATUS = 'PICK_COMPLETED'
		AND p1.PTL_ID = p_ptlId 
		AND WAVE_ID = p_waveId
		LIMIT 1;
		
		UPDATE pick_wave_order_master AS p1
		JOIN (
		    SELECT ORDER_ID
		    FROM pick_wave_order_master
		    WHERE WAVE_ID = p_waveId
		    GROUP BY ORDER_ID
		    HAVING COUNT(CASE WHEN STATUS != 'PICK_COMPLETED' THEN 1 END) = 0
		) AS p2
		ON p1.ORDER_ID = p2.ORDER_ID
		SET p1.STATUS = 'ORDER_COMPLETED'
		WHERE p1.STATUS = 'PICK_COMPLETED'
		AND p1.PTL_ID = p_ptlId
		AND WAVE_ID = p_waveId;
		
		select * from `pick_wave_order_master` 
		where `PICK_ORDER_ID` = v_orderCompleted
		and `STATUS` = 'ORDER_COMPLETED'
		AND WAVE_ID = p_waveId;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlCheckIfOpenBag` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlCheckIfOpenBag` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlCheckIfOpenBag`(
                                    IN p_ptlId INT
                                )
BEGIN
                                    SELECT `LPN_ID` 
                                    FROM `lpn_master` 
                                    WHERE `PTL_ID` = p_ptlId
                                    AND `LPN_STATUS` = 'LPN_OPEN';
                                END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlCloseBag` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlCloseBag` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlCloseBag`(
    IN p_ptlId INT
)
BEGIN
    
	
	UPDATE `lpn_master`
	SET `LPN_STATUS` = 'LPN_CLOSED', LPN_CLOSE_TIMESTAMP = CURRENT_TIMESTAMP(3)
	WHERE PTL_ID= p_ptlId
	and `LPN_STATUS` = 'LPN_OPEN';
	
	UPDATE `lpn_master`
	SET `LPN_STATUS` = 'LPN_CLOSED'
	WHERE PTL_ID= p_ptlId;
	
	UPDATE `hw_ptl_master` SET `STATUS` = 'LPN_CLOSED' WHERE `PTL_ID` = p_ptlId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlCofirmationButton` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlCofirmationButton` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlCofirmationButton`(in p_ptlId int)
BEGIN
		update `pick_wave_order_master` 
		set `STATUS` = 'PICK_COMPLETED'
		where `PTL_ID` = p_ptlId
		AND `STATUS` = 'PICK_STARTED';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlDecrementButton` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlDecrementButton` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlDecrementButton`(in p_ptlId int, in p_quantity int)
BEGIN
		DECLARE v_remainingQuantity INT;
		DECLARE v_ptlQuantity INT;
		SELECT (`DISPLAY` - p_quantity) INTO v_ptlQuantity FROM hw_ptl_master WHERE `PTL_ID` = p_ptlId;
		SELECT wm_PickWavePtlGetRemainingQuantity(p_ptlId) INTO v_remainingQuantity;	
		 IF v_ptlQuantity <= v_remainingQuantity THEN
			UPDATE `hw_ptl_master` 
			SET `DISPLAY` = GREATEST(v_ptlQuantity, 1)
			WHERE `PTL_ID` = p_ptlId;
		    ELSE
			UPDATE `hw_ptl_master` 
			SET `DISPLAY` = v_remainingQuantity
			WHERE `PTL_ID` = p_ptlId;
		    END IF;
		
		SELECT DISPLAY FROM hw_ptl_master WHERE `PTL_ID` = p_ptlId limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlGetRemainingQuantity` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlGetRemainingQuantity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlGetRemainingQuantity`(in p_ptlId int)
BEGIN
	select wm_PickWavePtlGetRemainingQuantity(p_ptlId);
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlGetRemainingQuantityByPtlId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlGetRemainingQuantityByPtlId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlGetRemainingQuantityByPtlId`(in p_ptlId int)
BEGIN
	select wm_PickWavePtlGetRemainingQuantity(p_ptlId) as REMAINING;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlIncrementButton` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlIncrementButton` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlIncrementButton`(in p_ptlId int, in p_quantity int)
BEGIN
		declare v_remainingQuantity int;
		declare v_ptlQuantity int;
		
		select (DISPLAY +p_quantity) into v_ptlQuantity from hw_ptl_master WHERE `PTL_ID` = p_ptlId;
		
		SELECT wm_PickWavePtlGetRemainingQuantity(p_ptlId) INTO v_remainingQuantity;	
					
		 IF v_ptlQuantity <= v_remainingQuantity THEN
			UPDATE `hw_ptl_master` 
			SET `DISPLAY` = v_ptlQuantity
			WHERE `PTL_ID` = p_ptlId;
		    ELSE
			UPDATE `hw_ptl_master` 
			SET `DISPLAY` = v_remainingQuantity
			WHERE `PTL_ID` = p_ptlId;
		    END IF;
		
		select DISPLAY from hw_ptl_master WHERE `PTL_ID` = p_ptlId limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlOpenNewBag` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlOpenNewBag` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlOpenNewBag`(
    IN p_ptl_id INT, IN p_lpn_barcode VARCHAR(100),in p_parentId int
)
BEGIN
    DECLARE v_lpnId VARCHAR(50);
    SET v_lpnId = UUID();
    
    INSERT INTO `lpn_master`(LPN_ID, LPN_BARCODE, PTL_ID, LPN_STATUS)
    SELECT v_lpnId, p_lpn_barcode, p_ptl_id, 'LPN_OPEN'
    FROM `hw_ptl_master`
    WHERE `PARENT_ID` = p_parentId
    AND PTL_ID = p_ptl_id;
    
    
    SELECT v_lpnId AS LPN_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlOpenNewBagOld` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlOpenNewBagOld` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlOpenNewBagOld`(
    IN p_ptl_id INT
)
BEGIN
    DECLARE v_lpnId VARCHAR(50);
    SET v_lpnId = UUID();
    
    INSERT INTO `lpn_master` (LPN_ID,PTL_ID, LPN_STATUS)
    VALUES (v_lpnId,p_ptl_id, 'LPN_OPEN');
    
    SELECT v_lpnId AS LPN_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlOperationScan` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlOperationScan` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlOperationScan`(IN p_barcodeData VARCHAR(200), in p_parentId int)
BEGIN
    DECLARE v_operation VARCHAR(20);
    DECLARE v_ptlId INT;
    DECLARE v_currentStatus VARCHAR(100);
    
    
    
    
    
    IF v_operation IS NULL THEN
        SELECT 'LPN_SCAN', `PTL_ID`, `STATUS` INTO v_operation, v_ptlId, v_currentStatus
        FROM `hw_ptl_master`
        WHERE `STATUS` = 'LPN_SCAN'
        AND PARENT_ID = p_parentId
        LIMIT 1;
    END IF;
    IF v_operation IS NULL THEN
        SELECT 'LPN_OPEN', `PTL_ID`, `STATUS` INTO v_operation, v_ptlId, v_currentStatus
        FROM `hw_ptl_master`
        WHERE `BARCODE_OPEN_BAG` = p_barcodeData
        and PARENT_ID = p_parentId
        LIMIT 1;
    END IF;
    
    IF v_operation IS NULL THEN
        SELECT 'LPN_CLOSED', `PTL_ID`, `STATUS` INTO v_operation, v_ptlId, v_currentStatus
        FROM `hw_ptl_master`
        WHERE `BARCODE_CLOSE_BAG` = p_barcodeData
        AND PARENT_ID = p_parentId
        LIMIT 1;
    END IF;
    IF v_operation IS NULL THEN
        SET v_operation = 'NOT_FOUND';
    END IF;
    SELECT v_operation AS OPERATION, v_ptlId AS PTL_ID, v_currentStatus AS CURRENT_STATUS;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlOperationScanCopy` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlOperationScanCopy` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlOperationScanCopy`(IN barcodeData VARCHAR(200))
BEGIN
    DECLARE v_operation VARCHAR(20);
    DECLARE v_ptlId INT;
    DECLARE v_currentStatus VARCHAR(100);
    
    
    
    
    
    IF v_operation IS NULL THEN
        SELECT 'LPN_SCAN', `PTL_ID`, `STATUS` INTO v_operation, v_ptlId, v_currentStatus
        FROM `hw_ptl_master`
        WHERE `STATUS` = 'LPN_SCAN'
        LIMIT 1;
    ELSEIF v_operation IS NULL THEN
        SELECT 'LPN_OPEN', `PTL_ID`, `STATUS` INTO v_operation, v_ptlId, v_currentStatus
        FROM `hw_ptl_master`
        WHERE `BARCODE_OPEN_BAG` = barcodeData
        LIMIT 1;
    ELSEIF v_operation IS NULL THEN
        SELECT 'LPN_CLOSED', `PTL_ID`, `STATUS` INTO v_operation, v_ptlId, v_currentStatus
        FROM `hw_ptl_master`
        WHERE `BARCODE_CLOSE_BAG` = barcodeData
        LIMIT 1;
    END IF;
    IF v_operation IS NULL THEN
        SET v_operation = 'NOT_FOUND';
    END IF;
    SELECT v_operation AS OPERATION, v_ptlId AS PTL_ID, v_currentStatus AS CURRENT_STATUS;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlOperationScanold` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlOperationScanold` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlOperationScanold`(IN barcodeData VARCHAR(200))
BEGIN
		DECLARE v_operation VARCHAR(20);
		DECLARE v_ptlId INT;
		DECLARE v_currentStatus VARCHAR(100);
		SELECT 'ORDER_COMPLETED', `PTL_ID`, `STATUS` INTO v_operation, v_ptlId, v_currentStatus
		FROM `hw_ptl_master`
		WHERE `BARCODE_ORDER_COMPLETE` = barcodeData
		LIMIT 1;
		IF v_operation IS NULL THEN
			SELECT 'LPN_OPEN', `PTL_ID`, `STATUS` INTO v_operation, v_ptlId, v_currentStatus
			FROM `hw_ptl_master`
			WHERE `BARCODE_OPEN_BAG` = barcodeData
			LIMIT 1;
		END IF;
		IF v_operation IS NULL THEN
			SELECT 'LPN_CLOSED', `PTL_ID`, `STATUS` INTO v_operation, v_ptlId, v_currentStatus
			FROM `hw_ptl_master`
			WHERE `BARCODE_CLOSE_BAG` = barcodeData
			LIMIT 1;
		END IF;
		IF v_operation IS NULL THEN
			SET v_operation = 'NOT_FOUND';
		END IF;
		SELECT v_operation as OPERATION, v_ptlId as PTL_ID, v_currentStatus as CURRENT_STATUS;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlOrderPendingByPtlId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlOrderPendingByPtlId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlOrderPendingByPtlId`(in p_ptl_id int)
BEGIN
		select `PICK_ORDER_ID` 
		from `pick_wave_order_master`
		where `PTL_ID` = p_ptl_id
		and `STATUS` not in ('PICK_COMPLETED','ORDER_COMPLETED');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlSetStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlSetStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlSetStatus`(
    IN p_ptlId INT,
    IN p_status VARCHAR(20),
    in p_parentId int)
BEGIN
		UPDATE hw_ptl_master
		SET `STATUS` = p_status
		WHERE PTL_ID = p_ptlId
		and `PARENT_ID` = p_parentId;
		
		SELECT `DISPLAY` 
		FROM `hw_ptl_master` 
		WHERE `PTL_ID` = p_ptlId
		and `PARENT_ID` = p_parentId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavePtlValue` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavePtlValue` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavePtlValue`(in p_ptlId int)
BEGIN
		select `DISPLAY` from `hw_ptl_master` 
		where `PTL_ID` = p_ptlId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveReleaseShortPickStarted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveReleaseShortPickStarted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveReleaseShortPickStarted`(in p_waveId varchar(200), in p_stationId int)
BEGIN
		select * from `pick_wave_order_master` 
		where `SHORT_PICK_QUANTITY` < 0
		and `WAVE_ID` =  p_waveId
		and `STATION_ID` = p_stationId
		and `STATUS` = 'PICK_STARTED';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveRemoveOrderBinTaskMasterByWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveRemoveOrderBinTaskMasterByWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveRemoveOrderBinTaskMasterByWaveId`(
	IN p_waveId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
	
	CREATE TEMPORARY TABLE IF NOT EXISTS temp_order_bin_ids (
		ORDER_BIN_ID INT NOT NULL,
		INDEX(ORDER_BIN_ID)
	) ENGINE=MEMORY;
	
	INSERT INTO temp_order_bin_ids (ORDER_BIN_ID)
	SELECT `ORDER_BIN_ID` 
	FROM `pick_wave_order_master` 
	WHERE `WAVE_ID` = p_waveId;
	
	DELETE A  FROM `order_bin_task_master` A
	INNER JOIN temp_order_bin_ids B  ON A.ORDER_BIN_ID=B.ORDER_BIN_ID;
	
	
	DELETE A  FROM `order_bin_mapping` A
	INNER JOIN temp_order_bin_ids B  ON A.ORDER_BIN_ID=B.ORDER_BIN_ID
	
	where A.`STATUS` ='TASK_COMPLETED';
	
	DELETE A FROM `order_bin_mapping` A
	INNER JOIN temp_order_bin_ids B  ON A.ORDER_BIN_ID=B.ORDER_BIN_ID
	
	WHERE  A.`STATUS` = 'PENDING' AND A.`BOT_ID` IS NULL;
	
	DROP TEMPORARY TABLE IF EXISTS temp_order_bin_ids;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveResetShortPick` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveResetShortPick` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveResetShortPick`(in p_ptlId int)
BEGIN
		update `pick_wave_order_master` 
		set `SHORT_PICK_QUANTITY` = 0
		where PTL_ID =  p_ptlId
		and `STATUS` = 'PICK_STARTED'
		and `SHORT_PICK_QUANTITY` < 0;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveSetOrderCompleteByPtlId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveSetOrderCompleteByPtlId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveSetOrderCompleteByPtlId`(in p_ptl_id int)
BEGIN
		update `pick_wave_order_master`
		set `STATUS` = 'ORDER_COMPLETED'
		where `PTL_ID` = p_ptl_id
		and `STATUS` = 'PICK_COMPLETED';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveSetPickStartedByOrderBinIdSegmentNumber` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveSetPickStartedByOrderBinIdSegmentNumber` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveSetPickStartedByOrderBinIdSegmentNumber`(IN p_order_bin_id INT, IN p_segment INT)
BEGIN
		                            UPDATE `pick_wave_order_master`
		                            SET `STATUS` = 'PICK_STARTED',PICK_START_TIMESTAMP = current_timestamp(3),
		                            `SHORT_PICK_QUANTITY` = 0
		                            WHERE `ORDER_BIN_ID` = p_order_bin_id
		                            AND `BIN_SEGMENT_NO` = p_segment
		                            and `STATUS` = 'PENDING'; 
		                            
	                            END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWavesToReleaseObjects` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWavesToReleaseObjects` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWavesToReleaseObjects`(
	IN inserted_time_ TIMESTAMP
    )
BEGIN
		SELECT * FROM `wave_master` 
		WHERE `WAVE_STATUS` IN ('PENDING','UPLOADED','STATION_SELECTED','PROCESSING') 
		AND `INSERTED_TIMESTAMP` > inserted_time_
		AND `WAVE_TYPE` IN ('PICK', 'PICK_ORDER_REQUEST');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateIfLeftOver` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateIfLeftOver` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdateIfLeftOver`(
	IN p_waveId VARCHAR(200)
)
BEGIN
	DECLARE v_totalQuantity INT DEFAULT 0;
	SELECT 
        SUM(pwwd.`QUANTITY`) 
    INTO v_totalQuantity
    FROM 
        `pick_wave_wms_data` pwwd
    WHERE 
        pwwd.`LEFT_OVER` > 0 
        AND pwwd.`WAVE_ID` = p_waveId;
    IF v_totalQuantity > 0 THEN
    UPDATE  `wave_master`
    SET `LEFT_OVER_STATUS` = 'IS_LEFT_OVER'
    WHERE `WAVE_ID` = p_waveId;
    ELSE
    UPDATE  `wave_master`
    SET `LEFT_OVER_STATUS` = 'NO_LEFT_OVER'
    WHERE `WAVE_ID` = p_waveId;
    end if;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateLeftOverBySkuIdAndBatchId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateLeftOverBySkuIdAndBatchId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdateLeftOverBySkuIdAndBatchId`(
    IN p_skuId VARCHAR(200), 
    IN p_batchId VARCHAR(200), 
    IN p_leftOver INT,
    in p_waveId varchar(200)
)
BEGIN
    DECLARE v_quantityPresent INT;
    DECLARE v_waveMasterId INT;
    
    
    SELECT `QUANTITY`, `WAVE_MASTER_ID` 
    INTO v_quantityPresent, v_waveMasterId
    FROM `pick_wave_wms_data`
    WHERE `SKU_ID` = p_skuId
      AND `BATCH_ID` = p_batchId
      AND `LEFT_OVER` = -1
      and `WAVE_ID` = p_waveId
    ORDER BY `PRIORITY` 
    LIMIT 1;
    
    set v_quantityPresent = IFNULL(v_quantityPresent,0);
    
    IF v_quantityPresent < p_leftOver THEN
        SET p_leftOver = v_quantityPresent;
    END IF;
    
    
    UPDATE `pick_wave_wms_data`
    SET `LEFT_OVER` = p_leftOver
    WHERE (`WAVE_MASTER_ID` = v_waveMasterId OR p_leftOver = 0)
      AND `SKU_ID` = p_skuId
      AND `BATCH_ID` = p_batchId
      and `WAVE_ID` = p_waveId
      and `LEFT_OVER` = -1;
      
    
    SELECT p_leftOver;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateMasterOrderStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateMasterOrderStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdateMasterOrderStatus`(
	in binID int,
	in stationID int, 
	in whereStatus varchar(50),
	in setStatus varchar(50)
    )
BEGIN
		DECLARE v_loggedInUser VARCHAR(200);
		
		SELECT `LOGGED_IN_USER_ID` INTO v_loggedInUser
		FROM `hw_station_master`
		WHERE `STATION_ID` = stationId;
		
		update 
		`pick_wave_order_master` 
		set `STATUS` = 'PICK_COMPLETED',
		`PICKED_QUANTITY` = `EXPECTED_QUANTITY`,
		`SHORT_PICK_QUANTITY` = 0,
		`PICK_TIMESTAMP` = current_timeStamp(),
		`PICK_BY` = v_loggedInUser
		where `BIN_ID` = binID 
		and `STATION_ID` = stationID 
		and `STATUS` in ('PENDING','ALLOCATED');
		
		UPDATE pick_wave_order_master AS p1
		JOIN (
		    SELECT ORDER_ID
		    FROM pick_wave_order_master
		    GROUP BY ORDER_ID
		    HAVING COUNT(CASE WHEN STATUS != 'PICK_COMPLETED' THEN 1 END) = 0
		) AS p2
		ON p1.ORDER_ID = p2.ORDER_ID
		SET p1.STATUS = 'ORDER_COMPLETED'
		WHERE p1.STATUS = 'PICK_COMPLETED';
		
		update `order_bin_mapping`
		set `STATUS` = 'OPERATION_COMPLETED'
		where `BIN_ID` = binID
		and `STATION_ID` = stationID
		and `STATUS` = 'ON_STATION';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateOnStationBinStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateOnStationBinStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdateOnStationBinStatus`(
	in p_botID VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in p_stationID int,
	in p_whereStatus VARCHAR(200),
	in p_binId int
    )
BEGIN
		UPDATE `order_bin_mapping` 
		SET `STATUS` = 'ON_STATION' 
		WHERE `BOT_ID`= p_botID 
		and `STATUS` = p_whereStatus 
		and `STATION_ID`=p_stationID
		and `BIN_ID` = p_binId
		and `TYPE` = 'RACK_PICK';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateOrderIdStatusToIntCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateOrderIdStatusToIntCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PickWaveUpdateOrderIdStatusToIntCompleted`(
    IN p_waveId VARCHAR(200)
)
proc:BEGIN
    
    DECLARE v_got_lock INT DEFAULT 0;
    DECLARE v_lock_name VARCHAR(300) DEFAULT '';
    DECLARE v_err_msg TEXT DEFAULT '';

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        
        ROLLBACK;

        
        IF v_lock_name <> '' THEN
            DO RELEASE_LOCK(v_lock_name);
        END IF;

        
        SET v_err_msg = CONCAT('wm_PickWaveUpdateOrderIdStatusToIntCompleted failed for waveId=', p_waveId);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_err_msg;
    END;

    
    SET v_lock_name = CONCAT('WM_PICK_COMPLETE_WAVE_', p_waveId);

    
    SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
    SET SESSION innodb_lock_wait_timeout = 10;

    
    SELECT GET_LOCK(v_lock_name, 5) INTO v_got_lock;

    IF v_got_lock <> 1 THEN
        
        LEAVE proc;
    END IF;

    START TRANSACTION;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_completed_orders;
    CREATE TEMPORARY TABLE tmp_completed_orders (
        ORDER_ID VARCHAR(200) NOT NULL,
        PRIMARY KEY (ORDER_ID)
    ) ENGINE=MEMORY;

    
    INSERT IGNORE INTO tmp_completed_orders (ORDER_ID)
    SELECT wl.ORDER_ID
    FROM pick_wave_wms_data p
    JOIN wms_to_wcs_order_line_request_data wl
         ON wl.ORDER_ID = p.ORDER_ID
    WHERE p.WAVE_ID = p_waveId
    GROUP BY wl.ORDER_ID
    HAVING SUM(wl.ORDER_LINE_PROCESS_STATUS = 'ORDERLINE_COMPLETED') = COUNT(*);

    
    UPDATE wms_to_wcs_order_request_data ord
    JOIN tmp_completed_orders t
         ON t.ORDER_ID = ord.ORDER_ID
    SET ord.ORDER_REQUEST_STATUS = 'ORDER_PICK_COMPLETED',
        ord.UPDATED_TIMESTAMP    = NOW(),
        ord.UPDATED_BY           = 'BACKEND'
    WHERE ord.ORDER_REQUEST_STATUS = 'ORDER_PICK_STARTED';

    COMMIT;

    
    DO RELEASE_LOCK(v_lock_name);

END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateOrderRequestStatusToPending` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateOrderRequestStatusToPending` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdateOrderRequestStatusToPending`(IN p_waveId varchar(200))
BEGIN
    
    UPDATE `wms_to_wcs_order_request_data` 
    SET 
        ORDER_REQUEST_STATUS = 'PENDING'
   
    WHERE ORDER_ID IN (
        SELECT ORDER_ID 
        FROM `pick_wave_wms_data` 
        WHERE WAVE_ID = p_waveId
        AND ORDER_ID IS NOT NULL
    )
    AND ORDER_REQUEST_STATUS = 'ROLLING_BACK';
    
    
    SELECT ROW_COUNT() AS updated_records_count;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateOrderStatusToCompletedOnCancellation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateOrderStatusToCompletedOnCancellation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdateOrderStatusToCompletedOnCancellation`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    
    
    UPDATE wms_to_wcs_order_request_data w
    SET 
        w.ORDER_REQUEST_STATUS = 'ORDER_PICK_COMPLETED',
        w.UPDATED_TIMESTAMP = NOW(3),
        w.UPDATED_BY = 'SYSTEM'
    WHERE 
        w.ORDER_REQUEST_STATUS = 'ORDER_PICK_STARTED'
        AND w.ORDER_ID IN (
            SELECT DISTINCT p.ORDER_ID 
            FROM pick_wave_order_master p 
            WHERE p.STATUS = 'ORDER_COMPLETED'
            AND p.WAVE_ID = p_waveId
        );
    
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdatePtlDisplayByPtlId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdatePtlDisplayByPtlId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdatePtlDisplayByPtlId`(
IN p_ptlId INT, in p_display varchar(10), in p_light varchar(10)
)
BEGIN    
	INSERT INTO `ptl_current_state` (`PTL_ID`, `DISPLAY`, `LIGHT`)
	VALUES (p_ptlId, p_display, p_light)
	ON DUPLICATE KEY UPDATE
	`DISPLAY` = p_display,
	`LIGHT` = p_light;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdatePtlDisplayValue` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdatePtlDisplayValue` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdatePtlDisplayValue`(
IN p_ptlId INT, in p_display varchar(10)
)
BEGIN    
update `hw_ptl_master`
set `DISPLAY` = p_display
where `PTL_ID` = p_ptlId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateVirtualPickForShortPick` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateVirtualPickForShortPick` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PickWaveUpdateVirtualPickForShortPick`(IN p_ptlId INT, IN p_waveId VARCHAR(200))
BEGIN
		DECLARE v_binId INT;
		DECLARE v_segmentNumber INT;
		DECLARE v_quantity INT;
		DECLARE v_errorMessage TEXT;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
		BEGIN
        
        GET DIAGNOSTICS CONDITION 1 v_errorMessage =MESSAGE_TEXT;
        SET v_errorMessage= CONCAT(v_errorMessage,'-',v_step);
        
        ROLLBACK;
        
        SIGNAL SQLSTATE '45000'        
        SET MESSAGE_TEXT = v_errorMessage;
		END;
        
        START TRANSACTION;
		SELECT `BIN_ID`, `BIN_SEGMENT_NO`, SUM(`SHORT_PICK_QUANTITY`) INTO 
		v_binId, v_segmentNumber, v_quantity
		FROM `pick_wave_order_master`
		WHERE `PTL_ID` = p_ptlId
		AND `WAVE_ID` = p_waveId
		AND `STATUS` = 'PICK_STARTED'
		GROUP BY BIN_ID,BIN_SEGMENT_NO,PTL_ID,WAVE_ID;
		
		UPDATE `live_inventory_master`
		SET `VIRTUAL_QUANTITY_TO_PICK` = VIRTUAL_QUANTITY_TO_PICK - v_quantity,
		REMARK='AUDIT_MARKED'
		WHERE `BIN_ID` = v_binId
		AND `SEGMENT_NO` = v_segmentNumber;
        
        COMMIT;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateVirtualPickForShortPick1` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateVirtualPickForShortPick1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdateVirtualPickForShortPick1`(IN p_ptlId INT, in p_waveId varchar(200))
BEGIN
		DECLARE v_binId INT;
		DECLARE v_segmentNumber INT;
		DECLARE v_quantity INT;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            
            ROLLBACK;
		SIGNAL SQLSTATE '45000' 
		SET MESSAGE_TEXT = 'Some Error occurred';
        END;
        
        START TRANSACTION;
		SELECT `BIN_ID`, `BIN_SEGMENT_NO`, sum(`SHORT_PICK_QUANTITY`) INTO 
		v_binId, v_segmentNumber, v_quantity
		FROM `pick_wave_order_master`
		WHERE `PTL_ID` = p_ptlId
		AND `WAVE_ID` = p_waveId
		and `STATUS` = 'PICK_STARTED'
		group by BIN_ID, BIN_SEGMENT_NO, PTL_ID, WAVE_ID;
		
		UPDATE `live_inventory_master`
		SET `VIRTUAL_QUANTITY_TO_PICK` = VIRTUAL_QUANTITY_TO_PICK - v_quantity,
		REMARK='AUDIT_MARKED'
		WHERE `BIN_ID` = v_binId
		AND `SEGMENT_NO` = v_segmentNumber;
        
        COMMIT;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveUpdateVirtualQuantityUponCancellation` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveUpdateVirtualQuantityUponCancellation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveUpdateVirtualQuantityUponCancellation`(
    IN p_binId INT,
    IN p_segmentNumber INT,
    IN p_virtualQuantity INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE error_message TEXT;
        DECLARE error_code INT;
        
        GET DIAGNOSTICS CONDITION 1 
            error_message = MESSAGE_TEXT,
            error_code = MYSQL_ERRNO;
        
        ROLLBACK;
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = error_message;    
    END;
    
    
    START TRANSACTION;
    
    IF (SELECT `VIRTUAL_QUANTITY_TO_PICK` FROM `live_inventory_master`
        WHERE `BIN_ID` = p_binId AND `SEGMENT_NO` = p_segmentNumber) - p_virtualQuantity < 0 THEN
        UPDATE `live_inventory_master`
        SET `VIRTUAL_QUANTITY_TO_PICK` = 0
        WHERE `BIN_ID` = p_binId AND `SEGMENT_NO` = p_segmentNumber;
    ELSE
        UPDATE `live_inventory_master`
        SET `VIRTUAL_QUANTITY_TO_PICK` = `VIRTUAL_QUANTITY_TO_PICK` - p_virtualQuantity
        WHERE `BIN_ID` = p_binId AND `SEGMENT_NO` = p_segmentNumber;
    END IF;
    
    
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PickWaveWmsDataArchiveAndRemove` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PickWaveWmsDataArchiveAndRemove` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PickWaveWmsDataArchiveAndRemove`(IN p_waveId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci, IN p_state VARCHAR(200)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    
    INSERT IGNORE INTO `pick_wave_wms_data_archive` (
        `WAVE_MASTER_ID`, WAVE_ID, ORDER_ID,`ORDER_LINE_ID`, SKU_ID, BATCH_ID, QUANTITY, LEFT_OVER, MRP, EXPIRY_DATE, PRIORITY,
        INSERTED_TIMESTAMP, INSERTED_BY, UPDATED_TIMESTAMP, UPDATED_BY, `ARCHIVE_REASON`
    )
    SELECT 
        `WAVE_MASTER_ID`, WAVE_ID, ORDER_ID,`ORDER_LINE_ID`, SKU_ID, BATCH_ID, QUANTITY, LEFT_OVER, MRP, EXPIRY_DATE, PRIORITY,
        INSERTED_TIMESTAMP, INSERTED_BY, UPDATED_TIMESTAMP, UPDATED_BY, p_state
    FROM `pick_wave_wms_data`
    WHERE WAVE_ID = p_waveId;
    
    DELETE FROM `pick_wave_wms_data`
    WHERE WAVE_ID = p_waveId;
    
    delete from `pick_wave_wms_data_dsb_upload_validation`
    where `WAVE_ID` = p_waveId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveCancelTaskByOrderBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveCancelTaskByOrderBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveCancelTaskByOrderBinId`(
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
	FROM put_wave_order_master
	WHERE `ORDER_BIN_ID` = p_orderBinId
	  AND `STATUS` = 'PENDING'
	  AND `WAVE_ID` = p_waveId;
	
	DELETE FROM put_wave_order_master
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

/* Procedure structure for procedure `wm_PutPalletWaveCheckIfSyncCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveCheckIfSyncCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPalletWaveCheckIfSyncCompleted`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    DECLARE v_put_order_master_count INT;
    DECLARE v_processedCount INT;
    
    SELECT COUNT(*)
    INTO v_put_order_master_count
    FROM put_wave_order_master
    WHERE wave_id = p_waveId
    AND STATUS = 'inventory_updated'
    and expected_quantity != short_put_quantity;
    
    SELECT COUNT(*)
    INTO v_processedCount
    FROM put_wave_order_master pom
    JOIN wcs_to_wms_payload wp 
      ON wp.PAYLOAD_ID = pom.bin_transfer_payload_id
    WHERE pom.wave_id = p_waveId
    AND pom.STATUS = 'inventory_updated'
    AND wp.is_processed = 1;
    
    IF v_put_order_master_count = v_processedCount THEN 
        SELECT 1;
    ELSE 
        SELECT 0;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveDeleteDataByPutOrderId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveDeleteDataByPutOrderId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveDeleteDataByPutOrderId`( 
	IN p_putOrderId VARCHAR(200)
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
	
	
	Delete FROM put_wave_order_master
	WHERE `PUT_ORDER_ID` = p_putOrderId;
	COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetCurrentQuantityForBins` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetCurrentQuantityForBins` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPalletWaveGetCurrentQuantityForBins`(IN p_binIdsJson JSON)
BEGIN
  WITH bins AS (
    SELECT CAST(j.bin_id AS UNSIGNED) AS BIN_ID
    FROM JSON_TABLE(p_binIdsJson, "$[*]" COLUMNS (bin_id INT PATH "$")) j
  )
  SELECT
    lim.BIN_ID,
    lim.SEGMENT_NO,
    COALESCE(lim.QUANTITY + lim.VIRTUAL_QUANTITY_TO_PUT, 0) AS QUANTITY,
    COALESCE(lim.ARTICLE_ID, 'no-sku') AS SKU_ID,
    COALESCE(lim.BATCH_ID,  'no-sku') AS BATCH_ID
  FROM bins b
  LEFT JOIN live_inventory_master lim
    ON lim.BIN_ID = b.BIN_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetCurrentQuantityInBinByBinIdSegmentId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetCurrentQuantityInBinByBinIdSegmentId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetCurrentQuantityInBinByBinIdSegmentId`(
    IN p_binId INT, 
    IN p_segmentId INT
)
BEGIN
    
    IF NOT EXISTS (
        SELECT 1
        FROM `live_inventory_master`
        WHERE `BIN_ID` = p_binId
        AND `SEGMENT_NO` = p_segmentId
    ) THEN
        
        SELECT 0 AS `QUANTITY`, 'no-sku' AS `SKU_ID`, 'no-sku' AS `BATCH_ID`;
    ELSE
        
        SELECT
            IFNULL(`QUANTITY` + `VIRTUAL_QUANTITY_TO_PUT`, 0) AS `QUANTITY`,
            IFNULL(`ARTICLE_ID`, 'no-sku') AS `SKU_ID`,
            IFNULL(`BATCH_ID`, 'no-sku') AS `BATCH_ID`
        FROM `live_inventory_master`
        WHERE `BIN_ID` = p_binId
        AND `SEGMENT_NO` = p_segmentId
        LIMIT 1;  
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetCurrentVersion` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetCurrentVersion` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetCurrentVersion`()
BEGIN

		SELECT `KEY_VALUE` FROM `master_config` WHERE `KEY_NAME` = 'CURRENT_VERSION_OF_PUT_WAVE';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetMaxBinSegment` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetMaxBinSegment` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetMaxBinSegment`()
BEGIN
		select max(BIN_SEGMENT) from `bin_info_master`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetMaxBinVelocity` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetMaxBinVelocity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetMaxBinVelocity`()
BEGIN
		select max(`VELOCITY`) from store_bin_master;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetMaxWeightAllowedOnBot` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetMaxWeightAllowedOnBot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetMaxWeightAllowedOnBot`()
BEGIN
		select `KEY_VALUE` from `master_config` where `KEY_NAME` = 'MAX_WEIGHT_ALLOWED_ON_BOT_GRAMS';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetProcessingOrders` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetProcessingOrders` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetProcessingOrders`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    SELECT `WAVE_MASTER_ID`, 
           `SKU_ID`, 
           `BATCH_ID`, 
	    SUM(`QUANTITY` - CASE WHEN `LEFT_OVER` < 0 THEN 0 ELSE `LEFT_OVER` END) AS `QUANTITY`,
           `STORAGE_ID`,
           `STORAGE_REQUEST_ID`
    FROM `put_wave_wms_data` 
    WHERE `LEFT_OVER` >= 0 
      AND `WAVE_ID` = p_waveId
     GROUP BY 
    `SKU_ID`, 
    `BATCH_ID`, 
    `STORAGE_ID`, 
    `STORAGE_REQUEST_ID`
ORDER BY `QUANTITY` DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetProcessingOrdersForSP` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetProcessingOrdersForSP` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPalletWaveGetProcessingOrdersForSP`(
    IN p_waveId VARCHAR(200)
)
BEGIN
	UPDATE `live_inventory_master` SET `ARTICLE_ID` = 'no-sku', `BATCH_ID` ='no-sku' WHERE quantity=0 AND virtual_quantity_to_put=0; 
    SELECT `WAVE_MASTER_ID`, 
           `SKU_ID`, 
           `BATCH_ID`, 
           `STATION_ID`,
	    SUM(`QUANTITY` - CASE WHEN `LEFT_OVER` < 0 THEN 0 ELSE `LEFT_OVER` END) AS `QUANTITY`,
           `STORAGE_ID`,
           `STORAGE_REQUEST_ID`
    FROM `put_wave_wms_data` 
    WHERE `LEFT_OVER` >= 0 
      AND `WAVE_ID` = p_waveId
      AND STATUS = 'pending'
     GROUP BY 
    `SKU_ID`, 
    `BATCH_ID`, 
    `STORAGE_ID`, 
    `STORAGE_REQUEST_ID`
ORDER BY `QUANTITY` DESC
limit 50;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetProximitySkuList` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetProximitySkuList` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetProximitySkuList`(
    IN p_skuId VARCHAR(200),
    IN p_minSegment INT)
BEGIN
    DECLARE v_category INT;
    
    
    SELECT `CATEGORY` INTO v_category 
    FROM `sku_master` WHERE `SKU_ID` = p_skuId;
    
    
    CREATE TEMPORARY TABLE IF NOT EXISTS v_proximityTable (
        SKU_ID VARCHAR(200),
        SCORE DECIMAL(10,3),
        CATEGORY INT
    );
    
    
    INSERT INTO v_proximityTable (SKU_ID, SCORE, CATEGORY)
    SELECT aps.`PARENT_ARTICLE_ID`, aps.`PROXIMITY_SCORE`, sm.`CATEGORY`
    FROM `article_proximity_score` aps
    JOIN `sku_master` sm ON sm.`SKU_ID` = aps.`PARENT_ARTICLE_ID`
    WHERE aps.`CHILD_ARTICLE_ID` = p_skuId;
    
    
    INSERT INTO v_proximityTable (SKU_ID, SCORE, CATEGORY)
    SELECT aps.`CHILD_ARTICLE_ID`, aps.`PROXIMITY_SCORE`, sm.`CATEGORY`
    FROM `article_proximity_score` aps
    JOIN `sku_master` sm ON sm.`SKU_ID` = aps.`CHILD_ARTICLE_ID`
    WHERE aps.`PARENT_ARTICLE_ID` = p_skuId;
    
    
    SELECT SKU_ID, SCORE
    FROM v_proximityTable
    WHERE CATEGORY IN (
        SELECT `CHILD_CATEGORY_ID` 
        FROM `category_matrix` 
        WHERE `PARENT_CATEGORY_ID` = v_category
    )
    ORDER BY SCORE DESC
    LIMIT p_minSegment;
    
    
    DROP TEMPORARY TABLE IF EXISTS v_proximityTable;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetQuantityAllocatedByStorageId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetQuantityAllocatedByStorageId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetQuantityAllocatedByStorageId`(
	IN p_waveId VARCHAR(200), in p_storageId varchar(200)
    )
BEGIN
		SELECT IFNULL(SUM(IFNULL(`EXPECTED_QUANTITY`, 0)), 0)
		FROM `put_wave_order_master` 
		WHERE `STORAGE_ID` = p_storageId
		AND `WAVE_ID`= p_waveId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetStorageRequestDataByPalletId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetStorageRequestDataByPalletId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `wm_PutPalletWaveGetStorageRequestDataByPalletId`(
    IN p_waveId VARCHAR(200),
    IN p_palletBarcode VARCHAR(200),
	IN p_stationId     INT
)
BEGIN
    DECLARE v_storageRequestStatus VARCHAR(100);
    DECLARE v_storageRequestId VARCHAR(36);
    declare v_wmsStorageRequestPalletData bigint;
    DECLARE v_errorMessage TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;
        
        ROLLBACK;
        
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errorMessage;
    END;
    
    START TRANSACTION;
    
    SELECT `STORAGE_REQUEST_STATUS`, `STORAGE_REQUEST_ID`,`WMS_STORAGE_REQUEST_PALLET_DATA_ID`
    INTO v_storageRequestStatus, v_storageRequestId,v_wmsStorageRequestPalletData
    FROM `wms_to_wcs_storage_request_pallet_data`
    WHERE `PALLET_ID` = p_palletBarcode 
    order by `INSERT_TIMESTAMP` desc 
    LIMIT 1;
    
    IF v_storageRequestStatus IS NULL THEN
        SELECT 'Pallet Data Is Not Available' AS Message, 0 AS Status;
    ELSEIF v_storageRequestStatus = 'PENDING' THEN
        SELECT 'Pallet Scanned Successfully' AS Message, v_wmsStorageRequestPalletData AS Status;
    ELSEIF v_storageRequestStatus = 'PALLET_SCANNED' THEN
        SELECT 'Pallet SKU Already Added To The Wave' AS Message, 0 AS Status;
    ELSE
        SELECT 'Pallet Data Is Not Available' AS Message, 0 AS Status;
    END IF;
    
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetStorageRequestDataIdByStorageRequestId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetStorageRequestDataIdByStorageRequestId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetStorageRequestDataIdByStorageRequestId`(
    IN p_storageRequestId VARCHAR(36)
)
BEGIN
    DECLARE v_palletId VARCHAR(36);
    DECLARE v_gln VARCHAR(100);
    DECLARE v_insertedBy VARCHAR(50);
    DECLARE v_updatedBy VARCHAR(50);
    DECLARE v_existingRecordId INT;
    
    SELECT WMS_STORAGE_REQUEST_PALLET_DATA_ID 
    INTO v_existingRecordId
    FROM wms_to_wcs_storage_request_pallet_data
    WHERE STORAGE_REQUEST_ID = p_storageRequestId
    AND STORAGE_REQUEST_STATUS = 'ROLLING_BACK'
    LIMIT 1;
    
    IF v_existingRecordId IS NOT NULL THEN
        SELECT v_existingRecordId AS newRecordId;
    ELSE
        
        SELECT 
            GLN, PALLET_ID, INSERTED_BY, UPDATED_BY
        INTO 
            v_gln, v_palletId, v_insertedBy, v_updatedBy
        FROM wms_to_wcs_storage_request_pallet_data
        WHERE STORAGE_REQUEST_ID = p_storageRequestId
        AND STORAGE_REQUEST_STATUS = 'PALLET_SCANNED'
        AND PALLET_SCANNED = 1
        ORDER BY INSERT_TIMESTAMP DESC
        LIMIT 1;
        
        
        update wms_to_wcs_storage_request_pallet_data
        SET STORAGE_REQUEST_STATUS = 'PALLET_SUSPENDED'
        WHERE STORAGE_REQUEST_ID = p_storageRequestId
        AND STORAGE_REQUEST_STATUS = 'PALLET_SCANNED'
        AND PALLET_SCANNED = 1
        ORDER BY INSERT_TIMESTAMP DESC
        LIMIT 1 ;
        
        
        INSERT INTO wms_to_wcs_storage_request_pallet_data (
            GLN, STORAGE_REQUEST_ID, PALLET_ID, STORAGE_REQUEST_STATUS, PALLET_SCANNED, 
            INSERT_TIMESTAMP, INSERTED_BY, UPDATE_TIMESTAMP, UPDATED_BY
        )
        VALUES (
            v_gln, p_storageRequestId, v_palletId, 'ROLLING_BACK', 0, 
            CURRENT_TIMESTAMP(3), v_insertedBy, CURRENT_TIMESTAMP(3), v_updatedBy
        );
        
        SELECT LAST_INSERT_ID() AS newRecordId;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetTaskByOrderBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetTaskByOrderBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetTaskByOrderBinId`(
	IN p_orderBinId INT, 
	IN p_waveId VARCHAR(200)
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
	
	
	SELECT * FROM put_wave_order_master
	WHERE `ORDER_BIN_ID` = p_orderBinId
	  AND `WAVE_ID` = p_waveId;
	COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveGetValidStationBarcodeScanMessage` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveGetValidStationBarcodeScanMessage` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveGetValidStationBarcodeScanMessage`()
BEGIN
		select 'You Have Scanned Valid Station Barcode Now Scan Pallet Barcode To Map';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveInsertInPutWaveOrderMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveInsertInPutWaveOrderMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveInsertInPutWaveOrderMaster`(
    IN p_waveId VARCHAR(200),
    IN p_skuId VARCHAR(200),
    IN p_batchId VARCHAR(200),
    IN p_quantity INT,
    IN p_binId INT,
    IN p_segmentNumber INT,
    IN p_stationId INT,
    IN p_orderBinId INT,
    in p_storageRequestId varchar(50),
    in p_storageId varchar(50)
)
BEGIN
    DECLARE v_putOrderId CHAR(36);
    DECLARE v_errorMessage TEXT;
DECLARE EXIT HANDLER FOR SQLEXCEPTION
BEGIN
    
    GET DIAGNOSTICS CONDITION 1
    v_errorMessage = MESSAGE_TEXT;
    
    ROLLBACK;
    
    SIGNAL SQLSTATE '45000' 
    SET MESSAGE_TEXT = v_errorMessage;
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
          and `STORAGE_REQUEST_ID` = p_storageRequestId
          and `STORAGE_ID` = p_storageId
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
          AND `STORAGE_REQUEST_ID` = p_storageRequestId
          AND `STORAGE_ID` = p_storageId
          AND `STATUS` = 'PENDING';
    ELSE
        
        SELECT UUID() INTO v_putOrderId;
        
        INSERT INTO `put_wave_order_master`
            (`PUT_ORDER_ID`, `WAVE_ID`, `SKU_ID`, 
            `BATCH_ID`, `EXPECTED_QUANTITY`, `ORDER_BIN_ID`, 
            `BIN_ID`, `BIN_SEGMENT_NO`, `STATION_ID`, `STATUS`,STORAGE_REQUEST_ID,STORAGE_ID)
        VALUES
            (v_putOrderId, p_waveId, p_skuId, p_batchId, p_quantity, p_orderBinId, p_binId, p_segmentNumber, p_stationId, 'PENDING',p_storageRequestId,p_storageId);
    END IF;
    
    UPDATE `hw_station_master`
    SET `STATION_UTILISATION` = `STATION_UTILISATION` + p_quantity + 1
    WHERE `STATION_ID` = p_stationId;
    
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveInsertIntoWmsDataByPalletId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveInsertIntoWmsDataByPalletId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveInsertIntoWmsDataByPalletId`(
    IN p_waveId VARCHAR(200),
    IN p_stationId INT,
    IN p_palletBarcode VARCHAR(200),
    in p_wmsStorageRequestPalletData int
)
BEGIN
    
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
    
	DECLARE v_errorMessage TEXT;
	
        
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;
        
        ROLLBACK;
        
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errorMessage;
    END;
    
    START TRANSACTION;
    
        INSERT INTO put_wave_wms_data (
            WAVE_ID,
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            STATION_ID,
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
            p_stationId,
            ARTICLE_ID AS SKU_ID,
            BATCH_ID,
            QUANTITY,
            INSERTED_BY,
            UPDATED_BY,
            0
        FROM wms_to_wcs_storage_request_data
        WHERE `WMS_STORAGE_REQUEST_PALLET_DATA_ID` = p_wmsStorageRequestPalletData;
        
        
        UPDATE wms_to_wcs_storage_request_pallet_data
        SET 
            `STORAGE_REQUEST_STATUS` = 'PALLET_SCANNED',
            `PALLET_SCANNED_TIMESTAMP` = CURRENT_TIMESTAMP(3),
            `PALLET_SCANNED` = 1
        WHERE `PALLET_ID` = p_palletBarcode
        AND `WMS_STORAGE_REQUEST_PALLET_DATA_ID` = p_wmsStorageRequestPalletData;
        
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveMarkPalletCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveMarkPalletCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveMarkPalletCompleted`(IN p_waveId CHAR(200), IN p_state VARCHAR(200))
BEGIN
    UPDATE `wms_to_wcs_storage_request_pallet_data`
    SET `PALLET_COMPLETION` = 1,
        `PALLET_COMPLETION_TIMESTAMP` = CURRENT_TIMESTAMP(),
        `STORAGE_REQUEST_STATUS` = 'PALLET_COMPLETED'
    WHERE `STORAGE_REQUEST_ID` IN (
        SELECT `STORAGE_REQUEST_ID`
        FROM `put_wave_order_master`
        WHERE `WAVE_ID` = p_waveId
    )
    AND `STORAGE_REQUEST_STATUS` = 'PALLET_SCANNED';
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveOrderMasterArchiveAndRemove` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveOrderMasterArchiveAndRemove` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveOrderMasterArchiveAndRemove`(IN p_waveId CHAR(200), IN p_state VARCHAR(200))
BEGIN
     
    INSERT IGNORE INTO `put_wave_order_master_archive` (
        `PUT_ORDER_ID`, `WAVE_ID`, `STORAGE_REQUEST_ID`, `STORAGE_ID`, `ORDER_BIN_ID`, `BIN_ID`, 
        `BIN_SEGMENT_NO`, `STATUS`, `STATION_ID`, `SKU_ID`, `BATCH_ID`, `EAN_NO`, 
        `EXPECTED_QUANTITY`, `PUT_QUANTITY`, `SHORT_PUT_QUANTITY`, `PUT_START_TIMESTAMP`, 
        `PUT_TIMESTAMP`, `PUT_BY`, `BIN_TRANSFER_PAYLOAD_ID`, `INSERTED_TIMESTAMP`, 
        `INSERTED_BY`, `UPDATED_TIMESTAMP`, `UPDATED_BY`, `ARCHIVE_REASON`
    )
    SELECT 
        `PUT_ORDER_ID`, `WAVE_ID`, `STORAGE_REQUEST_ID`, `STORAGE_ID`, `ORDER_BIN_ID`, `BIN_ID`, 
        `BIN_SEGMENT_NO`, `STATUS`, `STATION_ID`, `SKU_ID`, `BATCH_ID`, `EAN_NO`, 
        `EXPECTED_QUANTITY`, `PUT_QUANTITY`, `SHORT_PUT_QUANTITY`, `PUT_START_TIMESTAMP`, 
        `PUT_TIMESTAMP`, `PUT_BY`, `BIN_TRANSFER_PAYLOAD_ID`, `INSERTED_TIMESTAMP`, 
        `INSERTED_BY`, `UPDATED_TIMESTAMP`, `UPDATED_BY`, p_state
    FROM `put_wave_order_master`
    WHERE `WAVE_ID` = p_waveId;
    
    DELETE FROM `put_wave_order_master`
    WHERE `WAVE_ID` = p_waveId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveOrderMasterQuantityRevert` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveOrderMasterQuantityRevert` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveOrderMasterQuantityRevert`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    SELECT 
        pwwd.STORAGE_REQUEST_ID,
        pwwd.STORAGE_ID,
        pwwd.total_quantity AS WMS_QUANTITY,
        IFNULL(completed.completed_quantity, 0) AS PUT_COMPLETED_QUANTITY,
        IFNULL(reattempted.reattempted_quantity, 0) AS REATTEMPTED_QUANTITY,
        (pwwd.total_quantity 
            - (IFNULL(completed.completed_quantity, 0) 
            + IFNULL(reattempted.reattempted_quantity, 0))
        ) AS REVERT_QUANTITY
    FROM (
        SELECT 
            STORAGE_REQUEST_ID, 
            STORAGE_ID, 
            SUM(
		QUANTITY - IF(IFNULL(LEFT_OVER, 0) < 0, 0, IFNULL(LEFT_OVER, 0))
		) AS total_quantity
        FROM 
            put_wave_wms_data
        WHERE 
            WAVE_ID = p_waveId
        GROUP BY 
            STORAGE_REQUEST_ID, 
            STORAGE_ID
    ) AS pwwd
    join `wms_to_wcs_storage_request_pallet_data` wwsrpd
    on wwsrpd.`STORAGE_REQUEST_ID` = pwwd.STORAGE_REQUEST_ID and wwsrpd.`STORAGE_REQUEST_STATUS` = 'PALLET_SCANNED'
    LEFT JOIN (
        SELECT 
            STORAGE_REQUEST_ID, 
            STORAGE_ID, 
            SUM(PUT_QUANTITY) AS completed_quantity
        FROM 
            put_wave_order_master
        WHERE 
            STATUS in ('PUT_COMPLETED','INVENTORY_UPDATED')
            AND WAVE_ID = p_waveId
        GROUP BY 
            STORAGE_REQUEST_ID, 
            STORAGE_ID
    ) AS completed
    ON completed.STORAGE_REQUEST_ID = pwwd.STORAGE_REQUEST_ID 
       AND completed.STORAGE_ID = pwwd.STORAGE_ID
    LEFT JOIN (
        SELECT 
            pwom.STORAGE_REQUEST_ID, 
            pwom.STORAGE_ID, 
            SUM(IFNULL(spwr.RE_ATTEMPT_QUANTITY, 0)) AS reattempted_quantity
        FROM 
            put_wave_order_master pwom
        JOIN 
            short_put_wave_reason spwr
        ON 
            spwr.PUT_ORDER_ID = pwom.PUT_ORDER_ID
        WHERE 
            pwom.WAVE_ID = p_waveId
            AND (IFNULL(spwr.SHORT_PUT_QUANTITY, 0) - IFNULL(spwr.RE_ATTEMPT_QUANTITY, 0)) = 0
        GROUP BY 
            pwom.STORAGE_REQUEST_ID, 
            pwom.STORAGE_ID
    ) AS reattempted
    ON reattempted.STORAGE_REQUEST_ID = pwwd.STORAGE_REQUEST_ID 
       AND reattempted.STORAGE_ID = pwwd.STORAGE_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveOrderMasterQuantityRevert1` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveOrderMasterQuantityRevert1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveOrderMasterQuantityRevert1`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    SELECT 
        pwwd.STORAGE_REQUEST_ID,
        pwwd.STORAGE_ID,
        pwwd.total_quantity AS WMS_QUANTITY,
        IFNULL(completed.completed_quantity, 0) AS PUT_COMPLETED_QUANTITY,
        IFNULL(reattempted.reattempted_quantity, 0) AS REATTEMPTED_QUANTITY,
        (pwwd.total_quantity 
            - (IFNULL(completed.completed_quantity, 0) 
            + IFNULL(reattempted.reattempted_quantity, 0))
        ) AS REVERT_QUANTITY
    FROM (
        SELECT 
            STORAGE_REQUEST_ID, 
            STORAGE_ID, 
            SUM(
		QUANTITY - IF(IFNULL(LEFT_OVER, 0) < 0, 0, IFNULL(LEFT_OVER, 0))
		) AS total_quantity
        FROM 
            put_wave_wms_data
        WHERE 
            WAVE_ID = p_waveId
        GROUP BY 
            STORAGE_REQUEST_ID, 
            STORAGE_ID
    ) AS pwwd
    join `wms_to_wcs_storage_request_pallet_data` wwsrpd
    on wwsrpd.`STORAGE_REQUEST_ID` = pwwd.STORAGE_REQUEST_ID and wwsrpd.`STORAGE_REQUEST_STATUS` = 'PALLET_SCANNED'
    LEFT JOIN (
        SELECT 
            STORAGE_REQUEST_ID, 
            STORAGE_ID, 
            SUM(PUT_QUANTITY) AS completed_quantity
        FROM 
            put_wave_order_master
        WHERE 
            STATUS in ('PUT_COMPLETED','INVENTORY_UPDATED')
            AND WAVE_ID = p_waveId
        GROUP BY 
            STORAGE_REQUEST_ID, 
            STORAGE_ID
    ) AS completed
    ON completed.STORAGE_REQUEST_ID = pwwd.STORAGE_REQUEST_ID 
       AND completed.STORAGE_ID = pwwd.STORAGE_ID
    LEFT JOIN (
        SELECT 
            pwom.STORAGE_REQUEST_ID, 
            pwom.STORAGE_ID, 
            SUM(IFNULL(spwr.RE_ATTEMPT_QUANTITY, 0)) AS reattempted_quantity
        FROM 
            put_wave_order_master pwom
        JOIN 
            short_put_wave_reason spwr
        ON 
            spwr.PUT_ORDER_ID = pwom.PUT_ORDER_ID
        WHERE 
            pwom.WAVE_ID = p_waveId
            AND (IFNULL(spwr.SHORT_PUT_QUANTITY, 0) - IFNULL(spwr.RE_ATTEMPT_QUANTITY, 0)) = 0
        GROUP BY 
            pwom.STORAGE_REQUEST_ID, 
            pwom.STORAGE_ID
    ) AS reattempted
    ON reattempted.STORAGE_REQUEST_ID = pwwd.STORAGE_REQUEST_ID 
       AND reattempted.STORAGE_ID = pwwd.STORAGE_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveOrderMasterShortPutQuantityRevert` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveOrderMasterShortPutQuantityRevert` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveOrderMasterShortPutQuantityRevert`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    SELECT 
	spwr.`SHORT_PUT_WAVE_REASON_ID` as SHORT_PUT_WAVE_REASON_ID,
        pwom.STORAGE_REQUEST_ID AS STORAGE_REQUEST_ID,
        pwom.STORAGE_ID AS STORAGE_ID,
        (IFNULL(spwr.SHORT_PUT_QUANTITY, 0) - IFNULL(spwr.RE_ATTEMPT_QUANTITY, 0)) AS QUANTITY
    FROM `put_wave_order_master` pwom
    JOIN `short_put_wave_reason` spwr
        ON spwr.PUT_ORDER_ID = pwom.PUT_ORDER_ID
    WHERE pwom.WAVE_ID = p_waveId
      AND (IFNULL(spwr.SHORT_PUT_QUANTITY, 0) - IFNULL(spwr.RE_ATTEMPT_QUANTITY, 0)) > 0;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveSelectBinsAllocatedToBots` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveSelectBinsAllocatedToBots` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveSelectBinsAllocatedToBots`(
	IN p_minSlotSize INT, IN p_velocity INT, in p_skuId varchar(200), in p_batchId varchar(200))
BEGIN
	SELECT OBM.`BIN_ID`
	FROM `order_bin_mapping` OBM
	LEFT JOIN `bin_info_master` BIM 
	ON BIM.`BIN_ID` = OBM.`BIN_ID` 
	WHERE BIM.`BIN_SEGMENTS` = p_minSlotSize
	and OBM.BOT_ID is not null;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveUpdateInventoryUpdatedStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveUpdateInventoryUpdatedStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveUpdateInventoryUpdatedStatus`(
    IN p_putOrderId varchar(50)
)
BEGIN
    UPDATE `put_wave_order_master`
    SET `STATUS` = 'INVENTORY_UPDATED'
    WHERE `PUT_ORDER_ID` = p_putOrderId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveUpdateLeftOverByArticleId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveUpdateLeftOverByArticleId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveUpdateLeftOverByArticleId`( in p_storageId varchar(200), in p_leftOverQuantity INT, IN p_waveId varchar(200))
BEGIN
		UPDATE put_wave_wms_data
		SET LEFT_OVER = p_leftOverQuantity  
		WHERE `STORAGE_ID` = p_storageId
		and `WAVE_ID` = p_waveId
		ORDER BY `INSERTED_TIMESTAMP` DESC
		limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveUpdateShortPutReattemptFlag` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveUpdateShortPutReattemptFlag` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveUpdateShortPutReattemptFlag`(
    IN p_shortPutWaveReasonId VARCHAR(200)
)
BEGIN
    update short_put_wave_reason
    set `RE_ATTEMPT_FLAG` = 1,
    `RE_ATTEMPT_QUANTITY` = `SHORT_PUT_QUANTITY`
    where `SHORT_PUT_WAVE_REASON_ID` = p_shortPutWaveReasonId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveUpdateShortPutReAttemptFlagByWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveUpdateShortPutReAttemptFlagByWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveUpdateShortPutReAttemptFlagByWaveId`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    UPDATE short_put_wave_reason spr
	JOIN put_wave_order_master pwom 
	    ON spr.PUT_ORDER_ID = pwom.PUT_ORDER_ID
	JOIN wms_to_wcs_storage_request_pallet_data ws
	    ON pwom.STORAGE_REQUEST_ID = ws.STORAGE_REQUEST_ID
	SET spr.RE_ATTEMPT_FLAG = 1,
	    spr.RE_ATTEMPT_QUANTITY = spr.SHORT_PUT_QUANTITY
	WHERE pwom.WAVE_ID = p_waveId
	  AND spr.RE_ATTEMPT_FLAG = 0
	  AND ws.STORAGE_REQUEST_STATUS = 'PENDING';
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveUpdateStatusRollingBackToPending` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveUpdateStatusRollingBackToPending` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveUpdateStatusRollingBackToPending`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    update `wms_to_wcs_storage_request_pallet_data`
    set `STORAGE_REQUEST_STATUS` = 'PENDING'
    where `STORAGE_REQUEST_STATUS` = 'ROLLING_BACK'
    and `STORAGE_REQUEST_ID` in (select `STORAGE_REQUEST_ID` 
				from `put_wave_wms_data`
				where `WAVE_ID` = p_waveId);
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_PutPalletWaveUpsertStorageRequestData` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_PutPalletWaveUpsertStorageRequestData` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_PutPalletWaveUpsertStorageRequestData`(
    IN p_storageRequestId VARCHAR(36),
    IN p_storageId VARCHAR(36),
    IN p_wmsStorageRequestPalletDataId BIGINT,
    IN p_quantity INT
)
BEGIN
    DECLARE v_existingRecordId BIGINT;
    
    
    SELECT WMS_STORAGE_REQUEST_DATA_ID 
    INTO v_existingRecordId
    FROM wms_to_wcs_storage_request_data
    WHERE STORAGE_REQUEST_ID = p_storageRequestId
    AND STORAGE_ID = p_storageId
    AND WMS_STORAGE_REQUEST_PALLET_DATA_ID = p_wmsStorageRequestPalletDataId
    LIMIT 1;
    
    IF v_existingRecordId IS NOT NULL THEN
        UPDATE wms_to_wcs_storage_request_data
        SET QUANTITY = QUANTITY + p_quantity
        WHERE WMS_STORAGE_REQUEST_DATA_ID = v_existingRecordId; 
    ELSE
        
        INSERT INTO wms_to_wcs_storage_request_data (
            WMS_STORAGE_REQUEST_PALLET_DATA_ID, STORAGE_REQUEST_ID, STORAGE_ID, ARTICLE_ID,
            QUANTITY, BATCH_ID, PAYLOAD_ID, INSERTED_BY, 
            UPDATED_BY, STATUS
        )
        SELECT 
            p_wmsStorageRequestPalletDataId, p_storageRequestId, p_storageId, ARTICLE_ID,
            p_quantity, BATCH_ID, PAYLOAD_ID, INSERTED_BY,
            UPDATED_BY, 'PENDING'
        FROM wms_to_wcs_storage_request_data
        WHERE STORAGE_REQUEST_ID = p_storageRequestId
        AND STORAGE_ID = p_storageId
        LIMIT 1;
        
        SET v_existingRecordId = LAST_INSERT_ID();
    END IF;
  
END */$$
DELIMITER ;