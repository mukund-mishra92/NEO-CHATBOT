
------------------------------------------------------------------------------------------------------------------------
/* Procedure structure for procedure `tm_SelectStationHomeWithYnX` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectStationHomeWithYnX` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectStationHomeWithYnX`(
	IN stationId INT
    )
BEGIN
		SELECT lm.*, hsm.STATION_ID 
		FROM `location_master` lm
		JOIN `hw_station_master` hsm ON lm.LOCATION_ID = hsm.`ASSOCIATED_HOME_1`
		WHERE hsm.`PICK_LOCATION_ID` = stationId 
		UNION ALL 
		SELECT lm.*, hsm.STATION_ID 
		FROM `location_master` lm
		JOIN `hw_station_master` hsm ON lm.LOCATION_ID = hsm.`ASSOCIATED_HOME_2`
		WHERE hsm.`PICK_LOCATION_ID` = stationId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectSubConWithParentID` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectSubConWithParentID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectSubConWithParentID`(
	in parentLocationID int
    )
BEGIN
		Select `LOCATION_ID` from `subcontroller_reservations_master` where `PARENT_LOCATION_ID` = parentLocationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectTypeFromLocationID` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectTypeFromLocationID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectTypeFromLocationID`(
	in locationID int
    )
BEGIN
		select `TYPE` from `location_master` where `LOCATION_ID` = locationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_StationPickPoint` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_StationPickPoint` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_StationPickPoint`(in StationID varchar(50))
BEGIN
		select * from location_master where `x` = 77 and `y` = 4 and z = 0;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_TruncateSubControllerReservation` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_TruncateSubControllerReservation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_TruncateSubControllerReservation`(
    
    )
BEGIN
		TRUNCATE `subcontroller_reservations_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateBinLocationInStoreBinMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateBinLocationInStoreBinMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateBinLocationInStoreBinMaster`(
	in binID int, 
	in rackLocation int
    )
BEGIN
		update `store_bin_master` set `PREV_BIN_ID` = `BIN_ID`, `BIN_ID` = binID where `LOCATION_ID` =  rackLocation;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateMaintanenceTaskEndLocationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateMaintanenceTaskEndLocationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateMaintanenceTaskEndLocationId`(in task_id int, in EndLocationId int)
BEGIN
		update task_master set DESTINATION_LOCATION_ID = EndLocationId WHERE TASK_ID = task_id;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateMaintenanceTaskMasterWithMaintenancePickBot` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateMaintenanceTaskMasterWithMaintenancePickBot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateMaintenanceTaskMasterWithMaintenancePickBot`(
	IN maintenanceId INT, in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		UPDATE `maintenance_task_master` SET `MAINTENANCE_PICK_POINT_BOT_ID` = botId WHERE `MAINTENANCE_ID` = maintenanceId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateManaulTaskReq` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateManaulTaskReq` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateManaulTaskReq`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in taskStatus varchar(50)
    )
BEGIN
		update `dashboard_manual_task_master` set `STATUS` = taskStatus where `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateRemoveSubControllerReservation` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateRemoveSubControllerReservation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateRemoveSubControllerReservation`(
	in locationID int,
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		DELETE FROM `subcontroller_reservations_master` WHERE `LOCATION_ID` = locationID and `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateStoreBinMasterAudit` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateStoreBinMasterAudit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateStoreBinMasterAudit`(
    in binLocationID int,
    in state boolean
    )
BEGIN
		update `store_bin_master` set `AUDIT` = state, `BIN_ID` = null, `AUDIT_MARKED_TIMESTAMP`=CURRENT_TIMESTAMP(3) where `LOCATION_ID` = binLocationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateStoreBinMasterAuditAlarm15` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateStoreBinMasterAuditAlarm15` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateStoreBinMasterAuditAlarm15`(
    IN binLocationID INT,
    IN state BOOLEAN
    )
BEGIN
		UPDATE `store_bin_master` SET `AUDIT` = state, `BIN_ID` = NULL WHERE `LOCATION_ID` = binLocationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateStoreBinMasterNull` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateStoreBinMasterNull` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateStoreBinMasterNull`(
	in locationID int
    )
BEGIN
		UPDATE `store_bin_master` SET `PREV_BIN_ID` = `BIN_ID`, `BIN_ID` = NULL WHERE `LOCATION_ID` = locationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateSubControllerReservation` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateSubControllerReservation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateSubControllerReservation`(
	IN SetBotID VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN SetDestinationID INT,
	IN SetBuffer TINYINT,
	IN locationID INT,
	in locationType varchar(100),
	IN parentLocationID int
    )
BEGIN
		INSERT into `subcontroller_reservations_master` (`LOCATION_ID`,`TYPE`,`BOT_ID`,`DESTINATION_ID`,`IS_BUFFER`, `PARENT_LOCATION_ID`, `UPDATED_TIMESTAMP`)
		VALUES (locationID, locationType, SetBotID, SetDestinationID, SetBuffer, parentLocationID, NOW());
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_UpdateTaskMasterProcessing` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_UpdateTaskMasterProcessing` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_UpdateTaskMasterProcessing`(
	in taskMasterID bigint
    )
BEGIN
		update `task_master` set `STATUS` = 'PROCESSING' WHERE `TASK_ID` = taskMasterID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_CheckAnyBotInMaintenance` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_CheckAnyBotInMaintenance` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_CheckAnyBotInMaintenance`()
BEGIN
    SELECT EXISTS(
        SELECT 1
        FROM subcontroller_reservations_master r
        JOIN hw_maintenance_master hm
          ON r.LOCATION_ID = hm.MAINTENANCE_POINT_LOCATION_ID          
        WHERE hm.IS_ACTIVE = 1
          AND r.BOT_ID IS NOT NULL
        LIMIT 1
    ) AS AnyMaintenance;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_CheckBinInBinInfo` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_CheckBinInBinInfo` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_CheckBinInBinInfo`(
	IN binID varchar(100)
    )
BEGIN
		SELECT * FROM `bin_info_master` WHERE BIN_BARCODE = binID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_CheckIfStoreLocationNull` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_CheckIfStoreLocationNull` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_CheckIfStoreLocationNull`(
	in p_storeLocationID int
    )
BEGIN
            DECLARE v_isNull BOOLEAN;
	    -- Check if BIN_ID is null for the matching store location.
	    SELECT BIN_ID IS NULL
	      INTO v_isNull
	      FROM store_bin_master
	     WHERE LOCATION_ID = p_storeLocationID
	     LIMIT 1;  -- Optional: ensures only one row is returned
	    -- Return the result (1 if BIN_ID is null; 0 if it is not null)
	    SELECT v_isNull AS IsBinNull;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_DeleteChargingBitOnLog` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_DeleteChargingBitOnLog` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_DeleteChargingBitOnLog`(
    IN p_bot_id VARCHAR(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    DELETE FROM bot_charging_bit_log
            WHERE bot_id = p_bot_id AND counter<15;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_DeleteMaintenanceTaskMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_DeleteMaintenanceTaskMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_DeleteMaintenanceTaskMaster`(
	IN maintenanceId INT
    )
BEGIN
		DELETE FROM `maintenance_task_master` WHERE MAINTENANCE_ID = maintenanceId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_EstimateNeededRobots` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_EstimateNeededRobots` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ts_EstimateNeededRobots`()
BEGIN
  /* needed_robots = base_needed (your per-station logic)
     + number of bots currently doing STATION_TO_STATION
  */
  SELECT
    base.base_needed + sts.sts_bots AS needed_robots
  FROM
  (
    SELECT
      COALESCE(SUM(
        LEAST(
          CASE
            WHEN COALESCE(t.pending_tasks, 0) = 0
                 AND EXISTS (
                   SELECT 1
                   FROM order_bin_mapping m
                   WHERE m.STATION_ID = s.STATION_ID
                     AND m.`TYPE`   = 'STATION_PICK'
                     AND m.`STATUS` = 'PENDING'
                     AND m.BOT_ID IS NULL
                 )
            THEN 1
            ELSE COALESCE(t.pending_tasks, 0)
          END,
          COALESCE(a.bot_count_current, 0)
        )
      ), 0) AS base_needed
    FROM (
      /* candidate stations = stations with tasks OR with a qualifying STATION_PICK */
      SELECT STATION_ID FROM order_bin_task_master
      UNION
      SELECT DISTINCT STATION_ID
      FROM order_bin_mapping
      WHERE `TYPE`='STATION_PICK' AND `STATUS`='PENDING' AND BOT_ID IS NULL
    ) s
    LEFT JOIN (
      SELECT STATION_ID, COUNT(*) AS pending_tasks
      FROM order_bin_task_master
      GROUP BY STATION_ID
    ) t ON t.STATION_ID = s.STATION_ID
    LEFT JOIN (
      /* only BOT_COUNT_CURRENT, choose the max non-NULL if multiple rows exist */
      SELECT STATION_ID, MAX(COALESCE(BOT_COUNT_CURRENT,0)) AS bot_count_current
      FROM wave_station_rule_mapping
      GROUP BY STATION_ID
    ) a ON a.STATION_ID = s.STATION_ID
  ) AS base
  CROSS JOIN
  (
    SELECT COUNT(tm.task_id) AS sts_bots
    FROM task_master tm
    WHERE tm.`STATUS` = 'PROCESSING'
      AND tm.`TASK_TYPE` = 'STATION_TO_STATION'
  ) AS sts;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_FindNearestBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_FindNearestBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_FindNearestBin`(IN stationid INT,
    IN aisleid INT,
    IN towerid INT)
BEGIN
	SELECT `ORDER_BIN_ID`, `BIN_ID` FROM `order_bin_task_master`
    WHERE STATION_ID = stationid AND `AISLE_ID` = aisleid AND `TOWER_ID` = towerid order by `TOWER_LEVEL`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetAislesWithTasks` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetAislesWithTasks` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetAislesWithTasks`()
BEGIN
    SELECT DISTINCT `AISLE_ID` FROM `order_bin_task_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetAutoStartErrorCount` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetAutoStartErrorCount` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetAutoStartErrorCount`()
BEGIN
    SELECT COUNT(DISTINCT bm.BOT_ID) AS AutoStartErrorCount
    FROM bot_master bm
    JOIN teleoperation_bool_data_feedback t
         ON t.bot_id = bm.BOT_ID
    WHERE t.`Auto Start Feedback` = 1
      AND IFNULL(bm.ALARM, 0) <> 0;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetAutoStartZeroCount` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetAutoStartZeroCount` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetAutoStartZeroCount`()
BEGIN
    SELECT COUNT(DISTINCT t.bot_id) AS AutoStartBotCount
    FROM teleoperation_bool_data_feedback t
    WHERE t.`Auto Start Feedback` = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetBotChargingCounter` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetBotChargingCounter` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetBotChargingCounter`(
    IN p_bot_id VARCHAR(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    SELECT counter
    FROM   bot_charging_bit_log
    WHERE  bot_id = p_bot_id
    ORDER  BY inserted_timestamp DESC
    LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetMuxAutoBool` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetMuxAutoBool` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetMuxAutoBool`(
)
BEGIN
    SELECT AUTO_BOOL
    FROM hw_conveyor_mux_master
    WHERE MUX_ID = 91;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetNearestBinInAisles` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetNearestBinInAisles` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetNearestBinInAisles`(in p_stationId int, in p_aisleId int)
BEGIN
		select obtm.`ORDER_BIN_ID`,obtm.`BIN_ID`
		from `order_bin_task_master` obtm INNER join location_master lm 
		on obtm.tower_id = lm.location_id
		where obtm.`STATION_ID` = p_stationId
		and obtm.`AISLE_ID` = p_aisleId 
		order by lm.X, obtm.`TOWER_LEVEL`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetOrderBinMappingState` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetOrderBinMappingState` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetOrderBinMappingState`(
	IN orderBinId INT
    )
BEGIN
		SELECT `STATUS` FROM `order_bin_mapping` WHERE `ORDER_BIN_ID` = orderBinId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetOrderBinMappingStatusByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetOrderBinMappingStatusByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetOrderBinMappingStatusByBinId`(in p_binId int, in p_orderBinId int)
BEGIN
		SELECT `ORDER_BIN_ID`,`STATUS`, `TYPE`
		FROM `order_bin_mapping` 
		WHERE `BIN_ID` = p_binId
		AND ORDER_BIN_ID <> p_orderBinId
		AND (`STATUS` NOT IN ('PENDING','TASK_COMPLETED','POST_ON_STATION')
		OR `STATUS` = 'PENDING' AND `BOT_ID` IS NOT NULL)
		LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_getputpickcompletestatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_getputpickcompletestatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_getputpickcompletestatus`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in taskDetailID varchar(50),
	in pickput varchar(100)
    )
BEGIN
		
	SELECT IS_COMPLETED FROM steps WHERE `BOT_ID` = botID AND `TASK_DETAIL_ID`=taskDetailID AND `PICK_PUT`=pickput;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetStarvingStationIds` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetStarvingStationIds` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetStarvingStationIds`()
BEGIN
    /*
      Starving station:
        - Has >=1 task in order_bin_task_master
        - Has 0 distinct non-null BOT_ID in order_bin_mapping
      Output: only station_id list
    */

    SELECT tc.station_id
    FROM (
        SELECT obtm.STATION_ID AS station_id
        FROM order_bin_task_master obtm
        WHERE obtm.STATION_ID IS NOT NULL
        GROUP BY obtm.STATION_ID
    ) tc
    LEFT JOIN (
        SELECT obm.STATION_ID AS station_id,
               COUNT(DISTINCT obm.BOT_ID) AS assigned_bots
        FROM order_bin_mapping obm
        WHERE obm.type = 'RACK_PICK' and obm.status <> 'TASK_COMPLETED'
          AND obm.BOT_ID IS NOT NULL
        GROUP BY obm.STATION_ID
    ) bc
      ON bc.station_id = tc.station_id
    WHERE COALESCE(bc.assigned_bots, 0) = 0
    ORDER BY tc.station_id ASC;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_GetStationsWithTasks` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_GetStationsWithTasks` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_GetStationsWithTasks`()
BEGIN
    SELECT DISTINCT `STATION_ID` FROM `order_bin_task_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_IfTowerHasTasks` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_IfTowerHasTasks` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_IfTowerHasTasks`(in towerID int)
BEGIN
    SELECT `AISLE_ID` FROM `order_bin_task_master` WHERE `TOWER_ID` = towerID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_InsertBotEntryInChargingBitLog` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_InsertBotEntryInChargingBitLog` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_InsertBotEntryInChargingBitLog`(
    IN p_bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN battery  INT
)
BEGIN
    INSERT INTO bot_charging_bit_log
          (bot_id, battery_percentage, counter)
    VALUES (p_bot_id, battery, 1);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_InsertOrderBinTask` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_InsertOrderBinTask` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_InsertOrderBinTask`(IN orderBinId INT,
    IN bin_id INT,
    IN station_id INT,
    IN aisle_id INT,
    IN tower_id INT,
    in tower_level int)
BEGIN
    DELETE FROM order_bin_task_master where ORDER_BIN_ID = orderBinId;
    INSERT INTO order_bin_task_master (`STATION_ID`, `AISLE_ID`, `TOWER_ID`, `ORDER_BIN_ID`, `BIN_ID`, `TOWER_LEVEL`)
    VALUES (station_id, aisle_id, tower_id, orderBinId, bin_id, tower_level);
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_InsertRecoveryBinTask` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_InsertRecoveryBinTask` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_InsertRecoveryBinTask`(
	IN orderBinId INT, 
	IN stationId INT, 
	IN binId INT
    )
BEGIN
		INSERT INTO `recovery_pick_task_master` (`ORDER_BIN_ID`,`STATION_ID`,`BIN_ID`) VALUES (orderBinId, stationId, binId);
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_InsertStationBinTask` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_InsertStationBinTask` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_InsertStationBinTask`(
	IN orderBinId int, 
	in stationId INT, 
	IN binId int
    )
BEGIN
		insert into `station_pick_task_master` (`ORDER_BIN_ID`,`STATION_ID`,`BIN_ID`) values (orderBinId, stationId, binId);
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_IsBotPresentInChargingBitOnLog` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_IsBotPresentInChargingBitOnLog` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_IsBotPresentInChargingBitOnLog`(
    IN p_bot_id VARCHAR(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
     SELECT COUNTER
    FROM bot_charging_bit_log
    WHERE bot_id = p_bot_id
    AND INSERTED_TIMESTAMP >= NOW(3)- INTERVAL 10 MINUTE
    ORDER BY INSERTED_TIMESTAMP DESC
    LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_RemoveBinById` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_RemoveBinById` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_RemoveBinById`(IN p_binId INT)
BEGIN
	    DELETE FROM `order_bin_task_master` WHERE `BIN_ID` = p_binId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_RemoveRecoveryPickBinById` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_RemoveRecoveryPickBinById` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_RemoveRecoveryPickBinById`(IN p_binId INT)
BEGIN
		DELETE FROM `recovery_pick_task_master` WHERE `BIN_ID` = p_binId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_RemoveStationPickBinById` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_RemoveStationPickBinById` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_RemoveStationPickBinById`(IN p_binId INT)
BEGIN
		DELETE FROM `station_pick_task_master` WHERE `BIN_ID` = p_binId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllBlockedAisleLocations` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllBlockedAisleLocations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllBlockedAisleLocations`()
BEGIN
		select * from `location_block_master` where TYPE = "AISLE_ENTRY";
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllBlockedHomeLocations` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllBlockedHomeLocations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllBlockedHomeLocations`()
BEGIN
		select * from `location_block_master` where TYPE in ("HOME", "STATION_HOME");
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllBlockedStationLocations` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllBlockedStationLocations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllBlockedStationLocations`()
BEGIN
		select * from `location_block_master` where TYPE = "STATION";
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllBlockedStorageLocations` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllBlockedStorageLocations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllBlockedStorageLocations`()
BEGIN
		select * from `location_block_master` where TYPE = "STORAGE_LOCATION";
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllBlockedTowerLocations` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllBlockedTowerLocations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllBlockedTowerLocations`()
BEGIN
		select * from `location_block_master` where TYPE LIKE '%TOWER%';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllocatedRobotBins` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllocatedRobotBins` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllocatedRobotBins`(
    )
BEGIN
		select `BIN_ID` from `order_bin_mapping` WHERE STATUS NOT IN ('PENDING', 'OPERATION_COMPLETED', 'TASK_COMPLETED');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllPendingNonRecovery` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllPendingNonRecovery` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllPendingNonRecovery`()
BEGIN
		 CREATE TEMPORARY TABLE temp_recovery_task_master AS
	    SELECT *
	    FROM order_bin_mapping 
	    WHERE STATUS = 'PENDING' AND IS_SYNCED = 0 AND `TYPE` = 'RECOVERY_PICK';
	    
	    UPDATE order_bin_mapping
	    SET IS_SYNCED = 1
	    WHERE ORDER_BIN_ID IN (SELECT ORDER_BIN_ID FROM temp_recovery_task_master);
	    
	    SELECT * FROM temp_recovery_task_master;
	    
	    DROP TEMPORARY TABLE IF EXISTS temp_recovery_task_master;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllStationPickTasks` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllStationPickTasks` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllStationPickTasks`(
    )
BEGIN
		SELECT `ORDER_BIN_ID`,`STATION_ID`,`BIN_ID` FROM `station_pick_task_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllSyncedTasks` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllSyncedTasks` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllSyncedTasks`()
BEGIN
		select `ORDER_BIN_ID`,`BIN_ID`,`STATION_ID`,`TYPE` from `order_bin_mapping` where `STATUS` = 'PENDING' AND `IS_SYNCED` = 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAllUnloadedBins` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAllUnloadedBins` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAllUnloadedBins`()
BEGIN
     -- Step 1: Create a Temporary Table
    CREATE TEMPORARY TABLE temp_order_bin_mapping AS
    SELECT *
    FROM order_bin_mapping 
    WHERE STATUS = 'PENDING' AND IS_SYNCED = 0 and `TYPE` = 'RACK_PICK';
    -- Step 2: Update the IS_SYNCED Field in the Main Table
    UPDATE order_bin_mapping
    SET IS_SYNCED = 1
    WHERE ORDER_BIN_ID IN (SELECT ORDER_BIN_ID FROM temp_order_bin_mapping);
    
    select * from temp_order_bin_mapping;
    -- Optional: Drop the Temporary Table (it will be dropped automatically at the end of the session)
    DROP TEMPORARY TABLE IF EXISTS temp_order_bin_mapping;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectAuditMarkLocations` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectAuditMarkLocations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectAuditMarkLocations`(
    )
BEGIN
		SELECT location_id FROM store_bin_master WHERE audit=1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBestAisleToPutFromStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBestAisleToPutFromStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ts_SelectBestAisleToPutFromStation`(IN p_station_id INT)
BEGIN
  /* ---- Weights ---- */
  DECLARE w_future     DOUBLE DEFAULT 0.50;  -- favors positions with more future tasks ahead (follow-on efficiency)
  DECLARE w_div        DOUBLE DEFAULT 1.00;  -- station diversity window
  DECLARE w_same       DOUBLE DEFAULT 0.10;  -- same-tower pending tasks
  DECLARE w_dist       DOUBLE DEFAULT 0.25;  -- distance to aisle entry (penalty)
  DECLARE w_depth      DOUBLE DEFAULT 0.10;  -- deeper towers get a small penalty
  DECLARE w_bal_tower  DOUBLE DEFAULT 0.80;  -- NEW: tower fill balancing (higher empties => higher score)
  DECLARE w_bal_aisle  DOUBLE DEFAULT 0.20;  -- NEW: aisle fill balancing (higher empties => higher score)
 
  WITH
  /* ---- Station pick coords ---- */
  station_pick AS (
    SELECT s.STATION_ID, s.PICK_ACTION_LOCATION_ID AS pick_loc_id,
           lm.X AS sx, lm.Y AS sy, COALESCE(lm.Z,0) AS sz
    FROM hw_station_master s
    JOIN location_master lm ON lm.LOCATION_ID = s.PICK_ACTION_LOCATION_ID
    WHERE s.STATION_ID = p_station_id
  ),
 
  /* ---- All aisle entries ---- */
  aisle_entries AS (
    SELECT lm.LOCATION_ID AS entry_loc_id, lm.AISLE_NUMBER,
           lm.X AS ex, lm.Y AS ey, COALESCE(lm.Z,0) AS ez
    FROM location_master lm
    WHERE lm.TYPE = 'AISLE_ENTRY'
  ),
 
  /* ---- Nearest entry per aisle to this station ---- */
  nearest_entry AS (
    SELECT ae.AISLE_NUMBER,
           ae.entry_loc_id,
           ABS(sp.sx - ae.ex) + ABS(sp.sy - ae.ey) + ABS(sp.sz - ae.ez) AS dist,
           ROW_NUMBER() OVER (
             PARTITION BY ae.AISLE_NUMBER
             ORDER BY ABS(sp.sx - ae.ex) + ABS(sp.sy - ae.ey) + ABS(sp.sz - ae.ez)
           ) AS rn
    FROM aisle_entries ae
    CROSS JOIN station_pick sp
  ),
  nearest_entry_pick AS (
    SELECT AISLE_NUMBER, entry_loc_id, dist
    FROM nearest_entry
    WHERE rn = 1
  ),
 
  /* ---- Map task rows (location_id → numeric aisle/tower) ---- */
  task_positions AS (
    SELECT
      CAST(SUBSTRING(la.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lt.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      ob.STATION_ID
    FROM order_bin_task_master ob
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
    -- WHERE ob.TASK_STATUS IN ('PENDING','ASSIGNED')
  ),
 
  /* ---- Aggregates per (aisle,tower) for task signals ---- */
  tower_task_base AS (
    SELECT
      aisle_num_id AS AISLE_ID,
      tower_num_id AS TOWER_ID,
      COUNT(*)                   AS tower_tasks,
      COUNT(DISTINCT STATION_ID) AS tower_station_div
    FROM task_positions
    GROUP BY aisle_num_id, tower_num_id
  ),
  tower_task_cum AS (
    SELECT AISLE_ID, TOWER_ID,
           SUM(tower_tasks) OVER (
             PARTITION BY AISLE_ID
             ORDER BY TOWER_ID
             ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
           ) AS aisle_future_tasks_from_here
    FROM tower_task_base
  ),
  aisle_station_max AS (
    SELECT
      aisle_num_id AS AISLE_ID,
      STATION_ID,
      MAX(tower_num_id) AS max_tower_id
    FROM task_positions
    GROUP BY aisle_num_id, STATION_ID
  ),
 
  /* ---- Compute per-(aisle,tower) max Z; we'll reserve that top Z ---- */
  tower_z_cap AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lm.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      MAX(COALESCE(lm.Z,0)) AS z_top
    FROM location_master lm
    GROUP BY aisle_num_id, tower_num_id
  ),
 
  /* ---- Usable locations = not blocked, audit=0; and EXCLUDE top Z per tower ---- */
  usable_locations AS (
    SELECT
      sb.LOCATION_ID,
      sb.BIN_ID,
      COALESCE(sb.AUDIT,0) AS audit,
      sb.COST,
      lm.AISLE_NUMBER,
      CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lm.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      COALESCE(lm.Z,0) AS z
    FROM store_bin_master sb
    JOIN location_master lm ON lm.LOCATION_ID = sb.LOCATION_ID
    LEFT JOIN location_block_master lbm ON lbm.LOCATION_ID = sb.LOCATION_ID
    JOIN tower_z_cap tz ON tz.aisle_num_id = CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED)
                       AND tz.tower_num_id = CAST(SUBSTRING(lm.TOWER_NUMBER,2) AS UNSIGNED)
    WHERE lbm.LOCATION_ID IS NULL
      AND COALESCE(sb.AUDIT,0) = 0
      AND COALESCE(lm.Z,0) < tz.z_top   -- <-- reserve the highest Z per (aisle,tower)
  ),
 
  /* ---- Capacity & fill per (aisle,tower) over usable set ---- */
  tower_fill AS (
    SELECT
      aisle_num_id,
      tower_num_id,
      COUNT(*)                                   AS cap_usable,
      SUM(CASE WHEN BIN_ID IS NOT NULL THEN 1 ELSE 0 END) AS occ_usable,
      SUM(CASE WHEN BIN_ID IS NULL  THEN 1 ELSE 0 END)    AS emp_usable
    FROM usable_locations
    GROUP BY aisle_num_id, tower_num_id
  ),
  /* Fill per aisle (sum across towers) */
  aisle_fill AS (
    SELECT
      aisle_num_id,
      SUM(cap_usable) AS aisle_cap_usable,
      SUM(occ_usable) AS aisle_occ_usable,
      SUM(emp_usable) AS aisle_emp_usable
    FROM tower_fill
    GROUP BY aisle_num_id
  ),
 
  /* ---- Candidate empty locations (one representative row per (aisle,tower)) ---- */
  candidate_towers AS (
    SELECT
      ul.aisle_num_id,
      ul.tower_num_id,
      MIN(ul.COST)        AS tower_cost,          -- representative cost
      MIN(ul.LOCATION_ID) AS sample_location_id,  -- representative location to place
      MIN(ul.AISLE_NUMBER) AS AISLE_NUMBER
    FROM usable_locations ul
    WHERE ul.BIN_ID IS NULL
    GROUP BY ul.aisle_num_id, ul.tower_num_id
  ),
 
  /* ---- Distance using nearest entry per aisle ---- */
  cand_with_dist AS (
    SELECT
      ct.sample_location_id AS LOCATION_ID,
      ct.tower_cost         AS COST,
      ct.AISLE_NUMBER,
      ct.aisle_num_id,
      ct.tower_num_id,
      ne.entry_loc_id,
      ne.dist AS dist_to_aisle_entry
    FROM candidate_towers ct
    JOIN nearest_entry_pick ne
      ON ne.AISLE_NUMBER = ct.AISLE_NUMBER
  ),
 
  /* ---- Diversity window (precomputed once per candidate) ---- */
  station_div_by_cand AS (
    SELECT
      c.aisle_num_id,
      c.tower_num_id,
      COUNT(DISTINCT asm.STATION_ID) AS station_div_window
    FROM cand_with_dist c
    JOIN aisle_station_max asm
      ON asm.AISLE_ID = c.aisle_num_id
     AND asm.max_tower_id >= c.tower_num_id
    GROUP BY c.aisle_num_id, c.tower_num_id
  ),
 
  /* ---- Scoring with balancing terms ---- */
  scored AS (
    SELECT
      c.LOCATION_ID,
      c.COST,
      c.AISLE_NUMBER,
      c.aisle_num_id,
      c.tower_num_id,
      c.entry_loc_id,
      c.dist_to_aisle_entry,
 
      COALESCE(ttb.tower_tasks, 0)        AS same_tower_tasks,
      COALESCE(ttb.tower_station_div, 0)  AS same_tower_station_div,
      COALESCE(ttc.aisle_future_tasks_from_here, 0) AS aisle_future_tasks,
      COALESCE(sd.station_div_window, 0)  AS station_div_window,
 
      /* Balancing ratios */
      COALESCE(tf.emp_usable / NULLIF(tf.cap_usable,0), 0)   AS tower_empty_ratio,
      COALESCE(af.aisle_emp_usable / NULLIF(af.aisle_cap_usable,0), 0) AS aisle_empty_ratio,
 
      ( w_future * COALESCE(ttc.aisle_future_tasks_from_here, 0)
      + w_div    * COALESCE(sd.station_div_window, 0)
      + w_same   * COALESCE(ttb.tower_tasks, 0)
      + w_bal_tower * COALESCE(tf.emp_usable / NULLIF(tf.cap_usable,0), 0)
      + w_bal_aisle * COALESCE(af.aisle_emp_usable / NULLIF(af.aisle_cap_usable,0), 0)
      - w_dist   * c.dist_to_aisle_entry
      - w_depth  * GREATEST(c.tower_num_id - 1, 0)
      ) AS score
    FROM cand_with_dist c
    LEFT JOIN tower_task_base ttb
      ON ttb.AISLE_ID = c.aisle_num_id
     AND ttb.TOWER_ID = c.tower_num_id
    LEFT JOIN tower_task_cum ttc
      ON ttc.AISLE_ID = c.aisle_num_id
     AND ttc.TOWER_ID = c.tower_num_id
    LEFT JOIN station_div_by_cand sd
      ON sd.aisle_num_id = c.aisle_num_id
     AND sd.tower_num_id = c.tower_num_id
    LEFT JOIN tower_fill tf
      ON tf.aisle_num_id = c.aisle_num_id
     AND tf.tower_num_id = c.tower_num_id
    LEFT JOIN aisle_fill af
      ON af.aisle_num_id = c.aisle_num_id
  ),
 
  /* ---- Aggregate per aisle ---- */
  aisle_agg AS (
    SELECT
      s.AISLE_NUMBER,
      ROUND(SUM(s.score), 2) AS score,
      SUM(s.COST) AS cost
    FROM scored s
    GROUP BY s.AISLE_NUMBER
  )
 
  /* ---- Final: Best aisle’s entry location for the given station ---- */
  SELECT
    ne.entry_loc_id AS AISLE_ENTRY_LOCATION_ID
  FROM aisle_agg aa
  JOIN nearest_entry_pick ne
    ON ne.AISLE_NUMBER = aa.AISLE_NUMBER
  ORDER BY aa.score DESC, aa.cost ASC;
 
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBestAisleToPutFromStation_block` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBestAisleToPutFromStation_block` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ts_SelectBestAisleToPutFromStation_block`(IN p_station_id INT)
BEGIN
  
  DECLARE w_future     DOUBLE DEFAULT 0.50;  
  DECLARE w_div        DOUBLE DEFAULT 1.00;  
  DECLARE w_same       DOUBLE DEFAULT 0.10;  
  DECLARE w_dist       DOUBLE DEFAULT 0.25;  
  DECLARE w_depth      DOUBLE DEFAULT 0.10;  
  DECLARE w_bal_tower  DOUBLE DEFAULT 0.80;  
  DECLARE w_bal_aisle  DOUBLE DEFAULT 0.20;  

  
  DECLARE v_top_aisles INT DEFAULT 5;              
  DECLARE v_max_locs_per_aisle INT DEFAULT 10;     

  WITH
  
  station_pick AS (
    SELECT s.STATION_ID, s.PICK_ACTION_LOCATION_ID AS pick_loc_id,
           lm.X AS sx, lm.Y AS sy, COALESCE(lm.Z,0) AS sz
    FROM hw_station_master s
    JOIN location_master lm ON lm.LOCATION_ID = s.PICK_ACTION_LOCATION_ID
    WHERE s.STATION_ID = p_station_id
  ),

  
  aisle_entries AS (
    SELECT lm.LOCATION_ID AS entry_loc_id, lm.AISLE_NUMBER,
           lm.X AS ex, lm.Y AS ey, COALESCE(lm.Z,0) AS ez
    FROM location_master lm
    WHERE lm.TYPE = 'AISLE_ENTRY'
  ),

  
  nearest_entry AS (
    SELECT ae.AISLE_NUMBER,
           ae.entry_loc_id,
           ABS(sp.sx - ae.ex) + ABS(sp.sy - ae.ey) + ABS(sp.sz - ae.ez) AS dist,
           ROW_NUMBER() OVER (
             PARTITION BY ae.AISLE_NUMBER
             ORDER BY ABS(sp.sx - ae.ex) + ABS(sp.sy - ae.ey) + ABS(sp.sz - ae.ez)
           ) AS rn
    FROM aisle_entries ae
    CROSS JOIN station_pick sp
  ),
  nearest_entry_pick AS (
    SELECT AISLE_NUMBER, entry_loc_id, dist
    FROM nearest_entry
    WHERE rn = 1
  ),

  
  task_positions AS (
    SELECT
      CAST(SUBSTRING(la.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lt.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      ob.ORDER_BIN_ID,
      ob.STATION_ID
    FROM order_bin_task_master ob
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
  ),

  
  tower_task_base AS (
    SELECT
      aisle_num_id AS AISLE_ID,
      tower_num_id AS TOWER_ID,
      COUNT(*)                   AS tower_tasks,
      COUNT(DISTINCT STATION_ID) AS tower_station_div
    FROM task_positions
    GROUP BY aisle_num_id, tower_num_id
  ),
  tower_task_cum AS (
    SELECT AISLE_ID, TOWER_ID,
           SUM(tower_tasks) OVER (
             PARTITION BY AISLE_ID
             ORDER BY TOWER_ID
             ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
           ) AS aisle_future_tasks_from_here
    FROM tower_task_base
  ),
  aisle_station_max AS (
    SELECT
      aisle_num_id AS AISLE_ID,
      STATION_ID,
      MAX(tower_num_id) AS max_tower_id
    FROM task_positions
    GROUP BY aisle_num_id, STATION_ID
  ),

  
  tower_z_cap AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lm.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      MAX(COALESCE(lm.Z,0)) AS z_top
    FROM location_master lm
    GROUP BY aisle_num_id, tower_num_id
  ),

  
  usable_locations AS (
    SELECT
      sb.LOCATION_ID,
      sb.BIN_ID,
      COALESCE(sb.AUDIT,0) AS audit,
      sb.COST,
      lm.AISLE_NUMBER,
      CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lm.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      COALESCE(lm.Z,0) AS z
    FROM store_bin_master sb
    JOIN location_master lm ON lm.LOCATION_ID = sb.LOCATION_ID
    LEFT JOIN location_block_master lbm ON lbm.LOCATION_ID = sb.LOCATION_ID
    JOIN tower_z_cap tz ON tz.aisle_num_id = CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED)
                       AND tz.tower_num_id = CAST(SUBSTRING(lm.TOWER_NUMBER,2) AS UNSIGNED)
    WHERE lbm.LOCATION_ID IS NULL
      AND COALESCE(sb.AUDIT,0) = 0
      AND COALESCE(lm.Z,0) < tz.z_top
  ),

  
  tower_fill AS (
    SELECT
      aisle_num_id,
      tower_num_id,
      COUNT(*) AS cap_usable,
      SUM(CASE WHEN BIN_ID IS NOT NULL THEN 1 ELSE 0 END) AS occ_usable,
      SUM(CASE WHEN BIN_ID IS NULL  THEN 1 ELSE 0 END)    AS emp_usable
    FROM usable_locations
    GROUP BY aisle_num_id, tower_num_id
  ),
  aisle_fill AS (
    SELECT
      aisle_num_id,
      SUM(cap_usable) AS aisle_cap_usable,
      SUM(occ_usable) AS aisle_occ_usable,
      SUM(emp_usable) AS aisle_emp_usable
    FROM tower_fill
    GROUP BY aisle_num_id
  ),

  
  candidate_towers AS (
    SELECT
      ul.aisle_num_id,
      ul.tower_num_id,
      MIN(ul.COST)         AS tower_cost,
      MIN(ul.LOCATION_ID)  AS sample_location_id,
      MIN(ul.AISLE_NUMBER) AS AISLE_NUMBER
    FROM usable_locations ul
    WHERE ul.BIN_ID IS NULL
    GROUP BY ul.aisle_num_id, ul.tower_num_id
  ),

  
  cand_with_dist AS (
    SELECT
      ct.sample_location_id AS LOCATION_ID,
      ct.tower_cost         AS COST,
      ct.AISLE_NUMBER,
      ct.aisle_num_id,
      ct.tower_num_id,
      ne.entry_loc_id,
      ne.dist AS dist_to_aisle_entry
    FROM candidate_towers ct
    JOIN nearest_entry_pick ne
      ON ne.AISLE_NUMBER = ct.AISLE_NUMBER
  ),

  
  station_div_by_cand AS (
    SELECT
      c.aisle_num_id,
      c.tower_num_id,
      COUNT(DISTINCT asm.STATION_ID) AS station_div_window
    FROM cand_with_dist c
    JOIN aisle_station_max asm
      ON asm.AISLE_ID = c.aisle_num_id
     AND asm.max_tower_id >= c.tower_num_id
    GROUP BY c.aisle_num_id, c.tower_num_id
  ),

  
  scored AS (
    SELECT
      c.LOCATION_ID,
      c.COST,
      c.AISLE_NUMBER,
      c.aisle_num_id,
      c.tower_num_id,
      c.entry_loc_id,
      c.dist_to_aisle_entry,

      COALESCE(ttb.tower_tasks, 0)        AS same_tower_tasks,
      COALESCE(ttb.tower_station_div, 0)  AS same_tower_station_div,
      COALESCE(ttc.aisle_future_tasks_from_here, 0) AS aisle_future_tasks,
      COALESCE(sd.station_div_window, 0)  AS station_div_window,

      COALESCE(tf.emp_usable / NULLIF(tf.cap_usable,0), 0)   AS tower_empty_ratio,
      COALESCE(af.aisle_emp_usable / NULLIF(af.aisle_cap_usable,0), 0) AS aisle_empty_ratio,

      ( w_future * COALESCE(ttc.aisle_future_tasks_from_here, 0)
      + w_div    * COALESCE(sd.station_div_window, 0)
      + w_same   * COALESCE(ttb.tower_tasks, 0)
      + w_bal_tower * COALESCE(tf.emp_usable / NULLIF(tf.cap_usable,0), 0)
      + w_bal_aisle * COALESCE(af.aisle_emp_usable / NULLIF(af.aisle_cap_usable,0), 0)
      - w_dist   * c.dist_to_aisle_entry
      - w_depth  * GREATEST(c.tower_num_id - 1, 0)
      ) AS score
    FROM cand_with_dist c
    LEFT JOIN tower_task_base ttb
      ON ttb.AISLE_ID = c.aisle_num_id
     AND ttb.TOWER_ID = c.tower_num_id
    LEFT JOIN tower_task_cum ttc
      ON ttc.AISLE_ID = c.aisle_num_id
     AND ttc.TOWER_ID = c.tower_num_id
    LEFT JOIN station_div_by_cand sd
      ON sd.aisle_num_id = c.aisle_num_id
     AND sd.tower_num_id = c.tower_num_id
    LEFT JOIN tower_fill tf
      ON tf.aisle_num_id = c.aisle_num_id
     AND tf.tower_num_id = c.tower_num_id
    LEFT JOIN aisle_fill af
      ON af.aisle_num_id = c.aisle_num_id
  ),

  
  aisle_agg AS (
    SELECT
      s.AISLE_NUMBER,
      ROUND(SUM(s.score), 2) AS score,
      SUM(s.COST) AS cost
    FROM scored s
    GROUP BY s.AISLE_NUMBER
  ),
  aisle_ranked AS (
    SELECT
      a.*,
      ROW_NUMBER() OVER (ORDER BY a.score DESC, a.cost ASC) AS aisle_rank
    FROM aisle_agg a
  ),
  top_aisles AS (
    SELECT *
    FROM aisle_ranked
    WHERE aisle_rank <= v_top_aisles
  ),

  
  top_cands AS (
    SELECT
      s.AISLE_NUMBER,
      s.LOCATION_ID,
      s.aisle_num_id,
      s.tower_num_id,
      s.score,
      s.COST,
      ROW_NUMBER() OVER (
        PARTITION BY s.AISLE_NUMBER
        ORDER BY s.score DESC, s.COST ASC
      ) AS candidate_rank
    FROM scored s
    JOIN top_aisles ta ON ta.AISLE_NUMBER = s.AISLE_NUMBER
  ),
  limited_cands AS (
    SELECT *
    FROM top_cands
    WHERE candidate_rank <= v_max_locs_per_aisle
  ),

  
  stac AS (
    SELECT
      CAST(SUBSTRING(Aisle_Number, 2) AS UNSIGNED) AS aisle_num_id,
      Cost
    FROM station_to_aisle_cost
    WHERE Station_ID = p_station_id
  )

  
  SELECT
    lc.LOCATION_ID       AS Location_ID,
    q.ORDER_BIN_ID       AS Order_Bin_ID,
    q.STATION_ID         AS Station_ID,
    q.pref               AS Preference,      
    lc.AISLE_NUMBER      AS Aisle_Number,
    lc.tower_num_id      AS Tower_Num_Id,
    ta.aisle_rank        AS Aisle_Rank,
    lc.candidate_rank    AS Candidate_Rank
  FROM limited_cands lc
  JOIN top_aisles ta ON ta.AISLE_NUMBER = lc.AISLE_NUMBER
  JOIN (
    
    SELECT
      la.AISLE_NUMBER,
      CAST(SUBSTRING(lt.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      ob.ORDER_BIN_ID,
      ob.STATION_ID,
      0 AS pref
    FROM order_bin_task_master ob
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
    UNION ALL
    
    SELECT
      la.AISLE_NUMBER,
      CAST(SUBSTRING(lt.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      ob.ORDER_BIN_ID,
      ob.STATION_ID,
      1 AS pref
    FROM order_bin_task_master ob
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
  ) q
    ON q.AISLE_NUMBER = lc.AISLE_NUMBER
   AND (
        (q.pref = 0 AND q.tower_num_id =  lc.tower_num_id)      
        OR
        (q.pref = 1 AND q.tower_num_id <> lc.tower_num_id)      
       )
  LEFT JOIN stac sc
    ON sc.aisle_num_id = lc.aisle_num_id
  
  ORDER BY
    COALESCE(sc.Cost, 1000000000),
    lc.candidate_rank,
    q.pref,
    q.ORDER_BIN_ID;

  
  WITH per_station AS (
    SELECT
      ob.STATION_ID,
      ob.ORDER_BIN_ID,
      ROW_NUMBER() OVER (PARTITION BY ob.STATION_ID ORDER BY ob.ORDER_BIN_ID) AS rn
    FROM order_bin_task_master ob
  )
  SELECT
    ps.STATION_ID,
    ps.ORDER_BIN_ID
  FROM per_station ps
  WHERE ps.rn = 1
  ORDER BY ps.STATION_ID;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBestPutLocationsForStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBestPutLocationsForStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectBestPutLocationsForStation`(IN p_station_id INT)
BEGIN
  /* ---- Weights ---- */
  DECLARE w_future     DOUBLE DEFAULT 0.50;
  DECLARE w_div        DOUBLE DEFAULT 1.00;
  DECLARE w_same       DOUBLE DEFAULT 0.10;
  DECLARE w_dist       DOUBLE DEFAULT 0.25;
  DECLARE w_depth      DOUBLE DEFAULT 0.10;
  DECLARE w_bal_tower  DOUBLE DEFAULT 0.80;
  DECLARE w_bal_aisle  DOUBLE DEFAULT 0.20;
  DECLARE w_bot_pen    DOUBLE DEFAULT 5.00;
  DECLARE w_topz_pen   DOUBLE DEFAULT 2.50;  -- soft penalty at top Z (fallback)

  /* N = live stations (min 12) */
  DECLARE v_n INT DEFAULT 0;
  SELECT COUNT(*) INTO v_n
  FROM hw_station_master
  WHERE UPPER(wave_status) = 'WAVE_LIVE';

  IF (v_n < 12) THEN
    SET v_n = 12;
  END IF;

  WITH
  station_pick AS (
    SELECT s.STATION_ID, s.PICK_ACTION_LOCATION_ID AS pick_loc_id,
           lm.X AS sx, lm.Y AS sy, COALESCE(lm.Z,0) AS sz
    FROM hw_station_master s
    JOIN location_master lm ON lm.LOCATION_ID = s.PICK_ACTION_LOCATION_ID
    WHERE s.STATION_ID = p_station_id
  ),

  aisle_entries AS (
    SELECT lm.LOCATION_ID AS entry_loc_id,
           lm.AISLE_NUMBER,
           CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
           lm.X AS ex, lm.Y AS ey, COALESCE(lm.Z,0) AS ez
    FROM location_master lm
    WHERE lm.TYPE = 'AISLE_ENTRY'
      AND lm.AISLE_NUMBER IS NOT NULL
  ),

  nearest_entry AS (
    SELECT ae.aisle_num_id,
           ae.entry_loc_id,
           ABS(sp.sx - ae.ex) + ABS(sp.sy - ae.ey) + ABS(sp.sz - ae.ez) AS dist,
           ROW_NUMBER() OVER (
             PARTITION BY ae.aisle_num_id
             ORDER BY ABS(sp.sx - ae.ex) + ABS(sp.sy - ae.ey) + ABS(sp.sz - ae.ez)
           ) AS rn
    FROM aisle_entries ae
    CROSS JOIN station_pick sp
  ),
  nearest_entry_pick AS (
    SELECT aisle_num_id, entry_loc_id, dist
    FROM nearest_entry
    WHERE rn = 1
  ),

  /* actionable tasks only, and only live stations */
  task_positions AS (
    SELECT
      CAST(SUBSTRING(la.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lt.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      ob.STATION_ID
    FROM order_bin_task_master ob
    JOIN hw_station_master s
      ON s.STATION_ID = ob.STATION_ID
     AND UPPER(s.WAVE_STATUS) = 'WAVE_LIVE'
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
    WHERE la.AISLE_NUMBER IS NOT NULL
      AND lt.TOWER_NUMBER IS NOT NULL
  ),

  tower_task_base AS (
    SELECT
      aisle_num_id AS AISLE_ID,
      tower_num_id AS TOWER_ID,
      COUNT(*)                   AS tower_tasks,
      COUNT(DISTINCT STATION_ID) AS tower_station_div
    FROM task_positions
    GROUP BY aisle_num_id, tower_num_id
  ),
  tower_task_cum AS (
    SELECT AISLE_ID, TOWER_ID,
           SUM(tower_tasks) OVER (
             PARTITION BY AISLE_ID
             ORDER BY TOWER_ID
             ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
           ) AS aisle_future_tasks_from_here
    FROM tower_task_base
  ),

  aisle_station_max AS (
    SELECT aisle_num_id AS AISLE_ID, STATION_ID, MAX(tower_num_id) AS max_tower_id
    FROM task_positions
    GROUP BY aisle_num_id, STATION_ID
  ),
  asm_levels AS (
    SELECT AISLE_ID, max_tower_id AS lvl, COUNT(*) AS stations_at_lvl
    FROM aisle_station_max
    GROUP BY AISLE_ID, max_tower_id
  ),
  asm_cum AS (
    SELECT AISLE_ID, lvl,
           SUM(stations_at_lvl) OVER (
             PARTITION BY AISLE_ID
             ORDER BY lvl
             ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
           ) AS stations_ahead
    FROM asm_levels
  ),

  /* z-top only from storage-bin locations */
  tower_z_cap AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lm.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      MAX(COALESCE(lm.Z,0)) AS z_top
    FROM store_bin_master sb
    JOIN location_master lm ON lm.LOCATION_ID = sb.LOCATION_ID
    WHERE lm.AISLE_NUMBER IS NOT NULL
      AND lm.TOWER_NUMBER IS NOT NULL
    GROUP BY aisle_num_id, tower_num_id
  ),

  usable_locations AS (
    SELECT
      sb.LOCATION_ID,
      sb.BIN_ID,
      COALESCE(sb.AUDIT,0) AS audit,
      sb.COST,
      lm.AISLE_NUMBER,
      CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lm.TOWER_NUMBER,2) AS UNSIGNED) AS tower_num_id,
      COALESCE(lm.Z,0) AS z,
      tz.z_top,
      CASE WHEN COALESCE(lm.Z,0) = tz.z_top THEN 1 ELSE 0 END AS is_top_z
    FROM store_bin_master sb
    JOIN location_master lm ON lm.LOCATION_ID = sb.LOCATION_ID
    LEFT JOIN location_block_master lbm ON lbm.LOCATION_ID = sb.LOCATION_ID
    JOIN tower_z_cap tz
      ON tz.aisle_num_id = CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED)
     AND tz.tower_num_id = CAST(SUBSTRING(lm.TOWER_NUMBER,2) AS UNSIGNED)
    WHERE lbm.LOCATION_ID IS NULL
      AND COALESCE(sb.AUDIT,0) = 0
  ),

  tower_fill AS (
    SELECT
      aisle_num_id,
      tower_num_id,
      COUNT(*)                                             AS cap_usable,
      SUM(CASE WHEN BIN_ID IS NOT NULL THEN 1 ELSE 0 END) AS occ_usable,
      SUM(CASE WHEN BIN_ID IS NULL  THEN 1 ELSE 0 END)    AS emp_usable
    FROM usable_locations
    GROUP BY aisle_num_id, tower_num_id
  ),

  aisle_fill AS (
    SELECT
      aisle_num_id,
      SUM(cap_usable) AS aisle_cap_usable,
      SUM(occ_usable) AS aisle_occ_usable,
      SUM(emp_usable) AS aisle_emp_usable
    FROM tower_fill
    GROUP BY aisle_num_id
  ),

  /* ---- HARD RULE: tower must have >= 2 empty eligible slots ---- */
  eligible_towers AS (
    SELECT aisle_num_id, tower_num_id
    FROM tower_fill
    WHERE emp_usable >= 2
  ),

  /* ---- Pick ONE candidate per tower by MIN(COST) (NOT min(location_id)) ---- */
  min_cost_empty_location_per_tower AS (
    SELECT
      ul.*,
      ROW_NUMBER() OVER (
        PARTITION BY ul.aisle_num_id, ul.tower_num_id
        ORDER BY ul.COST ASC, ul.LOCATION_ID ASC   -- COST is the metric; LOCATION_ID only tie-break
      ) AS rn_cost
    FROM usable_locations ul
    JOIN eligible_towers et
      ON et.aisle_num_id = ul.aisle_num_id
     AND et.tower_num_id = ul.tower_num_id
    WHERE ul.BIN_ID IS NULL
  ),

  candidate_locations AS (
    SELECT *
    FROM min_cost_empty_location_per_tower
    WHERE rn_cost = 1
  ),

  cand_with_dist AS (
    SELECT
      cl.LOCATION_ID,
      cl.COST,
      cl.AISLE_NUMBER,
      cl.aisle_num_id,
      cl.tower_num_id,
      cl.z,
      cl.is_top_z,
      ne.entry_loc_id,
      ne.dist AS dist_to_aisle_entry
    FROM candidate_locations cl
    JOIN nearest_entry_pick ne
      ON ne.aisle_num_id = cl.aisle_num_id
  ),

  aisle_bot_load AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER,2) AS UNSIGNED) AS aisle_num_id,
      COUNT(DISTINCT crm.BOT_ID) AS bots_in_aisle
    FROM controller_reservations_master crm
    JOIN location_master lm ON lm.LOCATION_ID = crm.LOCATION_ID
    WHERE UPPER(crm.TYPE) = 'AISLE_ENTRY'
      AND lm.TYPE = 'AISLE_ENTRY'
      AND lm.AISLE_NUMBER IS NOT NULL
    GROUP BY aisle_num_id
  ),

  scored AS (
    SELECT
      c.LOCATION_ID,
      c.COST,
      c.AISLE_NUMBER,
      c.aisle_num_id,
      c.tower_num_id,
      c.z,
      c.is_top_z,
      c.entry_loc_id,
      c.dist_to_aisle_entry,

      COALESCE(ttb.tower_tasks, 0)        AS same_tower_tasks,
      COALESCE(ttc.aisle_future_tasks_from_here, 0) AS aisle_future_tasks,
      COALESCE(ac.stations_ahead, 0)      AS station_div_window,

      COALESCE(tf.emp_usable / NULLIF(tf.cap_usable,0), 0) AS tower_empty_ratio,
      COALESCE(af.aisle_emp_usable / NULLIF(af.aisle_cap_usable,0), 0) AS aisle_empty_ratio,

      COALESCE(abl.bots_in_aisle, 0)      AS bots_in_aisle,

      (
        w_future    * LOG(1 + COALESCE(ttc.aisle_future_tasks_from_here, 0))
      + w_div       * (COALESCE(ac.stations_ahead, 0) / v_n)
      + w_same      * COALESCE(ttb.tower_tasks, 0)
      + w_bal_tower * COALESCE(tf.emp_usable / NULLIF(tf.cap_usable,0), 0)
      + w_bal_aisle * COALESCE(af.aisle_emp_usable / NULLIF(af.aisle_cap_usable,0), 0)
      - w_dist      * c.dist_to_aisle_entry
      - w_depth     * GREATEST(c.tower_num_id - 1, 0)
      - w_bot_pen   * COALESCE(abl.bots_in_aisle, 0)
      - w_topz_pen  * c.is_top_z
      ) AS score
    FROM cand_with_dist c
    LEFT JOIN tower_task_base ttb
      ON ttb.AISLE_ID = c.aisle_num_id
     AND ttb.TOWER_ID = c.tower_num_id
    LEFT JOIN tower_task_cum ttc
      ON ttc.AISLE_ID = c.aisle_num_id
     AND ttc.TOWER_ID = c.tower_num_id
    LEFT JOIN asm_cum ac
      ON ac.AISLE_ID = c.aisle_num_id
     AND ac.lvl      = c.tower_num_id
    LEFT JOIN tower_fill tf
      ON tf.aisle_num_id = c.aisle_num_id
     AND tf.tower_num_id = c.tower_num_id
    LEFT JOIN aisle_fill af
      ON af.aisle_num_id = c.aisle_num_id
    LEFT JOIN aisle_bot_load abl
      ON abl.aisle_num_id = c.aisle_num_id
  )

  /* ---- Final: one location per tower; every returned tower had >=2 empties ---- */
  SELECT
    s.LOCATION_ID AS PUT_LOCATION_ID
  FROM scored s
  ORDER BY
    s.score DESC,
    s.bots_in_aisle ASC,
    s.COST ASC
  LIMIT v_n;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBestPutLocationsWithFutureTaskConsideringCluster` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBestPutLocationsWithFutureTaskConsideringCluster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectBestPutLocationsWithFutureTaskConsideringCluster`(
  IN p_station_id INT,
  IN p_subsequent_included TINYINT  -- 0 = same-tower only; 1 = same-tower + subsequent towers (NO previous)
)
BEGIN
  /***********************************************************************
    Goal (strict):
      - Return ONLY those rows where:
          PUT aisle == FUTURE pick-task aisle
      - Allow ONLY:
          * same tower (always)
          * subsequent towers (only if p_subsequent_included = 1)
        Never allow previous-tower tasks.
      - HARD guard rail:
          If a tower has ONLY 1 empty slot left, we will NOT use it
          unless the future task is SAME-TOWER.
  ***********************************************************************/

  /* Tunables */
  DECLARE w_dist     DOUBLE DEFAULT 1.00;   -- distance weight
  DECLARE w_bot_pen  DOUBLE DEFAULT 5.00;   -- crowd penalty only beyond cap
  DECLARE v_bot_cap  INT    DEFAULT 6;      -- allowed bots/aisle without penalty
  DECLARE v_top_k    INT    DEFAULT 5;      -- initial K aisles (ring 0)

  WITH
  /* 1) Station→aisle costs */
  sac_all AS (
    SELECT
      Station_ID,
      CAST(SUBSTRING(Aisle_Number, 2) AS UNSIGNED) AS aisle_num_id,
      MIN(Cost) AS Cost
    FROM station_to_aisle_cost
    GROUP BY Station_ID, aisle_num_id
  ),

  /* 2) Distance stats for current station */
  dist_stats AS (
    SELECT
      MIN(Cost) AS dmin,
      MAX(Cost) AS dmax
    FROM sac_all
    WHERE Station_ID = p_station_id
  ),

  /* 3) Aisle ranks for current station */
  sac_ranked AS (
    SELECT
      s.aisle_num_id,
      s.Cost,
      ROW_NUMBER() OVER (
        ORDER BY s.Cost ASC, s.aisle_num_id ASC
      ) AS aisle_rank
    FROM sac_all s
    WHERE s.Station_ID = p_station_id
  ),

  /* 4) Future tasks (pending only) */
  future_tasks AS (
    SELECT
      ob.ORDER_BIN_ID,
      ob.STATION_ID  AS future_station_id,

      la.LOCATION_ID AS future_aisle_loc_id,
      lt.LOCATION_ID AS future_tower_loc_id,

      la.AISLE_NUMBER AS task_aisle_str,
      lt.TOWER_NUMBER AS task_tower_str,

      CAST(SUBSTRING(la.AISLE_NUMBER, 2) AS UNSIGNED) AS task_aisle_id,
      CAST(CAST(SUBSTRING(lt.TOWER_NUMBER, 2) AS UNSIGNED) AS SIGNED) AS task_tower_id
    FROM order_bin_task_master ob
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
  ),

  /* 5) Best empty slot per (aisle,tower) + empty count per tower */
  best_slot_per_tower AS (
    SELECT
      aisle_num_id,
      tower_num_id,
      put_location_id,
      empty_slots_in_tower
    FROM (
      SELECT
        CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
        CAST(CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED) AS SIGNED) AS tower_num_id,
        sb.LOCATION_ID AS put_location_id,

        COUNT(*) OVER (
          PARTITION BY
            CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED),
            CAST(CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED) AS SIGNED)
        ) AS empty_slots_in_tower,

        ROW_NUMBER() OVER (
          PARTITION BY
            CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED),
            CAST(CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED) AS SIGNED)
          ORDER BY sb.COST ASC, sb.LOCATION_ID ASC
        ) AS rn
      FROM store_bin_master sb
      JOIN location_master lm
        ON lm.LOCATION_ID = sb.LOCATION_ID
      LEFT JOIN location_block_master lbm
        ON lbm.LOCATION_ID = sb.LOCATION_ID
      WHERE sb.BIN_ID IS NULL
        AND COALESCE(sb.AUDIT, 0) = 0
        AND lbm.LOCATION_ID IS NULL
    ) X
    WHERE x.rn = 1
  ),

  /* 6) Candidate towers */
  tower_candidates AS (
    SELECT
      aisle_num_id,
      tower_num_id,
      empty_slots_in_tower
    FROM best_slot_per_tower
  ),

  /* 7) Aisle crowd */
  aisle_bot_load AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
      COUNT(DISTINCT crm.BOT_ID) AS bots_in_aisle
    FROM controller_reservations_master crm
    JOIN location_master lm
      ON lm.LOCATION_ID = crm.LOCATION_ID
    WHERE UPPER(crm.TYPE) = 'AISLE_ENTRY'
      AND lm.TYPE = 'AISLE_ENTRY'
    GROUP BY aisle_num_id
  ),

  /* 8) Candidate base */
  cand_base AS (
    SELECT
      tc.aisle_num_id,
      tc.tower_num_id,
      tc.empty_slots_in_tower,

      COALESCE(sr.Cost, 999999) AS aisle_dist,
      CASE
        WHEN (ds.dmax - ds.dmin) = 0 THEN 0
        ELSE (COALESCE(sr.Cost, 999999) - ds.dmin) / (ds.dmax - ds.dmin)
      END AS dist_norm,

      COALESCE(abl.bots_in_aisle, 0) AS bots_in_aisle
    FROM tower_candidates tc
    LEFT JOIN sac_ranked sr
      ON sr.aisle_num_id = tc.aisle_num_id
    CROSS JOIN dist_stats ds
    LEFT JOIN aisle_bot_load abl
      ON abl.aisle_num_id = tc.aisle_num_id
  ),

  /* 9) Score */
  cand_scored AS (
    SELECT
      cb.*,
      ( w_dist * cb.dist_norm )
      + ( w_bot_pen * GREATEST(cb.bots_in_aisle - v_bot_cap, 0) ) AS score
    FROM cand_base cb
  ),

  /* 10) Rank puts */
  best_puts AS (
    SELECT
      cs.aisle_num_id,
      cs.tower_num_id,
      cs.empty_slots_in_tower,
      cs.dist_norm,
      cs.bots_in_aisle,
      cs.score,
      ROW_NUMBER() OVER (
        ORDER BY
          cs.score ASC,
          cs.dist_norm ASC,
          cs.aisle_num_id ASC,
          cs.tower_num_id ASC
      ) AS put_rank
    FROM cand_scored cs
  ),

  /* 11) Put + Task list (same aisle; same/subsequent tower only; HARD guard rail) */
  put_task_list AS (
    SELECT
      bp.aisle_num_id      AS put_aisle_id,
      bp.tower_num_id      AS put_tower_id,
      bp.put_rank,
      bp.empty_slots_in_tower,
      bp.score AS score,

      sr.aisle_rank,
      CASE
        WHEN sr.aisle_rank <= v_top_k THEN 0
        ELSE CEIL( (sr.aisle_rank - v_top_k) / 2.0 )
      END AS ring_idx,

      bp.dist_norm,

      ft.ORDER_BIN_ID,
      ft.future_station_id,
      ft.future_aisle_loc_id,
      ft.future_tower_loc_id,

      ft.task_aisle_id,
      ft.task_tower_id,

      CASE WHEN ft.task_tower_id = bp.tower_num_id THEN 0 ELSE 1 END AS not_same_tower,
      (ft.task_tower_id - bp.tower_num_id) AS tower_delta,

      /* kept for visibility/debugging (should always be 0 due to hard-guard) */
      CASE
        WHEN bp.empty_slots_in_tower <= 1 AND ft.task_tower_id <> bp.tower_num_id THEN 1
        ELSE 0
      END AS reserve_violation,

      COALESCE(sf.Cost, 999999) AS future_station_aisle_cost
    FROM best_puts bp
    JOIN sac_ranked sr
      ON sr.aisle_num_id = bp.aisle_num_id
    JOIN future_tasks ft
      ON ft.task_aisle_id = bp.aisle_num_id
     AND (
          (p_subsequent_included = 0 AND ft.task_tower_id = bp.tower_num_id)
       OR (p_subsequent_included = 1 AND ft.task_tower_id >= bp.tower_num_id)
         )
     /* ===================== HARD GUARD RAIL =====================
        If tower has only 1 empty slot left:
          allow ONLY same-tower future pick.
        i.e. for non-same-tower tasks, tower must have >= 2 empties.
     ============================================================ */
     AND (bp.empty_slots_in_tower > 1 OR ft.task_tower_id = bp.tower_num_id)

    LEFT JOIN sac_all sf
      ON sf.Station_ID   = ft.future_station_id
     AND sf.aisle_num_id = ft.task_aisle_id
  ),

  /* 12) One task per future station per put */
  put_task_per_station AS (
    SELECT *
    FROM (
      SELECT
        ptl.*,
        ROW_NUMBER() OVER (
          PARTITION BY ptl.put_aisle_id, ptl.put_tower_id, ptl.future_station_id
          ORDER BY
            ptl.not_same_tower ASC,
            ptl.tower_delta ASC,
            ptl.future_station_aisle_cost ASC,
            ptl.ORDER_BIN_ID
        ) AS rn_station
      FROM put_task_list ptl
    ) X
    WHERE x.rn_station = 1
  ),

  /* 13) Global ranking */
  final_ranked AS (
    SELECT
      pps.*,
      ROW_NUMBER() OVER (
        ORDER BY
          pps.not_same_tower ASC,

          /* if it's a subsequent-tower task, prefer towers with more empties */
          CASE WHEN pps.not_same_tower = 1 THEN pps.empty_slots_in_tower ELSE 999999 END DESC,

          pps.dist_norm ASC,
          pps.future_station_aisle_cost ASC,
          pps.ring_idx ASC,
          pps.aisle_rank ASC,
          pps.tower_delta ASC,
          pps.score ASC,
          pps.put_rank ASC,
          pps.put_aisle_id ASC,
          pps.put_tower_id ASC,
          pps.ORDER_BIN_ID ASC
      ) AS global_rn
    FROM put_task_per_station pps
  ),

  /* 14) Cap per future station */
  limited_per_station AS (
    SELECT *
    FROM (
      SELECT
        fr.*,
        ROW_NUMBER() OVER (
          PARTITION BY fr.future_station_id
          ORDER BY fr.global_rn
        ) AS rn_per_station
      FROM final_ranked fr
    ) X
    WHERE x.rn_per_station <= 10
  )

  /* 15) Output: strict same-aisle */
  SELECT
    bst.put_location_id,
    lm_put.AISLE_NUMBER      AS put_aisle_number,
    lm_put.TOWER_NUMBER      AS put_tower_number,

    lps.ORDER_BIN_ID         AS future_order_bin_id,
    lm_ft_aisle.AISLE_NUMBER AS future_order_aisle_number,
    lm_ft_tower.TOWER_NUMBER AS future_pick_tower_number,
    lps.future_station_id    AS future_order_station_id
  FROM limited_per_station lps
  JOIN best_slot_per_tower bst
    ON bst.aisle_num_id = lps.put_aisle_id
   AND bst.tower_num_id = lps.put_tower_id
  JOIN location_master lm_put
    ON lm_put.LOCATION_ID = bst.put_location_id
  JOIN location_master lm_ft_aisle
    ON lm_ft_aisle.LOCATION_ID = lps.future_aisle_loc_id
  JOIN location_master lm_ft_tower
    ON lm_ft_tower.LOCATION_ID = lps.future_tower_loc_id
  WHERE lm_put.AISLE_NUMBER = lm_ft_aisle.AISLE_NUMBER
  ORDER BY lps.global_rn;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBestPutLocationsWithFutureTaskConsideringCluster2` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBestPutLocationsWithFutureTaskConsideringCluster2` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectBestPutLocationsWithFutureTaskConsideringCluster2`(
  IN p_station_id INT,
  IN p_subsequent_included TINYINT  
)
BEGIN
  

  
  DECLARE w_dist     DOUBLE DEFAULT 1.00;   
  DECLARE w_bot_pen  DOUBLE DEFAULT 5.00;   
  DECLARE v_bot_cap  INT    DEFAULT 6;      
  DECLARE v_top_k    INT    DEFAULT 5;      

  WITH
  
  sac_all AS (
    SELECT
      Station_ID,
      CAST(SUBSTRING(Aisle_Number, 2) AS UNSIGNED) AS aisle_num_id,
      MIN(Cost) AS Cost
    FROM station_to_aisle_cost
    GROUP BY Station_ID, aisle_num_id
  ),

  
  dist_stats AS (
    SELECT
      MIN(Cost) AS dmin,
      MAX(Cost) AS dmax
    FROM sac_all
    WHERE Station_ID = p_station_id
  ),

  
  sac_ranked AS (
    SELECT
      s.aisle_num_id,
      s.Cost,
      ROW_NUMBER() OVER (
        ORDER BY s.Cost ASC, s.aisle_num_id ASC
      ) AS aisle_rank
    FROM sac_all s
    WHERE s.Station_ID = p_station_id
  ),

  
  future_tasks AS (
    SELECT
      ob.ORDER_BIN_ID,
      ob.STATION_ID  AS future_station_id,

      la.LOCATION_ID AS future_aisle_loc_id,
      lt.LOCATION_ID AS future_tower_loc_id,

      la.AISLE_NUMBER AS task_aisle_str,
      lt.TOWER_NUMBER AS task_tower_str,

      CAST(SUBSTRING(la.AISLE_NUMBER, 2) AS UNSIGNED) AS task_aisle_id,
      CAST(CAST(SUBSTRING(lt.TOWER_NUMBER, 2) AS UNSIGNED) AS SIGNED) AS task_tower_id
    FROM order_bin_task_master ob
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
  ),

  
  best_slot_per_tower AS (
    SELECT
      aisle_num_id,
      tower_num_id,
      put_location_id
    FROM (
      SELECT
        CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
        CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED) AS tower_num_id,
        sb.LOCATION_ID AS put_location_id,
        ROW_NUMBER() OVER (
          PARTITION BY
            CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED),
            CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED)
          ORDER BY sb.COST ASC, sb.LOCATION_ID ASC
        ) AS rn
      FROM store_bin_master sb
      JOIN location_master lm
        ON lm.LOCATION_ID = sb.LOCATION_ID
      LEFT JOIN location_block_master lbm
        ON lbm.LOCATION_ID = sb.LOCATION_ID
      WHERE sb.BIN_ID IS NULL
        AND COALESCE(sb.AUDIT, 0) = 0
        AND lbm.LOCATION_ID IS NULL
    ) X
    WHERE x.rn = 1
  ),

  
  tower_candidates AS (
    SELECT aisle_num_id, tower_num_id
    FROM best_slot_per_tower
  ),

  
  aisle_bot_load AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
      COUNT(DISTINCT crm.BOT_ID) AS bots_in_aisle
    FROM controller_reservations_master crm
    JOIN location_master lm
      ON lm.LOCATION_ID = crm.LOCATION_ID
    WHERE UPPER(crm.TYPE) = 'AISLE_ENTRY'
      AND lm.TYPE = 'AISLE_ENTRY'
    GROUP BY aisle_num_id
  ),

  
  cand_base AS (
    SELECT
      tc.aisle_num_id,
      tc.tower_num_id,
      COALESCE(sr.Cost, 999999) AS aisle_dist,
      CASE
        WHEN (ds.dmax - ds.dmin) = 0 THEN 0
        ELSE (COALESCE(sr.Cost, 999999) - ds.dmin) / (ds.dmax - ds.dmin)
      END AS dist_norm,
      COALESCE(abl.bots_in_aisle, 0) AS bots_in_aisle
    FROM tower_candidates tc
    LEFT JOIN sac_ranked sr
      ON sr.aisle_num_id = tc.aisle_num_id
    CROSS JOIN dist_stats ds
    LEFT JOIN aisle_bot_load abl
      ON abl.aisle_num_id = tc.aisle_num_id
  ),

  
  cand_scored AS (
    SELECT
      cb.*,
      ( w_dist * cb.dist_norm )
      + ( w_bot_pen * GREATEST(cb.bots_in_aisle - v_bot_cap, 0) ) AS score
    FROM cand_base cb
  ),

  
  best_puts AS (
    SELECT
      cs.aisle_num_id,
      cs.tower_num_id,
      cs.dist_norm,
      cs.bots_in_aisle,
      cs.score,
      ROW_NUMBER() OVER (
        ORDER BY
          cs.score ASC,
          cs.dist_norm ASC,
          cs.aisle_num_id ASC,
          cs.tower_num_id ASC
      ) AS put_rank
    FROM cand_scored cs
  ),

  
  put_task_list AS (
    SELECT
      bp.aisle_num_id      AS put_aisle_id,
      bp.tower_num_id      AS put_tower_id,
      bp.put_rank,
      sr.aisle_rank,
      CASE
        WHEN sr.aisle_rank <= v_top_k THEN 0
        ELSE CEIL( (sr.aisle_rank - v_top_k) / 2.0 )
      END AS ring_idx,
      bp.dist_norm,

      ft.ORDER_BIN_ID,
      ft.future_station_id,
      ft.future_aisle_loc_id,
      ft.future_tower_loc_id,

      ft.task_aisle_id,
      ft.task_tower_id,

      
      CASE WHEN ft.task_tower_id = CAST(bp.tower_num_id AS SIGNED) THEN 0 ELSE 1 END AS not_same_tower,
      (ft.task_tower_id - CAST(bp.tower_num_id AS SIGNED)) AS tower_delta,

      
      COALESCE(sf.Cost, 999999) AS future_station_aisle_cost
    FROM best_puts bp
    JOIN sac_ranked sr
      ON sr.aisle_num_id = bp.aisle_num_id
    JOIN future_tasks ft
      ON ft.task_aisle_id = bp.aisle_num_id
     AND (
          (p_subsequent_included = 0 AND ft.task_tower_id = CAST(bp.tower_num_id AS SIGNED))
       OR (p_subsequent_included = 1 AND ft.task_tower_id >= CAST(bp.tower_num_id AS SIGNED))
         )
    LEFT JOIN sac_all sf
      ON sf.Station_ID   = ft.future_station_id
     AND sf.aisle_num_id = ft.task_aisle_id
  ),

  
  put_task_per_station AS (
    SELECT *
    FROM (
      SELECT
        ptl.*,
        ROW_NUMBER() OVER (
          PARTITION BY ptl.put_aisle_id, ptl.put_tower_id, ptl.future_station_id
          ORDER BY
            ptl.not_same_tower ASC,
            ptl.future_station_aisle_cost ASC,
            ptl.tower_delta ASC,
            ptl.ORDER_BIN_ID
        ) AS rn_station
      FROM put_task_list ptl
    ) X
    WHERE x.rn_station = 1
  ),

  
  final_ranked AS (
    SELECT
      pps.*,
      ROW_NUMBER() OVER (
        ORDER BY
          pps.not_same_tower ASC,
          pps.dist_norm ASC,
          pps.future_station_aisle_cost ASC,
          pps.ring_idx ASC,
          pps.aisle_rank ASC,
          pps.tower_delta ASC,
          pps.put_rank ASC,
          pps.put_aisle_id ASC,
          pps.put_tower_id ASC,
          pps.ORDER_BIN_ID
      ) AS global_rn
    FROM put_task_per_station pps
  ),

  
  limited_per_station AS (
    SELECT *
    FROM (
      SELECT
        fr.*,
        ROW_NUMBER() OVER (
          PARTITION BY fr.future_station_id
          ORDER BY fr.global_rn
        ) AS rn_per_station
      FROM final_ranked fr
    ) X
    WHERE x.rn_per_station <= 10
  )

  
  SELECT
    bst.put_location_id,
    lm_put.AISLE_NUMBER      AS put_aisle_number,
    lm_put.TOWER_NUMBER      AS put_tower_number,

    lps.ORDER_BIN_ID         AS future_order_bin_id,
    lm_ft_aisle.AISLE_NUMBER AS future_order_aisle_number,
    lm_ft_tower.TOWER_NUMBER AS future_pick_tower_number,
    lps.future_station_id    AS future_order_station_id
  FROM limited_per_station lps
  JOIN best_slot_per_tower bst
    ON bst.aisle_num_id = lps.put_aisle_id
   AND bst.tower_num_id = lps.put_tower_id
  JOIN location_master lm_put
    ON lm_put.LOCATION_ID = bst.put_location_id
  JOIN location_master lm_ft_aisle
    ON lm_ft_aisle.LOCATION_ID = lps.future_aisle_loc_id
  JOIN location_master lm_ft_tower
    ON lm_ft_tower.LOCATION_ID = lps.future_tower_loc_id

  
  WHERE lm_put.AISLE_NUMBER = lm_ft_aisle.AISLE_NUMBER

  ORDER BY lps.global_rn;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBestPutLocationsWithFutureTaskConsideringCluster_backup` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBestPutLocationsWithFutureTaskConsideringCluster_backup` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectBestPutLocationsWithFutureTaskConsideringCluster_backup`(
  IN p_station_id INT,
  IN p_subsequent_included TINYINT  
)
BEGIN
  

  
  DECLARE w_dist     DOUBLE DEFAULT 1.00;   
  DECLARE w_bot_pen  DOUBLE DEFAULT 5.00;   
  DECLARE v_bot_cap  INT    DEFAULT 6;      
  DECLARE v_top_k    INT    DEFAULT 5;      

  WITH
  
  sac_all AS (
    SELECT
      Station_ID,
      CAST(SUBSTRING(Aisle_Number, 2) AS UNSIGNED) AS aisle_num_id,
      MIN(Cost) AS Cost
    FROM station_to_aisle_cost
    GROUP BY Station_ID, aisle_num_id
  ),

  
  dist_stats AS (
    SELECT
      MIN(Cost) AS dmin,
      MAX(Cost) AS dmax
    FROM sac_all
    WHERE Station_ID = p_station_id
  ),

  
  sac_ranked AS (
    SELECT
      s.aisle_num_id,
      s.Cost,
      ROW_NUMBER() OVER (
        ORDER BY s.Cost ASC, s.aisle_num_id ASC
      ) AS aisle_rank
    FROM sac_all s
    WHERE s.Station_ID = p_station_id
  ),

  
  future_tasks AS (
    SELECT
      ob.ORDER_BIN_ID,
      ob.STATION_ID  AS future_station_id,
      la.LOCATION_ID AS future_aisle_loc_id,
      lt.LOCATION_ID AS future_tower_loc_id,
      CAST(SUBSTRING(la.AISLE_NUMBER, 2) AS UNSIGNED) AS task_aisle_id,
      CAST(SUBSTRING(lt.TOWER_NUMBER, 2) AS UNSIGNED) AS task_tower_id
    FROM order_bin_task_master ob
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
  ),

  
  best_slot_per_tower AS (
    SELECT
      aisle_num_id,
      tower_num_id,
      location_id AS put_location_id
    FROM (
      SELECT
        CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
        CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED) AS tower_num_id,
        sb.LOCATION_ID AS location_id,
        ROW_NUMBER() OVER (
          PARTITION BY
            CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED),
            CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED)
          ORDER BY sb.COST ASC, sb.LOCATION_ID ASC
        ) AS rn
      FROM store_bin_master sb
      JOIN location_master lm
        ON lm.LOCATION_ID = sb.LOCATION_ID
      LEFT JOIN location_block_master lbm
        ON lbm.LOCATION_ID = sb.LOCATION_ID
      WHERE sb.BIN_ID IS NULL
        AND COALESCE(sb.AUDIT, 0) = 0
        AND lbm.LOCATION_ID IS NULL
    ) x
    WHERE x.rn = 1
  ),

  
  tower_candidates AS (
    SELECT aisle_num_id, tower_num_id
    FROM best_slot_per_tower
  ),

  
  aisle_bot_load AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
      COUNT(DISTINCT crm.BOT_ID) AS bots_in_aisle
    FROM controller_reservations_master crm
    JOIN location_master lm
      ON lm.LOCATION_ID = crm.LOCATION_ID
    WHERE UPPER(crm.TYPE) = 'AISLE_ENTRY'
      AND lm.TYPE = 'AISLE_ENTRY'
    GROUP BY aisle_num_id
  ),

  
  cand_base AS (
    SELECT
      tc.aisle_num_id,
      tc.tower_num_id,
      COALESCE(sr.Cost, 999999) AS aisle_dist,
      CASE
        WHEN (ds.dmax - ds.dmin) = 0 THEN 0
        ELSE (COALESCE(sr.Cost, 999999) - ds.dmin) / (ds.dmax - ds.dmin)
      END AS dist_norm,
      COALESCE(abl.bots_in_aisle, 0) AS bots_in_aisle
    FROM tower_candidates tc
    LEFT JOIN sac_ranked sr
      ON sr.aisle_num_id = tc.aisle_num_id
    CROSS JOIN dist_stats ds
    LEFT JOIN aisle_bot_load abl
      ON abl.aisle_num_id = tc.aisle_num_id
  ),

  
  cand_scored AS (
    SELECT
      cb.*,
      ( w_dist * cb.dist_norm )
      + ( w_bot_pen * GREATEST(cb.bots_in_aisle - v_bot_cap, 0) ) AS score
    FROM cand_base cb
  ),

  
  best_puts AS (
    SELECT
      cs.aisle_num_id,
      cs.tower_num_id,
      cs.dist_norm,
      cs.bots_in_aisle,
      cs.score,
      ROW_NUMBER() OVER (
        ORDER BY
          cs.score ASC,
          cs.dist_norm ASC,
          cs.aisle_num_id ASC,
          cs.tower_num_id ASC
      ) AS put_rank
    FROM cand_scored cs
  ),

  
  put_task_list AS (
    SELECT
      bp.aisle_num_id      AS put_aisle_id,
      bp.tower_num_id      AS put_tower_id,
      bp.put_rank,
      sr.aisle_rank,
      CASE
        WHEN sr.aisle_rank <= v_top_k THEN 0
        ELSE CEIL( (sr.aisle_rank - v_top_k) / 2.0 )
      END AS ring_idx,
      bp.dist_norm,
      ft.ORDER_BIN_ID,
      ft.future_station_id,
      ft.future_aisle_loc_id,
      ft.future_tower_loc_id,
      ft.task_tower_id,
      CASE WHEN ft.task_tower_id = bp.tower_num_id THEN 0 ELSE 1 END AS not_same_tower,
      (ft.task_tower_id - bp.tower_num_id) AS tower_delta,
      COALESCE(sf.Cost, 999999) AS future_station_aisle_cost
    FROM best_puts bp
    JOIN sac_ranked sr
      ON sr.aisle_num_id = bp.aisle_num_id
    JOIN future_tasks ft
      ON ft.task_aisle_id = bp.aisle_num_id
     AND (
          (p_subsequent_included = 0 AND ft.task_tower_id = bp.tower_num_id)
       OR (p_subsequent_included = 1 AND ft.task_tower_id >= bp.tower_num_id)
         )
    LEFT JOIN sac_all sf
      ON sf.Station_ID   = ft.future_station_id
     AND sf.aisle_num_id = ft.task_aisle_id
  ),

  
  put_task_per_station AS (
    SELECT
      x.put_aisle_id,
      x.put_tower_id,
      x.put_rank,
      x.aisle_rank,
      x.ring_idx,
      x.dist_norm,
      x.ORDER_BIN_ID,
      x.future_station_id,
      x.future_aisle_loc_id,
      x.future_tower_loc_id,
      x.task_tower_id,
      x.not_same_tower,
      x.tower_delta,
      x.future_station_aisle_cost
    FROM (
      SELECT
        ptl.*,
        ROW_NUMBER() OVER (
          PARTITION BY ptl.put_aisle_id, ptl.put_tower_id, ptl.future_station_id
          ORDER BY
            ptl.not_same_tower ASC,
            ptl.future_station_aisle_cost ASC,
            ptl.tower_delta ASC,
            ptl.ORDER_BIN_ID
        ) AS rn_station
      FROM put_task_list ptl
    ) x
    WHERE x.rn_station = 1
  ),

  
  per_put_ordered AS (
    SELECT
      pps.*,
      ROW_NUMBER() OVER (
        PARTITION BY pps.put_aisle_id, pps.put_tower_id
        ORDER BY
          pps.not_same_tower ASC,
          pps.future_station_aisle_cost ASC,
          pps.tower_delta ASC,
          pps.aisle_rank ASC,
          pps.ORDER_BIN_ID
      ) AS per_put_rn
    FROM put_task_per_station pps
  ),

  
  final_ranked AS (
    SELECT
      ppo.*,
      ROW_NUMBER() OVER (
        ORDER BY
          ppo.not_same_tower ASC,
          ppo.dist_norm ASC,
          ppo.future_station_aisle_cost ASC,
          ppo.ring_idx ASC,
          ppo.aisle_rank ASC,
          ppo.tower_delta ASC,
          ppo.put_rank ASC,
          ppo.put_aisle_id ASC,
          ppo.put_tower_id ASC,
          ppo.ORDER_BIN_ID
      ) AS global_rn
    FROM per_put_ordered ppo
  ),

  
  limited_per_station AS (
    SELECT *
    FROM (
      SELECT
        fr.*,
        ROW_NUMBER() OVER (
          PARTITION BY fr.future_station_id
          ORDER BY fr.global_rn
        ) AS rn_per_station
      FROM final_ranked fr
    ) x
    WHERE x.rn_per_station <= 10
  )

  
  SELECT
    bst.put_location_id,
    lm_put.AISLE_NUMBER      AS put_aisle_number,
    lm_put.TOWER_NUMBER      AS put_tower_number,
    lps.ORDER_BIN_ID         AS future_order_bin_id,
    lm_ft_aisle.AISLE_NUMBER AS future_order_aisle_number,
    lm_ft_tower.TOWER_NUMBER AS future_pick_tower_number,
    lps.future_station_id    AS future_order_station_id
  FROM limited_per_station lps
  JOIN best_slot_per_tower bst
    ON bst.aisle_num_id = lps.put_aisle_id
   AND bst.tower_num_id = lps.put_tower_id
  JOIN location_master lm_put
    ON lm_put.LOCATION_ID = bst.put_location_id
  JOIN location_master lm_ft_aisle
    ON lm_ft_aisle.LOCATION_ID = lps.future_aisle_loc_id
  JOIN location_master lm_ft_tower
    ON lm_ft_tower.LOCATION_ID = lps.future_tower_loc_id
  ORDER BY lps.global_rn;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBestPutLocationsWithFutureTaskForStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBestPutLocationsWithFutureTaskForStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectBestPutLocationsWithFutureTaskForStation`(
  IN p_station_id INT,
  IN p_subsequent_included TINYINT  -- 0 = same-tower only; 1 = same-tower + subsequent towers
)
BEGIN
  /***********************************************************************
    Goal:
      - Remove LOCATION_ID from *all* decision-making (ranking/partitioning).
      - Rank put candidates purely by (aisle,tower) using the same logic:
          * dist_norm from station_to_aisle_cost (current station)
          * aisle crowd penalty beyond cap
      - After selecting a (aisle,tower), map to a real empty LOCATION_ID:
          pick the empty slot with LOWEST store_bin_master.COST
          (tie-breaker: lowest LOCATION_ID) -- only for execution handle/output.
  ***********************************************************************/

  /* Tunables */
  DECLARE w_dist     DOUBLE DEFAULT 1.00;   -- distance weight
  DECLARE w_bot_pen  DOUBLE DEFAULT 5.00;   -- crowd penalty only beyond cap
  DECLARE v_bot_cap  INT    DEFAULT 4;      -- allowed bots/aisle without penalty
  DECLARE v_top_k    INT    DEFAULT 5;      -- initial K aisles (ring 0)

  WITH
  /* Station→aisle costs (for BOTH current and future stations) */
  sac_all AS (
    SELECT
      Station_ID,
      CAST(SUBSTRING(Aisle_Number, 2) AS UNSIGNED) AS aisle_num_id,
      MIN(Cost) AS Cost
    FROM station_to_aisle_cost
    GROUP BY Station_ID, aisle_num_id
  ),

  /* Distance stats for current station */
  dist_stats AS (
    SELECT
      MIN(Cost) AS dmin,
      MAX(Cost) AS dmax
    FROM sac_all
    WHERE Station_ID = p_station_id
  ),

  /* Aisle ranks for current station (for ring logic) */
  sac_ranked AS (
    SELECT
      s.aisle_num_id,
      s.Cost,
      ROW_NUMBER() OVER (
        ORDER BY s.Cost ASC, s.aisle_num_id ASC
      ) AS aisle_rank
    FROM sac_all s
    WHERE s.Station_ID = p_station_id
  ),

  /* Future tasks: keep the chosen task's LOCATION_IDs as well */
  future_tasks AS (
    SELECT
      ob.ORDER_BIN_ID,
      ob.STATION_ID  AS future_station_id,
      la.LOCATION_ID AS future_aisle_loc_id,
      lt.LOCATION_ID AS future_tower_loc_id,
      CAST(SUBSTRING(la.AISLE_NUMBER, 2) AS UNSIGNED) AS task_aisle_id,
      CAST(SUBSTRING(lt.TOWER_NUMBER, 2) AS UNSIGNED) AS task_tower_id
    FROM order_bin_task_master ob
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
  ),

  /* Best empty slot per (aisle,tower): lowest sb.COST, tie lowest LOCATION_ID
     NOTE: LOCATION_ID here is *only* the execution handle / output mapping,
           NOT used for ranking (aisle,tower) candidates. */
  best_slot_per_tower AS (
    SELECT
      aisle_num_id,
      tower_num_id,
      location_id AS put_location_id
    FROM (
      SELECT
        CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
        CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED) AS tower_num_id,
        sb.LOCATION_ID AS location_id,
        ROW_NUMBER() OVER (
          PARTITION BY
            CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED),
            CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED)
          ORDER BY sb.COST ASC, sb.LOCATION_ID ASC
        ) AS rn
      FROM store_bin_master sb
      JOIN location_master lm
        ON lm.LOCATION_ID = sb.LOCATION_ID
      LEFT JOIN location_block_master lbm
        ON lbm.LOCATION_ID = sb.LOCATION_ID
      WHERE sb.BIN_ID IS NULL
        AND COALESCE(sb.AUDIT, 0) = 0
        AND lbm.LOCATION_ID IS NULL
    ) x
    WHERE x.rn = 1
  ),

  /* Candidate set: one row per (aisle,tower) that has at least 1 empty slot */
  tower_candidates AS (
    SELECT aisle_num_id, tower_num_id
    FROM best_slot_per_tower
  ),

  /* Current aisle crowd */
  aisle_bot_load AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
      COUNT(DISTINCT crm.BOT_ID) AS bots_in_aisle
    FROM controller_reservations_master crm
    JOIN location_master lm
      ON lm.LOCATION_ID = crm.LOCATION_ID
    WHERE UPPER(crm.TYPE) = 'AISLE_ENTRY'
      AND lm.TYPE = 'AISLE_ENTRY'
    GROUP BY aisle_num_id
  ),

  /* Candidate (aisle,tower) with normalized distance + crowd (NO LOCATION_ID) */
  cand_base AS (
    SELECT
      tc.aisle_num_id,
      tc.tower_num_id,
      COALESCE(sr.Cost, 999999) AS aisle_dist,
      CASE
        WHEN (ds.dmax - ds.dmin) = 0 THEN 0
        ELSE (COALESCE(sr.Cost, 999999) - ds.dmin) / (ds.dmax - ds.dmin)
      END AS dist_norm,
      COALESCE(abl.bots_in_aisle, 0) AS bots_in_aisle
    FROM tower_candidates tc
    LEFT JOIN sac_ranked sr
      ON sr.aisle_num_id = tc.aisle_num_id
    CROSS JOIN dist_stats ds
    LEFT JOIN aisle_bot_load abl
      ON abl.aisle_num_id = tc.aisle_num_id
  ),

  /* Distance-first scoring, penalize crowd > cap */
  cand_scored AS (
    SELECT
      cb.*,
      ( w_dist * cb.dist_norm )
      + ( w_bot_pen * GREATEST(cb.bots_in_aisle - v_bot_cap, 0) ) AS score
    FROM cand_base cb
  ),

  /* Rank puts – tie-break by aisle,tower (NOT location_id) */
  best_puts AS (
    SELECT
      cs.aisle_num_id,
      cs.tower_num_id,
      cs.dist_norm,
      cs.bots_in_aisle,
      cs.score,
      ROW_NUMBER() OVER (
        ORDER BY
          cs.score ASC,
          cs.dist_norm ASC,
          cs.aisle_num_id ASC,
          cs.tower_num_id ASC
      ) AS put_rank
    FROM cand_scored cs
  ),

  /* Build put+task list – only rows that ACTUALLY have future tasks */
  put_task_list AS (
    SELECT
      bp.aisle_num_id      AS put_aisle_id,
      bp.tower_num_id      AS put_tower_id,
      bp.put_rank,
      sr.aisle_rank,
      CASE
        WHEN sr.aisle_rank <= v_top_k THEN 0
        ELSE CEIL( (sr.aisle_rank - v_top_k) / 2.0 )
      END AS ring_idx,
      bp.dist_norm,
      ft.ORDER_BIN_ID,
      ft.future_station_id,
      ft.future_aisle_loc_id,
      ft.future_tower_loc_id,
      ft.task_tower_id,
      CASE WHEN ft.task_tower_id = bp.tower_num_id THEN 0 ELSE 1 END AS not_same_tower,
      (ft.task_tower_id - bp.tower_num_id) AS tower_delta,
      COALESCE(sf.Cost, 999999) AS future_station_aisle_cost
    FROM best_puts bp
    JOIN sac_ranked sr
      ON sr.aisle_num_id = bp.aisle_num_id
    JOIN future_tasks ft
      ON ft.task_aisle_id = bp.aisle_num_id
     AND (
          (p_subsequent_included = 0 AND ft.task_tower_id = bp.tower_num_id)
       OR (p_subsequent_included = 1 AND ft.task_tower_id >= bp.tower_num_id)
         )
    LEFT JOIN sac_all sf
      ON sf.Station_ID   = ft.future_station_id
     AND sf.aisle_num_id = ft.task_aisle_id
  ),

  /* One task per future station per put (aisle,tower) */
  put_task_per_station AS (
    SELECT
      x.put_aisle_id,
      x.put_tower_id,
      x.put_rank,
      x.aisle_rank,
      x.ring_idx,
      x.dist_norm,
      x.ORDER_BIN_ID,
      x.future_station_id,
      x.future_aisle_loc_id,
      x.future_tower_loc_id,
      x.task_tower_id,
      x.not_same_tower,
      x.tower_delta,
      x.future_station_aisle_cost
    FROM (
      SELECT
        ptl.*,
        ROW_NUMBER() OVER (
          PARTITION BY ptl.put_aisle_id, ptl.put_tower_id, ptl.future_station_id
          ORDER BY
            ptl.not_same_tower ASC,
            ptl.future_station_aisle_cost ASC,
            ptl.tower_delta ASC,
            ptl.ORDER_BIN_ID
        ) AS rn_station
      FROM put_task_list ptl
    ) x
    WHERE x.rn_station = 1
  ),

  /* Order tasks within each put (aisle,tower) */
  per_put_ordered AS (
    SELECT
      pps.*,
      ROW_NUMBER() OVER (
        PARTITION BY pps.put_aisle_id, pps.put_tower_id
        ORDER BY
          pps.not_same_tower ASC,
          pps.future_station_aisle_cost ASC,
          pps.tower_delta ASC,
          pps.aisle_rank ASC,
          pps.ORDER_BIN_ID
      ) AS per_put_rn
    FROM put_task_per_station pps
  ),

  /* Global ranking: same tower → closer to CURRENT station → better for FUTURE station */
  final_ranked AS (
    SELECT
      ppo.*,
      ROW_NUMBER() OVER (
        ORDER BY
          ppo.not_same_tower ASC,
          ppo.dist_norm ASC,
          ppo.future_station_aisle_cost ASC,
          ppo.ring_idx ASC,
          ppo.aisle_rank ASC,
          ppo.tower_delta ASC,
          ppo.put_rank ASC,
          ppo.put_aisle_id ASC,
          ppo.put_tower_id ASC,
          ppo.ORDER_BIN_ID
      ) AS global_rn
    FROM per_put_ordered ppo
  ),

  /* At most 2 tasks per future station (strict cap) */
  limited_per_station AS (
    SELECT *
    FROM (
      SELECT
        fr.*,
        ROW_NUMBER() OVER (
          PARTITION BY fr.future_station_id
          ORDER BY fr.global_rn
        ) AS rn_per_station
      FROM final_ranked fr
    ) x
    WHERE x.rn_per_station <= 2
  )

  /* Output: map chosen (aisle,tower) -> best empty LOCATION_ID (lowest COST) */
  SELECT
    bst.put_location_id,
    lm_put.AISLE_NUMBER      AS put_aisle_number,
    lm_put.TOWER_NUMBER      AS put_tower_number,
    lps.ORDER_BIN_ID         AS future_order_bin_id,
    lm_ft_aisle.AISLE_NUMBER AS future_order_aisle_number,
    lm_ft_tower.TOWER_NUMBER AS future_pick_tower_number,
    lps.future_station_id    AS future_order_station_id
  FROM limited_per_station lps
  JOIN best_slot_per_tower bst
    ON bst.aisle_num_id = lps.put_aisle_id
   AND bst.tower_num_id = lps.put_tower_id
  JOIN location_master lm_put
    ON lm_put.LOCATION_ID = bst.put_location_id
  JOIN location_master lm_ft_aisle
    ON lm_ft_aisle.LOCATION_ID = lps.future_aisle_loc_id
  JOIN location_master lm_ft_tower
    ON lm_ft_tower.LOCATION_ID = lps.future_tower_loc_id
  ORDER BY lps.global_rn;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBestPutLocationsWithFutureTaskForStation_backup` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBestPutLocationsWithFutureTaskForStation_backup` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectBestPutLocationsWithFutureTaskForStation_backup`(
  IN p_station_id INT,
  IN p_subsequent_included TINYINT  
)
BEGIN
  
  DECLARE w_dist     DOUBLE DEFAULT 1.00;   
  DECLARE w_bot_pen  DOUBLE DEFAULT 5.00;   
  DECLARE v_bot_cap  INT    DEFAULT 4;      
  DECLARE v_top_k    INT    DEFAULT 5;      

  WITH
  
  sac_all AS (
    SELECT
      Station_ID,
      CAST(SUBSTRING(Aisle_Number, 2) AS UNSIGNED) AS aisle_num_id,
      MIN(Cost) AS Cost
    FROM station_to_aisle_cost
    GROUP BY Station_ID, aisle_num_id
  ),

  
  dist_stats AS (
    SELECT
      MIN(Cost) AS dmin,
      MAX(Cost) AS dmax
    FROM sac_all
    WHERE Station_ID = p_station_id
  ),

  
  sac_ranked AS (
    SELECT
      s.aisle_num_id,
      s.Cost,
      ROW_NUMBER() OVER (
        ORDER BY s.Cost ASC, s.aisle_num_id ASC
      ) AS aisle_rank
    FROM sac_all s
    WHERE s.Station_ID = p_station_id
  ),

  
  future_tasks AS (
    SELECT
      ob.ORDER_BIN_ID,
      ob.STATION_ID  AS future_station_id,
      la.LOCATION_ID AS future_aisle_loc_id,
      lt.LOCATION_ID AS future_tower_loc_id,
      CAST(SUBSTRING(la.AISLE_NUMBER, 2) AS UNSIGNED) AS task_aisle_id,
      CAST(SUBSTRING(lt.TOWER_NUMBER, 2) AS UNSIGNED) AS task_tower_id
    FROM order_bin_task_master ob
    JOIN location_master la ON la.LOCATION_ID = ob.AISLE_ID
    JOIN location_master lt ON lt.LOCATION_ID = ob.TOWER_ID
  ),

  
  slots_empty AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
      CAST(SUBSTRING(lm.TOWER_NUMBER, 2) AS UNSIGNED) AS tower_num_id,
      MIN(sb.COST)        AS tower_cost,
      MIN(sb.LOCATION_ID) AS sample_location_id
    FROM store_bin_master sb
    JOIN location_master lm
      ON lm.LOCATION_ID = sb.LOCATION_ID
    LEFT JOIN location_block_master lbm
      ON lbm.LOCATION_ID = sb.LOCATION_ID
    WHERE sb.BIN_ID IS NULL
      AND COALESCE(sb.AUDIT, 0) = 0
      AND lbm.LOCATION_ID IS NULL
    GROUP BY aisle_num_id, tower_num_id
  ),

  
  aisle_bot_load AS (
    SELECT
      CAST(SUBSTRING(lm.AISLE_NUMBER, 2) AS UNSIGNED) AS aisle_num_id,
      COUNT(DISTINCT crm.BOT_ID) AS bots_in_aisle
    FROM controller_reservations_master crm
    JOIN location_master lm
      ON lm.LOCATION_ID = crm.LOCATION_ID
    WHERE UPPER(crm.TYPE) = 'AISLE_ENTRY'
      AND lm.TYPE = 'AISLE_ENTRY'
    GROUP BY aisle_num_id
  ),

  
  cand_base AS (
    SELECT
      se.sample_location_id AS LOCATION_ID,
      se.aisle_num_id,
      se.tower_num_id,
      COALESCE(sr.Cost, 999999) AS aisle_dist,
      CASE
        WHEN (ds.dmax - ds.dmin) = 0 THEN 0
        ELSE (COALESCE(sr.Cost, 999999) - ds.dmin) / (ds.dmax - ds.dmin)
      END AS dist_norm,
      COALESCE(abl.bots_in_aisle, 0) AS bots_in_aisle
    FROM slots_empty se
    LEFT JOIN sac_ranked sr
      ON sr.aisle_num_id = se.aisle_num_id
    CROSS JOIN dist_stats ds
    LEFT JOIN aisle_bot_load abl
      ON abl.aisle_num_id = se.aisle_num_id
  ),

  
  cand_scored AS (
    SELECT
      cb.*,
      ( w_dist * cb.dist_norm )
      + ( w_bot_pen * GREATEST(cb.bots_in_aisle - v_bot_cap, 0) ) AS score
    FROM cand_base cb
  ),

  
  best_puts AS (
    SELECT
      cs.LOCATION_ID,
      cs.aisle_num_id,
      cs.tower_num_id,
      cs.dist_norm,
      cs.bots_in_aisle,
      cs.score,
      ROW_NUMBER() OVER (
        ORDER BY cs.score ASC, cs.dist_norm ASC, cs.LOCATION_ID ASC
      ) AS put_rank
    FROM cand_scored cs
  ),

  
  put_task_list AS (
    SELECT
      bp.LOCATION_ID       AS put_location_id,
      bp.aisle_num_id      AS put_aisle_id,
      bp.tower_num_id      AS put_tower_id,
      bp.put_rank,
      sr.aisle_rank,
      CASE
        WHEN sr.aisle_rank <= v_top_k THEN 0
        ELSE CEIL( (sr.aisle_rank - v_top_k) / 2.0 )
      END AS ring_idx,
      cb.dist_norm,
      ft.ORDER_BIN_ID,
      ft.future_station_id,
      ft.future_aisle_loc_id,
      ft.future_tower_loc_id,
      ft.task_tower_id,
      CASE WHEN ft.task_tower_id = bp.tower_num_id THEN 0 ELSE 1 END AS not_same_tower,
      (ft.task_tower_id - bp.tower_num_id) AS tower_delta,
      COALESCE(sf.Cost, 999999) AS future_station_aisle_cost
    FROM best_puts bp
    JOIN sac_ranked sr
      ON sr.aisle_num_id = bp.aisle_num_id
    JOIN cand_base cb
      ON cb.LOCATION_ID = bp.LOCATION_ID
    JOIN future_tasks ft
      ON ft.task_aisle_id = bp.aisle_num_id
     AND (
          (p_subsequent_included = 0 AND ft.task_tower_id = bp.tower_num_id)
       OR (p_subsequent_included = 1 AND ft.task_tower_id >= bp.tower_num_id)
         )
    LEFT JOIN sac_all sf
      ON sf.Station_ID   = ft.future_station_id
     AND sf.aisle_num_id = ft.task_aisle_id
  ),

  
  put_task_per_station AS (
    SELECT
      x.put_location_id,
      x.put_aisle_id,
      x.put_tower_id,
      x.put_rank,
      x.aisle_rank,
      x.ring_idx,
      x.dist_norm,
      x.ORDER_BIN_ID,
      x.future_station_id,
      x.future_aisle_loc_id,
      x.future_tower_loc_id,
      x.task_tower_id,
      x.not_same_tower,
      x.tower_delta,
      x.future_station_aisle_cost
    FROM (
      SELECT
        ptl.*,
        ROW_NUMBER() OVER (
          PARTITION BY ptl.put_location_id, ptl.future_station_id
          ORDER BY
            ptl.not_same_tower ASC,
            ptl.future_station_aisle_cost ASC,
            ptl.tower_delta ASC,
            ptl.ORDER_BIN_ID
        ) AS rn_station
      FROM put_task_list ptl
    ) AS x
    WHERE x.rn_station = 1
  ),

  
  per_put_ordered AS (
    SELECT
      pps.*,
      ROW_NUMBER() OVER (
        PARTITION BY pps.put_location_id
        ORDER BY
          pps.not_same_tower ASC,
          pps.future_station_aisle_cost ASC,
          pps.tower_delta ASC,
          pps.aisle_rank ASC,
          pps.ORDER_BIN_ID
      ) AS per_put_rn
    FROM put_task_per_station pps
  ),

  
  final_ranked AS (
    SELECT
      ppo.*,
      ROW_NUMBER() OVER (
        ORDER BY
          ppo.not_same_tower ASC,           
          ppo.dist_norm ASC,                
          ppo.future_station_aisle_cost ASC,
          ppo.ring_idx ASC,
          ppo.aisle_rank ASC,
          ppo.tower_delta ASC,
          ppo.put_rank ASC,
          ppo.ORDER_BIN_ID
      ) AS global_rn
    FROM per_put_ordered ppo
  ),

  
  limited_per_station AS (
    SELECT *
    FROM (
      SELECT
        fr.*,
        ROW_NUMBER() OVER (
          PARTITION BY fr.future_station_id
          ORDER BY fr.global_rn
        ) AS rn_per_station
      FROM final_ranked fr
    ) AS x
    WHERE x.rn_per_station <= 2
  )

  
  SELECT
    lps.put_location_id,
    lm_put.AISLE_NUMBER      AS put_aisle_number,
    lm_put.TOWER_NUMBER      AS put_tower_number,
    lps.ORDER_BIN_ID         AS future_order_bin_id,
    lm_ft_aisle.AISLE_NUMBER AS future_order_aisle_number,
    lm_ft_tower.TOWER_NUMBER AS future_pick_tower_number,
    lps.future_station_id    AS future_order_station_id
  FROM limited_per_station lps
  JOIN location_master lm_put
       ON lm_put.LOCATION_ID = lps.put_location_id
  JOIN location_master lm_ft_aisle
       ON lm_ft_aisle.LOCATION_ID = lps.future_aisle_loc_id
  JOIN location_master lm_ft_tower
       ON lm_ft_tower.LOCATION_ID = lps.future_tower_loc_id
  ORDER BY lps.global_rn;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBestRackPutLocationForBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBestRackPutLocationForBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectBestRackPutLocationForBin`(
	in velocity_ inT,
	in x_ int,
	in y_ int
    )
BEGIN
	 if x_ = 0 and y_ = 0 then 
		SELECT `LOCATION_ID` FROM `store_bin_master` WHERE  `BIN_ID` IS null and `VELOCITY` = velocity_ and COST > 0 AND `AUDIT` = 0 ORDER BY `COST` ASC LIMIT 1; 
	 else
		select sbm.LOCATION_ID from store_bin_master sbm join location_master lm on sbm.LOCATION_ID = lm.LOCATION_ID 
		WHERE sbm.COST > 0 and sbm.BIN_ID is null 
		and sbm.VELOCITY = velocity_
		and (lm.Y = y_ + 1 or lm.Y = y_- 1) and lm.X = x_ AND `AUDIT` = 0
		ORDER BY sbm.COST ASC LIMIT 1;
	 end if;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectBotAllocatedBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectBotAllocatedBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectBotAllocatedBin`(
	in bin_id_ int
    )
BEGIN
		SELECT `BOT_ID` FROM `order_bin_mapping` WHERE `BOT_ID` <> NULL AND `BIN_ID` = bin_id_ AND `STATUS` NOT IN ('PENDING', 'TASK_COMPLETED');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectExistingRecoveryPick` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectExistingRecoveryPick` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectExistingRecoveryPick`(
    IN p_binID      VARCHAR(50),
    IN p_stationID  INT
)
BEGIN
    SELECT 
        `ORDER_BIN_ID`
    FROM 
        order_bin_mapping
    WHERE 
        `BIN_ID`     = p_binID
      AND `STATION_ID` = p_stationID
      AND `TYPE`  = 'RECOVERY_PICK'
      AND `STATUS` IN ('PENDING','TASK_ALLOCATED')
    ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectFutureBinOnRobot` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectFutureBinOnRobot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectFutureBinOnRobot`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select `BIN_ID`,`ORDER_BIN_ID`,`STATUS`,`STATION_ID`,`TYPE` FROM `order_bin_mapping` where `BOT_ID` = botID and status in ('PENDING') ORDER BY `ORDER_BIN_ID` LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectFutureOrderBinRobot` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectFutureOrderBinRobot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectFutureOrderBinRobot`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select `BIN_ID`,`ORDER_BIN_ID`,`STATUS`,`STATION_ID`,`TYPE` FROM `order_bin_mapping` where `BOT_ID` = botID and status in ('PENDING') ORDER BY `ORDER_BIN_ID` LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectHorizontalHomesWithReturnAisle` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectHorizontalHomesWithReturnAisle` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ts_SelectHorizontalHomesWithReturnAisle`()
BEGIN
    SELECT
        (
            SELECT rae.location_id
            FROM location_master AS rae
            WHERE rae.type = 'RETURN_AISLE_ENTRY'
              AND rae.Y <= lm.Y
            ORDER BY rae.Y DESC
            LIMIT 1
        ) AS return_aisle_location_id,
        lm.location_id,
        lm.X,
        lm.Y,
        lm.Z
    FROM location_master AS lm
    WHERE lm.type = 'HOME'
      AND (lm.X = 20 OR lm.X = 369) ORDER BY return_aisle_location_id;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectIfBotHealthy` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectIfBotHealthy` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectIfBotHealthy`(
	IN maintenanceLocationId INT
    )
BEGIN
		SELECT
        mtm.*
    FROM
        `maintenance_task_master` AS mtm
        LEFT JOIN `hw_maintenance_master` AS hmm
            ON mtm.`MAINTENANCE_ID` = hmm.`MAINTENANCE_ID`
    WHERE
        mtm.`IS_MP_BOT_HEALTHY` = 1
        AND hmm.`MAINTENANCE_POINT_LOCATION_ID` = maintenanceLocationId
        order by mtm.`INSERTED_TIMESTAMP` desc
        limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectLiveStations` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectLiveStations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectLiveStations`()
BEGIN
		select `STATION_ID` from `hw_station_master` where `WAVE_STATUS` = 'WAVE_LIVE';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectManualPendingTasks` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectManualPendingTasks` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectManualPendingTasks`()
BEGIN
		SELECT * FROM `dashboard_manual_task_master` WHERE `STATUS` IN ('WAITING');
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectNotCompletedBinsByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectNotCompletedBinsByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectNotCompletedBinsByBinId`(IN p_binId INT)
BEGIN
    SELECT `BIN_ID` 
    FROM `order_bin_mapping` 
    WHERE `STATUS` not in ('PENDING','TASK_COMPLETED')
    AND `BIN_ID` = p_binId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectOperationDoneBins` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectOperationDoneBins` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectOperationDoneBins`()
BEGIN
		Select `BIN_ID` from `order_bin_mapping` where `STATUS` = 'OPERATION_COMPLETED';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectOrderBinIDFromBinStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectOrderBinIDFromBinStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectOrderBinIDFromBinStation`(
	in binID int,
	in stationID INT
    )
BEGIN
		SELECT * FROM `order_bin_mapping` WHERE `BIN_ID` = binID and `STATION_ID` = stationID and `STATUS` = 'PENDING' limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectOrderBinIdWithBinStationCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectOrderBinIdWithBinStationCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectOrderBinIdWithBinStationCompleted`( 
    	IN binID INT,
	IN stationID INT
)
BEGIN
		SELECT * FROM `order_bin_mapping` WHERE `BIN_ID` = binID AND `STATION_ID` = stationID AND `STATUS` in ('OPERATION_COMPLETED', 'POST_ON_STATION');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectOrderBinMappingPendingByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectOrderBinMappingPendingByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectOrderBinMappingPendingByBinId`(in p_binId int, in p_orderBinId int)
BEGIN
		SELECT `ORDER_BIN_ID`,`STATUS` 
		FROM `order_bin_mapping` 
		WHERE `BIN_ID` = p_binId
		AND ORDER_BIN_ID <> p_orderBinId
		AND `STATUS` IN ('PENDING')
		LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectPendingOrderByBotId` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectPendingOrderByBotId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectPendingOrderByBotId`(
	in botId varchar(50)
    )
BEGIN
		select * from order_bin_mapping where bot_id = botId and Status = 'PENDING';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectPickBinFromStatonTasks` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectPickBinFromStatonTasks` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectPickBinFromStatonTasks`()
BEGIN
		-- Step 1: Create a Temporary Table
	    CREATE TEMPORARY TABLE temp_station_task_master AS
	    SELECT *
	    FROM order_bin_mapping 
	    WHERE STATUS = 'PENDING' AND IS_SYNCED = 0 AND `TYPE` = 'STATION_PICK';
	    -- Step 2: Update the IS_SYNCED Field in the Main Table
	    UPDATE order_bin_mapping
	    SET IS_SYNCED = 1
	    WHERE ORDER_BIN_ID IN (SELECT ORDER_BIN_ID FROM temp_station_task_master);
	    
	    SELECT * FROM temp_station_task_master;
	    -- Optional: Drop the Temporary Table (it will be dropped automatically at the end of the session)
	    DROP TEMPORARY TABLE IF EXISTS temp_station_task_master;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectProcessingBinOnRobot` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectProcessingBinOnRobot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectProcessingBinOnRobot`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select `BIN_ID`,`ORDER_BIN_ID`,`STATUS`,`STATION_ID`,`TYPE` FROM `order_bin_mapping` where `BOT_ID` = botID and status not in ('PENDING', 'TASK_COMPLETED') ORDER BY `ORDER_BIN_ID` LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectRackOrderBinFromBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectRackOrderBinFromBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectRackOrderBinFromBin`(
	in binID int
    )
BEGIN
		select `ORDER_BIN_ID`,`STATION_ID` from `order_bin_mapping` where `BIN_ID` = binID and status = 'PENDING' and type = 'RACK_PICK';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectRackOrderBinFromStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectRackOrderBinFromStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectRackOrderBinFromStation`(
	in stationID int
    )
BEGIN
		select `ORDER_BIN_ID`  from `order_bin_mapping` where `STATION_ID` = stationID and status = 'PENDING';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectRecoveryPickTasks` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectRecoveryPickTasks` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectRecoveryPickTasks`(
    )
BEGIN
		select `ORDER_BIN_ID`,`STATION_ID`,`BIN_ID` from `recovery_pick_task_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectRobotReachingAStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectRobotReachingAStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectRobotReachingAStation`(
	in stationID int
    )
BEGIN
		SELECT `ORDER_BIN_ID` FROM `order_bin_mapping` WHERE `STATION_ID` = stationID AND `TYPE` = 'RACK_PICK' AND `STATUS` IN ('TASK_ALLOCATED', 'BIN_PICKED', 'PENDING') and BOT_ID IS NOT NULL;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectRobotsBinAlreadyPresentRecovery` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectRobotsBinAlreadyPresentRecovery` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectRobotsBinAlreadyPresentRecovery`()
BEGIN
		select `BOT_ID` where `BIN_ALREDY_PRSENT_RECOVERY_` = 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectStationPickTasksOfStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectStationPickTasksOfStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectStationPickTasksOfStation`(
	in stationId int
    )
BEGIN
		select `ORDER_BIN_ID`,`STATION_ID`,`BIN_ID` from `station_pick_task_master` where `STATION_ID` = stationId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectStationsOfBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectStationsOfBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectStationsOfBin`(
	in binID int
    )
BEGIN
		select `STATION_ID` from `order_bin_mapping` where `BIN_ID` = binID and `STATUS` = 'PENDING';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectStorageLocationFromBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectStorageLocationFromBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectStorageLocationFromBin`(
	in binID int
    )
BEGIN
		select `LOCATION_ID` from `store_bin_master` WHERE `BIN_ID` = binID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_SelectVelocityOfBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_SelectVelocityOfBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_SelectVelocityOfBin`(
	in bin_id_ int
    )
BEGIN
SELECT 
    IFNULL(
        (SELECT MIN(aim.`VELOCITY`) 
         FROM `sku_master` aim 
         LEFT JOIN `live_inventory_master` lim 
         ON lim.`ARTICLE_ID` = aim.`SKU_ID` 
         WHERE lim.`BIN_ID` = bin_id_), 
        (SELECT MIN(sbm.`VELOCITY`) 
         FROM `store_bin_master` sbm)
    ) AS bin_velocity;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_Updatechargingbit` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_Updatechargingbit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_Updatechargingbit`(
        in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN setChargingrequiredbit INT)
BEGIN
              UPDATE  `bot_master` set `CHARGING_BIT`=setChargingrequiredbit where `BOT_ID`= botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_UpdatechargingbitafterreachingChargingstation` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_UpdatechargingbitafterreachingChargingstation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_UpdatechargingbitafterreachingChargingstation`(
        in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN setChargingrequiredbit INT)
BEGIN
              UPDATE  `bot_master` SET `CHARGING_BIT`=setChargingrequiredbit,`AUTO_MANUAL`='manual'  WHERE `BOT_ID`= botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_updateIsSyncedToZero` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_updateIsSyncedToZero` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_updateIsSyncedToZero`(in orderBinId int)
BEGIN
		update order_bin_mapping set `IS_SYNCED` = 0 where `ORDER_BIN_ID` = orderBinId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_UpdateMuxAutoBoolBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_UpdateMuxAutoBoolBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_UpdateMuxAutoBoolBit`(
    IN p_mux_id INT,
    IN p_bit_position INT,
    IN p_bit_value TINYINT
)
BEGIN
    DECLARE v_len INT;
    DECLARE v_auto_bool VARCHAR(50);

    -- Read current AUTO_BOOL
    SELECT AUTO_BOOL
    INTO v_auto_bool
    FROM hw_conveyor_mux_master
    WHERE MUX_ID = p_mux_id
    FOR UPDATE;

    -- If AUTO_BOOL is NULL, initialize it
    IF v_auto_bool IS NULL THEN
        SET v_auto_bool = '000000';

        UPDATE hw_conveyor_mux_master
        SET AUTO_BOOL = v_auto_bool
        WHERE MUX_ID = p_mux_id;
    END IF;

    -- Length after initialization
    SET v_len = CHAR_LENGTH(v_auto_bool);

    -- Safety check for bit position
    IF p_bit_position < 0 OR p_bit_position >= v_len THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Bit position out of range';
    END IF;

    -- Update only the required bit
    UPDATE hw_conveyor_mux_master
    SET AUTO_BOOL = CONCAT(
        SUBSTRING(v_auto_bool, 1, p_bit_position),
        p_bit_value,
        SUBSTRING(v_auto_bool, p_bit_position + 2)
    )
    WHERE MUX_ID = p_mux_id;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_UpdateOrderBinMappingState` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_UpdateOrderBinMappingState` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_UpdateOrderBinMappingState`(    
    IN setStatus VARCHAR(100),
    IN orderBinID INT
    )
BEGIN
		    UPDATE `order_bin_mapping`
	    SET
		`STATUS` = setStatus
	    WHERE `ORDER_BIN_ID` = orderBinID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_UpdateOrderBinMappingStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_UpdateOrderBinMappingStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_UpdateOrderBinMappingStatus`(
    IN setStatus VARCHAR(100),
    in botID varchar(50),
    IN orderBinID INT
)
BEGIN
    UPDATE `order_bin_mapping`
    SET BOT_ID = IF(botID = 'NULL', NULL, botID),
        `STATUS` = setStatus
    WHERE `ORDER_BIN_ID` = orderBinID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ts_UpdateRobotsBinAlreadyPresentRecovery` */

/*!50003 DROP PROCEDURE IF EXISTS  `ts_UpdateRobotsBinAlreadyPresentRecovery` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `ts_UpdateRobotsBinAlreadyPresentRecovery`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in recStatus int
    )
BEGIN
		update `bot_master` set  `BIN_ALREDY_PRSENT_RECOVERY_` = recStatus where `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_ArchiveAndDeleteWaveMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_ArchiveAndDeleteWaveMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_ArchiveAndDeleteWaveMaster`(
    IN p_waveId VARCHAR(50)
)
BEGIN    
    
    
    INSERT IGNORE INTO wave_master_archive (
        WAVE_ID,
        CLIENT_WAVE_ID,
        WAVE_TYPE,
        WAVE_STATUS,
        LEFT_OVER_STATUS,
        START_TIMESTAMP,
        STARTED_BY,
        IS_STOPPED,
        COMPLETED_TIMESTAMP,
        COMPLETED_BY,
        IS_CANCELLED,
        CANCELLED_TIMESTAMP,
        CANCELLED_BY,
        IS_ACTIVE,
        INSERTED_BY,
        INSERTED_TIMESTAMP,
        UPDATED_BY,
        UPDATED_TIMESTAMP,
        HAS_SHORT_PUT
    )
    SELECT 
        WAVE_ID,
        CLIENT_WAVE_ID,
        WAVE_TYPE,
        WAVE_STATUS,
        LEFT_OVER_STATUS,
        START_TIMESTAMP,
        STARTED_BY,
        IS_STOPPED,
        COMPLETED_TIMESTAMP,
        COMPLETED_BY,
        IS_CANCELLED,
        CANCELLED_TIMESTAMP,
        CANCELLED_BY,
        IS_ACTIVE,
        INSERTED_BY,
        INSERTED_TIMESTAMP,
        UPDATED_BY,
        UPDATED_TIMESTAMP,
        HAS_SHORT_PUT
    FROM wave_master
    WHERE WAVE_ID = p_waveId;
    
    
    DELETE FROM wave_master
    WHERE WAVE_ID = p_waveId;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_AuditBinWaveCheckIfWaveCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_AuditBinWaveCheckIfWaveCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_AuditBinWaveCheckIfWaveCompleted`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    DECLARE v_countCompletedStockAuditOrderMaster INT;
   
    SELECT COUNT(*)
    INTO v_countCompletedStockAuditOrderMaster
    FROM `order_bin_mapping`
    WHERE `STATUS`= 'LOCATION_PICK';
   
    SELECT (v_countCompletedStockAuditOrderMaster) AS 'COUNT';
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_BinInfoMasterByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_BinInfoMasterByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_BinInfoMasterByBinId`(in p_binId int)
BEGIN
		SELECT * FROM `bin_info_master`
		where `BIN_ID` = p_binId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_BinLoadingWaveCheckIfWaveCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_BinLoadingWaveCheckIfWaveCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_BinLoadingWaveCheckIfWaveCompleted`(
    IN p_waveId VARCHAR(200)
)
BEGIN
    DECLARE v_countCompletedStockAuditOrderMaster INT;
   
    
    SELECT COUNT(*)
    INTO v_countCompletedStockAuditOrderMaster
    FROM `bin_loading_wave_order_master`
    WHERE `STATUS` <> 'BIN_MOVED' 
    AND `WAVE_ID`= p_waveId;
    
    IF EXISTS (SELECT 1 FROM `order_bin_mapping`
                   WHERE `STATUS` IN ('PRE_ON_STATION', 'ON_STATION')
                   AND `ORDER_BIN_ID` IN (SELECT `ORDER_BIN_ID` 
                                          FROM `bin_loading_wave_order_master`
                                          WHERE `WAVE_ID` = p_waveId)) THEN
        SELECT 1 AS 'COUNT';
    ELSE
         
	SELECT (v_countCompletedStockAuditOrderMaster) AS 'COUNT';
    END IF;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_BinLoadingWaveDeleteDetailsOfBinUsingBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_BinLoadingWaveDeleteDetailsOfBinUsingBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_BinLoadingWaveDeleteDetailsOfBinUsingBinId`(IN p_binId INT)
BEGIN
    DECLARE v_binExistsInStore INT DEFAULT 0;
    DECLARE v_deletedFromLiveInventory INT DEFAULT 0;
    DECLARE v_deletedFromBinInfo INT DEFAULT 0;
    DECLARE v_deletedFromBinLoading INT DEFAULT 0;
    DECLARE v_error_message TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_error_message = MESSAGE_TEXT;
        ROLLBACK;
        SELECT CONCAT('Error occurred during deletion: ', v_error_message) AS ErrorMessage;
    END;
    
    START TRANSACTION;
    
    
    SELECT COUNT(1) INTO v_binExistsInStore
    FROM `store_bin_master`
    WHERE `BIN_ID` = p_binId;
    
    
    IF v_binExistsInStore > 0 THEN
        SELECT CONCAT('Bin ID ', p_binId, ' exists in store_bin_master. Deletion not allowed.') AS Message;
        ROLLBACK;
    ELSE
        
        DELETE FROM `live_inventory_master`
        WHERE `BIN_ID` = p_binId;
        
        SET v_deletedFromLiveInventory = ROW_COUNT();
        
        
        DELETE FROM `bin_info_master`
        WHERE `BIN_ID` = p_binId;
        
        SET v_deletedFromBinInfo = ROW_COUNT();
        
        
        DELETE FROM `bin_loading_wave_order_master`
        WHERE `bin_id` = p_binId;
        
        SET v_deletedFromBinLoading = ROW_COUNT();
        
        COMMIT;
        
        
        SELECT 
            p_binId AS BinId,
            'Deletion completed successfully' AS Status,
            v_deletedFromLiveInventory AS DeletedFromLiveInventory,
            v_deletedFromBinInfo AS DeletedFromBinInfo,
            v_deletedFromBinLoading AS DeletedFromBinLoading;
    END IF;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `wm_BinLoadingWaveGetRegistrationCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `wm_BinLoadingWaveGetRegistrationCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `wm_BinLoadingWaveGetRegistrationCompleted`(IN p_stationId INT)
BEGIN
    SELECT * FROM `bin_loading_wave_order_master` 
    where `STATION_ID` = p_stationId
    AND `STATUS` = 'BIN_REGISTRATION_COMPLETED';
END */$$
DELIMITER ;