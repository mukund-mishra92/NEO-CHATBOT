
------------------------------------------------------------------------------------------------------------------------
/* Procedure structure for procedure `INT_CRON_PICK_ORDER_REQUEST_SCANNED_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_PICK_ORDER_REQUEST_SCANNED_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_PICK_ORDER_REQUEST_SCANNED_STATUS`()
BEGIN
  
     
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    
    SELECT KEY_VALUE INTO @IntegrationTimeCounter FROM `master_config` WHERE KEY_NAME='INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    
    CREATE TEMPORARY TABLE TempPayloads (
        `id` INT,
        `payload_id` CHAR(36),
        `headers` JSON,
        `json_output` JSON
    );
    
    
    INSERT INTO TempPayloads (id, `payload_id`,headers, `json_output`)  
	SELECT 
	    wm.`WMS_ORDER_REQUEST_DATA_ID`,
	     UUID(),
        JSON_OBJECT(
		@glnHeader,wm.`GLN`),
	    JSON_OBJECT(
		'Gln', wm.`GLN`,
		'PickingType', wm.`PICKING_TYPE`, 
		'BatchPicklistId', wm.`BATCH_PICKLIST_ID`,  
		'OrderId', wm.`CLIENT_ORDER_ID`,
		'Status', 'NEO_PICKING_IN_PROGRESS', 
		'EventTimestamp', wm.`UPDATED_TIMESTAMP`
	    )
	FROM  `wms_to_wcs_order_level_pre_staged_data` wm
	WHERE wm.`ORDER_REQUEST_STATUS` = 'ORDER_PICK_STARTED'
	  AND wm.`ORDER_REQUEST_SCANNED_PAYLOAD` IS NULL LIMIT 500;
    
    START TRANSACTION;    
    
    
    INSERT  INTO `wcs_to_wms_payload` (`PAYLOAD_ID`,`API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`,headers, '308', 'cronJob', `json_output`
    FROM TempPayloads;
    
    UPDATE `wms_to_wcs_order_level_pre_staged_data` AS C
    INNER JOIN TempPayloads AS T ON C.`WMS_ORDER_REQUEST_DATA_ID` = T.`id`
    SET C.`ORDER_REQUEST_SCANNED_PAYLOAD` = T.`payload_id`;
	
    COMMIT;
    
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    
    SELECT *
	FROM `wcs_to_wms_payload` wcs
	WHERE wcs.`API_ID` = 308
	  AND wcs.`IS_PROCESSED` <> 1

	  
	  AND (
		wcs.`IS_PROCESSED` <> -2
		OR (
		     wcs.`IS_PROCESSED` = -2
		     AND wcs.`PROCESSED_TIMESTAMP` < DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 6000 SECOND)
		   )
	      )

	  
	  AND (
		wcs.`NO_OF_ATTEMPTS` = 0
		OR (
		     wcs.`NO_OF_ATTEMPTS` < 5
		     AND wcs.`PROCESSED_TIMESTAMP` < DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 1000 SECOND)
		   )
	      )
	LIMIT 100;    
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_PICK_ORDER_REQUEST_SUSPENDED_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_PICK_ORDER_REQUEST_SUSPENDED_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_PICK_ORDER_REQUEST_SUSPENDED_STATUS`()
BEGIN
    
    DECLARE TimerCounter INT DEFAULT 1000;    
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    
    CREATE TEMPORARY TABLE TempPayloads (
        `wms_order_id` INT,
        `payload_id` CHAR(36),
        `json_output` JSON
    );
    
    
    INSERT INTO TempPayloads (wms_order_id, `payload_id`, `json_output`)  
	SELECT 
	    wm.`WMS_ORDER_REQUEST_DATA_ID`,
	    UUID(),
	    JSON_OBJECT(
		'Gln', wm.`GLN`,
		'PickingType', wm.`PICKING_TYPE`, 
		'BatchPicklistId', wm.`BATCH_PICKLIST_ID`,  
		'OrderId', wm.`CLIENT_ORDER_ID`,
		'Status', 'NEO_PICKING_SUSPENDED', 
		'EventTimestamp', wm.`UPDATED_TIMESTAMP`
	    )
	FROM `wms_to_wcs_order_level_pre_staged_data` wm
	WHERE wm.`ORDER_REQUEST_STATUS` = 'SUSPENDED'
	  AND wm.`ORDER_REQUEST_COMPLETED_PAYLOAD` IS NULL LIMIT 500;
    start Transaction;
    
    INSERT IGNORE INTO `wcs_to_wms_payload` (`PAYLOAD_ID`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`, '307', 'cronJob', `json_output`
    FROM TempPayloads;
    
    UPDATE `wms_to_wcs_order_level_pre_staged_data` AS C
    INNER JOIN TempPayloads AS T ON C.`WMS_ORDER_REQUEST_DATA_ID` = T.`wms_order_id`
    SET C.ORDER_REQUEST_COMPLETED_PAYLOAD = T.`payload_id`;
    commit;
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    SELECT *
    FROM `wcs_to_wms_payload` wcs
    WHERE wcs.`API_ID` = '-1' 
      AND wcs.`IS_PROCESSED` <> 1
      AND (
          wcs.`NO_OF_ATTEMPTS` = 0 
          OR (
              wcs.`NO_OF_ATTEMPTS` < 5
              AND wcs.`PROCESSED_TIMESTAMP` < DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL -5000 SECOND)
          )
      )
    LIMIT 500;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_PUT_STORAGE_REQUEST_BIN_TRANSFER` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_PUT_STORAGE_REQUEST_BIN_TRANSFER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_PUT_STORAGE_REQUEST_BIN_TRANSFER`()
BEGIN
    
  SELECT KEY_VALUE INTO @IntegrationTimeCounter FROM `master_config` WHERE KEY_NAME='INTEGRATION_RETRY_TIMER';
  SELECT KEY_VALUE INTO @InfiniteRetryAttemtps FROM `master_config` WHERE KEY_NAME='INTEGRATION_INFINITE_RETRY_TIMER';
  SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
      
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    
    CREATE TEMPORARY TABLE TempPayloads (
        `id` VARCHAR(50),
        `payload_id` CHAR(36),
        `headers` JSON,
        `json_output` JSON,
         UNIQUE KEY (`id`)
    );
    
   
    
    
    INSERT INTO TempPayloads (id, `payload_id`,headers, `json_output`)  
    SELECT 
        wm.`PUT_ORDER_ID`,
        UUID(),
         JSON_OBJECT(
		@glnHeader,pd.`GLN`),
        JSON_OBJECT(
            'Gln', pd.`GLN`,
            'StorageId', wm.`STORAGE_ID`,
            'BinId', CAST(wm.`BIN_ID` AS CHAR),
            'BinSegment', wm.`BIN_SEGMENT_NO`,
            'Quantity', wm.`PUT_QUANTITY`,
            'UserId', wm.`PUT_BY`,
            'EventTimestamp', wm.`PUT_TIMESTAMP`
        )
    FROM `put_wave_order_master` wm
    INNER JOIN (
 SELECT 
        STORAGE_REQUEST_ID,
        MAX(GLN)  AS GLN  
    FROM wms_to_wcs_storage_request_pallet_data
    GROUP BY STORAGE_REQUEST_ID
) pd ON pd.STORAGE_REQUEST_ID = wm.STORAGE_REQUEST_ID  
    WHERE 
       wm.`BIN_TRANSFER_PAYLOAD_ID` IS NULL 
      AND wm.`STATUS` = 'INVENTORY_UPDATED' 
      AND wm.`STORAGE_ID` IS NOT NULL 
      AND wm.PUT_QUANTITY <>0 
    LIMIT 500;
    
     
    INSERT IGNORE INTO TempPayloads (id, `payload_id`,headers, `json_output`)  
    SELECT 
        wm.`PUT_ORDER_ID`,
        UUID(),
         JSON_OBJECT(
		@glnHeader,pd.`GLN`),
        JSON_OBJECT(
            'Gln', pd.`GLN`,
            'StorageId', wm.`STORAGE_ID`,
            'BinId', CAST(wm.`BIN_ID` AS CHAR),
            'BinSegment', wm.`BIN_SEGMENT_NO`,
            'Quantity', wm.`PUT_QUANTITY`,
            'UserId', wm.`PUT_BY`,
            'EventTimestamp', wm.`PUT_TIMESTAMP`
        )
    FROM `put_wave_order_master_archive` wm
    INNER JOIN (
 SELECT 
        STORAGE_REQUEST_ID,
        MAX(GLN)  AS GLN  
    FROM wms_to_wcs_storage_request_pallet_data
    GROUP BY STORAGE_REQUEST_ID
) pd ON pd.STORAGE_REQUEST_ID = wm.STORAGE_REQUEST_ID  
    WHERE 
       wm.`BIN_TRANSFER_PAYLOAD_ID` IS NULL 
      AND wm.`STATUS` = 'INVENTORY_UPDATED' 
      AND wm.`STORAGE_ID` IS NOT NULL 
      AND wm.PUT_QUANTITY <>0 
      AND wm.INSERTED_TIMESTAMP > NOW() - INTERVAL 10 DAY
    LIMIT 500;
    
   START TRANSACTION;
    
    
    INSERT IGNORE INTO `wcs_to_wms_payload` (`PAYLOAD_ID`,`API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`, headers, '322', 'cronJob', `json_output`
    FROM TempPayloads;
    
    
    UPDATE `put_wave_order_master` AS C
    INNER JOIN TempPayloads AS T ON C.`PUT_ORDER_ID` = T.`id`
    SET C.`BIN_TRANSFER_PAYLOAD_ID` = T.`payload_id`;
    
    
     UPDATE `put_wave_order_master_archive` AS C
    INNER JOIN TempPayloads AS T ON C.`PUT_ORDER_ID` = T.`id`
    SET C.`BIN_TRANSFER_PAYLOAD_ID` = T.`payload_id` WHERE C.INSERTED_TIMESTAMP> NOW() - INTERVAL 10 DAY ;
    
    COMMIT;
    
    
    
    
     
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    SELECT *
    FROM `wcs_to_wms_payload` wcs
    WHERE wcs.`API_ID` = '322' 
      AND wcs.`IS_PROCESSED` <> 1
      AND (wcs.http_status IS NULL OR wcs.http_status NOT IN (400, 422))
       AND (
		wcs.`IS_PROCESSED` <> -2
		OR (
		     wcs.`IS_PROCESSED` = -2
		     AND wcs.`PROCESSED_TIMESTAMP` < DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 600 SECOND)
		   )
	      )
	  
	  AND (
		wcs.`NO_OF_ATTEMPTS` = 0
		OR (
		     wcs.`NO_OF_ATTEMPTS` < @InfiniteRetryAttemtps
		     AND wcs.`PROCESSED_TIMESTAMP` < DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 1000 SECOND)
		   )
	      )
	LIMIT 10; 
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_PUT_STORAGE_REQUEST_COMPLETED_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_PUT_STORAGE_REQUEST_COMPLETED_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_PUT_STORAGE_REQUEST_COMPLETED_STATUS`()
BEGIN
 
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    SELECT KEY_VALUE INTO @InfiniteRetryAttemtps FROM `master_config` WHERE KEY_NAME='INTEGRATION_INFINITE_RETRY_TIMER';
    SELECT KEY_VALUE INTO @IntegrationTimeCounter FROM `master_config` WHERE KEY_NAME='INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    
    
    CREATE TEMPORARY TABLE TempPayloads (
        `storage_request_id` INT,
        `payload_id` CHAR(36),
        `headers` JSON,
        `json_output` JSON
    );
    
    
    INSERT INTO TempPayloads (storage_request_id, `payload_id`,headers, `json_output`)  
    SELECT 
        wm.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`,
        UUID(),
        JSON_OBJECT(
		@glnHeader,wm.`GLN`),
        JSON_OBJECT(
            'Gln', wm.`GLN`,
            'StorageRequestId', wm.`STORAGE_REQUEST_ID`,
            'Status', 'COMPLETED',
            'Remarks', '',
            'EventTimestamp', wm.`PALLET_SCANNED_TIMESTAMP`
        )
    FROM `wms_to_wcs_storage_request_pallet_data` wm
		WHERE wm.`PALLET_COMPLETION`=1
		  AND wm.`PALLET_COMPLETION_PAYLOAD_ID` IS NULL
		  AND NOT EXISTS (
		      SELECT 1
		      FROM  `wms_to_wcs_storage_request_data` l
		      WHERE l.`STORAGE_REQUEST_ID` = wm.`STORAGE_REQUEST_ID`
			AND l.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL
		  )
		  AND NOT EXISTS (
		      SELECT 1
		      FROM   `put_wave_order_master` l3
		      LEFT JOIN `wcs_to_wms_payload` wwp 
		      ON l3.BIN_TRANSFER_PAYLOAD_ID=wwp.PAYLOAD_ID
		      
		      WHERE l3.`STORAGE_REQUEST_ID` = wm.`STORAGE_REQUEST_ID`
		      
		      AND wwp.IS_PROCESSED <>1
			
		  )
		   AND NOT EXISTS (
		      SELECT 1
		      FROM   `put_wave_order_master_archive` l3
		      LEFT JOIN `wcs_to_wms_payload` wwp 
		      ON l3.BIN_TRANSFER_PAYLOAD_ID=wwp.PAYLOAD_ID
		      
		      WHERE l3.`STORAGE_REQUEST_ID` = wm.`STORAGE_REQUEST_ID`
		      
		      AND wwp.IS_PROCESSED <>1
			
		  )
		  AND NOT EXISTS (
		      SELECT 1
		      FROM wms_to_wcs_storage_request_data l2
		      JOIN wcs_to_wms_payload p ON l2.STOCK_ADJUSTMENT_PAYLOAD_ID = p.PAYLOAD_ID
		      WHERE l2.`STORAGE_REQUEST_ID` = wm.`STORAGE_REQUEST_ID`
			AND p.IS_PROCESSED <> 1
		  )
		LIMIT 100;
        
        
        
    
    INSERT IGNORE INTO `wcs_to_wms_payload` (`PAYLOAD_ID`,`API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`, headers, '321', 'cronJob', `json_output`
    FROM TempPayloads;
    
    
    UPDATE `wms_to_wcs_storage_request_pallet_data` AS C
    INNER JOIN TempPayloads AS T ON C.`WMS_STORAGE_REQUEST_PALLET_DATA_ID` = T.`storage_request_id`
    SET C.`PALLET_COMPLETION_PAYLOAD_ID` = T.`payload_id`;
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
  
	SELECT *
	FROM `wcs_to_wms_payload` wcs
	WHERE wcs.`API_ID` = '321'
	  AND wcs.`IS_PROCESSED` <> 1
	  AND (wcs.http_status IS NULL OR wcs.http_status NOT IN (400))
	  AND (
		wcs.`IS_PROCESSED` <> -2
		OR (
		     wcs.`IS_PROCESSED` = -2
		     AND wcs.`PROCESSED_TIMESTAMP` < DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 6000 SECOND)
		   )
	      )
	
		  AND (
			wcs.`NO_OF_ATTEMPTS` = 0
			OR (
			     wcs.`NO_OF_ATTEMPTS` < @InfiniteRetryAttemtps
			     AND wcs.`PROCESSED_TIMESTAMP` < DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 1000 SECOND)
			   )
		      )
		LIMIT 500;
   
   
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_PUT_STORAGE_REQUEST_SCANNED_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_PUT_STORAGE_REQUEST_SCANNED_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_PUT_STORAGE_REQUEST_SCANNED_STATUS`()
BEGIN
    
       
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    select KEY_VALUE into @IntegrationTimeCounter from `master_config` where KEY_NAME='INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    
    CREATE TEMPORARY TABLE TempPayloads (
        `id` INT,
        `payload_id` CHAR(36),
        `headers` JSON,
        `json_output` JSON
    );
    
    
    INSERT INTO TempPayloads (id, `payload_id`,headers, `json_output`)  
    SELECT 
        wm.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`,
        UUID(),
        JSON_OBJECT(
		@glnHeader,wm.`GLN`),
        JSON_OBJECT(
            'Gln', wm.`GLN`,
            'StorageRequestId', wm.`STORAGE_REQUEST_ID`,
            'Status', 'SCANNED',
            'Remarks', '',
            'EventTimestamp', wm.`PALLET_SCANNED_TIMESTAMP`
        )
    FROM `wms_to_wcs_storage_request_pallet_data` wm
   
    WHERE wm.`PALLET_SCANNED` = 1
        AND wm.`PALLET_SCANNED_PAYLOAD_ID` IS NULL;
        
        
        
    
    INSERT IGNORE INTO `wcs_to_wms_payload` (`PAYLOAD_ID`,`API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`, headers, '321', 'cronJob', `json_output`
    FROM TempPayloads;
    
    
    UPDATE `wms_to_wcs_storage_request_pallet_data` AS C
    INNER JOIN TempPayloads AS T ON C.`WMS_STORAGE_REQUEST_PALLET_DATA_ID` = T.`id`
    SET C.PALLET_SCANNED_PAYLOAD_ID = T.`payload_id`;
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    
    SELECT *
    FROM `wcs_to_wms_payload` wcs
    WHERE wcs.`API_ID` = '-1' 
      AND wcs.`IS_PROCESSED` <> 1
      AND (
          wcs.`NO_OF_ATTEMPTS` = 0 
          OR (
              wcs.`NO_OF_ATTEMPTS` < 5
              AND wcs.`PROCESSED_TIMESTAMP` < DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL @IntegrationTimeCounter SECOND)
          )
      )
    LIMIT 500;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_PUT_STORAGE_REQUEST_STOCK_ADJUSTMENT` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_PUT_STORAGE_REQUEST_STOCK_ADJUSTMENT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_PUT_STORAGE_REQUEST_STOCK_ADJUSTMENT`()
BEGIN
    
    DECLARE TimerCounter INT DEFAULT 1000;    
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    
    CREATE TEMPORARY TABLE TempPayloads (
        `STORAGE_ID` VARCHAR(36),
        `payload_id` CHAR(36),
        `json_output` JSON
    );
    
    
    INSERT INTO TempPayloads (`STORAGE_ID`, `payload_id`, `json_output`)  
    SELECT 
        wm.`STORAGE_ID`,
        UUID(),
        JSON_OBJECT(
            'Gln', 'FARUKHNAGAR',
            'Process', 'PUT',
            'StorageId', wm.`STORAGE_ID`,
            'causeList', JSON_MERGE_PRESERVE(
                
                (SELECT IFNULL(
                    JSON_ARRAYAGG(
                        JSON_OBJECT(
                            'BinId', wm.`BIN_ID`,
                            'BinSegment', wm.`BIN_SEGMENT_NO`,
                            'Quantity', spwr.`SHORT_PUT_QUANTITY`,
                            'Reason', spwr.`REASON`
                        )
                    ), JSON_ARRAY()  
                )
                FROM `short_put_wave_reason` spwr 
                WHERE spwr.`PUT_ORDER_ID` = wm.`PUT_ORDER_ID`),
                
                (SELECT IF(pwwd.`LEFT_OVER` > 0, 
                    JSON_ARRAY(
                        JSON_OBJECT(
                            'BinId', '',
                            'BinSegment', '', 
                            'Quantity', pwwd.`LEFT_OVER`, 
                            'Reason', 'NO_SPACE_IN_INVENTORY'
                        )
                    ), 
                    JSON_ARRAY()
                ))
            ),
            'UserId', 'SYSTEM',  
            'EventTimestamp', wm.`INSERTED_TIMESTAMP`
        )
    FROM `put_wave_order_master` wm 
    INNER JOIN `put_wave_wms_data` AS pwwd ON pwwd.`STORAGE_ID` = wm.`STORAGE_ID`
    WHERE pwwd.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL;
    
    INSERT INTO `wcs_to_wms_payload` (`PAYLOAD_ID`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`, '26', 'cronJob', `json_output`
    FROM TempPayloads;
    
    UPDATE `put_wave_wms_data` AS C
    INNER JOIN TempPayloads AS T ON C.`STORAGE_ID` = T.`STORAGE_ID`
    SET C.`STOCK_ADJUSTMENT_PAYLOAD_ID` = T.`payload_id`;
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    SELECT wcs.*
    FROM `wcs_to_wms_payload` AS wcs
    INNER JOIN `put_wave_wms_data` AS B ON wcs.`PAYLOAD_ID` = B.`STOCK_ADJUSTMENT_PAYLOAD_ID` 
    WHERE wcs.`IS_PROCESSED` <> 1  
    AND (wcs.`NO_OF_ATTEMPTS` = 0 OR 
         (wcs.`NO_OF_ATTEMPTS` < 5 
          AND (wcs.`PROCESSED_TIMESTAMP` + INTERVAL (POWER(2, wcs.`NO_OF_ATTEMPTS`) * TimerCounter) SECOND) < CURRENT_TIMESTAMP
         ));
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_PUT_STORAGE_REQUEST_SUSPENDED_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_PUT_STORAGE_REQUEST_SUSPENDED_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_PUT_STORAGE_REQUEST_SUSPENDED_STATUS`()
BEGIN
    
       
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    select KEY_VALUE into @IntegrationTimeCounter from `master_config` where KEY_NAME='INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    
    CREATE TEMPORARY TABLE TempPayloads (
        `id` INT,
        `payload_id` CHAR(36),
        `headers` JSON,
        `json_output` JSON
    );
    
    
    INSERT INTO TempPayloads (id, `payload_id`,headers, `json_output`)  
    SELECT 
        wm.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`,
        UUID(),
        JSON_OBJECT(
		@glnHeader,wm.`GLN`),
        JSON_OBJECT(
            'Gln', wm.`GLN`,
            'StorageRequestId', wm.`STORAGE_REQUEST_ID`,
            'Status', 'SUSPENDED',
            'Remarks', '',
            'EventTimestamp', wm.`PALLET_SCANNED_TIMESTAMP`
        )
    FROM `wms_to_wcs_storage_request_pallet_data` wm
   
    WHERE 
         wm.`STORAGE_REQUEST_STATUS` = 'PALLET_SUSPENDED' AND`PALLET_COMPLETION_PAYLOAD_ID` is NULL ;
        
        
        
    
    INSERT IGNORE INTO `wcs_to_wms_payload` (`PAYLOAD_ID`,`API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`, headers, '14', 'cronJob', `json_output`
    FROM TempPayloads;
    
    
    UPDATE `wms_to_wcs_storage_request_pallet_data` AS C
    INNER JOIN TempPayloads AS T ON C.`WMS_STORAGE_REQUEST_PALLET_DATA_ID` = T.`id`
    SET C.`PALLET_COMPLETION_PAYLOAD_ID` = T.`payload_id`;
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    
    SELECT *
    FROM `wcs_to_wms_payload` wcs
    WHERE wcs.`API_ID` = '-1' 
      AND wcs.`IS_PROCESSED` <> 1
      AND (
          wcs.`NO_OF_ATTEMPTS` = 0 
          OR (
              wcs.`NO_OF_ATTEMPTS` < 5
              AND wcs.`PROCESSED_TIMESTAMP` < DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL @IntegrationTimeCounter SECOND)
          )
      )
    LIMIT 500;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_STOCK_AUDIT_NEW_SKU` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_STOCK_AUDIT_NEW_SKU` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_STOCK_AUDIT_NEW_SKU`(
)
BEGIN
    
    SELECT KEY_VALUE INTO @IntegrationTimeCounter
    FROM master_config
    WHERE KEY_NAME = 'INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    SELECT KEY_VALUE INTO @IntegrationReattemptLimit
    FROM master_config
    WHERE KEY_NAME = 'INTEGRATION_REATTEMPT_LIMIT';
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    CREATE TEMPORARY TABLE TempPayloads (
        id VARCHAR(50),
        payload_id VARCHAR(36),
        headers JSON,
        json_output JSON,
        INDEX(payload_id)
    ) ;
    
    
    UPDATE stock_audit_bin_segments_details
    SET UPDATED_BATCH_PAYLOAD_ID = 'not_required', `PREV_BATCH_PAYLOAD_ID`= 'not_required'
    WHERE UPDATED_BATCH_PAYLOAD_ID IS NULL
      AND type = 'PICK'  limit 50 ;
      
      
    
    UPDATE stock_audit_bin_segments_details
    SET UPDATED_BATCH_PAYLOAD_ID = 'not_required'
    WHERE UPDATED_BATCH_PAYLOAD_ID IS NULL
      AND ( UPDATED_QUANTITY = 0 or `UPDATED_SKU_ID` = 'no-sku')  LIMIT 500;
      
     
      
      
    
    INSERT INTO TempPayloads (id, payload_id, headers, json_output)
    SELECT
        sad.ID,
        UUID(),
        JSON_OBJECT(@glnHeader, sbm.`GLN`),
        JSON_OBJECT(
            'Gln', sbm.GLN,
            'AuditRequestId', sad.WAVE_ID,
            'AuditProcess', sad.TYPE,
            'AuditItem', JSON_OBJECT(
                'SkuId', sad.`UPDATED_SKU_ID`,
                'BatchId', sbm.CLIENT_BATCH_ID,
                'AdjustmentType', 'INCREASE',
                'AdjustmentQuantity', ABS(sad.`UPDATED_QUANTITY`)
            ),
            'UserId', sad.AUDIT_BY,
            'Timestamp', sad.AUDIT_CLOSE_TIMESTAMP
        )
    FROM `stock_audit_bin_segments_details` sad
    INNER JOIN `sku_batch_master` sbm ON sbm.`BATCH_ID` = sad.`UPDATED_BATCH_ID`
    WHERE sad.UPDATED_BATCH_PAYLOAD_ID IS NULL
      AND sad.UPDATED_QUANTITY <> 0
      AND sad.UPDATED_BATCH_ID <> sad.`PREV_BATCH_ID` LIMIT 500;
    
    UPDATE stock_audit_bin_segments_details AS d
    INNER JOIN TempPayloads AS t ON d.ID = t.id
    SET d.UPDATED_BATCH_PAYLOAD_ID = t.payload_id;
    
    INSERT IGNORE INTO wcs_to_wms_payload (PAYLOAD_ID, API_HEADERS, API_ID, API_SOURCE, JSON_REQUEST)
    SELECT payload_id, headers, '330', 'cronJob', json_output
    FROM TempPayloads;
   
    
    SELECT *
    FROM wcs_to_wms_payload wcs
    WHERE wcs.API_ID = '330'
      AND wcs.IS_PROCESSED <> 1
      AND (
          wcs.NO_OF_ATTEMPTS = 0
          OR (
              wcs.NO_OF_ATTEMPTS < CAST(@IntegrationReattemptLimit AS UNSIGNED)
              AND (wcs.PROCESSED_TIMESTAMP IS NULL
                   OR wcs.PROCESSED_TIMESTAMP < DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL @IntegrationTimeCounter SECOND))
          )
      )
    LIMIT 500;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_STOCK_AUDIT_OLD_SKU` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_STOCK_AUDIT_OLD_SKU` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_STOCK_AUDIT_OLD_SKU`(
)
BEGIN
    
    SELECT KEY_VALUE INTO @IntegrationTimeCounter
    FROM master_config
    WHERE KEY_NAME = 'INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    SELECT KEY_VALUE INTO @IntegrationReattemptLimit
    FROM master_config
    WHERE KEY_NAME = 'INTEGRATION_REATTEMPT_LIMIT';
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    CREATE TEMPORARY TABLE TempPayloads (
        id VARCHAR(50),
        payload_id VARCHAR(36),
        headers JSON,
        json_output JSON,
        INDEX(payload_id)
    ) ;
    
    
    
    UPDATE stock_audit_bin_segments_details
    SET UPDATED_BATCH_PAYLOAD_ID = 'not_required', `PREV_BATCH_PAYLOAD_ID`= 'not_required'
    WHERE PREV_BATCH_PAYLOAD_ID IS NULL
      AND TYPE = 'PICK'  LIMIT 50 ;
      
    UPDATE stock_audit_bin_segments_details
    SET PREV_BATCH_PAYLOAD_ID = 'not_required'
    WHERE PREV_BATCH_PAYLOAD_ID IS NULL
      AND ( `PREV_QUANTITY` = 0  OR `PREV_SKU_ID` = 'no-sku') limit 500;
    
    INSERT INTO TempPayloads (id, payload_id, headers, json_output)
    SELECT 
        sad.ID,
        UUID(),
        JSON_OBJECT(@glnHeader, sbm.`GLN`),
        JSON_OBJECT(
            'Gln', sbm.`GLN`,
            'AuditRequestId', sad.WAVE_ID,
            'AuditProcess',sad.TYPE,
            'AuditItem', JSON_OBJECT(
                'SkuId', sad.`PREV_SKU_ID`,
                'BatchId', sbm.CLIENT_BATCH_ID,
                'AdjustmentType', 'DECREASE',
                'AdjustmentQuantity', sad.`PREV_QUANTITY`
            ),
            'UserId', sad.AUDIT_BY,
            'Timestamp', sad.AUDIT_CLOSE_TIMESTAMP
        )
    FROM `stock_audit_bin_segments_details` sad
    INNER JOIN `sku_batch_master` sbm ON sbm.`BATCH_ID` = sad.`PREV_BATCH_ID`
    WHERE sad.PREV_BATCH_PAYLOAD_ID IS NULL
      AND sad.PREV_QUANTITY <> 0
      AND sad.UPDATED_BATCH_ID <> sad.`PREV_BATCH_ID`;
    
    UPDATE stock_audit_bin_segments_details AS d
    INNER JOIN TempPayloads AS t ON d.ID = t.id
    SET d.PREV_BATCH_PAYLOAD_ID = t.payload_id;
    
    INSERT IGNORE INTO wcs_to_wms_payload (PAYLOAD_ID, API_HEADERS, API_ID, API_SOURCE, JSON_REQUEST)
    SELECT payload_id, headers, '330', 'cronJob', json_output
    FROM TempPayloads;
    SELECT *
    FROM wcs_to_wms_payload wcs
    WHERE wcs.API_ID = '330'
      AND wcs.IS_PROCESSED <> 1
      AND (
          wcs.NO_OF_ATTEMPTS = 0
          OR (
              wcs.NO_OF_ATTEMPTS < CAST(@IntegrationReattemptLimit AS UNSIGNED)
              AND (wcs.PROCESSED_TIMESTAMP IS NULL
                   OR wcs.PROCESSED_TIMESTAMP < DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL @IntegrationTimeCounter SECOND))
          )
      )
    LIMIT 500;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_STOCK_AUDIT_SAME_SKU` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_STOCK_AUDIT_SAME_SKU` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_STOCK_AUDIT_SAME_SKU`(
)
BEGIN
    
    SELECT KEY_VALUE INTO @IntegrationTimeCounter
    FROM master_config
    WHERE KEY_NAME = 'INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    SELECT KEY_VALUE INTO @IntegrationReattemptLimit
    FROM master_config
    WHERE KEY_NAME = 'INTEGRATION_REATTEMPT_LIMIT';
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    CREATE TEMPORARY TABLE TempPayloads (
        id VARCHAR(50),
        payload_id VARCHAR(36) ,
        headers JSON,
        json_output JSON,
        INDEX(payload_id)
    ) ;
    
    UPDATE stock_audit_bin_segments_details
    SET UPDATED_BATCH_PAYLOAD_ID = 'not_required', `PREV_BATCH_PAYLOAD_ID`= 'not_required'
    WHERE PREV_BATCH_PAYLOAD_ID IS NULL
      AND TYPE = 'PICK'  LIMIT 50 ;
      
     UPDATE stock_audit_bin_segments_details
    SET UPDATED_BATCH_PAYLOAD_ID = 'not_required',
    `PREV_BATCH_PAYLOAD_ID` = 'not_required'
    WHERE UPDATED_BATCH_PAYLOAD_ID IS NULL
     AND UPDATED_BATCH_ID = `PREV_BATCH_ID`
      AND  `PREV_SKU_ID` = 'no-sku'  LIMIT 500;
      
    UPDATE stock_audit_bin_segments_details
    SET UPDATED_BATCH_PAYLOAD_ID = 'not_required',
    `PREV_BATCH_PAYLOAD_ID` = 'not_required'
    WHERE UPDATED_BATCH_PAYLOAD_ID IS NULL
     AND UPDATED_BATCH_ID = `PREV_BATCH_ID`
      AND  (`PREV_QUANTITY` - UPDATED_QUANTITY) = 0 limit 500;
      
      
    INSERT INTO TempPayloads (id, payload_id, headers, json_output)
    SELECT
        sad.ID,
        UUID(),
        JSON_OBJECT(@glnHeader, sbm.`GLN`),
        JSON_OBJECT(
            'Gln', sbm.GLN,
            'AuditRequestId', sad.WAVE_ID,
            'AuditProcess', sad.TYPE,
            'AuditItem', JSON_OBJECT(
                'SkuId', sad.UPDATED_SKU_ID,
                'BatchId', sbm.CLIENT_BATCH_ID,
                'AdjustmentType',
                    CASE
                        WHEN (sad.`UPDATED_QUANTITY` - sad.`PREV_QUANTITY`) > 0 THEN 'INCREASE'
                        WHEN (sad.`UPDATED_QUANTITY` - sad.`PREV_QUANTITY`) < 0 THEN 'DECREASE'
                        ELSE 'NO_CHANGE'
                    END,
                'AdjustmentQuantity', ABS(sad.PREV_QUANTITY - sad.UPDATED_QUANTITY)
            ),
            'UserId', sad.AUDIT_BY,
            'Timestamp', sad.AUDIT_CLOSE_TIMESTAMP
        )
    FROM `stock_audit_bin_segments_details` sad
     INNER JOIN `sku_batch_master` sbm ON sbm.`BATCH_ID` = sad.`UPDATED_BATCH_ID`
    WHERE sad.UPDATED_BATCH_ID = sad.`PREV_BATCH_ID`
      AND (sad.`PREV_QUANTITY` - sad.UPDATED_QUANTITY) <> 0
      AND sad.UPDATED_BATCH_PAYLOAD_ID IS NULL LIMIT 500; 
    
    INSERT IGNORE INTO wcs_to_wms_payload (PAYLOAD_ID, API_HEADERS, API_ID, API_SOURCE, JSON_REQUEST)
    SELECT payload_id, headers, '330', 'cronJob', json_output
    FROM TempPayloads;
    
    UPDATE stock_audit_bin_segments_details AS d
    INNER JOIN TempPayloads AS t ON d.ID = t.id
    SET d.UPDATED_BATCH_PAYLOAD_ID = t.payload_id ,
    d.PREV_BATCH_PAYLOAD_ID = t.payload_id ;
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    SELECT *
    FROM wcs_to_wms_payload wcs
    WHERE wcs.API_ID = '330'
      AND wcs.IS_PROCESSED <> 1
      AND (
          wcs.NO_OF_ATTEMPTS = 0
          OR (
              wcs.NO_OF_ATTEMPTS < CAST(@IntegrationReattemptLimit AS UNSIGNED)
              AND (wcs.PROCESSED_TIMESTAMP IS NULL
                   OR wcs.PROCESSED_TIMESTAMP < DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL @IntegrationTimeCounter SECOND))
          )
      )
    LIMIT 500;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_ARTICLE_INFORMATION_BATCH_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_ARTICLE_INFORMATION_BATCH_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_ARTICLE_INFORMATION_BATCH_INSERT`(IN Parameters JSON)
BEGIN
    
    DROP TEMPORARY TABLE IF EXISTS _tmpEandata;
    DROP TEMPORARY TABLE IF EXISTS _tmpEandata1;
    CREATE TEMPORARY TABLE _tmpEandata
    (
        PAYLOAD_ID VARCHAR(36),
        Gln VARCHAR(64),
        Width DECIMAL(10,2),
        Height DECIMAL(10,2),
        LENGTH DECIMAL(10,2),
        Weight DECIMAL(10,2),
        Category VARCHAR(30),
        ImageUrl VARCHAR(1000),
        Velocity INT,
        ArticleId VARCHAR(255),
        ArticleName VARCHAR(300),
        MaxBinStorage INT,
        MinBinStorage INT,
        MinSegmentSize INT,
        ArticleDescription VARCHAR(4000),
        MaxQuantityStorage INT,
        MaxQuantityPerSegment INT,
        Ean VARCHAR(255),
        INDEX(PAYLOAD_ID),
        INDEX(Category),
        INDEX(ArticleId),
        INDEX(Ean)
    ) ENGINE=MEMORY;
    
    CREATE TEMPORARY TABLE _tmpEandata1
    (
        PAYLOAD_ID VARCHAR(36),
        Gln VARCHAR(64),
        Width DECIMAL(10,2),
        Height DECIMAL(10,2),
        LENGTH DECIMAL(10,2),
        Weight DECIMAL(10,2),
        Category VARCHAR(30),
        ImageUrl VARCHAR(1000),
        Velocity INT,
        ArticleId VARCHAR(255),
        ArticleName VARCHAR(300),
        MaxBinStorage INT,
        MinBinStorage INT,
        MinSegmentSize INT,
        ArticleDescription VARCHAR(4000),
        MaxQuantityStorage INT,
        MaxQuantityPerSegment INT,
        Ean VARCHAR(255),
        INDEX(PAYLOAD_ID),
        INDEX(Category),
        INDEX(ArticleId),
        INDEX(Ean)
    ) ENGINE=MEMORY;
    
    INSERT INTO _tmpEandata (
        PAYLOAD_ID, Gln, Width, Height, LENGTH, Weight, Category, ImageUrl, Velocity, ArticleId,
        ArticleName, MaxBinStorage, MinBinStorage, MinSegmentSize, ArticleDescription,
        MaxQuantityStorage, MaxQuantityPerSegment, Ean
    )
    SELECT
        jt.PAYLOAD_ID, jt.Gln, jt.Width, jt.Height, jt.LENGTH, jt.Weight, jt.Category,
        jt.ImageUrl, jt.Velocity, jt.ArticleId, jt.ArticleName, jt.MaxBinStorage,
        jt.MinBinStorage, IFNULL(jt.MinSegmentSize, 1), jt.ArticleDescription,
        jt.MaxQuantityStorage, IFNULL(jt.MaxQuantityPerSegment, 1), je.Ean
    FROM JSON_TABLE(
        Parameters,
        "$[*]"
        COLUMNS (
            PAYLOAD_ID VARCHAR(64) PATH '$.PAYLOAD_ID',
            Gln VARCHAR(64) PATH "$.DATA.Gln",
            Width DECIMAL(10,2) PATH "$.DATA.Width",
            Height DECIMAL(10,2) PATH "$.DATA.Height",
            LENGTH DECIMAL(10,2) PATH "$.DATA.Length",
            Weight DECIMAL(10,2) PATH "$.DATA.Weight",
            Category VARCHAR(30) PATH '$.DATA.Category',
            ImageUrl VARCHAR(300) PATH '$.DATA.ImageUrl',
            Velocity INT PATH '$.DATA.Velocity',
            ArticleId VARCHAR(64) PATH '$.DATA.ArticleId',
            ArticleName VARCHAR(300) PATH '$.DATA.ArticleName',
            MaxBinStorage INT PATH '$.DATA.MaxBinStorage',
            MinBinStorage INT PATH '$.DATA.MinBinStorage',
            MinSegmentSize INT PATH '$.DATA.MinSegmentSize',
            ArticleDescription VARCHAR(1000) PATH '$.DATA.ArticleDescription',
            MaxQuantityStorage INT PATH '$.DATA.MaxQuantityStorage',
            MaxQuantityPerSegment INT PATH '$.DATA.MaxQuantityPerSegment',
            EanList JSON PATH '$.DATA.EanList'
        )
    ) AS jt,
    JSON_TABLE(jt.EanList, '$[*]' COLUMNS (
        Ean VARCHAR(255) PATH '$'
    )) je;
   insert into _tmpEandata1
   select * from _tmpEandata;
    
    INSERT INTO `category_master` (`CATEGORY_NAME`)
    SELECT DISTINCT jt.Category
    FROM _tmpEandata jt
    LEFT JOIN category_master c ON c.`CATEGORY_NAME` = jt.Category
    WHERE c.`CATEGORY_ID` IS NULL;
    
    UPDATE sku_master sm
    INNER JOIN _tmpEandata p ON sm.SKU_ID = p.ArticleId
    INNER JOIN category_master c ON c.`CATEGORY_NAME` = p.Category
    SET
        sm.SKU_NAME = IFNULL(p.ArticleName, sm.SKU_NAME),
        sm.VELOCITY = IFNULL(p.Velocity, sm.VELOCITY),
        sm.CATEGORY = IFNULL(c.CATEGORY_ID, sm.CATEGORY),
        sm.MIN_SEGMENT_SIZE = IFNULL(p.MinSegmentSize, sm.MIN_SEGMENT_SIZE),
        sm.MAX_QUANTITY_PER_SEGMENT = IFNULL(p.MaxQuantityPerSegment, sm.MAX_QUANTITY_PER_SEGMENT),
        sm.LENGTH = IFNULL(p.LENGTH, sm.LENGTH),
        sm.WIDTH = IFNULL(p.Width, sm.WIDTH),
        sm.HEIGHT = IFNULL(p.Height, sm.HEIGHT),
        sm.WEIGHT_OF_EACH_SKU = IFNULL(p.Weight, sm.WEIGHT_OF_EACH_SKU),
        sm.IMAGE_URL = IFNULL(p.ImageUrl, sm.IMAGE_URL)
      where sm.SKU_ID in (select  ArticleId from _tmpEandata1);
    
    INSERT INTO `sku_master` (
        SKU_ID, SKU_NAME, VELOCITY, CATEGORY, MIN_SEGMENT_SIZE,
        MAX_QUANTITY_PER_SEGMENT, `LENGTH`, `WIDTH`, `HEIGHT`,
        WEIGHT_OF_EACH_SKU, IMAGE_URL,
        IS_ACTIVE, INSERTED_BY, UPDATED_BY
    )
    SELECT DISTINCT
        jt.ArticleId, jt.ArticleName, jt.Velocity, c.CATEGORY_ID, jt.MinSegmentSize,
        jt.MaxQuantityPerSegment, jt.LENGTH, jt.WIDTH, jt.HEIGHT, jt.Weight,
        COALESCE(jt.ImageUrl, 'no-image-found.png'), 1, 'BACKEND', 'BACKEND'
    FROM _tmpEandata jt
    INNER JOIN category_master c ON c.`CATEGORY_NAME` = jt.Category
    LEFT OUTER JOIN sku_master sm ON sm.SKU_ID = jt.ArticleId
    WHERE sm.SKU_ID IS NULL;
    
    INSERT IGNORE INTO sku_ean_mapping (SKU_ID, EAN_ID, GLN)
    SELECT jt.ArticleId, jt.Ean, jt.Gln FROM _tmpEandata jt;
    
    UPDATE wms_to_wcs_payload p
    INNER JOIN _tmpEandata tp ON tp.PAYLOAD_ID = p.PAYLOAD_ID
    SET p.`IS_PROCESSED` = 1, p.`PROCESSED_TIMESTAMP` = NOW()
    WHERE p.`API_ID` = 324;
    
    SELECT 1 AS SUCCESS, 'UPDATED_SUCCESSFULLY' AS MESSAGE;
    
    DROP TEMPORARY TABLE IF EXISTS _tmpEandata;
    DROP TEMPORARY TABLE IF EXISTS _tmpEandata1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_ARTICLE_INFORMATION_DELETE` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_ARTICLE_INFORMATION_DELETE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_ARTICLE_INFORMATION_DELETE`(
    IN p_Gln VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN p_ArticleId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    DECLARE articleExists INT;
    DECLARE associatedGln VARCHAR(50);
    DECLARE inventoryExists INT;
    
    SELECT COUNT(1), GLN 
    INTO articleExists, associatedGln 
    FROM sku_master 
    WHERE SKU_ID = p_ArticleId;
    
    IF articleExists = 0 THEN
        SELECT 0 AS SUCCESS, "ARTICLE NOT FOUND" AS MESSAGE;
   
    ELSE
        
        SELECT COUNT(1) INTO inventoryExists 
        FROM `live_inventory_master` 
        WHERE `ARTICLE_ID` = p_ArticleId;
        
        IF inventoryExists > 0 THEN
            SELECT 0 AS SUCCESS, "ARTICLE CANNOT BE DELETED - EXISTS IN LIVE INVENTORY" AS MESSAGE;
	ELSE
            
            DELETE FROM sku_master WHERE SKU_ID = p_ArticleId;
            
            
            SELECT 1 AS SUCCESS, "ARTICLE DELETED SUCCESSFULLY" AS MESSAGE;
        END IF;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_ARTICLE_INFORMATION_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_ARTICLE_INFORMATION_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_ARTICLE_INFORMATION_INSERT`(IN Parameters JSON)
BEGIN
    DECLARE v_errorMessage TEXT;
    DECLARE p_ArticleId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci;   
    Declare p_GLn varchar(64);
    DECLARE p_UpdatedBy VARCHAR(50);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION  
    BEGIN  
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;  
        ROLLBACK;  
        SELECT 0 AS SUCCESS, 'FAILED DUE TO ERROR' AS MESSAGE, v_errorMessage AS `RESULT`;  
    END;  
    START TRANSACTION;
	
    SET p_ArticleId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ArticleId'));
    set p_GLn = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Gln'));
    SET p_UpdatedBy = 'BACKEND';
    Drop temporary table if exists _tmpEanList;
    create temporary table _tmpEanList
    ( 
	SKU_ID  varchar(255),
	Eanid varchar(255),
    primary key (Eanid),
    index(SKU_ID)
    ) Engine=memory;
    
     DROP TEMPORARY TABLE IF EXISTS _tmpEanList1;
    CREATE TEMPORARY TABLE _tmpEanList1
    ( 
	SKU_ID  VARCHAR(255),
	Eanid VARCHAR(255),
    PRIMARY KEY (Eanid),
    INDEX(SKU_ID)
    ) ENGINE=MEMORY;
    
   INSERT INTO _tmpEanList (SKU_ID, Eanid)
	SELECT sem.SKU_ID,
	       jt.eanId
	FROM JSON_TABLE(
	       Parameters,
	       "$.EanList[*]"
	       COLUMNS (eanId VARCHAR(50) PATH "$")
	     ) AS jt
	STRAIGHT_JOIN  
	  sku_ean_mapping AS sem
	USE INDEX (EAN_ID)
	  ON sem.EAN_ID = jt.eanId;
	  
     INSERT INTO _tmpEanList1(SKU_ID,Eanid)
     SELECT  p_ArticleId,
            jt.eanId
       FROM   JSON_TABLE(
            Parameters,
            "$.EanList[*]" COLUMNS (
                eanId VARCHAR(50) PATH "$"
            )
        ) jt;
    
    INSERT INTO `category_master` (`CATEGORY_NAME`, `INSERTED_BY`, `UPDATED_BY`)
    
    SELECT distinct Category,'API_SERVICE', 'API_SERVICE'
	FROM JSON_TABLE(
	  Parameters,
	  "$"
	  COLUMNS (
	    Gln VARCHAR(50) PATH "$.Gln",
	    Width DECIMAL(10,2) PATH "$.Width",
	    Height DECIMAL(10,2) PATH "$.Height",
	    LENGTH DECIMAL(10,2) PATH "$.Length",
	    Weight DECIMAL(10,2) PATH "$.Weight",
	    Category VARCHAR(50) PATH "$.Category",
	    ImageUrl VARCHAR(255) PATH "$.ImageUrl",
	    Velocity INT PATH "$.Velocity",
	    ArticleId VARCHAR(50) PATH "$.ArticleId",
	    Perishable VARCHAR(50) PATH "$.Perishable",
	    ArticleName VARCHAR(255) PATH "$.ArticleName",
	    MaxBinStorage INT PATH "$.MaxBinStorage",
	    MinBinStorage INT PATH "$.MinBinStorage",
	    MinSegmentSize VARCHAR(50) PATH "$.MinSegmentSize",
	    ArticleDescription VARCHAR(255) PATH "$.ArticleDescription",
	    MaxQuantityStorage INT PATH "$.MaxQuantityStorage",
	    MaxQuantityPerSegment VARCHAR(50) PATH "$.MaxQuantityPerSegment"
	  )
	) AS jt
	Left outer join category_master C  on C.CATEGORY_NAME=jt.Category
	where C.CATEGORY_NAME is null limit 1;
    
    if not exists(select 1 from sku_master where SKU_ID=p_ArticleId) then
	    INSERT INTO `sku_master` (
		SKU_ID, SKU_NAME, VELOCITY, CATEGORY, MIN_SEGMENT_SIZE, 
		MAX_QUANTITY_PER_SEGMENT,  `LENGTH`, `WIDTH`, `HEIGHT`, 
		WEIGHT_OF_EACH_SKU, IMAGE_URL, 
		IS_ACTIVE, INSERTED_BY, UPDATED_BY
	    ) 
	    SELECT ArticleId,ArticleName,Velocity,C.CATEGORY_ID,ifnull(MinSegmentSize,1),
	    ifnull(MaxQuantityPerSegment,1),jt.LENGTH,jt.Width,jt.Height,jt.Weight,COALESCE(jt.ImageUrl, 'no-image-found.png'),
	    1, p_UpdatedBy, p_UpdatedBy
	FROM JSON_TABLE(
	  Parameters,
	  "$"
	  COLUMNS (
	    Gln VARCHAR(50) PATH "$.Gln",
	    Width DECIMAL(10,2) PATH "$.Width",
	    Height DECIMAL(10,2) PATH "$.Height",
	    LENGTH DECIMAL(10,2) PATH "$.Length",
	    Weight DECIMAL(10,2) PATH "$.Weight",
	    Category VARCHAR(50) PATH "$.Category",
	    ImageUrl VARCHAR(255) PATH "$.ImageUrl",
	    Velocity INT PATH "$.Velocity",
	    ArticleId VARCHAR(50) PATH "$.ArticleId",
	    Perishable VARCHAR(50) PATH "$.Perishable",
	    ArticleName VARCHAR(255) PATH "$.ArticleName",
	    MaxBinStorage INT PATH "$.MaxBinStorage",
	    MinBinStorage INT PATH "$.MinBinStorage",
	    MinSegmentSize VARCHAR(50) PATH "$.MinSegmentSize",
	    ArticleDescription VARCHAR(255) PATH "$.ArticleDescription",
	    MaxQuantityStorage INT PATH "$.MaxQuantityStorage",
	    MaxQuantityPerSegment VARCHAR(50) PATH "$.MaxQuantityPerSegment"
	  )
	) AS jt
	inner JOIN category_master C  ON C.CATEGORY_NAME=jt.Category limit 1;	   
    else
        update sku_master SM  inner Join (
	   select jt.*
	   FROM JSON_TABLE(
	  Parameters,
	  "$"
	  COLUMNS (
	    Gln VARCHAR(50) PATH "$.Gln",
	    Width DECIMAL(10,2) PATH "$.Width",
	    Height DECIMAL(10,2) PATH "$.Height",
	    LENGTH DECIMAL(10,2) PATH "$.Length",
	    Weight DECIMAL(10,2) PATH "$.Weight",
	    Category VARCHAR(50) PATH "$.Category",
	    ImageUrl VARCHAR(255) PATH "$.ImageUrl",
	    Velocity INT PATH "$.Velocity",
	    ArticleId VARCHAR(50) PATH "$.ArticleId",
	    Perishable VARCHAR(50) PATH "$.Perishable",
	    ArticleName VARCHAR(255) PATH "$.ArticleName",
	    MaxBinStorage INT PATH "$.MaxBinStorage",
	    MinBinStorage INT PATH "$.MinBinStorage",
	    MinSegmentSize VARCHAR(50) PATH "$.MinSegmentSize",
	    ArticleDescription VARCHAR(255) PATH "$.ArticleDescription",
	    MaxQuantityStorage INT PATH "$.MaxQuantityStorage",
	    MaxQuantityPerSegment VARCHAR(50) PATH "$.MaxQuantityPerSegment"
	  )
	) AS jt) P  on P.ArticleId=SM.SKU_ID
	INNER JOIN category_master C  ON C.CATEGORY_NAME=P.Category
	set SKU_NAME = IFNULL(P.ArticleName, SKU_NAME),
        SM.VELOCITY = IFNULL(P.Velocity, SM.VELOCITY),
        SM.CATEGORY = IFNULL(C.CATEGORY_ID, SM.CATEGORY),
        MIN_SEGMENT_SIZE = IFNULL(P.MinSegmentSize, MIN_SEGMENT_SIZE),
        MAX_QUANTITY_PER_SEGMENT = IFNULL(P.MaxQuantityPerSegment, MAX_QUANTITY_PER_SEGMENT),
        SM.LENGTH = IFNULL(P.LENGTH, SM.LENGTH),
        SM.WIDTH = IFNULL(P.Width, SM.WIDTH),
        SM.HEIGHT = IFNULL(P.Height, SM.HEIGHT),
        SM.WEIGHT_OF_EACH_SKU = IFNULL(p.Weight, WEIGHT_OF_EACH_SKU),
        SM.IMAGE_URL = IFNULL(P.ImageUrl, SM.IMAGE_URL),
	SM.UPDATED_BY = p_UpdatedBy
	where SM.SKU_ID=p_ArticleId ;
      end if;
    
    IF JSON_EXTRACT(Parameters, '$.EanList') IS NOT NULL THEN
        
       IF EXISTS (
	   select 1 from  _tmpEanList jt where SKU_ID!= p_ArticleId
        ) THEN
            SET v_errorMessage = 'One or more EANs already mapped to a different Article ID';
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = v_errorMessage;
        END IF;
       
        INSERT ignore INTO sku_ean_mapping (SKU_ID, EAN_ID, GLN)
        SELECT p_ArticleId, jt.eanId, p_GLn FROM _tmpEanList1 jt;           
    END IF;
    
    COMMIT;
    
    SELECT 1 AS SUCCESS, 'UPDATED_SUCCESSFULLY' AS MESSAGE;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_ARTICLE_INFORMATION_INSERT_V0` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_ARTICLE_INFORMATION_INSERT_V0` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_ARTICLE_INFORMATION_INSERT_V0`(IN Parameters JSON)
BEGIN
    DECLARE v_errorMessage TEXT;
    DECLARE p_ArticleId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_GLn VARCHAR(200);
    DECLARE p_ArticleName VARCHAR(200);
    DECLARE p_Velocity INT;
    DECLARE p_Category VARCHAR(100);
    DECLARE v_Category INT;
    DECLARE p_MinSegmentSize INT;
    DECLARE p_MaxQuantityPerSegment INT;
    DECLARE p_MinBinStorage INT;
    DECLARE p_MaxBinStorage INT;
    DECLARE p_MaxQuantityStorage INT;
    DECLARE p_Length DECIMAL(10,3);
    DECLARE p_Width DECIMAL(10,3);
    DECLARE p_Height DECIMAL(10,3);
    DECLARE p_Weight DECIMAL(10,3);
    DECLARE p_ImageUrl VARCHAR(1000);
    DECLARE p_UpdatedBy VARCHAR(50);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION  
    BEGIN  
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;  
        ROLLBACK;  
        SELECT 0 AS SUCCESS, 'FAILED DUE TO ERROR' AS MESSAGE, v_errorMessage AS `RESULT`;  
    END;
    
    SET p_ArticleId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ArticleId'));
    SET p_GLn = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Gln'));
    SET p_ArticleName = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ArticleName'));
    SET p_Velocity = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Velocity'));
    SET p_Category = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Category'));
    SET p_MinSegmentSize = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.MinSegmentSize'));
    SET p_MaxQuantityPerSegment = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.MaxQuantityPerSegment'));
    SET p_Length = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Length'));
    SET p_Width = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Width'));
    SET p_Height = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Height'));
    SET p_Weight = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Weight'));
    SET p_ImageUrl = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ImageUrl'));
    SET p_UpdatedBy = 'BACKEND';
    START TRANSACTION;
    
    INSERT IGNORE INTO `category_master` (`CATEGORY_NAME`, `INSERTED_BY`, `UPDATED_BY`)
    SELECT p_Category, 'API_SERVICE', 'API_SERVICE';
    
    SELECT `CATEGORY_ID` INTO v_Category FROM `category_master` WHERE `CATEGORY_NAME` = p_Category LIMIT 1;
    
    INSERT INTO `sku_master` (
        SKU_ID, SKU_NAME, VELOCITY, CATEGORY, MIN_SEGMENT_SIZE, 
        MAX_QUANTITY_PER_SEGMENT,  `LENGTH`, `WIDTH`, `HEIGHT`, 
        WEIGHT_OF_EACH_SKU, IMAGE_URL, 
        IS_ACTIVE, INSERTED_BY, UPDATED_BY
    ) 
    VALUES (
        p_ArticleId, p_ArticleName, p_Velocity, v_Category, p_MinSegmentSize, 
        p_MaxQuantityPerSegment, p_Length, p_Width, p_Height, 
        p_Weight, 
        COALESCE(p_ImageUrl, 'no-image-found.png'), 
        1, p_UpdatedBy, p_UpdatedBy
    )
    ON DUPLICATE KEY UPDATE 
        SKU_NAME = IFNULL(p_ArticleName, SKU_NAME),
        VELOCITY = IFNULL(p_Velocity, VELOCITY),
        CATEGORY = IFNULL(v_Category, CATEGORY),
        MIN_SEGMENT_SIZE = IFNULL(p_MinSegmentSize, MIN_SEGMENT_SIZE),
        MAX_QUANTITY_PER_SEGMENT = IFNULL(p_MaxQuantityPerSegment, MAX_QUANTITY_PER_SEGMENT),
        LENGTH = IFNULL(p_Length, LENGTH),
        WIDTH = IFNULL(p_Width, WIDTH),
        HEIGHT = IFNULL(p_Height, HEIGHT),
        WEIGHT_OF_EACH_SKU = IFNULL(p_Weight, WEIGHT_OF_EACH_SKU),
        IMAGE_URL = IFNULL(p_ImageUrl, IMAGE_URL),
        UPDATED_BY = p_UpdatedBy;
    
    IF JSON_EXTRACT(Parameters, '$.EanList') IS NOT NULL THEN
        
        IF EXISTS (
            SELECT 1
            FROM JSON_TABLE(
                Parameters,
                "$.EanList[*]" COLUMNS (
                    eanId VARCHAR(50) PATH "$"
                )
            ) jt
            JOIN sku_ean_mapping sem ON sem.EAN_ID = jt.eanId
            WHERE sem.SKU_ID != p_ArticleId
        ) THEN
            SET v_errorMessage = 'One or more EANs already mapped to a different Article ID';
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = v_errorMessage;
        END IF;
        
        INSERT IGNORE INTO sku_ean_mapping (SKU_ID, EAN_ID, GLN)
        SELECT 
            p_ArticleId,
            jt.eanId,
            p_GLn
        FROM JSON_TABLE(
            Parameters,
            "$.EanList[*]" COLUMNS (
                eanId VARCHAR(50) PATH "$"
            )
        ) jt;
    END IF;
    COMMIT;
    
    SELECT 1 AS SUCCESS, 'UPDATED_SUCCESSFULLY' AS MESSAGE;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_ARTICLE_INFORMATION_INSERT_V1` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_ARTICLE_INFORMATION_INSERT_V1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_ARTICLE_INFORMATION_INSERT_V1`(IN Parameters JSON)
BEGIN
    DECLARE v_errorMessage TEXT;
    DECLARE p_ArticleId VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci;   
    Declare p_GLn varchar(64);
    DECLARE p_UpdatedBy VARCHAR(50);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION  
    BEGIN  
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;  
        ROLLBACK;  
        SELECT 0 AS SUCCESS, 'FAILED DUE TO ERROR' AS MESSAGE, v_errorMessage AS `RESULT`;  
    END;  
    START TRANSACTION;
	
    SET p_ArticleId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ArticleId'));
    set p_GLn = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Gln'));
    SET p_UpdatedBy = 'BACKEND';
    Drop temporary table if exists _tmpEanList;
    create temporary table _tmpEanList
    ( 
	SKU_ID  varchar(255),
	Eanid varchar(255),
    primary key (Eanid),
    index(SKU_ID)
    ) Engine=memory;
    
     DROP TEMPORARY TABLE IF EXISTS _tmpEanList1;
    CREATE TEMPORARY TABLE _tmpEanList1
    ( 
	SKU_ID  VARCHAR(255),
	Eanid VARCHAR(255),
    PRIMARY KEY (Eanid),
    INDEX(SKU_ID)
    ) ENGINE=MEMORY;
    
    insert into _tmpEanList(SKU_ID,Eanid)
     SELECT 
            sem.SKU_ID,
            jt.eanId
       FROM  sku_ean_mapping sem 
       INNER JOIN JSON_TABLE(
            Parameters,
            "$.EanList[*]" COLUMNS (
                eanId VARCHAR(50) PATH "$"
            )
        ) jt
         ON sem.EAN_ID = jt.eanId;
         
     INSERT INTO _tmpEanList1(SKU_ID,Eanid)
     SELECT  p_ArticleId,
            jt.eanId
       FROM   JSON_TABLE(
            Parameters,
            "$.EanList[*]" COLUMNS (
                eanId VARCHAR(50) PATH "$"
            )
        ) jt;
    
    INSERT INTO `category_master` (`CATEGORY_NAME`, `INSERTED_BY`, `UPDATED_BY`)
    
    SELECT distinct Category,'API_SERVICE', 'API_SERVICE'
	FROM JSON_TABLE(
	  Parameters,
	  "$"
	  COLUMNS (
	    Gln VARCHAR(50) PATH "$.Gln",
	    Width DECIMAL(10,2) PATH "$.Width",
	    Height DECIMAL(10,2) PATH "$.Height",
	    LENGTH DECIMAL(10,2) PATH "$.Length",
	    Weight DECIMAL(10,2) PATH "$.Weight",
	    Category VARCHAR(50) PATH "$.Category",
	    ImageUrl VARCHAR(255) PATH "$.ImageUrl",
	    Velocity INT PATH "$.Velocity",
	    ArticleId VARCHAR(50) PATH "$.ArticleId",
	    Perishable VARCHAR(50) PATH "$.Perishable",
	    ArticleName VARCHAR(255) PATH "$.ArticleName",
	    MaxBinStorage INT PATH "$.MaxBinStorage",
	    MinBinStorage INT PATH "$.MinBinStorage",
	    MinSegmentSize VARCHAR(50) PATH "$.MinSegmentSize",
	    ArticleDescription VARCHAR(255) PATH "$.ArticleDescription",
	    MaxQuantityStorage INT PATH "$.MaxQuantityStorage",
	    MaxQuantityPerSegment VARCHAR(50) PATH "$.MaxQuantityPerSegment"
	  )
	) AS jt
	Left outer join category_master C  on C.CATEGORY_NAME=jt.Category
	where C.CATEGORY_NAME is null limit 1;
    
    if not exists(select 1 from sku_master where SKU_ID=p_ArticleId) then
	    INSERT INTO `sku_master` (
		SKU_ID, SKU_NAME, VELOCITY, CATEGORY, MIN_SEGMENT_SIZE, 
		MAX_QUANTITY_PER_SEGMENT,  `LENGTH`, `WIDTH`, `HEIGHT`, 
		WEIGHT_OF_EACH_SKU, IMAGE_URL, 
		IS_ACTIVE, INSERTED_BY, UPDATED_BY
	    ) 
	    SELECT ArticleId,ArticleName,Velocity,C.CATEGORY_ID,ifnull(MinSegmentSize,1),
	    ifnull(MaxQuantityPerSegment,1),jt.LENGTH,jt.Width,jt.Height,jt.Weight,COALESCE(jt.ImageUrl, 'no-image-found.png'),
	    1, p_UpdatedBy, p_UpdatedBy
	FROM JSON_TABLE(
	  Parameters,
	  "$"
	  COLUMNS (
	    Gln VARCHAR(50) PATH "$.Gln",
	    Width DECIMAL(10,2) PATH "$.Width",
	    Height DECIMAL(10,2) PATH "$.Height",
	    LENGTH DECIMAL(10,2) PATH "$.Length",
	    Weight DECIMAL(10,2) PATH "$.Weight",
	    Category VARCHAR(50) PATH "$.Category",
	    ImageUrl VARCHAR(255) PATH "$.ImageUrl",
	    Velocity INT PATH "$.Velocity",
	    ArticleId VARCHAR(50) PATH "$.ArticleId",
	    Perishable VARCHAR(50) PATH "$.Perishable",
	    ArticleName VARCHAR(255) PATH "$.ArticleName",
	    MaxBinStorage INT PATH "$.MaxBinStorage",
	    MinBinStorage INT PATH "$.MinBinStorage",
	    MinSegmentSize VARCHAR(50) PATH "$.MinSegmentSize",
	    ArticleDescription VARCHAR(255) PATH "$.ArticleDescription",
	    MaxQuantityStorage INT PATH "$.MaxQuantityStorage",
	    MaxQuantityPerSegment VARCHAR(50) PATH "$.MaxQuantityPerSegment"
	  )
	) AS jt
	inner JOIN category_master C  ON C.CATEGORY_NAME=jt.Category limit 1;	   
    else
        update sku_master SM  inner Join (
	   select jt.*
	   FROM JSON_TABLE(
	  Parameters,
	  "$"
	  COLUMNS (
	    Gln VARCHAR(50) PATH "$.Gln",
	    Width DECIMAL(10,2) PATH "$.Width",
	    Height DECIMAL(10,2) PATH "$.Height",
	    LENGTH DECIMAL(10,2) PATH "$.Length",
	    Weight DECIMAL(10,2) PATH "$.Weight",
	    Category VARCHAR(50) PATH "$.Category",
	    ImageUrl VARCHAR(255) PATH "$.ImageUrl",
	    Velocity INT PATH "$.Velocity",
	    ArticleId VARCHAR(50) PATH "$.ArticleId",
	    Perishable VARCHAR(50) PATH "$.Perishable",
	    ArticleName VARCHAR(255) PATH "$.ArticleName",
	    MaxBinStorage INT PATH "$.MaxBinStorage",
	    MinBinStorage INT PATH "$.MinBinStorage",
	    MinSegmentSize VARCHAR(50) PATH "$.MinSegmentSize",
	    ArticleDescription VARCHAR(255) PATH "$.ArticleDescription",
	    MaxQuantityStorage INT PATH "$.MaxQuantityStorage",
	    MaxQuantityPerSegment VARCHAR(50) PATH "$.MaxQuantityPerSegment"
	  )
	) AS jt) P  on P.ArticleId=SM.SKU_ID
	INNER JOIN category_master C  ON C.CATEGORY_NAME=P.Category
	set SKU_NAME = IFNULL(P.ArticleName, SKU_NAME),
        SM.VELOCITY = IFNULL(P.Velocity, SM.VELOCITY),
        SM.CATEGORY = IFNULL(C.CATEGORY_ID, SM.CATEGORY),
        MIN_SEGMENT_SIZE = IFNULL(P.MinSegmentSize, MIN_SEGMENT_SIZE),
        MAX_QUANTITY_PER_SEGMENT = IFNULL(P.MaxQuantityPerSegment, MAX_QUANTITY_PER_SEGMENT),
        SM.LENGTH = IFNULL(P.LENGTH, SM.LENGTH),
        SM.WIDTH = IFNULL(P.Width, SM.WIDTH),
        SM.HEIGHT = IFNULL(P.Height, SM.HEIGHT),
        SM.WEIGHT_OF_EACH_SKU = IFNULL(p.Weight, WEIGHT_OF_EACH_SKU),
        SM.IMAGE_URL = IFNULL(P.ImageUrl, SM.IMAGE_URL),
	SM.UPDATED_BY = p_UpdatedBy
	where SM.SKU_ID=p_ArticleId ;
      end if;
    
    IF JSON_EXTRACT(Parameters, '$.EanList') IS NOT NULL THEN
        
       IF EXISTS (
	   select 1 from  _tmpEanList jt where SKU_ID!= p_ArticleId
        ) THEN
            SET v_errorMessage = 'One or more EANs already mapped to a different Article ID';
            SIGNAL SQLSTATE '45000' 
            SET MESSAGE_TEXT = v_errorMessage;
        END IF;
       
        INSERT ignore INTO sku_ean_mapping (SKU_ID, EAN_ID, GLN)
        SELECT p_ArticleId, jt.eanId, p_GLn FROM _tmpEanList1 jt;           
    END IF;
    
    COMMIT;
    
    SELECT 1 AS SUCCESS, 'UPDATED_SUCCESSFULLY' AS MESSAGE;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_CACHING_SKU_EAN_COUNT` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_CACHING_SKU_EAN_COUNT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_CACHING_SKU_EAN_COUNT`()
BEGIN
    
    SELECT COUNT(DISTINCT SKU_ID) AS  RESULT,1 AS SUCCESS FROM `sku_ean_mapping` ;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_ERROR_LOG` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_ERROR_LOG` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_ERROR_LOG`(IN Parameters JSON)
BEGIN
	DECLARE soureceApplication VARCHAR(50);
	DECLARE `endpoint` VARCHAR(255);
	DECLARE classMethodName TEXT;
	DECLARE errorCodeText VARCHAR(50);
	DECLARE errorCode INT;
	DECLARE errorMessage TEXT;
	DECLARE innerErrorMessage TEXT;
	DECLARE errorStackTrace TEXT;
	DECLARE errorDescription TEXT;
	
	SET soureceApplication = Parameters ->> '$.sourceApplication';
	SET `endpoint` = Parameters ->> '$.endpoint';
	SET classMethodName = Parameters ->>'$.classMethodName';
	SET errorCodeText = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.errorCode'));
	SET errorMessage = Parameters ->>'$.errorMessage';
	SET innerErrorMessage = Parameters ->>'$.innerErrorMessage';
	SET errorStackTrace = Parameters ->>'$.errorStackTrace';
	SET errorDescription = Parameters ->> '$.errorDescription';
	
	 IF errorCodeText IS NULL OR errorCodeText = 'null' OR errorCodeText = '' THEN
        SET errorCode = NULL;
    ELSE
        SET errorCode = CAST(errorCodeText AS SIGNED);
    END IF;
    
	INSERT INTO `integration_error_logs`(SOURCE_APPLICATION, ENDPOINT, CLASS_METHOD_NAME, ERROR_CODE, ERROR_MESSAGE,
	`INNER_ERROR_MESSAGE`, ERROR_STACKTRACE, ERROR_DESCRIPTION) 
	VALUES (soureceApplication, `endpoint`, classMethodName, errorCode, errorMessage, 
	innerErrorMessage,errorStackTrace, errorDescription);
	
	END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_GET_API_DETAILS_BY_API_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_GET_API_DETAILS_BY_API_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_GET_API_DETAILS_BY_API_ID`(IN Parameters BIGINT)
BEGIN
	SELECT CONCAT(`API_DOMAIN`, `API_ENDPOINT`) AS ApiUrl, `API_ID`AS ApiId, `API_ENDPOINT` AS ApiEndpoint,
	 `API_HEADER` AS ApiHeader, `API_TOKEN` AS ApiToken,`API_TYPE` AS ApiType
	FROM api_master
	WHERE `API_ID` = Parameters; 
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_GET_CURRENT_INVENTORY_SYN_FLAG` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_GET_CURRENT_INVENTORY_SYN_FLAG` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_GET_CURRENT_INVENTORY_SYN_FLAG`()
BEGIN
	declare InvetorySyncCurrentState int default 0;
	select `KEY_VALUE` into InvetorySyncCurrentState from `master_config` where `KEY_NAME`='INTEGRATION_INVENTORY_SYNC_STATUS' ;
	select InvetorySyncCurrentState as SUCCESS ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_GET_CURRENT_IVENTORY_SYN_FLAG` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_GET_CURRENT_IVENTORY_SYN_FLAG` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_GET_CURRENT_IVENTORY_SYN_FLAG`()
BEGIN
	declare InvetorySyncCurrentState int default 0;
	select `KEY_VALUE` into InvetorySyncCurrentState from `master_config` where `KEY_NAME`='InvetorySyncCurrentState' ;
	select InvetorySyncCurrentState as SUCCESS ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_GET_ORDER_ID_DETAILS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_GET_ORDER_ID_DETAILS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_GET_ORDER_ID_DETAILS`(IN Parameters JSON)
BEGIN
       DECLARE lpnBarcode VARCHAR(100);
   DECLARE parentOrderId VARCHAR(100);
    DECLARE orderId VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE _gln VARCHAR(100);
    DECLARE clientOrderId VARCHAR(100);
     DECLARE clientOrdertype VARCHAR(100);
    DECLARE pickingType VARCHAR(100);
    DECLARE batchPicklistId VARCHAR(100);
    DECLARE destinationStoreCode VARCHAR(100);
    DECLARE orderCount INT DEFAULT 0;
    DECLARE deletedOrderCount VARCHAR(100);
    
    SET lpnBarcode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.LpnBarcode'));
    SET orderId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderId'));
    
    
	SELECT `PARENT_ORDER_ID`, `ORDER_TYPE`
	INTO parentOrderId, clientOrderType
	FROM `wms_to_wcs_order_request_data`
	WHERE `ORDER_ID` = orderId
	LIMIT 1;
    
    
    
    SELECT COUNT(1) INTO orderCount
    FROM `wms_to_wcs_order_level_pre_staged_data`
    WHERE `PARENT_ORDER_ID` = parentOrderId ;
    
    SELECT count(1) INTO deletedOrderCount
  FROM `wms_to_wcs_order_level_pre_staged_data`
    WHERE `PARENT_ORDER_ID` = parentOrderId  AND ORDER_REQUEST_STATUS = 'DELETED' LIMIT 1 ;
    
    IF orderCount = 0 THEN
        
        SELECT 
            0 AS SUCCESS, 
            'ORDER_NOT_FOUND' AS MESSAGE;
     ELSEIF  deletedOrderCount >0  THEN 
     SELECT 
            2 AS SUCCESS, 
            'INVALID_ORDER' AS MESSAGE;
    ELSE
        
        SELECT 
            GLN, 
            `PICKING_TYPE`, 
            `BATCH_PICKLIST_ID`, 
            `STORE_ID`,
            `CLIENT_ORDER_ID`
        INTO 
            _gln, 
            pickingType, 
            batchPicklistId, 
            destinationStoreCode,
            clientOrderId
        FROM `wms_to_wcs_order_level_pre_staged_data`
        WHERE `PARENT_ORDER_ID` = parentOrderId
        LIMIT 1;
        
      
        
        SELECT 
            1 AS SUCCESS,
            JSON_OBJECT(
                'Gln', _gln,
                'LpnBarcode', lpnBarcode,
                'OrderId', clientOrderId,
                'OrderCategoryType',`clientOrdertype`,
                'DestinationStoreCode', destinationStoreCode,
                'BatchPicklistId', batchPicklistId,
                'PickingType', pickingType
            ) AS `RESULT`,_gln AS HEADERS;
    END IF;
    
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_GET_SKU_EAN_DATA` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_GET_SKU_EAN_DATA` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_GET_SKU_EAN_DATA`(IN Parameters JSON)
BEGIN
    DECLARE batchListSize INT;
    DECLARE counterValue INT;
     DECLARE offsetValue INT;
     
    
    SET batchListSize = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.batchSize')) AS UNSIGNED);
    SET counterValue   = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.counter')) AS UNSIGNED);
    
   
    SET offsetValue = batchListSize * counterValue;
    
  
    
    SELECT 
        `SKU_ID` AS skuId,
        `EAN_ID` AS eanId
    FROM 
        `sku_ean_mapping`
    ORDER BY 
        `INSERTED_TIMESTAMP`
    LIMIT 
        batchListSize
    OFFSET 
        offsetValue;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_GET_SKU_EAN_REFRESH_DATA` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_GET_SKU_EAN_REFRESH_DATA` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_GET_SKU_EAN_REFRESH_DATA`(IN Parameters JSON)
BEGIN
    DECLARE lastFetchedTime DATETIME;
    DECLARE counterValue BIGINT;
    DECLARE startTime DATETIME;
    DECLARE endTime DATETIME;
    
    SET lastFetchedTime = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.LastFetchedTime'));
    SET counterValue  = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.timeCounter')) AS UNSIGNED);
    
   SET startTime = lastFetchedTime;  
   SET endTime = DATE_ADD(startTime, INTERVAL counterValue SECOND);
    
   
    
    SELECT 
        `SKU_ID` AS skuId,
        `EAN_ID` AS eanId
    FROM 
        `sku_ean_mapping`
    WHERE 
        `INSERTED_TIMESTAMP` BETWEEN startTime AND endTime;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_INVENTORY_SNAPSHOT` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_INVENTORY_SNAPSHOT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_INVENTORY_SNAPSHOT`(IN Parameters JSON)
proc: BEGIN
    
    DECLARE _gln VARCHAR(100);
    DECLARE v_errorMessage TEXT DEFAULT NULL;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;
        SELECT 0 AS SUCCESS,
               'FAILED' AS MESSAGE,
               JSON_OBJECT('error', v_errorMessage) AS RESULT;
    END;
    
    SET _gln = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Gln'));
	DROP TEMPORARY TABLE IF EXISTS inventorySyncSkuItems;
	DROP TEMPORARY TABLE IF EXISTS inventorySyncBatchSummary;
    
    CREATE TEMPORARY TABLE inventorySyncSkuItems (
        sku_id VARCHAR(100),
        batch_id VARCHAR(100),
        inventory INT DEFAULT 0
    );
    
    INSERT INTO inventorySyncSkuItems (sku_id, batch_id)
    SELECT jt.sku_id, jt.batch_id
    FROM JSON_TABLE(
        Parameters,
        '$.Items[*]' 
        COLUMNS (
            sku_id VARCHAR(100) PATH '$.SkuId',
            batch_id VARCHAR(100) PATH '$.BatchId'
        )
    ) AS jt;
    
    CREATE TEMPORARY TABLE inventorySyncBatchSummary (
        batch_id VARCHAR(100),
        inventory INT DEFAULT 0
    );
    
   
    INSERT INTO inventorySyncBatchSummary (batch_id, inventory)
    SELECT 
        sm.CLIENT_BATCH_ID,
        SUM(lm.QUANTITY) AS inventory
    FROM live_inventory_master lm
    INNER JOIN sku_batch_master sm 
        ON lm.BATCH_ID = sm.BATCH_ID
    INNER JOIN inventorySyncSkuItems si
        ON si.batch_id = sm.CLIENT_BATCH_ID
    GROUP BY sm.CLIENT_BATCH_ID;
    
    UPDATE inventorySyncSkuItems si
    INNER JOIN inventorySyncBatchSummary sb 
        ON si.batch_id = sb.batch_id
    SET si.inventory = sb.inventory;
    
    SELECT 
        1 AS SUCCESS,
        'SUCCESS' AS MESSAGE,
        JSON_OBJECT(
            'Gln', _gln,
            'Items', JSON_ARRAYAGG(
                JSON_OBJECT(
                    'SkuId', si.sku_id,
                    'BatchId', si.batch_id,
                    'Inventory', si.inventory
                )
            )
        ) AS RESULT
    FROM inventorySyncSkuItems si;
END proc */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_INVENTORY_SYN_CALL_BACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_INVENTORY_SYN_CALL_BACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_INVENTORY_SYN_CALL_BACK`(IN parameters JSON)
BEGIN
    
    
    
    DECLARE _inventorySyncMainId VARCHAR(100);
    DECLARE _inventorySyncMappingId VARCHAR(100);
    DECLARE _masterid VARCHAR(100);
    DECLARE _startTime DATETIME;
    DECLARE _waveCompletionTime DATETIME;
    DECLARE _comments TEXT;
    DECLARE _status VARCHAR(50);
    DECLARE _dashboardWaveDisable INT;
    DECLARE _inventorySyncGlnModels JSON;
    DECLARE _recordExists INT DEFAULT 0;
    DECLARE total_gln INT DEFAULT 0;
    DECLARE completed_roles INT DEFAULT 0;
    
    
    
    SET _inventorySyncMappingId = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.InventorySyncRequestId'));
    SET _status = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.Status'));
    
    
    
    SELECT COUNT(*) INTO _recordExists 
    FROM `inventory_sync_gln_mapping`
    WHERE `INVENTORY_SYN_GLN_MAPPING_ID` = _inventorySyncMappingId;
    
    
    
    IF _recordExists > 0 THEN
        SELECT `INVENTORY_SYNC_MASTER_ID` INTO _masterid 
        FROM `inventory_sync_gln_mapping`
        WHERE `INVENTORY_SYN_GLN_MAPPING_ID` = _inventorySyncMappingId;
        UPDATE `inventory_sync_gln_mapping` 
        SET `STATUS` = _status
        WHERE `INVENTORY_SYN_GLN_MAPPING_ID` = _inventorySyncMappingId;
        SELECT COUNT(*) INTO total_gln 
        FROM `inventory_sync_gln_mapping` 
        WHERE `INVENTORY_SYNC_MASTER_ID` = _masterid;
        SELECT COUNT(*) INTO completed_roles 
        FROM `inventory_sync_gln_mapping` 
        WHERE `INVENTORY_SYNC_MASTER_ID` = _masterid 
          AND ( `STATUS` = 'SUCCESS' or `STATUS`='PARTIAL_SUCCESS');
        IF (total_gln = completed_roles) THEN
            UPDATE `inventory_sync_master`
            SET `STATUS` = 'COMPLETED'
            WHERE `INVENTORY_SYNC_MASTER_ID` = _masterid;
        ELSE
            UPDATE `inventory_sync_master`
            SET `STATUS` = 'PARTIAL_COMPLETED'
            WHERE `INVENTORY_SYNC_MASTER_ID` = _masterid;
        END IF;
        SELECT 1 AS SUCCESS, 'UPDATED_SUCCESSFULLY' AS MESSAGE;
    ELSE
        SELECT 0 AS SUCCESS, 'RECORD_NOT_FOUND' AS MESSAGE;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_LPN_DATA_PUSH` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_LPN_DATA_PUSH` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_LPN_DATA_PUSH`(IN Parameters JSON)
BEGIN
    
    DECLARE v_lpnId VARCHAR(50);
    DECLARE v_gln VARCHAR(50);
     DECLARE v_parentOrderId VARCHAR(50);
    DECLARE v_orderId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_PickingType VARCHAR(50);
    DECLARE v_BatchPicklistId VARCHAR(100);
    DECLARE v_ClientOrderId VARCHAR(100);
    DECLARE v_BatchPicklistCode VARCHAR(100);
    DECLARE v_LpnBarcode VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_parentDestinationCode VARCHAR(100);
    DECLARE v_OpenTimestamp DATETIME;
    DECLARE v_CloseTimestamp DATETIME;
    DECLARE lpnclosePayloadId CHAR(36);
    
    SET v_LpnBarcode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.LpnId'));
    SET v_orderId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderId'));
    
    
    SELECT KEY_VALUE INTO @glnHeader  FROM `master_config`  WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    SELECT `PARENT_ORDER_ID`  INTO v_parentOrderId FROM `wms_to_wcs_order_request_data`
   WHERE `ORDER_ID` = v_orderId LIMIT 1;
	
    
    SELECT 
        `GLN`,
        `CLIENT_ORDER_ID`,
        `PICKING_TYPE`,
        `BATCH_PICKLIST_ID`,
        `BATCH_PICKLIST_CODE`,
        `STORE_ID`
    INTO 
        v_gln,
        v_ClientOrderId,
        v_PickingType,
        v_BatchPicklistId,
        v_BatchPicklistCode,
        v_parentDestinationCode
    FROM 
        `wms_to_wcs_order_level_pre_staged_data`
    WHERE 
        `PARENT_ORDER_ID` = v_parentOrderId  LIMIT 1;
 
    
    SELECT 
        `LPN_ID`,
        `LPN_OPEN_TIMESTAMP`,
        NOW()
    INTO 
        v_lpnId,
        v_OpenTimestamp,
        v_CloseTimestamp
    FROM 
        `lpn_master`
    WHERE 
        `LPN_BARCODE` = v_LpnBarcode
    ORDER BY `LPN_OPEN_TIMESTAMP` DESC
    LIMIT 1;
    
    
    SELECT `LPN_CLOSED_PAYLOAD_ID` 
    INTO lpnclosePayloadId 
    FROM `lpn_master` 
    WHERE `LPN_ID` = v_lpnId LIMIT 1;
    
        DROP TEMPORARY TABLE IF EXISTS TempPayloads;
        CREATE TEMPORARY TABLE TempPayloads (
            `id` VARCHAR(36),
            `payload_id` CHAR(36),
            `headers` JSON,
            `json_output` JSON,
            INDEX(id),
            INDEX(payload_id)
        );
        
        INSERT INTO TempPayloads (id, `payload_id`, headers, `json_output`)
        SELECT 
            v_lpnId,
            UUID(),
            JSON_OBJECT(@glnHeader,v_gln),
            JSON_OBJECT(
                'Gln', v_gln,
                'LpnBarcode', v_LpnBarcode,
                'OrderId', v_ClientOrderId,
                'DestinationStoreCode', v_parentDestinationCode,
                'BatchPicklistId', v_BatchPicklistId,
                'PickingType', v_PickingType,
                'PickingTransfers', IFNULL((
                    SELECT JSON_ARRAYAGG(
                        JSON_OBJECT(
                            'OrderLineId', pwom.`ORDER_LINE_ID`,
                            'ArticleId', sbm.`SKU_ID`,
                            'ArticleEAN', (
                                SELECT `EAN_ID` 
                                FROM `sku_ean_mapping` sem 
                                WHERE sem.`SKU_ID` = pwom.`SKU_ID` 
                                ORDER BY sem.`INSERTED_TIMESTAMP` DESC 
                                LIMIT 1
                            ),
                            'Quantity', lpm.`PICKED_QUANTITY`,
                            'Traceability', JSON_OBJECT(
                                'BatchId', sbm.`CLIENT_BATCH_ID`,
                                'BatchNumber', sbm.`BATCH_NUMBER`,
                                'ExpirationDate', DATE_FORMAT(sbm.`EXPIRY_DATE`, '%Y-%m-%d'),
                                'Mrp', sbm.`MRP`,
                                'CountryOfOrigin', sbm.`COUNTRY_OF_ORIGIN`
                            ),
                            'UserName', pwom.`PICK_BY`,
                            'PickTimestamp', DATE_FORMAT(pwom.`PICK_TIMESTAMP`, '%Y-%m-%dT%H:%i:%s.%fZ')
                        )
                    )
                    FROM `lpn_pick_wave_order_mapping` lpm
                    INNER JOIN `pick_wave_order_master` pwom ON pwom.`PICK_ORDER_ID` = lpm.`PICK_ORDER_ID`
                    INNER JOIN `sku_batch_master` sbm ON sbm.`BATCH_ID` = pwom.`BATCH_ID`
                    WHERE lpm.`LPN_ID` = v_lpnId
                ), JSON_ARRAY()),
                'OpenTimestamp', DATE_FORMAT(v_OpenTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ'),
                'CloseTimestamp', DATE_FORMAT(v_CloseTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ')
            ) AS RESULT;
            
    
    IF EXISTS (
        SELECT 1 FROM `wcs_to_wms_payload` 
        WHERE `PAYLOAD_ID` = lpnclosePayloadId AND `IS_PROCESSED` = 1
        UNION
        SELECT 1 FROM `wcs_to_wms_payload_archive` 
        WHERE `PAYLOAD_ID` = lpnclosePayloadId AND `IS_PROCESSED` = 1
    ) THEN
        SELECT 2 AS SUCCESS , 'lpnId already closed' AS RESULT;
        
    ELSEIF EXISTS (
        SELECT 1 FROM `wcs_to_wms_payload` 
        WHERE `PAYLOAD_ID` = lpnclosePayloadId AND `IS_PROCESSED` = 0 
       
    ) THEN
        SELECT 3 AS SUCCESS , 'REQUEST_IN_PROCESSING' AS MESSAGE;

    ELSE
        
        
        START TRANSACTION  ;
        
        INSERT INTO `wcs_to_wms_payload` (`PAYLOAD_ID`, `API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
        SELECT `payload_id`, headers, '304', 'cronJob', `json_output`
        FROM TempPayloads;
        
        UPDATE `lpn_master` AS C
        INNER JOIN TempPayloads AS T ON C.`LPN_ID` = T.`id`
        SET C.`LPN_CLOSED_PAYLOAD_ID` = T.`payload_id`;
        
        SELECT  `JSON_REQUEST` AS RESULT, 1 AS SUCCESS,`API_HEADERS` AS HEADERS,P.PAYLOAD_ID 
        FROM `wcs_to_wms_payload` P
        INNER JOIN TempPayloads T ON P.`PAYLOAD_ID` = T.`payload_id`;
        
        COMMIT ;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_LPN_DATA_PUSH_backup` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_LPN_DATA_PUSH_backup` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_LPN_DATA_PUSH_backup`(IN Parameters JSON)
BEGIN
    
    DECLARE v_lpnId VARCHAR(50);
    DECLARE v_gln VARCHAR(50);
     DECLARE v_parentOrderId VARCHAR(50);
    DECLARE v_orderId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_PickingType VARCHAR(50);
    DECLARE v_BatchPicklistId VARCHAR(100);
    DECLARE v_ClientOrderId VARCHAR(100);
    DECLARE v_BatchPicklistCode VARCHAR(100);
    DECLARE v_LpnBarcode VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_parentDestinationCode VARCHAR(100);
    DECLARE v_OpenTimestamp DATETIME;
    DECLARE v_CloseTimestamp DATETIME;
    DECLARE lpnclosePayloadId CHAR(36);
    
    SET v_LpnBarcode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.LpnId'));
    SET v_orderId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderId'));
    
    
    SELECT KEY_VALUE INTO @glnHeader  FROM `master_config`  WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    SELECT `PARENT_ORDER_ID`  INTO v_parentOrderId FROM `wms_to_wcs_order_request_data`
   WHERE `ORDER_ID` = v_orderId LIMIT 1;
	
    
    SELECT 
        `GLN`,
        `CLIENT_ORDER_ID`,
        `PICKING_TYPE`,
        `BATCH_PICKLIST_ID`,
        `BATCH_PICKLIST_CODE`,
        `STORE_ID`
    INTO 
        v_gln,
        v_ClientOrderId,
        v_PickingType,
        v_BatchPicklistId,
        v_BatchPicklistCode,
        v_parentDestinationCode
    FROM 
        `wms_to_wcs_order_level_pre_staged_data`
    WHERE 
        `PARENT_ORDER_ID` = v_parentOrderId ;
 
    
    SELECT 
        `LPN_ID`,
        `LPN_OPEN_TIMESTAMP`,
        NOW()
    INTO 
        v_lpnId,
        v_OpenTimestamp,
        v_CloseTimestamp
    FROM 
        `lpn_master`
    WHERE 
        `LPN_BARCODE` = v_LpnBarcode
    ORDER BY `LPN_OPEN_TIMESTAMP` DESC
    LIMIT 1;
    
    
    SELECT `LPN_CLOSED_PAYLOAD_ID` 
    INTO lpnclosePayloadId 
    FROM `lpn_master` 
    WHERE `LPN_ID` = v_lpnId;
    
    IF EXISTS (
        SELECT 1 FROM `wcs_to_wms_payload` 
        WHERE `PAYLOAD_ID` = lpnclosePayloadId AND `IS_PROCESSED` = 1
        UNION
        SELECT 1 FROM `wcs_to_wms_payload_archive` 
        WHERE `PAYLOAD_ID` = lpnclosePayloadId AND `IS_PROCESSED` = 1
    ) THEN
        SELECT 2 AS SUCCESS , 'lpnId already closed' AS RESULT;
    ELSE
        
        DROP TEMPORARY TABLE IF EXISTS TempPayloads;
        CREATE TEMPORARY TABLE TempPayloads (
            `id` varchar(36),
            `payload_id` CHAR(36),
            `headers` JSON,
            `json_output` JSON,
            INDEX(id),
            INDEX(payload_id)
        );
        
        INSERT INTO TempPayloads (id, `payload_id`, headers, `json_output`)
        SELECT 
            v_lpnId,
            UUID(),
            JSON_OBJECT(@glnHeader,v_gln),
            JSON_OBJECT(
                'Gln', v_gln,
                'LpnBarcode', v_LpnBarcode,
                'OrderId', v_ClientOrderId,
                'DestinationStoreCode', v_parentDestinationCode,
                'BatchPicklistId', v_BatchPicklistId,
                'PickingType', v_PickingType,
                'PickingTransfers', IFNULL((
                    SELECT JSON_ARRAYAGG(
                        JSON_OBJECT(
                            'OrderLineId', pwom.`ORDER_LINE_ID`,
                            'ArticleId', sbm.`SKU_ID`,
                            'ArticleEAN', (
                                SELECT `EAN_ID` 
                                FROM `sku_ean_mapping` sem 
                                WHERE sem.`SKU_ID` = pwom.`SKU_ID` 
                                ORDER BY sem.`INSERTED_TIMESTAMP` DESC 
                                LIMIT 1
                            ),
                            'Quantity', lpm.`PICKED_QUANTITY`,
                            'Traceability', JSON_OBJECT(
                                'BatchId', sbm.`CLIENT_BATCH_ID`,
                                'BatchNumber', sbm.`BATCH_NUMBER`,
                                'ExpirationDate', DATE_FORMAT(sbm.`EXPIRY_DATE`, '%Y-%m-%d'),
                                'Mrp', sbm.`MRP`,
                                'CountryOfOrigin', sbm.`COUNTRY_OF_ORIGIN`
                            ),
                            'UserName', pwom.`PICK_BY`,
                            'PickTimestamp', DATE_FORMAT(pwom.`PICK_TIMESTAMP`, '%Y-%m-%dT%H:%i:%s.%fZ')
                        )
                    )
                    FROM `lpn_pick_wave_order_mapping` lpm
                    INNER JOIN `pick_wave_order_master` pwom ON pwom.`PICK_ORDER_ID` = lpm.`PICK_ORDER_ID`
                    INNER JOIN `sku_batch_master` sbm ON sbm.`BATCH_ID` = pwom.`BATCH_ID`
                    WHERE lpm.`LPN_ID` = v_lpnId
                ), JSON_ARRAY()),
                'OpenTimestamp', DATE_FORMAT(v_OpenTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ'),
                'CloseTimestamp', DATE_FORMAT(v_CloseTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ')
            ) AS RESULT;
        
        INSERT INTO `wcs_to_wms_payload` (`PAYLOAD_ID`, `API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
        SELECT `payload_id`, headers, '304', 'cronJob', `json_output`
        FROM TempPayloads;
        
        UPDATE `lpn_master` AS C
        INNER JOIN TempPayloads AS T ON C.`LPN_ID` = T.`id`
        SET C.`LPN_CLOSED_PAYLOAD_ID` = T.`payload_id`;
        
        SELECT  `JSON_REQUEST` AS RESULT, 1 AS SUCCESS,`API_HEADERS` AS HEADERS,P.PAYLOAD_ID 
        FROM `wcs_to_wms_payload` P
        INNER JOIN TempPayloads T ON P.`PAYLOAD_ID` = T.`payload_id`;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_LPN_DATA_PUSH_NEW` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_LPN_DATA_PUSH_NEW` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_LPN_DATA_PUSH_NEW`(IN Parameters JSON)
BEGIN
    
    DECLARE v_lpnId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_orderId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_PickingType VARCHAR(50);
    DECLARE v_BatchPicklistId VARCHAR(100);
    DECLARE v_BatchPicklistCode VARCHAR(100);
    DECLARE v_LpnBarcode VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_OpenTimestamp DATETIME;
    DECLARE v_CloseTimestamp DATETIME;
    
    SET v_lpnId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.LpnId'));
    SET v_orderId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderId'));
    
    SELECT 
        `PICKING_TYPE`,
        `BATCH_PICKLIST_ID`,
        `BATCH_PICKLIST_CODE`
    INTO 
        v_PickingType,
        v_BatchPicklistId,
        v_BatchPicklistCode
    FROM 
        `wms_to_wcs_order_request_data`
    WHERE 
        ORDER_ID = v_orderId
    LIMIT 1;
    
    SELECT 
        `LPN_BARCODE`,
        `LPN_CREATED_TIMESTAMP`,
        `LPN_CLOSE_TIMESTAMP`
    INTO 
        v_LpnBarcode,
        v_OpenTimestamp,
        v_CloseTimestamp
    FROM 
        `lpn_master`
    WHERE 
        LPN_ID = v_lpnId
    LIMIT 1;
    
    SELECT JSON_OBJECT(
        'Gln', 'string',
        'LpnBarcode', v_LpnBarcode,
        'OrderId', v_orderId,
        'DestinationStoreCode', v_BatchPicklistCode,
        'BatchPicklistId', v_BatchPicklistId,
        'PickingType', v_PickingType,
        'PickingTransfers', (
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'OrderLineId', lpm.`ORDER_LINE_ID`,
                    'ArticleId', lpm.`SKU_ID`,
                    'ArticleEAN', (
                        SELECT `EAN_ID` 
                        FROM `sku_ean_mapping` sem 
                        WHERE sem.`SKU_ID` = lpm.`SKU_ID` 
                        ORDER BY sem.`INSERTED_TIMESTAMP` DESC 
                        LIMIT 1
                    ),
                    'Quantity', lpm.`PICKED_QUANTITY`,
                    'Traceability', JSON_OBJECT(
                        'BatchId', lpm.`BATCH_ID`,
                        'BatchNumber', sbm.`CLIENT_BATCH_ID`,
                        'ExpirationDate', DATE_FORMAT(sbm.`EXPIRY_DATE`, '%Y-%m-%d'),
                        'Mrp', sbm.`MRP`,
                        'CountryOfOrigin', sbm.`COUNTRY_OF_ORIGIN`
                    ),
                    'UserName', lpm.`PICK_BY`,
                    'PickTimestamp', DATE_FORMAT(lpm.`PICK_TIMESTAMP`, '%Y-%m-%dT%H:%i:%s.%fZ')
                )
            )
            FROM `lpn_pick_wave_order_mapping` lpm
            INNER JOIN `pick_wave_order_master` pwom ON pwom.`PICK_ORDER_ID` = lpm.`PICK_ORDER_ID`
            INNER JOIN `sku_batch_master` sbm ON sbm.`BATCH_ID` = lpm.`BATCH_ID`
            WHERE lpm.`LPN_ID` = v_lpnId
        ),
        'OpenTimestamp', DATE_FORMAT(v_OpenTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ'),
        'CloseTimestamp', DATE_FORMAT(v_CloseTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ')
    ) AS FinalPayload;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_LPN_DATA_PUSH_test1` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_LPN_DATA_PUSH_test1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_LPN_DATA_PUSH_test1`(IN Parameters JSON)
BEGIN
    
    DECLARE v_lpnId VARCHAR(50);
    DECLARE v_gln VARCHAR(50);
     DECLARE v_parentOrderId VARCHAR(50);
    DECLARE v_orderId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_PickingType VARCHAR(50);
    DECLARE v_BatchPicklistId VARCHAR(100);
    DECLARE v_ClientOrderId VARCHAR(100);
    DECLARE v_BatchPicklistCode VARCHAR(100);
    DECLARE v_LpnBarcode VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_parentDestinationCode VARCHAR(100);
    DECLARE v_OpenTimestamp DATETIME;
    DECLARE v_CloseTimestamp DATETIME;
    DECLARE lpnclosePayloadId CHAR(36);
    
    SET v_LpnBarcode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.LpnId'));
    SET v_orderId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderId'));
    
    
    SELECT KEY_VALUE INTO @glnHeader  FROM `master_config`  WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    SELECT `PARENT_ORDER_ID`  INTO v_parentOrderId FROM `wms_to_wcs_order_request_data`
   WHERE `ORDER_ID` = v_orderId LIMIT 1;
	
    
    SELECT 
        `GLN`,
        `CLIENT_ORDER_ID`,
        `PICKING_TYPE`,
        `BATCH_PICKLIST_ID`,
        `BATCH_PICKLIST_CODE`,
        `STORE_ID`
    INTO 
        v_gln,
        v_ClientOrderId,
        v_PickingType,
        v_BatchPicklistId,
        v_BatchPicklistCode,
        v_parentDestinationCode
    FROM 
        `wms_to_wcs_order_level_pre_staged_data`
    WHERE 
        `PARENT_ORDER_ID` = v_parentOrderId  LIMIT 1;
 
    
    SELECT 
        `LPN_ID`,
        `LPN_OPEN_TIMESTAMP`,
        NOW()
    INTO 
        v_lpnId,
        v_OpenTimestamp,
        v_CloseTimestamp
    FROM 
        `lpn_master`
    WHERE 
        `LPN_BARCODE` = v_LpnBarcode
    ORDER BY `LPN_OPEN_TIMESTAMP` DESC
    LIMIT 1;
    
    
    SELECT `LPN_CLOSED_PAYLOAD_ID` 
    INTO lpnclosePayloadId 
    FROM `lpn_master` 
    WHERE `LPN_ID` = v_lpnId LIMIT 1;
    
        DROP TEMPORARY TABLE IF EXISTS TempPayloads;
        CREATE TEMPORARY TABLE TempPayloads (
            `id` VARCHAR(36),
            `payload_id` CHAR(36),
            `headers` JSON,
            `json_output` JSON,
            INDEX(id),
            INDEX(payload_id)
        );
        
        INSERT INTO TempPayloads (id, `payload_id`, headers, `json_output`)
        SELECT 
            v_lpnId,
            UUID(),
            JSON_OBJECT(@glnHeader,v_gln),
            JSON_OBJECT(
                'Gln', v_gln,
                'LpnBarcode', v_LpnBarcode,
                'OrderId', v_ClientOrderId,
                'DestinationStoreCode', v_parentDestinationCode,
                'BatchPicklistId', v_BatchPicklistId,
                'PickingType', v_PickingType,
                'PickingTransfers', IFNULL((
                    SELECT JSON_ARRAYAGG(
                        JSON_OBJECT(
                            'OrderLineId', pwom.`ORDER_LINE_ID`,
                            'ArticleId', sbm.`SKU_ID`,
                            'ArticleEAN', (
                                SELECT `EAN_ID` 
                                FROM `sku_ean_mapping` sem 
                                WHERE sem.`SKU_ID` = pwom.`SKU_ID` 
                                ORDER BY sem.`INSERTED_TIMESTAMP` DESC 
                                LIMIT 1
                            ),
                            'Quantity', lpm.`PICKED_QUANTITY`,
                            'Traceability', JSON_OBJECT(
                                'BatchId', sbm.`CLIENT_BATCH_ID`,
                                'BatchNumber', sbm.`BATCH_NUMBER`,
                                'ExpirationDate', DATE_FORMAT(sbm.`EXPIRY_DATE`, '%Y-%m-%d'),
                                'Mrp', sbm.`MRP`,
                                'CountryOfOrigin', sbm.`COUNTRY_OF_ORIGIN`
                            ),
                            'UserName', pwom.`PICK_BY`,
                            'PickTimestamp', DATE_FORMAT(pwom.`PICK_TIMESTAMP`, '%Y-%m-%dT%H:%i:%s.%fZ')
                        )
                    )
                    FROM `lpn_pick_wave_order_mapping` lpm
                    INNER JOIN `pick_wave_order_master` pwom ON pwom.`PICK_ORDER_ID` = lpm.`PICK_ORDER_ID`
                    INNER JOIN `sku_batch_master` sbm ON sbm.`BATCH_ID` = pwom.`BATCH_ID`
                    WHERE lpm.`LPN_ID` = v_lpnId
                ), JSON_ARRAY()),
                'OpenTimestamp', DATE_FORMAT(v_OpenTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ'),
                'CloseTimestamp', DATE_FORMAT(v_CloseTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ')
            ) AS RESULT;
            
    
    IF EXISTS (
        SELECT 1 FROM `wcs_to_wms_payload` 
        WHERE `PAYLOAD_ID` = lpnclosePayloadId AND `IS_PROCESSED` = 1
        UNION
        SELECT 1 FROM `wcs_to_wms_payload_archive` 
        WHERE `PAYLOAD_ID` = lpnclosePayloadId AND `IS_PROCESSED` = 1
    ) THEN
        SELECT 2 AS SUCCESS , 'lpnId already closed' AS RESULT;
        
    ELSEIF EXISTS (
        SELECT 1 FROM `wcs_to_wms_payload` 
        WHERE `PAYLOAD_ID` = lpnclosePayloadId AND `IS_PROCESSED` = 0 
       
    ) THEN
        SELECT 3 AS SUCCESS , 'REQUEST_IN_PROCESSING' AS MESSAGE;

    ELSE
        
        
        START TRANSACTION  ;
        
        INSERT INTO `wcs_to_wms_payload` (`PAYLOAD_ID`, `API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
        SELECT `payload_id`, headers, '304', 'cronJob', `json_output`
        FROM TempPayloads;
        
        UPDATE `lpn_master` AS C
        INNER JOIN TempPayloads AS T ON C.`LPN_ID` = T.`id`
        SET C.`LPN_CLOSED_PAYLOAD_ID` = T.`payload_id`;
        
        SELECT  `JSON_REQUEST` AS RESULT, 1 AS SUCCESS,`API_HEADERS` AS HEADERS,P.PAYLOAD_ID 
        FROM `wcs_to_wms_payload` P
        INNER JOIN TempPayloads T ON P.`PAYLOAD_ID` = T.`payload_id`;
        
        COMMIT ;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_LPN_DATA_PUSH_V1` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_LPN_DATA_PUSH_V1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_LPN_DATA_PUSH_V1`(IN Parameters JSON)
BEGIN
    
    DECLARE v_lpnId VARCHAR(50);
    DECLARE v_gln VARCHAR(50);
    DECLARE v_orderId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_PickingType VARCHAR(50);
    DECLARE v_BatchPicklistId VARCHAR(100);
    DECLARE v_BatchPicklistCode VARCHAR(100);
    DECLARE v_LpnBarcode VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_parentDestinationCode VARCHAR(100);
    DECLARE v_OpenTimestamp DATETIME;
    DECLARE v_CloseTimestamp DATETIME;
    
    SET v_LpnBarcode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.LpnId'));
    SET v_orderId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderId'));
    
    SELECT 
        `GLN`,
        `PICKING_TYPE`,
        `BATCH_PICKLIST_ID`,
        `BATCH_PICKLIST_CODE`,
        `PARENT_STORE_ID`
    INTO 
        v_gln,
        v_PickingType,
        v_BatchPicklistId,
        v_BatchPicklistCode,
        v_parentDestinationCode
    FROM 
        `wms_to_wcs_order_request_data`
    WHERE 
        ORDER_ID = v_orderId
    LIMIT 1;
    
    SELECT 
        `LPN_ID`,
        `LPN_OPEN_TIMESTAMP`,
        `LPN_CLOSE_TIMESTAMP`
    INTO 
        v_lpnId,
        v_OpenTimestamp,
        v_CloseTimestamp
    FROM 
        `lpn_master`
    WHERE 
        `LPN_BARCODE` = v_LpnBarcode
      ORDER  BY `LPN_OPEN_TIMESTAMP` DESC
    LIMIT 1;
    
    SELECT 
        1 AS SUCCESS,
        v_gln AS HEADERS,
        JSON_OBJECT(
            'Gln', v_gln,
            'LpnBarcode', v_LpnBarcode,
            'OrderId', v_orderId,
            'DestinationStoreCode', v_parentDestinationCode,
            'BatchPicklistId', v_BatchPicklistId,
            'PickingType', v_PickingType,
            'PickingTransfers', IFNULL((
                SELECT JSON_ARRAYAGG(
                    JSON_OBJECT(
                        'OrderLineId', pwom.`ORDER_LINE_ID`,
                        'ArticleId', sbm.`SKU_ID`,
                        'ArticleEAN', (
                            SELECT `EAN_ID` 
                            FROM `sku_ean_mapping` sem 
                            WHERE sem.`SKU_ID` = pwom.`SKU_ID` 
                            ORDER BY sem.`INSERTED_TIMESTAMP` DESC 
                            LIMIT 1
                        ),
                        'Quantity', lpm.`PICKED_QUANTITY`,
                        'Traceability', JSON_OBJECT(
                            'BatchId', sbm.`CLIENT_BATCH_ID`,
                            'BatchNumber', sbm.`BATCH_NUMBER`,
                            'ExpirationDate', DATE_FORMAT(sbm.`EXPIRY_DATE`, '%Y-%m-%d'),
                            'Mrp', sbm.`MRP`,
                            'CountryOfOrigin', sbm.`COUNTRY_OF_ORIGIN`
                        ),
                        'UserName', pwom.`PICK_BY`,
                        'PickTimestamp', DATE_FORMAT(pwom.`PICK_TIMESTAMP`, '%Y-%m-%dT%H:%i:%s.%fZ')
                    )
                )
                FROM `lpn_pick_wave_order_mapping` lpm
                INNER JOIN `pick_wave_order_master` pwom ON pwom.`PICK_ORDER_ID` = lpm.`PICK_ORDER_ID`
                INNER JOIN `sku_batch_master` sbm ON sbm.`BATCH_ID` = pwom.`BATCH_ID`
                WHERE lpm.`LPN_ID` = v_lpnId
            ), JSON_ARRAY()),
            'OpenTimestamp', DATE_FORMAT(v_OpenTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ'),
            'CloseTimestamp', DATE_FORMAT(v_CloseTimestamp, '%Y-%m-%dT%H:%i:%s.%fZ')
        ) AS RESULT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_ORDER_ID_DELETION_VALIDATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_ORDER_ID_DELETION_VALIDATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_ORDER_ID_DELETION_VALIDATION`(IN Parameters JSON)
BEGIN
    DECLARE orderId VARCHAR(50);
    DECLARE isOrderLevelCancellation VARCHAR(10);
    DECLARE OrderStatus VARCHAR(50);
    DECLARE lpnOpenCount INT DEFAULT 0;
    DECLARE successCode INT DEFAULT 0;
    DECLARE message VARCHAR(255) DEFAULT '';
    DECLARE description VARCHAR(255) DEFAULT '';
    
    SET orderId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderId'));
    SET isOrderLevelCancellation = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.IsOrderLevelCancellation'));
    
    IF NOT EXISTS (SELECT 1 FROM `wms_to_wcs_order_request_data` WHERE `ORDER_ID` = orderId) THEN
        SET successCode = 0;
        SET message = 'ORDER_INVALID';
    ELSE
        
        SELECT `ORDER_REQUEST_STATUS`
        INTO OrderStatus
        FROM `wms_to_wcs_order_request_data`
        WHERE `ORDER_ID` = orderId
        ORDER BY `UPDATED_TIMESTAMP` DESC
        LIMIT 1;
        
        IF OrderStatus = 'ORDER_PICK_COMPLETED' THEN
            SET successCode = 0;
            SET message = 'ORDER_COMPLETED';
        ELSEIF isOrderLevelCancellation = 'false' AND OrderStatus <> 'PENDING' THEN
            SET successCode = 0;
            SET message = 'ORDER_LINE_NOT_BE_DELETE_WHILE_PROCESSING';
        ELSEIF OrderStatus = 'PENDING' THEN
            SET successCode = 1;
        ELSEIF OrderStatus = 'ORDER_PICK_STARTED' THEN
            
            SELECT COUNT(*) INTO lpnOpenCount
            FROM `lpn_master` lm
            INNER JOIN `lpn_pick_wave_order_mapping` lpwom ON lm.`LPN_ID` = lpwom.`LPN_ID`
            INNER JOIN `pick_wave_order_master` pwom ON pwom.`PICK_ORDER_ID` = lpwom.`PICK_ORDER_ID`
            WHERE pwom.`ORDER_ID` = orderId AND lm.`LPN_STATUS` = 'LPN_OPEN';
            IF lpnOpenCount > 0 THEN
                SET successCode = 0;
                SET message = 'LPN_IS_OPEN_FOR_THIS_ORDER_LPN_ID';
            ELSE
                SET successCode = 2;
            END IF;
        END IF;
    END IF;
    
    IF successCode = 1 THEN
        IF isOrderLevelCancellation = 'true' THEN
            
            UPDATE `wms_to_wcs_order_request_data`
            SET `ORDER_REQUEST_STATUS` = 'DELETED'
            WHERE `ORDER_ID` = orderId AND `ORDER_REQUEST_STATUS` = 'PENDING';
            
            SET message = 'DELETED SUCCESSFULLY';
            SET description = '';
        ELSE
            
            DROP TEMPORARY TABLE IF EXISTS temp_order_line_ids;
            CREATE TEMPORARY TABLE temp_order_line_ids (orderLineId VARCHAR(50));
            INSERT INTO temp_order_line_ids (orderLineId)
            SELECT jt.orderLineId
            FROM JSON_TABLE(
                Parameters,
                '$.OrderLineId[*]' COLUMNS (
                    orderLineId VARCHAR(50) PATH '$'
                )
            ) AS jt;
            
            UPDATE `wms_to_wcs_order_line_request_data` t
            JOIN temp_order_line_ids temp ON temp.orderLineId = t.ORDER_LINE_ID
            SET t.ORDER_LINE_PROCESS_STATUS = 'DELETED'
            WHERE t.ORDER_LINE_PROCESS_STATUS = 'PENDING';
            DROP TEMPORARY TABLE IF EXISTS temp_order_line_ids;
            SET message = 'DELETED SUCCESSFULLY';
            SET description = '';
        END IF;
    ELSEIF successCode = 2 THEN
        
        SET message = 'DELETION_REQUEST_SEND_TO_SYSTEM';
        SET successCode=1 ;
        SET description = '';
    END IF;
    
    SELECT successCode AS SUCCESS, message AS MESSAGE, description AS DESCRIPTION;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_PAYLOAD_INSERT_WCS_TO_WMS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_PAYLOAD_INSERT_WCS_TO_WMS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_PAYLOAD_INSERT_WCS_TO_WMS`(IN Parameters JSON)
BEGIN
    DECLARE ApiId BIGINT;
    DECLARE ApiSource VARCHAR(100);
    DECLARE _Headers json;
    DECLARE IsProcessed TINYINT;
    DECLARE JsonRequest JSON;
    DECLARE JsonResponse text;
    DECLARE HttpStatus INT;
    DECLARE IdempotencyKey VARCHAR(50);
    DECLARE MainPayloadId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE MappingReferenceId VARCHAR(50)  CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    
    
    SET JsonRequest         = Parameters ->> '$.JsonRequest';
    SET _Headers         = Parameters ->> '$.Headers';
    SET MainPayloadId       = Parameters ->> '$.PayloadId';
    SET MappingReferenceId  = Parameters ->> '$.MappingPayloadId';
    SET IdempotencyKey      = Parameters ->> '$.IdempotencyId';
    SET IsProcessed         = Parameters ->> '$.IsProcessed';
    SET ApiId               = Parameters ->> '$.ApiId';
    SET ApiSource           = Parameters ->> '$.ApiSource';
    SET JsonResponse        = Parameters ->> '$.JsonResponse';
    
    SET HttpStatus = 
        CASE 
            WHEN Parameters ->> '$.HttpStatus' IS NULL OR Parameters ->> '$.HttpStatus' = 'null' THEN NULL
            ELSE CAST(Parameters ->> '$.HttpStatus' AS SIGNED)
        END;
    
    IF NOT EXISTS (SELECT 1 FROM `wcs_to_wms_payload` WHERE `PAYLOAD_ID`=MainPayloadId) THEN
    INSERT INTO `wcs_to_wms_payload`
    (
        `PAYLOAD_ID`,
        `IDEMPOTENCY_KEY`,
        `API_ID`,
        `API_HEADERS`,
        `API_SOURCE`,
        `JSON_REQUEST`,
        `JSON_RESPONSE`,
        `HTTP_STATUS`,
        `IS_PROCESSED`,
        
        `INSERTED_BY`,
        `PROCESSED_TIMESTAMP`
    )
    VALUES (
        MainPayloadId,
        IdempotencyKey,
        ApiId,
        _Headers,
        ApiSource,
        JsonRequest,
        JsonResponse,
        HttpStatus,
        IsProcessed,
        'BACKEND',
        NOW()
    );
    ELSE 
	    UPDATE wcs_to_wms_payload 
	   SET 
		    IDEMPOTENCY_KEY    = IFNULL(IdempotencyKey, IDEMPOTENCY_KEY),
		    API_ID             = IFNULL(ApiId, API_ID),
		    API_SOURCE         = IFNULL(ApiSource, API_SOURCE),
		    JSON_REQUEST       = IFNULL(JsonRequest, JSON_REQUEST),
		    JSON_RESPONSE      = IFNULL(JsonResponse, JSON_RESPONSE),
		    HTTP_STATUS        = IFNULL(HttpStatus, HTTP_STATUS),
		    IS_PROCESSED       = IFNULL(IsProcessed, IS_PROCESSED),
		    INSERTED_BY        = 'SYSTEM',
		    `NO_OF_ATTEMPTS`  = `NO_OF_ATTEMPTS`+1,
		    PROCESSED_TIMESTAMP = NOW()
		WHERE PAYLOAD_ID = MainPayloadId;
     END IF;
    
    UPDATE `wms_to_wcs_payload`
    SET `ASYNC_PAYLOAD_ID` = MainPayloadId
    WHERE `PAYLOAD_ID` = MappingReferenceId;
    SELECT 1 AS Success;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_PAYLOAD_INSERT_WMS_TO_WCS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_PAYLOAD_INSERT_WMS_TO_WCS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_PAYLOAD_INSERT_WMS_TO_WCS`(IN Parameters JSON)
BEGIN
        DECLARE ApiId BIGINT;
	DECLARE ApiSource VARCHAR(100);
	DECLARE PayloadId varchar(36) ;
	DECLARE IsProcessed tinyInt;
	DECLARE JsonRequest JSON;
	DECLARE JsonResponse JSON;
	DECLARE HttpStatus INT;
	DECLARE IdempotencyKey VARCHAR(50);
	SET JsonRequest = Parameters ->> '$.JsonRequest';
	SET PayloadId = Parameters->>'$.PayloadId';
	SET IdempotencyKey = Parameters ->> '$.IdempotencyKey';
	SET IsProcessed = Parameters ->> '$.IsProcessed' ;
	SET ApiId = Parameters ->> '$.ApiId';
	SET ApiSource = Parameters->> '$.ApiSource';
	SET JsonResponse = Parameters ->> '$.JsonResponse';
	SET HttpStatus = Parameters ->> '$.HttpStatus';
	
	
	INSERT INTO wms_to_wcs_payload(`PAYLOAD_ID`,`IDEMPOTENCY_KEY`,API_ID, API_SOURCE, JSON_REQUEST, JSON_RESPONSE, HTTP_STATUS,`IS_PROCESSED`,`INSERTED_BY`,`PROCESSED_TIMESTAMP`)
	 VALUES (PayloadId,IdempotencyKey,ApiId, ApiSource, JsonRequest, JsonResponse, HttpStatus,IsProcessed,"BACKEND",nOW());
	 
	 select 1 as Success ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_PREPARE_ORDERS_DELETE` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_PREPARE_ORDERS_DELETE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_PREPARE_ORDERS_DELETE`(IN Parameters JSON)
BEGIN
    DECLARE clientOrderId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE isOrderLevelCancellation VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE lpnBarcode VARCHAR(50);
    DECLARE lpnIds VARCHAR(100);
    DECLARE successCode INT DEFAULT 0;
    DECLARE result VARCHAR(255) DEFAULT '';
    DECLARE message VARCHAR(255) DEFAULT 'ORDER_SUSPENSION_ERROR';
    DECLARE allStatuses TEXT DEFAULT NULL;
    
    SET clientOrderId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderId'));
    SET isOrderLevelCancellation = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.IsOrderIdLevelCancellation'));
     
    
    
    IF NOT EXISTS (
        SELECT 1
        FROM `wms_to_wcs_order_level_pre_staged_data`
        WHERE `CLIENT_ORDER_ID` = clientOrderId
    ) THEN
        SET successCode = 0;
        SET result = 'ORDER_INVALID';
        SET message = 'ORDER_INVALID';
    ELSE
        
        SELECT GROUP_CONCAT(DISTINCT ORDER_REQUEST_STATUS) INTO allStatuses
        FROM wms_to_wcs_order_level_pre_staged_data
        WHERE CLIENT_ORDER_ID = clientOrderId;
        
        DROP TEMPORARY TABLE IF EXISTS temp_All_Order_Id;
        CREATE TEMPORARY TABLE temp_All_Order_Id (
            order_id VARCHAR(50),
            INDEX(order_id)
        ) ENGINE = MEMORY;
        INSERT INTO temp_All_Order_Id (order_id)
        SELECT DISTINCT `ORDER_ID`
        FROM `wms_to_wcs_order_level_pre_staged_data` a
        inner join `wms_to_wcs_order_request_data` b on a.PARENT_ORDER_ID=b.PARENT_ORDER_ID 
        WHERE `CLIENT_ORDER_ID` = clientOrderId;
        
        
        IF (NOT FIND_IN_SET('PENDING', allStatuses) AND NOT FIND_IN_SET('ORDER_PICK_STARTED', allStatuses)
            AND FIND_IN_SET('ORDER_PICK_COMPLETED', allStatuses)) THEN
            SET successCode = 0;
            SET message = 'ORDER_COMPLETED';
            SET result = 'ORDER_COMPLETED';
        
        
        ELSEIF  isOrderLevelCancellation = 'false'   THEN
	            SET successCode = 0;
		    SET message = 'ORDER_LINE_LEVEL_CANCELATION_NOT_SUPPORTED';
		    SET result = ''; 
        
        ELSEIF allStatuses = 'PENDING' THEN
            UPDATE wms_to_wcs_order_level_pre_staged_data
            SET ORDER_REQUEST_STATUS = 'DELETED'
            WHERE CLIENT_ORDER_ID = clientOrderId;
            UPDATE `wms_to_wcs_order_request_data` a
            INNER JOIN wms_to_wcs_order_level_pre_staged_data b
                ON a.`PARENT_ORDER_ID` = b.`PARENT_ORDER_ID`
            SET a.ORDER_REQUEST_STATUS = 'DELETED'
            WHERE b.CLIENT_ORDER_ID = clientOrderId
              AND a.ORDER_REQUEST_STATUS = 'PENDING';
            SET successCode = 1;
            SET message = 'Deleted successfully';
            SET result = '';
        
        ELSEIF FIND_IN_SET('ORDER_PICK_STARTED', allStatuses) THEN
            
            
            SELECT lm.LPN_ID
            INTO lpnIds
            FROM lpn_master lm
            INNER JOIN lpn_pick_wave_order_mapping lpwom ON lm.LPN_ID = lpwom.LPN_ID
            INNER JOIN pick_wave_order_master pwom ON pwom.PICK_ORDER_ID = lpwom.PICK_ORDER_ID
            INNER JOIN temp_All_Order_Id ts ON ts.order_id = pwom.ORDER_ID
            WHERE lm.LPN_STATUS = 'LPN_OPEN'
            LIMIT 1;
            IF lpnIds IS NOT NULL THEN
                SELECT `LPN_BARCODE` INTO lpnBarcode
                FROM `lpn_master`
                WHERE `LPN_ID` = lpnIds
                LIMIT 1;
                SET successCode = 0;
                SET result = CONCAT('LPN_IS_OPEN_FOR_THIS_ORDER_', lpnBarcode);
                SET message = result;
            ELSE
                
                UPDATE wms_to_wcs_order_level_pre_staged_data
                SET ORDER_REQUEST_STATUS = 'DELETED'
                WHERE CLIENT_ORDER_ID = clientOrderId;
                UPDATE `wms_to_wcs_order_request_data` a
                INNER JOIN wms_to_wcs_order_level_pre_staged_data b
                    ON a.`PARENT_ORDER_ID` = b.`PARENT_ORDER_ID`
                SET a.ORDER_REQUEST_STATUS = 'DELETED'
                WHERE b.CLIENT_ORDER_ID = clientOrderId
                  AND a.ORDER_REQUEST_STATUS = 'PENDING';
                SET successCode = 1;
                SET result = 'NO_OPEN_LPN';
                SET message = 'DELETION_ACCEPTED';
            END IF;
        
        ELSE
		UPDATE wms_to_wcs_order_level_pre_staged_data
                SET ORDER_REQUEST_STATUS = 'DELETED'
                WHERE CLIENT_ORDER_ID = clientOrderId;
                UPDATE `wms_to_wcs_order_request_data` a
                INNER JOIN wms_to_wcs_order_level_pre_staged_data b
                    ON a.`PARENT_ORDER_ID` = b.`PARENT_ORDER_ID`
                SET a.ORDER_REQUEST_STATUS = 'DELETED'
                WHERE b.CLIENT_ORDER_ID = clientOrderId
                  AND a.ORDER_REQUEST_STATUS = 'PENDING';
                  
            SET successCode = 1;
            SET result = '';
            SET message = 'DELETION_SUCCESSFULL';
        END IF;
        
        DROP TEMPORARY TABLE IF EXISTS temp_All_Order_Id;
    END IF;
    
    SELECT successCode AS SUCCESS, result AS RESULT, message AS MESSAGE;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_PREPARE_ORDERS_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_PREPARE_ORDERS_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_PREPARE_ORDERS_INSERT`(IN Parameters JSON)
BEGIN
    
    DECLARE clientOrderId            VARCHAR(50);
    DECLARE storeCode               VARCHAR(100);
    DECLARE storeName               VARCHAR(100);
    DECLARE OrderCreationTime       DATETIME;
    DECLARE payloadId               VARCHAR(36);
    DECLARE v_errorMessage          TEXT;
    
    DECLARE _gln                    VARCHAR(100);
    DECLARE pickingType             VARCHAR(50);
    DECLARE wmsBatchId              VARCHAR(50);
    DECLARE batchPicklistCode       VARCHAR(100);
    DECLARE batchPicklistId         VARCHAR(50);
    DECLARE orderCategory           VARCHAR(50);
    DECLARE priority                INT;
    DECLARE orderTimeStr            VARCHAR(30);
    
    DECLARE _parentOrderId          VARCHAR(36);
    DECLARE _priority_str           VARCHAR(64);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;
        ROLLBACK;
        SELECT 0 AS SUCCESS, 'FAILED DUE TO ERROR' AS MESSAGE, v_errorMessage AS DESCRIPTION;
    END;
    
    SET payloadId     = UUID();
    SET clientOrderId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderId'));
    SET storeCode     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.DestinationStoreCode'));
    SET storeName     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.DestinationStoreName'));
    SET orderTimeStr  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderCreationTime'));
    IF orderTimeStr IS NOT NULL AND orderTimeStr <> '' THEN
        
        SET OrderCreationTime = STR_TO_DATE(orderTimeStr, '%Y-%m-%dT%H:%i:%sZ');
    ELSE
        SET OrderCreationTime = NULL;
    END IF;
    SET _gln              = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Gln'));
    SET pickingType       = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.PickingType'));
    SET wmsBatchId        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.WMSBatchId'));
    SET batchPicklistCode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.BatchPicklistCode'));
    SET batchPicklistId   = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.BatchPicklistId'));
    SET orderCategory     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.OrderCategory'));
    
    SET _priority_str = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Priority'));
    IF _priority_str IS NULL OR _priority_str = '' THEN
        SET priority = NULL;
    ELSE
        SET priority = CAST(_priority_str AS SIGNED);
    END IF;
    
    DROP TEMPORARY TABLE IF EXISTS temp_order_lines;
    DROP TEMPORARY TABLE IF EXISTS temp_invalid_data;
    DROP TEMPORARY TABLE IF EXISTS batch_id_map;
    
    CREATE TEMPORARY TABLE temp_order_lines (
        ID INT AUTO_INCREMENT PRIMARY KEY,
        CLIENT_ORDER_ID         VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        ORDER_LINE_ID           VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        ARTICLE_ID              VARCHAR(255) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        QUANTITY                INT,
        DELIVERY_DATE           DATE,
        DISPLAY_INSTRUCTION     TEXT,
        CLIENT_BATCH_ID         VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        BATCH_NUMBER            VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        EXPIRY_DATE             DATE,
        MRP                     DECIMAL(10,3),
        COUNTRY_OF_ORIGIN       VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        PAYLOAD_ID              VARCHAR(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        INDEX(ORDER_LINE_ID),
        INDEX(CLIENT_ORDER_ID),
        INDEX(ARTICLE_ID),
        INDEX(MRP),
        INDEX(EXPIRY_DATE)
    );
    
    CREATE TEMPORARY TABLE temp_invalid_data (
        ID            VARCHAR(100),
        ERROR_TYPE    VARCHAR(36),
        ERROR_MESSAGE VARCHAR(1000)
    );
    
    INSERT INTO temp_order_lines (
        CLIENT_ORDER_ID,  ORDER_LINE_ID, ARTICLE_ID, QUANTITY, DELIVERY_DATE,
        DISPLAY_INSTRUCTION, CLIENT_BATCH_ID, BATCH_NUMBER, EXPIRY_DATE, MRP,
        COUNTRY_OF_ORIGIN, PAYLOAD_ID
    )
    SELECT
        clientOrderId,                       
        JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.OrderLineId')) AS ORDER_LINE_ID,
        JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.ArticleId')) AS ARTICLE_ID,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.Quantity')) AS UNSIGNED) AS QUANTITY,
        NULL,
        JSON_UNQUOTE(JSON_EXTRACT(j.value, '$.DisplayOperatorInstruction')) AS DISPLAY_INSTRUCTION,
        JSON_UNQUOTE(JSON_EXTRACT(j.value, '$."Traceability".BatchId')) AS CLIENT_BATCH_ID,
        JSON_UNQUOTE(JSON_EXTRACT(j.value, '$."Traceability".BatchNumber')) AS BATCH_NUMBER,
        STR_TO_DATE(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$."Traceability".ExpirationDate')), '%Y-%m-%d') AS EXPIRY_DATE,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(j.value, '$."Traceability".Mrp')) AS DECIMAL(10,3)) AS MRP,
        JSON_UNQUOTE(JSON_EXTRACT(j.value, '$."Traceability".CountryOfOrigin')) AS COUNTRY_OF_ORIGIN,
        payloadId
    FROM JSON_TABLE(
        Parameters, '$.OrderLines[*]'
        COLUMNS ( VALUE JSON PATH '$' )
    ) AS j;
    
    SET _parentOrderId = UUID();
    CREATE TEMPORARY TABLE batch_id_map AS
    SELECT 
        ARTICLE_ID,
        CLIENT_BATCH_ID,
        BATCH_NUMBER,
        GLN,
        MRP,
        EXPIRY_DATE,
        COUNTRY_OF_ORIGIN,
        UUID() AS BATCH_ID
    FROM (
        SELECT DISTINCT
            ARTICLE_ID,
            CLIENT_BATCH_ID,
            BATCH_NUMBER,
            _gln AS GLN,
            MRP,
            EXPIRY_DATE,
            COUNTRY_OF_ORIGIN
        FROM temp_order_lines temp
        WHERE NOT EXISTS (
            SELECT 1 FROM `sku_batch_master` sbm 
            WHERE temp.ARTICLE_ID = sbm.`SKU_ID`
              AND sbm.`GLN` = _gln 
              AND sbm.`CLIENT_BATCH_ID` = temp.CLIENT_BATCH_ID
        )
    ) AS deduplicated;
    
    INSERT INTO temp_invalid_data (ID, ERROR_TYPE, ERROR_MESSAGE)
    SELECT `CLIENT_ORDER_ID`, 'ORDER_LEVEL', 'ORDER_ID_ALREADY_PROCESSED'
    FROM `wms_to_wcs_order_level_pre_staged_data`
    WHERE CLIENT_ORDER_ID = clientOrderId
      AND `BATCH_PICKLIST_CODE` = batchPicklistCode;
    INSERT INTO temp_invalid_data (ID, ERROR_TYPE, ERROR_MESSAGE)
    SELECT tol.ORDER_LINE_ID, 'ORDER_LINE_LEVEL', 'ORDER_LINE_ID_ALREADY_PROCESSED'
    FROM temp_order_lines tol
    INNER JOIN `wms_to_wcs_order_line_level_pre_staged_data` olr ON tol.ORDER_LINE_ID = olr.ORDER_LINE_ID
    WHERE tol.CLIENT_ORDER_ID = clientOrderId;
    INSERT INTO temp_invalid_data (ID, ERROR_TYPE, ERROR_MESSAGE)
    SELECT tol.ORDER_LINE_ID, 'ORDER_LINE_LEVEL', 'ARTICLE_ID_MISSING'
    FROM temp_order_lines tol
    LEFT JOIN `sku_master` sm ON tol.ARTICLE_ID = sm.SKU_ID
    WHERE sm.SKU_ID IS NULL;
    IF EXISTS (SELECT 1 FROM temp_invalid_data) THEN
        SELECT * FROM temp_invalid_data;
    ELSE
        START TRANSACTION;
        INSERT IGNORE INTO sku_batch_master (
            SKU_ID, CLIENT_BATCH_ID, BATCH_NUMBER, GLN, BATCH_ID, MRP, EXPIRY_DATE, COUNTRY_OF_ORIGIN
        )
        SELECT  bim.ARTICLE_ID, bim.CLIENT_BATCH_ID, bim.BATCH_NUMBER,
            bim.GLN, bim.BATCH_ID,
            bim.MRP, bim.EXPIRY_DATE, bim.COUNTRY_OF_ORIGIN
        FROM (
            SELECT 
                bim.ARTICLE_ID, bim.CLIENT_BATCH_ID,
                bim.BATCH_NUMBER,
                bim.GLN,
                bim.BATCH_ID,
                bim.MRP,
                bim.EXPIRY_DATE,
                bim.COUNTRY_OF_ORIGIN,
                DENSE_RANK() OVER(PARTITION BY ARTICLE_ID,CLIENT_BATCH_ID,GLN ORDER BY BATCH_ID) AS ARank
            FROM batch_id_map bim
        ) bim
        WHERE bim.ARank = 1;
        INSERT INTO `wms_to_wcs_order_level_pre_staged_data`
            (CLIENT_ORDER_ID, `PARENT_ORDER_ID`, STORE_ID, PARENT_STORE_ID, ORDER_REQUEST_STATUS,
             ORDER_CREATION_TIME, GLN, PICKING_TYPE, WMS_BATCH_ID, BATCH_PICKLIST_CODE, BATCH_PICKLIST_ID,
             ORDER_CATEGORY, PRIORITY)
        SELECT
            clientOrderId,
            _parentOrderId,
            storeCode,
            NULL,
            'PENDING',
            OrderCreationTime,
            _gln,
            pickingType,
            wmsBatchId,
            batchPicklistCode,
            batchPicklistId,
            orderCategory,
            priority;
        
        INSERT IGNORE INTO `wms_to_wcs_order_line_level_pre_staged_data`
        (WMS_ORDER_REQUEST_DATA_ID, `PARENT_ORDER_ID`, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, DELIVERY_DATE,
         DISPLAY_OPERATOR_INSTRUCTION, BATCH_ID, MRP, EXPIRY_DATE, ORDER_LINE_PROCESS_STATUS)
        SELECT
            wword.WMS_ORDER_REQUEST_DATA_ID,
            wword.PARENT_ORDER_ID,
            tol.ORDER_LINE_ID,
            tol.ARTICLE_ID,
            tol.QUANTITY,
            tol.DELIVERY_DATE,
            tol.DISPLAY_INSTRUCTION,
            sbm.BATCH_ID,
            sbm.MRP,
            sbm.EXPIRY_DATE,
            'PENDING'
        FROM temp_order_lines tol
        INNER JOIN `wms_to_wcs_order_level_pre_staged_data` wword
            ON wword.parent_order_id = _parentOrderId
        INNER JOIN sku_batch_master sbm
            ON sbm.SKU_ID = tol.ARTICLE_ID
           AND sbm.CLIENT_BATCH_ID = tol.CLIENT_BATCH_ID
           AND sbm.GLN = _gln;
        COMMIT;
        SELECT 1 AS SUCCESS, "UPLOADED SUCCESSFULLY" AS MESSAGE, '' AS DESCRIPTION;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS temp_order_lines;
    DROP TEMPORARY TABLE IF EXISTS temp_invalid_data;
    DROP TEMPORARY TABLE IF EXISTS batch_id_map;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_REPLACE_SKU_EAN_MAPPING` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_REPLACE_SKU_EAN_MAPPING` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_REPLACE_SKU_EAN_MAPPING`(
    IN p_Gln VARCHAR(50),
    IN p_ArticleId VARCHAR(200),
    IN p_BarcodeList JSON
)
BEGIN
    DECLARE barcode_count INT;
    DECLARE i INT DEFAULT 0;
    DECLARE current_barcode VARCHAR(50);
    
    SELECT COUNT(*) INTO barcode_count FROM sku_master WHERE SKU_ID = p_ArticleId;
    IF barcode_count = 0 THEN
        
        SELECT 0 AS SUCCESS, "ARTICLE NOT FOUND" AS MESSAGE;
    ELSE
        
        DELETE FROM sku_ean_mapping WHERE SKU_ID = p_ArticleId;
        
        SET barcode_count = JSON_LENGTH(p_BarcodeList);
        
        WHILE i < barcode_count DO
            SET current_barcode = JSON_UNQUOTE(JSON_EXTRACT(p_BarcodeList, CONCAT('$[', i, ']')));
            
            INSERT INTO sku_ean_mapping (SKU_ID, BARCODE)
            VALUES (p_ArticleId, current_barcode);
            
            SET i = i + 1;
        END WHILE;
        
        SELECT 1 AS SUCCESS, "BARCODES UPDATED SUCCESSFULLY" AS MESSAGE;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_SKU_VALIDATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_SKU_VALIDATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_SKU_VALIDATION`(IN Parameters JSON)
BEGIN
    DECLARE _gln VARCHAR(100) ;
    SET _gln = Parameters->>'$.Gln';
    
    CREATE TEMPORARY TABLE IF NOT EXISTS articleList (
        skuid VARCHAR(100),
        flag bool DEFAULT false,
        index(skuid)
    ) engine = memory;
    
    INSERT INTO articleList (skuid)
    SELECT jt.`skuId`
    FROM JSON_TABLE(
        Parameters, 
        '$.ArticleIdList[*]' COLUMNS(
            skuId VARCHAR(100) PATH '$'
        )
    ) AS jt;
    
UPDATE articleList al
INNER JOIN `sku_ean_mapping`  sem ON al.skuid=sem.`SKU_ID`
SET al.flag = TRUE;
    
    SELECT 
        JSON_OBJECT(
            'Gln', _gln,
            'ArticleIdList',
                (SELECT JSON_ARRAYAGG(
                    JSON_OBJECT(
                        al.skuid,al.flag 
                    )
                ) FROM articleList al)
        ) AS RESULT,
        1 AS SUCCESS,
        'Request processed successfully' AS MESSAGE;
    
    DROP TEMPORARY TABLE IF EXISTS articleList;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_SKU_VALIDATION_1` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_SKU_VALIDATION_1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_SKU_VALIDATION_1`(IN Parameters JSON)
BEGIN
    DECLARE _gln VARCHAR(100);
    
    SET _gln = Parameters->>'$.gln';
    
    SELECT 
        JSON_OBJECT(
            'Gln', _gln,
            'ArticleIdList',
                JSON_ARRAYAGG(
                    JSON_OBJECT(
                        jt.skuId, IF(sem.SKU_ID IS NOT NULL, TRUE, FALSE)
                    )
                )
        ) AS RESULT,
        1 AS SUCCESS,
        'Request processed successfully' AS MESSAGE
    FROM JSON_TABLE(
        Parameters,
        '$.ArticleIdList[*]' COLUMNS (
            skuId VARCHAR(100) PATH '$'
        )
    ) AS jt
    LEFT JOIN sku_ean_mapping sem ON jt.skuId = sem.SKU_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_SKU_VALIDATION_testing1` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_SKU_VALIDATION_testing1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_SKU_VALIDATION_testing1`(IN Parameters JSON)
BEGIN
    DECLARE _gln VARCHAR(100) ;
    SET _gln = Parameters->>'$.Gln';
    
    CREATE TEMPORARY TABLE IF NOT EXISTS articleList (
        id int AUTO_increment primary KEY,
        skuid VARCHAR(100),
        flag bool DEFAULT false,
        index(skuid)
    ) engine = memory;
    
     CREATE TEMPORARY TABLE IF NOT EXISTS articleListtemp1 (
        skuid VARCHAR(100),
        flag BOOL DEFAULT FALSE,
        INDEX(skuid)
    ) ENGINE = MEMORY;
    
    
    INSERT INTO articleList (skuid)
    SELECT jt.`skuId`
    FROM JSON_TABLE(
        Parameters, 
        '$.ArticleIdList[*]' COLUMNS(
            skuId VARCHAR(100) PATH '$'
        )
    ) AS jt;
    
     INSERT INTO articleListtemp1 (skuid)
    SELECT jt.`skuId`
    FROM JSON_TABLE(
        Parameters, 
        '$.ArticleIdList[*]' COLUMNS(
            skuId VARCHAR(100) PATH '$'
        )
    ) AS jt;
    
    
    
   
    
 
    
UPDATE articleList al
INNER JOIN `sku_ean_mapping`  sem ON al.skuid=sem.`SKU_ID`
SET al.flag = TRUE  ; 
    
   
 
  
    
    SELECT 
        JSON_OBJECT(
            'Gln', _gln,
            'ArticleIdList',
                (SELECT JSON_ARRAYAGG(
                    JSON_OBJECT(
                        al.skuid,al.flag 
                    )
                ) FROM articleList al)
        ) AS RESULT,
        1 AS SUCCESS,
        'Request processed successfully' AS MESSAGE;
    
    DROP TEMPORARY TABLE IF EXISTS articleList;
    DROP TEMPORARY TABLE IF EXISTS articleListtemp1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_STORAGE_PALLET_SCANNED_STORAGE_REQUEST` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_STORAGE_PALLET_SCANNED_STORAGE_REQUEST` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_STORAGE_PALLET_SCANNED_STORAGE_REQUEST`(IN Parameters JSON)
BEGIN
    
    DECLARE lpnBarcode VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE storageRequestId VARCHAR(100);
    DECLARE _gln VARCHAR(100);
    DECLARE orderCount INT DEFAULT 0;
    DECLARE _payloadId VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE _isProcessed INT DEFAULT 0;
    
    
    SET lpnBarcode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.PalletBarcode'));
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
   
	SELECT COUNT(1) INTO orderCount
	FROM wms_to_wcs_storage_request_pallet_data
	WHERE PALLET_ID = lpnBarcode AND STORAGE_REQUEST_STATUS = 'PENDING';
	
	IF orderCount = 1 THEN
	    SELECT PALLET_SCANNED_PAYLOAD_ID INTO _payloadId
	    FROM wms_to_wcs_storage_request_pallet_data
	    WHERE PALLET_ID = lpnBarcode AND STORAGE_REQUEST_STATUS = 'PENDING'
	    LIMIT 1;
	END IF;
    IF orderCount = 0 THEN
        
        SELECT 
            0 AS SUCCESS, 
            'PALLET_ID_NOT_FOUND' AS MESSAGE;
    ELSE
        
        SELECT `IS_PROCESSED` INTO _isProcessed
        FROM `wcs_to_wms_payload`
        WHERE `PAYLOAD_ID` = _payloadId;
        IF _isProcessed = 1 THEN
            SELECT 
                2 AS SUCCESS, 
                'ALREADY_PROCESSED_FROM_ZEPTO' AS RESULT, 
                'nil' AS HEADERS;
        ELSE
        
        DROP TEMPORARY TABLE IF EXISTS TempPayloads;
         CREATE TEMPORARY TABLE TempPayloads (
        `id` INT,
        `payload_id` CHAR(36),
        `headers` JSON,
        `json_output` JSON,
        index(id),
        index(payload_id)
     );
        
            
            INSERT INTO TempPayloads (id, `payload_id`, headers, `json_output`)
            SELECT 
                wm.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`,
                UUID(),
                JSON_OBJECT(@glnHeader, wm.`GLN`),
                JSON_OBJECT(
                    'Gln', wm.`GLN`,
                    'StorageRequestId', wm.`STORAGE_REQUEST_ID`,
                    'Status', 'SCANNED',
                    'Remarks', '',
                    'EventTimestamp', Now()
                )
            FROM `wms_to_wcs_storage_request_pallet_data` wm
            WHERE wm.`PALLET_ID` = lpnBarcode AND wm.`STORAGE_REQUEST_STATUS` = 'PENDING';
            
            INSERT  INTO `wcs_to_wms_payload` (`PAYLOAD_ID`, `API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
            SELECT `payload_id`, headers, '319', 'cronJob', `json_output`
            FROM TempPayloads;
            
            UPDATE `wms_to_wcs_storage_request_pallet_data` AS C
            INNER JOIN TempPayloads AS T ON C.`WMS_STORAGE_REQUEST_PALLET_DATA_ID` = T.`id`
            SET C.PALLET_SCANNED_PAYLOAD_ID = T.`payload_id`;
            
            SELECT  `JSON_REQUEST` AS RESULT, 1 AS SUCCESS,`API_HEADERS` AS HEADERS,P.PAYLOAD_ID 
            FROM `wcs_to_wms_payload` P
            INNER JOIN TempPayloads T ON P.`PAYLOAD_ID` = T.`payload_id`;
        END IF;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_STORAGE_REQUEST_DELETE` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_STORAGE_REQUEST_DELETE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_STORAGE_REQUEST_DELETE`(IN Parameters JSON)
BEGIN
    DECLARE storageRequestId VARCHAR(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE gln VARCHAR(100);
    DECLARE palletId VARCHAR(36);
    DECLARE eventTimestamp DATETIME;
    DECLARE payloadId VARCHAR(36);
    DECLARE storageID VARCHAR(36);
    
    SET payloadId = UUID();
    
    
    SET gln = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Gln'));
    SET storageRequestId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.StorageRequestId'));
    SET storageID = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.StorageId')), '');
    
    CREATE TEMPORARY TABLE temp_invalid_data (
        ID INT AUTO_INCREMENT PRIMARY KEY,
        ERROR_MESSAGE VARCHAR(255)
    );
    
    INSERT INTO temp_invalid_data (ERROR_MESSAGE)
    SELECT CONCAT('Pallet ID ', storageID, ' already scanned.')
    FROM `wms_storage_request_pallet_data` wsrpd 
    WHERE wsrpd.`STORAGE_REQUEST_ID` = storageRequestId
    LIMIT 1;
   
    
    IF EXISTS (SELECT 1 FROM temp_invalid_data) THEN
        SELECT 0 AS SUCCESS, "VALIDATION FAILED" AS MESSAGE, ERROR_MESSAGE AS `DESCRIPTION` FROM temp_invalid_data;
    ELSE 
        IF storageID = '' THEN
            UPDATE `wms_storage_request_pallet_data` 
            SET `STORAGE_REQUEST_STATUS` = 'DELETED'
            WHERE `STORAGE_REQUEST_ID` = storageRequestId;
        ELSE
            UPDATE `wms_storage_request_data` 
            SET `STATUS` = 'DELETED'
            WHERE `STORAGE_REQUEST_ID` = storageRequestId;
        END IF;
        
        SELECT 1 AS SUCCESS, "DELETED SUCCESSFULLY" AS MESSAGE, '' AS `DESCRIPTION`;
    END IF;
    
    DROP TEMPORARY TABLE IF EXISTS temp_invalid_data;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_STORAGE_REQUEST_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_STORAGE_REQUEST_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_STORAGE_REQUEST_INSERT`(IN Parameters JSON)
BEGIN
    DECLARE storageRequestId VARCHAR(36);
    DECLARE _gln VARCHAR(100);
    DECLARE palletId VARCHAR(36);
    DECLARE eventTimestamp DATETIME;
    DECLARE payloadId VARCHAR(36);
    DECLARE v_storageRequestPalletData BIGINT;
    DECLARE v_errorMessage TEXT; 
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION  
    BEGIN  
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;  
        ROLLBACK;  
        SELECT 0 AS SUCCESS, 'FAILED DUE TO ERROR' AS MESSAGE, v_errorMessage AS RESULT;  
    END;
    
    SET payloadId = UUID();
    
    
    SET _gln = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Gln'));
    SET storageRequestId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.StorageRequestId'));
    SET palletId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.PalletId'));
    SET eventTimestamp = STR_TO_DATE(
        JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.EventTimestamp')), '%Y-%m-%dT%H:%i:%s.%fZ'
    );
    
    DROP TEMPORARY TABLE IF EXISTS temp_storage_request;
    DROP TEMPORARY TABLE IF EXISTS temp_invalid_data;
    
    CREATE TEMPORARY TABLE temp_storage_request (
        ID INT AUTO_INCREMENT PRIMARY KEY,
        STORAGE_REQUEST_ID VARCHAR(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        STORAGE_ID VARCHAR(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        ARTICLE_ID VARCHAR(255) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        QUANTITY INT,
        CLIENT_BATCH_ID VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        EXPIRY_DATE DATE,
        MRP DECIMAL(10,3),
        COUNTRY_OF_ORIGIN VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        PAYLOAD_ID VARCHAR(36) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    );
    
    INSERT INTO temp_storage_request (
        STORAGE_REQUEST_ID, STORAGE_ID, ARTICLE_ID, QUANTITY, CLIENT_BATCH_ID, EXPIRY_DATE, MRP, COUNTRY_OF_ORIGIN, PAYLOAD_ID
    )
    SELECT
        storageRequestId,
        storage_id,
        article_id,
        quantity,
        batch_id,
        expiry_date,
        mrp,
        country_of_origin,
        payloadId
    FROM JSON_TABLE(
        Parameters, 
        '$.PalletList[*]' 
        COLUMNS (
            storage_id VARCHAR(36) PATH '$.StorageId',
            article_id VARCHAR(255) PATH '$.ArticleId',
            quantity INT PATH '$.Quantity',
            batch_id VARCHAR(200) PATH '$.Traceability.BatchId',
            expiry_date DATE PATH '$.Traceability.ExpirationDate',
            mrp DECIMAL(10,3) PATH '$.Traceability.Mrp',
            country_of_origin VARCHAR(100) PATH '$.Traceability.CountryOfOrigin'
        )
    ) AS jt;
    
    CREATE TEMPORARY TABLE temp_invalid_data (
        ID INT AUTO_INCREMENT PRIMARY KEY,
        ERROR_MESSAGE VARCHAR(255)
    );
    
    CREATE TEMPORARY TABLE batch_id_map AS
	SELECT 
	    ARTICLE_ID,
	    CLIENT_BATCH_ID,
	    GLN,
	    MRP,
	    EXPIRY_DATE,
	    COUNTRY_OF_ORIGIN,
	    UUID() AS BATCH_ID
	FROM (
	    SELECT DISTINCT
		ARTICLE_ID,
		CLIENT_BATCH_ID,
		_gln AS GLN,
		MRP,
		EXPIRY_DATE,
		COUNTRY_OF_ORIGIN
	    FROM temp_storage_request temp
	    WHERE NOT EXISTS ( SELECT 1 FROM `sku_batch_master` sbm 
	    WHERE 
	     temp.ARTICLE_ID = sbm.`SKU_ID`
	     AND sbm.`GLN`=_gln 
	     AND sbm.CLIENT_BATCH_ID= temp.CLIENT_BATCH_ID
	     )
	) AS deduplicated;
	
	
    
    
    INSERT INTO temp_invalid_data (ERROR_MESSAGE)
    SELECT CONCAT('StorageRequest Id ', storageRequestId, ' is already processed')
    FROM `wms_to_wcs_storage_request_pallet_data` 
    WHERE STORAGE_REQUEST_ID = storageRequestId;
    
     INSERT INTO temp_invalid_data (ERROR_MESSAGE)
    SELECT CONCAT('StorageRequest Id ', storageRequestId, ' is already processed')
    FROM `wms_to_wcs_storage_request_pallet_data_Archive` 
    WHERE STORAGE_REQUEST_ID = storageRequestId;
    
    
    INSERT INTO temp_invalid_data (ERROR_MESSAGE)
    SELECT CONCAT('PalletId ', palletId, ' is already pending with StorageRequestId ',STORAGE_REQUEST_ID)
    FROM `wms_to_wcs_storage_request_pallet_data` 
    WHERE `PALLET_ID` = palletId and `STORAGE_REQUEST_STATUS`='PENDING';
    
   
    
    INSERT INTO temp_invalid_data (ERROR_MESSAGE)
    SELECT CONCAT('Storage Id ', tsr.STORAGE_ID, ' is already processed')
    FROM temp_storage_request tsr
    INNER JOIN `wms_to_wcs_storage_request_data` wsrpd ON tsr.STORAGE_ID = wsrpd.STORAGE_ID;
   
    
    INSERT INTO temp_invalid_data (ERROR_MESSAGE)
    SELECT CONCAT('Missing ARTICLE_ID: ', tsr.ARTICLE_ID)
    FROM temp_storage_request tsr
    LEFT JOIN `sku_master` sm ON tsr.ARTICLE_ID = sm.SKU_ID
    WHERE sm.SKU_ID IS NULL;
    
    IF EXISTS (SELECT 1 FROM temp_invalid_data) THEN
        SELECT 0 AS SUCCESS, "VALIDATION FAILED" AS MESSAGE, ERROR_MESSAGE AS `RESULT` FROM temp_invalid_data;
    ELSE 
        
        START TRANSACTION;
        
        
        INSERT INTO `wms_to_wcs_storage_request_pallet_data` (
            GLN, STORAGE_REQUEST_ID, PALLET_ID, STORAGE_REQUEST_STATUS
        ) VALUES (
            _gln, storageRequestId, palletId, 'PENDING'
        );
        
        SELECT  `WMS_STORAGE_REQUEST_PALLET_DATA_ID` INTO v_storageRequestPalletData 
        FROM `wms_to_wcs_storage_request_pallet_data`
        WHERE STORAGE_REQUEST_ID = storageRequestId 
        LIMIT 1;
        
        INSERT IGNORE INTO sku_batch_master (
	    SKU_ID, CLIENT_BATCH_ID,  GLN, BATCH_ID, MRP, EXPIRY_DATE, COUNTRY_OF_ORIGIN
		)
		SELECT  bim.ARTICLE_ID, bim.CLIENT_BATCH_ID,
		    bim.GLN, bim.BATCH_ID,
		    bim.MRP, bim.EXPIRY_DATE, bim.COUNTRY_OF_ORIGIN
		    FROM (
			SELECT 
			    bim.ARTICLE_ID,
			    bim.CLIENT_BATCH_ID,
			    bim.GLN,
			    bim.BATCH_ID,
			    bim.MRP,
			    bim.EXPIRY_DATE,
			    bim.COUNTRY_OF_ORIGIN,
			    DENSE_RANK() OVER(PARTITION BY ARTICLE_ID,CLIENT_BATCH_ID,GLN ORDER BY BATCH_ID) AS ARank
		FROM batch_id_map bim) bim WHERE bim.ARank=1;
		
		
        
        INSERT INTO `wms_to_wcs_storage_request_data` (
            `WMS_STORAGE_REQUEST_PALLET_DATA_ID`, STORAGE_REQUEST_ID, STORAGE_ID, ARTICLE_ID, QUANTITY, BATCH_ID, PAYLOAD_ID
        )
        SELECT  v_storageRequestPalletData, STORAGE_REQUEST_ID, STORAGE_ID, ARTICLE_ID, QUANTITY, sbm.batch_id, PAYLOAD_ID
        FROM temp_storage_request 
        INNER JOIN `sku_batch_master` sbm 
        ON (temp_storage_request.ARTICLE_ID = sbm.SKU_ID 
            AND temp_storage_request.CLIENT_BATCH_ID = sbm.CLIENT_BATCH_ID 
            aND sbm.GLN=_gln
           );
        
        COMMIT;
        
        SELECT 1 AS SUCCESS, "UPLOADED SUCCESSFULLY" AS MESSAGE, '' AS `RESULT`;
    END IF;
    
    DROP TEMPORARY TABLE IF EXISTS temp_storage_request;
    DROP TEMPORARY TABLE IF EXISTS temp_invalid_data;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_STORAGE_REQUEST_UPDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_STORAGE_REQUEST_UPDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_SERVICE_API_STORAGE_REQUEST_UPDATE`(IN Parameters JSON)
BEGIN
    DECLARE storageRequestId VARCHAR(36);
    DECLARE gln VARCHAR(100);
    DECLARE storageId VARCHAR(36);
    DECLARE containerBarcode VARCHAR(100);
    DECLARE articleId VARCHAR(50);
    DECLARE quantity INT;
    DECLARE eventTimestamp DATETIME;
    DECLARE payloadId VARCHAR(36);
    
    DECLARE batchId VARCHAR(50);
    DECLARE batchNumber VARCHAR(50);
    DECLARE expirationDate DATE;
    DECLARE mrp DECIMAL(10,2);
    DECLARE countryOfOrigin VARCHAR(10);
    
    SET payloadId = UUID();
    
    SET gln = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Gln'));
    SET storageRequestId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.StorageRequestId'));
    SET storageId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.StorageId'));
    SET containerBarcode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ContainerBarcode'));
    SET articleId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ArticleId'));
    SET quantity = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Quantity'));
    SET eventTimestamp = STR_TO_DATE(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.EventTimestamp')), '%Y-%m-%dT%H:%i:%s.%fZ');
    
    SET batchId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Traceability.BatchId'));
    SET batchNumber = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Traceability.BatchNumber'));
    SET expirationDate = STR_TO_DATE(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Traceability.ExpirationDate')), '%Y-%m-%d');
    SET mrp = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Traceability.Mrp'));
    SET countryOfOrigin = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Traceability.CountryOfOrigin'));
    
    CREATE TEMPORARY TABLE temp_invalid_data (
        ID INT AUTO_INCREMENT PRIMARY KEY,
        ERROR_MESSAGE VARCHAR(255)
    );
    
    IF NOT EXISTS (SELECT 1 FROM `wms_storage_request_data` WHERE `STORAGE_REQUEST_ID` = storageRequestId) THEN
        INSERT INTO temp_invalid_data (ERROR_MESSAGE)
        VALUES (CONCAT('Storage Request ID ', storageRequestId, ' does not exist.'));
    END IF;
    
    IF EXISTS (SELECT 1 FROM temp_invalid_data) THEN
        SELECT 0 AS SUCCESS, "VALIDATION FAILED" AS MESSAGE, ERROR_MESSAGE AS `DESCRIPTION` FROM temp_invalid_data;
    ELSE 
        
        UPDATE `wms_storage_request_data`
        SET `GLN` = gln,
            
            `CONTAINER_BARCODE` = containerBarcode,
            `ARTICLE_ID` = articleId,
            `QUANTITY` = quantity,
            `EVENT_TIMESTAMP` = eventTimestamp,
            
            `BATCH_ID` = batchId,
            `BATCH_NUMBER` = batchNumber,
            `EXPIRATION_DATE` = expirationDate,
            `MRP` = mrp,
            `COUNTRY_OF_ORIGIN` = countryOfOrigin
        WHERE `STORAGE_ID` = storageId;
        
        SELECT 1 AS SUCCESS, "UPDATED SUCCESSFULLY" AS MESSAGE, '' AS `DESCRIPTION`;
    END IF;
    
    DROP TEMPORARY TABLE IF EXISTS temp_invalid_data;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_UPDATE_PAYLOAD_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_UPDATE_PAYLOAD_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_UPDATE_PAYLOAD_STATUS`(IN PayloadId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci,IN JsonResponse TEXT,IN HttpStatus INT,IN Success BOOL)
BEGIN
	DECLARE is_processed INT DEFAULT -1;
	
	DECLARE i INT DEFAULT 0;
	
	
	IF (Success) THEN
		SET is_processed=1;
	END IF;
		UPDATE `wcs_to_wms_payload` SET
		`JSON_RESPONSE`= JsonResponse,
		`HTTP_STATUS`=HttpStatus,
		`IS_PROCESSED`=is_processed,
		`NO_OF_ATTEMPTS`=NO_OF_ATTEMPTS+1,
		`PROCESSED_TIMESTAMP`=NOW()
		 WHERE PAYLOAD_ID=PayloadId;
		
	 
	
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_API_WMS_PAYLOAD_ID_UPDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_API_WMS_PAYLOAD_ID_UPDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_API_WMS_PAYLOAD_ID_UPDATE`(IN Parameters JSON)
BEGIN
    DECLARE v_IsProcessed INT;
    
    SET v_IsProcessed = Parameters ->> '$.IsProcessed';
    
    UPDATE `wms_to_wcs_payload` w
    JOIN JSON_TABLE(
        Parameters, 
        "$.PayloadIdList[*]" 
        COLUMNS (payload_id VARCHAR(50) PATH "$")
    ) jt
    ON w.PAYLOAD_ID = jt.payload_id
    SET w.IS_PROCESSED = v_IsProcessed,
        w.PROCESSED_TIMESTAMP = NOW() where `IS_PROCESSED` =2;
   
    SELECT 1 AS Success;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_SERVICE_VALIDATE_CHECK_IDEMPOTENCY_KEY` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_SERVICE_VALIDATE_CHECK_IDEMPOTENCY_KEY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_SERVICE_VALIDATE_CHECK_IDEMPOTENCY_KEY`(
    IN Parameter1 VARCHAR(100)
)
BEGIN
    DECLARE idempotencyKey VARCHAR(50);
    DECLARE payload LONGTEXT;
    DECLARE RetryCounter INT DEFAULT 5;
    DECLARE existingStatus INT DEFAULT -2;
    DECLARE attempts INT DEFAULT 0;
    DECLARE jsonResponse LONGTEXT;
    DECLARE existingPayload LONGTEXT;
    DECLARE processedTimestamp DATETIME;

    
    DECLARE CONTINUE HANDLER FOR NOT FOUND
        SET existingStatus = -2;

    
    SET idempotencyKey = Parameter1;

    
    SELECT IS_PROCESSED,
           NO_OF_ATTEMPTS,
           JSON_RESPONSE,
           PROCESSED_TIMESTAMP
    INTO existingStatus,
         attempts,
         jsonResponse,
         processedTimestamp
    FROM `wms_to_wcs_payload`
    WHERE `IDEMPOTENCY_KEY` = idempotencyKey
    ORDER BY `PROCESSED_TIMESTAMP` DESC
    LIMIT 1;

    IF existingStatus = -2 THEN
        SELECT 'New Idempotency Id' AS Message, 1 AS Success;

    ELSEIF existingStatus = 1 THEN
        SELECT jsonResponse AS Message, 5 AS Success;

    ELSEIF existingStatus = -1 THEN
        SELECT 'Data can be Processed' AS Message, 4 AS Success;

    ELSE
        SELECT 'Data to be processed' AS Message, 4 AS Success;
    END IF;

END */$$
DELIMITER ;

/* Procedure structure for procedure `isautocaldone` */

/*!50003 DROP PROCEDURE IF EXISTS  `isautocaldone` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `isautocaldone`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
              SELECT `Auto Calibration Done` FROM `teleoperation_bool_data_feedback` WHERE BOT_ID= bot_id_;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `lm_SelectAisleWithY` */

/*!50003 DROP PROCEDURE IF EXISTS  `lm_SelectAisleWithY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `lm_SelectAisleWithY`(
	in aisleY INT
    )
BEGIN
		select * from location_master where type = 'AISLE_ENTRY' and `Y` = aisleY ORDER BY X;
 	END */$$
DELIMITER ;

/* Procedure structure for procedure `lm_SelectDynamicProperties` */

/*!50003 DROP PROCEDURE IF EXISTS  `lm_SelectDynamicProperties` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `lm_SelectDynamicProperties`()
BEGIN
    SELECT 
        XSTART AS XStart, 
        YSTART AS YStart, 
        XEND AS XEnd, 
        YEND AS YEnd, 
        PROPERTY 
    FROM `dynamic_property_master`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `lm_SelectHomesOfReturnAisle` */

/*!50003 DROP PROCEDURE IF EXISTS  `lm_SelectHomesOfReturnAisle` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `lm_SelectHomesOfReturnAisle`(
	in maxX INT,
	IN returnX INT,
	in returnY INT
    )
BEGIN
		select * from `location_master` where `TYPE`='HOME' AND `Y` = returnY and `X` > maxX and `X` < returnX ORDER BY `X`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `lm_SelectReturnAisleWithYnX` */

/*!50003 DROP PROCEDURE IF EXISTS  `lm_SelectReturnAisleWithYnX` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `lm_SelectReturnAisleWithYnX`(
	in returnY INT,
	IN returnX INT
    )
BEGIN
		select * from `location_master` where `TYPE` = 'RETURN_AISLE_ENTRY' and `Y`= returnY and `X` < returnX ORDER BY `X` LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `lm_SelectStationAtX` */

/*!50003 DROP PROCEDURE IF EXISTS  `lm_SelectStationAtX` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `lm_SelectStationAtX`(
    
	in stationX int
    )
BEGIN
		select * from location_master where X = stationX and TYPE IN ("STATION", "STATION_ENTRY");
	END */$$
DELIMITER ;

/* Procedure structure for procedure `lm_SelectStationEntryAtX` */

/*!50003 DROP PROCEDURE IF EXISTS  `lm_SelectStationEntryAtX` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `lm_SelectStationEntryAtX`(
    
	IN stationX INT
    )
BEGIN
		SELECT * FROM location_master WHERE X = stationX AND TYPE IN ("STATION_ENTRY");
	END */$$
DELIMITER ;

/* Procedure structure for procedure `lm_SelectStationPickAtX` */

/*!50003 DROP PROCEDURE IF EXISTS  `lm_SelectStationPickAtX` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `lm_SelectStationPickAtX`(
    
	IN stationX INT
    )
BEGIN
		SELECT * FROM location_master WHERE X = stationX AND TYPE IN ("STATION");
	END */$$
DELIMITER ;

/* Procedure structure for procedure `lm_SelectTowersAtX` */

/*!50003 DROP PROCEDURE IF EXISTS  `lm_SelectTowersAtX` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `lm_SelectTowersAtX`(
	in towerX int
    )
BEGIN
		select * from `location_master` where `TYPE` like '%TOWER%' AND `X` = towerX and `Z` = 0;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `lm_SelectTowersOfAisle` */

/*!50003 DROP PROCEDURE IF EXISTS  `lm_SelectTowersOfAisle` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `lm_SelectTowersOfAisle`(
	in aisleX int, 
	in aisleY int, 
	in nextAisleX INT
    )
BEGIN
		select * from `location_master` where `TYPE` LIKE '%TOWER%' AND `Y`= aisleY AND `X` > aisleX and `Z` = 0 AND `X` < nextAisleX ORDER BY `X`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ls_SelectPointFromID` */

/*!50003 DROP PROCEDURE IF EXISTS  `ls_SelectPointFromID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ls_SelectPointFromID`(
	in locationID int
    )
BEGIN
		select * from `location_master` where `LOCATION_ID` = locationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ls_SelectPointFromXYZ` */

/*!50003 DROP PROCEDURE IF EXISTS  `ls_SelectPointFromXYZ` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ls_SelectPointFromXYZ`(
	in pointX int,
	in pointY int,
	in pointZ int
    )
BEGIN
		select * from `location_master` where `X`=pointX and `Y`=pointY and `Z`=pointZ;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `make_home_to_station_costing` */

/*!50003 DROP PROCEDURE IF EXISTS  `make_home_to_station_costing` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `make_home_to_station_costing`(
    IN p_wx DECIMAL(10,4),
    IN p_wy DECIMAL(10,4),
    IN p_turn_penalty DECIMAL(10,4)
)
BEGIN
    DECLARE v_wx   DECIMAL(10,4);
    DECLARE v_wy   DECIMAL(10,4);
    DECLARE v_turn DECIMAL(10,4);

    SET SESSION group_concat_max_len = 1000000;
    SET v_wx   = IFNULL(p_wx, 1);
    SET v_wy   = IFNULL(p_wy, 1);
    SET v_turn = IFNULL(p_turn_penalty, 0);

    
    DROP TABLE IF EXISTS home_to_station_cost;
    CREATE TABLE home_to_station_cost (
        Station_ID       INT NOT NULL,
        Home_Location_ID INT NOT NULL,
        Home_Type        ENUM('HOME','STATION_HOME') NOT NULL,
        Cost             DECIMAL(18,6) NOT NULL,
        PRIMARY KEY (Station_ID, Home_Location_ID)
    ) ENGINE=INNODB;

    
    DROP TEMPORARY TABLE IF EXISTS station_xy;
    CREATE TEMPORARY TABLE station_xy AS
    SELECT 
        hsm.station_id,
        lm.location_id,
        CAST(lm.X AS DECIMAL(12,4)) AS X,
        CAST(lm.Y AS DECIMAL(12,4)) AS Y
    FROM location_master lm
    JOIN hw_station_master hsm 
        ON hsm.location_id = lm.location_id
    WHERE lm.TYPE = 'STATION'
      AND lm.X IS NOT NULL 
      AND lm.Y IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS aisle_xy;
    CREATE TEMPORARY TABLE aisle_xy AS
    SELECT 
        lm.location_id AS Home_Location_ID,
        lm.aisle_number,
        lm.type AS Home_Type,
        CAST(lm.X AS DECIMAL(12,4)) AS X,
        CAST(lm.Y AS DECIMAL(12,4)) AS Y
    FROM location_master lm
    WHERE lm.TYPE IN ('HOME','STATION_HOME')
      AND lm.X IS NOT NULL 
      AND lm.Y IS NOT NULL;

    
    INSERT INTO home_to_station_cost (Station_ID, Home_Location_ID, Home_Type, Cost)
    SELECT 
        st.station_id,
        h.Home_Location_ID,
        h.Home_Type,
        (v_wx * ABS(st.X - h.X))
      + (v_wy * ABS(st.Y - h.Y))
      + (CASE WHEN st.X <> h.X AND st.Y <> h.Y THEN v_turn ELSE 0 END) AS total_cost
    FROM aisle_xy h
    CROSS JOIN station_xy st;

    
    CREATE INDEX idx_station ON home_to_station_cost (Station_ID);
    CREATE INDEX idx_home    ON home_to_station_cost (Home_Location_ID);

    
    DROP TEMPORARY TABLE IF EXISTS station_xy;
    DROP TEMPORARY TABLE IF EXISTS aisle_xy;
END */$$
DELIMITER ;

/* Procedure structure for procedure `make_station_to_aisle_costing` */

/*!50003 DROP PROCEDURE IF EXISTS  `make_station_to_aisle_costing` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `make_station_to_aisle_costing`(
    IN p_wx DECIMAL(10,4),
    IN p_wy DECIMAL(10,4),
    IN p_turn_penalty DECIMAL(10,4)
)
BEGIN
  DECLARE v_wx   DECIMAL(10,4);
  DECLARE v_wy   DECIMAL(10,4);
  DECLARE v_turn DECIMAL(10,4);
 
  SET SESSION group_concat_max_len = 1000000;
  SET v_wx   = IFNULL(p_wx, 1);
  SET v_wy   = IFNULL(p_wy, 1);
  SET v_turn = IFNULL(p_turn_penalty, 0);
 
  
  DROP TABLE IF EXISTS station_to_aisle_cost;
  CREATE TABLE station_to_aisle_cost (
      Station_ID INT NOT NULL,
      Aisle_Number VARCHAR(50) NOT NULL,
      Cost DECIMAL(18,6) NOT NULL,
      PRIMARY KEY (Station_ID, Aisle_Number)
  ) ENGINE=INNODB;
 
  
  DROP TEMPORARY TABLE IF EXISTS station_xy;
  CREATE TEMPORARY TABLE station_xy AS
  SELECT 
      hsm.station_id,
      lm.location_id,
      CAST(lm.X AS DECIMAL(12,4)) AS X,
      CAST(lm.Y AS DECIMAL(12,4)) AS Y
  FROM location_master lm
  JOIN hw_station_master hsm ON hsm.location_id = lm.location_id
  WHERE lm.TYPE = 'STATION'
    AND lm.X IS NOT NULL AND lm.Y IS NOT NULL;
 
  DROP TEMPORARY TABLE IF EXISTS aisle_xy;
  CREATE TEMPORARY TABLE aisle_xy AS
  SELECT 
      lm.location_id AS aisle_id,
      lm.aisle_number,
      CAST(lm.X AS DECIMAL(12,4)) AS X,
      CAST(lm.Y AS DECIMAL(12,4)) AS Y
  FROM location_master lm
  WHERE lm.TYPE = 'AISLE_ENTRY'
    AND lm.X IS NOT NULL AND lm.Y IS NOT NULL;
 
  
  INSERT INTO station_to_aisle_cost (Station_ID, Aisle_Number, Cost)
  SELECT 
      s.station_id,
      a.aisle_number,
      (v_wx * ABS(s.X - a.X))
    + (v_wy * ABS(s.Y - a.Y))
    + (CASE WHEN s.X <> a.X AND s.Y <> a.Y THEN v_turn ELSE 0 END) AS total_cost
  FROM station_xy s
  CROSS JOIN aisle_xy a;
 
  
  CREATE INDEX idx_station ON station_to_aisle_cost (Station_ID);
  CREATE INDEX idx_aisle ON station_to_aisle_cost (Aisle_Number);
 
  
  DROP TEMPORARY TABLE IF EXISTS station_xy;
  DROP TEMPORARY TABLE IF EXISTS aisle_xy;
END */$$
DELIMITER ;

/* Procedure structure for procedure `nfm_SelectEnabledBots` */

/*!50003 DROP PROCEDURE IF EXISTS  `nfm_SelectEnabledBots` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `nfm_SelectEnabledBots`()
BEGIN
		Select * from `bot_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_AutoRecoveryAcknowledgementzero` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_AutoRecoveryAcknowledgementzero` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_AutoRecoveryAcknowledgementzero`(IN AutoRecoveryDoneBit INT, 
IN _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
	       
               UPDATE `teleoperation_bool_data` SET `Auto Recovery Acknowledgement` = '0',
                          `Auto Recovery Complete` =  AutoRecoveryDoneBit,`Auto Recovery End Edge` = '0' WHERE `bot_id` = _bot_id;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_AutoRecoveryDone` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_AutoRecoveryDone` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_AutoRecoveryDone`(IN AutoRecoveryDoneBit INT, IN _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
	       
               UPDATE `teleoperation_bool_data` SET `Auto Recovery Complete` = AutoRecoveryDoneBit,`Auto Recovery End Edge` = '0' WHERE `bot_id` = _bot_id;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_BotCalibratingOrNot` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_BotCalibratingOrNot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_BotCalibratingOrNot`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
                 SELECT COUNT(`TASK_ID`) FROM `task_master` WHERE BOT_ID= bot_id_ AND `task_type` = 'BOT_AUTO_CALIBRATION'
               AND `STATUS` = 'PROCESSING';   
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_ChangeAutomanualStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_ChangeAutomanualStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_ChangeAutomanualStatus`(IN _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
	       
               UPDATE `bot_master` SET `auto_manual` = 'manual' WHERE `bot_id` = _bot_id AND `auto_manual` = 'auto';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_CheckBotMaintenanceCleared` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_CheckBotMaintenanceCleared` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_CheckBotMaintenanceCleared`(
    IN botID VARCHAR(50)
)
BEGIN
    DECLARE maintenanceLocationId INT;
    
    
    SELECT lm.LOCATION_ID INTO maintenanceLocationId
    FROM location_master lm
    INNER JOIN robot_master rm ON rm.CUR_LOCATION = lm.LOCATION_ID
    WHERE rm.BOT_ID = botID
        AND lm.PROPERTY_DESCRIPTION = 'MTNC'
    LIMIT 1;
    
    
    IF maintenanceLocationId IS NOT NULL THEN
        SELECT
            CASE 
                WHEN mtm.IS_MP_BOT_HEALTHY = 1 THEN 1
                ELSE 0
            END AS IS_CLEARED
        FROM maintenance_task_master AS mtm
        LEFT JOIN hw_maintenance_master AS hmm
            ON mtm.MAINTENANCE_ID = hmm.MAINTENANCE_ID
        WHERE mtm.MAINTENANCE_POINT_BOT_ID = botID
            AND hmm.MAINTENANCE_POINT_LOCATION_ID = maintenanceLocationId
        ORDER BY mtm.INSERTED_TIMESTAMP DESC
        LIMIT 1;
    ELSE
        
        SELECT 1 AS IS_CLEARED;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_completetaskdetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_completetaskdetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_completetaskdetail`(
    IN taskDetailID INT)
BEGIN
               UPDATE task_detail
               SET 
                   `UPDATED_TIMESTAMP`= NOW(), `END_TIME`=now() , STATUS="COMPLETED" WHERE `TASK_DETAIL_ID`=taskDetailID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_DeleteAndArchiveStepsWithTaskDetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_DeleteAndArchiveStepsWithTaskDetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_DeleteAndArchiveStepsWithTaskDetail`(
	in taskDetailID int
    )
BEGIN
		INSERT INTO steps_archive (
		    TASK_DETAIL_ID,
		    BOT_ID,
		    X,
		    Y,
		    Z,
		    PROPERTY,
		    COUNTER,
		    LAST_SENT_TIMESTAMP,
		    IS_COMPLETED,
		    PICK_PUT,
		    IS_COMPLETED_TIMESTAMP,
		    INSERT_TIME,
		    DISTANCE_FROM_LAST_STEP
		)
		SELECT 
		    TASK_DETAIL_ID,
		    BOT_ID,
		    X,
		    Y,
		    Z,
		    PROPERTY,
		    COUNTER,
		    LAST_SENT_TIMESTAMP,
		    IS_COMPLETED,
		    PICK_PUT,
		    IS_COMPLETED_TIMESTAMP,
		    INSERT_TIME,
		    DISTANCE_FROM_LAST_STEP
		FROM steps
		WHERE TASK_DETAIL_ID = taskDetailID AND IS_COMPLETED = 1;
		Delete from steps where TASK_DETAIL_ID = taskDetailID and IS_COMPLETED = 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_deleteOrderBinMappingUsingOrderBinid` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_deleteOrderBinMappingUsingOrderBinid` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_deleteOrderBinMappingUsingOrderBinid`(IN orderBinID INT)
BEGIN
		DELETE FROM `order_bin_mapping` WHERE `ORDER_BIN_ID` = orderBinID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_DeleteStepsTaskDetailTaskMasterWithBotId` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_DeleteStepsTaskDetailTaskMasterWithBotId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_DeleteStepsTaskDetailTaskMasterWithBotId`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
                INSERT INTO steps_archive (
		    TASK_DETAIL_ID,
		    BOT_ID,
		    X,
		    Y,
		    Z,
		    PROPERTY,
		    COUNTER,
		    LAST_SENT_TIMESTAMP,
		    IS_COMPLETED,
		    PICK_PUT,
		    IS_COMPLETED_TIMESTAMP,
		    INSERT_TIME,
		    DISTANCE_FROM_LAST_STEP
		)
		SELECT 
		    TASK_DETAIL_ID,
		    BOT_ID,
		    X,
		    Y,
		    Z,
		    PROPERTY,
		    COUNTER,
		    LAST_SENT_TIMESTAMP,
		    IS_COMPLETED,
		    PICK_PUT,
		    IS_COMPLETED_TIMESTAMP,
		    INSERT_TIME,
		    DISTANCE_FROM_LAST_STEP
		FROM steps
		WHERE BOT_ID = botId;
		
		
	INSERT INTO task_detail_log (
		TASK_DETAIL_ID,
		TASK_MASTER_ID,
		BOT_ID,
		START_LOCATION_ID,
		END_LOCATION_ID,
		STATUS,
		START_PICK_PUT_SIDE,
		START_Z,
		END_PICK_PUT_SIDE,
		END_Z,
		START_TIME,
		END_TIME,
		UPDATED_TIMESTAMP,
		TASK_DETAIL_TYPE,
		IS_TOWER_BUFFER,
		IS_STEPS_INSERTED,
		COUNT_OF_STEPS,
		COUNT_OF_STEPS_SENT,
		INSERTED_TIMESTAMP,
		LOGGED_TIMESTAMP
	)
	SELECT 
		TASK_DETAIL_ID,
		TASK_MASTER_ID,
		BOT_ID,
		START_LOCATION_ID,
		END_LOCATION_ID,
		STATUS,
		START_PICK_PUT_SIDE,
		START_Z,
		END_PICK_PUT_SIDE,
		END_Z,
		START_TIME,
		END_TIME,
		UPDATED_TIMESTAMP,
		TASK_DETAIL_TYPE,
		IS_TOWER_BUFFER,
		IS_STEPS_INSERTED,
		COUNT_OF_STEPS,
		COUNT_OF_STEPS_SENT,
		INSERTED_TIMESTAMP,
		NOW(3)
	FROM task_detail
	WHERE BOT_ID = botId;
	
	INSERT INTO task_master_log (
		TASK_ID,
		BOT_ID,
		FROM_LOCATION_ID,
		DESTINATION_LOCATION_ID,
		STATUS,
		START_TIME,
		END_TIME,
		TASK_TYPE,
		UPDATED_TIMESTAMP,
		INSERTED_TIMESTAMP,
		LOGGED_TIMESTAMP
	)
	SELECT 
		TASK_ID,
		BOT_ID,
		FROM_LOCATION_ID,
		DESTINATION_LOCATION_ID,
		STATUS,
		START_TIME,
		END_TIME,
		TASK_TYPE,
		UPDATED_TIMESTAMP,
		INSERTED_TIMESTAMP,
		NOW(3)
	FROM task_master
	WHERE BOT_ID = botId;
	
	DELETE FROM steps WHERE BOT_ID = botId;
        DELETE FROM task_detail WHERE BOT_ID = botId;
	DELETE FROM task_master WHERE BOT_ID = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_deletetaskstep` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_deletetaskstep` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_deletetaskstep`(
    IN taskMasterID INT,
    IN taskDetailID INT
    )
BEGIN
        delete from steps where `TASK_DETAIL_ID`=taskDetailID;
        DELETE FROM task_detail WHERE `TASK_MASTER_ID`= taskMasterID and `TASK_DETAIL_ID`=taskDetailID;
 END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetAutoCalBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetAutoCalBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetAutoCalBit`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
              SELECT `Auto Calibration On` FROM `teleoperation_bool_data_feedback` WHERE BOT_ID= bot_id_;             
             
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_getAutoStartBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_getAutoStartBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_getAutoStartBit`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		select `Auto Start Feedback` from `teleoperation_bool_data_feedback` where bot_id = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_getbarcodenumberfromxy` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_getbarcodenumberfromxy` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_getbarcodenumberfromxy`( _X INT, _Y INT)
BEGIN
SELECT `BARCODE_NUMBER` FROM LOCATION_MASTER WHERE X=_X AND Y=_Y AND IS_BARCODE=1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_getbatterypercentage` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_getbatterypercentage` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_getbatterypercentage`(
      in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
 )
BEGIN
                select `AH_REMAINING_NORMAL` from `bot_master` where `BOT_ID`=botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetBotAutoManualStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetBotAutoManualStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetBotAutoManualStatus`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		select `AUTO_MANUAL` from `bot_master` where BOT_ID = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetBotHomeStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetBotHomeStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetBotHomeStatus`(
      IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
 )
BEGIN
      SELECT `Home OK Feedback` FROM `teleoperation_bool_data_feedback` WHERE `BOT_ID`=bot_id_;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetBotIdByRecoveryBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetBotIdByRecoveryBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetBotIdByRecoveryBit`(
	IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		
	select RECOVERY_BIT from bot_master where BOT_ID = CONVERT(bot_id_ USING latin1) COLLATE latin1_swedish_ci ;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetBotXYZ` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetBotXYZ` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetBotXYZ`(in _robotId varchar(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		select `GRIDX` , `GRIDY` , `GRIDZ` from bot_master where BOT_ID = _robotId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetGearCheckStartbit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetGearCheckStartbit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `rm_GetGearCheckStartbit`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
              SELECT `Gearbox_Health_Check_Start` FROM `teleoperation_bool_data` WHERE BOT_ID= bot_id_;             
             
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetGeardonebit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetGeardonebit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `rm_GetGeardonebit`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
              SELECT `Gear Box Health Check Completed` FROM `teleoperation_bool_data_feedback` WHERE BOT_ID= bot_id_;             
             
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_getLastLocationOnInitiation` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_getLastLocationOnInitiation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_getLastLocationOnInitiation`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		select `GRIDX`,`GRIDY`,`GRIDZ` from bot_master where `BOT_ID` = botID limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetLoadNonRecoveryBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetLoadNonRecoveryBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetLoadNonRecoveryBit`(
	IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		
	SELECT LOAD_NON_RECOVERY_BIT FROM bot_master WHERE BOT_ID = CONVERT(bot_id_ USING latin1) COLLATE latin1_swedish_ci ;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetLocationIdforpickputStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetLocationIdforpickputStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetLocationIdforpickputStation`(IN xcoordinateAgentScaled INT, IN ycoordinateAgentScaled INT, IN zcoordinateAgentScaled INT,IN _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
       
       SELECT LOCATION_ID FROM `location_master` WHERE `x`= xcoordinateAgentScaled and `y`=ycoordinateAgentScaled and `z`=zcoordinateAgentScaled;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetNearestGreaterZValue` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetNearestGreaterZValue` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetNearestGreaterZValue`(in zcoordinateAgentScaled double,in _bot_id varchar(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		select distinct z from location_master where z >= zcoordinateAgentScaled order by z asc LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetNonRecoveryBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetNonRecoveryBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetNonRecoveryBit`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		select NON_RECOVERY_BIT from bot_master where bot_id = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetRobotTeleoperationNumericData` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetRobotTeleoperationNumericData` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetRobotTeleoperationNumericData`(botId varchar(30))
BEGIN
		
		    SELECT * FROM `teleoperation_numeric_data` where bot_id = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetTeleoperationBoolData` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetTeleoperationBoolData` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetTeleoperationBoolData`(RobotCurrentMode BOOLEAN, steps_completion INT, botId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		  DECLARE bits TEXT DEFAULT '';
		    DECLARE data1 VARCHAR(100);
		    DECLARE data2 VARCHAR(100);
		    DECLARE data3 VARCHAR(100);
		    DECLARE data4 VARCHAR(100);
		    DECLARE data5 VARCHAR(8);
		    DECLARE data6 VARCHAR(8);
		    DECLARE data7 VARCHAR(8);
		    DECLARE data8 VARCHAR(8);
		    DECLARE data9 VARCHAR(8);
		    DECLARE data10 VARCHAR(8) DEFAULT '00000000';
		    DECLARE data11 VARCHAR(8) DEFAULT '00000000';
		    DECLARE data12 VARCHAR(8) DEFAULT '00000000';
		    DECLARE data13 VARCHAR(8) DEFAULT '00000000';
		    DECLARE data14 VARCHAR(8) DEFAULT '00000000';
		    DECLARE data15 VARCHAR(8) DEFAULT '00000000';
			
		    IF RobotCurrentMode = TRUE THEN
		    BEGIN
			
			SELECT
			    CONCAT(
				CAST(`Bot at Y Track for Home` AS UNSIGNED),
				CAST(`Rev Direction for Home` AS UNSIGNED),
				CAST(`Bin Load Status` AS UNSIGNED),
				CAST(`Emergency Stop` AS UNSIGNED),
				CAST(`Auto Start Bit` AS UNSIGNED),
				CAST(`Alarm Reset Bit` AS UNSIGNED),
				CAST(`Global Pause Bit` AS UNSIGNED),
				CAST(`Auto Home Call Bit` AS UNSIGNED)
			    )
			INTO data1
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			SELECT
			    CONCAT(
				'0',
				CAST(`slider_recovery_fail_acknowledge` AS UNSIGNED),
				CAST(`slider_recovery_acknowledge` AS UNSIGNED),
				CAST(`Auto Recovery Complete` AS UNSIGNED),
				CAST(`Auto Recovery End Edge` AS UNSIGNED),
				CAST(`Auto Recovery Acknowledgement` AS UNSIGNED),
				CAST(`Gearbox_Health_Check_Start` AS UNSIGNED),  
				CAST(`Auto Calibration Start` AS UNSIGNED)
			    )
			INTO data2
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			SELECT
			    CONCAT(
				'0',
				'0',
				'0',
				'0',
				'0',
				'0',
				CAST(`Interruption and erasure of all pending steps` AS UNSIGNED),
				CAST(`Execution, followed by erasure of all subsequent steps` AS UNSIGNED)
			    )
			INTO data3
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			SELECT
			    CONCAT(
				'0',
				'0',
				'0',
				'0',
				'0',
				'0',
				'0',
				'0'
			    )
			INTO data4
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			SET bits = CONCAT(data1, data2, data3, data4);
		    END;
		    ELSE
		    BEGIN
			
			
			SELECT
			    CONCAT(		
				CAST(`X-Axis Position Manual Run` AS UNSIGNED),
				CAST(`Y-Axis Position Manual Run` AS UNSIGNED),
				CAST(`Camera Trigger Bit` AS UNSIGNED),
				CAST(`Alarm Reset Bit` AS UNSIGNED),
				CAST(`BIN LOAD STATUS` AS UNSIGNED), 
				'0', 
				CAST(`Emergency Stop` AS UNSIGNED), 
				CAST(`All servos disable` AS UNSIGNED) 
			    )
			INTO data1
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			
			SELECT
			    CONCAT(
			        CAST(`Z-Axis Jog Down` AS UNSIGNED),
				CAST(`Z-Axis Jog Up` AS UNSIGNED),
				CAST(`Z-Jog Operation Limits Overwrite Acknowledge` AS UNSIGNED),
				CAST(`Z-Jog Operation Limits Overwrite Bit` AS UNSIGNED),
				CAST(`Rear Finger Actuator on/off` AS UNSIGNED),
				CAST(`Front Finger Actuator on/off` AS UNSIGNED),
				CAST(`Slider-Axis Position Manual Run` AS UNSIGNED),
				CAST(`Lift-Axis Position Manual Run` AS UNSIGNED)
		
			    )
			INTO data2
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			
			
			
			SELECT
			    CONCAT(
			        CAST(`Alarm Bypass-8 (Alarm code -70)` AS UNSIGNED),
				CAST(`Alarm Bypass-7 (Alarm code -48)` AS UNSIGNED),
				CAST(`Alarm Bypass-6 (Alarm code -47)` AS UNSIGNED),
				CAST(`Alarm Bypass-5 (Alarm code -35)` AS UNSIGNED),
				CAST(`Alarm Bypass-4 (Alarm code -26)` AS UNSIGNED),
				CAST(`Alarm Bypass-3 (Alarm code -24)` AS UNSIGNED),
				CAST(`Alarm Bypass-2 (Alarm code -22)` AS UNSIGNED),
				CAST(`Alarm Bypass-1 (Alarm code -1)` AS UNSIGNED)
				)
			INTO data3
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			
			SELECT
			    CONCAT(
				'0',
				'0',
				'0',
				'0',
				CAST(`Alarm Bypass-12` AS UNSIGNED),
				CAST(`Alarm Bypass-11` AS UNSIGNED),
				CAST(`Alarm Bypass-10` AS UNSIGNED),
				CAST(`Alarm Bypass-9 (Alarm code -77)` AS UNSIGNED)
			    )
			INTO data4
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			
			SELECT
			    CONCAT(
				'0',
				'0', 
				'0',
				'0', 
				'0', 
				'0',
				'0',
				'0'
			    )
			INTO data5
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			
			
			SELECT
			    CONCAT(
				'0',
				'0',
				'0',
				'0',
				'0',
				'0',
				'0',
				'0'
			    )
			INTO data6
			FROM teleoperation_bool_data
			WHERE bot_id = botId;
			
			SET bits = CONCAT(data1, data2, data3, data4, data5, data6);
		    END;
		    END IF;
		    SELECT bits AS bits;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_GetUncompletedSteps` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_GetUncompletedSteps` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_GetUncompletedSteps`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		declare isCount TINYINT(1);
		
		SET isCount = (SELECT COUNT(*) FROM steps WHERE `BOT_ID` = botId AND LAST_SENT_TIMESTAMP IS NOT NULL AND IS_COMPLETED = 0) > 0;
		select isCount;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_HandleCompletedStepsBatch` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_HandleCompletedStepsBatch` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_HandleCompletedStepsBatch`(
    IN in_task_detail_id INT
)
BEGIN
    DECLARE done_steps INT;
    SELECT COUNT(*) INTO done_steps
    FROM steps
    WHERE TASK_DETAIL_ID = in_task_detail_id
      AND IS_COMPLETED = 1;
    
    IF done_steps >= 10 THEN
        INSERT INTO steps_archive (
		    TASK_DETAIL_ID,
		    BOT_ID,
		    X,
		    Y,
		    Z,
		    PROPERTY,
		    COUNTER,
		    LAST_SENT_TIMESTAMP,
		    IS_COMPLETED,
		    PICK_PUT,
		    IS_COMPLETED_TIMESTAMP,
		    INSERT_TIME,
		    DISTANCE_FROM_LAST_STEP
		)
		SELECT 
		    TASK_DETAIL_ID,
		    BOT_ID,
		    X,
		    Y,
		    Z,
		    PROPERTY,
		    COUNTER,
		    LAST_SENT_TIMESTAMP,
		    IS_COMPLETED,
		    PICK_PUT,
		    IS_COMPLETED_TIMESTAMP,
		    INSERT_TIME,
		    DISTANCE_FROM_LAST_STEP
		FROM steps
		WHERE TASK_DETAIL_ID = taskDetailID AND IS_COMPLETED = 1 ORDER BY IS_COMPLETED_TIMESTAMP LIMIT 10;
		DELETE FROM steps WHERE TASK_DETAIL_ID = taskDetailID AND IS_COMPLETED = 1 ORDER BY IS_COMPLETED_TIMESTAMP LIMIT 10;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_InsertAlarmCodeOnAlarm` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_InsertAlarmCodeOnAlarm` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `rm_InsertAlarmCodeOnAlarm`(IN alarmCode INT, IN botID VARCHAR(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci, IN alarmType VARCHAR(20))
BEGIN
  DECLARE v_gridx INT;
    DECLARE v_gridy INT;
    DECLARE v_gridz INT;
    
     SELECT GRIDX, GRIDY, GRIDZ
      INTO v_gridx, v_gridy, v_gridz
      FROM bot_master
     WHERE BOT_ID = botID
     LIMIT 1;
     
    IF alarmType = 'NORMAL' THEN
        INSERT INTO bot_alarm_log (
            BOT_ID,
            ALARM_CODE,
            ALARM_DESCRIPTION,
            TASK_TYPE,
            ALARMPOSITION_X,
            ALARMPOSITION_Y,
            ALARMPOSITION_Z
        )
        SELECT
            botId                        AS BOT_ID,
            alarmCode                    AS ALARM_CODE,
            am.ALARM_DESCRIPTION         AS ALARM_DESCRIPTION,
            (
                SELECT tm.TASK_TYPE
                FROM task_master tm
                WHERE tm.BOT_ID = botId AND STATUS="PROCESSING" ORDER BY tm.`INSERTED_TIMESTAMP` DESC LIMIT 1
            )                           AS TASK_TYPE,
            (SELECT bm.GRIDX FROM bot_master bm WHERE bm.BOT_ID = botId) AS ALARMPOSITION_X,
            (SELECT bm.GRIDY FROM bot_master bm WHERE bm.BOT_ID = botId) AS ALARMPOSITION_Y,
            (SELECT bm.GRIDZ FROM bot_master bm WHERE bm.BOT_ID = botId) AS ALARMPOSITION_Z
        FROM alarm_master am
        WHERE am.ALARM_CODE = alarmCode
          AND am.ALARM_TYPE = alarmType;
          
           UPDATE bot_master
           SET ALARM_TIMESTAMP = NOW(),
               ALARM_POSITION_X_Y_Z = CONCAT(v_gridx, ',', v_gridy, ',', v_gridz)
            WHERE BOT_ID = botId;

    ELSEIF alarmType = 'MAINTENANCE' THEN
        INSERT INTO maintenance_alarm_logs (
            BOT_ID,
            ALARM_CODE,
            ALARM_DESCRIPTION,
            TASK_TYPE,
            ALARMPOSITION_X,
            ALARMPOSITION_Y,
            ALARMPOSITION_Z
        )
        SELECT
            botId                        AS BOT_ID,
            alarmCode                    AS ALARM_CODE,
            am.ALARM_DESCRIPTION         AS ALARM_DESCRIPTION,
            (
                SELECT tm.TASK_TYPE
                FROM task_master tm
                WHERE tm.BOT_ID = botId AND STATUS="PROCESSING" ORDER BY tm.`INSERTED_TIMESTAMP` DESC LIMIT 1
            )                             AS TASK_TYPE,
            (SELECT bm.GRIDX FROM bot_master bm WHERE bm.BOT_ID = botId) AS ALARMPOSITION_X,
            (SELECT bm.GRIDY FROM bot_master bm WHERE bm.BOT_ID = botId) AS ALARMPOSITION_Y,
            (SELECT bm.GRIDZ FROM bot_master bm WHERE bm.BOT_ID = botId) AS ALARMPOSITION_Z
        FROM alarm_master am
        WHERE am.ALARM_CODE = alarmCode
          AND am.ALARM_TYPE = alarmType;
          
           UPDATE bot_master 
           SET ALARM_TIMESTAMP = NOW(),
               ALARM_POSITION_X_Y_Z = CONCAT(v_gridx, ',', v_gridy, ',', v_gridz)
           WHERE BOT_ID = botId;

     ELSEIF alarmType = 'PSEUDO' THEN
        INSERT INTO pseudo_bot_alarm_log (
            BOT_ID,
            ALARM_CODE,
            ALARM_DESCRIPTION,
            TASK_TYPE,
            BIN_ID,
            ALARMPOSITION_X,
            ALARMPOSITION_Y,
            ALARMPOSITION_Z
        )
        SELECT
            botId                        AS BOT_ID,
            alarmCode                    AS ALARM_CODE,
            am.ALARM_DESCRIPTION         AS ALARM_DESCRIPTION,
            (
                SELECT tm.TASK_TYPE
                FROM task_master tm
                WHERE tm.BOT_ID = botId AND STATUS="PROCESSING" ORDER BY tm.`INSERTED_TIMESTAMP` DESC LIMIT 1
            )                           AS TASK_TYPE,
            (SELECT obm.BIN_ID FROM `order_bin_mapping` obm WHERE obm.BOT_ID = botId AND obm.STATUS IN ('BIN_PICKED','TASK_ALLOCATED','OPERATION_COMPLETD') ORDER BY obm.`INSERTED_TIMESTAMP` DESC LIMIT 1) AS BIN_ID,
            (SELECT bm.GRIDX FROM bot_master bm WHERE bm.BOT_ID = botId) AS ALARMPOSITION_X,
            (SELECT bm.GRIDY FROM bot_master bm WHERE bm.BOT_ID = botId) AS ALARMPOSITION_Y,
            (SELECT bm.GRIDZ FROM bot_master bm WHERE bm.BOT_ID = botId) AS ALARMPOSITION_Z
        FROM `alarm_master` am
        WHERE am.ALARM_CODE = alarmCode
          AND am.ALARM_TYPE = alarmType; 
          
            UPDATE bot_master 
           SET ALARM_TIMESTAMP = NOW(),
               ALARM_POSITION_X_Y_Z = CONCAT(v_gridx, ',', v_gridy, ',', v_gridz)
            WHERE BOT_ID = botId;

    ELSE
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid alarmType provided';
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_InsertBotIdAndMaintenanceIdInMaintenanceTaskMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_InsertBotIdAndMaintenanceIdInMaintenanceTaskMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_InsertBotIdAndMaintenanceIdInMaintenanceTaskMaster`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci, IN maintenanceId INT)
BEGIN
		
		INSERT INTO `maintenance_task_master`(`MAINTENANCE_ID`,`MAINTENANCE_POINT_BOT_ID`) 
		VALUES(maintenanceId, botId);
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_InsertIntoSteps` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_InsertIntoSteps` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_InsertIntoSteps`(
	IN stepx INT,
	IN stepy INT,
	IN stepz DOUBLE,
	IN stepProperty INT,
	IN stepCounter INT,
	IN stepTaskDetailID INT,
	IN stepBotID VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN pickPut VARCHAR(50),
	IN distanceFromLastStep INT
)
BEGIN
    
    INSERT INTO steps(`X`, `Y`, `Z`, `PROPERTY`, `COUNTER`, `TASK_DETAIL_ID`, `BOT_ID`, `PICK_PUT`, `DISTANCE_FROM_LAST_STEP`) 
    VALUES (stepx, stepy, stepz, stepProperty, stepCounter, stepTaskDetailID, stepBotID, pickPut, distanceFromLastStep)
    ON DUPLICATE KEY UPDATE
        `X` = VALUES(`X`),
        `Y` = VALUES(`Y`),
        `Z` = VALUES(`Z`),
        `PROPERTY` = VALUES(`PROPERTY`),
        `BOT_ID` = VALUES(`BOT_ID`),
        `PICK_PUT` = VALUES(`PICK_PUT`),
        `DISTANCE_FROM_LAST_STEP` = VALUES(`DISTANCE_FROM_LAST_STEP`);
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_insertManualAlarmOrUpdateExisting` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_insertManualAlarmOrUpdateExisting` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_insertManualAlarmOrUpdateExisting`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci, in differenceIndex int)
BEGIN
		declare alarmDescription text;
		DECLARE alarmID INT;
			IF EXISTS (
			 SELECT 1 
			 FROM bot_manual_alarm_log 
			 WHERE RECOVERY_TIMESTAMP is  NULL 
			 AND ALARM_CODE = differenceIndex 
			 AND BOT_ID = botId
			) 
		then 
			 update bot_manual_alarm_log set RECOVERY_TIMESTAMP = now() where RECOVERY_TIMESTAMP is null and ALARM_CODE = differenceIndex and BOT_ID = botId;
		else
			SELECT ALARM_ID, AlARM_DESCRIPTION INTO alarmID, alarmDescription FROM manual_alarm_master WHERE ALARM_CODE = differenceIndex;
			insert into `bot_manual_alarm_log`(BOT_ID, ALARM_CODE,ALARM_ID, ALARM_DESCRIPTION, INSERTED_TIMESTAMP) values(botId, differenceIndex, alarmID, alarmDescription, now());
		end if;		
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_Isbarcode` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_Isbarcode` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_Isbarcode`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    SELECT `GRIDX`,`GRIDY`,`GRIDZ` from `bot_master` bm
    WHERE bm.`BOT_ID` = bot_id_;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_IsEdgeFromLocationMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_IsEdgeFromLocationMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_IsEdgeFromLocationMaster`(IN xcoordinateAgentScaled INT, IN ycoordinateAgentScaled INT, IN zcoordinateAgentScaled INT)
BEGIN
              SELECT IS_EDGE FROM `location_master` WHERE `x`= xcoordinateAgentScaled AND `y`=ycoordinateAgentScaled AND `z`=zcoordinateAgentScaled;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_NonRecoverSubControllers` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_NonRecoverSubControllers` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_NonRecoverSubControllers`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in locationID int
    )
BEGIN
		update `subcontroller_reservations_master` set `IS_BUFFER` = 0, `DESTINATION_ID` = `LOCATION_ID` 
		where `BOT_ID` = botID and `LOCATION_ID` = locationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectAllFutTaskDetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectAllFutTaskDetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectAllFutTaskDetail`(
	IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		Select * from `task_detail` where `BOT_ID` =  bot_id_ and status = 'PENDING' order by `TASK_DETAIL_ID`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectAllSteps` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectAllSteps` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectAllSteps`(
	in taskDetailID int,
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN totalStepsCount int
    )
BEGIN
		SELECT ID,`TASK_DETAIL_ID`,`X`,`Y`,`Z`,`PROPERTY`,COUNTER,PICK_PUT FROM steps where `TASK_DETAIL_ID` = taskDetailID and LAST_SENT_TIMESTAMP IS NULL and BOT_ID = botID ORDER BY ID LIMIT totalStepsCount;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectAutoModeTeleOperationData` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectAutoModeTeleOperationData` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectAutoModeTeleOperationData`(
	in _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		SELECT `Auto Mode` FROM `teleoperation_bool_data` WHERE `bot_id` = _bot_id;
	END */$$
DELIMITER ;