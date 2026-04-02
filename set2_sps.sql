
----------------------------------------------------------------
/* Procedure structure for procedure `DSB_DROPDOWN_LIST_GET_BY_HEADER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_DROPDOWN_LIST_GET_BY_HEADER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_DROPDOWN_LIST_GET_BY_HEADER`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_header_value           VARCHAR(255);	
    DECLARE v_target_table           VARCHAR(100);
    DECLARE v_target_column_value    VARCHAR(100);
    DECLARE v_target_column_text     VARCHAR(100);
    DECLARE v_list_by_enum           BOOLEAN DEFAULT 0;
    DECLARE enum_json                LONGTEXT;
    
    SET p_header_value = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.header'));
    
    CASE p_header_value
        WHEN 'TABLE_WAVE_TYPE'           THEN SET v_target_table = 'wave_master',       v_target_column_value = 'WAVE_TYPE',        v_target_column_text = 'WAVE_TYPE',        v_list_by_enum = 1;
        WHEN 'TABLE_WAVE_STATUS'         THEN SET v_target_table = 'wave_master',       v_target_column_value = 'WAVE_STATUS',      v_target_column_text = 'WAVE_STATUS',      v_list_by_enum = 1;
        WHEN 'TABLE_STATION_WAVE_STATUS' THEN SET v_target_table = 'hw_station_master', v_target_column_value = 'WAVE_STATUS',      v_target_column_text = 'WAVE_STATUS',      v_list_by_enum = 1;
        WHEN 'TABLE_BOT_STATUS'          THEN SET v_target_table = 'bot_master',        v_target_column_value = 'STATUS',           v_target_column_text = 'STATUS',           v_list_by_enum = 1;
        WHEN 'TABLE_BOT_MODE'            THEN SET v_target_table = 'bot_master',        v_target_column_value = 'AUTO_MANUAL',      v_target_column_text = 'AUTO_MANUAL',      v_list_by_enum = 1;
        WHEN 'TABLE_BOT_LOAD_STATUS'     THEN SET v_target_table = 'bot_master',        v_target_column_value = 'LOAD_CONDITION',   v_target_column_text = 'LOAD_CONDITION',   v_list_by_enum = 1;
        WHEN 'TABLE_AISLE_NUMBER'        THEN SET v_target_table = 'location_master',   v_target_column_value = 'AISLE_NUMBER',     v_target_column_text = 'AISLE_NUMBER',     v_list_by_enum = 1;
        WHEN 'STATION_LIST'              THEN SET v_target_table = 'hw_station_master', v_target_column_value = 'STATION_ID',       v_target_column_text = 'STATION_ALIAS_NAME', v_list_by_enum = 0;
        ELSE 
            SET v_target_table = NULL, 
                v_target_column_value = NULL, 
                v_target_column_text = NULL, 
                v_list_by_enum = 0;
    END CASE;
    
    IF v_target_table IS NOT NULL AND v_target_column_value IS NOT NULL THEN
        
        IF v_list_by_enum = 1 THEN
            SELECT 
                REPLACE(REPLACE(REPLACE(
                    SUBSTRING(COLUMN_TYPE, 6, LENGTH(COLUMN_TYPE) - 6), 
                    '''', ''
                ), ',', '","'), ' ', '') 
            INTO enum_json
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = v_target_table 
              AND COLUMN_NAME = v_target_column_value
              AND TABLE_SCHEMA = DATABASE();
            
            IF enum_json IS NOT NULL THEN
                SELECT 
                    TRIM(BOTH '"' FROM enum_value) AS DROPDOWN_TEXT,
                    TRIM(BOTH '"' FROM enum_value) AS DROPDOWN_VALUE
                FROM JSON_TABLE(
                    CONCAT('["', enum_json, '"]'),
                    '$[*]' COLUMNS (
                        enum_value VARCHAR(255) PATH '$'
                    )
                ) AS enums;
            ELSE
                SELECT 'No ENUM values found' AS DROPDOWN_TEXT, NULL AS DROPDOWN_VALUE;
            END IF;
        ELSE
            
            SET @sql = CONCAT(
                'SELECT DISTINCT ', v_target_column_text, ' AS DROPDOWN_TEXT, ',
                v_target_column_value, ' AS DROPDOWN_VALUE ',
                'FROM ', v_target_table, ' ',
                'WHERE ', v_target_column_value, ' IS NOT NULL'
            );
            PREPARE stmt FROM @sql;
            EXECUTE stmt;
            DEALLOCATE PREPARE stmt;
        END IF;
    ELSE
        
        SELECT 
            DROPDOWN_TEXT, 
            DROPDOWN_VALUE 
        FROM dashboard_master_data 
        WHERE HEADER = p_header_value
          AND IS_ACTIVE = 1;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GENERIC_TRANSACTION_ERROR_HANDLER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GENERIC_TRANSACTION_ERROR_HANDLER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GENERIC_TRANSACTION_ERROR_HANDLER`()
BEGIN
    DECLARE v_error_message TEXT;

    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    ROLLBACK;
    SELECT 0 AS Success, v_error_message AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GET_LIVE_INVENTORY_ARTCILE_BY_SKU_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GET_LIVE_INVENTORY_ARTCILE_BY_SKU_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GET_LIVE_INVENTORY_ARTCILE_BY_SKU_ID`(IN Parameters VARCHAR(1000))
BEGIN
    DECLARE sql_query TEXT;
    DECLARE delete_query TEXT;
     SET sql_query = CONCAT('SELECT distinct ARTICLE_ID AS SKU_ID FROM `live_inventory_master` WHERE `ARTICLE_ID` IN (', Parameters, ')');
    
    
    SET @sql = sql_query;
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    
  
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_AUDIT_MARKED_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_AUDIT_MARKED_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_AUDIT_MARKED_FEEDBACK`()
BEGIN
    SELECT 
        
        
        lm.AISLE_NUMBER,
        lm.TOWER_NUMBER,
        lm.Z AS `LEVEL`,
        CASE
            WHEN lm.Y IN (
                SELECT DISTINCT (Y - 1)
                FROM location_master
                WHERE TYPE LIKE 'TOWER%'
            ) THEN 'LEFT'
            WHEN lm.Y IN (
                SELECT DISTINCT (Y + 1)
                FROM location_master
                WHERE TYPE LIKE 'TOWER%'
            ) THEN 'RIGHT'
            ELSE NULL
        END AS `TOWER SIDE`,
        lm.LOCATION_ID,
        lm.X,
        lm.Y,
        sbm.AUDIT_MARKED_TIMESTAMP,
        sbm.AUDIT_REASON
    FROM 
        store_bin_master sbm
    LEFT JOIN 
        bin_info_master bim ON bim.BIN_ID = sbm.BIN_ID
    LEFT JOIN 
        location_master lm ON sbm.LOCATION_ID = lm.LOCATION_ID
    WHERE 
        sbm.AUDIT = 1
    ORDER BY 
        sbm.UPDATED_TIMESTAMP DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_BOTS_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_BOTS_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_BOTS_FEEDBACK`()
BEGIN
  WITH
  LatestTask AS (
    SELECT
      t.BOT_ID,
      t.TASK_ID,
      t.TASK_TYPE,
      t.DESTINATION_LOCATION_ID,
      lm_dest.AISLE_NUMBER AS FINAL_AISLE,
      lm_dest.TOWER_NUMBER AS FINAL_TOWER,
      lm_dest.Z            AS FINAL_Z,
      ROW_NUMBER() OVER (PARTITION BY t.BOT_ID ORDER BY t.INSERTED_TIMESTAMP DESC) AS rn
    FROM task_master AS t
    LEFT JOIN location_master AS lm_dest
           ON lm_dest.LOCATION_ID = t.DESTINATION_LOCATION_ID
    WHERE t.STATUS = 'PROCESSING'
  ),
  LatestTaskDetail AS (
    SELECT
      td.TASK_MASTER_ID,
      lm_next.AISLE_NUMBER AS NEXT_AISLE,
      lm_next.TOWER_NUMBER AS NEXT_TOWER,
      lm_next.Z            AS NEXT_Z,
      td.END_LOCATION_ID,
      ROW_NUMBER() OVER (PARTITION BY td.TASK_MASTER_ID ORDER BY td.INSERTED_TIMESTAMP DESC) AS rns
    FROM task_detail AS td
    INNER JOIN LatestTask lt
            ON lt.TASK_ID = td.TASK_MASTER_ID
    LEFT JOIN location_master AS lm_next
           ON lm_next.LOCATION_ID = td.END_LOCATION_ID
    WHERE td.STATUS = 'PROCESSING'
  ),
  LatestBinMapping AS (
    SELECT
      BOT_ID,
      BIN_ID,
      STATION_ID,
      TYPE,
      STATUS,
      ROW_NUMBER() OVER (PARTITION BY BOT_ID ORDER BY UPDATED_TIMESTAMP DESC) AS rn
    FROM order_bin_mapping
    WHERE STATUS NOT IN ('PENDING', 'TASK_COMPLETED')
  )
  SELECT
    bm.STATUS,
    bm.BOT_ID,
    CASE
      WHEN tbd.`Manual Position Mode` = TRUE THEN 'HMI'
      WHEN UPPER(bm.AUTO_MANUAL) = 'AUTO' AND tbdf.`Auto Start Feedback` = TRUE  THEN 'AUTO START'
      WHEN UPPER(bm.AUTO_MANUAL) = 'AUTO' AND tbdf.`Auto Start Feedback` = FALSE THEN 'AUTO STOP'
      ELSE UPPER(bm.AUTO_MANUAL)
    END AS BOT_MODE,
    bm.AUTO_MANUAL,
    bm.BATTERY,
    bm.ALARM AS ALARM_CODE,
    am.ALARM_DESCRIPTION,
    CONCAT(bm.ALARM, ' - ', am.ALARM_DESCRIPTION) AS ALARM_CODE_DESCRIPTION,
    CASE WHEN bm.ALARM > 0 THEN bm.ALARM_TIMESTAMP      ELSE NULL END AS ALARM_TIMESTAMP,
    CASE WHEN bm.ALARM > 0 THEN bm.ALARM_POSITION_X_Y_Z ELSE NULL END AS ALARM_LOCATION_X_Y_Z,
    bm.IP AS BOT_IP,
    CONCAT(bm.GRIDX, ', ', bm.GRIDY, ', ', bm.GRIDZ) AS `X_Y_Z`,
    bm.GRIDX,
    bm.GRIDY,
    bm.GRIDZ,
    CASE
      WHEN bm.LOAD_CONDITION = 'UL' THEN 'Unloaded'
      WHEN bm.LOAD_CONDITION = 'LD' THEN 'Loaded'
      ELSE bm.LOAD_CONDITION
    END AS LOAD_STATUS,
    bm.LOAD_CONDITION,
    bm.COUNTER,
    bm.SLIDER_RECOVERY_FAIL_ALARM_BIT,
    bm.BOT_TO_MAINTENANCE_BIT AS BOT_TO_MAINTENANCE_BIT,
    tbdf.`Emergency Stop Feedback`             AS EMERGENCY_STOP_FEEDBACK,
    tbdf.`Auto Start Feedback`                 AS AUTO_START_FEEDBACK,
    tbd.`Manual Position Mode`                 AS HMI_MODE_FEEDBACK,
    tbd.`Gearbox_Health_Check_Start`            AS GEARBOX_HEALTH_CHECK_START_FEEDBACK,
    tbdf.`Gear Box Health Check Completed`      AS GEARBOX_HEALTH_CHECK_COMPLETED_FEEDBACK,
    lm_cur.TYPE,
    lt.TASK_TYPE,
    IF(bm.LOAD_CONDITION = 'LD', obm.BIN_ID, NULL) AS BIN_ID,
    IF(bm.LOAD_CONDITION = 'LD', obm.TYPE, NULL) AS OBM_TYPE,
    IF(bm.LOAD_CONDITION = 'LD', obm.STATUS, NULL) AS OBM_STATUS,
    CASE
      WHEN lt.TASK_TYPE = 'BIN_ZONE_TO_STORE'
        THEN CONCAT(ltd.NEXT_AISLE, ', ', ltd.NEXT_TOWER, ', ', ltd.NEXT_Z)
      WHEN lt.TASK_TYPE IN ('BIN_STORE_TO_ZONE', 'STATION_TO_STATION') AND ltd.NEXT_TOWER IS NOT NULL
        THEN CONCAT(ltd.NEXT_AISLE, ', ', ltd.NEXT_TOWER, ', ', ltd.NEXT_Z)
      WHEN lt.TASK_TYPE IN ('BIN_STORE_TO_ZONE', 'STATION_TO_STATION') AND ltd.NEXT_TOWER IS NULL
        THEN CONCAT('Station ', obm.STATION_ID)
      ELSE NULL
    END AS NEXT_DESTINATION,
    CASE
      WHEN lt.TASK_TYPE = 'BIN_ZONE_TO_STORE'
        THEN CONCAT(lt.FINAL_AISLE, ', ', lt.FINAL_TOWER, ', ', lt.FINAL_Z)
      WHEN lt.TASK_TYPE IN ('BIN_STORE_TO_ZONE', 'STATION_TO_STATION')
        THEN CONCAT('Station ', obm.STATION_ID)
      ELSE NULL
    END AS FINAL_DESTINATION,

    
    COALESCE(s.TOTAL_STEPS, 0)      AS STEPS_TOTAL,
    COALESCE(s.COMPLETED_STEPS, 0)  AS STEPS_COMPLETED,
    COALESCE(s.STEPS_NOT_SENT, 0)   AS STEPS_NOT_SENT,

    
    EXISTS (
      SELECT 1
      FROM subcontroller_reservations_master AS sr
      WHERE sr.BOT_ID = bm.BOT_ID
        AND sr.IS_BUFFER = 1
    ) AS IS_BUFFER,

    
    dbm.LOCK_BY,
    dbm.LOCK_TIMESTAMP,
    dbm.UNLOCK_BY,
    dbm.UNLOCK_TIMESTAMP,
    dbm.REQUEST_BY
  FROM bot_master AS bm
  LEFT JOIN alarm_master AS am
         ON am.ALARM_CODE = bm.ALARM
        AND am.ALARM_TYPE = bm.ALARM_TYPE
  LEFT JOIN teleoperation_bool_data AS tbd
         ON tbd.BOT_ID = bm.BOT_ID
  LEFT JOIN teleoperation_bool_data_feedback AS tbdf
         ON tbdf.BOT_ID = bm.BOT_ID
  LEFT JOIN dashboard_bot_master AS dbm
         ON dbm.BOT_ID = bm.BOT_ID

  
  LEFT JOIN LatestTask        AS lt
         ON lt.BOT_ID = bm.BOT_ID AND lt.rn = 1
  LEFT JOIN LatestTaskDetail  AS ltd
         ON ltd.TASK_MASTER_ID = lt.TASK_ID AND ltd.rns = 1
  LEFT JOIN LatestBinMapping  AS obm
         ON obm.BOT_ID = bm.BOT_ID AND obm.rn = 1

  
  LEFT JOIN (
    SELECT
      BOT_ID,
      COUNT(*)                                                  AS TOTAL_STEPS,
      SUM(CASE WHEN IS_COMPLETED = 1 THEN 1 ELSE 0 END)        AS COMPLETED_STEPS,
      SUM(CASE WHEN LAST_SENT_TIMESTAMP IS NULL THEN 1 ELSE 0 END) AS STEPS_NOT_SENT
    FROM steps
    GROUP BY BOT_ID
  ) AS s
    ON s.BOT_ID = bm.BOT_ID

  LEFT JOIN location_master AS lm_cur
         ON lm_cur.X = bm.GRIDX
        AND lm_cur.Y = bm.GRIDY
        AND lm_cur.Z = bm.GRIDZ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_BOTS_OVERVIEW` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_BOTS_OVERVIEW` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_BOTS_OVERVIEW`()
BEGIN
  WITH
  LatestTask AS (
    SELECT
      t.BOT_ID,
      t.TASK_ID,
      t.TASK_TYPE,
      t.DESTINATION_LOCATION_ID,
      lm_dest.AISLE_NUMBER AS FINAL_AISLE,
      lm_dest.TOWER_NUMBER AS FINAL_TOWER,
      lm_dest.Z            AS FINAL_Z,
      ROW_NUMBER() OVER (PARTITION BY t.BOT_ID ORDER BY t.INSERTED_TIMESTAMP DESC) AS rn
    FROM task_master AS t
    LEFT JOIN location_master AS lm_dest
           ON lm_dest.LOCATION_ID = t.DESTINATION_LOCATION_ID
    WHERE t.STATUS = 'PROCESSING'
  ),
  LatestTaskDetail AS (
    SELECT
      td.TASK_MASTER_ID,
      lm_next.AISLE_NUMBER AS NEXT_AISLE,
      lm_next.TOWER_NUMBER AS NEXT_TOWER,
      lm_next.Z            AS NEXT_Z,
      td.END_LOCATION_ID,
      ROW_NUMBER() OVER (PARTITION BY td.TASK_MASTER_ID ORDER BY td.INSERTED_TIMESTAMP DESC) AS rns
    FROM task_detail AS td
    INNER JOIN LatestTask lt
            ON lt.TASK_ID = td.TASK_MASTER_ID
    LEFT JOIN location_master AS lm_next
           ON lm_next.LOCATION_ID = td.END_LOCATION_ID
    WHERE td.STATUS = 'PROCESSING'
  ),
  LatestBinMapping AS (
    SELECT
      BOT_ID,
      BIN_ID,
      STATION_ID,
      TYPE,
      STATUS,
      ROW_NUMBER() OVER (PARTITION BY BOT_ID ORDER BY UPDATED_TIMESTAMP DESC) AS rn
    FROM order_bin_mapping
    WHERE STATUS NOT IN ('PENDING', 'TASK_COMPLETED')
  )
  SELECT
    bm.STATUS,
    bm.BOT_ID,
    CASE
      WHEN tbd.`Manual Position Mode` = TRUE THEN 'HMI'
      WHEN UPPER(bm.AUTO_MANUAL) = 'AUTO' AND tbdf.`Auto Start Feedback` = TRUE  THEN 'AUTO START'
      WHEN UPPER(bm.AUTO_MANUAL) = 'AUTO' AND tbdf.`Auto Start Feedback` = FALSE THEN 'AUTO STOP'
      ELSE UPPER(bm.AUTO_MANUAL)
    END AS BOT_MODE,
    bm.AUTO_MANUAL,
    bm.BATTERY,
    bm.ALARM AS ALARM_CODE,
    am.ALARM_DESCRIPTION,
    CONCAT(bm.ALARM, ' - ', am.ALARM_DESCRIPTION) AS ALARM_CODE_DESCRIPTION,
    CASE WHEN bm.ALARM > 0 THEN bm.ALARM_TIMESTAMP      ELSE NULL END AS ALARM_TIMESTAMP,
    CASE WHEN bm.ALARM > 0 THEN bm.ALARM_POSITION_X_Y_Z ELSE NULL END AS ALARM_LOCATION_X_Y_Z,
    bm.IP AS BOT_IP,
    CONCAT(bm.GRIDX, ', ', bm.GRIDY, ', ', bm.GRIDZ) AS `X_Y_Z`,
    bm.GRIDX,
    bm.GRIDY,
    bm.GRIDZ,
    CASE
      WHEN bm.LOAD_CONDITION = 'UL' THEN 'Unloaded'
      WHEN bm.LOAD_CONDITION = 'LD' THEN 'Loaded'
      ELSE bm.LOAD_CONDITION
    END AS LOAD_STATUS,
    bm.LOAD_CONDITION,
    bm.COUNTER,
    bm.SLIDER_RECOVERY_FAIL_ALARM_BIT,
    bm.BOT_TO_MAINTENANCE_BIT AS BOT_TO_MAINTENANCE_BIT,
    tbdf.`Emergency Stop Feedback`             AS EMERGENCY_STOP_FEEDBACK,
    tbdf.`Auto Start Feedback`                 AS AUTO_START_FEEDBACK,
    tbd.`Manual Position Mode`                 AS HMI_MODE_FEEDBACK,
    tbd.`Gearbox_Health_Check_Start`            AS GEARBOX_HEALTH_CHECK_START_FEEDBACK,
    tbdf.`Gear Box Health Check Completed`      AS GEARBOX_HEALTH_CHECK_COMPLETED_FEEDBACK,
    lm_cur.TYPE,
    lt.TASK_TYPE,
    IF(bm.LOAD_CONDITION = 'LD', obm.BIN_ID, NULL) AS BIN_ID,
    IF(bm.LOAD_CONDITION = 'LD', obm.TYPE, NULL) AS OBM_TYPE,
    IF(bm.LOAD_CONDITION = 'LD', obm.STATUS, NULL) AS OBM_STATUS,
    CASE
      WHEN lt.TASK_TYPE = 'BIN_ZONE_TO_STORE'
        THEN CONCAT(ltd.NEXT_AISLE, ', ', ltd.NEXT_TOWER, ', ', ltd.NEXT_Z)
      WHEN lt.TASK_TYPE IN ('BIN_STORE_TO_ZONE', 'STATION_TO_STATION') AND ltd.NEXT_TOWER IS NOT NULL
        THEN CONCAT(ltd.NEXT_AISLE, ', ', ltd.NEXT_TOWER, ', ', ltd.NEXT_Z)
      WHEN lt.TASK_TYPE IN ('BIN_STORE_TO_ZONE', 'STATION_TO_STATION') AND ltd.NEXT_TOWER IS NULL
        THEN CONCAT('Station ', obm.STATION_ID)
      ELSE NULL
    END AS NEXT_DESTINATION,
    CASE
      WHEN lt.TASK_TYPE = 'BIN_ZONE_TO_STORE'
        THEN CONCAT(lt.FINAL_AISLE, ', ', lt.FINAL_TOWER, ', ', lt.FINAL_Z)
      WHEN lt.TASK_TYPE IN ('BIN_STORE_TO_ZONE', 'STATION_TO_STATION')
        THEN CONCAT('Station ', obm.STATION_ID)
      ELSE NULL
    END AS FINAL_DESTINATION,

    
    COALESCE(s.TOTAL_STEPS, 0)      AS STEPS_TOTAL,
    COALESCE(s.COMPLETED_STEPS, 0)  AS STEPS_COMPLETED,
    COALESCE(s.STEPS_NOT_SENT, 0)   AS STEPS_NOT_SENT,

    
    EXISTS (
      SELECT 1
      FROM subcontroller_reservations_master AS sr
      WHERE sr.BOT_ID = bm.BOT_ID
        AND sr.IS_BUFFER = 1
    ) AS IS_BUFFER,

    
    dbm.LOCK_BY,
    dbm.LOCK_TIMESTAMP,
    dbm.UNLOCK_BY,
    dbm.UNLOCK_TIMESTAMP,
    dbm.REQUEST_BY
  FROM bot_master AS bm
  LEFT JOIN alarm_master AS am
         ON am.ALARM_CODE = bm.ALARM
        AND am.ALARM_TYPE = bm.ALARM_TYPE
  LEFT JOIN teleoperation_bool_data AS tbd
         ON tbd.BOT_ID = bm.BOT_ID
  LEFT JOIN teleoperation_bool_data_feedback AS tbdf
         ON tbdf.BOT_ID = bm.BOT_ID
  LEFT JOIN dashboard_bot_master AS dbm
         ON dbm.BOT_ID = bm.BOT_ID

  
  LEFT JOIN LatestTask        AS lt
         ON lt.BOT_ID = bm.BOT_ID AND lt.rn = 1
  LEFT JOIN LatestTaskDetail  AS ltd
         ON ltd.TASK_MASTER_ID = lt.TASK_ID AND ltd.rns = 1
  LEFT JOIN LatestBinMapping  AS obm
         ON obm.BOT_ID = bm.BOT_ID AND obm.rn = 1

  
  LEFT JOIN (
    SELECT
      BOT_ID,
      COUNT(*)                                                  AS TOTAL_STEPS,
      SUM(CASE WHEN IS_COMPLETED = 1 THEN 1 ELSE 0 END)        AS COMPLETED_STEPS,
      SUM(CASE WHEN LAST_SENT_TIMESTAMP IS NULL THEN 1 ELSE 0 END) AS STEPS_NOT_SENT
    FROM steps
    GROUP BY BOT_ID
  ) AS s
    ON s.BOT_ID = bm.BOT_ID

  LEFT JOIN location_master AS lm_cur
         ON lm_cur.X = bm.GRIDX
        AND lm_cur.Y = bm.GRIDY
        AND lm_cur.Z = bm.GRIDZ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_BOT_BATTERY_CHARGING_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_BOT_BATTERY_CHARGING_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_BOT_BATTERY_CHARGING_FEEDBACK`()
BEGIN
    SELECT *
    FROM (
        SELECT
            bm.STATUS,
            bm.BOT_ID,
            
            CASE 
                WHEN srm.TYPE = 'CHARGING_STATION' AND ((bm.GRIDX = 0 AND bm.GRIDY = 12) OR (bm.GRIDX = 0 AND bm.GRIDY = 228)) THEN 'REACHED'
                WHEN srm.TYPE = 'CHARGING_STATION' THEN 'REACHING'
                ELSE 'WAITING'
            END AS `REACHING_STATUS`,
            
            CASE
                WHEN tbd.`Manual Position Mode` = TRUE THEN 'HMI'
                WHEN UPPER(bm.AUTO_MANUAL) = 'AUTO' AND tbdf.`Auto Start Feedback` = TRUE THEN 'AUTO START'
                WHEN UPPER(bm.AUTO_MANUAL) = 'AUTO' AND tbdf.`Auto Start Feedback` = FALSE THEN 'AUTO STOP'
                ELSE UPPER(bm.AUTO_MANUAL)
            END AS `BOT_MODE`,
            
		bm.BATTERY, 
            CONCAT(GRIDX, ', ', GRIDY, ', ', GRIDZ) AS `X_Y_Z`,
            
            CASE
                WHEN bm.ALARM = 0 THEN 'NO'
                ELSE 'YES'
            END AS ALARM,
            CASE 
                WHEN bm.ALARM_TYPE IN ('NORMAL', 'MAINTENANCE') THEN CONCAT(bm.ALARM, ' - ', am.ALARM_DESCRIPTION)
                ELSE (
                    SELECT CONCAT(bm.ALARM, ' - ', am2.ALARM_DESCRIPTION)
                    FROM alarm_master am2 
                    WHERE am2.ALARM_TYPE = 'NORMAL' AND am2.ALARM_CODE = 0
                    LIMIT 1
                )
            END AS ALARM_CODE_DESCRIPTION,
            
            CASE 
                WHEN bm.GRIDX = 0 AND bm.GRIDY = 12 THEN 'Charging Station 1'
                WHEN bm.GRIDX = 0 AND bm.GRIDY = 228 THEN 'Charging Station 2'
                ELSE ''
            END AS `STATION`,
            
            CONCAT(bcbl.BATTERY_PERCENTAGE, '%') AS `BATTERY_AT_CHARGING_BIT_HIGH`,
            bcbl.INSERTED_TIMESTAMP AS `TIMESTAMP_AT_CHARGING_BIT_HIGH`
        FROM bot_master bm
        LEFT JOIN alarm_master am 
            ON am.ALARM_CODE = bm.ALARM AND am.ALARM_TYPE = bm.ALARM_TYPE
        LEFT JOIN (
            SELECT BOT_ID, TYPE
            FROM subcontroller_reservations_master
            WHERE TYPE = 'CHARGING_STATION'
        ) srm ON srm.BOT_ID = bm.BOT_ID
        LEFT JOIN teleoperation_bool_data tbd 
            ON tbd.BOT_ID = bm.BOT_ID
        LEFT JOIN teleoperation_bool_data_feedback tbdf 
            ON tbdf.BOT_ID = bm.BOT_ID
        LEFT JOIN (
            SELECT BOT_ID, BATTERY_PERCENTAGE, INSERTED_TIMESTAMP
            FROM bot_charging_bit_log
            ORDER BY INSERTED_TIMESTAMP DESC
            limit 1
        ) bcbl ON bcbl.BOT_ID = bm.BOT_ID
        WHERE bm.CHARGING_BIT = 1 AND bm.STATUS = 'ENABLED'
    ) AS charging_info
    ORDER BY 
        CASE 
            WHEN REACHING_STATUS = 'REACHED' THEN 1
            WHEN REACHING_STATUS = 'REACHING' THEN 2
            ELSE 3
        END;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_BOT_G_PAUSE_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_BOT_G_PAUSE_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_BOT_G_PAUSE_FEEDBACK`()
BEGIN
    SELECT 
        `Global Pause Bit` AS FEEDBACK
    FROM 
        teleoperation_bool_data
    LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_BOT_MASTER_UPDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_BOT_MASTER_UPDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_BOT_MASTER_UPDATE`(
    IN Parameters JSON  
)
BEGIN
    
    DECLARE p_bot_id        VARCHAR(10);
    DECLARE p_column_value  VARCHAR(50);
    DECLARE p_column_name   VARCHAR(50);
    DECLARE p_user_name     VARCHAR(50);
    DECLARE Success         INT DEFAULT 1;
    DECLARE Result          VARCHAR(255);

    
    SET p_bot_id       = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bot_id'));
    SET p_column_value = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.column_value'));
    SET p_column_name  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.column_name'));
    SET p_user_name    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));

    
    IF p_bot_id IS NULL OR p_bot_id = '' THEN
        SET Success = 0;
        SET Result  = 'BOT ID is required';
    END IF;

    IF p_column_name IS NULL OR p_column_name = '' THEN
        SET Success = 0;
        SET Result  = 'Column name is required';
    END IF;

    
    IF Success = 1 THEN

        
        IF EXISTS (SELECT 1 FROM `bot_master` WHERE `BOT_ID` = p_bot_id) THEN

            
            IF p_column_name = 'DSB_TMM_Z_AXIS_ACKNOWLEDGEMENT' THEN
                CALL DSB_BOT_Z_ACKNOWLEDGEMENT_UPDATE(p_bot_id, p_column_value);

            ELSEIF p_column_name = 'AUTO_MANUAL' THEN
                CALL DSB_BOT_MODE_UPDATE_BY_BOT_ID(p_bot_id, p_column_value);

            ELSEIF p_column_name = 'ENABLE_DISABLE' THEN
                CALL DSB_BOT_STATUS_UPDATE_BY_BOT_ID(p_bot_id, p_column_value);

            ELSEIF p_column_name = 'CHARGING_BIT' THEN
                CALL DSB_BOT_CHARGING_BIT_UPDATE_BY_BOT_ID(p_bot_id, p_column_value);

            ELSEIF p_column_name = 'BOT_TO_MAINTENANCE' THEN
                CALL DSB_BOT_MASTER_UPDATE_BOT_TO_MAINTENANCE(p_bot_id, p_column_value);

            ELSEIF p_column_name = 'MOVE_OUT_OF_FLEET' THEN
                CALL DSB_BOT_UPDATE_MOVE_OUT_OF_FLEET(p_bot_id);

            ELSE
                SET Success = 0;
                SET Result  = 'ColumnName Not Found';
            END IF;

        ELSE
            SET Success = 0;
            SET Result  = 'Bot Not Exists';
        END IF;
    END IF;

    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_BOT_OBSTACLE_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_BOT_OBSTACLE_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_BOT_OBSTACLE_FEEDBACK`()
BEGIN
    SELECT
        bol.`BOT_ID`,
        CONCAT_WS(', ', bol.`X`, bol.`Y`, bol.`Z`) AS `X_Y_Z`,
        COALESCE(lm.`TYPE`, 'UNKNOWN')            AS `TYPE`,
        bol.`BARCODE_NUMBER`,
        CONCAT(TIMESTAMPDIFF(SECOND, bol.`OBSTACLE_DETECTION_TIMESTAMP`, NOW()), ' Secs') AS `OBSTACLE_SINCE`,
        bol.`OBSTACLE_DETECTION_TIMESTAMP`
    FROM `bot_obstacle_log` AS bol
    LEFT JOIN `location_master` AS lm
           ON lm.`X` = bol.`X`
          AND lm.`Y` = bol.`Y`
          AND lm.`Z` = bol.`Z`
    ORDER BY bol.`OBSTACLE_DETECTION_TIMESTAMP` DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_FEEDBACK_BY_BOT_ID`(
    IN Parameters JSON 
)
BEGIN
    
    DECLARE p_bot_id           VARCHAR(10);
    DECLARE p_feedback_name    VARCHAR(50);
    DECLARE p_extra_parameters JSON;

    
    DECLARE Identifier      VARCHAR(50);
    DECLARE IdentifierType  VARCHAR(50); 

    
    SET p_bot_id           = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.botId'));
    SET p_feedback_name    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.feedbackName'));
    SET p_extra_parameters = JSON_EXTRACT(Parameters, '$.extraProperties');

    SET Identifier     = JSON_UNQUOTE(JSON_EXTRACT(p_extra_parameters, '$.identifier'));
    SET IdentifierType = JSON_UNQUOTE(JSON_EXTRACT(p_extra_parameters, '$.type'));

    
    IF p_feedback_name = 'BOT_HOME_FEEDBACK' THEN
        CALL DSB_BOT_HOME_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_RESET_FEEDBACK' THEN
        CALL DSB_BOT_RESET_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_AUTO_CALIBRATION_FEEDBACK' THEN
        CALL DSB_BOT_AUTO_CALIBRATION_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_HOME_CALL_FEEDBACK' THEN
        CALL DSB_BOT_HOME_CALL_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_Z_ACKNOWLEDGEMENT_FEEDBACK' THEN
        CALL DSB_BOT_Z_ACKNOWLEDGEMENT_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_RECOVERY_NON_RECOVERY_FEEDBACK' THEN
        CALL DSB_BOT_RECOVERY_NON_RECOVERY_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'HMI_GET_ACTUATOR_FEEDBACK' THEN
        CALL DSB_HMI_GET_ACTUATOR_FEEDBACK(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_MANUAL_PACKET_FEEDBACK' THEN
        CALL DSB_BOT_MANUAL_PACKET_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_JUNCTION_COORDINATE_FEEDBACK' THEN
        CALL DSB_HMI_GET_BARCODE_JUNCTION_COORD_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_BARCODE_COORDINATE_FEEDBACK' THEN
        CALL DSB_HMI_GET_BARCODE_COORD_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_BARCODE_SCANNER_SERVO_POS_FEEDBACK' THEN
        CALL DSB_HMI_GET_BARCODE_SERVOPOS_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_INPUT_STATUS_FEEDBACK' THEN
        CALL DSB_HMI_GET_INPUT_STATUS_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_XY_SLIPPAGE_FEEDBACK' THEN
        CALL DSB_HMI_GET_XY_SLIPPAGE_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_BATTERY_STATUS_FEEDBACK' THEN
        CALL DSB_HMI_GET_BATTERY_STATUS_DISPLAY(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_BARCODE_CODE_PRESENT_FEEDBACK' THEN
        CALL DSB_HMI_GET_BARCODE_CODE_PRESENT_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSEIF p_feedback_name = 'BOT_NUMERIC_DATA_FEEDBACK' THEN
        CALL DSB_HMI_GET_NUMERIC_DATA_BY_IDENTTIFIER(p_bot_id, Identifier);

    ELSEIF p_feedback_name = 'BOT_LIFTING_SLIDER_FEEDBACK' THEN
        CALL DSB_HMI_GET_LIFTING_SLIDER_FEEDBACK(p_bot_id, Identifier);

    ELSEIF p_feedback_name = 'BOT_ALARMS_HISTORY' THEN
        CALL DSB_BOT_ALARMS_HISTORY_BY_BOT_ID(p_bot_id, IdentifierType);

    ELSEIF p_feedback_name = 'BOT_POWER_SAVING_FEEDBACK' THEN
        CALL DSB_BOT_POWER_SAVING_MODE_FEEDBACK_BY_BOT_ID(p_bot_id);

    ELSE
        SELECT 0 AS Success, 'FeedbackName not matched' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_GET_WAVE_TYPE_BY_WAVE_ID_SP` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_GET_WAVE_TYPE_BY_WAVE_ID_SP` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_GET_WAVE_TYPE_BY_WAVE_ID_SP`(IN WaveId VARCHAR(255))
BEGIN
    DECLARE WaveType VARCHAR(100);
    DECLARE Success INT DEFAULT 0; 
    DECLARE Result VARCHAR(255) DEFAULT 'Wave Id exists'; 
    
    
    SET WaveType = DSB_GLOBAL_GET_WAVE_TYPE_BY_WAVE_ID(WaveId);
    
    
    IF WaveType IS NOT NULL THEN
        SET Success = 1;
    ELSE
        SET Success = 0;
        SET WaveType = 'Wave Type not found'; 
        SET Result = 'Wave Id not exists';
    END IF;
    
    
    SELECT Success, Result, WaveType;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_MAINTENANCE_TASK_MASTER_UPDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_MAINTENANCE_TASK_MASTER_UPDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_MAINTENANCE_TASK_MASTER_UPDATE`(
    IN Parameters JSON 
)
BEGIN
    
    DECLARE p_maintenance_task_id INT;
    DECLARE p_maintenance_id INT;
    DECLARE p_column_name VARCHAR(100);
    DECLARE p_column_value VARCHAR(100);
    
    
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255) DEFAULT 'Success';
    
    SET p_maintenance_task_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.maintenance_task_id')) AS UNSIGNED);
    SET p_maintenance_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.maintenance_id')) AS UNSIGNED);
    SET p_column_name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.column_name'));
    SET p_column_value = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.column_value'));
    
    IF (p_maintenance_task_id = 0 AND p_maintenance_id = 0) THEN
        UPDATE maintenance_task_master 
        SET MAINTENANCE_POINT_BARCODE_SCANNED = 0;
    ELSE
        
        IF EXISTS (
            SELECT 1
            FROM maintenance_task_master
            WHERE MAINTENANCE_TASK_ID = p_maintenance_task_id AND MAINTENANCE_ID = p_maintenance_id
        ) THEN
            
            IF p_column_name = 'MAINTENANCE_POINT_BARCODE_SCANNED' THEN
                CALL DSB_MTM_MPBS_UPDATE_BY_MAINTENANCE_ID(
                    JSON_OBJECT(
                        'maintenance_task_id', p_maintenance_task_id,
                        'maintenance_id', p_maintenance_id,
                        'column_value', CAST(p_column_value AS UNSIGNED)
                    )
                );
            ELSEIF p_column_name = 'IS_MP_BOT_HEALTHY' THEN
                CALL DSB_MTM_IMPBH_UPDATE_BY_MAINTENANCE_ID(
                    JSON_OBJECT(
                        'maintenance_task_id', p_maintenance_task_id,
                        'maintenance_id', p_maintenance_id,
                        'column_value', CAST(p_column_value AS UNSIGNED)
                    )
                );
            ELSE
                SET Success = 0;
                SET Result = 'ColumnName Not Found';
            END IF;
        ELSE
            SET Success = 0;
            SET Result = 'Maintenance ID Not Found';
        END IF;
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_SCRM_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_SCRM_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_SCRM_FEEDBACK`()
BEGIN
  
  WITH base AS (
    SELECT
      srm.LOCATION_ID,
      srm.TYPE,
      srm.BOT_ID,
      srm.DESTINATION_ID,
      srm.IS_BUFFER,
      srm.PARENT_LOCATION_ID,
      srm.INSERTED_TIMESTAMP,
      srm.UPDATED_TIMESTAMP,
      lm.X AS RESERVED_X,
      lm.Y AS RESERVED_Y,
      lm.AISLE_NUMBER,
      lm.TOWER_NUMBER,
      
      (srm.TYPE LIKE 'TOWER_%') AS is_tower,
      CASE
        WHEN srm.INSERTED_TIMESTAMP IS NULL THEN NULL
        ELSE TIMESTAMPDIFF(SECOND, srm.INSERTED_TIMESTAMP, NOW())
      END AS age_sec
    FROM subcontroller_reservations_master AS srm
    LEFT JOIN location_master AS lm
      ON lm.LOCATION_ID = srm.LOCATION_ID
  )
  SELECT
    LOCATION_ID,
    TYPE,
    BOT_ID,
    DESTINATION_ID,
    IS_BUFFER,
    PARENT_LOCATION_ID,
    INSERTED_TIMESTAMP,
    UPDATED_TIMESTAMP,
    RESERVED_X,
    RESERVED_Y,
    CASE WHEN is_tower AND age_sec > 180 THEN CONCAT(AISLE_NUMBER, ', ', TOWER_NUMBER) ELSE NULL END AS RESERVED_TOWER_AISLE_TOWER,
    CASE WHEN is_tower AND age_sec > 180 THEN CONCAT(age_sec, ' Secs') ELSE NULL END AS RESERVED_TOWER_SINCE
  FROM base
  ORDER BY UPDATED_TIMESTAMP DESC;   
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_STATIONS_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_STATIONS_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_STATIONS_FEEDBACK`()
BEGIN
    SELECT
        hsm.STATUS AS STATION_STATUS,
        hsm.STATION_ID,
        hsm.STATION_ALIAS_NAME,
        hsm.STATION_TYPE,
        hsm.PALLET_SCAN_BARCODE,
        hsm.MAX_BUFFER_COUNT AS STATION_BUFFER_COUNT,
        hdm.LAST_MESSAGE,
        hdm.NOREAD_MESSAGE,
        lm_sput.X AS STATION_PUT_X,
        lm_sput.Y AS STATION_PUT_Y,
        
        hcm.PUT_REQUEST,
        hcm.PUT_CONFIRM,
        lm_spick.X AS STATION_PICK_X,
        lm_spick.Y AS STATION_PICK_Y,
        
        hcm.BIN_ON_PICK_BOOL AS PICK_REQUEST,
        CASE 
            WHEN lm_spick.X > 0 AND lm_sput.X > 0 THEN 1
            ELSE 0
        END AS DUAL_SIDE_STATION,
        hsm.WAVE_ID,
        wm.WAVE_TYPE,
        wm.WAVE_STATUS AS WM_WAVE_STATUS,
        CASE 
            WHEN wm.IS_CANCELLED = 1 THEN 'SUSPENSION_INITIATED'
            WHEN wm.IS_STOPPED = 1 THEN 'COMPLETION_INITIATED'
            ELSE hsm.WAVE_STATUS
        END AS HSM_WAVE_STATUS,
        wm.LEFT_OVER_STATUS,
        wm.START_TIMESTAMP,
        wm.STARTED_BY,
        wm.IS_CANCELLED,
        wm.CANCELLED_TIMESTAMP,
        wm.CANCELLED_BY,
        wm.IS_STOPPED,
        wm.COMPLETED_TIMESTAMP,
        wm.COMPLETED_BY,
        wm.INSERTED_TIMESTAMP,
        wm.INSERTED_BY,
	    CASE 
		WHEN hsm.STATUS = 'DISABLED' OR hsm.WAVE_STATUS IN ('NO_WAVE', 'WAVE_LIVE') THEN 1
		ELSE 0 
	    END AS isRunDisabled,
	    CASE 
		WHEN hsm.STATUS = 'DISABLED' OR hsm.WAVE_STATUS IN ('NO_WAVE', 'WAITING_OPERATOR') OR wrsm.BREAK_STATUS = 1 THEN 1
		ELSE 0 
	    END AS isLiveStatusDisabled,
	    CASE
		WHEN hsm.STATUS = 'DISABLED' OR hsm.WAVE_STATUS IN ('NO_WAVE', 'WAITING_OPERATOR') OR wrsm.BREAK_STATUS = 0 THEN 1
		ELSe 0
	    END AS isResumeStationDisabled
    FROM hw_station_master AS hsm
    LEFT JOIN hw_display_master  AS hdm ON hdm.PARENT_ID = hsm.STATION_ID
    LEFT JOIN hw_conveyor_master AS hcm ON hcm.PARENT_ID = hsm.STATION_ID
    LEFT JOIN location_master AS lm_spick ON lm_spick.LOCATION_ID = hsm.LOCATION_ID
    LEFT JOIN location_master AS lm_sput  ON lm_sput.LOCATION_ID = hsm.STATION_ENTRY_LOCATION_ID
    LEFT JOIN wave_master wm ON wm.WAVE_ID = hsm.WAVE_ID
    LEFT JOIN wave_station_rule_mapping wrsm ON wrsm.STATION_ID = hsm.STATION_ID
    ORDER BY hsm.STATION_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_STATIONS_OVERVIEW` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_STATIONS_OVERVIEW` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_STATIONS_OVERVIEW`()
BEGIN
    SELECT
        hsm.STATUS AS STATION_STATUS,
        hsm.STATION_ID,
        hsm.STATION_ALIAS_NAME,
        hsm.STATION_TYPE,
        hsm.PALLET_SCAN_BARCODE,
        hsm.MAX_BUFFER_COUNT AS STATION_BUFFER_COUNT,
        
        
        lm_sput.X AS STATION_PUT_X,
        lm_sput.Y AS STATION_PUT_Y,
        lm_sput.Z AS STATION_PUT_Z,
        
        
        lm_spick.X AS STATION_PICK_X,
        lm_spick.Y AS STATION_PICK_Y,
        lm_spick.Z AS STATION_PICK_Z,
        
        
         CASE 
            WHEN lm_spick.X > 0 AND lm_sput.X > 0 THEN 1
            ELSE 0
        END AS DUAL_SIDE_STATION
        
    FROM hw_station_master AS hsm
        
    
    LEFT JOIN location_master AS lm_sput  
        ON lm_sput.LOCATION_ID = hsm.STATION_ENTRY_LOCATION_ID
    
    LEFT JOIN location_master AS lm_spick 
        ON lm_spick.LOCATION_ID = hsm.LOCATION_ID
    
    
    ORDER BY hsm.STATION_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GLOBAL_TBD_AND_TBDF_UPDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GLOBAL_TBD_AND_TBDF_UPDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GLOBAL_TBD_AND_TBDF_UPDATE`(
    IN Parameters JSON 
)
BEGIN
    
    DECLARE BotId VARCHAR(255);
    DECLARE UpdateFor VARCHAR(255);
    DECLARE IdentifierBit INT DEFAULT 0; 
    DECLARE InnerParams JSON;
    
    SET BotId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.BotId'));
    SET UpdateFor = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.UpdateFor'));
    SET IdentifierBit = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Bit'));
    
    IF UpdateFor = 'SET_EMERGENCY_STOP_BY_BOT_ID' THEN
        
        SET InnerParams = JSON_OBJECT('botId', BotId, 'EmergencyStopBit', IdentifierBit);
        CALL DSB_BOT_EMERGENCY_STOP_SET_BY_BOT_ID(InnerParams);
    ELSEIF UpdateFor = 'SET_RESET_BY_BOT_ID' THEN
        CALL DSB_BOT_RESET_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SET_HOME_BY_BOT_ID' THEN
        CALL DSB_BOT_HOME_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SET_HOME_REVERSE_BY_BOT_ID' THEN
        CALL DSB_BOT_HOME_REVERSE_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SET_AUTO_START_BY_BOT_ID' THEN
        CALL DSB_BOT_AUTO_START_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SET_AUTO_STOP_BY_BOT_ID' THEN
        CALL DSB_BOT_AUTO_STOP_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SET_HOME_CALL_BY_BOT_ID' THEN
        CALL DSB_BOT_HOME_CALL_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SET_AUTO_CALIBRATION_BY_BOT_ID' THEN
	SET InnerParams = JSON_OBJECT('bot_id', BotId, 'bit', IdentifierBit);
        CALL DSB_BOT_AUTO_CALIBRATION_BY_BOT_ID(InnerParams);
    ELSEIF UpdateFor = 'SET_RECOVERY_BY_BOT_ID' THEN
        CALL DSB_BOT_RECOVERY_UPDATE_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SET_NON_RECOVERY_BY_BOT_ID' THEN
        CALL DSB_BOT_NON_RECOVERY_UPDATE_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SET_BOT_BIN_STATUS_BY_BOT_ID' THEN
	SET InnerParams = JSON_OBJECT('botId', BotId, 'identifierBit', IdentifierBit);
        CALL DSB_BOT_BIN_STATUS_UPDATE_BY_BOT_ID(InnerParams);
    ELSEIF UpdateFor = 'SET_BOT_LOAD_STATUS_RECOVERY_BY_BOT_ID' THEN
        CALL DSB_BOT_BIN_STATUS_RECOVERY_UPDATE_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SET_BOT_LOAD_STATUS_NON_RECOVERY_BY_BOT_ID' THEN
        CALL DSB_BOT_BIN_STATUS_NON_RECOVERY_UPDATE_BY_BOT_ID(BotId);
    ELSEIF UpdateFor = 'SWITCH_TO_MANUAL_PACKET' THEN
        SET InnerParams = JSON_OBJECT('botId', BotId, 'manualModeBit', IdentifierBit);
        CALL DSB_SWITCH_TO_MANUAL_MODE_BY_BOT_ID(InnerParams);
    ELSEIF UpdateFor = 'SWITCH_TO_POWER_SAVING_MODE' THEN
	SET InnerParams = JSON_OBJECT('botId', BotId, 'identifierBit', IdentifierBit);
        CALL DSB_BOT_POWER_SAVING_MODE_UPDATE_BY_BOT_ID(InnerParams);
    ELSE
	SELECT 0 AS Success, 'UpdateFor not matched' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GRID_BLOCK_UNBLOCK_LOCATION_BY_AISLE_NUMBER_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GRID_BLOCK_UNBLOCK_LOCATION_BY_AISLE_NUMBER_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GRID_BLOCK_UNBLOCK_LOCATION_BY_AISLE_NUMBER_GET_ALL`(
    IN Parameters TEXT
)
BEGIN
    
    DROP TEMPORARY TABLE IF EXISTS temp_list;
    CREATE TEMPORARY TABLE temp_list (item VARCHAR(10));
    
    WHILE LOCATE(',', Parameters) > 0 DO
        INSERT INTO temp_list (item)
        VALUES (TRIM(SUBSTRING_INDEX(Parameters, ',', 1)));
        SET Parameters = SUBSTRING(Parameters, LOCATE(',', Parameters) + 1);
    END WHILE;
    
    IF LENGTH(TRIM(Parameters)) > 0 THEN
        INSERT INTO temp_list (item)
        VALUES (TRIM(Parameters));
    END IF;
    
    SELECT
        lm.X, 
        lm.Y, 
        lm.Z, 
        lm.TOWER_NUMBER
    FROM 
        location_master lm
    INNER JOIN 
        temp_list t ON lm.AISLE_NUMBER = t.item
    WHERE 
        lm.Z = 1
    GROUP BY
	lm.TOWER_NUMBER
    ORDER BY 
        lm.X;
    
    DROP TEMPORARY TABLE IF EXISTS temp_list;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GRID_BLOCK_UNBLOCK_LOCATION_VIEW_UPDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GRID_BLOCK_UNBLOCK_LOCATION_VIEW_UPDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GRID_BLOCK_UNBLOCK_LOCATION_VIEW_UPDATE`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_view_update       VARCHAR(100);
    DECLARE p_block_unblock     VARCHAR(100);
    DECLARE p_updated_by        VARCHAR(100);
    DECLARE v_aisle_count       INT DEFAULT 0;
    DECLARE v_tower_count       INT DEFAULT 0;
    DECLARE v_level_count       INT DEFAULT 0;
    DECLARE v_tower_side_count  INT DEFAULT 0;
    DECLARE v_location_id_count INT DEFAULT 0;
    DECLARE Success             INT DEFAULT 1;
    DECLARE Result              VARCHAR(255);
    DECLARE err_msg             TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 err_msg = MESSAGE_TEXT;
        SELECT 0 AS Success, CONCAT('SQL Error: ', err_msg) AS Result;
    END;
    
    SET p_updated_by        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    SET p_block_unblock     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.block_unblock'));
    SET p_view_update       = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.view_update'));
    SET v_aisle_count       = JSON_LENGTH(JSON_EXTRACT(Parameters, '$.aisles'));
    SET v_tower_count       = JSON_LENGTH(JSON_EXTRACT(Parameters, '$.towers'));
    SET v_level_count       = JSON_LENGTH(JSON_EXTRACT(Parameters, '$.levels'));
    SET v_tower_side_count  = JSON_LENGTH(JSON_EXTRACT(Parameters, '$.tower_side'));
    SET v_location_id_count = JSON_LENGTH(JSON_EXTRACT(Parameters, '$.location_ids'));
    
    DROP TEMPORARY TABLE IF EXISTS temp_aisles;
    CREATE TEMPORARY TABLE temp_aisles (aisle VARCHAR(10));
    INSERT INTO temp_aisles
    SELECT TRIM(JSON_UNQUOTE(j.value))
    FROM JSON_TABLE(JSON_EXTRACT(Parameters, '$.aisles'), '$[*]'
        COLUMNS (VALUE JSON PATH '$')) AS j;
    
    DROP TEMPORARY TABLE IF EXISTS temp_towers;
    CREATE TEMPORARY TABLE temp_towers (tower VARCHAR(10));
    INSERT INTO temp_towers
    SELECT TRIM(JSON_UNQUOTE(j.value))
    FROM JSON_TABLE(JSON_EXTRACT(Parameters, '$.towers'), '$[*]'
        COLUMNS (VALUE JSON PATH '$')) AS j;
    
    DROP TEMPORARY TABLE IF EXISTS temp_aisle_tower_mapping;
    CREATE TEMPORARY TABLE temp_aisle_tower_mapping AS
    SELECT DISTINCT
	    lm.AISLE_NUMBER,
	    lm_ai.LOCATION_ID AS AISLE_ID,
	    lm.TOWER_NUMBER,
	    lm_t.LOCATION_ID AS TOWER_ID
	FROM location_master lm
	JOIN location_master lm_ai 
	    ON lm_ai.TYPE = 'AISLE_ENTRY' 
	    AND lm_ai.AISLE_NUMBER = lm.AISLE_NUMBER
	LEFT JOIN location_master lm_t 
	    ON lm_t.X = lm.X AND lm_t.Y = lm_ai.Y AND lm_t.Z = 0
	WHERE 
	    lm.AISLE_NUMBER IN (SELECT aisle FROM temp_aisles) 
	    AND lm.TOWER_NUMBER IS NOT NULL 
	    AND lm.Z = 0
	    AND lm.TYPE LIKE '%TOWER_ENTRY%';
    
    DROP TEMPORARY TABLE IF EXISTS temp_levels;
    CREATE TEMPORARY TABLE temp_levels (LEVEL INT);
    INSERT INTO temp_levels
    SELECT CAST(JSON_UNQUOTE(j.value) AS UNSIGNED)
    FROM JSON_TABLE(JSON_EXTRACT(Parameters, '$.levels'), '$[*]'
        COLUMNS (VALUE JSON PATH '$')) AS j;
    
    DROP TEMPORARY TABLE IF EXISTS temp_tower_sides;
    CREATE TEMPORARY TABLE temp_tower_sides (tower_side VARCHAR(10));
    INSERT INTO temp_tower_sides
    SELECT TRIM(JSON_UNQUOTE(j.value))
    FROM JSON_TABLE(JSON_EXTRACT(Parameters, '$.tower_side'), '$[*]'
        COLUMNS (VALUE JSON PATH '$')) AS j;
    
    DROP TEMPORARY TABLE IF EXISTS temp_locations;
    CREATE TEMPORARY TABLE temp_locations (location INT);
    INSERT INTO temp_locations
    SELECT CAST(JSON_UNQUOTE(j.value) AS UNSIGNED)
    FROM JSON_TABLE(JSON_EXTRACT(Parameters, '$.location_ids'), '$[*]'
        COLUMNS (VALUE JSON PATH '$')) AS j;
        
    
	IF p_view_update = 'view' THEN
	    IF v_aisle_count > 0 AND v_tower_count > 0 AND v_level_count > 0 AND v_tower_side_count > 0 THEN
		IF v_tower_side_count = 2 THEN
		    SELECT LOCATION_ID, X, Y, MIN(Z) AS Z, TYPE, AISLE_NUMBER, TOWER_NUMBER
		    FROM location_master
		    WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
		      AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
		      AND Z IN (0, 1)
		      AND TYPE NOT LIKE 'TOWER_%'
		    GROUP BY X, Y
		    ORDER BY X, Y, Z;
		ELSE
		    IF (SELECT tower_side FROM temp_tower_sides LIMIT 1) = 'LEFT' THEN
			SELECT MIN(Y) INTO @selectedY
			FROM location_master
			WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
			  AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
			  AND TYPE NOT LIKE 'TOWER_%';
		    ELSE
			SELECT MAX(Y) INTO @selectedY
			FROM location_master
			WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
			  AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
			  AND TYPE NOT LIKE 'TOWER_%';
		    END IF;
		    SELECT LOCATION_ID, X, Y, MIN(Z) AS Z, TYPE, AISLE_NUMBER, TOWER_NUMBER
		    FROM location_master
		    WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
		      AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
		      AND Z IN (0, 1)
		      AND TYPE NOT LIKE 'TOWER_%'
		      AND Y = @selectedY
		    GROUP BY X, Y
		    ORDER BY X, Y, Z;
		END IF;
	    ELSEIF v_aisle_count > 0 AND v_tower_count > 0 AND v_level_count > 0 THEN
		SELECT LOCATION_ID, X, Y, MIN(Z) AS Z, TYPE, AISLE_NUMBER, TOWER_NUMBER
		FROM location_master
		WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
		  AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
		  AND Z IN (0, 1)
		  AND TYPE NOT LIKE 'TOWER_%'
		GROUP BY X, Y
		ORDER BY X, Y, Z;
	    ELSEIF v_aisle_count > 0 AND v_tower_count > 0 THEN
		SELECT LOCATION_ID, X, Y, MIN(Z) AS Z, TYPE, AISLE_NUMBER, TOWER_NUMBER
		FROM location_master
		WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
		  AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
		  AND Z IN (0, 1)
		  
		GROUP BY X, Y
		ORDER BY X, Y, Z;
	    ELSEIF v_aisle_count > 0 THEN
		SELECT LOCATION_ID, X, Y, MIN(Z) AS Z, TYPE, AISLE_NUMBER, TOWER_NUMBER
		FROM location_master
		WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
		  AND Z IN (0, 1)
		GROUP BY X, Y
		ORDER BY X, Y, Z;
	    END IF;
	    SET Success = 1;
	    SET Result = 'View query executed successfully.';
	ELSEIF p_view_update = 'update' THEN
	    START TRANSACTION;
		
		IF v_location_id_count > 0 AND p_block_unblock = 'UNBLOCK' THEN
		    
		    INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
		    SELECT LOCATION_ID, 'UNBLOCK', TYPE, AISLE_ID, TOWER_ID, p_updated_by
		    FROM location_block_master
		    WHERE LOCATION_ID IN (SELECT location FROM temp_locations);
		    
		    DELETE FROM location_block_master
		    WHERE LOCATION_ID IN (SELECT location FROM temp_locations);
		ELSE
		    
		    IF v_aisle_count > 0 AND v_tower_count > 0 AND v_level_count > 0 AND v_tower_side_count > 0 THEN
			IF p_block_unblock = 'BLOCK' THEN
			    IF v_tower_side_count = 2 THEN
				
				INSERT INTO location_block_master (LOCATION_ID, TYPE, AISLE_ID, TOWER_ID, BLOCK_BY)
				SELECT 
				    lm.LOCATION_ID,
				    lm.TYPE,
				    tatm.AISLE_ID,
				    CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				    p_updated_by
				FROM location_master lm
				JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
				JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
				JOIN temp_levels tl ON lm.Z = tl.level
				LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
				WHERE lm.TYPE = 'STORAGE_LOCATION'
				ON DUPLICATE KEY UPDATE BLOCK_BY = VALUES(BLOCK_BY);
				
				INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
				SELECT 
				    lm.LOCATION_ID,
				    'BLOCK',
				    lm.TYPE,
				    tatm.AISLE_ID,
				    CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				    p_updated_by
				FROM location_master lm
				JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
				JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
				JOIN temp_levels tl ON lm.Z = tl.level
				LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
				WHERE lm.TYPE = 'STORAGE_LOCATION';
			    ELSE
				
				IF (SELECT tower_side FROM temp_tower_sides LIMIT 1) = 'LEFT' THEN
				    SELECT MIN(Y) INTO @selectedY
				    FROM location_master
				    WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
				      AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
				      AND TYPE NOT LIKE 'TOWER_%';
				ELSE
				    SELECT MAX(Y) INTO @selectedY
				    FROM location_master
				    WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
				      AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
				      AND TYPE NOT LIKE 'TOWER_%';
				END IF;
				
				INSERT INTO location_block_master (LOCATION_ID, TYPE, AISLE_ID, TOWER_ID, BLOCK_BY)
				SELECT 
				    lm.LOCATION_ID,
				    lm.TYPE,
				    tatm.AISLE_ID,
				    CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				    p_updated_by
				FROM location_master lm
				JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
				JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
				JOIN temp_levels tl ON lm.Z = tl.level
				LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
				WHERE lm.Y = @selectedY AND lm.TYPE = 'STORAGE_LOCATION'
				ON DUPLICATE KEY UPDATE BLOCK_BY = VALUES(BLOCK_BY);
				
				INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
				SELECT 
				    lm.LOCATION_ID,
				    'BLOCK',
				    lm.TYPE,
				    tatm.AISLE_ID,
				    CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				    p_updated_by
				FROM location_master lm
				JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
				JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
				JOIN temp_levels tl ON lm.Z = tl.level
				LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
				WHERE lm.Y = @selectedY AND lm.TYPE = 'STORAGE_LOCATION';
			    END IF;
			ELSEIF p_block_unblock = 'UNBLOCK' THEN
			    IF v_tower_side_count = 2 THEN
				
				INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
				SELECT 
				    lm.LOCATION_ID,
				    'UNBLOCK',
				    lm.TYPE,
				    tatm.AISLE_ID,
				    CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				    p_updated_by
				FROM location_master lm
				JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
				JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
				JOIN temp_levels tl ON lm.Z = tl.level
				LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
				WHERE lm.TYPE = 'STORAGE_LOCATION';
				DELETE lbm
				FROM location_block_master lbm
				JOIN location_master lm ON lbm.LOCATION_ID = lm.LOCATION_ID
				JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
				JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
				JOIN temp_levels tl ON lm.Z = tl.level
				WHERE lbm.TYPE = 'STORAGE_LOCATION';
			    ELSE
				IF (SELECT tower_side FROM temp_tower_sides LIMIT 1) = 'LEFT' THEN
				    SELECT MIN(Y) INTO @selectedY
				    FROM location_master
				    WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
				      AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
				      AND TYPE NOT LIKE 'TOWER_%';
				ELSE
				    SELECT MAX(Y) INTO @selectedY
				    FROM location_master
				    WHERE AISLE_NUMBER IN (SELECT aisle FROM temp_aisles)
				      AND TOWER_NUMBER IN (SELECT tower FROM temp_towers)
				      AND TYPE NOT LIKE 'TOWER_%';
				END IF;
				INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
				SELECT 
				    lm.LOCATION_ID,
				    'UNBLOCK',
				    lm.TYPE,
				    tatm.AISLE_ID,
				    CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				    p_updated_by
				FROM location_master lm
				JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
				JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
				JOIN temp_levels tl ON lm.Z = tl.level
				LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
				WHERE lm.Y = @selectedY AND lm.TYPE = 'STORAGE_LOCATION';
				DELETE lbm
				FROM location_block_master lbm
				JOIN location_master lm ON lbm.LOCATION_ID = lm.LOCATION_ID
				JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
				JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
				JOIN temp_levels tl ON lm.Z = tl.level
				WHERE lm.Y = @selectedY AND lbm.TYPE = 'STORAGE_LOCATION';
			    END IF;
			END IF;
		    
		    ELSEIF v_aisle_count > 0 AND v_tower_count > 0 AND v_level_count > 0 THEN
			IF p_block_unblock = 'BLOCK' THEN
			    INSERT INTO location_block_master (LOCATION_ID, TYPE, AISLE_ID, TOWER_ID, BLOCK_BY)
			    SELECT 
				lm.LOCATION_ID,
				lm.TYPE,
				tatm.AISLE_ID,
				CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				p_updated_by
			    FROM location_master lm
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
			    JOIN temp_levels tl ON lm.Z = tl.level
			    LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
			    WHERE lm.TYPE = 'STORAGE_LOCATION'
			    ON DUPLICATE KEY UPDATE BLOCK_BY = VALUES(BLOCK_BY);
			    INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
			    SELECT 
				lm.LOCATION_ID,
				'BLOCK',
				lm.TYPE,
				tatm.AISLE_ID,
				CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				p_updated_by
			    FROM location_master lm
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
			    JOIN temp_levels tl ON lm.Z = tl.level
			    LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
			    WHERE lm.TYPE = 'STORAGE_LOCATION';
			ELSEIF p_block_unblock = 'UNBLOCK' THEN
			    INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
			    SELECT 
				lm.LOCATION_ID,
				'UNBLOCK',
				lm.TYPE,
				tatm.AISLE_ID,
				CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				p_updated_by
			    FROM location_master lm
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
			    JOIN temp_levels tl ON lm.Z = tl.level
			    LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
			    WHERE lm.TYPE = 'STORAGE_LOCATION';
			    DELETE lbm
			    FROM location_block_master lbm
			    JOIN location_master lm ON lbm.LOCATION_ID = lm.LOCATION_ID
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
			    JOIN temp_levels tl ON lm.Z = tl.level
			    WHERE lbm.TYPE = 'STORAGE_LOCATION';
			END IF;
		    
		    ELSEIF v_aisle_count > 0 AND v_tower_count > 0 THEN
			IF p_block_unblock = 'BLOCK' THEN
			    INSERT INTO location_block_master (LOCATION_ID, TYPE, AISLE_ID, TOWER_ID, BLOCK_BY)
			    SELECT 
				lm.LOCATION_ID,
				lm.TYPE,
				tatm.AISLE_ID,
				CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				p_updated_by
			    FROM location_master lm
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
			    LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER
			    ON DUPLICATE KEY UPDATE BLOCK_BY = VALUES(BLOCK_BY);
			    INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
			    SELECT 
				lm.LOCATION_ID,
				'BLOCK',
				lm.TYPE,
				tatm.AISLE_ID,
				CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				p_updated_by
			    FROM location_master lm
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
			    LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER;
			ELSEIF p_block_unblock = 'UNBLOCK' THEN
			    INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
			    SELECT 
				lm.LOCATION_ID,
				'UNBLOCK',
				lm.TYPE,
				tatm.AISLE_ID,
				CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				p_updated_by
			    FROM location_master lm
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower
			    LEFT JOIN temp_aisle_tower_mapping tatm ON lm.TOWER_NUMBER = tatm.TOWER_NUMBER AND lm.AISLE_NUMBER = tatm.AISLE_NUMBER;
			    DELETE lbm
			    FROM location_block_master lbm
			    JOIN location_master lm ON lbm.LOCATION_ID = lm.LOCATION_ID
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    JOIN temp_towers tt ON lm.TOWER_NUMBER = tt.tower;
			END IF;
		    
		    ELSEIF v_aisle_count > 0 THEN
			IF p_block_unblock = 'BLOCK' THEN
			    INSERT INTO location_block_master (LOCATION_ID, TYPE, AISLE_ID, TOWER_ID, BLOCK_BY)
			    SELECT 
				lm.LOCATION_ID,
				lm.TYPE,
				tatm.AISLE_ID,
				CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				p_updated_by
			    FROM location_master lm
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    LEFT JOIN temp_aisle_tower_mapping tatm ON lm.AISLE_NUMBER = tatm.AISLE_NUMBER
			    AND lm.TOWER_NUMBER = tatm.TOWER_NUMBER
			    ON DUPLICATE KEY UPDATE BLOCK_BY = VALUES(BLOCK_BY);
			    INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
			    SELECT 
				lm.LOCATION_ID,
				'BLOCK',
				lm.TYPE,
				tatm.AISLE_ID,
				CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				p_updated_by
			    FROM location_master lm
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    LEFT JOIN temp_aisle_tower_mapping tatm ON lm.AISLE_NUMBER = tatm.AISLE_NUMBER AND lm.TOWER_NUMBER = tatm.TOWER_NUMBER;
			ELSEIF p_block_unblock = 'UNBLOCK' THEN
			    INSERT INTO dashboard_log_location_block_master (LOCATION_ID, BLOCK_STATUS, TYPE, AISLE_ID, TOWER_ID, UPDATED_BY)
			    SELECT 
				lm.LOCATION_ID,
				'UNBLOCK',
				lm.TYPE,
				tatm.AISLE_ID,
				CASE WHEN lm.TYPE = 'STORAGE_LOCATION' THEN tatm.TOWER_ID ELSE NULL END,
				p_updated_by
			    FROM location_master lm
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle
			    LEFT JOIN temp_aisle_tower_mapping tatm ON lm.AISLE_NUMBER = tatm.AISLE_NUMBER AND lm.TOWER_NUMBER = tatm.TOWER_NUMBER;
			    DELETE lbm
			    FROM location_block_master lbm
			    JOIN location_master lm ON lbm.LOCATION_ID = lm.LOCATION_ID
			    JOIN temp_aisles ta ON lm.AISLE_NUMBER = ta.aisle;
			END IF;
		    END IF;
		END IF;
		COMMIT;
		
	SET Success = 1;
        SET Result = CONCAT('Update completed successfully for ', p_block_unblock, ' operation.');
    ELSE
        SET Success = 0;
        SET Result = 'View/Update not passed.';
    END IF;
    
    SELECT Success, Result;
    
    DROP TEMPORARY TABLE IF EXISTS temp_aisles;
    DROP TEMPORARY TABLE IF EXISTS temp_towers;
    DROP TEMPORARY TABLE IF EXISTS temp_aisle_tower_mapping;
    DROP TEMPORARY TABLE IF EXISTS temp_levels;
    DROP TEMPORARY TABLE IF EXISTS temp_locations;
    DROP TEMPORARY TABLE IF EXISTS temp_tower_sides;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GRID_GET_LAYOUT_COORDINATES` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GRID_GET_LAYOUT_COORDINATES` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GRID_GET_LAYOUT_COORDINATES`()
BEGIN
  WITH
  blocked_coords AS (
      SELECT DISTINCT lm.X, lm.Y
      FROM location_block_master lbm
      JOIN location_master lm
        ON lm.LOCATION_ID = lbm.LOCATION_ID
  ),
  y_storage AS (
      SELECT DISTINCT Y
      FROM location_master
      WHERE TYPE = 'STORAGE_LOCATION'
  ),
  y_special AS (
      SELECT DISTINCT Y
      FROM location_master
      WHERE TYPE IN ('STATION_ENTRY','STATION_HOME','STATION_BUFFER_JUNCTION','HOME')
  ),
  storage_min_ids AS (
      SELECT LOCATION_ID
      FROM (
          SELECT
              lm.LOCATION_ID,
              ROW_NUMBER() OVER (
                  PARTITION BY lm.X, lm.Y
                  ORDER BY lm.Z
              ) AS rn
          FROM location_master lm
          WHERE lm.TYPE = 'STORAGE_LOCATION'
      ) t
      WHERE t.rn = 1
  ),
  candidate_ids AS (
      
      SELECT lm.LOCATION_ID
      FROM location_master lm
      WHERE lm.IS_BARCODE = 1
        AND (lm.XP <> 0 OR lm.XN <> 0 OR lm.YP <> 0 OR lm.YN <> 0)
      UNION ALL
      
      SELECT LOCATION_ID
      FROM storage_min_ids
      UNION ALL
      
      SELECT lm.LOCATION_ID
      FROM location_master lm
      JOIN y_storage ys ON ys.Y = lm.Y
      WHERE lm.TYPE = 'PATH'
        AND (lm.XP <> 0 OR lm.XN <> 0 OR lm.YP <> 0 OR lm.YN <> 0)
      UNION ALL
      
      SELECT lm.LOCATION_ID
      FROM location_master lm
      JOIN y_special ys ON ys.Y = lm.Y
      WHERE lm.TYPE = 'PATH'
        AND (lm.YP = 1 OR lm.YN = 1)
  ),
  final_ids AS (
      SELECT DISTINCT LOCATION_ID
      FROM candidate_ids
  )
  SELECT
      lm.LOCATION_ID,
      lm.X,
      lm.Y,
      lm.Z,
      CONCAT(lm.X, ', ', lm.Y, ', ', lm.Z) AS `X_Y_Z`,
      lm.XP,
      lm.XN,
      lm.YP,
      lm.YN,
      lm.ZP,
      lm.ZN,
      CONCAT(lm.XP, ', ', lm.XN, ', ', lm.YP, ', ', lm.YN) AS `XP_XN_YP_YN`,
      lm.TYPE,
      lm.XP_PROPERTY,
      lm.XN_PROPERTY,
      lm.YP_PROPERTY,
      lm.YN_PROPERTY,
      CONCAT(lm.XP_PROPERTY, ', ', lm.XN_PROPERTY, ', ', lm.YP_PROPERTY, ', ', lm.YN_PROPERTY) AS `PROPERTY_XP_XN_YP_YN`,
      lm.IS_BARCODE,
      lm.IS_EDGE,
      lm.AISLE_NUMBER,
      lm.TOWER_NUMBER,
      CASE WHEN bc.X IS NOT NULL THEN 1 ELSE 0 END AS BLOCK_STATUS,
      0 AS BLOCK_STATUS_TEMPORARY
  FROM final_ids f
  JOIN location_master lm
    ON lm.LOCATION_ID = f.LOCATION_ID
  LEFT JOIN blocked_coords bc
    ON bc.X = lm.X AND bc.Y = lm.Y
  ORDER BY lm.X, lm.Y, lm.Z;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GRID_GET_POINTS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GRID_GET_POINTS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GRID_GET_POINTS`()
BEGIN
  
  SELECT DISTINCT
         d.`TYPE`         AS `TYPE`,
         d.`ABBREVIATION` AS `ABBREVIATION`,
         d.`BG_COLOR`     AS `BG_COLOR`,
         'DGPM'           AS `SOURCE`
  FROM   `dashboard_grid_points_master` AS d
  UNION ALL
  SELECT DISTINCT
         l.`TYPE`         AS `TYPE`,
         NULL             AS `ABBREVIATION`,
         '#FFFFFF'        AS `BG_COLOR`,
         'LM_ONLY'        AS `SOURCE`
  FROM   `location_master` AS l
  LEFT JOIN `dashboard_grid_points_master` AS d
         ON d.`TYPE` = l.`TYPE`
  WHERE  d.`TYPE` IS NULL
    AND  l.`TYPE` NOT IN (
           'TOWER_PARKING_MEDIUM',
           'TOWER_PARKING_MAX',
           'TOWER_PARKING_HIGH',
           'TOWER_PARKING_LOW',
           'STATION_PICK',
           'STATION_PUT'
         )
  ORDER BY `TYPE`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GRID_GET_Z_LEVELS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GRID_GET_Z_LEVELS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GRID_GET_Z_LEVELS`()
BEGIN
    
    SELECT DISTINCT Z 
    FROM location_master 
    WHERE TYPE = 'TOWER_UP_DOWN' 
    ORDER BY Z;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_GRID_Z_LEVEL_BY_TOWER_NUMBER_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_GRID_Z_LEVEL_BY_TOWER_NUMBER_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_GRID_Z_LEVEL_BY_TOWER_NUMBER_GET_ALL`(
    IN Parameters TEXT
)
BEGIN
    
    DROP TEMPORARY TABLE IF EXISTS temp_list;
    CREATE TEMPORARY TABLE temp_list (item VARCHAR(10));
    
    WHILE LOCATE(',', Parameters) > 0 DO
        INSERT INTO temp_list (item)
        VALUES (TRIM(SUBSTRING_INDEX(Parameters, ',', 1)));
        SET Parameters = SUBSTRING(Parameters, LOCATE(',', Parameters) + 1);
    END WHILE;
    
    IF LENGTH(TRIM(Parameters)) > 0 THEN
        INSERT INTO temp_list (item)
        VALUES (TRIM(Parameters));
    END IF;
    
    SELECT DISTINCT
        lm.Z, 
        CONCAT('LEVEL ', lm.Z) AS Z_LEVEL
    FROM 
        location_master lm
    INNER JOIN 
        temp_list t ON lm.TOWER_NUMBER = t.item
    WHERE 
        lm.TYPE = 'STORAGE_LOCATION'
    ORDER BY 
        lm.Z;
    
    DROP TEMPORARY TABLE IF EXISTS temp_list;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_ACTUATOR_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_ACTUATOR_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_ACTUATOR_FEEDBACK`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
	SELECT
            `Front Right Finger Actuator Open` AS frontRight,
            `Front Left Finger Actuator Open` AS frontLeft,
            `Rear Right Finger Actuator Open` AS rearRight,
            `Rear Left Finger Actuator Open` AS rearLeft
        FROM
            `teleoperation_bool_data_feedback`
        WHERE   bot_id = botId;
 
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_BARCODE_CODE_PRESENT_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_BARCODE_CODE_PRESENT_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_BARCODE_CODE_PRESENT_FEEDBACK_BY_BOT_ID`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
        
	SELECT `Camera Control Code Present Feedback`
	FROM
	`teleoperation_bool_data_feedback`
	WHERE bot_id = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_BARCODE_COORD_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_BARCODE_COORD_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_BARCODE_COORD_FEEDBACK_BY_BOT_ID`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    SELECT 
        'X Position' AS `Property`, `X-Axis Position of Control Code` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        'Y Position' AS `Property`, `Y-Axis Position of Control Code` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        'Angle' AS `Property`, `Angle of Control Code` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_BARCODE_JUNCTION_COORD_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_BARCODE_JUNCTION_COORD_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_BARCODE_JUNCTION_COORD_FEEDBACK_BY_BOT_ID`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    SELECT 
        'X Axis' AS `Property`, `X-Axis Co-ordinate of Control Code` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        'Y Axis' AS `Property`, `Y-Axis Co-ordinate of Control Code` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        'Z Axis' AS `Property`, `Z-Axis Co-ordinate of Control Code` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
        
     union all
     
    select 'Control Code' as `Property`,  `Control Code No of Camera` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId;
   
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_BARCODE_SCANNER_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_BARCODE_SCANNER_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_BARCODE_SCANNER_FEEDBACK_BY_BOT_ID`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    
    SELECT 
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'Property', 'X_Axis_Coordinate_of_Control_Code', 
                'Value', `X-Axis Co-ordinate of Control Code`
            )
        ) AS `junction`
    FROM 
        bot.`teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'Property', 'Y_Axis_Coordinate_of_Control_Code', 
                'Value', `Y-Axis Co-ordinate of Control Code`
            )
        ) AS `junction`
    FROM 
        bot.`teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'Property', 'Z_Axis_Coordinate_of_Control_Code', 
                'Value', `Z-Axis Co-ordinate of Control Code`
            )
        ) AS `junction`
    FROM 
        bot.`teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    
    SELECT 
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'Property', 'X_Axis_Position_of_Control_Code', 
                'Value', `X-Axis Position of Control Code`
            )
        ) AS `position_display`
    FROM 
        bot.`teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'Property', 'Y_Axis_Position_of_Control_Code', 
                'Value', `Y-Axis Position of Control Code`
            )
        ) AS `position_display`
    FROM 
        bot.`teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'Property', 'Angle_of_Control_Code', 
                'Value', `Angle of Control Code`
            )
        ) AS `position_display`
    FROM 
        bot.`teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    
    SELECT 
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'Property', 'X_Axis_Actual_Position', 
                'Value', `X-Axis Actual Position`
            )
        ) AS `actual_position_display`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'Property', 'Y_Axis_Actual_Position', 
                'Value', `Y-Axis Actual Position`
            )
        ) AS `actual_position_display`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'Property', 'Z_Axis_Actual_Position', 
                'Value', `Z-Axis Actual Position`
            )
        ) AS `actual_position_display`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_BARCODE_SERVOPOS_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_BARCODE_SERVOPOS_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_BARCODE_SERVOPOS_FEEDBACK_BY_BOT_ID`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    SELECT 
        'X Axis Actual Position' AS `Property`, `X-Axis Actual Position` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        'Y Axis Actual Position' AS `Property`, `Y-Axis Actual Position` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        'Z Axis Actual Position' AS `Property`, `Z-Axis Actual Position` AS `Value`
    FROM 
        `teleoperation_numeric_data_feedback`
    WHERE 
        bot_id = botId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_BATTERY_STATUS_DISPLAY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_BATTERY_STATUS_DISPLAY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_BATTERY_STATUS_DISPLAY`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    SELECT 
        'Battery S.NO' AS `Property`, `Battery S. NO.` AS `Value`
    FROM
        `teleoperation_numeric_data_feedback`
    WHERE
        bot_id = botId
    UNION ALL
    SELECT 
        'Battery Voltage' AS `Property`, `Battery Voltage` AS `Value`
    FROM
        `teleoperation_numeric_data_feedback`
    WHERE
        bot_id = botId
    UNION ALL
    SELECT 
        'Battery Discharging Current' AS `Property`, `Battery Discharging Current` AS `Value`
    FROM
        `teleoperation_numeric_data_feedback`
    WHERE
        bot_id = botId
    UNION ALL
    SELECT 
        'Temperature-1' AS `Property`, `Temperature-1` AS `Value`
    FROM
        `teleoperation_numeric_data_feedback`
    WHERE
        bot_id = botId
    UNION ALL
    SELECT 
        'Temperature-2' AS `Property`, `Temperature-2` AS `Value`
    FROM
        `teleoperation_numeric_data_feedback`
    WHERE
        bot_id = botId
    UNION ALL
    SELECT 
        'Battery Remaining AH' AS `Property`, `Battery Remaining AH` AS `Value`
    FROM
        `teleoperation_numeric_data_feedback`
    WHERE
        bot_id = botId
    UNION ALL
    SELECT 
        'Battery Full AH' AS `Property`, `Battery Full AH` AS `Value`
    FROM
        `teleoperation_numeric_data_feedback`
    WHERE
        bot_id = botId;
 
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_INPUT_STATUS_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_INPUT_STATUS_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_INPUT_STATUS_FEEDBACK_BY_BOT_ID`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    SELECT 
        'Input 00 - Front Lidar Healthy' AS `Property`, 
        IF(`Front Lidar Healthy` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 01 - Front Lidar Alert' AS `Property`, 
        IF(`Front Lidar Alert` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 02 - Emergency Stop AT BOT' AS `Property`, 
        IF(`Emergency Stop AT BOT` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 03 - Axis Change Home Sensor' AS `Property`, 
        IF(`Axis Change Home Sensor` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 04 - Bin Presence Sensor' AS `Property`, 
        IF(`Bin Presence Sensor` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 05 - spare41' AS `Property`, 
        IF(`spare41` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 06 - spare42' AS `Property`, 
        IF(`spare42` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 07 - Front Lidar Danger' AS `Property`, 
        IF(`Front Lidar Danger` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 08 - Slide Right Zero Position Sensor' AS `Property`, 
        IF(`Slide Right Zero Position Sensor` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 09 - Front Lidar Warning' AS `Property`, 
        IF(`Front Lidar Warning` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 10 - Top Sensor Alert' AS `Property`, 
        IF(`Top Sensor Alert` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 11 - Top Sensor Danger' AS `Property`, 
        IF(`Top Sensor Danger` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 12 - Slide Left Zero Position Sensor' AS `Property`, 
        IF(`Slide Left Zero Position Sensor` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 13 - spare45' AS `Property`, 
        IF(`spare45` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 14 - spare46' AS `Property`, 
        IF(`spare46` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 15 - Rear Lidar Healthy' AS `Property`, 
        IF(`Rear Lidar Healthy` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 16 - Rear Lidar Danger' AS `Property`, 
        IF(`Rear Lidar Danger` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 17 - Rear Lidar Alert' AS `Property`, 
        IF(`Rear Lidar Alert` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 18 - Rear Lidar Warning' AS `Property`, 
        IF(`Rear Lidar Warning` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 19 - Bottom Lidar Healthy' AS `Property`, 
        IF(`Bottom Lidar Healthy` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 20 - Bottom Lidar Danger' AS `Property`, 
        IF(`Bottom Lidar Danger` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 21 - Bottom Lidar Alert' AS `Property`, 
        IF(`Bottom Lidar Alert` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 22 - Bottom Lidar Warning' AS `Property`, 
        IF(`Bottom Lidar Warning` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId
    UNION ALL
    SELECT 
        'Input 23 - spare47' AS `Property`, 
        IF(`spare47` = 1, 'true', 'false') AS `Value`
    FROM `teleoperation_bool_data_feedback`
    WHERE bot_id = botId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_LIFTING_SLIDER_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_LIFTING_SLIDER_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_LIFTING_SLIDER_FEEDBACK`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci, IN identifier VARCHAR(100))
BEGIN
    IF identifier = 'slider' THEN
        SELECT
            'slider' AS identifier,
            `Slider-Axis Actual Position` AS `Slider Actual Position`,
            `Slider-Axis Servo Current` AS `Servo Current`,
            `Slider-Axis Actual Velocity` AS `Actual Speed`
        FROM
            `teleoperation_numeric_data_feedback`
        WHERE
            bot_id = botId;
           
    ELSEIF identifier = 'lifting' THEN
        SELECT
            'lifting' AS identifier,
            `Lift-Axis Actual Position` AS `Lift Axis Actual Position`,
            `Lift-Axis Servo Current` AS `Servo Current`,
            `Lift-Axis Actual Velocity` AS `Actual Speed`
        FROM
            `teleoperation_numeric_data_feedback`
        WHERE
            bot_id = botId;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_NUMERIC_DATA_BY_IDENTTIFIER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_NUMERIC_DATA_BY_IDENTTIFIER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_NUMERIC_DATA_BY_IDENTTIFIER`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci, IN identifier VARCHAR(100))
BEGIN
    IF identifier = 'xaxis' THEN
        SELECT 
            'xaxis' AS `identifier`,
            `X-Axis Actual Velocity` AS `Actual Speed(mm/s)`, 
            `X-Axis Actual Position` AS `Actual Position(mm)`,
            `Front Right Wheel Servo Current` AS `Front Right Wheel Servo Current(amps)` ,
            `Front Left Wheel Servo Current` AS `Front Left Wheel Servo Current(amps)`,
            `Rear Right Wheel Servo Current` AS `Rear Right Wheel Servo Current(amps)`,
            `Rear Left Wheel Servo Current` AS `Rear Left Wheel Servo Current(amps)`
        FROM 
            `teleoperation_numeric_data_feedback`
        WHERE 
            bot_id = botId;
    
    ELSEIF identifier = 'yaxis' THEN
        SELECT 
            'yaxis' AS `identifier`,
            `Y-Axis Actual Velocity` AS `Actual Speed(mm/s)`, 
            `Y-Axis Actual Position` AS `Actual Position(mm)`,
            `Y-Axis Servo Current`
        FROM 
            `teleoperation_numeric_data_feedback`
        WHERE 
            bot_id = botId;
    
    ELSEIF identifier = 'zaxis' THEN
        SELECT 
            'zaxis' AS `identifier`,
            tnf.`Z-Axis Actual Position`  AS `Actual Position(mm)`,
            tnf.`Z-Axis Actual Velocity` AS `Actual Speed(mm/s)`, 
            tnf.`Front Right Wheel Servo Current` AS `Front Right Wheel Servo Current(amps)`,
            tnf.`Front Left Wheel Servo Current` AS `Front Left Wheel Servo Current(amps)`,
            tnf.`Rear Right Wheel Servo Current` AS `Rear Right Wheel Servo Current(amps)`,
            tnf.`Rear Left Wheel Servo Current` AS `Rear Left Wheel Servo Current(amps)`
        FROM 
            `teleoperation_numeric_data_feedback` tnf
        WHERE 
            bot_id = botId;
    
    ELSE
        SELECT 0;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_GET_XY_SLIPPAGE_FEEDBACK_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_GET_XY_SLIPPAGE_FEEDBACK_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_GET_XY_SLIPPAGE_FEEDBACK_BY_BOT_ID`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    SELECT 
        'X Axis Before Slippage' AS `Property`, 
        `X-Axis Before Slippage (*1000)` / 1000 AS `Value`
    FROM 
        `teleoperation_numeric_data`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        'X Axis After Slippage' AS `Property`, 
        `X-Axis After Slippage (*1000)` / 1000 AS `Value`
    FROM 
        `teleoperation_numeric_data`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        'Y Axis Before Slippage' AS `Property`, 
        `Y-Axis Before Slippage (*1000)` / 1000 AS `Value`
    FROM 
        `teleoperation_numeric_data`
    WHERE 
        bot_id = botId
    UNION ALL
    SELECT 
        'Y Axis After Slippage' AS `Property`, 
        `Y-Axis After Slippage (*1000)` / 1000 AS `Value`
    FROM 
        `teleoperation_numeric_data`
    WHERE 
        bot_id = botId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_BARCODE_TRIGGER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_BARCODE_TRIGGER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_BARCODE_TRIGGER`(IN Parameters JSON)
BEGIN
  
    DECLARE triggerBit INT DEFAULT NULL;
    DECLARE botId VARCHAR(50);
    
    UPDATE `teleoperation_bool_data` SET `Manual Code reader Bit` = '{triggerBit}' 
    WHERE bot_id = botId; 
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_LIFTING_SLIDER_AXIS_VELOCITY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_LIFTING_SLIDER_AXIS_VELOCITY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_LIFTING_SLIDER_AXIS_VELOCITY`(IN Parameters JSON)
BEGIN
    DECLARE _velocity INT DEFAULT NULL;
    DECLARE botId VARCHAR(50);
    DECLARE identifier VARCHAR(20);
    
    SET _velocity = IF(Parameters ->> "$.velocity" = 'null', NULL, CAST(Parameters ->> "$.velocity" AS UNSIGNED));
    SET botId = Parameters->> "$.botId";
    SET identifier = Parameters->> "$.identifier";
    
    
    IF identifier = 'lifting' THEN
        UPDATE `teleoperation_numeric_data` 
        SET 
            `Lift-Axis Set Position Velocity` = COALESCE(_velocity, `Lift-Axis Set Position Velocity`)
        WHERE 
            bot_id = botId;
	SELECT `Lift-Axis Set Position Velocity` AS `Set Speed (mm/s)` FROM `teleoperation_numeric_data` WHERE bot_id = botId;
    ELSEIF identifier = 'slider' THEN
        UPDATE `teleoperation_numeric_data` 
        SET 
            `Slider-Axis Set Position Velocity` = COALESCE(_velocity, `Slider-Axis Set Position Velocity`)
        WHERE 
            bot_id = botId;
            SELECT `Slider-Axis Set Position Velocity` AS `Set Speed (mm/s)` FROM `teleoperation_numeric_data` WHERE bot_id = botId;
    END IF;
    
   
	
	
	
	
	
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_REAR_FRONT_ACTUATOR_BY_IDENTIFIER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_REAR_FRONT_ACTUATOR_BY_IDENTIFIER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_REAR_FRONT_ACTUATOR_BY_IDENTIFIER`(in Parameters json)
BEGIN
	DECLARE _botId VARCHAR(50) DEFAULT Parameters ->> "$.botId";
        DECLARE _frontRearIdentifier VARCHAR(50) DEFAULT Parameters ->> "$.frontRearIdentifier";
        DECLARE _actuatorBit TINYINT DEFAULT Parameters ->> "$.actuatorBit";
       
       
        IF _frontRearIdentifier = 'front' THEN
        BEGIN
            UPDATE `teleoperation_bool_data` SET `Front Finger Actuator on/off` = _actuatorBit WHERE bot_id = _botId;
            SELECT bot_id AS botId, `Front Finger Actuator on/off` AS `bit` FROM `teleoperation_bool_data` WHERE bot_id = _botId;
         END;
   
       
        ELSEIF _frontRearIdentifier = 'rear' THEN
        BEGIN
            UPDATE `teleoperation_bool_data` SET `Rear Finger Actuator on/off` = _actuatorBit WHERE bot_id = _botId;
            SELECT bot_id AS botId, `Rear Finger Actuator on/off` AS `bit` FROM `teleoperation_bool_data` WHERE bot_id = _botId;
         END;
       
        ELSE
            SELECT -1 AS `bit`;
        END IF;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_RUN_BUTTON_XY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_RUN_BUTTON_XY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_RUN_BUTTON_XY`(in Parameters json)
BEGIN
		declare _identifier varchar(100);
		declare _botId varchar(50); 
		declare _runBit tinyint;
		
		set _runBit = Parameters ->> "$.runBit";
		set _identifier = Parameters ->> "$.identifier";
		set _botId = Parameters ->> "$.botId";
		
		if _identifier = 'xaxis' then
		begin
			UPDATE `teleoperation_bool_data` SET `X-Axis Position Manual Run` = _runBit WHERE bot_id = _botId;
			select 'xaxis' as identifier,`X-Axis Position Manual Run` as `Response` from `teleoperation_bool_data` where bot_id = _botId;
			end;
		elseif _identifier = 'yaxis' then
		begin 
			UPDATE `teleoperation_bool_data` SET `Y-Axis Position Manual Run` = _runBit WHERE bot_id = _botId;
			SELECT 'yaxis' as identifier, `Y-Axis Position Manual Run` as `Response` FROM `teleoperation_bool_data` WHERE bot_id = _botId;
			end;
		else
			select _identifier as identifier , '-1' as `Response`;
		end if;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_SLIDER_LIFTING_AXIS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_SLIDER_LIFTING_AXIS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_SLIDER_LIFTING_AXIS`(in Parameters json)
BEGIN
	DECLARE _botId VARCHAR(50) DEFAULT Parameters ->> "$.botId";
        DECLARE _identifier VARCHAR(100) DEFAULT Parameters ->> "$.identifier";
        DECLARE _liftingSliderValue INT DEFAULT Parameters ->> "$.liftingSliderValue";
        DECLARE _modificationBit TINYINT DEFAULT Parameters ->> "$.bit";
        
        IF _identifier = 'lifting' THEN
        BEGIN
            UPDATE `teleoperation_numeric_data` SET `Lift-Axis Set Position` = _liftingSliderValue WHERE bot_id = _botId;
                    
            DO SLEEP(1);
            UPDATE `teleoperation_bool_data`  SET `Lift-Axis Position Manual Run` = _modificationBit WHERE bot_id = _botId;
            SELECT bot_id AS botId, 'lifting' AS identifier, `Lift-Axis Position Manual Run` AS `bit`, 'Running' AS `message` FROM `teleoperation_bool_data` WHERE bot_id = _botId;
        END;        
        ELSEIF _identifier = 'slider' THEN
        BEGIN
            UPDATE `teleoperation_numeric_data` SET `Slider-Axis Set Position` = _liftingSliderValue WHERE bot_id = _botId;
            DO SLEEP(1);
            UPDATE `teleoperation_bool_data` SET `Slider-Axis Position Manual Run` = _modificationBit WHERE bot_id = _botId;
            SELECT bot_id AS botId, 'slider' AS identifier, `Slider-Axis Position Manual Run` AS `bit`, 'Running' AS `message` FROM `teleoperation_bool_data` WHERE bot_id = _botId;
           
        END;
        ELSE
            SELECT '-1' AS `bit`, 'Wrong Identifier' AS message;
        END IF;
		
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_XY_SLIPPAGE_VELOCITY_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_XY_SLIPPAGE_VELOCITY_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_XY_SLIPPAGE_VELOCITY_BY_BOT_ID`(IN Parameters JSON)
BEGIN
    DECLARE _botId VARCHAR(50) DEFAULT Parameters ->> "$.botId";
    DECLARE _identifier VARCHAR(100) DEFAULT Parameters ->> "$.identifier";
    DECLARE _velocity FLOAT DEFAULT Parameters ->> "$.slippageValue";
    
    IF _identifier = 'xbefore' THEN
    BEGIN
        UPDATE `teleoperation_numeric_data` 
        SET `X-Axis Before Slippage (*1000)` = _velocity * 1000 
        WHERE bot_id = _botId;
        
        
        SELECT bot_id AS botId, 'xbefore' AS identifier, _velocity * 1000 AS `X-Axis Before Slippage`, 'Updated X-Axis Before Slippage' AS `message`
        FROM `teleoperation_numeric_data`
        WHERE bot_id = _botId;
    END;
    ELSEIF _identifier = 'xafter' THEN
    BEGIN
        UPDATE `teleoperation_numeric_data` 
        SET `X-Axis After Slippage (*1000)` = _velocity * 1000 
        WHERE bot_id = _botId;
        
        SELECT bot_id AS botId, 'xafter' AS identifier, _velocity * 1000 AS `X-Axis After Slippage`, 'Updated X-Axis After Slippage' AS `message`
        FROM `teleoperation_numeric_data`
        WHERE bot_id = _botId;
    END;
    ELSEIF _identifier = 'ybefore' THEN
    BEGIN
        UPDATE `teleoperation_numeric_data` 
        SET `Y-Axis Before Slippage (*1000)` = _velocity * 1000 
        WHERE bot_id = _botId;
        
        SELECT bot_id AS botId, 'ybefore' AS identifier, _velocity * 1000 AS `Y-Axis Before Slippage`, 'Updated Y-Axis Before Slippage' AS `message`
        FROM `teleoperation_numeric_data`
        WHERE bot_id = _botId;
    END;
    ELSEIF _identifier = 'yafter' THEN
    BEGIN
        UPDATE `teleoperation_numeric_data` 
        SET `Y-Axis After Slippage (*1000)` = _velocity * 1000 
        WHERE bot_id = _botId;
        
        SELECT bot_id AS botId, 'yafter' AS identifier, _velocity * 1000 AS `Y-Axis After Slippage`, 'Updated Y-Axis After Slippage' AS `message`
        FROM `teleoperation_numeric_data`
        WHERE bot_id = _botId;
    END;
    ELSE 
        SELECT '-1' AS `bit`, 'Wrong Identifier' AS message;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_X_AXIS_POSITION_VELOCITY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_X_AXIS_POSITION_VELOCITY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_X_AXIS_POSITION_VELOCITY`(IN Parameters JSON)
BEGIn
    DECLARE _position BIGINT DEFAULT NULL;
    DECLARE _velocity INT DEFAULT NULL;
    DECLARE botId VARCHAR(50);
    DECLARE max_position_value BIGINT DEFAULT 99999999999;  
    DECLARE max_velocity_value INT DEFAULT 2147483647;       
    
    SET _position = IF(Parameters ->> "$.position" = 'null', NULL, CAST(Parameters ->> "$.position" AS SIGNED));
    SET _velocity = IF(Parameters ->> "$.velocity" = 'null', NULL, CAST(Parameters ->> "$.velocity" AS SIGNED));
    SET botId = Parameters ->> "$.botId";
    
    IF _position IS NOT NULL THEN
        IF _position < 0 OR Parameters ->> "$.position" REGEXP '[^0-9]' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Position must be a positive integer.';
        END IF;
        IF _position > max_position_value THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Position exceeds maximum allowed value (11 digits).';
        END IF;
    END IF;
    
    IF _velocity IS NOT NULL THEN
        IF _velocity < 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Velocity cannot be negative.';
        END IF;
        IF _velocity > max_velocity_value THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Velocity exceeds maximum allowed value.';
        END IF;
    END IF;
    
    UPDATE `teleoperation_numeric_data` 
    SET 
        `X-Axis Set Position Velocity` = COALESCE(_velocity, `X-Axis Set Position Velocity`),
        `X-Axis Set Position` = COALESCE(_position, `X-Axis Set Position`)
    WHERE bot_id = botId; 
        SELECT 
        `X-Axis Set Position` AS  `Set Position (mm)`,
        `X-Axis Set Position Velocity` AS `Set Speed (mm/s)`
        FROM 
        `teleoperation_numeric_data`
	WHERE 
	bot_id = botId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_Y_AXIS_POSITION_VELOCITY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_Y_AXIS_POSITION_VELOCITY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_Y_AXIS_POSITION_VELOCITY`(IN Parameters JSON)
BEGIN
    DECLARE _position INT DEFAULT NULL;
    DECLARE _velocity INT DEFAULT NULL;
    DECLARE botId VARCHAR(50);
    
    SET _position = IF(Parameters ->> "$.position" = 'null', NULL, CAST(Parameters ->> "$.position" AS SIGNED));
    SET _velocity = IF(Parameters ->> "$.velocity" = 'null', NULL, CAST(Parameters ->> "$.velocity" AS SIGNED));
    SET botId = Parameters->> "$.botId";
    
    IF _position IS NOT NULL AND (_position < 0 OR Parameters ->> "$.position" NOT REGEXP '^[0-9]+$') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Position must be a positive integer.';
    END IF;
    
    IF _velocity IS NOT NULL AND (_velocity < 0 OR Parameters ->> "$.velocity" NOT REGEXP '^[0-9]+$') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Velocity must be a positive integer.';
    END IF;
    
    UPDATE `teleoperation_numeric_data` 
    SET 
        `Y-Axis Set Position Velocity` = COALESCE(_velocity, `Y-Axis Set Position Velocity`),
        `Y-Axis Set Position` = COALESCE(_position, `Y-Axis Set Position`)
    WHERE bot_id = botId; 
    
   
	SELECT 
        `Y-Axis Set Position` AS  `Set Position (mm)`,
        `Y-Axis Set Position Velocity` AS `Set Speed (mm/s)`
        FROM 
        `teleoperation_numeric_data`
	WHERE 
	bot_id = botId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_Z_AXIS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_Z_AXIS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_Z_AXIS`(IN parameters JSON)
BEGIN
    DECLARE `_velocity` INT DEFAULT NULL;
    DECLARE `_position` INT DEFAULT NULL;
    DECLARE `botId` VARCHAR(50) DEFAULT NULL;
    DECLARE _zaxisUplimit INT DEFAULT NULL;
    DECLARE  _zaxisDownlimit INT DEFAULT NULL;
 
    
    SET _velocity = IF(parameters ->> "$.jogVelocity" = 'null', NULL, CAST(parameters ->> "$.jogVelocity" AS SIGNED));
    
    SET botId = parameters ->> "$.botId";
   
    SET _zaxisUplimit = IF(parameters ->> "$.upperLimit" = 'null', NULL, CAST(parameters ->> "$.upperLimit" AS SIGNED));
    SET _zaxisDownlimit = IF(parameters ->> "$.lowerLimit" = 'null', NULL, CAST(parameters ->> "$.lowerLimit" AS SIGNED));
    
    IF _velocity IS NOT NULL AND (_velocity < 0 OR parameters ->> "$.jogVelocity" NOT REGEXP '^[0-9]+$') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Jog velocity must be a positive integer.';
    END IF;
 
    
    UPDATE `teleoperation_numeric_data`
    SET  
        `Z-Axis Jog Fwd Limit` = COALESCE(_zaxisUplimit,`Z-Axis Jog Fwd Limit`),
        `Z-Axis Jog Rev Limit` = COALESCE(_zaxisDownlimit,`Z-Axis Jog Rev Limit`),
        `Z-Axis Set Jog Velocity` = COALESCE(_velocity, `Z-Axis Set Jog Velocity`)
    WHERE bot_id = botId;
   
     UPDATE `teleoperation_bool_data` SET `Z-Jog Operation Limits Overwrite Bit` =  1 WHERE bot_id = botId;
    
    
    SELECT
    `Z-Axis Jog Rev Limit` AS `Min Position (mm)`,
    `Z-Axis Jog Fwd Limit` AS `Max Position (mm)`,
    `Z-Axis Set Jog Velocity` AS `Set Jog Speed (mm/s)`
    FROM
    `teleoperation_numeric_data`
    WHERE
    bot_id = botId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_HMI_UPDATE_Z_UP_DOWN` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_HMI_UPDATE_Z_UP_DOWN` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_HMI_UPDATE_Z_UP_DOWN`(IN Parameters JSON)
BEGIN
	DECLARE botId VARCHAR(50);
    DECLARE _identifier VARCHAR(100);
    DECLARE _upperLowerBit TINYINT;
    DECLARE z_min INT;
    DECLARE z_max INT;
    DECLARE z_position INT;
    DECLARE Message VARCHAR(255);
    
    SET _upperLowerBit = Parameters ->> "$.upperLowerBit";
    SET _identifier = Parameters ->> "$.identifier";
    SET botId = Parameters ->> "$.botId";
    
    SELECT `KEY_VALUE` INTO z_min FROM `master_config` WHERE `KEY_NAME` = 'TELEOPERATION_Z_MIN_DIRECTION';
    SELECT `KEY_VALUE` INTO z_max FROM `master_config` WHERE `KEY_NAME` = 'TELEOPERATION_Z_MAX_DIRECTION';
    
    SELECT `Z-Axis Actual Position` INTO z_position
    FROM `teleoperation_numeric_data_feedback`
    WHERE bot_id = botId;
    
    IF z_position <= z_min THEN
        SET Message = 'Lower limit reached';
    ELSEIF z_position >= z_max THEN
        SET Message = 'Upper limit reached';
    ELSE
        SET Message = 'Within limits';
    END IF;
    
    IF _identifier = 'upper' THEN
    BEGIN
        UPDATE `teleoperation_bool_data` SET `Z-Axis Jog Up` = _upperLowerBit WHERE bot_id = botId;
        UPDATE `teleoperation_bool_data` SET `Z-Axis Jog Down` = '0' WHERE bot_id = botId;
        SELECT
            'upper' AS identifier,
            `Z-Axis Jog Up` AS upperLowerBit,
            z_position AS `Actual Position(mm)`,
            Message AS `Limit Status`
        FROM `teleoperation_bool_data`
        WHERE bot_id = botId;
    END;
    ELSEIF _identifier = 'lower' THEN
    BEGIN
        UPDATE `teleoperation_bool_data` SET `Z-Axis Jog Down` = _upperLowerBit WHERE bot_id = botId;
        UPDATE `teleoperation_bool_data` SET `Z-Axis Jog Up` = '0' WHERE bot_id = botId;
        SELECT
            'lower' AS identifier,
            `Z-Axis Jog Down` AS upperLowerBit,
            z_position AS `Actual Position(mm)`,
            Message AS `Limit Status`
        FROM `teleoperation_bool_data`
        WHERE bot_id = botId;
    END;
    ELSE
        SELECT _identifier AS identifier, '-1' AS `Response`;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_INVENTORY_LIVE_COUNTS_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_INVENTORY_LIVE_COUNTS_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_INVENTORY_LIVE_COUNTS_FEEDBACK`()
BEGIN
    SELECT 
        COUNT(DISTINCT ARTICLE_ID) AS DISTINCT_SKU,
        SUM(QUANTITY) AS TOTAL_QUANTITY,
        SUM(VIRTUAL_QUANTITY_TO_PICK) AS VIRTUAL_PICK_QUANTITY
    FROM live_inventory_master;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_INVENTORY_SYNC_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_INVENTORY_SYNC_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_INVENTORY_SYNC_FEEDBACK`()
BEGIN
    SELECT
        im.STATUS,
        im.REASON,
        im.INSERTED_TIMESTAMP,
        im.UPDATED_TIMESTAMP,
        mc.KEY_VALUE AS FEEDBACK
    FROM master_config AS mc
    LEFT JOIN (
        SELECT 
            STATUS,
            REASON,
            INSERTED_TIMESTAMP,
            UPDATED_TIMESTAMP
        FROM inventory_sync_master
        ORDER BY INSERTED_TIMESTAMP DESC
        LIMIT 1
    ) AS im ON 1 = 1
    WHERE mc.KEY_NAME = 'INTEGRATION_INVENTORY_SYNC_STATUS';
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_IP_LIST_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_IP_LIST_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_IP_LIST_GET`(IN Parameters JSON)
BEGIN
    
    DECLARE p_request_type VARCHAR(255);
    DECLARE p_request_extra_parameters JSON;
    DECLARE p_station_id INT;
    
    SET p_request_type             = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.request_type'));
    SET p_request_extra_parameters = JSON_EXTRACT(Parameters, '$.request_extra_parameters');
    SET p_station_id               = CAST(JSON_UNQUOTE(JSON_EXTRACT(p_request_extra_parameters, '$.station_id')) AS UNSIGNED);
    
    IF p_request_type = 'STATION' THEN
        
        SELECT 'STATION DISPLAY' AS NAME, IP 
        FROM hw_display_master
        WHERE PARENT_ID = p_station_id
        UNION ALL
        
        SELECT DISTINCT 'PTL' AS NAME, IP 
        FROM hw_ptl_master
        WHERE PARENT_ID = p_station_id
        UNION ALL
        
        SELECT 'CONVEYOR' AS NAME, IP 
        FROM hw_conveyor_master
        WHERE PARENT_ID = p_station_id AND MAKE = 'OMRON'
        UNION ALL
        
        SELECT 'CONVEYOR MULTIPLEXER' AS NAME, IP 
        FROM hw_conveyor_mux_master
        WHERE MUX_ID IN (
            SELECT CONVEYOR_MUX_ID 
            FROM hw_conveyor_master 
            WHERE PARENT_ID = p_station_id AND MAKE = 'CONVEYOR_MULTIPLEXER'
        )
        UNION ALL
        
        SELECT 'CURTAIN LIGHT' AS NAME, IP 
        FROM hw_curtain_light_master
        WHERE PARENT_ID = p_station_id
        UNION ALL
        
        SELECT 'FIXED SCANNER' AS NAME, IP
        FROM hw_scanner_master
        WHERE PARENT_ID = p_station_id
        UNION ALL
        
        SELECT 'PTL SCANNER' AS NAME, IP 
        FROM hw_scanner_master
        WHERE PARENT_ID IN (
            SELECT PTL_ID 
            FROM hw_ptl_master
            WHERE PARENT_ID = p_station_id
        );
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_KNOW_YOUR_DATA` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_KNOW_YOUR_DATA` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_KNOW_YOUR_DATA`(IN Parameters JSON)
BEGIN
  DECLARE p_search_type    VARCHAR(50);
  DECLARE p_search_pattern VARCHAR(255);
  DECLARE v_limit          INT DEFAULT 100;
  SET p_search_type    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.search_type'));
  SET p_search_pattern = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.search_pattern'));
  IF p_search_type = 'pallet_id' THEN
    SELECT DISTINCT
           t.PALLET_ID AS DROPDOWN_TEXT,
           t.PALLET_ID AS DROPDOWN_VALUE
    FROM (
      SELECT PALLET_ID
      FROM wms_to_wcs_storage_request_pallet_data
      WHERE PALLET_ID LIKE CONCAT('%', p_search_pattern, '%')
      UNION ALL
      SELECT PALLET_ID
      FROM wms_to_wcs_storage_request_pallet_data_archive
      WHERE PALLET_ID LIKE CONCAT('%', p_search_pattern, '%')
    ) AS t
    LIMIT v_limit;
  ELSEIF p_search_type = 'batch_picklist_code' THEN
    SELECT DISTINCT
           t.BATCH_PICKLIST_CODE AS DROPDOWN_TEXT,
           t.BATCH_PICKLIST_CODE AS DROPDOWN_VALUE
    FROM (
      SELECT BATCH_PICKLIST_CODE
      FROM wms_to_wcs_order_level_pre_staged_data
      WHERE BATCH_PICKLIST_CODE LIKE CONCAT('%', p_search_pattern, '%')
      UNION ALL
      SELECT BATCH_PICKLIST_CODE
      FROM wms_to_wcs_order_level_pre_staged_data_archive
      WHERE BATCH_PICKLIST_CODE LIKE CONCAT('%', p_search_pattern, '%')
    ) AS t
    LIMIT v_limit;
  ELSEIF p_search_type = 'sku_name' THEN
    SELECT
      SKU_NAME AS DROPDOWN_TEXT,
      SKU_ID   AS DROPDOWN_VALUE
    FROM sku_master
    WHERE SKU_NAME LIKE CONCAT('%', p_search_pattern, '%')
    LIMIT v_limit;
  ELSEIF p_search_type = 'sku_id' THEN
    SELECT
      SKU_NAME AS DROPDOWN_TEXT,
      SKU_ID   AS DROPDOWN_VALUE
    FROM sku_master
    WHERE SKU_ID LIKE CONCAT('%', p_search_pattern, '%')
    LIMIT v_limit;
  ELSEIF p_search_type = 'ean_id' THEN
    SELECT  
         DISTINCT sm.SKU_NAME AS DROPDOWN_TEXT, sm.SKU_ID AS DROPDOWN_VALUE
    FROM 
        sku_ean_mapping AS sem
    INNER JOIN 
        sku_master AS sm ON sem.SKU_ID = sm.SKU_ID
    WHERE 
        sem.EAN_ID LIKE CONCAT('%', p_search_pattern, '%')
    LIMIT v_limit;
  ELSEIF p_search_type = 'bin_id' THEN
    SELECT
      BIN_BARCODE AS DROPDOWN_TEXT,
      BIN_ID      AS DROPDOWN_VALUE
    FROM bin_info_master
    WHERE BIN_ID LIKE CONCAT('%', p_search_pattern, '%')
    LIMIT v_limit;
  ELSEIF p_search_type = 'bin_barcode' THEN
    SELECT
      BIN_BARCODE AS DROPDOWN_TEXT,
      BIN_ID      AS DROPDOWN_VALUE
    FROM bin_info_master
    WHERE BIN_BARCODE LIKE CONCAT('%', p_search_pattern, '%')
    LIMIT v_limit;
  ELSEIF p_search_type = 'ptl_id' THEN
    SELECT
      PTL_ID AS DROPDOWN_TEXT,
      PTL_ID   AS DROPDOWN_VALUE
    FROM hw_ptl_master
    WHERE PTL_ID LIKE CONCAT('%', p_search_pattern, '%')
    LIMIT v_limit;
  ELSE
    SELECT 0 AS Success, 'Wrong Search Type' AS Message;
  END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_LANGUAGE_TRANSLATION_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_LANGUAGE_TRANSLATION_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_LANGUAGE_TRANSLATION_GET_ALL`()
BEGIN
    SELECT 
        *
    FROM 
        dashboard_language_translate_master
    WHERE 
        IS_ACTIVE = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_LIVE_PUT_WAVE_DATA` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_LIVE_PUT_WAVE_DATA` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_LIVE_PUT_WAVE_DATA`(IN Parameters JSON)
BEGIN
    
    DECLARE p_station_id INT;
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255) DEFAULT '';
    
    SET p_station_id = CAST(Parameters ->> '$.station_id' AS UNSIGNED);
    
    IF EXISTS (
        SELECT 1 
        FROM hw_station_master 
        WHERE STATION_ID = p_station_id
    ) THEN
        
        CREATE TEMPORARY TABLE temp_put_wave_summary AS
        SELECT 
            WAVE_ID,
            STATION_ID,
            STORAGE_ID,
            SUM(PUT_QUANTITY) AS total_put_quantity
        FROM put_wave_order_master 
        WHERE STATION_ID = p_station_id
        GROUP BY STORAGE_ID, WAVE_ID, STATION_ID;
        
        CREATE TEMPORARY TABLE temp_short_put_summary AS
        SELECT 
            pwom.STORAGE_ID,
            SUM(spwr.SHORT_PUT_QUANTITY) AS total_short_quantity
        FROM short_put_wave_reason spwr 
        JOIN put_wave_order_master pwom 
            ON pwom.PUT_ORDER_ID = spwr.PUT_ORDER_ID
        JOIN temp_put_wave_summary tpws 
            ON tpws.STORAGE_ID = pwom.STORAGE_ID
        WHERE spwr.REASON IN ('MISSING', 'DAMAGED_PRODUCT') 
        GROUP BY pwom.STORAGE_ID;
        
        CREATE TEMPORARY TABLE temp_scanned_pallets AS
        SELECT 
            wtwsrpd.PALLET_ID, 
            wtwsrpd.storage_request_id,
            wtwsrpd.storage_request_status,
            wtwsrd.storage_id, 
            wtwsrd.quantity, 
            wtwsrpd.PALLET_SCANNED_TIMESTAMP,
            wtwsrpd.PALLET_COMPLETION_TIMESTAMP 
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd 
        JOIN wms_to_wcs_storage_request_data wtwsrd 
            ON wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID = wtwsrd.WMS_STORAGE_REQUEST_PALLET_DATA_ID 
        JOIN temp_put_wave_summary tpws 
            ON tpws.STORAGE_ID = wtwsrd.STORAGE_ID
        WHERE wtwsrpd.storage_request_status IN ('PALLET_SCANNED', 'PALLET_COMPLETED');
        
        SELECT 
            sp.PALLET_ID,
            sp.STORAGE_REQUEST_ID,
            sp.STORAGE_REQUEST_STATUS,
            COUNT(DISTINCT sp.STORAGE_ID) AS TOTAL_STORAGE_ID,
            COALESCE(SUM(sp.quantity), 0) AS TOTAL_EACHES,
            COALESCE(SUM(pws.total_put_quantity), 0) AS EACHES_KEPT,
            COALESCE(SUM(sps.total_short_quantity), 0) AS STOCK_ADJUSTMENT,
            (
                COALESCE(SUM(sp.quantity), 0) 
                - (
                    COALESCE(SUM(pws.total_put_quantity), 0) 
                    + COALESCE(SUM(sps.total_short_quantity), 0)
                )
            ) AS PENDING,
            sp.PALLET_SCANNED_TIMESTAMP,
            sp.PALLET_COMPLETION_TIMESTAMP
        FROM temp_scanned_pallets sp
        LEFT JOIN temp_put_wave_summary pws 
            ON sp.storage_id = pws.storage_id
        LEFT JOIN temp_short_put_summary sps 
            ON pws.storage_id = sps.storage_id
        GROUP BY 
            sp.PALLET_ID, 
            sp.STORAGE_REQUEST_ID
        ORDER BY 
            sp.PALLET_SCANNED_TIMESTAMP DESC;
        
        DROP TEMPORARY TABLE IF EXISTS temp_scanned_pallets;
        DROP TEMPORARY TABLE IF EXISTS temp_put_wave_summary;
        DROP TEMPORARY TABLE IF EXISTS temp_short_put_summary;
    ELSE
        
        SET Success = 0;
        SET Result = CONCAT('Station ', p_station_id, ' does not exist.');
        SELECT Success AS Success, Result AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_LOG_BOT_BATTERY_CHARGING` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_LOG_BOT_BATTERY_CHARGING` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_LOG_BOT_BATTERY_CHARGING`(IN Parameters JSON)
BEGIN
    
    DECLARE p_bot_id     VARCHAR(100);
    DECLARE p_log_at     VARCHAR(100);
    DECLARE p_user_name  VARCHAR(100);
    DECLARE v_last_id    BIGINT;
    
    SET p_bot_id     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bot_id'));
    SET p_log_at     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.log_at'));
    SET p_user_name  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    
    
    SELECT ID INTO v_last_id
    FROM dashboard_log_bot_charging
    WHERE BOT_ID = p_bot_id AND TIMESTAMP_AFTER_STATION IS NULL
    ORDER BY UPDATED_TIMESTAMP DESC
    LIMIT 1;
    
    IF p_log_at = 'CHARGING_BIT_HIGH' THEN
	DELETE FROM dashboard_log_bot_charging WHERE ID = v_last_id;
	
        INSERT INTO dashboard_log_bot_charging (
            BOT_ID,
            BATTERY_AT_CHARGING_BIT_1,
            TIMESTAMP_AT_CHARGING_BIT_1,
            INSERTED_TIMESTAMP,
            INSERTED_BY,
            UPDATED_BY
        )
        SELECT 
            p_bot_id,
            BATTERY_PERCENTAGE,
            INSERTED_TIMESTAMP,
            NOW(),
            p_user_name,
            p_user_name
        FROM bot_charging_bit_log
        WHERE BOT_ID = p_bot_id
        ORDER BY inserted_timestamp DESC
        LIMIT 1;
    
    ELSEIF p_log_at = 'ON_STATION' THEN
        IF v_last_id IS NOT NULL THEN
            UPDATE dashboard_log_bot_charging 
            SET 
                BATTERY_AT_STATION = (SELECT BATTERY FROM bot_master WHERE BOT_ID = p_bot_id),
                TIMESTAMP_AT_STATION = NOW()
            WHERE ID = v_last_id;
        END IF;
        
    ELSEIF p_log_at = 'LEAVING_STATION' THEN
	IF v_last_id IS NOT NULL THEN
            UPDATE dashboard_log_bot_charging 
            SET 
                BATTERY_AFTER_STATION = (SELECT BATTERY FROM bot_master WHERE BOT_ID = p_bot_id),
                TIMESTAMP_AFTER_STATION = NOW()
            WHERE ID = v_last_id;
        END IF;
    END IF;
    
    SELECT 1 AS Success, 'Result' AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_LOG_ERROR_API` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_LOG_ERROR_API` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_LOG_ERROR_API`(IN Parameters JSON)
BEGIN
    
    DECLARE p_controller_name VARCHAR(100);
    DECLARE p_method_name VARCHAR(100);
    DECLARE p_request_type VARCHAR(100);
    DECLARE p_ip_address VARCHAR(100);
    DECLARE p_error_code INT;
    DECLARE p_error_message TEXT;
    DECLARE p_error_stacktrace TEXT;
    DECLARE p_updated_by VARCHAR(100);
    
    SET p_controller_name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.controller_name'));
    SET p_method_name   = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.method_name'));
    SET p_request_type   = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.request_type'));
    SET p_ip_address   = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ip_address'));
    SET p_error_code      = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.error_code'));
    SET p_error_message   = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.error_message'));
    SET p_error_stacktrace= JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.error_stacktrace'));
    SET p_updated_by      = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.updated_by'));
    
    INSERT INTO dashboard_log_error_api (
        CONTROLLER_NAME,
        METHOD_NAME,
        REQUEST_TYPE,
        IP_ADDRESS,
        ERROR_CODE,
        ERROR_MESSAGE,
        ERROR_STACKTRACE,
        INSERTED_BY
    )
    VALUES (
        p_controller_name,
        p_method_name,
        p_request_type,
        p_ip_address,
        p_error_code,
        p_error_message,
        p_error_stacktrace,
        p_updated_by
    );
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_LOG_MAINTENANCE_TASK_MASTER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_LOG_MAINTENANCE_TASK_MASTER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_LOG_MAINTENANCE_TASK_MASTER`()
BEGIN
    
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_task_id INT;
    
    DECLARE cur CURSOR FOR
        SELECT 
	    mtm.MAINTENANCE_TASK_ID
	FROM 
	    maintenance_task_master mtm
	LEFT JOIN 
	    hw_maintenance_master hmm ON mtm.MAINTENANCE_ID = hmm.MAINTENANCE_ID
	WHERE 
	    NOT EXISTS (
		SELECT 1
		FROM subcontroller_reservations_master srm
		WHERE srm.TYPE = 'MAINTENANCE'
		  AND srm.BOT_ID = mtm.MAINTENANCE_POINT_BOT_ID
		  AND srm.LOCATION_ID = hmm.MAINTENANCE_POINT_LOCATION_ID
	    );
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN cur;
    
    read_loop: LOOP
        FETCH cur INTO v_task_id;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        INSERT INTO dashboard_log_maintenance_task_master (
            MAINTENANCE_TASK_ID,
            MAINTENANCE_ID,
            MAINTENANCE_POINT_BOT_ID,
            MAINTENANCE_PICK_POINT_BOT_ID,
            BIN_BARCODE_SCANNED,
            MAINTENANCE_POINT_BARCODE_SCANNED,
            IS_MP_BOT_HEALTHY,
            TASK_DONE,
            INSERTED_TIMESTAMP,
            UPDATED_TIMESTAMP,
            LOGGED_TIMESTAMP
        )
        SELECT 
            MAINTENANCE_TASK_ID,
            MAINTENANCE_ID,
            MAINTENANCE_POINT_BOT_ID,
            MAINTENANCE_PICK_POINT_BOT_ID,
            BIN_BARCODE_SCANNED,
            MAINTENANCE_POINT_BARCODE_SCANNED,
            IS_MP_BOT_HEALTHY,
            TASK_DONE,
            INSERTED_TIMESTAMP,
            UPDATED_TIMESTAMP,
            NOW()
        FROM maintenance_task_master
        WHERE MAINTENANCE_TASK_ID = v_task_id;
        
        DELETE FROM maintenance_task_master
        WHERE MAINTENANCE_TASK_ID = v_task_id;
    END LOOP;
    
    CLOSE cur;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_LOG_STATION_BREAK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_LOG_STATION_BREAK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_LOG_STATION_BREAK`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_station_id INT;
    DECLARE p_action VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE v_last_log_id VARCHAR(36);
    DECLARE v_current_break_status INT DEFAULT 0;
    DECLARE v_success INT DEFAULT 0;
    DECLARE v_message VARCHAR(255) DEFAULT 'Action Failed';

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CALL DSB_GENERIC_TRANSACTION_ERROR_HANDLER();
    END;

    
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
    SET p_action     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.action'));
    SET p_user_name  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));

    START TRANSACTION;

        
        IF p_action = 'WORKING' THEN
            INSERT INTO station_break_logs (ID, STATION_ID, OPERATOR_NAME, WORKED_BY, WORKED_TIMESTAMP)
            VALUES (UUID(), p_station_id, p_user_name, p_user_name, NOW());
            
            UPDATE wave_station_rule_mapping 
            SET BREAK_STATUS = 0 
            WHERE STATION_ID = p_station_id; 
            
            SET v_success = 1;
            SET v_message = 'Station set to WORKING';

        
        ELSEIF p_action = 'PAUSE' THEN
            INSERT INTO station_break_logs (ID, STATION_ID, OPERATOR_NAME, PAUSED_BY, PAUSED_TIMESTAMP)
            VALUES (UUID(), p_station_id, p_user_name, p_user_name, NOW());
            
            UPDATE wave_station_rule_mapping 
            SET BREAK_STATUS = 1 
            WHERE STATION_ID = p_station_id; 
            
            SET v_success = 1;
            SET v_message = 'Station PAUSED';

        
        ELSEIF p_action = 'RESUME' THEN
            
            SELECT BREAK_STATUS INTO v_current_break_status 
            FROM wave_station_rule_mapping 
            WHERE STATION_ID = p_station_id;

            IF v_current_break_status = 1 THEN
                
                SELECT ID INTO v_last_log_id 
                FROM station_break_logs 
                WHERE STATION_ID = p_station_id 
                  AND PAUSED_TIMESTAMP IS NOT NULL 
                  AND RESUMED_TIMESTAMP IS NULL 
                ORDER BY UPDATED_TIMESTAMP DESC 
                LIMIT 1;

                IF v_last_log_id IS NOT NULL THEN
                    UPDATE station_break_logs 
                    SET RESUMED_TIMESTAMP = NOW(),
                        RESUMED_BY = p_user_name
                    WHERE ID = v_last_log_id;
                    
                    UPDATE wave_station_rule_mapping 
                    SET BREAK_STATUS = 0 
                    WHERE STATION_ID = p_station_id; 
                    
                    SET v_success = 1;
                    SET v_message = 'Station RESUMED';
                ELSE
                    SET v_success = 0;
                    SET v_message = 'No active pause record found to resume';
                END IF;
            ELSE
                SET v_success = 0;
                SET v_message = 'Station is not currently in PAUSE status';
            END IF;
        END IF;

    COMMIT;

    
    SELECT v_success AS Success, v_message AS Result;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_LPN_DETAILS_BY_LPN_BARCODE_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_LPN_DETAILS_BY_LPN_BARCODE_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_LPN_DETAILS_BY_LPN_BARCODE_GET`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_lpn_barcode VARCHAR(100);
    
    SET p_lpn_barcode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.lpn_barcode'));
    
    
    SELECT 
        pwom.ORDER_LINE_ID,
        pwom.SKU_ID,
        sm.SKU_NAME,
        lpwom.PICKED_QUANTITY
    FROM lpn_master lm
    LEFT JOIN lpn_pick_wave_order_mapping lpwom 
        ON lm.LPN_ID = lpwom.LPN_ID
    LEFT JOIN pick_wave_order_master pwom 
        ON lpwom.PICK_ORDER_ID = pwom.PICK_ORDER_ID
    LEFT JOIN sku_master sm 
        ON sm.SKU_ID = pwom.SKU_ID
    WHERE 
        lm.LPN_BARCODE = p_lpn_barcode
        AND lm.LPN_STATUS = 'LPN_OPEN';
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_MAINTENANCE_OVERVIEW_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_MAINTENANCE_OVERVIEW_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_MAINTENANCE_OVERVIEW_FEEDBACK`()
BEGIN
    SELECT 
	mtm.MAINTENANCE_TASK_ID,
        hmm.MAINTENANCE_ID,
        hmm.MAINTENANCE_POINT_LOCATION_ID,
        mtm.MAINTENANCE_POINT_BOT_ID,
        lm_m.X AS MAINTENANCE_POINT_X,
        lm_m.Y AS MAINTENANCE_POINT_Y,
        
        CASE 
            WHEN srm_m.LOCATION_ID = hmm.MAINTENANCE_POINT_LOCATION_ID
                 AND srm_m.BOT_ID = mtm.MAINTENANCE_POINT_BOT_ID THEN 1
            ELSE 0
        END AS MAINTENANCE_POINT_RESERVED,
        
        CASE 
            WHEN srm_m.BOT_ID IS NOT NULL THEN 
                CASE 
                    WHEN bm_m.GRIDX = lm_m.X AND bm_m.GRIDY = lm_m.Y THEN 'REACHED'
                    ELSE 'REACHING'
                END
            ELSE ''
        END AS MAINTENANCE_POINT_BOT_STATUS_CURRENT,
        hmm.MAINTENANCE_PICK_POINT_LOCATION_ID,
        mtm.MAINTENANCE_PICK_POINT_BOT_ID,
        lm_mp.X AS MAINTENANCE_PICK_POINT_X,
        lm_mp.Y AS MAINTENANCE_PICK_POINT_Y,
        
        CASE 
            WHEN srm_mp.LOCATION_ID = hmm.MAINTENANCE_PICK_POINT_LOCATION_ID
                 AND srm_mp.BOT_ID = mtm.MAINTENANCE_PICK_POINT_BOT_ID THEN 1
            ELSE 0
        END AS MAINTENANCE_PICK_POINT_RESERVED,
        
        CASE 
            WHEN srm_mp.BOT_ID IS NOT NULL THEN 
                CASE 
                    WHEN bm_mp.GRIDX = lm_mp.X AND bm_mp.GRIDY = lm_mp.Y THEN 'REACHED'
                    ELSE 'REACHING'
                END
            ELSE ''
        END AS MAINTENANCE_PICK_POINT_BOT_STATUS_CURRENT,
        
        mtm.BIN_BARCODE_SCANNED,
        IFNULL(mtm.MAINTENANCE_POINT_BARCODE_SCANNED, 0) AS MAINTENANCE_POINT_BARCODE_SCANNED,
        IFNULL(mtm.IS_MP_BOT_HEALTHY, 0) AS IS_MP_BOT_HEALTHY,
        IFNULL(mtm.TASK_DONE, 0) AS TASK_DONE,
        mtm.INSERTED_TIMESTAMP
    FROM hw_maintenance_master hmm
    LEFT JOIN (
        SELECT *
        FROM maintenance_task_master mt
        WHERE (mt.MAINTENANCE_ID, mt.INSERTED_TIMESTAMP) IN (
            SELECT MAINTENANCE_ID, MAX(INSERTED_TIMESTAMP)
            FROM maintenance_task_master
            GROUP BY MAINTENANCE_ID
        )
    ) mtm
        ON hmm.MAINTENANCE_ID = mtm.MAINTENANCE_ID
    LEFT JOIN location_master lm_m
        ON lm_m.LOCATION_ID = hmm.MAINTENANCE_POINT_LOCATION_ID
    LEFT JOIN location_master lm_mp
        ON lm_mp.LOCATION_ID = hmm.MAINTENANCE_PICK_POINT_LOCATION_ID
    LEFT JOIN subcontroller_reservations_master srm_m
        ON srm_m.LOCATION_ID = hmm.MAINTENANCE_POINT_LOCATION_ID
       AND srm_m.BOT_ID = mtm.MAINTENANCE_POINT_BOT_ID
    LEFT JOIN subcontroller_reservations_master srm_mp
        ON srm_mp.LOCATION_ID = hmm.MAINTENANCE_PICK_POINT_LOCATION_ID
       AND srm_mp.BOT_ID = mtm.MAINTENANCE_PICK_POINT_BOT_ID
    LEFT JOIN bot_master bm_m
        ON bm_m.BOT_ID = mtm.MAINTENANCE_POINT_BOT_ID
    LEFT JOIN bot_master bm_mp
        ON bm_mp.BOT_ID = mtm.MAINTENANCE_PICK_POINT_BOT_ID;
        
        CALL DSB_LOG_MAINTENANCE_TASK_MASTER();
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_MANUAL_UPLOAD_DATA_VALIDATION_FAILED` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_MANUAL_UPLOAD_DATA_VALIDATION_FAILED` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_MANUAL_UPLOAD_DATA_VALIDATION_FAILED`(IN Parameters VARCHAR(50))
BEGIN
    DECLARE waveType VARCHAR(50);
    DECLARE IDnumber INT;
    
    
    SELECT `WAVE_TYPE`, `ID` 
    INTO waveType, IDnumber 
    FROM `dashboard_wave_upload_status` 
    WHERE `CLIENT_WAVE_ID` = Parameters 
    ORDER BY `INSERTED_ON` DESC 
    LIMIT 1;
    
    IF waveType = 'stock_audit_by_bin_id_new' THEN
        SELECT row_num AS 'BIN ID', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                ID AS modified_ID,
                `VALIDATION_MESSAGE`,
                BIN_ID AS ROW_NUM
            FROM `stock_audit_wave_wms_data_dsb_upload_validation`
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
        
    ELSEIF waveType = 'stock_audit_by_sku_id_new' THEN
        SELECT row_num AS 'SKU ID', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                ID AS modified_ID,
                `VALIDATION_MESSAGE`,
                SKU_ID AS ROW_NUM
            FROM `stock_audit_wave_wms_data_dsb_upload_validation`
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
    ELSEIF waveType = 'stock_audit_by_bin_id_and_segment_id_new' THEN
        SELECT row_num AS 'BIN AND SEGMENT', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                ID AS modified_ID,
                `VALIDATION_MESSAGE`,
                CONCAT(BIN_ID, ' ', BIN_SEGMENT_NO) AS ROW_NUM
            FROM `stock_audit_wave_wms_data_dsb_upload_validation`
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
        
    ELSEIF waveType = 'stock_audit_by_random_new' THEN
        SELECT row_num AS 'NUMBER', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                ID AS modified_ID,
                `VALIDATION_MESSAGE`,
                BIN_ID AS ROW_NUM
            FROM `stock_audit_wave_wms_data_dsb_upload_validation`
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
    END IF;
   DELETE FROM `stock_audit_wave_wms_data_dsb_upload_validation` WHERE `UPLOADED_WAVE_ID`=IDnumber;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_MENU_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_MENU_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_MENU_GET_ALL`()
BEGIN
    SELECT 
        IS_ACTIVE, 
        MAIN_MENU,
        MENU_ID, 
        PARENT_ID, 
        MENU_NAME, 
        MENU_ICON, 
        MENU_PATH, 
        MENU_DESCRIPTION, 
        IS_BOT_AUTH_GUARD,
        IS_MENU_VISIBLE,
        IS_MENU_OPEN,
        IS_PAGE_HEADING_VISIBLE,
        IS_FOOTER_VISIBLE,
        INSERTED_BY,
        INSERTED_TIMESTAMP,
        UPDATED_BY,
        UPDATED_TIMESTAMP
    FROM 
        dashboard_menu_master;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_MENU_GET_BY_GROUP_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_MENU_GET_BY_GROUP_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_MENU_GET_BY_GROUP_ID`(IN Parameters JSON)
BEGIN
    DECLARE v_group_id INT;
    
    SET v_group_id = Parameters ->> '$.groupId';
    
    SELECT 
        dmm.IS_ACTIVE,
        dmm.MAIN_MENU, 
        dmm.PARENT_ID, 
        dmm.MENU_ID, 
        dmm.MENU_NAME, 
        dmm.MENU_PATH,
        dmm.MENU_ICON, 
        dmm.MENU_DESCRIPTION, 
        dmm.IS_BOT_AUTH_GUARD, 
        dmm.IS_MENU_VISIBLE, 
        dmm.IS_MENU_OPEN,
        dmm.IS_PAGE_HEADING_VISIBLE,
        dmm.IS_FOOTER_VISIBLE, 
        dam.VIEW AS MENU_ACCESS_VIEW, 
        dam.UPDATE AS MENU_ACCESS_UPDATE,
        dam.DELETE AS MENU_ACCESS_DELETE
    FROM
        dashboard_role_master AS drm  
    INNER JOIN  
        dashboard_role_menu_access_mapping AS drmam 
        ON drmam.ROLE_ID = drm.ROLE_ID 
    INNER JOIN 
        dashboard_menu_master AS dmm 
        ON dmm.MENU_ID = drmam.MENU_ID 
    INNER JOIN 
        dashboard_access_master AS dam 
        ON drmam.ACCESS_ID = dam.ACCESS_ID
    WHERE 
        drm.ROLE_ID = v_group_id 
        AND drm.IS_ACTIVE = 1 
        AND dmm.IS_ACTIVE = 1 
        AND drmam.IS_ACTIVE = 1
    ORDER BY 
        dmm.SEQUENCE ASC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_MTM_IMPBH_UPDATE_BY_MAINTENANCE_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_MTM_IMPBH_UPDATE_BY_MAINTENANCE_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_MTM_IMPBH_UPDATE_BY_MAINTENANCE_ID`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_maintenance_task_id INT;
    DECLARE p_maintenance_id INT;
    DECLARE p_column_value VARCHAR(100);
    
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(200);
    
    SET p_maintenance_task_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.maintenance_task_id')) AS UNSIGNED);
    SET p_maintenance_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.maintenance_id')) AS UNSIGNED);
    SET p_column_value = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.column_value'));
    
    IF p_column_value NOT IN ('0', '1') THEN
        SET Success = 0;
        SET Result = 'Invalid column value. Must be 0 or 1.';
    ELSE
        
        UPDATE maintenance_task_master 
        SET 
            MAINTENANCE_POINT_BARCODE_SCANNED = p_column_value,
            IS_MP_BOT_HEALTHY = p_column_value
        WHERE 
            MAINTENANCE_TASK_ID = p_maintenance_task_id
            AND MAINTENANCE_ID = p_maintenance_id;
        
        IF p_column_value = '1' THEN
            SET Result = 'Maintenance Point Barcode Scanned & Bot is Healthy Done';
        ELSE
            SET Result = 'Maintenance Point Barcode Scanned & Bot is Healthy Removed';
        END IF;
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_MTM_MPBS_UPDATE_BY_MAINTENANCE_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_MTM_MPBS_UPDATE_BY_MAINTENANCE_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_MTM_MPBS_UPDATE_BY_MAINTENANCE_ID`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_maintenance_task_id INT;
    DECLARE p_maintenance_id INT;
    DECLARE p_column_value VARCHAR(100);
    
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(200);
    
    SET p_maintenance_task_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.maintenance_task_id')) AS UNSIGNED);
    SET p_maintenance_id       = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.maintenance_id')) AS UNSIGNED);
    SET p_column_value         = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.column_value'));
    
    IF p_column_value NOT IN ('0', '1') THEN
        SET Success = 0;
        SET Result  = 'Invalid column value. Must be 0 or 1.';
    ELSE
        
        UPDATE maintenance_task_master 
        SET MAINTENANCE_POINT_BARCODE_SCANNED = p_column_value
        WHERE MAINTENANCE_TASK_ID = p_maintenance_task_id 
          AND MAINTENANCE_ID = p_maintenance_id;
        
        IF p_column_value = '1' THEN
            SET Result = 'Maintenance Point Barcode Scanned: Marked';
        ELSE
            SET Result = 'Maintenance Point Barcode Scanned: Unmarked';
        END IF;
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OBM_FEEDBACK_BY_STATION_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OBM_FEEDBACK_BY_STATION_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OBM_FEEDBACK_BY_STATION_ID`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_station_id INT;

    
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);

    
    SELECT
        obm.STATION_ID,
        obm.BIN_ID,
        bim.BIN_SEGMENTS,
        obm.TYPE,
        obm.STATUS AS BIN_STATUS,
        obm.BOT_ID,
        obm.IS_SYNCED,
        obm.INSERTED_TIMESTAMP,
        obm.UPDATED_TIMESTAMP,
        
        CASE 
            WHEN obm.STATUS = 'ON_STATION' 
            THEN CONCAT(TIMESTAMPDIFF(SECOND, obm.UPDATED_TIMESTAMP, NOW()), ' Secs')
            ELSE NULL
        END AS SECONDS_SINCE_ON_STATION
    FROM 
        order_bin_mapping AS obm
    
    
    INNER JOIN (
        SELECT 
            BIN_ID, 
            MAX(UPDATED_TIMESTAMP) AS Latest_Timestamp
        FROM 
            order_bin_mapping
        WHERE 
            STATION_ID = p_station_id
            AND STATUS <> 'TASK_COMPLETED'
        GROUP BY 
            BIN_ID
    ) AS Latest_OBM
        
        ON obm.BIN_ID = Latest_OBM.BIN_ID 
       AND obm.UPDATED_TIMESTAMP = Latest_OBM.Latest_Timestamp
        
    LEFT JOIN 
        bin_info_master AS bim
        ON bim.BIN_ID = obm.BIN_ID
        
    
    WHERE 
        obm.STATION_ID = p_station_id
        AND obm.STATUS <> 'TASK_COMPLETED'
        
    ORDER BY
        
        CASE
            WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'TASK_ALLOCATED'      THEN 1
            WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'PENDING'             THEN 2
            WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'POST_ON_STATION'     THEN 3
            WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'OPERATION_COMPLETED' THEN 4
            WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'ON_STATION'          THEN 5
            WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'PRE_ON_STATION'      THEN 6
            WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'BIN_PICKED'          THEN 7
            WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'TASK_ALLOCATED'      THEN 8
            WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'PENDING'             THEN 9
            ELSE 10
        END,
        obm.UPDATED_TIMESTAMP DESC;

    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OBTM_FEEDBACK_BY_STATION_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OBTM_FEEDBACK_BY_STATION_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OBTM_FEEDBACK_BY_STATION_ID`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_station_id INT;

    
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);

    
    SELECT
        STATION_ID,
        AISLE_ID,
        TOWER_ID,
        TOWER_LEVEL,
        ORDER_BIN_ID,
        BIN_ID,
        INSERTED_TIMESTAMP
    FROM 
        order_bin_task_master
    WHERE 
        STATION_ID = p_station_id
    ORDER BY 
        INSERTED_TIMESTAMP DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_LAST_MESSAGE_UPDATE_BY_STATION_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_LAST_MESSAGE_UPDATE_BY_STATION_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_LAST_MESSAGE_UPDATE_BY_STATION_ID`(IN StationId INT)
BEGIN
    
    DECLARE v_checkStationExists INT DEFAULT 0;
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255) DEFAULT 'Station ID does not exist';
    
    SELECT COUNT(*) 
    INTO v_checkStationExists    
    FROM `hw_display_master` 
    WHERE `PARENT_ID` = stationId
    LIMIT 1;
    
    
    IF v_checkStationExists = 1 THEN
        UPDATE `hw_display_master`
        SET `LAST_MESSAGE` = NULL
        WHERE `PARENT_ID` = StationId;
        
        SET Success = 1;
        SET Result = "Last Message Column Updated Successfully";
        
    ELSE
        
        SET Success = 0;
        SET Result = "Station ID not found. Update failed.";
    END IF;
    
    
    SELECT 
        Success, 
        Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_LIVE_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_LIVE_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_LIVE_STATUS`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_station_id    INT;
    DECLARE p_wave_id       VARCHAR(50);
    DECLARE p_wave_type     VARCHAR(50);
    DECLARE p_screenWise    VARCHAR(50);

    
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_screenWise = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.screen_wise'));

    
    IF p_station_id IS NOT NULL AND p_wave_id IS NOT NULL AND p_screenWise IS NOT NULL THEN
        
        
        SET p_wave_type = NULL;
        
        SELECT `WAVE_TYPE`
        INTO p_wave_type
        FROM `wave_master`
        WHERE `WAVE_ID` = p_wave_id
        LIMIT 1;

        IF p_wave_type IS NULL THEN
            
            SELECT 0 AS `Success`, CONCAT(p_wave_id, ' not exists') AS `Result`;
        ELSE
            
            CASE
                WHEN p_wave_type = 'PUT'          THEN CALL `DSB_OPERATOR_LIVE_STATUS_WAVE_PUT`(Parameters);
                WHEN p_wave_type = 'PICK'         THEN CALL `DSB_OPERATOR_LIVE_STATUS_WAVE_PICK`(Parameters);
                WHEN p_wave_type = 'BIN_LOADING'  THEN CALL `DSB_OPERATOR_LIVE_STATUS_WAVE_BIN_LOADING`(Parameters);
                WHEN p_wave_type = 'STOCK_AUDIT'  THEN CALL `DSB_OPERATOR_LIVE_STATUS_WAVE_STOCK_AUDIT`(Parameters);
                ELSE
                    
                    SELECT 0 AS `Success`, 'Unsupported wave type: ' AS `Result`;
            END CASE;
        END IF;

    ELSE
        
        SELECT 0 AS `Success`, 'Station ID or Wave ID or Search By is NULL' AS `Result`;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_LIVE_STATUS_WAVE_BIN_LOADING` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_LIVE_STATUS_WAVE_BIN_LOADING` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_LIVE_STATUS_WAVE_BIN_LOADING`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_station_id INT;
    DECLARE p_wave_id VARCHAR(50);
    DECLARE p_screenWise VARCHAR(50);

    
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_screenWise = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.screen_wise'));
    
    
    IF (p_screenWise = 'live-gtc') THEN
        SELECT 
            blwom.BIN_ID,
            blwom.BIN_BARCODE, 
            obm.STATUS AS BIN_STATUS,
            blwom.STATUS AS BIN_SEGMENT_STATUS
        FROM 
            bin_loading_wave_order_master AS blwom
        LEFT JOIN 
            order_bin_mapping AS obm 
            ON blwom.BIN_ID = obm.BIN_ID 
            OR blwom.ORDER_BIN_ID = obm.ORDER_BIN_ID
        WHERE 
            blwom.WAVE_ID = p_wave_id
            AND obm.STATION_ID = p_station_id
            AND obm.STATUS IN ('ON_STATION')
            AND obm.TYPE IN ('RACK_PICK')
        ORDER BY 
            obm.UPDATED_TIMESTAMP ASC;
            
    
    ELSEIF (p_screenWise = 'order-list') THEN
        SELECT DISTINCT 
            blwom.BIN_ID,
            blwom.BIN_BARCODE,      
            obm.BOT_ID,
            obm.STATUS AS BIN_STATUS,
            blwom.STATUS AS BIN_SEGMENT_STATUS
        FROM 
            bin_loading_wave_order_master AS blwom
        LEFT JOIN 
            order_bin_mapping AS obm 
            ON blwom.BIN_ID = obm.BIN_ID
        WHERE 
            blwom.WAVE_ID = p_wave_id
            AND obm.STATION_ID = p_station_id
            AND obm.STATUS NOT IN ('TASK_COMPLETED')
        ORDER BY 
            obm.INSERTED_TIMESTAMP DESC 
        LIMIT 30;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_LIVE_STATUS_WAVE_PICK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_LIVE_STATUS_WAVE_PICK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_LIVE_STATUS_WAVE_PICK`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_station_id    INT;
    DECLARE p_wave_id       VARCHAR(50);
    DECLARE p_screenWise    VARCHAR(50);

    
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_screenWise = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.screen_wise'));

    IF (p_screenWise = 'heading') THEN
	SELECT 
	    CONCAT(
		'Batch Picklist Code: ', a.BATCH_PICKLIST_CODE, ' | ',
		'Distinct Order Lines: ', COUNT(DISTINCT pwwd.ORDER_LINE_ID), ' | ',
		'Expected Qty: ', SUM(pwwd.QUANTITY - pwwd.LEFT_OVER)
	    ) AS HEADING
	FROM pick_wave_wms_data AS pwwd
	JOIN wms_to_wcs_order_request_data AS wtword
	      ON pwwd.ORDER_ID = wtword.ORDER_ID
	JOIN wms_to_wcs_order_level_pre_staged_data AS a
	ON a.PARENT_ORDER_ID = wtword.PARENT_ORDER_ID
	WHERE pwwd.WAVE_ID = p_wave_id and
	wtword.`ORDER_REQUEST_STATUS` = 'ORDER_PICK_STARTED'
	GROUP BY 
	    a.BATCH_PICKLIST_CODE;

    
    ELSEIF (p_screenWise = 'live-gtc') THEN
        SELECT DISTINCT
            DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL) AS IMAGE_URL,
            sm.SKU_NAME,
            pwom.EXPECTED_QUANTITY                    AS QUANTITY,
            CONCAT(pwom.BIN_ID, ' - ', pwom.BIN_SEGMENT_NO) AS BIN,
            pwom.BIN_ID,
            pwom.BIN_SEGMENT_NO,
            obm.STATUS                                AS BIN_STATUS,
            pwom.STATUS                               AS BIN_SEGMENT_STATUS
        FROM 
            pick_wave_order_master AS pwom
        LEFT JOIN 
            order_bin_mapping AS obm ON obm.BIN_ID = pwom.BIN_ID
        LEFT JOIN 
            sku_master AS sm ON sm.SKU_ID = pwom.SKU_ID
        WHERE 
            pwom.WAVE_ID     = p_wave_id
            AND obm.STATION_ID   = p_station_id
            AND obm.STATUS IN ('PRE_ON_STATION', 'ON_STATION')
            AND obm.TYPE    IN ('RACK_PICK')
        ORDER BY
            FIELD(obm.STATUS, 'PRE_ON_STATION', 'ON_STATION'),
            obm.UPDATED_TIMESTAMP ASC,
            pwom.BIN_SEGMENT_NO ASC;

    
    ELSEIF (p_screenWise = 'order-list') THEN
        SELECT DISTINCT
            sm.SKU_NAME,
            pwom.EXPECTED_QUANTITY                          AS QUANTITY,
            CONCAT(pwom.BIN_ID, ' - ', pwom.BIN_SEGMENT_NO) AS BIN,
            pwom.BIN_ID,
            pwom.BIN_SEGMENT_NO,
            
            CASE
                
                WHEN EXISTS (
                    SELECT 1
                    FROM store_bin_master
                    WHERE BIN_ID = obm.BIN_ID
                ) THEN 
                    
                    CASE 
                        WHEN obm.TYPE = 'RACK_PICK' 
                            AND obm.STATUS = 'TASK_ALLOCATED' 
                            AND obm.BOT_ID IS NOT NULL
                        THEN CONCAT('RACK (', obm.BOT_ID, ')') 
                        ELSE 'RACK'
                    END
                
                ELSE
                    CASE
                        
                        WHEN obm.TYPE = 'RACK_PICK' 
                            AND obm.STATUS = 'BIN_PICKED' 
                            AND obm.BOT_ID IS NOT NULL
                        THEN obm.BOT_ID
                        
                        
                        WHEN (obm.TYPE = 'RACK_PICK' 
                              AND obm.STATUS IN (
                                    'PRE_ON_STATION',
                                    'POST_ON_STATION',
                                    'ON_STATION',
                                    'OPERATION_COMPLETED'
                                )) 
                                OR (obm.TYPE = 'STATION_PICK' 
                                    AND obm.STATUS IN ('PENDING')
                                )
                        THEN CONCAT('STATION ', obm.STATION_ID)
                        
                        WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'TASK_ALLOCATED' 
			THEN CONCAT('STATION ', obm.STATION_ID, ' (', obm.BOT_ID, ')')
                        
                        
                        WHEN obm1.STATION_ID IS NULL AND obm1.BOT_ID IS NULL THEN NULL
                        WHEN obm1.STATION_ID IS NOT NULL AND obm1.BOT_ID IS NOT NULL THEN CONCAT('STATION ', obm1.STATION_ID, ' (', obm1.BOT_ID, ')')
                        WHEN obm1.BOT_ID IS NULL THEN CONCAT('STATION ', obm1.STATION_ID)
                        ELSE NULL
                    END
            END AS CURRENT_BIN_LOCATION,
            obm.TYPE,
            obm.STATUS                                      AS BIN_STATUS,
            pwom.STATUS                                     AS BIN_SEGMENT_STATUS
        FROM 
            pick_wave_order_master AS pwom
        JOIN 
            order_bin_mapping AS obm ON obm.BIN_ID = pwom.BIN_ID
        LEFT JOIN 
            order_bin_mapping AS obm1 
            ON obm1.BIN_ID = obm.BIN_ID
            AND obm1.TYPE   = 'RACK_PICK'
            AND obm1.STATUS IN (
                'BIN_PICKED',
                'PRE_ON_STATION',
                'POST_ON_STATION',
                'ON_STATION',
                'OPERATION_COMPLETED'
            )
            AND obm1.STATION_ID <> p_station_id
        JOIN 
            sku_master AS sm ON sm.SKU_ID = pwom.SKU_ID
        WHERE 
            pwom.WAVE_ID     = p_wave_id
            AND obm.STATION_ID   = p_station_id
            AND obm.STATUS    <> 'TASK_COMPLETED'
        ORDER BY
            CASE
                
                WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'TASK_ALLOCATED'    THEN 1
                WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'PENDING'           THEN 2
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'POST_ON_STATION'    THEN 3
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'OPERATION_COMPLETED' THEN 4
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'ON_STATION'         THEN 5
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'PRE_ON_STATION'     THEN 6
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'BIN_PICKED'         THEN 7
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'TASK_ALLOCATED'     THEN 8
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'PENDING'            THEN 9
                ELSE 10
            END,
            obm.UPDATED_TIMESTAMP DESC;
        
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_LIVE_STATUS_WAVE_PUT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_LIVE_STATUS_WAVE_PUT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_LIVE_STATUS_WAVE_PUT`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_station_id    INT;
    DECLARE p_wave_id       VARCHAR(50);
    DECLARE p_screenWise    VARCHAR(50);

    
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_screenWise = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.screen_wise'));

    IF (p_screenWise = 'heading') THEN
	SELECT 
	    CONCAT(
		'Pallet Id: ', wwsrp.PALLET_ID, ' | ',
		'Distinct Storages: ', COUNT(DISTINCT pwwd.STORAGE_ID), ' | ',
		'Expected Qty: ', SUM(pwwd.QUANTITY - pwwd.LEFT_OVER)
	    ) AS HEADING
	FROM put_wave_wms_data AS pwwd
	JOIN wms_to_wcs_storage_request_pallet_data AS wwsrp
	      ON pwwd.STORAGE_REQUEST_ID = wwsrp.STORAGE_REQUEST_ID
	WHERE pwwd.WAVE_ID = p_wave_id
	and wwsrp.`STORAGE_REQUEST_STATUS` = 'PALLET_SCANNED'
	GROUP BY 
	    wwsrp.STORAGE_REQUEST_ID;

    
    ELSEIF (p_screenWise = 'live-gtc') THEN
        SELECT DISTINCT
            DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL) AS IMAGE_URL,
            sm.SKU_NAME,
            pwom.EXPECTED_QUANTITY                    AS QUANTITY,
            CONCAT(pwom.BIN_ID, ' - ', pwom.BIN_SEGMENT_NO) AS BIN,
            pwom.BIN_ID,
            pwom.BIN_SEGMENT_NO,
            wtwsrp.PALLET_ID,
            obm.STATUS                                AS BIN_STATUS,
            pwom.STATUS                               AS BIN_SEGMENT_STATUS
        FROM 
            put_wave_order_master AS pwom
        LEFT JOIN 
            order_bin_mapping AS obm ON obm.BIN_ID = pwom.BIN_ID
        LEFT JOIN 
            sku_master AS sm ON sm.SKU_ID = pwom.SKU_ID
        LEFT JOIN 
            wms_to_wcs_storage_request_pallet_data AS wtwsrp 
            ON wtwsrp.STORAGE_REQUEST_ID = pwom.STORAGE_REQUEST_ID
        WHERE 
            pwom.WAVE_ID     = p_wave_id
            AND obm.STATION_ID   = p_station_id
            AND obm.STATUS IN ('PRE_ON_STATION', 'ON_STATION')
            AND obm.TYPE    IN ('RACK_PICK')
        ORDER BY
            FIELD(obm.STATUS, 'PRE_ON_STATION', 'ON_STATION'),
            obm.UPDATED_TIMESTAMP ASC,
            pwom.BIN_SEGMENT_NO ASC;

    
    ELSEIF (p_screenWise = 'order-list') THEN
        SELECT DISTINCT
            sm.SKU_NAME,
            pwom.EXPECTED_QUANTITY                          AS QUANTITY,
            CONCAT(pwom.BIN_ID, ' - ', pwom.BIN_SEGMENT_NO) AS BIN,
            pwom.BIN_ID,
            pwom.BIN_SEGMENT_NO,
            
            CASE
                
                WHEN EXISTS (
                    SELECT 1
                    FROM store_bin_master
                    WHERE BIN_ID = obm.BIN_ID
                ) THEN 
                    
                    CASE 
                        WHEN obm.TYPE = 'RACK_PICK' 
                            AND obm.STATUS = 'TASK_ALLOCATED' 
                            AND obm.BOT_ID IS NOT NULL
                        THEN CONCAT('RACK (', obm.BOT_ID, ')') 
                        ELSE 'RACK'
                    END
                
                ELSE
                    CASE
                        
                        WHEN obm.TYPE = 'RACK_PICK' 
                            AND obm.STATUS = 'BIN_PICKED' 
                            AND obm.BOT_ID IS NOT NULL
                        THEN obm.BOT_ID
                        
                        
                         WHEN (obm.TYPE = 'RACK_PICK' 
                              AND obm.STATUS IN (
                                    'PRE_ON_STATION',
                                    'POST_ON_STATION',
                                    'ON_STATION',
                                    'OPERATION_COMPLETED'
                                )) 
                                OR (obm.TYPE = 'STATION_PICK' 
                                    AND obm.STATUS IN ('PENDING')
                                )
                        THEN CONCAT('STATION ', obm.STATION_ID)
                        
                        WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'TASK_ALLOCATED' 
			THEN CONCAT('STATION ', obm.STATION_ID, ' (', obm.BOT_ID, ')')
                        
                        
                        WHEN obm1.STATION_ID IS NULL AND obm1.BOT_ID IS NULL THEN NULL
                        WHEN obm1.STATION_ID IS NOT NULL AND obm1.BOT_ID IS NOT NULL THEN CONCAT('STATION ', obm1.STATION_ID, ' (', obm1.BOT_ID, ')')
                        WHEN obm1.BOT_ID IS NULL THEN CONCAT('STATION ', obm1.STATION_ID)
                        ELSE NULL
                    END
            END AS CURRENT_BIN_LOCATION,
            obm.TYPE,
            obm.STATUS                                      AS BIN_STATUS,
            pwom.STATUS                                     AS BIN_SEGMENT_STATUS
        FROM 
            put_wave_order_master AS pwom
        LEFT JOIN 
            order_bin_mapping AS obm ON obm.BIN_ID = pwom.BIN_ID
        LEFT JOIN 
            order_bin_mapping AS obm1 
            ON obm1.BIN_ID = obm.BIN_ID
            AND obm1.TYPE   = 'RACK_PICK'
            AND obm1.STATUS IN (
                'BIN_PICKED',
                'PRE_ON_STATION',
                'POST_ON_STATION',
                'ON_STATION',
                'OPERATION_COMPLETED'
            )
            AND obm1.STATION_ID <> p_station_id
        LEFT JOIN 
            sku_master AS sm ON sm.SKU_ID = pwom.SKU_ID
        WHERE 
            pwom.WAVE_ID     = p_wave_id
            AND obm.STATION_ID   = p_station_id
            AND obm.STATUS    <> 'TASK_COMPLETED'
        ORDER BY
            CASE
                
                WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'TASK_ALLOCATED'    THEN 1
                WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'PENDING'           THEN 2
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'POST_ON_STATION'    THEN 3
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'OPERATION_COMPLETED' THEN 4
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'ON_STATION'         THEN 5
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'PRE_ON_STATION'     THEN 6
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'BIN_PICKED'         THEN 7
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'TASK_ALLOCATED'     THEN 8
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'PENDING'            THEN 9
                ELSE 10
            END,
            obm.UPDATED_TIMESTAMP DESC;
        

    
    ELSEIF (p_screenWise = 'storage-request') THEN
        SELECT
            wtwsrd.STORAGE_REQUEST_ID,
            wtwsrd.STORAGE_ID,
            sm.SKU_NAME,
            pwom.EXPECTED_QUANTITY
        FROM 
            wms_to_wcs_storage_request_data AS wtwsrd
        LEFT JOIN 
            put_wave_order_master AS pwom 
            ON pwom.SKU_ID = wtwsrd.ARTICLE_ID
        LEFT JOIN 
            sku_master AS sm 
            ON sm.SKU_ID = pwom.SKU_ID
        WHERE 
            pwom.WAVE_ID    = p_wave_id
            AND pwom.STATION_ID = p_station_id;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_LIVE_STATUS_WAVE_STOCK_AUDIT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_LIVE_STATUS_WAVE_STOCK_AUDIT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_LIVE_STATUS_WAVE_STOCK_AUDIT`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_station_id    INT;
    DECLARE p_wave_id       VARCHAR(50);
    DECLARE p_screenWise    VARCHAR(50);

    
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_screenWise = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.screen_wise'));

    
    
    IF (p_screenWise = 'live-gtc') THEN
        SELECT DISTINCT
            DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL)       AS IMAGE_URL,
            sm.SKU_NAME,
            sawom.EXPECTED_QUANTITY                         AS QUANTITY,
            CONCAT(sawom.BIN_ID, ' - ', sawom.BIN_SEGMENT_NO) AS BIN,
            sawom.BIN_ID,
            sawom.BIN_SEGMENT_NO,
            obm.STATUS                                      AS BIN_STATUS,
            sawom.STATUS                                    AS BIN_SEGMENT_STATUS
        FROM 
            stock_audit_wave_order_master AS sawom
        LEFT JOIN 
            order_bin_mapping AS obm ON obm.BIN_ID = sawom.BIN_ID
        LEFT JOIN 
            sku_master AS sm ON sm.SKU_ID = sawom.SKU_ID
        WHERE 
            sawom.WAVE_ID    = p_wave_id
            AND obm.STATION_ID   = p_station_id
            AND obm.STATUS IN ('PRE_ON_STATION', 'ON_STATION')
            AND obm.TYPE    IN ('RACK_PICK')
        ORDER BY
            FIELD(obm.STATUS, 'PRE_ON_STATION', 'ON_STATION'),
            obm.UPDATED_TIMESTAMP ASC,
            sawom.BIN_SEGMENT_NO ASC;
            
    
    ELSEIF (p_screenWise = 'order-list') THEN
        SELECT DISTINCT
            sm.SKU_NAME,
            sawom.EXPECTED_QUANTITY                         AS QUANTITY,
            CONCAT(sawom.BIN_ID, ' - ', sawom.BIN_SEGMENT_NO) AS BIN,
            sawom.BIN_ID,
            sawom.BIN_SEGMENT_NO,
            
            CASE
                
                WHEN EXISTS (
                    SELECT 1
                    FROM store_bin_master
                    WHERE BIN_ID = obm.BIN_ID
                ) THEN 
                    
                    CASE 
                        WHEN obm.TYPE = 'RACK_PICK' 
                            AND obm.STATUS = 'TASK_ALLOCATED' 
                            AND obm.BOT_ID IS NOT NULL
                        THEN CONCAT('RACK (', obm.BOT_ID, ')') 
                        ELSE 'RACK'
                    END
                
                ELSE
                    CASE
                        
                        WHEN obm.TYPE = 'RACK_PICK' 
                            AND obm.STATUS = 'BIN_PICKED' 
                            AND obm.BOT_ID IS NOT NULL
                        THEN obm.BOT_ID
                        
                        
                         WHEN (obm.TYPE = 'RACK_PICK' 
                              AND obm.STATUS IN (
                                    'PRE_ON_STATION',
                                    'POST_ON_STATION',
                                    'ON_STATION',
                                    'OPERATION_COMPLETED'
                                )) 
                                OR (obm.TYPE = 'STATION_PICK' 
                                    AND obm.STATUS IN ('PENDING')
                                )
                        THEN CONCAT('STATION ', obm.STATION_ID)
                        
                        WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'TASK_ALLOCATED' 
			THEN CONCAT('STATION ', obm.STATION_ID, ' (', obm.BOT_ID, ')')
                        
                        
                        WHEN obm1.STATION_ID IS NULL AND obm1.BOT_ID IS NULL THEN NULL
                        WHEN obm1.STATION_ID IS NOT NULL AND obm1.BOT_ID IS NOT NULL THEN CONCAT('STATION ', obm1.STATION_ID, ' (', obm1.BOT_ID, ')')
                        WHEN obm1.BOT_ID IS NULL THEN CONCAT('STATION ', obm1.STATION_ID)
                        ELSE NULL
                    END
            END AS CURRENT_BIN_LOCATION,
            obm.TYPE,
            obm.STATUS                                      AS BIN_STATUS,
            sawom.STATUS                                    AS BIN_SEGMENT_STATUS
        FROM 
            stock_audit_wave_order_master AS sawom
        LEFT JOIN 
            order_bin_mapping AS obm ON obm.BIN_ID = sawom.BIN_ID
        LEFT JOIN 
            order_bin_mapping AS obm1 
            ON obm1.BIN_ID = obm.BIN_ID
            AND obm1.TYPE   = 'RACK_PICK'
            AND obm1.STATUS IN (
                'BIN_PICKED',
                'PRE_ON_STATION',
                'POST_ON_STATION',
                'ON_STATION',
                'OPERATION_COMPLETED'
            )
            AND obm1.STATION_ID <> p_station_id
        LEFT JOIN 
            sku_master AS sm ON sm.SKU_ID = sawom.SKU_ID
        WHERE 
            sawom.WAVE_ID    = p_wave_id
            AND obm.STATION_ID   = p_station_id
            AND obm.STATUS    <> 'TASK_COMPLETED'
        ORDER BY
            CASE
                
                WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'TASK_ALLOCATED'    THEN 1
                WHEN obm.TYPE = 'STATION_PICK' AND obm.STATUS = 'PENDING'           THEN 2
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'POST_ON_STATION'    THEN 3
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'OPERATION_COMPLETED' THEN 4
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'ON_STATION'         THEN 5
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'PRE_ON_STATION'     THEN 6
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'BIN_PICKED'         THEN 7
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'TASK_ALLOCATED'     THEN 8
                WHEN obm.TYPE = 'RACK_PICK'    AND obm.STATUS = 'PENDING'            THEN 9
                ELSE 10
            END,
            obm.UPDATED_TIMESTAMP DESC;
        
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_LPN_BARCODE_GET_BY_STATION_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_LPN_BARCODE_GET_BY_STATION_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_LPN_BARCODE_GET_BY_STATION_ID`(IN stationId INT)
BEGIN
    
    SELECT 
        `LPN_BARCODE`, 
        `LPN_REASON` 
    FROM 
        `lpn_master_stock_audit`
    WHERE 
        `STATION_ID` = stationId;  
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS`(IN Parameters JSON)
BEGIN
    DECLARE p_wave_id VARCHAR(50);
    DECLARE p_wave_type VARCHAR(50);
    DECLARE p_station_id INT;

    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_wave_type  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_type'));
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);

    IF EXISTS (
        SELECT 1
        FROM wave_master
        WHERE WAVE_ID = p_wave_id
          AND WAVE_STATUS = 'PROCESSING'
    ) THEN
        CASE
            WHEN p_wave_type = 'PUT'         THEN CALL DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_PUT(Parameters);
            WHEN p_wave_type = 'PICK'        THEN CALL DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_PICK(Parameters);
            WHEN p_wave_type = 'STOCK_AUDIT' THEN CALL DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_BIN_RECALL(Parameters);
            WHEN p_wave_type = 'BIN_LOADING' THEN CALL DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_BIN_LOADING(Parameters);
            ELSE SELECT CONCAT('Wave Type Not Found For ', p_wave_id) AS Result;
        END CASE;
    ELSE
        SELECT CONCAT('Wave Not Processing For ', IFNULL(p_wave_id, '')) AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_BIN_LOADING` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_BIN_LOADING` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_BIN_LOADING`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_wave_id      VARCHAR(50);
    DECLARE p_station_id   INT;
    DECLARE v_bin_barcode  VARCHAR(50);

    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);

    SELECT BIN_BARCODE
      INTO v_bin_barcode
    FROM bin_loading_wave_order_master
    WHERE STATION_ID = p_station_id
      AND WAVE_ID    = p_wave_id
      AND STATUS     = 'BIN_REGISTRATION_STARTED'
    LIMIT 1;

    IF v_bin_barcode IS NOT NULL THEN
        SELECT v_bin_barcode AS BIN_BARCODE;
    ELSE
        SELECT 0 AS Success, 'No Data Found' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_BIN_RECALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_BIN_RECALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_BIN_RECALL`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_wave_id    VARCHAR(50);
    DECLARE p_station_id INT;

    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);

    SELECT
        CASE WHEN COALESCE(lim.QUANTITY, 0) = 0 THEN 'no-sku' ELSE sm.SKU_ID   END AS SKU_ID,
        CASE WHEN COALESCE(lim.QUANTITY, 0) = 0 THEN 'no-sku' ELSE sm.SKU_NAME END AS SKU_NAME,
        DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL) AS IMAGE_URL,
        CASE WHEN COALESCE(lim.QUANTITY, 0) = 0 THEN 0        ELSE obm.ORDER_BIN_ID END AS ORDER_BIN_ID,
        CASE WHEN COALESCE(lim.QUANTITY, 0) = 0 THEN 0        ELSE sbm.MRP          END AS MRP,
        CASE WHEN COALESCE(lim.QUANTITY, 0) = 0 THEN '01-01-1970'
             ELSE DATE_FORMAT(sbm.EXPIRY_DATE, '%d-%m-%Y') END AS EXPIRY_DATE,
        sbm.GLN,
        CASE WHEN COALESCE(lim.QUANTITY, 0) = 0 THEN 'no-sku'     ELSE sbm.BATCH_ID     END AS BATCH_ID,
        bim.BIN_BARCODE,
        saom.BIN_ID,
        bim.BIN_SEGMENTS,
        saom.BIN_SEGMENT_NO,
        saom.EXPECTED_QUANTITY,
        saom.STOCK_AUDIT_ORDER_ID
    FROM stock_audit_wave_order_master saom
    INNER JOIN order_bin_mapping obm
        ON obm.ORDER_BIN_ID = saom.ORDER_BIN_ID
       AND obm.STATUS = 'ON_STATION'
    LEFT JOIN sku_master       sm  ON sm.SKU_ID  = saom.SKU_ID
    LEFT JOIN bin_info_master  bim ON bim.BIN_ID = saom.BIN_ID
    LEFT JOIN live_inventory_master lim
        ON lim.ARTICLE_ID = saom.SKU_ID
       AND lim.SEGMENT_NO = saom.BIN_SEGMENT_NO
       AND lim.BIN_ID     = saom.BIN_ID
    LEFT JOIN sku_batch_master sbm
        ON sbm.SKU_ID   = lim.ARTICLE_ID
       AND sbm.BATCH_ID = lim.BATCH_ID
    WHERE saom.WAVE_ID    = p_wave_id
      AND saom.STATION_ID = p_station_id
      AND saom.STATUS     = 'AUDIT_STARTED';
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_PICK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_PICK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_PICK`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_wave_id VARCHAR(50);
    DECLARE p_station_id INT;

    DECLARE v_expected_quantity INT DEFAULT 0;
    DECLARE v_picked_quantity INT DEFAULT 0;
    DECLARE v_short_pick_quantity INT DEFAULT 0;
    DECLARE v_order_bin_id INT;
    DECLARE v_segment_number INT;
    DECLARE v_bin_segment_status VARCHAR(50);

    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);

    SELECT
        pwom.ORDER_BIN_ID,
        pwom.BIN_SEGMENT_NO,
        pwom.STATUS
    INTO v_order_bin_id, v_segment_number, v_bin_segment_status
    FROM pick_wave_order_master pwom
    JOIN order_bin_mapping obm
      ON obm.ORDER_BIN_ID = pwom.ORDER_BIN_ID
     AND obm.STATUS = 'ON_STATION'
    WHERE pwom.WAVE_ID    = p_wave_id
      AND pwom.STATION_ID = p_station_id
      AND pwom.STATUS IN ('PICK_STARTED','MID_WAVE_AUDIT_STARTED')
    ORDER BY pwom.UPDATED_TIMESTAMP DESC
    LIMIT 1;

    IF v_bin_segment_status = 'PICK_STARTED' THEN
        SELECT
            COALESCE(SUM(EXPECTED_QUANTITY),0),
            COALESCE(SUM(PICKED_QUANTITY),0),
            COALESCE(SUM(SHORT_PICK_QUANTITY),0)
        INTO v_expected_quantity, v_picked_quantity, v_short_pick_quantity
        FROM pick_wave_order_master
        WHERE ORDER_BIN_ID   = v_order_bin_id
          AND BIN_SEGMENT_NO = v_segment_number;

        SELECT
            sm.SKU_ID,
            sm.SKU_NAME,
            DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL) AS IMAGE_URL,
            v_order_bin_id AS ORDER_BIN_ID,
            sbm.MRP,
            DATE_FORMAT(sbm.EXPIRY_DATE, '%d-%m-%Y') AS EXPIRY_DATE,
            sem.EAN_ID AS EAN,
            bim.BIN_BARCODE,
            pwom.BIN_ID,
            bim.BIN_SEGMENTS,
            pwom.BIN_SEGMENT_NO,
            v_expected_quantity   AS EXPECTED_QUANTITY,
            v_picked_quantity     AS PICKED_QUANTITY,
            v_short_pick_quantity AS SHORT_PICK_QUANTITY,
            pwom.PICK_ORDER_ID
        FROM pick_wave_order_master pwom
        LEFT JOIN sku_master       sm  ON sm.SKU_ID  = pwom.SKU_ID
        LEFT JOIN sku_batch_master sbm ON sbm.SKU_ID = pwom.SKU_ID
        LEFT JOIN sku_ean_mapping  sem ON sem.SKU_ID = pwom.SKU_ID
        LEFT JOIN bin_info_master  bim ON bim.BIN_ID = pwom.BIN_ID
        WHERE pwom.ORDER_BIN_ID   = v_order_bin_id
          AND pwom.BIN_SEGMENT_NO = v_segment_number
        ORDER BY pwom.UPDATED_TIMESTAMP DESC
        LIMIT 1;

    ELSEIF v_bin_segment_status = 'MID_WAVE_AUDIT_STARTED' THEN
        SELECT
            sm.SKU_ID,
            sm.SKU_NAME,
            DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL) AS IMAGE_URL,
            v_order_bin_id AS ORDER_BIN_ID,
            sbm.MRP,
            DATE_FORMAT(sbm.EXPIRY_DATE, '%d-%m-%Y') AS EXPIRY_DATE,
            sem.EAN_ID AS EAN,
            sbm.GLN,
            sbm.BATCH_ID,
            bim.BIN_BARCODE,
            sawom.BIN_ID,
            bim.BIN_SEGMENTS,
            sawom.BIN_SEGMENT_NO,
            sawom.EXPECTED_QUANTITY,
            sawom.STOCK_AUDIT_ORDER_ID
        FROM stock_audit_wave_order_master sawom
        LEFT JOIN sku_master       sm  ON sm.SKU_ID  = sawom.SKU_ID
        LEFT JOIN sku_batch_master sbm ON sbm.SKU_ID = sawom.SKU_ID
        LEFT JOIN sku_ean_mapping  sem ON sem.SKU_ID = sawom.SKU_ID
        LEFT JOIN bin_info_master  bim ON bim.BIN_ID = sawom.BIN_ID
        WHERE sawom.ORDER_BIN_ID   = v_order_bin_id
          AND sawom.BIN_SEGMENT_NO = v_segment_number
        ORDER BY sawom.UPDATED_TIMESTAMP DESC
        LIMIT 1;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_PUT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_PUT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_ON_STATION_BIN_SEGMENT_DETAILS_PUT`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_wave_id    VARCHAR(50);
    DECLARE p_station_id INT;

    SET p_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);

    WITH pd AS (
        SELECT STORAGE_REQUEST_ID, PALLET_ID
        FROM (
            SELECT
                STORAGE_REQUEST_ID,
                PALLET_ID,
                ROW_NUMBER() OVER (
                    PARTITION BY STORAGE_REQUEST_ID
                    ORDER BY COALESCE(PALLET_COMPLETION_TIMESTAMP, INSERT_TIMESTAMP) DESC
                ) AS rn
            FROM wms_to_wcs_storage_request_pallet_data
        ) t
        WHERE rn = 1
    )
    SELECT
        sm.SKU_ID,
        sm.SKU_NAME,
        DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL) AS IMAGE_URL,
        obm.ORDER_BIN_ID,
        sbm.MRP,
        DATE_FORMAT(sbm.EXPIRY_DATE, '%d-%m-%Y') AS EXPIRY_DATE,
        pwom.EAN_NO AS EAN,
        bim.BIN_BARCODE,
        pwom.BIN_ID,
        bim.BIN_SEGMENTS,
        pwom.BIN_SEGMENT_NO,
        pwom.EXPECTED_QUANTITY,
        pwom.PUT_QUANTITY,
        pwom.PUT_ORDER_ID,
        pd.PALLET_ID
    FROM put_wave_order_master pwom
    INNER JOIN order_bin_mapping obm
        ON obm.ORDER_BIN_ID = pwom.ORDER_BIN_ID
       AND obm.STATUS = 'ON_STATION'
    LEFT JOIN sku_master       sm  ON sm.SKU_ID  = pwom.SKU_ID
    LEFT JOIN sku_batch_master sbm ON sbm.SKU_ID = pwom.SKU_ID
    LEFT JOIN bin_info_master  bim ON bim.BIN_ID = pwom.BIN_ID
    LEFT JOIN pd                    ON pd.STORAGE_REQUEST_ID = pwom.STORAGE_REQUEST_ID
    WHERE pwom.WAVE_ID    = p_wave_id
      AND pwom.STATION_ID = p_station_id
      AND pwom.STATUS     = 'PUT_STARTED'
    ORDER BY pwom.UPDATED_TIMESTAMP DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_OPEN_SHORT_PICK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_OPEN_SHORT_PICK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_OPEN_SHORT_PICK`(
    IN Parameters JSON
)
proc:BEGIN
    DECLARE v_station_id INT;
    DECLARE v_wave_id    VARCHAR(200);
    DECLARE v_ptl_status INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CALL DSB_GENERIC_TRANSACTION_ERROR_HANDLER();
    END;

    
    SET v_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
    SET v_wave_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET v_ptl_status = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ptl_status')) AS UNSIGNED);

    
    IF v_station_id IS NULL OR v_station_id = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'station_id is required';
    END IF;

    IF v_wave_id IS NULL OR v_wave_id = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'wave_id is required';
    END IF;

    IF v_ptl_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ptl_status is required';
    END IF;

    START TRANSACTION;

    IF v_ptl_status = 1 THEN
        
        UPDATE pick_wave_order_master pwo
        INNER JOIN order_bin_mapping obm
            ON obm.order_bin_id = pwo.order_bin_id
           AND obm.`STATUS` = 'ON_STATION'
        SET pwo.SHORT_PICK_QUANTITY = (pwo.EXPECTED_QUANTITY - pwo.PICKED_QUANTITY)
        WHERE pwo.station_id = v_station_id
          AND pwo.wave_id    = v_wave_id
          AND pwo.`STATUS`   = 'PICK_STARTED';

        COMMIT;
        SELECT 1 AS Success, 'PTL Pressing is now OFF' AS Result;

    ELSE
        
        UPDATE pick_wave_order_master pwo
        INNER JOIN order_bin_mapping obm
            ON obm.order_bin_id = pwo.order_bin_id
           AND obm.`STATUS` = 'ON_STATION'
        SET pwo.SHORT_PICK_QUANTITY = -1
        WHERE pwo.station_id = v_station_id
          AND pwo.wave_id    = v_wave_id
          AND pwo.`STATUS`   = 'PICK_STARTED';

        COMMIT;
        SELECT 1 AS Success, 'PTL Pressing is now ON' AS Result;
    END IF;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_OPEN_SHORT_PICK_BKP` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_OPEN_SHORT_PICK_BKP` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_OPEN_SHORT_PICK_BKP`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE stationId INT;
    DECLARE waveId VARCHAR(200);
    DECLARE ptlstatus INT;
    
    SET stationId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id'));
    SET waveId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET ptlstatus = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ptl_status'));
    
    IF ptlstatus = 1 THEN
        
        UPDATE pick_wave_order_master
        SET SHORT_PICK_QUANTITY = EXPECTED_QUANTITY - PICKED_QUANTITY
        WHERE station_id = stationId
          AND wave_id = waveId
          AND order_bin_id IN (
              
              SELECT order_bin_id 
              FROM order_bin_mapping 
              WHERE STATUS = 'ON_STATION'
          )
          AND `STATUS` = 'PICK_STARTED';
        SELECT 1 AS Success, "PTL Pressing is now OFF" AS Result;
    ELSE
        
        UPDATE pick_wave_order_master
        SET SHORT_PICK_QUANTITY = -1
        WHERE station_id = stationId
          AND wave_id = waveId
          AND order_bin_id IN (
              
              SELECT order_bin_id 
              FROM order_bin_mapping 
              WHERE STATUS = 'ON_STATION'
          )
          AND `STATUS` = 'PICK_STARTED';
        SELECT 1 AS Success, "PTL Pressing is now ON" AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_STATION_ID_BY_CLIENT_IP` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_STATION_ID_BY_CLIENT_IP` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_STATION_ID_BY_CLIENT_IP`(IN ClientIPAddress VARCHAR(100))
BEGIN
	IF EXISTS(SELECT 1 FROM hw_display_master WHERE IP = ClientIPAddress) THEN
	    SELECT `PARENT_ID` AS STATION_ID FROM hw_display_master WHERE IP = ClientIPAddress;
	ELSE 
	    SELECT 0 AS STATION_ID;
	END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_SUBMIT_BIN_REGISTRATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_SUBMIT_BIN_REGISTRATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_SUBMIT_BIN_REGISTRATION`(IN Parameters JSON)
BEGIN
    
    DECLARE Success INT DEFAULT 1; 
    DECLARE Result VARCHAR(255) DEFAULT 'Bin loading update completed successfully.';
    
    
    DECLARE p_wave_id VARCHAR(255);
    DECLARE p_station_id INT;
    DECLARE p_bin_segment INT;
    DECLARE p_bin_barcode VARCHAR(255);
    DECLARE p_user_name VARCHAR(255);
    DECLARE p_bin_id VARCHAR(200);
    
    
    SET p_wave_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_station_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id'));
    SET p_bin_segment = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_segment'));
    SET p_bin_barcode = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_barcode'));
    SET p_bin_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_id'));
    SET p_user_name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    
    IF (SELECT COUNT(*) FROM bin_loading_wave_order_master WHERE BIN_ID = p_bin_id) = 0 THEN
        
        UPDATE `bin_loading_wave_order_master`
        SET 
            `BIN_SEGMENT_NO` = p_bin_segment,
            `status` = 'BIN_REGISTRATION_COMPLETED',
            `UPDATED_BY` = p_user_name,
            `BIN_ID` = p_bin_id
        WHERE
            `WAVE_ID` = p_wave_id
            AND `STATION_ID` = p_station_id
            AND `BIN_BARCODE` = p_bin_barcode
            AND `status` = 'BIN_REGISTRATION_STARTED';
        
        IF ROW_COUNT() = 0 THEN
            SET Success = 0;
            SET Result = 'Unknown Error. Not able to Register.';
        END IF;
    ELSE
        
        SET Success = 0;
        SET Result = 'Bin Already Exists';
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_SUBMIT_SHORT_PICK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_SUBMIT_SHORT_PICK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_SUBMIT_SHORT_PICK`(IN Parameters JSON)
BEGIN
    DECLARE _wave_id VARCHAR(50);
    DECLARE _bin_id INT;
    DECLARE _bin_segment_no INT;
    DECLARE _reasons_with_quantity JSON;
    DECLARE _pick_by VARCHAR(20);
    DECLARE _short_pick_quantity INT DEFAULT 0;
    DECLARE _json_length INT;
    DECLARE _index INT DEFAULT 0;
    DECLARE _reason_key VARCHAR(255);
    DECLARE _reason_value INT;
    DECLARE _quant INT;
    DECLARE _id1 INT;
    DECLARE _id2 VARCHAR(200);
    DECLARE _quant2 INT;
    DECLARE _reason VARCHAR(255);
    
    SET _wave_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET _bin_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_id'));
    SET _bin_segment_no = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_segment'));
    SET _reasons_with_quantity = JSON_EXTRACT(Parameters, '$.reasons_with_quantity'); 
    SET _pick_by = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    
    DROP TEMPORARY TABLE IF EXISTS quantityAndReason;
    CREATE TEMPORARY TABLE quantityAndReason (
        id INT AUTO_INCREMENT PRIMARY KEY,
        quantity INT,
        reason VARCHAR(255)
    );
   
    
    DROP TEMPORARY TABLE IF EXISTS shortpickreason;
    CREATE TEMPORARY TABLE shortpickreason (
        id VARCHAR(200),
        quantity INT
    );
    
    INSERT INTO shortpickreason (id, quantity)
    SELECT pwom.`PICK_ORDER_ID`, pwom.`SHORT_PICK_QUANTITY`
    FROM `pick_wave_order_master` pwom
    left outer join 
	(
		select PICK_ORDER_ID,sum(SHORT_PICK_QUANTITY) as SHORT_PICK_QUANTITY 
		from short_pick_wave_reason
		Group by PICK_ORDER_ID 
	) SP on SP.PICK_ORDER_ID=pwom.PICK_ORDER_ID 
    WHERE `BIN_ID` = _bin_id 
      AND `BIN_SEGMENT_NO` = _bin_segment_no 
      AND `WAVE_ID` = _wave_id 
      and (ifnull(SP.SHORT_PICK_QUANTITY,0)<(pwom.`EXPECTED_QUANTITY`- pwom.`PICKED_QUANTITY`));
      
      
    
    SET _json_length = JSON_LENGTH(_reasons_with_quantity);
    
    
    WHILE _index < _json_length DO
        SET _reason_value = JSON_UNQUOTE(JSON_EXTRACT(_reasons_with_quantity, CONCAT('$[', _index, '].Quantity')));
        SET _reason_key = JSON_UNQUOTE(JSON_EXTRACT(_reasons_with_quantity, CONCAT('$[', _index, '].Reason')));
        
        INSERT INTO quantityAndReason (quantity, reason)
        VALUES (_reason_value, _reason_key);
        
        SET _index = _index + 1;
    END WHILE;
    
    SET _index = 0;
    
    
    WHILE (SELECT COUNT(*) FROM quantityAndReason WHERE quantity > 0) > 0 AND 
 (SELECT COUNT(*) FROM shortpickreason WHERE quantity > 0) > 0    
     AND _index < 10000 DO
        SELECT quantity, id, reason INTO _quant, _id1, _reason
        FROM quantityAndReason
        WHERE quantity > 0
        LIMIT 1;
        SELECT id, quantity INTO _id2, _quant2
        FROM shortpickreason
        WHERE quantity > 0
        LIMIT 1;
        IF (_quant > _quant2) THEN
            INSERT INTO `short_pick_wave_reason` (`SHORT_PICK_WAVE_REASON_ID`, `PICK_ORDER_ID`, `SHORT_PICK_QUANTITY`, `REASON`)
            VALUES (UUID(), _id2, _quant2, _reason);
            UPDATE quantityAndReason
            SET quantity = quantity - _quant2
            WHERE id = _id1;
            UPDATE shortpickreason
            SET quantity = 0
            WHERE id = _id2;
        ELSE
		IF NOT EXISTS (
		    SELECT 1 
		    FROM `short_pick_wave_reason`
		    WHERE `PICK_ORDER_ID` = _id2 AND `REASON` = _reason
		) THEN 
		    INSERT INTO `short_pick_wave_reason` (`SHORT_PICK_WAVE_REASON_ID`, `PICK_ORDER_ID`, `SHORT_PICK_QUANTITY`, `REASON`)
		    VALUES (UUID(), _id2, _quant, _reason);
		END IF;
          
          
            UPDATE shortpickreason
            SET quantity = quantity - _quant
            WHERE id = _id2;
            UPDATE quantityAndReason
            SET quantity = 0
            WHERE id = _id1;
        END IF;
        SET _index = _index + 1;
    END WHILE;
    
    IF _index>10000 THEN 
	SELECT 0 AS Success, "Error Occured while assigning reason to pick order id" AS Result;
    ELSE
        SELECT 1 AS Success, "Success" AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_SUBMIT_SHORT_PUT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_SUBMIT_SHORT_PUT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_SUBMIT_SHORT_PUT`(IN Parameters JSON)
BEGIN
    
    DECLARE _wave_id                VARCHAR(200);
    DECLARE _bin_id                 INT;
    DECLARE _bin_segment_no         INT;
    DECLARE _reasons_with_quantity JSON;
    DECLARE _put_by                 VARCHAR(20);
    DECLARE _put_order_id           VARCHAR(200);
    DECLARE _short_put_quantity     INT DEFAULT 0;
    DECLARE _json_length            INT;
    DECLARE _index                  INT DEFAULT 0;
    DECLARE _reason_key             VARCHAR(255);
    DECLARE _reason_value           INT;
    DECLARE _expected_quantity      INT;
    DECLARE userName                VARCHAR(100);
    DECLARE _sku_id                 VARCHAR(200);
    DECLARE _batch_id               VARCHAR(200);
    DECLARE v_station_id INT;    
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CALL DSB_GENERIC_TRANSACTION_ERROR_HANDLER();
    END;
    
    START TRANSACTION;
    
    SET _wave_id                = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET _bin_id                 = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_id')) AS UNSIGNED);
    SET _bin_segment_no         = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_segment')) AS UNSIGNED);
    SET _reasons_with_quantity = JSON_EXTRACT(Parameters, '$.reasons_with_quantity');
    SET _put_order_id           = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.put_order_id'));
    SET _expected_quantity      = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.expected_quantity')) AS UNSIGNED);
    SET _put_by                 = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    SET userName                = _put_by;
    
    SET _json_length = JSON_LENGTH(_reasons_with_quantity);
    
    
    WHILE _index < _json_length DO
        SET _reason_value = CAST(JSON_UNQUOTE(JSON_EXTRACT(_reasons_with_quantity, CONCAT('$[', _index, '].Quantity'))) AS UNSIGNED);
        SET _short_put_quantity = _short_put_quantity + _reason_value;
        SET _reason_key = JSON_UNQUOTE(JSON_EXTRACT(_reasons_with_quantity, CONCAT('$[', _index, '].Reason')));
        
        SET _reason_key = CASE _reason_key
            WHEN 'Damaged Quantity' THEN 'DAMAGED_PRODUCT'
            WHEN 'Missing Quantity' THEN 'MISSING'
            WHEN 'Expired Quantity' THEN 'EXPIRED_PRODUCT'
            WHEN 'No Space in Bin'  THEN 'NO_SPACE_IN_BIN'
            ELSE _reason_key
        END;
        
        SET @short_put_reason_id = UUID();
        INSERT INTO short_put_wave_reason (
            SHORT_PUT_WAVE_REASON_ID,
            PUT_ORDER_ID,
            SHORT_PUT_QUANTITY,
            REASON
        )
        VALUES (
            @short_put_reason_id,
            _put_order_id,
            _reason_value,
            _reason_key
        );
        
        UPDATE short_put_wave_reason
        SET 
            RE_ATTEMPT_FLAG     = 1,
            RE_ATTEMPT_QUANTITY = _reason_value
        WHERE 
            SHORT_PUT_WAVE_REASON_ID = @short_put_reason_id
            AND PUT_ORDER_ID = _put_order_id
            and _reason_key = 'NO_SPACE_IN_BIN';
        
        INSERT INTO put_wave_wms_data (
            WAVE_ID,
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            STATION_ID,
            SKU_ID,
            BATCH_ID,
            QUANTITY,
            LEFT_OVER,
            INSERTED_BY,
            UPDATED_BY
        ) 
        SELECT
            _wave_id,
            pwo.STORAGE_REQUEST_ID,
            pwo.STORAGE_ID,
            hsm.STATION_ID,
            pwo.SKU_ID,
		pwo.BATCH_ID,
            _reason_value,
            CASE 
                WHEN _reason_key = 'NO_SPACE_IN_BIN' THEN 0 
                ELSE _reason_value 
            END,
            userName,
            userName
        FROM put_wave_order_master pwo
        INNER JOIN hw_station_master hsm ON hsm.WAVE_ID = pwo.WAVE_ID
        WHERE pwo.WAVE_ID = _wave_id 
  AND pwo.PUT_ORDER_ID = _put_order_id
        and _reason_key = 'NO_SPACE_IN_BIN';
        SET _index = _index + 1;
    END WHILE;
    
    UPDATE put_wave_order_master
    SET 
        SHORT_PUT_QUANTITY = _short_put_quantity,
        PUT_QUANTITY       = (_expected_quantity - _short_put_quantity),
        STATUS             = 'PUT_COMPLETED',
        PUT_TIMESTAMP      = NOW(),
        PUT_BY             = userName,
        UPDATED_BY         = userName
    WHERE 
        BIN_ID         = _bin_id 
        AND BIN_SEGMENT_NO = _bin_segment_no 
        AND WAVE_ID        = _wave_id
        AND PUT_ORDER_ID   = _put_order_id;
        
        COMMIT;
    
    SELECT 1 AS Success, 'Put Submitted Successfully' AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_SUBMIT_SHORT_PUT_BKP` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_SUBMIT_SHORT_PUT_BKP` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_SUBMIT_SHORT_PUT_BKP`(IN Parameters JSON)
BEGIN
    
    DECLARE _wave_id                VARCHAR(200);
    DECLARE _bin_id                 INT;
    DECLARE _bin_segment_no         INT;
    DECLARE _reasons_with_quantity JSON;
    DECLARE _put_by                 VARCHAR(20);
    DECLARE _put_order_id           VARCHAR(200);
    DECLARE _short_put_quantity     INT DEFAULT 0;
    DECLARE _json_length            INT;
    DECLARE _index                  INT DEFAULT 0;
    DECLARE _reason_key             VARCHAR(255);
    DECLARE _reason_value           INT;
    DECLARE _expected_quantity      INT;
    DECLARE userName                VARCHAR(100);
    DECLARE _sku_id                 VARCHAR(200);
    DECLARE _batch_id               VARCHAR(200);
    DECLARE v_station_id INT;
    
    SET _wave_id                = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET _bin_id                 = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_id')) AS UNSIGNED);
    SET _bin_segment_no         = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_segment')) AS UNSIGNED);
    SET _reasons_with_quantity = JSON_EXTRACT(Parameters, '$.reasons_with_quantity');
    SET _put_order_id           = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.put_order_id'));
    SET _expected_quantity      = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.expected_quantity')) AS UNSIGNED);
    SET _put_by                 = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    SET userName                = _put_by;
    
    SET _json_length = JSON_LENGTH(_reasons_with_quantity);
    
    
    WHILE _index < _json_length DO
        SET _reason_value = CAST(JSON_UNQUOTE(JSON_EXTRACT(_reasons_with_quantity, CONCAT('$[', _index, '].Quantity'))) AS UNSIGNED);
        SET _short_put_quantity = _short_put_quantity + _reason_value;
        SET _reason_key = JSON_UNQUOTE(JSON_EXTRACT(_reasons_with_quantity, CONCAT('$[', _index, '].Reason')));
        
        SET _reason_key = CASE _reason_key
            WHEN 'Damaged Quantity' THEN 'DAMAGED_PRODUCT'
            WHEN 'Missing Quantity' THEN 'MISSING'
            WHEN 'Expired Quantity' THEN 'EXPIRED_PRODUCT'
            WHEN 'No Space in Bin'  THEN 'NO_SPACE_IN_BIN'
            ELSE _reason_key
        END;
        
        SET @short_put_reason_id = UUID();
        INSERT INTO short_put_wave_reason (
            SHORT_PUT_WAVE_REASON_ID,
            PUT_ORDER_ID,
            SHORT_PUT_QUANTITY,
            REASON
        )
        VALUES (
            @short_put_reason_id,
            _put_order_id,
            _reason_value,
            _reason_key
        );
        
        UPDATE short_put_wave_reason
        SET 
            RE_ATTEMPT_FLAG     = 1,
            RE_ATTEMPT_QUANTITY = _reason_value
        WHERE 
            SHORT_PUT_WAVE_REASON_ID = @short_put_reason_id
            AND PUT_ORDER_ID = _put_order_id
            and _reason_key = 'NO_SPACE_IN_BIN';
        
        INSERT INTO put_wave_wms_data (
            WAVE_ID,
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            STATION_ID,
            SKU_ID,
            BATCH_ID,
            QUANTITY,
            LEFT_OVER,
            INSERTED_BY,
            UPDATED_BY
        ) 
        SELECT
            _wave_id,
            pwo.STORAGE_REQUEST_ID,
            pwo.STORAGE_ID,
            hsm.STATION_ID,
            pwo.SKU_ID,
		pwo.BATCH_ID,
            _reason_value,
            CASE 
                WHEN _reason_key = 'NO_SPACE_IN_BIN' THEN 0 
                ELSE _reason_value 
            END,
            userName,
            userName
        FROM put_wave_order_master pwo
        INNER JOIN hw_station_master hsm ON hsm.WAVE_ID = pwo.WAVE_ID
        WHERE pwo.WAVE_ID = _wave_id 
  AND pwo.PUT_ORDER_ID = _put_order_id
        and _reason_key = 'NO_SPACE_IN_BIN';
        SET _index = _index + 1;
    END WHILE;
    
    UPDATE put_wave_order_master
    SET 
        SHORT_PUT_QUANTITY = _short_put_quantity,
        PUT_QUANTITY       = (_expected_quantity - _short_put_quantity),
        STATUS             = 'PUT_COMPLETED',
        PUT_TIMESTAMP      = NOW(),
        PUT_BY             = userName,
        UPDATED_BY         = userName
    WHERE 
        BIN_ID         = _bin_id 
        AND BIN_SEGMENT_NO = _bin_segment_no 
        AND WAVE_ID        = _wave_id
        AND PUT_ORDER_ID   = _put_order_id;
    
    SELECT 1 AS Success, 'Put Submitted Successfully' AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_SUBMIT_SHORT_PUT_NEW` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_SUBMIT_SHORT_PUT_NEW` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_SUBMIT_SHORT_PUT_NEW`(IN Parameters JSON)
proc:BEGIN
    DECLARE v_wave_id            VARCHAR(200);
    DECLARE v_bin_id             INT;
    DECLARE v_bin_segment_no     INT;
    DECLARE v_reasons            JSON;
    DECLARE v_put_order_id       VARCHAR(200);
    DECLARE v_expected_qty       INT;
    DECLARE v_user_name          VARCHAR(100);

    DECLARE v_short_put_qty      INT DEFAULT 0;

    DECLARE v_storage_request_id VARCHAR(200);
    DECLARE v_storage_id         VARCHAR(200);
    DECLARE v_station_id         INT;
    DECLARE v_sku_id             VARCHAR(200);
    DECLARE v_batch_id           VARCHAR(200);
    DECLARE v_curr_status        VARCHAR(50);

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CALL DSB_GENERIC_TRANSACTION_ERROR_HANDLER();
    END;

    
    SET v_wave_id        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET v_bin_id         = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_id')) AS UNSIGNED);
    SET v_bin_segment_no = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_segment')) AS UNSIGNED);
    SET v_reasons        = JSON_EXTRACT(Parameters, '$.reasons_with_quantity');
    SET v_put_order_id   = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.put_order_id'));
    SET v_expected_qty   = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.expected_quantity')) AS UNSIGNED);
    SET v_user_name      = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));

    
    IF v_wave_id IS NULL OR v_wave_id = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'wave_id is required';
    END IF;

    IF v_put_order_id IS NULL OR v_put_order_id = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'put_order_id is required';
    END IF;

    IF v_bin_id IS NULL OR v_bin_id = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'bin_id is required';
    END IF;

    IF v_bin_segment_no IS NULL OR v_bin_segment_no = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'bin_segment is required';
    END IF;

    IF v_expected_qty IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'expected_quantity is required';
    END IF;

    IF v_reasons IS NULL OR JSON_LENGTH(v_reasons) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'reasons_with_quantity is empty';
    END IF;

    START TRANSACTION;

    
    SELECT
        pwo.STORAGE_REQUEST_ID,
        pwo.STORAGE_ID,
        pwo.SKU_ID,
        pwo.BATCH_ID,
        pwo.STATUS
    INTO
        v_storage_request_id,
        v_storage_id,
        v_sku_id,
        v_batch_id,
        v_curr_status
    FROM put_wave_order_master pwo
    WHERE pwo.WAVE_ID = v_wave_id
      AND pwo.PUT_ORDER_ID = v_put_order_id
      AND pwo.BIN_ID = v_bin_id
      AND pwo.BIN_SEGMENT_NO = v_bin_segment_no
    LIMIT 1
    FOR UPDATE;

    IF v_storage_request_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PUT order not found for given wave/bin/segment/put_order_id';
    END IF;

    IF v_curr_status = 'PUT_COMPLETED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PUT already submitted (PUT_COMPLETED)';
    END IF;

    
    SELECT hsm.STATION_ID
    INTO v_station_id
    FROM hw_station_master hsm
    WHERE hsm.WAVE_ID = v_wave_id
    ORDER BY hsm.STATION_ID
    LIMIT 1;

    IF v_station_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Station not found for wave_id';
    END IF;

    
    SELECT IFNULL(SUM(jt.qty), 0)
    INTO v_short_put_qty
    FROM JSON_TABLE(v_reasons, '$[*]'
        COLUMNS (
            qty    INT PATH '$.Quantity' NULL ON ERROR,
            reason VARCHAR(255) PATH '$.Reason' NULL ON ERROR
        )
    ) jt
    WHERE jt.qty IS NOT NULL AND jt.qty > 0;

    IF v_short_put_qty > v_expected_qty THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = 'Short put quantity cannot be greater than expected_quantity';
    END IF;

    
    INSERT ignore INTO short_put_wave_reason (
        SHORT_PUT_WAVE_REASON_ID,
        PUT_ORDER_ID,
        SHORT_PUT_QUANTITY,
        REASON,
        RE_ATTEMPT_FLAG,
        RE_ATTEMPT_QUANTITY
    )
    SELECT
        UUID(),
        v_put_order_id,
        jt.qty,
        jt.norm_reason,
        CASE WHEN jt.norm_reason = 'NO_SPACE_IN_BIN' THEN 1 ELSE 0 END,
        CASE WHEN jt.norm_reason = 'NO_SPACE_IN_BIN' THEN jt.qty ELSE 0 END
    FROM (
        SELECT
            jt.qty,
            CASE TRIM(jt.reason)
                WHEN 'Damaged Quantity' THEN 'DAMAGED_PRODUCT'
                WHEN 'Missing Quantity' THEN 'MISSING'
                WHEN 'Expired Quantity' THEN 'EXPIRED_PRODUCT'
                WHEN 'No Space in Bin'  THEN 'NO_SPACE_IN_BIN'
                ELSE TRIM(jt.reason)
            END AS norm_reason
        FROM JSON_TABLE(v_reasons, '$[*]'
            COLUMNS (
                qty    INT PATH '$.Quantity' NULL ON ERROR,
                reason VARCHAR(255) PATH '$.Reason' NULL ON ERROR
            )
        ) jt
        WHERE jt.qty IS NOT NULL AND jt.qty > 0
          AND jt.reason IS NOT NULL AND TRIM(jt.reason) <> ''
    ) jt;
    
    

     if row_count() > 0 then 
	    
	    INSERT INTO put_wave_wms_data (
		WAVE_ID,
		STORAGE_REQUEST_ID,
		STORAGE_ID,
		STATION_ID,
		SKU_ID,
		BATCH_ID,
		QUANTITY,
		LEFT_OVER,
		INSERTED_BY,
		UPDATED_BY
	    )
	    SELECT
		v_wave_id,
		v_storage_request_id,
		v_storage_id,
		v_station_id,
		v_sku_id,
		v_batch_id,
		jt.qty,
		0,
		v_user_name,
		v_user_name
	    FROM (
		SELECT
		    jt.qty,
		    CASE TRIM(jt.reason)
			WHEN 'Damaged Quantity' THEN 'DAMAGED_PRODUCT'
			WHEN 'Missing Quantity' THEN 'MISSING'
			WHEN 'Expired Quantity' THEN 'EXPIRED_PRODUCT'
			WHEN 'No Space in Bin'  THEN 'NO_SPACE_IN_BIN'
			ELSE TRIM(jt.reason)
		    END AS norm_reason
		FROM JSON_TABLE(v_reasons, '$[*]'
		    COLUMNS (
			qty    INT PATH '$.Quantity' NULL ON ERROR,
			reason VARCHAR(255) PATH '$.Reason' NULL ON ERROR
		    )
		) jt
		WHERE jt.qty IS NOT NULL AND jt.qty > 0
		  AND jt.reason IS NOT NULL AND TRIM(jt.reason) <> ''
	    ) jt
	    WHERE jt.norm_reason = 'NO_SPACE_IN_BIN';

	    
	    UPDATE put_wave_order_master
	    SET
		SHORT_PUT_QUANTITY = v_short_put_qty,
		PUT_QUANTITY       = (v_expected_qty - v_short_put_qty),
		STATUS             = 'PUT_COMPLETED',
		PUT_TIMESTAMP      = NOW(3),
		PUT_BY             = v_user_name,
		UPDATED_BY         = v_user_name
	    WHERE
		BIN_ID         = v_bin_id
		AND BIN_SEGMENT_NO = v_bin_segment_no
		AND WAVE_ID        = v_wave_id
		AND PUT_ORDER_ID   = v_put_order_id;

	    IF ROW_COUNT() <> 1 THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'PUT order update failed (no row updated)';
	    END IF;
     end if;
    COMMIT;

    SELECT 1 AS Success, 'Put Submitted Successfully' AS Result;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_SUBMIT_STOCK_AUDIT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_SUBMIT_STOCK_AUDIT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_OPERATOR_SUBMIT_STOCK_AUDIT`(IN Parameters JSON)
BEGIN
    DECLARE Success INT DEFAULT 1;
    DECLARE Result  VARCHAR(255) DEFAULT 'Stock audit completed successfully.';

    DECLARE p_wave_id               VARCHAR(50);
    DECLARE p_stock_audit_order_id  VARCHAR(50);
    DECLARE p_bin_id                VARCHAR(10);
    DECLARE p_bin_segment_no        INT;
    DECLARE p_sku_id                VARCHAR(50);
    DECLARE p_updated_sku_id        VARCHAR(50);
    DECLARE p_batch_id              VARCHAR(50);
    DECLARE p_updated_batch_id      VARCHAR(50);
    
    DECLARE p_expected_quantity     INT;
    DECLARE p_updated_quantity      INT;
    DECLARE p_stock_audit_list      JSON;
    DECLARE p_audit_status          VARCHAR(50);
    DECLARE p_audit_type            VARCHAR(50);
    DECLARE p_user_name             VARCHAR(50);
    DECLARE p_audit_start_timestamp VARCHAR(50);
    DECLARE p_audit_close_timestamp VARCHAR(50);
    DECLARE v_errorMessage     TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
     GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;
        ROLLBACK;
        SELECT 0 AS Success, v_errorMessage AS Result;
    END;

    SET p_wave_id               = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_stock_audit_order_id  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.stock_audit_order_id'));
    SET p_bin_id                = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_id'));
    SET p_bin_segment_no        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.bin_segment_no'));
    SET p_sku_id                = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sku_id'));
    SET p_updated_sku_id        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.updated_sku_id'));
    SET p_batch_id              = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.batch_id'));
    SET p_updated_batch_id      = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.updated_batch_id'));
    
    SET p_expected_quantity     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.expected_quantity'));
    SET p_updated_quantity      = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.updated_quantity'));
    SET p_stock_audit_list      = JSON_EXTRACT(Parameters, '$.stock_audit_list');
    SET p_audit_status          = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.audit_status'));
    SET p_audit_type            = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.audit_type'));

    SET @raw_start_ts = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.audit_start_timestamp'));
    SET @raw_close_ts = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.audit_close_timestamp'));

    
        SET p_audit_start_timestamp = STR_TO_DATE(@raw_start_ts, '%Y-%m-%d %H:%i:%s');
    

    
        SET p_audit_close_timestamp = STR_TO_DATE(@raw_close_ts, '%Y-%m-%d %H:%i:%s');
    

    SET p_user_name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));

    START TRANSACTION;

    SET @stock_audit_id = UUID();

    INSERT INTO `stock_audit_bin_segments_details`
        (`ID`, `STOCK_AUDIT_ORDER_ID`, `TYPE`, `WAVE_ID`, `BIN_ID`, `BIN_SEGMENT_NO`,
         `PREV_SKU_ID`, `UPDATED_SKU_ID`, `PREV_BATCH_ID`, `UPDATED_BATCH_ID`,
         `PREV_QUANTITY`, `UPDATED_QUANTITY`, `AUDIT_BY`, `AUDIT_START_TIMESTAMP`, `AUDIT_CLOSE_TIMESTAMP`)
    VALUES
        (@stock_audit_id, p_stock_audit_order_id, p_audit_type, p_wave_id, p_bin_id, p_bin_segment_no,
         p_sku_id, p_updated_sku_id, p_batch_id, p_updated_batch_id,
         p_expected_quantity, p_updated_quantity,  
         p_user_name, p_audit_start_timestamp, p_audit_close_timestamp);

    INSERT INTO `stock_audit_reason_list`
        (`ID`, `STOCK_AUDIT_BIN_SEGMENTS_ID`, `BATCH_ID`, `LPN_ID`, `REASON`, `QUANTITY`)
    SELECT
        UUID(),
        @stock_audit_id,
        p_batch_id,
        JSON_UNQUOTE(JSON_EXTRACT(line.value,  '$.lpn_id')),
        JSON_UNQUOTE(JSON_EXTRACT(line.value,  '$.reason')),
        JSON_UNQUOTE(JSON_EXTRACT(line.value,  '$.quantity'))
    FROM JSON_TABLE(p_stock_audit_list, '$[*]' COLUMNS (value JSON PATH '$')) AS line;

    UPDATE `stock_audit_wave_order_master`
    SET
        `UPDATED_SKU_ID`   = p_updated_sku_id,
        `UPDATED_QUANTITY` = p_updated_quantity,
        `UPDATED_BATCH_ID` = p_updated_batch_id,
        `AUDIT_BY`         = p_user_name,
        `STATUS`           = p_audit_status
    WHERE `STOCK_AUDIT_ORDER_ID` = p_stock_audit_order_id;   

    COMMIT;

    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_OPERATOR_WAVE_SHORT_PUT_SUBMIT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_OPERATOR_WAVE_SHORT_PUT_SUBMIT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_OPERATOR_WAVE_SHORT_PUT_SUBMIT`(
    IN Parameters JSON
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION  
    BEGIN  
        ROLLBACK;  
        SELECT 0 AS SUCCESS, 'Failed due to error' AS MESSAGE;
    END;
    DROP TEMPORARY TABLE IF EXISTS temp_short_put_data;
    CREATE TEMPORARY TABLE temp_short_put_data (
        storage_id VARCHAR(36),
        put_order_id VARCHAR(36),
        short_put_quantity INT,
        inserted_by VARCHAR(100)
    );
    INSERT INTO temp_short_put_data (storage_id, put_order_id, short_put_quantity, inserted_by)
    SELECT 
        jt.storage_id,
        jt.put_order_id,
        jt.short_put_quantity,
        jt.inserted_by
    FROM JSON_TABLE(
        Parameters,
        '$[*]' COLUMNS (
            storage_id VARCHAR(36) PATH '$.storage_id',
            put_order_id VARCHAR(36) PATH '$.put_order_id',
            short_put_quantity INT PATH '$.short_put_quantity',
            inserted_by VARCHAR(100) PATH '$.inserted_by'
        )
    ) AS jt;
    START TRANSACTION;
    IF EXISTS (
        SELECT 1 
        FROM short_put_wave_reason spwr
        INNER JOIN temp_short_put_data tmp ON spwr.PUT_ORDER_ID = tmp.put_order_id
        WHERE spwr.RE_ATTEMPT_FLAG = 1
    ) THEN
        ROLLBACK;
        SELECT 0 AS Success, 'PUT SHORT already created' AS Result;
    ELSE
        UPDATE short_put_wave_reason spwr
        INNER JOIN temp_short_put_data tmp ON spwr.PUT_ORDER_ID = tmp.put_order_id
        SET 
            spwr.RE_ATTEMPT_FLAG = 1,
            spwr.RE_ATTEMPT_QUANTITY = tmp.short_put_quantity;
        INSERT INTO put_wave_wms_data (
            WAVE_ID,
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            SKU_ID,
            BATCH_ID,
            QUANTITY,
            LEFT_OVER,
            INSERTED_BY,
            UPDATED_BY
        ) 
        SELECT
            pwom.WAVE_ID,
            pwom.STORAGE_REQUEST_ID,
            pwom.STORAGE_ID,
            pwom.SKU_ID,
            pwom.BATCH_ID,
            SUM(tmp.short_put_quantity) AS QUANTITY,
            0,
            tmp.inserted_by,
            tmp.inserted_by
        FROM temp_short_put_data tmp
        INNER JOIN put_wave_order_master pwom ON pwom.PUT_ORDER_ID = tmp.put_order_id
        GROUP BY tmp.storage_id;
        
        COMMIT;
        SELECT 1 AS Success, 'Short Put Submitted Successfully' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_report_name VARCHAR(255);
    DECLARE p_table_unique_identifier VARCHAR(255);
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_wave_id VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    
    SET p_report_name               = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.report_name'));
    SET p_table_unique_identifier  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.table_unique_identifier'));
    SET p_report_extra_parameters  = JSON_EXTRACT(Parameters, '$.report_extra_parameters');
    SET p_wave_id                  = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
    IF p_report_name = 'PAGINATED_0_SITE_BIN_REGISTRATION' THEN
	CALL DSB_0_UAT_SITE_PAGINATED_BIN_REGISTRATION_LIST(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_ALL_BLOCKED_LOCATIONS' THEN
        CALL DSB_PAGINATED_DATA_LOCATION_BLOCK_MASTER(Parameters);
    ELSEIF p_report_name = 'PAGINATED_ALL_BIN_INFO' THEN
        CALL DSB_PAGINATED_DATA_BIN_INFO(Parameters);
    ELSEIF p_report_name = 'PAGINATED_ALL_USERS' THEN
        CALL DSB_PAGINATED_DATA_USERS(Parameters);
    ELSEIF p_report_name = 'PAGINATED_SKU_MASTER' THEN
        CALL DSB_PAGINATED_DATA_SKU_MASTER(Parameters);
    ELSEIF p_report_name = 'PAGINATED_SKU_EAN_MAPPING' THEN
        CALL DSB_PAGINATED_DATA_SKU_EAN_MAPPING(Parameters);
    ELSEIF p_report_name = 'PAGINATED_LIVE_INVENTORY' THEN
        CALL DSB_PAGINATED_DATA_LIVE_INVENTORY(Parameters);
    ELSEIF p_report_name = 'PAGINATED_ALARM_HISTORY_BY_BOT_ID' THEN
        CALL DSB_PAGINATED_DATA_ALARM_HISTORY_BY_BOT_ID(Parameters);
    ELSEIF p_report_name = 'PAGINATED_WAVE_PICK_OVERALL_SUMMARY' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_WAVE_PICK_OVERALL_ORDER_LEVEL_SUMMARY' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LEVEL_SUMMARY(Parameters);
 
    ELSEIF p_report_name = 'PAGINATED_WAVE_PICK_OVERALL_ORDER_LINE_LEVEL_SUMMARY' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LINE_LEVEL_SUMMARY(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_WAVE_PICK_OVERALL_LPN_LEVEL_SUMMARY' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_LPN_LEVEL_SUMMARY(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_WAVE_PUT_OVERALL_SUMMARY' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_SUMMARY(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_WAVE_PICK_OVERALL_SR_LEVEL_SUMMARY' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_SR_LEVEL_SUMMARY(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_WAVE_PICK_OVERALL_STORAGE_LEVEL_SUMMARY' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_STORAGE_LEVEL_SUMMARY(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_WAVE_PICK_OVERALL_BIN_LEVEL_SUMMARY' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_BIN_LEVEL_SUMMARY(Parameters);
    ELSEIF p_report_name IN (
        'PAGINATED_PICK_WAVE',
        'PAGINATED_PUT_WAVE',
        'PAGINATED_STOCK_AUDIT_WAVE',
        'PAGINATED_BIN_LOADING_WAVE'
    ) THEN
        IF p_wave_id IS NOT NULL AND p_wave_id != '' THEN
            IF p_table_unique_identifier IN ('report_wave_pick_orders', 'report_wave_pick_orders_wms') THEN
                CALL DSB_PAGINATED_DATA_WAVE_PICK_ORDERS(Parameters);
            ELSEIF p_table_unique_identifier = 'report_wave_pick_bin_level' THEN
                CALL DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL(Parameters);
            ELSEIF p_table_unique_identifier IN ('report_wave_put_orders', 'report_wave_put_orders_wms') THEN
                CALL DSB_PAGINATED_DATA_WAVE_PUT_ORDERS(Parameters);
            ELSEIF p_table_unique_identifier = 'report_wave_put_bin_level' THEN
                CALL DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL(Parameters);
            ELSEIF p_table_unique_identifier = 'report_wave_put_left_over' THEN
                CALL DSB_PAGINATED_DATA_WAVE_PUT_WAVE_LEFT_OVER(Parameters);
            ELSEIF p_table_unique_identifier = 'report_wave_pick_left_over' THEN
                CALL DSB_PAGINATED_DATA_WAVE_PICK_WAVE_LEFT_OVER(Parameters);
            ELSEIF p_table_unique_identifier IN (
                'report_wave_stock_audit_orders',
                'report_wave_stock_audit_orders_wms',
                'report_wave_stock_audit_orders_temp'
            ) THEN
                CALL DSB_PAGINATED_DATA_WAVE_STOCK_AUDIT_ORDERS(Parameters);
            ELSEIF p_table_unique_identifier = 'report_wave_stock_audit_bin_level' THEN
                CALL DSB_PAGINATED_DATA_WAVE_STOCK_AUDIT_BIN_LEVEL(Parameters);
            ELSEIF p_table_unique_identifier = 'report_wave_bin_loading_orders' THEN
                CALL DSB_PAGINATED_DATA_WAVE_BIN_LOADING_ORDERS(Parameters);
            ELSEIF p_table_unique_identifier = 'report_wave_put_pending_orders' THEN
                CALL DSB_PAGINATED_DATA_WAVE_PUT_PENDING_ORDERS(Parameters);
            END IF;
        ELSE
            CALL DSB_PAGINATED_DATA_WAVE_GENERIC(Parameters);
        END IF;
    ELSEIF p_report_name = 'PAGINATED_TOWER_DETAILS_BY_X_Y' THEN
        CALL DSB_PAGINATED_DATA_TOWER_DETAILS_BY_X_Y(Parameters);
    ELSEIF p_report_name = 'PAGINATED_SHORT_PUT_LIST' THEN
        CALL DSB_PAGINATED_DATA_SHORT_PUT_LIST(Parameters);
    ELSEIF p_report_name = 'PAGINATED_BOT_HISTORY' THEN
        CALL DSB_PAGINATED_DATA_BOT_HISTORY(Parameters);
    ELSEIF p_report_name = 'PAGINATED_SYSTEM_LEVEL_BIN_SUMMARY' THEN
        IF p_table_unique_identifier = 'report_system_level_bin_summary' THEN
            CALL DSB_PAGINATED_DATA_SYSTEM_LEVEL_BIN_SUMMARY(Parameters);
        ELSEIF p_table_unique_identifier = 'report_bin_level_summary' THEN
            CALL DSB_PAGINATED_DATA_BIN_LEVEL_SUMMARY(Parameters);
        ELSEIF p_table_unique_identifier = 'report_bin_segment_level_summary' THEN
            CALL DSB_PAGINATED_DATA_BIN_SEGMENT_LEVEL_SUMMARY(Parameters);
        END IF;
        
    ELSEIF p_report_name = 'PAGINATED_API_REQUEST_RESPONSE' THEN
	CALL DSB_PAGINATED_DATA_API_REQUEST_RESPONSE(Parameters);
    ELSEIF p_report_name = 'PAGINATED_WMS_WCS_INVENTORY_SYNC' THEN
	CALL DSB_PAGINATED_DATA_WMS_WCS_INVENTORY_SYNC(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_DATA_WAVE_PICK_BIN_LEVEL_BY_DATE' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL_BY_DATE(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_DATE_WAVE_PUT_BIN_LEVEL_BY_DATE' THEN
	CALL DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL_BY_DATE(Parameters);
    ELSEIF p_report_name = 'PAGINATED_IPP_REPORT' THEN
	CALL DSB_PAGINATED_IPP_BY_BATCH_STATION(Parameters);
    ELSEIF p_report_name = 'PAGINATED_IPP_REPORT_PICK' THEN
	CALL DSB_PAGINATED_IPP_REPORT_PICK(Parameters);
    ELSEIF p_report_name = 'PAGINATED_IPP_REPORT_PUT' THEN
	CALL DSB_PAGINATED_IPP_REPORT_PUT(Parameters);
	
    ELSEIF p_report_name = 'PAGINATED_GLOBAL_PAUSE_LIST' THEN
	CALL DSB_PAGINATED_DATA_GLOBAL_PAUSE(Parameters);
    ELSEIF p_report_name = 'PAGINATED_INVENTORY_SYNC_HISTORY' THEN
	CALL DSB_PAGINATED_DATA_INVENTORY_SYNC_HISTORY(Parameters);
    ELSEIF p_report_name = 'PAGINATED_GTC_CAMERA_NO_READ_LIST' THEN
	CALL DSB_PAGINATED_DATA_GTC_CAMERA_NO_READ(Parameters);
    ELSEIF p_report_name = 'PAGINATED_DATA_PUT_WAVE_ANALYSIS_BY_DATE' THEN
	CALL DSB_PAGINATED_DATA_PUT_WAVE_ANALYSIS_BY_DATE(Parameters);
    ELSEIF p_report_name = 'PAGINATED_DATA_ORDER_SPLIT_ANALYSIS' THEN
	CALL DSB_PAGINATED_DATA_ORDER_SPLIT_ANALYSIS(Parameters);
    
    ELSE
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid report name provided.';
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_ALARM_HISTORY_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_ALARM_HISTORY_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_ALARM_HISTORY_BY_BOT_ID`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_table_unique_identifier VARCHAR(50);
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_alaram_type VARCHAR(50);
    DECLARE p_bot_id VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    DECLARE AlarmID BIGINT DEFAULT 0;
    DECLARE Inserted_time DATETIME;
    DECLARE BINOPERATION VARCHAR(100);
    DECLARE BOTOPERATION VARCHAR(100);
    DECLARE ACTION_INSTRUCTION VARCHAR(200);
    
    SET p_page_number             = Parameters ->> '$.page_number';
    SET p_rows_per_page           = Parameters ->> '$.rows_per_page';
    SET p_user_id                 = Parameters ->> '$.user_id';
    SET p_user_name               = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag              = Parameters ->> '$.count';
    SET p_filter_condition        = Parameters ->> '$.filter_data';
    SET p_select_clause           = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name     = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby  = Parameters ->> '$.sorting_column_orderby';
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_alaram_type             = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.alarm_type'));
    SET p_bot_id                  = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.bot_id'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
        OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `ALARM TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    IF p_alaram_type = 'normal' THEN
        SET p_table_unique_identifier = 'report_alarm_history_normal';
    ELSEIF p_alaram_type = 'manual' THEN
        SET p_table_unique_identifier = 'report_alarm_history_manual';
    ELSEIF p_alaram_type = 'maintenance' THEN
        SET p_table_unique_identifier = 'report_alarm_history_maintenance';
    ELSEIF p_alaram_type = 'bypass' THEN
        SET p_table_unique_identifier = 'report_alarm_history_bypass';
    ELSE
        SELECT 0 AS Success, 'Wrong Alarm History Type' AS Result;
    END IF;
    
    IF p_table_unique_identifier = 'report_alarm_history_normal' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                BOT_ID AS 'BOT ID', 
                ALARM_CODE AS 'ALARM CODE', 
                ALARM_DESCRIPTION AS 'ALARM DESCRIPTION',
                TASK_TYPE AS 'TASK TYPE',
                ALARMPOSITION_X AS 'ALARM POSITION (X)',
                ALARMPOSITION_Y AS 'ALARM POSITION (Y)',
                ALARMPOSITION_Z AS 'ALARM POSITION (Z)',
                INSERTED_TIMESTAMP AS 'ALARM TIME'
            FROM 
                bot_alarm_log
            WHERE
                BOT_ID = '", p_bot_id, "'", p_filter_condition
        );
    ELSEIF p_table_unique_identifier = 'report_alarm_history_manual' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                BOT_ID AS 'BOT ID', 
                ALARM_DESCRIPTION AS 'ALARM DESCRIPTION', 
                INSERTED_TIMESTAMP AS 'ALARM TIME'
            FROM 
                bot_manual_alarm_log
            WHERE 
                BOT_ID = '", p_bot_id, "'", p_filter_condition
        );
    ELSEIF p_table_unique_identifier = 'report_alarm_history_bypass' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                bal.BOT_ID AS 'BOT ID', 
                bal.ALARM_ID AS 'ALARM CODE', 
                mam.ALARM_DESCRIPTION AS 'ALARM DESCRIPTION', 
                bal.INSERTED_TIMESTAMP AS 'ALARM TIME', 
                bal.IS_BYPASSED AS 'IS BYPASSED'
             FROM 
                bot_manual_alarm_log bal
             LEFT JOIN 
                manual_alarm_master mam ON bal.alarm_id = mam.alarm_id
             WHERE 
                mam.bypass = 1 
                AND bal.BOT_ID = '", p_bot_id, "'", p_filter_condition
        );
    ELSEIF p_table_unique_identifier = 'report_alarm_history_maintenance' THEN
        
        SELECT ID, INSERTED_TIMESTAMP 
        INTO AlarmID, Inserted_time 
        FROM maintenance_alarm_logs 
        WHERE BOT_ID = p_bot_id 
          AND ALARM_DESCRIPTION = 'Slider Servo Error' 
        ORDER BY ID DESC LIMIT 1;
        
        SELECT 
            CONCAT('Bin ', PICK_PUT),
            CONCAT('BOT is performing ', PICK_PUT, ' operation'),
            CASE 
                WHEN PICK_PUT = 'PICK' THEN 'Keep Bin Back in Rack'
                WHEN PICK_PUT = 'PUT' THEN 'Keep Bin on Bot'
                ELSE NULL
            END
        INTO BINOPERATION, BOTOPERATION, ACTION_INSTRUCTION
        FROM steps_archive
        WHERE BOT_ID = p_bot_id
          AND PICK_PUT IN ('PICK', 'PUT')
          AND INSERT_TIME < Inserted_time
        ORDER BY ID DESC LIMIT 1;
        SET v_base_query = CONCAT(
            "SELECT 
                BOT_ID AS 'BOT ID', 
                ALARM_CODE AS 'ALARM CODE', 
                ALARM_DESCRIPTION AS 'ALARM DESCRIPTION', 
                TASK_TYPE AS 'TASK TYPE',
                ALARMPOSITION_X AS 'ALARM POSITION (X)',
                ALARMPOSITION_Y AS 'ALARM POSITION (Y)',
                ALARMPOSITION_Z AS 'ALARM POSITION (Z)',
                INSERTED_TIMESTAMP AS 'ALARM TIME',
                CASE 
                    WHEN ID = ", IFNULL(AlarmID, 0), " THEN '", IFNULL(BINOPERATION, ''), "'           
                    ELSE NULL
                END AS 'BIN OPERATION',
                CASE 
                    WHEN ID = ", IFNULL(AlarmID, 0), " THEN '", IFNULL(BOTOPERATION, ''), "'
                    ELSE NULL
                END AS 'BOT OPERATION',
                CASE 
                    WHEN ID = ", IFNULL(AlarmID, 0), " THEN '", IFNULL(ACTION_INSTRUCTION, ''), "'
                    ELSE NULL
                END AS 'ACTION INSTRUCTION'
            FROM 
                maintenance_alarm_logs
            WHERE 
                BOT_ID = '", p_bot_id, "'", p_filter_condition
        );
    END IF;
    
    SET v_paginated_query = CONCAT(
        'SELECT ', p_select_clause,
        ' FROM (', v_base_query, ') AS subquery',
        v_sorting,
        ' LIMIT ', p_page_number * p_rows_per_page, ', ', p_rows_per_page
    );
    
    SET @countQuery = CONCAT('SELECT COUNT(*) INTO @rowCount FROM (', v_base_query, ') AS t');
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_API_REQUEST_RESPONSE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_API_REQUEST_RESPONSE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_API_REQUEST_RESPONSE`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number              INT;
    DECLARE p_rows_per_page           INT;
    DECLARE p_download_flag           BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag              INT;
    DECLARE p_filter_condition        VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause           TEXT;
    DECLARE p_sorting_column_name     VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby  VARCHAR(50) DEFAULT '';
    DECLARE p_user_id                 VARCHAR(50);
    DECLARE p_user_name               VARCHAR(50);
    DECLARE p_table_unique_identifier VARCHAR(50);
    DECLARE p_report_name             VARCHAR(255);
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_start_date_time         VARCHAR(50);
    DECLARE p_end_date_time           VARCHAR(50);
    DECLARE p_api_id                  INT;
    
    DECLARE v_sorting         VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_base_query      TEXT;
    DECLARE v_total_rows      INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number              = Parameters ->> '$.page_number';
    SET p_rows_per_page           = Parameters ->> '$.rows_per_page';
    SET p_user_id                 = Parameters ->> '$.user_id';
    SET p_user_name               = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag              = Parameters ->> '$.count';
    SET p_filter_condition        = Parameters ->> '$.filter_data';
    SET p_select_clause           = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name     = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby  = Parameters ->> '$.sorting_column_orderby';
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_name             = Parameters ->> '$.report_name';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    SET p_api_id                  = CAST(JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.api_id')) AS UNSIGNED);
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `INSERTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = CONCAT(
            " WHERE wtwp.API_ID = ", p_api_id,
            " AND wtwp.INSERTED_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'"
        );
    ELSE
        SET p_filter_condition = CONCAT(
            " WHERE wtwp.API_ID = ", p_api_id,
            " AND wtwp.INSERTED_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "' ",
            p_filter_condition
        );
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    SELECT DSB_OPERATION_TYPE, DSB_TABLE_TO_FETCH 
    INTO @OperationType, @TableToFetch 
    FROM api_master 
    WHERE API_ID = p_api_id;
    SET @live_payload_table = @TableToFetch;
    SET @archive_payload_table = CONCAT(@TableToFetch, '_archive');
    
    IF @OperationType = 'PICK' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                am.API_TYPE AS 'API TYPE',
                wtwp.HTTP_STATUS AS 'HTTP STATUS',
		CASE 
		    WHEN wtwp.IS_PROCESSED = -1 THEN 'FAILED'
		    WHEN wtwp.IS_PROCESSED = 0 THEN 'PENDING'
		    WHEN wtwp.IS_PROCESSED = 1 THEN 'SUCCESS'
		    WHEN wtwp.IS_PROCESSED = 2 THEN 'IN PROGRESS'
		    ELSE 'UNKNOWN'
		END AS 'STATUS',
                wtwp.IDEMPOTENCY_KEY AS 'IDEMPOTENCY KEY',
                wtword.GLN AS 'GLN',
                wtword.PARENT_ORDER_ID AS 'ORDER ID',
                wtword.BATCH_PICKLIST_CODE AS 'BATCH PICKLIST CODE',
                wtwp.JSON_REQUEST AS 'JSON REQUEST',
                wtwp.JSON_RESPONSE AS 'JSON RESPONSE', 
                wtwp.NO_OF_ATTEMPTS AS 'NO OF ATTEMPTS',
                DATE_FORMAT(wtwp.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME'
             FROM ", @live_payload_table, " wtwp
             LEFT JOIN api_master am ON am.API_ID = wtwp.API_ID
             LEFT JOIN wms_to_wcs_order_level_pre_staged_data wtword ON wtword.ACK_PAYLOAD_ID = wtwp.PAYLOAD_ID",
             p_filter_condition, "
             UNION ALL
             SELECT 
                am.API_TYPE AS 'API TYPE',
                wtwp.HTTP_STATUS AS 'HTTP STATUS',
                CASE 
		    WHEN wtwp.IS_PROCESSED = -1 THEN 'FAILED'
		    WHEN wtwp.IS_PROCESSED = 0 THEN 'PENDING'
		    WHEN wtwp.IS_PROCESSED = 1 THEN 'SUCCESS'
		    WHEN wtwp.IS_PROCESSED = 2 THEN 'IN PROGRESS'
		    ELSE 'UNKNOWN'
		END AS 'STATUS',
                wtwp.IDEMPOTENCY_KEY AS 'IDEMPOTENCY KEY',
                wtword.GLN AS 'GLN',
                wtword.PARENT_ORDER_ID AS 'ORDER ID',
                wtword.BATCH_PICKLIST_CODE AS 'BATCH PICKLIST CODE',
                wtwp.JSON_REQUEST AS 'JSON REQUEST',
                wtwp.JSON_RESPONSE AS 'JSON RESPONSE', 
                wtwp.NO_OF_ATTEMPTS AS 'NO OF ATTEMPTS',
                DATE_FORMAT(wtwp.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME'
             FROM ", @archive_payload_table, " wtwp
             LEFT JOIN api_master am ON am.API_ID = wtwp.API_ID
             LEFT JOIN wms_to_wcs_order_level_pre_staged_data wtword ON wtword.ACK_PAYLOAD_ID = wtwp.PAYLOAD_ID",
             p_filter_condition
        );
    ELSEIF @OperationType = 'PUT' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                am.API_TYPE AS 'API TYPE',
                wtwp.HTTP_STATUS AS 'HTTP STATUS',
                CASE 
		    WHEN wtwp.IS_PROCESSED = -1 THEN 'FAILED'
		    WHEN wtwp.IS_PROCESSED = 0 THEN 'PENDING'
		    WHEN wtwp.IS_PROCESSED = 1 THEN 'SUCCESS'
		    WHEN wtwp.IS_PROCESSED = 2 THEN 'IN PROGRESS'
		    ELSE 'UNKNOWN'
		END AS 'STATUS',
                wtwp.IDEMPOTENCY_KEY AS 'IDEMPOTENCY KEY',
                wtwsrd.STORAGE_REQUEST_ID AS 'STORAGE REQUEST ID',
                wtwsrd.STORAGE_ID AS 'STORAGE ID',
                wtwp.JSON_REQUEST AS 'JSON REQUEST',
                wtwp.JSON_RESPONSE AS 'JSON RESPONSE', 
                wtwp.NO_OF_ATTEMPTS AS 'NO OF ATTEMPTS',
                DATE_FORMAT(wtwp.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME'
             FROM ", @live_payload_table, " wtwp
             LEFT JOIN api_master am ON am.API_ID = wtwp.API_ID
             LEFT JOIN wms_to_wcs_storage_request_data wtwsrd ON wtwsrd.PAYLOAD_ID = wtwp.PAYLOAD_ID",
             p_filter_condition, "
             UNION ALL
             SELECT 
                am.API_TYPE AS 'API TYPE',
                wtwp.HTTP_STATUS AS 'HTTP STATUS',
                CASE 
		    WHEN wtwp.IS_PROCESSED = -1 THEN 'FAILED'
		    WHEN wtwp.IS_PROCESSED = 0 THEN 'PENDING'
		    WHEN wtwp.IS_PROCESSED = 1 THEN 'SUCCESS'
		    WHEN wtwp.IS_PROCESSED = 2 THEN 'IN PROGRESS'
		    ELSE 'UNKNOWN'
		END AS 'STATUS',
                wtwp.IDEMPOTENCY_KEY AS 'IDEMPOTENCY KEY',
                wtwsrd.STORAGE_REQUEST_ID AS 'STORAGE REQUEST ID',
                wtwsrd.STORAGE_ID AS 'STORAGE ID',
                wtwp.JSON_REQUEST AS 'JSON REQUEST',
                wtwp.JSON_RESPONSE AS 'JSON RESPONSE', 
                wtwp.NO_OF_ATTEMPTS AS 'NO OF ATTEMPTS',
                DATE_FORMAT(wtwp.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME'
             FROM ", @archive_payload_table, " wtwp
             LEFT JOIN api_master am ON am.API_ID = wtwp.API_ID
             LEFT JOIN wms_to_wcs_storage_request_data wtwsrd ON wtwsrd.PAYLOAD_ID = wtwp.PAYLOAD_ID",
             p_filter_condition
        );
    END IF;
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery",
        v_sorting,
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    SET @countQuery = CONCAT("SELECT COUNT(*) INTO @rowCount FROM (", v_base_query, ") AS t");
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_BIN_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_BIN_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_BIN_INFO`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_table_unique_identifier VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number               = Parameters ->> '$.page_number';
    SET p_rows_per_page            = Parameters ->> '$.rows_per_page';
    SET p_user_id                  = Parameters ->> '$.user_id';
    SET p_user_name                = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag  = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag               = Parameters ->> '$.count';
    SET p_filter_condition         = Parameters ->> '$.filter_data';
    SET p_select_clause            = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name      = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby   = Parameters ->> '$.sorting_column_orderby';
    SET p_table_unique_identifier  = Parameters ->> '$.table_unique_identifier';
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = '';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' AND ', p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    SET v_base_query = CONCAT(
        "SELECT 
            bim.BIN_ID AS 'BIN ID', 
            bim.BIN_BARCODE AS 'BIN BARCODE', 
            bim.BIN_SEGMENTS AS 'BIN SEGMENTS',
            lm.AISLE_NUMBER AS 'AISLE NUMBER', 
            lm.TOWER_NUMBER AS 'TOWER NUMBER',
            CASE
                WHEN lm.Y IN (
                    SELECT DISTINCT (Y - 1) FROM location_master WHERE TYPE LIKE 'TOWER%'
                ) THEN 'LEFT'
                WHEN lm.Y IN (
                    SELECT DISTINCT (Y + 1) FROM location_master WHERE TYPE LIKE 'TOWER%'
                ) THEN 'RIGHT'
                ELSE NULL
            END AS 'TOWER SIDE',
            lm.Z AS 'LEVEL',
            lm.LOCATION_ID AS 'LOCATION ID', 
            lm.X AS 'X',
            lm.Y AS 'Y'
         FROM bin_info_master bim 
         LEFT JOIN store_bin_master sbm ON sbm.BIN_ID = bim.BIN_ID
         LEFT JOIN location_master lm ON sbm.LOCATION_ID = lm.LOCATION_ID 
         WHERE bim.BIN_BARCODE NOT LIKE 'D%'",
         p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery",
        v_sorting,
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    SET @countQuery = CONCAT("SELECT COUNT(*) INTO @rowCount FROM (", v_base_query, ") AS t");
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_BIN_LEVEL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_BIN_LEVEL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_BIN_LEVEL_SUMMARY`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_table_unique_identifier VARCHAR(50);
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_drill_down_filter VARCHAR(100) DEFAULT '';
    
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    DECLARE v_bin_volume DECIMAL(15,3) DEFAULT 0;
    DECLARE v_drill_down_condition TEXT DEFAULT '';
    
    
    SET p_page_number                = Parameters ->> '$.page_number';
    SET p_rows_per_page             = Parameters ->> '$.rows_per_page';
    SET p_user_id                   = Parameters ->> '$.user_id';
    SET p_user_name                 = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag   = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag                = Parameters ->> '$.count';
    SET p_filter_condition          = Parameters ->> '$.filter_data';
    SET p_select_clause             = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name       = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby    = Parameters ->> '$.sorting_column_orderby';
    SET p_table_unique_identifier   = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters   = Parameters ->> '$.report_extra_parameters';
    
    
    IF p_report_extra_parameters IS NOT NULL THEN
        SET p_drill_down_filter = COALESCE(p_report_extra_parameters ->> '$.filter_type', '');
    END IF;
    
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    
    SET v_bin_volume = 81 * 57 * 42.5 * 0.95; 
    
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `% UTILISATION` DESC, `BIN ID` ASC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' WHERE (', p_filter_condition, ')');
    END IF;
    
    
    CASE p_drill_down_filter
        WHEN 'Total Bins' THEN
            
            SET v_drill_down_condition = '';
            
        WHEN 'Empty Bins' THEN
            
            SET v_drill_down_condition = ' AND bin_analysis.utilization_percentage = 0';
            
        WHEN 'Partially Utilized Bins' THEN
            
            SET v_drill_down_condition = ' AND bin_analysis.utilization_percentage > 0 AND bin_analysis.utilization_percentage < 90';
            
        WHEN 'Fully Utilized Bins' THEN
            
            SET v_drill_down_condition = ' AND bin_analysis.utilization_percentage >= 90';
            
        ELSE
            
            SET v_drill_down_condition = '';
    END CASE;
    
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    
    SET v_base_query = CONCAT(
        "SELECT 
            CASE 
                WHEN bin_analysis.BIN_BARCODE IS NOT NULL AND bin_analysis.BIN_BARCODE != '' 
                THEN bin_analysis.BIN_BARCODE
                ELSE CONCAT('BIN-', LPAD(bin_analysis.BIN_ID, 6, '0'))
            END AS 'BIN ID',
            bin_analysis.total_partitions AS 'PARTITIONS',
            bin_analysis.used_partitions AS 'USED PARTITIONS',
            bin_analysis.empty_partitions AS 'EMPTY PARTITIONS',
            FORMAT(ROUND(bin_analysis.volume_used, 0), 0) AS 'VOLUME USED (CM³)',
            FORMAT(ROUND(bin_analysis.total_volume, 0), 0) AS 'TOTAL VOLUME (CM³)',
            CONCAT(ROUND(bin_analysis.utilization_percentage, 0), '%') AS '% UTILISATION'
        FROM (
            SELECT 
                bim.BIN_ID,
                bim.BIN_BARCODE,
                COALESCE(bim.BIN_SEGMENTS, 1) AS total_partitions,
                COUNT(DISTINCT CASE 
                    WHEN lim.SEGMENT_NO IS NOT NULL 
                        AND COALESCE(lim.QUANTITY, 0) > 0 
                        AND (lim.IS_ACTIVE IS NULL OR lim.IS_ACTIVE = 1)
                    THEN lim.SEGMENT_NO 
                    END
                ) AS used_partitions,
                (COALESCE(bim.BIN_SEGMENTS, 1) - COUNT(DISTINCT CASE 
                    WHEN lim.SEGMENT_NO IS NOT NULL 
                        AND COALESCE(lim.QUANTITY, 0) > 0 
                        AND (lim.IS_ACTIVE IS NULL OR lim.IS_ACTIVE = 1)
                    THEN lim.SEGMENT_NO 
                    END
                )) AS empty_partitions,
                COALESCE(SUM(
                    CASE 
                        WHEN (lim.IS_ACTIVE IS NULL OR lim.IS_ACTIVE = 1) 
                            AND (sm.IS_ACTIVE IS NULL OR sm.IS_ACTIVE = 1)
                        THEN COALESCE(lim.QUANTITY, 0) * COALESCE((sm.LENGTH * sm.WIDTH * sm.HEIGHT) / 1000, 0)
                        ELSE 0 
                    END
                ), 0) AS volume_used,
                ", v_bin_volume, " AS total_volume,
                CASE 
                    WHEN ", v_bin_volume, " > 0 THEN (COALESCE(SUM(
                        CASE 
                            WHEN (lim.IS_ACTIVE IS NULL OR lim.IS_ACTIVE = 1) 
                                AND (sm.IS_ACTIVE IS NULL OR sm.IS_ACTIVE = 1)
                            THEN COALESCE(lim.QUANTITY, 0) * COALESCE((sm.LENGTH * sm.WIDTH * sm.HEIGHT) / 1000, 0)
                            ELSE 0 
                        END
                    ), 0) / ", v_bin_volume, ") * 100
                    ELSE 0 
                END AS utilization_percentage
            FROM bin_info_master bim
            LEFT JOIN live_inventory_master lim ON bim.BIN_ID = lim.BIN_ID
            LEFT JOIN sku_master sm ON lim.ARTICLE_ID = sm.SKU_ID
            GROUP BY bim.BIN_ID, bim.BIN_BARCODE, bim.BIN_SEGMENTS
        ) bin_analysis
        WHERE 1=1", 
        v_drill_down_condition
    );
    
    
    IF p_filter_condition != '' THEN
        SET v_base_query = REPLACE(v_base_query, 'WHERE 1=1', CONCAT('WHERE 1=1 ', SUBSTRING(p_filter_condition, 2))); 
    END IF;
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery", 
        v_sorting, 
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    
    SET @countQuery = CONCAT('SELECT COUNT(*) INTO @rowCount FROM (', v_base_query, ') AS t');
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_BIN_SEGMENT_LEVEL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_BIN_SEGMENT_LEVEL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_BIN_SEGMENT_LEVEL_SUMMARY`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_table_unique_identifier VARCHAR(50);
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_bin_id_filter VARCHAR(50) DEFAULT NULL;
    DECLARE p_bin_barcode_filter VARCHAR(50) DEFAULT NULL;
    
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    DECLARE v_bin_volume DECIMAL(15,3) DEFAULT 0;
    DECLARE v_bin_filter TEXT DEFAULT '';
    DECLARE v_numeric_bin_id INT DEFAULT NULL;
    
    
    SET p_page_number                = Parameters ->> '$.page_number';
    SET p_rows_per_page             = Parameters ->> '$.rows_per_page';
    SET p_user_id                   = Parameters ->> '$.user_id';
    SET p_user_name                 = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag   = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag                = Parameters ->> '$.count';
    SET p_filter_condition          = Parameters ->> '$.filter_data';
    SET p_select_clause             = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name       = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby    = Parameters ->> '$.sorting_column_orderby';
    SET p_table_unique_identifier   = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters   = Parameters ->> '$.report_extra_parameters';
    
    
    IF p_report_extra_parameters IS NOT NULL THEN
        SET p_bin_id_filter = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.bin_id'));
        SET p_bin_barcode_filter = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.bin_barcode'));
    END IF;
    
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    
    SET v_bin_volume = 81 * 57 * 42.5 * 0.95; 
    
    
    IF p_bin_id_filter IS NOT NULL AND p_bin_id_filter != '' THEN
        
        IF p_bin_id_filter LIKE 'BIN-%' THEN
            
            SET v_numeric_bin_id = CAST(SUBSTRING(p_bin_id_filter, 5) AS UNSIGNED);
            SET v_bin_filter = CONCAT(' AND bim.BIN_ID = ', v_numeric_bin_id);
        ELSEIF p_bin_id_filter LIKE 'N%' THEN
            
            SET v_bin_filter = CONCAT(' AND bim.BIN_BARCODE = ''', p_bin_id_filter, '''');
        ELSE
            
            SET v_numeric_bin_id = CAST(p_bin_id_filter AS UNSIGNED);
            SET v_bin_filter = CONCAT(' AND bim.BIN_ID = ', v_numeric_bin_id);
        END IF;
    ELSEIF p_bin_barcode_filter IS NOT NULL AND p_bin_barcode_filter != '' THEN
        
        SET v_bin_filter = CONCAT(' AND bim.BIN_BARCODE = ''', p_bin_barcode_filter, '''');
    END IF;
    
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `BIN ID` ASC, `PARTITION` ASC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' WHERE (', p_filter_condition, ')');
    END IF;
    
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    
    SET v_base_query = CONCAT(
        "SELECT 
            CASE 
                WHEN partition_analysis.BIN_BARCODE IS NOT NULL AND partition_analysis.BIN_BARCODE != '' 
                THEN partition_analysis.BIN_BARCODE
                ELSE CONCAT('BIN-', LPAD(partition_analysis.BIN_ID, 6, '0'))
            END AS 'BIN ID',
            partition_analysis.PARTITION_NO AS 'PARTITION',
            partition_analysis.SKU_NAME AS 'SKU NAME',
            FORMAT(ROUND(partition_analysis.volume_used, 0), 0) AS 'VOLUME USED (CM³)',
            FORMAT(ROUND(partition_analysis.max_volume_per_partition, 0), 0) AS 'MAX VOLUME PER PARTITION',
            CONCAT(ROUND(partition_analysis.utilization_percentage, 0), '%') AS '% UTILISED'
        FROM (
            SELECT 
                all_partitions.BIN_ID,
                all_partitions.BIN_BARCODE,
                all_partitions.PARTITION_NO,
                COALESCE(inventory_data.SKU_NAME, 'Empty') AS SKU_NAME,
                COALESCE(inventory_data.total_volume_used, 0) AS volume_used,
                all_partitions.max_volume_per_partition,
                CASE 
                    WHEN all_partitions.max_volume_per_partition > 0 
                    THEN (COALESCE(inventory_data.total_volume_used, 0) / all_partitions.max_volume_per_partition) * 100
                    ELSE 0 
                END AS utilization_percentage
            FROM (
                SELECT 
                    bim.BIN_ID,
                    bim.BIN_BARCODE,
                    segment_numbers.segment_no AS PARTITION_NO,
                    ", v_bin_volume, " / COALESCE(bim.BIN_SEGMENTS, 1) AS max_volume_per_partition
                FROM bin_info_master bim
                CROSS JOIN (
                    SELECT 1 AS segment_no UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL 
                    SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL 
                    SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
                ) segment_numbers
                WHERE segment_numbers.segment_no <= COALESCE(bim.BIN_SEGMENTS, 1)", 
                v_bin_filter, "
            ) all_partitions
            LEFT JOIN (
                SELECT 
                    lim.BIN_ID,
                    lim.SEGMENT_NO,
                    GROUP_CONCAT(DISTINCT COALESCE(sm.SKU_NAME, lim.ARTICLE_ID) ORDER BY (lim.QUANTITY * COALESCE((sm.LENGTH * sm.WIDTH * sm.HEIGHT) / 1000, 0)) DESC SEPARATOR ', ') AS SKU_NAME,
                    SUM(COALESCE(lim.QUANTITY, 0) * COALESCE((sm.LENGTH * sm.WIDTH * sm.HEIGHT) / 1000, 0)) AS total_volume_used
                FROM live_inventory_master lim
                LEFT JOIN sku_master sm ON lim.ARTICLE_ID = sm.SKU_ID 
                    AND (sm.IS_ACTIVE IS NULL OR sm.IS_ACTIVE = 1)
                WHERE (lim.IS_ACTIVE IS NULL OR lim.IS_ACTIVE = 1)
                    AND COALESCE(lim.QUANTITY, 0) > 0
                GROUP BY lim.BIN_ID, lim.SEGMENT_NO
            ) inventory_data ON all_partitions.BIN_ID = inventory_data.BIN_ID 
                AND all_partitions.PARTITION_NO = inventory_data.SEGMENT_NO
        ) partition_analysis",
        p_filter_condition
    );
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery", 
        v_sorting, 
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    
    SET @countQuery = CONCAT('SELECT COUNT(*) INTO @rowCount FROM (', v_base_query, ') AS t');
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_BOT_HISTORY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_BOT_HISTORY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_BOT_HISTORY`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_table_unique_identifier VARCHAR(50);
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_bot_id VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number              = Parameters ->> '$.page_number';
    SET p_rows_per_page           = Parameters ->> '$.rows_per_page';
    SET p_user_id                 = Parameters ->> '$.user_id';
    SET p_user_name               = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag              = Parameters ->> '$.count';
    SET p_filter_condition        = Parameters ->> '$.filter_data';
    SET p_select_clause           = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name     = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby  = Parameters ->> '$.sorting_column_orderby';
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_bot_id                  = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.bot_id'));
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        IF p_table_unique_identifier = 'table_bot_history_order_bin_mapping' THEN
            SET v_sorting = ' ORDER BY `UPDATED TIME` DESC';
        ELSEIF p_table_unique_identifier = 'table_bot_history_order_bin_mapping_log' THEN
            SET v_sorting = ' ORDER BY `LOGGED TIME` DESC';
        ELSEIF p_table_unique_identifier = 'table_bot_history_task_master' THEN
            SET v_sorting = ' ORDER BY `UPDATED TIME` DESC';
        ELSEIF p_table_unique_identifier = 'table_bot_history_task_master_log' THEN
            SET v_sorting = ' ORDER BY `LOGGED TIME` DESC';
        ELSEIF p_table_unique_identifier = 'table_bot_history_task_detail' THEN
            SET v_sorting = ' ORDER BY `UPDATED TIME` DESC';
        ELSEIF p_table_unique_identifier = 'table_bot_history_task_detail_log' THEN
            SET v_sorting = ' ORDER BY `LOGGED TIME` DESC';
        ELSEIF p_table_unique_identifier = 'table_bot_history_steps' THEN
            SET v_sorting = ' ORDER BY `INSERTED TIME` DESC';
        ELSEIF p_table_unique_identifier = 'table_bot_history_steps_archive' THEN
            SET v_sorting = ' ORDER BY `ARCHIVED TIME` DESC';
        END IF;
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    IF p_table_unique_identifier = 'table_bot_history_order_bin_mapping' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                ORDER_BIN_ID AS 'ORDER BIN ID',
                BIN_ID AS 'BIN ID',
                STATION_ID AS 'STATION ID',
                TYPE AS 'TYPE',
                STATUS AS 'STATUS',
                BOT_ID AS 'BOT ID',
                IS_SYNCED AS 'IS SYNCED',
                DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
                DATE_FORMAT(UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME'
             FROM order_bin_mapping
             WHERE BOT_ID = '", p_bot_id, "'", p_filter_condition);
    ELSEIF p_table_unique_identifier = 'table_bot_history_order_bin_mapping_log' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                LOG_ID AS 'LOG ID',
                ORDER_BIN_ID AS 'ORDER BIN ID',
                BIN_ID AS 'BIN ID',
                STATION_ID AS 'STATION ID',
                TYPE AS 'TYPE',
                STATUS AS 'STATUS',
                BOT_ID AS 'BOT ID',
                DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
                DATE_FORMAT(UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME',
                DATE_FORMAT(LOGGED_TIMESTAMP, '", v_datetime_format, "') AS 'LOGGED TIME'
             FROM order_bin_mapping_log
             WHERE BOT_ID = '", p_bot_id, "'", p_filter_condition);
    ELSEIF p_table_unique_identifier = 'table_bot_history_task_master' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                TASK_ID AS 'TASK ID',
                BOT_ID AS 'BOT ID',
                FROM_LOCATION_ID AS 'FROM LOCATION ID',
                DESTINATION_LOCATION_ID AS 'DESTINATION LOCATION_ID',
                STATUS AS 'STATUS',
                DATE_FORMAT(START_TIME, '", v_datetime_format, "') AS 'START TIME',
                DATE_FORMAT(END_TIME, '", v_datetime_format, "') AS 'END TIME',
                TASK_TYPE AS 'TASK TYPE',
                DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
                DATE_FORMAT(UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME'
             FROM task_master
             WHERE BOT_ID = '", p_bot_id, "'", p_filter_condition);
    ELSEIF p_table_unique_identifier = 'table_bot_history_task_master_log' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                LOG_ID AS 'LOG ID',
                TASK_ID AS 'TASK ID',
                BOT_ID AS 'BOT ID',
                FROM_LOCATION_ID AS 'FROM LOCATION ID',
                DESTINATION_LOCATION_ID AS 'DESTINATION LOCATION ID',
                STATUS AS 'STATUS',
                START_TIME AS 'START TIME',
                END_TIME AS 'END TIME',
                TASK_TYPE AS 'TASK TYPE',
                DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
                DATE_FORMAT(UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME',
                DATE_FORMAT(LOGGED_TIMESTAMP, '", v_datetime_format, "') AS 'LOGGED TIME'
             FROM task_master_log
             WHERE BOT_ID = '", p_bot_id, "'", p_filter_condition);
    ELSEIF p_table_unique_identifier = 'table_bot_history_task_detail' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                TASK_DETAIL_ID AS 'TASK DETAIL ID',
                TASK_MASTER_ID AS 'TASK MASTER ID',
                BOT_ID AS 'BOT ID',
                START_LOCATION_ID AS 'START LOCATION ID',
                END_LOCATION_ID AS 'END LOCATION ID',
                STATUS AS 'STATUS',
                START_PICK_PUT_SIDE AS 'START PICK PUT SIDE',
                START_Z AS 'START Z',
                END_PICK_PUT_SIDE AS 'END PICK PUT SIDE',
                END_Z AS 'END Z',
                DATE_FORMAT(START_TIME, '", v_datetime_format, "') AS 'START TIME',
                DATE_FORMAT(END_TIME, '", v_datetime_format, "') AS 'END TIME',
                DATE_FORMAT(UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME',
                TASK_DETAIL_TYPE AS 'TASK DETAIL TYPE',
                IS_TOWER_BUFFER AS 'IS TOWER BUFFER',
                IS_STEPS_INSERTED AS 'IS STEPS INSERTED',
                COUNT_OF_STEPS AS 'COUNT OF STEPS',
                DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME'
             FROM task_detail
             WHERE BOT_ID = '", p_bot_id, "'", p_filter_condition);
    ELSEIF p_table_unique_identifier = 'table_bot_history_task_detail_log' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                LOG_ID AS 'LOG ID',
                TASK_DETAIL_ID AS 'TASK DETAIL ID',
                TASK_MASTER_ID AS 'TASK MASTER ID',
                BOT_ID AS 'BOT ID',
                START_LOCATION_ID AS 'START LOCATION ID',
                END_LOCATION_ID AS 'END LOCATION ID',
                STATUS AS 'STATUS',
                START_PICK_PUT_SIDE AS 'START PICK PUT SIDE',
                START_Z AS 'START Z',
                END_PICK_PUT_SIDE AS 'END PICK PUT SIDE',
                END_Z AS 'END Z',
                DATE_FORMAT(START_TIME, '", v_datetime_format, "') AS 'START TIME',
                DATE_FORMAT(END_TIME, '", v_datetime_format, "') AS 'END TIME',
                DATE_FORMAT(UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME',
                TASK_DETAIL_TYPE AS 'TASK DETAIL TYPE',
                IS_TOWER_BUFFER AS 'IS TOWER BUFFER',
                IS_STEPS_INSERTED AS 'IS STEPS INSERTED',
                COUNT_OF_STEPS AS 'COUNT OF STEPS',
                DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
                DATE_FORMAT(LOGGED_TIMESTAMP, '", v_datetime_format, "') AS 'LOGGED TIME'
             FROM task_detail_log
             WHERE BOT_ID = '", p_bot_id, "'", p_filter_condition);
    ELSEIF p_table_unique_identifier = 'table_bot_history_steps' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                ID AS 'ID',
                TASK_DETAIL_ID AS 'TASK DETAIL ID',
                BOT_ID AS 'BOT ID',
                X AS 'X',
                Y AS 'Y',
                Z AS 'Z',
                PROPERTY AS 'PROPERTY',
                COUNTER AS 'COUNTER',
                DATE_FORMAT(LAST_SENT_TIMESTAMP, '", v_datetime_format, "') AS 'LAST SENT TIME',
                IS_COMPLETED AS 'IS COMPLETED',
                PICK_PUT AS 'PICK PUT',
                DATE_FORMAT(IS_COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'IS COMPLETED TIME',
                DATE_FORMAT(INSERT_TIME, '", v_datetime_format, "') AS 'INSERTED TIME',
                DISTANCE_FROM_LAST_STEP AS 'DISTANCE FROM LAST STEP'
             FROM steps
             WHERE BOT_ID = '", p_bot_id, "'", p_filter_condition);
    ELSEIF p_table_unique_identifier = 'table_bot_history_steps_archive' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                ID AS 'ID',
                TASK_DETAIL_ID AS 'TASK DETAIL ID',
                BOT_ID AS 'BOT ID',
                X AS 'X',
                Y AS 'Y',
                Z AS 'Z',
                PROPERTY AS 'PROPERTY',
                COUNTER AS 'COUNTER',
                DATE_FORMAT(LAST_SENT_TIMESTAMP, '", v_datetime_format, "') AS 'LAST SENT TIME',
                IS_COMPLETED AS 'IS COMPLETED',
                PICK_PUT AS 'PICK PUT',
                DATE_FORMAT(IS_COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'IS COMPLETED TIME',
                DATE_FORMAT(INSERT_TIME, '", v_datetime_format, "') AS 'INSERTED TIME',
                DISTANCE_FROM_LAST_STEP AS 'DISTANCE FROM LAST STEP',
                DATE_FORMAT(ARCHIVE_TIMESTAMP, '", v_datetime_format, "') AS 'ARCHIVED TIME'
             FROM steps_archive
             WHERE BOT_ID = '", p_bot_id, "'", p_filter_condition);
    END IF;
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery",
        v_sorting,
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page);
    
    SET @countQuery = CONCAT("SELECT COUNT(*) INTO @rowCount FROM (", v_base_query, ") AS t");
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_DAILY_OPERATIONS_SUMMARY_PICK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_DAILY_OPERATIONS_SUMMARY_PICK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_DAILY_OPERATIONS_SUMMARY_PICK`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT DEFAULT 0;
    DECLARE p_rows_per_page INT DEFAULT 50;
    DECLARE p_download_flag BOOL DEFAULT FALSE;
    DECLARE p_page_zero_metadata_flag BOOL DEFAULT FALSE;
    DECLARE p_count_flag INT DEFAULT 0;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT DEFAULT '*';
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_user_id VARCHAR(50) DEFAULT 'system';
    DECLARE p_user_name VARCHAR(50) DEFAULT 'System User';
    DECLARE p_table_unique_identifier VARCHAR(50) DEFAULT 'daily_operations_summary';
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_start_date VARCHAR(20) DEFAULT '';
    DECLARE p_end_date VARCHAR(20) DEFAULT '';
    
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50) DEFAULT '%d-%m-%Y %H:%i';
    DECLARE v_date_format VARCHAR(50) DEFAULT '%d-%m-%Y';
    DECLARE v_base_query TEXT DEFAULT '';
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT DEFAULT '';
    DECLARE v_start_timestamp TIMESTAMP;
    DECLARE v_end_timestamp TIMESTAMP;
    
    
    IF Parameters IS NOT NULL AND JSON_VALID(Parameters) THEN
        
        SET p_page_number = COALESCE(CAST(NULLIF(Parameters ->> '$.page_number', '') AS UNSIGNED), 0);
        SET p_rows_per_page = COALESCE(CAST(NULLIF(Parameters ->> '$.rows_per_page', '') AS UNSIGNED), 50);
        SET p_count_flag = COALESCE(CAST(NULLIF(Parameters ->> '$.count', '') AS UNSIGNED), 0);
        
        
        SET p_user_id = COALESCE(NULLIF(TRIM(Parameters ->> '$.user_id'), ''), 'system');
        SET p_user_name = COALESCE(NULLIF(TRIM(Parameters ->> '$.user_name'), ''), 'System User');
        SET p_filter_condition = COALESCE(NULLIF(TRIM(Parameters ->> '$.filter_data'), ''), '');
        SET p_select_clause = COALESCE(NULLIF(TRIM(Parameters ->> '$.select_clause'), ''), '*');
        SET p_sorting_column_name = COALESCE(NULLIF(TRIM(Parameters ->> '$.sorting_column_name'), ''), '');
        SET p_sorting_column_orderby = COALESCE(NULLIF(TRIM(Parameters ->> '$.sorting_column_orderby'), ''), '');
        SET p_table_unique_identifier = COALESCE(NULLIF(TRIM(Parameters ->> '$.table_unique_identifier'), ''), 'daily_operations_summary');
        
        
        SET p_page_zero_metadata_flag = CASE 
            WHEN LOWER(COALESCE(NULLIF(Parameters ->> '$.page_zero_metadata_flag', ''), 'false')) IN ('true', '1') THEN TRUE
            ELSE FALSE
        END;
        
        SET p_download_flag = CASE 
            WHEN LOWER(COALESCE(NULLIF(Parameters ->> '$.download', ''), 'false')) IN ('true', '1') THEN TRUE
            ELSE FALSE
        END;
        
        
        SET p_report_extra_parameters = JSON_EXTRACT(Parameters, '$.report_extra_parameters');
        IF p_report_extra_parameters IS NOT NULL AND JSON_VALID(p_report_extra_parameters) THEN
            SET p_start_date = COALESCE(NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date'))), ''), '');
            SET p_end_date = COALESCE(NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date'))), ''), '');
        END IF;
    END IF;
    
    
    IF p_start_date = '' THEN
        SET p_start_date = DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 7 DAY), '%Y-%m-%d');
    END IF;
    IF p_end_date = '' THEN
        SET p_end_date = DATE_FORMAT(CURDATE(), '%Y-%m-%d');
    END IF;
    
    
    SET v_start_timestamp = TIMESTAMP(CONCAT(p_start_date, ' 00:00:00'));
    SET v_end_timestamp = TIMESTAMP(CONCAT(p_end_date, ' 23:59:59'));
    
    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
        BEGIN
            SET v_datetime_format = '%d-%m-%Y %H:%i';
            SET v_date_format = '%d-%m-%Y';
        END;
        
        SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
        SET v_date_format = DSB_GET_DATE_FORMAT('date');
    END;
    
    
    IF p_sorting_column_name != '' AND p_sorting_column_orderby != '' THEN
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    ELSE
        SET v_sorting = ' ORDER BY Date DESC';
    END IF;
    
    
    IF p_start_date = '' OR p_end_date = '' THEN
        IF p_count_flag = 1 THEN
            SELECT 0 AS 'TOTAL_ROWS';
        ELSE
            SELECT 'ERROR: Both start_date and end_date parameters are required in report_extra_parameters' AS 'Error Message';
        END IF;
    ELSE
        
        SET v_base_query = CONCAT(
            "SELECT 
                DATE_FORMAT(daily_ops.operation_date, '", v_date_format, "') AS 'Date',
                daily_ops.total_gtc_used AS 'Total GTC Used',
                daily_ops.total_bin_presentation AS 'Total Bin Presentation',
                daily_ops.total_time_hours AS 'Total Time (Hours)'
            FROM (
                SELECT 
                    operation_date,
                    COUNT(DISTINCT station_id) AS total_gtc_used,
                    COUNT(DISTINCT bin_id) AS total_bin_presentation,
                    ROUND(
                        GREATEST(
                            TIMESTAMPDIFF(MINUTE, MIN(operation_timestamp), MAX(operation_timestamp)), 
                            5
                        ) / 60.0, 
                        2
                    ) AS total_time_hours
                FROM (
                    -- OPTIMIZED: Pre-filtered PICK operations
                    SELECT STRAIGHT_JOIN
                        DATE(pwm.PICK_TIMESTAMP) AS operation_date,
                        pwm.STATION_ID AS station_id,
                        pwm.BIN_ID AS bin_id,
                        pwm.PICK_TIMESTAMP AS operation_timestamp,
                        pwm.WAVE_ID
                    FROM pick_wave_order_master_archive pwm USE INDEX (WAVE_ID)
                    WHERE pwm.PICK_TIMESTAMP >= '", p_start_date, " 00:00:00'
                        AND pwm.PICK_TIMESTAMP <= '", p_end_date, " 23:59:59'
                        AND pwm.PICKED_QUANTITY > 0
                        AND pwm.PICK_BY IS NOT NULL
                        AND pwm.PICK_BY != ''
                        AND pwm.WAVE_ID IS NOT NULL
                    
                    UNION ALL
                    
                    -- OPTIMIZED: Pre-filtered PUT operations  
                    SELECT STRAIGHT_JOIN
                        DATE(puwm.PUT_TIMESTAMP) AS operation_date,
                        puwm.STATION_ID AS station_id,
                        puwm.BIN_ID AS bin_id,
                        puwm.PUT_TIMESTAMP AS operation_timestamp,
                        puwm.WAVE_ID
                    FROM put_wave_order_master_archive puwm USE INDEX (WAVE_ID)
                    WHERE puwm.PUT_TIMESTAMP >= '", p_start_date, " 00:00:00'
                        AND puwm.PUT_TIMESTAMP <= '", p_end_date, " 23:59:59'
                        AND puwm.PUT_QUANTITY > 0
                        AND puwm.PUT_BY IS NOT NULL
                        AND puwm.PUT_BY != ''
                        AND puwm.WAVE_ID IS NOT NULL
                    
                    UNION ALL
                    
                    -- OPTIMIZED: Pre-filtered STOCK_AUDIT operations
                    SELECT STRAIGHT_JOIN
                        DATE(sawm.UPDATED_TIMESTAMP) AS operation_date,
                        sawm.STATION_ID AS station_id,
                        sawm.BIN_ID AS bin_id,
                        sawm.UPDATED_TIMESTAMP AS operation_timestamp,
                        sawm.WAVE_ID
                    FROM stock_audit_wave_order_master_archive sawm USE INDEX (WAVE_ID)
                    WHERE sawm.UPDATED_TIMESTAMP >= '", p_start_date, " 00:00:00'
                        AND sawm.UPDATED_TIMESTAMP <= '", p_end_date, " 23:59:59'
                        AND sawm.STATUS = 'AUDIT_COMPLETED'
                        AND sawm.AUDIT_BY IS NOT NULL
                        AND sawm.AUDIT_BY != ''
                        AND sawm.WAVE_ID IS NOT NULL
                        
                ) unified_ops
                -- OPTIMIZED: Simplified wave validation with EXISTS for better performance
                WHERE EXISTS (
                    SELECT 1 
                    FROM wave_master_archive wma
                    WHERE wma.WAVE_ID = unified_ops.WAVE_ID
                        AND wma.WAVE_TYPE IN ('PICK', 'PUT', 'STOCK_AUDIT')
                        AND wma.WAVE_STATUS = 'COMPLETED'
                        AND wma.IS_CANCELLED = 0
                        LIMIT 1
                )
                GROUP BY operation_date
                HAVING total_bin_presentation > 0
            ) daily_ops"
        );
        
        
        IF p_filter_condition != '' THEN
            SET v_base_query = CONCAT(v_base_query, " WHERE (", p_filter_condition, ")");
        END IF;
        
        
        SET v_paginated_query = CONCAT(
            "SELECT ", p_select_clause, 
            " FROM (", v_base_query, ") AS subquery", 
            v_sorting, 
            " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
        );
        
        
        SET @countQuery = CONCAT('SELECT COUNT(*) INTO @rowCount FROM (', v_base_query, ') AS count_table');
        PREPARE stmt FROM @countQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
        SET v_total_rows = @rowCount;
        
        
        IF p_count_flag = 1 THEN
            
            SELECT v_total_rows AS 'TOTAL_ROWS';
        ELSE
            
            IF p_page_zero_metadata_flag = TRUE THEN
                
                BEGIN
                    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION 
                    BEGIN
                        SET @finalQuery = v_paginated_query;
                    END;
                    
                    SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                        p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
                    );
                END;
            ELSE
                SET @finalQuery = v_paginated_query;
            END IF;
            
            
            PREPARE stmt FROM @finalQuery;
            EXECUTE stmt;
            DEALLOCATE PREPARE stmt;
        END IF;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_GLOBAL_PAUSE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_GLOBAL_PAUSE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_GLOBAL_PAUSE`(IN Parameters JSON)
BEGIN
  DECLARE p_page_number              INT;
  DECLARE p_rows_per_page            INT;
  DECLARE p_download_flag            BOOL;
  DECLARE p_page_zero_metadata_flag  BOOL;
  DECLARE p_count_flag               INT;
  DECLARE p_filter_condition         VARCHAR(2000) DEFAULT '';
  DECLARE p_select_clause            TEXT;
  DECLARE p_sorting_column_name      VARCHAR(50) DEFAULT '';
  DECLARE p_sorting_column_orderby   VARCHAR(50) DEFAULT '';
  DECLARE p_user_id                  VARCHAR(50);
  DECLARE p_user_name                VARCHAR(50);
  DECLARE p_table_unique_identifier  VARCHAR(50);
  DECLARE v_sorting          VARCHAR(200) DEFAULT '';
  DECLARE v_datetime_format  VARCHAR(50);
  DECLARE v_base_query       TEXT;
  DECLARE v_total_rows       INT DEFAULT 0;
  DECLARE v_paginated_query  TEXT;
  DECLARE v_offset           INT DEFAULT 0;
  SET p_page_number              = Parameters ->> '$.page_number';
  SET p_rows_per_page            = Parameters ->> '$.rows_per_page';
  SET p_user_id                  = Parameters ->> '$.user_id';
  SET p_user_name                = Parameters ->> '$.user_name';
  SET p_page_zero_metadata_flag  = Parameters ->> '$.page_zero_metadata_flag';
  SET p_count_flag               = Parameters ->> '$.count';
  SET p_filter_condition         = Parameters ->> '$.filter_data';
  SET p_select_clause            = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
  SET p_sorting_column_name      = Parameters ->> '$.sorting_column_name';
  SET p_sorting_column_orderby   = Parameters ->> '$.sorting_column_orderby';
  SET p_table_unique_identifier  = Parameters ->> '$.table_unique_identifier';
  
  SET p_download_flag = CASE
    WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
    ELSE FALSE
  END;
  IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
     OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
    SET v_sorting = ' ORDER BY `PRESSED TIME` DESC';
  ELSE
    SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
  END IF;
  IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
    SET p_filter_condition = '';
  ELSE
    SET p_filter_condition = CONCAT(' AND ', p_filter_condition);
  END IF;
  SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
  SET v_base_query = CONCAT(
    "SELECT
      SOURCE AS `SOURCE`,
      DATE_FORMAT(PRESSED_TIMESTAMP, '", v_datetime_format, "') AS `PRESSED TIME`,
      DATE_FORMAT(RELEASED_TIMESTAMP, '", v_datetime_format, "') AS `RELEASED TIME`
    FROM global_pause_log
    WHERE GLOBAL_PAUSE_BIT = 1",
    p_filter_condition
  );
  SET v_offset = p_page_number * p_rows_per_page;
  SET v_paginated_query = CONCAT(
    'SELECT ', p_select_clause, ' ',
    'FROM (', v_base_query, ') AS subquery',
    v_sorting,
    ' LIMIT ', v_offset, ', ', p_rows_per_page
  );
  SET @countQuery = CONCAT(
    'SELECT COUNT(*) INTO @rowCount FROM (', v_base_query, ') AS t'
  );
  PREPARE stmt FROM @countQuery;
  EXECUTE stmt;
  DEALLOCATE PREPARE stmt;
  SET v_total_rows = @rowCount;
  
  IF p_count_flag = 1 THEN
    SELECT v_total_rows AS 'TOTAL_ROWS';
  ELSE
    IF p_page_zero_metadata_flag THEN
      SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
        p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
      );
    ELSE
      SET @finalQuery = v_paginated_query;
    END IF;
    PREPARE stmt FROM @finalQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_GTC_CAMERA_NO_READ` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_GTC_CAMERA_NO_READ` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_GTC_CAMERA_NO_READ`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT DEFAULT (Parameters ->> '$.page_number');
    DECLARE p_rows_per_page INT DEFAULT (Parameters ->> '$.rows_per_page');
    DECLARE p_download_flag BOOLEAN DEFAULT (JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true');
    DECLARE p_page_zero_metadata_flag BOOLEAN DEFAULT (Parameters ->> '$.page_zero_metadata_flag');
    DECLARE p_count_flag BOOLEAN DEFAULT (Parameters ->> '$.count');
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT (COALESCE(Parameters ->> '$.filter_data', ''));
    DECLARE p_select_clause TEXT DEFAULT (COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*'));
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT (Parameters ->> '$.sorting_column_name');
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT (Parameters ->> '$.sorting_column_orderby');
    DECLARE p_user_id INT DEFAULT (Parameters ->> '$.user_id');
    DECLARE p_user_name VARCHAR(50) DEFAULT (Parameters ->> '$.user_name');
    DECLARE p_table_unique_identifier VARCHAR(50) DEFAULT (Parameters ->> '$.table_unique_identifier');
    DECLARE p_report_extra_parameters JSON DEFAULT (Parameters ->> '$.report_extra_parameters');
    DECLARE p_start_date_time DATETIME DEFAULT (JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time')));
    DECLARE p_end_date_time DATETIME DEFAULT (JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time')));
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
     OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
    SET v_sorting = ' ORDER BY `INSERTED TIME` DESC';
  ELSE
    SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
  END IF;
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(' AND ', p_filter_condition, '');
    END IF;
    
    SET v_base_query = CONCAT(
    "SELECT
      STATION_ID AS `STATION ID`,
      TYPE AS `TYPE`,
      PLACE AS `PLACE`,
      DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS `INSERTED TIME`
    FROM station_no_read_logs
    WHERE INSERTED_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'",
    p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery", 
        v_sorting, 
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    SET @countQuery = CONCAT("SELECT COUNT(*) INTO @rowCount FROM (", v_base_query, ") AS t");
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_INVENTORY_SYNC_HISTORY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_INVENTORY_SYNC_HISTORY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_INVENTORY_SYNC_HISTORY`(IN Parameters JSON)
BEGIN
  DECLARE p_page_number              INT;
  DECLARE p_rows_per_page            INT;
  DECLARE p_download_flag            BOOL;
  DECLARE p_page_zero_metadata_flag  BOOL;
  DECLARE p_count_flag               INT;
  DECLARE p_filter_condition         VARCHAR(2000) DEFAULT '';
  DECLARE p_select_clause            TEXT;
  DECLARE p_sorting_column_name      VARCHAR(50) DEFAULT '';
  DECLARE p_sorting_column_orderby   VARCHAR(50) DEFAULT '';
  DECLARE p_user_id                  VARCHAR(50);
  DECLARE p_user_name                VARCHAR(50);
  DECLARE p_table_unique_identifier  VARCHAR(50);
  DECLARE v_sorting          VARCHAR(200) DEFAULT '';
  DECLARE v_datetime_format  VARCHAR(50);
  DECLARE v_base_query       TEXT;
  DECLARE v_total_rows       INT DEFAULT 0;
  DECLARE v_paginated_query  TEXT;
  DECLARE v_offset           INT DEFAULT 0;
  SET p_page_number              = Parameters ->> '$.page_number';
  SET p_rows_per_page            = Parameters ->> '$.rows_per_page';
  SET p_user_id                  = Parameters ->> '$.user_id';
  SET p_user_name                = Parameters ->> '$.user_name';
  SET p_page_zero_metadata_flag  = Parameters ->> '$.page_zero_metadata_flag';
  SET p_count_flag               = Parameters ->> '$.count';
  SET p_filter_condition         = Parameters ->> '$.filter_data';
  SET p_select_clause            = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
  SET p_sorting_column_name      = Parameters ->> '$.sorting_column_name';
  SET p_sorting_column_orderby   = Parameters ->> '$.sorting_column_orderby';
  SET p_table_unique_identifier  = Parameters ->> '$.table_unique_identifier';
  
  SET p_download_flag = CASE
    WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
    ELSE FALSE
  END;
  IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
     OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
    SET v_sorting = ' ORDER BY `INSERTED TIME` DESC';
  ELSE
    SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
  END IF;
  IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
    SET p_filter_condition = '';
  ELSE
    SET p_filter_condition = CONCAT(' AND ', p_filter_condition);
  END IF;
  SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
  SET v_base_query = CONCAT(
    "SELECT 
            STATUS AS `STATUS`,
            REASON AS `REASON`,
            DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS `INSERTED TIME`,
            DATE_FORMAT(UPDATED_TIMESTAMP, '", v_datetime_format, "') AS `UPDATED TIME`
        FROM inventory_sync_master",
    p_filter_condition
  );
  SET v_offset = p_page_number * p_rows_per_page;
  SET v_paginated_query = CONCAT(
    'SELECT ', p_select_clause, ' ',
    'FROM (', v_base_query, ') AS subquery',
    v_sorting,
    ' LIMIT ', v_offset, ', ', p_rows_per_page
  );
  SET @countQuery = CONCAT(
    'SELECT COUNT(*) INTO @rowCount FROM (', v_base_query, ') AS t'
  );
  PREPARE stmt FROM @countQuery;
  EXECUTE stmt;
  DEALLOCATE PREPARE stmt;
  SET v_total_rows = @rowCount;
  
  IF p_count_flag = 1 THEN
    SELECT v_total_rows AS 'TOTAL_ROWS';
  ELSE
    IF p_page_zero_metadata_flag THEN
      SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
        p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
      );
    ELSE
      SET @finalQuery = v_paginated_query;
    END IF;
    PREPARE stmt FROM @finalQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_LIVE_INVENTORY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_LIVE_INVENTORY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_LIVE_INVENTORY`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_table_unique_identifier VARCHAR(50);
    DECLARE p_report_extra_parameters JSON;
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number                    = Parameters ->> '$.page_number';
    SET p_rows_per_page                 = Parameters ->> '$.rows_per_page';
    SET p_user_id                       = Parameters ->> '$.user_id';
    SET p_user_name                     = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag       = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag                    = Parameters ->> '$.count';
    SET p_filter_condition              = Parameters ->> '$.filter_data';
    SET p_select_clause                 = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name           = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby        = Parameters ->> '$.sorting_column_orderby';
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = '';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY ', '`', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    
    SET p_table_unique_identifier             = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.report_extra_parameters'));
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    SET v_base_query = CONCAT(
        "SELECT 
            lim.BIN_ID AS 'BIN ID',
            lim.SEGMENT_NO AS 'SEGMENT NO',
            lim.ARTICLE_ID AS 'SKU ID',
            sbm.GLN AS 'GLN',
            sbm.CLIENT_BATCH_ID AS 'CLIENT BATCH ID',
            sbm.MRP AS 'MRP',
            DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
            lim.QUANTITY AS 'QUANTITY',
            lim.REMARK AS 'REMARK'
         FROM 
            live_inventory_master lim
         INNER JOIN 
            sku_batch_master sbm ON sbm.BATCH_ID = lim.BATCH_ID",
         p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery",
        v_sorting,
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    SET @countQuery = CONCAT('SELECT COUNT(*) INTO @rowCount FROM (', v_base_query, ') AS t');
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_LOCATION_BLOCK_MASTER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_LOCATION_BLOCK_MASTER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_LOCATION_BLOCK_MASTER`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_table_unique_identifier VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number                = Parameters ->> '$.page_number';
    SET p_rows_per_page               = Parameters ->> '$.rows_per_page';
    SET p_user_id                     = Parameters ->> '$.user_id';
    SET p_user_name                   = Parameters ->> '$.user_name';
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    SET p_page_zero_metadata_flag     = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag                  = Parameters ->> '$.count';
    SET p_filter_condition            = Parameters ->> '$.filter_data';
    SET p_select_clause               = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name         = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby      = Parameters ->> '$.sorting_column_orderby';
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = '';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY ', '`', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition = '' OR p_filter_condition IS NULL THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    SET p_table_unique_identifier           = Parameters ->> '$.table_unique_identifier';
    
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    SET v_base_query = CONCAT(
        "SELECT 
            lbm.LOCATION_ID AS 'LOCATION ID', 
            lm.X AS 'X', 
            lm.Y AS 'Y', 
            lm.Z AS 'Z', 
            lm.AISLE_NUMBER AS 'AISLE NUMBER', 
            lm.TOWER_NUMBER AS 'TOWER NUMBER', 
            CASE
		WHEN lm.Y IN (
		    SELECT DISTINCT (Y - 1) FROM location_master WHERE TYPE LIKE 'TOWER%'
		) THEN 'LEFT'
		WHEN lm.Y IN (
		    SELECT DISTINCT (Y + 1) FROM location_master WHERE TYPE LIKE 'TOWER%'
		) THEN 'RIGHT'
		ELSE NULL
	    END AS 'TOWER SIDE',
            DATE_FORMAT(lbm.BLOCK_TIMESTAMP, '", v_datetime_format, "') AS 'BLOCK TIME',
            lbm.BLOCK_BY AS 'BLOCK BY'
         FROM location_block_master lbm
         INNER JOIN location_master lm ON lm.LOCATION_ID = lbm.LOCATION_ID", p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, " FROM (", v_base_query, 
        ") AS subquery", v_sorting,
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    
    SET @countQuery = CONCAT('SELECT COUNT(*) INTO @rowCount FROM (', v_base_query, ') AS t');
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag IS TRUE THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_ORDER_SPLIT_ANALYSIS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_ORDER_SPLIT_ANALYSIS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_ORDER_SPLIT_ANALYSIS`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT DEFAULT (Parameters ->> '$.page_number');
    DECLARE p_rows_per_page INT DEFAULT (Parameters ->> '$.rows_per_page');
    DECLARE p_download_flag BOOLEAN DEFAULT (JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true');
    DECLARE p_page_zero_metadata_flag BOOLEAN DEFAULT (Parameters ->> '$.page_zero_metadata_flag');
    DECLARE p_count_flag BOOLEAN DEFAULT (Parameters ->> '$.count');
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT (COALESCE(Parameters ->> '$.filter_data', ''));
    DECLARE p_select_clause TEXT DEFAULT (COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*'));
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT (Parameters ->> '$.sorting_column_name');
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT (Parameters ->> '$.sorting_column_orderby');
    DECLARE p_user_id INT DEFAULT (Parameters ->> '$.user_id');
    DECLARE p_user_name VARCHAR(50) DEFAULT (Parameters ->> '$.user_name');
    DECLARE p_table_unique_identifier VARCHAR(50) DEFAULT (Parameters ->> '$.table_unique_identifier');
    
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    
    IF p_sorting_column_name IS NULL OR p_sorting_column_name = '' THEN
        SET v_sorting = ' ORDER BY `INSERTED DATE` DESC, `PARENT ORDER ID`, `ORDER TYPE`';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    
    
    SET v_base_query = CONCAT("
        WITH order_ids AS (
            SELECT 
                MIN(CAST(INSERTED_TIMESTAMP AS DATE)) AS insert_date,
                parent_order_id, 
                order_id, 
                order_type,
                MIN(WMS_ORDER_REQUEST_DATA_ID) AS id
            FROM wms_to_wcs_order_request_data
            GROUP BY parent_order_id, order_id, order_type
         
            UNION ALL
         
            SELECT 
                MIN(CAST(INSERTED_TIMESTAMP AS DATE)) AS insert_date,
                parent_order_id, 
                order_id, 
                order_type,
                MIN(WMS_ORDER_REQUEST_DATA_ID) AS id
            FROM wms_to_wcs_order_request_data_archive
            GROUP BY parent_order_id, order_id, order_type
        )
        SELECT * FROM (
            SELECT 
                
                parent_order_id AS `PARENT ORDER ID`, 
                order_type AS `ORDER TYPE`,
                COUNT(order_line_id) AS `COUNT OF ORDERLINES`, 
                SUM(quantity) AS `QUANTITY`,
                COUNT(DISTINCT wtw.order_id) AS `COUNT OF ORDER ID`,
                CASE 
                    WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                    ELSE CEILING(COUNT(order_line_id) / 100)
                END AS `SPLIT OL`,
                CASE 
                    WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                    ELSE CEILING(SUM(quantity) / 800)
                END AS `SPLIT QTY`,
                GREATEST(
                    CASE 
                        WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                        ELSE CEILING(COUNT(order_line_id) / 100)
                    END,
                    CASE 
                        WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                        ELSE CEILING(SUM(quantity) / 800)
                    END
                ) AS `IDEAL SPLIT`,
                CONCAT(
                    ROUND(
                        (
                            COUNT(DISTINCT wtw.order_id) /
                            GREATEST(
                                CASE WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                                     ELSE CEILING(COUNT(order_line_id) / 100)
                                END,
                                CASE WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                                     ELSE CEILING(SUM(quantity) / 800)
                                END
                            )
                        ) * 100, 
                        0
                    ),
                    '%'
                ) AS `SPLIT EFFICIENCY`,
                CASE
                    WHEN (
                        COUNT(DISTINCT wtw.order_id) /
                        GREATEST(
                            CASE WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                                 ELSE CEILING(COUNT(order_line_id) / 100)
                            END,
                            CASE WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                                 ELSE CEILING(SUM(quantity) / 800)
                            END
                        )
                    ) > 1 THEN 'Over Split'
                    WHEN (
                        COUNT(DISTINCT wtw.order_id) /
                        GREATEST(
                            CASE WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                                 ELSE CEILING(COUNT(order_line_id) / 100)
                            END,
                            CASE WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                                 ELSE CEILING(SUM(quantity) / 800)
                            END
                        )
                    ) < 1 THEN 'Under Split'
                    ELSE 'Perfect Split'
                END AS `SPLIT TYPE`,
                CAST(wtw.INSERTED_TIMESTAMP AS DATE) AS `INSERTED DATE`
            FROM wms_to_wcs_order_line_request_data wtw
            JOIN order_ids od ON od.id = wtw.WMS_ORDER_REQUEST_DATA_ID
            GROUP BY 
                CAST(INSERTED_TIMESTAMP AS DATE),
                parent_order_id,
                order_type
         
            UNION ALL
         
            SELECT 
                CAST(wtw.INSERTED_TIMESTAMP AS DATE) AS `INSERTED DATE`,
                parent_order_id AS `PARENT ORDER ID`, 
                order_type AS `ORDER TYPE`,
                COUNT(order_line_id) AS `COUNT OF ORDERLINES`, 
                SUM(quantity) AS `QUANTITY`,
                COUNT(DISTINCT wtw.order_id) AS `COUNT OF ORDER ID`,
                CASE 
                    WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                    ELSE CEILING(COUNT(order_line_id) / 100)
                END AS `SPLIT OL`,
                CASE 
                    WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                    ELSE CEILING(SUM(quantity) / 800)
                END AS `SPLIT QTY`,
                GREATEST(
                    CASE 
                        WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                        ELSE CEILING(COUNT(order_line_id) / 100)
                    END,
                    CASE 
                        WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                        ELSE CEILING(SUM(quantity) / 800)
                    END
                ) AS `IDEAL SPLIT`,
                CONCAT(
                    ROUND(
                        (
                            COUNT(DISTINCT wtw.order_id) /
                            GREATEST(
                                CASE WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                                     ELSE CEILING(COUNT(order_line_id) / 100)
                                END,
                                CASE WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                                     ELSE CEILING(SUM(quantity) / 800)
                                END
                            )
                        ) * 100, 
                        0
                    ),
                    '%'
                ) AS `SPLIT EFFICIENCY`,
                CASE
                    WHEN (
                        COUNT(DISTINCT wtw.order_id) /
                        GREATEST(
                            CASE WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                                 ELSE CEILING(COUNT(order_line_id) / 100)
                            END,
                            CASE WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                                 ELSE CEILING(SUM(quantity) / 800)
                            END
                        )
                    ) > 1 THEN 'Over Split'
                    WHEN (
                        COUNT(DISTINCT wtw.order_id) /
                        GREATEST(
                            CASE WHEN COUNT(order_line_id) <= 110 THEN CEILING(COUNT(order_line_id) / 110)
                                 ELSE CEILING(COUNT(order_line_id) / 100)
                            END,
                            CASE WHEN SUM(quantity) <= 900 THEN CEILING(SUM(quantity) / 900)
                                 ELSE CEILING(SUM(quantity) / 800)
                            END
                        )
                    ) < 1 THEN 'Under Split'
                    ELSE 'Perfect Split'
                END AS `SPLIT TYPE`,
                CAST(wtw.INSERTED_TIMESTAMP AS DATE) AS `INSERTED DATE`
            FROM wms_to_wcs_order_line_request_data_archive wtw
            JOIN order_ids od ON od.id = wtw.WMS_ORDER_REQUEST_DATA_ID
            GROUP BY 
                CAST(INSERTED_TIMESTAMP AS DATE),
                parent_order_id,
                order_type
        ) combined_results
    ", p_filter_condition);
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery", 
        v_sorting, 
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    
    SET @countQuery = CONCAT("SELECT COUNT(*) INTO @rowCount FROM (", v_base_query, ") AS t");
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_ORDER_SPLIT_ANALYSIS_BY_DATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_ORDER_SPLIT_ANALYSIS_BY_DATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_ORDER_SPLIT_ANALYSIS_BY_DATE`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT DEFAULT (Parameters ->> '$.page_number');
    DECLARE p_rows_per_page INT DEFAULT (Parameters ->> '$.rows_per_page');
    DECLARE p_download_flag BOOLEAN DEFAULT (JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true');
    DECLARE p_page_zero_metadata_flag BOOLEAN DEFAULT (Parameters ->> '$.page_zero_metadata_flag');
    DECLARE p_count_flag BOOLEAN DEFAULT (Parameters ->> '$.count');
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT (COALESCE(Parameters ->> '$.filter_data', ''));
    DECLARE p_select_clause TEXT DEFAULT (COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*'));
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT (Parameters ->> '$.sorting_column_name');
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT (Parameters ->> '$.sorting_column_orderby');
    DECLARE p_user_id INT DEFAULT (Parameters ->> '$.user_id');
    DECLARE p_user_name VARCHAR(50) DEFAULT (Parameters ->> '$.user_name');
    DECLARE p_table_unique_identifier VARCHAR(50) DEFAULT (Parameters ->> '$.table_unique_identifier');
    DECLARE p_report_extra_parameters JSON DEFAULT (Parameters ->> '$.report_extra_parameters');
    DECLARE p_start_date_time DATETIME DEFAULT (JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time')));
    DECLARE p_end_date_time DATETIME DEFAULT (JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time')));
    
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    
    IF p_sorting_column_name IS NULL OR p_sorting_column_name = '' THEN
        SET v_sorting = ' ORDER BY `INSERTED DATE` DESC, `PARENT ORDER ID`, `ORDER TYPE`';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    
    
    SET v_base_query = CONCAT("
        WITH order_ids AS (
            SELECT 
                MIN(CAST(INSERTED_TIMESTAMP AS DATE)) AS insert_date,
                parent_order_id, 
                order_id, 
                order_type,
                MIN(WMS_ORDER_REQUEST_DATA_ID) AS id
            FROM wms_to_wcs_order_request_data
            WHERE INSERTED_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
            GROUP BY parent_order_id, order_id, order_type
         
            UNION ALL
         
            SELECT 
                MIN(CAST(INSERTED_TIMESTAMP AS DATE)) AS insert_date,
                parent_order_id, 
                order_id, 
                order_type,
                MIN(WMS_ORDER_REQUEST_DATA_ID) AS id
            FROM wms_to_wcs_order_request_data_archive
            WHERE INSERTED_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
            GROUP BY parent_order_id, order_id, order_type
        )
        SELECT * FROM (
            SELECT 
                
                od.parent_order_id AS `PARENT ORDER ID`, 
                od.order_type AS `ORDER TYPE`,
                COUNT(wtw.order_line_id) AS `COUNT OF ORDERLINES`, 
                SUM(wtw.quantity) AS `QUANTITY`,
                COUNT(DISTINCT wtw.order_id) AS `COUNT OF ORDER ID`,
                CASE 
                    WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                    ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                END AS `SPLIT OL`,
                CASE 
                    WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                    ELSE CEILING(SUM(wtw.quantity) / 800)
                END AS `SPLIT QTY`,
                GREATEST(
                    CASE 
                        WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                        ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                    END,
                    CASE 
                        WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                        ELSE CEILING(SUM(wtw.quantity) / 800)
                    END
                ) AS `IDEAL SPLIT`,
                CONCAT(
                    ROUND(
                        (
                            COUNT(DISTINCT wtw.order_id) /
                            GREATEST(
                                CASE WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                                     ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                                END,
                                CASE WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                                     ELSE CEILING(SUM(wtw.quantity) / 800)
                                END
                            )
                        ) * 100, 
                        0
                    ),
                    '%'
                ) AS `SPLIT EFFICIENCY`,
                CASE
                    WHEN (
                        COUNT(DISTINCT wtw.order_id) /
                        GREATEST(
                            CASE WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                                 ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                            END,
                            CASE WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                                 ELSE CEILING(SUM(wtw.quantity) / 800)
                            END
                        )
                    ) > 1 THEN 'Over Split'
                    WHEN (
                        COUNT(DISTINCT wtw.order_id) /
                        GREATEST(
                            CASE WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                                 ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                            END,
                            CASE WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                                 ELSE CEILING(SUM(wtw.quantity) / 800)
                            END
                        )
                    ) < 1 THEN 'Under Split'
                    ELSE 'Perfect Split'
                END AS `SPLIT TYPE`,
				CAST(wtw.INSERTED_TIMESTAMP AS DATE) AS `INSERTED DATE`
            FROM wms_to_wcs_order_line_request_data wtw
            JOIN order_ids od ON od.id = wtw.WMS_ORDER_REQUEST_DATA_ID
            GROUP BY 
                CAST(wtw.INSERTED_TIMESTAMP AS DATE),
                od.parent_order_id,
                od.order_type
         
            UNION ALL
         
            SELECT 
                
                od.parent_order_id AS `PARENT ORDER ID`, 
                od.order_type AS `ORDER TYPE`,
                COUNT(wtw.order_line_id) AS `COUNT OF ORDERLINES`, 
                SUM(wtw.quantity) AS `QUANTITY`,
                COUNT(DISTINCT wtw.order_id) AS `COUNT OF ORDER ID`,
                CASE 
                    WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                    ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                END AS `SPLIT OL`,
                CASE 
                    WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                    ELSE CEILING(SUM(wtw.quantity) / 800)
                END AS `SPLIT QTY`,
                GREATEST(
                    CASE 
                        WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                        ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                    END,
                    CASE 
                        WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                        ELSE CEILING(SUM(wtw.quantity) / 800)
                    END
                ) AS `IDEAL SPLIT`,
                CONCAT(
                    ROUND(
                        (
                            COUNT(DISTINCT wtw.order_id) /
                            GREATEST(
                                CASE WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                                     ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                                END,
                                CASE WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                                     ELSE CEILING(SUM(wtw.quantity) / 800)
                                END
                            )
                        ) * 100, 
                        0
                    ),
                    '%'
                )  AS `SPLIT EFFICIENCY`,
                CASE
                    WHEN (
                        COUNT(DISTINCT wtw.order_id) /
                        GREATEST(
                            CASE WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                                 ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                            END,
                            CASE WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                                 ELSE CEILING(SUM(wtw.quantity) / 800)
                            END
                        )
                    ) > 1 THEN 'Over Split'
                    WHEN (
                        COUNT(DISTINCT wtw.order_id) /
                        GREATEST(
                            CASE WHEN COUNT(wtw.order_line_id) <= 110 THEN CEILING(COUNT(wtw.order_line_id) / 110)
                                 ELSE CEILING(COUNT(wtw.order_line_id) / 100)
                            END,
                            CASE WHEN SUM(wtw.quantity) <= 900 THEN CEILING(SUM(wtw.quantity) / 900)
                                 ELSE CEILING(SUM(wtw.quantity) / 800)
                            END
                        )
                    ) < 1 THEN 'Under Split'
                    ELSE 'Perfect Split'
                END AS `SPLIT TYPE`,
				CAST(wtw.INSERTED_TIMESTAMP AS DATE) AS `INSERTED DATE`
            FROM wms_to_wcs_order_line_request_data_archive wtw
            JOIN order_ids od ON od.id = wtw.WMS_ORDER_REQUEST_DATA_ID
            GROUP BY 
                CAST(wtw.INSERTED_TIMESTAMP AS DATE),
                od.parent_order_id,
                od.order_type
        ) combined_results
    ", p_filter_condition);
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery", 
        v_sorting, 
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    
    SET @countQuery = CONCAT("SELECT COUNT(*) INTO @rowCount FROM (", v_base_query, ") AS t");
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    
    
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS 'TOTAL_ROWS';
    ELSE
        IF p_page_zero_metadata_flag THEN
            SET @finalQuery = DSB_PAGINATED_PAGE_0_META_DATA_GENERATION(
                p_table_unique_identifier, p_user_id, p_page_number, p_rows_per_page, v_total_rows
            );
        ELSE
            SET @finalQuery = v_paginated_query;
        END IF;
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
    
END */$$
DELIMITER ;

