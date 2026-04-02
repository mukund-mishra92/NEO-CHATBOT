/*
SQLyog Community v13.1.9 (64 bit)
MySQL - 8.0.44 : Database - neo
*********************************************************************
*/

/*!40101 SET NAMES utf8 */;

/*!40101 SET SQL_MODE=''*/;

/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
CREATE DATABASE /*!32312 IF NOT EXISTS*/`neo` /*!40100 DEFAULT CHARACTER SET utf8mb3 */ /*!80016 DEFAULT ENCRYPTION='N' */;

USE `neo`;

/* Procedure structure for procedure `ARC_ARCHIVE_TABLE` */

/*!50003 DROP PROCEDURE IF EXISTS  `ARC_ARCHIVE_TABLE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ARC_ARCHIVE_TABLE`(
    IN mainTableName VARCHAR(100),
    IN archiveTableName VARCHAR(100),
    IN limitWhenInUse INT,
    IN limitWhenNotInUse INT,
    IN duration INT,
    IN primaryIdField VARCHAR(100),
    IN timestampField VARCHAR(100),
    IN orderByField VARCHAR(100),
    IN operation VARCHAR(100)
)
BEGIN
    DECLARE archivedCount INT;
    DECLARE done INT DEFAULT FALSE;
    
    START TRANSACTION;
    
    
    DROP TEMPORARY TABLE IF EXISTS tmpIds;
    CREATE TEMPORARY TABLE tmpIds (
        id VARCHAR(255) PRIMARY KEY  
    );
    
    
    SELECT SUM(cnt) INTO @cnt
    FROM (SELECT COUNT(*) AS cnt FROM hw_station_master WHERE wave_id IS NOT NULL) AS v;
    
    SET @limit = IF(@cnt > 0, limitWhenInUse, limitWhenNotInUse);
    
    IF operation = 'ARCHIVE' THEN
        
        SET @SelectIDs = CONCAT(
            'INSERT INTO tmpIds (id) ',
            'SELECT ', primaryIdField, ' FROM ', mainTableName,
            ' WHERE ', timestampField, ' <= DATE_SUB(NOW(), INTERVAL ', duration, ' DAY)',
            CASE WHEN LENGTH(orderByField) > 0 THEN CONCAT(' ORDER BY ', orderByField) ELSE '' END,
            ' LIMIT ', @limit
        );
        
        PREPARE selectids FROM @SelectIDs;
        EXECUTE selectids;
        DEALLOCATE PREPARE selectids;
        
        
        SET @insertStatement = CONCAT(
            'INSERT IGNORE INTO ', archiveTableName,
            ' SELECT A.* FROM ', mainTableName, ' AS A',
            ' INNER JOIN tmpIds AS TA ON TA.id = A.', primaryIdField,
            ' LEFT OUTER JOIN ', archiveTableName, ' AS C ON C.', primaryIdField, ' = A.', primaryIdField,
            ' WHERE C.', primaryIdField, ' IS NULL'
        );
        
        PREPARE insertStmt FROM @insertStatement;
        EXECUTE insertStmt;
        DEALLOCATE PREPARE insertStmt;
        
        
        SET @deleteStatement = CONCAT(
            'DELETE A FROM ', mainTableName, ' AS A',
            ' INNER JOIN tmpIds AS TA ON TA.id = A.', primaryIdField
        );
        
        PREPARE deleteStmt FROM @deleteStatement;
        EXECUTE deleteStmt;
        DEALLOCATE PREPARE deleteStmt;
        
    ELSEIF operation = 'DELETE' THEN
        SET @onlyDeleteStatement = CONCAT(
            'DELETE FROM ', mainTableName,
            ' WHERE ', timestampField, ' <= DATE_SUB(NOW(), INTERVAL ', duration, ' DAY)',
            CASE WHEN LENGTH(orderByField) > 0 THEN CONCAT(' ORDER BY ', orderByField) ELSE '' END,
            ' LIMIT ', @limit
        );
        
        PREPARE onlyDeleteStmt FROM @onlyDeleteStatement;
        EXECUTE onlyDeleteStmt;
        DEALLOCATE PREPARE onlyDeleteStmt;
        
    ELSEIF operation = 'TRUNCATE' THEN
        IF @limit = 1 THEN
            SET @truncateStatement = CONCAT('TRUNCATE TABLE ', mainTableName);
            
            PREPARE truncateStmt FROM @truncateStatement;
            EXECUTE truncateStmt;
            DEALLOCATE PREPARE truncateStmt;
        END IF;
    END IF;
    
    
    DROP TEMPORARY TABLE IF EXISTS tmpIds;
    
    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ARC_ORDER_REQUEST_ARCHIVE` */

/*!50003 DROP PROCEDURE IF EXISTS  `ARC_ORDER_REQUEST_ARCHIVE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ARC_ORDER_REQUEST_ARCHIVE`(
    IN limitWhenInUse INT,
    IN limitWhenNotInUse INT,
    IN duration INT
)
BEGIN
    
    DECLARE done INT DEFAULT FALSE;
    
    START TRANSACTION;
    
    
    SELECT SUM(cnt) INTO @cnt
    FROM (SELECT COUNT(*) AS cnt FROM hw_station_master WHERE wave_id IS NOT NULL) AS v;
    SET @limit = IF(@cnt > 0, limitWhenInUse, limitWhenNotInUse);
    
    CREATE TEMPORARY TABLE IF NOT EXISTS tmpOrderRequestIds (
        id INT
    );
    
    
    SET @SelectIDs = CONCAT(
        'INSERT INTO tmpOrderRequestIds (id) ',
        'SELECT WMS_ORDER_REQUEST_DATA_ID ',
        'FROM wms_to_wcs_order_request_data ',
        'WHERE INSERTED_TIMESTAMP <= DATE_SUB(NOW(), INTERVAL ', duration, ' DAY) ',
        'AND ORDER_REQUEST_STATUS IN (''DELETED'', ''ORDER_PICK_COMPLETED'', ''ORDER_SUSPENDED'') ',
        'ORDER BY INSERTED_TIMESTAMP ',
        'LIMIT ', @limit
    );
    
    
    PREPARE selectids FROM @SelectIDs;
    EXECUTE selectids;
    DEALLOCATE PREPARE selectids;
    
    
    INSERT IGNORE INTO wms_to_wcs_order_line_request_data_archive
    SELECT B.* 
    FROM wms_to_wcs_order_line_request_data AS B
    INNER JOIN tmpOrderRequestIds AS TA ON TA.id = B.WMS_ORDER_REQUEST_DATA_ID;
    
    
    INSERT IGNORE INTO wms_to_wcs_order_request_data_archive
    SELECT A.* 
    FROM wms_to_wcs_order_request_data AS A
    INNER JOIN tmpOrderRequestIds AS TA ON TA.id = A.WMS_ORDER_REQUEST_DATA_ID;
    
    
    DELETE B 
    FROM wms_to_wcs_order_line_request_data AS B
    INNER JOIN tmpOrderRequestIds AS TA ON TA.id = B.WMS_ORDER_REQUEST_DATA_ID;
    
    
    DELETE A 
    FROM wms_to_wcs_order_request_data AS A
    INNER JOIN tmpOrderRequestIds AS TA ON TA.id = A.WMS_ORDER_REQUEST_DATA_ID;
    
    DROP TEMPORARY TABLE IF EXISTS tmpOrderRequestIds;
    
    COMMIT;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `ARC_ORDER_REQUEST_PRE_STAGED_ARCHIVE` */

/*!50003 DROP PROCEDURE IF EXISTS  `ARC_ORDER_REQUEST_PRE_STAGED_ARCHIVE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ARC_ORDER_REQUEST_PRE_STAGED_ARCHIVE`(
    IN limitWhenInUse INT,
    IN limitWhenNotInUse INT,
    IN duration INT
)
BEGIN
    START TRANSACTION;

    
    SELECT COUNT(*) INTO @cnt
    FROM hw_station_master
    WHERE wave_id IS NOT NULL;

    SET @limit = IF(@cnt > 0, limitWhenInUse, limitWhenNotInUse);

    DROP TEMPORARY TABLE IF EXISTS tmpOrderRequestIds;
    CREATE TEMPORARY TABLE tmpOrderRequestIds (
        id INT PRIMARY KEY
    );

    SET @SelectIDs = CONCAT(
        'INSERT INTO tmpOrderRequestIds (id) ',
        'SELECT WMS_ORDER_REQUEST_DATA_ID ',
        'FROM wms_to_wcs_order_level_pre_staged_data ',
        'WHERE INSERTED_TIMESTAMP <= DATE_SUB(NOW(), INTERVAL ', duration, ' DAY) ',
        'AND ORDER_REQUEST_STATUS IN (''DELETED'', ''ORDER_PICK_COMPLETED'', ''ORDER_SUSPENDED'') ',
        'ORDER BY INSERTED_TIMESTAMP ',
        'LIMIT ', @limit
    );

    PREPARE selectids FROM @SelectIDs;
    EXECUTE selectids;
    DEALLOCATE PREPARE selectids;

    
    INSERT IGNORE INTO wms_to_wcs_order_line_level_pre_staged_data_archive
    SELECT B.*
    FROM wms_to_wcs_order_line_level_pre_staged_data AS B
    INNER JOIN tmpOrderRequestIds AS TA ON TA.id = B.WMS_ORDER_REQUEST_DATA_ID;

    
    INSERT IGNORE INTO wms_to_wcs_order_level_pre_staged_data_archive
    SELECT A.*
    FROM wms_to_wcs_order_level_pre_staged_data AS A
    INNER JOIN tmpOrderRequestIds AS TA ON TA.id = A.WMS_ORDER_REQUEST_DATA_ID;

    
    DELETE B
    FROM wms_to_wcs_order_line_level_pre_staged_data AS B
    INNER JOIN tmpOrderRequestIds AS TA ON TA.id = B.WMS_ORDER_REQUEST_DATA_ID;

    
    DELETE A
    FROM wms_to_wcs_order_level_pre_staged_data AS A
    INNER JOIN tmpOrderRequestIds AS TA ON TA.id = A.WMS_ORDER_REQUEST_DATA_ID;

    DROP TEMPORARY TABLE IF EXISTS tmpOrderRequestIds;

    COMMIT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ARC_STORAGE_PALLET_ARCHIVE` */

/*!50003 DROP PROCEDURE IF EXISTS  `ARC_STORAGE_PALLET_ARCHIVE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ARC_STORAGE_PALLET_ARCHIVE`(
    IN limitWhenInUse INT,
    IN limitWhenNotInUse INT,
    IN duration INT
)
BEGIN
    
    DECLARE done INT DEFAULT FALSE;
    
    
    START TRANSACTION;
    
    
    SELECT SUM(cnt) INTO @cnt
    FROM (SELECT COUNT(*) AS cnt FROM hw_station_master WHERE wave_id IS NOT NULL) AS v;
    SET @limit = IF(@cnt > 0, limitWhenInUse, limitWhenNotInUse);
    
    
    CREATE TEMPORARY TABLE IF NOT EXISTS tmpStoragePalletIds (
        id INT
    );
    
    
    SET @SelectIDs = CONCAT(
        'INSERT INTO tmpStoragePalletIds (id) ',
        'SELECT WMS_STORAGE_REQUEST_PALLET_DATA_ID ',
        'FROM wms_to_wcs_storage_request_pallet_data ',
        'WHERE INSERT_TIMESTAMP <= DATE_SUB(NOW(), INTERVAL ', duration, ' DAY) ',
        'AND STORAGE_REQUEST_STATUS IN (''DELETED'', ''PALLET_SUSPENDED'', ''PALLET_COMPLETED'') ',
        'ORDER BY INSERT_TIMESTAMP ',
        'LIMIT ', @limit
    );
    
    
    PREPARE selectids FROM @SelectIDs;
    EXECUTE selectids;
    DEALLOCATE PREPARE selectids;
    
    
    INSERT INTO wms_to_wcs_storage_request_data_archive
    SELECT B.* 
    FROM wms_to_wcs_storage_request_data AS B
    INNER JOIN tmpStoragePalletIds AS TA ON TA.id = B.WMS_STORAGE_REQUEST_PALLET_DATA_ID;
    
    
    INSERT INTO wms_to_wcs_storage_request_pallet_data_archive
    SELECT A.* 
    FROM wms_to_wcs_storage_request_pallet_data AS A
    INNER JOIN tmpStoragePalletIds AS TA ON TA.id = A.WMS_STORAGE_REQUEST_PALLET_DATA_ID;
    
    
    DELETE B 
    FROM wms_to_wcs_storage_request_data AS B
    INNER JOIN tmpStoragePalletIds AS TA ON TA.id = B.WMS_STORAGE_REQUEST_PALLET_DATA_ID;
    
    
    DELETE A 
    FROM wms_to_wcs_storage_request_pallet_data AS A
    INNER JOIN tmpStoragePalletIds AS TA ON TA.id = A.WMS_STORAGE_REQUEST_PALLET_DATA_ID;
    
    
    DROP TEMPORARY TABLE IF EXISTS tmpStoragePalletIds;
    
    
    COMMIT;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `ARC_TASK_ARCHIVE` */

/*!50003 DROP PROCEDURE IF EXISTS  `ARC_TASK_ARCHIVE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ARC_TASK_ARCHIVE`(
    IN limitWhenInUse INT,
    IN limitWhenNotInUse INT,
    IN duration INT
)
BEGIN
    
    DECLARE done INT DEFAULT FALSE;
    
    START TRANSACTION;
    
    
    SELECT SUM(cnt) INTO @cnt
    FROM (SELECT COUNT(*) AS cnt FROM hw_station_master WHERE wave_id IS NOT NULL) AS v;
    SET @limit = IF(@cnt > 0, limitWhenInUse, limitWhenNotInUse);
    
    CREATE TEMPORARY TABLE IF NOT EXISTS tmpTaskIds (
        id BIGINT
    );
    
    
    
    SET @SelectIDs = CONCAT(
        'INSERT INTO tmpTaskIds (id) ',
        'SELECT TASK_ID ',
        'FROM task_master ',
        'WHERE INSERTED_TIMESTAMP <= DATE_SUB(NOW(), INTERVAL ', duration, ' DAY) ',
        'AND STATUS = ''COMPLETED'' ',
        'ORDER BY INSERTED_TIMESTAMP ',
        'LIMIT ', @limit
    );
    
    
    PREPARE selectids FROM @SelectIDs;
    EXECUTE selectids;
    DEALLOCATE PREPARE selectids;
    
    
    INSERT INTO task_detail_log (
        TASK_DETAIL_ID, TASK_MASTER_ID, BOT_ID, START_LOCATION_ID, END_LOCATION_ID, 
        STATUS, START_PICK_PUT_SIDE, START_Z, END_PICK_PUT_SIDE, END_Z, 
        START_TIME, END_TIME, UPDATED_TIMESTAMP, TASK_DETAIL_TYPE, 
        IS_TOWER_BUFFER, IS_STEPS_INSERTED, COUNT_OF_STEPS, COUNT_OF_STEPS_SENT, 
        INSERTED_TIMESTAMP, LOGGED_TIMESTAMP
    )
    SELECT 
        TD.TASK_DETAIL_ID, TD.TASK_MASTER_ID, TD.BOT_ID, TD.START_LOCATION_ID, TD.END_LOCATION_ID, 
        TD.STATUS, TD.START_PICK_PUT_SIDE, TD.START_Z, TD.END_PICK_PUT_SIDE, TD.END_Z, 
        TD.START_TIME, TD.END_TIME, TD.UPDATED_TIMESTAMP, TD.TASK_DETAIL_TYPE, 
        TD.IS_TOWER_BUFFER, TD.IS_STEPS_INSERTED, TD.COUNT_OF_STEPS, TD.COUNT_OF_STEPS_SENT, 
        TD.INSERTED_TIMESTAMP, NOW(3)
    FROM task_detail AS TD
    INNER JOIN tmpTaskIds AS TI ON TI.id = TD.TASK_MASTER_ID;
    
    
    INSERT INTO task_master_log (
        TASK_ID, BOT_ID, FROM_LOCATION_ID, DESTINATION_LOCATION_ID, 
        STATUS, START_TIME, END_TIME, TASK_TYPE, UPDATED_TIMESTAMP, 
        INSERTED_TIMESTAMP, LOGGED_TIMESTAMP
    )
    SELECT 
        TM.TASK_ID, TM.BOT_ID, TM.FROM_LOCATION_ID, TM.DESTINATION_LOCATION_ID, 
        TM.STATUS, TM.START_TIME, TM.END_TIME, TM.TASK_TYPE, TM.UPDATED_TIMESTAMP, 
        TM.INSERTED_TIMESTAMP, NOW(3)
    FROM task_master AS TM
    INNER JOIN tmpTaskIds AS TI ON TI.id = TM.TASK_ID;
    
    
    DELETE TD 
    FROM task_detail AS TD
    INNER JOIN tmpTaskIds AS TI ON TI.id = TD.TASK_MASTER_ID;
    
    
    DELETE TM 
    FROM task_master AS TM
    INNER JOIN tmpTaskIds AS TI ON TI.id = TM.TASK_ID;
    
    DROP TEMPORARY TABLE IF EXISTS tmpTaskIds;
    
    COMMIT;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `BOT_ALLOCATION_ENGINE` */

/*!50003 DROP PROCEDURE IF EXISTS  `BOT_ALLOCATION_ENGINE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `BOT_ALLOCATION_ENGINE`()
BEGIN
    

    
    DECLARE V_NoBot                      INT DEFAULT 0;  
    DECLARE V_OtherWaveCount             INT DEFAULT 0;  
    DECLARE V_AllocatedPBotsPerStation   INT DEFAULT 0;  
    DECLARE V_PendingBots                INT DEFAULT 0;  
    DECLARE V_PickStation                INT DEFAULT 0;  
    DECLARE V_PutStation                 INT DEFAULT 0;  
    DECLARE V_ActiveStation              INT DEFAULT 0;  
    DECLARE V_BotforOtherWave            INT DEFAULT 0;  
    DECLARE V_BotStationDemand           INT DEFAULT 0;  
    DECLARE V_BotDemandinPick            INT DEFAULT 0;  

    DECLARE V_NoBotSA                    INT DEFAULT 0;  
    DECLARE V_NoBotBL                    INT DEFAULT 0;  
    DECLARE V_NoBotLA                    INT DEFAULT 0;  

    

    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;
   
    
    CREATE TEMPORARY TABLE tmp_wave_station_rule_mapping
    SELECT * FROM wave_station_rule_mapping;
    
    UPDATE tmp_wave_station_rule_mapping SET BOT_COUNT_CURRENT=0;
    
    
    CREATE TEMPORARY TABLE tmp_station_demand AS 
    SELECT A.STATION_ID,W.WAVE_TYPE,A.RACK_PENDING_CNT,A.STATION_PICK_PENDING_CNT
    FROM (
	    SELECT OBM.STATION_ID, SUM( CASE WHEN OBM.TYPE = 'RACK_PICK' AND 
	    OBM.STATUS IN ('PENDING','TASK_ALLOCATED','BIN_PICKED') 
	    THEN 1 ELSE 0 END ) AS RACK_PENDING_CNT, 
	    
	    SUM( CASE WHEN (OBM.TYPE = 'STATION_PICK' AND OBM.STATUS = 'PENDING') 
	    
	    THEN 1 ELSE 0 END ) AS STATION_PICK_PENDING_CNT 
	    FROM order_bin_mapping OBM
	     GROUP BY OBM.STATION_ID
	  ) A
    JOIN hw_station_master HS ON HS.STATION_ID = A.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE (A.RACK_PENDING_CNT>0  OR  A.STATION_PICK_PENDING_CNT>0);
    
     CREATE TEMPORARY TABLE  tmp_station_demand1 AS 
    SELECT  * FROM tmp_station_demand;
   
    

    SELECT COUNT(*) INTO V_NoBot
    FROM bot_master
    WHERE AUTO_MANUAL = 'auto'
      AND STATUS      = 'ENABLED';

    
	
    SELECT KEY_VALUE INTO V_NoBotSA FROM master_config WHERE KEY_NAME = 'MAX_BOT_SA';
    SELECT KEY_VALUE INTO V_NoBotBL FROM master_config WHERE KEY_NAME = 'MAX_BOT_BL';
    SELECT KEY_VALUE INTO V_NoBotLA FROM master_config WHERE KEY_NAME = 'MAX_BOT_LA';

    SET V_NoBotSA = IFNULL(V_NoBotSA, 0);
    SET V_NoBotBL = IFNULL(V_NoBotBL, 0);
    SET V_NoBotLA = IFNULL(V_NoBotLA, 0);


    

    IF V_NoBot < (V_NoBotSA + V_NoBotBL + V_NoBotLA) THEN

        
        SELECT COUNT(DISTINCT W.Wave_ID)
        INTO V_OtherWaveCount
        FROM tmp_wave_station_rule_mapping WR
        JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
        JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
        WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
          AND HS.STATUS      = 'ENABLED'
          AND HS.WAVE_STATUS = 'WAVE_LIVE';

        IF V_OtherWaveCount > 0 THEN
            SET V_BotforOtherWave = FLOOR(V_NoBot / V_OtherWaveCount);

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = V_BotforOtherWave
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = V_BotforOtherWave
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = V_BotforOtherWave
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
        END IF;

    ELSE
        

        UPDATE tmp_wave_station_rule_mapping WR
        JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
        JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
        SET WR.BOT_COUNT_CURRENT = V_NoBotSA
        WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
          AND HS.STATUS      = 'ENABLED'
          AND HS.WAVE_STATUS = 'WAVE_LIVE';

        UPDATE tmp_wave_station_rule_mapping WR
        JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
        JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
        SET WR.BOT_COUNT_CURRENT = V_NoBotBL
        WHERE W.WAVE_TYPE   = 'BIN_LOADING'
          AND HS.STATUS      = 'ENABLED'
          AND HS.WAVE_STATUS = 'WAVE_LIVE';

        UPDATE tmp_wave_station_rule_mapping WR
        JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
        JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
        SET WR.BOT_COUNT_CURRENT = V_NoBotLA
        WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
          AND HS.STATUS      = 'ENABLED'
          AND HS.WAVE_STATUS = 'WAVE_LIVE';
    END IF;

    
           
    SELECT SUM(WR.BOT_COUNT_CURRENT)
    INTO V_OtherWaveCount
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE NOT IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SET V_NoBot = V_NoBot - IFNULL(V_OtherWaveCount, 0);
    IF V_NoBot < 0 THEN
        SET V_NoBot = 0;
    END IF;

    

    SELECT COUNT(*)
    INTO V_ActiveStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';
      
    SELECT COUNT(*)
    INTO V_PickStation
    FROM tmp_wave_station_rule_mapping WR
    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
    WHERE W.WAVE_TYPE = 'PICK'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';
     
    SELECT COUNT(*)
    INTO V_PutStation
    FROM tmp_wave_station_rule_mapping WR
    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
    WHERE W.WAVE_TYPE = 'PUT'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';
    

    IF IFNULL(V_ActiveStation, 0) > 0 THEN

        
        
        IF FLOOR(V_NoBot / V_ActiveStation) > 0 THEN

            
            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID           
            INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=HS.STATION_ID
            SET WR.BOT_COUNT_CURRENT =
                CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 AND  FLOOR(V_NoBot / V_ActiveStation)>TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN  IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 AND   FLOOR(V_NoBot / V_ActiveStation)>TSD.STATION_PICK_PENDING_CNT
                    THEN  TSD.STATION_PICK_PENDING_CNT
                    WHEN FLOOR(V_NoBot / V_ActiveStation) >=
                         (CASE WHEN W.WAVE_TYPE = 'PUT'
                               THEN WR.MIN_BOT_COUNT_PUT
                               ELSE WR.MIN_BOT_COUNT_PICK
                          END)
                    THEN (CASE WHEN W.WAVE_TYPE = 'PICK'
                               THEN WR.MIN_BOT_COUNT_PICK
                               ELSE WR.MIN_BOT_COUNT_PUT
                          END)
                    ELSE 1
                END
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
          
            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
            
            SELECT (SUM(CASE WHEN W.WAVE_TYPE = 'PUT'
                               THEN WR.MAX_BOT_COUNT_PUT
                               ELSE WR.MAX_BOT_COUNT_PICK
                          END)- SUM(WR.BOT_COUNT_CURRENT)) into V_BotDemandinPick 
                          FROM  tmp_wave_station_rule_mapping WR
            INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID           
            INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=HS.STATION_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
              
           while V_BotDemandinPick>0  Do 
		set V_BotDemandinPick=case  when V_BotDemandinPick>V_PendingBots then V_PendingBots else V_BotDemandinPick end ;
		
		
                    if floor(V_BotDemandinPick/V_ActiveStation)>0 then 
			    UPDATE tmp_wave_station_rule_mapping WR
			    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID           
			    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
			    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=HS.STATION_ID
			    SET WR.BOT_COUNT_CURRENT =
				CASE
				    WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 AND  (WR.BOT_COUNT_CURRENT+1)>TSD.RACK_PENDING_CNT
				    THEN TSD.RACK_PENDING_CNT
				    WHEN  IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 AND (WR.BOT_COUNT_CURRENT+1)>TSD.STATION_PICK_PENDING_CNT
				    THEN  TSD.STATION_PICK_PENDING_CNT
				    WHEN (WR.BOT_COUNT_CURRENT+1)>=
					 (CASE WHEN W.WAVE_TYPE = 'PUT'
					       THEN WR.MAX_BOT_COUNT_PUT
					       ELSE WR.MAX_BOT_COUNT_PICK
					  END)
				    THEN (CASE WHEN W.WAVE_TYPE = 'PICK'
					       THEN WR.MAX_BOT_COUNT_PICK
					       ELSE WR.MAX_BOT_COUNT_PUT
					  END)
				    ELSE (WR.BOT_COUNT_CURRENT+1)
				END
			      WHERE W.WAVE_TYPE IN ('PICK','PUT')
			      AND HS.STATUS      = 'ENABLED'
			      AND HS.WAVE_STATUS = 'WAVE_LIVE';
		    else
		     UPDATE tmp_wave_station_rule_mapping WR
		     INNER JOIN (
			SELECT HS.STATION_ID,
			       HS.Wave_ID,
			       ROW_NUMBER() OVER (
				   ORDER BY CASE WHEN W.WAVE_TYPE = 'PICK' THEN 1 ELSE 2 END,
					    HS.STATION_ID
			       ) AS SRank
			FROM hw_station_master HS
			INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
			WHERE W.WAVE_TYPE IN ('PICK','PUT')
			  AND HS.STATUS      = 'ENABLED'
			  AND HS.WAVE_STATUS = 'WAVE_LIVE'
		    ) AS X ON X.STATION_ID = WR.STATION_ID
		    INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
		    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
		    SET WR.BOT_COUNT_CURRENT =
			CASE
			    WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 AND  (WR.BOT_COUNT_CURRENT+1)>TSD.RACK_PENDING_CNT
			    THEN TSD.RACK_PENDING_CNT
			    WHEN  IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 AND (WR.BOT_COUNT_CURRENT+1)>TSD.STATION_PICK_PENDING_CNT
			    THEN  TSD.STATION_PICK_PENDING_CNT
			    WHEN (WR.BOT_COUNT_CURRENT+1)>=
				 (CASE WHEN W.WAVE_TYPE = 'PUT'
				       THEN WR.MAX_BOT_COUNT_PUT
				       ELSE WR.MAX_BOT_COUNT_PICK
				  END)
			    THEN (CASE WHEN W.WAVE_TYPE = 'PICK'
				      THEN WR.MAX_BOT_COUNT_PICK
				       ELSE WR.MAX_BOT_COUNT_PUT
				  END)
			    ELSE (WR.BOT_COUNT_CURRENT+1)
			END
		      WHERE W.WAVE_TYPE IN ('PICK','PUT')
		      AND X.SRank <= V_BotDemandinPick; 

		      SET V_BotDemandinPick = 0; 
		    end if;
		    SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
		    INTO V_PendingBots
		    FROM tmp_wave_station_rule_mapping WR
		    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
		    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
		    WHERE W.WAVE_TYPE IN ('PICK','PUT')
		      AND HS.STATUS      = 'ENABLED'
		      AND HS.WAVE_STATUS = 'WAVE_LIVE';
		    if V_PendingBots>0 then
			    SELECT (SUM(CASE WHEN W.WAVE_TYPE = 'PUT'
				       THEN WR.MAX_BOT_COUNT_PUT
				       ELSE WR.MAX_BOT_COUNT_PICK
				  END)- SUM(WR.BOT_COUNT_CURRENT)) INTO V_BotDemandinPick 
				  FROM  tmp_wave_station_rule_mapping WR
			    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID           
			    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
			    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=HS.STATION_ID
			    WHERE W.WAVE_TYPE IN ('PICK','PUT')
			      AND HS.STATUS      = 'ENABLED'
			      AND HS.WAVE_STATUS = 'WAVE_LIVE';
			    else 
			    set V_BotDemandinPick=0;
		     end if;
            end while;
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
          
           
            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
        ELSE
            
            
            

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = 0
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN (
                SELECT HS.STATION_ID,
                       HS.Wave_ID,
                       ROW_NUMBER() OVER (
                           ORDER BY CASE WHEN W.WAVE_TYPE = 'PICK' THEN 1 ELSE 2 END,
                                    HS.STATION_ID
                       ) AS SRank
                FROM hw_station_master HS
                INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE'
            ) AS X ON X.STATION_ID = WR.STATION_ID
            INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
            INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = 1
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND X.SRank <= V_NoBot;

            SET V_PendingBots = 0;  
        END IF;

        IF V_PendingBots < 0 THEN
            SET V_PendingBots = 0;
        END IF;

        IF V_PendingBots > 0 THEN
            IF V_PickStation > 0 THEN
                SET V_AllocatedPBotsPerStation = FLOOR(V_PendingBots / V_PickStation);

                IF V_AllocatedPBotsPerStation > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                    SET WR.BOT_COUNT_CURRENT =
                     CASE
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.RACK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PICK)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.STATION_PICK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PICK)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)=0 
                     THEN LEAST((WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PICK)
                     END                      
                    WHERE W.WAVE_TYPE = 'PICK'
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE';
                END IF;
            END IF;
            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            IF V_PendingBots < 0 THEN
                SET V_PendingBots = 0;
            END IF;
           
            
           
		SELECT (SUM(WR.MAX_BOT_COUNT_PICK)-SUM(WR.BOT_COUNT_CURRENT)) INTO V_BotDemandinPick  
		FROM tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
		INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
		INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID  
		WHERE W.WAVE_TYPE = 'PICK'
                AND HS.STATUS      = 'ENABLED'
                AND HS.WAVE_STATUS = 'WAVE_LIVE';
                
	 IF V_BotDemandinPick>0 AND V_PendingBots>0 THEN
		UPDATE tmp_wave_station_rule_mapping WR
			INNER JOIN (
				SELECT  STATION_ID,Wave_ID,ROW_NUMBER() OVER (ORDER BY STATION_ID) AS SRank
				FROM (
					 SELECT HS.STATION_ID,HS.Wave_ID
					 FROM hw_station_master HS
					 INNER JOIN tmp_station_demand1 TSD ON TSD.STATION_ID=HS.STATION_ID
					 INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
					 WHERE W.WAVE_TYPE = 'PICK'
					  AND HS.STATUS      = 'ENABLED'
					  AND HS.WAVE_STATUS = 'WAVE_LIVE'
				   ) A
			) AS X ON X.STATION_ID = WR.STATION_ID
			INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
			INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
			SET WR.BOT_COUNT_CURRENT =
			     CASE
			     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 
			     THEN LEAST(TSD.RACK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + 1),WR.MAX_BOT_COUNT_PICK)
			     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 
			     THEN LEAST(TSD.STATION_PICK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + 1),WR.MAX_BOT_COUNT_PICK)
			     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)=0 
			     THEN LEAST((WR.BOT_COUNT_CURRENT + 1),WR.MAX_BOT_COUNT_PICK)
			     END  
			WHERE W.WAVE_TYPE = 'PICK'
			  AND X.SRank     <= V_PendingBots;
			  
		    SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
		    INTO V_PendingBots
		    FROM tmp_wave_station_rule_mapping WR
		    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
		    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
		    WHERE W.WAVE_TYPE IN ('PICK','PUT')
		      AND HS.STATUS      = 'ENABLED'
		      AND HS.WAVE_STATUS = 'WAVE_LIVE';

		    IF V_PendingBots < 0 THEN
			SET V_PendingBots = 0;
		    END IF;
	END IF;
	 
           
         
            IF V_PutStation > 0 AND V_PendingBots > 0 THEN
                SET V_AllocatedPBotsPerStation = FLOOR(V_PendingBots / V_PutStation);
                
                IF V_AllocatedPBotsPerStation > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                    SET WR.BOT_COUNT_CURRENT = 
                    CASE
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.RACK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PUT)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.STATION_PICK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PUT)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)=0 
                     THEN LEAST((WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PUT)
                     END  
                    WHERE W.WAVE_TYPE = 'PUT'
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE' ;
                END IF;
            END IF;
            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            IF V_PendingBots < 0 THEN
                SET V_PendingBots = 0;
            END IF;

            IF V_PutStation > 0 AND V_PendingBots > 0 THEN
		IF V_PendingBots>V_PutStation THEN
		       UPDATE tmp_wave_station_rule_mapping WR
			INNER JOIN (
			    SELECT  STATION_ID,Wave_ID,ROW_NUMBER() OVER (ORDER BY STATION_ID) AS SRank
			    FROM (
				    SELECT HS.STATION_ID,HS.Wave_ID
				    FROM hw_station_master HS
				    INNER JOIN tmp_station_demand1 TSD ON TSD.STATION_ID=HS.STATION_ID
				    INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
				    WHERE W.WAVE_TYPE = 'PUT'
				      AND HS.STATUS      = 'ENABLED'
				      AND HS.WAVE_STATUS = 'WAVE_LIVE'
			       ) A
			) AS X ON X.STATION_ID = WR.STATION_ID
			INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
			INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
			SET WR.BOT_COUNT_CURRENT =
			     CASE
			     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 
			     THEN LEAST(TSD.RACK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + FLOOR(V_PendingBots/V_PutStation)),WR.UPPER_BOT_COUNT_PUT)
			     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 
			     THEN LEAST(TSD.STATION_PICK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + FLOOR(V_PendingBots/V_PutStation)),WR.UPPER_BOT_COUNT_PUT)
			     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)=0 
			     THEN LEAST((WR.BOT_COUNT_CURRENT + FLOOR(V_PendingBots/V_PutStation)),WR.UPPER_BOT_COUNT_PUT)
			     END 
			WHERE W.WAVE_TYPE = 'PUT'
			  AND X.SRank     <= V_PendingBots;
		ELSE
			UPDATE tmp_wave_station_rule_mapping WR
			INNER JOIN (
			    SELECT  STATION_ID,Wave_ID,ROW_NUMBER() OVER (ORDER BY STATION_ID) AS SRank
			    FROM (
				    SELECT HS.STATION_ID,HS.Wave_ID
				    FROM hw_station_master HS
				    INNER JOIN tmp_station_demand1 TSD ON TSD.STATION_ID=HS.STATION_ID
				    INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
				    WHERE W.WAVE_TYPE = 'PUT'
				      AND HS.STATUS      = 'ENABLED'
				      AND HS.WAVE_STATUS = 'WAVE_LIVE'
			       ) A
			) AS X ON X.STATION_ID = WR.STATION_ID
			INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
			INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
			SET WR.BOT_COUNT_CURRENT =
			     CASE
			     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 
			     THEN LEAST(TSD.RACK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + 1),WR.UPPER_BOT_COUNT_PUT)
			     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 
			     THEN LEAST(TSD.STATION_PICK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + 1),WR.UPPER_BOT_COUNT_PUT)
			     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)=0 
			     THEN LEAST((WR.BOT_COUNT_CURRENT + 1),WR.UPPER_BOT_COUNT_PUT)
			     END 
			WHERE W.WAVE_TYPE = 'PUT'
			  AND X.SRank     <= V_PendingBots;
		END IF;

                SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
                INTO V_PendingBots
                FROM tmp_wave_station_rule_mapping WR
                JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE';

                IF V_PendingBots < 0 THEN
                    SET V_PendingBots = 0;
                END IF;
            END IF;

        END IF; 

    END IF; 

    

    

    

 
    SELECT
        HS.WAVE_ID,
        W.WAVE_TYPE,
        WR.STATION_ID,
        WR.BOT_COUNT_CURRENT,
        WR.BOT_COUNT_DEFAULT,
        IFNULL(TSD.RACK_PENDING_CNT,0) AS RACK_PENDING_CNT,
        IFNULL(TSD.STATION_PICK_PENDING_CNT,0) AS STATION_PICK_PENDING_CNT,      
        WR.MAX_BOT_COUNT_PICK,
        WR.MIN_BOT_COUNT_PICK,
        WR.MAX_BOT_COUNT_PUT,
        WR.MIN_BOT_COUNT_PUT,
        WR.UPPER_BOT_COUNT_PUT
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
    WHERE HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;

END */$$
DELIMITER ;

/* Procedure structure for procedure `BOT_ALLOCATION_ENGINE_V1` */

/*!50003 DROP PROCEDURE IF EXISTS  `BOT_ALLOCATION_ENGINE_V1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `BOT_ALLOCATION_ENGINE_V1`()
BEGIN
    

    
    DECLARE V_NoBot                      INT DEFAULT 0;  
    DECLARE V_OtherWaveCount             INT DEFAULT 0;  
    DECLARE V_AllocatedPBotsPerStation   INT DEFAULT 0;  
    DECLARE V_PendingBots                INT DEFAULT 0;  
    DECLARE V_PickStation                INT DEFAULT 0;  
    DECLARE V_PutStation                 INT DEFAULT 0;  
    DECLARE V_ActiveStation              INT DEFAULT 0;  
    DECLARE V_BotforOtherWave            INT DEFAULT 0;  
    DECLARE V_BotStationDemand           INT DEFAULT 0;  
    DECLARE V_BotDemandinPick            INT DEFAULT 0;  

    DECLARE V_NoBotSA                    INT DEFAULT 0;  
    DECLARE V_NoBotBL                    INT DEFAULT 0;  
    DECLARE V_NoBotLA                    INT DEFAULT 0;  

    DECLARE V_SAStation                  INT DEFAULT 0;  
    DECLARE V_BLStation                  INT DEFAULT 0;  
    DECLARE V_LAStation                  INT DEFAULT 0;  
    DECLARE V_SpecialStations            INT DEFAULT 0;  
    DECLARE V_SpecialAllocated           INT DEFAULT 0;  
    DECLARE V_PerStation                 INT DEFAULT 0;  
    DECLARE V_RemainingForType           INT DEFAULT 0;  

    

    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;
   
    
    CREATE TEMPORARY TABLE tmp_wave_station_rule_mapping
    SELECT * FROM wave_station_rule_mapping;
    
    UPDATE tmp_wave_station_rule_mapping SET BOT_COUNT_CURRENT = 0;
    
    
    CREATE TEMPORARY TABLE tmp_station_demand AS 
    SELECT A.STATION_ID,
           W.WAVE_TYPE,
           A.RACK_PENDING_CNT,
           A.STATION_PICK_PENDING_CNT
    FROM (
        SELECT OBM.STATION_ID,
               SUM(CASE WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED','BIN_PICKED')
                        THEN 1 ELSE 0 END) AS RACK_PENDING_CNT,
               
               SUM(CASE WHEN (OBM.TYPE = 'STATION_PICK'
                               AND OBM.STATUS = 'PENDING')
                        THEN 1 ELSE 0 END) AS STATION_PICK_PENDING_CNT
        FROM order_bin_mapping OBM
        GROUP BY OBM.STATION_ID
    ) A
    JOIN hw_station_master HS ON HS.STATION_ID = A.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE (A.RACK_PENDING_CNT > 0 OR A.STATION_PICK_PENDING_CNT > 0);
    
    CREATE TEMPORARY TABLE tmp_station_demand1 AS 
    SELECT * FROM tmp_station_demand;

    

    SELECT COUNT(*) INTO V_NoBot
    FROM bot_master
    WHERE AUTO_MANUAL = 'auto'
      AND STATUS      = 'ENABLED';

    
	
    SELECT KEY_VALUE INTO V_NoBotSA FROM master_config WHERE KEY_NAME = 'MAX_BOT_SA';
    SELECT KEY_VALUE INTO V_NoBotBL FROM master_config WHERE KEY_NAME = 'MAX_BOT_BL';
    SELECT KEY_VALUE INTO V_NoBotLA FROM master_config WHERE KEY_NAME = 'MAX_BOT_LA';

    SET V_NoBotSA = IFNULL(V_NoBotSA, 0);
    SET V_NoBotBL = IFNULL(V_NoBotBL, 0);
    SET V_NoBotLA = IFNULL(V_NoBotLA, 0);

    

    SELECT COUNT(*)
    INTO V_SAStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SELECT COUNT(*)
    INTO V_BLStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE   = 'BIN_LOADING'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SELECT COUNT(*)
    INTO V_LAStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SET V_SpecialStations  = V_SAStation + V_BLStation + V_LAStation;
    SET V_SpecialAllocated = 0;

    

    IF V_SpecialStations > 0 AND V_NoBot > 0 THEN

        IF V_NoBot < (V_NoBotSA + V_NoBotBL + V_NoBotLA) THEN
            

            SET V_PerStation = FLOOR(V_NoBot / V_SpecialStations);

            IF V_PerStation > 0 THEN
                UPDATE tmp_wave_station_rule_mapping WR
                JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                SET WR.BOT_COUNT_CURRENT = V_PerStation
                WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE';

                SET V_SpecialAllocated = V_PerStation * V_SpecialStations;
            END IF;

            SET V_RemainingForType = V_NoBot - V_SpecialAllocated;

            IF V_RemainingForType > 0 THEN
                
                UPDATE tmp_wave_station_rule_mapping WR
                INNER JOIN (
                    SELECT HS.STATION_ID,
                           HS.Wave_ID,
                           ROW_NUMBER() OVER (
                               ORDER BY CASE W.WAVE_TYPE
                                            WHEN 'STOCK_AUDIT'  THEN 1
                                            WHEN 'BIN_LOADING'  THEN 2
                                            WHEN 'LOCATION_AUDIT' THEN 3
                                            ELSE 4
                                        END,
                                        HS.STATION_ID
                           ) AS SRank
                    FROM hw_station_master HS
                    JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                    WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE'
                ) X ON X.STATION_ID = WR.STATION_ID
                JOIN wave_master W ON W.Wave_ID = X.Wave_ID
                SET WR.BOT_COUNT_CURRENT = WR.BOT_COUNT_CURRENT + 1
                WHERE X.SRank <= V_RemainingForType;

                SET V_SpecialAllocated = V_SpecialAllocated + V_RemainingForType;
            END IF;

        ELSE
            

            
            SET V_RemainingForType = V_NoBot - V_SpecialAllocated;
            IF V_SAStation > 0 AND V_NoBotSA > 0 AND V_RemainingForType > 0 THEN
                SET V_BotforOtherWave = LEAST(V_NoBotSA, V_RemainingForType);
                SET V_PerStation      = FLOOR(V_BotforOtherWave / V_SAStation);

                IF V_PerStation > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    SET WR.BOT_COUNT_CURRENT = V_PerStation
                    WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE';
                END IF;

                SET V_SpecialAllocated = V_SpecialAllocated + (V_PerStation * V_SAStation);
                SET V_RemainingForType = V_BotforOtherWave - (V_PerStation * V_SAStation);

                IF V_RemainingForType > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN (
                        SELECT HS.STATION_ID,
                               HS.Wave_ID,
                               ROW_NUMBER() OVER (ORDER BY HS.STATION_ID) AS SRank
                        FROM hw_station_master HS
                        JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                        WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
                          AND HS.STATUS      = 'ENABLED'
                          AND HS.WAVE_STATUS = 'WAVE_LIVE'
                    ) X ON X.STATION_ID = WR.STATION_ID
                    JOIN wave_master W ON W.Wave_ID = X.Wave_ID
                    SET WR.BOT_COUNT_CURRENT = WR.BOT_COUNT_CURRENT + 1
                    WHERE X.SRank <= V_RemainingForType;

                    SET V_SpecialAllocated = V_SpecialAllocated + V_RemainingForType;
                END IF;
            END IF;

            
            SET V_RemainingForType = V_NoBot - V_SpecialAllocated;
            IF V_BLStation > 0 AND V_NoBotBL > 0 AND V_RemainingForType > 0 THEN
                SET V_BotforOtherWave = LEAST(V_NoBotBL, V_RemainingForType);
                SET V_PerStation      = FLOOR(V_BotforOtherWave / V_BLStation);

                IF V_PerStation > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    SET WR.BOT_COUNT_CURRENT = V_PerStation
                    WHERE W.WAVE_TYPE   = 'BIN_LOADING'
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE';
                END IF;

                SET V_SpecialAllocated = V_SpecialAllocated + (V_PerStation * V_BLStation);
                SET V_RemainingForType = V_BotforOtherWave - (V_PerStation * V_BLStation);

                IF V_RemainingForType > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN (
                        SELECT HS.STATION_ID,
                               HS.Wave_ID,
                               ROW_NUMBER() OVER (ORDER BY HS.STATION_ID) AS SRank
                        FROM hw_station_master HS
                        JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                        WHERE W.WAVE_TYPE   = 'BIN_LOADING'
                          AND HS.STATUS      = 'ENABLED'
                          AND HS.WAVE_STATUS = 'WAVE_LIVE'
                    ) X ON X.STATION_ID = WR.STATION_ID
                    JOIN wave_master W ON W.Wave_ID = X.Wave_ID
                    SET WR.BOT_COUNT_CURRENT = WR.BOT_COUNT_CURRENT + 1
                    WHERE X.SRank <= V_RemainingForType;

                    SET V_SpecialAllocated = V_SpecialAllocated + V_RemainingForType;
                END IF;
            END IF;

            
            SET V_RemainingForType = V_NoBot - V_SpecialAllocated;
            IF V_LAStation > 0 AND V_NoBotLA > 0 AND V_RemainingForType > 0 THEN
                SET V_BotforOtherWave = LEAST(V_NoBotLA, V_RemainingForType);
                SET V_PerStation      = FLOOR(V_BotforOtherWave / V_LAStation);

                IF V_PerStation > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    SET WR.BOT_COUNT_CURRENT = V_PerStation
                    WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE';
                END IF;

                SET V_SpecialAllocated = V_SpecialAllocated + (V_PerStation * V_LAStation);
                SET V_RemainingForType = V_BotforOtherWave - (V_PerStation * V_LAStation);

                IF V_RemainingForType > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN (
                        SELECT HS.STATION_ID,
                               HS.Wave_ID,
                               ROW_NUMBER() OVER (ORDER BY HS.STATION_ID) AS SRank
                        FROM hw_station_master HS
                        JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                        WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
                          AND HS.STATUS      = 'ENABLED'
                          AND HS.WAVE_STATUS = 'WAVE_LIVE'
                    ) X ON X.STATION_ID = WR.STATION_ID
                    JOIN wave_master W ON W.Wave_ID = X.Wave_ID
                    SET WR.BOT_COUNT_CURRENT = WR.BOT_COUNT_CURRENT + 1
                    WHERE X.SRank <= V_RemainingForType;

                    SET V_SpecialAllocated = V_SpecialAllocated + V_RemainingForType;
                END IF;
            END IF;

        END IF;  
        
        
        SET V_NoBot = V_NoBot - V_SpecialAllocated;
        IF V_NoBot < 0 THEN
            SET V_NoBot = 0;
        END IF;

    END IF;  

    

    SELECT COUNT(*)
    INTO V_ActiveStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE W.WAVE_TYPE IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';
      
    SELECT COUNT(*)
    INTO V_PickStation
    FROM tmp_wave_station_rule_mapping WR
    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE W.WAVE_TYPE = 'PICK'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';
     
    SELECT COUNT(*)
    INTO V_PutStation
    FROM tmp_wave_station_rule_mapping WR
    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE W.WAVE_TYPE = 'PUT'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    

    IF IFNULL(V_ActiveStation, 0) > 0 AND V_NoBot > 0 THEN

        
        IF FLOOR(V_NoBot / V_ActiveStation) > 0 THEN

            
            
            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID           
            INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
            SET WR.BOT_COUNT_CURRENT =
                CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND FLOOR(V_NoBot / V_ActiveStation) > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND FLOOR(V_NoBot / V_ActiveStation) > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN FLOOR(V_NoBot / V_ActiveStation) >=
                         (CASE WHEN W.WAVE_TYPE = 'PUT'
                               THEN WR.MIN_BOT_COUNT_PUT
                               ELSE WR.MIN_BOT_COUNT_PICK
                          END)
                    THEN (CASE WHEN W.WAVE_TYPE = 'PICK'
                               THEN WR.MIN_BOT_COUNT_PICK
                               ELSE WR.MIN_BOT_COUNT_PUT
                          END)
                    ELSE 1
                END
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
          
            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
            
            
            SELECT (SUM(CASE WHEN W.WAVE_TYPE = 'PUT'
                             THEN WR.MAX_BOT_COUNT_PUT
                             ELSE WR.MAX_BOT_COUNT_PICK
                        END) - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_BotDemandinPick
            FROM tmp_wave_station_rule_mapping WR
            INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID           
            INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
              
           WHILE V_BotDemandinPick > 0 DO 
                SET V_BotDemandinPick =
                    CASE WHEN V_BotDemandinPick > V_PendingBots
                         THEN V_PendingBots
                         ELSE V_BotDemandinPick
                    END;
		
                IF FLOOR(V_BotDemandinPick / V_ActiveStation) > 0 THEN 
                    
                    
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID           
                    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
                    SET WR.BOT_COUNT_CURRENT =
                        CASE
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                                 AND (WR.BOT_COUNT_CURRENT + 1) > TSD.RACK_PENDING_CNT
                            THEN TSD.RACK_PENDING_CNT
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                                 AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                                 AND (WR.BOT_COUNT_CURRENT + 1) > TSD.STATION_PICK_PENDING_CNT
                            THEN TSD.STATION_PICK_PENDING_CNT
                            WHEN (WR.BOT_COUNT_CURRENT + 1) >=
                                 (CASE WHEN W.WAVE_TYPE = 'PUT'
                                       THEN WR.MAX_BOT_COUNT_PUT
                                       ELSE WR.MAX_BOT_COUNT_PICK
                                  END)
                            THEN (CASE WHEN W.WAVE_TYPE = 'PICK'
                                       THEN WR.MAX_BOT_COUNT_PICK
                                       ELSE WR.MAX_BOT_COUNT_PUT
                                  END)
                            ELSE (WR.BOT_COUNT_CURRENT + 1)
                        END
                    WHERE W.WAVE_TYPE IN ('PICK','PUT')
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE';
                        ELSE
            
            
            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN (
                SELECT HS.STATION_ID,
                       HS.Wave_ID,
                       ROW_NUMBER() OVER (
                           ORDER BY CASE WHEN W.WAVE_TYPE = 'PICK' THEN 1 ELSE 2 END,
                                    HS.STATION_ID
                       ) AS SRank
                FROM hw_station_master HS
                INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                INNER JOIN tmp_station_demand1 TSD1 ON TSD1.STATION_ID = HS.STATION_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE'
            ) AS X ON X.STATION_ID = WR.STATION_ID
            INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
            INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT =
                CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND (WR.BOT_COUNT_CURRENT + 1) > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND (WR.BOT_COUNT_CURRENT + 1) > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN (WR.BOT_COUNT_CURRENT + 1) >=
                         (CASE WHEN W.WAVE_TYPE = 'PUT'
                               THEN WR.MAX_BOT_COUNT_PUT
                               ELSE WR.MAX_BOT_COUNT_PICK
                          END)
                    THEN (CASE WHEN W.WAVE_TYPE = 'PICK'
                               THEN WR.MAX_BOT_COUNT_PICK
                               ELSE WR.MAX_BOT_COUNT_PUT
                          END)
                    ELSE (WR.BOT_COUNT_CURRENT + 1)
                END
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND X.SRank <= V_BotDemandinPick; 

            SET V_BotDemandinPick = 0; 
        END IF;


                
                SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
                INTO V_PendingBots
                FROM tmp_wave_station_rule_mapping WR
                JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE';

                IF V_PendingBots > 0 THEN
                    SELECT (SUM(CASE WHEN W.WAVE_TYPE = 'PUT'
                                     THEN WR.MAX_BOT_COUNT_PUT
                                     ELSE WR.MAX_BOT_COUNT_PICK
                                END) - SUM(WR.BOT_COUNT_CURRENT))
                    INTO V_BotDemandinPick 
                    FROM tmp_wave_station_rule_mapping WR
                    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID           
                    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
                    WHERE W.WAVE_TYPE IN ('PICK','PUT')
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE';
                ELSE 
                    SET V_BotDemandinPick = 0;
                END IF;
            END WHILE;

            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

        ELSE
            
            
            

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = 0
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN (
                SELECT HS.STATION_ID,
                       HS.Wave_ID,
                       ROW_NUMBER() OVER (
                           ORDER BY CASE WHEN W.WAVE_TYPE = 'PICK' THEN 1 ELSE 2 END,
                                    HS.STATION_ID
                       ) AS SRank
                FROM hw_station_master HS
                INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE'
            ) AS X ON X.STATION_ID = WR.STATION_ID
            INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
            SET WR.BOT_COUNT_CURRENT = 1
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND X.SRank <= V_NoBot;

            
            SET V_PendingBots = 0;
        END IF;

        IF V_PendingBots < 0 THEN
            SET V_PendingBots = 0;
        END IF;

        

        IF V_PendingBots > 0 THEN
            
            IF V_PickStation > 0 THEN
                SET V_AllocatedPBotsPerStation = FLOOR(V_PendingBots / V_PickStation);

                IF V_AllocatedPBotsPerStation > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
                    SET WR.BOT_COUNT_CURRENT =
                        CASE
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0 
                            THEN LEAST(
                                     TSD.RACK_PENDING_CNT,
                                     (WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),
                                     WR.MAX_BOT_COUNT_PICK
                                 )
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                                 AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0 
                            THEN LEAST(
                                     TSD.STATION_PICK_PENDING_CNT,
                                     (WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),
                                     WR.MAX_BOT_COUNT_PICK
                                 )
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                                 AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0 
                            THEN LEAST(
                                     (WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),
                                     WR.MAX_BOT_COUNT_PICK
                                 )
                        END                      
                    WHERE W.WAVE_TYPE = 'PICK'
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE';
                END IF;
            END IF;
            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            IF V_PendingBots < 0 THEN
                SET V_PendingBots = 0;
            END IF;
           
            
            SELECT (SUM(WR.MAX_BOT_COUNT_PICK) - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_BotDemandinPick  
            FROM tmp_wave_station_rule_mapping WR
            INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID  
            WHERE W.WAVE_TYPE = 'PICK'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
                
            IF V_BotDemandinPick > 0 AND V_PendingBots > 0 THEN
                UPDATE tmp_wave_station_rule_mapping WR
                INNER JOIN (
                    SELECT STATION_ID,
                           Wave_ID,
                           ROW_NUMBER() OVER (ORDER BY STATION_ID) AS SRank
                    FROM (
                        SELECT HS.STATION_ID,
                               HS.Wave_ID
                        FROM hw_station_master HS
                        INNER JOIN tmp_station_demand1 TSD ON TSD.STATION_ID = HS.STATION_ID
                        INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                        WHERE W.WAVE_TYPE = 'PICK'
                          AND HS.STATUS      = 'ENABLED'
                          AND HS.WAVE_STATUS = 'WAVE_LIVE'
                    ) A
                ) AS X ON X.STATION_ID = WR.STATION_ID
                INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
                INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
                SET WR.BOT_COUNT_CURRENT =
                    CASE
                        WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0 
                        THEN LEAST(
                                 TSD.RACK_PENDING_CNT,
                                 (WR.BOT_COUNT_CURRENT + 1),
                                 WR.MAX_BOT_COUNT_PICK
                             )
                        WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                             AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0 
                        THEN LEAST(
                                 TSD.STATION_PICK_PENDING_CNT,
                                 (WR.BOT_COUNT_CURRENT + 1),
                                 WR.MAX_BOT_COUNT_PICK
                             )
                        WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                             AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0 
                        THEN LEAST(
                                 (WR.BOT_COUNT_CURRENT + 1),
                                 WR.MAX_BOT_COUNT_PICK
                             )
                    END  
                WHERE W.WAVE_TYPE = 'PICK'
                  AND X.SRank     <= V_PendingBots;
			  
                SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
                INTO V_PendingBots
                FROM tmp_wave_station_rule_mapping WR
                JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE';

                IF V_PendingBots < 0 THEN
                    SET V_PendingBots = 0;
                END IF;
            END IF;
	 
            
            IF V_PutStation > 0 AND V_PendingBots > 0 THEN
                SET V_AllocatedPBotsPerStation = FLOOR(V_PendingBots / V_PutStation);

                IF V_AllocatedPBotsPerStation > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
                    SET WR.BOT_COUNT_CURRENT = 
                        CASE
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0 
                            THEN LEAST(
                                     TSD.RACK_PENDING_CNT,
                                     (WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),
                                     WR.MAX_BOT_COUNT_PUT
                                 )
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                                 AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0 
                            THEN LEAST(
                                     TSD.STATION_PICK_PENDING_CNT,
                                     (WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),
                                     WR.MAX_BOT_COUNT_PUT
                                 )
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                                 AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0 
                            THEN LEAST(
                                     (WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),
                                     WR.MAX_BOT_COUNT_PUT
                                 )
                        END  
                    WHERE W.WAVE_TYPE = 'PUT'
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE';
                END IF;
            END IF;
            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            IF V_PendingBots < 0 THEN
                SET V_PendingBots = 0;
            END IF;

            
            IF V_PutStation > 0 AND V_PendingBots > 0 THEN
                IF V_PendingBots > V_PutStation THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN (
                        SELECT STATION_ID,
                               Wave_ID,
                               ROW_NUMBER() OVER (ORDER BY STATION_ID) AS SRank
                        FROM (
                            SELECT HS.STATION_ID,
                                   HS.Wave_ID
                            FROM hw_station_master HS
                            INNER JOIN tmp_station_demand1 TSD ON TSD.STATION_ID = HS.STATION_ID
                            INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                            WHERE W.WAVE_TYPE = 'PUT'
                              AND HS.STATUS      = 'ENABLED'
                              AND HS.WAVE_STATUS = 'WAVE_LIVE'
                        ) A
                    ) AS X ON X.STATION_ID = WR.STATION_ID
                    INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
                    SET WR.BOT_COUNT_CURRENT =
                        CASE
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0 
                            THEN LEAST(
                                     TSD.RACK_PENDING_CNT,
                                     (WR.BOT_COUNT_CURRENT + FLOOR(V_PendingBots / V_PutStation)),
                                     WR.UPPER_BOT_COUNT_PUT
                                 )
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                                 AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0 
                            THEN LEAST(
                                     TSD.STATION_PICK_PENDING_CNT,
                                     (WR.BOT_COUNT_CURRENT + FLOOR(V_PendingBots / V_PutStation)),
                                     WR.UPPER_BOT_COUNT_PUT
                                 )
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                                 AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0 
                            THEN LEAST(
                                     (WR.BOT_COUNT_CURRENT + FLOOR(V_PendingBots / V_PutStation)),
                                     WR.UPPER_BOT_COUNT_PUT
                                 )
                        END 
                    WHERE W.WAVE_TYPE = 'PUT'
                      AND X.SRank     <= V_PendingBots;
                ELSE
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN (
                        SELECT STATION_ID,
                               Wave_ID,
                               ROW_NUMBER() OVER (ORDER BY STATION_ID) AS SRank
                        FROM (
                            SELECT HS.STATION_ID,
                                   HS.Wave_ID
                            FROM hw_station_master HS
                            INNER JOIN tmp_station_demand1 TSD ON TSD.STATION_ID = HS.STATION_ID
                            INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                            WHERE W.WAVE_TYPE = 'PUT'
                              AND HS.STATUS      = 'ENABLED'
                              AND HS.WAVE_STATUS = 'WAVE_LIVE'
                        ) A
                    ) AS X ON X.STATION_ID = WR.STATION_ID
                    INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
                    SET WR.BOT_COUNT_CURRENT =
                        CASE
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0 
                            THEN LEAST(
                                     TSD.RACK_PENDING_CNT,
                                     (WR.BOT_COUNT_CURRENT + 1),
                                     WR.UPPER_BOT_COUNT_PUT
                                 )
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                                 AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0 
                            THEN LEAST(
                                     TSD.STATION_PICK_PENDING_CNT,
                                     (WR.BOT_COUNT_CURRENT + 1),
                                     WR.UPPER_BOT_COUNT_PUT
                                 )
                            WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                                 AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0 
                            THEN LEAST(
                                     (WR.BOT_COUNT_CURRENT + 1),
                                     WR.UPPER_BOT_COUNT_PUT
                                 )
                        END 
                    WHERE W.WAVE_TYPE = 'PUT'
                      AND X.SRank     <= V_PendingBots;
                END IF;

                SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
                INTO V_PendingBots
                FROM tmp_wave_station_rule_mapping WR
                JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE';

                IF V_PendingBots < 0 THEN
                    SET V_PendingBots = 0;
                END IF;
            END IF;

        END IF; 

    END IF; 

    

    

    

    SELECT
        HS.WAVE_ID,
        W.WAVE_TYPE,
        WR.STATION_ID,
        WR.BOT_COUNT_CURRENT,
        WR.BOT_COUNT_DEFAULT,
        IFNULL(TSD.RACK_PENDING_CNT, 0)          AS RACK_PENDING_CNT,
        IFNULL(TSD.STATION_PICK_PENDING_CNT, 0)  AS STATION_PICK_PENDING_CNT,      
        WR.MAX_BOT_COUNT_PICK,
        WR.MIN_BOT_COUNT_PICK,
        WR.MAX_BOT_COUNT_PUT,
        WR.MIN_BOT_COUNT_PUT,
        WR.UPPER_BOT_COUNT_PUT
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    

    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;

END */$$
DELIMITER ;

/* Procedure structure for procedure `BOT_ALLOCATION_ENGINE_V10` */

/*!50003 DROP PROCEDURE IF EXISTS  `BOT_ALLOCATION_ENGINE_V10` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `BOT_ALLOCATION_ENGINE_V10`()
BEGIN
    

    
    DECLARE V_TotalBots                  INT DEFAULT 0;  
    DECLARE V_GlobalInflightBots         INT DEFAULT 0;  
    DECLARE V_SpecialUsed                INT DEFAULT 0;  
    DECLARE V_FreeBots                   INT DEFAULT 0;  

    DECLARE V_OtherWaveCount             INT DEFAULT 0;

    DECLARE V_NoBotSA                    INT DEFAULT 0;
    DECLARE V_NoBotBL                    INT DEFAULT 0;
    DECLARE V_NoBotLA                    INT DEFAULT 0;

    
    DECLARE V_PreCapPick                 INT DEFAULT 3;
    DECLARE V_PreCapPut                  INT DEFAULT 3;

    
    DECLARE V_SelectedStation            INT DEFAULT NULL;
    DECLARE V_SelectedWaveType           VARCHAR(50) DEFAULT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;

    
    CREATE TEMPORARY TABLE tmp_wave_station_rule_mapping
    SELECT * FROM wave_station_rule_mapping;

    UPDATE tmp_wave_station_rule_mapping
    SET BOT_COUNT_CURRENT = 0;

    
    SELECT COUNT(*) INTO V_TotalBots
    FROM bot_master
    WHERE AUTO_MANUAL = 'auto'
      AND STATUS      = 'ENABLED';

    
    SELECT KEY_VALUE INTO V_NoBotSA FROM master_config WHERE KEY_NAME = 'MAX_BOT_SA';
    SELECT KEY_VALUE INTO V_NoBotBL FROM master_config WHERE KEY_NAME = 'MAX_BOT_BL';
    SELECT KEY_VALUE INTO V_NoBotLA FROM master_config WHERE KEY_NAME = 'MAX_BOT_LA';
    SET V_NoBotSA = IFNULL(V_NoBotSA, 0);
    SET V_NoBotBL = IFNULL(V_NoBotBL, 0);
    SET V_NoBotLA = IFNULL(V_NoBotLA, 0);

    
    SELECT KEY_VALUE INTO V_PreCapPick FROM master_config WHERE KEY_NAME = 'PRE_ON_CAP_PICK';
    SELECT KEY_VALUE INTO V_PreCapPut  FROM master_config WHERE KEY_NAME = 'PRE_ON_CAP_PUT';
    SET V_PreCapPick = IFNULL(V_PreCapPick, 3);
    SET V_PreCapPut  = IFNULL(V_PreCapPut, 3);

    
    CREATE TEMPORARY TABLE tmp_station_demand AS
    SELECT
        A.STATION_ID,
        W.WAVE_TYPE,

        
        A.RACK_PENDING_CNT,
        A.STATION_PICK_PENDING_CNT,

        
        A.RACK_PENDING_ONLY_CNT,
        A.PRE_ON_STATION_CNT,
        A.INFLIGHT_BOT_CNT,

        
        (A.RACK_PENDING_ONLY_CNT + A.STATION_PICK_PENDING_CNT) AS BACKLOG,

        
        GREATEST(
            A.INFLIGHT_BOT_CNT,
            GREATEST(0, (A.RACK_PENDING_ONLY_CNT + A.STATION_PICK_PENDING_CNT) - A.PRE_ON_STATION_CNT)
        ) AS EFFECTIVE_DEMAND

    FROM (
        SELECT
            OBM.STATION_ID,

            
            SUM(
                CASE
                    WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED','BIN_PICKED')
                    THEN 1 ELSE 0
                END
            ) AS RACK_PENDING_CNT,

            SUM(
                CASE
                    WHEN OBM.TYPE = 'STATION_PICK'
                         AND OBM.STATUS = 'PENDING'
                    THEN 1 ELSE 0
                END
            ) AS STATION_PICK_PENDING_CNT,

            
            SUM(
                CASE
                    WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','RACK_PENDING')
                    THEN 1 ELSE 0
                END
            ) AS RACK_PENDING_ONLY_CNT,

            SUM(CASE WHEN OBM.STATUS = 'PRE_ON_STATION' THEN 1 ELSE 0 END) AS PRE_ON_STATION_CNT,

            
            COUNT(DISTINCT
                CASE
                    WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATUS IN ('TASK_ALLOCATED','BIN_PICKED')
                         AND OBM.BOT_ID IS NOT NULL
                    THEN OBM.BOT_ID
                    ELSE NULL
                END
            ) AS INFLIGHT_BOT_CNT

        FROM order_bin_mapping OBM
        WHERE OBM.STATION_ID IS NOT NULL
        GROUP BY OBM.STATION_ID
    ) A
    JOIN hw_station_master HS ON HS.STATION_ID = A.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    WHERE HS.STATUS='ENABLED'
      AND HS.WAVE_STATUS='WAVE_LIVE'
      AND (
            A.RACK_PENDING_CNT > 0
         OR A.STATION_PICK_PENDING_CNT > 0
         OR A.PRE_ON_STATION_CNT > 0
         OR A.INFLIGHT_BOT_CNT > 0
      );

    CREATE TEMPORARY TABLE tmp_station_demand1 AS
    SELECT * FROM tmp_station_demand;

    
    SELECT COUNT(DISTINCT OBM.BOT_ID)
      INTO V_GlobalInflightBots
    FROM order_bin_mapping OBM
    WHERE OBM.TYPE = 'RACK_PICK'
      AND OBM.STATUS IN ('TASK_ALLOCATED','BIN_PICKED')
      AND OBM.BOT_ID IS NOT NULL;

    
    SELECT COUNT(DISTINCT W.Wave_ID)
      INTO V_OtherWaveCount
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    IF V_OtherWaveCount > 0 THEN
        IF V_TotalBots < (V_NoBotSA * V_OtherWaveCount) THEN

            SET V_SpecialUsed = FLOOR(V_TotalBots / V_OtherWaveCount);

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_SpecialUsed,0) > 0
                    THEN V_SpecialUsed
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_SpecialUsed,0) > 0
                    THEN V_SpecialUsed
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_SpecialUsed,0) > 0
                    THEN V_SpecialUsed
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            SELECT IFNULL(V_TotalBots - SUM(WR.BOT_COUNT_CURRENT), 0)
              INTO V_SpecialUsed
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE NOT IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN (
                SELECT HS.STATION_ID,
                       HS.Wave_ID,
                       ROW_NUMBER() OVER (
                           ORDER BY CASE W.WAVE_TYPE
                                      WHEN 'STOCK_AUDIT'    THEN 1
                                      WHEN 'BIN_LOADING'    THEN 2
                                      WHEN 'LOCATION_AUDIT' THEN 3
                                      ELSE 4 END,
                                    HS.STATION_ID
                       ) AS SRank
                FROM hw_station_master HS
                JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE'
            ) X ON X.STATION_ID = WR.STATION_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND WR.BOT_COUNT_CURRENT+1 > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND WR.BOT_COUNT_CURRENT+1 > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_SpecialUsed,0) > 0
                    THEN WR.BOT_COUNT_CURRENT+1
                    ELSE 1
                END
            WHERE X.SRank <= V_SpecialUsed;

        ELSE
            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_NoBotSA > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_NoBotSA > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_NoBotSA,0) > 0
                    THEN V_NoBotSA
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_NoBotBL > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_NoBotBL > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_NoBotBL,0) > 0
                    THEN V_NoBotBL
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_NoBotLA > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_NoBotLA > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_NoBotLA,0) > 0
                    THEN V_NoBotLA
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
        END IF;
    END IF;

    
    SELECT IFNULL(SUM(WR.BOT_COUNT_CURRENT), 0)
      INTO V_SpecialUsed
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE NOT IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    
    SET V_FreeBots = V_TotalBots - IFNULL(V_SpecialUsed,0) - IFNULL(V_GlobalInflightBots,0);
    IF V_FreeBots < 0 THEN SET V_FreeBots = 0; END IF;

    
    UPDATE tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    SET WR.BOT_COUNT_CURRENT = IFNULL(TSD.INFLIGHT_BOT_CNT,0)
    WHERE W.WAVE_TYPE IN ('PICK','PUT')
      AND HS.STATUS='ENABLED'
      AND HS.WAVE_STATUS='WAVE_LIVE';

    

    
    min_loop: WHILE V_FreeBots > 0 DO

        SET V_SelectedStation  = NULL;
        SET V_SelectedWaveType = NULL;

        SELECT X.STATION_ID, X.WAVE_TYPE
          INTO V_SelectedStation, V_SelectedWaveType
        FROM (
            SELECT
                HS.STATION_ID AS STATION_ID,
                WM.WAVE_TYPE  AS WAVE_TYPE,
                WR.BOT_COUNT_CURRENT AS CURR,
                IFNULL(TSD.BACKLOG,0) AS BACKLOG,
                IFNULL(TSD.EFFECTIVE_DEMAND,0) AS DEMAND,
                IFNULL(TSD.PRE_ON_STATION_CNT,0) AS PRECNT,
                GREATEST(0, IFNULL(TSD.EFFECTIVE_DEMAND,0) - WR.BOT_COUNT_CURRENT) AS RESIDUAL,
                CASE WHEN WM.WAVE_TYPE='PICK' THEN IFNULL(WR.MIN_BOT_COUNT_PICK,0)
                     ELSE IFNULL(WR.MIN_BOT_COUNT_PUT,0) END AS MINREQ,
                CASE WHEN WM.WAVE_TYPE='PICK' THEN IFNULL(WR.MAX_BOT_COUNT_PICK,0)
                     ELSE IFNULL(WR.MAX_BOT_COUNT_PUT,0) END AS CAPMAX,
                CASE
                    WHEN WM.WAVE_TYPE='PICK' AND IFNULL(TSD.PRE_ON_STATION_CNT,0) >= V_PreCapPick THEN 1
                    WHEN WM.WAVE_TYPE='PUT'  AND IFNULL(TSD.PRE_ON_STATION_CNT,0) >= V_PreCapPut  THEN 1
                    ELSE 0
                END AS BLOCKED
            FROM hw_station_master HS
            JOIN wave_master WM  ON WM.Wave_ID = HS.Wave_ID
            JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = HS.STATION_ID
            JOIN tmp_station_demand TSD           ON TSD.STATION_ID = HS.STATION_ID
            WHERE HS.STATUS='ENABLED'
              AND HS.WAVE_STATUS='WAVE_LIVE'
              AND WM.WAVE_TYPE IN ('PICK','PUT')
        ) X
        WHERE X.BACKLOG > 0
          AND X.CURR < X.MINREQ
          AND X.CURR < X.CAPMAX
        ORDER BY
            X.BLOCKED ASC,
            X.PRECNT ASC,
            (X.RESIDUAL * 1.0 / (X.CURR+1)) DESC,
            CASE WHEN X.WAVE_TYPE='PICK' THEN 1 ELSE 2 END,
            X.STATION_ID
        LIMIT 1;

        IF V_SelectedStation IS NULL THEN
            LEAVE min_loop;
        END IF;

        UPDATE tmp_wave_station_rule_mapping
        SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
        WHERE STATION_ID = V_SelectedStation;

        SET V_FreeBots = V_FreeBots - 1;

    END WHILE min_loop;

    
    loop1: WHILE V_FreeBots > 0 DO

        SET V_SelectedStation  = NULL;
        SET V_SelectedWaveType = NULL;

        SELECT X.STATION_ID, X.WAVE_TYPE
          INTO V_SelectedStation, V_SelectedWaveType
        FROM (
            SELECT
                HS.STATION_ID AS STATION_ID,
                WM.WAVE_TYPE  AS WAVE_TYPE,
                WR.BOT_COUNT_CURRENT AS CURR,
                IFNULL(TSD.BACKLOG,0) AS BACKLOG,
                IFNULL(TSD.EFFECTIVE_DEMAND,0) AS DEMAND,
                IFNULL(TSD.PRE_ON_STATION_CNT,0) AS PRECNT,
                GREATEST(0, IFNULL(TSD.EFFECTIVE_DEMAND,0) - WR.BOT_COUNT_CURRENT) AS RESIDUAL,
                CASE WHEN WM.WAVE_TYPE='PICK' THEN IFNULL(WR.MAX_BOT_COUNT_PICK,0)
                     ELSE IFNULL(WR.MAX_BOT_COUNT_PUT,0) END AS CAPMAX,
                CASE
                    WHEN WM.WAVE_TYPE='PICK' AND IFNULL(TSD.PRE_ON_STATION_CNT,0) >= V_PreCapPick THEN 1
                    WHEN WM.WAVE_TYPE='PUT'  AND IFNULL(TSD.PRE_ON_STATION_CNT,0) >= V_PreCapPut  THEN 1
                    ELSE 0
                END AS BLOCKED
            FROM hw_station_master HS
            JOIN wave_master WM  ON WM.Wave_ID = HS.Wave_ID
            JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = HS.STATION_ID
            JOIN tmp_station_demand TSD           ON TSD.STATION_ID = HS.STATION_ID
            WHERE HS.STATUS='ENABLED'
              AND HS.WAVE_STATUS='WAVE_LIVE'
              AND WM.WAVE_TYPE IN ('PICK','PUT')
        ) X
        WHERE X.CURR < X.CAPMAX
          AND X.RESIDUAL > 0
        ORDER BY
            X.BLOCKED ASC,
            (X.RESIDUAL * 1.0 / (X.CURR+1)) DESC,
            X.PRECNT ASC,
            CASE WHEN X.WAVE_TYPE='PICK' THEN 1 ELSE 2 END,
            X.STATION_ID
        LIMIT 1;

        IF V_SelectedStation IS NULL THEN
            LEAVE loop1;
        END IF;

        UPDATE tmp_wave_station_rule_mapping
        SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
        WHERE STATION_ID = V_SelectedStation;

        SET V_FreeBots = V_FreeBots - 1;

    END WHILE loop1;

    
    put_upper_loop: WHILE V_FreeBots > 0 DO

        SET V_SelectedStation = NULL;

        SELECT X.STATION_ID
          INTO V_SelectedStation
        FROM (
            SELECT
                HS.STATION_ID AS STATION_ID,
                WR.BOT_COUNT_CURRENT AS CURR,
                IFNULL(TSD.EFFECTIVE_DEMAND,0) AS DEMAND,
                IFNULL(TSD.PRE_ON_STATION_CNT,0) AS PRECNT,
                GREATEST(0, IFNULL(TSD.EFFECTIVE_DEMAND,0) - WR.BOT_COUNT_CURRENT) AS RESIDUAL,
                IFNULL(WR.UPPER_BOT_COUNT_PUT,0) AS CAPUP,
                CASE WHEN IFNULL(TSD.PRE_ON_STATION_CNT,0) >= V_PreCapPut THEN 1 ELSE 0 END AS BLOCKED
            FROM hw_station_master HS
            JOIN wave_master W          ON W.Wave_ID = HS.Wave_ID
            JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = HS.STATION_ID
            JOIN tmp_station_demand TSD           ON TSD.STATION_ID = HS.STATION_ID
            WHERE HS.STATUS='ENABLED'
              AND HS.WAVE_STATUS='WAVE_LIVE'
              AND W.WAVE_TYPE='PUT'
        ) X
        WHERE X.CURR < X.CAPUP
          AND X.RESIDUAL > 0
        ORDER BY
            X.BLOCKED ASC,
            (X.RESIDUAL * 1.0 / (X.CURR+1)) DESC,
            X.PRECNT ASC,
            X.STATION_ID
        LIMIT 1;

        IF V_SelectedStation IS NULL THEN
            LEAVE put_upper_loop;
        END IF;

        UPDATE tmp_wave_station_rule_mapping
        SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
        WHERE STATION_ID = V_SelectedStation;

        SET V_FreeBots = V_FreeBots - 1;

    END WHILE put_upper_loop;

    
    spillover: WHILE V_FreeBots > 0 DO

        SET V_SelectedStation  = NULL;
        SET V_SelectedWaveType = NULL;

        SELECT X.STATION_ID, X.WAVE_TYPE
          INTO V_SelectedStation, V_SelectedWaveType
        FROM (
            SELECT
                WM.WAVE_TYPE AS WAVE_TYPE,
                HS.STATION_ID AS STATION_ID,
                WR.BOT_COUNT_CURRENT AS CURR,
                IFNULL(TSD.PRE_ON_STATION_CNT,0) AS PRECNT,
                CASE
                    WHEN WM.WAVE_TYPE='PICK' THEN IFNULL(WR.MAX_BOT_COUNT_PICK,0)
                    WHEN WM.WAVE_TYPE='PUT'  THEN IFNULL(WR.UPPER_BOT_COUNT_PUT, IFNULL(WR.MAX_BOT_COUNT_PUT,0))
                END AS CAPX,
                CASE
                    WHEN WM.WAVE_TYPE='PICK' AND IFNULL(TSD.PRE_ON_STATION_CNT,0) >= V_PreCapPick THEN 1
                    WHEN WM.WAVE_TYPE='PUT'  AND IFNULL(TSD.PRE_ON_STATION_CNT,0) >= V_PreCapPut  THEN 1
                    ELSE 0
                END AS BLOCKED
            FROM hw_station_master HS
            JOIN wave_master WM  ON WM.Wave_ID = HS.Wave_ID
            JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = HS.STATION_ID
            LEFT JOIN tmp_station_demand TSD      ON TSD.STATION_ID = HS.STATION_ID
            WHERE HS.STATUS='ENABLED'
              AND HS.WAVE_STATUS='WAVE_LIVE'
              AND WM.WAVE_TYPE IN ('PICK','PUT')
        ) X
        WHERE X.CURR < IFNULL(X.CAPX,0)
        ORDER BY
            X.BLOCKED ASC,
            (X.CURR * 1.0 / (IFNULL(X.CAPX,1))) ASC,
            CASE WHEN X.WAVE_TYPE='PICK' THEN 1 ELSE 2 END,
            X.PRECNT ASC,
            X.STATION_ID
        LIMIT 1;

        IF V_SelectedStation IS NULL THEN
            LEAVE spillover;
        END IF;

        UPDATE tmp_wave_station_rule_mapping
        SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
        WHERE STATION_ID = V_SelectedStation;

        SET V_FreeBots = V_FreeBots - 1;

    END WHILE spillover;

    
    UPDATE wave_station_rule_mapping WR
    JOIN tmp_wave_station_rule_mapping TWR
      ON WR.WAVE_STATION_RULE_MAPPING_ID = TWR.WAVE_STATION_RULE_MAPPING_ID
    SET WR.BOT_COUNT_CURRENT = TWR.BOT_COUNT_CURRENT;

    
    SELECT
        HS.WAVE_ID,
        W.WAVE_TYPE,
        WR.STATION_ID,
        WR.BOT_COUNT_CURRENT,
        WR.BOT_COUNT_DEFAULT,

        IFNULL(TSD.RACK_PENDING_CNT,0)            AS RACK_PENDING_CNT,
        IFNULL(TSD.RACK_PENDING_ONLY_CNT,0)       AS RACK_PENDING_ONLY_CNT,
        IFNULL(TSD.STATION_PICK_PENDING_CNT,0)    AS STATION_PICK_PENDING_CNT,

        IFNULL(TSD.PRE_ON_STATION_CNT,0)          AS PRE_ON_STATION_CNT,
        IFNULL(TSD.INFLIGHT_BOT_CNT,0)            AS INFLIGHT_BOT_CNT,
        IFNULL(TSD.BACKLOG,0)                     AS BACKLOG,
        IFNULL(TSD.EFFECTIVE_DEMAND,0)            AS EFFECTIVE_DEMAND,
        GREATEST(0, IFNULL(TSD.EFFECTIVE_DEMAND,0) - WR.BOT_COUNT_CURRENT) AS RESIDUAL,

        WR.MAX_BOT_COUNT_PICK,
        WR.MIN_BOT_COUNT_PICK,
        WR.MAX_BOT_COUNT_PUT,
        WR.MIN_BOT_COUNT_PUT,
        WR.UPPER_BOT_COUNT_PUT
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE HS.STATUS='ENABLED'
      AND HS.WAVE_STATUS='WAVE_LIVE';

    
    SELECT
        V_TotalBots                 AS TOTAL_ENABLED_AUTO,
        V_SpecialUsed               AS SPECIAL_USED,
        V_GlobalInflightBots        AS GLOBAL_INFLIGHT_BOTS,
        (SELECT IFNULL(SUM(WR.BOT_COUNT_CURRENT),0)
           FROM tmp_wave_station_rule_mapping WR
           JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
           JOIN wave_master W ON W.Wave_ID=HS.Wave_ID
          WHERE HS.STATUS='ENABLED' AND HS.WAVE_STATUS='WAVE_LIVE') AS TOTAL_ASSIGNED_AFTER_SP;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;

END */$$
DELIMITER ;

/* Procedure structure for procedure `BOT_ALLOCATION_ENGINE_V11` */

/*!50003 DROP PROCEDURE IF EXISTS  `BOT_ALLOCATION_ENGINE_V11` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `BOT_ALLOCATION_ENGINE_V11`()
BEGIN
    

    
    DECLARE V_TotalBots                  INT DEFAULT 0;
    DECLARE V_GlobalInflightBots         INT DEFAULT 0;
    DECLARE V_SpecialUsed                INT DEFAULT 0;
    DECLARE V_FreeBots                   INT DEFAULT 0;

    DECLARE V_OtherWaveCount             INT DEFAULT 0;

    DECLARE V_NoBotSA                    INT DEFAULT 0;
    DECLARE V_NoBotBL                    INT DEFAULT 0;
    DECLARE V_NoBotLA                    INT DEFAULT 0;

    
    DECLARE V_AnyIncrement               INT DEFAULT 0;

    DECLARE V_PickCount                  INT DEFAULT 0;
    DECLARE V_PutCount                   INT DEFAULT 0;

    DECLARE V_PickPtr                    INT DEFAULT 1;
    DECLARE V_PutPtr                     INT DEFAULT 1;

    DECLARE V_i                          INT DEFAULT 0;
    DECLARE V_RN                         INT DEFAULT 0;

    
    DECLARE V_StationId                  INT DEFAULT 0;

    DECLARE V_CurrentBots                INT DEFAULT 0;
    DECLARE V_Backlog                    INT DEFAULT 0;
    DECLARE V_EffectiveDemand            INT DEFAULT 0;
    DECLARE V_Residual                   INT DEFAULT 0;

    DECLARE V_MinPick                    INT DEFAULT 0;
    DECLARE V_MinPut                     INT DEFAULT 0;
    DECLARE V_MaxPick                    INT DEFAULT 0;
    DECLARE V_MaxPut                     INT DEFAULT 0;
    DECLARE V_UpperPut                   INT DEFAULT 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_pick;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_put;

    
    CREATE TEMPORARY TABLE tmp_wave_station_rule_mapping
    SELECT * FROM wave_station_rule_mapping;

    UPDATE tmp_wave_station_rule_mapping
    SET BOT_COUNT_CURRENT = 0;

    
    SELECT COUNT(*) INTO V_TotalBots
    FROM bot_master
    WHERE AUTO_MANUAL = 'auto'
      AND STATUS      = 'ENABLED';

    
    SELECT KEY_VALUE INTO V_NoBotSA FROM master_config WHERE KEY_NAME = 'MAX_BOT_SA';
    SELECT KEY_VALUE INTO V_NoBotBL FROM master_config WHERE KEY_NAME = 'MAX_BOT_BL';
    SELECT KEY_VALUE INTO V_NoBotLA FROM master_config WHERE KEY_NAME = 'MAX_BOT_LA';
    SET V_NoBotSA = IFNULL(V_NoBotSA, 0);
    SET V_NoBotBL = IFNULL(V_NoBotBL, 0);
    SET V_NoBotLA = IFNULL(V_NoBotLA, 0);

    
    CREATE TEMPORARY TABLE tmp_station_demand AS
    SELECT
        A.STATION_ID,
        W.WAVE_TYPE,

        
        A.RACK_PENDING_CNT,
        A.STATION_PICK_PENDING_CNT,

        
        A.RACK_PENDING_ONLY_CNT,
        A.PRE_ON_STATION_CNT,
        A.INFLIGHT_BOT_CNT,

        
        (A.RACK_PENDING_ONLY_CNT + A.STATION_PICK_PENDING_CNT) AS BACKLOG,
        GREATEST(
            A.INFLIGHT_BOT_CNT,
            GREATEST(0, (A.RACK_PENDING_ONLY_CNT + A.STATION_PICK_PENDING_CNT) - A.PRE_ON_STATION_CNT)
        ) AS EFFECTIVE_DEMAND

    FROM (
        SELECT
            OBM.STATION_ID,

            
            SUM(
                CASE
                    WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED','BIN_PICKED')
                    THEN 1 ELSE 0
                END
            ) AS RACK_PENDING_CNT,

            SUM(
                CASE
                    WHEN OBM.TYPE = 'STATION_PICK'
                         AND OBM.STATUS = 'PENDING'
                    THEN 1 ELSE 0
                END
            ) AS STATION_PICK_PENDING_CNT,

            
            SUM(
                CASE
                    WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATUS IN ('PENDING','RACK_PENDING')
                    THEN 1 ELSE 0
                END
            ) AS RACK_PENDING_ONLY_CNT,

            SUM(CASE WHEN OBM.STATUS = 'PRE_ON_STATION' THEN 1 ELSE 0 END) AS PRE_ON_STATION_CNT,

            
            COUNT(DISTINCT
                CASE
                    WHEN OBM.TYPE = 'RACK_PICK'
                         AND OBM.STATUS IN ('TASK_ALLOCATED','BIN_PICKED')
                         AND OBM.BOT_ID IS NOT NULL
                    THEN OBM.BOT_ID
                    ELSE NULL
                END
            ) AS INFLIGHT_BOT_CNT

        FROM order_bin_mapping OBM
        WHERE OBM.STATION_ID IS NOT NULL
        GROUP BY OBM.STATION_ID
    ) A
    JOIN hw_station_master HS ON HS.STATION_ID = A.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    WHERE HS.STATUS='ENABLED'
      AND HS.WAVE_STATUS='WAVE_LIVE';

    CREATE TEMPORARY TABLE tmp_station_demand1 AS
    SELECT * FROM tmp_station_demand;

    
    SELECT COUNT(DISTINCT OBM.BOT_ID)
      INTO V_GlobalInflightBots
    FROM order_bin_mapping OBM
    WHERE OBM.TYPE = 'RACK_PICK'
      AND OBM.STATUS IN ('TASK_ALLOCATED','BIN_PICKED')
      AND OBM.BOT_ID IS NOT NULL;

    
    SELECT COUNT(DISTINCT W.Wave_ID)
      INTO V_OtherWaveCount
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    IF V_OtherWaveCount > 0 THEN
        IF V_TotalBots < (V_NoBotSA * V_OtherWaveCount) THEN

            SET V_SpecialUsed = FLOOR(V_TotalBots / V_OtherWaveCount);

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            LEFT JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_SpecialUsed,0) > 0
                    THEN V_SpecialUsed
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            LEFT JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_SpecialUsed,0) > 0
                    THEN V_SpecialUsed
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            LEFT JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_SpecialUsed > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_SpecialUsed,0) > 0
                    THEN V_SpecialUsed
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

        ELSE
            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            LEFT JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_NoBotSA > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_NoBotSA > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_NoBotSA,0) > 0
                    THEN V_NoBotSA
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            LEFT JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_NoBotBL > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_NoBotBL > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_NoBotBL,0) > 0
                    THEN V_NoBotBL
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS    ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W           ON W.Wave_ID      = HS.Wave_ID
            LEFT JOIN tmp_station_demand TSD  ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_NoBotLA > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_NoBotLA > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_NoBotLA,0) > 0
                    THEN V_NoBotLA
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
        END IF;
    END IF;

    
    SELECT IFNULL(SUM(WR.BOT_COUNT_CURRENT), 0)
      INTO V_SpecialUsed
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE NOT IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    
    SET V_FreeBots = V_TotalBots - IFNULL(V_SpecialUsed,0) - IFNULL(V_GlobalInflightBots,0);
    IF V_FreeBots < 0 THEN SET V_FreeBots = 0; END IF;

    
    UPDATE tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    SET WR.BOT_COUNT_CURRENT = IFNULL(TSD.INFLIGHT_BOT_CNT,0)
    WHERE W.WAVE_TYPE IN ('PICK','PUT')
      AND HS.STATUS='ENABLED'
      AND HS.WAVE_STATUS='WAVE_LIVE';

    
    CREATE TEMPORARY TABLE tmp_live_pick AS
    SELECT
        ROW_NUMBER() OVER (ORDER BY HS.STATION_ID) AS RN,
        HS.STATION_ID
    FROM hw_station_master HS
    JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
    WHERE HS.STATUS='ENABLED'
      AND HS.WAVE_STATUS='WAVE_LIVE'
      AND W.WAVE_TYPE='PICK';

    SELECT COUNT(*) INTO V_PickCount FROM tmp_live_pick;

    
    CREATE TEMPORARY TABLE tmp_live_put AS
    SELECT
        ROW_NUMBER() OVER (ORDER BY HS.STATION_ID) AS RN,
        HS.STATION_ID
    FROM hw_station_master HS
    JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
    WHERE HS.STATUS='ENABLED'
      AND HS.WAVE_STATUS='WAVE_LIVE'
      AND W.WAVE_TYPE='PUT';

    SELECT COUNT(*) INTO V_PutCount FROM tmp_live_put;

    
    IF V_FreeBots > 0 THEN

        
        SET V_i = 1;
        WHILE V_i <= V_PickCount AND V_FreeBots > 0 DO
            SELECT STATION_ID INTO V_StationId FROM tmp_live_pick WHERE RN = V_i;

            SELECT
                IFNULL(WR.BOT_COUNT_CURRENT,0),
                IFNULL(TSD.BACKLOG,0),
                IFNULL(WR.MAX_BOT_COUNT_PICK,0)
            INTO
                V_CurrentBots, V_Backlog, V_MaxPick
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
            JOIN wave_master W ON W.Wave_ID=HS.Wave_ID
            LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
            WHERE WR.STATION_ID = V_StationId
              AND W.WAVE_TYPE='PICK';

            IF V_Backlog > 0 AND V_CurrentBots = 0 AND V_CurrentBots < V_MaxPick THEN
                UPDATE tmp_wave_station_rule_mapping
                SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                WHERE STATION_ID = V_StationId;
                SET V_FreeBots = V_FreeBots - 1;
            END IF;

            SET V_i = V_i + 1;
        END WHILE;

        
        SET V_i = 1;
        WHILE V_i <= V_PutCount AND V_FreeBots > 0 DO
            SELECT STATION_ID INTO V_StationId FROM tmp_live_put WHERE RN = V_i;

            SELECT
                IFNULL(WR.BOT_COUNT_CURRENT,0),
                IFNULL(TSD.BACKLOG,0),
                IFNULL(WR.MAX_BOT_COUNT_PUT,0)
            INTO
                V_CurrentBots, V_Backlog, V_MaxPut
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
            JOIN wave_master W ON W.Wave_ID=HS.Wave_ID
            LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
            WHERE WR.STATION_ID = V_StationId
              AND W.WAVE_TYPE='PUT';

            IF V_Backlog > 0 AND V_CurrentBots = 0 AND V_CurrentBots < V_MaxPut THEN
                UPDATE tmp_wave_station_rule_mapping
                SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                WHERE STATION_ID = V_StationId;
                SET V_FreeBots = V_FreeBots - 1;
            END IF;

            SET V_i = V_i + 1;
        END WHILE;

    END IF;

    
    IF V_FreeBots > 0 THEN
        min_outer: WHILE V_FreeBots > 0 DO
            SET V_AnyIncrement = 0;

            
            IF V_PickCount > 0 THEN
                SET V_i = 1;
                WHILE V_i <= V_PickCount AND V_FreeBots > 0 DO
                    SET V_RN = V_PickPtr;
                    SELECT STATION_ID INTO V_StationId FROM tmp_live_pick WHERE RN = V_RN;

                    SELECT
                        IFNULL(WR.BOT_COUNT_CURRENT,0),
                        IFNULL(TSD.BACKLOG,0),
                        IFNULL(WR.MIN_BOT_COUNT_PICK,0),
                        IFNULL(WR.MAX_BOT_COUNT_PICK,0)
                    INTO
                        V_CurrentBots, V_Backlog, V_MinPick, V_MaxPick
                    FROM tmp_wave_station_rule_mapping WR
                    JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
                    JOIN wave_master W ON W.Wave_ID=HS.Wave_ID
                    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                    WHERE WR.STATION_ID = V_StationId
                      AND W.WAVE_TYPE='PICK';

                    IF V_Backlog > 0 AND V_CurrentBots < V_MinPick AND V_CurrentBots < V_MaxPick THEN
                        UPDATE tmp_wave_station_rule_mapping
                        SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                        WHERE STATION_ID = V_StationId;

                        SET V_FreeBots = V_FreeBots - 1;
                        SET V_AnyIncrement = 1;
                    END IF;

                    SET V_PickPtr = V_PickPtr + 1;
                    IF V_PickPtr > V_PickCount THEN SET V_PickPtr = 1; END IF;

                    SET V_i = V_i + 1;
                END WHILE;
            END IF;

            
            IF V_PutCount > 0 THEN
                SET V_i = 1;
                WHILE V_i <= V_PutCount AND V_FreeBots > 0 DO
                    SET V_RN = V_PutPtr;
                    SELECT STATION_ID INTO V_StationId FROM tmp_live_put WHERE RN = V_RN;

                    SELECT
                        IFNULL(WR.BOT_COUNT_CURRENT,0),
                        IFNULL(TSD.BACKLOG,0),
                        IFNULL(WR.MIN_BOT_COUNT_PUT,0),
                        IFNULL(WR.MAX_BOT_COUNT_PUT,0)
                    INTO
                        V_CurrentBots, V_Backlog, V_MinPut, V_MaxPut
                    FROM tmp_wave_station_rule_mapping WR
                    JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
                    JOIN wave_master W ON W.Wave_ID=HS.Wave_ID
                    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                    WHERE WR.STATION_ID = V_StationId
                      AND W.WAVE_TYPE='PUT';

                    IF V_Backlog > 0 AND V_CurrentBots < V_MinPut AND V_CurrentBots < V_MaxPut THEN
                        UPDATE tmp_wave_station_rule_mapping
                        SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                        WHERE STATION_ID = V_StationId;

                        SET V_FreeBots = V_FreeBots - 1;
                        SET V_AnyIncrement = 1;
                    END IF;

                    SET V_PutPtr = V_PutPtr + 1;
                    IF V_PutPtr > V_PutCount THEN SET V_PutPtr = 1; END IF;

                    SET V_i = V_i + 1;
                END WHILE;
            END IF;

            IF V_AnyIncrement = 0 THEN
                LEAVE min_outer;
            END IF;
        END WHILE min_outer;
    END IF;

    
    IF V_FreeBots > 0 THEN
        loop1_outer: WHILE V_FreeBots > 0 DO
            SET V_AnyIncrement = 0;

            
            IF V_PickCount > 0 THEN
                SET V_i = 1;
                WHILE V_i <= V_PickCount AND V_FreeBots > 0 DO
                    SET V_RN = V_PickPtr;
                    SELECT STATION_ID INTO V_StationId FROM tmp_live_pick WHERE RN = V_RN;

                    SELECT
                        IFNULL(WR.BOT_COUNT_CURRENT,0),
                        IFNULL(TSD.BACKLOG,0),
                        IFNULL(TSD.EFFECTIVE_DEMAND,0),
                        IFNULL(WR.MAX_BOT_COUNT_PICK,0)
                    INTO
                        V_CurrentBots, V_Backlog, V_EffectiveDemand, V_MaxPick
                    FROM tmp_wave_station_rule_mapping WR
                    JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
                    JOIN wave_master W ON W.Wave_ID=HS.Wave_ID
                    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                    WHERE WR.STATION_ID = V_StationId
                      AND W.WAVE_TYPE='PICK';

                    SET V_Residual = GREATEST(0, V_EffectiveDemand - V_CurrentBots);

                    IF V_Backlog > 0 AND V_Residual > 0 AND V_CurrentBots < V_MaxPick THEN
                        UPDATE tmp_wave_station_rule_mapping
                        SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                        WHERE STATION_ID = V_StationId;

                        SET V_FreeBots = V_FreeBots - 1;
                        SET V_AnyIncrement = 1;
                    END IF;

                    SET V_PickPtr = V_PickPtr + 1;
                    IF V_PickPtr > V_PickCount THEN SET V_PickPtr = 1; END IF;

                    SET V_i = V_i + 1;
                END WHILE;
            END IF;

            
            IF V_PutCount > 0 THEN
                SET V_i = 1;
                WHILE V_i <= V_PutCount AND V_FreeBots > 0 DO
                    SET V_RN = V_PutPtr;
                    SELECT STATION_ID INTO V_StationId FROM tmp_live_put WHERE RN = V_RN;

                    SELECT
                        IFNULL(WR.BOT_COUNT_CURRENT,0),
                        IFNULL(TSD.BACKLOG,0),
                        IFNULL(TSD.EFFECTIVE_DEMAND,0),
                        IFNULL(WR.MAX_BOT_COUNT_PUT,0)
                    INTO
                        V_CurrentBots, V_Backlog, V_EffectiveDemand, V_MaxPut
                    FROM tmp_wave_station_rule_mapping WR
                    JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
                    JOIN wave_master W ON W.Wave_ID=HS.Wave_ID
                    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                    WHERE WR.STATION_ID = V_StationId
                      AND W.WAVE_TYPE='PUT';

                    SET V_Residual = GREATEST(0, V_EffectiveDemand - V_CurrentBots);

                    IF V_Backlog > 0 AND V_Residual > 0 AND V_CurrentBots < V_MaxPut THEN
                        UPDATE tmp_wave_station_rule_mapping
                        SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                        WHERE STATION_ID = V_StationId;

                        SET V_FreeBots = V_FreeBots - 1;
                        SET V_AnyIncrement = 1;
                    END IF;

                    SET V_PutPtr = V_PutPtr + 1;
                    IF V_PutPtr > V_PutCount THEN SET V_PutPtr = 1; END IF;

                    SET V_i = V_i + 1;
                END WHILE;
            END IF;

            IF V_AnyIncrement = 0 THEN
                LEAVE loop1_outer;
            END IF;

        END WHILE loop1_outer;
    END IF;

    
    IF V_FreeBots > 0 AND V_PutCount > 0 THEN
        put_upper_outer: WHILE V_FreeBots > 0 DO
            SET V_AnyIncrement = 0;

            SET V_i = 1;
            WHILE V_i <= V_PutCount AND V_FreeBots > 0 DO
                SET V_RN = V_PutPtr;
                SELECT STATION_ID INTO V_StationId FROM tmp_live_put WHERE RN = V_RN;

                SELECT
                    IFNULL(WR.BOT_COUNT_CURRENT,0),
                    IFNULL(TSD.BACKLOG,0),
                    IFNULL(TSD.EFFECTIVE_DEMAND,0),
                    IFNULL(WR.UPPER_BOT_COUNT_PUT,0)
                INTO
                    V_CurrentBots, V_Backlog, V_EffectiveDemand, V_UpperPut
                FROM tmp_wave_station_rule_mapping WR
                JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
                JOIN wave_master W ON W.Wave_ID=HS.Wave_ID
                LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                WHERE WR.STATION_ID = V_StationId
                  AND W.WAVE_TYPE='PUT';

                SET V_Residual = GREATEST(0, V_EffectiveDemand - V_CurrentBots);

                IF V_Backlog > 0 AND V_Residual > 0 AND V_CurrentBots < V_UpperPut THEN
                    UPDATE tmp_wave_station_rule_mapping
                    SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                    WHERE STATION_ID = V_StationId;

                    SET V_FreeBots = V_FreeBots - 1;
                    SET V_AnyIncrement = 1;
                END IF;

                SET V_PutPtr = V_PutPtr + 1;
                IF V_PutPtr > V_PutCount THEN SET V_PutPtr = 1; END IF;

                SET V_i = V_i + 1;
            END WHILE;

            IF V_AnyIncrement = 0 THEN
                LEAVE put_upper_outer;
            END IF;

        END WHILE put_upper_outer;
    END IF;

    
    UPDATE wave_station_rule_mapping WR
    JOIN tmp_wave_station_rule_mapping TWR
      ON WR.WAVE_STATION_RULE_MAPPING_ID = TWR.WAVE_STATION_RULE_MAPPING_ID
    SET WR.BOT_COUNT_CURRENT = TWR.BOT_COUNT_CURRENT;

    
    SELECT
        HS.WAVE_ID,
        W.WAVE_TYPE,
        WR.STATION_ID,
        WR.BOT_COUNT_CURRENT,
        WR.BOT_COUNT_DEFAULT,

        IFNULL(TSD.RACK_PENDING_CNT,0)            AS RACK_PENDING_CNT,
        IFNULL(TSD.RACK_PENDING_ONLY_CNT,0)       AS RACK_PENDING_ONLY_CNT,
        IFNULL(TSD.STATION_PICK_PENDING_CNT,0)    AS STATION_PICK_PENDING_CNT,

        IFNULL(TSD.PRE_ON_STATION_CNT,0)          AS PRE_ON_STATION_CNT,
        IFNULL(TSD.INFLIGHT_BOT_CNT,0)            AS INFLIGHT_BOT_CNT,
        IFNULL(TSD.BACKLOG,0)                     AS BACKLOG,
        IFNULL(TSD.EFFECTIVE_DEMAND,0)            AS EFFECTIVE_DEMAND,
        GREATEST(0, IFNULL(TSD.EFFECTIVE_DEMAND,0) - WR.BOT_COUNT_CURRENT) AS RESIDUAL,

        WR.MAX_BOT_COUNT_PICK,
        WR.MIN_BOT_COUNT_PICK,
        WR.MAX_BOT_COUNT_PUT,
        WR.MIN_BOT_COUNT_PUT,
        WR.UPPER_BOT_COUNT_PUT
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE HS.STATUS='ENABLED'
      AND HS.WAVE_STATUS='WAVE_LIVE';

    
    SELECT
        V_TotalBots                  AS TOTAL_ENABLED_AUTO,
        V_SpecialUsed                AS SPECIAL_USED,
        V_GlobalInflightBots         AS GLOBAL_DISTINCT_INFLIGHT,
        (V_TotalBots - V_SpecialUsed - V_GlobalInflightBots) AS FREE_POOL_START,
        V_FreeBots                   AS FREE_POOL_END,
        (SELECT IFNULL(SUM(GREATEST(0, IFNULL(TSD.EFFECTIVE_DEMAND,0) - WR.BOT_COUNT_CURRENT)),0)
           FROM tmp_wave_station_rule_mapping WR
           JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
           JOIN wave_master W ON W.Wave_ID=HS.Wave_ID
           LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
          WHERE HS.STATUS='ENABLED' AND HS.WAVE_STATUS='WAVE_LIVE'
            AND W.WAVE_TYPE IN ('PICK','PUT')) AS TOTAL_RESIDUAL_END;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_pick;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_put;

END */$$
DELIMITER ;

/* Procedure structure for procedure `BOT_ALLOCATION_ENGINE_V2` */

/*!50003 DROP PROCEDURE IF EXISTS  `BOT_ALLOCATION_ENGINE_V2` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `BOT_ALLOCATION_ENGINE_V2`()
BEGIN
    

    
    DECLARE V_NoBot                      INT DEFAULT 0;  
    DECLARE V_OtherWaveCount             INT DEFAULT 0;  
    DECLARE V_AllocatedPBotsPerStation   INT DEFAULT 0;  
    DECLARE V_PendingBots                INT DEFAULT 0;  
    DECLARE V_PickStation                INT DEFAULT 0;  
    DECLARE V_PutStation                 INT DEFAULT 0;  
    DECLARE V_ActiveStation              INT DEFAULT 0;  
    DECLARE V_BotforOtherWave            INT DEFAULT 0;  
    DECLARE V_BotStationDemand           INT DEFAULT 0;  

    DECLARE V_NoBotSA                    INT DEFAULT 0;  
    DECLARE V_NoBotBL                    INT DEFAULT 0;  
    DECLARE V_NoBotLA                    INT DEFAULT 0;  

    

    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
   
    
    CREATE TEMPORARY TABLE tmp_wave_station_rule_mapping
    SELECT * FROM wave_station_rule_mapping;
    
    UPDATE tmp_wave_station_rule_mapping SET BOT_COUNT_CURRENT=0;
    
    
    CREATE TEMPORARY TABLE tmp_station_demand AS 
    SELECT A.STATION_ID,W.WAVE_TYPE,A.RACK_PENDING_CNT,A.STATION_PICK_PENDING_CNT
    FROM (
	    SELECT OBM.STATION_ID, SUM( CASE WHEN OBM.TYPE = 'RACK_PICK' AND 
	    OBM.STATUS IN ('PENDING','TASK_ALLOCATED','BIN_PICKED') 
	    THEN 1 ELSE 0 END ) AS RACK_PENDING_CNT, 
	    
	    SUM( CASE WHEN (OBM.TYPE = 'STATION_PICK' AND OBM.STATUS = 'PENDING') 
	    
	    THEN 1 ELSE 0 END ) AS STATION_PICK_PENDING_CNT 
	    FROM order_bin_mapping OBM
	     GROUP BY OBM.STATION_ID
	  ) A
    JOIN hw_station_master HS ON HS.STATION_ID = A.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE (A.RACK_PENDING_CNT>0  OR  A.STATION_PICK_PENDING_CNT>0);
    
    

    SELECT COUNT(*) INTO V_NoBot
    FROM bot_master
    WHERE AUTO_MANUAL = 'auto'
      AND STATUS      = 'ENABLED';

    

    SELECT KEY_VALUE INTO V_NoBotSA FROM master_config WHERE KEY_NAME = 'MAX_BOT_SA';
    SELECT KEY_VALUE INTO V_NoBotBL FROM master_config WHERE KEY_NAME = 'MAX_BOT_BL';
    SELECT KEY_VALUE INTO V_NoBotLA FROM master_config WHERE KEY_NAME = 'MAX_BOT_LA';

    SET V_NoBotSA = IFNULL(V_NoBotSA, 0);
    SET V_NoBotBL = IFNULL(V_NoBotBL, 0);
    SET V_NoBotLA = IFNULL(V_NoBotLA, 0);


    

    IF V_NoBot < (V_NoBotSA + V_NoBotBL + V_NoBotLA) THEN

        
        SELECT COUNT(DISTINCT W.Wave_ID)
        INTO V_OtherWaveCount
        FROM tmp_wave_station_rule_mapping WR
        JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
        JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
        WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
          AND HS.STATUS      = 'ENABLED'
          AND HS.WAVE_STATUS = 'WAVE_LIVE';

        IF V_OtherWaveCount > 0 THEN
            SET V_BotforOtherWave = FLOOR(V_NoBot / V_OtherWaveCount);

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = V_BotforOtherWave
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = V_BotforOtherWave
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = V_BotforOtherWave
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
        END IF;

    ELSE
        

        UPDATE tmp_wave_station_rule_mapping WR
        JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
        JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
        SET WR.BOT_COUNT_CURRENT = V_NoBotSA
        WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
          AND HS.STATUS      = 'ENABLED'
          AND HS.WAVE_STATUS = 'WAVE_LIVE';

        UPDATE tmp_wave_station_rule_mapping WR
        JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
        JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
        SET WR.BOT_COUNT_CURRENT = V_NoBotBL
        WHERE W.WAVE_TYPE   = 'BIN_LOADING'
          AND HS.STATUS      = 'ENABLED'
          AND HS.WAVE_STATUS = 'WAVE_LIVE';

        UPDATE tmp_wave_station_rule_mapping WR
        JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
        JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
        SET WR.BOT_COUNT_CURRENT = V_NoBotLA
        WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
          AND HS.STATUS      = 'ENABLED'
          AND HS.WAVE_STATUS = 'WAVE_LIVE';
    END IF;

    
           
    SELECT SUM(WR.BOT_COUNT_CURRENT)
    INTO V_OtherWaveCount
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE NOT IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SET V_NoBot = V_NoBot - IFNULL(V_OtherWaveCount, 0);
    IF V_NoBot < 0 THEN
        SET V_NoBot = 0;
    END IF;

    

    SELECT COUNT(*)
    INTO V_ActiveStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    

    IF IFNULL(V_ActiveStation, 0) > 0 THEN

        
        IF FLOOR(V_NoBot / V_ActiveStation) > 0 THEN

            
            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID           
            INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=HS.STATION_ID
            SET WR.BOT_COUNT_CURRENT =
                CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 AND  FLOOR(V_NoBot / V_ActiveStation)>TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN  IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 AND   FLOOR(V_NoBot / V_ActiveStation)>TSD.STATION_PICK_PENDING_CNT
                    THEN  TSD.STATION_PICK_PENDING_CNT
                    WHEN FLOOR(V_NoBot / V_ActiveStation) >=
                         (CASE WHEN W.WAVE_TYPE = 'PUT'
                               THEN WR.MIN_BOT_COUNT_PUT
                               ELSE WR.MIN_BOT_COUNT_PICK
                          END)
                    THEN (CASE WHEN W.WAVE_TYPE = 'PUT'
                               THEN WR.MIN_BOT_COUNT_PUT
                               ELSE WR.MIN_BOT_COUNT_PICK
                          END)
                    ELSE 1
                END
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

        ELSE
            
            
            

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = 0
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN (
                SELECT HS.STATION_ID,
                       HS.Wave_ID,
                       ROW_NUMBER() OVER (
                           ORDER BY CASE WHEN W.WAVE_TYPE = 'PICK' THEN 1 ELSE 2 END,
                                    HS.STATION_ID
                       ) AS SRank
                FROM hw_station_master HS
                INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE'
            ) AS X ON X.STATION_ID = WR.STATION_ID
            INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
            INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = 1
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND X.SRank <= V_NoBot;

            SET V_PendingBots = 0;  
        END IF;

        IF V_PendingBots < 0 THEN
            SET V_PendingBots = 0;
        END IF;

        
      
        IF V_PendingBots > 0 THEN

            
           
            SELECT COUNT(*)
            INTO V_PickStation
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE = 'PICK'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
              
           
            IF V_PickStation > 0 THEN
                SET V_AllocatedPBotsPerStation = FLOOR(V_PendingBots / V_PickStation);

                IF V_AllocatedPBotsPerStation > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                    SET WR.BOT_COUNT_CURRENT =
                     CASE
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.RACK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PICK)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.STATION_PICK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PICK)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)=0 
                     THEN LEAST((WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PICK)
                     END                      
                    WHERE W.WAVE_TYPE = 'PICK'
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE';
                END IF;
            END IF;

            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            IF V_PendingBots < 0 THEN
                SET V_PendingBots = 0;
            END IF;

            
           
            SELECT COUNT(*)
            INTO V_PutStation
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE = 'PUT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
              
           
            IF V_PutStation > 0 AND V_PendingBots > 0 THEN
                SET V_AllocatedPBotsPerStation = FLOOR(V_PendingBots / V_PutStation);

                IF V_AllocatedPBotsPerStation > 0 THEN
                    UPDATE tmp_wave_station_rule_mapping WR
                    INNER JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                    INNER JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                    INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                    SET WR.BOT_COUNT_CURRENT = 
                    CASE
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.RACK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PUT)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.STATION_PICK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PUT)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)=0 
                     THEN LEAST((WR.BOT_COUNT_CURRENT + V_AllocatedPBotsPerStation),WR.MAX_BOT_COUNT_PUT)
                     END  
                    WHERE W.WAVE_TYPE = 'PUT'
                      AND HS.STATUS      = 'ENABLED'
                      AND HS.WAVE_STATUS = 'WAVE_LIVE' ;
                END IF;
            END IF;
            
            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
            INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            IF V_PendingBots < 0 THEN
                SET V_PendingBots = 0;
            END IF;

            

            IF V_PickStation > 0 AND V_PendingBots > 0 THEN
                UPDATE tmp_wave_station_rule_mapping WR
                INNER JOIN (
			SELECT  STATION_ID,Wave_ID,ROW_NUMBER() OVER (ORDER BY STATION_ID) AS SRank
			FROM (
			         SELECT HS.STATION_ID,HS.Wave_ID
			         FROM hw_station_master HS
			         INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
			         WHERE W.WAVE_TYPE = 'PICK'
			          AND HS.STATUS      = 'ENABLED'
			          AND HS.WAVE_STATUS = 'WAVE_LIVE'
			   ) A
                ) AS X ON X.STATION_ID = WR.STATION_ID
                INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
                INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                SET WR.BOT_COUNT_CURRENT =
                     CASE
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.RACK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + 1),WR.MAX_BOT_COUNT_PICK)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.STATION_PICK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + 1),WR.MAX_BOT_COUNT_PICK)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)=0 
                     THEN LEAST((WR.BOT_COUNT_CURRENT + 1),WR.MAX_BOT_COUNT_PICK)
                     END  
                WHERE W.WAVE_TYPE = 'PICK'
                  AND X.SRank     <= V_PendingBots;

                SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
                INTO V_PendingBots
                FROM tmp_wave_station_rule_mapping WR
                JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE';

                IF V_PendingBots < 0 THEN
                    SET V_PendingBots = 0;
                END IF;
            END IF;

            
            IF V_PutStation > 0 AND V_PendingBots > 0 THEN
                UPDATE tmp_wave_station_rule_mapping WR
                INNER JOIN (
		    SELECT  STATION_ID,Wave_ID,ROW_NUMBER() OVER (ORDER BY STATION_ID) AS SRank
		    FROM (
			    SELECT HS.STATION_ID,HS.Wave_ID
			    FROM hw_station_master HS
			    INNER JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
			    WHERE W.WAVE_TYPE = 'PUT'
			      AND HS.STATUS      = 'ENABLED'
			      AND HS.WAVE_STATUS = 'WAVE_LIVE'
		       ) A
                ) AS X ON X.STATION_ID = WR.STATION_ID
                INNER JOIN wave_master W ON W.Wave_ID = X.Wave_ID
                INNER JOIN tmp_station_demand TSD ON TSD.STATION_ID=WR.STATION_ID
                SET WR.BOT_COUNT_CURRENT =
                     CASE
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.RACK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + 1),WR.UPPER_BOT_COUNT_PUT)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)>0 
                     THEN LEAST(TSD.STATION_PICK_PENDING_CNT,(WR.BOT_COUNT_CURRENT + 1),WR.UPPER_BOT_COUNT_PUT)
                     WHEN IFNULL(TSD.RACK_PENDING_CNT,0)=0 AND IFNULL(TSD.STATION_PICK_PENDING_CNT,0)=0 
                     THEN LEAST((WR.BOT_COUNT_CURRENT + 1),WR.UPPER_BOT_COUNT_PUT)
                     END 
                WHERE W.WAVE_TYPE = 'PUT'
                  AND X.SRank     <= V_PendingBots;

                SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
                INTO V_PendingBots
                FROM tmp_wave_station_rule_mapping WR
                JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
                JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE';

                IF V_PendingBots < 0 THEN
                    SET V_PendingBots = 0;
                END IF;
            END IF;

        END IF; 

    END IF; 

    

    UPDATE wave_station_rule_mapping WR
    JOIN tmp_wave_station_rule_mapping TWR
      ON WR.WAVE_STATION_RULE_MAPPING_ID = TWR.WAVE_STATION_RULE_MAPPING_ID
    SET WR.BOT_COUNT_CURRENT = TWR.BOT_COUNT_CURRENT;

    

 
    SELECT
        HS.WAVE_ID,
        W.WAVE_TYPE,
        WR.STATION_ID,
        WR.BOT_COUNT_CURRENT,
        WR.BOT_COUNT_DEFAULT,
        WR.MAX_BOT_COUNT_PICK,
        WR.MIN_BOT_COUNT_PICK,
        WR.MAX_BOT_COUNT_PUT,
        WR.MIN_BOT_COUNT_PUT,
        WR.UPPER_BOT_COUNT_PUT
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;

END */$$
DELIMITER ;

/* Procedure structure for procedure `BOT_ALLOCATION_ENGINE_V4` */

/*!50003 DROP PROCEDURE IF EXISTS  `BOT_ALLOCATION_ENGINE_V4` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `BOT_ALLOCATION_ENGINE_V4`()
BEGIN
    

    
    DECLARE V_NoBot                      INT DEFAULT 0;  
    DECLARE V_OtherWaveCount             INT DEFAULT 0;
    DECLARE V_AllocatedPBotsPerStation   INT DEFAULT 0;
    DECLARE V_PendingBots                INT DEFAULT 0;
    DECLARE V_PickStation                INT DEFAULT 0;
    DECLARE V_PutStation                 INT DEFAULT 0;
    DECLARE V_ActiveStation              INT DEFAULT 0;
    DECLARE V_BotforOtherWave            INT DEFAULT 0;
    DECLARE V_BotStationDemand           INT DEFAULT 0;
    DECLARE V_BotDemandinPick            INT DEFAULT 0;

    DECLARE V_NoBotSA                    INT DEFAULT 0;
    DECLARE V_NoBotBL                    INT DEFAULT 0;
    DECLARE V_NoBotLA                    INT DEFAULT 0;

    DECLARE V_SAStation                  INT DEFAULT 0;
    DECLARE V_BLStation                  INT DEFAULT 0;
    DECLARE V_LAStation                  INT DEFAULT 0;
    DECLARE V_SpecialStations            INT DEFAULT 0;
    DECLARE V_SpecialAllocated           INT DEFAULT 0;
    DECLARE V_PerStation                 INT DEFAULT 0;
    DECLARE V_RemainingForType           INT DEFAULT 0;

    
    DECLARE V_TotalDemand                INT DEFAULT 0;
    DECLARE V_AnyIncrement               INT DEFAULT 0;
    DECLARE V_TotalRN                    INT DEFAULT 0;
    DECLARE V_CurrentRN                  INT DEFAULT 0;

    DECLARE V_StationId                  INT DEFAULT 0;
    DECLARE V_WaveType                   VARCHAR(50);
    DECLARE V_CurrentStationBots         INT DEFAULT 0;
    DECLARE V_RackPending                INT DEFAULT 0;
    DECLARE V_StationPickPending         INT DEFAULT 0;
    DECLARE V_MaxPick                    INT DEFAULT 0;
    DECLARE V_MaxPut                     INT DEFAULT 0;
    DECLARE V_UpperPut                   INT DEFAULT 0;
    DECLARE V_StationDemand              INT DEFAULT 0;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_pickput;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_put;

    
    CREATE TEMPORARY TABLE tmp_wave_station_rule_mapping
    SELECT * FROM wave_station_rule_mapping;

    UPDATE tmp_wave_station_rule_mapping
    SET BOT_COUNT_CURRENT = 0;

    
    CREATE TEMPORARY TABLE tmp_station_demand AS 
    SELECT A.STATION_ID,
           W.WAVE_TYPE,
           A.RACK_PENDING_CNT,
           A.STATION_PICK_PENDING_CNT
    FROM (
        SELECT OBM.STATION_ID,
               SUM(
                   CASE
                       WHEN OBM.TYPE = 'RACK_PICK'
                            AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED','BIN_PICKED')
                       THEN 1 ELSE 0
                   END
               ) AS RACK_PENDING_CNT,
               SUM(
                   CASE
                       WHEN OBM.TYPE = 'STATION_PICK'
                            AND OBM.STATUS = 'PENDING'
                       THEN 1 ELSE 0
                   END
               ) AS STATION_PICK_PENDING_CNT
        FROM order_bin_mapping OBM
        GROUP BY OBM.STATION_ID
    ) A
    JOIN hw_station_master HS ON HS.STATION_ID = A.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    WHERE (A.RACK_PENDING_CNT > 0 OR A.STATION_PICK_PENDING_CNT > 0);

    CREATE TEMPORARY TABLE tmp_station_demand1 AS 
    SELECT * FROM tmp_station_demand;

    

    SELECT COUNT(*) INTO V_NoBot
    FROM bot_master
    WHERE AUTO_MANUAL = 'auto'
      AND STATUS      = 'ENABLED';

    

    SELECT KEY_VALUE INTO V_NoBotSA FROM master_config WHERE KEY_NAME = 'MAX_BOT_SA';
    SELECT KEY_VALUE INTO V_NoBotBL FROM master_config WHERE KEY_NAME = 'MAX_BOT_BL';
    SELECT KEY_VALUE INTO V_NoBotLA FROM master_config WHERE KEY_NAME = 'MAX_BOT_LA';

    SET V_NoBotSA = IFNULL(V_NoBotSA, 0);
    SET V_NoBotBL = IFNULL(V_NoBotBL, 0);
    SET V_NoBotLA = IFNULL(V_NoBotLA, 0);

    

    SELECT COUNT(DISTINCT W.Wave_ID)
      INTO V_OtherWaveCount
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    IF V_OtherWaveCount > 0 THEN
        IF V_NoBot < (V_NoBotSA * V_OtherWaveCount) THEN

            SET V_BotforOtherWave = FLOOR(V_NoBot / V_OtherWaveCount);

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_BotforOtherWave > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_BotforOtherWave > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    when ifnull(V_BotforOtherWave,0) > 0
                    then V_BotforOtherWave
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_BotforOtherWave > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_BotforOtherWave > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_BotforOtherWave,0) > 0
                    THEN V_BotforOtherWave
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_BotforOtherWave > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_BotforOtherWave > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_BotforOtherWave,0) > 0
                    THEN V_BotforOtherWave
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            SELECT IFNULL(V_NoBot - SUM(WR.BOT_COUNT_CURRENT), 0)
              INTO V_BotforOtherWave
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE NOT IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN (
                SELECT HS.STATION_ID,
                       HS.Wave_ID,
                       ROW_NUMBER() OVER (
                           ORDER BY CASE W.WAVE_TYPE
                                      WHEN 'STOCK_AUDIT'    THEN 1
                                      WHEN 'BIN_LOADING'    THEN 2
                                      WHEN 'LOCATION_AUDIT' THEN 3
                                      ELSE 4
                                    END,
                                    HS.STATION_ID
                       ) AS SRank
                FROM hw_station_master HS
                JOIN wave_master W ON W.Wave_ID = HS.Wave_ID
                WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE'
            ) X ON X.STATION_ID = WR.STATION_ID
            JOIN wave_master W ON W.Wave_ID = X.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND WR.BOT_COUNT_CURRENT+1 > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND WR.BOT_COUNT_CURRENT+1 > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    when IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    then 0
                    WHEN IFNULL(V_BotforOtherWave,0) > 0
                    THEN WR.BOT_COUNT_CURRENT+1
                    ELSE 1
                END
            WHERE X.SRank <= V_BotforOtherWave;

        ELSE
            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_NoBotSA > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_NoBotSA > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_NoBotSA,0) > 0
                    THEN V_NoBotSA
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_NoBotBL > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_NoBotBL > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_NoBotBL,0) > 0
                    THEN V_NoBotBL
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND V_NoBotLA > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND V_NoBotLA > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) = 0
                    THEN 0
                    WHEN IFNULL(V_NoBotLA,0) > 0
                    THEN V_NoBotLA
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
        END IF;
    END IF;

    
    SELECT IFNULL(SUM(WR.BOT_COUNT_CURRENT), 0)
      INTO V_BotforOtherWave
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE NOT IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SET V_NoBot = V_NoBot - V_BotforOtherWave;

    

    SELECT COUNT(*)
      INTO V_ActiveStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE W.WAVE_TYPE IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SELECT COUNT(*)
      INTO V_PickStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE W.WAVE_TYPE = 'PICK'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SELECT COUNT(*)
      INTO V_PutStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE W.WAVE_TYPE = 'PUT'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    

    IF IFNULL(V_ActiveStation, 0) > 0 AND V_NoBot > 0 THEN

        IF FLOOR(V_NoBot / V_ActiveStation) > 0 THEN

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
            SET WR.BOT_COUNT_CURRENT =
                CASE
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) > 0
                         AND FLOOR(V_NoBot / V_ActiveStation) > TSD.RACK_PENDING_CNT
                    THEN TSD.RACK_PENDING_CNT
                    WHEN IFNULL(TSD.RACK_PENDING_CNT, 0) = 0
                         AND IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) > 0
                         AND FLOOR(V_NoBot / V_ActiveStation) > TSD.STATION_PICK_PENDING_CNT
                    THEN TSD.STATION_PICK_PENDING_CNT
                    WHEN FLOOR(V_NoBot / V_ActiveStation) >=
                         (CASE WHEN W.WAVE_TYPE = 'PUT'
                               THEN WR.MIN_BOT_COUNT_PUT
                               ELSE WR.MIN_BOT_COUNT_PICK
                          END)
                    THEN (CASE WHEN W.WAVE_TYPE = 'PICK'
                               THEN WR.MIN_BOT_COUNT_PICK
                               ELSE WR.MIN_BOT_COUNT_PUT
                          END)
                    ELSE 1
                END
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            SELECT (V_NoBot - SUM(WR.BOT_COUNT_CURRENT))
              INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

        ELSE
            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = 0
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN (
                SELECT HS.STATION_ID,
                       HS.Wave_ID,
                       ROW_NUMBER() OVER (
                           ORDER BY CASE WHEN W.WAVE_TYPE = 'PICK' THEN 1 ELSE 2 END,
                                    HS.STATION_ID
                       ) AS SRank
                FROM hw_station_master HS
                JOIN wave_master      W ON W.Wave_ID = HS.Wave_ID
                JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE'
            ) AS X ON X.STATION_ID = WR.STATION_ID
            JOIN wave_master W ON W.Wave_ID = X.Wave_ID
            SET WR.BOT_COUNT_CURRENT = 1
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND X.SRank <= V_NoBot;

            SET V_PendingBots = 0;
        END IF;

        IF V_PendingBots < 0 THEN
            SET V_PendingBots = 0;
        END IF;

        

        IF V_PendingBots > 0 THEN

            
            CREATE TEMPORARY TABLE tmp_live_pickput AS
            SELECT
                ROW_NUMBER() OVER (
                    ORDER BY CASE W.WAVE_TYPE WHEN 'PICK' THEN 1 ELSE 2 END,
                             HS.STATION_ID
                ) AS RN,
                HS.STATION_ID,
                HS.Wave_ID,
                W.WAVE_TYPE
            FROM hw_station_master HS
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            SELECT COUNT(*) INTO V_TotalRN FROM tmp_live_pickput;

            IF V_TotalRN > 0 THEN

                
                pickput_outer_loop: WHILE V_PendingBots > 0 DO

                    
                    SELECT SUM(
                               GREATEST(
                                   0,
                                   (IFNULL(TSD.RACK_PENDING_CNT, 0)
                                    + IFNULL(TSD.STATION_PICK_PENDING_CNT, 0))
                                   - WR.BOT_COUNT_CURRENT
                               )
                           )
                      INTO V_TotalDemand
                    FROM tmp_live_pickput LP
                    JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = LP.STATION_ID
                    JOIN tmp_station_demand TSD           ON TSD.STATION_ID = LP.STATION_ID;

                    IF IFNULL(V_TotalDemand, 0) <= 0 THEN
                        LEAVE pickput_outer_loop;
                    END IF;

                    SET V_AnyIncrement = 0;
                    SET V_CurrentRN    = 1;

                    
                    pickput_inner_loop: WHILE V_CurrentRN <= V_TotalRN AND V_PendingBots > 0 DO

                        SELECT
                            LP.STATION_ID,
                            LP.WAVE_TYPE,
                            WR.BOT_COUNT_CURRENT,
                            IFNULL(TSD.RACK_PENDING_CNT, 0),
                            IFNULL(TSD.STATION_PICK_PENDING_CNT, 0),
                            WR.MAX_BOT_COUNT_PICK,
                            WR.MAX_BOT_COUNT_PUT,
                            WR.UPPER_BOT_COUNT_PUT
                        INTO
                            V_StationId,
                            V_WaveType,
                            V_CurrentStationBots,
                            V_RackPending,
                            V_StationPickPending,
                            V_MaxPick,
                            V_MaxPut,
                            V_UpperPut
                        FROM tmp_live_pickput LP
                        JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = LP.STATION_ID
                        JOIN tmp_station_demand TSD           ON TSD.STATION_ID = LP.STATION_ID
                        WHERE LP.RN = V_CurrentRN;

                        SET V_StationDemand = V_RackPending + V_StationPickPending;

                        IF V_StationDemand > V_CurrentStationBots THEN
                            IF V_WaveType = 'PICK' AND V_CurrentStationBots < V_MaxPick THEN
                                UPDATE tmp_wave_station_rule_mapping
                                SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                                WHERE STATION_ID = V_StationId;

                                SET V_PendingBots  = V_PendingBots - 1;
                                SET V_AnyIncrement = 1;
                            ELSEIF V_WaveType = 'PUT' AND V_CurrentStationBots < V_MaxPut THEN
                                UPDATE tmp_wave_station_rule_mapping
                                SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                                WHERE STATION_ID = V_StationId;

                                SET V_PendingBots  = V_PendingBots - 1;
                                SET V_AnyIncrement = 1;
                            END IF;
                        END IF;

                        SET V_CurrentRN = V_CurrentRN + 1;
                    END WHILE pickput_inner_loop;

                    IF V_AnyIncrement = 0 THEN
                        LEAVE pickput_outer_loop;
                    END IF;

                END WHILE pickput_outer_loop;

            END IF;  

        END IF; 

        

        IF V_PendingBots > 0 AND V_PutStation > 0 THEN

            CREATE TEMPORARY TABLE tmp_live_put AS
            SELECT
                ROW_NUMBER() OVER (
                    ORDER BY HS.STATION_ID
                ) AS RN,
                HS.STATION_ID,
                HS.Wave_ID,
                W.WAVE_TYPE
            FROM hw_station_master HS
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
            WHERE W.WAVE_TYPE = 'PUT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            SELECT COUNT(*) INTO V_TotalRN FROM tmp_live_put;

            IF V_TotalRN > 0 THEN

                put_outer_loop: WHILE V_PendingBots > 0 DO

                    SELECT SUM(
                               GREATEST(
                                   0,
                                   (IFNULL(TSD.RACK_PENDING_CNT, 0)
                                    + IFNULL(TSD.STATION_PICK_PENDING_CNT, 0))
                                   - WR.BOT_COUNT_CURRENT
                               )
                           )
                      INTO V_TotalDemand
                    FROM tmp_live_put LP
                    JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = LP.STATION_ID
                    JOIN tmp_station_demand TSD           ON TSD.STATION_ID = LP.STATION_ID;

                    IF IFNULL(V_TotalDemand, 0) <= 0 THEN
                        LEAVE put_outer_loop;
                    END IF;

                    SET V_AnyIncrement = 0;
                    SET V_CurrentRN    = 1;

                    put_inner_loop: WHILE V_CurrentRN <= V_TotalRN AND V_PendingBots > 0 DO

                        SELECT
                            LP.STATION_ID,
                            WR.BOT_COUNT_CURRENT,
                            IFNULL(TSD.RACK_PENDING_CNT, 0),
                            IFNULL(TSD.STATION_PICK_PENDING_CNT, 0),
                            WR.MAX_BOT_COUNT_PUT,
                            WR.UPPER_BOT_COUNT_PUT
                        INTO
                            V_StationId,
                            V_CurrentStationBots,
                            V_RackPending,
                            V_StationPickPending,
                            V_MaxPut,
                            V_UpperPut
                        FROM tmp_live_put LP
                        JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = LP.STATION_ID
                        JOIN tmp_station_demand TSD           ON TSD.STATION_ID = LP.STATION_ID
                        WHERE LP.RN = V_CurrentRN;

                        SET V_StationDemand = V_RackPending + V_StationPickPending;

                        IF V_StationDemand > V_CurrentStationBots
                           AND V_CurrentStationBots < V_UpperPut THEN

                            UPDATE tmp_wave_station_rule_mapping
                            SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                            WHERE STATION_ID = V_StationId;

                            SET V_PendingBots  = V_PendingBots - 1;
                            SET V_AnyIncrement = 1;
                        END IF;

                        SET V_CurrentRN = V_CurrentRN + 1;
                    END WHILE put_inner_loop;

                    IF V_AnyIncrement = 0 THEN
                        LEAVE put_outer_loop;
                    END IF;

                END WHILE put_outer_loop;

            END IF; 

        END IF; 

    END IF; 


	
    

    SELECT
        HS.WAVE_ID,
        W.WAVE_TYPE,
        WR.STATION_ID,
        WR.BOT_COUNT_CURRENT,
        WR.BOT_COUNT_DEFAULT,
        IFNULL(TSD.RACK_PENDING_CNT, 0)         AS RACK_PENDING_CNT,
        IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) AS STATION_PICK_PENDING_CNT,
        WR.MAX_BOT_COUNT_PICK,
        WR.MIN_BOT_COUNT_PICK,
        WR.MAX_BOT_COUNT_PUT,
        WR.MIN_BOT_COUNT_PUT,
        WR.UPPER_BOT_COUNT_PUT
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    

    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_pickput;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_put;

END */$$
DELIMITER ;

/* Procedure structure for procedure `BOT_ALLOCATION_ENGINE_V5` */

/*!50003 DROP PROCEDURE IF EXISTS  `BOT_ALLOCATION_ENGINE_V5` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `BOT_ALLOCATION_ENGINE_V5`()
BEGIN
    

    
    DECLARE v_lock_ok INT DEFAULT 0;

    
    DECLARE V_NoBot                      INT DEFAULT 0;  
    DECLARE V_OtherWaveCount             INT DEFAULT 0;
    DECLARE V_PendingBots                INT DEFAULT 0;
    DECLARE V_PickStation                INT DEFAULT 0;
    DECLARE V_PutStation                 INT DEFAULT 0;
    DECLARE V_ActiveStation              INT DEFAULT 0;
    DECLARE V_BotforOtherWave            INT DEFAULT 0;

    DECLARE V_NoBotSA                    INT DEFAULT 0;
    DECLARE V_NoBotBL                    INT DEFAULT 0;
    DECLARE V_NoBotLA                    INT DEFAULT 0;

    
    DECLARE V_TotalDemand                INT DEFAULT 0;
    DECLARE V_AnyIncrement               INT DEFAULT 0;
    DECLARE V_TotalRN                    INT DEFAULT 0;
    DECLARE V_CurrentRN                  INT DEFAULT 0;

    DECLARE V_StationId                  INT DEFAULT 0;
    DECLARE V_WaveType                   VARCHAR(50);
    DECLARE V_CurrentStationBots         INT DEFAULT 0;
    DECLARE V_RackPending                INT DEFAULT 0;
    DECLARE V_StationPickPending         INT DEFAULT 0;
    DECLARE V_MaxPick                    INT DEFAULT 0;
    DECLARE V_MaxPut                     INT DEFAULT 0;
    DECLARE V_UpperPut                   INT DEFAULT 0;
    DECLARE V_StationDemand              INT DEFAULT 0;

    DECLARE V_BaseShare                  INT DEFAULT 0;  

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        
        DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
        DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
        DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;
        DROP TEMPORARY TABLE IF EXISTS tmp_live_pickput;
        DROP TEMPORARY TABLE IF EXISTS tmp_live_put;

        
        IF v_lock_ok = 1 THEN
            DO RELEASE_LOCK('BOT_ALLOCATION_ENGINE_V5_LOCK');
        END IF;

        RESIGNAL;
    END;

    
    SELECT GET_LOCK('BOT_ALLOCATION_ENGINE_V5_LOCK', 5) INTO v_lock_ok;
    IF IFNULL(v_lock_ok,0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BOT_ALLOCATION_ENGINE_V5 is already running (lock not acquired).';
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_pickput;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_put;

    CREATE TEMPORARY TABLE tmp_wave_station_rule_mapping
    SELECT * FROM wave_station_rule_mapping;

    UPDATE tmp_wave_station_rule_mapping
    SET BOT_COUNT_CURRENT = 0;

    
    CREATE TEMPORARY TABLE tmp_station_demand AS
    SELECT A.STATION_ID,
           W.WAVE_TYPE,
           A.RACK_PENDING_CNT,
           A.STATION_PICK_PENDING_CNT
    FROM (
        SELECT OBM.STATION_ID,
               SUM(
                   CASE
                       WHEN OBM.TYPE = 'RACK_PICK'
                            AND OBM.STATUS IN ('PENDING','TASK_ALLOCATED','BIN_PICKED')
                       THEN 1 ELSE 0
                   END
               ) AS RACK_PENDING_CNT,
               SUM(
                   CASE
                       WHEN OBM.TYPE = 'STATION_PICK'
                            AND OBM.STATUS = 'PENDING'
                       THEN 1 ELSE 0
                   END
               ) AS STATION_PICK_PENDING_CNT
        FROM order_bin_mapping OBM
        GROUP BY OBM.STATION_ID
    ) A
    JOIN hw_station_master HS ON HS.STATION_ID = A.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    WHERE (A.RACK_PENDING_CNT > 0 OR A.STATION_PICK_PENDING_CNT > 0);

    CREATE TEMPORARY TABLE tmp_station_demand1 AS
    SELECT * FROM tmp_station_demand;

    
    SELECT COUNT(*) INTO V_NoBot
    FROM bot_master
    WHERE AUTO_MANUAL = 'auto'
      AND STATUS      = 'ENABLED';

    
    SELECT KEY_VALUE INTO V_NoBotSA FROM master_config WHERE KEY_NAME = 'MAX_BOT_SA';
    SELECT KEY_VALUE INTO V_NoBotBL FROM master_config WHERE KEY_NAME = 'MAX_BOT_BL';
    SELECT KEY_VALUE INTO V_NoBotLA FROM master_config WHERE KEY_NAME = 'MAX_BOT_LA';

    SET V_NoBotSA = IFNULL(V_NoBotSA, 0);
    SET V_NoBotBL = IFNULL(V_NoBotBL, 0);
    SET V_NoBotLA = IFNULL(V_NoBotLA, 0);

    
    SELECT COUNT(DISTINCT W.Wave_ID)
      INTO V_OtherWaveCount
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE IN ('STOCK_AUDIT','BIN_LOADING','LOCATION_AUDIT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    IF V_OtherWaveCount > 0 THEN
        IF V_NoBot < (V_NoBotSA * V_OtherWaveCount) THEN
            SET V_BotforOtherWave = FLOOR(V_NoBot / V_OtherWaveCount);

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)) <= 0 THEN 0
                    WHEN V_BotforOtherWave > (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0))
                      THEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0))
                    WHEN IFNULL(V_BotforOtherWave,0) > 0 THEN V_BotforOtherWave
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)) <= 0 THEN 0
                    WHEN V_BotforOtherWave > (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0))
                      THEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0))
                    WHEN IFNULL(V_BotforOtherWave,0) > 0 THEN V_BotforOtherWave
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)) <= 0 THEN 0
                    WHEN V_BotforOtherWave > (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0))
                      THEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0))
                    WHEN IFNULL(V_BotforOtherWave,0) > 0 THEN V_BotforOtherWave
                    ELSE 1
                END
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

        ELSE
            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)) <= 0 THEN 0
                    ELSE LEAST(V_NoBotSA, (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)))
                END
            WHERE W.WAVE_TYPE   = 'STOCK_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)) <= 0 THEN 0
                    ELSE LEAST(V_NoBotBL, (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)))
                END
            WHERE W.WAVE_TYPE   = 'BIN_LOADING'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
            SET WR.BOT_COUNT_CURRENT = CASE
                    WHEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)) <= 0 THEN 0
                    ELSE LEAST(V_NoBotLA, (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)))
                END
            WHERE W.WAVE_TYPE   = 'LOCATION_AUDIT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';
        END IF;
    END IF;

    
    SELECT IFNULL(SUM(WR.BOT_COUNT_CURRENT), 0)
      INTO V_BotforOtherWave
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
    WHERE W.WAVE_TYPE NOT IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SET V_NoBot = V_NoBot - V_BotforOtherWave;
    IF V_NoBot < 0 THEN SET V_NoBot = 0; END IF;

    
    SELECT COUNT(*)
      INTO V_ActiveStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE W.WAVE_TYPE IN ('PICK','PUT')
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SELECT COUNT(*)
      INTO V_PickStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE W.WAVE_TYPE = 'PICK'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    SELECT COUNT(*)
      INTO V_PutStation
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE W.WAVE_TYPE = 'PUT'
      AND HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    
    IF IFNULL(V_ActiveStation, 0) > 0 AND V_NoBot > 0 THEN

        SET V_BaseShare = FLOOR(V_NoBot / V_ActiveStation);

        IF V_BaseShare > 0 THEN

            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
            SET WR.BOT_COUNT_CURRENT =
                CASE
                    WHEN (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)) <= 0 THEN 0
                    ELSE
                        LEAST(
                            
                            (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0)),

                            
                            CASE
                                WHEN W.WAVE_TYPE = 'PICK' THEN IFNULL(WR.MAX_BOT_COUNT_PICK, 999999)
                                ELSE IFNULL(WR.MAX_BOT_COUNT_PUT, 999999)
                            END,

                            
                            LEAST(
                                V_BaseShare,
                                CASE
                                    WHEN V_BaseShare >=
                                         (CASE WHEN W.WAVE_TYPE='PICK' THEN WR.MIN_BOT_COUNT_PICK ELSE WR.MIN_BOT_COUNT_PUT END)
                                    THEN (CASE WHEN W.WAVE_TYPE='PICK' THEN WR.MIN_BOT_COUNT_PICK ELSE WR.MIN_BOT_COUNT_PUT END)
                                    ELSE 1
                                END
                            )
                        )
                END
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            
            SELECT (V_NoBot - IFNULL(SUM(WR.BOT_COUNT_CURRENT),0))
              INTO V_PendingBots
            FROM tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            IF V_PendingBots < 0 THEN SET V_PendingBots = 0; END IF;

        ELSE
            
            UPDATE tmp_wave_station_rule_mapping WR
            JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
            JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
            SET WR.BOT_COUNT_CURRENT = 0
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            UPDATE tmp_wave_station_rule_mapping WR
            INNER JOIN (
                SELECT HS.STATION_ID,
                       HS.Wave_ID,
                       ROW_NUMBER() OVER (
                           ORDER BY CASE WHEN W.WAVE_TYPE = 'PICK' THEN 1 ELSE 2 END,
                                    HS.STATION_ID
                       ) AS SRank
                FROM hw_station_master HS
                JOIN wave_master      W ON W.Wave_ID = HS.Wave_ID
                JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
                WHERE W.WAVE_TYPE IN ('PICK','PUT')
                  AND HS.STATUS      = 'ENABLED'
                  AND HS.WAVE_STATUS = 'WAVE_LIVE'
            ) AS X ON X.STATION_ID = WR.STATION_ID
            JOIN wave_master W ON W.Wave_ID = X.Wave_ID
            SET WR.BOT_COUNT_CURRENT = 1
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND X.SRank <= V_NoBot;

            SET V_PendingBots = 0;
        END IF;

        
        IF V_PendingBots > 0 THEN
            CREATE TEMPORARY TABLE tmp_live_pickput AS
            SELECT
                ROW_NUMBER() OVER (
                    ORDER BY CASE W.WAVE_TYPE WHEN 'PICK' THEN 1 ELSE 2 END,
                             HS.STATION_ID
                ) AS RN,
                HS.STATION_ID,
                HS.Wave_ID,
                W.WAVE_TYPE
            FROM hw_station_master HS
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
            WHERE W.WAVE_TYPE IN ('PICK','PUT')
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            SELECT COUNT(*) INTO V_TotalRN FROM tmp_live_pickput;

            IF V_TotalRN > 0 THEN
                pickput_outer_loop: WHILE V_PendingBots > 0 DO

                    SELECT SUM(
                               GREATEST(
                                   0,
                                   (IFNULL(TSD.RACK_PENDING_CNT, 0)
                                    + IFNULL(TSD.STATION_PICK_PENDING_CNT, 0))
                                   - WR.BOT_COUNT_CURRENT
                               )
                           )
                      INTO V_TotalDemand
                    FROM tmp_live_pickput LP
                    JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = LP.STATION_ID
                    JOIN tmp_station_demand TSD           ON TSD.STATION_ID = LP.STATION_ID;

                    IF IFNULL(V_TotalDemand, 0) <= 0 THEN
                        LEAVE pickput_outer_loop;
                    END IF;

                    SET V_AnyIncrement = 0;
                    SET V_CurrentRN    = 1;

                    pickput_inner_loop: WHILE V_CurrentRN <= V_TotalRN AND V_PendingBots > 0 DO

                        SELECT
                            LP.STATION_ID,
                            LP.WAVE_TYPE,
                            WR.BOT_COUNT_CURRENT,
                            IFNULL(TSD.RACK_PENDING_CNT, 0),
                            IFNULL(TSD.STATION_PICK_PENDING_CNT, 0),
                            WR.MAX_BOT_COUNT_PICK,
                            WR.MAX_BOT_COUNT_PUT,
                            WR.UPPER_BOT_COUNT_PUT
                        INTO
                            V_StationId,
                            V_WaveType,
                            V_CurrentStationBots,
                            V_RackPending,
                            V_StationPickPending,
                            V_MaxPick,
                            V_MaxPut,
                            V_UpperPut
                        FROM tmp_live_pickput LP
                        JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = LP.STATION_ID
                        JOIN tmp_station_demand TSD           ON TSD.STATION_ID = LP.STATION_ID
                        WHERE LP.RN = V_CurrentRN;

                        SET V_StationDemand = V_RackPending + V_StationPickPending;

                        IF V_StationDemand > V_CurrentStationBots THEN
                            IF V_WaveType = 'PICK' AND V_CurrentStationBots < V_MaxPick THEN
                                UPDATE tmp_wave_station_rule_mapping
                                SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                                WHERE STATION_ID = V_StationId;

                                SET V_PendingBots  = V_PendingBots - 1;
                                SET V_AnyIncrement = 1;

                            ELSEIF V_WaveType = 'PUT' AND V_CurrentStationBots < V_MaxPut THEN
                                UPDATE tmp_wave_station_rule_mapping
                                SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                                WHERE STATION_ID = V_StationId;

                                SET V_PendingBots  = V_PendingBots - 1;
                                SET V_AnyIncrement = 1;
                            END IF;
                        END IF;

                        SET V_CurrentRN = V_CurrentRN + 1;
                    END WHILE pickput_inner_loop;

                    IF V_AnyIncrement = 0 THEN
                        LEAVE pickput_outer_loop;
                    END IF;

                END WHILE pickput_outer_loop;
            END IF;
        END IF;

        
        IF V_PendingBots > 0 AND V_PutStation > 0 THEN

            CREATE TEMPORARY TABLE tmp_live_put AS
            SELECT
                ROW_NUMBER() OVER (ORDER BY HS.STATION_ID) AS RN,
                HS.STATION_ID,
                HS.Wave_ID,
                W.WAVE_TYPE
            FROM hw_station_master HS
            JOIN wave_master W        ON W.Wave_ID      = HS.Wave_ID
            JOIN tmp_station_demand TSD ON TSD.STATION_ID = HS.STATION_ID
            WHERE W.WAVE_TYPE = 'PUT'
              AND HS.STATUS      = 'ENABLED'
              AND HS.WAVE_STATUS = 'WAVE_LIVE';

            SELECT COUNT(*) INTO V_TotalRN FROM tmp_live_put;

            IF V_TotalRN > 0 THEN
                put_outer_loop: WHILE V_PendingBots > 0 DO

                    SELECT SUM(
                               GREATEST(
                                   0,
                                   (IFNULL(TSD.RACK_PENDING_CNT, 0)
                                    + IFNULL(TSD.STATION_PICK_PENDING_CNT, 0))
                                   - WR.BOT_COUNT_CURRENT
                               )
                           )
                      INTO V_TotalDemand
                    FROM tmp_live_put LP
                    JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = LP.STATION_ID
                    JOIN tmp_station_demand TSD           ON TSD.STATION_ID = LP.STATION_ID;

                    IF IFNULL(V_TotalDemand, 0) <= 0 THEN
                        LEAVE put_outer_loop;
                    END IF;

                    SET V_AnyIncrement = 0;
                    SET V_CurrentRN    = 1;

                    put_inner_loop: WHILE V_CurrentRN <= V_TotalRN AND V_PendingBots > 0 DO

                        SELECT
                            LP.STATION_ID,
                            WR.BOT_COUNT_CURRENT,
                            IFNULL(TSD.RACK_PENDING_CNT, 0),
                            IFNULL(TSD.STATION_PICK_PENDING_CNT, 0),
                            WR.MAX_BOT_COUNT_PUT,
                            WR.UPPER_BOT_COUNT_PUT
                        INTO
                            V_StationId,
                            V_CurrentStationBots,
                            V_RackPending,
                            V_StationPickPending,
                            V_MaxPut,
                            V_UpperPut
                        FROM tmp_live_put LP
                        JOIN tmp_wave_station_rule_mapping WR ON WR.STATION_ID = LP.STATION_ID
                        JOIN tmp_station_demand TSD           ON TSD.STATION_ID = LP.STATION_ID
                        WHERE LP.RN = V_CurrentRN;

                        SET V_StationDemand = V_RackPending + V_StationPickPending;

                        IF V_StationDemand > V_CurrentStationBots
                           AND V_CurrentStationBots < V_UpperPut THEN

                            UPDATE tmp_wave_station_rule_mapping
                            SET BOT_COUNT_CURRENT = BOT_COUNT_CURRENT + 1
                            WHERE STATION_ID = V_StationId;

                            SET V_PendingBots  = V_PendingBots - 1;
                            SET V_AnyIncrement = 1;
                        END IF;

                        SET V_CurrentRN = V_CurrentRN + 1;
                    END WHILE put_inner_loop;

                    IF V_AnyIncrement = 0 THEN
                        LEAVE put_outer_loop;
                    END IF;

                END WHILE put_outer_loop;
            END IF;
        END IF;

    END IF; 

    
    UPDATE tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master W ON W.WAVE_ID = HS.WAVE_ID
    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    SET WR.BOT_COUNT_CURRENT =
      CASE
        WHEN W.WAVE_TYPE = 'PICK' THEN
          LEAST(
            IFNULL(WR.BOT_COUNT_CURRENT,0),
            IFNULL(WR.MAX_BOT_COUNT_PICK, IFNULL(WR.BOT_COUNT_CURRENT,0)),
            (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0))
          )
        WHEN W.WAVE_TYPE = 'PUT' THEN
          LEAST(
            IFNULL(WR.BOT_COUNT_CURRENT,0),
            CASE
              WHEN IFNULL(WR.UPPER_BOT_COUNT_PUT,0) > 0 THEN WR.UPPER_BOT_COUNT_PUT
              ELSE IFNULL(WR.MAX_BOT_COUNT_PUT, IFNULL(WR.BOT_COUNT_CURRENT,0))
            END,
            (IFNULL(TSD.RACK_PENDING_CNT,0) + IFNULL(TSD.STATION_PICK_PENDING_CNT,0))
          )
        ELSE WR.BOT_COUNT_CURRENT
      END
    WHERE HS.STATUS='ENABLED'
      AND HS.WAVE_STATUS='WAVE_LIVE'
      AND W.WAVE_TYPE IN ('PICK','PUT');

    
    UPDATE wave_station_rule_mapping WR
    JOIN tmp_wave_station_rule_mapping TWR
      ON WR.WAVE_STATION_RULE_MAPPING_ID = TWR.WAVE_STATION_RULE_MAPPING_ID
    SET WR.BOT_COUNT_CURRENT = TWR.BOT_COUNT_CURRENT;

    
    SELECT
        HS.WAVE_ID,
        W.WAVE_TYPE,
        WR.STATION_ID,
        WR.BOT_COUNT_CURRENT,
        WR.BOT_COUNT_DEFAULT,
        IFNULL(TSD.RACK_PENDING_CNT, 0)         AS RACK_PENDING_CNT,
        IFNULL(TSD.STATION_PICK_PENDING_CNT, 0) AS STATION_PICK_PENDING_CNT,
        WR.MAX_BOT_COUNT_PICK,
        WR.MIN_BOT_COUNT_PICK,
        WR.MAX_BOT_COUNT_PUT,
        WR.MIN_BOT_COUNT_PUT,
        WR.UPPER_BOT_COUNT_PUT
    FROM tmp_wave_station_rule_mapping WR
    JOIN hw_station_master HS ON HS.STATION_ID = WR.STATION_ID
    JOIN wave_master      W   ON W.Wave_ID      = HS.Wave_ID
    LEFT JOIN tmp_station_demand TSD ON TSD.STATION_ID = WR.STATION_ID
    WHERE HS.STATUS      = 'ENABLED'
      AND HS.WAVE_STATUS = 'WAVE_LIVE';

    
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_demand1;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_pickput;
    DROP TEMPORARY TABLE IF EXISTS tmp_live_put;

    
    DO RELEASE_LOCK('BOT_ALLOCATION_ENGINE_V5_LOCK');

END */$$
DELIMITER ;

/* Procedure structure for procedure `bot_GetActiveObstacleLog` */

/*!50003 DROP PROCEDURE IF EXISTS  `bot_GetActiveObstacleLog` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `bot_GetActiveObstacleLog`(
    IN _botId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    DECLARE log_count INT DEFAULT 0;
    
    
    SELECT COUNT(*) INTO log_count
    FROM `bot_obstacle_log`
    WHERE BOT_ID = _botId
    ORDER BY OBSTACLE_DETECTION_TIMESTAMP DESC
    LIMIT 1;
    
    
    SELECT 
        CASE 
            WHEN log_count > 0 THEN 1
            ELSE 0
        END 
    FROM 
        `bot_obstacle_log`
    WHERE 
        BOT_ID = _botId
    ORDER BY 
        OBSTACLE_DETECTION_TIMESTAMP DESC
    LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `bot_GetObstacleEligibilityDuration` */

/*!50003 DROP PROCEDURE IF EXISTS  `bot_GetObstacleEligibilityDuration` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `bot_GetObstacleEligibilityDuration`()
BEGIN
    SELECT 
        OBSTACLE_ELIGIBILITY_DURATION
    FROM config_master
    LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `bot_GetObstacleLogId` */

/*!50003 DROP PROCEDURE IF EXISTS  `bot_GetObstacleLogId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `bot_GetObstacleLogId`(
    IN _botId VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    SELECT 
        COALESCE(OBSTACLE_LOG_ID, 0) AS LogId
    FROM 
        `bot_obstacle_log`
    WHERE 
        BOT_ID = _botId
    ORDER BY 
        OBSTACLE_DETECTION_TIMESTAMP DESC
    LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `bot_InsertObstacleEvent` */

/*!50003 DROP PROCEDURE IF EXISTS  `bot_InsertObstacleEvent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `bot_InsertObstacleEvent`(
    IN _botId VARCHAR(20),
    IN _barcode INT
)
BEGIN
    DECLARE v_x INT;
    DECLARE v_y INT;
    DECLARE v_z INT;

    SELECT X, Y, Z
    INTO v_x, v_y, v_z
    FROM location_master
    WHERE BARCODE_NUMBER = _barcode
    LIMIT 1;

    INSERT INTO bot_obstacle_log
    (
        BOT_ID,
        OBSTACLE_DETECTION_TIMESTAMP,
        X, Y, Z,
        BARCODE_NUMBER
    )
    VALUES
    (
        _botId,
        NOW(3) - INTERVAL (SELECT OBSTACLE_ELIGIBILITY_DURATION FROM config_master) SECOND,
        v_x, v_y, v_z,
        _barcode
    );

    SELECT LAST_INSERT_ID() AS LogId;

END */$$
DELIMITER ;

/* Procedure structure for procedure `bot_UpdateObstacleRemovalDuration` */

/*!50003 DROP PROCEDURE IF EXISTS  `bot_UpdateObstacleRemovalDuration` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `bot_UpdateObstacleRemovalDuration`(
    IN _logId INT
)
BEGIN
    INSERT INTO bot_obstacle_log_archive 
    (
        OBSTACLE_LOG_ID,
        BOT_ID,
        X, Y, Z,
        BARCODE_NUMBER,
        OBSTACLE_DETECTION_TIMESTAMP
    )
    SELECT
        OBSTACLE_LOG_ID,
        BOT_ID,
        X, Y, Z,
        BARCODE_NUMBER,
        OBSTACLE_DETECTION_TIMESTAMP
    FROM bot_obstacle_log
    WHERE OBSTACLE_LOG_ID = _logId;

    DELETE FROM bot_obstacle_log
    WHERE OBSTACLE_LOG_ID = _logId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `bot_UpdateObstacleRemovalDurationTest` */

/*!50003 DROP PROCEDURE IF EXISTS  `bot_UpdateObstacleRemovalDurationTest` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `bot_UpdateObstacleRemovalDurationTest`(
    IN _logId INT,
    IN _removal_duartion_seconds INT
)
BEGIN
    DECLARE procName VARCHAR(100) DEFAULT 'bot_UpdateObstacleRemovalDuration';

    
    INSERT INTO sp_debug_log (PROC_NAME, STEP, MESSAGE)
    VALUES (procName, 'START', CONCAT('Started with logId=', _logId, ', removal=', _removal_duartion_seconds));

    
    INSERT INTO sp_debug_log (PROC_NAME, STEP, MESSAGE)
    VALUES (procName, 'UPDATE_START', CONCAT('Updating bot_obstacle_log for ID ', _logId));

    UPDATE `bot_obstacle_log`
    SET `REMOVAL_DURATION` = _removal_duartion_seconds
    WHERE `OBSTACLE_LOG_ID` = _logId;

    INSERT INTO sp_debug_log (PROC_NAME, STEP, MESSAGE)
    VALUES (procName, 'UPDATE_END', CONCAT('Rows affected: ', ROW_COUNT()));

    
    INSERT INTO sp_debug_log (PROC_NAME, STEP, MESSAGE)
    VALUES (procName, 'ARCHIVE_INSERT_START', CONCAT('Trying to archive ID ', _logId));

    INSERT INTO `bot_obstacle_log_archive` (
        `OBSTACLE_LOG_ID`,
        `BOT_ID`,
        `OBSTACLE_LOG_INSERTED_TIMESTAMP`,
        `REMOVAL_DURATION`
    )
    SELECT
        `OBSTACLE_LOG_ID`,
        `BOT_ID`,
        `INSERTED_TIMESTAMP`,
        `REMOVAL_DURATION`
    FROM `bot_obstacle_log`
    WHERE `OBSTACLE_LOG_ID` = _logId;

    INSERT INTO sp_debug_log (PROC_NAME, STEP, MESSAGE)
    VALUES (procName, 'ARCHIVE_INSERT_END', CONCAT('Rows inserted: ', ROW_COUNT()));

    
    INSERT INTO sp_debug_log (PROC_NAME, STEP, MESSAGE)
    VALUES (procName, 'DELETE_START', CONCAT('Deleting ID ', _logId, ' from bot_obstacle_log'));

    DELETE FROM `bot_obstacle_log`
    WHERE `OBSTACLE_LOG_ID` = _logId;

    INSERT INTO sp_debug_log (PROC_NAME, STEP, MESSAGE)
    VALUES (procName, 'DELETE_END', CONCAT('Rows deleted: ', ROW_COUNT()));

    
    INSERT INTO sp_debug_log (PROC_NAME, STEP, MESSAGE)
    VALUES (procName, 'END', 'Procedure completed');

END */$$
DELIMITER ;

/* Procedure structure for procedure `BulkInsertData` */

/*!50003 DROP PROCEDURE IF EXISTS  `BulkInsertData` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `BulkInsertData`(
    IN p_X VARCHAR(255),
    IN p_Y VARCHAR(255),
    IN p_Z VARCHAR(255),
    IN p_TYPE VARCHAR(255),
    IN p_XP VARCHAR(255),
    IN p_XN VARCHAR(255),
    IN p_YP VARCHAR(255),
    IN p_YN VARCHAR(255),
    IN p_BARCODE VARCHAR(255)
)
BEGIN
    INSERT INTO location_master (X, Y, Z, TYPE, XP, XN, YP, YN, ZP, ZN, IS_BARCODE)
    VALUES (p_X, p_Y, p_Z, p_TYPE, p_XP, p_XN, p_YP, p_YN, 0, 0, p_BARCODE);
END */$$
DELIMITER ;

/* Procedure structure for procedure `CostCalculator` */

/*!50003 DROP PROCEDURE IF EXISTS  `CostCalculator` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `CostCalculator`()
BEGIN
		SET @cost = 0;
		UPDATE store_bin_master sbm
		JOIN (
		SELECT lm.LOCATION_ID, lm.x, lm.y, lm.z,
		@cost := @cost + 1 AS COST
		FROM location_master lm
		WHERE lm.TYPE = 'STORAGE_LOCATION'
		ORDER BY lm.X, lm.Y, lm.Z) as cost_table
		ON sbm.LOCATION_ID = cost_table.LOCATION_ID
		set sbm.COST = cost_table.COST;		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `debug_FindStoredProcWithName` */

/*!50003 DROP PROCEDURE IF EXISTS  `debug_FindStoredProcWithName` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `debug_FindStoredProcWithName`(in p_keyWord text)
BEGIN
		select concat('%',p_keyWord,'%') into p_keyWord;
		SELECT ROUTINE_NAME, ROUTINE_DEFINITION, ROUTINE_TYPE, ROUTINE_SCHEMA, LAST_ALTERED
		FROM information_schema.ROUTINES
		WHERE (ROUTINE_TYPE = 'PROCEDURE'
		OR ROUTINE_TYPE = 'FUNCTION')
		and ROUTINE_SCHEMA = DATABASE()
		AND (ROUTINE_DEFINITION LIKE p_keyWord or ROUTINE_NAME like p_keyWord);
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `debug_InsertIntoOrderBinMapping` */

/*!50003 DROP PROCEDURE IF EXISTS  `debug_InsertIntoOrderBinMapping` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `debug_InsertIntoOrderBinMapping`(
    IN p_binId INT,
    IN p_stationId INT
)
BEGIN
    
    
    IF NOT EXISTS (
        SELECT 1
        FROM order_bin_mapping
        WHERE BIN_ID = p_binId
          AND STATION_ID = p_stationId
          AND STATUS <> 'TASK_COMPLETED'
    ) THEN
        INSERT INTO `order_bin_mapping` 
        (
            BIN_ID, 
            STATION_ID, 
            TYPE 
        )
        VALUES
        (
            p_binId,               
            p_stationId,           
            'STATION_PICK'         
        );
                UPDATE `hw_conveyor_master` SET `BIN_ON_PICK_ACK` = 1 where PARENT_ID = p_stationId;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `debug_InvetoryByClientBatchId` */

/*!50003 DROP PROCEDURE IF EXISTS  `debug_InvetoryByClientBatchId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `debug_InvetoryByClientBatchId`(IN p_clientBatchId VARCHAR(200))
BEGIN
    DECLARE v_batchId VARCHAR(200);

SELECT batch_id 
INTO v_batchId
FROM sku_batch_master
WHERE client_batch_id = p_clientBatchId
LIMIT 1;

    
    SELECT 
        (SELECT IFNULL(SUM(put_quantity),0) 
         FROM put_wave_order_master_archive
         WHERE batch_id = v_batchId)
        +
        (SELECT IFNULL(SUM(put_quantity),0)
         FROM put_wave_order_master
         WHERE batch_id = v_batchId)
         AS TOTAL_PUT_QUANTITY;

    
    SELECT 
        (SELECT IFNULL(SUM(picked_quantity),0)
         FROM pick_wave_order_master_archive
         WHERE batch_id = v_batchId)
        +
        (SELECT IFNULL(SUM(picked_quantity),0)
         FROM pick_wave_order_master
         WHERE batch_id = v_batchId)
         AS TOTAL_PICKED_QUANTITY;
         
         
    
    SELECT 
        (SELECT IFNULL(SUM(IF(SHORT_PICK_QUANTITY < 0, 0, SHORT_PICK_QUANTITY)), 0)
         FROM pick_wave_order_master_archive
         WHERE batch_id = v_batchId)
        +
        (SELECT IFNULL(SUM(IF(SHORT_PICK_QUANTITY < 0, 0, SHORT_PICK_QUANTITY)), 0)
         FROM pick_wave_order_master
         WHERE batch_id = v_batchId)
         AS TOTAL_SHORT_PICK_QUANTITY;

    
    SELECT 
        IFNULL(SUM(expected_quantity), 0) AS LIVE_EXPECTED_QUANTITY
    FROM pick_wave_order_master
    WHERE batch_id = v_batchId;

    
    SELECT 
        (SELECT IFNULL(SUM(quantity),0)
         FROM live_inventory_master
         WHERE batch_id = v_batchId)
         AS TOTAL_INVENTORY_QUANTITY;
        
        
    SELECT
    sbm.LOCATION_ID,
    SUM(lim.quantity) AS TOTAL_QUANTITY,
    'Location Block Master (Live)' AS RESULT_NAME
FROM live_inventory_master lim
JOIN store_bin_master sbm 
        ON sbm.bin_id = lim.bin_id
JOIN location_block_master lbm 
        ON lbm.location_id = sbm.location_id
WHERE lim.batch_id = v_batchId
GROUP BY sbm.location_id;

END */$$
DELIMITER ;

/* Procedure structure for procedure `debug_PickWaveAllocatedQuantity` */

/*!50003 DROP PROCEDURE IF EXISTS  `debug_PickWaveAllocatedQuantity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `debug_PickWaveAllocatedQuantity`(in p_waveId varchar(200))
BEGIN
declare v_ExpectedQuantity int;
declare v_AllocatedQuantity int;
	SELECT IFNULL(SUM(`QUANTITY` - `LEFT_OVER`), 0)
	INTO v_ExpectedQuantity
    FROM `pick_wave_wms_data`
    WHERE `WAVE_ID` = p_waveId;
    
SELECT IFNULL(SUM(`PICKED_QUANTITY`), 0)
    INTO v_AllocatedQuantity
    FROM `pick_wave_order_master`
    WHERE `WAVE_ID` = p_waveId;
select v_ExpectedQuantity,v_AllocatedQuantity;    
    
SELECT DISTINCT order_id
    FROM `pick_wave_wms_data`
    WHERE `WAVE_ID` = p_waveId
    AND order_id NOT IN(
		SELECT DISTINCT order_id
		    FROM `pick_wave_order_master`
		    WHERE `WAVE_ID` = p_waveId);
SELECT order_id, sum(quantity-left_over) as quantiy
    FROM `pick_wave_wms_data`
    WHERE `WAVE_ID` = p_waveId
    group by order_id
    order by order_id;
    
SELECT order_id, SUM(`EXPECTED_QUANTITY`) AS quantiy
    FROM `pick_wave_order_master`
    WHERE `WAVE_ID` = p_waveId
    GROUP BY order_id
    ORDER BY order_id;
END */$$
DELIMITER ;

/* Procedure structure for procedure `debug_PickWaveArchiveAllocatedQuantity` */

/*!50003 DROP PROCEDURE IF EXISTS  `debug_PickWaveArchiveAllocatedQuantity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `debug_PickWaveArchiveAllocatedQuantity`(in p_waveId varchar(200))
BEGIN
declare v_ExpectedQuantity int;
declare v_AllocatedQuantity int;
	SELECT IFNULL(SUM(`QUANTITY` - `LEFT_OVER`), 0)
	INTO v_ExpectedQuantity
    FROM `pick_wave_wms_data_archive`
    WHERE `WAVE_ID` = p_waveId;
    
SELECT IFNULL(SUM(`EXPECTED_QUANTITY`), 0)
    INTO v_AllocatedQuantity
    FROM `pick_wave_order_master_archive`
    WHERE `WAVE_ID` = p_waveId;
select v_ExpectedQuantity,v_AllocatedQuantity;    
    
SELECT DISTINCT order_id
    FROM `pick_wave_wms_data_archive`
    WHERE `WAVE_ID` = p_waveId
    AND order_id NOT IN(
		SELECT DISTINCT order_id
		    FROM `pick_wave_order_master_archive`
		    WHERE `WAVE_ID` = p_waveId);
SELECT order_id, sum(quantity-left_over) as quantiy
    FROM `pick_wave_wms_data_archive`
    WHERE `WAVE_ID` = p_waveId
    group by order_id
    order by order_id;
    
SELECT order_id, SUM(`EXPECTED_QUANTITY`) AS quantiy
    FROM `pick_wave_order_master_archive`
    WHERE `WAVE_ID` = p_waveId
    GROUP BY order_id
    ORDER BY order_id;
END */$$
DELIMITER ;

/* Procedure structure for procedure `debug_TasksByBotId` */

/*!50003 DROP PROCEDURE IF EXISTS  `debug_TasksByBotId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `debug_TasksByBotId`(in p_botId varchar(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
SELECT * FROM order_bin_mapping WHERE bot_id IN (p_botId);
SELECT * FROM order_bin_mapping_log WHERE bot_id = p_botId;
SELECT * FROM `task_master` WHERE bot_id = p_botId;
SELECT * FROM `task_detail` WHERE bot_id = p_botId;
SELECT * FROM `task_detail_log` WHERE bot_id = p_botId;
SELECT * FROM `steps` WHERE `BOT_ID` = p_botId;
SELECT * FROM `steps_archive` WHERE `BOT_ID` = p_botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_AFTER_DEPLOYMENT_GRID_LABELING` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_AFTER_DEPLOYMENT_GRID_LABELING` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_AFTER_DEPLOYMENT_GRID_LABELING`()
BEGIN
  
  DECLARE p_max_aisle               INT;
  DECLARE p_max_return_aisle        INT;
  DECLARE p_max_under_return_aisle  INT;
  DECLARE p_max_tower               INT;
  DECLARE i                         INT DEFAULT 1;
  DECLARE v_enum_aisle              TEXT DEFAULT '';
  DECLARE v_enum_return_aisle       TEXT DEFAULT '';
  DECLARE v_enum_under_return_aisle TEXT DEFAULT '';
  DECLARE v_enum_aisle_parts        TEXT DEFAULT '';
  DECLARE v_enum_tower              TEXT DEFAULT '';
  
  DECLARE v_tower_min_x             INT DEFAULT NULL;
  DECLARE v_tower_max_x             INT DEFAULT NULL;
  DECLARE v_aisle_entry_x           INT DEFAULT NULL;  
  
  DROP TEMPORARY TABLE IF EXISTS temp_process_log;
  CREATE TEMPORARY TABLE temp_process_log (
    ID      INT NOT NULL AUTO_INCREMENT,
    STEP    VARCHAR(64) NOT NULL,
    MESSAGE TEXT NOT NULL,
    PRIMARY KEY (ID)
  ) ENGINE=INNODB;
  
  IF EXISTS (
    SELECT 1
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'location_master'
      AND COLUMN_NAME  = 'AISLE_NUMBER'
  ) THEN
    SET @sql_drop_aisle = 'ALTER TABLE location_master DROP COLUMN AISLE_NUMBER';
    PREPARE stmt1a FROM @sql_drop_aisle; EXECUTE stmt1a; DEALLOCATE PREPARE stmt1a;
    INSERT INTO temp_process_log(STEP, MESSAGE) VALUES ('DROP', 'Dropped column AISLE_NUMBER');
  ELSE
    INSERT INTO temp_process_log(STEP, MESSAGE) VALUES ('DROP', 'AISLE_NUMBER does not exist');
  END IF;
  IF EXISTS (
    SELECT 1
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'location_master'
      AND COLUMN_NAME  = 'TOWER_NUMBER'
  ) THEN
    SET @sql_drop_tower = 'ALTER TABLE location_master DROP COLUMN TOWER_NUMBER';
    PREPARE stmt2 FROM @sql_drop_tower; EXECUTE stmt2; DEALLOCATE PREPARE stmt2;
    INSERT INTO temp_process_log(STEP, MESSAGE) VALUES ('DROP', 'Dropped column TOWER_NUMBER');
  ELSE
    INSERT INTO temp_process_log(STEP, MESSAGE) VALUES ('DROP', 'TOWER_NUMBER does not exist');
  END IF;
  IF EXISTS (
    SELECT 1
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'location_master'
      AND COLUMN_NAME  = 'TOWER_SIDE'
  ) THEN
    SET @sql_drop_tower_side = 'ALTER TABLE location_master DROP COLUMN TOWER_SIDE';
    PREPARE stmt2a FROM @sql_drop_tower_side; EXECUTE stmt2a; DEALLOCATE PREPARE stmt2a;
    INSERT INTO temp_process_log(STEP, MESSAGE) VALUES ('DROP', 'Dropped column TOWER_SIDE');
  ELSE
    INSERT INTO temp_process_log(STEP, MESSAGE) VALUES ('DROP', 'TOWER_SIDE does not exist');
  END IF;
  
  SELECT COUNT(DISTINCT Y)
    INTO p_max_aisle
  FROM location_master
  WHERE TYPE = 'AISLE_ENTRY';
  SELECT COUNT(DISTINCT X)
    INTO p_max_tower
  FROM location_master
  WHERE TYPE LIKE 'TOWER%';
  
  DROP TEMPORARY TABLE IF EXISTS tmp_ra_list;
  CREATE TEMPORARY TABLE tmp_ra_list (
    Y           INT NOT NULL,
    has_z1_pm3  TINYINT(1) NOT NULL
  ) ENGINE=MEMORY;
  INSERT INTO tmp_ra_list (Y, has_z1_pm3)
  SELECT
    rc.Y,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM location_master lm
        WHERE lm.Z = 1
          AND lm.Y IN (rc.Y - 3, rc.Y + 3)
      ) THEN 1 ELSE 0
    END AS has_z1_pm3
  FROM (
    SELECT DISTINCT Y
    FROM location_master
    WHERE TYPE = 'RETURN_AISLE_ENTRY'
  ) rc;
  SELECT
    SUM(has_z1_pm3 = 1),
    SUM(has_z1_pm3 = 0)
  INTO
    p_max_under_return_aisle,
    p_max_return_aisle
  FROM tmp_ra_list;
  INSERT INTO temp_process_log(STEP, MESSAGE) VALUES
    ('COUNT (TOTAL AISLES)',               p_max_aisle),
    ('COUNT (TOTAL RETURN AISLES)',        p_max_return_aisle),
    ('COUNT (TOTAL UNDER RETURN AISLES)',  p_max_under_return_aisle),
    ('COUNT (TOTAL TOWERS)',               p_max_tower);
  
  WHILE i <= p_max_aisle DO
    SET v_enum_aisle = CONCAT(v_enum_aisle, '''A', LPAD(i, 2, '0'), '''', IF(i < p_max_aisle, ',', ''));
    SET i = i + 1;
  END WHILE;
  SET i = 1;
  WHILE i <= p_max_return_aisle DO
    SET v_enum_return_aisle = CONCAT(v_enum_return_aisle, '''RA', LPAD(i, 2, '0'), '''', IF(i < p_max_return_aisle, ',', ''));
    SET i = i + 1;
  END WHILE;
  SET i = 1;
  WHILE i <= p_max_under_return_aisle DO
    SET v_enum_under_return_aisle = CONCAT(v_enum_under_return_aisle, '''URA', LPAD(i, 2, '0'), '''', IF(i < p_max_under_return_aisle, ',', ''));
    SET i = i + 1;
  END WHILE;
  SET v_enum_aisle_parts = '';
  IF p_max_aisle > 0 THEN SET v_enum_aisle_parts = v_enum_aisle; END IF;
  IF p_max_return_aisle > 0 THEN SET v_enum_aisle_parts = CONCAT_WS(',', v_enum_aisle_parts, v_enum_return_aisle); END IF;
  IF p_max_under_return_aisle > 0 THEN SET v_enum_aisle_parts = CONCAT_WS(',', v_enum_aisle_parts, v_enum_under_return_aisle); END IF;
  SET i = 1;
  WHILE i <= p_max_tower DO
    SET v_enum_tower = CONCAT(v_enum_tower, '''T', LPAD(i, 2, '0'), '''', IF(i < p_max_tower, ',', ''));
    SET i = i + 1;
  END WHILE;
  
  SET @alter_query = CONCAT(
    'ALTER TABLE location_master ',
    'ADD COLUMN AISLE_NUMBER ENUM(', v_enum_aisle_parts, ') DEFAULT NULL, ',
    'ADD COLUMN TOWER_NUMBER ENUM(', v_enum_tower, ') DEFAULT NULL, ',
    'ADD COLUMN TOWER_SIDE ENUM(''LEFT'',''RIGHT'') DEFAULT NULL;'
  );
  PREPARE stmt3 FROM @alter_query; EXECUTE stmt3; DEALLOCATE PREPARE stmt3;
  
  SET @index := 0;
  UPDATE location_master lm
  JOIN (
    SELECT
      Y,
      CONCAT('A', LPAD(@index := @index + 1, 2, '0')) AS aisle_label
    FROM (
      SELECT DISTINCT Y
      FROM location_master
      WHERE TYPE = 'AISLE_ENTRY'
      ORDER BY Y
    ) ordered_y, (SELECT @index := 0) init
  ) aisles
    ON lm.Y = aisles.Y
  SET lm.AISLE_NUMBER = aisles.aisle_label
  WHERE lm.TYPE IN ('AISLE_ENTRY', 'AISLE_MOVEMENT', 'AISLE_ENTRY_JUNCTION')
     OR lm.TYPE LIKE 'TOWER%';
  INSERT INTO temp_process_log(STEP, MESSAGE)
  VALUES ('ASSIGN', CONCAT('AISLE_NUMBER assign (AISLE_ENTRY/AISLE_MOVEMENT/TOWER%): ', ROW_COUNT()));
  
  SET @index := 0;
  UPDATE location_master lm
  JOIN (
    SELECT DISTINCT
      (Y - 1) AS Y,
      CONCAT('A', LPAD(@index := @index + 1, 2, '0')) AS aisle_label
    FROM (
      SELECT DISTINCT Y
      FROM location_master
      WHERE TYPE = 'AISLE_ENTRY'
      ORDER BY Y
    ) base, (SELECT @index := 0) init
  ) aislesL ON lm.Y = aislesL.Y
  SET
    lm.AISLE_NUMBER = aislesL.aisle_label,
    lm.TOWER_SIDE   = 'LEFT'
  WHERE lm.TYPE = 'STORAGE_LOCATION';
  INSERT INTO temp_process_log(STEP, MESSAGE)
  VALUES ('ASSIGN', CONCAT('STORAGE LEFT assign: ', ROW_COUNT()));
  
  SET @index := 0;
  UPDATE location_master lm
  JOIN (
    SELECT DISTINCT
      (Y + 1) AS Y,
      CONCAT('A', LPAD(@index := @index + 1, 2, '0')) AS aisle_label
    FROM (
      SELECT DISTINCT Y
      FROM location_master
      WHERE TYPE = 'AISLE_ENTRY'
      ORDER BY Y
    ) base, (SELECT @index := 0) init
  ) aislesR ON lm.Y = aislesR.Y
  SET
    lm.AISLE_NUMBER = aislesR.aisle_label,
    lm.TOWER_SIDE   = 'RIGHT'
  WHERE lm.TYPE = 'STORAGE_LOCATION';
  INSERT INTO temp_process_log(STEP, MESSAGE)
  VALUES ('ASSIGN', CONCAT('STORAGE RIGHT assign: ', ROW_COUNT()));
  
  SET @index := 0;
  UPDATE location_master lm
  JOIN (
    SELECT
      X,
      CONCAT('T', LPAD(@index := @index + 1, 2, '0')) AS tower_label
    FROM (
      SELECT DISTINCT X
      FROM location_master
      WHERE TYPE = 'STORAGE_LOCATION'
      ORDER BY X
    ) ordered_x, (SELECT @index := 0) init
  ) towersS ON lm.X = towersS.X
  SET lm.TOWER_NUMBER = towersS.tower_label
  WHERE lm.TYPE = 'STORAGE_LOCATION';
  INSERT INTO temp_process_log(STEP, MESSAGE)
  VALUES ('ASSIGN', CONCAT('TOWER_NUMBER assign (STORAGE_LOCATION): ', ROW_COUNT()));
  
  SET @index := 0;
  UPDATE location_master lm
  JOIN (
    SELECT
      X,
      CONCAT('T', LPAD(@index := @index + 1, 2, '0')) AS tower_label
    FROM (
      SELECT DISTINCT X
      FROM location_master
      WHERE TYPE LIKE 'TOWER%'
      ORDER BY X
    ) ordered_x, (SELECT @index := 0) init
  ) towersT ON lm.X = towersT.X
  SET lm.TOWER_NUMBER = towersT.tower_label
  WHERE lm.TYPE LIKE 'TOWER%';
  INSERT INTO temp_process_log(STEP, MESSAGE)
  VALUES ('ASSIGN', CONCAT('TOWER_NUMBER assign (TOWER%): ', ROW_COUNT()));
  
  SELECT MIN(X), MAX(X)
    INTO v_tower_min_x, v_tower_max_x
  FROM location_master
  WHERE TYPE LIKE 'TOWER%';
  SELECT MIN(xs.X)
    INTO v_aisle_entry_x
  FROM (SELECT DISTINCT X FROM location_master WHERE IS_BARCODE = 1) xs
  WHERE xs.X > v_tower_max_x;
  INSERT INTO temp_process_log(STEP, MESSAGE)
  VALUES ('X_RANGE', CONCAT('tower_min_x=', COALESCE(v_tower_min_x, -1),
                            ', tower_max_x=', COALESCE(v_tower_max_x, -1),
                            ', next_x=', COALESCE(v_aisle_entry_x, -1)));
  
  SET @rn := 0;
  UPDATE location_master lm
  JOIN (
    SELECT
      Y,
      CONCAT('RA', LPAD(@rn := @rn + 1, 2, '0')) AS aisle_label
    FROM (
      SELECT DISTINCT Y
      FROM tmp_ra_list
      WHERE has_z1_pm3 = 0
      ORDER BY Y
    ) d
  ) m ON m.Y = lm.Y
  SET lm.AISLE_NUMBER = m.aisle_label
  WHERE lm.X >= COALESCE(v_tower_min_x, 0)
    AND lm.X <= COALESCE(v_aisle_entry_x, 0)
    AND lm.IS_BARCODE = 1;
  INSERT INTO temp_process_log(STEP, MESSAGE)
  VALUES ('ASSIGN', CONCAT('AISLE_NUMBER assign (RA): ', ROW_COUNT()));
  
  SET @rn := 0;
  UPDATE location_master lm
  JOIN (
    SELECT
      Y,
      CONCAT('URA', LPAD(@rn := @rn + 1, 2, '0')) AS aisle_label
    FROM (
      SELECT DISTINCT Y
      FROM tmp_ra_list
      WHERE has_z1_pm3 = 1
      ORDER BY Y
    ) d
  ) m ON m.Y = lm.Y
  SET lm.AISLE_NUMBER = m.aisle_label
  WHERE lm.X >= COALESCE(v_tower_min_x, 0)
    AND lm.X <= COALESCE(v_aisle_entry_x, 0)
    AND lm.IS_BARCODE = 1;
  INSERT INTO temp_process_log(STEP, MESSAGE)
  VALUES ('ASSIGN', CONCAT('AISLE_NUMBER assign (URA): ', ROW_COUNT()));
  
  INSERT INTO temp_process_log(STEP, MESSAGE)
  VALUES ('SUMMARY', 'Location Master Updated Successfully');
  SELECT ID, STEP, MESSAGE
  FROM temp_process_log
  ORDER BY ID DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_AFTER_DEPLOYMENT_RUN` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_AFTER_DEPLOYMENT_RUN` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_AFTER_DEPLOYMENT_RUN`()
BEGIN
    
    CALL DSB_AFTER_DEPLOYMENT_GRID_LABELING();
    
    
    SET @dbm_row = 0;
    
    UPDATE dashboard_menu_master
    SET SEQUENCE = (@dbm_row := @dbm_row + 1)
    ORDER BY SEQUENCE;
    
    
    SET @drm_row = 0;
    
    UPDATE dashboard_report_master
    SET SEQUENCE = (@drm_row := @drm_row + 1)
    ORDER BY SEQUENCE;
    
    
    SET @drpm_row = 0;
    UPDATE dashboard_report_parent_master
    SET SEQUENCE = (@drpm_row := @drpm_row + 1)
    ORDER BY SEQUENCE;
    
    
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_API_MASTER_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_API_MASTER_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_API_MASTER_GET_ALL`()
BEGIN
    
    SELECT * 
    FROM api_master WHERE API_ENV = "PROD" AND DSB_OPERATION_TYPE in ("PICK", "PUT");
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BIN_DETAILS_BY_BIN_ID_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BIN_DETAILS_BY_BIN_ID_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BIN_DETAILS_BY_BIN_ID_GET`(
  IN Parameters JSON
)
BEGIN
    DECLARE p_bin_ids JSON;
    DECLARE p_info_type VARCHAR(100);
    SET p_bin_ids = JSON_EXTRACT(Parameters, '$.bin_ids');
    SET p_info_type = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.info_type'));   
    
    IF p_info_type = 'bin_live_location' THEN
        CALL DSB_BIN_DETAILS_BY_BIN_ID_GET_LIVE_LOCATION(p_bin_ids);
    ELSEIF p_info_type = 'bin_info' THEN
        CALL DSB_BIN_DETAILS_BY_BIN_ID_GET_BIN_INFO(p_bin_ids);
    ELSEIF p_info_type = 'location_info' THEN
        CALL DSB_BIN_DETAILS_BY_BIN_ID_GET_LOCATION_INFO(p_bin_ids);
    ELSEIF p_info_type = 'bin_segment_info' THEN
        CALL DSB_BIN_DETAILS_BY_BIN_ID_GET_BIN_SEGMENT_INFO(p_bin_ids);
    ELSEIF p_info_type = 'last_put_wave_details' THEN
        CALL DSB_BIN_DETAILS_BY_BIN_ID_GET_LAST_PUT_WAVE_DETAILS(p_bin_ids);
    ELSEIF p_info_type = 'last_pick_wave_details' THEN
        CALL DSB_BIN_DETAILS_BY_BIN_ID_GET_LAST_PICK_WAVE_DETAILS(p_bin_ids);
ELSE
SELECT
0 AS Success,
  CONCAT('Unsupported Bin info type: ', p_info_type) AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BIN_DETAILS_BY_BIN_ID_GET_BIN_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BIN_DETAILS_BY_BIN_ID_GET_BIN_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BIN_DETAILS_BY_BIN_ID_GET_BIN_INFO`(
    IN p_bin_ids JSON
)
BEGIN
    SELECT 
        bim.BIN_ID,
        bim.BIN_BARCODE,
        bim.BIN_SEGMENTS
    FROM 
        bin_info_master bim
    WHERE bim.BIN_ID IN (
        SELECT jt.bin_id
        FROM JSON_TABLE(
            p_bin_ids,
            '$[*]' COLUMNS (
                bin_id VARCHAR(100) PATH '$'
            )
        ) jt
    );
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BIN_DETAILS_BY_BIN_ID_GET_BIN_SEGMENT_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BIN_DETAILS_BY_BIN_ID_GET_BIN_SEGMENT_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BIN_DETAILS_BY_BIN_ID_GET_BIN_SEGMENT_INFO`(
    IN p_bin_ids JSON
)
BEGIN
    SELECT 
	bim.BIN_BARCODE,
	lim.BIN_ID,
        lim.SEGMENT_NO,
        lim.ARTICLE_ID AS SKU_ID,
        sm.SKU_NAME,
        lim.QUANTITY,
        DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL) AS IMAGE_URL
    FROM 
        live_inventory_master AS lim
    INNER JOIN 
        sku_master AS sm
            ON sm.SKU_ID = lim.ARTICLE_ID
    INNER JOIN 
        bin_info_master As bim
            ON lim.BIN_ID = bim.BIN_ID
    WHERE 
        lim.BIN_ID IN (
            SELECT jt.bin_id
            FROM JSON_TABLE(
                p_bin_ids,
                '$[*]' COLUMNS (
                    bin_id VARCHAR(100) PATH '$'
                )
            ) jt
        );
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BIN_DETAILS_BY_BIN_ID_GET_LAST_PICK_WAVE_DETAILS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BIN_DETAILS_BY_BIN_ID_GET_LAST_PICK_WAVE_DETAILS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BIN_DETAILS_BY_BIN_ID_GET_LAST_PICK_WAVE_DETAILS`(
    IN p_bin_id VARCHAR(100)
)
BEGIN
    
    IF (
        SELECT COUNT(*) 
        FROM pick_wave_order_master
        WHERE BIN_ID = p_bin_id
          AND PICK_TIMESTAMP IS NOT NULL
    ) > 0 THEN

        SELECT 
            WAVE_ID,
            STATION_ID,
            PICK_TIMESTAMP,
            PICKED_QUANTITY
        FROM 
            pick_wave_order_master
        WHERE 
            BIN_ID = p_bin_id
        ORDER BY 
            PICK_TIMESTAMP DESC
        LIMIT 1;

    ELSE

        SELECT 
            WAVE_ID,
            STATION_ID,
            PICK_TIMESTAMP,
            PICKED_QUANTITY
        FROM 
            pick_wave_order_master_archive
        WHERE 
            BIN_ID = p_bin_id
        ORDER BY 
            PICK_TIMESTAMP DESC
        LIMIT 1;

    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BIN_DETAILS_BY_BIN_ID_GET_LAST_PUT_WAVE_DETAILS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BIN_DETAILS_BY_BIN_ID_GET_LAST_PUT_WAVE_DETAILS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BIN_DETAILS_BY_BIN_ID_GET_LAST_PUT_WAVE_DETAILS`(
    IN p_bin_id VARCHAR(100)
)
BEGIN
    IF (
        SELECT COUNT(*) 
        FROM put_wave_order_master
        WHERE BIN_ID = p_bin_id
          AND PUT_TIMESTAMP IS NOT NULL
    ) > 0 THEN
    
        SELECT 
            WAVE_ID,
            STATION_ID,
            PUT_TIMESTAMP,
            PUT_QUANTITY
        FROM 
            put_wave_order_master
        WHERE 
            BIN_ID = p_bin_id
        ORDER BY 
            PUT_TIMESTAMP DESC
        LIMIT 1;

    ELSE
    
        SELECT 
            WAVE_ID,
            STATION_ID,
            PUT_TIMESTAMP,
            PUT_QUANTITY
        FROM 
            put_wave_order_master_archive
        WHERE 
            BIN_ID = p_bin_id
        ORDER BY 
            PUT_TIMESTAMP DESC
        LIMIT 1;

    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BIN_DETAILS_BY_BIN_ID_GET_LIVE_LOCATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BIN_DETAILS_BY_BIN_ID_GET_LIVE_LOCATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BIN_DETAILS_BY_BIN_ID_GET_LIVE_LOCATION`(
    IN p_bin_ids JSON
)
BEGIN
    
    SELECT
        CASE WHEN COALESCE(obm.STATUS, 'PENDING') = 'PENDING' THEN lm.X END AS X,
        CASE WHEN COALESCE(obm.STATUS, 'PENDING') = 'PENDING' THEN lm.Y END AS Y,
        CASE WHEN COALESCE(obm.STATUS, 'PENDING') = 'PENDING' THEN lm.Z END AS Z,
        CASE WHEN obm.STATUS IN ('TASK_ALLOCATED','BIN_PICKED','OPERATION_COMPLETED')
             THEN obm.BOT_ID END AS BOT_ID,
        CASE WHEN obm.STATUS IN ('PRE_ON_STATION','ON_STATION','POST_ON_STATION')
             THEN obm.STATION_ID END AS STATION_ID
    FROM store_bin_master AS sbm
    JOIN location_master AS lm
      ON lm.LOCATION_ID = sbm.LOCATION_ID
    LEFT JOIN (
        
        SELECT obm1.BIN_ID, obm1.STATUS, obm1.BOT_ID, obm1.STATION_ID
        FROM order_bin_mapping AS obm1
        WHERE obm1.BIN_ID = BIN_ID
        ORDER BY obm1.INSERTED_TIMESTAMP DESC
        LIMIT 1
    ) AS obm
    ON obm.BIN_ID = sbm.BIN_ID
    WHERE sbm.BIN_ID IN (
        SELECT jt.bin_id
        FROM JSON_TABLE(
            p_bin_ids,
            '$[*]' COLUMNS (
                bin_id VARCHAR(100) PATH '$'
            )
        ) jt
    );
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BIN_DETAILS_BY_BIN_ID_GET_LOCATION_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BIN_DETAILS_BY_BIN_ID_GET_LOCATION_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BIN_DETAILS_BY_BIN_ID_GET_LOCATION_INFO`(
    IN p_bin_ids JSON
)
BEGIN
    SELECT
	sbm.BIN_ID,
	bim.BIN_BARCODE,
        lm.X,
        lm.Y,
        lm.Z,
        lm.LOCATION_ID,
        lm.Z AS LEVEL,
        lm.AISLE_NUMBER AS AISLE,
        lm.TOWER_NUMBER AS TOWER,
        lm.TOWER_SIDE AS SIDE
    FROM 
        store_bin_master sbm
    INNER JOIN 
        location_master lm 
            ON sbm.LOCATION_ID = lm.LOCATION_ID
    left join
	bin_info_master bim
	on sbm.BIN_ID = bim.BIN_ID
    WHERE 
        sbm.BIN_ID IN (
            SELECT jt.bin_id
            FROM JSON_TABLE(
                p_bin_ids,
                '$[*]' COLUMNS (
                    bin_id VARCHAR(100) PATH '$'
                )
            ) jt
        );
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_ALARMS_BYPASS_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_ALARMS_BYPASS_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_ALARMS_BYPASS_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
 SELECT 
        bal.bot_id, 
        bal.alarm_id AS 'alarm_code', 
        am.alarm_description, 
        bal.inserted_timestamp,
        bal.is_bypassed
    FROM 
        `bot_manual_alarm_log` bal
    LEFT JOIN 
        `manual_alarm_master` am 
    ON 
        bal.alarm_id = am.alarm_id
    WHERE 
        am.bypass = 1
    AND 
        bal.bot_id = BotId
    ORDER BY 
        bal.inserted_timestamp DESC;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_ALARMS_BYPASS_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_ALARMS_BYPASS_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_ALARMS_BYPASS_UPDATE_BY_BOT_ID`(IN Parameters JSON)
BEGIN
    DECLARE BotId VARCHAR(255);
    DECLARE AlarmCode VARCHAR(20);
    DECLARE AlarmTimestamp DATETIME;
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    
    SET BotId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.botId'));
    SET AlarmCode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.alarm_code'));
    SET AlarmTimestamp = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.timestamp'));
    
    IF AlarmCode = "1" THEN
        UPDATE teleoperation_bool_data
        SET `Alarm Bypass-1 (Alarm code -1)` = 1
        WHERE BOT_ID = BotId;
    ELSEIF AlarmCode = "22" THEN
        UPDATE teleoperation_bool_data
        SET `Alarm Bypass-2 (Alarm code -22)` = 1
        WHERE BOT_ID = BotId;
    ELSEIF AlarmCode = "24" THEN
        UPDATE teleoperation_bool_data
        SET `Alarm Bypass-3 (Alarm code -24)` = 1
        WHERE BOT_ID = BotId;
    ELSEIF AlarmCode = "26" THEN
        UPDATE teleoperation_bool_data
        SET `Alarm Bypass-4 (Alarm code -26)` = 1
        WHERE BOT_ID = BotId;
    ELSEIF AlarmCode = "35" THEN
        UPDATE teleoperation_bool_data
        SET `Alarm Bypass-5 (Alarm code -35)` = 1
        WHERE BOT_ID = BotId;
    ELSEIF AlarmCode = "47" THEN
        UPDATE teleoperation_bool_data
        SET `Alarm Bypass-6 (Alarm code -47)` = 1
        WHERE BOT_ID = BotId;
    ELSEIF AlarmCode = "48" THEN
        UPDATE teleoperation_bool_data
        SET `Alarm Bypass-7 (Alarm code -48)` = 1
        WHERE BOT_ID = BotId;
    ELSEIF AlarmCode = "70" THEN
        UPDATE teleoperation_bool_data
        SET `Alarm Bypass-8 (Alarm code -70)` = 1
        WHERE BOT_ID = BotId;
    ELSEIF AlarmCode = "77" THEN
        UPDATE teleoperation_bool_data
        SET `Alarm Bypass-9 (Alarm code -77)` = 1
        WHERE BOT_ID = BotId;
    ELSE
        
        SET Success = 0; 
        SET Result = 'Invalid Alarm Code';
        SELECT Success AS Success, Result AS Result; 
      
    END IF;
    UPDATE bot_manual_alarm_log
    SET IS_BYPASSED = 1
    WHERE BOT_ID = BotId
    AND ALARM_ID = AlarmCode
    AND INSERTED_TIMESTAMP = AlarmTimestamp;
    
    SET Result = 'Successfully updated';
    
    SELECT Success AS Success, Result AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_ALARMS_BYPASS_USER_VALIDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_ALARMS_BYPASS_USER_VALIDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_ALARMS_BYPASS_USER_VALIDATE`(
    IN UserName VARCHAR(200), 
    IN UserPassword VARCHAR(100)
)
BEGIN
    DECLARE PasswordWithSalt VARCHAR(256);
    DECLARE userCount INT DEFAULT 0;
    
    
    SELECT CONCAT(UserPassword, SALT) INTO PasswordWithSalt 
    FROM dashboard_user_master 
    WHERE USER_NAME = UserName;
    
    
    SELECT COUNT(*) INTO userCount
    FROM dashboard_user_master 
    WHERE USER_NAME = UserName
      AND USER_PASSWORD = MD5(PasswordWithSalt)
      AND IS_ACTIVE = 1;
      
    
    IF userCount >= 1 THEN
        SELECT '1' AS Success, 'USER is Valid' AS Result;
    ELSE
        SELECT '0' AS Success, 'Invalid Password' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_ALARMS_HISTORY_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_ALARMS_HISTORY_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_ALARMS_HISTORY_BY_BOT_ID`(
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN TYPE VARCHAR(255)
)
BEGIN
	DECLARE Inserted_time DATETIME(3);
	DECLARE AlarmID  BIGINT;
	DECLARE BINOPERATION VARCHAR(100);
        DECLARE BOTOPERATION VARCHAR(100);
        DECLARE ACTION_INSTRUCTION VARCHAR(100);
        
    
    IF TYPE = 'normal' THEN
        SELECT 
            bal.BOT_ID, 
            bal.ALARM_CODE, 
            am.ALARM_DESCRIPTION, 
            bal.INSERTED_TIMESTAMP
        FROM 
            bot_alarm_log bal
        LEFT JOIN 
            alarm_master am 
        ON 
            bal.ALARM_CODE = am.ALARM_CODE
        WHERE 
            am.ALARM_TYPE = 'normal'
        AND 
            bal.BOT_ID = BotId
        ORDER BY 
            bal.INSERTED_TIMESTAMP DESC;
    
    ELSEIF TYPE = 'maintenance' THEN
    
	SELECT ID,INSERTED_TIMESTAMP FROM maintenance_alarm_logs WHERE BOT_ID = BotId 
	AND ALARM_DESCRIPTION = 'Slider Servo Error' 
	ORDER BY ID DESC LIMIT 1 INTO AlarmID,Inserted_time;
	
	SELECT CONCAT('Bin ', s.PICK_PUT) AS BIN_OPERATION,
	CONCAT('BOT is performing ', s.PICK_PUT, ' operation') AS BOT_OPERATION,
	CASE 
	WHEN s.PICK_PUT = 'PICK' THEN 'Keep Bin Back in Rack'
	WHEN s.PICK_PUT = 'PUT' THEN 'Keep Bin on Bot'
	ELSE NULL
	END AS ACTION_INSTRUCTION
	INTO 
            BINOPERATION, BOTOPERATION, ACTION_INSTRUCTION
                    FROM 
                        steps_archive s
                    WHERE 
                        s.BOT_ID = BotId
                    AND 
                        s.PICK_PUT IN ('PICK', 'PUT')
                   
                     
                    AND 
                        s.INSERT_TIME < Inserted_time
                    ORDER BY 
                        s.ID DESC 
                    LIMIT 1 ;
                   
        SELECT 
            mal.BOT_ID, 
            mal.ALARM_CODE, 
            am.ALARM_DESCRIPTION, 
            mal.INSERTED_TIMESTAMP,
            CASE 
                WHEN mal.ID = AlarmID THEN BINOPERATION          
                ELSE NULL
            END AS BIN_OPERATION,
            CASE 
                WHEN mal.ID = AlarmID THEN BOTOPERATION
                ELSE NULL
            END AS BOT_OPERATION,
	CASE 
	WHEN mal.ID = AlarmID THEN ACTION_INSTRUCTION
	ELSE NULL
	END AS ACTION_INSTRUCTION
        FROM 
            maintenance_alarm_logs mal
        LEFT JOIN 
            alarm_master am 
        ON 
            mal.ALARM_CODE = am.ALARM_CODE
        WHERE 
            am.ALARM_TYPE = 'maintenance'
        AND 
            mal.BOT_ID = BotId
        ORDER BY 
            mal.INSERTED_TIMESTAMP DESC;
    
    ELSEIF TYPE = 'manual' THEN
        SELECT 
            m.BOT_ID, 
            m.ALARM_DESCRIPTION, 
            m.INSERTED_TIMESTAMP
        FROM 
            bot_manual_alarm_log m
        WHERE 
            m.BOT_ID = BotId
        ORDER BY 
            m.INSERTED_TIMESTAMP DESC;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_AUTO_CALIBRATION_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_AUTO_CALIBRATION_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_AUTO_CALIBRATION_BY_BOT_ID`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_bot_id VARCHAR(50);
    DECLARE p_bit    INT;
    
    DECLARE is_bot_enabled      INT DEFAULT 0;
    DECLARE is_bot_at_home      INT DEFAULT 0;
    DECLARE wave_running_count  INT DEFAULT 0;
    DECLARE task_running_count  INT DEFAULT 0;
    
    DECLARE Success INT DEFAULT 1;
    DECLARE Result  VARCHAR(255) DEFAULT 'Operation Successful';
    
    SET p_bot_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bot_id'));
    SET p_bit    = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bit')) AS UNSIGNED);
    
    SELECT COUNT(*)
    INTO is_bot_enabled
    FROM bot_master
    WHERE BOT_ID = p_bot_id AND STATUS = 'ENABLED';
    
    SELECT COUNT(*)
    INTO is_bot_at_home
    FROM subcontroller_reservations_master
    WHERE BOT_ID = p_bot_id AND TYPE = 'HOME';
    
    SELECT COUNT(*)
    INTO wave_running_count
    FROM hw_station_master
    WHERE WAVE_ID IS NOT NULL;
    
    SELECT COUNT(*)
    INTO task_running_count
    FROM task_master
    WHERE BOT_ID = p_bot_id AND STATUS IN ('PENDING', 'PROCESSING');
    
    IF is_bot_enabled = 0 THEN
        SET Success = 0;
        SET Result = 'Bot is not ENABLED';
    ELSEIF is_bot_at_home = 0 THEN
        SET Success = 0;
        SET Result = 'Bot is not at HOME location';
    ELSEIF wave_running_count > 0 THEN
        SET Success = 0;
        SET Result = 'Wave(s) Running';
    ELSEIF task_running_count > 0 THEN
        SET Success = 0;
        SET Result = 'Task(s) Running';
    ELSE
        IF p_bit = 1 THEN
            UPDATE teleoperation_bool_data
            SET `Auto Calibration Start` = 1
            WHERE BOT_ID = p_bot_id;
        ELSEIF p_bit = 0 THEN
            UPDATE teleoperation_bool_data
            SET `Auto Calibration Start` = 0
            WHERE BOT_ID = p_bot_id;
            UPDATE teleoperation_bool_data_feedback
            SET `Auto Calibration On` = 0
            WHERE BOT_ID = p_bot_id;
        END IF;
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_AUTO_CALIBRATION_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_AUTO_CALIBRATION_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_AUTO_CALIBRATION_FEEDBACK_BY_BOT_ID`(
    IN p_bot_id VARCHAR(10)
)
BEGIN
    DECLARE Success                          INT         DEFAULT 1;
    DECLARE Result                           TEXT;
    DECLARE wave_running_count               INT         DEFAULT 0;
    DECLARE is_bot_enabled                   INT         DEFAULT 0;
    DECLARE is_bot_at_home                   INT         DEFAULT 0;
    

    DECLARE auto_calibration_start_feedback  TINYINT     DEFAULT 0;
    DECLARE auto_calibration_on_feedback     TINYINT     DEFAULT 0;
    DECLARE auto_calibration_done_feedback   TINYINT     DEFAULT 0;

    DECLARE auto_calibration_done_ts         DATETIME    DEFAULT NULL;
    DECLARE auto_calibration_done_since      INT         DEFAULT 0;
    DECLARE auto_calibration_status_text     TEXT;
    DECLARE auto_calibration_button_color    VARCHAR(10);

    
    DROP TEMPORARY TABLE IF EXISTS temp_validations_list;
    CREATE TEMPORARY TABLE temp_validations_list (
        FAILED_ID     INT  NOT NULL AUTO_INCREMENT,
        FAILED_REASON TEXT NOT NULL,
        PRIMARY KEY (FAILED_ID)
    ) ENGINE=INNODB;

    SELECT COUNT(*)
      INTO wave_running_count
    FROM `hw_station_master`
    WHERE `WAVE_ID` IS NOT NULL;

    IF (wave_running_count < 0) THEN
      INSERT INTO temp_validations_list (FAILED_REASON)
      VALUES (CONCAT('Wave running on ', wave_running_count, ' station(s).'));
    END IF;

    SELECT COUNT(*)
      INTO is_bot_enabled
    FROM bot_master
    WHERE BOT_ID = p_bot_id
      AND STATUS = 'ENABLED';

    IF (is_bot_enabled = 0) THEN
        INSERT INTO temp_validations_list (FAILED_REASON)
        VALUES ('Bot is not ENABLED');
    END IF;

    SELECT COUNT(*)
      INTO is_bot_at_home
    FROM subcontroller_reservations_master
    WHERE BOT_ID = p_bot_id
      AND TYPE = 'HOME';

    IF (is_bot_at_home = 0) THEN
        INSERT INTO temp_validations_list (FAILED_REASON)
        VALUES ('Bot is not at HOME location');
    END IF;

    

    IF (SELECT COUNT(*) FROM `temp_validations_list`) > 0 THEN
        SELECT
            0   AS `Success`,
            'Validation failed.' AS `Result`,
            409 AS `StatusCode`,
            COALESCE(
                JSON_ARRAYAGG(
                    JSON_OBJECT('FAILED_ID', `FAILED_ID`, 'FAILED_REASON', `FAILED_REASON`)
                ),
                JSON_ARRAY()
            ) AS `DataSet`
        FROM `temp_validations_list`;
    ELSE
        
        SELECT
            AUTO_CALIBRATION_DONE_TIMESTAMP,
            IFNULL(DATEDIFF(CURDATE(), AUTO_CALIBRATION_DONE_TIMESTAMP), 0)
        INTO
            auto_calibration_done_ts,
            auto_calibration_done_since
        FROM dashboard_bot_master
        WHERE BOT_ID = p_bot_id
        LIMIT 1;

        SELECT `Auto Calibration Start`
          INTO auto_calibration_start_feedback
        FROM teleoperation_bool_data
        WHERE BOT_ID = p_bot_id
        LIMIT 1;

        SELECT `Auto Calibration On`, `Auto Calibration Done`
          INTO auto_calibration_on_feedback, auto_calibration_done_feedback
        FROM teleoperation_bool_data_feedback
        WHERE BOT_ID = p_bot_id
        LIMIT 1;

        CASE
            WHEN auto_calibration_done_since <= 45 OR auto_calibration_done_ts IS NULL THEN
                SET auto_calibration_status_text  = '(PENDING)';
                SET auto_calibration_button_color = 'danger';
            WHEN auto_calibration_start_feedback = 1
             AND auto_calibration_on_feedback    = 1
             AND auto_calibration_done_feedback  = 1 THEN
                SET auto_calibration_status_text  = '(COMPLETED)';
                SET auto_calibration_button_color = 'success';
            WHEN auto_calibration_start_feedback = 1
             AND auto_calibration_on_feedback    = 1 THEN
                SET auto_calibration_status_text  = '(IN PROGRESS)';
                SET auto_calibration_button_color = 'warning';
            ELSE
                SET auto_calibration_status_text  = '';
                SET auto_calibration_button_color = 'success';
        END CASE;

        SELECT
            Success,
            Result,
            auto_calibration_on_feedback      AS FEEDBACK,
            auto_calibration_done_since       AS AUTO_CALIBRATION_DONE_SINCE,
            auto_calibration_done_ts          AS AUTO_CALIBRATION_DONE_TIMESTAMP,
            auto_calibration_status_text      AS AUTO_CALIBRATION_STATUS_TEXT,
            auto_calibration_button_color     AS AUTO_CALIBRATION_BUTTON_COLOR;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS `temp_validations_list`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_AUTO_START_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_AUTO_START_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_AUTO_START_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE estop_feedback VARCHAR(255);
    DECLARE statusalarambit VARCHAR(255);
    DECLARE home_ok_feedback VARCHAR(255);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    
    
    SELECT `Emergency Stop Feedback` 
    INTO estop_feedback
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = BotId;
    
    IF estop_feedback = 0 THEN
        
        SELECT `No Alarm Feedback` 
        INTO statusalarambit
        FROM `teleoperation_bool_data_feedback`
        WHERE bot_id = BotId;
        
        IF statusalarambit = 0 THEN
            
            SELECT `Home OK Feedback` 
            INTO home_ok_feedback
            FROM `teleoperation_bool_data_feedback`
            WHERE bot_id = BotId;
            
            IF home_ok_feedback = 1 THEN
                
                UPDATE `teleoperation_bool_data`
                SET `Auto Start Bit` = 0
                WHERE bot_id = BotId;
                
                UPDATE `teleoperation_bool_data`
                SET `Auto Start Bit` = '1'
                WHERE bot_id = BotId;
                
                SET Success = 1;
                SET Result = CONCAT('Auto Start successful for Bot ID ', BotId);
            ELSE
                
                SET Success = 0;
                SET Result = CONCAT('Home OK Feedback failed for Bot ID ', BotId);
            END IF;
        ELSE
            
            SET Success = 0;
            SET Result = CONCAT('No Alarm Feedback is active for Bot ID ', BotId);
        END IF;
    ELSE
        
        SET Success = 0;
        SET Result = CONCAT('Emergency Stop Feedback is active for Bot ID ', BotId);
    END IF;
    
    SELECT Success, Result;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_AUTO_STOP_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_AUTO_STOP_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_AUTO_STOP_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE estop_feedback VARCHAR(255);
    DECLARE no_alarm_feedback VARCHAR(255);
    DECLARE auto_start_feedback VARCHAR(255);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    
    SELECT `Emergency Stop Feedback`
    INTO estop_feedback
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = BotId;
    
    IF estop_feedback = 0 THEN
        
        SELECT `No Alarm Feedback`
        INTO no_alarm_feedback
        FROM `teleoperation_bool_data_feedback`
        WHERE bot_id = BotId;
        
        IF no_alarm_feedback = 0 THEN
            
            SELECT `Auto Start Feedback`
            INTO auto_start_feedback
            FROM `teleoperation_bool_data_feedback`
            WHERE bot_id = BotId;
            
            IF auto_start_feedback = 1 THEN
                
                UPDATE `teleoperation_bool_data`
                SET `Auto Start Bit` = 0
                WHERE bot_id = BotId;
                
                SET Success = 1;
                SET Result = CONCAT('Auto Stop successful for Bot ID ', BotId);
            ELSE
                
                SET Success = 0;
                SET Result = CONCAT('Auto Start Feedback not active for Bot ID ', BotId);
            END IF;
        ELSE
            
            SET Success = 0;
            SET Result = CONCAT('No Alarm Feedback is active for Bot ID ', BotId);
        END IF;
    ELSE
        
        SET Success = 0;
        SET Result = CONCAT('Emergency Stop Feedback is active for Bot ID ', BotId);
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_BIN_STATUS_NON_RECOVERY_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_BIN_STATUS_NON_RECOVERY_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_BIN_STATUS_NON_RECOVERY_UPDATE_BY_BOT_ID`(
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    DECLARE v_bot_status VARCHAR(10);
    DECLARE v_current_status VARCHAR(10);
    DECLARE attempt INT DEFAULT 1;
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255);
    
    IF EXISTS (SELECT 1 FROM teleoperation_bool_data WHERE bot_id = BotId) THEN
        
        IF EXISTS (
            SELECT 1 
            FROM task_master 
            WHERE bot_id = BotId 
              AND task_type = 'BIN_FROM_ZONE' 
              AND STATUS != 'COMPLETED'
        ) THEN
            
            SELECT LOAD_CONDITION INTO v_bot_status
            FROM bot_master
            WHERE BOT_ID = BotId;
            
            IF v_bot_status = 'LD' THEN
                UPDATE bot_master
                SET LOAD_NON_RECOVERY_BIT = 1
                WHERE BOT_ID = BotId;
                SET Success = 1;
                SET Result = 'Bin Status already Loaded & Non-Recovery Done Successfully';
            ELSE
                
                UPDATE teleoperation_bool_data
                SET `Bin Load Status` = 1
                WHERE bot_id = BotId;
                DO SLEEP(1);
                UPDATE teleoperation_bool_data
                SET `Bin Load Status` = 0
                WHERE bot_id = BotId;
                DO SLEEP(1);
                SELECT LOAD_CONDITION INTO v_current_status
                FROM bot_master
                WHERE BOT_ID = BotId;
                IF v_current_status != v_bot_status THEN
                    UPDATE bot_master
                    SET LOAD_NON_RECOVERY_BIT = 1
                    WHERE BOT_ID = BotId;
                    SET Success = 1;
                    SET Result = CONCAT('Bin Status for ', BotId, ' changed to ', v_current_status, ' from ', v_bot_status, ' & Non-Recovery Done Successfully');
                ELSE
                    
                    WHILE attempt < 3 DO
                        SET attempt = attempt + 1;
                        UPDATE teleoperation_bool_data
                        SET `Bin Load Status` = 1
                        WHERE bot_id = BotId;
                        DO SLEEP(1);
                        UPDATE teleoperation_bool_data
                        SET `Bin Load Status` = 0
                        WHERE bot_id = BotId;
                        DO SLEEP(1);
                        SELECT LOAD_CONDITION INTO v_current_status
                        FROM bot_master
                        WHERE BOT_ID = BotId;
                        IF v_current_status != v_bot_status THEN
                            UPDATE bot_master
                            SET LOAD_NON_RECOVERY_BIT = 1
                            WHERE BOT_ID = BotId;
                            SET Success = 1;
                            SET Result = CONCAT('Bin Status for ', BotId, ' changed to ', v_current_status, ' from ', v_bot_status, ' & Non-Recovery Done Successfully');
                        END IF;
                    END WHILE;
                    
                    IF Success = 0 THEN
                        SET Result = 'Bin Status did not change within expected time';
                    END IF;
                END IF;
            END IF;
        ELSE
            SET Success = 0;
            SET Result = 'No active BIN_FROM_ZONE task found for given BotId';
        END IF;
    ELSE
        SET Success = 0;
        SET Result = 'No record found for given BotId';
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_BIN_STATUS_RECOVERY_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_BIN_STATUS_RECOVERY_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_BIN_STATUS_RECOVERY_UPDATE_BY_BOT_ID`(
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    DECLARE v_bot_status VARCHAR(10);
    DECLARE v_current_status VARCHAR(10);
    DECLARE attempt INT DEFAULT 1;
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255);
    IF EXISTS (SELECT 1 FROM teleoperation_bool_data WHERE bot_id = BotId) THEN
        
        SELECT LOAD_CONDITION INTO v_bot_status
        FROM bot_master
        WHERE BOT_ID = BotId;
        
        IF v_bot_status = 'LD' THEN
            UPDATE bot_master
            SET RECOVERY_BIT = 1
            WHERE BOT_ID = BotId;
            SET Success = 1;
            SET Result = 'Bin Status already Loaded & Recovery Done Successfully';
        ELSE
            
            UPDATE teleoperation_bool_data
            SET `Bin Load Status` = 1
            WHERE bot_id = BotId;
            DO SLEEP(1);
            UPDATE teleoperation_bool_data
            SET `Bin Load Status` = 0
            WHERE bot_id = BotId;
            DO SLEEP(1);
            SELECT LOAD_CONDITION INTO v_current_status
            FROM bot_master
            WHERE BOT_ID = BotId;
            IF v_current_status != v_bot_status THEN
                UPDATE bot_master
                SET RECOVERY_BIT = 1
                WHERE BOT_ID = BotId;
                SET Success = 1;
                SET Result = CONCAT('Bin Status for ', BotId, ' changed to ', v_current_status, ' from ', v_bot_status, ' & Recovery Done Successfully');
            ELSE
                
                WHILE attempt < 3 DO
                    SET attempt = attempt + 1;
                    UPDATE teleoperation_bool_data
                    SET `Bin Load Status` = 1
                    WHERE bot_id = BotId;
                    DO SLEEP(1);
                    UPDATE teleoperation_bool_data
                    SET `Bin Load Status` = 0
                    WHERE bot_id = BotId;
                    DO SLEEP(1);
                    SELECT LOAD_CONDITION INTO v_current_status
                    FROM bot_master
                    WHERE BOT_ID = BotId;
                    IF v_current_status != v_bot_status THEN
                        UPDATE bot_master
                        SET RECOVERY_BIT = 1
                        WHERE BOT_ID = BotId;
                        SET Success = 1;
                        SET Result = CONCAT('Bin Status for ', BotId, ' changed to ', v_current_status, ' from ', v_bot_status, ' & Recovery Done Successfully');
                    END IF;
                END WHILE;
                
                IF Success = 0 THEN
                    SET Result = 'Bin Status did not change within expected time';
                END IF;
            END IF;
        END IF;
    ELSE
        SET Success = 0;
        SET Result = 'No record found for given BotId';
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_BIN_STATUS_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_BIN_STATUS_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_BIN_STATUS_UPDATE_BY_BOT_ID`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_bot_id VARCHAR(20);
    DECLARE p_identifier_bit INT;
    DECLARE v_bot_status VARCHAR(10);
    DECLARE v_current_status VARCHAR(10);
    DECLARE attempt INT DEFAULT 1;
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255);
    
    SET p_bot_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.botId'));
    SET p_identifier_bit = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.identifierBit'));
    
    IF EXISTS (SELECT 1 FROM teleoperation_bool_data WHERE bot_id = p_bot_id) THEN
        
        SELECT LOAD_CONDITION INTO v_bot_status
        FROM bot_master
        WHERE BOT_ID = p_bot_id;
        
        IF v_bot_status = 'LD' AND p_identifier_bit = 1 THEN
            SET Success = 1;
            SET Result = 'Bin Status already Loaded';
        ELSEIF v_bot_status = 'UL' AND p_identifier_bit = 0 THEN
            SET Success = 1;
            SET Result = 'Bin Status already Unloaded';
        ELSE
            
            UPDATE teleoperation_bool_data
            SET `Bin Load Status` = 1
            WHERE bot_id = p_bot_id;
            DO SLEEP(1);
            UPDATE teleoperation_bool_data
            SET `Bin Load Status` = 0
            WHERE bot_id = p_bot_id;
            DO SLEEP(1);
            SELECT LOAD_CONDITION INTO v_current_status
            FROM bot_master
            WHERE BOT_ID = p_bot_id;
            
            IF v_current_status != v_bot_status THEN
                SET Success = 1;
                SET Result = CONCAT('Bin Status for ', p_bot_id, ' changed to ', v_current_status, ' from ', v_bot_status);
            ELSE
                
                WHILE attempt < 3 DO
                    SET attempt = attempt + 1;
                    UPDATE teleoperation_bool_data
                    SET `Bin Load Status` = 1
                    WHERE bot_id = p_bot_id;
                    DO SLEEP(1);
                    UPDATE teleoperation_bool_data
                    SET `Bin Load Status` = 0
                    WHERE bot_id = p_bot_id;
                    DO SLEEP(1);
                    SELECT LOAD_CONDITION INTO v_current_status
                    FROM bot_master
                    WHERE BOT_ID = p_bot_id;
                    IF v_current_status != v_bot_status THEN
                        SET Success = 1;
                        SET Result = CONCAT('Bin Status for ', p_bot_id, ' changed to ', v_current_status, ' from ', v_bot_status);
                    END IF;
                END WHILE;
                IF Success = 0 THEN
                    SET Result = 'Bin Status did not change within expected time';
                END IF;
            END IF;
        END IF;
    ELSE
        SET Success = 0;
        SET Result = 'No record found for given p_bot_id';
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_CHARGING_BIT_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_CHARGING_BIT_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_CHARGING_BIT_UPDATE_BY_BOT_ID`( 
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,       
    IN ColumnValue VARCHAR(255)  
)
BEGIN
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET Success = 0;
        SET Result = 'An error occurred while processing the request.';
        SELECT Success, Result;
    END;
    
    START TRANSACTION;
    
    IF ColumnValue NOT IN ('0', '1') THEN
        SET Success = 0;
        SET Result = 'Invalid ColumnValue. Must be 0 or 1.';
        ROLLBACK;
        SELECT Success, Result;
    END IF;
    
    UPDATE bot_master 
    SET CHARGING_BIT = CAST(ColumnValue AS UNSIGNED) 
    WHERE BOT_ID = BotId;
    SET Result = CONCAT('Charging Bit changed to ', ColumnValue);
    
    COMMIT;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_CREATE_MANUAL_TASK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_CREATE_MANUAL_TASK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_BOT_CREATE_MANUAL_TASK`(IN Parameters JSON)
proc: BEGIN
    DECLARE p_source_x INT;
    DECLARE p_source_y INT;
    DECLARE p_source_z DOUBLE;
    DECLARE p_destination_x INT;
    DECLARE p_destination_y INT;
    DECLARE p_destination_z DOUBLE;
    DECLARE p_bot_id VARCHAR(10);
    DECLARE p_task_type VARCHAR(50);
    DECLARE p_username VARCHAR(50);

    DECLARE v_task_processing_count INT DEFAULT 0;
    DECLARE v_no_alarm_feedback INT DEFAULT 0;
    DECLARE v_home_ok_feedback INT DEFAULT 0;

    DECLARE v_start_location_id INT DEFAULT 0;
    DECLARE v_end_location_id INT DEFAULT 0;
    DECLARE v_pick_put_offset INT DEFAULT 0;

    DECLARE v_inserted_id INT DEFAULT 0;
    DECLARE v_current_status VARCHAR(50);
    DECLARE v_attempts INT DEFAULT 0;
    DECLARE v_max_attempts INT DEFAULT 10;

    DECLARE v_bot_loaded VARCHAR(2) DEFAULT 'UL';
    DECLARE v_location_blocked INT DEFAULT 0;
    DECLARE v_location_type VARCHAR(50) DEFAULT '';
    DECLARE v_is_barcode INT DEFAULT 1;
    DECLARE v_bot_present INT DEFAULT 0;

    
    DECLARE v_source_type VARCHAR(50) DEFAULT '';
    DECLARE v_dest_type_raw VARCHAR(50) DEFAULT '';

    DECLARE v_can_insert INT DEFAULT 1;

    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255) DEFAULT '';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CALL DSB_GENERIC_TRANSACTION_ERROR_HANDLER();
    END;

    
    SET p_source_x      = Parameters ->> '$.source_x';
    SET p_source_y      = Parameters ->> '$.source_y';
    SET p_source_z      = Parameters ->> '$.source_z';
    SET p_destination_x = Parameters ->> '$.destination_x';
    SET p_destination_y = Parameters ->> '$.destination_y';
    SET p_destination_z = Parameters ->> '$.destination_z';
    SET p_bot_id        = Parameters ->> '$.bot_id';
    SET p_task_type     = Parameters ->> '$.task_type';
    SET p_username      = Parameters ->> '$.updated_by';

    
    SELECT COUNT(*)
    INTO v_task_processing_count
    FROM task_master
    WHERE STATUS <> 'COMPLETED'
      AND BOT_ID = p_bot_id;

    IF v_task_processing_count > 0 THEN
        SET v_can_insert = 0;
        SET Result = 'Manual task already running ...';
    END IF;

    
    IF v_can_insert = 1 THEN
        SELECT `No Alarm Feedback`, `Home OK Feedback`
        INTO v_no_alarm_feedback, v_home_ok_feedback
        FROM teleoperation_bool_data_feedback
        WHERE BOT_ID = p_bot_id;

        IF v_no_alarm_feedback = 1 THEN
            SET v_can_insert = 0;
            SET Result = 'Alarm active.';
        ELSEIF v_home_ok_feedback = 0 THEN
            SET v_can_insert = 0;
            SET Result = 'Bot not in Home position.';
        END IF;
    END IF;

    
    IF v_can_insert = 1 THEN
        SELECT GRIDX, GRIDY, GRIDZ, LOAD_CONDITION
        INTO p_source_x, p_source_y, p_source_z, v_bot_loaded
        FROM bot_master
        WHERE BOT_ID = p_bot_id;

        
        SELECT TYPE
        INTO v_source_type
        FROM location_master
        WHERE X = p_source_x AND Y = p_source_y AND Z = p_source_z
        LIMIT 1;
    END IF;

    
    IF v_can_insert = 1 THEN
        SELECT TYPE
        INTO v_location_type
        FROM location_master
        WHERE X = p_destination_x AND Y = p_destination_y AND Z = p_destination_z
        LIMIT 1;

        SET v_dest_type_raw = v_location_type;

        IF v_location_type = 'STORAGE_LOCATION' THEN
            SET v_can_insert = 0;
            SET Result = 'Destination location is STORAGE_LOCATION, please select another location.';
        END IF;
    END IF;

    
    IF v_can_insert = 1 THEN
        SELECT IS_BARCODE
        INTO v_is_barcode
        FROM location_master
        WHERE X = p_destination_x AND Y = p_destination_y AND Z = 0
        LIMIT 1;

        IF v_is_barcode = 0 THEN
            SET v_can_insert = 0;
            SET Result = 'Destination location is not barcode location, please select another location.';
        END IF;
    END IF;

    
    IF v_can_insert = 1 THEN
        IF p_source_x = p_destination_x
           AND p_source_y = p_destination_y
           AND p_source_z = p_destination_z
           AND v_location_type NOT LIKE 'TOWER%' THEN
            SET v_can_insert = 0;
            SET Result = 'Source and destination cannot be the same.';
        END IF;
    END IF;

    
    IF v_can_insert = 1 THEN
        IF v_bot_loaded = 'LD' AND v_location_type = 'CHARGING_STATION' THEN
            SET v_can_insert = 0;
            SET Result = 'Loaded bot cannot be sent to charging station';
        END IF;
    END IF;

    
    IF v_can_insert = 1 THEN
        IF v_source_type = 'CHARGING_STATION' AND v_dest_type_raw = 'HOME' THEN
            SET v_can_insert = 0;
            SET Result = 'Bot is at CHARGING_STATION, can go Home in Auto Start Mode.';
        END IF;
    END IF;

    
    IF v_can_insert = 1 THEN
        SELECT LOCATION_ID
        INTO v_start_location_id
        FROM location_master
        WHERE X = p_source_x AND Y = p_source_y AND Z = p_source_z
        LIMIT 1;

        
        IF p_task_type = 'NONE' THEN
            SELECT LOCATION_ID
            INTO v_end_location_id
            FROM location_master
            WHERE X = p_destination_x AND Y = p_destination_y AND Z = p_destination_z
              AND TYPE != 'STORAGE_LOCATION';
        ELSE
            IF p_task_type IN ('PICK LEFT', 'PUT LEFT', 'STATION_PUT') THEN
                SET v_pick_put_offset = -1;
            ELSEIF p_task_type IN ('PICK RIGHT', 'PUT RIGHT', 'STATION_PICK') THEN
                SET v_pick_put_offset = 1;
            ELSE
                SET v_pick_put_offset = 0;
            END IF;

            SELECT LOCATION_ID
            INTO v_end_location_id
            FROM location_master
            WHERE X = p_destination_x
              AND Y = p_destination_y + v_pick_put_offset
              AND Z = p_destination_z
              AND TYPE IN ('STORAGE_LOCATION', 'STATION_PUT', 'STATION_PICK');
        END IF;
    END IF;

    
    IF v_can_insert = 1 THEN
        SELECT COUNT(*)
        INTO v_location_blocked
        FROM location_block_master
        WHERE LOCATION_ID = v_end_location_id;

        IF v_location_blocked > 0 THEN
            SET v_can_insert = 0;
            SET Result = 'Destination location is blocked, please select another location.';
        END IF;
    END IF;

    
    IF v_can_insert = 1 THEN
        SELECT COUNT(*)
        INTO v_bot_present
        FROM bot_master
        WHERE GRIDX = p_destination_x
          AND GRIDY = p_destination_y
          AND GRIDZ = p_destination_z
          AND BOT_ID <> p_bot_id;

        IF v_bot_present > 0 THEN
            SET v_can_insert = 0;
            SET Result = 'Another bot already present at destination';
        END IF;
    END IF;

    
    IF v_can_insert = 0 THEN
        SET Success = 0;
        SELECT Success, Result;
        LEAVE proc;
    END IF;

    
    START TRANSACTION;

    UPDATE teleoperation_bool_data
    SET `Auto Start Bit` = 1
    WHERE BOT_ID = p_bot_id;

    INSERT INTO dashboard_manual_task_master (
        BOT_ID, START_LOCATION_ID, END_LOCATION_ID,
        START_PICK_PUT_SIDE, END_PICK_PUT_SIDE, STATUS,
        INSERTED_TIMESTAMP, INSERTED_BY
    ) VALUES (
        p_bot_id, v_start_location_id, v_end_location_id,
        'NONE', SUBSTRING_INDEX(p_task_type, ' ', 1), 'WAITING',
        NOW(), p_username
    );

    SET v_inserted_id = LAST_INSERT_ID();
    COMMIT;

    
    loop_check: LOOP
        SELECT STATUS
        INTO v_current_status
        FROM dashboard_manual_task_master
        WHERE ID = v_inserted_id;

        IF v_current_status <> 'WAITING' THEN
            LEAVE loop_check;
        END IF;

        SET v_attempts = v_attempts + 1;
        IF v_attempts >= v_max_attempts THEN
            SET v_current_status = 'TIMEOUT';
            LEAVE loop_check;
        END IF;

        DO SLEEP(1);
    END LOOP loop_check;

    IF v_current_status = 'FAILED' THEN
        SET Success = 0;
        SET Result = 'Manual task creation failed.';
    ELSEIF v_current_status = 'TIMEOUT' OR v_current_status = 'WAITING' THEN
        SET Success = 0;
        SET Result = 'Task creation timed out or still waiting';
    ELSE
        SET Success = 1;
        SET Result = 'Manual task created successfully';
    END IF;

    
    START TRANSACTION;

    INSERT INTO dashboard_log_manual_task_master (
        BOT_ID, START_LOCATION_ID, END_LOCATION_ID,
        START_PICK_PUT_SIDE, END_PICK_PUT_SIDE, STATUS,
        INSERTED_TIMESTAMP, INSERTED_BY
    )
    SELECT
        BOT_ID, START_LOCATION_ID, END_LOCATION_ID,
        START_PICK_PUT_SIDE, END_PICK_PUT_SIDE, STATUS,
        INSERTED_TIMESTAMP, INSERTED_BY
    FROM dashboard_manual_task_master
    WHERE ID = v_inserted_id;

    DELETE FROM dashboard_manual_task_master
    WHERE ID = v_inserted_id;

    COMMIT;

    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_CREATE_MANUAL_TASK_20260131` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_CREATE_MANUAL_TASK_20260131` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_BOT_CREATE_MANUAL_TASK_20260131`(IN Parameters JSON)
BEGIN
    
    DECLARE p_source_x INT;
    DECLARE p_source_y INT;
    DECLARE p_source_z DOUBLE;
    DECLARE p_destination_x INT;
    DECLARE p_destination_y INT;
    DECLARE p_destination_z DOUBLE;
    DECLARE p_bot_id VARCHAR(255);
    DECLARE p_task_type VARCHAR(255);
    DECLARE p_updated_by VARCHAR(255);
    
    DECLARE v_no_alarm_feedback INT DEFAULT 0;
    DECLARE v_home_ok_feedback INT DEFAULT 0;
    DECLARE v_task_processing_count INT DEFAULT 0;
    DECLARE v_start_location_id INT DEFAULT 0;
    DECLARE v_end_location_id INT DEFAULT 0;
    DECLARE v_pick_put_offset INT DEFAULT 0;
    DECLARE v_inserted_id INT DEFAULT 0;
    DECLARE v_current_status VARCHAR(50);
    DECLARE v_attempts INT DEFAULT 0;
    DECLARE v_max_attempts INT DEFAULT 10;
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255);
    
    SET p_source_x      = Parameters ->> '$.source_x';
    SET p_source_y      = Parameters ->> '$.source_y';
    SET p_source_z      = Parameters ->> '$.source_z';
    SET p_destination_x = Parameters ->> '$.destination_x';
    SET p_destination_y = Parameters ->> '$.destination_y';
    SET p_destination_z = Parameters ->> '$.destination_z';
    SET p_bot_id        = Parameters ->> '$.bot_id';
    SET p_task_type     = Parameters ->> '$.task_type';
    SET p_updated_by    = Parameters ->> '$.updated_by';
    
    SELECT `No Alarm Feedback`, `Home OK Feedback`
    INTO v_no_alarm_feedback, v_home_ok_feedback
    FROM teleoperation_bool_data_feedback
    WHERE BOT_ID = p_bot_id;
    
    SELECT COUNT(*) INTO v_task_processing_count
    FROM task_master
    WHERE STATUS <> 'COMPLETED' AND BOT_ID = p_bot_id;
    
    IF v_task_processing_count > 0 THEN
        SET Success = 0;
        SET Result = CONCAT('Manual task(s) already running for ', p_bot_id, '.');
    ELSEIF p_task_type IS NULL THEN
        SET Success = 0;
        SET Result = CONCAT('Task Type is missing for ', p_bot_id, '.');
    ELSEIF v_no_alarm_feedback = 1 THEN
        SET Success = 0;
        SET Result = CONCAT('Alarm active on ', p_bot_id, '.');
    ELSEIF v_home_ok_feedback = 0 THEN
        SET Success = 0;
        SET Result = CONCAT('Not Home for ', p_bot_id, '.');
    ELSE
        
        UPDATE teleoperation_bool_data
        SET `Auto Start Bit` = 1
        WHERE BOT_ID = p_bot_id;
        
        SELECT GRIDX, GRIDY, GRIDZ
        INTO p_source_x, p_source_y, p_source_z
        FROM bot_master
        WHERE BOT_ID = p_bot_id;
        SELECT LOCATION_ID
        INTO v_start_location_id
        FROM location_master
        WHERE X = p_source_x AND Y = p_source_y AND Z = p_source_z;
        
        IF p_task_type = 'NONE' THEN
            SELECT LOCATION_ID
            INTO v_end_location_id
            FROM location_master
            WHERE X = p_destination_x AND Y = p_destination_y AND Z = p_destination_z
              AND TYPE != 'STORAGE_LOCATION';
        ELSE
            IF p_task_type IN ('PICK LEFT', 'PUT LEFT', 'STATION_PUT') THEN
                SET v_pick_put_offset = -1;
            ELSEIF p_task_type IN ('PICK RIGHT', 'PUT RIGHT', 'STATION_PICK') THEN
                SET v_pick_put_offset = 1;
            ELSE
                SET v_pick_put_offset = 0;
            END IF;
            SELECT LOCATION_ID
            INTO v_end_location_id
            FROM location_master
            WHERE X = p_destination_x
              AND Y = p_destination_y + v_pick_put_offset
              AND Z = p_destination_z
              AND TYPE IN ('STORAGE_LOCATION', 'STATION_PUT', 'STATION_PICK');
        END IF;
        
        INSERT INTO dashboard_manual_task_master (
            BOT_ID, START_LOCATION_ID, END_LOCATION_ID,
            START_PICK_PUT_SIDE, END_PICK_PUT_SIDE, STATUS,
            INSERTED_TIMESTAMP, INSERTED_BY
        ) VALUES (
            p_bot_id, v_start_location_id, v_end_location_id,
            'NONE', SUBSTRING_INDEX(p_task_type, ' ', 1), 'WAITING',
            NOW(), p_updated_by
        );
        SET v_inserted_id = LAST_INSERT_ID();
        
        loop_check: LOOP
            SELECT STATUS
            INTO v_current_status
            FROM dashboard_manual_task_master
            WHERE ID = v_inserted_id;
            IF v_current_status != 'WAITING' THEN
                LEAVE loop_check;
            END IF;
            SET v_attempts = v_attempts + 1;
            IF v_attempts >= v_max_attempts THEN
                SET v_current_status = 'TIMEOUT';
                LEAVE loop_check;
            END IF;
            DO SLEEP(1);
        END LOOP loop_check;
        
        IF v_current_status = 'FAILED' THEN
            SET Success = 0;
            SET Result = CONCAT('Manual task creation failed for ', p_bot_id, '.');
        ELSEIF v_current_status = 'TIMEOUT' OR v_current_status = 'WAITING' THEN
            SET Success = 0;
            SET Result = CONCAT('Task creation timed out or still waiting for ', p_bot_id);
        ELSE
            SET Success = 1;
            SET Result = CONCAT('Manual task created successfully for ', p_bot_id, '.');
        END IF;
        
        INSERT INTO dashboard_log_manual_task_master (
            BOT_ID, START_LOCATION_ID, END_LOCATION_ID,
            START_PICK_PUT_SIDE, END_PICK_PUT_SIDE, STATUS,
            INSERTED_TIMESTAMP, INSERTED_BY
        )
        SELECT 
            BOT_ID, START_LOCATION_ID, END_LOCATION_ID,
            START_PICK_PUT_SIDE, END_PICK_PUT_SIDE, STATUS,
            INSERTED_TIMESTAMP, INSERTED_BY
        FROM dashboard_manual_task_master
        WHERE ID = v_inserted_id;
        DELETE FROM dashboard_manual_task_master
        WHERE ID = v_inserted_id;
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_EMERGENCY_STOP_SET_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_EMERGENCY_STOP_SET_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_EMERGENCY_STOP_SET_BY_BOT_ID`(IN Parameters JSON)
BEGIN
    DECLARE BotId VARCHAR(255);
    DECLARE EmergencyStopBit INT;
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255) DEFAULT 'Operation Successful';
    
    SET BotId = Parameters ->> '$.botId';
    SET EmergencyStopBit = Parameters ->> '$.EmergencyStopBit';
    
    
    IF EmergencyStopBit = 1 THEN 
        
        UPDATE teleoperation_bool_data
        SET `Emergency Stop` = 1
        WHERE bot_id = BotId;
        
        IF ROW_COUNT() = 0 THEN
            SET Success = 0;
            SET Result = CONCAT('Failed to update Emergency Stop for Bot ID: ', BotId);
        END IF;
        
    ELSE
        
        UPDATE teleoperation_bool_data
        SET `Emergency Stop` = 0
        WHERE bot_id = BotId;
        
        
        UPDATE `teleoperation_bool_data`
        SET `Alarm Reset Bit` = 0
        WHERE bot_id = BotId;
        
        DO SLEEP(1);  
        
        UPDATE `teleoperation_bool_data`
        SET `Alarm Reset Bit` = 1
        WHERE bot_id = BotId;
        
        IF ROW_COUNT() = 0 THEN
            SET Success = 0;
            SET Result = CONCAT('Failed to reset Emergency Stop for Bot ID: ', BotId);
        END IF;
    END IF;
    
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_GEARBOX_HEALTH_START` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_GEARBOX_HEALTH_START` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_GEARBOX_HEALTH_START`(
  IN Parameters JSON   
)
BEGIN
  
  DECLARE wave_running_count   INT     DEFAULT 0;

  
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SELECT 0 AS `Success`, 'SQL exception occurred' AS `Result`;
  END;

  
  SELECT COUNT(*)
    INTO wave_running_count
  FROM `hw_station_master`
  WHERE `WAVE_ID` IS NOT NULL;

  IF (wave_running_count > 0) THEN
    SELECT 0 AS `Success`,
           CONCAT('Wave running on ', wave_running_count, ' station(s).') AS `Result`;
  ELSE

    
    DROP TEMPORARY TABLE IF EXISTS `tmp_bots`;
    CREATE TEMPORARY TABLE `tmp_bots` (
      `BOT_ID` VARCHAR(50) PRIMARY KEY
    ) ENGINE=MEMORY;

    INSERT IGNORE INTO `tmp_bots` (`BOT_ID`)
    SELECT jt.`bot_id`
    FROM JSON_TABLE(
           Parameters, '$.bot_ids[*]'
           COLUMNS (`bot_id` VARCHAR(50) PATH '$')
         ) AS jt;

    
    IF (SELECT COUNT(*) FROM `tmp_bots`) = 0 THEN
      SELECT 0 AS `Success`, 'No bot_ids provided.' AS `Result`;
    ELSE

      
      DROP TEMPORARY TABLE IF EXISTS `tmp_check`;
      CREATE TEMPORARY TABLE `tmp_check` AS
      SELECT
        b.`BOT_ID`,
        (bm.`BOT_ID` IS NOT NULL)                                   AS `IS_FOUND`,
        (bm.`BOT_ID` IS NOT NULL AND UPPER(bm.`STATUS`) = 'ENABLED') AS `IS_ENABLED`,
        EXISTS (
          SELECT 1
          FROM `subcontroller_reservations_master` srm
          WHERE srm.`BOT_ID` = b.`BOT_ID`
            AND srm.`TYPE`   = 'HOME'
        )                                                           AS `IS_AT_HOME`,
        EXISTS (
          SELECT 1
          FROM `task_master` t
          WHERE t.`BOT_ID` = b.`BOT_ID`
            AND t.`STATUS` IN ('PENDING', 'PROCESSING')
        )                                                           AS `HAS_RUNNING_TASK`
      FROM `tmp_bots` b
      LEFT JOIN `bot_master` bm
             ON bm.`BOT_ID` = b.`BOT_ID`;

      
      DROP TEMPORARY TABLE IF EXISTS `tmp_fail`;
      CREATE TEMPORARY TABLE `tmp_fail` AS
      SELECT
        c.`BOT_ID`,
        TRIM(BOTH ',' FROM CONCAT(
          CASE WHEN c.`IS_FOUND`         = 0 THEN 'Not found, '       ELSE '' END,
          CASE WHEN c.`IS_ENABLED`       = 0 THEN 'Not enabled, '     ELSE '' END,
          CASE WHEN c.`IS_AT_HOME`       = 0 THEN 'Not on HOME, '     ELSE '' END,
          CASE WHEN c.`HAS_RUNNING_TASK` = 1 THEN 'Has Running Tasks' ELSE '' END
        )) AS `FAIL_REASON`
      FROM `tmp_check` c
      WHERE c.`IS_FOUND` = 0
         OR c.`IS_ENABLED` = 0
         OR c.`IS_AT_HOME` = 0
         OR c.`HAS_RUNNING_TASK` = 1;

      
      IF (SELECT COUNT(*) FROM `tmp_fail`) > 0 THEN
        SELECT
          0            AS `Success`,
          'Validation failed for one or more bots.'    AS `Result`,
          409          AS `StatusCode`,
          COALESCE(
            JSON_ARRAYAGG(
              JSON_OBJECT('BOT_ID', `BOT_ID`, 'FAIL_REASON', `FAIL_REASON`)
            ),
            JSON_ARRAY()
          )            AS `DataSet`
        FROM `tmp_fail`;
      ELSE
        
        START TRANSACTION;

          UPDATE `teleoperation_bool_data`
          SET `Gearbox_Health_Check_Start` = TRUE
          WHERE `BOT_ID` IN (SELECT `BOT_ID` FROM `tmp_check`);

        COMMIT;

        SELECT 1 AS `Success`, 'Gearbox health check initiated successfully.' AS `Result`;
      END IF;

    END IF;  

  END IF;    

  
  DROP TEMPORARY TABLE IF EXISTS `tmp_fail`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_check`;
  DROP TEMPORARY TABLE IF EXISTS `tmp_bots`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_GLOBAL_STOP_SET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_GLOBAL_STOP_SET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_GLOBAL_STOP_SET`(IN GlobalPauseBit INT)
BEGIN
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255);
    
    UPDATE `master_config` 
    SET `KEY_VALUE` = GlobalPauseBit
    WHERE `KEY_NAME` = 'DSB_GLOBAL_PAUSE';
    
    UPDATE teleoperation_bool_data
    SET `Global Pause Bit` = GlobalPauseBit;
    
    IF ROW_COUNT() > 0 THEN
        SET Success = 1;
        SET Result = CONCAT('Global pause bit set successfully to ', GlobalPauseBit);
    ELSE
        SET Success = 0;
        SET Result = 'Failed to set the global pause bit';
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_HOME_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_HOME_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_HOME_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE estop_feedback VARCHAR(10);
    DECLARE no_alarm_feedback VARCHAR(10);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    
    
    SELECT `Emergency Stop Feedback` 
    INTO estop_feedback 
    FROM `teleoperation_bool_data_feedback` 
    WHERE bot_id = BotId;
    IF estop_feedback = 0 THEN
        
        SELECT `No Alarm Feedback` 
        INTO no_alarm_feedback 
        FROM `teleoperation_bool_data_feedback` 
        WHERE bot_id = BotId;
        IF no_alarm_feedback = 0 THEN
            
            UPDATE `teleoperation_bool_data` 
            SET `Auto Home Call Bit` = '0' 
            WHERE bot_id = BotId;
            
            DO SLEEP(1);
            
            UPDATE `teleoperation_bool_data` 
            SET `Auto Home Call Bit` = '1' 
            WHERE bot_id = BotId;
            
            SET Success = 1;
            SET Result = 'Auto Home Call Bit set to 1 successfully';
        ELSE
            
            SET Success = 0;
            SET Result = 'Operation failed: No Alarm Feedback is True';
        END IF;
    ELSE
        
        SET Success = 0;
        SET Result = 'Operation failed: Emergency Stop Feedback is True';
    END IF;
    
    SELECT Success, Result;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_HOME_CALL_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_HOME_CALL_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_HOME_CALL_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE estop_feedback VARCHAR(10);
    DECLARE no_alarm_feedback VARCHAR(10);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    
    SELECT `Emergency Stop Feedback` 
    INTO estop_feedback 
    FROM `teleoperation_bool_data_feedback` 
    WHERE bot_id = BotId;
 
    IF estop_feedback = 0 THEN
        
        SELECT `No Alarm Feedback` 
        INTO no_alarm_feedback 
        FROM `teleoperation_bool_data_feedback` 
        WHERE bot_id = BotId;
 
        IF no_alarm_feedback = 0 THEN
            
            UPDATE `teleoperation_bool_data` 
            SET `Home Call in Manual` = '0' 
            WHERE bot_id = BotId;
 
            
            DO SLEEP(1);
 
            
            UPDATE `teleoperation_bool_data` 
            SET `Home Call in Manual` = '1' 
            WHERE bot_id = BotId;
 
            
            SET Success = 1;
            SET Result = 'Home Call in Manual set to 1 successfully';
        ELSE
            
            SET Success = 0;
            SET Result = 'Operation failed: No Alarm Feedback is True';
        END IF;
    ELSE
        
        SET Success = 0;
        SET Result = 'Operation failed: Emergency Stop Feedback is True';
    END IF;
 
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_HOME_CALL_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_HOME_CALL_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_HOME_CALL_FEEDBACK_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE home_ok_feedback VARCHAR(10);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    DECLARE noAlarmFeedback VARCHAR(10);
 
    
    SELECT `Home OK`
    INTO home_ok_feedback
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = BotId;
    
    SELECT `No Alarm Feedback` INTO noAlarmFeedback
    FROM teleoperation_bool_data_feedback 
    WHERE bot_id = BotId;
    
    
    IF noAlarmFeedback = '1' THEN
        SET home_ok_feedback = '0';  
       UPDATE `teleoperation_bool_data` 
            SET `Home Call in Manual` = '0' 
            WHERE bot_id = BotId;
    END IF;
    
    IF home_ok_feedback = '0' THEN
        
        SET Success = 0;
        SET Result = 'Operation failed: Home OK Feedback is False';
    ELSE
        
        SET Success = 1;
        UPDATE `teleoperation_bool_data` set `Home Call in Manual` = 0;
        SET Result = 'Home OK Feedback is True';
    END IF;
 
    
    SELECT Success, Result;
 
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_HOME_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_HOME_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_HOME_FEEDBACK_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE home_ongoing VARCHAR(10);
    DECLARE home_done_feedback VARCHAR(10);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    DECLARE FEEDBACK INT DEFAULT 1;
    
    SELECT `Auto Home Being Feedback` INTO home_ongoing 
    FROM `teleoperation_bool_data_feedback` 
    WHERE bot_id = BotId;
    
    SELECT `Home OK Feedback` INTO home_done_feedback 
    FROM `teleoperation_bool_data_feedback` 
    WHERE bot_id = BotId;
    
    IF home_done_feedback = 1 THEN
        
        DO SLEEP(1);
        
        
        UPDATE `teleoperation_bool_data` 
        SET `Auto Home Call Bit` = '0',
            `Rev Direction for Home` = '0'
        WHERE bot_id = BotId;
        
        
        SET Success = 1;
        SET Result = 'Auto Home Call Bit and Rev Direction for Home updated to 0';
        SET FEEDBACK = 1;
        
    
    ELSEIF home_ongoing = 1 THEN
        
        DO SLEEP(1);
        
        
        UPDATE `teleoperation_bool_data` 
        SET `Auto Home Call Bit` = '0'
        WHERE bot_id = BotId;
        
        
        SET Success = 0;
        SET Result = 'Auto Home Call Bit is set to 0';
        SET FEEDBACK = 0;
    ELSE
        
        UPDATE `teleoperation_bool_data` 
        SET `Auto Start Bit` = '0'
        WHERE bot_id = BotId;
        
        SET Success = 0;
        SET Result = 'Auto Start Bit updated to 0';
        SET FEEDBACK = 0;
    END IF;
    
    SELECT Success, Result, FEEDBACK;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_HOME_REVERSE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_HOME_REVERSE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_HOME_REVERSE_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE estop_feedback VARCHAR(10);
    DECLARE no_alarm_feedback VARCHAR(10);
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255);
    
    SELECT `Emergency Stop Feedback` INTO estop_feedback 
    FROM `teleoperation_bool_data_feedback` 
    WHERE bot_id = BotId;
    IF estop_feedback = 0 THEN
        
        SELECT `No Alarm Feedback` INTO no_alarm_feedback 
        FROM `teleoperation_bool_data_feedback` 
        WHERE bot_id = BotId;
        IF no_alarm_feedback = 0 THEN
            
            UPDATE `teleoperation_bool_data` 
            SET `Rev Direction for Home` = 0 
            WHERE bot_id = BotId;
            
            DO SLEEP(1);
            
            UPDATE `teleoperation_bool_data` 
            SET `Rev Direction for Home` = 1 
            WHERE bot_id = BotId;
            
             DO SLEEP(1);
            
            UPDATE `teleoperation_bool_data` 
            SET `Auto Home Call Bit` = 0
            WHERE bot_id = BotId;
            
            DO SLEEP(1);
            
            UPDATE `teleoperation_bool_data` 
            SET `Auto Home Call Bit` = 1 
            WHERE bot_id = BotId;
            
            SET Success = 1;
            SET Result = CONCAT('Home Reverse operation successful for Bot ID ', BotId);
        ELSE
            
            SET Success = 0;
            SET Result = CONCAT('No Alarm Feedback is active for Bot ID ', BotId);
        END IF;
    ELSE
        
        SET Success = 0;
        SET Result = CONCAT('Emergency Stop Feedback is active for Bot ID ', BotId);
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_LOGIN_APPROVE_REJECT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_LOGIN_APPROVE_REJECT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_LOGIN_APPROVE_REJECT`(
    IN Parameters VARCHAR(255)
)
BEGIN
    
    DECLARE UserName VARCHAR(255);
    DECLARE BotId VARCHAR(50);
    DECLARE Operation INT;
    
    
    SET UserName = Parameters ->> '$.Username';
    SET BotId = Parameters ->> '$.BotId';
    SET Operation = IF(Parameters ->> '$.ApproveLogin' = 'true', 1, 0);
    
    
    IF (SELECT REQUEST_BY FROM `dashboard_bot_master` WHERE BOT_ID = BotId) IS NULL THEN
        SELECT 0 AS Success, 'No User Is Requesting for Access' AS Result;
    ELSE
        
        IF Operation = 1 THEN
            UPDATE `dashboard_bot_master`
            SET 
                LOCK_BY = REQUEST_BY,
                REQUEST_BY = NULL
            WHERE BOT_ID = BotId;
            
            
            SELECT 
                1 AS Success, 
                CONCAT(BotId, ' successfully taken by ', LOCK_BY) AS Result 
            FROM `dashboard_bot_master` 
            WHERE BOT_ID = BotId;
        ELSE
            
            UPDATE `dashboard_bot_master`
            SET REQUEST_BY = NULL
            WHERE BOT_ID = BotId;
            
            SELECT 1 AS Success, 'Request Denied Successfully' AS Result;
        END IF;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_LOGIN_DETAILS_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_LOGIN_DETAILS_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_LOGIN_DETAILS_BY_BOT_ID`(
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    
    SELECT 
        LOCK_BY, 
        REQUEST_BY  
    FROM 
        dashboard_bot_master
    WHERE 
        BOT_ID = BotId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_MANUAL_PACKET_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_MANUAL_PACKET_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_MANUAL_PACKET_FEEDBACK_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    DECLARE FEEDBACK INT DEFAULT 1;
    
    
    SELECT `Manual Position Mode`
    INTO FEEDBACK
    FROM `teleoperation_bool_data`
    WHERE bot_id = BotId;
    
    IF FEEDBACK = 1 THEN
        
        SET Result = 'Return to HMI Mode';
    ELSE
        
        SET Result = 'Return to Auto Mode';
    END IF;
    
    
    SELECT Success, Result, FEEDBACK;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_MASTER_DELETE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_MASTER_DELETE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_MASTER_DELETE`(IN Parameters JSON)
BEGIN
    DECLARE p_bot_id        VARCHAR(50);

   
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CALL DSB_GENERIC_TRANSACTION_ERROR_HANDLER();
    END;

    
    SET p_bot_id = UPPER(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bot_id')));

    
    IF p_bot_id IS NULL OR p_bot_id = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BOT ID is required for delete';
    END IF;

    START TRANSACTION;

        
        DELETE FROM `teleoperation_bool_data_feedback`
        WHERE `bot_id` = p_bot_id;

        DELETE FROM `teleoperation_bool_data`
        WHERE `bot_id` = p_bot_id;

        DELETE FROM `teleoperation_numeric_data_feedback`
        WHERE `bot_id` = p_bot_id;

        DELETE FROM `teleoperation_numeric_data`
        WHERE `bot_id` = p_bot_id;

        
        DELETE FROM `bot_master`
        WHERE `BOT_ID` = p_bot_id;

    COMMIT;

    SELECT 1 AS Success, CONCAT(p_bot_id, ' Deleted Successfully') AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_MASTER_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_MASTER_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_MASTER_GET_ALL`()
BEGIN
    SELECT 
        STATUS,
        BOT_MASTER_ID,
        BOT_ID,
        AUTO_MANUAL,
        IP,
        PORT,
        GRIDX,
        GRIDY,
        GRIDZ,
        LOAD_CONDITION
    FROM 
        bot_master;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_MASTER_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_MASTER_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_MASTER_INSERT`(IN Parameters JSON)
BEGIN
    
    DECLARE p_bot_master_id   INT;
    DECLARE p_bot_id          VARCHAR(50);
    DECLARE p_bot_status      VARCHAR(50);
    DECLARE p_auto_manual     VARCHAR(50);
    DECLARE p_bot_ip          VARCHAR(50);
    DECLARE p_bot_port        INT;
    DECLARE p_grid_x          INT;
    DECLARE p_grid_y          INT;
    DECLARE p_grid_z          INT;
    DECLARE p_load_condition  VARCHAR(50);
    DECLARE p_user_name       VARCHAR(50);

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CALL DSB_GENERIC_TRANSACTION_ERROR_HANDLER();
    END;

    
    SET p_bot_master_id  = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bot_master_id')) AS UNSIGNED);
    SET p_bot_id         = UPPER(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bot_id')));
    SET p_bot_status     = UPPER(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bot_status')));
    SET p_auto_manual    = LOWER(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.auto_manual')));
    SET p_bot_ip         = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bot_ip'));
    SET p_bot_port       = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.port')) AS UNSIGNED);
    SET p_grid_x         = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.grid_x')) AS UNSIGNED);
    SET p_grid_y         = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.grid_y')) AS UNSIGNED);
    SET p_grid_z         = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.grid_z')) AS UNSIGNED);
    SET p_load_condition = UPPER(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.load_condition')));
    SET p_user_name         = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));

    
    IF p_bot_master_id IS NULL OR p_bot_master_id < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BOT MASTER ID is required';
    END IF;

    
    IF p_bot_id IS NULL OR p_bot_id = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BOT ID is required';
    END IF;

    
    IF p_bot_status IS NULL OR p_bot_status = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BOT STATUS is required';
    END IF;

    
    IF p_auto_manual IS NULL OR p_auto_manual = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'AUTO MANUAL is required';
    END IF;

    
    IF p_bot_ip IS NULL OR p_bot_ip = '' OR INET_ATON(p_bot_ip) IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid BOT IP address';
    END IF;

    
    IF p_bot_port IS NULL OR p_bot_port <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'PORT must be a positive integer';
    END IF;

    
    IF p_grid_x IS NULL OR p_grid_x < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'GRID X must be a positive integer';
    END IF;

    IF p_grid_y IS NULL OR p_grid_y < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'GRID Y must be a positive integer';
    END IF;

    IF p_grid_z IS NULL OR p_grid_z < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'GRID Z must be a positive integer';
    END IF;

    
    IF p_load_condition IS NULL OR p_load_condition = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'LOAD CONDITION is required';
    END IF;

    
    IF p_bot_master_id = 0 THEN

        
        IF EXISTS (SELECT 1 FROM `bot_master` WHERE `BOT_ID` = p_bot_id) THEN

            
            SELECT 0 AS Success, CONCAT(p_bot_id, ' already exists') AS Result;

        ELSE
            START TRANSACTION;

            INSERT INTO `bot_master` (
                `BOT_ID`,
                `STATUS`,
                `AUTO_MANUAL`,
                `IP`,
                `PORT`,
                `GRIDX`,
                `GRIDY`,
                `GRIDZ`,
                `LOAD_CONDITION`
            )
            VALUES (
                p_bot_id,
                p_bot_status,
                p_auto_manual,
                p_bot_ip,
                p_bot_port,
                p_grid_x,
                p_grid_y,
                p_grid_z,
                p_load_condition
            );

            INSERT INTO `teleoperation_bool_data`             (`bot_id`) VALUES (p_bot_id);
            INSERT INTO `teleoperation_bool_data_feedback`    (`bot_id`) VALUES (p_bot_id);
            INSERT INTO `teleoperation_numeric_data`          (`bot_id`) VALUES (p_bot_id);
            INSERT INTO `teleoperation_numeric_data_feedback` (`bot_id`) VALUES (p_bot_id);

            SELECT 1 AS Success, CONCAT(p_bot_id, ' Added Successfully') AS Result;

            COMMIT;
        END IF;

    ELSE
        
        START TRANSACTION;

        UPDATE `bot_master`
        SET
            `STATUS`         = p_bot_status,
            `AUTO_MANUAL`    = p_auto_manual,
            `IP`             = p_bot_ip,
            `PORT`           = p_bot_port,
            `GRIDX`          = p_grid_x,
            `GRIDY`          = p_grid_y,
            `GRIDZ`          = p_grid_z,
            `LOAD_CONDITION` = p_load_condition
        WHERE
            `BOT_ID`        = p_bot_id
            AND `BOT_MASTER_ID` = p_bot_master_id;

        SELECT 1 AS Success, CONCAT(p_bot_id, ' Updated Successfully') AS Result;

        COMMIT;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_MASTER_UPDATE_BOT_TO_MAINTENANCE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_MASTER_UPDATE_BOT_TO_MAINTENANCE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_MASTER_UPDATE_BOT_TO_MAINTENANCE`(
    IN p_bot_id       VARCHAR(10),
    IN p_column_value INT
)
BEGIN
  DECLARE Success         INT          DEFAULT 1;
  DECLARE Result          TEXT DEFAULT '';
  DECLARE v_error_message TEXT;

  
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    ROLLBACK;
    SELECT 0 AS Success, v_error_message AS Result;
  END;

  START TRANSACTION;

  
  IF p_column_value NOT IN (0, 1) THEN
    SET Success = 0;
    SET Result  = 'Invalid ColumnValue. Must be 0 or 1.';
    ROLLBACK;
    SELECT Success, Result;
  END IF;

  
  UPDATE bot_master
  SET BOT_TO_MAINTENANCE_BIT = CAST(p_column_value AS UNSIGNED)
  WHERE BOT_ID = p_bot_id;

  COMMIT;

  SET Result = CONCAT('BOT_TO_MAINTENANCE updated to ', p_column_value, ' for BotId: ', p_bot_id);
  SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_MODE_GET_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_MODE_GET_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_MODE_GET_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
	SELECT AUTO_MANUAL AS BOT_MODE FROM bot_master WHERE bot_id = BotId;	
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_MODE_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_MODE_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_MODE_UPDATE_BY_BOT_ID`(
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,       
    IN ColumnValue VARCHAR(255)  
)
BEGIN
    
    DECLARE Result VARCHAR(200);
    DECLARE Success INT;
    
    IF ColumnValue IN ('auto', 'manual') THEN
        
        UPDATE `bot_master`
        SET `AUTO_MANUAL` = ColumnValue
        WHERE BOT_ID = BotId;
        
        SET Success = 1;
        SET Result = CONCAT('Bot Mode Changed to ', ColumnValue);
    ELSE
        
        SET Success = 0;
        SET Result = 'Invalid Bot Mode. Must be AUTO or MANUAL.';
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_NON_RECOVERY_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_NON_RECOVERY_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_NON_RECOVERY_UPDATE_BY_BOT_ID`(
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    
    UPDATE `bot_master`
    SET non_recovery_bit = 1
    WHERE bot_id = BotId;
    
    IF ROW_COUNT() = 0 THEN
        SET Success = 0; 
        SET Result = 'No bot found with the given BotId'; 
    ELSE
        SET Result = 'Non-Recovery bit updated successfully'; 
    END IF;
    
    SELECT Success AS Success, Result AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_POWER_SAVING_MODE_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_POWER_SAVING_MODE_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_POWER_SAVING_MODE_FEEDBACK_BY_BOT_ID`(
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    DECLARE Feedback INT DEFAULT 1;
    
    IF EXISTS (
        SELECT 1 FROM teleoperation_bool_data WHERE bot_id = BotId
    ) THEN
        
        SELECT `All servos disable` INTO Feedback 
        FROM teleoperation_bool_data 
        WHERE bot_id = BotId;
        SET Success = 1;
        SET Result = CONCAT(BotId, ' Power Saving Mode is ', IF(Feedback = 0, 'OFF', 'ON'));
    ELSE
        SET Success = 0;
        SET Result = CONCAT('No record found for given bot ID: ', BotId);
    END IF;
    
    SELECT Success, Result, Feedback;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_POWER_SAVING_MODE_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_POWER_SAVING_MODE_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_POWER_SAVING_MODE_UPDATE_BY_BOT_ID`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_bot_id VARCHAR(20);
    DECLARE p_identifier_bit INT;
    
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255);
    
    SET p_bot_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.botId'));
    SET p_identifier_bit = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.identifierBit')) AS UNSIGNED);
    
    IF EXISTS (
        SELECT 1 FROM teleoperation_bool_data WHERE bot_id = p_bot_id
    ) THEN
        UPDATE teleoperation_bool_data
        SET `All servos disable`= p_identifier_bit
        WHERE bot_id = p_bot_id;
        SET Success = 1;
        SET Result = CONCAT(p_bot_id, ' Power Saving Mode turned ', IF(p_identifier_bit = 0, 'OFF', 'ON'));
    ELSE
        SET Success = 0;
        SET Result = CONCAT('No record found for given bot ID: ', p_bot_id);
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_RECOVERY_NON_RECOVERY_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_RECOVERY_NON_RECOVERY_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_RECOVERY_NON_RECOVERY_FEEDBACK_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    
    WITH LatestAlarm AS (
        SELECT 
            BOT_ID, 
            ALARM_CODE, 
            INSERTED_TIMESTAMP, 
            'MAINTENANCE' AS SOURCE
        FROM maintenance_alarm_logs 
        WHERE BOT_ID = BotId
        UNION ALL
        SELECT 
            BOT_ID, 
            ALARM_CODE, 
            INSERTED_TIMESTAMP, 
            'BOT' AS SOURCE
        FROM bot_alarm_log 
        WHERE BOT_ID = BotId 
          AND RECOVERY_TIMESTAMP IS NULL
    ),
    RankedAlarms AS (
        SELECT 
            *, 
            ROW_NUMBER() OVER (ORDER BY INSERTED_TIMESTAMP DESC) AS RN
        FROM LatestAlarm
    ),
    FinalAlarm AS (
        SELECT 
            CASE 
                WHEN L.ALARM_CODE = 12 THEN 
                    (CASE 
                        WHEN NOT EXISTS (
                            SELECT 1 
                            FROM bot_alarm_log 
                            WHERE BOT_ID = BotId 
                              AND INSERTED_TIMESTAMP < L.INSERTED_TIMESTAMP 
                              AND RECOVERY_TIMESTAMP IS NULL
                        ) THEN 12
                        ELSE (
                            SELECT ALARM_CODE 
                            FROM bot_alarm_log 
                            WHERE BOT_ID = BotId 
                              AND INSERTED_TIMESTAMP < L.INSERTED_TIMESTAMP 
                              AND RECOVERY_TIMESTAMP IS NULL
                            ORDER BY INSERTED_TIMESTAMP DESC
                            LIMIT 1
                        )
                    END)
                ELSE L.ALARM_CODE
            END AS FINAL_ALARM_CODE,
            L.SOURCE
        FROM RankedAlarms L
        WHERE L.RN = 1
    )
    
    SELECT 
        CASE
            WHEN bm.GRIDZ > 0 THEN 0
            
            WHEN lm.TYPE = 'STATION' AND tm.TASK_TYPE = 'BIN_ZONE_TO_STORE' AND bm.LOAD_CONDITION = 'LD' THEN 1
            
            ELSE IFNULL(am.RECOVERY, 0)
        END AS RECOVERY,
        
        0 AS LOAD_AND_RECOVERY,
        CASE 
            WHEN bm.GRIDZ > 0 OR lm.TYPE = 'STATION' THEN 0
            WHEN lm.TYPE = 'STATION_ENTRY' AND (tm.TASK_TYPE = 'BIN_STORE_TO_ZONE' OR tm.TASK_TYPE = 'STATION_TO_STATION') AND  bm.LOAD_CONDITION = 'LD' THEN 1
            WHEN lm.TYPE = 'STATION_ENTRY' THEN 0
            
            ELSE IFNULL(am.NON_RECOVERY, 0)
        END AS NON_RECOVERY,
        CASE 
            WHEN lm.TYPE = 'STATION' AND tm.TASK_TYPE = 'BIN_FROM_ZONE' AND bm.LOAD_CONDITION = 'UL' AND am.NON_RECOVERY = 1 THEN 1 
            ELSE 0 
        END AS LOAD_AND_NON_RECOVERY,
        tm.TASK_TYPE,
        bm.LOAD_CONDITION,
        fa.FINAL_ALARM_CODE,
        fa.SOURCE
    FROM bot_master bm
    JOIN FinalAlarm fa ON 1=1
    LEFT JOIN alarm_master am ON am.ALARM_CODE = fa.FINAL_ALARM_CODE 
        AND am.ALARM_TYPE = (CASE 
                                WHEN fa.SOURCE = 'MAINTENANCE' THEN 'MAINTENANCE' 
                                ELSE 'NORMAL' 
                             END)
    LEFT JOIN location_master lm ON lm.X = bm.GRIDX 
        AND lm.Y = bm.GRIDY 
        AND lm.Z = bm.GRIDZ
    LEFT JOIN task_master tm ON tm.BOT_ID = bm.BOT_ID 
        AND tm.STATUS = 'PROCESSING'
    WHERE bm.BOT_ID = BotId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_RECOVERY_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_RECOVERY_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_RECOVERY_UPDATE_BY_BOT_ID`(
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    
    UPDATE `bot_master`
    SET recovery_bit = 1
    WHERE bot_id = BotId;
    
    IF ROW_COUNT() = 0 THEN
        SET Success = 0; 
        SET Result = 'No bot found with the given BotId'; 
    ELSE
        SET Result = 'Recovery bit updated successfully'; 
    END IF;
    
    SELECT Success AS Success, Result AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_RESET_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_RESET_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_RESET_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE no_alarm_feedback VARCHAR(255);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    
    SELECT `No Alarm Feedback` 
    INTO no_alarm_feedback 
    FROM `teleoperation_bool_data_feedback` 
    WHERE bot_id = BotId;
    
    IF no_alarm_feedback = 1 THEN
        
        UPDATE `teleoperation_bool_data`
        SET `Alarm Reset Bit` = '0'
        WHERE bot_id = BotId;
        
        DO SLEEP(1);  
        
        UPDATE `teleoperation_bool_data`
        SET `Alarm Reset Bit` = '1'
        WHERE bot_id = BotId;
        
        SET Success = 1;
        SET Result = 'Reset Successful';
        UPDATE bot_alarm_log SET RECOVERY_TIMESTAMP = NOW() 
        WHERE BOT_ID = BotId AND RECOVERY_TIMESTAMP IS NULL;
    ELSE
        SET Success = 0;
        SET Result = 'Reset Not Successful';
    END IF;
    
    SELECT Success, Result;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_RESET_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_RESET_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_RESET_FEEDBACK_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE no_alarm_feedback VARCHAR(255);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    DECLARE FEEDBACK INT DEFAULT 1;
    
    
    SELECT `No Alarm Feedback` 
    INTO no_alarm_feedback 
    FROM `teleoperation_bool_data_feedback` 
    WHERE bot_id = BotId;
    
    IF no_alarm_feedback = 0 THEN
        UPDATE `teleoperation_bool_data`
        SET `Alarm Reset Bit` = '0'
        WHERE bot_id = BotId;
        
        
        SET Success = 1;
        SET Result = 'Reset Feedback Successful';
        SET FEEDBACK = 1;
    
    ELSE
        UPDATE `teleoperation_bool_data`
        SET `Auto Home Call Bit` = '0'
        WHERE bot_id = BotId;
        UPDATE `teleoperation_bool_data`
        SET `Auto Start Bit` = '0'
        WHERE bot_id = BotId;
        UPDATE `teleoperation_bool_data`
        SET `Auto Calibration Start` = '0'
        WHERE bot_id = BotId;
        
        
        SET Success = 0;
        SET Result = 'Reset Feedback Not Successful';
        SET FEEDBACK = 0;
    END IF;
    
    SELECT Success, Result, FEEDBACK;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_RESET_MISSION_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_RESET_MISSION_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_BOT_RESET_MISSION_BY_BOT_ID`(
    IN BotId VARCHAR(10)
)
BEGIN
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255) DEFAULT '';
    DECLARE v_current_non_recovery INT DEFAULT NULL;

    
    SELECT NON_RECOVERY_BIT
    INTO v_current_non_recovery
    FROM bot_master
    WHERE BOT_ID = BotId
    LIMIT 1;

    
    IF v_current_non_recovery IS NULL THEN
        SET Success = 0;
        SET Result = 'No bot found for the given BOT_ID.';

    
    ELSEIF v_current_non_recovery = 1 THEN
        SET Success = 0;
        SET Result = 'NON_RECOVERY_BIT is already set (already high) for this bot.';

    
    ELSE
        UPDATE bot_master
        SET NON_RECOVERY_BIT = 1
        WHERE BOT_ID = BotId;

        SET Success = 1;
        SET Result = 'NON_RECOVERY_BIT set successfully.';
    END IF;

    SELECT Success AS Success, Result AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_RESET_MISSION_BY_BOT_ID_20260131` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_RESET_MISSION_BY_BOT_ID_20260131` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_BOT_RESET_MISSION_BY_BOT_ID_20260131`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE Result VARCHAR(255);
    DECLARE Success INT DEFAULT 0;
    DECLARE TaskType VARCHAR(255);
    DECLARE noAlarmFeedback INT DEFAULT 0;
    
    SELECT `No Alarm Feedback` 
    INTO noAlarmFeedback 
    FROM teleoperation_bool_data_feedback 
    WHERE BOT_ID = BotId;
    IF noAlarmFeedback = 0 THEN 
        
        SELECT TASK_TYPE 
        INTO TaskType
        FROM task_master 
        WHERE BOT_ID = BotId and status in ('PROCESSING','PENDING') order by `INSERTED_TIMESTAMP` DESC
        LIMIT 1; 
        
        IF TaskType = 'MANUAL' THEN
            
        DELETE FROM task_master WHERE BOT_ID = BotId AND TASK_TYPE = 'MANUAL';
	DELETE td
	FROM task_detail td
	INNER JOIN task_master tm
	    ON td.task_master_id = tm.task_id
	WHERE td.BOT_ID = BotId
	  AND tm.TASK_TYPE = 'MANUAL';
         DELETE s
	FROM steps s
	INNER JOIN task_detail td
	    ON s.task_detail_id = td.task_detail_id
	INNER JOIN task_master tm
	    ON td.task_master_id = tm.task_id
	WHERE td.BOT_ID = BotId
	  AND tm.TASK_TYPE = 'MANUAL';
		    
            SET Success = 1;
            SET Result = CONCAT('Mission reset successfully for Bot ID ', BotId, ' performing manual tasks.');
        ELSE
            
            SET Success = 0;
            SET Result = CONCAT('No manual tasks found to reset for Bot ID ', BotId, '. Non-manual tasks are retained.');
        END IF;
    ELSE
        
        SET Success = 0;
        SET Result = CONCAT('Unable to reset mission for Bot ID ', BotId, '. Active alarms present.');
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_STATUS_UPDATE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_STATUS_UPDATE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_STATUS_UPDATE_BY_BOT_ID`( 
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,        
    IN ColumnValue VARCHAR(255)   
)
BEGIN
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    DECLARE v_load_condition VARCHAR(10);
    
    SET ColumnValue = UPPER(ColumnValue);
    
    IF ColumnValue NOT IN ('ENABLED', 'DISABLED') THEN
        SET Success = 0;
        SET Result = 'Invalid Bot Status. Must be ENABLED or DISABLED';
    
    ELSE
        
        START TRANSACTION;
        
        IF ColumnValue = 'DISABLED' THEN
            SELECT LOAD_CONDITION INTO v_load_condition
            FROM bot_master
            WHERE BOT_ID = BotId;
            IF v_load_condition = 'LD' THEN
                
                SET Success = 0;
                SET Result = 'BOT is in Loaded State. Cannot be disabled.';
                ROLLBACK;
            ELSE
                
                UPDATE bot_master
		SET
		    AUTO_MANUAL = 'manual',
		    NON_RECOVERY_BIT = 1,
		    STATUS = ColumnValue
		WHERE BOT_ID = BotId;
                SET Result = CONCAT('Bot Status Changed to ', ColumnValue);
                COMMIT;
            END IF;
        ELSE
            
            UPDATE bot_master
            SET STATUS = ColumnValue
            WHERE BOT_ID = BotId;
            SET Result = CONCAT('Bot Status Changed to ', ColumnValue);
            COMMIT;
        END IF;
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_UPDATE_MOVE_OUT_OF_FLEET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_UPDATE_MOVE_OUT_OF_FLEET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_UPDATE_MOVE_OUT_OF_FLEET`(
    IN p_bot_id VARCHAR(10)
)
BEGIN
    DECLARE Success   INT  DEFAULT 1;
    DECLARE Result    TEXT DEFAULT '';
    DECLARE v_grid_x  INT;
    DECLARE v_grid_y  INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CALL DSB_GENERIC_TRANSACTION_ERROR_HANDLER();
    END;

    START TRANSACTION;

    
    SELECT 
        X - 1,
        Y
    INTO 
        v_grid_x,
        v_grid_y
    FROM location_master
    WHERE TYPE = 'MAINTENANCE'
    ORDER BY X ASC
    LIMIT 1;

    
    IF v_grid_x IS NULL OR v_grid_y IS NULL THEN
        SET Success = 0;
        SET Result  = 'Maintenance location not configured in location_master';
        ROLLBACK;
        SELECT Success, Result;
    END IF;

    
    UPDATE bot_master
    SET 
        Non_Recovery_Bit = 1,
        GRIDX            = v_grid_x,
        GRIDY            = v_grid_y
    WHERE BOT_ID = p_bot_id;

    COMMIT;

    SET Result = CONCAT(
        'Bot moved out of fleet and parked at (',
        v_grid_x, ',', v_grid_y,
        ') for BOT_ID: ', p_bot_id
    );

    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_UPDATE_SLIDER_RECOVERY_FAIL_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_UPDATE_SLIDER_RECOVERY_FAIL_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_UPDATE_SLIDER_RECOVERY_FAIL_BY_BOT_ID`(IN Parameters JSON)
BEGIN
    DECLARE BotId VARCHAR(255);
    DECLARE ConfirmationBit VARCHAR(10);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
     
     SET BotId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.botId'));
     SET ConfirmationBit = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.confirmationBit'));
    
    IF LOWER(ConfirmationBit) = 'yes' THEN
        
        UPDATE `bot_master`
        SET `slider_recovery_fail_true` = 1
        WHERE `bot_id` = BotId;
        SET Success = 1;
        SET Result = 'Successfully updated fail true, send to maintenance';
        
    ELSEIF LOWER(ConfirmationBit) = 'no' THEN
        
        UPDATE `bot_master`
        SET `slider_recovery_fail_false` = 1
        WHERE `bot_id` = BotId;
        SET Success = 1;
        SET Result = 'Successfully updated fail to false, generate alarm';
    ELSE
        
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid ConfirmationBit value. Please use "yes" or "no".';
    END IF;
    
    SELECT Success, Result ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_USERID_LOCK_CHECK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_USERID_LOCK_CHECK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_USERID_LOCK_CHECK`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE BotId VARCHAR(50);
    DECLARE UserName VARCHAR(100);
    DECLARE FunctionName VARCHAR(100);
    DECLARE LockFlag TINYINT;
    DECLARE v_locked_by_user VARCHAR(100);
    
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
    DECLARE FEEDBACK INT DEFAULT 0;
    
    
    SET BotId = Parameters ->> '$.BotId';
    SET UserName = Parameters ->> '$.UserName';
    SET FunctionName = Parameters ->> '$.FunctionName';
    SET LockFlag = IF(Parameters ->> '$.Lock' = 'true', 1, 0);
    
    
    SELECT LOCK_BY INTO v_locked_by_user
    FROM `dashboard_bot_master`
    WHERE BOT_ID = BotId;
    
    IF (LockFlag = 1) THEN
        IF v_locked_by_user IS NOT NULL THEN
            
            UPDATE `dashboard_bot_master`
            SET REQUEST_BY = UserName
            WHERE BOT_ID = BotId;
            
            SET Result = CONCAT(BotId, ' is already assigned to ', v_locked_by_user);
            SET FEEDBACK = 1;
        ELSE
            
            UPDATE `dashboard_bot_master`
            SET LOCK_BY = UserName
            WHERE BOT_ID = BotId;
            
            SET Result = CONCAT(BotId, ' is locked by ', UserName);
        END IF;
    ELSE
        
        IF v_locked_by_user != UserName THEN
            SET Result = CONCAT(UserName, ' is not authorized to unlock ', BotId);
            SET Success = 0;
        ELSE
            
            UPDATE `dashboard_bot_master`
            SET 
                LOCK_BY = NULL,
                UNLOCK_BY = UserName
            WHERE BOT_ID = BotId AND LOCK_BY = UserName;
            
            SET Result = CONCAT(BotId, ' is unlocked by ', UserName);
        END IF;
    END IF;
    
    
    SELECT Success, Result, FEEDBACK;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_USERID_VALIDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_USERID_VALIDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_USERID_VALIDATE`(IN UserName VARCHAR(45), IN UserPassword VARCHAR(100))
BEGIN
    DECLARE Success VARCHAR(50) DEFAULT "0";
    DECLARE PasswordWithSalt VARCHAR(256);
    SELECT CONCAT(UserPassword, SALT) INTO PasswordWithSalt 
    FROM dashboard_user_master 
    WHERE USER_NAME = UserName;
    IF ((SELECT COUNT(*) 
         FROM dashboard_user_master 
         WHERE USER_NAME = UserName
           AND USER_PASSWORD = MD5(PasswordWithSalt)
           AND IS_ACTIVE = 1) >= 1)
    THEN
	SET Success="1";
        
    END IF;
    SELECT Success;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_Z_ACKNOWLEDGEMENT_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_Z_ACKNOWLEDGEMENT_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_Z_ACKNOWLEDGEMENT_FEEDBACK_BY_BOT_ID`(IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    DECLARE z_acknowledgement_teleoperation INT DEFAULT 0;
    DECLARE z_acknowledgement_botmaster INT DEFAULT 0;
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255);
 
    
    SELECT `Z-Jog Operation Limits Overwrite Confirm`
    INTO z_acknowledgement_teleoperation
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = BotId;
 
    
    UPDATE `teleoperation_bool_data`
    SET `Z-Jog Operation Limits Overwrite Acknowledge` = (z_acknowledgement_teleoperation = 1)
    WHERE bot_id = BotId;
 
    
    IF z_acknowledgement_teleoperation = 1 THEN
        UPDATE bot_master
        SET `DSB_TMM_Z_AXIS_ACKNOWLEDGEMENT` = 1
        WHERE bot_id = BotId;
    END IF;
 
    
    SELECT `DSB_TMM_Z_AXIS_ACKNOWLEDGEMENT`
    INTO z_acknowledgement_botmaster
    FROM bot_master
    WHERE bot_id = BotId;
 
    
    IF z_acknowledgement_botmaster = 1 THEN
        SET Result = "Acknowledgment value for bot is 1";
    ELSE
        SET Success = 0;
        SET Result = "Acknowledgment value for bot is 0";
    END IF;
 
    
    SELECT Success, Success AS FEEDBACK, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BOT_Z_ACKNOWLEDGEMENT_UPDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BOT_Z_ACKNOWLEDGEMENT_UPDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BOT_Z_ACKNOWLEDGEMENT_UPDATE`(
    IN BotId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,       
    IN ColumnValue VARCHAR(255)  
)
BEGIN
    
    DECLARE Result VARCHAR(200);
    DECLARE Success INT;
    
    UPDATE `bot_master`
    SET `DSB_TMM_Z_AXIS_ACKNOWLEDGEMENT` = ColumnValue
    WHERE BOT_ID = BotId;
    
    SET Success = 1;
    SET Result = "Value Updated Successfully";
    
    SELECT Success AS `Success`, Result AS `Message`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_BREADCRUMB_GET_BY_MENU_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_BREADCRUMB_GET_BY_MENU_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_BREADCRUMB_GET_BY_MENU_ID`(IN MenuId INT)
BEGIN    
    SELECT 
        dmm.MENU_NAME,                                
        dmm.MENU_PATH,                                
        dbm.SEQUENCE,                                 
        CASE 
            WHEN dbm.MENU_ID = dbm.CHILD_MENU_ID THEN TRUE  
            ELSE FALSE                                      
        END AS CURRENT_PAGE                            
    FROM
        `dashboard_breadcrumb_master` dbm
    LEFT JOIN 
        `dashboard_menu_master` dmm 
        ON dbm.CHILD_MENU_ID = dmm.MENU_ID             
    WHERE 
        dbm.MENU_ID = MenuId                           
    ORDER BY 
        dbm.SEQUENCE ASC;                              
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_CATEGORY_CATEGORY_MASTER_DELETE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_CATEGORY_CATEGORY_MASTER_DELETE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_CATEGORY_CATEGORY_MASTER_DELETE`(IN Parameters JSON)
BEGIN
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found'; 
    DECLARE _index INT DEFAULT 0;
    DECLARE jsonLength INT DEFAULT JSON_LENGTH(Parameters->'$.CategoryMasterId');
    DECLARE id INT DEFAULT 0;
    
    WHILE _index < jsonLength DO
        
        SET id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$.CategoryMasterId[', _index, ']')));
        
        
        DELETE FROM `category_matrix` WHERE `PARENT_CATEGORY_ID` = id OR `CHILD_CATEGORY_ID` = id;
        
        
        DELETE FROM `category_master` WHERE `CATEGORY_ID` = id;
        
        SET _index = _index + 1;
    END WHILE;
    
    
    SET Success = 1;
    SET Result = 'Deletion completed';
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_CATEGORY_CATEGORY_MASTER_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_CATEGORY_CATEGORY_MASTER_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_CATEGORY_CATEGORY_MASTER_GET`()
BEGIN
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found'; 
    
    SELECT 
        IS_ACTIVE ,
         CATEGORY_ID,
        CATEGORY_NAME,
        
        INSERTED_BY,
        INSERTED_TIMESTAMP,
         UPDATED_BY,
        UPDATED_TIMESTAMP
    FROM `category_master`;
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_CATEGORY_CATEGORY_MASTER_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_CATEGORY_CATEGORY_MASTER_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_CATEGORY_CATEGORY_MASTER_INSERT`(IN Parameters JSON)
BEGIN
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found'; 
    DECLARE masterId INT;
    DECLARE _name VARCHAR(255);
    DECLARE _aliasName VARCHAR(255);
  
    
    SET masterId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.CategoryMasterId'));
    SET _name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Name'));
    SET _aliasName = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.AliasName'));
  
    
    IF (masterId IS NULL OR masterId = 0) THEN
        
        INSERT INTO `category_master` (`CATEGORY_NAME`)
        VALUES (_name);
         SET Success = 1;
         
    SET Result = 'Insert completed';
    ELSE
        
        UPDATE `category_master` 
        SET `CATEGORY_NAME` = _name
        WHERE `CATEGORY_ID` = masterId;
        
         SET Success = 1;
    SET Result = 'Update completed';
    END IF;
    
   
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_CATEGORY_CATEGORY_MASTER_UPDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_CATEGORY_CATEGORY_MASTER_UPDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_CATEGORY_CATEGORY_MASTER_UPDATE`(IN Parameters JSON)
BEGIN
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found'; 
    DECLARE _index INT DEFAULT 0;
    DECLARE jsonLength INT DEFAULT JSON_LENGTH(Parameters->'$.CategoryMasterModel');
    
    
    WHILE _index < jsonLength DO
        
        UPDATE `category_master` 
        SET 
            `CATEGORY_NAME` = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$.CategoryMasterModel[', _index, '].Name'))),
            `CATEGORY_ALIAS_NAME` = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$.CategoryMasterModel[', _index, '].AliasName'))),
            `IS_ACTIVE` = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$.CategoryMasterModel[', _index, '].IsActive')))
        WHERE 
            `CATEGORY_ID` = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$.CategoryMasterModel[', _index, '].CategoryMasterId')));
        
        
        SET _index = _index + 1;
    END WHILE;
    
    
    SET Success = 1;
    SET Result = 'Update completed';
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_CATEGORY_CATEGORY_MATRIX_DELETE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_CATEGORY_CATEGORY_MATRIX_DELETE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_CATEGORY_CATEGORY_MATRIX_DELETE`(IN Parameters JSON)
BEGIN
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found'; 
    DECLARE _index INT DEFAULT 0;
    DECLARE jsonLength INT DEFAULT JSON_LENGTH(Parameters->'$.CategoryMatrixId');
    DECLARE id INT DEFAULT 0;
    DECLARE parentId INT DEFAULT 0;
    DECLARE childId INT DEFAULT 0;
    
    WHILE _index < jsonLength DO
        
        SET id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$.CategoryMatrixId[', _index, ']')));
        
        SELECT `PARENT_CATEGORY_ID`, `CHILD_CATEGORY_ID` 
        INTO parentId, childId 
        FROM `category_matrix` 
        WHERE `MATRIX_ID` = id;
        
        DELETE FROM `category_matrix` 
        WHERE (`PARENT_CATEGORY_ID` = parentId AND `CHILD_CATEGORY_ID` = childId)
        OR (`PARENT_CATEGORY_ID` = childId AND `CHILD_CATEGORY_ID` = parentId);
        
        SET _index = _index + 1;
    END WHILE;
    
    
    SET Success = 1;
    SET Result = 'Deletion completed';
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_CATEGORY_CATEGORY_MATRIX_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_CATEGORY_CATEGORY_MATRIX_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_CATEGORY_CATEGORY_MATRIX_GET`()
BEGIN
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found'; 
    SELECT 
        cm.IS_ACTIVE,
        cm.MATRIX_ID,
        cm.PARENT_CATEGORY_ID,
        cm.CHILD_CATEGORY_ID,
        parent.CATEGORY_NAME,
        child.CATEGORY_NAME,
        cm.INSERTED_BY,
        cm.INSERTED_TIMESTAMP, 
        cm.UPDATED_BY,
        cm.UPDATED_TIMESTAMP
    FROM `category_matrix` cm
    LEFT JOIN `category_master` parent ON cm.PARENT_CATEGORY_ID = parent.CATEGORY_ID
    LEFT JOIN `category_master` child ON cm.CHILD_CATEGORY_ID = child.CATEGORY_ID;
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_CATEGORY_CATEGORY_MATRIX_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_CATEGORY_CATEGORY_MATRIX_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_CATEGORY_CATEGORY_MATRIX_INSERT`(IN Parameters JSON)
BEGIN
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found'; 
    DECLARE parentId INT;
    DECLARE childId INT;
    DECLARE _index INT DEFAULT 0;
    DECLARE jsonLength INT;
    
    SET parentId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ParentId'));
    SET jsonLength = JSON_LENGTH(Parameters, '$.ChildId');
    
    DELETE FROM `category_matrix` WHERE `PARENT_CATEGORY_ID` = parentId OR `CHILD_CATEGORY_ID` = parentId;
    
    WHILE _index < jsonLength DO
        
        SET childId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$.ChildId[', _index, ']')));
        
        INSERT INTO `category_matrix` (`PARENT_CATEGORY_ID`, `CHILD_CATEGORY_ID`)
        VALUES (parentId, childId);
        
        IF (parentId <> childId) THEN
            INSERT INTO `category_matrix` (`PARENT_CATEGORY_ID`, `CHILD_CATEGORY_ID`)
            VALUES (childId, parentId);
        END IF;
        
        SET _index = _index + 1;
    END WHILE;
    
    SET Success = 1;
    SET Result = 'Insertion completed';
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_COMMUNICATION_STRING_MASTER_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_COMMUNICATION_STRING_MASTER_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_COMMUNICATION_STRING_MASTER_GET_ALL`()
BEGIN
  
  SELECT
    *
  FROM
    dashboard_communication_string_master
  WHERE
    IS_ACTIVE = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_CONFIG_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_CONFIG_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_CONFIG_GET_ALL`()
BEGIN
    
    SELECT 
        `IS_ACTIVE`, 
        `KEY_NAME`, 
        `KEY_VALUE`, 
        `KEY_DESCRIPTION`, 
        `INSERTED_BY`, 
        `INSERTED_ON`, 
        `UPDATED_BY`, 
        `UPDATED_ON`
    FROM 
        `master_config`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_CONFIG_GET_BY_KEY_NAME` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_CONFIG_GET_BY_KEY_NAME` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_CONFIG_GET_BY_KEY_NAME`(
    IN keyName VARCHAR(255)
)
BEGIN
    
    SELECT 
        `KEY_NAME`, 
        `KEY_VALUE`
    FROM 
        `master_config`
    WHERE 
        `IS_ACTIVE` = 1
        AND `KEY_NAME` = keyName;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_DASHBOARD_CONFIG_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_DASHBOARD_CONFIG_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_DASHBOARD_CONFIG_GET_ALL`()
BEGIN

    SELECT
        CASE
            WHEN KEY_NAME LIKE 'DSB\_%' THEN SUBSTRING(KEY_NAME, 5)  
            ELSE KEY_NAME
        END AS KEY_NAME,
        KEY_VALUE,
        KEY_DATA_TYPE
    FROM master_config
    WHERE KEY_NAME IN (

        
        'FALCON_FULL_NAME',
        'FALCON_LINK_WEBSITE',
        'PRODUCT_TYPE',
        'PRODUCT_VERSION',
        'LOCATION_NAME',
        'LOCATION_ID',
        'TOOL_NUMBER',

        'DSB_JWT_TOKEN_EXPIRY_TIME',
        'DSB_DEFAULT_ERROR_MESSAGE_ENABLED',
        'DSB_DEFAULT_ERROR_MESSAGE',
        'DSB_DEFAULT_ERROR_MESSAGE_401',
        'DSB_DEFAULT_DATE_FORMAT',
        'DSB_DEFAULT_DATETIME_FORMAT',

        
        'DSB_BOT_LOGIN_VALID_TIMER',
        'DSB_DEFAULT_AUTO_CALIBRATION_THRESHOLD',
        'DSB_DEFAULT_BOT_BATTERY_THRESHOLD',
        'DSB_DEFAULT_CURRENCY_CONVERSION',
        'DSB_DEFAULT_CURRENCY_DENOMINATION',
        'DSB_DEFAULT_DASHBOARD_UPDATES_TEXT',
        'DSB_DEFAULT_EXPIRY_MAX_DATE',
        'DSB_DEFAULT_EXPIRY_MIN_DATE',
        'DSB_DEFAULT_PAGE_AUTO_REFRESH',
        'DSB_DEFAULT_PAGE_TIME_INTERVAL',
        'DSB_DEFAULT_PAGE_TI_CUSTOM_MAX_DATE',
        'DSB_DEFAULT_PAGE_TI_CUSTOM_MIN_DATE',
        'DSB_DEFAULT_PICK_RULE_JSON',
        'DSB_DEFAULT_PTL_SEQUENCE',
        'DSB_DEFAULT_USER_LOCK_MAX',
        'DSB_DEFAULT_USER_LOCK_PERIOD',
        'DSB_DISABLE_BOTS_PER_STATION',
        'DSB_GLOBAL_PAUSE',
        'DSB_LAST_DASHBOARD_UPDATES_TEXT',
        'DSB_OPERATOR_PTL_MAX_COLUMN_COUNT',
        'DSB_OPERATOR_PTL_MAX_ROW_COUNT',
        'DSB_OPERATOR_P_SHOW_TIMER',
        'DSB_OPERATOR_SPR_VIEW_ENABLED',
        'DSB_PAGE_SESSION_TIME',
        'DSB_PAYLOAD_P_C_MAX_DATE',
        'DSB_PAYLOAD_P_D_TI',
        'DSB_REPORTS_P_C_MAX_DATE',
        'DSB_REPORTS_P_D_TI',
        'DSB_SKU_IMAGE_BASE_URL',
        'DSB_TOOL_GEO_LOCATION',
        'BIN_BARCODE_REGEX',
        'DSB_DEFAULT_STATION_BREAK_TIMER',

        
        'TELEOPERATION_LIFT_SLIDER_FEEDBACK_THRESHOLD',
        'TELEOPERATION_X_MIN_VELOCITY',
        'TELEOPERATION_X_MAX_VELOCITY',
        'TELEOPERATION_Y_MIN_VELOCITY',
        'TELEOPERATION_Y_MAX_VELOCITY',
        'TELEOPERATION_Z_AXIS_MIN_VELOCITY',
        'TELEOPERATION_Z_AXIS_MAX_VELOCITY',
        'TELEOPERATION_Z_MIN_DIRECTION',
        'TELEOPERATION_Z_MAX_DIRECTION',
        'TELEOPERATION_LIFT_MIN_VELOCITY',
        'TELEOPERATION_LIFT_MAX_VELOCITY',
        'TELEOPERATION_LIFT_X_POSITION',
        'TELEOPERATION_LIFT_Y_POSITION',
        'TELEOPERATION_LIFT_Z_POSITION',
        'TELEOPERATION_SLIDER_MIN_VELOCITY',
        'TELEOPERATION_SLIDER_MAX_VELOCITY',
        'TELEOPERATION_SLIDER_LEFT',
        'TELEOPERATION_SLIDER_CENTER',
        'TELEOPERATION_SLIDER_RIGHT'

    )
    AND IS_ACTIVE = 1;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_DASHBOARD_CONFIG_GET_BEFORE_LOGIN` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_DASHBOARD_CONFIG_GET_BEFORE_LOGIN` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_DASHBOARD_CONFIG_GET_BEFORE_LOGIN`()
BEGIN
  SELECT
      CASE
        WHEN KEY_NAME LIKE "DSB\_%" THEN SUBSTRING(KEY_NAME, 5)   
        ELSE KEY_NAME
      END AS KEY_NAME,
      KEY_VALUE,
      KEY_DATA_TYPE
  FROM master_config
  WHERE KEY_NAME IN (
      "FALCON_FULL_NAME",
      "FALCON_LINK_WEBSITE",
      "PRODUCT_TYPE",
      "PRODUCT_VERSION",
      "LOCATION_NAME",
      "LOCATION_ID",
      "TOOL_NUMBER",
      "DSB_JWT_TOKEN_EXPIRY_TIME",
      "DSB_DEFAULT_ERROR_MESSAGE_ENABLED",
      "DSB_DEFAULT_ERROR_MESSAGE",
      "DSB_DEFAULT_ERROR_MESSAGE_401",
      "DSB_DEFAULT_DATE_FORMAT",
      "DSB_DEFAULT_DATETIME_FORMAT"
  )
    AND IS_ACTIVE = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_DASHBOARD_TABS_LIST_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_DASHBOARD_TABS_LIST_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_DASHBOARD_TABS_LIST_GET`(IN Parameters JSON)
BEGIN
    DECLARE p_menu_id INT;
    DECLARE p_section_name VARCHAR(100);
    SET p_menu_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.menu_id')) AS UNSIGNED);
    SET p_section_name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.section_name'));
    IF EXISTS (
        SELECT 1
        FROM dashboard_tab_master
        WHERE IS_ACTIVE = 1
          AND (MENU_ID = p_menu_id OR SECTION_NAME = p_section_name)
    ) THEN
    
        IF p_section_name IS NOT NULL AND p_section_name <> '' THEN
            SELECT *
            FROM dashboard_tab_master
            WHERE SECTION_NAME = p_section_name
              AND IS_ACTIVE = 1
            ORDER BY SEQUENCE;
        ELSE
            SELECT *
            FROM dashboard_tab_master
            WHERE MENU_ID = p_menu_id
              AND IS_ACTIVE = 1
            ORDER BY SEQUENCE;
        END IF;
    ELSE
        SELECT 
            0 AS Success, 
            'Menu ID or Section Name not found.' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_DASHBOARD_TAB_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_DASHBOARD_TAB_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_DASHBOARD_TAB_GET_ALL`()
BEGIN
	SELECT `IS_ACTIVE`, `TAB_ID`, `TAB_IDENTIFIER_NAME`, `TAB_KEY_NAME`, `TAB_NAME`, `INSERTED_BY`, `INSERTED_ON`, `UPDATED_BY`, `UPDATED_ON` FROM dashboard_tab_master;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_DELETE_SKU_MASTER_BY_SKU_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_DELETE_SKU_MASTER_BY_SKU_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_DELETE_SKU_MASTER_BY_SKU_ID`(IN Parameters VARCHAR(1000))
BEGIN
    DECLARE sql_query TEXT;
    DECLARE deleted_rows INT default 0;
    
    SET sql_query = CONCAT('DELETE FROM `sku_batch_master` WHERE SKU_ID IN (', Parameters, ')');
    
    SET @sql = sql_query;
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
     SET sql_query = CONCAT('DELETE FROM `sku_ean_mapping` WHERE SKU_ID IN (', Parameters, ')');
    
    SET @sql = sql_query;
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    
    SET sql_query = CONCAT('DELETE FROM `sku_master` WHERE SKU_ID IN (', Parameters, ')');
    
    SET @sql = sql_query;
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    
    SET deleted_rows = ROW_COUNT();
    
    DEALLOCATE PREPARE stmt;
    
     select deleted_rows;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_DOWNLOAD_LOGS_LIST_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_DOWNLOAD_LOGS_LIST_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_DOWNLOAD_LOGS_LIST_GET_ALL`()
BEGIN
    
    SELECT 
        BOT_ID AS DROPDOWN_TEXT,
        'BOTH' AS COMMUNICATION_TYPE,
        BOT_ID AS PATH_URL
    FROM 
        bot_master
    UNION ALL
    
    SELECT 
        HARDWARE_ALIAS AS DROPDOWN_TEXT,
        HARDWARE_COMMUNICATION_TYPE AS COMMUNICATION_TYPE,
        CASE 
            WHEN HARDWARE_TYPE = 'CONVEYOR' THEN CONCAT('Conveyor-', HARDWARE_ID)
            WHEN HARDWARE_TYPE IN ('PTL_SCANNER', 'STATION_SCANNER') THEN CONCAT('Scanner-', HARDWARE_ID)
            ELSE ''
        END AS PATH_URL
    FROM 
        hardware_registered
    WHERE 
        HARDWARE_COMMUNICATION_TYPE <> 'NONE'
        AND (
            (HARDWARE_TYPE = 'CONVEYOR' AND HARDWARE_ID IS NOT NULL) OR
            (HARDWARE_TYPE = 'PTL_SCANNER' AND HARDWARE_ID IS NOT NULL) or
            (HARDWARE_TYPE = 'STATION_SCANNER' AND HARDWARE_ID IS NOT NULL)
        );
END */$$
DELIMITER ;