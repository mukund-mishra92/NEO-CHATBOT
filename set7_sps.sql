
------------------------------------------------------------------------------------------------------------------------
/* Procedure structure for procedure `sm_GetPalletScanBarcodeByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetPalletScanBarcodeByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetPalletScanBarcodeByStationId`(IN p_stationId INT)
BEGIN
		SELECT `PALLET_SCAN_BARCODE` FROM `hw_station_master`
		WHERE `STATION_ID` = p_stationId
		LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetPendingStationPick` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetPendingStationPick` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetPendingStationPick`(
	in stationID int,
	in whereType varchar(50)	
    )
BEGIN
		select * from `order_bin_mapping` where `TYPE` = whereType and `STATION_ID` = stationID AND `STATUS` in ('PENDING','TASK_ALLOCATED');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetPickBinIdByBarcode` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetPickBinIdByBarcode` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetPickBinIdByBarcode`(IN p_barcode VARCHAR(200), IN p_stationId INT)
BEGIN
		DECLARE v_isWaveLive TINYINT; 
		-- Set v_isWaveLive based on WAVE_STATUS not being 'NO_WAVE'
		SET v_isWaveLive = (
			SELECT IF(`WAVE_STATUS` != 'NO_WAVE', 1, 0)
			FROM `hw_station_master`
			WHERE `STATION_ID` = p_stationId
		);
		-- Check the value of v_isWaveLive
		IF(v_isWaveLive = 1) THEN
			SELECT bim.`BIN_ID` 
			FROM `bin_info_master` bim
			JOIN `order_bin_mapping` obm 
			ON bim.`BIN_ID` = obm.`BIN_ID`
			WHERE bim.`BIN_BARCODE` = p_barcode 
			AND obm.`TYPE` = 'RACK_PICK'
			AND obm.`STATUS` = 'POST_ON_STATION'
			AND obm.`STATION_ID` = p_stationId
			LIMIT 1;
		ELSE
			SELECT bim.`BIN_ID` 
			FROM `bin_info_master` bim
			WHERE bim.`BIN_BARCODE` = p_barcode;
		END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetStationConveyorByHardwareId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetStationConveyorByHardwareId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetStationConveyorByHardwareId`(
	in p_hardwareID INT
    )
BEGIN
		SELECT * FROM `hw_conveyor_master`
		where `CONVEYOR_ID` = p_hardwareID 
		limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetStationConveyorByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetStationConveyorByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetStationConveyorByStationId`(
	in p_stationID INT
    )
BEGIN
		SELECT * FROM `hw_conveyor_master`
		where `PARENT_ID` = p_stationID 
		limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetStationPickOrderBinIdByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetStationPickOrderBinIdByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetStationPickOrderBinIdByStationId`(
	in p_stationId int
    )
BEGIN
	SELECT `ORDER_BIN_ID` 
	FROM `order_bin_mapping` 
	WHERE `STATION_ID` = p_stationId
	AND `STATUS` in ('PENDING','TASK_ALLOCATED')
	and `TYPE` = 'STATION_PICK';
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetStationScannerByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetStationScannerByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetStationScannerByStationId`(
	in p_stationID INT
    )
BEGIN
		SELECT * FROM `hw_scanner_master` 
		where `PARENT_ID` = p_stationID 
		limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetWaveIdByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetWaveIdByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetWaveIdByStationId`(
	in p_stationId int
    )
BEGIN
	SELECT `WAVE_ID`
	FROM `hw_station_master` 
	WHERE `STATION_ID` = p_stationId
	and WAVE_ID is not null;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_InsertMessageToDisplay` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_InsertMessageToDisplay` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_InsertMessageToDisplay`(in p_message json, in p_displayId int)
BEGIN
		update `hw_display_master`
		set `LAST_MESSAGE` = p_message
		where `DISPLAY_ID` = p_displayId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_InsertNoReadMessageToDisplay` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_InsertNoReadMessageToDisplay` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_InsertNoReadMessageToDisplay`(IN p_message varchar(200), IN p_displayId INT)
BEGIN
    -- Check if the input message is the string 'null' and update accordingly
   -- select p_message;
    IF p_message = 'null' THEN
        UPDATE `hw_display_master`
        SET NOREAD_MESSAGE = NULL
        WHERE `DISPLAY_ID` = p_displayId;
    ELSE
        -- Otherwise, update with the provided JSON message
        UPDATE `hw_display_master`
        SET NOREAD_MESSAGE = p_message
        WHERE `DISPLAY_ID` = p_displayId;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_InsertStationNoReads` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_InsertStationNoReads` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_InsertStationNoReads`(
                                    IN p_stationId INT,
                                    IN p_type VARCHAR(100),
                                    IN p_place VARCHAR(255)
                                )
BEGIN
                                    INSERT INTO `station_no_read_logs` (
                                        `STATION_ID`,
                                        `TYPE`,
                                        `PLACE`,
                                        `INSERTED_TIMESTAMP`
                                    ) VALUES (
                                        p_stationId,
                                        p_type,
                                        p_place,
                                        NOW()
                                    );
                                END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_MuxUpdateGlobalPauseInAutoBool` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_MuxUpdateGlobalPauseInAutoBool` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sm_MuxUpdateGlobalPauseInAutoBool`()
BEGIN
    DECLARE v_muxId INT;
    DECLARE v_globalPauseBit TINYINT(1);

    -- Get global pause bit (deterministic)
    SELECT CAST(`Global Pause Bit` AS UNSIGNED)
    INTO v_globalPauseBit
    FROM `teleoperation_bool_data`
    ORDER BY `ID` DESC
    LIMIT 1;

    -- Get MUX ID (deterministic)
    SELECT `MUX_ID`
    INTO v_muxId
    FROM `hw_conveyor_mux_master`
    ORDER BY `MUX_ID`
    LIMIT 1;

    -- Safety check
    IF v_muxId IS NOT NULL AND v_globalPauseBit IS NOT NULL THEN
        CALL `ts_UpdateMuxAutoBoolBit`(v_muxId, 4, v_globalPauseBit);
    END IF;

END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectAllConveyor` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectAllConveyor` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectAllConveyor`()
BEGIN
	SELECT * FROM `hw_conveyor_master`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectAllMaintenance` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectAllMaintenance` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectAllMaintenance`()
BEGIN
		SELECT * FROM `hw_maintenance_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectAllStations` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectAllStations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectAllStations`()
BEGIN
		SELECT * FROM `hw_station_master` WHERE STATUS = 'ENABLED';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectConveyorMoveBinConfirm` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectConveyorMoveBinConfirm` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectConveyorMoveBinConfirm`(
	IN conveyorID INT
    )
BEGIN
		select `MOVE_BIN_CONFIRM` from `hw_conveyor_master` where `CONVEYOR_ID` = conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectConveyorPickConfirm` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectConveyorPickConfirm` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectConveyorPickConfirm`(
	in conveyorID int
    )
BEGIN
		select `PICK_CONFIRM` from `hw_conveyor_master` where `CONVEYOR_ID` = conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectConveyorPutConfirm` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectConveyorPutConfirm` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectConveyorPutConfirm`(
	in conveyorID int
    )
BEGIN
		select `PUT_CONFIRM`, `PUT_BIN_ID` from `hw_conveyor_master` where `CONVEYOR_ID` = conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectConveyorWithHardwareID` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectConveyorWithHardwareID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectConveyorWithHardwareID`(
	in hardwareID int
    )
BEGIN
		select * from `hw_conveyor_master` where  `CONVEYOR_ID` = hardwareID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectConveyorWithParentID` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectConveyorWithParentID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sm_SelectConveyorWithParentID`(
	in hardwareID int
    )
BEGIN
		select * from `hw_conveyor_master` where  `PARENT_ID` = hardwareID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectCorrespondingMaintenancePickLocation` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectCorrespondingMaintenancePickLocation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectCorrespondingMaintenancePickLocation`(
	IN maintenanceLocationId INT
    )
BEGIN
		SELECT `MAINTENANCE_PICK_POINT_LOCATION_ID` FROM `hw_maintenance_master` WHERE `MAINTENANCE_POINT_LOCATION_ID` = maintenanceLocationId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectCurtainLightFromParent` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectCurtainLightFromParent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectCurtainLightFromParent`(
	IN p_parentId int
    )
BEGIN
		SELECT * FROM `hw_curtain_light_master` WHERE `PARENT_ID` = p_parentId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectDisplayFromParent` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectDisplayFromParent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectDisplayFromParent`(
	IN p_parentId int
    )
BEGIN
		SELECT * FROM `hw_display_master` WHERE `PARENT_ID` = p_parentId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectMaintenancePointPopup` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectMaintenancePointPopup` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectMaintenancePointPopup`(
	
    )
BEGIN
		SELECT * FROM `maintenance_task_master` WHERE MAINTENANCE_POINT_BARCODE_SCANNED = 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectPTLFromParent` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectPTLFromParent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectPTLFromParent`(
	IN p_parentId int
    )
BEGIN
		SELECT * FROM `hw_ptl_master` WHERE `PARENT_ID` = p_parentId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectPtlScannerFromParent` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectPtlScannerFromParent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectPtlScannerFromParent`(
	in p_parentID INT
    )
BEGIN
		SELECT * 
		FROM `hw_scanner_master` 
		where `PARENT_ID` in (select `PTL_ID` 
			from `hw_ptl_master` 
			where `PARENT_ID` = p_parentID);
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectRfidScannerFromParent` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectRfidScannerFromParent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sm_SelectRfidScannerFromParent`(
	IN p_parentID INT
    )
BEGIN
		SELECT * 
		FROM `hw_rfidscan_master` 
		WHERE `PARENT_ID` = p_parentID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectScannerFromMaintenanceLocation` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectScannerFromMaintenanceLocation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectScannerFromMaintenanceLocation`(
	in parentID INT
    )
BEGIN
		SELECT * FROM `hw_scanner_master` WHERE PARENT_ID = parentID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectScannerFromParent` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectScannerFromParent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectScannerFromParent`(
	in parentID INT
    )
BEGIN
		SELECT * FROM `hw_scanner_master` where `PARENT_ID` = parentID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectStationCurtainLightFromParent` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectStationCurtainLightFromParent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectStationCurtainLightFromParent`(
	in p_parentID INT
    )
BEGIN
		SELECT * 
		FROM `hw_curtain_light_master`
		where `PARENT_ID` = p_parentID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SelectStationScannerFromParent` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SelectStationScannerFromParent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SelectStationScannerFromParent`(
	in p_parentID INT
    )
BEGIN
		SELECT * 
		FROM `hw_scanner_master` 
		where `PARENT_ID` = p_parentID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_SetConveyorMutliplexerCounter` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_SetConveyorMutliplexerCounter` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_SetConveyorMutliplexerCounter`(
	IN p_hardwareId INT, in p_commsCounter int
    )
BEGIN
	-- SELECT `IP`,`PORT`,`MAKE`,`REGISTER_WRITE_ADDRESS`,`REGISTER_READ_ADDRESS`,`REGISTER_READ_LENGTH`
	update `hw_conveyor_mux_master`
	set `COUNTER` = p_commsCounter
	WHERE `MUX_ID` = p_hardwareId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateChargingStationBitHighLow` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateChargingStationBitHighLow` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateChargingStationBitHighLow`(
    IN p_state INT,
    IN p_location_id INT
)
BEGIN
    UPDATE hw_charging_station_master
    SET `SLIDING_DOOR_1_OPEN` = p_state
    WHERE LOCATION_ID = p_location_id;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateChargingStationGlobalPause` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateChargingStationGlobalPause` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateChargingStationGlobalPause`(
	IN p_state INT,
	IN p_hardwareId INT
    )
BEGIN
		UPDATE `hw_charging_station_master` 
		SET `GLOBAL_PAUSE` = p_state 
		WHERE `STATION_ID` = p_hardwareId;
		UPDATE teleoperation_bool_data
		SET `Global Pause Bit` = p_state;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorBinOnPickAckByParentId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorBinOnPickAckByParentId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorBinOnPickAckByParentId`(
	in p_parentID int,
	in p_state int
    )
BEGIN
		update `hw_conveyor_master` 
		set `BIN_ON_PICK_ACK` = p_state 
		where `PARENT_ID` = p_parentID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorData` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorData` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorData`(
	IN p_conveyorID INT,
	IN p_setCommCounter INT,
	IN p_setPutReq TINYINT,
	IN p_setPutConfirmAck TINYINT,
	IN p_setPickConfirmAck TINYINT,
	in p_setOnStationBool tinyint,
	in p_setPickBinBool tinyint,
	in p_binOnStaionBarcode varchar(50),
	in p_binOnPickBarcode varchar(50),
	in p_moveBinAck tinyint
    )
BEGIN
		UPDATE `hw_conveyor_master` SET `COUNTER` = p_setCommCounter, 
		`PUT_REQUEST` = p_setPutReq,
		`PUT_CONFIRM_ACK` = p_setPutConfirmAck, 
		`PICK_CONFIRM_ACK` = p_setPickConfirmAck,
		`BIN_ON_STATION_BOOL` = p_setOnStationBool,
		`BIN_ON_PICK_BOOL` = p_setPickBinBool,
		`BIN_ON_STATION_BARCODE` = p_binOnStaionBarcode,
		`BIN_ON_PICK_BARCODE` = p_binOnPickBarcode,
		`MOVE_BIN_CONFIRM_ACK` = p_moveBinAck
		 WHERE `CONVEYOR_ID` = p_conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorLastMsg` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorLastMsg` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorLastMsg`(
	in p_parentID int,
	in p_msg text
    )
BEGIN
		update `hw_conveyor_master` set `LAST_MSG_RECEIVED` = p_msg where `PARENT_ID` = p_parentID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorLastMsgSend` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorLastMsgSend` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorLastMsgSend`(
	in p_parentID int,
	in p_msg varchar(255) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		declare v_CONVEYOR_ID int;
		DECLARE v_msg varchar(255);
		select  `CONVEYOR_ID`, LAST_MSG_SENT from hw_conveyor_master where `PARENT_ID` = p_parentID into v_CONVEYOR_ID ,v_msg;
		
		if v_msg<>p_msg then
			update `hw_conveyor_master` set `LAST_MSG_SENT` = p_msg where `CONVEYOR_ID` = v_CONVEYOR_ID;
		end if;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorMoveBinConfirm` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorMoveBinConfirm` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorMoveBinConfirm`(
	IN conveyorID INT,
	IN setMoveBinConfirm tinyint
    )
BEGIN
		update `hw_conveyor_master` SET `MOVE_BIN_CONFIRM` = setMoveBinConfirm where `CONVEYOR_ID` = conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorOnStationBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorOnStationBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorOnStationBin`(
	in conveyorID int,
	in setOnStationBin varchar(200)
    )
BEGIN
		update `hw_conveyor_master` set `BIN_ON_STATION` = setOnStationBin where `CONVEYOR_ID` = conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorOnStationBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorOnStationBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorOnStationBinId`(
	IN p_conveyorID INT,
	IN p_onStationBin INT
    )
BEGIN
		UPDATE `hw_conveyor_master` 
		SET `BIN_ON_STATION` = p_onStationBin
		WHERE `CONVEYOR_ID` = p_conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorPickBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorPickBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorPickBin`(
	in conveyorID int,
	in setPickBin varchar(200)
    )
BEGIN
		update `hw_conveyor_master` set `BIN_ON_PICK` = setPickBin where `CONVEYOR_ID` = conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorPickBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorPickBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorPickBinId`(
	in p_conveyorID int,
	in p_pickBin varchar(200)
    )
BEGIN
		update `hw_conveyor_master` set `BIN_ON_PICK` = p_pickBin where `CONVEYOR_ID` = p_conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorPickConfirm` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorPickConfirm` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorPickConfirm`(
	in conveyorID int,
	in setPickConfirm tinyint
    )
BEGIN
		update `hw_conveyor_master` set `PICK_CONFIRM` = setPickConfirm where `CONVEYOR_ID` = conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateConveyorPutConfirm` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateConveyorPutConfirm` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateConveyorPutConfirm`(
	in conveyorID int,
	in setPutConfirm tinyint,
	in binID int
    )
BEGIN
		update `hw_conveyor_master` set `PUT_BIN_ID` = binID, `PUT_CONFIRM` = setPutConfirm where `CONVEYOR_ID` = conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateCurtainLightCounter` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateCurtainLightCounter` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateCurtainLightCounter`(
	IN p_counter INT,
	in p_hardwareId int
    )
BEGIN
		update `hw_curtain_light_master` SET `COUNTER` = p_counter where `LIGHT_ID` = p_hardwareId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateCurtainLightGlobalPause` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateCurtainLightGlobalPause` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateCurtainLightGlobalPause`(
	IN p_state INT,
	IN p_hardwareId INT
    )
BEGIN
		UPDATE `hw_curtain_light_master` 
		SET `GLOBAL_PAUSE` = p_state 
		WHERE `LIGHT_ID` = p_hardwareId;
		UPDATE teleoperation_bool_data
		SET `Global Pause Bit` = p_state;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateCurtainLightGlobalPauseByParentId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateCurtainLightGlobalPauseByParentId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sm_UpdateCurtainLightGlobalPauseByParentId`(
    IN p_state INT,
    IN p_parentId INT
)
BEGIN
    DECLARE v_hardwareAlias VARCHAR(255);
    DECLARE v_count INT DEFAULT 0;

    -- Update pause state in hardware table
    UPDATE `hw_curtain_light_master`
    SET `GLOBAL_PAUSE` = p_state
    WHERE `PARENT_ID` = p_parentId;

    -- Update teleoperation flag
    UPDATE `teleoperation_bool_data`
    SET `Global Pause Bit` = p_state;

    IF p_state = 1 THEN
        -- Check if a record for this source already exists with GLOBAL_PAUSE_BIT = 1
        SELECT COUNT(*) INTO v_count 
        FROM `global_pause_log`
        WHERE `source_id` = p_parentId
          AND `global_pause_bit` = 1
          AND `released_timestamp` IS NULL;

        IF v_count = 0 THEN
            -- Fetch hardware alias
            SELECT `HARDWARE_ALIAS` INTO v_hardwareAlias
            FROM `hardware_registered`
            WHERE `HARDWARE_ID` = p_parentId
            LIMIT 1;

            -- Insert with fresh UUID into LOG_ID
            INSERT INTO `global_pause_log`
                (`LOG_ID`, `source_id`, `source`, `global_pause_bit`, `pressed_timestamp`, `updated_timestamp`)
            VALUES
                (UUID(), p_parentId, v_hardwareAlias, 1, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
        END IF;

    ELSEIF p_state = 0 THEN
        -- Release the pause state if active
        UPDATE `global_pause_log`
        SET
            `global_pause_bit` = 0,
            `released_timestamp` = CURRENT_TIMESTAMP(),
            `updated_timestamp` = CURRENT_TIMESTAMP()
        WHERE
            `global_pause_bit` = 1
            AND `source_id` = p_parentId
            AND `released_timestamp` IS NULL;
    END IF;

END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdateCurtainLightLastSentBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdateCurtainLightLastSentBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdateCurtainLightLastSentBit`(
	IN p_lastSentBit varchar(100),
	IN p_hardwareId INT
    )
BEGIN
		UPDATE `hw_curtain_light_master` 
		SET `LAST_SENT_BITS` = p_lastSentBit 
		WHERE `LIGHT_ID` = p_hardwareId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_UpdatePreAndOnStationBinIdByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_UpdatePreAndOnStationBinIdByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_UpdatePreAndOnStationBinIdByStationId`(
	in p_stationId int,
	in p_binId int
    )
BEGIN
	UPDATE `order_bin_mapping` 
	SET `STATUS` = 'PENDING',
	`IS_SYNCED` = 0
	where BIN_ID = p_binId
	AND `STATUS` in ('ON_STATION','PRE_ON_STATION');
END */$$
DELIMITER ;

/* Procedure structure for procedure `sp_allocate_bots_to_station` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_allocate_bots_to_station` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_allocate_bots_to_station`()
BEGIN
    
    DROP TEMPORARY TABLE IF EXISTS tmp_station_allocation;
    CREATE TEMPORARY TABLE tmp_station_allocation (
        STATION_ID INT,
        STATION_ALIAS_NAME VARCHAR(255),
        ASSIGNED_BOT_COUNT INT
    );
 
    
    SELECT COUNT(*) INTO @TOTAL_AVAILABLE_BOTS
    FROM bot_master 
    WHERE STATUS = 'ENABLED' AND AUTO_MANUAL = 'auto';
 
    
    DROP TEMPORARY TABLE IF EXISTS tmp_live_stations;
    CREATE TEMPORARY TABLE tmp_live_stations AS
    SELECT
        s.STATION_ID,
        s.STATION_ALIAS_NAME,
        s.WAVE_ID,
        w.WAVE_TYPE,
        r.MIN_BOT_COUNT_PICK,
        r.MAX_BOT_COUNT_PICK,
        r.MIN_BOT_COUNT_PUT,
        r.MAX_BOT_COUNT_PUT,
        r.UPPER_BOT_COUNT_PUT
    FROM hw_station_master s
    JOIN wave_station_rule_mapping r ON r.STATION_ID = s.STATION_ID
    JOIN wave_master w ON w.WAVE_ID = s.WAVE_ID
    WHERE s.STATUS = 'ENABLED' AND s.WAVE_STATUS = 'WAVE_LIVE' AND r.IS_ACTIVE = 1;
 
    SET @available_bots = @TOTAL_AVAILABLE_BOTS;
 
    
    SET @done = 0;
    SET @round = 1;
 
    
    SELECT COUNT(*) INTO @pick_station_count FROM tmp_live_stations WHERE WAVE_TYPE = 'PICK';
 
    WHILE @done = 0 DO
        
        UPDATE tmp_live_stations
        SET MIN_BOT_COUNT_PICK = IF(@round <= MAX_BOT_COUNT_PICK, @round, MAX_BOT_COUNT_PICK)
        WHERE WAVE_TYPE = 'PICK' AND MAX_BOT_COUNT_PICK IS NOT NULL AND MIN_BOT_COUNT_PICK IS NOT NULL;
 
        
        SELECT SUM(MIN_BOT_COUNT_PICK) INTO @round_pick_bots FROM tmp_live_stations WHERE WAVE_TYPE = 'PICK';
 
        IF @available_bots >= @round_pick_bots THEN
            SET @available_bots = @available_bots - @round_pick_bots;
            SET @round = @round + 1;
            
            IF @round > (SELECT MAX(MAX_BOT_COUNT_PICK) FROM tmp_live_stations WHERE WAVE_TYPE = 'PICK') THEN
                SET @done = 1;
            END IF;
        ELSE
            SET @done = 1;
        END IF;
    END WHILE;
 
    
    INSERT INTO tmp_station_allocation (STATION_ID, STATION_ALIAS_NAME, ASSIGNED_BOT_COUNT)
    SELECT STATION_ID, STATION_ALIAS_NAME, MIN_BOT_COUNT_PICK
    FROM tmp_live_stations WHERE WAVE_TYPE = 'PICK';
 
    
    SET @done = 0;
    SET @round = 1;
 
    
    SELECT COUNT(*) INTO @put_station_count FROM tmp_live_stations WHERE WAVE_TYPE = 'PUT';
 
    WHILE @done = 0 DO
        
        UPDATE tmp_live_stations
        SET MIN_BOT_COUNT_PUT = IF(@round <= MAX_BOT_COUNT_PUT, @round, MAX_BOT_COUNT_PUT)
        WHERE WAVE_TYPE = 'PUT' AND MAX_BOT_COUNT_PUT IS NOT NULL AND MIN_BOT_COUNT_PUT IS NOT NULL;
 
        
        SELECT SUM(MIN_BOT_COUNT_PUT) INTO @round_put_bots FROM tmp_live_stations WHERE WAVE_TYPE = 'PUT';
 
        IF @available_bots >= @round_put_bots THEN
            SET @available_bots = @available_bots - @round_put_bots;
            SET @round = @round + 1;
            
            IF @round > (SELECT MAX(MAX_BOT_COUNT_PUT) FROM tmp_live_stations WHERE WAVE_TYPE = 'PUT') THEN
                SET @done = 1;
            END IF;
        ELSE
            SET @done = 1;
        END IF;
    END WHILE;
 
    
    SELECT SUM(MIN_BOT_COUNT_PUT) INTO @total_put_bots FROM tmp_live_stations WHERE WAVE_TYPE = 'PUT';
    SELECT MAX(UPPER_BOT_COUNT_PUT) INTO @upper_put_limit FROM tmp_live_stations WHERE WAVE_TYPE = 'PUT';
    IF @total_put_bots > @upper_put_limit THEN
        
        UPDATE tmp_live_stations SET MIN_BOT_COUNT_PUT = UPPER_BOT_COUNT_PUT WHERE WAVE_TYPE = 'PUT';
    END IF;
 
    
    INSERT INTO tmp_station_allocation (STATION_ID, STATION_ALIAS_NAME, ASSIGNED_BOT_COUNT)
    SELECT STATION_ID, STATION_ALIAS_NAME, MIN_BOT_COUNT_PUT
    FROM tmp_live_stations WHERE WAVE_TYPE = 'PUT';
 
    
    SELECT STATION_ID, STATION_ALIAS_NAME, ASSIGNED_BOT_COUNT FROM tmp_station_allocation;
 
    
    DROP TEMPORARY TABLE IF EXISTS tmp_live_stations;
    DROP TEMPORARY TABLE IF EXISTS tmp_station_allocation;
END */$$
DELIMITER ;

/* Procedure structure for procedure `SP_cdctest` */

/*!50003 DROP PROCEDURE IF EXISTS  `SP_cdctest` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `SP_cdctest`(_data varchar(20))
BEGIN
		select  'hello111' as message;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `SP_FIX_QUANTITY_MISMATCH` */

/*!50003 DROP PROCEDURE IF EXISTS  `SP_FIX_QUANTITY_MISMATCH` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `SP_FIX_QUANTITY_MISMATCH`()
BEGIN
    DECLARE done INT DEFAULT 0;

    DECLARE v_storage_id VARCHAR(64);
    DECLARE v_sku_id     VARCHAR(64);
    DECLARE v_batch_id   VARCHAR(64);
    DECLARE v_client_batch_id VARCHAR(64);
    DECLARE v_pallet_id VARCHAR(100);
    DECLARE v_pallet_status VARCHAR(64);

    DECLARE v_requested_qty INT DEFAULT 0;
    DECLARE v_put_qty       INT DEFAULT 0;
    DECLARE v_sync_put_qty  INT DEFAULT 0;
    DECLARE v_no_space_qty  INT DEFAULT 0;
    DECLARE v_other_qty     INT DEFAULT 0;
    DECLARE v_excess_qty    INT DEFAULT 0;
    DECLARE v_storage_id_complete_date DATETIME;

    
    DECLARE cur_storage CURSOR FOR
        SELECT DISTINCT
            a.STORAGE_ID,
            a.ARTICLE_ID,
            a.BATCH_ID,
            b.PALLET_ID
        FROM wms_to_wcs_storage_request_data a
        INNER JOIN wms_to_wcs_storage_request_pallet_data b
            ON a.WMS_STORAGE_REQUEST_PALLET_DATA_ID = b.WMS_STORAGE_REQUEST_PALLET_DATA_ID
        WHERE b.pallet_id IN (
'P_FRK_DEL-Dwarka Sector 12 Network',
'P_FRK_GGN-Sector 10A',
'PLT_CHD-Manimajra',
'PLT_GGN-Sector 79',
'PLT_NEO-GUR033-FRK_056',
'PLT_NEO-GUR033-FRK_057',
'PLT_NEO-GUR033-FRK_058',
'PLT_NEO-GUR033-FRK_059',
'PLT_NEO-GUR033-FRK_062',
'PLT_NEO-GUR033-FRK_076'
);



    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_quantity_mismatch_report;
    CREATE TEMPORARY TABLE tmp_quantity_mismatch_report (
        STORAGE_ID VARCHAR(64),
        PALLET_ID VARCHAR(100),
        SKU_ID VARCHAR(64),
        BATCH_ID VARCHAR(64),
        CLIENT_BATCH_ID VARCHAR(64),
        REQUESTED_QTY INT,
        PUT_QTY INT,
        SYNC_PUT_QTY INT,
        EXCESS_QTY INT,
        NO_SPACE_IN_INVENTORY_QTY INT,
        storage_id_complete_date DATETIME,
        OTHER_REASON_QTY INT,
        PALLET_STATUS VARCHAR(64)
    );

    OPEN cur_storage;

    read_loop: LOOP
        FETCH cur_storage INTO v_storage_id, v_sku_id, v_batch_id, v_pallet_id;
        IF done = 1 THEN
            LEAVE read_loop;
        END IF;

        
        SET v_requested_qty = 0;
        SET v_put_qty = 0;
        SET v_sync_put_qty = 0;
        SET v_no_space_qty = 0;
        SET v_other_qty = 0;
        SET v_excess_qty = 0;
        SET v_client_batch_id = NULL;
        SET v_pallet_status = NULL;

        
        SELECT sbm.CLIENT_BATCH_ID
        INTO v_client_batch_id
        FROM sku_batch_master sbm
        WHERE sbm.BATCH_ID = v_batch_id
        LIMIT 1;

        
        SELECT STORAGE_REQUEST_STATUS
        INTO v_pallet_status
        FROM (
            SELECT `STORAGE_REQUEST_STATUS`, INSERT_TIMESTAMP
            FROM wms_to_wcs_storage_request_pallet_data
            WHERE PALLET_ID = v_pallet_id
            UNION ALL
            SELECT `STORAGE_REQUEST_STATUS`, INSERT_TIMESTAMP
            FROM wms_to_wcs_storage_request_pallet_data_archive
            WHERE PALLET_ID = v_pallet_id
        ) t
        ORDER BY INSERT_TIMESTAMP DESC
        LIMIT 1;

        
        SELECT A.QUANTITY
        INTO v_requested_qty
        FROM (
            SELECT QUANTITY, INSERT_TIMESTAMP
            FROM wms_to_wcs_storage_request_data
            WHERE STORAGE_ID = v_storage_id
            UNION ALL
            SELECT QUANTITY, INSERT_TIMESTAMP
            FROM wms_to_wcs_storage_request_data_archive
            WHERE STORAGE_ID = v_storage_id
        ) A
        ORDER BY INSERT_TIMESTAMP ASC
        LIMIT 1;

        
        SELECT IFNULL(SUM(x.put_qty), 0)
        INTO v_put_qty
        FROM (
            SELECT PUT_ORDER_ID, MAX(PUT_QUANTITY) AS put_qty
            FROM (
                SELECT PUT_ORDER_ID, PUT_QUANTITY
                FROM put_wave_order_master
                WHERE STORAGE_ID = v_storage_id
                UNION ALL
                SELECT PUT_ORDER_ID, PUT_QUANTITY
                FROM put_wave_order_master_archive
                WHERE STORAGE_ID = v_storage_id
            ) t
            GROUP BY PUT_ORDER_ID
        ) X;

        
        SELECT IFNULL(SUM(x.put_qty), 0)
        INTO v_sync_put_qty
        FROM (
            SELECT wa.PUT_ORDER_ID, MAX(wa.PUT_QUANTITY) put_qty
            FROM put_wave_order_master_archive wa
            INNER JOIN wcs_to_wms_payload_archive wpa
                ON wpa.PAYLOAD_ID = wa.BIN_TRANSFER_PAYLOAD_ID
               AND wpa.IS_PROCESSED = 1
            WHERE wa.STORAGE_ID = v_storage_id
            GROUP BY wa.PUT_ORDER_ID
        ) X;

        
        SELECT IFNULL(SUM(LEFT_OVER), 0)
        INTO v_no_space_qty
        FROM (
            SELECT LEFT_OVER FROM put_wave_wms_data WHERE STORAGE_ID = v_storage_id
            UNION ALL
            SELECT LEFT_OVER FROM put_wave_wms_data_archive WHERE STORAGE_ID = v_storage_id
        ) t;

        
        SELECT IFNULL(SUM(r.SHORT_PUT_QUANTITY - r.RE_ATTEMPT_QUANTITY), 0)
        INTO v_other_qty
        FROM short_put_wave_reason r
        INNER JOIN (
            SELECT PUT_ORDER_ID FROM put_wave_order_master WHERE STORAGE_ID = v_storage_id
            UNION ALL
            SELECT PUT_ORDER_ID FROM put_wave_order_master_archive WHERE STORAGE_ID = v_storage_id
        ) o ON o.PUT_ORDER_ID = r.PUT_ORDER_ID
        WHERE (r.SHORT_PUT_QUANTITY - r.RE_ATTEMPT_QUANTITY) > 0;

        SET v_excess_qty =
              v_requested_qty
            - v_put_qty
            - v_other_qty
            - v_no_space_qty;

        SELECT UPDATE_TIMESTAMP
        INTO v_storage_id_complete_date
        FROM wms_to_wcs_storage_request_data
        WHERE STORAGE_ID = v_storage_id
        ORDER BY UPDATE_TIMESTAMP ASC
        LIMIT 1;

        INSERT INTO tmp_quantity_mismatch_report VALUES (
            v_storage_id,
            v_pallet_id,
            v_sku_id,
            v_batch_id,
            v_client_batch_id,
            v_requested_qty,
            v_put_qty,
            v_sync_put_qty,
            v_excess_qty,
            v_no_space_qty,
            v_storage_id_complete_date,
            v_other_qty,
            v_pallet_status
        );

    END LOOP;

    CLOSE cur_storage;

    
    SELECT * FROM tmp_quantity_mismatch_report;

END */$$
DELIMITER ;

/* Procedure structure for procedure `sp_InsertRecoveryLogFromAlarmMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_InsertRecoveryLogFromAlarmMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_InsertRecoveryLogFromAlarmMaster`(
    IN p_bot_id VARCHAR(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN p_alarm_code VARCHAR(5),  
    IN p_recovery_type ENUM('AUTO_NON_RECOVERY','NON_RECOVERY','RECOVERY','AUTO_RECOVERY'),
    IN p_location_id BIGINT,
    IN p_source ENUM('DASHBOARD','FMS')
)
BEGIN
    
    DECLARE v_alarm_code VARCHAR(5);
    DECLARE v_alarm_description TEXT;
    
    SELECT ALARM_CODE, ALARM_DESCRIPTION
    INTO v_alarm_code, v_alarm_description
    FROM (
        SELECT ALARM_CODE, ALARM_DESCRIPTION, INSERTED_TIMESTAMP
        FROM bot_alarm_log
        WHERE BOT_ID = p_bot_id
        UNION ALL
        SELECT ALARM_CODE, ALARM_DESCRIPTION, INSERTED_TIMESTAMP
        FROM maintenance_alarm_logs
        WHERE BOT_ID = p_bot_id
    ) AS all_alarms
    ORDER BY INSERTED_TIMESTAMP DESC
    LIMIT 1;
    
    IF v_alarm_code IS NULL THEN
        SET v_alarm_code = NULL;
        SET v_alarm_description = NULL;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM recovery_logs
        WHERE BOT_ID = p_bot_id
          AND TYPE = p_recovery_type
          AND (ALARM_CODE = v_alarm_code OR (ALARM_CODE IS NULL AND v_alarm_code IS NULL))
          AND LOCATION_ID = p_location_id
          AND SOURCE = p_source
          AND INSERTED_TIMESTAMP > NOW() - INTERVAL 5 SECOND
    ) THEN
        
        INSERT INTO recovery_logs
        (
            BOT_ID,
            TYPE,
            ALARM_CODE,
            ALARM_DESCRIPTION,
            SOURCE,
            LOCATION_ID
        )
        VALUES
        (
            p_bot_id,
            p_recovery_type,
            v_alarm_code,
            v_alarm_description,
            p_source,
            p_location_id
        );
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sp_InsertRobotChargeLog` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_InsertRobotChargeLog` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_InsertRobotChargeLog`(
    IN p_bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN battery int,
    in _Counter int
)
BEGIN
    UPDATE bot_charging_bit_log
SET    battery_percentage  = battery,
       Counter = _Counter,
       inserted_timestamp= NOW(3)
WHERE bot_id = p_bot_id and Counter>0
        ORDER  BY inserted_timestamp DESC
        LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sp_split_orders_ops_v10` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_split_orders_ops_v10` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sp_split_orders_ops_v10`()
sp_main: BEGIN

    
    DECLARE v_max_lines INT DEFAULT 50;
    DECLARE v_max_qty   INT DEFAULT 500;
    DECLARE v_tol_lines INT DEFAULT 10;
    DECLARE v_tol_qty   INT DEFAULT 100;

    DECLARE v_hard_lines INT DEFAULT 60;
    DECLARE v_hard_qty   INT DEFAULT 600;

    DECLARE v_suspend_short_lines INT DEFAULT 0;  
    DECLARE v_res_ttl_minutes INT DEFAULT 30;

    
    DECLARE v_ruleLog_id BIGINT DEFAULT NULL;
    DECLARE v_rule_id BIGINT DEFAULT NULL;
    DECLARE v_rule_defination TEXT DEFAULT NULL;

    
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_lock_key VARCHAR(128) DEFAULT NULL;

    
    DECLARE v_reservation_key VARCHAR(64) DEFAULT NULL;

    
    DECLARE v_station_mode ENUM('FINAL','INITIAL') DEFAULT NULL;
    DECLARE v_user_station_cnt BIGINT DEFAULT 0;

    
    DECLARE v_run_priority ENUM('INITIAL','FINAL') DEFAULT 'FINAL';
    DECLARE v_is_dry_run INT DEFAULT 0;

    
    DECLARE v_parent_cnt BIGINT DEFAULT 0;
    DECLARE v_line_cnt BIGINT DEFAULT 0;
    DECLARE v_child_cnt BIGINT DEFAULT 0;

    
    DECLARE v_cnt_lines BIGINT DEFAULT 0;
    DECLARE v_cnt_lines_cat BIGINT DEFAULT 0;
    DECLARE v_cnt_line_assign BIGINT DEFAULT 0;
    DECLARE v_cnt_ranked BIGINT DEFAULT 0;
    DECLARE v_cnt_final BIGINT DEFAULT 0;
    DECLARE v_cnt_db_child_lines BIGINT DEFAULT 0;

    DECLARE v_pre_lines BIGINT DEFAULT 0;
    DECLARE v_post_lines BIGINT DEFAULT 0;
    DECLARE v_pre_qty BIGINT DEFAULT 0;
    DECLARE v_post_qty BIGINT DEFAULT 0;
    DECLARE v_missing_lines BIGINT DEFAULT 0;

    DECLARE v_errmsg TEXT DEFAULT '';

    
    DECLARE v_has_or_cluster INT DEFAULT 0;
    DECLARE v_has_ol_cluster INT DEFAULT 0;

    DECLARE v_has_reco_col INT DEFAULT 0;   
    DECLARE v_has_reco1 INT DEFAULT 0;      
    DECLARE v_has_reco2 INT DEFAULT 0;      
    DECLARE v_has_reco1_alt INT DEFAULT 0;  
    DECLARE v_has_reco2_alt INT DEFAULT 0;  

    DECLARE v_has_hw_station INT DEFAULT 0;
    DECLARE v_has_hw_wave_status INT DEFAULT 0;

    
    DECLARE v_sku   VARCHAR(200) DEFAULT NULL;
    DECLARE v_batch VARCHAR(200) DEFAULT NULL;

    DECLARE v_rn INT DEFAULT 0;
    DECLARE v_maxrn INT DEFAULT 0;

    DECLARE v_line_parent VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_cat    VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_id     VARCHAR(36)  DEFAULT NULL;
    DECLARE v_line_qty    INT DEFAULT 0;

    DECLARE v_pick_cluster VARCHAR(50) DEFAULT NULL;

    DECLARE v_need BIGINT DEFAULT 0;
    DECLARE v_total_rem BIGINT DEFAULT 0;

    DECLARE v_crn INT DEFAULT 0;
    DECLARE v_cmax INT DEFAULT 0;
    DECLARE v_cur_cluster VARCHAR(50) DEFAULT NULL;
    DECLARE v_cur_rem BIGINT DEFAULT 0;
    DECLARE v_alloc BIGINT DEFAULT 0;

    
    DECLARE v_balance_mode INT DEFAULT 1;   
    DECLARE v_k1_pool INT DEFAULT 1;        

    
    DECLARE v_use_station_bias INT DEFAULT 0;   
    DECLARE v_near_aisle_window INT DEFAULT 1;  
    DECLARE v_min_pref_aisle INT DEFAULT NULL;
    DECLARE v_max_pref_aisle INT DEFAULT NULL;

    DECLARE v_total_lines_all BIGINT DEFAULT 0;
    DECLARE v_total_qty_all BIGINT DEFAULT 0;
    DECLARE v_total_lines_pickable BIGINT DEFAULT 0;
    DECLARE v_total_qty_pickable BIGINT DEFAULT 0;
    DECLARE v_alloc_qty_total BIGINT DEFAULT 0;
    DECLARE v_alloc_lines_total BIGINT DEFAULT 0;
    
	    
    DECLARE v_tmp_user_stations_ready INT DEFAULT 0;
        
    DECLARE v_lock_wait_seconds INT DEFAULT -1;

    
    DECLARE v_station_pref_consumed INT DEFAULT 0;

    
    DECLARE v_job_id BIGINT DEFAULT NULL;
    DECLARE v_job_rule_id BIGINT DEFAULT NULL;
    DECLARE v_job_priority ENUM('INITIAL','FINAL') DEFAULT NULL;



    
       
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;

        
        IF v_rule_id IS NOT NULL
           AND v_station_mode IS NOT NULL
           AND v_user_station_cnt > 0
           AND v_tmp_user_stations_ready = 1
        THEN
            UPDATE picklist_split_station_pref p
            JOIN tmp_user_stations t
              ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
            SET p.IS_PROCESSED = 0
            WHERE p.RULE_ID = v_rule_id
              AND p.PRIORITY = v_station_mode
              AND p.IS_PROCESSED = 1;
        END IF;

        
        IF v_ruleLog_id IS NOT NULL THEN
            UPDATE picklist_split_order_master
               SET IS_PROCESSED = '0',
                   ORDERSPLIT_ENDTIME = NOW()
             WHERE ID = v_ruleLog_id;
        END IF;

        
        
DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;

DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;       
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;     
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;      

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_final_map;

DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2;

DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;

DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;

DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;

        
        IF v_lock_ok = 1 AND v_lock_key IS NOT NULL THEN
            DO RELEASE_LOCK(v_lock_key);
        END IF;

        RESIGNAL;
    END;


    

    SET v_max_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_ORDER_LINES_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_lines
    );

    SET v_max_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_QUANTITY_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_qty
    );

    SET v_near_aisle_window = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_NEAR_AISLE_WINDOW' AND IS_ACTIVE = 1
          LIMIT 1),
        v_near_aisle_window
    );
    SET v_near_aisle_window = GREATEST(v_near_aisle_window, 0);

    SET v_tol_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_lines
    );

    SET v_tol_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_QTY' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_qty
    );

    SET v_suspend_short_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'SUSPEND_SHORT_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_suspend_short_lines
    );

    SET v_res_ttl_minutes = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'RESERVATION_TTL_MINUTES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_res_ttl_minutes
    );

    SET v_balance_mode = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_BALANCE_MODE' AND IS_ACTIVE = 1
          LIMIT 1),
        v_balance_mode
    );

    SET v_k1_pool = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_K1_POOL' AND IS_ACTIVE = 1
          LIMIT 1),
        v_k1_pool
    );
    SET v_k1_pool = GREATEST(v_k1_pool, 1);

        
    SET v_max_lines = GREATEST(v_max_lines, 1);
    SET v_max_qty   = GREATEST(v_max_qty,   1);
    SET v_tol_lines = GREATEST(v_tol_lines, 0);
    SET v_tol_qty   = GREATEST(v_tol_qty,   0);

    SET v_hard_lines = v_max_lines + v_tol_lines;
    SET v_hard_qty   = v_max_qty   + v_tol_qty;


    

    SELECT COUNT(*) INTO v_has_or_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_ol_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_line_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_reco_col
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'RECOMMENDATION';

    SELECT COUNT(*) INTO v_has_reco1
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_1';

    SELECT COUNT(*) INTO v_has_reco2
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_2';

    SELECT COUNT(*) INTO v_has_reco1_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_1';

    SELECT COUNT(*) INTO v_has_reco2_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_2';

    SELECT COUNT(*) INTO v_has_hw_station
      FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master';

    SELECT COUNT(*) INTO v_has_hw_wave_status
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master'
       AND COLUMN_NAME  = 'wave_status';

          

    job_pick: LOOP

        SET v_job_id = NULL;
        SET v_job_rule_id = NULL;
        SET v_job_priority = NULL;

        
        SELECT
            ID,
            RULE_ID,
            CASE
                WHEN COALESCE(NULLIF(PRIORITY,''),'FINAL') IN ('FINAL','INITIAL')
                    THEN COALESCE(NULLIF(PRIORITY,''),'FINAL')
                ELSE 'FINAL'
            END
          INTO v_job_id, v_job_rule_id, v_job_priority
        FROM picklist_split_order_master
        WHERE IS_PROCESSED = '0'
        ORDER BY ID
        LIMIT 1;

        IF v_job_id IS NULL OR v_job_rule_id IS NULL THEN

    
    SET @reco1_cluster_json := JSON_ARRAY(
        JSON_OBJECT(
            'CLUSTER_ID',  'NA',
            'STATION_ID',  '',
            'STATION_CNT', 0,
            'ORDER_LINES', 0,
            '%_LINES',     0.00,
            'ORDER_QTY',   0,
            '%_QTY',       0.00
        )
    );

    SET @reco2_cluster_json := @reco1_cluster_json;

    SET @dummy_master_reco := JSON_OBJECT(
        'RECOMMENDATION_1_ALL_STATIONS',          CAST(@reco1_cluster_json AS JSON),
        'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

        'STATION_PREF_MODE', NULL,
        'USER_SELECTED_STATIONS', '',
        'RULE_ID', NULL,
        'RULE_LOG_ID', NULL,
        'TOTAL_INITIAL_ORDERS', 0,
        'TOTAL_SPLIT_ORDERS',  0,

        'INITIAL_ORDER_LINES', 0,
        'AFTER_ALLOCATION_ORDER_LINES', 0,
        'TOTAL_LINES_PICKABLE', 0,

        'TOTAL_QTY_ALL', 0,
        'TOTAL_QTY_PICKABLE', 0,
        'ALLOC_QTY_TOTAL', 0,
        'ALLOC_LINES_TOTAL', 0,

        'NOTES', JSON_OBJECT(
            'PARENT_FIELD', 'PARENT_ORDER_ID',
            'CHILD_FIELD',  'ORDER_ID',
            'SUB_ORDER_ID', 'NOT_USED',
            'RESERVATION_KEY', '',
            'RESERVATION_TTL_MINUTES', 0,
            'DUMMY', 1
        )
    );

    
    SELECT
        'NO_RULE_TO_PROCESS' AS STATUS,
        CAST(@reco1_cluster_json AS JSON) AS recommendation_1,
        CAST(@reco2_cluster_json AS JSON) AS recommendation_2,
        CAST(@dummy_master_reco  AS JSON) AS RECOMMENDATION;

    LEAVE sp_main;
END IF;


        
        SET v_lock_key = CONCAT('SPLIT_CLUSTER_', v_job_rule_id);
        SELECT GET_LOCK(v_lock_key, v_lock_wait_seconds) INTO v_lock_ok;

        IF v_lock_ok IS NULL THEN
            SET v_errmsg = CONCAT('GET_LOCK_ERROR: key=', v_lock_key);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        ELSEIF v_lock_ok = 0 THEN
            
            SET v_errmsg = CONCAT('Split job already running (lock timeout) for RULE_ID=', v_job_rule_id);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        END IF;

        
        START TRANSACTION;

        SELECT
            ID,
            RULE_ID,
            v_job_priority
          INTO v_ruleLog_id, v_rule_id, v_run_priority
        FROM picklist_split_order_master
        WHERE ID = v_job_id
          AND IS_PROCESSED = '0'
        FOR UPDATE SKIP LOCKED;

        
        IF v_ruleLog_id IS NULL OR v_rule_id IS NULL THEN
            ROLLBACK;
            DO RELEASE_LOCK(v_lock_key);
            SET v_lock_ok = 0;
            ITERATE job_pick;
        END IF;

        LEAVE job_pick;
    END LOOP;

    
    SET v_is_dry_run = CASE WHEN v_run_priority = 'INITIAL' THEN 1 ELSE 0 END;

    
    IF v_is_dry_run = 1 THEN
        SET v_balance_mode = 0;
        SET v_k1_pool      = 1;
    END IF;



        

    SELECT FILTER_CONDITION
      INTO v_rule_defination
    FROM pick_rule_master
    WHERE PICK_RULE_ID = v_rule_id
    LIMIT 1;

    IF v_rule_defination IS NULL OR LENGTH(v_rule_defination) < 3 THEN
        
        UPDATE picklist_split_order_master
           SET IS_PROCESSED = '2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        COMMIT;
        DO RELEASE_LOCK(v_lock_key);

        SELECT 'NO_RULE_DEFINITION_FOUND' AS STATUS, v_rule_id AS RULE_ID;
        LEAVE sp_main;
    END IF;

    
    SET v_rule_defination = LEFT(v_rule_defination, LENGTH(v_rule_defination)-1);


    

SET v_station_mode = NULL;
SET v_user_station_cnt = 0;
SET v_station_pref_consumed = 0;   


IF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'FINAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'FINAL';
ELSEIF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'INITIAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'INITIAL';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
CREATE TEMPORARY TABLE tmp_user_stations (
    STATION_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (STATION_ID)
) ENGINE=INNODB;

SET v_tmp_user_stations_ready = 1;

IF v_station_mode IS NOT NULL THEN

    
    INSERT IGNORE INTO tmp_user_stations (STATION_ID)
    SELECT CAST(STATION_ID AS CHAR(50))
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND PRIORITY = v_station_mode
       AND IS_PROCESSED = 0
     ORDER BY STATION_ID
     FOR UPDATE;

    SELECT COUNT(*) INTO v_user_station_cnt FROM tmp_user_stations;

END IF;


SET v_use_station_bias =
    CASE
        WHEN v_is_dry_run = 0 AND v_user_station_cnt > 0 AND v_has_hw_station = 1 THEN 1
        ELSE 0
    END;



DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
CREATE TEMPORARY TABLE tmp_pref_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
CREATE TEMPORARY TABLE tmp_near_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_pref_clusters (CLUSTER_ID)
    SELECT DISTINCT CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.CLUSTER_ID IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
    CREATE TEMPORARY TABLE tmp_pref_aisle_num (
        AISLE_NUM INT NOT NULL,
        PRIMARY KEY (AISLE_NUM)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_pref_aisle_num (AISLE_NUM)
    SELECT DISTINCT
           CAST(
               NULLIF(
                   REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                   ''
               ) AS UNSIGNED
           ) AS AISLE_NUM
      FROM cluster_aisle_mapping cam
      JOIN tmp_pref_clusters pc
        ON pc.CLUSTER_ID = cam.CLUSTER_ID
     WHERE cam.AISLE_NUMBER IS NOT NULL;

    
    SELECT MIN(AISLE_NUM), MAX(AISLE_NUM)
      INTO v_min_pref_aisle, v_max_pref_aisle
      FROM tmp_pref_aisle_num;

    IF v_min_pref_aisle IS NOT NULL AND v_max_pref_aisle IS NOT NULL THEN

        
        INSERT IGNORE INTO tmp_near_clusters (CLUSTER_ID)
        SELECT DISTINCT cam.CLUSTER_ID
          FROM cluster_aisle_mapping cam
         WHERE cam.CLUSTER_ID IS NOT NULL
           AND cam.AISLE_NUMBER IS NOT NULL
           AND CAST(
                   NULLIF(
                       REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                       ''
                   ) AS UNSIGNED
               ) BETWEEN (v_min_pref_aisle - v_near_aisle_window)
                   AND (v_max_pref_aisle + v_near_aisle_window);

        
        DELETE n
          FROM tmp_near_clusters n
          JOIN tmp_pref_clusters p
            ON p.CLUSTER_ID = n.CLUSTER_ID;

    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;

END IF;




DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
CREATE TEMPORARY TABLE tmp_parent_orders (
    PRE_STAGED_REQ_ID BIGINT NOT NULL,
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    ORDER_TYPE        VARCHAR(100) NOT NULL,
    PRIMARY KEY (PRE_STAGED_REQ_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;


IF v_rule_defination IS NULL OR LENGTH(TRIM(v_rule_defination)) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULE_DEFINITION_EMPTY';
END IF;

SET @sql = CONCAT(
    'INSERT INTO tmp_parent_orders (PRE_STAGED_REQ_ID, PARENT_ORDER_ID, ORDER_TYPE)
     SELECT WMS_ORDER_REQUEST_DATA_ID,
            PARENT_ORDER_ID,
            COALESCE(NULLIF(PICKING_TYPE, ''''), NULLIF(ORDER_CATEGORY, ''''), ''PICK'') AS ORDER_TYPE
       FROM wms_to_wcs_order_level_pre_staged_data
      WHERE IFNULL(IS_STAGED,0) = 0
        AND PARENT_ORDER_ID IN (', v_rule_defination, ')'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT COUNT(*) INTO v_parent_cnt FROM tmp_parent_orders;

IF v_parent_cnt = 0 THEN

    
    IF v_station_pref_consumed = 1
       AND v_rule_id IS NOT NULL
       AND v_station_mode IS NOT NULL
       AND v_tmp_user_stations_ready = 1
    THEN
        UPDATE picklist_split_station_pref p
        JOIN tmp_user_stations t
          ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
        SET p.IS_PROCESSED = 0
        WHERE p.RULE_ID = v_rule_id
          AND p.PRIORITY = v_station_mode
          AND p.IS_PROCESSED = 1;

        SET v_station_pref_consumed = 0;
    END IF;

    
    
    SET v_line_cnt = 0;

    
    IF v_reservation_key IS NULL OR v_reservation_key = '' THEN
        SET v_reservation_key = CONCAT('SPLIT_', COALESCE(v_ruleLog_id,0), '_', REPLACE(UUID(),'-',''));
    END IF;

    SET @reco1_cluster_json := JSON_ARRAY(
        JSON_OBJECT(
            'CLUSTER_ID',  'NA',
            'STATION_ID',  '',
            'STATION_CNT', 0,
            'ORDER_LINES', 0,
            '%_LINES',     0.00,
            'ORDER_QTY',   0,
            '%_QTY',       0.00
        )
    );
    SET @reco2_cluster_json := @reco1_cluster_json;

    SET @dummy_user_selected := '';
    IF v_tmp_user_stations_ready = 1 THEN
        SELECT COALESCE(GROUP_CONCAT(STATION_ID ORDER BY STATION_ID SEPARATOR ','), '')
          INTO @dummy_user_selected
          FROM tmp_user_stations;
    END IF;

    SET @dummy_master_reco := JSON_OBJECT(
        'RECOMMENDATION_1_ALL_STATIONS',          CAST(@reco1_cluster_json AS JSON),
        'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

        'STATION_PREF_MODE', v_station_mode,
        'USER_SELECTED_STATIONS', @dummy_user_selected,
        'RULE_ID', v_rule_id,
        'RULE_LOG_ID', v_ruleLog_id,
        'TOTAL_INITIAL_ORDERS', v_parent_cnt,
        'TOTAL_SPLIT_ORDERS',  0,

        'INITIAL_ORDER_LINES', v_line_cnt,
        'AFTER_ALLOCATION_ORDER_LINES', 0,
        'TOTAL_LINES_PICKABLE', 0,

        'TOTAL_QTY_ALL', 0,
        'TOTAL_QTY_PICKABLE', 0,
        'ALLOC_QTY_TOTAL', 0,
        'ALLOC_LINES_TOTAL', 0,

        'NOTES', JSON_OBJECT(
            'PARENT_FIELD', 'PARENT_ORDER_ID',
            'CHILD_FIELD',  'ORDER_ID',
            'SUB_ORDER_ID', 'NOT_USED',
            'RESERVATION_KEY', COALESCE(v_reservation_key,''),
            'RESERVATION_TTL_MINUTES', v_res_ttl_minutes,
            'DUMMY', 1,
            'REASON', 'NO_PARENTS_TO_SPLIT'
        )
    );

    
    IF v_ruleLog_id IS NOT NULL THEN

        IF v_has_reco1 = 1 OR v_has_reco1_alt = 1 THEN
            UPDATE picklist_split_order_master
               SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

        IF v_has_reco2 = 1 OR v_has_reco2_alt = 1 THEN
            UPDATE picklist_split_order_master
               SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

        IF v_has_reco_col = 1 THEN
            UPDATE picklist_split_order_master
               SET RECOMMENDATION = CAST(@dummy_master_reco AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

    END IF;

    
    UPDATE picklist_split_order_master
       SET IS_PROCESSED = '2',
           ORDERSPLIT_ENDTIME = NOW()
     WHERE ID = v_ruleLog_id;

    COMMIT;

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
    END;

    DO RELEASE_LOCK(v_lock_key);

    SELECT 'NO_PARENTS_TO_SPLIT' AS STATUS, v_rule_id AS RULE_ID;
    LEAVE sp_main;
END IF;


UPDATE picklist_split_order_master
   SET IS_PROCESSED = '1',
       ORDERSPLIT_STARTTIME = NOW()
 WHERE ID = v_ruleLog_id
   AND IS_PROCESSED = '0';

IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULELOG_NOT_IN_STARTABLE_STATE';
END IF;


IF v_station_mode IS NOT NULL
   AND v_user_station_cnt > 0
   AND v_tmp_user_stations_ready = 1
THEN
    UPDATE picklist_split_station_pref p
    JOIN tmp_user_stations t
      ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
    SET p.IS_PROCESSED = 1
    WHERE p.RULE_ID = v_rule_id
      AND p.PRIORITY = v_station_mode
      AND p.IS_PROCESSED = 0;

    SET v_station_pref_consumed = 1;
END IF;


SET v_reservation_key = CONCAT('SPLIT_', v_ruleLog_id, '_', REPLACE(UUID(),'-',''));



DROP TEMPORARY TABLE IF EXISTS tmp_lines;
CREATE TEMPORARY TABLE tmp_lines (
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
    ARTICLE_ID      VARCHAR(200) NULL,
    BATCH_ID        VARCHAR(200) NULL,
    QUANTITY        INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_lines
SELECT
    l.PARENT_ORDER_ID,
    l.ORDER_LINE_ID,
    l.ARTICLE_ID,
    l.BATCH_ID,
    l.QUANTITY,
    l.DISPLAY_OPERATOR_INSTRUCTION
FROM wms_to_wcs_order_line_level_pre_staged_data l
JOIN tmp_parent_orders p
  ON p.PARENT_ORDER_ID = l.PARENT_ORDER_ID
WHERE IFNULL(l.ORDER_LINE_PROCESS_STATUS,'PENDING') <> 'DELETED';

SELECT COUNT(*) INTO v_line_cnt FROM tmp_lines;

IF v_line_cnt = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'NO_LINES_FOUND_FOR_SELECTED_PARENTS';
END IF;



    

    DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
    CREATE TEMPORARY TABLE tmp_line_category (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (ARTICLE_ID),
        KEY (CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_category (ARTICLE_ID, CLIENT_ORDER_TYPE)
    SELECT
        al.ARTICLE_ID,
        COALESCE(NULLIF(cm.CLIENT_ORDER_TYPE,''), 'FOOD') AS CLIENT_ORDER_TYPE
    FROM (SELECT DISTINCT ARTICLE_ID FROM tmp_lines WHERE ARTICLE_ID IS NOT NULL) al
    LEFT JOIN sku_master sm
      ON sm.SKU_ID = al.ARTICLE_ID
    LEFT JOIN category_master cm
      ON cm.CATEGORY_ID = sm.CATEGORY;

    DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
    CREATE TEMPORARY TABLE tmp_lines_cat (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines_cat
    SELECT
        tl.PARENT_ORDER_ID,
        COALESCE(lc.CLIENT_ORDER_TYPE, 'FOOD') AS CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION
    FROM tmp_lines tl
    LEFT JOIN tmp_line_category lc
      ON lc.ARTICLE_ID = tl.ARTICLE_ID;

    
    SELECT COUNT(*) INTO v_cnt_lines     FROM tmp_lines;
    SELECT COUNT(*) INTO v_cnt_lines_cat FROM tmp_lines_cat;

    IF v_cnt_lines_cat <> v_cnt_lines THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_CATEGORY: tmp_lines=', v_cnt_lines,
                              ', tmp_lines_cat=', v_cnt_lines_cat);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

 


DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
CREATE TEMPORARY TABLE tmp_aisle_cluster_raw (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER, CLUSTER_ID),
    KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster_raw (AISLE_NUMBER, CLUSTER_ID)
SELECT DISTINCT AISLE_NUMBER, CLUSTER_ID
  FROM cluster_aisle_mapping
 WHERE AISLE_NUMBER IS NOT NULL
   AND CLUSTER_ID IS NOT NULL;

IF (SELECT COUNT(*) FROM tmp_aisle_cluster_raw) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: cluster_aisle_mapping has no AISLE_NUMBER->CLUSTER_ID rows';
END IF;

IF EXISTS (
    SELECT 1
      FROM (
            SELECT AISLE_NUMBER, COUNT(*) AS c
              FROM tmp_aisle_cluster_raw
             GROUP BY AISLE_NUMBER
            HAVING c > 1
      ) X
    LIMIT 1
) THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: AISLE_NUMBER maps to multiple CLUSTER_ID in cluster_aisle_mapping';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
CREATE TEMPORARY TABLE tmp_aisle_cluster (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster (AISLE_NUMBER, CLUSTER_ID)
SELECT AISLE_NUMBER, CLUSTER_ID
  FROM tmp_aisle_cluster_raw;




DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
CREATE TEMPORARY TABLE tmp_sku_global (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_global
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_lines_cat
 WHERE ARTICLE_ID IS NOT NULL AND BATCH_ID IS NOT NULL;

DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
CREATE TEMPORARY TABLE tmp_inv_bin (
    BIN_ID INT NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    AVAIL_QTY BIGINT NOT NULL,
    LAST_TS DATETIME(3) NULL,
    PRIMARY KEY (BIN_ID, ARTICLE_ID, BATCH_ID),

    KEY (ARTICLE_ID, BATCH_ID),
    KEY (CLUSTER_ID),
    KEY (AISLE_NUMBER),

    
    KEY idx_ab_cluster (ARTICLE_ID, BATCH_ID, CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_inv_bin (BIN_ID, ARTICLE_ID, BATCH_ID, AISLE_NUMBER, CLUSTER_ID, AVAIL_QTY, LAST_TS)
SELECT
    lim.BIN_ID,
    lim.ARTICLE_ID,
    lim.BATCH_ID,
    lmst.AISLE_NUMBER,
    ac.CLUSTER_ID,
    GREATEST(
        CAST(SUM(GREATEST(lim.QUANTITY - lim.VIRTUAL_QUANTITY_TO_PICK, 0)) AS SIGNED),
        0
    ) AS AVAIL_QTY,
    MAX(lim.UPDATED_TIMESTAMP) AS LAST_TS
FROM live_inventory_master lim
JOIN tmp_sku_global sg
  ON sg.ARTICLE_ID = lim.ARTICLE_ID
 AND sg.BATCH_ID   = lim.BATCH_ID
JOIN store_bin_master sb
  ON sb.BIN_ID = lim.BIN_ID
JOIN location_master lmst
  ON lmst.LOCATION_ID = sb.LOCATION_ID
LEFT JOIN location_block_master lb
  ON lb.LOCATION_ID = sb.LOCATION_ID
JOIN tmp_aisle_cluster ac
  ON ac.AISLE_NUMBER = lmst.AISLE_NUMBER
WHERE lim.IS_ACTIVE = 1
  AND lim.BIN_ID IS NOT NULL
  AND lmst.AISLE_NUMBER IS NOT NULL
  AND lb.LOCATION_ID IS NULL
GROUP BY lim.BIN_ID, lim.ARTICLE_ID, lim.BATCH_ID, lmst.AISLE_NUMBER, ac.CLUSTER_ID
HAVING AVAIL_QTY > 0;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
CREATE TEMPORARY TABLE tmp_cluster_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply (ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY)
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUM(AVAIL_QTY) AS SUPPLY_QTY
  FROM tmp_inv_bin
 GROUP BY ARTICLE_ID, BATCH_ID, CLUSTER_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
CREATE TEMPORARY TABLE tmp_sku_total_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_SUPPLY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_total_supply
SELECT ARTICLE_ID, BATCH_ID, SUM(SUPPLY_QTY) AS TOTAL_SUPPLY
  FROM tmp_cluster_supply
 GROUP BY ARTICLE_ID, BATCH_ID;




DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
CREATE TEMPORARY TABLE tmp_final_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    CL_NUM     INT NULL,
    PRIMARY KEY (CLUSTER_ID),
    KEY (CL_NUM)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
CREATE TEMPORARY TABLE tmp_cluster_snap_map (
    SRC_CLUSTER_ID      VARCHAR(50) NOT NULL,
    SNAPPED_CLUSTER_ID  VARCHAR(50) NOT NULL,
    PRIMARY KEY (SRC_CLUSTER_ID),
    KEY (SNAPPED_CLUSTER_ID)
) ENGINE=INNODB;


DROP TEMPORARY TABLE IF EXISTS tmp_final_cluster_default;
CREATE TEMPORARY TABLE tmp_final_cluster_default (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_final_clusters (CLUSTER_ID, CL_NUM)
    SELECT
        pc.CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(pc.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS CL_NUM
    FROM tmp_pref_clusters pc
    WHERE pc.CLUSTER_ID IS NOT NULL;

    
    IF (SELECT COUNT(*) FROM tmp_final_clusters) = 0 THEN
        SET v_use_station_bias = 0;
    END IF;

    
    IF v_use_station_bias = 1 THEN
        INSERT INTO tmp_final_cluster_default (CLUSTER_ID)
        SELECT fc.CLUSTER_ID
          FROM tmp_final_clusters fc
         ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
         LIMIT 1;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;
    CREATE TEMPORARY TABLE tmp_supply_clusters (
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        SRC_NUM        INT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID),
        KEY (SRC_NUM)
    ) ENGINE=INNODB;

    INSERT INTO tmp_supply_clusters (SRC_CLUSTER_ID, SRC_NUM)
    SELECT DISTINCT
        cs.CLUSTER_ID AS SRC_CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(cs.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS SRC_NUM
    FROM tmp_cluster_supply cs;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    CREATE TEMPORARY TABLE tmp_snap_candidates (
        SRC_CLUSTER_ID   VARCHAR(50) NOT NULL,
        CAND_CLUSTER_ID  VARCHAR(50) NOT NULL,
        RN               INT NOT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID, RN),
        KEY (CAND_CLUSTER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_snap_candidates (SRC_CLUSTER_ID, CAND_CLUSTER_ID, RN)
    SELECT
        sc.SRC_CLUSTER_ID,
        fc.CLUSTER_ID AS CAND_CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY sc.SRC_CLUSTER_ID
            ORDER BY
                ABS(COALESCE(fc.CL_NUM,0) - COALESCE(sc.SRC_NUM,0)),
                
                CASE WHEN COALESCE(fc.CL_NUM,0) >= COALESCE(sc.SRC_NUM,0) THEN 0 ELSE 1 END,
                COALESCE(fc.CL_NUM,0),
                fc.CLUSTER_ID
        ) AS RN
    FROM tmp_supply_clusters sc
    JOIN tmp_final_clusters fc
      ON 1=1;

    
    INSERT IGNORE INTO tmp_cluster_snap_map (SRC_CLUSTER_ID, SNAPPED_CLUSTER_ID)
    SELECT
        sc.SRC_CLUSTER_ID,
        CASE
            WHEN fc_same.CLUSTER_ID IS NOT NULL THEN sc.SRC_CLUSTER_ID
            ELSE COALESCE(c.CAND_CLUSTER_ID, d.CLUSTER_ID)
        END AS SNAPPED_CLUSTER_ID
    FROM tmp_supply_clusters sc
    LEFT JOIN tmp_final_clusters fc_same
      ON fc_same.CLUSTER_ID = sc.SRC_CLUSTER_ID
    LEFT JOIN tmp_snap_candidates c
      ON c.SRC_CLUSTER_ID = sc.SRC_CLUSTER_ID
     AND c.RN = 1
    LEFT JOIN tmp_final_cluster_default d
      ON 1=1;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;

END IF;


    

    DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
    CREATE TEMPORARY TABLE tmp_line_cluster_candidates (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID VARCHAR(36) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        CLUSTER_ID VARCHAR(50)  NOT NULL,
        SUPPLY_QTY BIGINT NOT NULL,
        C_RANK INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, CLUSTER_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, C_RANK)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_cluster_candidates
    SELECT
        lc.PARENT_ORDER_ID,
        lc.CLIENT_ORDER_TYPE,
        lc.ORDER_LINE_ID,
        lc.ARTICLE_ID,
        lc.BATCH_ID,
        cs.CLUSTER_ID,
        cs.SUPPLY_QTY,
        ROW_NUMBER() OVER (
            PARTITION BY lc.PARENT_ORDER_ID, lc.CLIENT_ORDER_TYPE, lc.ORDER_LINE_ID
            ORDER BY cs.SUPPLY_QTY DESC, cs.CLUSTER_ID
        ) AS C_RANK
    FROM tmp_lines_cat lc
    JOIN tmp_cluster_supply cs
      ON cs.ARTICLE_ID = lc.ARTICLE_ID
     AND cs.BATCH_ID   = lc.BATCH_ID;

    DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
    CREATE TEMPORARY TABLE tmp_line_assign (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID VARCHAR(36) NOT NULL,
        ARTICLE_ID VARCHAR(200) NULL,
        BATCH_ID   VARCHAR(200) NULL,
        QUANTITY   INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

        ASSIGNED_CLUSTER_ID VARCHAR(50) NULL,
        ASSIGNED_RANK INT NOT NULL DEFAULT 0,

        SHORT_FLAG_SCHEMA INT NOT NULL DEFAULT 0,
        SHORT_FLAG_SUPPLY INT NOT NULL DEFAULT 0,
        SHORT_FLAG INT NOT NULL DEFAULT 0,

        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_assign
    SELECT
        lc.PARENT_ORDER_ID,
        lc.CLIENT_ORDER_TYPE,
        lc.ORDER_LINE_ID,
        lc.ARTICLE_ID,
        lc.BATCH_ID,
        lc.QUANTITY,
        lc.DISPLAY_OPERATOR_INSTRUCTION,
        NULL, 0,
        0, 0, 0
    FROM tmp_lines_cat lc;

    UPDATE tmp_line_assign la
    LEFT JOIN tmp_sku_total_supply ts
      ON ts.ARTICLE_ID = la.ARTICLE_ID
     AND ts.BATCH_ID   = la.BATCH_ID
    SET la.SHORT_FLAG_SCHEMA = CASE
        WHEN la.ARTICLE_ID IS NULL OR la.BATCH_ID IS NULL THEN 1
        WHEN ts.TOTAL_SUPPLY IS NULL THEN 1
        ELSE 0
    END;

    SELECT COUNT(*) INTO v_cnt_line_assign FROM tmp_line_assign;
    IF v_cnt_line_assign <> v_cnt_lines_cat THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_ASSIGN: tmp_lines_cat=', v_cnt_lines_cat,
                              ', tmp_line_assign=', v_cnt_line_assign);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
CREATE TEMPORARY TABLE tmp_bucket_k (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    TOTAL_LINES         BIGINT NOT NULL,
    TOTAL_QTY           BIGINT NOT NULL,
    K                   INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_k (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, TOTAL_LINES, TOTAL_QTY, K)
SELECT
    la.PARENT_ORDER_ID,
    la.CLIENT_ORDER_TYPE,
    COUNT(*) AS TOTAL_LINES,
    COALESCE(SUM(la.QUANTITY),0) AS TOTAL_QTY,
    GREATEST(
        1,
        IF(v_max_lines > 0, CEIL(COUNT(*) / v_max_lines), 1),
        IF(v_max_qty   > 0, CEIL(COALESCE(SUM(la.QUANTITY),0) / v_max_qty), 1)
    ) AS K
FROM tmp_line_assign la
GROUP BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
CREATE TEMPORARY TABLE tmp_bucket_cluster_score (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    BEST_LINE_CNT       BIGINT NOT NULL,
    BEST_QTY_FIT        BIGINT NOT NULL,
    SCORE               DECIMAL(30,0) NOT NULL,
    SCORE_RANK          INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SCORE_RANK),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_cluster_score
SELECT
    x.PARENT_ORDER_ID,
    x.CLIENT_ORDER_TYPE,
    x.CLUSTER_ID,
    x.BEST_LINE_CNT,
    x.BEST_QTY_FIT,
    (x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT AS SCORE,
    ROW_NUMBER() OVER (
        PARTITION BY x.PARENT_ORDER_ID, x.CLIENT_ORDER_TYPE
        ORDER BY ((x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT) DESC, x.CLUSTER_ID
    ) AS SCORE_RANK
FROM (
    SELECT
        c.PARENT_ORDER_ID,
        c.CLIENT_ORDER_TYPE,
        c.CLUSTER_ID,
        SUM(CASE WHEN c.C_RANK = 1 THEN 1 ELSE 0 END) AS BEST_LINE_CNT,
        SUM(CASE
                WHEN c.C_RANK = 1 THEN LEAST(c.SUPPLY_QTY, la.QUANTITY)
                ELSE 0
            END) AS BEST_QTY_FIT
    FROM tmp_line_cluster_candidates c
    JOIN tmp_line_assign la
      ON la.PARENT_ORDER_ID = c.PARENT_ORDER_ID
     AND la.CLIENT_ORDER_TYPE = c.CLIENT_ORDER_TYPE
     AND la.ORDER_LINE_ID = c.ORDER_LINE_ID
    GROUP BY c.PARENT_ORDER_ID, c.CLIENT_ORDER_TYPE, c.CLUSTER_ID
) X;

DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
CREATE TEMPORARY TABLE tmp_allowed_clusters (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
SELECT
    s.PARENT_ORDER_ID,
    s.CLIENT_ORDER_TYPE,
    s.CLUSTER_ID
FROM tmp_bucket_cluster_score s
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
WHERE s.SCORE_RANK <= CASE
    WHEN v_balance_mode = 1 AND k.K = 1 THEN GREATEST(k.K, v_k1_pool)
    ELSE k.K
END;

IF (SELECT COUNT(*) FROM tmp_allowed_clusters) = 0 THEN
    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
      FROM tmp_bucket_cluster_score;
END IF;


IF v_use_station_bias = 1 THEN

    DELETE ac
      FROM tmp_allowed_clusters ac
      LEFT JOIN tmp_final_clusters fc
        ON fc.CLUSTER_ID = ac.CLUSTER_ID
     WHERE fc.CLUSTER_ID IS NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
    CREATE TEMPORARY TABLE tmp_empty_buckets (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_empty_buckets (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    SELECT bk.PARENT_ORDER_ID, bk.CLIENT_ORDER_TYPE
      FROM tmp_bucket_k bk
      LEFT JOIN tmp_allowed_clusters ac2
        ON ac2.PARENT_ORDER_ID   = bk.PARENT_ORDER_ID
       AND ac2.CLIENT_ORDER_TYPE = bk.CLIENT_ORDER_TYPE
     WHERE ac2.PARENT_ORDER_ID IS NULL;

    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT eb.PARENT_ORDER_ID, eb.CLIENT_ORDER_TYPE, fc2.CLUSTER_ID
      FROM tmp_empty_buckets eb
      CROSS JOIN tmp_final_clusters fc2;

    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
CREATE TEMPORARY TABLE tmp_bucket_choice (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CHOSEN_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CHOSEN_CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_choice
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    MAX(CASE WHEN rn = 1 + MOD(bucket_hash, pool_cnt) THEN CLUSTER_ID END) AS CHOSEN_CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK, s.CLUSTER_ID
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
        ) AS pool_cnt,
        CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE)) AS bucket_hash
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
      AND s.SCORE_RANK <= v_k1_pool
) X
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;


INSERT IGNORE INTO tmp_bucket_choice (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CHOSEN_CLUSTER_ID)
SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK, s.CLUSTER_ID
        ) AS rn
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
) z
WHERE rn = 1;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_bucket_choice bc
    LEFT JOIN tmp_cluster_snap_map sm
      ON sm.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID
    SET bc.CHOSEN_CLUSTER_ID = COALESCE(sm.SNAPPED_CLUSTER_ID, bc.CHOSEN_CLUSTER_ID);
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
CREATE TEMPORARY TABLE tmp_final_first_cluster (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_final_first_cluster (CLUSTER_ID)
    SELECT fc.CLUSTER_ID
      FROM tmp_final_clusters fc
     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
     LIMIT 1;
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
CREATE TEMPORARY TABLE tmp_bucket_top_final (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_bucket_top_final (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
    FROM (
        SELECT
            s.PARENT_ORDER_ID,
            s.CLIENT_ORDER_TYPE,
            s.CLUSTER_ID,
            ROW_NUMBER() OVER (
                PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
                ORDER BY s.SCORE_RANK, s.CLUSTER_ID
            ) AS rn
        FROM tmp_bucket_cluster_score s
        JOIN tmp_final_clusters fcx
          ON fcx.CLUSTER_ID = s.CLUSTER_ID
    ) q
    WHERE rn = 1;
END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
CREATE TEMPORARY TABLE tmp_bucket_fallback (
    PARENT_ORDER_ID       VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE     VARCHAR(100) NOT NULL,
    FALLBACK_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (FALLBACK_CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    INSERT INTO tmp_bucket_fallback (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, FALLBACK_CLUSTER_ID)
    SELECT
        k.PARENT_ORDER_ID,
        k.CLIENT_ORDER_TYPE,
        COALESCE(bc.CHOSEN_CLUSTER_ID, topf.CLUSTER_ID, firstf.CLUSTER_ID) AS FALLBACK_CLUSTER_ID
    FROM tmp_bucket_k k
    LEFT JOIN tmp_bucket_choice bc
      ON bc.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND bc.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    LEFT JOIN tmp_bucket_top_final topf
      ON topf.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND topf.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    CROSS JOIN tmp_final_first_cluster firstf;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
CREATE TEMPORARY TABLE tmp_parent_cluster_load (
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    CLUSTER_ID        VARCHAR(50)  NOT NULL,
    LINE_CNT          BIGINT NOT NULL DEFAULT 0,
    QTY_CNT           BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
) ENGINE=INNODB;


     

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
CREATE TEMPORARY TABLE tmp_cluster_supply_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    REM_QTY    BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply_rem
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY, SUPPLY_QTY
  FROM tmp_cluster_supply;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
CREATE TEMPORARY TABLE tmp_sku_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_REM  BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_rem (ARTICLE_ID, BATCH_ID, TOTAL_REM)
SELECT ARTICLE_ID, BATCH_ID, SUM(REM_QTY) AS TOTAL_REM
  FROM tmp_cluster_supply_rem
 GROUP BY ARTICLE_ID, BATCH_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
CREATE TEMPORARY TABLE tmp_line_alloc (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NOT NULL,
    BATCH_ID            VARCHAR(200) NOT NULL,
    SRC_CLUSTER_ID      VARCHAR(50)  NOT NULL,
    ALLOC_QTY           BIGINT       NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, SRC_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (SRC_CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
CREATE TEMPORARY TABLE tmp_sku_queue (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_sku_queue
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_line_assign
 WHERE SHORT_FLAG_SCHEMA = 0
   AND ARTICLE_ID IS NOT NULL
   AND BATCH_ID IS NOT NULL;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
CREATE TEMPORARY TABLE tmp_sku_line_queue (
    RN INT NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    ORDER_LINE_ID VARCHAR(36) NOT NULL,
    QUANTITY INT NOT NULL,
    PRIMARY KEY (RN),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (ORDER_LINE_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
CREATE TEMPORARY TABLE tmp_line_cluster_seq (
    RN INT NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    REM_QTY BIGINT NOT NULL,
    PRIMARY KEY (RN),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

sku_loop: WHILE EXISTS (SELECT 1 FROM tmp_sku_queue LIMIT 1) DO

    SELECT ARTICLE_ID, BATCH_ID
      INTO v_sku, v_batch
      FROM tmp_sku_queue
      LIMIT 1;

    DELETE FROM tmp_sku_queue
     WHERE ARTICLE_ID = v_sku
       AND BATCH_ID   = v_batch;

    TRUNCATE TABLE tmp_sku_line_queue;

    
    INSERT INTO tmp_sku_line_queue (RN, PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY)
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE, la.QUANTITY DESC, la.ORDER_LINE_ID
        ) AS RN,
        la.PARENT_ORDER_ID,
        la.CLIENT_ORDER_TYPE,
        la.ORDER_LINE_ID,
        la.QUANTITY
    FROM tmp_line_assign la
    WHERE la.SHORT_FLAG_SCHEMA = 0
      AND la.ARTICLE_ID = v_sku
      AND la.BATCH_ID   = v_batch;

    SELECT COALESCE(MAX(RN),0) INTO v_maxrn FROM tmp_sku_line_queue;
    SET v_rn = 1;

    line_loop: WHILE v_rn <= v_maxrn DO

        SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY
          INTO v_line_parent, v_line_cat, v_line_id, v_line_qty
          FROM tmp_sku_line_queue
         WHERE RN = v_rn;

        
        DELETE FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        SELECT COALESCE(TOTAL_REM,0)
          INTO v_total_rem
          FROM tmp_sku_rem
         WHERE ARTICLE_ID = v_sku
           AND BATCH_ID   = v_batch;

        
        IF v_total_rem <= 0 THEN

            IF v_use_station_bias = 1 THEN
                
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;

                
                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        TRUNCATE TABLE tmp_line_cluster_seq;

        
        INSERT INTO tmp_line_cluster_seq (RN, CLUSTER_ID, REM_QTY)
        SELECT
            ROW_NUMBER() OVER (
                ORDER BY
                    
                    CASE
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND csr.CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                        ELSE 2
                    END,
                    
                    CASE
                        WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                        WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                        WHEN v_use_station_bias = 1 THEN 2
                        ELSE 3
                    END,
                    
                    CASE WHEN ac.CLUSTER_ID IS NOT NULL THEN 0 ELSE 1 END,
                    
                    COALESCE(bcs.SCORE_RANK, 999999),
                    
                    COALESCE(pcl.LINE_CNT,0) DESC,
                    COALESCE(pcl.QTY_CNT,0)  DESC,
                    
                    csr.REM_QTY DESC,
                    csr.CLUSTER_ID
            ) AS RN,
            csr.CLUSTER_ID,
            csr.REM_QTY
        FROM tmp_cluster_supply_rem csr
        LEFT JOIN tmp_allowed_clusters ac
          ON ac.PARENT_ORDER_ID   = v_line_parent
         AND ac.CLIENT_ORDER_TYPE = v_line_cat
         AND ac.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = v_line_parent
         AND bcs.CLIENT_ORDER_TYPE = v_line_cat
         AND bcs.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_choice bc
          ON bc.PARENT_ORDER_ID   = v_line_parent
         AND bc.CLIENT_ORDER_TYPE = v_line_cat
        LEFT JOIN tmp_parent_cluster_load pcl
          ON pcl.PARENT_ORDER_ID   = v_line_parent
         AND pcl.CLIENT_ORDER_TYPE = v_line_cat
         AND pcl.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_pref_clusters pfc
          ON pfc.CLUSTER_ID = csr.CLUSTER_ID
        LEFT JOIN tmp_near_clusters nfc
          ON nfc.CLUSTER_ID = csr.CLUSTER_ID
        WHERE csr.ARTICLE_ID = v_sku
          AND csr.BATCH_ID   = v_batch
          AND csr.REM_QTY   > 0;

        SELECT COALESCE(MAX(RN),0) INTO v_cmax FROM tmp_line_cluster_seq;

        
        SET v_need = v_line_qty;
        SET v_crn  = 1;

        cluster_loop: WHILE v_need > 0 AND v_crn <= v_cmax DO

            SELECT CLUSTER_ID, REM_QTY
              INTO v_cur_cluster, v_cur_rem
              FROM tmp_line_cluster_seq
             WHERE RN = v_crn;

            SET v_alloc = LEAST(v_cur_rem, v_need);

            IF v_alloc > 0 THEN

                INSERT INTO tmp_line_alloc (
                    PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID,
                    ARTICLE_ID, BATCH_ID, SRC_CLUSTER_ID, ALLOC_QTY
                )
                VALUES (
                    v_line_parent, v_line_cat, v_line_id,
                    v_sku, v_batch, v_cur_cluster, v_alloc
                )
                ON DUPLICATE KEY UPDATE
                    ALLOC_QTY = ALLOC_QTY + VALUES(ALLOC_QTY);

                UPDATE tmp_cluster_supply_rem
                   SET REM_QTY = REM_QTY - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch
                   AND CLUSTER_ID = v_cur_cluster;

                
                UPDATE tmp_sku_rem
                   SET TOTAL_REM = TOTAL_REM - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch;

                SET v_need = v_need - v_alloc;

            END IF;

            SET v_crn = v_crn + 1;
        END WHILE;

        
        SELECT COALESCE(SUM(ALLOC_QTY),0)
          INTO v_alloc
          FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        IF v_alloc <= 0 THEN

            IF v_use_station_bias = 1 THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;

                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        
        SET v_pick_cluster = NULL;

        
        SELECT la.SRC_CLUSTER_ID
          INTO v_pick_cluster
          FROM tmp_line_alloc la
          JOIN tmp_allowed_clusters ac
            ON ac.PARENT_ORDER_ID   = v_line_parent
           AND ac.CLIENT_ORDER_TYPE = v_line_cat
           AND ac.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_cluster_score bcs
            ON bcs.PARENT_ORDER_ID   = v_line_parent
           AND bcs.CLIENT_ORDER_TYPE = v_line_cat
           AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_choice bc
            ON bc.PARENT_ORDER_ID   = v_line_parent
           AND bc.CLIENT_ORDER_TYPE = v_line_cat
          LEFT JOIN tmp_pref_clusters pfc
            ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_near_clusters nfc
            ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
         WHERE la.PARENT_ORDER_ID   = v_line_parent
           AND la.CLIENT_ORDER_TYPE = v_line_cat
           AND la.ORDER_LINE_ID     = v_line_id
         ORDER BY
            la.ALLOC_QTY DESC,
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                ELSE 2
            END,
            CASE
                WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                WHEN v_use_station_bias = 1 THEN 2
                ELSE 3
            END,
            COALESCE(bcs.SCORE_RANK, 999999),
            la.SRC_CLUSTER_ID
         LIMIT 1;

        
        IF v_pick_cluster IS NULL THEN
            SELECT la.SRC_CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_line_alloc la
              LEFT JOIN tmp_bucket_cluster_score bcs
                ON bcs.PARENT_ORDER_ID   = v_line_parent
               AND bcs.CLIENT_ORDER_TYPE = v_line_cat
               AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_bucket_choice bc
                ON bc.PARENT_ORDER_ID   = v_line_parent
               AND bc.CLIENT_ORDER_TYPE = v_line_cat
              LEFT JOIN tmp_pref_clusters pfc
                ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_near_clusters nfc
                ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
             WHERE la.PARENT_ORDER_ID   = v_line_parent
               AND la.CLIENT_ORDER_TYPE = v_line_cat
               AND la.ORDER_LINE_ID     = v_line_id
             ORDER BY
                la.ALLOC_QTY DESC,
                CASE
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                    ELSE 2
                END,
                CASE
                    WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                    WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                    WHEN v_use_station_bias = 1 THEN 2
                    ELSE 3
                END,
                COALESCE(bcs.SCORE_RANK, 999999),
                la.SRC_CLUSTER_ID
             LIMIT 1;
        END IF;

        
        IF v_pick_cluster IS NULL THEN
            SELECT csr.CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_cluster_supply_rem csr
             WHERE csr.ARTICLE_ID = v_sku
               AND csr.BATCH_ID = v_batch
             ORDER BY csr.REM_QTY DESC, csr.CLUSTER_ID
             LIMIT 1;
        END IF;

        
        IF v_use_station_bias = 1
           AND v_pick_cluster IS NOT NULL
        THEN
            SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_pick_cluster)
              INTO v_pick_cluster
              FROM tmp_cluster_snap_map sm
             WHERE sm.SRC_CLUSTER_ID = v_pick_cluster
             LIMIT 1;

            
            IF v_pick_cluster IS NULL THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT fc.CLUSTER_ID
                  INTO v_pick_cluster
                  FROM tmp_final_clusters fc
                 ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                 LIMIT 1;
            END IF;
        END IF;

        
        UPDATE tmp_line_assign
           SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
               ASSIGNED_RANK = 1,
               SHORT_FLAG_SUPPLY = CASE WHEN v_alloc < v_line_qty THEN 1 ELSE 0 END
         WHERE PARENT_ORDER_ID = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID = v_line_id;

        
        INSERT INTO tmp_parent_cluster_load (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, LINE_CNT, QTY_CNT)
        VALUES (v_line_parent, v_line_cat, v_pick_cluster, 1, v_line_qty)
        ON DUPLICATE KEY UPDATE
            LINE_CNT = LINE_CNT + 1,
            QTY_CNT  = QTY_CNT  + VALUES(QTY_CNT);

        SET v_rn = v_rn + 1;
    END WHILE;

END WHILE;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_line_assign la
    LEFT JOIN tmp_bucket_fallback bf
      ON bf.PARENT_ORDER_ID = la.PARENT_ORDER_ID
     AND bf.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
    SET la.ASSIGNED_CLUSTER_ID = COALESCE(
            bf.FALLBACK_CLUSTER_ID,
            (SELECT fc.CLUSTER_ID
               FROM tmp_final_clusters fc
              ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
              LIMIT 1)
        ),
        la.ASSIGNED_RANK = 0
    WHERE la.SHORT_FLAG_SCHEMA = 1
      AND la.ASSIGNED_CLUSTER_ID IS NULL;
END IF;

UPDATE tmp_line_assign
   SET SHORT_FLAG = GREATEST(SHORT_FLAG_SCHEMA, SHORT_FLAG_SUPPLY);




        

    DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
    CREATE TEMPORARY TABLE tmp_cluster_plan (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        LINE_CNT            BIGINT NOT NULL,
        TOTAL_QTY           BIGINT NOT NULL,
        GRP_CNT             INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_cluster_plan
    SELECT
        la.PARENT_ORDER_ID,
        la.CLIENT_ORDER_TYPE,
        COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY') AS CLUSTER_ID,
        COUNT(*) AS LINE_CNT,
        COALESCE(SUM(la.QUANTITY),0) AS TOTAL_QTY,
        GREATEST(
            IF(v_max_lines > 0, (COUNT(*) + v_max_lines - 1) DIV v_max_lines, 1),
            IF(v_max_qty   > 0, (COALESCE(SUM(la.QUANTITY),0) + v_max_qty - 1) DIV v_max_qty, 1)
        ) AS GRP_CNT
    FROM tmp_line_assign la
    GROUP BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE, COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY');

    DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
    CREATE TEMPORARY TABLE tmp_ranked_lines (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
        ARTICLE_ID          VARCHAR(200) NULL,
        BATCH_ID            VARCHAR(200) NULL,
        QUANTITY            INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

        
        SHORT_FLAG          INT NOT NULL,   
        NO_INV_FLAG         INT NOT NULL,   

        RN BIGINT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, RN)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_ranked_lines
    SELECT
        la.PARENT_ORDER_ID,
        la.CLIENT_ORDER_TYPE,
        COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY') AS CLUSTER_ID,
        la.ORDER_LINE_ID,
        la.ARTICLE_ID,
        la.BATCH_ID,
        la.QUANTITY,
        la.DISPLAY_OPERATOR_INSTRUCTION,

        
        CASE
            WHEN COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = 'NO_INVENTORY' THEN 0
            WHEN la.SHORT_FLAG_SUPPLY = 1 THEN 1
            ELSE 0
        END AS SHORT_FLAG,

        CASE
            WHEN COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = 'NO_INVENTORY' THEN 1
            ELSE 0
        END AS NO_INV_FLAG,

        ROW_NUMBER() OVER (
            PARTITION BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE, COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY')
            ORDER BY la.QUANTITY DESC, la.ARTICLE_ID, la.ORDER_LINE_ID
        ) AS RN
    FROM tmp_line_assign la;

    SELECT COUNT(*) INTO v_cnt_ranked FROM tmp_ranked_lines;
    IF v_cnt_ranked <> v_cnt_line_assign THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_RANKING: tmp_line_assign=', v_cnt_line_assign,
                              ', tmp_ranked_lines=', v_cnt_ranked);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
    CREATE TEMPORARY TABLE tmp_final_map (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
        ARTICLE_ID          VARCHAR(200) NULL,
        BATCH_ID            VARCHAR(200) NULL,
        QUANTITY            INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

        SPLIT_GROUP         INT NOT NULL,

        
        IS_SUSPENDED_GROUP  INT NOT NULL,   
        IS_SHORT_LINE       INT NOT NULL,   

        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP)
    ) ENGINE=INNODB;

    INSERT INTO tmp_final_map
    SELECT
        r.PARENT_ORDER_ID,
        r.CLIENT_ORDER_TYPE,
        r.CLUSTER_ID,
        r.ORDER_LINE_ID,
        r.ARTICLE_ID,
        r.BATCH_ID,
        r.QUANTITY,
        r.DISPLAY_OPERATOR_INSTRUCTION,

        1 + ((r.RN - 1) * p.GRP_CNT) DIV p.LINE_CNT AS SPLIT_GROUP,

        
        r.NO_INV_FLAG AS IS_SUSPENDED_GROUP,

        
        r.SHORT_FLAG AS IS_SHORT_LINE
    FROM tmp_ranked_lines r
    JOIN tmp_cluster_plan p
      ON p.PARENT_ORDER_ID   = r.PARENT_ORDER_ID
     AND p.CLIENT_ORDER_TYPE = r.CLIENT_ORDER_TYPE
     AND p.CLUSTER_ID        = r.CLUSTER_ID;

    SELECT COUNT(*) INTO v_cnt_final FROM tmp_final_map;
    IF v_cnt_final <> v_cnt_ranked THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_FINAL_MAP: tmp_ranked_lines=', v_cnt_ranked,
                              ', tmp_final_map=', v_cnt_final);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;


    

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_pre_lines, v_pre_qty
    FROM tmp_lines;

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_post_lines, v_post_qty
    FROM tmp_final_map;

    IF v_pre_lines <> v_post_lines OR v_pre_qty <> v_post_qty THEN
        SET v_errmsg = CONCAT(
            'CONSERVATION_FAILED: PRE_LINES=', v_pre_lines,
            ', POST_LINES=', v_post_lines,
            ', PRE_QTY=', v_pre_qty,
            ', POST_QTY=', v_post_qty
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_lines tl
    LEFT JOIN tmp_final_map fm
      ON fm.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND fm.ORDER_LINE_ID   = tl.ORDER_LINE_ID
    WHERE fm.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('MISSING_LINES_IN_OUTPUT=', v_missing_lines);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

        

    DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
    CREATE TEMPORARY TABLE tmp_cat_seq (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CAT_SEQ             INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_cat_seq
    SELECT
        x.PARENT_ORDER_ID,
        x.CLIENT_ORDER_TYPE,
        ROW_NUMBER() OVER (PARTITION BY x.PARENT_ORDER_ID ORDER BY x.CLIENT_ORDER_TYPE) AS CAT_SEQ
    FROM (SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE FROM tmp_lines_cat) X;

    DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
    CREATE TEMPORARY TABLE tmp_groupmax (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        MAX_GRP             INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_groupmax
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, MAX(SPLIT_GROUP) AS MAX_GRP
      FROM tmp_final_map
     GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID;

    DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
    CREATE TEMPORARY TABLE tmp_child_orders (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        SPLIT_GROUP         INT NOT NULL,
        CHILD_ORDER_ID      VARCHAR(180) NOT NULL,
        CHILD_STATUS        ENUM('PENDING','ORDER_SUSPENDED') NOT NULL,

        
        HAS_SHORT_LINES     INT NOT NULL DEFAULT 0,  
        HAS_NO_INV_LINES    INT NOT NULL DEFAULT 0,  

        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP),
        KEY (CHILD_ORDER_ID),
        KEY (CHILD_STATUS)
    ) ENGINE=INNODB;

    INSERT INTO tmp_child_orders
    SELECT
        fm.PARENT_ORDER_ID,
        fm.CLIENT_ORDER_TYPE,
        fm.CLUSTER_ID,
        fm.SPLIT_GROUP,

        CASE
            WHEN gm.MAX_GRP = 1 THEN
                CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID)
            ELSE
                CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID, '-', LPAD(fm.SPLIT_GROUP, 3, '0'))
        END AS CHILD_ORDER_ID,

        
        CASE
            WHEN MAX(fm.IS_SUSPENDED_GROUP) = 1 THEN 'ORDER_SUSPENDED'
            ELSE 'PENDING'
        END AS CHILD_STATUS,

        
        CASE WHEN MAX(fm.IS_SHORT_LINE) = 1 THEN 1 ELSE 0 END AS HAS_SHORT_LINES,
        CASE WHEN MAX(fm.IS_SUSPENDED_GROUP) = 1 THEN 1 ELSE 0 END AS HAS_NO_INV_LINES

    FROM tmp_final_map fm
    JOIN tmp_cat_seq cs
      ON cs.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
     AND cs.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
    JOIN tmp_groupmax gm
      ON gm.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
     AND gm.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
     AND gm.CLUSTER_ID        = fm.CLUSTER_ID
    GROUP BY
        fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.SPLIT_GROUP,
        gm.MAX_GRP, cs.CAT_SEQ;

    SELECT COUNT(*) INTO v_child_cnt FROM tmp_child_orders;


	

SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_all,
        v_total_qty_all
    FROM tmp_line_assign;
    
    SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_pickable,
        v_total_qty_pickable
    FROM tmp_line_assign
    WHERE SHORT_FLAG_SCHEMA = 0
      AND COALESCE(ASSIGNED_CLUSTER_ID,'NO_INVENTORY') <> 'NO_INVENTORY';

    SELECT
        COALESCE(SUM(a.ALLOC_QTY),0),
        COALESCE(COUNT(DISTINCT CONCAT(a.PARENT_ORDER_ID,'|',a.CLIENT_ORDER_TYPE,'|',a.ORDER_LINE_ID)),0)
    INTO
        v_alloc_qty_total,
        v_alloc_lines_total
    FROM tmp_line_alloc a;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
CREATE TEMPORARY TABLE tmp_reco1 (
    STATION_ID VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NULL,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
CREATE TEMPORARY TABLE tmp_reco2 (
    STATION_ID   VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NULL,
    IS_SELECTED  INT NOT NULL DEFAULT 0,
    IS_NO_WAVE   INT NOT NULL DEFAULT 0,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID),
    KEY (IS_NO_WAVE, IS_SELECTED)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2_avail_clusters;
CREATE TEMPORARY TABLE tmp_reco2_avail_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_has_hw_station = 0 THEN

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT STATION_ID, NULL
      FROM tmp_user_stations;

    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT STATION_ID, NULL, 1, 0
      FROM tmp_user_stations;

ELSE

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM hw_station_master hs
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50)),
           1 AS IS_SELECTED,
           0 AS IS_NO_WAVE
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    IF v_has_hw_wave_status = 1 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
               CAST(hs.CLUSTER_ID AS CHAR(50)),
               0 AS IS_SELECTED,
               1 AS IS_NO_WAVE
          FROM hw_station_master hs
         WHERE hs.STATION_ID IS NOT NULL
           AND hs.CLUSTER_ID IS NOT NULL
           AND LOWER(REPLACE(COALESCE(hs.wave_status,''),' ','_')) IN ('no_wave','nowave','no-wave');
    END IF;

    
    IF v_user_station_cnt = 0 AND v_has_hw_wave_status = 0 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT STATION_ID, CLUSTER_ID, 0, 0 FROM tmp_reco1;
    END IF;

END IF;


INSERT IGNORE INTO tmp_reco2_avail_clusters (CLUSTER_ID)
SELECT DISTINCT COALESCE(CLUSTER_ID,'?')
  FROM tmp_reco2
 WHERE CLUSTER_ID IS NOT NULL;



DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
CREATE TEMPORARY TABLE tmp_job_cluster_stats (
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    ORDER_LINES  BIGINT NOT NULL,
    ORDER_QTY    BIGINT NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_job_cluster_stats (CLUSTER_ID, ORDER_LINES, ORDER_QTY)
SELECT
    co.CLUSTER_ID,
    COUNT(DISTINCT co.CHILD_ORDER_ID) AS ORDER_LINES,
    COALESCE(SUM(fm.QUANTITY),0)      AS ORDER_QTY
FROM tmp_child_orders co
LEFT JOIN tmp_final_map fm
  ON fm.PARENT_ORDER_ID   = co.PARENT_ORDER_ID
 AND fm.CLIENT_ORDER_TYPE = co.CLIENT_ORDER_TYPE
 AND fm.CLUSTER_ID        = co.CLUSTER_ID
 AND fm.SPLIT_GROUP       = co.SPLIT_GROUP

WHERE co.CLUSTER_ID <> 'NO_INVENTORY'
GROUP BY co.CLUSTER_ID;



DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco1_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco1_total_lines,
    @reco1_total_qty
FROM tmp_job_cluster_stats js;


INSERT INTO tmp_reco1_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID ORDER BY r.STATION_ID SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco1_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco1_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco1_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco1_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco1 r
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco2_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco2_total_lines,
    @reco2_total_qty
FROM tmp_job_cluster_stats js
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = js.CLUSTER_ID;


INSERT INTO tmp_reco2_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID
                          ORDER BY r.IS_NO_WAVE DESC, r.IS_SELECTED DESC, r.STATION_ID
                          SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco2_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco2_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco2_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco2_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco2 r
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = r.CLUSTER_ID
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



SET @reco1_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco1_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);

SET @reco2_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco2_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);



IF v_has_reco1 = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2 = 1 THEN
    UPDATE picklist_split_order_master
      SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco1_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco_col = 1 THEN
   UPDATE picklist_split_order_master
SET RECOMMENDATION = JSON_OBJECT(
    'RECOMMENDATION_1_ALL_STATIONS', CAST(@reco1_cluster_json AS JSON),
    'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

    'STATION_PREF_MODE', v_station_mode,
    'USER_SELECTED_STATIONS', (
        SELECT COALESCE(GROUP_CONCAT(STATION_ID ORDER BY STATION_ID SEPARATOR ','), '')
        FROM tmp_user_stations
    ),
    'RULE_ID', v_rule_id,
    'RULE_LOG_ID', v_ruleLog_id,
    'TOTAL_INITIAL_ORDERS', v_parent_cnt,
    'TOTAL_SPLIT_ORDERS', v_child_cnt,

    'INITIAL_ORDER_LINES', v_line_cnt,
    'AFTER_ALLOCATION_ORDER_LINES', v_cnt_final,

    'TOTAL_LINES_PICKABLE', v_total_lines_pickable,

    
    'TOTAL_QTY_ALL', v_pre_qty,
    'TOTAL_QTY_PICKABLE', v_total_qty_pickable,

    
    'ALLOC_QTY_TOTAL', v_post_qty,
    'ALLOC_LINES_TOTAL', v_alloc_lines_total,

    'NOTES', JSON_OBJECT(
        'PARENT_FIELD', 'PARENT_ORDER_ID',
        'CHILD_FIELD', 'ORDER_ID',
        'SUB_ORDER_ID', 'NOT_USED',
        'RESERVATION_KEY', v_reservation_key,
        'RESERVATION_TTL_MINUTES', v_res_ttl_minutes
    )
)
WHERE ID = v_ruleLog_id;

END IF;

    

IF v_is_dry_run = 0 THEN

    
    SET @or_cols = 'PARENT_ORDER_ID, ORDER_TYPE, ORDER_ID, ORDER_REQUEST_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @or_sel  = 'co.PARENT_ORDER_ID, co.CLIENT_ORDER_TYPE, co.CHILD_ORDER_ID, co.CHILD_STATUS, CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_or_cluster = 1 THEN
        SET @or_cols = CONCAT(@or_cols, ', CLUSTER_ID');
        SET @or_sel  = CONCAT(@or_sel,  ', co.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_request_data (', @or_cols, ') ',
        'SELECT ', @or_sel, ' ',
        '  FROM tmp_child_orders co ',
        '  LEFT JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        ' WHERE r.ORDER_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SET @line_cols = 'WMS_ORDER_REQUEST_DATA_ID, ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, BATCH_ID, DISPLAY_OPERATOR_INSTRUCTION, ORDER_LINE_PROCESS_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @line_sel  = 'r.WMS_ORDER_REQUEST_DATA_ID, r.ORDER_ID, fm.ORDER_LINE_ID, fm.ARTICLE_ID, fm.QUANTITY, fm.BATCH_ID, fm.DISPLAY_OPERATOR_INSTRUCTION, ''PENDING'', CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_ol_cluster = 1 THEN
        SET @line_cols = CONCAT(@line_cols, ', CLUSTER_ID');
        SET @line_sel  = CONCAT(@line_sel,  ', fm.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_line_request_data (', @line_cols, ') ',
        'SELECT ', @line_sel, ' ',
        '  FROM tmp_final_map fm ',
        '  JOIN tmp_child_orders co ',
        '    ON co.PARENT_ORDER_ID = fm.PARENT_ORDER_ID ',
        '   AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE ',
        '   AND co.CLUSTER_ID = fm.CLUSTER_ID ',
        '   AND co.SPLIT_GROUP = fm.SPLIT_GROUP ',
        '  JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        '  LEFT JOIN wms_to_wcs_order_line_request_data lr ',
        '    ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID ',
        '   AND lr.ORDER_LINE_ID = fm.ORDER_LINE_ID ',
        ' WHERE lr.ORDER_LINE_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_final_map fm
    JOIN tmp_child_orders co
      ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
     AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
     AND co.CLUSTER_ID        = fm.CLUSTER_ID
     AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
    JOIN wms_to_wcs_order_request_data r
      ON r.ORDER_ID = co.CHILD_ORDER_ID
    LEFT JOIN wms_to_wcs_order_line_request_data lr
      ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID
     AND lr.ORDER_LINE_ID            = fm.ORDER_LINE_ID
    WHERE lr.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('DB_WRITE_MISSING_LINES=', v_missing_lines, ' (expected all tmp_final_map lines in DB)');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    
    SELECT COUNT(*) INTO v_cnt_db_child_lines
    FROM wms_to_wcs_order_line_request_data lr
    JOIN wms_to_wcs_order_request_data r
      ON r.WMS_ORDER_REQUEST_DATA_ID = lr.WMS_ORDER_REQUEST_DATA_ID
    JOIN tmp_child_orders co
      ON co.CHILD_ORDER_ID = r.ORDER_ID;

ELSE
    SET v_cnt_db_child_lines = 0;
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
CREATE TEMPORARY TABLE tmp_child_demand (
    ORDER_ID VARCHAR(180) NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    DEMAND_QTY BIGINT NOT NULL,
    PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, DEMAND_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_child_demand
SELECT
    co.CHILD_ORDER_ID AS ORDER_ID,
    fm.PARENT_ORDER_ID,
    fm.CLIENT_ORDER_TYPE,
    fm.CLUSTER_ID AS DEMAND_CLUSTER_ID,
    fm.ARTICLE_ID,
    fm.BATCH_ID,
    SUM(fm.QUANTITY) AS DEMAND_QTY
FROM tmp_final_map fm
JOIN tmp_child_orders co
  ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
 AND co.CLUSTER_ID        = fm.CLUSTER_ID
 AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
WHERE fm.IS_SUSPENDED_GROUP = 0
  AND fm.ARTICLE_ID IS NOT NULL
  AND fm.BATCH_ID IS NOT NULL
  AND fm.CLUSTER_ID <> 'NO_INVENTORY'
  AND co.CHILD_STATUS = 'PENDING'
GROUP BY co.CHILD_ORDER_ID, fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.ARTICLE_ID, fm.BATCH_ID;

IF (SELECT COUNT(*) FROM tmp_child_demand) > 0 THEN

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
    CREATE TEMPORARY TABLE tmp_res_need_clusters (
        ORDER_ID         VARCHAR(180) NOT NULL,
        ARTICLE_ID       VARCHAR(200) NOT NULL,
        BATCH_ID         VARCHAR(200) NOT NULL,
        CLUSTER_ID       VARCHAR(50)  NOT NULL,
        DEMAND_QTY       BIGINT NOT NULL,
        PRIORITY         INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,
        CLUSTER_SUPPLY   BIGINT NOT NULL,
        CUM_SUPPLY_PREV  BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID),
        KEY idx_need (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_need_clusters
        (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID, DEMAND_QTY, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_SUPPLY, CUM_SUPPLY_PREV)
    SELECT
        z.ORDER_ID,
        z.ARTICLE_ID,
        z.BATCH_ID,
        z.CLUSTER_ID,
        z.DEMAND_QTY,
        z.PRIORITY,
        z.SRC_CLUSTER_RANK,
        z.CLUSTER_SUPPLY,
        COALESCE(z.cum_supply_prev, 0) AS CUM_SUPPLY_PREV
    FROM (
        SELECT
            d.ORDER_ID,
            d.PARENT_ORDER_ID,
            d.CLIENT_ORDER_TYPE,
            d.DEMAND_CLUSTER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            d.DEMAND_QTY,

            cs.CLUSTER_ID,
            cs.SUPPLY_QTY AS CLUSTER_SUPPLY,

            CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END AS PRIORITY,
            COALESCE(bcs.SCORE_RANK, 999999) AS SRC_CLUSTER_RANK,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
            ) AS cum_supply,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_supply_prev

        FROM tmp_child_demand d
        JOIN tmp_cluster_supply cs
          ON cs.ARTICLE_ID = d.ARTICLE_ID
         AND cs.BATCH_ID   = d.BATCH_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = d.PARENT_ORDER_ID
         AND bcs.CLIENT_ORDER_TYPE = d.CLIENT_ORDER_TYPE
         AND bcs.CLUSTER_ID        = cs.CLUSTER_ID
    ) z
    WHERE COALESCE(z.cum_supply_prev, 0) < z.DEMAND_QTY;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
    CREATE TEMPORARY TABLE tmp_res_bins (
        ORDER_ID VARCHAR(180) NOT NULL,
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,

        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,

        AVAIL_QTY BIGINT NOT NULL,
        LAST_TS DATETIME(3) NULL,

        PRIORITY INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,

        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY idx_rank (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK),
        KEY (BIN_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_bins
    SELECT
        d.ORDER_ID,
        d.PARENT_ORDER_ID,
        d.CLIENT_ORDER_TYPE,
        d.DEMAND_CLUSTER_ID,

        ib.CLUSTER_ID AS SRC_CLUSTER_ID,
        ib.ARTICLE_ID,
        ib.BATCH_ID,
        ib.BIN_ID,
        ib.AISLE_NUMBER,

        ib.AVAIL_QTY,
        ib.LAST_TS,

        nc.PRIORITY,
        nc.SRC_CLUSTER_RANK
    FROM tmp_child_demand d
    JOIN tmp_res_need_clusters nc
      ON nc.ORDER_ID   = d.ORDER_ID
     AND nc.ARTICLE_ID = d.ARTICLE_ID
     AND nc.BATCH_ID   = d.BATCH_ID
    
    JOIN tmp_inv_bin ib
      ON ib.ARTICLE_ID = d.ARTICLE_ID
     AND ib.BATCH_ID   = d.BATCH_ID
     AND ib.CLUSTER_ID = nc.CLUSTER_ID
    WHERE ib.AVAIL_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
    CREATE TEMPORARY TABLE tmp_res_alloc_child (
        ORDER_ID VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY (BIN_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_alloc_child
    SELECT
        rb.ORDER_ID,
        rb.ARTICLE_ID,
        rb.BATCH_ID,
        rb.BIN_ID,
        rb.AISLE_NUMBER,
        rb.SRC_CLUSTER_ID,
        rb.RESERVED_QTY
    FROM (
        SELECT
            d.ORDER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            b.BIN_ID,
            b.AISLE_NUMBER,
            b.SRC_CLUSTER_ID,
            b.AVAIL_QTY,
            b.LAST_TS,
            d.DEMAND_QTY,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
            ) AS cum_avail,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_avail_prev,

            LEAST(
                b.AVAIL_QTY,
                GREATEST(d.DEMAND_QTY - COALESCE(
                    SUM(b.AVAIL_QTY) OVER (
                        PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                        ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                    ), 0
                ), 0)
            ) AS RESERVED_QTY

        FROM tmp_child_demand d
        JOIN tmp_res_bins b
          ON b.ORDER_ID   = d.ORDER_ID
         AND b.ARTICLE_ID = d.ARTICLE_ID
         AND b.BATCH_ID   = d.BATCH_ID
    ) rb
    WHERE rb.RESERVED_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
    CREATE TEMPORARY TABLE tmp_res_shortfall (
        ORDER_ID   VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        DEMAND_QTY BIGINT NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        SHORT_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_shortfall (ORDER_ID, ARTICLE_ID, BATCH_ID, DEMAND_QTY, RESERVED_QTY, SHORT_QTY)
    SELECT
        d.ORDER_ID,
        d.ARTICLE_ID,
        d.BATCH_ID,
        d.DEMAND_QTY,
        COALESCE(a.got,0) AS RESERVED_QTY,
        GREATEST(d.DEMAND_QTY - COALESCE(a.got,0), 0) AS SHORT_QTY
    FROM tmp_child_demand d
    LEFT JOIN (
        SELECT ORDER_ID, ARTICLE_ID, BATCH_ID, SUM(RESERVED_QTY) AS got
          FROM tmp_res_alloc_child
         GROUP BY ORDER_ID, ARTICLE_ID, BATCH_ID
    ) a
      ON a.ORDER_ID = d.ORDER_ID
     AND a.ARTICLE_ID = d.ARTICLE_ID
     AND a.BATCH_ID = d.BATCH_ID
    WHERE COALESCE(a.got,0) < d.DEMAND_QTY;

END IF;


	
    

    IF v_is_dry_run = 0 THEN

        UPDATE wms_to_wcs_order_level_pre_staged_data p
        JOIN tmp_parent_orders t
          ON t.PRE_STAGED_REQ_ID = p.WMS_ORDER_REQUEST_DATA_ID
        SET p.IS_STAGED = 1,
            p.UPDATED_TIMESTAMP = CURRENT_TIMESTAMP(3),
            p.UPDATED_BY = 'SPLIT-OPS-V6';
    END IF;

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='2',
           ORDERSPLIT_ENDTIME = NOW(),
           RULE_STATS = JSON_OBJECT(
               'RULE_ID', v_rule_id,
               'RULE_LOG_ID', v_ruleLog_id,
               'RUN_PRIORITY', v_run_priority,
               'DRY_RUN', v_is_dry_run,
               'RESERVATION_KEY', v_reservation_key,
               'PARENTS_FOUND', v_parent_cnt,
               'LINES_CONSIDERED', v_line_cnt,
               'CHILD_ORDERS_CREATED', v_child_cnt,
               'MAX_ORDER_LINES_PER_ORDER', v_max_lines,
               'MAX_QUANTITY_PER_ORDER', v_max_qty,
               'TOL_LINES', v_tol_lines,
               'TOL_QTY', v_tol_qty,
               'HARD_LINES', v_hard_lines,
               'HARD_QTY', v_hard_qty,
               'SUSPEND_SHORT_LINES', v_suspend_short_lines,
               'CATEGORY_DEFAULT', 'FOOD',
               'NAMING', 'PARENT_ORDER_ID parent; ORDER_ID child/sub; SUB_ORDER_ID NOT USED',
               'STATION_PREF', JSON_OBJECT(
                   'MODE_USED', v_station_mode,
                   'USER_STATION_CNT', v_user_station_cnt,
                   'STATION_BIAS_ENABLED', v_use_station_bias
               ),
               'VALIDATIONS', JSON_OBJECT(
                   'tmp_lines', v_cnt_lines,
                   'tmp_lines_cat', v_cnt_lines_cat,
                   'tmp_line_assign', v_cnt_line_assign,
                   'tmp_ranked_lines', v_cnt_ranked,
                   'tmp_final_map', v_cnt_final,
                   'db_child_lines', v_cnt_db_child_lines
               ),
               'SUPPLY_CAP', JSON_OBJECT(
                   'ENABLED', 1,
                   'NOTE', 'Allocator decrements per SKU/BATCH/CLUSTER; assigns dominant cluster; NO_INVENTORY lines suspended'
               ),
               'RESERVATION', JSON_OBJECT(
                   'TTL_MINUTES', v_res_ttl_minutes,
                   'BLOCKED_LOCATION_EXCLUDED', 1,
                   'AUDIT_GRANULARITY', 'ORDER_ID+SKU/BATCH+BIN'
               )
           )
     WHERE ID = v_ruleLog_id;

    

    COMMIT;
    DO RELEASE_LOCK(v_lock_key);

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
        DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
        DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
        DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
        DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
        DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
    END;


SELECT
    v_rule_id AS RULE_ID,
    v_ruleLog_id AS RULE_LOG_ID,
    v_reservation_key AS RESERVATION_KEY,
    v_parent_cnt AS PARENTS_PROCESSED,
    v_line_cnt AS LINES_CONSIDERED,
    v_child_cnt AS CHILD_ORDERS_CREATED;



END sp_main */$$
DELIMITER ;

/* Procedure structure for procedure `sp_split_orders_ops_v12` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_split_orders_ops_v12` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sp_split_orders_ops_v12`()
sp_main: BEGIN

    
    DECLARE v_max_lines INT DEFAULT 50;
    DECLARE v_max_qty   INT DEFAULT 500;
    DECLARE v_tol_lines INT DEFAULT 10;
    DECLARE v_tol_qty   INT DEFAULT 100;

    DECLARE v_hard_lines INT DEFAULT 60;
    DECLARE v_hard_qty   INT DEFAULT 600;
	
	DECLARE v_bucketK INT DEFAULT 1;
DECLARE v_bucket_primary_cluster VARCHAR(50) DEFAULT NULL;
DECLARE v_last_bucket_parent VARCHAR(100) DEFAULT NULL;
DECLARE v_last_bucket_cat    VARCHAR(100) DEFAULT NULL;


    DECLARE v_suspend_short_lines INT DEFAULT 0;  
    DECLARE v_res_ttl_minutes INT DEFAULT 30;

    
    DECLARE v_ruleLog_id BIGINT DEFAULT NULL;
    DECLARE v_rule_id BIGINT DEFAULT NULL;
    DECLARE v_rule_defination TEXT DEFAULT NULL;

    
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_lock_key VARCHAR(128) DEFAULT NULL;

    
    DECLARE v_reservation_key VARCHAR(64) DEFAULT NULL;

    
    DECLARE v_station_mode ENUM('FINAL','INITIAL') DEFAULT NULL;
    DECLARE v_user_station_cnt BIGINT DEFAULT 0;

    
    DECLARE v_run_priority ENUM('INITIAL','FINAL') DEFAULT 'FINAL';
    DECLARE v_is_dry_run INT DEFAULT 0;

    
    DECLARE v_parent_cnt BIGINT DEFAULT 0;
    DECLARE v_line_cnt BIGINT DEFAULT 0;
    DECLARE v_child_cnt BIGINT DEFAULT 0;

    
    DECLARE v_cnt_lines BIGINT DEFAULT 0;
    DECLARE v_cnt_lines_cat BIGINT DEFAULT 0;
    DECLARE v_cnt_line_assign BIGINT DEFAULT 0;
    DECLARE v_cnt_ranked BIGINT DEFAULT 0;
    DECLARE v_cnt_final BIGINT DEFAULT 0;
    DECLARE v_cnt_db_child_lines BIGINT DEFAULT 0;

    DECLARE v_pre_lines BIGINT DEFAULT 0;
    DECLARE v_post_lines BIGINT DEFAULT 0;
    DECLARE v_pre_qty BIGINT DEFAULT 0;
    DECLARE v_post_qty BIGINT DEFAULT 0;
    DECLARE v_missing_lines BIGINT DEFAULT 0;

    DECLARE v_errmsg TEXT DEFAULT '';

    
    DECLARE v_has_or_cluster INT DEFAULT 0;
    DECLARE v_has_ol_cluster INT DEFAULT 0;

    DECLARE v_has_reco_col INT DEFAULT 0;   
    DECLARE v_has_reco1 INT DEFAULT 0;      
    DECLARE v_has_reco2 INT DEFAULT 0;      
    DECLARE v_has_reco1_alt INT DEFAULT 0;  
    DECLARE v_has_reco2_alt INT DEFAULT 0;  

    DECLARE v_has_hw_station INT DEFAULT 0;
    DECLARE v_has_hw_wave_status INT DEFAULT 0;

    
    DECLARE v_sku   VARCHAR(200) DEFAULT NULL;
    DECLARE v_batch VARCHAR(200) DEFAULT NULL;

    DECLARE v_rn INT DEFAULT 0;
    DECLARE v_maxrn INT DEFAULT 0;

    DECLARE v_line_parent VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_cat    VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_id     VARCHAR(36)  DEFAULT NULL;
    DECLARE v_line_qty    INT DEFAULT 0;

    DECLARE v_pick_cluster VARCHAR(50) DEFAULT NULL;

    DECLARE v_need BIGINT DEFAULT 0;
    DECLARE v_total_rem BIGINT DEFAULT 0;

    DECLARE v_crn INT DEFAULT 0;
    DECLARE v_cmax INT DEFAULT 0;
    DECLARE v_cur_cluster VARCHAR(50) DEFAULT NULL;
    DECLARE v_cur_rem BIGINT DEFAULT 0;
    DECLARE v_alloc BIGINT DEFAULT 0;

    
    DECLARE v_balance_mode INT DEFAULT 1;   
    DECLARE v_k1_pool INT DEFAULT 3;        

    
    DECLARE v_use_station_bias INT DEFAULT 0;   
    DECLARE v_near_aisle_window INT DEFAULT 1;  
    DECLARE v_min_pref_aisle INT DEFAULT NULL;
    DECLARE v_max_pref_aisle INT DEFAULT NULL;

    DECLARE v_total_lines_all BIGINT DEFAULT 0;
    DECLARE v_total_qty_all BIGINT DEFAULT 0;
    DECLARE v_total_lines_pickable BIGINT DEFAULT 0;
    DECLARE v_total_qty_pickable BIGINT DEFAULT 0;
    DECLARE v_alloc_qty_total BIGINT DEFAULT 0;
    DECLARE v_alloc_lines_total BIGINT DEFAULT 0;
    
	    
    DECLARE v_tmp_user_stations_ready INT DEFAULT 0;
        
    DECLARE v_lock_wait_seconds INT DEFAULT -1;

    
    DECLARE v_station_pref_consumed INT DEFAULT 0;

    
    DECLARE v_job_id BIGINT DEFAULT NULL;
    DECLARE v_job_rule_id BIGINT DEFAULT NULL;
    DECLARE v_job_priority ENUM('INITIAL','FINAL') DEFAULT NULL;



    
       
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;

        
        IF v_rule_id IS NOT NULL
           AND v_station_mode IS NOT NULL
           AND v_user_station_cnt > 0
           AND v_tmp_user_stations_ready = 1
        THEN
            UPDATE picklist_split_station_pref p
            JOIN tmp_user_stations t
              ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
            SET p.IS_PROCESSED = 0
            WHERE p.RULE_ID = v_rule_id
              AND p.PRIORITY = v_station_mode
              AND p.IS_PROCESSED = 1;
        END IF;

        
        IF v_ruleLog_id IS NOT NULL THEN
            UPDATE picklist_split_order_master
               SET IS_PROCESSED = '0',
                   ORDERSPLIT_ENDTIME = NOW()
             WHERE ID = v_ruleLog_id;
        END IF;

        
        
DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;

DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;       
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;     
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;      

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_final_map;

DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2;

DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;

DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;

DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc_sum;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster_weight;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_group_flags;


        
        IF v_lock_ok = 1 AND v_lock_key IS NOT NULL THEN
            DO RELEASE_LOCK(v_lock_key);
        END IF;

        RESIGNAL;
    END;


    

    SET v_max_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_ORDER_LINES_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_lines
    );

    SET v_max_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_QUANTITY_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_qty
    );

    SET v_near_aisle_window = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_NEAR_AISLE_WINDOW' AND IS_ACTIVE = 1
          LIMIT 1),
        v_near_aisle_window
    );
    SET v_near_aisle_window = GREATEST(v_near_aisle_window, 0);

    SET v_tol_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_lines
    );

    SET v_tol_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_QTY' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_qty
    );

    SET v_suspend_short_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'SUSPEND_SHORT_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_suspend_short_lines
    );

    SET v_res_ttl_minutes = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'RESERVATION_TTL_MINUTES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_res_ttl_minutes
    );

    SET v_balance_mode = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_BALANCE_MODE' AND IS_ACTIVE = 1
          LIMIT 1),
        v_balance_mode
    );

    SET v_k1_pool = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_K1_POOL' AND IS_ACTIVE = 1
          LIMIT 1),
        v_k1_pool
    );
    SET v_k1_pool = GREATEST(v_k1_pool, 1);

        
    SET v_max_lines = GREATEST(v_max_lines, 1);
    SET v_max_qty   = GREATEST(v_max_qty,   1);
    SET v_tol_lines = GREATEST(v_tol_lines, 0);
    SET v_tol_qty   = GREATEST(v_tol_qty,   0);

    SET v_hard_lines = v_max_lines + v_tol_lines;
    SET v_hard_qty   = v_max_qty   + v_tol_qty;


    

    SELECT COUNT(*) INTO v_has_or_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_ol_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_line_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_reco_col
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'RECOMMENDATION';

    SELECT COUNT(*) INTO v_has_reco1
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_1';

    SELECT COUNT(*) INTO v_has_reco2
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_2';

    SELECT COUNT(*) INTO v_has_reco1_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_1';

    SELECT COUNT(*) INTO v_has_reco2_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_2';

    SELECT COUNT(*) INTO v_has_hw_station
      FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master';

    SELECT COUNT(*) INTO v_has_hw_wave_status
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master'
       AND COLUMN_NAME  = 'wave_status';

          

    job_pick: LOOP

        SET v_job_id = NULL;
        SET v_job_rule_id = NULL;
        SET v_job_priority = NULL;

        
        SELECT
            ID,
            RULE_ID,
            CASE
                WHEN COALESCE(NULLIF(PRIORITY,''),'FINAL') IN ('FINAL','INITIAL')
                    THEN COALESCE(NULLIF(PRIORITY,''),'FINAL')
                ELSE 'FINAL'
            END
          INTO v_job_id, v_job_rule_id, v_job_priority
        FROM picklist_split_order_master
        WHERE IS_PROCESSED = '0'
        ORDER BY ID
        LIMIT 1;

        IF v_job_id IS NULL OR v_job_rule_id IS NULL THEN

    
    SET @reco1_cluster_json := JSON_ARRAY(
        JSON_OBJECT(
            'CLUSTER_ID',  'NA',
            'STATION_ID',  '0',
            'STATION_CNT', 0,
            'ORDER_LINES', 0,
            '%_LINES',     0.00,
            'ORDER_QTY',   0,
            '%_QTY',       0.00
        )
    );

    SET @reco2_cluster_json := @reco1_cluster_json;

    SET @dummy_master_reco := JSON_OBJECT(
        'RECOMMENDATION_1_ALL_STATIONS',          CAST(@reco1_cluster_json AS JSON),
        'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

        'STATION_PREF_MODE', NULL,
        'USER_SELECTED_STATIONS', '',
        'RULE_ID', NULL,
        'RULE_LOG_ID', NULL,
        'TOTAL_INITIAL_ORDERS', 0,
        'TOTAL_SPLIT_ORDERS',  0,

        'INITIAL_ORDER_LINES', 0,
        'AFTER_ALLOCATION_ORDER_LINES', 0,
        'TOTAL_LINES_PICKABLE', 0,

        'TOTAL_QTY_ALL', 0,
        'TOTAL_QTY_PICKABLE', 0,
        'ALLOC_QTY_TOTAL', 0,
        'ALLOC_LINES_TOTAL', 0,

        'NOTES', JSON_OBJECT(
            'PARENT_FIELD', 'PARENT_ORDER_ID',
            'CHILD_FIELD',  'ORDER_ID',
            'SUB_ORDER_ID', 'NOT_USED',
            'RESERVATION_KEY', '',
            'RESERVATION_TTL_MINUTES', 0,
            'DUMMY', 1
        )
    );

    
    SELECT
        'NO_RULE_TO_PROCESS' AS STATUS,
        CAST(@reco1_cluster_json AS JSON) AS recommendation_1,
        CAST(@reco2_cluster_json AS JSON) AS recommendation_2,
        CAST(@dummy_master_reco  AS JSON) AS RECOMMENDATION;

    LEAVE sp_main;
END IF;


        
        SET v_lock_key = CONCAT('SPLIT_CLUSTER_', v_job_rule_id);
        SELECT GET_LOCK(v_lock_key, v_lock_wait_seconds) INTO v_lock_ok;

        IF v_lock_ok IS NULL THEN
            SET v_errmsg = CONCAT('GET_LOCK_ERROR: key=', v_lock_key);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        ELSEIF v_lock_ok = 0 THEN
            
            SET v_errmsg = CONCAT('Split job already running (lock timeout) for RULE_ID=', v_job_rule_id);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        END IF;

        
        START TRANSACTION;

        SELECT
            ID,
            RULE_ID,
            v_job_priority
          INTO v_ruleLog_id, v_rule_id, v_run_priority
        FROM picklist_split_order_master
        WHERE ID = v_job_id
          AND IS_PROCESSED = '0'
        FOR UPDATE SKIP LOCKED;

        
        IF v_ruleLog_id IS NULL OR v_rule_id IS NULL THEN
            ROLLBACK;
            DO RELEASE_LOCK(v_lock_key);
            SET v_lock_ok = 0;
            ITERATE job_pick;
        END IF;

        LEAVE job_pick;
    END LOOP;

    
    SET v_is_dry_run = CASE WHEN v_run_priority = 'INITIAL' THEN 1 ELSE 0 END;

    
    IF v_is_dry_run = 1 THEN
        SET v_balance_mode = 0;
        SET v_k1_pool      = 1;
    END IF;



        

    SELECT FILTER_CONDITION
      INTO v_rule_defination
    FROM pick_rule_master
    WHERE PICK_RULE_ID = v_rule_id
    LIMIT 1;

    IF v_rule_defination IS NULL OR LENGTH(v_rule_defination) < 3 THEN
        
        UPDATE picklist_split_order_master
           SET IS_PROCESSED = '2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        COMMIT;
        DO RELEASE_LOCK(v_lock_key);

        SELECT 'NO_RULE_DEFINITION_FOUND' AS STATUS, v_rule_id AS RULE_ID;
        LEAVE sp_main;
    END IF;

    
    SET v_rule_defination = LEFT(v_rule_defination, LENGTH(v_rule_defination)-1);


    

SET v_station_mode = NULL;
SET v_user_station_cnt = 0;
SET v_station_pref_consumed = 0;   


IF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'FINAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'FINAL';
ELSEIF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'INITIAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'INITIAL';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
CREATE TEMPORARY TABLE tmp_user_stations (
    STATION_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (STATION_ID)
) ENGINE=INNODB;

SET v_tmp_user_stations_ready = 1;

IF v_station_mode IS NOT NULL THEN

    
    INSERT IGNORE INTO tmp_user_stations (STATION_ID)
    SELECT CAST(STATION_ID AS CHAR(50))
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND PRIORITY = v_station_mode
       AND IS_PROCESSED = 0
     ORDER BY STATION_ID
     FOR UPDATE;

    SELECT COUNT(*) INTO v_user_station_cnt FROM tmp_user_stations;

END IF;


SET v_use_station_bias =
    CASE
        WHEN v_is_dry_run = 0 AND v_user_station_cnt > 0 AND v_has_hw_station = 1 THEN 1
        ELSE 0
    END;



DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
CREATE TEMPORARY TABLE tmp_pref_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
CREATE TEMPORARY TABLE tmp_near_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_pref_clusters (CLUSTER_ID)
    SELECT DISTINCT CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.CLUSTER_ID IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
    CREATE TEMPORARY TABLE tmp_pref_aisle_num (
        AISLE_NUM INT NOT NULL,
        PRIMARY KEY (AISLE_NUM)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_pref_aisle_num (AISLE_NUM)
    SELECT DISTINCT
           CAST(
               NULLIF(
                   REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                   ''
               ) AS UNSIGNED
           ) AS AISLE_NUM
      FROM cluster_aisle_mapping cam
      JOIN tmp_pref_clusters pc
        ON pc.CLUSTER_ID = cam.CLUSTER_ID
     WHERE cam.AISLE_NUMBER IS NOT NULL;

    
    SELECT MIN(AISLE_NUM), MAX(AISLE_NUM)
      INTO v_min_pref_aisle, v_max_pref_aisle
      FROM tmp_pref_aisle_num;

    IF v_min_pref_aisle IS NOT NULL AND v_max_pref_aisle IS NOT NULL THEN

        
        INSERT IGNORE INTO tmp_near_clusters (CLUSTER_ID)
        SELECT DISTINCT cam.CLUSTER_ID
          FROM cluster_aisle_mapping cam
         WHERE cam.CLUSTER_ID IS NOT NULL
           AND cam.AISLE_NUMBER IS NOT NULL
           AND CAST(
                   NULLIF(
                       REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                       ''
                   ) AS UNSIGNED
               ) BETWEEN (v_min_pref_aisle - v_near_aisle_window)
                   AND (v_max_pref_aisle + v_near_aisle_window);

        
        DELETE n
          FROM tmp_near_clusters n
          JOIN tmp_pref_clusters p
            ON p.CLUSTER_ID = n.CLUSTER_ID;

    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;

END IF;




DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
CREATE TEMPORARY TABLE tmp_parent_orders (
    PRE_STAGED_REQ_ID BIGINT NOT NULL,
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    ORDER_TYPE        VARCHAR(100) NOT NULL,
    PRIMARY KEY (PRE_STAGED_REQ_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;


IF v_rule_defination IS NULL OR LENGTH(TRIM(v_rule_defination)) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULE_DEFINITION_EMPTY';
END IF;

SET @sql = CONCAT(
    'INSERT INTO tmp_parent_orders (PRE_STAGED_REQ_ID, PARENT_ORDER_ID, ORDER_TYPE)
     SELECT WMS_ORDER_REQUEST_DATA_ID,
            PARENT_ORDER_ID,
            COALESCE(NULLIF(PICKING_TYPE, ''''), NULLIF(ORDER_CATEGORY, ''''), ''PICK'') AS ORDER_TYPE
       FROM wms_to_wcs_order_level_pre_staged_data
      WHERE IFNULL(IS_STAGED,0) = 0
        AND PARENT_ORDER_ID IN (', v_rule_defination, ')'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT COUNT(*) INTO v_parent_cnt FROM tmp_parent_orders;

IF v_parent_cnt = 0 THEN

    
    IF v_station_pref_consumed = 1
       AND v_rule_id IS NOT NULL
       AND v_station_mode IS NOT NULL
       AND v_tmp_user_stations_ready = 1
    THEN
        UPDATE picklist_split_station_pref p
        JOIN tmp_user_stations t
          ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
        SET p.IS_PROCESSED = 0
        WHERE p.RULE_ID = v_rule_id
          AND p.PRIORITY = v_station_mode
          AND p.IS_PROCESSED = 1;

        SET v_station_pref_consumed = 0;
    END IF;

    
    
    SET v_line_cnt = 0;

    
    IF v_reservation_key IS NULL OR v_reservation_key = '' THEN
        SET v_reservation_key = CONCAT('SPLIT_', COALESCE(v_ruleLog_id,0), '_', REPLACE(UUID(),'-',''));
    END IF;

    SET @reco1_cluster_json := JSON_ARRAY(
        JSON_OBJECT(
            'CLUSTER_ID',  'NA',
            'STATION_ID',  '0',
            'STATION_CNT', 0,
            'ORDER_LINES', 0,
            '%_LINES',     0.00,
            'ORDER_QTY',   0,
            '%_QTY',       0.00
        )
    );
    SET @reco2_cluster_json := @reco1_cluster_json;

    SET @dummy_user_selected := '';
    IF v_tmp_user_stations_ready = 1 THEN
        SELECT COALESCE(GROUP_CONCAT(STATION_ID ORDER BY STATION_ID SEPARATOR ','), '')
          INTO @dummy_user_selected
          FROM tmp_user_stations;
    END IF;

    SET @dummy_master_reco := JSON_OBJECT(
        'RECOMMENDATION_1_ALL_STATIONS',          CAST(@reco1_cluster_json AS JSON),
        'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

        'STATION_PREF_MODE', v_station_mode,
        'USER_SELECTED_STATIONS', @dummy_user_selected,
        'RULE_ID', v_rule_id,
        'RULE_LOG_ID', v_ruleLog_id,
        'TOTAL_INITIAL_ORDERS', v_parent_cnt,
        'TOTAL_SPLIT_ORDERS',  0,

        'INITIAL_ORDER_LINES', v_line_cnt,
        'AFTER_ALLOCATION_ORDER_LINES', 0,
        'TOTAL_LINES_PICKABLE', 0,

        'TOTAL_QTY_ALL', 0,
        'TOTAL_QTY_PICKABLE', 0,
        'ALLOC_QTY_TOTAL', 0,
        'ALLOC_LINES_TOTAL', 0,

        'NOTES', JSON_OBJECT(
            'PARENT_FIELD', 'PARENT_ORDER_ID',
            'CHILD_FIELD',  'ORDER_ID',
            'SUB_ORDER_ID', 'NOT_USED',
            'RESERVATION_KEY', COALESCE(v_reservation_key,''),
            'RESERVATION_TTL_MINUTES', v_res_ttl_minutes,
            'DUMMY', 1,
            'REASON', 'NO_PARENTS_TO_SPLIT'
        )
    );

    
    IF v_ruleLog_id IS NOT NULL THEN

        IF v_has_reco1 = 1 OR v_has_reco1_alt = 1 THEN
            UPDATE picklist_split_order_master
               SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

        IF v_has_reco2 = 1 OR v_has_reco2_alt = 1 THEN
            UPDATE picklist_split_order_master
               SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

        IF v_has_reco_col = 1 THEN
            UPDATE picklist_split_order_master
               SET RECOMMENDATION = CAST(@dummy_master_reco AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

    END IF;

    
    UPDATE picklist_split_order_master
       SET IS_PROCESSED = '2',
           ORDERSPLIT_ENDTIME = NOW()
     WHERE ID = v_ruleLog_id;

    COMMIT;

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
    END;

    DO RELEASE_LOCK(v_lock_key);

    SELECT 'NO_PARENTS_TO_SPLIT' AS STATUS, v_rule_id AS RULE_ID;
    LEAVE sp_main;
END IF;


UPDATE picklist_split_order_master
   SET IS_PROCESSED = '1',
       ORDERSPLIT_STARTTIME = NOW()
 WHERE ID = v_ruleLog_id
   AND IS_PROCESSED = '0';

IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULELOG_NOT_IN_STARTABLE_STATE';
END IF;


IF v_station_mode IS NOT NULL
   AND v_user_station_cnt > 0
   AND v_tmp_user_stations_ready = 1
THEN
    UPDATE picklist_split_station_pref p
    JOIN tmp_user_stations t
      ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
    SET p.IS_PROCESSED = 1
    WHERE p.RULE_ID = v_rule_id
      AND p.PRIORITY = v_station_mode
      AND p.IS_PROCESSED = 0;

    SET v_station_pref_consumed = 1;
END IF;


SET v_reservation_key = CONCAT('SPLIT_', v_ruleLog_id, '_', REPLACE(UUID(),'-',''));



DROP TEMPORARY TABLE IF EXISTS tmp_lines;
CREATE TEMPORARY TABLE tmp_lines (
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
    ARTICLE_ID      VARCHAR(200) NULL,
    BATCH_ID        VARCHAR(200) NULL,
    QUANTITY        INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_lines
SELECT
    l.PARENT_ORDER_ID,
    l.ORDER_LINE_ID,
    l.ARTICLE_ID,
    l.BATCH_ID,
    l.QUANTITY,
    l.DISPLAY_OPERATOR_INSTRUCTION
FROM wms_to_wcs_order_line_level_pre_staged_data l
JOIN tmp_parent_orders p
  ON p.PARENT_ORDER_ID = l.PARENT_ORDER_ID
WHERE IFNULL(l.ORDER_LINE_PROCESS_STATUS,'PENDING') <> 'DELETED';

SELECT COUNT(*) INTO v_line_cnt FROM tmp_lines;

IF v_line_cnt = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'NO_LINES_FOUND_FOR_SELECTED_PARENTS';
END IF;



    

    DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
    CREATE TEMPORARY TABLE tmp_line_category (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (ARTICLE_ID),
        KEY (CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_category (ARTICLE_ID, CLIENT_ORDER_TYPE)
    SELECT
        al.ARTICLE_ID,
        COALESCE(NULLIF(cm.CLIENT_ORDER_TYPE,''), 'FOOD') AS CLIENT_ORDER_TYPE
    FROM (SELECT DISTINCT ARTICLE_ID FROM tmp_lines WHERE ARTICLE_ID IS NOT NULL) al
    LEFT JOIN sku_master sm
      ON sm.SKU_ID = al.ARTICLE_ID
    LEFT JOIN category_master cm
      ON cm.CATEGORY_ID = sm.CATEGORY;

    DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
    CREATE TEMPORARY TABLE tmp_lines_cat (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines_cat
    SELECT
        tl.PARENT_ORDER_ID,
        COALESCE(lc.CLIENT_ORDER_TYPE, 'FOOD') AS CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION
    FROM tmp_lines tl
    LEFT JOIN tmp_line_category lc
      ON lc.ARTICLE_ID = tl.ARTICLE_ID;

    
    SELECT COUNT(*) INTO v_cnt_lines     FROM tmp_lines;
    SELECT COUNT(*) INTO v_cnt_lines_cat FROM tmp_lines_cat;

    IF v_cnt_lines_cat <> v_cnt_lines THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_CATEGORY: tmp_lines=', v_cnt_lines,
                              ', tmp_lines_cat=', v_cnt_lines_cat);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

 


DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
CREATE TEMPORARY TABLE tmp_aisle_cluster_raw (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER, CLUSTER_ID),
    KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster_raw (AISLE_NUMBER, CLUSTER_ID)
SELECT DISTINCT AISLE_NUMBER, CLUSTER_ID
  FROM cluster_aisle_mapping
 WHERE AISLE_NUMBER IS NOT NULL
   AND CLUSTER_ID IS NOT NULL;

IF (SELECT COUNT(*) FROM tmp_aisle_cluster_raw) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: cluster_aisle_mapping has no AISLE_NUMBER->CLUSTER_ID rows';
END IF;

IF EXISTS (
    SELECT 1
      FROM (
            SELECT AISLE_NUMBER, COUNT(*) AS c
              FROM tmp_aisle_cluster_raw
             GROUP BY AISLE_NUMBER
            HAVING c > 1
      ) X
    LIMIT 1
) THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: AISLE_NUMBER maps to multiple CLUSTER_ID in cluster_aisle_mapping';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
CREATE TEMPORARY TABLE tmp_aisle_cluster (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster (AISLE_NUMBER, CLUSTER_ID)
SELECT AISLE_NUMBER, CLUSTER_ID
  FROM tmp_aisle_cluster_raw;




DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
CREATE TEMPORARY TABLE tmp_sku_global (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_global
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_lines_cat
 WHERE ARTICLE_ID IS NOT NULL AND BATCH_ID IS NOT NULL;

DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
CREATE TEMPORARY TABLE tmp_inv_bin (
    BIN_ID INT NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    AVAIL_QTY BIGINT NOT NULL,
    LAST_TS DATETIME(3) NULL,
    PRIMARY KEY (BIN_ID, ARTICLE_ID, BATCH_ID),

    KEY (ARTICLE_ID, BATCH_ID),
    KEY (CLUSTER_ID),
    KEY (AISLE_NUMBER),

    
    KEY idx_ab_cluster (ARTICLE_ID, BATCH_ID, CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_inv_bin (BIN_ID, ARTICLE_ID, BATCH_ID, AISLE_NUMBER, CLUSTER_ID, AVAIL_QTY, LAST_TS)
SELECT
    lim.BIN_ID,
    lim.ARTICLE_ID,
    lim.BATCH_ID,
    lmst.AISLE_NUMBER,
    ac.CLUSTER_ID,
    GREATEST(
        CAST(SUM(GREATEST(lim.QUANTITY - lim.VIRTUAL_QUANTITY_TO_PICK, 0)) AS SIGNED),
        0
    ) AS AVAIL_QTY,
    MAX(lim.UPDATED_TIMESTAMP) AS LAST_TS
FROM live_inventory_master lim
JOIN tmp_sku_global sg
  ON sg.ARTICLE_ID = lim.ARTICLE_ID
 AND sg.BATCH_ID   = lim.BATCH_ID
JOIN store_bin_master sb
  ON sb.BIN_ID = lim.BIN_ID
JOIN location_master lmst
  ON lmst.LOCATION_ID = sb.LOCATION_ID
LEFT JOIN location_block_master lb
  ON lb.LOCATION_ID = sb.LOCATION_ID
JOIN tmp_aisle_cluster ac
  ON ac.AISLE_NUMBER = lmst.AISLE_NUMBER
WHERE lim.IS_ACTIVE = 1
  AND lim.BIN_ID IS NOT NULL
  AND lmst.AISLE_NUMBER IS NOT NULL
  AND lb.LOCATION_ID IS NULL
GROUP BY lim.BIN_ID, lim.ARTICLE_ID, lim.BATCH_ID, lmst.AISLE_NUMBER, ac.CLUSTER_ID
HAVING AVAIL_QTY > 0;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
CREATE TEMPORARY TABLE tmp_cluster_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply (ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY)
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUM(AVAIL_QTY) AS SUPPLY_QTY
  FROM tmp_inv_bin
 GROUP BY ARTICLE_ID, BATCH_ID, CLUSTER_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
CREATE TEMPORARY TABLE tmp_sku_total_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_SUPPLY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_total_supply
SELECT ARTICLE_ID, BATCH_ID, SUM(SUPPLY_QTY) AS TOTAL_SUPPLY
  FROM tmp_cluster_supply
 GROUP BY ARTICLE_ID, BATCH_ID;




DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
CREATE TEMPORARY TABLE tmp_final_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    CL_NUM     INT NULL,
    PRIMARY KEY (CLUSTER_ID),
    KEY (CL_NUM)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
CREATE TEMPORARY TABLE tmp_cluster_snap_map (
    SRC_CLUSTER_ID      VARCHAR(50) NOT NULL,
    SNAPPED_CLUSTER_ID  VARCHAR(50) NOT NULL,
    PRIMARY KEY (SRC_CLUSTER_ID),
    KEY (SNAPPED_CLUSTER_ID)
) ENGINE=INNODB;


DROP TEMPORARY TABLE IF EXISTS tmp_final_cluster_default;
CREATE TEMPORARY TABLE tmp_final_cluster_default (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_final_clusters (CLUSTER_ID, CL_NUM)
    SELECT
        pc.CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(pc.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS CL_NUM
    FROM tmp_pref_clusters pc
    WHERE pc.CLUSTER_ID IS NOT NULL;

    
    IF (SELECT COUNT(*) FROM tmp_final_clusters) = 0 THEN
        SET v_use_station_bias = 0;
    END IF;

    
    IF v_use_station_bias = 1 THEN
        INSERT INTO tmp_final_cluster_default (CLUSTER_ID)
        SELECT fc.CLUSTER_ID
          FROM tmp_final_clusters fc
         ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
         LIMIT 1;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;
    CREATE TEMPORARY TABLE tmp_supply_clusters (
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        SRC_NUM        INT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID),
        KEY (SRC_NUM)
    ) ENGINE=INNODB;

    INSERT INTO tmp_supply_clusters (SRC_CLUSTER_ID, SRC_NUM)
    SELECT DISTINCT
        cs.CLUSTER_ID AS SRC_CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(cs.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS SRC_NUM
    FROM tmp_cluster_supply cs;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    CREATE TEMPORARY TABLE tmp_snap_candidates (
        SRC_CLUSTER_ID   VARCHAR(50) NOT NULL,
        CAND_CLUSTER_ID  VARCHAR(50) NOT NULL,
        RN               INT NOT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID, RN),
        KEY (CAND_CLUSTER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_snap_candidates (SRC_CLUSTER_ID, CAND_CLUSTER_ID, RN)
    SELECT
        sc.SRC_CLUSTER_ID,
        fc.CLUSTER_ID AS CAND_CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY sc.SRC_CLUSTER_ID
            ORDER BY
                ABS(COALESCE(fc.CL_NUM,0) - COALESCE(sc.SRC_NUM,0)),
                
                CASE WHEN COALESCE(fc.CL_NUM,0) >= COALESCE(sc.SRC_NUM,0) THEN 0 ELSE 1 END,
                COALESCE(fc.CL_NUM,0),
                fc.CLUSTER_ID
        ) AS RN
    FROM tmp_supply_clusters sc
    JOIN tmp_final_clusters fc
      ON 1=1;

    
    INSERT IGNORE INTO tmp_cluster_snap_map (SRC_CLUSTER_ID, SNAPPED_CLUSTER_ID)
    SELECT
        sc.SRC_CLUSTER_ID,
        CASE
            WHEN fc_same.CLUSTER_ID IS NOT NULL THEN sc.SRC_CLUSTER_ID
            ELSE COALESCE(c.CAND_CLUSTER_ID, d.CLUSTER_ID)
        END AS SNAPPED_CLUSTER_ID
    FROM tmp_supply_clusters sc
    LEFT JOIN tmp_final_clusters fc_same
      ON fc_same.CLUSTER_ID = sc.SRC_CLUSTER_ID
    LEFT JOIN tmp_snap_candidates c
      ON c.SRC_CLUSTER_ID = sc.SRC_CLUSTER_ID
     AND c.RN = 1
    LEFT JOIN tmp_final_cluster_default d
      ON 1=1;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;

END IF;


    

    DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
    CREATE TEMPORARY TABLE tmp_line_cluster_candidates (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID VARCHAR(36) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        CLUSTER_ID VARCHAR(50)  NOT NULL,
        SUPPLY_QTY BIGINT NOT NULL,
        C_RANK INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, CLUSTER_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, C_RANK)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_cluster_candidates
    SELECT
        lc.PARENT_ORDER_ID,
        lc.CLIENT_ORDER_TYPE,
        lc.ORDER_LINE_ID,
        lc.ARTICLE_ID,
        lc.BATCH_ID,
        cs.CLUSTER_ID,
        cs.SUPPLY_QTY,
        ROW_NUMBER() OVER (
            PARTITION BY lc.PARENT_ORDER_ID, lc.CLIENT_ORDER_TYPE, lc.ORDER_LINE_ID
            ORDER BY cs.SUPPLY_QTY DESC, cs.CLUSTER_ID
        ) AS C_RANK
    FROM tmp_lines_cat lc
    JOIN tmp_cluster_supply cs
      ON cs.ARTICLE_ID = lc.ARTICLE_ID
     AND cs.BATCH_ID   = lc.BATCH_ID;

    DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
    CREATE TEMPORARY TABLE tmp_line_assign (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID VARCHAR(36) NOT NULL,
        ARTICLE_ID VARCHAR(200) NULL,
        BATCH_ID   VARCHAR(200) NULL,
        QUANTITY   INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

        ASSIGNED_CLUSTER_ID VARCHAR(50) NULL,
        ASSIGNED_RANK INT NOT NULL DEFAULT 0,

        SHORT_FLAG_SCHEMA INT NOT NULL DEFAULT 0,
        SHORT_FLAG_SUPPLY INT NOT NULL DEFAULT 0,
        SHORT_FLAG INT NOT NULL DEFAULT 0,

        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_assign
    SELECT
        lc.PARENT_ORDER_ID,
        lc.CLIENT_ORDER_TYPE,
        lc.ORDER_LINE_ID,
        lc.ARTICLE_ID,
        lc.BATCH_ID,
        lc.QUANTITY,
        lc.DISPLAY_OPERATOR_INSTRUCTION,
        NULL, 0,
        0, 0, 0
    FROM tmp_lines_cat lc;

    UPDATE tmp_line_assign la
    LEFT JOIN tmp_sku_total_supply ts
      ON ts.ARTICLE_ID = la.ARTICLE_ID
     AND ts.BATCH_ID   = la.BATCH_ID
    SET la.SHORT_FLAG_SCHEMA = CASE
        WHEN la.ARTICLE_ID IS NULL OR la.BATCH_ID IS NULL THEN 1
        WHEN ts.TOTAL_SUPPLY IS NULL THEN 1
        ELSE 0
    END;

    SELECT COUNT(*) INTO v_cnt_line_assign FROM tmp_line_assign;
    IF v_cnt_line_assign <> v_cnt_lines_cat THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_ASSIGN: tmp_lines_cat=', v_cnt_lines_cat,
                              ', tmp_line_assign=', v_cnt_line_assign);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
CREATE TEMPORARY TABLE tmp_bucket_k (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    TOTAL_LINES         BIGINT NOT NULL,
    TOTAL_QTY           BIGINT NOT NULL,
    K                   INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_k (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, TOTAL_LINES, TOTAL_QTY, K)
SELECT
    la.PARENT_ORDER_ID,
    la.CLIENT_ORDER_TYPE,
    COUNT(*) AS TOTAL_LINES,
    COALESCE(SUM(la.QUANTITY),0) AS TOTAL_QTY,
    GREATEST(
        1,
        IF(v_max_lines > 0, CEIL(COUNT(*) / v_max_lines), 1),
        IF(v_max_qty   > 0, CEIL(COALESCE(SUM(la.QUANTITY),0) / v_max_qty), 1)
    ) AS K
FROM tmp_line_assign la
GROUP BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
CREATE TEMPORARY TABLE tmp_bucket_cluster_score (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    BEST_LINE_CNT       BIGINT NOT NULL,
    BEST_QTY_FIT        BIGINT NOT NULL,
    SCORE               DECIMAL(30,0) NOT NULL,
    SCORE_RANK          INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SCORE_RANK),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_cluster_score
SELECT
    x.PARENT_ORDER_ID,
    x.CLIENT_ORDER_TYPE,
    x.CLUSTER_ID,
    x.BEST_LINE_CNT,
    x.BEST_QTY_FIT,
    (x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT AS SCORE,
    ROW_NUMBER() OVER (
        PARTITION BY x.PARENT_ORDER_ID, x.CLIENT_ORDER_TYPE
        ORDER BY ((x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT) DESC, x.CLUSTER_ID
    ) AS SCORE_RANK
FROM (
    SELECT
        c.PARENT_ORDER_ID,
        c.CLIENT_ORDER_TYPE,
        c.CLUSTER_ID,
        SUM(CASE WHEN c.C_RANK = 1 THEN 1 ELSE 0 END) AS BEST_LINE_CNT,
        SUM(CASE
                WHEN c.C_RANK = 1 THEN LEAST(c.SUPPLY_QTY, la.QUANTITY)
                ELSE 0
            END) AS BEST_QTY_FIT
    FROM tmp_line_cluster_candidates c
    JOIN tmp_line_assign la
      ON la.PARENT_ORDER_ID = c.PARENT_ORDER_ID
     AND la.CLIENT_ORDER_TYPE = c.CLIENT_ORDER_TYPE
     AND la.ORDER_LINE_ID = c.ORDER_LINE_ID
    GROUP BY c.PARENT_ORDER_ID, c.CLIENT_ORDER_TYPE, c.CLUSTER_ID
) X;

DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
CREATE TEMPORARY TABLE tmp_allowed_clusters (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
SELECT
    s.PARENT_ORDER_ID,
    s.CLIENT_ORDER_TYPE,
    s.CLUSTER_ID
FROM tmp_bucket_cluster_score s
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
WHERE s.SCORE_RANK <= CASE
    WHEN v_balance_mode = 1 AND k.K = 1 THEN GREATEST(k.K, v_k1_pool)
    ELSE k.K
END;

IF (SELECT COUNT(*) FROM tmp_allowed_clusters) = 0 THEN
    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
      FROM tmp_bucket_cluster_score;
END IF;


IF v_use_station_bias = 1 THEN

    DELETE ac
      FROM tmp_allowed_clusters ac
      LEFT JOIN tmp_final_clusters fc
        ON fc.CLUSTER_ID = ac.CLUSTER_ID
     WHERE fc.CLUSTER_ID IS NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
    CREATE TEMPORARY TABLE tmp_empty_buckets (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_empty_buckets (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    SELECT bk.PARENT_ORDER_ID, bk.CLIENT_ORDER_TYPE
      FROM tmp_bucket_k bk
      LEFT JOIN tmp_allowed_clusters ac2
        ON ac2.PARENT_ORDER_ID   = bk.PARENT_ORDER_ID
       AND ac2.CLIENT_ORDER_TYPE = bk.CLIENT_ORDER_TYPE
     WHERE ac2.PARENT_ORDER_ID IS NULL;

    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT eb.PARENT_ORDER_ID, eb.CLIENT_ORDER_TYPE, fc2.CLUSTER_ID
      FROM tmp_empty_buckets eb
      CROSS JOIN tmp_final_clusters fc2;

    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
CREATE TEMPORARY TABLE tmp_bucket_choice (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CHOSEN_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CHOSEN_CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_choice
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    MAX(CASE WHEN rn = 1 + MOD(bucket_hash, pool_cnt) THEN CLUSTER_ID END) AS CHOSEN_CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK, s.CLUSTER_ID
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
        ) AS pool_cnt,
        CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE)) AS bucket_hash
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
      AND s.SCORE_RANK <= v_k1_pool
) X
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;


INSERT IGNORE INTO tmp_bucket_choice (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CHOSEN_CLUSTER_ID)
SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK, s.CLUSTER_ID
        ) AS rn
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
) z
WHERE rn = 1;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_bucket_choice bc
    LEFT JOIN tmp_cluster_snap_map sm
      ON sm.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID
    SET bc.CHOSEN_CLUSTER_ID = COALESCE(sm.SNAPPED_CLUSTER_ID, bc.CHOSEN_CLUSTER_ID);
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
CREATE TEMPORARY TABLE tmp_final_first_cluster (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_final_first_cluster (CLUSTER_ID)
    SELECT fc.CLUSTER_ID
      FROM tmp_final_clusters fc
     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
     LIMIT 1;
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
CREATE TEMPORARY TABLE tmp_bucket_top_final (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_bucket_top_final (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
    FROM (
        SELECT
            s.PARENT_ORDER_ID,
            s.CLIENT_ORDER_TYPE,
            s.CLUSTER_ID,
            ROW_NUMBER() OVER (
                PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
                ORDER BY s.SCORE_RANK, s.CLUSTER_ID
            ) AS rn
        FROM tmp_bucket_cluster_score s
        JOIN tmp_final_clusters fcx
          ON fcx.CLUSTER_ID = s.CLUSTER_ID
    ) q
    WHERE rn = 1;
END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
CREATE TEMPORARY TABLE tmp_bucket_fallback (
    PARENT_ORDER_ID       VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE     VARCHAR(100) NOT NULL,
    FALLBACK_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (FALLBACK_CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    INSERT INTO tmp_bucket_fallback (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, FALLBACK_CLUSTER_ID)
    SELECT
        k.PARENT_ORDER_ID,
        k.CLIENT_ORDER_TYPE,
        COALESCE(bc.CHOSEN_CLUSTER_ID, topf.CLUSTER_ID, firstf.CLUSTER_ID) AS FALLBACK_CLUSTER_ID
    FROM tmp_bucket_k k
    LEFT JOIN tmp_bucket_choice bc
      ON bc.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND bc.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    LEFT JOIN tmp_bucket_top_final topf
      ON topf.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND topf.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    CROSS JOIN tmp_final_first_cluster firstf;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
CREATE TEMPORARY TABLE tmp_parent_cluster_load (
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    CLUSTER_ID        VARCHAR(50)  NOT NULL,
    LINE_CNT          BIGINT NOT NULL DEFAULT 0,
    QTY_CNT           BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
) ENGINE=INNODB;


     

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
CREATE TEMPORARY TABLE tmp_cluster_supply_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    REM_QTY    BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply_rem
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY, SUPPLY_QTY
  FROM tmp_cluster_supply;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
CREATE TEMPORARY TABLE tmp_sku_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_REM  BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_rem (ARTICLE_ID, BATCH_ID, TOTAL_REM)
SELECT ARTICLE_ID, BATCH_ID, SUM(REM_QTY) AS TOTAL_REM
  FROM tmp_cluster_supply_rem
 GROUP BY ARTICLE_ID, BATCH_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
CREATE TEMPORARY TABLE tmp_line_alloc (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NOT NULL,
    BATCH_ID            VARCHAR(200) NOT NULL,
    SRC_CLUSTER_ID      VARCHAR(50)  NOT NULL,
    ALLOC_QTY           BIGINT       NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, SRC_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (SRC_CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
CREATE TEMPORARY TABLE tmp_sku_queue (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_sku_queue
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_line_assign
 WHERE SHORT_FLAG_SCHEMA = 0
   AND ARTICLE_ID IS NOT NULL
   AND BATCH_ID IS NOT NULL;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
CREATE TEMPORARY TABLE tmp_sku_line_queue (
    RN INT NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    ORDER_LINE_ID VARCHAR(36) NOT NULL,
    QUANTITY INT NOT NULL,
    PRIMARY KEY (RN),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (ORDER_LINE_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
CREATE TEMPORARY TABLE tmp_line_cluster_seq (
    RN INT NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    REM_QTY BIGINT NOT NULL,
    PRIMARY KEY (RN),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

sku_loop: WHILE EXISTS (SELECT 1 FROM tmp_sku_queue LIMIT 1) DO

    SELECT ARTICLE_ID, BATCH_ID
      INTO v_sku, v_batch
      FROM tmp_sku_queue
      LIMIT 1;

    DELETE FROM tmp_sku_queue
     WHERE ARTICLE_ID = v_sku
       AND BATCH_ID   = v_batch;

    TRUNCATE TABLE tmp_sku_line_queue;

    
    INSERT INTO tmp_sku_line_queue (RN, PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY)
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE, la.QUANTITY DESC, la.ORDER_LINE_ID
        ) AS RN,
        la.PARENT_ORDER_ID,
        la.CLIENT_ORDER_TYPE,
        la.ORDER_LINE_ID,
        la.QUANTITY
    FROM tmp_line_assign la
    WHERE la.SHORT_FLAG_SCHEMA = 0
      AND la.ARTICLE_ID = v_sku
      AND la.BATCH_ID   = v_batch;

    SELECT COALESCE(MAX(RN),0) INTO v_maxrn FROM tmp_sku_line_queue;
    SET v_rn = 1;

    line_loop: WHILE v_rn <= v_maxrn DO

        SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY
          INTO v_line_parent, v_line_cat, v_line_id, v_line_qty
          FROM tmp_sku_line_queue
         WHERE RN = v_rn;

        
        IF v_last_bucket_parent IS NULL
           OR v_last_bucket_cat IS NULL
           OR v_last_bucket_parent <> v_line_parent
           OR v_last_bucket_cat <> v_line_cat
        THEN
            SET v_last_bucket_parent = v_line_parent;
            SET v_last_bucket_cat    = v_line_cat;

            
            SET v_bucketK = 1;
            SELECT COALESCE(K, 1)
              INTO v_bucketK
              FROM tmp_bucket_k
             WHERE PARENT_ORDER_ID = v_line_parent
               AND CLIENT_ORDER_TYPE = v_line_cat
             LIMIT 1;

            
            SET v_bucket_primary_cluster = NULL;

            SELECT bc.CHOSEN_CLUSTER_ID
              INTO v_bucket_primary_cluster
              FROM tmp_bucket_choice bc
             WHERE bc.PARENT_ORDER_ID = v_line_parent
               AND bc.CLIENT_ORDER_TYPE = v_line_cat
             LIMIT 1;

            IF v_bucket_primary_cluster IS NULL THEN
                SELECT bcs.CLUSTER_ID
                  INTO v_bucket_primary_cluster
                  FROM tmp_bucket_cluster_score bcs
                 WHERE bcs.PARENT_ORDER_ID = v_line_parent
                   AND bcs.CLIENT_ORDER_TYPE = v_line_cat
                 ORDER BY bcs.SCORE_RANK, bcs.CLUSTER_ID
                 LIMIT 1;
            END IF;

            IF v_bucket_primary_cluster IS NULL THEN
                SELECT ac.CLUSTER_ID
                  INTO v_bucket_primary_cluster
                  FROM tmp_allowed_clusters ac
                 WHERE ac.PARENT_ORDER_ID = v_line_parent
                   AND ac.CLIENT_ORDER_TYPE = v_line_cat
                 ORDER BY ac.CLUSTER_ID
                 LIMIT 1;
            END IF;

            
            IF v_use_station_bias = 1 AND v_bucket_primary_cluster IS NOT NULL THEN
                SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_bucket_primary_cluster)
                  INTO v_bucket_primary_cluster
                  FROM tmp_cluster_snap_map sm
                 WHERE sm.SRC_CLUSTER_ID = v_bucket_primary_cluster
                 LIMIT 1;

                
                IF v_bucket_primary_cluster IS NULL THEN
                    SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                      INTO v_bucket_primary_cluster
                      FROM tmp_bucket_fallback
                     WHERE PARENT_ORDER_ID = v_line_parent
                       AND CLIENT_ORDER_TYPE = v_line_cat
                     LIMIT 1;
                END IF;

                IF v_bucket_primary_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_bucket_primary_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;
            END IF;
        END IF;

        
        DELETE FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        SELECT COALESCE(TOTAL_REM,0)
          INTO v_total_rem
          FROM tmp_sku_rem
         WHERE ARTICLE_ID = v_sku
           AND BATCH_ID   = v_batch;

        
        IF v_total_rem <= 0 THEN

            IF v_use_station_bias = 1 THEN
                
                SET v_pick_cluster = v_bucket_primary_cluster;

                
                IF v_pick_cluster IS NULL THEN
                    SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                      INTO v_pick_cluster
                      FROM tmp_bucket_fallback
                     WHERE PARENT_ORDER_ID = v_line_parent
                       AND CLIENT_ORDER_TYPE = v_line_cat
                     LIMIT 1;
                END IF;

                
                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        TRUNCATE TABLE tmp_line_cluster_seq;

        
        INSERT INTO tmp_line_cluster_seq (RN, CLUSTER_ID, REM_QTY)
        SELECT
            ROW_NUMBER() OVER (
                ORDER BY
                    
                    CASE
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND csr.CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                        ELSE 2
                    END,
                    
                    CASE
                        WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                        WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                        WHEN v_use_station_bias = 1 THEN 2
                        ELSE 3
                    END,
                    
                    CASE WHEN ac.CLUSTER_ID IS NOT NULL THEN 0 ELSE 1 END,
                    
                    COALESCE(bcs.SCORE_RANK, 999999),
                    
                    COALESCE(pcl.LINE_CNT,0) DESC,
                    COALESCE(pcl.QTY_CNT,0)  DESC,
                    
                    csr.REM_QTY DESC,
                    csr.CLUSTER_ID
            ) AS RN,
            csr.CLUSTER_ID,
            csr.REM_QTY
        FROM tmp_cluster_supply_rem csr
        LEFT JOIN tmp_allowed_clusters ac
          ON ac.PARENT_ORDER_ID   = v_line_parent
         AND ac.CLIENT_ORDER_TYPE = v_line_cat
         AND ac.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = v_line_parent
         AND bcs.CLIENT_ORDER_TYPE = v_line_cat
         AND bcs.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_choice bc
          ON bc.PARENT_ORDER_ID   = v_line_parent
         AND bc.CLIENT_ORDER_TYPE = v_line_cat
        LEFT JOIN tmp_parent_cluster_load pcl
          ON pcl.PARENT_ORDER_ID   = v_line_parent
         AND pcl.CLIENT_ORDER_TYPE = v_line_cat
         AND pcl.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_pref_clusters pfc
          ON pfc.CLUSTER_ID = csr.CLUSTER_ID
        LEFT JOIN tmp_near_clusters nfc
          ON nfc.CLUSTER_ID = csr.CLUSTER_ID
        WHERE csr.ARTICLE_ID = v_sku
          AND csr.BATCH_ID   = v_batch
          AND csr.REM_QTY   > 0;

        SELECT COALESCE(MAX(RN),0) INTO v_cmax FROM tmp_line_cluster_seq;

        
        SET v_need = v_line_qty;
        SET v_crn  = 1;

        cluster_loop: WHILE v_need > 0 AND v_crn <= v_cmax DO

            SELECT CLUSTER_ID, REM_QTY
              INTO v_cur_cluster, v_cur_rem
              FROM tmp_line_cluster_seq
             WHERE RN = v_crn;

            SET v_alloc = LEAST(v_cur_rem, v_need);

            IF v_alloc > 0 THEN

                INSERT INTO tmp_line_alloc (
                    PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID,
                    ARTICLE_ID, BATCH_ID, SRC_CLUSTER_ID, ALLOC_QTY
                )
                VALUES (
                    v_line_parent, v_line_cat, v_line_id,
                    v_sku, v_batch, v_cur_cluster, v_alloc
                )
                ON DUPLICATE KEY UPDATE
                    ALLOC_QTY = ALLOC_QTY + VALUES(ALLOC_QTY);

                UPDATE tmp_cluster_supply_rem
                   SET REM_QTY = REM_QTY - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch
                   AND CLUSTER_ID = v_cur_cluster;

                
                UPDATE tmp_sku_rem
                   SET TOTAL_REM = TOTAL_REM - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch;

                SET v_need = v_need - v_alloc;

            END IF;

            SET v_crn = v_crn + 1;
        END WHILE;

        
        SELECT COALESCE(SUM(ALLOC_QTY),0)
          INTO v_alloc
          FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        IF v_alloc <= 0 THEN

            IF v_use_station_bias = 1 THEN
                
                SET v_pick_cluster = v_bucket_primary_cluster;

                IF v_pick_cluster IS NULL THEN
                    SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                      INTO v_pick_cluster
                      FROM tmp_bucket_fallback
                     WHERE PARENT_ORDER_ID = v_line_parent
                       AND CLIENT_ORDER_TYPE = v_line_cat
                     LIMIT 1;
                END IF;

                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        
        SET v_pick_cluster = NULL;

        
        SELECT la.SRC_CLUSTER_ID
          INTO v_pick_cluster
          FROM tmp_line_alloc la
          JOIN tmp_allowed_clusters ac
            ON ac.PARENT_ORDER_ID   = v_line_parent
           AND ac.CLIENT_ORDER_TYPE = v_line_cat
           AND ac.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_cluster_score bcs
            ON bcs.PARENT_ORDER_ID   = v_line_parent
           AND bcs.CLIENT_ORDER_TYPE = v_line_cat
           AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_choice bc
            ON bc.PARENT_ORDER_ID   = v_line_parent
           AND bc.CLIENT_ORDER_TYPE = v_line_cat
          LEFT JOIN tmp_pref_clusters pfc
            ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_near_clusters nfc
            ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
         WHERE la.PARENT_ORDER_ID   = v_line_parent
           AND la.CLIENT_ORDER_TYPE = v_line_cat
           AND la.ORDER_LINE_ID     = v_line_id
         ORDER BY
            la.ALLOC_QTY DESC,
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                ELSE 2
            END,
            CASE
                WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                WHEN v_use_station_bias = 1 THEN 2
                ELSE 3
            END,
            COALESCE(bcs.SCORE_RANK, 999999),
            la.SRC_CLUSTER_ID
         LIMIT 1;

        
        IF v_pick_cluster IS NULL THEN
            SELECT la.SRC_CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_line_alloc la
              LEFT JOIN tmp_bucket_cluster_score bcs
                ON bcs.PARENT_ORDER_ID   = v_line_parent
               AND bcs.CLIENT_ORDER_TYPE = v_line_cat
               AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_bucket_choice bc
                ON bc.PARENT_ORDER_ID   = v_line_parent
               AND bc.CLIENT_ORDER_TYPE = v_line_cat
              LEFT JOIN tmp_pref_clusters pfc
                ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_near_clusters nfc
                ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
             WHERE la.PARENT_ORDER_ID   = v_line_parent
               AND la.CLIENT_ORDER_TYPE = v_line_cat
               AND la.ORDER_LINE_ID     = v_line_id
             ORDER BY
                la.ALLOC_QTY DESC,
                CASE
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                    ELSE 2
                END,
                CASE
                    WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                    WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                    WHEN v_use_station_bias = 1 THEN 2
                    ELSE 3
                END,
                COALESCE(bcs.SCORE_RANK, 999999),
                la.SRC_CLUSTER_ID
             LIMIT 1;
        END IF;

        
        IF v_pick_cluster IS NULL THEN
            SELECT csr.CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_cluster_supply_rem csr
             WHERE csr.ARTICLE_ID = v_sku
               AND csr.BATCH_ID = v_batch
             ORDER BY csr.REM_QTY DESC, csr.CLUSTER_ID
             LIMIT 1;
        END IF;

        
        IF v_use_station_bias = 1
           AND v_pick_cluster IS NOT NULL
        THEN
            SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_pick_cluster)
              INTO v_pick_cluster
              FROM tmp_cluster_snap_map sm
             WHERE sm.SRC_CLUSTER_ID = v_pick_cluster
             LIMIT 1;

            
            IF v_pick_cluster IS NULL THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT fc.CLUSTER_ID
                  INTO v_pick_cluster
                  FROM tmp_final_clusters fc
                 ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                 LIMIT 1;
            END IF;
        END IF;

        
        IF v_pick_cluster IS NOT NULL
           AND v_pick_cluster <> 'NO_INVENTORY'
        THEN
            
            IF v_bucketK = 1 AND v_bucket_primary_cluster IS NOT NULL THEN
                SET v_pick_cluster = v_bucket_primary_cluster;

            ELSE
                
                IF NOT EXISTS (
                    SELECT 1
                      FROM tmp_allowed_clusters acx
                     WHERE acx.PARENT_ORDER_ID = v_line_parent
                       AND acx.CLIENT_ORDER_TYPE = v_line_cat
                       AND acx.CLUSTER_ID = v_pick_cluster
                     LIMIT 1
                )
                THEN
                    
                    SELECT ac.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_allowed_clusters ac
                      LEFT JOIN tmp_bucket_choice bc
                        ON bc.PARENT_ORDER_ID = ac.PARENT_ORDER_ID
                       AND bc.CLIENT_ORDER_TYPE = ac.CLIENT_ORDER_TYPE
                      LEFT JOIN tmp_bucket_cluster_score bcs
                        ON bcs.PARENT_ORDER_ID = ac.PARENT_ORDER_ID
                       AND bcs.CLIENT_ORDER_TYPE = ac.CLIENT_ORDER_TYPE
                       AND bcs.CLUSTER_ID = ac.CLUSTER_ID
                      LEFT JOIN tmp_parent_cluster_load pcl
                        ON pcl.PARENT_ORDER_ID = ac.PARENT_ORDER_ID
                       AND pcl.CLIENT_ORDER_TYPE = ac.CLIENT_ORDER_TYPE
                       AND pcl.CLUSTER_ID = ac.CLUSTER_ID
                      LEFT JOIN tmp_pref_clusters pfc
                        ON pfc.CLUSTER_ID = ac.CLUSTER_ID
                      LEFT JOIN tmp_near_clusters nfc
                        ON nfc.CLUSTER_ID = ac.CLUSTER_ID
                     WHERE ac.PARENT_ORDER_ID = v_line_parent
                       AND ac.CLIENT_ORDER_TYPE = v_line_cat
                     ORDER BY
                        CASE
                            WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND ac.CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                            WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                            ELSE 2
                        END,
                        CASE
                            WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                            WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                            WHEN v_use_station_bias = 1 THEN 2
                            ELSE 3
                        END,
                        COALESCE(bcs.SCORE_RANK, 999999),
                        COALESCE(pcl.LINE_CNT,0) DESC,
                        COALESCE(pcl.QTY_CNT,0)  DESC,
                        ac.CLUSTER_ID
                     LIMIT 1;

                    
                    IF v_pick_cluster IS NULL THEN
                        SET v_pick_cluster = v_bucket_primary_cluster;
                    END IF;
                END IF;
            END IF;
        END IF;

        
        IF v_use_station_bias = 1
           AND v_pick_cluster IS NOT NULL
           AND v_pick_cluster <> 'NO_INVENTORY'
        THEN
            SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_pick_cluster)
              INTO v_pick_cluster
              FROM tmp_cluster_snap_map sm
             WHERE sm.SRC_CLUSTER_ID = v_pick_cluster
             LIMIT 1;

            IF v_pick_cluster IS NULL THEN
                SET v_pick_cluster = v_bucket_primary_cluster;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT fc.CLUSTER_ID
                  INTO v_pick_cluster
                  FROM tmp_final_clusters fc
                 ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                 LIMIT 1;
            END IF;
        END IF;

        
        UPDATE tmp_line_assign
           SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
               ASSIGNED_RANK = 1,
               SHORT_FLAG_SUPPLY = CASE WHEN v_alloc < v_line_qty THEN 1 ELSE 0 END
         WHERE PARENT_ORDER_ID = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID = v_line_id;

        
        INSERT INTO tmp_parent_cluster_load (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, LINE_CNT, QTY_CNT)
        VALUES (v_line_parent, v_line_cat, v_pick_cluster, 1, v_line_qty)
        ON DUPLICATE KEY UPDATE
            LINE_CNT = LINE_CNT + 1,
            QTY_CNT  = QTY_CNT  + VALUES(QTY_CNT);

        SET v_rn = v_rn + 1;
    END WHILE;

END WHILE;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_line_assign la
    LEFT JOIN tmp_bucket_fallback bf
      ON bf.PARENT_ORDER_ID = la.PARENT_ORDER_ID
     AND bf.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
    SET la.ASSIGNED_CLUSTER_ID = COALESCE(
            bf.FALLBACK_CLUSTER_ID,
            (SELECT fc.CLUSTER_ID
               FROM tmp_final_clusters fc
              ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
              LIMIT 1)
        ),
        la.ASSIGNED_RANK = 0
    WHERE la.SHORT_FLAG_SCHEMA = 1
      AND la.ASSIGNED_CLUSTER_ID IS NULL;
END IF;

UPDATE tmp_line_assign
   SET SHORT_FLAG = GREATEST(SHORT_FLAG_SCHEMA, SHORT_FLAG_SUPPLY);



        

DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc_sum;
CREATE TEMPORARY TABLE tmp_line_alloc_sum (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ALLOC_SUM           BIGINT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID)
) ENGINE=INNODB;

INSERT INTO tmp_line_alloc_sum
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    ORDER_LINE_ID,
    SUM(ALLOC_QTY) AS ALLOC_SUM
FROM tmp_line_alloc
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID;


DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
CREATE TEMPORARY TABLE tmp_ranked_lines (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NULL,
    BATCH_ID            VARCHAR(200) NULL,
    QUANTITY            INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

    LINE_CLUSTER_ID     VARCHAR(50)  NOT NULL, 
    SHORT_FLAG          INT NOT NULL,          
    NO_INV_FLAG         INT NOT NULL,          

    RN                  BIGINT NOT NULL,
    SPLIT_GROUP         INT NOT NULL,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
    UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP, RN)
) ENGINE=INNODB;

INSERT INTO tmp_ranked_lines
SELECT
    la.PARENT_ORDER_ID,
    la.CLIENT_ORDER_TYPE,
    la.ORDER_LINE_ID,
    la.ARTICLE_ID,
    la.BATCH_ID,
    la.QUANTITY,
    la.DISPLAY_OPERATOR_INSTRUCTION,

    COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY') AS LINE_CLUSTER_ID,

    
    CASE
        WHEN la.SHORT_FLAG_SCHEMA = 1 THEN 0
        WHEN COALESCE(s.ALLOC_SUM,0) = 0 THEN 0
        WHEN COALESCE(s.ALLOC_SUM,0) < la.QUANTITY THEN 1
        ELSE 0
    END AS SHORT_FLAG,

    
    CASE
        WHEN la.SHORT_FLAG_SCHEMA = 1 THEN 1
        WHEN COALESCE(s.ALLOC_SUM,0) = 0 THEN 1
        ELSE 0
    END AS NO_INV_FLAG,

    ROW_NUMBER() OVER (
        PARTITION BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE
        ORDER BY
            
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL
                 AND COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = bc.CHOSEN_CLUSTER_ID
                THEN 0 ELSE 1
            END,
            la.QUANTITY DESC,
            COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY'),
            la.ORDER_LINE_ID
    ) AS RN,

    
    1 + ((ROW_NUMBER() OVER (
            PARTITION BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE
            ORDER BY
                CASE
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL
                     AND COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = bc.CHOSEN_CLUSTER_ID
                    THEN 0 ELSE 1
                END,
                la.QUANTITY DESC,
                COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY'),
                la.ORDER_LINE_ID
        ) - 1) * k.K) DIV k.TOTAL_LINES AS SPLIT_GROUP

FROM tmp_line_assign la
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = la.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
LEFT JOIN tmp_bucket_choice bc
  ON bc.PARENT_ORDER_ID   = la.PARENT_ORDER_ID
 AND bc.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
LEFT JOIN tmp_line_alloc_sum s
  ON s.PARENT_ORDER_ID     = la.PARENT_ORDER_ID
 AND s.CLIENT_ORDER_TYPE   = la.CLIENT_ORDER_TYPE
 AND s.ORDER_LINE_ID       = la.ORDER_LINE_ID;

SELECT COUNT(*) INTO v_cnt_ranked FROM tmp_ranked_lines;
IF v_cnt_ranked <> v_cnt_line_assign THEN
    SET v_errmsg = CONCAT('LINE_LOSS_AFTER_RANKING: tmp_line_assign=', v_cnt_line_assign,
                          ', tmp_ranked_lines=', v_cnt_ranked);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster_weight;
CREATE TEMPORARY TABLE tmp_group_cluster_weight (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    CLUSTER_ID          VARCHAR(50) NOT NULL,
    WQTY                BIGINT NOT NULL,
    RN                  INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP, RN),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_group_cluster_weight
SELECT
    rl.PARENT_ORDER_ID,
    rl.CLIENT_ORDER_TYPE,
    rl.SPLIT_GROUP,
    rl.LINE_CLUSTER_ID AS CLUSTER_ID,
    SUM(rl.QUANTITY) AS WQTY,
    ROW_NUMBER() OVER (
        PARTITION BY rl.PARENT_ORDER_ID, rl.CLIENT_ORDER_TYPE, rl.SPLIT_GROUP
        ORDER BY
            SUM(rl.QUANTITY) DESC,
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND rl.LINE_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID
                THEN 0 ELSE 1
            END,
            rl.LINE_CLUSTER_ID
    ) AS RN
FROM tmp_ranked_lines rl
LEFT JOIN tmp_bucket_choice bc
  ON bc.PARENT_ORDER_ID   = rl.PARENT_ORDER_ID
 AND bc.CLIENT_ORDER_TYPE = rl.CLIENT_ORDER_TYPE
WHERE rl.LINE_CLUSTER_ID IS NOT NULL
  AND rl.LINE_CLUSTER_ID <> 'NO_INVENTORY'
GROUP BY rl.PARENT_ORDER_ID, rl.CLIENT_ORDER_TYPE, rl.SPLIT_GROUP, rl.LINE_CLUSTER_ID, bc.CHOSEN_CLUSTER_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster;
CREATE TEMPORARY TABLE tmp_group_cluster (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    GROUP_CLUSTER_ID    VARCHAR(50) NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP),
    KEY (GROUP_CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_group_cluster
SELECT
    g.PARENT_ORDER_ID,
    g.CLIENT_ORDER_TYPE,
    g.SPLIT_GROUP,
    COALESCE(
        w.CLUSTER_ID,
        bc.CHOSEN_CLUSTER_ID,
        bf.FALLBACK_CLUSTER_ID,
        'NO_INVENTORY'
    ) AS GROUP_CLUSTER_ID
FROM (
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP
      FROM tmp_ranked_lines
     GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP
) g
LEFT JOIN tmp_group_cluster_weight w
  ON w.PARENT_ORDER_ID   = g.PARENT_ORDER_ID
 AND w.CLIENT_ORDER_TYPE = g.CLIENT_ORDER_TYPE
 AND w.SPLIT_GROUP       = g.SPLIT_GROUP
 AND w.RN = 1
LEFT JOIN tmp_bucket_choice bc
  ON bc.PARENT_ORDER_ID   = g.PARENT_ORDER_ID
 AND bc.CLIENT_ORDER_TYPE = g.CLIENT_ORDER_TYPE
LEFT JOIN tmp_bucket_fallback bf
  ON bf.PARENT_ORDER_ID   = g.PARENT_ORDER_ID
 AND bf.CLIENT_ORDER_TYPE = g.CLIENT_ORDER_TYPE;


DROP TEMPORARY TABLE IF EXISTS tmp_group_flags;
CREATE TEMPORARY TABLE tmp_group_flags (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    HAS_NO_INV          INT NOT NULL,
    HAS_SHORT           INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP)
) ENGINE=INNODB;

INSERT INTO tmp_group_flags
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    SPLIT_GROUP,
    MAX(NO_INV_FLAG) AS HAS_NO_INV,
    MAX(SHORT_FLAG)  AS HAS_SHORT
FROM tmp_ranked_lines
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP;


DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
CREATE TEMPORARY TABLE tmp_final_map (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NULL,
    BATCH_ID            VARCHAR(200) NULL,
    QUANTITY            INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

    SPLIT_GROUP         INT NOT NULL,

    IS_SUSPENDED_GROUP  INT NOT NULL,
    IS_SHORT_LINE       INT NOT NULL,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, ORDER_LINE_ID),
    UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP)
) ENGINE=INNODB;

INSERT INTO tmp_final_map
SELECT
    rl.PARENT_ORDER_ID,
    rl.CLIENT_ORDER_TYPE,
    gc.GROUP_CLUSTER_ID AS CLUSTER_ID,
    rl.ORDER_LINE_ID,
    rl.ARTICLE_ID,
    rl.BATCH_ID,
    rl.QUANTITY,
    rl.DISPLAY_OPERATOR_INSTRUCTION,
    rl.SPLIT_GROUP,
    gf.HAS_NO_INV AS IS_SUSPENDED_GROUP,
    rl.SHORT_FLAG AS IS_SHORT_LINE
FROM tmp_ranked_lines rl
JOIN tmp_group_cluster gc
  ON gc.PARENT_ORDER_ID   = rl.PARENT_ORDER_ID
 AND gc.CLIENT_ORDER_TYPE = rl.CLIENT_ORDER_TYPE
 AND gc.SPLIT_GROUP       = rl.SPLIT_GROUP
JOIN tmp_group_flags gf
  ON gf.PARENT_ORDER_ID   = rl.PARENT_ORDER_ID
 AND gf.CLIENT_ORDER_TYPE = rl.CLIENT_ORDER_TYPE
 AND gf.SPLIT_GROUP       = rl.SPLIT_GROUP;

SELECT COUNT(*) INTO v_cnt_final FROM tmp_final_map;
IF v_cnt_final <> v_cnt_ranked THEN
    SET v_errmsg = CONCAT('LINE_LOSS_AFTER_FINAL_MAP: tmp_ranked_lines=', v_cnt_ranked,
                          ', tmp_final_map=', v_cnt_final);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
END IF;



    

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_pre_lines, v_pre_qty
    FROM tmp_lines;

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_post_lines, v_post_qty
    FROM tmp_final_map;

    IF v_pre_lines <> v_post_lines OR v_pre_qty <> v_post_qty THEN
        SET v_errmsg = CONCAT(
            'CONSERVATION_FAILED: PRE_LINES=', v_pre_lines,
            ', POST_LINES=', v_post_lines,
            ', PRE_QTY=', v_pre_qty,
            ', POST_QTY=', v_post_qty
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_lines tl
    LEFT JOIN tmp_final_map fm
      ON fm.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND fm.ORDER_LINE_ID   = tl.ORDER_LINE_ID
    WHERE fm.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('MISSING_LINES_IN_OUTPUT=', v_missing_lines);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

       

DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
CREATE TEMPORARY TABLE tmp_cat_seq (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CAT_SEQ             INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT INTO tmp_cat_seq
SELECT
    x.PARENT_ORDER_ID,
    x.CLIENT_ORDER_TYPE,
    ROW_NUMBER() OVER (PARTITION BY x.PARENT_ORDER_ID ORDER BY x.CLIENT_ORDER_TYPE) AS CAT_SEQ
FROM (SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE FROM tmp_lines_cat) X;

DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
CREATE TEMPORARY TABLE tmp_child_orders (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    CHILD_ORDER_ID      VARCHAR(180) NOT NULL,
    CHILD_STATUS        ENUM('PENDING') NOT NULL,

    HAS_SHORT_LINES     INT NOT NULL DEFAULT 0,
    HAS_NO_INV_LINES    INT NOT NULL DEFAULT 0,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP),
    KEY (CHILD_ORDER_ID),
    KEY (CHILD_STATUS)
) ENGINE=INNODB;

INSERT INTO tmp_child_orders
SELECT
    fm.PARENT_ORDER_ID,
    fm.CLIENT_ORDER_TYPE,
    fm.CLUSTER_ID,
    fm.SPLIT_GROUP,

    CASE
        WHEN k.K = 1 THEN
            CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID)
        ELSE
            CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID, '-', LPAD(fm.SPLIT_GROUP, 3, '0'))
    END AS CHILD_ORDER_ID,

    'PENDING' AS CHILD_STATUS,

    CASE WHEN MAX(fm.IS_SHORT_LINE) = 1 THEN 1 ELSE 0 END AS HAS_SHORT_LINES,
    CASE WHEN MAX(fm.IS_SUSPENDED_GROUP) = 1 THEN 1 ELSE 0 END AS HAS_NO_INV_LINES

FROM tmp_final_map fm
JOIN tmp_cat_seq cs
  ON cs.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND cs.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
GROUP BY
    fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.SPLIT_GROUP, k.K, cs.CAT_SEQ;

SELECT COUNT(*) INTO v_child_cnt FROM tmp_child_orders;



	

SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_all,
        v_total_qty_all
    FROM tmp_line_assign;
    
    SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_pickable,
        v_total_qty_pickable
    FROM tmp_line_assign
    WHERE SHORT_FLAG_SCHEMA = 0
      AND COALESCE(ASSIGNED_CLUSTER_ID,'NO_INVENTORY') <> 'NO_INVENTORY';

    SELECT
        COALESCE(SUM(a.ALLOC_QTY),0),
        COALESCE(COUNT(DISTINCT CONCAT(a.PARENT_ORDER_ID,'|',a.CLIENT_ORDER_TYPE,'|',a.ORDER_LINE_ID)),0)
    INTO
        v_alloc_qty_total,
        v_alloc_lines_total
    FROM tmp_line_alloc a;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
CREATE TEMPORARY TABLE tmp_reco1 (
    STATION_ID VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NULL,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
CREATE TEMPORARY TABLE tmp_reco2 (
    STATION_ID   VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NULL,
    IS_SELECTED  INT NOT NULL DEFAULT 0,
    IS_NO_WAVE   INT NOT NULL DEFAULT 0,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID),
    KEY (IS_NO_WAVE, IS_SELECTED)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2_avail_clusters;
CREATE TEMPORARY TABLE tmp_reco2_avail_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_has_hw_station = 0 THEN

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT STATION_ID, NULL
      FROM tmp_user_stations;

    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT STATION_ID, NULL, 1, 0
      FROM tmp_user_stations;

ELSE

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM hw_station_master hs
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50)),
           1 AS IS_SELECTED,
           0 AS IS_NO_WAVE
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    IF v_has_hw_wave_status = 1 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
               CAST(hs.CLUSTER_ID AS CHAR(50)),
               0 AS IS_SELECTED,
               1 AS IS_NO_WAVE
          FROM hw_station_master hs
         WHERE hs.STATION_ID IS NOT NULL
           AND hs.CLUSTER_ID IS NOT NULL
           AND LOWER(REPLACE(COALESCE(hs.wave_status,''),' ','_')) IN ('no_wave','nowave','no-wave');
    END IF;

    
    IF v_user_station_cnt = 0 AND v_has_hw_wave_status = 0 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT STATION_ID, CLUSTER_ID, 0, 0 FROM tmp_reco1;
    END IF;

END IF;


INSERT IGNORE INTO tmp_reco2_avail_clusters (CLUSTER_ID)
SELECT DISTINCT COALESCE(CLUSTER_ID,'?')
  FROM tmp_reco2
 WHERE CLUSTER_ID IS NOT NULL;



DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
CREATE TEMPORARY TABLE tmp_job_cluster_stats (
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    ORDER_LINES  BIGINT NOT NULL,
    ORDER_QTY    BIGINT NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_job_cluster_stats (CLUSTER_ID, ORDER_LINES, ORDER_QTY)
SELECT
    co.CLUSTER_ID,
    COUNT(DISTINCT co.CHILD_ORDER_ID) AS ORDER_LINES,
    COALESCE(SUM(fm.QUANTITY),0)      AS ORDER_QTY
FROM tmp_child_orders co
LEFT JOIN tmp_final_map fm
  ON fm.PARENT_ORDER_ID   = co.PARENT_ORDER_ID
 AND fm.CLIENT_ORDER_TYPE = co.CLIENT_ORDER_TYPE
 AND fm.CLUSTER_ID        = co.CLUSTER_ID
 AND fm.SPLIT_GROUP       = co.SPLIT_GROUP

WHERE co.CLUSTER_ID <> 'NO_INVENTORY'
GROUP BY co.CLUSTER_ID;



DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco1_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco1_total_lines,
    @reco1_total_qty
FROM tmp_job_cluster_stats js;


INSERT INTO tmp_reco1_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID ORDER BY r.STATION_ID SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco1_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco1_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco1_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco1_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco1 r
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco2_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco2_total_lines,
    @reco2_total_qty
FROM tmp_job_cluster_stats js
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = js.CLUSTER_ID;


INSERT INTO tmp_reco2_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID
                          ORDER BY r.IS_NO_WAVE DESC, r.IS_SELECTED DESC, r.STATION_ID
                          SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco2_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco2_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco2_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco2_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco2 r
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = r.CLUSTER_ID
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



SET @reco1_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco1_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);

SET @reco2_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco2_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);



IF v_has_reco1 = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2 = 1 THEN
    UPDATE picklist_split_order_master
      SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco1_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco_col = 1 THEN
   UPDATE picklist_split_order_master
SET RECOMMENDATION = JSON_OBJECT(
    'RECOMMENDATION_1_ALL_STATIONS', CAST(@reco1_cluster_json AS JSON),
    'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

    'STATION_PREF_MODE', v_station_mode,
    'USER_SELECTED_STATIONS', (
        SELECT COALESCE(GROUP_CONCAT(STATION_ID ORDER BY STATION_ID SEPARATOR ','), '')
        FROM tmp_user_stations
    ),
    'RULE_ID', v_rule_id,
    'RULE_LOG_ID', v_ruleLog_id,
    'TOTAL_INITIAL_ORDERS', v_parent_cnt,
    'TOTAL_SPLIT_ORDERS', v_child_cnt,

    'INITIAL_ORDER_LINES', v_line_cnt,
    'AFTER_ALLOCATION_ORDER_LINES', v_cnt_final,

    'TOTAL_LINES_PICKABLE', v_total_lines_pickable,

    
    'TOTAL_QTY_ALL', v_pre_qty,
    'TOTAL_QTY_PICKABLE', v_total_qty_pickable,

    
    'ALLOC_QTY_TOTAL', v_post_qty,
    'ALLOC_LINES_TOTAL', v_alloc_lines_total,

    'NOTES', JSON_OBJECT(
        'PARENT_FIELD', 'PARENT_ORDER_ID',
        'CHILD_FIELD', 'ORDER_ID',
        'SUB_ORDER_ID', 'NOT_USED',
        'RESERVATION_KEY', v_reservation_key,
        'RESERVATION_TTL_MINUTES', v_res_ttl_minutes
    )
)
WHERE ID = v_ruleLog_id;

END IF;

    

IF v_is_dry_run = 0 THEN

    
    SET @or_cols = 'PARENT_ORDER_ID, ORDER_TYPE, ORDER_ID, ORDER_REQUEST_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @or_sel  = 'co.PARENT_ORDER_ID, co.CLIENT_ORDER_TYPE, co.CHILD_ORDER_ID, co.CHILD_STATUS, CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_or_cluster = 1 THEN
        SET @or_cols = CONCAT(@or_cols, ', CLUSTER_ID');
        SET @or_sel  = CONCAT(@or_sel,  ', co.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_request_data (', @or_cols, ') ',
        'SELECT ', @or_sel, ' ',
        '  FROM tmp_child_orders co ',
        '  LEFT JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        ' WHERE r.ORDER_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SET @line_cols = 'WMS_ORDER_REQUEST_DATA_ID, ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, BATCH_ID, DISPLAY_OPERATOR_INSTRUCTION, ORDER_LINE_PROCESS_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @line_sel  = 'r.WMS_ORDER_REQUEST_DATA_ID, r.ORDER_ID, fm.ORDER_LINE_ID, fm.ARTICLE_ID, fm.QUANTITY, fm.BATCH_ID, fm.DISPLAY_OPERATOR_INSTRUCTION, ''PENDING'', CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_ol_cluster = 1 THEN
        SET @line_cols = CONCAT(@line_cols, ', CLUSTER_ID');
        SET @line_sel  = CONCAT(@line_sel,  ', fm.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_line_request_data (', @line_cols, ') ',
        'SELECT ', @line_sel, ' ',
        '  FROM tmp_final_map fm ',
        '  JOIN tmp_child_orders co ',
        '    ON co.PARENT_ORDER_ID = fm.PARENT_ORDER_ID ',
        '   AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE ',
        '   AND co.CLUSTER_ID = fm.CLUSTER_ID ',
        '   AND co.SPLIT_GROUP = fm.SPLIT_GROUP ',
        '  JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        '  LEFT JOIN wms_to_wcs_order_line_request_data lr ',
        '    ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID ',
        '   AND lr.ORDER_LINE_ID = fm.ORDER_LINE_ID ',
        ' WHERE lr.ORDER_LINE_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_final_map fm
    JOIN tmp_child_orders co
      ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
     AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
     AND co.CLUSTER_ID        = fm.CLUSTER_ID
     AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
    JOIN wms_to_wcs_order_request_data r
      ON r.ORDER_ID = co.CHILD_ORDER_ID
    LEFT JOIN wms_to_wcs_order_line_request_data lr
      ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID
     AND lr.ORDER_LINE_ID            = fm.ORDER_LINE_ID
    WHERE lr.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('DB_WRITE_MISSING_LINES=', v_missing_lines, ' (expected all tmp_final_map lines in DB)');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    
    SELECT COUNT(*) INTO v_cnt_db_child_lines
    FROM wms_to_wcs_order_line_request_data lr
    JOIN wms_to_wcs_order_request_data r
      ON r.WMS_ORDER_REQUEST_DATA_ID = lr.WMS_ORDER_REQUEST_DATA_ID
    JOIN tmp_child_orders co
      ON co.CHILD_ORDER_ID = r.ORDER_ID;

ELSE
    SET v_cnt_db_child_lines = 0;
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
CREATE TEMPORARY TABLE tmp_child_demand (
    ORDER_ID VARCHAR(180) NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    DEMAND_QTY BIGINT NOT NULL,
    PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, DEMAND_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_child_demand
SELECT
    co.CHILD_ORDER_ID AS ORDER_ID,
    fm.PARENT_ORDER_ID,
    fm.CLIENT_ORDER_TYPE,
    fm.CLUSTER_ID AS DEMAND_CLUSTER_ID,
    fm.ARTICLE_ID,
    fm.BATCH_ID,
    SUM(fm.QUANTITY) AS DEMAND_QTY
FROM tmp_final_map fm
JOIN tmp_child_orders co
  ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
 AND co.CLUSTER_ID        = fm.CLUSTER_ID
 AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
WHERE fm.IS_SUSPENDED_GROUP = 0
  AND fm.ARTICLE_ID IS NOT NULL
  AND fm.BATCH_ID IS NOT NULL
  AND fm.CLUSTER_ID <> 'NO_INVENTORY'
  AND co.CHILD_STATUS = 'PENDING'
GROUP BY co.CHILD_ORDER_ID, fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.ARTICLE_ID, fm.BATCH_ID;

IF (SELECT COUNT(*) FROM tmp_child_demand) > 0 THEN

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
    CREATE TEMPORARY TABLE tmp_res_need_clusters (
        ORDER_ID         VARCHAR(180) NOT NULL,
        ARTICLE_ID       VARCHAR(200) NOT NULL,
        BATCH_ID         VARCHAR(200) NOT NULL,
        CLUSTER_ID       VARCHAR(50)  NOT NULL,
        DEMAND_QTY       BIGINT NOT NULL,
        PRIORITY         INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,
        CLUSTER_SUPPLY   BIGINT NOT NULL,
        CUM_SUPPLY_PREV  BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID),
        KEY idx_need (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_need_clusters
        (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID, DEMAND_QTY, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_SUPPLY, CUM_SUPPLY_PREV)
    SELECT
        z.ORDER_ID,
        z.ARTICLE_ID,
        z.BATCH_ID,
        z.CLUSTER_ID,
        z.DEMAND_QTY,
        z.PRIORITY,
        z.SRC_CLUSTER_RANK,
        z.CLUSTER_SUPPLY,
        COALESCE(z.cum_supply_prev, 0) AS CUM_SUPPLY_PREV
    FROM (
        SELECT
            d.ORDER_ID,
            d.PARENT_ORDER_ID,
            d.CLIENT_ORDER_TYPE,
            d.DEMAND_CLUSTER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            d.DEMAND_QTY,

            cs.CLUSTER_ID,
            cs.SUPPLY_QTY AS CLUSTER_SUPPLY,

            CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END AS PRIORITY,
            COALESCE(bcs.SCORE_RANK, 999999) AS SRC_CLUSTER_RANK,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
            ) AS cum_supply,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_supply_prev

        FROM tmp_child_demand d
        JOIN tmp_cluster_supply cs
          ON cs.ARTICLE_ID = d.ARTICLE_ID
         AND cs.BATCH_ID   = d.BATCH_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = d.PARENT_ORDER_ID
         AND bcs.CLIENT_ORDER_TYPE = d.CLIENT_ORDER_TYPE
         AND bcs.CLUSTER_ID        = cs.CLUSTER_ID
    ) z
    WHERE COALESCE(z.cum_supply_prev, 0) < z.DEMAND_QTY;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
    CREATE TEMPORARY TABLE tmp_res_bins (
        ORDER_ID VARCHAR(180) NOT NULL,
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,

        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,

        AVAIL_QTY BIGINT NOT NULL,
        LAST_TS DATETIME(3) NULL,

        PRIORITY INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,

        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY idx_rank (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK),
        KEY (BIN_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_bins
    SELECT
        d.ORDER_ID,
        d.PARENT_ORDER_ID,
        d.CLIENT_ORDER_TYPE,
        d.DEMAND_CLUSTER_ID,

        ib.CLUSTER_ID AS SRC_CLUSTER_ID,
        ib.ARTICLE_ID,
        ib.BATCH_ID,
        ib.BIN_ID,
        ib.AISLE_NUMBER,

        ib.AVAIL_QTY,
        ib.LAST_TS,

        nc.PRIORITY,
        nc.SRC_CLUSTER_RANK
    FROM tmp_child_demand d
    JOIN tmp_res_need_clusters nc
      ON nc.ORDER_ID   = d.ORDER_ID
     AND nc.ARTICLE_ID = d.ARTICLE_ID
     AND nc.BATCH_ID   = d.BATCH_ID
    
    JOIN tmp_inv_bin ib
      ON ib.ARTICLE_ID = d.ARTICLE_ID
     AND ib.BATCH_ID   = d.BATCH_ID
     AND ib.CLUSTER_ID = nc.CLUSTER_ID
    WHERE ib.AVAIL_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
    CREATE TEMPORARY TABLE tmp_res_alloc_child (
        ORDER_ID VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY (BIN_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_alloc_child
    SELECT
        rb.ORDER_ID,
        rb.ARTICLE_ID,
        rb.BATCH_ID,
        rb.BIN_ID,
        rb.AISLE_NUMBER,
        rb.SRC_CLUSTER_ID,
        rb.RESERVED_QTY
    FROM (
        SELECT
            d.ORDER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            b.BIN_ID,
            b.AISLE_NUMBER,
            b.SRC_CLUSTER_ID,
            b.AVAIL_QTY,
            b.LAST_TS,
            d.DEMAND_QTY,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
            ) AS cum_avail,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_avail_prev,

            LEAST(
                b.AVAIL_QTY,
                GREATEST(d.DEMAND_QTY - COALESCE(
                    SUM(b.AVAIL_QTY) OVER (
                        PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                        ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                    ), 0
                ), 0)
            ) AS RESERVED_QTY

        FROM tmp_child_demand d
        JOIN tmp_res_bins b
          ON b.ORDER_ID   = d.ORDER_ID
         AND b.ARTICLE_ID = d.ARTICLE_ID
         AND b.BATCH_ID   = d.BATCH_ID
    ) rb
    WHERE rb.RESERVED_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
    CREATE TEMPORARY TABLE tmp_res_shortfall (
        ORDER_ID   VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        DEMAND_QTY BIGINT NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        SHORT_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_shortfall (ORDER_ID, ARTICLE_ID, BATCH_ID, DEMAND_QTY, RESERVED_QTY, SHORT_QTY)
    SELECT
        d.ORDER_ID,
        d.ARTICLE_ID,
        d.BATCH_ID,
        d.DEMAND_QTY,
        COALESCE(a.got,0) AS RESERVED_QTY,
        GREATEST(d.DEMAND_QTY - COALESCE(a.got,0), 0) AS SHORT_QTY
    FROM tmp_child_demand d
    LEFT JOIN (
        SELECT ORDER_ID, ARTICLE_ID, BATCH_ID, SUM(RESERVED_QTY) AS got
          FROM tmp_res_alloc_child
         GROUP BY ORDER_ID, ARTICLE_ID, BATCH_ID
    ) a
      ON a.ORDER_ID = d.ORDER_ID
     AND a.ARTICLE_ID = d.ARTICLE_ID
     AND a.BATCH_ID = d.BATCH_ID
    WHERE COALESCE(a.got,0) < d.DEMAND_QTY;

END IF;


	
    

    IF v_is_dry_run = 0 THEN

        UPDATE wms_to_wcs_order_level_pre_staged_data p
        JOIN tmp_parent_orders t
          ON t.PRE_STAGED_REQ_ID = p.WMS_ORDER_REQUEST_DATA_ID
        SET p.IS_STAGED = 1,
            p.UPDATED_TIMESTAMP = CURRENT_TIMESTAMP(3),
            p.UPDATED_BY = 'SPLIT-OPS-V6';
    END IF;

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='2',
           ORDERSPLIT_ENDTIME = NOW(),
           RULE_STATS = JSON_OBJECT(
               'RULE_ID', v_rule_id,
               'RULE_LOG_ID', v_ruleLog_id,
               'RUN_PRIORITY', v_run_priority,
               'DRY_RUN', v_is_dry_run,
               'RESERVATION_KEY', v_reservation_key,
               'PARENTS_FOUND', v_parent_cnt,
               'LINES_CONSIDERED', v_line_cnt,
               'CHILD_ORDERS_CREATED', v_child_cnt,
               'MAX_ORDER_LINES_PER_ORDER', v_max_lines,
               'MAX_QUANTITY_PER_ORDER', v_max_qty,
               'TOL_LINES', v_tol_lines,
               'TOL_QTY', v_tol_qty,
               'HARD_LINES', v_hard_lines,
               'HARD_QTY', v_hard_qty,
               'SUSPEND_SHORT_LINES', v_suspend_short_lines,
               'CATEGORY_DEFAULT', 'FOOD',
               'NAMING', 'PARENT_ORDER_ID parent; ORDER_ID child/sub; SUB_ORDER_ID NOT USED',
               'STATION_PREF', JSON_OBJECT(
                   'MODE_USED', v_station_mode,
                   'USER_STATION_CNT', v_user_station_cnt,
                   'STATION_BIAS_ENABLED', v_use_station_bias
               ),
               'VALIDATIONS', JSON_OBJECT(
                   'tmp_lines', v_cnt_lines,
                   'tmp_lines_cat', v_cnt_lines_cat,
                   'tmp_line_assign', v_cnt_line_assign,
                   'tmp_ranked_lines', v_cnt_ranked,
                   'tmp_final_map', v_cnt_final,
                   'db_child_lines', v_cnt_db_child_lines
               ),
               'SUPPLY_CAP', JSON_OBJECT(
                   'ENABLED', 1,
                   'NOTE', 'Allocator decrements per SKU/BATCH/CLUSTER; assigns dominant cluster; NO_INVENTORY lines suspended'
               ),
               'RESERVATION', JSON_OBJECT(
                   'TTL_MINUTES', v_res_ttl_minutes,
                   'BLOCKED_LOCATION_EXCLUDED', 1,
                   'AUDIT_GRANULARITY', 'ORDER_ID+SKU/BATCH+BIN'
               )
           )
     WHERE ID = v_ruleLog_id;

    

    COMMIT;
    DO RELEASE_LOCK(v_lock_key);

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
        DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
        DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
        DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
        DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
        DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
		DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc_sum;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster_weight;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_group_flags;

    END;


SELECT
    v_rule_id AS RULE_ID,
    v_ruleLog_id AS RULE_LOG_ID,
    v_reservation_key AS RESERVATION_KEY,
    v_parent_cnt AS PARENTS_PROCESSED,
    v_line_cnt AS LINES_CONSIDERED,
    v_child_cnt AS CHILD_ORDERS_CREATED;



END sp_main */$$
DELIMITER ;

/* Procedure structure for procedure `sp_split_orders_ops_v15` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_split_orders_ops_v15` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sp_split_orders_ops_v15`()
sp_main: BEGIN

    
    DECLARE v_max_lines INT DEFAULT 50;
    DECLARE v_max_qty   INT DEFAULT 500;
    DECLARE v_tol_lines INT DEFAULT 10;
    DECLARE v_tol_qty   INT DEFAULT 100;

    DECLARE v_hard_lines INT DEFAULT 60;
    DECLARE v_hard_qty   INT DEFAULT 600;
	
	DECLARE v_bucketK INT DEFAULT 1;
DECLARE v_bucket_primary_cluster VARCHAR(50) DEFAULT NULL;
DECLARE v_last_bucket_parent VARCHAR(100) DEFAULT NULL;
DECLARE v_last_bucket_cat    VARCHAR(100) DEFAULT NULL;


    DECLARE v_suspend_short_lines INT DEFAULT 0;  
    DECLARE v_res_ttl_minutes INT DEFAULT 30;

    
    DECLARE v_ruleLog_id BIGINT DEFAULT NULL;
    DECLARE v_rule_id BIGINT DEFAULT NULL;
    DECLARE v_rule_defination TEXT DEFAULT NULL;

    
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_lock_key VARCHAR(128) DEFAULT NULL;

    
    DECLARE v_reservation_key VARCHAR(64) DEFAULT NULL;

    
    DECLARE v_station_mode ENUM('FINAL','INITIAL') DEFAULT NULL;
    DECLARE v_user_station_cnt BIGINT DEFAULT 0;

    
    DECLARE v_run_priority ENUM('INITIAL','FINAL') DEFAULT 'FINAL';
    DECLARE v_is_dry_run INT DEFAULT 0;

    
    DECLARE v_parent_cnt BIGINT DEFAULT 0;
    DECLARE v_line_cnt BIGINT DEFAULT 0;
    DECLARE v_child_cnt BIGINT DEFAULT 0;

    
    DECLARE v_cnt_lines BIGINT DEFAULT 0;
    DECLARE v_cnt_lines_cat BIGINT DEFAULT 0;
    DECLARE v_cnt_line_assign BIGINT DEFAULT 0;
    DECLARE v_cnt_ranked BIGINT DEFAULT 0;
    DECLARE v_cnt_final BIGINT DEFAULT 0;
    DECLARE v_cnt_db_child_lines BIGINT DEFAULT 0;

    DECLARE v_pre_lines BIGINT DEFAULT 0;
    DECLARE v_post_lines BIGINT DEFAULT 0;
    DECLARE v_pre_qty BIGINT DEFAULT 0;
    DECLARE v_post_qty BIGINT DEFAULT 0;
    DECLARE v_missing_lines BIGINT DEFAULT 0;

    DECLARE v_errmsg TEXT DEFAULT '';

    
    DECLARE v_has_or_cluster INT DEFAULT 0;
    DECLARE v_has_ol_cluster INT DEFAULT 0;

    DECLARE v_has_reco_col INT DEFAULT 0;   
    DECLARE v_has_reco1 INT DEFAULT 0;      
    DECLARE v_has_reco2 INT DEFAULT 0;      
    DECLARE v_has_reco1_alt INT DEFAULT 0;  
    DECLARE v_has_reco2_alt INT DEFAULT 0;  

    DECLARE v_has_hw_station INT DEFAULT 0;
    DECLARE v_has_hw_wave_status INT DEFAULT 0;

    
    DECLARE v_sku   VARCHAR(200) DEFAULT NULL;
    DECLARE v_batch VARCHAR(200) DEFAULT NULL;

    DECLARE v_rn INT DEFAULT 0;
    DECLARE v_maxrn INT DEFAULT 0;

    DECLARE v_line_parent VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_cat    VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_id     VARCHAR(36)  DEFAULT NULL;
    DECLARE v_line_qty    INT DEFAULT 0;

    DECLARE v_pick_cluster VARCHAR(50) DEFAULT NULL;

    DECLARE v_need BIGINT DEFAULT 0;
    DECLARE v_total_rem BIGINT DEFAULT 0;

    DECLARE v_crn INT DEFAULT 0;
    DECLARE v_cmax INT DEFAULT 0;
    DECLARE v_cur_cluster VARCHAR(50) DEFAULT NULL;
    DECLARE v_cur_rem BIGINT DEFAULT 0;
    DECLARE v_alloc BIGINT DEFAULT 0;

    
    DECLARE v_balance_mode INT DEFAULT 1;   
    DECLARE v_k1_pool INT DEFAULT 1;        

    
    DECLARE v_use_station_bias INT DEFAULT 0;   
    DECLARE v_near_aisle_window INT DEFAULT 1;  
    DECLARE v_min_pref_aisle INT DEFAULT NULL;
    DECLARE v_max_pref_aisle INT DEFAULT NULL;

    DECLARE v_total_lines_all BIGINT DEFAULT 0;
    DECLARE v_total_qty_all BIGINT DEFAULT 0;
    DECLARE v_total_lines_pickable BIGINT DEFAULT 0;
    DECLARE v_total_qty_pickable BIGINT DEFAULT 0;
    DECLARE v_alloc_qty_total BIGINT DEFAULT 0;
    DECLARE v_alloc_lines_total BIGINT DEFAULT 0;
    
	    
    DECLARE v_tmp_user_stations_ready INT DEFAULT 0;
        
    DECLARE v_lock_wait_seconds INT DEFAULT -1;

    
    DECLARE v_station_pref_consumed INT DEFAULT 0;

    
    DECLARE v_job_id BIGINT DEFAULT NULL;
    DECLARE v_job_rule_id BIGINT DEFAULT NULL;
    DECLARE v_job_priority ENUM('INITIAL','FINAL') DEFAULT NULL;



    
       
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;

        
        IF v_rule_id IS NOT NULL
           AND v_station_mode IS NOT NULL
           AND v_user_station_cnt > 0
           AND v_tmp_user_stations_ready = 1
        THEN
            UPDATE picklist_split_station_pref p
            JOIN tmp_user_stations t
              ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
            SET p.IS_PROCESSED = 0
            WHERE p.RULE_ID = v_rule_id
              AND p.PRIORITY = v_station_mode
              AND p.IS_PROCESSED = 1;
        END IF;

        
        IF v_ruleLog_id IS NOT NULL THEN
            UPDATE picklist_split_order_master
               SET IS_PROCESSED = '0',
                   ORDERSPLIT_ENDTIME = NOW()
             WHERE ID = v_ruleLog_id;
        END IF;

        
        
DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;

DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;       
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;     
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;      

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_final_map;

DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2;

DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;

DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;

DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc_sum;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster_weight;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_group_flags;


        
        IF v_lock_ok = 1 AND v_lock_key IS NOT NULL THEN
            DO RELEASE_LOCK(v_lock_key);
        END IF;

        RESIGNAL;
    END;


    

    SET v_max_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_ORDER_LINES_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_lines
    );

    SET v_max_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_QUANTITY_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_qty
    );

    SET v_near_aisle_window = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_NEAR_AISLE_WINDOW' AND IS_ACTIVE = 1
          LIMIT 1),
        v_near_aisle_window
    );
    SET v_near_aisle_window = GREATEST(v_near_aisle_window, 0);

    SET v_tol_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_lines
    );

    SET v_tol_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_QTY' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_qty
    );

    SET v_suspend_short_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'SUSPEND_SHORT_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_suspend_short_lines
    );

    SET v_res_ttl_minutes = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'RESERVATION_TTL_MINUTES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_res_ttl_minutes
    );

    SET v_balance_mode = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_BALANCE_MODE' AND IS_ACTIVE = 1
          LIMIT 1),
        v_balance_mode
    );

    SET v_k1_pool = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_K1_POOL' AND IS_ACTIVE = 1
          LIMIT 1),
        v_k1_pool
    );
    SET v_k1_pool = GREATEST(v_k1_pool, 1);

        
    SET v_max_lines = GREATEST(v_max_lines, 1);
    SET v_max_qty   = GREATEST(v_max_qty,   1);
    SET v_tol_lines = GREATEST(v_tol_lines, 0);
    SET v_tol_qty   = GREATEST(v_tol_qty,   0);

    SET v_hard_lines = v_max_lines + v_tol_lines;
    SET v_hard_qty   = v_max_qty   + v_tol_qty;


    

    SELECT COUNT(*) INTO v_has_or_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_ol_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_line_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_reco_col
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'RECOMMENDATION';

    SELECT COUNT(*) INTO v_has_reco1
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_1';

    SELECT COUNT(*) INTO v_has_reco2
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_2';

    SELECT COUNT(*) INTO v_has_reco1_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_1';

    SELECT COUNT(*) INTO v_has_reco2_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_2';

    SELECT COUNT(*) INTO v_has_hw_station
      FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master';

    SELECT COUNT(*) INTO v_has_hw_wave_status
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master'
       AND COLUMN_NAME  = 'wave_status';

          

    job_pick: LOOP

        SET v_job_id = NULL;
        SET v_job_rule_id = NULL;
        SET v_job_priority = NULL;

        
        SELECT
            ID,
            RULE_ID,
            CASE
                WHEN COALESCE(NULLIF(PRIORITY,''),'FINAL') IN ('FINAL','INITIAL')
                    THEN COALESCE(NULLIF(PRIORITY,''),'FINAL')
                ELSE 'FINAL'
            END
          INTO v_job_id, v_job_rule_id, v_job_priority
        FROM picklist_split_order_master
        WHERE IS_PROCESSED = '0'
        ORDER BY ID
        LIMIT 1;

        IF v_job_id IS NULL OR v_job_rule_id IS NULL THEN

    
    SET @reco1_cluster_json := JSON_ARRAY(
        JSON_OBJECT(
            'CLUSTER_ID',  'NA',
            'STATION_ID',  '0',
            'STATION_CNT', 0,
            'ORDER_LINES', 0,
            '%_LINES',     0.00,
            'ORDER_QTY',   0,
            '%_QTY',       0.00
        )
    );

    SET @reco2_cluster_json := @reco1_cluster_json;

    SET @dummy_master_reco := JSON_OBJECT(
        'RECOMMENDATION_1_ALL_STATIONS',          CAST(@reco1_cluster_json AS JSON),
        'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

        'STATION_PREF_MODE', NULL,
        'USER_SELECTED_STATIONS', '',
        'RULE_ID', NULL,
        'RULE_LOG_ID', NULL,
        'TOTAL_INITIAL_ORDERS', 0,
        'TOTAL_SPLIT_ORDERS',  0,

        'INITIAL_ORDER_LINES', 0,
        'AFTER_ALLOCATION_ORDER_LINES', 0,
        'TOTAL_LINES_PICKABLE', 0,

        'TOTAL_QTY_ALL', 0,
        'TOTAL_QTY_PICKABLE', 0,
        'ALLOC_QTY_TOTAL', 0,
        'ALLOC_LINES_TOTAL', 0,

        'NOTES', JSON_OBJECT(
            'PARENT_FIELD', 'PARENT_ORDER_ID',
            'CHILD_FIELD',  'ORDER_ID',
            'SUB_ORDER_ID', 'NOT_USED',
            'RESERVATION_KEY', '',
            'RESERVATION_TTL_MINUTES', 0,
            'DUMMY', 1
        )
    );

    
    SELECT
        'NO_RULE_TO_PROCESS' AS STATUS,
        CAST(@reco1_cluster_json AS JSON) AS recommendation_1,
        CAST(@reco2_cluster_json AS JSON) AS recommendation_2,
        CAST(@dummy_master_reco  AS JSON) AS RECOMMENDATION;

    LEAVE sp_main;
END IF;


        
        SET v_lock_key = CONCAT('SPLIT_CLUSTER_', v_job_rule_id);
        SELECT GET_LOCK(v_lock_key, v_lock_wait_seconds) INTO v_lock_ok;

        IF v_lock_ok IS NULL THEN
            SET v_errmsg = CONCAT('GET_LOCK_ERROR: key=', v_lock_key);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        ELSEIF v_lock_ok = 0 THEN
            
            SET v_errmsg = CONCAT('Split job already running (lock timeout) for RULE_ID=', v_job_rule_id);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        END IF;

        
        START TRANSACTION;

        SELECT
            ID,
            RULE_ID,
            v_job_priority
          INTO v_ruleLog_id, v_rule_id, v_run_priority
        FROM picklist_split_order_master
        WHERE ID = v_job_id
          AND IS_PROCESSED = '0'
        FOR UPDATE SKIP LOCKED;

        
        IF v_ruleLog_id IS NULL OR v_rule_id IS NULL THEN
            ROLLBACK;
            DO RELEASE_LOCK(v_lock_key);
            SET v_lock_ok = 0;
            ITERATE job_pick;
        END IF;

        LEAVE job_pick;
    END LOOP;

    
    SET v_is_dry_run = CASE WHEN v_run_priority = 'INITIAL' THEN 1 ELSE 0 END;

    
    IF v_is_dry_run = 1 THEN
        SET v_balance_mode = 0;
        SET v_k1_pool      = 1;
    END IF;



        

    SELECT FILTER_CONDITION
      INTO v_rule_defination
    FROM pick_rule_master
    WHERE PICK_RULE_ID = v_rule_id
    LIMIT 1;

    IF v_rule_defination IS NULL OR LENGTH(v_rule_defination) < 3 THEN
        
        UPDATE picklist_split_order_master
           SET IS_PROCESSED = '2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        COMMIT;
        DO RELEASE_LOCK(v_lock_key);

        SELECT 'NO_RULE_DEFINITION_FOUND' AS STATUS, v_rule_id AS RULE_ID;
        LEAVE sp_main;
    END IF;

    
    SET v_rule_defination = LEFT(v_rule_defination, LENGTH(v_rule_defination)-1);


    

SET v_station_mode = NULL;
SET v_user_station_cnt = 0;
SET v_station_pref_consumed = 0;   


IF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'FINAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'FINAL';
ELSEIF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'INITIAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'INITIAL';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
CREATE TEMPORARY TABLE tmp_user_stations (
    STATION_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (STATION_ID)
) ENGINE=INNODB;

SET v_tmp_user_stations_ready = 1;

IF v_station_mode IS NOT NULL THEN

    
    INSERT IGNORE INTO tmp_user_stations (STATION_ID)
    SELECT CAST(STATION_ID AS CHAR(50))
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND PRIORITY = v_station_mode
       AND IS_PROCESSED = 0
     ORDER BY STATION_ID
     FOR UPDATE;

    SELECT COUNT(*) INTO v_user_station_cnt FROM tmp_user_stations;

END IF;


SET v_use_station_bias =
    CASE
        WHEN v_is_dry_run = 0 AND v_user_station_cnt > 0 AND v_has_hw_station = 1 THEN 1
        ELSE 0
    END;



DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
CREATE TEMPORARY TABLE tmp_pref_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
CREATE TEMPORARY TABLE tmp_near_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_pref_clusters (CLUSTER_ID)
    SELECT DISTINCT CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.CLUSTER_ID IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
    CREATE TEMPORARY TABLE tmp_pref_aisle_num (
        AISLE_NUM INT NOT NULL,
        PRIMARY KEY (AISLE_NUM)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_pref_aisle_num (AISLE_NUM)
    SELECT DISTINCT
           CAST(
               NULLIF(
                   REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                   ''
               ) AS UNSIGNED
           ) AS AISLE_NUM
      FROM cluster_aisle_mapping cam
      JOIN tmp_pref_clusters pc
        ON pc.CLUSTER_ID = cam.CLUSTER_ID
     WHERE cam.AISLE_NUMBER IS NOT NULL;

    
    SELECT MIN(AISLE_NUM), MAX(AISLE_NUM)
      INTO v_min_pref_aisle, v_max_pref_aisle
      FROM tmp_pref_aisle_num;

    IF v_min_pref_aisle IS NOT NULL AND v_max_pref_aisle IS NOT NULL THEN

        
        INSERT IGNORE INTO tmp_near_clusters (CLUSTER_ID)
        SELECT DISTINCT cam.CLUSTER_ID
          FROM cluster_aisle_mapping cam
         WHERE cam.CLUSTER_ID IS NOT NULL
           AND cam.AISLE_NUMBER IS NOT NULL
           AND CAST(
                   NULLIF(
                       REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                       ''
                   ) AS UNSIGNED
               ) BETWEEN (v_min_pref_aisle - v_near_aisle_window)
                   AND (v_max_pref_aisle + v_near_aisle_window);

        
        DELETE n
          FROM tmp_near_clusters n
          JOIN tmp_pref_clusters p
            ON p.CLUSTER_ID = n.CLUSTER_ID;

    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;

END IF;




DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
CREATE TEMPORARY TABLE tmp_parent_orders (
    PRE_STAGED_REQ_ID BIGINT NOT NULL,
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    ORDER_TYPE        VARCHAR(100) NOT NULL,
    PRIMARY KEY (PRE_STAGED_REQ_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;


IF v_rule_defination IS NULL OR LENGTH(TRIM(v_rule_defination)) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULE_DEFINITION_EMPTY';
END IF;

SET @sql = CONCAT(
    'INSERT INTO tmp_parent_orders (PRE_STAGED_REQ_ID, PARENT_ORDER_ID, ORDER_TYPE)
     SELECT WMS_ORDER_REQUEST_DATA_ID,
            PARENT_ORDER_ID,
            COALESCE(NULLIF(PICKING_TYPE, ''''), NULLIF(ORDER_CATEGORY, ''''), ''PICK'') AS ORDER_TYPE
       FROM wms_to_wcs_order_level_pre_staged_data
      WHERE IFNULL(IS_STAGED,0) = 0
        AND PARENT_ORDER_ID IN (', v_rule_defination, ')'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT COUNT(*) INTO v_parent_cnt FROM tmp_parent_orders;

IF v_parent_cnt = 0 THEN

    
    IF v_station_pref_consumed = 1
       AND v_rule_id IS NOT NULL
       AND v_station_mode IS NOT NULL
       AND v_tmp_user_stations_ready = 1
    THEN
        UPDATE picklist_split_station_pref p
        JOIN tmp_user_stations t
          ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
        SET p.IS_PROCESSED = 0
        WHERE p.RULE_ID = v_rule_id
          AND p.PRIORITY = v_station_mode
          AND p.IS_PROCESSED = 1;

        SET v_station_pref_consumed = 0;
    END IF;

    
    
    SET v_line_cnt = 0;

    
    IF v_reservation_key IS NULL OR v_reservation_key = '' THEN
        SET v_reservation_key = CONCAT('SPLIT_', COALESCE(v_ruleLog_id,0), '_', REPLACE(UUID(),'-',''));
    END IF;

    SET @reco1_cluster_json := JSON_ARRAY(
        JSON_OBJECT(
            'CLUSTER_ID',  'NA',
            'STATION_ID',  '0',
            'STATION_CNT', 0,
            'ORDER_LINES', 0,
            '%_LINES',     0.00,
            'ORDER_QTY',   0,
            '%_QTY',       0.00
        )
    );
    SET @reco2_cluster_json := @reco1_cluster_json;

    SET @dummy_user_selected := '';
    IF v_tmp_user_stations_ready = 1 THEN
        SELECT COALESCE(GROUP_CONCAT(STATION_ID ORDER BY STATION_ID SEPARATOR ','), '')
          INTO @dummy_user_selected
          FROM tmp_user_stations;
    END IF;

    SET @dummy_master_reco := JSON_OBJECT(
        'RECOMMENDATION_1_ALL_STATIONS',          CAST(@reco1_cluster_json AS JSON),
        'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

        'STATION_PREF_MODE', v_station_mode,
        'USER_SELECTED_STATIONS', @dummy_user_selected,
        'RULE_ID', v_rule_id,
        'RULE_LOG_ID', v_ruleLog_id,
        'TOTAL_INITIAL_ORDERS', v_parent_cnt,
        'TOTAL_SPLIT_ORDERS',  0,

        'INITIAL_ORDER_LINES', v_line_cnt,
        'AFTER_ALLOCATION_ORDER_LINES', 0,
        'TOTAL_LINES_PICKABLE', 0,

        'TOTAL_QTY_ALL', 0,
        'TOTAL_QTY_PICKABLE', 0,
        'ALLOC_QTY_TOTAL', 0,
        'ALLOC_LINES_TOTAL', 0,

        'NOTES', JSON_OBJECT(
            'PARENT_FIELD', 'PARENT_ORDER_ID',
            'CHILD_FIELD',  'ORDER_ID',
            'SUB_ORDER_ID', 'NOT_USED',
            'RESERVATION_KEY', COALESCE(v_reservation_key,''),
            'RESERVATION_TTL_MINUTES', v_res_ttl_minutes,
            'DUMMY', 1,
            'REASON', 'NO_PARENTS_TO_SPLIT'
        )
    );

    
    IF v_ruleLog_id IS NOT NULL THEN

        IF v_has_reco1 = 1 OR v_has_reco1_alt = 1 THEN
            UPDATE picklist_split_order_master
               SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

        IF v_has_reco2 = 1 OR v_has_reco2_alt = 1 THEN
            UPDATE picklist_split_order_master
               SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

        IF v_has_reco_col = 1 THEN
            UPDATE picklist_split_order_master
               SET RECOMMENDATION = CAST(@dummy_master_reco AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

    END IF;

    
    UPDATE picklist_split_order_master
       SET IS_PROCESSED = '2',
           ORDERSPLIT_ENDTIME = NOW()
     WHERE ID = v_ruleLog_id;

    COMMIT;

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
    END;

    DO RELEASE_LOCK(v_lock_key);

    SELECT 'NO_PARENTS_TO_SPLIT' AS STATUS, v_rule_id AS RULE_ID;
    LEAVE sp_main;
END IF;


UPDATE picklist_split_order_master
   SET IS_PROCESSED = '1',
       ORDERSPLIT_STARTTIME = NOW()
 WHERE ID = v_ruleLog_id
   AND IS_PROCESSED = '0';

IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULELOG_NOT_IN_STARTABLE_STATE';
END IF;


IF v_station_mode IS NOT NULL
   AND v_user_station_cnt > 0
   AND v_tmp_user_stations_ready = 1
THEN
    UPDATE picklist_split_station_pref p
    JOIN tmp_user_stations t
      ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
    SET p.IS_PROCESSED = 1
    WHERE p.RULE_ID = v_rule_id
      AND p.PRIORITY = v_station_mode
      AND p.IS_PROCESSED = 0;

    SET v_station_pref_consumed = 1;
END IF;


SET v_reservation_key = CONCAT('SPLIT_', v_ruleLog_id, '_', REPLACE(UUID(),'-',''));



DROP TEMPORARY TABLE IF EXISTS tmp_lines;
CREATE TEMPORARY TABLE tmp_lines (
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
    ARTICLE_ID      VARCHAR(200) NULL,
    BATCH_ID        VARCHAR(200) NULL,
    QUANTITY        INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_lines
SELECT
    l.PARENT_ORDER_ID,
    l.ORDER_LINE_ID,
    l.ARTICLE_ID,
    l.BATCH_ID,
    l.QUANTITY,
    l.DISPLAY_OPERATOR_INSTRUCTION
FROM wms_to_wcs_order_line_level_pre_staged_data l
JOIN tmp_parent_orders p
  ON p.PARENT_ORDER_ID = l.PARENT_ORDER_ID
WHERE IFNULL(l.ORDER_LINE_PROCESS_STATUS,'PENDING') <> 'DELETED';

SELECT COUNT(*) INTO v_line_cnt FROM tmp_lines;

IF v_line_cnt = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'NO_LINES_FOUND_FOR_SELECTED_PARENTS';
END IF;



    

    DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
    CREATE TEMPORARY TABLE tmp_line_category (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (ARTICLE_ID),
        KEY (CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_category (ARTICLE_ID, CLIENT_ORDER_TYPE)
    SELECT
        al.ARTICLE_ID,
        COALESCE(NULLIF(cm.CLIENT_ORDER_TYPE,''), 'FOOD') AS CLIENT_ORDER_TYPE
    FROM (SELECT DISTINCT ARTICLE_ID FROM tmp_lines WHERE ARTICLE_ID IS NOT NULL) al
    LEFT JOIN sku_master sm
      ON sm.SKU_ID = al.ARTICLE_ID
    LEFT JOIN category_master cm
      ON cm.CATEGORY_ID = sm.CATEGORY;

    DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
    CREATE TEMPORARY TABLE tmp_lines_cat (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines_cat
    SELECT
        tl.PARENT_ORDER_ID,
        COALESCE(lc.CLIENT_ORDER_TYPE, 'FOOD') AS CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION
    FROM tmp_lines tl
    LEFT JOIN tmp_line_category lc
      ON lc.ARTICLE_ID = tl.ARTICLE_ID;

    
    SELECT COUNT(*) INTO v_cnt_lines     FROM tmp_lines;
    SELECT COUNT(*) INTO v_cnt_lines_cat FROM tmp_lines_cat;

    IF v_cnt_lines_cat <> v_cnt_lines THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_CATEGORY: tmp_lines=', v_cnt_lines,
                              ', tmp_lines_cat=', v_cnt_lines_cat);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

 


DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
CREATE TEMPORARY TABLE tmp_aisle_cluster_raw (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER, CLUSTER_ID),
    KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster_raw (AISLE_NUMBER, CLUSTER_ID)
SELECT DISTINCT AISLE_NUMBER, CLUSTER_ID
  FROM cluster_aisle_mapping
 WHERE AISLE_NUMBER IS NOT NULL
   AND CLUSTER_ID IS NOT NULL;

IF (SELECT COUNT(*) FROM tmp_aisle_cluster_raw) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: cluster_aisle_mapping has no AISLE_NUMBER->CLUSTER_ID rows';
END IF;

IF EXISTS (
    SELECT 1
      FROM (
            SELECT AISLE_NUMBER, COUNT(*) AS c
              FROM tmp_aisle_cluster_raw
             GROUP BY AISLE_NUMBER
            HAVING c > 1
      ) X
    LIMIT 1
) THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: AISLE_NUMBER maps to multiple CLUSTER_ID in cluster_aisle_mapping';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
CREATE TEMPORARY TABLE tmp_aisle_cluster (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster (AISLE_NUMBER, CLUSTER_ID)
SELECT AISLE_NUMBER, CLUSTER_ID
  FROM tmp_aisle_cluster_raw;




DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
CREATE TEMPORARY TABLE tmp_sku_global (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_global
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_lines_cat
 WHERE ARTICLE_ID IS NOT NULL AND BATCH_ID IS NOT NULL;

DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
CREATE TEMPORARY TABLE tmp_inv_bin (
    BIN_ID INT NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    AVAIL_QTY BIGINT NOT NULL,
    LAST_TS DATETIME(3) NULL,
    PRIMARY KEY (BIN_ID, ARTICLE_ID, BATCH_ID),

    KEY (ARTICLE_ID, BATCH_ID),
    KEY (CLUSTER_ID),
    KEY (AISLE_NUMBER),

    
    KEY idx_ab_cluster (ARTICLE_ID, BATCH_ID, CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_inv_bin (BIN_ID, ARTICLE_ID, BATCH_ID, AISLE_NUMBER, CLUSTER_ID, AVAIL_QTY, LAST_TS)
SELECT
    lim.BIN_ID,
    lim.ARTICLE_ID,
    lim.BATCH_ID,
    lmst.AISLE_NUMBER,
    ac.CLUSTER_ID,
    GREATEST(
        CAST(SUM(GREATEST(lim.QUANTITY - lim.VIRTUAL_QUANTITY_TO_PICK, 0)) AS SIGNED),
        0
    ) AS AVAIL_QTY,
    MAX(lim.UPDATED_TIMESTAMP) AS LAST_TS
FROM live_inventory_master lim
JOIN tmp_sku_global sg
  ON sg.ARTICLE_ID = lim.ARTICLE_ID
 AND sg.BATCH_ID   = lim.BATCH_ID
JOIN store_bin_master sb
  ON sb.BIN_ID = lim.BIN_ID
JOIN location_master lmst
  ON lmst.LOCATION_ID = sb.LOCATION_ID
LEFT JOIN location_block_master lb
  ON lb.LOCATION_ID = sb.LOCATION_ID
JOIN tmp_aisle_cluster ac
  ON ac.AISLE_NUMBER = lmst.AISLE_NUMBER
WHERE lim.IS_ACTIVE = 1
  AND lim.BIN_ID IS NOT NULL
  AND lmst.AISLE_NUMBER IS NOT NULL
  AND lb.LOCATION_ID IS NULL
GROUP BY lim.BIN_ID, lim.ARTICLE_ID, lim.BATCH_ID, lmst.AISLE_NUMBER, ac.CLUSTER_ID
HAVING AVAIL_QTY > 0;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
CREATE TEMPORARY TABLE tmp_cluster_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply (ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY)
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUM(AVAIL_QTY) AS SUPPLY_QTY
  FROM tmp_inv_bin
 GROUP BY ARTICLE_ID, BATCH_ID, CLUSTER_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
CREATE TEMPORARY TABLE tmp_sku_total_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_SUPPLY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_total_supply
SELECT ARTICLE_ID, BATCH_ID, SUM(SUPPLY_QTY) AS TOTAL_SUPPLY
  FROM tmp_cluster_supply
 GROUP BY ARTICLE_ID, BATCH_ID;




DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
CREATE TEMPORARY TABLE tmp_final_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    CL_NUM     INT NULL,
    PRIMARY KEY (CLUSTER_ID),
    KEY (CL_NUM)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
CREATE TEMPORARY TABLE tmp_cluster_snap_map (
    SRC_CLUSTER_ID      VARCHAR(50) NOT NULL,
    SNAPPED_CLUSTER_ID  VARCHAR(50) NOT NULL,
    PRIMARY KEY (SRC_CLUSTER_ID),
    KEY (SNAPPED_CLUSTER_ID)
) ENGINE=INNODB;


DROP TEMPORARY TABLE IF EXISTS tmp_final_cluster_default;
CREATE TEMPORARY TABLE tmp_final_cluster_default (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_final_clusters (CLUSTER_ID, CL_NUM)
    SELECT
        pc.CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(pc.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS CL_NUM
    FROM tmp_pref_clusters pc
    WHERE pc.CLUSTER_ID IS NOT NULL;

    
    IF (SELECT COUNT(*) FROM tmp_final_clusters) = 0 THEN
        SET v_use_station_bias = 0;
    END IF;

    
    IF v_use_station_bias = 1 THEN
        INSERT INTO tmp_final_cluster_default (CLUSTER_ID)
        SELECT fc.CLUSTER_ID
          FROM tmp_final_clusters fc
         ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
         LIMIT 1;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;
    CREATE TEMPORARY TABLE tmp_supply_clusters (
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        SRC_NUM        INT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID),
        KEY (SRC_NUM)
    ) ENGINE=INNODB;

    INSERT INTO tmp_supply_clusters (SRC_CLUSTER_ID, SRC_NUM)
    SELECT DISTINCT
        cs.CLUSTER_ID AS SRC_CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(cs.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS SRC_NUM
    FROM tmp_cluster_supply cs;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    CREATE TEMPORARY TABLE tmp_snap_candidates (
        SRC_CLUSTER_ID   VARCHAR(50) NOT NULL,
        CAND_CLUSTER_ID  VARCHAR(50) NOT NULL,
        RN               INT NOT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID, RN),
        KEY (CAND_CLUSTER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_snap_candidates (SRC_CLUSTER_ID, CAND_CLUSTER_ID, RN)
    SELECT
        sc.SRC_CLUSTER_ID,
        fc.CLUSTER_ID AS CAND_CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY sc.SRC_CLUSTER_ID
            ORDER BY
                ABS(COALESCE(fc.CL_NUM,0) - COALESCE(sc.SRC_NUM,0)),
                
                CASE WHEN COALESCE(fc.CL_NUM,0) >= COALESCE(sc.SRC_NUM,0) THEN 0 ELSE 1 END,
                COALESCE(fc.CL_NUM,0),
                fc.CLUSTER_ID
        ) AS RN
    FROM tmp_supply_clusters sc
    JOIN tmp_final_clusters fc
      ON 1=1;

    
    INSERT IGNORE INTO tmp_cluster_snap_map (SRC_CLUSTER_ID, SNAPPED_CLUSTER_ID)
    SELECT
        sc.SRC_CLUSTER_ID,
        CASE
            WHEN fc_same.CLUSTER_ID IS NOT NULL THEN sc.SRC_CLUSTER_ID
            ELSE COALESCE(c.CAND_CLUSTER_ID, d.CLUSTER_ID)
        END AS SNAPPED_CLUSTER_ID
    FROM tmp_supply_clusters sc
    LEFT JOIN tmp_final_clusters fc_same
      ON fc_same.CLUSTER_ID = sc.SRC_CLUSTER_ID
    LEFT JOIN tmp_snap_candidates c
      ON c.SRC_CLUSTER_ID = sc.SRC_CLUSTER_ID
     AND c.RN = 1
    LEFT JOIN tmp_final_cluster_default d
      ON 1=1;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;

END IF;


    

    

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
CREATE TEMPORARY TABLE tmp_line_cluster_candidates (
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    ORDER_LINE_ID VARCHAR(36) NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    C_RANK INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, C_RANK)
) ENGINE=INNODB;

INSERT INTO tmp_line_cluster_candidates
SELECT
    lc.PARENT_ORDER_ID,
    lc.CLIENT_ORDER_TYPE,
    lc.ORDER_LINE_ID,
    lc.ARTICLE_ID,
    lc.BATCH_ID,
    cs.CLUSTER_ID,
    cs.SUPPLY_QTY,
    ROW_NUMBER() OVER (
        PARTITION BY lc.PARENT_ORDER_ID, lc.CLIENT_ORDER_TYPE, lc.ORDER_LINE_ID
        ORDER BY
            cs.SUPPLY_QTY DESC,
            
            CRC32(CONCAT(
                lc.PARENT_ORDER_ID, '|',
                lc.CLIENT_ORDER_TYPE, '|',
                lc.ORDER_LINE_ID, '|',
                cs.CLUSTER_ID
            ))
    ) AS C_RANK
FROM tmp_lines_cat lc
JOIN tmp_cluster_supply cs
  ON cs.ARTICLE_ID = lc.ARTICLE_ID
 AND cs.BATCH_ID   = lc.BATCH_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
CREATE TEMPORARY TABLE tmp_line_assign (
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    ORDER_LINE_ID VARCHAR(36) NOT NULL,
    ARTICLE_ID VARCHAR(200) NULL,
    BATCH_ID   VARCHAR(200) NULL,
    QUANTITY   INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

    ASSIGNED_CLUSTER_ID VARCHAR(50) NULL,
    ASSIGNED_RANK INT NOT NULL DEFAULT 0,

    SHORT_FLAG_SCHEMA INT NOT NULL DEFAULT 0,
    SHORT_FLAG_SUPPLY INT NOT NULL DEFAULT 0,
    SHORT_FLAG INT NOT NULL DEFAULT 0,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
    UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_line_assign
SELECT
    lc.PARENT_ORDER_ID,
    lc.CLIENT_ORDER_TYPE,
    lc.ORDER_LINE_ID,
    lc.ARTICLE_ID,
    lc.BATCH_ID,
    lc.QUANTITY,
    lc.DISPLAY_OPERATOR_INSTRUCTION,
    NULL, 0,
    0, 0, 0
FROM tmp_lines_cat lc;

UPDATE tmp_line_assign la
LEFT JOIN tmp_sku_total_supply ts
  ON ts.ARTICLE_ID = la.ARTICLE_ID
 AND ts.BATCH_ID   = la.BATCH_ID
SET la.SHORT_FLAG_SCHEMA = CASE
    WHEN la.ARTICLE_ID IS NULL OR la.BATCH_ID IS NULL THEN 1
    WHEN ts.TOTAL_SUPPLY IS NULL THEN 1
    ELSE 0
END;

SELECT COUNT(*) INTO v_cnt_line_assign FROM tmp_line_assign;
IF v_cnt_line_assign <> v_cnt_lines_cat THEN
    SET v_errmsg = CONCAT('LINE_LOSS_AFTER_ASSIGN: tmp_lines_cat=', v_cnt_lines_cat,
                          ', tmp_line_assign=', v_cnt_line_assign);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
END IF;




DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
CREATE TEMPORARY TABLE tmp_bucket_k (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    TOTAL_LINES         BIGINT NOT NULL,
    TOTAL_QTY           BIGINT NOT NULL,
    K                   INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_k (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, TOTAL_LINES, TOTAL_QTY, K)
SELECT
    la.PARENT_ORDER_ID,
    la.CLIENT_ORDER_TYPE,
    COUNT(*) AS TOTAL_LINES,
    COALESCE(SUM(la.QUANTITY),0) AS TOTAL_QTY,
    GREATEST(
        1,
        IF(v_max_lines > 0, CEIL(COUNT(*) / v_max_lines), 1),
        IF(v_max_qty   > 0, CEIL(COALESCE(SUM(la.QUANTITY),0) / v_max_qty), 1)
    ) AS K
FROM tmp_line_assign la
GROUP BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
CREATE TEMPORARY TABLE tmp_bucket_cluster_score (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    BEST_LINE_CNT       BIGINT NOT NULL,
    BEST_QTY_FIT        BIGINT NOT NULL,
    SCORE               DECIMAL(30,0) NOT NULL,
    SCORE_RANK          INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SCORE_RANK),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_cluster_score
SELECT
    x.PARENT_ORDER_ID,
    x.CLIENT_ORDER_TYPE,
    x.CLUSTER_ID,
    x.BEST_LINE_CNT,
    x.BEST_QTY_FIT,
    (x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT AS SCORE,
    ROW_NUMBER() OVER (
        PARTITION BY x.PARENT_ORDER_ID, x.CLIENT_ORDER_TYPE
        ORDER BY ((x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT) DESC,
                 
                 CRC32(CONCAT(x.PARENT_ORDER_ID,'|',x.CLIENT_ORDER_TYPE,'|',x.CLUSTER_ID))
    ) AS SCORE_RANK
FROM (
    SELECT
        c.PARENT_ORDER_ID,
        c.CLIENT_ORDER_TYPE,
        c.CLUSTER_ID,
        SUM(CASE WHEN c.C_RANK = 1 THEN 1 ELSE 0 END) AS BEST_LINE_CNT,
        SUM(CASE
                WHEN c.C_RANK = 1 THEN LEAST(c.SUPPLY_QTY, la.QUANTITY)
                ELSE 0
            END) AS BEST_QTY_FIT
    FROM tmp_line_cluster_candidates c
    JOIN tmp_line_assign la
      ON la.PARENT_ORDER_ID = c.PARENT_ORDER_ID
     AND la.CLIENT_ORDER_TYPE = c.CLIENT_ORDER_TYPE
     AND la.ORDER_LINE_ID = c.ORDER_LINE_ID
    GROUP BY c.PARENT_ORDER_ID, c.CLIENT_ORDER_TYPE, c.CLUSTER_ID
) X;

DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
CREATE TEMPORARY TABLE tmp_allowed_clusters (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
SELECT
    s.PARENT_ORDER_ID,
    s.CLIENT_ORDER_TYPE,
    s.CLUSTER_ID
FROM tmp_bucket_cluster_score s
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
WHERE s.SCORE_RANK <= CASE
    WHEN v_balance_mode = 1 AND k.K = 1 THEN GREATEST(k.K, v_k1_pool)
    ELSE k.K
END;

IF (SELECT COUNT(*) FROM tmp_allowed_clusters) = 0 THEN
    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
      FROM tmp_bucket_cluster_score;
END IF;


IF v_use_station_bias = 1 THEN

    DELETE ac
      FROM tmp_allowed_clusters ac
      LEFT JOIN tmp_final_clusters fc
        ON fc.CLUSTER_ID = ac.CLUSTER_ID
     WHERE fc.CLUSTER_ID IS NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
    CREATE TEMPORARY TABLE tmp_empty_buckets (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_empty_buckets (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    SELECT bk.PARENT_ORDER_ID, bk.CLIENT_ORDER_TYPE
      FROM tmp_bucket_k bk
      LEFT JOIN tmp_allowed_clusters ac2
        ON ac2.PARENT_ORDER_ID   = bk.PARENT_ORDER_ID
       AND ac2.CLIENT_ORDER_TYPE = bk.CLIENT_ORDER_TYPE
     WHERE ac2.PARENT_ORDER_ID IS NULL;

    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT eb.PARENT_ORDER_ID, eb.CLIENT_ORDER_TYPE, fc2.CLUSTER_ID
      FROM tmp_empty_buckets eb
      CROSS JOIN tmp_final_clusters fc2;

    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
CREATE TEMPORARY TABLE tmp_bucket_choice (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CHOSEN_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CHOSEN_CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_choice
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    MAX(CASE WHEN rn = 1 + MOD(bucket_hash, pool_cnt) THEN CLUSTER_ID END) AS CHOSEN_CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK,
                     
                     CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE,'|',s.CLUSTER_ID))
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
        ) AS pool_cnt,
        CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE)) AS bucket_hash
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
      AND s.SCORE_RANK <= v_k1_pool
) X
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;


INSERT IGNORE INTO tmp_bucket_choice (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CHOSEN_CLUSTER_ID)
SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK,
                     
                     CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE,'|',s.CLUSTER_ID))
        ) AS rn
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
) z
WHERE rn = 1;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_bucket_choice bc
    LEFT JOIN tmp_cluster_snap_map sm
      ON sm.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID
    SET bc.CHOSEN_CLUSTER_ID = COALESCE(sm.SNAPPED_CLUSTER_ID, bc.CHOSEN_CLUSTER_ID);
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
CREATE TEMPORARY TABLE tmp_final_first_cluster (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_final_first_cluster (CLUSTER_ID)
    SELECT fc.CLUSTER_ID
      FROM tmp_final_clusters fc
     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
     LIMIT 1;
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
CREATE TEMPORARY TABLE tmp_bucket_top_final (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_bucket_top_final (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
    FROM (
        SELECT
            s.PARENT_ORDER_ID,
            s.CLIENT_ORDER_TYPE,
            s.CLUSTER_ID,
            ROW_NUMBER() OVER (
                PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
                ORDER BY s.SCORE_RANK,
                         
                         CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE,'|',s.CLUSTER_ID))
            ) AS rn
        FROM tmp_bucket_cluster_score s
        JOIN tmp_final_clusters fcx
          ON fcx.CLUSTER_ID = s.CLUSTER_ID
    ) q
    WHERE rn = 1;
END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
CREATE TEMPORARY TABLE tmp_bucket_fallback (
    PARENT_ORDER_ID       VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE     VARCHAR(100) NOT NULL,
    FALLBACK_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (FALLBACK_CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    INSERT INTO tmp_bucket_fallback (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, FALLBACK_CLUSTER_ID)
    SELECT
        k.PARENT_ORDER_ID,
        k.CLIENT_ORDER_TYPE,
        COALESCE(bc.CHOSEN_CLUSTER_ID, topf.CLUSTER_ID, firstf.CLUSTER_ID) AS FALLBACK_CLUSTER_ID
    FROM tmp_bucket_k k
    LEFT JOIN tmp_bucket_choice bc
      ON bc.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND bc.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    LEFT JOIN tmp_bucket_top_final topf
      ON topf.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND topf.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    CROSS JOIN tmp_final_first_cluster firstf;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
CREATE TEMPORARY TABLE tmp_parent_cluster_load (
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    CLUSTER_ID        VARCHAR(50)  NOT NULL,
    LINE_CNT          BIGINT NOT NULL DEFAULT 0,
    QTY_CNT           BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
) ENGINE=INNODB;



DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
CREATE TEMPORARY TABLE tmp_cluster_supply_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    REM_QTY    BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply_rem
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY, SUPPLY_QTY
  FROM tmp_cluster_supply;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
CREATE TEMPORARY TABLE tmp_sku_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_REM  BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_rem (ARTICLE_ID, BATCH_ID, TOTAL_REM)
SELECT ARTICLE_ID, BATCH_ID, SUM(REM_QTY) AS TOTAL_REM
  FROM tmp_cluster_supply_rem
 GROUP BY ARTICLE_ID, BATCH_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
CREATE TEMPORARY TABLE tmp_line_alloc (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NOT NULL,
    BATCH_ID            VARCHAR(200) NOT NULL,
    SRC_CLUSTER_ID      VARCHAR(50)  NOT NULL,
    ALLOC_QTY           BIGINT       NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, SRC_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (SRC_CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
CREATE TEMPORARY TABLE tmp_sku_queue (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_sku_queue
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_line_assign
 WHERE SHORT_FLAG_SCHEMA = 0
   AND ARTICLE_ID IS NOT NULL
   AND BATCH_ID IS NOT NULL;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
CREATE TEMPORARY TABLE tmp_sku_line_queue (
    RN INT NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    ORDER_LINE_ID VARCHAR(36) NOT NULL,
    QUANTITY INT NOT NULL,
    PRIMARY KEY (RN),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (ORDER_LINE_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
CREATE TEMPORARY TABLE tmp_line_cluster_seq (
    RN INT NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    REM_QTY BIGINT NOT NULL,
    PRIMARY KEY (RN),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

sku_loop: WHILE EXISTS (SELECT 1 FROM tmp_sku_queue LIMIT 1) DO

    SELECT ARTICLE_ID, BATCH_ID
      INTO v_sku, v_batch
      FROM tmp_sku_queue
      LIMIT 1;

    DELETE FROM tmp_sku_queue
     WHERE ARTICLE_ID = v_sku
       AND BATCH_ID   = v_batch;

    TRUNCATE TABLE tmp_sku_line_queue;

    
    INSERT INTO tmp_sku_line_queue (RN, PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY)
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE, la.QUANTITY DESC, la.ORDER_LINE_ID
        ) AS RN,
        la.PARENT_ORDER_ID,
        la.CLIENT_ORDER_TYPE,
        la.ORDER_LINE_ID,
        la.QUANTITY
    FROM tmp_line_assign la
    WHERE la.SHORT_FLAG_SCHEMA = 0
      AND la.ARTICLE_ID = v_sku
      AND la.BATCH_ID   = v_batch;

    SELECT COALESCE(MAX(RN),0) INTO v_maxrn FROM tmp_sku_line_queue;
    SET v_rn = 1;

    line_loop: WHILE v_rn <= v_maxrn DO

        SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY
          INTO v_line_parent, v_line_cat, v_line_id, v_line_qty
          FROM tmp_sku_line_queue
         WHERE RN = v_rn;

        
        IF v_last_bucket_parent IS NULL
           OR v_last_bucket_cat IS NULL
           OR v_last_bucket_parent <> v_line_parent
           OR v_last_bucket_cat <> v_line_cat
        THEN
            SET v_last_bucket_parent = v_line_parent;
            SET v_last_bucket_cat    = v_line_cat;

            
            SET v_bucketK = 1;
            SELECT COALESCE(K, 1)
              INTO v_bucketK
              FROM tmp_bucket_k
             WHERE PARENT_ORDER_ID = v_line_parent
               AND CLIENT_ORDER_TYPE = v_line_cat
             LIMIT 1;

            
            SET v_bucket_primary_cluster = NULL;

            SELECT bc.CHOSEN_CLUSTER_ID
              INTO v_bucket_primary_cluster
              FROM tmp_bucket_choice bc
             WHERE bc.PARENT_ORDER_ID = v_line_parent
               AND bc.CLIENT_ORDER_TYPE = v_line_cat
             LIMIT 1;

            IF v_bucket_primary_cluster IS NULL THEN
                SELECT bcs.CLUSTER_ID
                  INTO v_bucket_primary_cluster
                  FROM tmp_bucket_cluster_score bcs
                 WHERE bcs.PARENT_ORDER_ID = v_line_parent
                   AND bcs.CLIENT_ORDER_TYPE = v_line_cat
                 ORDER BY
                    bcs.SCORE_RANK,
                    
                    CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',bcs.CLUSTER_ID))
                 LIMIT 1;
            END IF;

            IF v_bucket_primary_cluster IS NULL THEN
                SELECT ac.CLUSTER_ID
                  INTO v_bucket_primary_cluster
                  FROM tmp_allowed_clusters ac
                 WHERE ac.PARENT_ORDER_ID = v_line_parent
                   AND ac.CLIENT_ORDER_TYPE = v_line_cat
                 ORDER BY
                    
                    CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',ac.CLUSTER_ID))
                 LIMIT 1;
            END IF;

            
            IF v_use_station_bias = 1 AND v_bucket_primary_cluster IS NOT NULL THEN
                SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_bucket_primary_cluster)
                  INTO v_bucket_primary_cluster
                  FROM tmp_cluster_snap_map sm
                 WHERE sm.SRC_CLUSTER_ID = v_bucket_primary_cluster
                 LIMIT 1;

                
                IF v_bucket_primary_cluster IS NULL THEN
                    SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                      INTO v_bucket_primary_cluster
                      FROM tmp_bucket_fallback
                     WHERE PARENT_ORDER_ID = v_line_parent
                       AND CLIENT_ORDER_TYPE = v_line_cat
                     LIMIT 1;
                END IF;

                IF v_bucket_primary_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_bucket_primary_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;
            END IF;
        END IF;

        
        DELETE FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        SELECT COALESCE(TOTAL_REM,0)
          INTO v_total_rem
          FROM tmp_sku_rem
         WHERE ARTICLE_ID = v_sku
           AND BATCH_ID   = v_batch;

        
        IF v_total_rem <= 0 THEN

            IF v_use_station_bias = 1 THEN
                
                SET v_pick_cluster = v_bucket_primary_cluster;

                
                IF v_pick_cluster IS NULL THEN
                    SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                      INTO v_pick_cluster
                      FROM tmp_bucket_fallback
                     WHERE PARENT_ORDER_ID = v_line_parent
                       AND CLIENT_ORDER_TYPE = v_line_cat
                     LIMIT 1;
                END IF;

                
                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        TRUNCATE TABLE tmp_line_cluster_seq;

        
        INSERT INTO tmp_line_cluster_seq (RN, CLUSTER_ID, REM_QTY)
        SELECT
            ROW_NUMBER() OVER (
                ORDER BY
                    
                    CASE
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND csr.CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                        ELSE 2
                    END,
                    
                    CASE
                        WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                        WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                        WHEN v_use_station_bias = 1 THEN 2
                        ELSE 3
                    END,
                    
                    CASE WHEN ac.CLUSTER_ID IS NOT NULL THEN 0 ELSE 1 END,
                    
                    COALESCE(bcs.SCORE_RANK, 999999),
                    
                    COALESCE(pcl.LINE_CNT,0) DESC,
                    COALESCE(pcl.QTY_CNT,0)  DESC,
                    
                    csr.REM_QTY DESC,
                    
                    CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',v_line_id,'|',csr.CLUSTER_ID))
            ) AS RN,
            csr.CLUSTER_ID,
            csr.REM_QTY
        FROM tmp_cluster_supply_rem csr
        LEFT JOIN tmp_allowed_clusters ac
          ON ac.PARENT_ORDER_ID   = v_line_parent
         AND ac.CLIENT_ORDER_TYPE = v_line_cat
         AND ac.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = v_line_parent
         AND bcs.CLIENT_ORDER_TYPE = v_line_cat
         AND bcs.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_choice bc
          ON bc.PARENT_ORDER_ID   = v_line_parent
         AND bc.CLIENT_ORDER_TYPE = v_line_cat
        LEFT JOIN tmp_parent_cluster_load pcl
          ON pcl.PARENT_ORDER_ID   = v_line_parent
         AND pcl.CLIENT_ORDER_TYPE = v_line_cat
         AND pcl.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_pref_clusters pfc
          ON pfc.CLUSTER_ID = csr.CLUSTER_ID
        LEFT JOIN tmp_near_clusters nfc
          ON nfc.CLUSTER_ID = csr.CLUSTER_ID
        WHERE csr.ARTICLE_ID = v_sku
          AND csr.BATCH_ID   = v_batch
          AND csr.REM_QTY   > 0;

        SELECT COALESCE(MAX(RN),0) INTO v_cmax FROM tmp_line_cluster_seq;

        
        SET v_need = v_line_qty;
        SET v_crn  = 1;

        cluster_loop: WHILE v_need > 0 AND v_crn <= v_cmax DO

            SELECT CLUSTER_ID, REM_QTY
              INTO v_cur_cluster, v_cur_rem
              FROM tmp_line_cluster_seq
             WHERE RN = v_crn;

            SET v_alloc = LEAST(v_cur_rem, v_need);

            IF v_alloc > 0 THEN

                INSERT INTO tmp_line_alloc (
                    PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID,
                    ARTICLE_ID, BATCH_ID, SRC_CLUSTER_ID, ALLOC_QTY
                )
                VALUES (
                    v_line_parent, v_line_cat, v_line_id,
                    v_sku, v_batch, v_cur_cluster, v_alloc
                )
                ON DUPLICATE KEY UPDATE
                    ALLOC_QTY = ALLOC_QTY + VALUES(ALLOC_QTY);

                UPDATE tmp_cluster_supply_rem
                   SET REM_QTY = REM_QTY - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch
                   AND CLUSTER_ID = v_cur_cluster;

                
                UPDATE tmp_sku_rem
                   SET TOTAL_REM = TOTAL_REM - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch;

                SET v_need = v_need - v_alloc;

            END IF;

            SET v_crn = v_crn + 1;
        END WHILE;

        
        SELECT COALESCE(SUM(ALLOC_QTY),0)
          INTO v_alloc
          FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        IF v_alloc <= 0 THEN

            IF v_use_station_bias = 1 THEN
                
                SET v_pick_cluster = v_bucket_primary_cluster;

                IF v_pick_cluster IS NULL THEN
                    SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                      INTO v_pick_cluster
                      FROM tmp_bucket_fallback
                     WHERE PARENT_ORDER_ID = v_line_parent
                       AND CLIENT_ORDER_TYPE = v_line_cat
                     LIMIT 1;
                END IF;

                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        
        SET v_pick_cluster = NULL;

        
        SELECT la.SRC_CLUSTER_ID
          INTO v_pick_cluster
          FROM tmp_line_alloc la
          JOIN tmp_allowed_clusters ac
            ON ac.PARENT_ORDER_ID   = v_line_parent
           AND ac.CLIENT_ORDER_TYPE = v_line_cat
           AND ac.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_cluster_score bcs
            ON bcs.PARENT_ORDER_ID   = v_line_parent
           AND bcs.CLIENT_ORDER_TYPE = v_line_cat
           AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_choice bc
            ON bc.PARENT_ORDER_ID   = v_line_parent
           AND bc.CLIENT_ORDER_TYPE = v_line_cat
          LEFT JOIN tmp_pref_clusters pfc
            ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_near_clusters nfc
            ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
         WHERE la.PARENT_ORDER_ID   = v_line_parent
           AND la.CLIENT_ORDER_TYPE = v_line_cat
           AND la.ORDER_LINE_ID     = v_line_id
         ORDER BY
            la.ALLOC_QTY DESC,
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                ELSE 2
            END,
            CASE
                WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                WHEN v_use_station_bias = 1 THEN 2
                ELSE 3
            END,
            COALESCE(bcs.SCORE_RANK, 999999),
            
            CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',v_line_id,'|',la.SRC_CLUSTER_ID))
         LIMIT 1;

        
        IF v_pick_cluster IS NULL THEN
            SELECT la.SRC_CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_line_alloc la
              LEFT JOIN tmp_bucket_cluster_score bcs
                ON bcs.PARENT_ORDER_ID   = v_line_parent
               AND bcs.CLIENT_ORDER_TYPE = v_line_cat
               AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_bucket_choice bc
                ON bc.PARENT_ORDER_ID   = v_line_parent
               AND bc.CLIENT_ORDER_TYPE = v_line_cat
              LEFT JOIN tmp_pref_clusters pfc
                ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_near_clusters nfc
                ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
             WHERE la.PARENT_ORDER_ID   = v_line_parent
               AND la.CLIENT_ORDER_TYPE = v_line_cat
               AND la.ORDER_LINE_ID     = v_line_id
             ORDER BY
                la.ALLOC_QTY DESC,
                CASE
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                    ELSE 2
                END,
                CASE
                    WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                    WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                    WHEN v_use_station_bias = 1 THEN 2
                    ELSE 3
                END,
                COALESCE(bcs.SCORE_RANK, 999999),
                
                CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',v_line_id,'|',la.SRC_CLUSTER_ID))
             LIMIT 1;
        END IF;

        
        IF v_pick_cluster IS NULL THEN
            SELECT csr.CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_cluster_supply_rem csr
             WHERE csr.ARTICLE_ID = v_sku
               AND csr.BATCH_ID = v_batch
             ORDER BY
                csr.REM_QTY DESC,
                
                CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',v_line_id,'|',csr.CLUSTER_ID))
             LIMIT 1;
        END IF;

        
        IF v_use_station_bias = 1
           AND v_pick_cluster IS NOT NULL
        THEN
            SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_pick_cluster)
              INTO v_pick_cluster
              FROM tmp_cluster_snap_map sm
             WHERE sm.SRC_CLUSTER_ID = v_pick_cluster
             LIMIT 1;

            
            IF v_pick_cluster IS NULL THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT fc.CLUSTER_ID
                  INTO v_pick_cluster
                  FROM tmp_final_clusters fc
                 ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                 LIMIT 1;
            END IF;
        END IF;

        
        IF v_pick_cluster IS NOT NULL
           AND v_pick_cluster <> 'NO_INVENTORY'
        THEN
            
            IF v_bucketK = 1 AND v_bucket_primary_cluster IS NOT NULL THEN
                SET v_pick_cluster = v_bucket_primary_cluster;

            ELSE
                
                IF NOT EXISTS (
                    SELECT 1
                      FROM tmp_allowed_clusters acx
                     WHERE acx.PARENT_ORDER_ID = v_line_parent
                       AND acx.CLIENT_ORDER_TYPE = v_line_cat
                       AND acx.CLUSTER_ID = v_pick_cluster
                     LIMIT 1
                )
                THEN
                    
                    SELECT ac.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_allowed_clusters ac
                      LEFT JOIN tmp_bucket_choice bc
                        ON bc.PARENT_ORDER_ID = ac.PARENT_ORDER_ID
                       AND bc.CLIENT_ORDER_TYPE = ac.CLIENT_ORDER_TYPE
                      LEFT JOIN tmp_bucket_cluster_score bcs
                        ON bcs.PARENT_ORDER_ID = ac.PARENT_ORDER_ID
                       AND bcs.CLIENT_ORDER_TYPE = ac.CLIENT_ORDER_TYPE
                       AND bcs.CLUSTER_ID = ac.CLUSTER_ID
                      LEFT JOIN tmp_parent_cluster_load pcl
                        ON pcl.PARENT_ORDER_ID = ac.PARENT_ORDER_ID
                       AND pcl.CLIENT_ORDER_TYPE = ac.CLIENT_ORDER_TYPE
                       AND pcl.CLUSTER_ID = ac.CLUSTER_ID
                      LEFT JOIN tmp_pref_clusters pfc
                        ON pfc.CLUSTER_ID = ac.CLUSTER_ID
                      LEFT JOIN tmp_near_clusters nfc
                        ON nfc.CLUSTER_ID = ac.CLUSTER_ID
                     WHERE ac.PARENT_ORDER_ID = v_line_parent
                       AND ac.CLIENT_ORDER_TYPE = v_line_cat
                     ORDER BY
                        CASE
                            WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND ac.CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                            WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                            ELSE 2
                        END,
                        CASE
                            WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                            WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                            WHEN v_use_station_bias = 1 THEN 2
                            ELSE 3
                        END,
                        COALESCE(bcs.SCORE_RANK, 999999),
                        COALESCE(pcl.LINE_CNT,0) DESC,
                        COALESCE(pcl.QTY_CNT,0)  DESC,
                        
                        CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',ac.CLUSTER_ID))
                     LIMIT 1;

                    
                    IF v_pick_cluster IS NULL THEN
                        SET v_pick_cluster = v_bucket_primary_cluster;
                    END IF;
                END IF;
            END IF;
        END IF;

        
        IF v_use_station_bias = 1
           AND v_pick_cluster IS NOT NULL
           AND v_pick_cluster <> 'NO_INVENTORY'
        THEN
            SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_pick_cluster)
              INTO v_pick_cluster
              FROM tmp_cluster_snap_map sm
             WHERE sm.SRC_CLUSTER_ID = v_pick_cluster
             LIMIT 1;

            IF v_pick_cluster IS NULL THEN
                SET v_pick_cluster = v_bucket_primary_cluster;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT fc.CLUSTER_ID
                  INTO v_pick_cluster
                  FROM tmp_final_clusters fc
                 ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                 LIMIT 1;
            END IF;
        END IF;

        
        UPDATE tmp_line_assign
           SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
               ASSIGNED_RANK = 1,
               SHORT_FLAG_SUPPLY = CASE WHEN v_alloc < v_line_qty THEN 1 ELSE 0 END
         WHERE PARENT_ORDER_ID = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID = v_line_id;

        
        INSERT INTO tmp_parent_cluster_load (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, LINE_CNT, QTY_CNT)
        VALUES (v_line_parent, v_line_cat, v_pick_cluster, 1, v_line_qty)
        ON DUPLICATE KEY UPDATE
            LINE_CNT = LINE_CNT + 1,
            QTY_CNT  = QTY_CNT  + VALUES(QTY_CNT);

        SET v_rn = v_rn + 1;
    END WHILE;

END WHILE;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_line_assign la
    LEFT JOIN tmp_bucket_fallback bf
      ON bf.PARENT_ORDER_ID = la.PARENT_ORDER_ID
     AND bf.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
    SET la.ASSIGNED_CLUSTER_ID = COALESCE(
            bf.FALLBACK_CLUSTER_ID,
            (SELECT fc.CLUSTER_ID
               FROM tmp_final_clusters fc
              ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
              LIMIT 1)
        ),
        la.ASSIGNED_RANK = 0
    WHERE la.SHORT_FLAG_SCHEMA = 1
      AND la.ASSIGNED_CLUSTER_ID IS NULL;
END IF;

UPDATE tmp_line_assign
   SET SHORT_FLAG = GREATEST(SHORT_FLAG_SCHEMA, SHORT_FLAG_SUPPLY);


        

DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc_sum;
CREATE TEMPORARY TABLE tmp_line_alloc_sum (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ALLOC_SUM           BIGINT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID)
) ENGINE=INNODB;

INSERT INTO tmp_line_alloc_sum
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    ORDER_LINE_ID,
    SUM(ALLOC_QTY) AS ALLOC_SUM
FROM tmp_line_alloc
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID;


DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
CREATE TEMPORARY TABLE tmp_ranked_lines (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NULL,
    BATCH_ID            VARCHAR(200) NULL,
    QUANTITY            INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

    LINE_CLUSTER_ID     VARCHAR(50)  NOT NULL, 
    SHORT_FLAG          INT NOT NULL,          
    NO_INV_FLAG         INT NOT NULL,          

    RN                  BIGINT NOT NULL,
    SPLIT_GROUP         INT NOT NULL,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
    UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP, RN)
) ENGINE=INNODB;

INSERT INTO tmp_ranked_lines
SELECT
    la.PARENT_ORDER_ID,
    la.CLIENT_ORDER_TYPE,
    la.ORDER_LINE_ID,
    la.ARTICLE_ID,
    la.BATCH_ID,
    la.QUANTITY,
    la.DISPLAY_OPERATOR_INSTRUCTION,

    COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY') AS LINE_CLUSTER_ID,

    
    CASE
        WHEN la.SHORT_FLAG_SCHEMA = 1 THEN 0
        WHEN COALESCE(s.ALLOC_SUM,0) = 0 THEN 0
        WHEN COALESCE(s.ALLOC_SUM,0) < la.QUANTITY THEN 1
        ELSE 0
    END AS SHORT_FLAG,

    
    CASE
        WHEN la.SHORT_FLAG_SCHEMA = 1 THEN 1
        WHEN COALESCE(s.ALLOC_SUM,0) = 0 THEN 1
        ELSE 0
    END AS NO_INV_FLAG,

    ROW_NUMBER() OVER (
        PARTITION BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE
        ORDER BY
            
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL
                 AND COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = bc.CHOSEN_CLUSTER_ID
                THEN 0 ELSE 1
            END,
            la.QUANTITY DESC,
            COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY'),
            la.ORDER_LINE_ID
    ) AS RN,

    
    1 + ((ROW_NUMBER() OVER (
            PARTITION BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE
            ORDER BY
                CASE
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL
                     AND COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = bc.CHOSEN_CLUSTER_ID
                    THEN 0 ELSE 1
                END,
                la.QUANTITY DESC,
                COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY'),
                la.ORDER_LINE_ID
        ) - 1) * k.K) DIV k.TOTAL_LINES AS SPLIT_GROUP

FROM tmp_line_assign la
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = la.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
LEFT JOIN tmp_bucket_choice bc
  ON bc.PARENT_ORDER_ID   = la.PARENT_ORDER_ID
 AND bc.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
LEFT JOIN tmp_line_alloc_sum s
  ON s.PARENT_ORDER_ID     = la.PARENT_ORDER_ID
 AND s.CLIENT_ORDER_TYPE   = la.CLIENT_ORDER_TYPE
 AND s.ORDER_LINE_ID       = la.ORDER_LINE_ID;

SELECT COUNT(*) INTO v_cnt_ranked FROM tmp_ranked_lines;
IF v_cnt_ranked <> v_cnt_line_assign THEN
    SET v_errmsg = CONCAT('LINE_LOSS_AFTER_RANKING: tmp_line_assign=', v_cnt_line_assign,
                          ', tmp_ranked_lines=', v_cnt_ranked);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster_weight;
CREATE TEMPORARY TABLE tmp_group_cluster_weight (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    CLUSTER_ID          VARCHAR(50) NOT NULL,
    WQTY                BIGINT NOT NULL,
    RN                  INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP, RN),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_group_cluster_weight
SELECT
    rl.PARENT_ORDER_ID,
    rl.CLIENT_ORDER_TYPE,
    rl.SPLIT_GROUP,
    rl.LINE_CLUSTER_ID AS CLUSTER_ID,
    SUM(rl.QUANTITY) AS WQTY,
    ROW_NUMBER() OVER (
        PARTITION BY rl.PARENT_ORDER_ID, rl.CLIENT_ORDER_TYPE, rl.SPLIT_GROUP
        ORDER BY
            SUM(rl.QUANTITY) DESC,
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND rl.LINE_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID
                THEN 0 ELSE 1
            END,
            rl.LINE_CLUSTER_ID
    ) AS RN
FROM tmp_ranked_lines rl
LEFT JOIN tmp_bucket_choice bc
  ON bc.PARENT_ORDER_ID   = rl.PARENT_ORDER_ID
 AND bc.CLIENT_ORDER_TYPE = rl.CLIENT_ORDER_TYPE
WHERE rl.LINE_CLUSTER_ID IS NOT NULL
  AND rl.LINE_CLUSTER_ID <> 'NO_INVENTORY'
GROUP BY rl.PARENT_ORDER_ID, rl.CLIENT_ORDER_TYPE, rl.SPLIT_GROUP, rl.LINE_CLUSTER_ID, bc.CHOSEN_CLUSTER_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster;
CREATE TEMPORARY TABLE tmp_group_cluster (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    GROUP_CLUSTER_ID    VARCHAR(50) NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP),
    KEY (GROUP_CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_group_cluster
SELECT
    g.PARENT_ORDER_ID,
    g.CLIENT_ORDER_TYPE,
    g.SPLIT_GROUP,
    COALESCE(
        w.CLUSTER_ID,
        bc.CHOSEN_CLUSTER_ID,
        bf.FALLBACK_CLUSTER_ID,
        'NO_INVENTORY'
    ) AS GROUP_CLUSTER_ID
FROM (
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP
      FROM tmp_ranked_lines
     GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP
) g
LEFT JOIN tmp_group_cluster_weight w
  ON w.PARENT_ORDER_ID   = g.PARENT_ORDER_ID
 AND w.CLIENT_ORDER_TYPE = g.CLIENT_ORDER_TYPE
 AND w.SPLIT_GROUP       = g.SPLIT_GROUP
 AND w.RN = 1
LEFT JOIN tmp_bucket_choice bc
  ON bc.PARENT_ORDER_ID   = g.PARENT_ORDER_ID
 AND bc.CLIENT_ORDER_TYPE = g.CLIENT_ORDER_TYPE
LEFT JOIN tmp_bucket_fallback bf
  ON bf.PARENT_ORDER_ID   = g.PARENT_ORDER_ID
 AND bf.CLIENT_ORDER_TYPE = g.CLIENT_ORDER_TYPE;


DROP TEMPORARY TABLE IF EXISTS tmp_group_flags;
CREATE TEMPORARY TABLE tmp_group_flags (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    HAS_NO_INV          INT NOT NULL,
    HAS_SHORT           INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP)
) ENGINE=INNODB;

INSERT INTO tmp_group_flags
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    SPLIT_GROUP,
    MAX(NO_INV_FLAG) AS HAS_NO_INV,
    MAX(SHORT_FLAG)  AS HAS_SHORT
FROM tmp_ranked_lines
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP;


DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
CREATE TEMPORARY TABLE tmp_final_map (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NULL,
    BATCH_ID            VARCHAR(200) NULL,
    QUANTITY            INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

    SPLIT_GROUP         INT NOT NULL,

    IS_SUSPENDED_GROUP  INT NOT NULL,
    IS_SHORT_LINE       INT NOT NULL,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, ORDER_LINE_ID),
    UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP)
) ENGINE=INNODB;

INSERT INTO tmp_final_map
SELECT
    rl.PARENT_ORDER_ID,
    rl.CLIENT_ORDER_TYPE,
    gc.GROUP_CLUSTER_ID AS CLUSTER_ID,
    rl.ORDER_LINE_ID,
    rl.ARTICLE_ID,
    rl.BATCH_ID,
    rl.QUANTITY,
    rl.DISPLAY_OPERATOR_INSTRUCTION,
    rl.SPLIT_GROUP,
    gf.HAS_NO_INV AS IS_SUSPENDED_GROUP,
    rl.SHORT_FLAG AS IS_SHORT_LINE
FROM tmp_ranked_lines rl
JOIN tmp_group_cluster gc
  ON gc.PARENT_ORDER_ID   = rl.PARENT_ORDER_ID
 AND gc.CLIENT_ORDER_TYPE = rl.CLIENT_ORDER_TYPE
 AND gc.SPLIT_GROUP       = rl.SPLIT_GROUP
JOIN tmp_group_flags gf
  ON gf.PARENT_ORDER_ID   = rl.PARENT_ORDER_ID
 AND gf.CLIENT_ORDER_TYPE = rl.CLIENT_ORDER_TYPE
 AND gf.SPLIT_GROUP       = rl.SPLIT_GROUP;

SELECT COUNT(*) INTO v_cnt_final FROM tmp_final_map;
IF v_cnt_final <> v_cnt_ranked THEN
    SET v_errmsg = CONCAT('LINE_LOSS_AFTER_FINAL_MAP: tmp_ranked_lines=', v_cnt_ranked,
                          ', tmp_final_map=', v_cnt_final);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
END IF;



    

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_pre_lines, v_pre_qty
    FROM tmp_lines;

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_post_lines, v_post_qty
    FROM tmp_final_map;

    IF v_pre_lines <> v_post_lines OR v_pre_qty <> v_post_qty THEN
        SET v_errmsg = CONCAT(
            'CONSERVATION_FAILED: PRE_LINES=', v_pre_lines,
            ', POST_LINES=', v_post_lines,
            ', PRE_QTY=', v_pre_qty,
            ', POST_QTY=', v_post_qty
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_lines tl
    LEFT JOIN tmp_final_map fm
      ON fm.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND fm.ORDER_LINE_ID   = tl.ORDER_LINE_ID
    WHERE fm.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('MISSING_LINES_IN_OUTPUT=', v_missing_lines);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

       

DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
CREATE TEMPORARY TABLE tmp_cat_seq (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CAT_SEQ             INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT INTO tmp_cat_seq
SELECT
    x.PARENT_ORDER_ID,
    x.CLIENT_ORDER_TYPE,
    ROW_NUMBER() OVER (PARTITION BY x.PARENT_ORDER_ID ORDER BY x.CLIENT_ORDER_TYPE) AS CAT_SEQ
FROM (SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE FROM tmp_lines_cat) X;

DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
CREATE TEMPORARY TABLE tmp_child_orders (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    CHILD_ORDER_ID      VARCHAR(180) NOT NULL,
    CHILD_STATUS        ENUM('PENDING') NOT NULL,

    HAS_SHORT_LINES     INT NOT NULL DEFAULT 0,
    HAS_NO_INV_LINES    INT NOT NULL DEFAULT 0,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP),
    KEY (CHILD_ORDER_ID),
    KEY (CHILD_STATUS)
) ENGINE=INNODB;

INSERT INTO tmp_child_orders
SELECT
    fm.PARENT_ORDER_ID,
    fm.CLIENT_ORDER_TYPE,
    fm.CLUSTER_ID,
    fm.SPLIT_GROUP,

    CASE
        WHEN k.K = 1 THEN
            CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID)
        ELSE
            CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID, '-', LPAD(fm.SPLIT_GROUP, 3, '0'))
    END AS CHILD_ORDER_ID,

    'PENDING' AS CHILD_STATUS,

    CASE WHEN MAX(fm.IS_SHORT_LINE) = 1 THEN 1 ELSE 0 END AS HAS_SHORT_LINES,
    CASE WHEN MAX(fm.IS_SUSPENDED_GROUP) = 1 THEN 1 ELSE 0 END AS HAS_NO_INV_LINES

FROM tmp_final_map fm
JOIN tmp_cat_seq cs
  ON cs.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND cs.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
GROUP BY
    fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.SPLIT_GROUP, k.K, cs.CAT_SEQ;

SELECT COUNT(*) INTO v_child_cnt FROM tmp_child_orders;



	

SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_all,
        v_total_qty_all
    FROM tmp_line_assign;
    
    SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_pickable,
        v_total_qty_pickable
    FROM tmp_line_assign
    WHERE SHORT_FLAG_SCHEMA = 0
      AND COALESCE(ASSIGNED_CLUSTER_ID,'NO_INVENTORY') <> 'NO_INVENTORY';

    SELECT
        COALESCE(SUM(a.ALLOC_QTY),0),
        COALESCE(COUNT(DISTINCT CONCAT(a.PARENT_ORDER_ID,'|',a.CLIENT_ORDER_TYPE,'|',a.ORDER_LINE_ID)),0)
    INTO
        v_alloc_qty_total,
        v_alloc_lines_total
    FROM tmp_line_alloc a;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
CREATE TEMPORARY TABLE tmp_reco1 (
    STATION_ID VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NULL,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
CREATE TEMPORARY TABLE tmp_reco2 (
    STATION_ID   VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NULL,
    IS_SELECTED  INT NOT NULL DEFAULT 0,
    IS_NO_WAVE   INT NOT NULL DEFAULT 0,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID),
    KEY (IS_NO_WAVE, IS_SELECTED)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2_avail_clusters;
CREATE TEMPORARY TABLE tmp_reco2_avail_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_has_hw_station = 0 THEN

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT STATION_ID, NULL
      FROM tmp_user_stations;

    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT STATION_ID, NULL, 1, 0
      FROM tmp_user_stations;

ELSE

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM hw_station_master hs
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50)),
           1 AS IS_SELECTED,
           0 AS IS_NO_WAVE
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    IF v_has_hw_wave_status = 1 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
               CAST(hs.CLUSTER_ID AS CHAR(50)),
               0 AS IS_SELECTED,
               1 AS IS_NO_WAVE
          FROM hw_station_master hs
         WHERE hs.STATION_ID IS NOT NULL
           AND hs.CLUSTER_ID IS NOT NULL
           AND LOWER(REPLACE(COALESCE(hs.wave_status,''),' ','_')) IN ('no_wave','nowave','no-wave');
    END IF;

    
    IF v_user_station_cnt = 0 AND v_has_hw_wave_status = 0 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT STATION_ID, CLUSTER_ID, 0, 0 FROM tmp_reco1;
    END IF;

END IF;


INSERT IGNORE INTO tmp_reco2_avail_clusters (CLUSTER_ID)
SELECT DISTINCT COALESCE(CLUSTER_ID,'?')
  FROM tmp_reco2
 WHERE CLUSTER_ID IS NOT NULL;



DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
CREATE TEMPORARY TABLE tmp_job_cluster_stats (
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    ORDER_LINES  BIGINT NOT NULL,
    ORDER_QTY    BIGINT NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_job_cluster_stats (CLUSTER_ID, ORDER_LINES, ORDER_QTY)
SELECT
    co.CLUSTER_ID,
    COUNT(DISTINCT co.CHILD_ORDER_ID) AS ORDER_LINES,
    COALESCE(SUM(fm.QUANTITY),0)      AS ORDER_QTY
FROM tmp_child_orders co
LEFT JOIN tmp_final_map fm
  ON fm.PARENT_ORDER_ID   = co.PARENT_ORDER_ID
 AND fm.CLIENT_ORDER_TYPE = co.CLIENT_ORDER_TYPE
 AND fm.CLUSTER_ID        = co.CLUSTER_ID
 AND fm.SPLIT_GROUP       = co.SPLIT_GROUP

WHERE co.CLUSTER_ID <> 'NO_INVENTORY'
GROUP BY co.CLUSTER_ID;



DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco1_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco1_total_lines,
    @reco1_total_qty
FROM tmp_job_cluster_stats js;


INSERT INTO tmp_reco1_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID ORDER BY r.STATION_ID SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco1_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco1_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco1_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco1_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco1 r
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco2_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco2_total_lines,
    @reco2_total_qty
FROM tmp_job_cluster_stats js
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = js.CLUSTER_ID;


INSERT INTO tmp_reco2_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID
                          ORDER BY r.IS_NO_WAVE DESC, r.IS_SELECTED DESC, r.STATION_ID
                          SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco2_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco2_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco2_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco2_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco2 r
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = r.CLUSTER_ID
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



SET @reco1_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco1_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);

SET @reco2_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco2_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);



IF v_has_reco1 = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2 = 1 THEN
    UPDATE picklist_split_order_master
      SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco1_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco_col = 1 THEN
   UPDATE picklist_split_order_master
SET RECOMMENDATION = JSON_OBJECT(
    'RECOMMENDATION_1_ALL_STATIONS', CAST(@reco1_cluster_json AS JSON),
    'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

    'STATION_PREF_MODE', v_station_mode,
    'USER_SELECTED_STATIONS', (
        SELECT COALESCE(GROUP_CONCAT(STATION_ID ORDER BY STATION_ID SEPARATOR ','), '')
        FROM tmp_user_stations
    ),
    'RULE_ID', v_rule_id,
    'RULE_LOG_ID', v_ruleLog_id,
    'TOTAL_INITIAL_ORDERS', v_parent_cnt,
    'TOTAL_SPLIT_ORDERS', v_child_cnt,

    'INITIAL_ORDER_LINES', v_line_cnt,
    'AFTER_ALLOCATION_ORDER_LINES', v_cnt_final,

    'TOTAL_LINES_PICKABLE', v_total_lines_pickable,

    
    'TOTAL_QTY_ALL', v_pre_qty,
    'TOTAL_QTY_PICKABLE', v_total_qty_pickable,

    
    'ALLOC_QTY_TOTAL', v_post_qty,
    'ALLOC_LINES_TOTAL', v_alloc_lines_total,

    'NOTES', JSON_OBJECT(
        'PARENT_FIELD', 'PARENT_ORDER_ID',
        'CHILD_FIELD', 'ORDER_ID',
        'SUB_ORDER_ID', 'NOT_USED',
        'RESERVATION_KEY', v_reservation_key,
        'RESERVATION_TTL_MINUTES', v_res_ttl_minutes
    )
)
WHERE ID = v_ruleLog_id;

END IF;

    

IF v_is_dry_run = 0 THEN

    
    SET @or_cols = 'PARENT_ORDER_ID, ORDER_TYPE, ORDER_ID, ORDER_REQUEST_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @or_sel  = 'co.PARENT_ORDER_ID, co.CLIENT_ORDER_TYPE, co.CHILD_ORDER_ID, co.CHILD_STATUS, CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_or_cluster = 1 THEN
        SET @or_cols = CONCAT(@or_cols, ', CLUSTER_ID');
        SET @or_sel  = CONCAT(@or_sel,  ', co.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_request_data (', @or_cols, ') ',
        'SELECT ', @or_sel, ' ',
        '  FROM tmp_child_orders co ',
        '  LEFT JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        ' WHERE r.ORDER_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SET @line_cols = 'WMS_ORDER_REQUEST_DATA_ID, ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, BATCH_ID, DISPLAY_OPERATOR_INSTRUCTION, ORDER_LINE_PROCESS_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @line_sel  = 'r.WMS_ORDER_REQUEST_DATA_ID, r.ORDER_ID, fm.ORDER_LINE_ID, fm.ARTICLE_ID, fm.QUANTITY, fm.BATCH_ID, fm.DISPLAY_OPERATOR_INSTRUCTION, ''PENDING'', CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_ol_cluster = 1 THEN
        SET @line_cols = CONCAT(@line_cols, ', CLUSTER_ID');
        SET @line_sel  = CONCAT(@line_sel,  ', fm.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_line_request_data (', @line_cols, ') ',
        'SELECT ', @line_sel, ' ',
        '  FROM tmp_final_map fm ',
        '  JOIN tmp_child_orders co ',
        '    ON co.PARENT_ORDER_ID = fm.PARENT_ORDER_ID ',
        '   AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE ',
        '   AND co.CLUSTER_ID = fm.CLUSTER_ID ',
        '   AND co.SPLIT_GROUP = fm.SPLIT_GROUP ',
        '  JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        '  LEFT JOIN wms_to_wcs_order_line_request_data lr ',
        '    ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID ',
        '   AND lr.ORDER_LINE_ID = fm.ORDER_LINE_ID ',
        ' WHERE lr.ORDER_LINE_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_final_map fm
    JOIN tmp_child_orders co
      ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
     AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
     AND co.CLUSTER_ID        = fm.CLUSTER_ID
     AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
    JOIN wms_to_wcs_order_request_data r
      ON r.ORDER_ID = co.CHILD_ORDER_ID
    LEFT JOIN wms_to_wcs_order_line_request_data lr
      ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID
     AND lr.ORDER_LINE_ID            = fm.ORDER_LINE_ID
    WHERE lr.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('DB_WRITE_MISSING_LINES=', v_missing_lines, ' (expected all tmp_final_map lines in DB)');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    
    SELECT COUNT(*) INTO v_cnt_db_child_lines
    FROM wms_to_wcs_order_line_request_data lr
    JOIN wms_to_wcs_order_request_data r
      ON r.WMS_ORDER_REQUEST_DATA_ID = lr.WMS_ORDER_REQUEST_DATA_ID
    JOIN tmp_child_orders co
      ON co.CHILD_ORDER_ID = r.ORDER_ID;

ELSE
    SET v_cnt_db_child_lines = 0;
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
CREATE TEMPORARY TABLE tmp_child_demand (
    ORDER_ID VARCHAR(180) NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    DEMAND_QTY BIGINT NOT NULL,
    PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, DEMAND_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_child_demand
SELECT
    co.CHILD_ORDER_ID AS ORDER_ID,
    fm.PARENT_ORDER_ID,
    fm.CLIENT_ORDER_TYPE,
    fm.CLUSTER_ID AS DEMAND_CLUSTER_ID,
    fm.ARTICLE_ID,
    fm.BATCH_ID,
    SUM(fm.QUANTITY) AS DEMAND_QTY
FROM tmp_final_map fm
JOIN tmp_child_orders co
  ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
 AND co.CLUSTER_ID        = fm.CLUSTER_ID
 AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
WHERE fm.IS_SUSPENDED_GROUP = 0
  AND fm.ARTICLE_ID IS NOT NULL
  AND fm.BATCH_ID IS NOT NULL
  AND fm.CLUSTER_ID <> 'NO_INVENTORY'
  AND co.CHILD_STATUS = 'PENDING'
GROUP BY co.CHILD_ORDER_ID, fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.ARTICLE_ID, fm.BATCH_ID;

IF (SELECT COUNT(*) FROM tmp_child_demand) > 0 THEN

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
    CREATE TEMPORARY TABLE tmp_res_need_clusters (
        ORDER_ID         VARCHAR(180) NOT NULL,
        ARTICLE_ID       VARCHAR(200) NOT NULL,
        BATCH_ID         VARCHAR(200) NOT NULL,
        CLUSTER_ID       VARCHAR(50)  NOT NULL,
        DEMAND_QTY       BIGINT NOT NULL,
        PRIORITY         INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,
        CLUSTER_SUPPLY   BIGINT NOT NULL,
        CUM_SUPPLY_PREV  BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID),
        KEY idx_need (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_need_clusters
        (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID, DEMAND_QTY, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_SUPPLY, CUM_SUPPLY_PREV)
    SELECT
        z.ORDER_ID,
        z.ARTICLE_ID,
        z.BATCH_ID,
        z.CLUSTER_ID,
        z.DEMAND_QTY,
        z.PRIORITY,
        z.SRC_CLUSTER_RANK,
        z.CLUSTER_SUPPLY,
        COALESCE(z.cum_supply_prev, 0) AS CUM_SUPPLY_PREV
    FROM (
        SELECT
            d.ORDER_ID,
            d.PARENT_ORDER_ID,
            d.CLIENT_ORDER_TYPE,
            d.DEMAND_CLUSTER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            d.DEMAND_QTY,

            cs.CLUSTER_ID,
            cs.SUPPLY_QTY AS CLUSTER_SUPPLY,

            CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END AS PRIORITY,
            COALESCE(bcs.SCORE_RANK, 999999) AS SRC_CLUSTER_RANK,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
            ) AS cum_supply,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_supply_prev

        FROM tmp_child_demand d
        JOIN tmp_cluster_supply cs
          ON cs.ARTICLE_ID = d.ARTICLE_ID
         AND cs.BATCH_ID   = d.BATCH_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = d.PARENT_ORDER_ID
         AND bcs.CLIENT_ORDER_TYPE = d.CLIENT_ORDER_TYPE
         AND bcs.CLUSTER_ID        = cs.CLUSTER_ID
    ) z
    WHERE COALESCE(z.cum_supply_prev, 0) < z.DEMAND_QTY;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
    CREATE TEMPORARY TABLE tmp_res_bins (
        ORDER_ID VARCHAR(180) NOT NULL,
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,

        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,

        AVAIL_QTY BIGINT NOT NULL,
        LAST_TS DATETIME(3) NULL,

        PRIORITY INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,

        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY idx_rank (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK),
        KEY (BIN_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_bins
    SELECT
        d.ORDER_ID,
        d.PARENT_ORDER_ID,
        d.CLIENT_ORDER_TYPE,
        d.DEMAND_CLUSTER_ID,

        ib.CLUSTER_ID AS SRC_CLUSTER_ID,
        ib.ARTICLE_ID,
        ib.BATCH_ID,
        ib.BIN_ID,
        ib.AISLE_NUMBER,

        ib.AVAIL_QTY,
        ib.LAST_TS,

        nc.PRIORITY,
        nc.SRC_CLUSTER_RANK
    FROM tmp_child_demand d
    JOIN tmp_res_need_clusters nc
      ON nc.ORDER_ID   = d.ORDER_ID
     AND nc.ARTICLE_ID = d.ARTICLE_ID
     AND nc.BATCH_ID   = d.BATCH_ID
    
    JOIN tmp_inv_bin ib
      ON ib.ARTICLE_ID = d.ARTICLE_ID
     AND ib.BATCH_ID   = d.BATCH_ID
     AND ib.CLUSTER_ID = nc.CLUSTER_ID
    WHERE ib.AVAIL_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
    CREATE TEMPORARY TABLE tmp_res_alloc_child (
        ORDER_ID VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY (BIN_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_alloc_child
    SELECT
        rb.ORDER_ID,
        rb.ARTICLE_ID,
        rb.BATCH_ID,
        rb.BIN_ID,
        rb.AISLE_NUMBER,
        rb.SRC_CLUSTER_ID,
        rb.RESERVED_QTY
    FROM (
        SELECT
            d.ORDER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            b.BIN_ID,
            b.AISLE_NUMBER,
            b.SRC_CLUSTER_ID,
            b.AVAIL_QTY,
            b.LAST_TS,
            d.DEMAND_QTY,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
            ) AS cum_avail,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_avail_prev,

            LEAST(
                b.AVAIL_QTY,
                GREATEST(d.DEMAND_QTY - COALESCE(
                    SUM(b.AVAIL_QTY) OVER (
                        PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                        ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                    ), 0
                ), 0)
            ) AS RESERVED_QTY

        FROM tmp_child_demand d
        JOIN tmp_res_bins b
          ON b.ORDER_ID   = d.ORDER_ID
         AND b.ARTICLE_ID = d.ARTICLE_ID
         AND b.BATCH_ID   = d.BATCH_ID
    ) rb
    WHERE rb.RESERVED_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
    CREATE TEMPORARY TABLE tmp_res_shortfall (
        ORDER_ID   VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        DEMAND_QTY BIGINT NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        SHORT_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_shortfall (ORDER_ID, ARTICLE_ID, BATCH_ID, DEMAND_QTY, RESERVED_QTY, SHORT_QTY)
    SELECT
        d.ORDER_ID,
        d.ARTICLE_ID,
        d.BATCH_ID,
        d.DEMAND_QTY,
        COALESCE(a.got,0) AS RESERVED_QTY,
        GREATEST(d.DEMAND_QTY - COALESCE(a.got,0), 0) AS SHORT_QTY
    FROM tmp_child_demand d
    LEFT JOIN (
        SELECT ORDER_ID, ARTICLE_ID, BATCH_ID, SUM(RESERVED_QTY) AS got
          FROM tmp_res_alloc_child
         GROUP BY ORDER_ID, ARTICLE_ID, BATCH_ID
    ) a
      ON a.ORDER_ID = d.ORDER_ID
     AND a.ARTICLE_ID = d.ARTICLE_ID
     AND a.BATCH_ID = d.BATCH_ID
    WHERE COALESCE(a.got,0) < d.DEMAND_QTY;

END IF;


	
    

    IF v_is_dry_run = 0 THEN

        UPDATE wms_to_wcs_order_level_pre_staged_data p
        JOIN tmp_parent_orders t
          ON t.PRE_STAGED_REQ_ID = p.WMS_ORDER_REQUEST_DATA_ID
        SET p.IS_STAGED = 1,
            p.UPDATED_TIMESTAMP = CURRENT_TIMESTAMP(3),
            p.UPDATED_BY = 'SPLIT-OPS-V6';
    END IF;

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='2',
           ORDERSPLIT_ENDTIME = NOW(),
           RULE_STATS = JSON_OBJECT(
               'RULE_ID', v_rule_id,
               'RULE_LOG_ID', v_ruleLog_id,
               'RUN_PRIORITY', v_run_priority,
               'DRY_RUN', v_is_dry_run,
               'RESERVATION_KEY', v_reservation_key,
               'PARENTS_FOUND', v_parent_cnt,
               'LINES_CONSIDERED', v_line_cnt,
               'CHILD_ORDERS_CREATED', v_child_cnt,
               'MAX_ORDER_LINES_PER_ORDER', v_max_lines,
               'MAX_QUANTITY_PER_ORDER', v_max_qty,
               'TOL_LINES', v_tol_lines,
               'TOL_QTY', v_tol_qty,
               'HARD_LINES', v_hard_lines,
               'HARD_QTY', v_hard_qty,
               'SUSPEND_SHORT_LINES', v_suspend_short_lines,
               'CATEGORY_DEFAULT', 'FOOD',
               'NAMING', 'PARENT_ORDER_ID parent; ORDER_ID child/sub; SUB_ORDER_ID NOT USED',
               'STATION_PREF', JSON_OBJECT(
                   'MODE_USED', v_station_mode,
                   'USER_STATION_CNT', v_user_station_cnt,
                   'STATION_BIAS_ENABLED', v_use_station_bias
               ),
               'VALIDATIONS', JSON_OBJECT(
                   'tmp_lines', v_cnt_lines,
                   'tmp_lines_cat', v_cnt_lines_cat,
                   'tmp_line_assign', v_cnt_line_assign,
                   'tmp_ranked_lines', v_cnt_ranked,
                   'tmp_final_map', v_cnt_final,
                   'db_child_lines', v_cnt_db_child_lines
               ),
               'SUPPLY_CAP', JSON_OBJECT(
                   'ENABLED', 1,
                   'NOTE', 'Allocator decrements per SKU/BATCH/CLUSTER; assigns dominant cluster; NO_INVENTORY lines suspended'
               ),
               'RESERVATION', JSON_OBJECT(
                   'TTL_MINUTES', v_res_ttl_minutes,
                   'BLOCKED_LOCATION_EXCLUDED', 1,
                   'AUDIT_GRANULARITY', 'ORDER_ID+SKU/BATCH+BIN'
               )
           )
     WHERE ID = v_ruleLog_id;

    

    COMMIT;
    DO RELEASE_LOCK(v_lock_key);

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
        DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
        DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
        DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
        DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
        DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
		DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc_sum;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster_weight;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_group_flags;

    END;


SELECT
    v_rule_id AS RULE_ID,
    v_ruleLog_id AS RULE_LOG_ID,
    v_reservation_key AS RESERVATION_KEY,
    v_parent_cnt AS PARENTS_PROCESSED,
    v_line_cnt AS LINES_CONSIDERED,
    v_child_cnt AS CHILD_ORDERS_CREATED;



END sp_main */$$
DELIMITER ;

/* Procedure structure for procedure `sp_split_orders_ops_v16` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_split_orders_ops_v16` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sp_split_orders_ops_v16`()
sp_main: BEGIN

    
    DECLARE v_max_lines INT DEFAULT 50;
    DECLARE v_max_qty   INT DEFAULT 500;
    DECLARE v_tol_lines INT DEFAULT 10;
    DECLARE v_tol_qty   INT DEFAULT 100;

    DECLARE v_hard_lines INT DEFAULT 60;
    DECLARE v_hard_qty   INT DEFAULT 600;
	
	DECLARE v_bucketK INT DEFAULT 1;
DECLARE v_bucket_primary_cluster VARCHAR(50) DEFAULT NULL;
DECLARE v_last_bucket_parent VARCHAR(100) DEFAULT NULL;
DECLARE v_last_bucket_cat    VARCHAR(100) DEFAULT NULL;


    DECLARE v_suspend_short_lines INT DEFAULT 0;  
    DECLARE v_res_ttl_minutes INT DEFAULT 30;

    
    DECLARE v_ruleLog_id BIGINT DEFAULT NULL;
    DECLARE v_rule_id BIGINT DEFAULT NULL;
    DECLARE v_rule_defination TEXT DEFAULT NULL;

    
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_lock_key VARCHAR(128) DEFAULT NULL;

    
    DECLARE v_reservation_key VARCHAR(64) DEFAULT NULL;

    
    DECLARE v_station_mode ENUM('FINAL','INITIAL') DEFAULT NULL;
    DECLARE v_user_station_cnt BIGINT DEFAULT 0;

    
    DECLARE v_run_priority ENUM('INITIAL','FINAL') DEFAULT 'FINAL';
    DECLARE v_is_dry_run INT DEFAULT 0;

    
    DECLARE v_parent_cnt BIGINT DEFAULT 0;
    DECLARE v_line_cnt BIGINT DEFAULT 0;
    DECLARE v_child_cnt BIGINT DEFAULT 0;

    
    DECLARE v_cnt_lines BIGINT DEFAULT 0;
    DECLARE v_cnt_lines_cat BIGINT DEFAULT 0;
    DECLARE v_cnt_line_assign BIGINT DEFAULT 0;
    DECLARE v_cnt_ranked BIGINT DEFAULT 0;
    DECLARE v_cnt_final BIGINT DEFAULT 0;
    DECLARE v_cnt_db_child_lines BIGINT DEFAULT 0;

    DECLARE v_pre_lines BIGINT DEFAULT 0;
    DECLARE v_post_lines BIGINT DEFAULT 0;
    DECLARE v_pre_qty BIGINT DEFAULT 0;
    DECLARE v_post_qty BIGINT DEFAULT 0;
    DECLARE v_missing_lines BIGINT DEFAULT 0;

    DECLARE v_errmsg TEXT DEFAULT '';

    
    DECLARE v_has_or_cluster INT DEFAULT 0;
    DECLARE v_has_ol_cluster INT DEFAULT 0;

    DECLARE v_has_reco_col INT DEFAULT 0;   
    DECLARE v_has_reco1 INT DEFAULT 0;      
    DECLARE v_has_reco2 INT DEFAULT 0;      
    DECLARE v_has_reco1_alt INT DEFAULT 0;  
    DECLARE v_has_reco2_alt INT DEFAULT 0;  

    DECLARE v_has_hw_station INT DEFAULT 0;
    DECLARE v_has_hw_wave_status INT DEFAULT 0;

    
    DECLARE v_sku   VARCHAR(200) DEFAULT NULL;
    DECLARE v_batch VARCHAR(200) DEFAULT NULL;

    DECLARE v_rn INT DEFAULT 0;
    DECLARE v_maxrn INT DEFAULT 0;

    DECLARE v_line_parent VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_cat    VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_id     VARCHAR(36)  DEFAULT NULL;
    DECLARE v_line_qty    INT DEFAULT 0;

    DECLARE v_pick_cluster VARCHAR(50) DEFAULT NULL;

    DECLARE v_need BIGINT DEFAULT 0;
    DECLARE v_total_rem BIGINT DEFAULT 0;

    DECLARE v_crn INT DEFAULT 0;
    DECLARE v_cmax INT DEFAULT 0;
    DECLARE v_cur_cluster VARCHAR(50) DEFAULT NULL;
    DECLARE v_cur_rem BIGINT DEFAULT 0;
    DECLARE v_alloc BIGINT DEFAULT 0;

    
    DECLARE v_balance_mode INT DEFAULT 1;   
    DECLARE v_k1_pool INT DEFAULT 1;        

    
    DECLARE v_use_station_bias INT DEFAULT 0;   
    DECLARE v_near_aisle_window INT DEFAULT 1;  
    DECLARE v_min_pref_aisle INT DEFAULT NULL;
    DECLARE v_max_pref_aisle INT DEFAULT NULL;

    DECLARE v_total_lines_all BIGINT DEFAULT 0;
    DECLARE v_total_qty_all BIGINT DEFAULT 0;
    DECLARE v_total_lines_pickable BIGINT DEFAULT 0;
    DECLARE v_total_qty_pickable BIGINT DEFAULT 0;
    DECLARE v_alloc_qty_total BIGINT DEFAULT 0;
    DECLARE v_alloc_lines_total BIGINT DEFAULT 0;
    
	    
    DECLARE v_tmp_user_stations_ready INT DEFAULT 0;
        
    DECLARE v_lock_wait_seconds INT DEFAULT -1;

    
    DECLARE v_station_pref_consumed INT DEFAULT 0;

    
    DECLARE v_job_id BIGINT DEFAULT NULL;
    DECLARE v_job_rule_id BIGINT DEFAULT NULL;
    DECLARE v_job_priority ENUM('INITIAL','FINAL') DEFAULT NULL;



    
       
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;

        
        IF v_rule_id IS NOT NULL
           AND v_station_mode IS NOT NULL
           AND v_user_station_cnt > 0
           AND v_tmp_user_stations_ready = 1
        THEN
            UPDATE picklist_split_station_pref p
            JOIN tmp_user_stations t
              ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
            SET p.IS_PROCESSED = 0
            WHERE p.RULE_ID = v_rule_id
              AND p.PRIORITY = v_station_mode
              AND p.IS_PROCESSED = 1;
        END IF;

        
        IF v_ruleLog_id IS NOT NULL THEN
            UPDATE picklist_split_order_master
               SET IS_PROCESSED = '0',
                   ORDERSPLIT_ENDTIME = NOW()
             WHERE ID = v_ruleLog_id;
        END IF;

        
        
DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;

DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;       
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;     
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;      

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_final_map;

DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2;

DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;

DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;

DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc_sum;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster_weight;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_group_flags;


        
        IF v_lock_ok = 1 AND v_lock_key IS NOT NULL THEN
            DO RELEASE_LOCK(v_lock_key);
        END IF;

        RESIGNAL;
    END;


    

    SET v_max_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_ORDER_LINES_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_lines
    );

    SET v_max_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_QUANTITY_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_qty
    );

    SET v_near_aisle_window = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_NEAR_AISLE_WINDOW' AND IS_ACTIVE = 1
          LIMIT 1),
        v_near_aisle_window
    );
    SET v_near_aisle_window = GREATEST(v_near_aisle_window, 0);

    SET v_tol_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_lines
    );

    SET v_tol_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_QTY' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_qty
    );

    SET v_suspend_short_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'SUSPEND_SHORT_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_suspend_short_lines
    );

    SET v_res_ttl_minutes = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'RESERVATION_TTL_MINUTES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_res_ttl_minutes
    );

    SET v_balance_mode = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_BALANCE_MODE' AND IS_ACTIVE = 1
          LIMIT 1),
        v_balance_mode
    );

    SET v_k1_pool = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_K1_POOL' AND IS_ACTIVE = 1
          LIMIT 1),
        v_k1_pool
    );
    SET v_k1_pool = GREATEST(v_k1_pool, 1);

        
    SET v_max_lines = GREATEST(v_max_lines, 1);
    SET v_max_qty   = GREATEST(v_max_qty,   1);
    SET v_tol_lines = GREATEST(v_tol_lines, 0);
    SET v_tol_qty   = GREATEST(v_tol_qty,   0);

    SET v_hard_lines = v_max_lines + v_tol_lines;
    SET v_hard_qty   = v_max_qty   + v_tol_qty;


    

    SELECT COUNT(*) INTO v_has_or_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_ol_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_line_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_reco_col
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'RECOMMENDATION';

    SELECT COUNT(*) INTO v_has_reco1
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_1';

    SELECT COUNT(*) INTO v_has_reco2
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_2';

    SELECT COUNT(*) INTO v_has_reco1_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_1';

    SELECT COUNT(*) INTO v_has_reco2_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_2';

    SELECT COUNT(*) INTO v_has_hw_station
      FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master';

    SELECT COUNT(*) INTO v_has_hw_wave_status
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master'
       AND COLUMN_NAME  = 'wave_status';

          

    job_pick: LOOP

        SET v_job_id = NULL;
        SET v_job_rule_id = NULL;
        SET v_job_priority = NULL;

        
        SELECT
            ID,
            RULE_ID,
            CASE
                WHEN COALESCE(NULLIF(PRIORITY,''),'FINAL') IN ('FINAL','INITIAL')
                    THEN COALESCE(NULLIF(PRIORITY,''),'FINAL')
                ELSE 'FINAL'
            END
          INTO v_job_id, v_job_rule_id, v_job_priority
        FROM picklist_split_order_master
        WHERE IS_PROCESSED = '0'
        ORDER BY ID
        LIMIT 1;

        IF v_job_id IS NULL OR v_job_rule_id IS NULL THEN

    
    SET @reco1_cluster_json := JSON_ARRAY(
        JSON_OBJECT(
            'CLUSTER_ID',  'NA',
            'STATION_ID',  '0',
            'STATION_CNT', 0,
            'ORDER_LINES', 0,
            '%_LINES',     0.00,
            'ORDER_QTY',   0,
            '%_QTY',       0.00
        )
    );

    SET @reco2_cluster_json := @reco1_cluster_json;

    SET @dummy_master_reco := JSON_OBJECT(
        'RECOMMENDATION_1_ALL_STATIONS',          CAST(@reco1_cluster_json AS JSON),
        'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

        'STATION_PREF_MODE', NULL,
        'USER_SELECTED_STATIONS', '',
        'RULE_ID', NULL,
        'RULE_LOG_ID', NULL,
        'TOTAL_INITIAL_ORDERS', 0,
        'TOTAL_SPLIT_ORDERS',  0,

        'INITIAL_ORDER_LINES', 0,
        'AFTER_ALLOCATION_ORDER_LINES', 0,
        'TOTAL_LINES_PICKABLE', 0,

        'TOTAL_QTY_ALL', 0,
        'TOTAL_QTY_PICKABLE', 0,
        'ALLOC_QTY_TOTAL', 0,
        'ALLOC_LINES_TOTAL', 0,

        'NOTES', JSON_OBJECT(
            'PARENT_FIELD', 'PARENT_ORDER_ID',
            'CHILD_FIELD',  'ORDER_ID',
            'SUB_ORDER_ID', 'NOT_USED',
            'RESERVATION_KEY', '',
            'RESERVATION_TTL_MINUTES', 0,
            'DUMMY', 1
        )
    );

    
    SELECT
        'NO_RULE_TO_PROCESS' AS STATUS,
        CAST(@reco1_cluster_json AS JSON) AS recommendation_1,
        CAST(@reco2_cluster_json AS JSON) AS recommendation_2,
        CAST(@dummy_master_reco  AS JSON) AS RECOMMENDATION;

    LEAVE sp_main;
END IF;


        
        SET v_lock_key = CONCAT('SPLIT_CLUSTER_', v_job_rule_id);
        SELECT GET_LOCK(v_lock_key, v_lock_wait_seconds) INTO v_lock_ok;

        IF v_lock_ok IS NULL THEN
            SET v_errmsg = CONCAT('GET_LOCK_ERROR: key=', v_lock_key);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        ELSEIF v_lock_ok = 0 THEN
            
            SET v_errmsg = CONCAT('Split job already running (lock timeout) for RULE_ID=', v_job_rule_id);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        END IF;

        
        START TRANSACTION;

        SELECT
            ID,
            RULE_ID,
            v_job_priority
          INTO v_ruleLog_id, v_rule_id, v_run_priority
        FROM picklist_split_order_master
        WHERE ID = v_job_id
          AND IS_PROCESSED = '0'
        FOR UPDATE SKIP LOCKED;

        
        IF v_ruleLog_id IS NULL OR v_rule_id IS NULL THEN
            ROLLBACK;
            DO RELEASE_LOCK(v_lock_key);
            SET v_lock_ok = 0;
            ITERATE job_pick;
        END IF;

        LEAVE job_pick;
    END LOOP;

    
    SET v_is_dry_run = CASE WHEN v_run_priority = 'INITIAL' THEN 1 ELSE 0 END;

    
    
    IF v_is_dry_run = 1 THEN
        
        SET v_balance_mode = 1;
        
        SET v_k1_pool      = GREATEST(v_k1_pool, 3);
    END IF;


    SELECT FILTER_CONDITION
      INTO v_rule_defination
    FROM pick_rule_master
    WHERE PICK_RULE_ID = v_rule_id
    LIMIT 1;

    IF v_rule_defination IS NULL OR LENGTH(v_rule_defination) < 3 THEN
        
        UPDATE picklist_split_order_master
           SET IS_PROCESSED = '2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        COMMIT;
        DO RELEASE_LOCK(v_lock_key);

        SELECT 'NO_RULE_DEFINITION_FOUND' AS STATUS, v_rule_id AS RULE_ID;
        LEAVE sp_main;
    END IF;

    
    SET v_rule_defination = LEFT(v_rule_defination, LENGTH(v_rule_defination)-1);


    

SET v_station_mode = NULL;
SET v_user_station_cnt = 0;
SET v_station_pref_consumed = 0;   


IF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'FINAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'FINAL';
ELSEIF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'INITIAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'INITIAL';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
CREATE TEMPORARY TABLE tmp_user_stations (
    STATION_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (STATION_ID)
) ENGINE=INNODB;

SET v_tmp_user_stations_ready = 1;

IF v_station_mode IS NOT NULL THEN

    
    INSERT IGNORE INTO tmp_user_stations (STATION_ID)
    SELECT CAST(STATION_ID AS CHAR(50))
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND PRIORITY = v_station_mode
       AND IS_PROCESSED = 0
     ORDER BY STATION_ID
     FOR UPDATE;

    SELECT COUNT(*) INTO v_user_station_cnt FROM tmp_user_stations;

END IF;


SET v_use_station_bias =
    CASE
        WHEN v_is_dry_run = 0 AND v_user_station_cnt > 0 AND v_has_hw_station = 1 THEN 1
        ELSE 0
    END;



DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
CREATE TEMPORARY TABLE tmp_pref_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
CREATE TEMPORARY TABLE tmp_near_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_pref_clusters (CLUSTER_ID)
    SELECT DISTINCT CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.CLUSTER_ID IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
    CREATE TEMPORARY TABLE tmp_pref_aisle_num (
        AISLE_NUM INT NOT NULL,
        PRIMARY KEY (AISLE_NUM)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_pref_aisle_num (AISLE_NUM)
    SELECT DISTINCT
           CAST(
               NULLIF(
                   REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                   ''
               ) AS UNSIGNED
           ) AS AISLE_NUM
      FROM cluster_aisle_mapping cam
      JOIN tmp_pref_clusters pc
        ON pc.CLUSTER_ID = cam.CLUSTER_ID
     WHERE cam.AISLE_NUMBER IS NOT NULL;

    
    SELECT MIN(AISLE_NUM), MAX(AISLE_NUM)
      INTO v_min_pref_aisle, v_max_pref_aisle
      FROM tmp_pref_aisle_num;

    IF v_min_pref_aisle IS NOT NULL AND v_max_pref_aisle IS NOT NULL THEN

        
        INSERT IGNORE INTO tmp_near_clusters (CLUSTER_ID)
        SELECT DISTINCT cam.CLUSTER_ID
          FROM cluster_aisle_mapping cam
         WHERE cam.CLUSTER_ID IS NOT NULL
           AND cam.AISLE_NUMBER IS NOT NULL
           AND CAST(
                   NULLIF(
                       REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                       ''
                   ) AS UNSIGNED
               ) BETWEEN (v_min_pref_aisle - v_near_aisle_window)
                   AND (v_max_pref_aisle + v_near_aisle_window);

        
        DELETE n
          FROM tmp_near_clusters n
          JOIN tmp_pref_clusters p
            ON p.CLUSTER_ID = n.CLUSTER_ID;

    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;

END IF;




DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
CREATE TEMPORARY TABLE tmp_parent_orders (
    PRE_STAGED_REQ_ID BIGINT NOT NULL,
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    ORDER_TYPE        VARCHAR(100) NOT NULL,
    PRIMARY KEY (PRE_STAGED_REQ_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;


IF v_rule_defination IS NULL OR LENGTH(TRIM(v_rule_defination)) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULE_DEFINITION_EMPTY';
END IF;

SET @sql = CONCAT(
    'INSERT INTO tmp_parent_orders (PRE_STAGED_REQ_ID, PARENT_ORDER_ID, ORDER_TYPE)
     SELECT WMS_ORDER_REQUEST_DATA_ID,
            PARENT_ORDER_ID,
            COALESCE(NULLIF(PICKING_TYPE, ''''), NULLIF(ORDER_CATEGORY, ''''), ''PICK'') AS ORDER_TYPE
       FROM wms_to_wcs_order_level_pre_staged_data
      WHERE IFNULL(IS_STAGED,0) = 0
        AND PARENT_ORDER_ID IN (', v_rule_defination, ')'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT COUNT(*) INTO v_parent_cnt FROM tmp_parent_orders;

IF v_parent_cnt = 0 THEN

    
    IF v_station_pref_consumed = 1
       AND v_rule_id IS NOT NULL
       AND v_station_mode IS NOT NULL
       AND v_tmp_user_stations_ready = 1
    THEN
        UPDATE picklist_split_station_pref p
        JOIN tmp_user_stations t
          ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
        SET p.IS_PROCESSED = 0
        WHERE p.RULE_ID = v_rule_id
          AND p.PRIORITY = v_station_mode
          AND p.IS_PROCESSED = 1;

        SET v_station_pref_consumed = 0;
    END IF;

    
    
    SET v_line_cnt = 0;

    
    IF v_reservation_key IS NULL OR v_reservation_key = '' THEN
        SET v_reservation_key = CONCAT('SPLIT_', COALESCE(v_ruleLog_id,0), '_', REPLACE(UUID(),'-',''));
    END IF;

    SET @reco1_cluster_json := JSON_ARRAY(
        JSON_OBJECT(
            'CLUSTER_ID',  'NA',
            'STATION_ID',  '0',
            'STATION_CNT', 0,
            'ORDER_LINES', 0,
            '%_LINES',     0.00,
            'ORDER_QTY',   0,
            '%_QTY',       0.00
        )
    );
    SET @reco2_cluster_json := @reco1_cluster_json;

    SET @dummy_user_selected := '';
    IF v_tmp_user_stations_ready = 1 THEN
        SELECT COALESCE(GROUP_CONCAT(STATION_ID ORDER BY STATION_ID SEPARATOR ','), '')
          INTO @dummy_user_selected
          FROM tmp_user_stations;
    END IF;

    SET @dummy_master_reco := JSON_OBJECT(
        'RECOMMENDATION_1_ALL_STATIONS',          CAST(@reco1_cluster_json AS JSON),
        'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

        'STATION_PREF_MODE', v_station_mode,
        'USER_SELECTED_STATIONS', @dummy_user_selected,
        'RULE_ID', v_rule_id,
        'RULE_LOG_ID', v_ruleLog_id,
        'TOTAL_INITIAL_ORDERS', v_parent_cnt,
        'TOTAL_SPLIT_ORDERS',  0,

        'INITIAL_ORDER_LINES', v_line_cnt,
        'AFTER_ALLOCATION_ORDER_LINES', 0,
        'TOTAL_LINES_PICKABLE', 0,

        'TOTAL_QTY_ALL', 0,
        'TOTAL_QTY_PICKABLE', 0,
        'ALLOC_QTY_TOTAL', 0,
        'ALLOC_LINES_TOTAL', 0,

        'NOTES', JSON_OBJECT(
            'PARENT_FIELD', 'PARENT_ORDER_ID',
            'CHILD_FIELD',  'ORDER_ID',
            'SUB_ORDER_ID', 'NOT_USED',
            'RESERVATION_KEY', COALESCE(v_reservation_key,''),
            'RESERVATION_TTL_MINUTES', v_res_ttl_minutes,
            'DUMMY', 1,
            'REASON', 'NO_PARENTS_TO_SPLIT'
        )
    );

    
    IF v_ruleLog_id IS NOT NULL THEN

        IF v_has_reco1 = 1 OR v_has_reco1_alt = 1 THEN
            UPDATE picklist_split_order_master
               SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

        IF v_has_reco2 = 1 OR v_has_reco2_alt = 1 THEN
            UPDATE picklist_split_order_master
               SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

        IF v_has_reco_col = 1 THEN
            UPDATE picklist_split_order_master
               SET RECOMMENDATION = CAST(@dummy_master_reco AS JSON)
             WHERE ID = v_ruleLog_id;
        END IF;

    END IF;

    
    UPDATE picklist_split_order_master
       SET IS_PROCESSED = '2',
           ORDERSPLIT_ENDTIME = NOW()
     WHERE ID = v_ruleLog_id;

    COMMIT;

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
    END;

    DO RELEASE_LOCK(v_lock_key);

    SELECT 'NO_PARENTS_TO_SPLIT' AS STATUS, v_rule_id AS RULE_ID;
    LEAVE sp_main;
END IF;


UPDATE picklist_split_order_master
   SET IS_PROCESSED = '1',
       ORDERSPLIT_STARTTIME = NOW()
 WHERE ID = v_ruleLog_id
   AND IS_PROCESSED = '0';

IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULELOG_NOT_IN_STARTABLE_STATE';
END IF;


IF v_station_mode IS NOT NULL
   AND v_user_station_cnt > 0
   AND v_tmp_user_stations_ready = 1
THEN
    UPDATE picklist_split_station_pref p
    JOIN tmp_user_stations t
      ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
    SET p.IS_PROCESSED = 1
    WHERE p.RULE_ID = v_rule_id
      AND p.PRIORITY = v_station_mode
      AND p.IS_PROCESSED = 0;

    SET v_station_pref_consumed = 1;
END IF;


SET v_reservation_key = CONCAT('SPLIT_', v_ruleLog_id, '_', REPLACE(UUID(),'-',''));



DROP TEMPORARY TABLE IF EXISTS tmp_lines;
CREATE TEMPORARY TABLE tmp_lines (
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
    ARTICLE_ID      VARCHAR(200) NULL,
    BATCH_ID        VARCHAR(200) NULL,
    QUANTITY        INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_lines
SELECT
    l.PARENT_ORDER_ID,
    l.ORDER_LINE_ID,
    l.ARTICLE_ID,
    l.BATCH_ID,
    l.QUANTITY,
    l.DISPLAY_OPERATOR_INSTRUCTION
FROM wms_to_wcs_order_line_level_pre_staged_data l
JOIN tmp_parent_orders p
  ON p.PARENT_ORDER_ID = l.PARENT_ORDER_ID
WHERE IFNULL(l.ORDER_LINE_PROCESS_STATUS,'PENDING') <> 'DELETED';

SELECT COUNT(*) INTO v_line_cnt FROM tmp_lines;

IF v_line_cnt = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'NO_LINES_FOUND_FOR_SELECTED_PARENTS';
END IF;



    

    DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
    CREATE TEMPORARY TABLE tmp_line_category (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (ARTICLE_ID),
        KEY (CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_category (ARTICLE_ID, CLIENT_ORDER_TYPE)
    SELECT
        al.ARTICLE_ID,
        COALESCE(NULLIF(cm.CLIENT_ORDER_TYPE,''), 'FOOD') AS CLIENT_ORDER_TYPE
    FROM (SELECT DISTINCT ARTICLE_ID FROM tmp_lines WHERE ARTICLE_ID IS NOT NULL) al
    LEFT JOIN sku_master sm
      ON sm.SKU_ID = al.ARTICLE_ID
    LEFT JOIN category_master cm
      ON cm.CATEGORY_ID = sm.CATEGORY;

    DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
    CREATE TEMPORARY TABLE tmp_lines_cat (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines_cat
    SELECT
        tl.PARENT_ORDER_ID,
        COALESCE(lc.CLIENT_ORDER_TYPE, 'FOOD') AS CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION
    FROM tmp_lines tl
    LEFT JOIN tmp_line_category lc
      ON lc.ARTICLE_ID = tl.ARTICLE_ID;

    
    SELECT COUNT(*) INTO v_cnt_lines     FROM tmp_lines;
    SELECT COUNT(*) INTO v_cnt_lines_cat FROM tmp_lines_cat;

    IF v_cnt_lines_cat <> v_cnt_lines THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_CATEGORY: tmp_lines=', v_cnt_lines,
                              ', tmp_lines_cat=', v_cnt_lines_cat);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

 


DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
CREATE TEMPORARY TABLE tmp_aisle_cluster_raw (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER, CLUSTER_ID),
    KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster_raw (AISLE_NUMBER, CLUSTER_ID)
SELECT DISTINCT AISLE_NUMBER, CLUSTER_ID
  FROM cluster_aisle_mapping
 WHERE AISLE_NUMBER IS NOT NULL
   AND CLUSTER_ID IS NOT NULL;

IF (SELECT COUNT(*) FROM tmp_aisle_cluster_raw) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: cluster_aisle_mapping has no AISLE_NUMBER->CLUSTER_ID rows';
END IF;

IF EXISTS (
    SELECT 1
      FROM (
            SELECT AISLE_NUMBER, COUNT(*) AS c
              FROM tmp_aisle_cluster_raw
             GROUP BY AISLE_NUMBER
            HAVING c > 1
      ) X
    LIMIT 1
) THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: AISLE_NUMBER maps to multiple CLUSTER_ID in cluster_aisle_mapping';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
CREATE TEMPORARY TABLE tmp_aisle_cluster (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster (AISLE_NUMBER, CLUSTER_ID)
SELECT AISLE_NUMBER, CLUSTER_ID
  FROM tmp_aisle_cluster_raw;




DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
CREATE TEMPORARY TABLE tmp_sku_global (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_global
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_lines_cat
 WHERE ARTICLE_ID IS NOT NULL AND BATCH_ID IS NOT NULL;

DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
CREATE TEMPORARY TABLE tmp_inv_bin (
    BIN_ID INT NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    AVAIL_QTY BIGINT NOT NULL,
    LAST_TS DATETIME(3) NULL,
    PRIMARY KEY (BIN_ID, ARTICLE_ID, BATCH_ID),

    KEY (ARTICLE_ID, BATCH_ID),
    KEY (CLUSTER_ID),
    KEY (AISLE_NUMBER),

    
    KEY idx_ab_cluster (ARTICLE_ID, BATCH_ID, CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_inv_bin (BIN_ID, ARTICLE_ID, BATCH_ID, AISLE_NUMBER, CLUSTER_ID, AVAIL_QTY, LAST_TS)
SELECT
    lim.BIN_ID,
    lim.ARTICLE_ID,
    lim.BATCH_ID,
    lmst.AISLE_NUMBER,
    ac.CLUSTER_ID,
    GREATEST(
        CAST(SUM(GREATEST(lim.QUANTITY - lim.VIRTUAL_QUANTITY_TO_PICK, 0)) AS SIGNED),
        0
    ) AS AVAIL_QTY,
    MAX(lim.UPDATED_TIMESTAMP) AS LAST_TS
FROM live_inventory_master lim
JOIN tmp_sku_global sg
  ON sg.ARTICLE_ID = lim.ARTICLE_ID
 AND sg.BATCH_ID   = lim.BATCH_ID
JOIN store_bin_master sb
  ON sb.BIN_ID = lim.BIN_ID
JOIN location_master lmst
  ON lmst.LOCATION_ID = sb.LOCATION_ID
LEFT JOIN location_block_master lb
  ON lb.LOCATION_ID = sb.LOCATION_ID
JOIN tmp_aisle_cluster ac
  ON ac.AISLE_NUMBER = lmst.AISLE_NUMBER
WHERE lim.IS_ACTIVE = 1
  AND lim.BIN_ID IS NOT NULL
  AND lmst.AISLE_NUMBER IS NOT NULL
  AND lb.LOCATION_ID IS NULL
GROUP BY lim.BIN_ID, lim.ARTICLE_ID, lim.BATCH_ID, lmst.AISLE_NUMBER, ac.CLUSTER_ID
HAVING AVAIL_QTY > 0;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
CREATE TEMPORARY TABLE tmp_cluster_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply (ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY)
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUM(AVAIL_QTY) AS SUPPLY_QTY
  FROM tmp_inv_bin
 GROUP BY ARTICLE_ID, BATCH_ID, CLUSTER_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
CREATE TEMPORARY TABLE tmp_sku_total_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_SUPPLY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_total_supply
SELECT ARTICLE_ID, BATCH_ID, SUM(SUPPLY_QTY) AS TOTAL_SUPPLY
  FROM tmp_cluster_supply
 GROUP BY ARTICLE_ID, BATCH_ID;




DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
CREATE TEMPORARY TABLE tmp_final_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    CL_NUM     INT NULL,
    PRIMARY KEY (CLUSTER_ID),
    KEY (CL_NUM)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
CREATE TEMPORARY TABLE tmp_cluster_snap_map (
    SRC_CLUSTER_ID      VARCHAR(50) NOT NULL,
    SNAPPED_CLUSTER_ID  VARCHAR(50) NOT NULL,
    PRIMARY KEY (SRC_CLUSTER_ID),
    KEY (SNAPPED_CLUSTER_ID)
) ENGINE=INNODB;


DROP TEMPORARY TABLE IF EXISTS tmp_final_cluster_default;
CREATE TEMPORARY TABLE tmp_final_cluster_default (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_final_clusters (CLUSTER_ID, CL_NUM)
    SELECT
        pc.CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(pc.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS CL_NUM
    FROM tmp_pref_clusters pc
    WHERE pc.CLUSTER_ID IS NOT NULL;

    
    IF (SELECT COUNT(*) FROM tmp_final_clusters) = 0 THEN
        SET v_use_station_bias = 0;
    END IF;

    
    IF v_use_station_bias = 1 THEN
        INSERT INTO tmp_final_cluster_default (CLUSTER_ID)
        SELECT fc.CLUSTER_ID
          FROM tmp_final_clusters fc
         ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
         LIMIT 1;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;
    CREATE TEMPORARY TABLE tmp_supply_clusters (
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        SRC_NUM        INT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID),
        KEY (SRC_NUM)
    ) ENGINE=INNODB;

    INSERT INTO tmp_supply_clusters (SRC_CLUSTER_ID, SRC_NUM)
    SELECT DISTINCT
        cs.CLUSTER_ID AS SRC_CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(cs.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS SRC_NUM
    FROM tmp_cluster_supply cs;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    CREATE TEMPORARY TABLE tmp_snap_candidates (
        SRC_CLUSTER_ID   VARCHAR(50) NOT NULL,
        CAND_CLUSTER_ID  VARCHAR(50) NOT NULL,
        RN               INT NOT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID, RN),
        KEY (CAND_CLUSTER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_snap_candidates (SRC_CLUSTER_ID, CAND_CLUSTER_ID, RN)
    SELECT
        sc.SRC_CLUSTER_ID,
        fc.CLUSTER_ID AS CAND_CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY sc.SRC_CLUSTER_ID
            ORDER BY
                ABS(COALESCE(fc.CL_NUM,0) - COALESCE(sc.SRC_NUM,0)),
                
                CASE WHEN COALESCE(fc.CL_NUM,0) >= COALESCE(sc.SRC_NUM,0) THEN 0 ELSE 1 END,
                COALESCE(fc.CL_NUM,0),
                fc.CLUSTER_ID
        ) AS RN
    FROM tmp_supply_clusters sc
    JOIN tmp_final_clusters fc
      ON 1=1;

    
    INSERT IGNORE INTO tmp_cluster_snap_map (SRC_CLUSTER_ID, SNAPPED_CLUSTER_ID)
    SELECT
        sc.SRC_CLUSTER_ID,
        CASE
            WHEN fc_same.CLUSTER_ID IS NOT NULL THEN sc.SRC_CLUSTER_ID
            ELSE COALESCE(c.CAND_CLUSTER_ID, d.CLUSTER_ID)
        END AS SNAPPED_CLUSTER_ID
    FROM tmp_supply_clusters sc
    LEFT JOIN tmp_final_clusters fc_same
      ON fc_same.CLUSTER_ID = sc.SRC_CLUSTER_ID
    LEFT JOIN tmp_snap_candidates c
      ON c.SRC_CLUSTER_ID = sc.SRC_CLUSTER_ID
     AND c.RN = 1
    LEFT JOIN tmp_final_cluster_default d
      ON 1=1;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;

END IF;


    

    

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
CREATE TEMPORARY TABLE tmp_line_cluster_candidates (
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    ORDER_LINE_ID VARCHAR(36) NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    C_RANK INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, C_RANK)
) ENGINE=INNODB;

INSERT INTO tmp_line_cluster_candidates
SELECT
    lc.PARENT_ORDER_ID,
    lc.CLIENT_ORDER_TYPE,
    lc.ORDER_LINE_ID,
    lc.ARTICLE_ID,
    lc.BATCH_ID,
    cs.CLUSTER_ID,
    cs.SUPPLY_QTY,
    ROW_NUMBER() OVER (
        PARTITION BY lc.PARENT_ORDER_ID, lc.CLIENT_ORDER_TYPE, lc.ORDER_LINE_ID
        ORDER BY
            cs.SUPPLY_QTY DESC,
            
            CRC32(CONCAT(
                lc.PARENT_ORDER_ID, '|',
                lc.CLIENT_ORDER_TYPE, '|',
                lc.ORDER_LINE_ID, '|',
                cs.CLUSTER_ID
            ))
    ) AS C_RANK
FROM tmp_lines_cat lc
JOIN tmp_cluster_supply cs
  ON cs.ARTICLE_ID = lc.ARTICLE_ID
 AND cs.BATCH_ID   = lc.BATCH_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
CREATE TEMPORARY TABLE tmp_line_assign (
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    ORDER_LINE_ID VARCHAR(36) NOT NULL,
    ARTICLE_ID VARCHAR(200) NULL,
    BATCH_ID   VARCHAR(200) NULL,
    QUANTITY   INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

    ASSIGNED_CLUSTER_ID VARCHAR(50) NULL,
    ASSIGNED_RANK INT NOT NULL DEFAULT 0,

    SHORT_FLAG_SCHEMA INT NOT NULL DEFAULT 0,
    SHORT_FLAG_SUPPLY INT NOT NULL DEFAULT 0,
    SHORT_FLAG INT NOT NULL DEFAULT 0,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
    UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_line_assign
SELECT
    lc.PARENT_ORDER_ID,
    lc.CLIENT_ORDER_TYPE,
    lc.ORDER_LINE_ID,
    lc.ARTICLE_ID,
    lc.BATCH_ID,
    lc.QUANTITY,
    lc.DISPLAY_OPERATOR_INSTRUCTION,
    NULL, 0,
    0, 0, 0
FROM tmp_lines_cat lc;

UPDATE tmp_line_assign la
LEFT JOIN tmp_sku_total_supply ts
  ON ts.ARTICLE_ID = la.ARTICLE_ID
 AND ts.BATCH_ID   = la.BATCH_ID
SET la.SHORT_FLAG_SCHEMA = CASE
    WHEN la.ARTICLE_ID IS NULL OR la.BATCH_ID IS NULL THEN 1
    WHEN ts.TOTAL_SUPPLY IS NULL THEN 1
    ELSE 0
END;

SELECT COUNT(*) INTO v_cnt_line_assign FROM tmp_line_assign;
IF v_cnt_line_assign <> v_cnt_lines_cat THEN
    SET v_errmsg = CONCAT('LINE_LOSS_AFTER_ASSIGN: tmp_lines_cat=', v_cnt_lines_cat,
                          ', tmp_line_assign=', v_cnt_line_assign);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
END IF;




DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
CREATE TEMPORARY TABLE tmp_bucket_k (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    TOTAL_LINES         BIGINT NOT NULL,
    TOTAL_QTY           BIGINT NOT NULL,
    K                   INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_k (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, TOTAL_LINES, TOTAL_QTY, K)
SELECT
    la.PARENT_ORDER_ID,
    la.CLIENT_ORDER_TYPE,
    COUNT(*) AS TOTAL_LINES,
    COALESCE(SUM(la.QUANTITY),0) AS TOTAL_QTY,
    GREATEST(
        1,
        IF(v_max_lines > 0, CEIL(COUNT(*) / v_max_lines), 1),
        IF(v_max_qty   > 0, CEIL(COALESCE(SUM(la.QUANTITY),0) / v_max_qty), 1)
    ) AS K
FROM tmp_line_assign la
GROUP BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
CREATE TEMPORARY TABLE tmp_bucket_cluster_score (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    BEST_LINE_CNT       BIGINT NOT NULL,
    BEST_QTY_FIT        BIGINT NOT NULL,
    SCORE               DECIMAL(30,0) NOT NULL,
    SCORE_RANK          INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SCORE_RANK),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_cluster_score
SELECT
    x.PARENT_ORDER_ID,
    x.CLIENT_ORDER_TYPE,
    x.CLUSTER_ID,
    x.BEST_LINE_CNT,
    x.BEST_QTY_FIT,
    (x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT AS SCORE,
    ROW_NUMBER() OVER (
        PARTITION BY x.PARENT_ORDER_ID, x.CLIENT_ORDER_TYPE
        ORDER BY ((x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT) DESC,
                 
                 CRC32(CONCAT(x.PARENT_ORDER_ID,'|',x.CLIENT_ORDER_TYPE,'|',x.CLUSTER_ID))
    ) AS SCORE_RANK
FROM (
    SELECT
        c.PARENT_ORDER_ID,
        c.CLIENT_ORDER_TYPE,
        c.CLUSTER_ID,
        SUM(CASE WHEN c.C_RANK = 1 THEN 1 ELSE 0 END) AS BEST_LINE_CNT,
        SUM(CASE
                WHEN c.C_RANK = 1 THEN LEAST(c.SUPPLY_QTY, la.QUANTITY)
                ELSE 0
            END) AS BEST_QTY_FIT
    FROM tmp_line_cluster_candidates c
    JOIN tmp_line_assign la
      ON la.PARENT_ORDER_ID = c.PARENT_ORDER_ID
     AND la.CLIENT_ORDER_TYPE = c.CLIENT_ORDER_TYPE
     AND la.ORDER_LINE_ID = c.ORDER_LINE_ID
    GROUP BY c.PARENT_ORDER_ID, c.CLIENT_ORDER_TYPE, c.CLUSTER_ID
) X;

DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
CREATE TEMPORARY TABLE tmp_allowed_clusters (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
SELECT
    s.PARENT_ORDER_ID,
    s.CLIENT_ORDER_TYPE,
    s.CLUSTER_ID
FROM tmp_bucket_cluster_score s
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
WHERE s.SCORE_RANK <= CASE
    WHEN v_balance_mode = 1 AND k.K = 1 THEN GREATEST(k.K, v_k1_pool)
    ELSE k.K
END;

IF (SELECT COUNT(*) FROM tmp_allowed_clusters) = 0 THEN
    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
      FROM tmp_bucket_cluster_score;
END IF;


IF v_use_station_bias = 1 THEN

    DELETE ac
      FROM tmp_allowed_clusters ac
      LEFT JOIN tmp_final_clusters fc
        ON fc.CLUSTER_ID = ac.CLUSTER_ID
     WHERE fc.CLUSTER_ID IS NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
    CREATE TEMPORARY TABLE tmp_empty_buckets (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_empty_buckets (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    SELECT bk.PARENT_ORDER_ID, bk.CLIENT_ORDER_TYPE
      FROM tmp_bucket_k bk
      LEFT JOIN tmp_allowed_clusters ac2
        ON ac2.PARENT_ORDER_ID   = bk.PARENT_ORDER_ID
       AND ac2.CLIENT_ORDER_TYPE = bk.CLIENT_ORDER_TYPE
     WHERE ac2.PARENT_ORDER_ID IS NULL;

    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT eb.PARENT_ORDER_ID, eb.CLIENT_ORDER_TYPE, fc2.CLUSTER_ID
      FROM tmp_empty_buckets eb
      CROSS JOIN tmp_final_clusters fc2;

    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
CREATE TEMPORARY TABLE tmp_bucket_choice (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CHOSEN_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CHOSEN_CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_choice
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    MAX(CASE WHEN rn = 1 + MOD(bucket_hash, pool_cnt) THEN CLUSTER_ID END) AS CHOSEN_CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK,
                     
                     CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE,'|',s.CLUSTER_ID))
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
        ) AS pool_cnt,
        CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE)) AS bucket_hash
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
      AND s.SCORE_RANK <= v_k1_pool
) X
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;


INSERT IGNORE INTO tmp_bucket_choice (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CHOSEN_CLUSTER_ID)
SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK,
                     
                     CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE,'|',s.CLUSTER_ID))
        ) AS rn
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
) z
WHERE rn = 1;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_bucket_choice bc
    LEFT JOIN tmp_cluster_snap_map sm
      ON sm.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID
    SET bc.CHOSEN_CLUSTER_ID = COALESCE(sm.SNAPPED_CLUSTER_ID, bc.CHOSEN_CLUSTER_ID);
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
CREATE TEMPORARY TABLE tmp_final_first_cluster (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_final_first_cluster (CLUSTER_ID)
    SELECT fc.CLUSTER_ID
      FROM tmp_final_clusters fc
     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
     LIMIT 1;
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
CREATE TEMPORARY TABLE tmp_bucket_top_final (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_bucket_top_final (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
    FROM (
        SELECT
            s.PARENT_ORDER_ID,
            s.CLIENT_ORDER_TYPE,
            s.CLUSTER_ID,
            ROW_NUMBER() OVER (
                PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
                ORDER BY s.SCORE_RANK,
                         
                         CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE,'|',s.CLUSTER_ID))
            ) AS rn
        FROM tmp_bucket_cluster_score s
        JOIN tmp_final_clusters fcx
          ON fcx.CLUSTER_ID = s.CLUSTER_ID
    ) q
    WHERE rn = 1;
END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
CREATE TEMPORARY TABLE tmp_bucket_fallback (
    PARENT_ORDER_ID       VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE     VARCHAR(100) NOT NULL,
    FALLBACK_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (FALLBACK_CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    INSERT INTO tmp_bucket_fallback (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, FALLBACK_CLUSTER_ID)
    SELECT
        k.PARENT_ORDER_ID,
        k.CLIENT_ORDER_TYPE,
        COALESCE(bc.CHOSEN_CLUSTER_ID, topf.CLUSTER_ID, firstf.CLUSTER_ID) AS FALLBACK_CLUSTER_ID
    FROM tmp_bucket_k k
    LEFT JOIN tmp_bucket_choice bc
      ON bc.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND bc.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    LEFT JOIN tmp_bucket_top_final topf
      ON topf.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND topf.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    CROSS JOIN tmp_final_first_cluster firstf;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
CREATE TEMPORARY TABLE tmp_parent_cluster_load (
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    CLUSTER_ID        VARCHAR(50)  NOT NULL,
    LINE_CNT          BIGINT NOT NULL DEFAULT 0,
    QTY_CNT           BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
) ENGINE=INNODB;



DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
CREATE TEMPORARY TABLE tmp_cluster_supply_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    REM_QTY    BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply_rem
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY, SUPPLY_QTY
  FROM tmp_cluster_supply;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
CREATE TEMPORARY TABLE tmp_sku_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_REM  BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_rem (ARTICLE_ID, BATCH_ID, TOTAL_REM)
SELECT ARTICLE_ID, BATCH_ID, SUM(REM_QTY) AS TOTAL_REM
  FROM tmp_cluster_supply_rem
 GROUP BY ARTICLE_ID, BATCH_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
CREATE TEMPORARY TABLE tmp_line_alloc (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NOT NULL,
    BATCH_ID            VARCHAR(200) NOT NULL,
    SRC_CLUSTER_ID      VARCHAR(50)  NOT NULL,
    ALLOC_QTY           BIGINT       NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, SRC_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (SRC_CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
CREATE TEMPORARY TABLE tmp_sku_queue (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_sku_queue
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_line_assign
 WHERE SHORT_FLAG_SCHEMA = 0
   AND ARTICLE_ID IS NOT NULL
   AND BATCH_ID IS NOT NULL;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
CREATE TEMPORARY TABLE tmp_sku_line_queue (
    RN INT NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    ORDER_LINE_ID VARCHAR(36) NOT NULL,
    QUANTITY INT NOT NULL,
    PRIMARY KEY (RN),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (ORDER_LINE_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
CREATE TEMPORARY TABLE tmp_line_cluster_seq (
    RN INT NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    REM_QTY BIGINT NOT NULL,
    PRIMARY KEY (RN),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

sku_loop: WHILE EXISTS (SELECT 1 FROM tmp_sku_queue LIMIT 1) DO

    SELECT ARTICLE_ID, BATCH_ID
      INTO v_sku, v_batch
      FROM tmp_sku_queue
      LIMIT 1;

    DELETE FROM tmp_sku_queue
     WHERE ARTICLE_ID = v_sku
       AND BATCH_ID   = v_batch;

    TRUNCATE TABLE tmp_sku_line_queue;

    
    INSERT INTO tmp_sku_line_queue (RN, PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY)
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE, la.QUANTITY DESC, la.ORDER_LINE_ID
        ) AS RN,
        la.PARENT_ORDER_ID,
        la.CLIENT_ORDER_TYPE,
        la.ORDER_LINE_ID,
        la.QUANTITY
    FROM tmp_line_assign la
    WHERE la.SHORT_FLAG_SCHEMA = 0
      AND la.ARTICLE_ID = v_sku
      AND la.BATCH_ID   = v_batch;

    SELECT COALESCE(MAX(RN),0) INTO v_maxrn FROM tmp_sku_line_queue;
    SET v_rn = 1;

    line_loop: WHILE v_rn <= v_maxrn DO

        SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY
          INTO v_line_parent, v_line_cat, v_line_id, v_line_qty
          FROM tmp_sku_line_queue
         WHERE RN = v_rn;

        
        IF v_last_bucket_parent IS NULL
           OR v_last_bucket_cat IS NULL
           OR v_last_bucket_parent <> v_line_parent
           OR v_last_bucket_cat <> v_line_cat
        THEN
            SET v_last_bucket_parent = v_line_parent;
            SET v_last_bucket_cat    = v_line_cat;

            
            SET v_bucketK = 1;
            SELECT COALESCE(K, 1)
              INTO v_bucketK
              FROM tmp_bucket_k
             WHERE PARENT_ORDER_ID = v_line_parent
               AND CLIENT_ORDER_TYPE = v_line_cat
             LIMIT 1;

            
            SET v_bucket_primary_cluster = NULL;

            SELECT bc.CHOSEN_CLUSTER_ID
              INTO v_bucket_primary_cluster
              FROM tmp_bucket_choice bc
             WHERE bc.PARENT_ORDER_ID = v_line_parent
               AND bc.CLIENT_ORDER_TYPE = v_line_cat
             LIMIT 1;

            IF v_bucket_primary_cluster IS NULL THEN
                SELECT bcs.CLUSTER_ID
                  INTO v_bucket_primary_cluster
                  FROM tmp_bucket_cluster_score bcs
                 WHERE bcs.PARENT_ORDER_ID = v_line_parent
                   AND bcs.CLIENT_ORDER_TYPE = v_line_cat
                 ORDER BY
                    bcs.SCORE_RANK,
                    
                    CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',bcs.CLUSTER_ID))
                 LIMIT 1;
            END IF;

            IF v_bucket_primary_cluster IS NULL THEN
                SELECT ac.CLUSTER_ID
                  INTO v_bucket_primary_cluster
                  FROM tmp_allowed_clusters ac
                 WHERE ac.PARENT_ORDER_ID = v_line_parent
                   AND ac.CLIENT_ORDER_TYPE = v_line_cat
                 ORDER BY
                    
                    CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',ac.CLUSTER_ID))
                 LIMIT 1;
            END IF;

            
            IF v_use_station_bias = 1 AND v_bucket_primary_cluster IS NOT NULL THEN
                SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_bucket_primary_cluster)
                  INTO v_bucket_primary_cluster
                  FROM tmp_cluster_snap_map sm
                 WHERE sm.SRC_CLUSTER_ID = v_bucket_primary_cluster
                 LIMIT 1;

                
                IF v_bucket_primary_cluster IS NULL THEN
                    SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                      INTO v_bucket_primary_cluster
                      FROM tmp_bucket_fallback
                     WHERE PARENT_ORDER_ID = v_line_parent
                       AND CLIENT_ORDER_TYPE = v_line_cat
                     LIMIT 1;
                END IF;

                IF v_bucket_primary_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_bucket_primary_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;
            END IF;
        END IF;

        
        DELETE FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        SELECT COALESCE(TOTAL_REM,0)
          INTO v_total_rem
          FROM tmp_sku_rem
         WHERE ARTICLE_ID = v_sku
           AND BATCH_ID   = v_batch;

        
        IF v_total_rem <= 0 THEN

            IF v_use_station_bias = 1 THEN
                
                SET v_pick_cluster = v_bucket_primary_cluster;

                
                IF v_pick_cluster IS NULL THEN
                    SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                      INTO v_pick_cluster
                      FROM tmp_bucket_fallback
                     WHERE PARENT_ORDER_ID = v_line_parent
                       AND CLIENT_ORDER_TYPE = v_line_cat
                     LIMIT 1;
                END IF;

                
                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        TRUNCATE TABLE tmp_line_cluster_seq;

        
        INSERT INTO tmp_line_cluster_seq (RN, CLUSTER_ID, REM_QTY)
        SELECT
            ROW_NUMBER() OVER (
                ORDER BY
                    
                    CASE
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND csr.CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                        ELSE 2
                    END,
                    
                    CASE
                        WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                        WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                        WHEN v_use_station_bias = 1 THEN 2
                        ELSE 3
                    END,
                    
                    CASE WHEN ac.CLUSTER_ID IS NOT NULL THEN 0 ELSE 1 END,
                    
                    CASE
                        WHEN v_balance_mode = 1 AND v_bucketK > 1 AND ac.CLUSTER_ID IS NOT NULL THEN
                            CASE
                                WHEN bcs.SCORE_RANK = (1 + MOD(CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',v_line_id)), v_bucketK))
                                THEN 0 ELSE 1
                            END
                        WHEN v_balance_mode = 1 AND v_bucketK > 1 THEN 2
                        ELSE 0
                    END,
                    
                    COALESCE(bcs.SCORE_RANK, 999999),
                    
                    CASE
                        WHEN v_balance_mode = 1 AND v_bucketK > 1 THEN COALESCE(pcl.LINE_CNT,0)
                        ELSE -COALESCE(pcl.LINE_CNT,0)
                    END ASC,
                    CASE
                        WHEN v_balance_mode = 1 AND v_bucketK > 1 THEN COALESCE(pcl.QTY_CNT,0)
                        ELSE -COALESCE(pcl.QTY_CNT,0)
                    END ASC,
                    
                    csr.REM_QTY DESC,
                    
                    CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',v_line_id,'|',csr.CLUSTER_ID))
            ) AS RN,
            csr.CLUSTER_ID,
            csr.REM_QTY
        FROM tmp_cluster_supply_rem csr
        LEFT JOIN tmp_allowed_clusters ac
          ON ac.PARENT_ORDER_ID   = v_line_parent
         AND ac.CLIENT_ORDER_TYPE = v_line_cat
         AND ac.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = v_line_parent
         AND bcs.CLIENT_ORDER_TYPE = v_line_cat
         AND bcs.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_choice bc
          ON bc.PARENT_ORDER_ID   = v_line_parent
         AND bc.CLIENT_ORDER_TYPE = v_line_cat
        LEFT JOIN tmp_parent_cluster_load pcl
          ON pcl.PARENT_ORDER_ID   = v_line_parent
         AND pcl.CLIENT_ORDER_TYPE = v_line_cat
         AND pcl.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_pref_clusters pfc
          ON pfc.CLUSTER_ID = csr.CLUSTER_ID
        LEFT JOIN tmp_near_clusters nfc
          ON nfc.CLUSTER_ID = csr.CLUSTER_ID
        WHERE csr.ARTICLE_ID = v_sku
          AND csr.BATCH_ID   = v_batch
          AND csr.REM_QTY   > 0;

        SELECT COALESCE(MAX(RN),0) INTO v_cmax FROM tmp_line_cluster_seq;

        
        SET v_need = v_line_qty;
        SET v_crn  = 1;

        cluster_loop: WHILE v_need > 0 AND v_crn <= v_cmax DO

            SELECT CLUSTER_ID, REM_QTY
              INTO v_cur_cluster, v_cur_rem
              FROM tmp_line_cluster_seq
             WHERE RN = v_crn;

            SET v_alloc = LEAST(v_cur_rem, v_need);

            IF v_alloc > 0 THEN

                INSERT INTO tmp_line_alloc (
                    PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID,
                    ARTICLE_ID, BATCH_ID, SRC_CLUSTER_ID, ALLOC_QTY
                )
                VALUES (
                    v_line_parent, v_line_cat, v_line_id,
                    v_sku, v_batch, v_cur_cluster, v_alloc
                )
                ON DUPLICATE KEY UPDATE
                    ALLOC_QTY = ALLOC_QTY + VALUES(ALLOC_QTY);

                UPDATE tmp_cluster_supply_rem
                   SET REM_QTY = REM_QTY - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch
                   AND CLUSTER_ID = v_cur_cluster;

                
                UPDATE tmp_sku_rem
                   SET TOTAL_REM = TOTAL_REM - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch;

                SET v_need = v_need - v_alloc;

            END IF;

            SET v_crn = v_crn + 1;
        END WHILE;

        
        SELECT COALESCE(SUM(ALLOC_QTY),0)
          INTO v_alloc
          FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        IF v_alloc <= 0 THEN

            IF v_use_station_bias = 1 THEN
                
                SET v_pick_cluster = v_bucket_primary_cluster;

                IF v_pick_cluster IS NULL THEN
                    SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                      INTO v_pick_cluster
                      FROM tmp_bucket_fallback
                     WHERE PARENT_ORDER_ID = v_line_parent
                       AND CLIENT_ORDER_TYPE = v_line_cat
                     LIMIT 1;
                END IF;

                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        
        SET v_pick_cluster = NULL;

        
        SELECT la.SRC_CLUSTER_ID
          INTO v_pick_cluster
          FROM tmp_line_alloc la
          JOIN tmp_allowed_clusters ac
            ON ac.PARENT_ORDER_ID   = v_line_parent
           AND ac.CLIENT_ORDER_TYPE = v_line_cat
           AND ac.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_cluster_score bcs
            ON bcs.PARENT_ORDER_ID   = v_line_parent
           AND bcs.CLIENT_ORDER_TYPE = v_line_cat
           AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_choice bc
            ON bc.PARENT_ORDER_ID   = v_line_parent
           AND bc.CLIENT_ORDER_TYPE = v_line_cat
          LEFT JOIN tmp_pref_clusters pfc
            ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_near_clusters nfc
            ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
         WHERE la.PARENT_ORDER_ID   = v_line_parent
           AND la.CLIENT_ORDER_TYPE = v_line_cat
           AND la.ORDER_LINE_ID     = v_line_id
         ORDER BY
            la.ALLOC_QTY DESC,
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                ELSE 2
            END,
            CASE
                WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                WHEN v_use_station_bias = 1 THEN 2
                ELSE 3
            END,
            COALESCE(bcs.SCORE_RANK, 999999),
            
            CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',v_line_id,'|',la.SRC_CLUSTER_ID))
         LIMIT 1;

        
        IF v_pick_cluster IS NULL THEN
            SELECT la.SRC_CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_line_alloc la
              LEFT JOIN tmp_bucket_cluster_score bcs
                ON bcs.PARENT_ORDER_ID   = v_line_parent
               AND bcs.CLIENT_ORDER_TYPE = v_line_cat
               AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_bucket_choice bc
                ON bc.PARENT_ORDER_ID   = v_line_parent
               AND bc.CLIENT_ORDER_TYPE = v_line_cat
              LEFT JOIN tmp_pref_clusters pfc
                ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_near_clusters nfc
                ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
             WHERE la.PARENT_ORDER_ID   = v_line_parent
               AND la.CLIENT_ORDER_TYPE = v_line_cat
               AND la.ORDER_LINE_ID     = v_line_id
             ORDER BY
                la.ALLOC_QTY DESC,
                CASE
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                    ELSE 2
                END,
                CASE
                    WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                    WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                    WHEN v_use_station_bias = 1 THEN 2
                    ELSE 3
                END,
                COALESCE(bcs.SCORE_RANK, 999999),
                
                CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',v_line_id,'|',la.SRC_CLUSTER_ID))
             LIMIT 1;
        END IF;

        
        IF v_pick_cluster IS NULL THEN
            SELECT csr.CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_cluster_supply_rem csr
             WHERE csr.ARTICLE_ID = v_sku
               AND csr.BATCH_ID = v_batch
             ORDER BY
                csr.REM_QTY DESC,
                
                CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',v_line_id,'|',csr.CLUSTER_ID))
             LIMIT 1;
        END IF;

        
        IF v_use_station_bias = 1
           AND v_pick_cluster IS NOT NULL
        THEN
            SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_pick_cluster)
              INTO v_pick_cluster
              FROM tmp_cluster_snap_map sm
             WHERE sm.SRC_CLUSTER_ID = v_pick_cluster
             LIMIT 1;

            
            IF v_pick_cluster IS NULL THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT fc.CLUSTER_ID
                  INTO v_pick_cluster
                  FROM tmp_final_clusters fc
                 ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                 LIMIT 1;
            END IF;
        END IF;

        
        IF v_pick_cluster IS NOT NULL
           AND v_pick_cluster <> 'NO_INVENTORY'
        THEN
            
            IF v_bucketK = 1 AND v_bucket_primary_cluster IS NOT NULL THEN
                SET v_pick_cluster = v_bucket_primary_cluster;

            ELSE
                
                IF NOT EXISTS (
                    SELECT 1
                      FROM tmp_allowed_clusters acx
                     WHERE acx.PARENT_ORDER_ID = v_line_parent
                       AND acx.CLIENT_ORDER_TYPE = v_line_cat
                       AND acx.CLUSTER_ID = v_pick_cluster
                     LIMIT 1
                )
                THEN
                    
                    SELECT ac.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_allowed_clusters ac
                      LEFT JOIN tmp_bucket_choice bc
                        ON bc.PARENT_ORDER_ID = ac.PARENT_ORDER_ID
                       AND bc.CLIENT_ORDER_TYPE = ac.CLIENT_ORDER_TYPE
                      LEFT JOIN tmp_bucket_cluster_score bcs
                        ON bcs.PARENT_ORDER_ID = ac.PARENT_ORDER_ID
                       AND bcs.CLIENT_ORDER_TYPE = ac.CLIENT_ORDER_TYPE
                       AND bcs.CLUSTER_ID = ac.CLUSTER_ID
                      LEFT JOIN tmp_parent_cluster_load pcl
                        ON pcl.PARENT_ORDER_ID = ac.PARENT_ORDER_ID
                       AND pcl.CLIENT_ORDER_TYPE = ac.CLIENT_ORDER_TYPE
                       AND pcl.CLUSTER_ID = ac.CLUSTER_ID
                      LEFT JOIN tmp_pref_clusters pfc
                        ON pfc.CLUSTER_ID = ac.CLUSTER_ID
                      LEFT JOIN tmp_near_clusters nfc
                        ON nfc.CLUSTER_ID = ac.CLUSTER_ID
                     WHERE ac.PARENT_ORDER_ID = v_line_parent
                       AND ac.CLIENT_ORDER_TYPE = v_line_cat
                     ORDER BY
                        CASE
                            WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND ac.CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                            WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                            ELSE 2
                        END,
                        CASE
                            WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                            WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                            WHEN v_use_station_bias = 1 THEN 2
                            ELSE 3
                        END,
                        COALESCE(bcs.SCORE_RANK, 999999),
                        COALESCE(pcl.LINE_CNT,0) DESC,
                        COALESCE(pcl.QTY_CNT,0)  DESC,
                        
                        CRC32(CONCAT(v_line_parent,'|',v_line_cat,'|',ac.CLUSTER_ID))
                     LIMIT 1;

                    
                    IF v_pick_cluster IS NULL THEN
                        SET v_pick_cluster = v_bucket_primary_cluster;
                    END IF;
                END IF;
            END IF;
        END IF;

        
        IF v_use_station_bias = 1
           AND v_pick_cluster IS NOT NULL
           AND v_pick_cluster <> 'NO_INVENTORY'
        THEN
            SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_pick_cluster)
              INTO v_pick_cluster
              FROM tmp_cluster_snap_map sm
             WHERE sm.SRC_CLUSTER_ID = v_pick_cluster
             LIMIT 1;

            IF v_pick_cluster IS NULL THEN
                SET v_pick_cluster = v_bucket_primary_cluster;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT fc.CLUSTER_ID
                  INTO v_pick_cluster
                  FROM tmp_final_clusters fc
                 ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                 LIMIT 1;
            END IF;
        END IF;

        
        UPDATE tmp_line_assign
           SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
               ASSIGNED_RANK = 1,
               SHORT_FLAG_SUPPLY = CASE WHEN v_alloc < v_line_qty THEN 1 ELSE 0 END
         WHERE PARENT_ORDER_ID = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID = v_line_id;

        
        INSERT INTO tmp_parent_cluster_load (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, LINE_CNT, QTY_CNT)
        VALUES (v_line_parent, v_line_cat, v_pick_cluster, 1, v_line_qty)
        ON DUPLICATE KEY UPDATE
            LINE_CNT = LINE_CNT + 1,
            QTY_CNT  = QTY_CNT  + VALUES(QTY_CNT);

        SET v_rn = v_rn + 1;
    END WHILE;

END WHILE;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_line_assign la
    LEFT JOIN tmp_bucket_fallback bf
      ON bf.PARENT_ORDER_ID = la.PARENT_ORDER_ID
     AND bf.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
    SET la.ASSIGNED_CLUSTER_ID = COALESCE(
            bf.FALLBACK_CLUSTER_ID,
            (SELECT fc.CLUSTER_ID
               FROM tmp_final_clusters fc
              ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
              LIMIT 1)
        ),
        la.ASSIGNED_RANK = 0
    WHERE la.SHORT_FLAG_SCHEMA = 1
      AND la.ASSIGNED_CLUSTER_ID IS NULL;
END IF;

UPDATE tmp_line_assign
   SET SHORT_FLAG = GREATEST(SHORT_FLAG_SCHEMA, SHORT_FLAG_SUPPLY);


        

DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc_sum;
CREATE TEMPORARY TABLE tmp_line_alloc_sum (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ALLOC_SUM           BIGINT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID)
) ENGINE=INNODB;

INSERT INTO tmp_line_alloc_sum
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    ORDER_LINE_ID,
    SUM(ALLOC_QTY) AS ALLOC_SUM
FROM tmp_line_alloc
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID;


DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
CREATE TEMPORARY TABLE tmp_ranked_lines (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NULL,
    BATCH_ID            VARCHAR(200) NULL,
    QUANTITY            INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

    LINE_CLUSTER_ID     VARCHAR(50)  NOT NULL, 
    SHORT_FLAG          INT NOT NULL,          
    NO_INV_FLAG         INT NOT NULL,          

    RN                  BIGINT NOT NULL,
    SPLIT_GROUP         INT NOT NULL,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
    UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP, RN)
) ENGINE=INNODB;

INSERT INTO tmp_ranked_lines
SELECT
    la.PARENT_ORDER_ID,
    la.CLIENT_ORDER_TYPE,
    la.ORDER_LINE_ID,
    la.ARTICLE_ID,
    la.BATCH_ID,
    la.QUANTITY,
    la.DISPLAY_OPERATOR_INSTRUCTION,

    COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY') AS LINE_CLUSTER_ID,

    
    CASE
        WHEN la.SHORT_FLAG_SCHEMA = 1 THEN 0
        WHEN COALESCE(s.ALLOC_SUM,0) = 0 THEN 0
        WHEN COALESCE(s.ALLOC_SUM,0) < la.QUANTITY THEN 1
        ELSE 0
    END AS SHORT_FLAG,

    
    CASE
        WHEN la.SHORT_FLAG_SCHEMA = 1 THEN 1
        WHEN COALESCE(s.ALLOC_SUM,0) = 0 THEN 1
        ELSE 0
    END AS NO_INV_FLAG,

    ROW_NUMBER() OVER (
        PARTITION BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE
        ORDER BY
            
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL
                 AND COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = bc.CHOSEN_CLUSTER_ID
                THEN 0 ELSE 1
            END,
            la.QUANTITY DESC,
            COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY'),
            la.ORDER_LINE_ID
    ) AS RN,

    
    1 + ((ROW_NUMBER() OVER (
            PARTITION BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE
            ORDER BY
                CASE
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL
                     AND COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = bc.CHOSEN_CLUSTER_ID
                    THEN 0 ELSE 1
                END,
                la.QUANTITY DESC,
                COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY'),
                la.ORDER_LINE_ID
        ) - 1) * k.K) DIV k.TOTAL_LINES AS SPLIT_GROUP

FROM tmp_line_assign la
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = la.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
LEFT JOIN tmp_bucket_choice bc
  ON bc.PARENT_ORDER_ID   = la.PARENT_ORDER_ID
 AND bc.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
LEFT JOIN tmp_line_alloc_sum s
  ON s.PARENT_ORDER_ID     = la.PARENT_ORDER_ID
 AND s.CLIENT_ORDER_TYPE   = la.CLIENT_ORDER_TYPE
 AND s.ORDER_LINE_ID       = la.ORDER_LINE_ID;

SELECT COUNT(*) INTO v_cnt_ranked FROM tmp_ranked_lines;
IF v_cnt_ranked <> v_cnt_line_assign THEN
    SET v_errmsg = CONCAT('LINE_LOSS_AFTER_RANKING: tmp_line_assign=', v_cnt_line_assign,
                          ', tmp_ranked_lines=', v_cnt_ranked);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster_weight;
CREATE TEMPORARY TABLE tmp_group_cluster_weight (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    CLUSTER_ID          VARCHAR(50) NOT NULL,
    WQTY                BIGINT NOT NULL,
    RN                  INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP, RN),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_group_cluster_weight
SELECT
    rl.PARENT_ORDER_ID,
    rl.CLIENT_ORDER_TYPE,
    rl.SPLIT_GROUP,
    rl.LINE_CLUSTER_ID AS CLUSTER_ID,
    SUM(rl.QUANTITY) AS WQTY,
    ROW_NUMBER() OVER (
        PARTITION BY rl.PARENT_ORDER_ID, rl.CLIENT_ORDER_TYPE, rl.SPLIT_GROUP
        ORDER BY
            SUM(rl.QUANTITY) DESC,
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND rl.LINE_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID
                THEN 0 ELSE 1
            END,
            rl.LINE_CLUSTER_ID
    ) AS RN
FROM tmp_ranked_lines rl
LEFT JOIN tmp_bucket_choice bc
  ON bc.PARENT_ORDER_ID   = rl.PARENT_ORDER_ID
 AND bc.CLIENT_ORDER_TYPE = rl.CLIENT_ORDER_TYPE
WHERE rl.LINE_CLUSTER_ID IS NOT NULL
  AND rl.LINE_CLUSTER_ID <> 'NO_INVENTORY'
GROUP BY rl.PARENT_ORDER_ID, rl.CLIENT_ORDER_TYPE, rl.SPLIT_GROUP, rl.LINE_CLUSTER_ID, bc.CHOSEN_CLUSTER_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster;
CREATE TEMPORARY TABLE tmp_group_cluster (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    GROUP_CLUSTER_ID    VARCHAR(50) NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP),
    KEY (GROUP_CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_group_cluster
SELECT
    g.PARENT_ORDER_ID,
    g.CLIENT_ORDER_TYPE,
    g.SPLIT_GROUP,
    COALESCE(
        w.CLUSTER_ID,
        bc.CHOSEN_CLUSTER_ID,
        bf.FALLBACK_CLUSTER_ID,
        'NO_INVENTORY'
    ) AS GROUP_CLUSTER_ID
FROM (
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP
      FROM tmp_ranked_lines
     GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP
) g
LEFT JOIN tmp_group_cluster_weight w
  ON w.PARENT_ORDER_ID   = g.PARENT_ORDER_ID
 AND w.CLIENT_ORDER_TYPE = g.CLIENT_ORDER_TYPE
 AND w.SPLIT_GROUP       = g.SPLIT_GROUP
 AND w.RN = 1
LEFT JOIN tmp_bucket_choice bc
  ON bc.PARENT_ORDER_ID   = g.PARENT_ORDER_ID
 AND bc.CLIENT_ORDER_TYPE = g.CLIENT_ORDER_TYPE
LEFT JOIN tmp_bucket_fallback bf
  ON bf.PARENT_ORDER_ID   = g.PARENT_ORDER_ID
 AND bf.CLIENT_ORDER_TYPE = g.CLIENT_ORDER_TYPE;


DROP TEMPORARY TABLE IF EXISTS tmp_group_flags;
CREATE TEMPORARY TABLE tmp_group_flags (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    HAS_NO_INV          INT NOT NULL,
    HAS_SHORT           INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP)
) ENGINE=INNODB;

INSERT INTO tmp_group_flags
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    SPLIT_GROUP,
    MAX(NO_INV_FLAG) AS HAS_NO_INV,
    MAX(SHORT_FLAG)  AS HAS_SHORT
FROM tmp_ranked_lines
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP;


DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
CREATE TEMPORARY TABLE tmp_final_map (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NULL,
    BATCH_ID            VARCHAR(200) NULL,
    QUANTITY            INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

    SPLIT_GROUP         INT NOT NULL,

    IS_SUSPENDED_GROUP  INT NOT NULL,
    IS_SHORT_LINE       INT NOT NULL,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, ORDER_LINE_ID),
    UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP)
) ENGINE=INNODB;

INSERT INTO tmp_final_map
SELECT
    rl.PARENT_ORDER_ID,
    rl.CLIENT_ORDER_TYPE,
    gc.GROUP_CLUSTER_ID AS CLUSTER_ID,
    rl.ORDER_LINE_ID,
    rl.ARTICLE_ID,
    rl.BATCH_ID,
    rl.QUANTITY,
    rl.DISPLAY_OPERATOR_INSTRUCTION,
    rl.SPLIT_GROUP,
    gf.HAS_NO_INV AS IS_SUSPENDED_GROUP,
    rl.SHORT_FLAG AS IS_SHORT_LINE
FROM tmp_ranked_lines rl
JOIN tmp_group_cluster gc
  ON gc.PARENT_ORDER_ID   = rl.PARENT_ORDER_ID
 AND gc.CLIENT_ORDER_TYPE = rl.CLIENT_ORDER_TYPE
 AND gc.SPLIT_GROUP       = rl.SPLIT_GROUP
JOIN tmp_group_flags gf
  ON gf.PARENT_ORDER_ID   = rl.PARENT_ORDER_ID
 AND gf.CLIENT_ORDER_TYPE = rl.CLIENT_ORDER_TYPE
 AND gf.SPLIT_GROUP       = rl.SPLIT_GROUP;

SELECT COUNT(*) INTO v_cnt_final FROM tmp_final_map;
IF v_cnt_final <> v_cnt_ranked THEN
    SET v_errmsg = CONCAT('LINE_LOSS_AFTER_FINAL_MAP: tmp_ranked_lines=', v_cnt_ranked,
                          ', tmp_final_map=', v_cnt_final);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
END IF;



    

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_pre_lines, v_pre_qty
    FROM tmp_lines;

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_post_lines, v_post_qty
    FROM tmp_final_map;

    IF v_pre_lines <> v_post_lines OR v_pre_qty <> v_post_qty THEN
        SET v_errmsg = CONCAT(
            'CONSERVATION_FAILED: PRE_LINES=', v_pre_lines,
            ', POST_LINES=', v_post_lines,
            ', PRE_QTY=', v_pre_qty,
            ', POST_QTY=', v_post_qty
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_lines tl
    LEFT JOIN tmp_final_map fm
      ON fm.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND fm.ORDER_LINE_ID   = tl.ORDER_LINE_ID
    WHERE fm.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('MISSING_LINES_IN_OUTPUT=', v_missing_lines);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

       

DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
CREATE TEMPORARY TABLE tmp_cat_seq (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CAT_SEQ             INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT INTO tmp_cat_seq
SELECT
    x.PARENT_ORDER_ID,
    x.CLIENT_ORDER_TYPE,
    ROW_NUMBER() OVER (PARTITION BY x.PARENT_ORDER_ID ORDER BY x.CLIENT_ORDER_TYPE) AS CAT_SEQ
FROM (SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE FROM tmp_lines_cat) X;

DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
CREATE TEMPORARY TABLE tmp_child_orders (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    SPLIT_GROUP         INT NOT NULL,
    CHILD_ORDER_ID      VARCHAR(180) NOT NULL,
    CHILD_STATUS        ENUM('PENDING') NOT NULL,

    HAS_SHORT_LINES     INT NOT NULL DEFAULT 0,
    HAS_NO_INV_LINES    INT NOT NULL DEFAULT 0,

    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP),
    KEY (CHILD_ORDER_ID),
    KEY (CHILD_STATUS)
) ENGINE=INNODB;

INSERT INTO tmp_child_orders
SELECT
    fm.PARENT_ORDER_ID,
    fm.CLIENT_ORDER_TYPE,
    fm.CLUSTER_ID,
    fm.SPLIT_GROUP,

    CASE
        WHEN k.K = 1 THEN
            CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID)
        ELSE
            CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID, '-', LPAD(fm.SPLIT_GROUP, 3, '0'))
    END AS CHILD_ORDER_ID,

    'PENDING' AS CHILD_STATUS,

    CASE WHEN MAX(fm.IS_SHORT_LINE) = 1 THEN 1 ELSE 0 END AS HAS_SHORT_LINES,
    CASE WHEN MAX(fm.IS_SUSPENDED_GROUP) = 1 THEN 1 ELSE 0 END AS HAS_NO_INV_LINES

FROM tmp_final_map fm
JOIN tmp_cat_seq cs
  ON cs.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND cs.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
GROUP BY
    fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.SPLIT_GROUP, k.K, cs.CAT_SEQ;

SELECT COUNT(*) INTO v_child_cnt FROM tmp_child_orders;



	

SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_all,
        v_total_qty_all
    FROM tmp_line_assign;
    
    SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_pickable,
        v_total_qty_pickable
    FROM tmp_line_assign
    WHERE SHORT_FLAG_SCHEMA = 0
      AND COALESCE(ASSIGNED_CLUSTER_ID,'NO_INVENTORY') <> 'NO_INVENTORY';

    SELECT
        COALESCE(SUM(a.ALLOC_QTY),0),
        COALESCE(COUNT(DISTINCT CONCAT(a.PARENT_ORDER_ID,'|',a.CLIENT_ORDER_TYPE,'|',a.ORDER_LINE_ID)),0)
    INTO
        v_alloc_qty_total,
        v_alloc_lines_total
    FROM tmp_line_alloc a;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
CREATE TEMPORARY TABLE tmp_reco1 (
    STATION_ID VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NULL,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
CREATE TEMPORARY TABLE tmp_reco2 (
    STATION_ID   VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NULL,
    IS_SELECTED  INT NOT NULL DEFAULT 0,
    IS_NO_WAVE   INT NOT NULL DEFAULT 0,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID),
    KEY (IS_NO_WAVE, IS_SELECTED)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2_avail_clusters;
CREATE TEMPORARY TABLE tmp_reco2_avail_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_has_hw_station = 0 THEN

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT STATION_ID, NULL
      FROM tmp_user_stations;

    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT STATION_ID, NULL, 1, 0
      FROM tmp_user_stations;

ELSE

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM hw_station_master hs
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50)),
           1 AS IS_SELECTED,
           0 AS IS_NO_WAVE
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    IF v_has_hw_wave_status = 1 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
               CAST(hs.CLUSTER_ID AS CHAR(50)),
               0 AS IS_SELECTED,
               1 AS IS_NO_WAVE
          FROM hw_station_master hs
         WHERE hs.STATION_ID IS NOT NULL
           AND hs.CLUSTER_ID IS NOT NULL
           AND LOWER(REPLACE(COALESCE(hs.wave_status,''),' ','_')) IN ('no_wave','nowave','no-wave');
    END IF;

    
    IF v_user_station_cnt = 0 AND v_has_hw_wave_status = 0 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT STATION_ID, CLUSTER_ID, 0, 0 FROM tmp_reco1;
    END IF;

END IF;


INSERT IGNORE INTO tmp_reco2_avail_clusters (CLUSTER_ID)
SELECT DISTINCT COALESCE(CLUSTER_ID,'?')
  FROM tmp_reco2
 WHERE CLUSTER_ID IS NOT NULL;



DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
CREATE TEMPORARY TABLE tmp_job_cluster_stats (
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    ORDER_LINES  BIGINT NOT NULL,
    ORDER_QTY    BIGINT NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_job_cluster_stats (CLUSTER_ID, ORDER_LINES, ORDER_QTY)
SELECT
    co.CLUSTER_ID,
    COUNT(DISTINCT co.CHILD_ORDER_ID) AS ORDER_LINES,
    COALESCE(SUM(fm.QUANTITY),0)      AS ORDER_QTY
FROM tmp_child_orders co
LEFT JOIN tmp_final_map fm
  ON fm.PARENT_ORDER_ID   = co.PARENT_ORDER_ID
 AND fm.CLIENT_ORDER_TYPE = co.CLIENT_ORDER_TYPE
 AND fm.CLUSTER_ID        = co.CLUSTER_ID
 AND fm.SPLIT_GROUP       = co.SPLIT_GROUP

WHERE co.CLUSTER_ID <> 'NO_INVENTORY'
GROUP BY co.CLUSTER_ID;



DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco1_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco1_total_lines,
    @reco1_total_qty
FROM tmp_job_cluster_stats js;


INSERT INTO tmp_reco1_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID ORDER BY r.STATION_ID SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco1_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco1_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco1_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco1_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco1 r
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco2_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco2_total_lines,
    @reco2_total_qty
FROM tmp_job_cluster_stats js
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = js.CLUSTER_ID;


INSERT INTO tmp_reco2_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID
                          ORDER BY r.IS_NO_WAVE DESC, r.IS_SELECTED DESC, r.STATION_ID
                          SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco2_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco2_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco2_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco2_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco2 r
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = r.CLUSTER_ID
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



SET @reco1_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco1_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);

SET @reco2_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco2_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);



IF v_has_reco1 = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2 = 1 THEN
    UPDATE picklist_split_order_master
      SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco1_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco_col = 1 THEN
   UPDATE picklist_split_order_master
SET RECOMMENDATION = JSON_OBJECT(
    'RECOMMENDATION_1_ALL_STATIONS', CAST(@reco1_cluster_json AS JSON),
    'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

    'STATION_PREF_MODE', v_station_mode,
    'USER_SELECTED_STATIONS', (
        SELECT COALESCE(GROUP_CONCAT(STATION_ID ORDER BY STATION_ID SEPARATOR ','), '')
        FROM tmp_user_stations
    ),
    'RULE_ID', v_rule_id,
    'RULE_LOG_ID', v_ruleLog_id,
    'TOTAL_INITIAL_ORDERS', v_parent_cnt,
    'TOTAL_SPLIT_ORDERS', v_child_cnt,

    'INITIAL_ORDER_LINES', v_line_cnt,
    'AFTER_ALLOCATION_ORDER_LINES', v_cnt_final,

    'TOTAL_LINES_PICKABLE', v_total_lines_pickable,

    
    'TOTAL_QTY_ALL', v_pre_qty,
    'TOTAL_QTY_PICKABLE', v_total_qty_pickable,

    
    'ALLOC_QTY_TOTAL', v_post_qty,
    'ALLOC_LINES_TOTAL', v_alloc_lines_total,

    'NOTES', JSON_OBJECT(
        'PARENT_FIELD', 'PARENT_ORDER_ID',
        'CHILD_FIELD', 'ORDER_ID',
        'SUB_ORDER_ID', 'NOT_USED',
        'RESERVATION_KEY', v_reservation_key,
        'RESERVATION_TTL_MINUTES', v_res_ttl_minutes
    )
)
WHERE ID = v_ruleLog_id;

END IF;

    

IF v_is_dry_run = 0 THEN

    
    SET @or_cols = 'PARENT_ORDER_ID, ORDER_TYPE, ORDER_ID, ORDER_REQUEST_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @or_sel  = 'co.PARENT_ORDER_ID, co.CLIENT_ORDER_TYPE, co.CHILD_ORDER_ID, co.CHILD_STATUS, CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_or_cluster = 1 THEN
        SET @or_cols = CONCAT(@or_cols, ', CLUSTER_ID');
        SET @or_sel  = CONCAT(@or_sel,  ', co.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_request_data (', @or_cols, ') ',
        'SELECT ', @or_sel, ' ',
        '  FROM tmp_child_orders co ',
        '  LEFT JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        ' WHERE r.ORDER_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SET @line_cols = 'WMS_ORDER_REQUEST_DATA_ID, ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, BATCH_ID, DISPLAY_OPERATOR_INSTRUCTION, ORDER_LINE_PROCESS_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @line_sel  = 'r.WMS_ORDER_REQUEST_DATA_ID, r.ORDER_ID, fm.ORDER_LINE_ID, fm.ARTICLE_ID, fm.QUANTITY, fm.BATCH_ID, fm.DISPLAY_OPERATOR_INSTRUCTION, ''PENDING'', CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_ol_cluster = 1 THEN
        SET @line_cols = CONCAT(@line_cols, ', CLUSTER_ID');
        SET @line_sel  = CONCAT(@line_sel,  ', fm.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_line_request_data (', @line_cols, ') ',
        'SELECT ', @line_sel, ' ',
        '  FROM tmp_final_map fm ',
        '  JOIN tmp_child_orders co ',
        '    ON co.PARENT_ORDER_ID = fm.PARENT_ORDER_ID ',
        '   AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE ',
        '   AND co.CLUSTER_ID = fm.CLUSTER_ID ',
        '   AND co.SPLIT_GROUP = fm.SPLIT_GROUP ',
        '  JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        '  LEFT JOIN wms_to_wcs_order_line_request_data lr ',
        '    ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID ',
        '   AND lr.ORDER_LINE_ID = fm.ORDER_LINE_ID ',
        ' WHERE lr.ORDER_LINE_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_final_map fm
    JOIN tmp_child_orders co
      ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
     AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
     AND co.CLUSTER_ID        = fm.CLUSTER_ID
     AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
    JOIN wms_to_wcs_order_request_data r
      ON r.ORDER_ID = co.CHILD_ORDER_ID
    LEFT JOIN wms_to_wcs_order_line_request_data lr
      ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID
     AND lr.ORDER_LINE_ID            = fm.ORDER_LINE_ID
    WHERE lr.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('DB_WRITE_MISSING_LINES=', v_missing_lines, ' (expected all tmp_final_map lines in DB)');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    
    SELECT COUNT(*) INTO v_cnt_db_child_lines
    FROM wms_to_wcs_order_line_request_data lr
    JOIN wms_to_wcs_order_request_data r
      ON r.WMS_ORDER_REQUEST_DATA_ID = lr.WMS_ORDER_REQUEST_DATA_ID
    JOIN tmp_child_orders co
      ON co.CHILD_ORDER_ID = r.ORDER_ID;

ELSE
    SET v_cnt_db_child_lines = 0;
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
CREATE TEMPORARY TABLE tmp_child_demand (
    ORDER_ID VARCHAR(180) NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    DEMAND_QTY BIGINT NOT NULL,
    PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, DEMAND_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_child_demand
SELECT
    co.CHILD_ORDER_ID AS ORDER_ID,
    fm.PARENT_ORDER_ID,
    fm.CLIENT_ORDER_TYPE,
    fm.CLUSTER_ID AS DEMAND_CLUSTER_ID,
    fm.ARTICLE_ID,
    fm.BATCH_ID,
    SUM(fm.QUANTITY) AS DEMAND_QTY
FROM tmp_final_map fm
JOIN tmp_child_orders co
  ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
 AND co.CLUSTER_ID        = fm.CLUSTER_ID
 AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
WHERE fm.IS_SUSPENDED_GROUP = 0
  AND fm.ARTICLE_ID IS NOT NULL
  AND fm.BATCH_ID IS NOT NULL
  AND fm.CLUSTER_ID <> 'NO_INVENTORY'
  AND co.CHILD_STATUS = 'PENDING'
GROUP BY co.CHILD_ORDER_ID, fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.ARTICLE_ID, fm.BATCH_ID;

IF (SELECT COUNT(*) FROM tmp_child_demand) > 0 THEN

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
    CREATE TEMPORARY TABLE tmp_res_need_clusters (
        ORDER_ID         VARCHAR(180) NOT NULL,
        ARTICLE_ID       VARCHAR(200) NOT NULL,
        BATCH_ID         VARCHAR(200) NOT NULL,
        CLUSTER_ID       VARCHAR(50)  NOT NULL,
        DEMAND_QTY       BIGINT NOT NULL,
        PRIORITY         INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,
        CLUSTER_SUPPLY   BIGINT NOT NULL,
        CUM_SUPPLY_PREV  BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID),
        KEY idx_need (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_need_clusters
        (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID, DEMAND_QTY, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_SUPPLY, CUM_SUPPLY_PREV)
    SELECT
        z.ORDER_ID,
        z.ARTICLE_ID,
        z.BATCH_ID,
        z.CLUSTER_ID,
        z.DEMAND_QTY,
        z.PRIORITY,
        z.SRC_CLUSTER_RANK,
        z.CLUSTER_SUPPLY,
        COALESCE(z.cum_supply_prev, 0) AS CUM_SUPPLY_PREV
    FROM (
        SELECT
            d.ORDER_ID,
            d.PARENT_ORDER_ID,
            d.CLIENT_ORDER_TYPE,
            d.DEMAND_CLUSTER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            d.DEMAND_QTY,

            cs.CLUSTER_ID,
            cs.SUPPLY_QTY AS CLUSTER_SUPPLY,

            CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END AS PRIORITY,
            COALESCE(bcs.SCORE_RANK, 999999) AS SRC_CLUSTER_RANK,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
            ) AS cum_supply,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_supply_prev

        FROM tmp_child_demand d
        JOIN tmp_cluster_supply cs
          ON cs.ARTICLE_ID = d.ARTICLE_ID
         AND cs.BATCH_ID   = d.BATCH_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = d.PARENT_ORDER_ID
         AND bcs.CLIENT_ORDER_TYPE = d.CLIENT_ORDER_TYPE
         AND bcs.CLUSTER_ID        = cs.CLUSTER_ID
    ) z
    WHERE COALESCE(z.cum_supply_prev, 0) < z.DEMAND_QTY;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
    CREATE TEMPORARY TABLE tmp_res_bins (
        ORDER_ID VARCHAR(180) NOT NULL,
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,

        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,

        AVAIL_QTY BIGINT NOT NULL,
        LAST_TS DATETIME(3) NULL,

        PRIORITY INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,

        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY idx_rank (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK),
        KEY (BIN_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_bins
    SELECT
        d.ORDER_ID,
        d.PARENT_ORDER_ID,
        d.CLIENT_ORDER_TYPE,
        d.DEMAND_CLUSTER_ID,

        ib.CLUSTER_ID AS SRC_CLUSTER_ID,
        ib.ARTICLE_ID,
        ib.BATCH_ID,
        ib.BIN_ID,
        ib.AISLE_NUMBER,

        ib.AVAIL_QTY,
        ib.LAST_TS,

        nc.PRIORITY,
        nc.SRC_CLUSTER_RANK
    FROM tmp_child_demand d
    JOIN tmp_res_need_clusters nc
      ON nc.ORDER_ID   = d.ORDER_ID
     AND nc.ARTICLE_ID = d.ARTICLE_ID
     AND nc.BATCH_ID   = d.BATCH_ID
    
    JOIN tmp_inv_bin ib
      ON ib.ARTICLE_ID = d.ARTICLE_ID
     AND ib.BATCH_ID   = d.BATCH_ID
     AND ib.CLUSTER_ID = nc.CLUSTER_ID
    WHERE ib.AVAIL_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
    CREATE TEMPORARY TABLE tmp_res_alloc_child (
        ORDER_ID VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY (BIN_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_alloc_child
    SELECT
        rb.ORDER_ID,
        rb.ARTICLE_ID,
        rb.BATCH_ID,
        rb.BIN_ID,
        rb.AISLE_NUMBER,
        rb.SRC_CLUSTER_ID,
        rb.RESERVED_QTY
    FROM (
        SELECT
            d.ORDER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            b.BIN_ID,
            b.AISLE_NUMBER,
            b.SRC_CLUSTER_ID,
            b.AVAIL_QTY,
            b.LAST_TS,
            d.DEMAND_QTY,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
            ) AS cum_avail,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_avail_prev,

            LEAST(
                b.AVAIL_QTY,
                GREATEST(d.DEMAND_QTY - COALESCE(
                    SUM(b.AVAIL_QTY) OVER (
                        PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                        ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                    ), 0
                ), 0)
            ) AS RESERVED_QTY

        FROM tmp_child_demand d
        JOIN tmp_res_bins b
          ON b.ORDER_ID   = d.ORDER_ID
         AND b.ARTICLE_ID = d.ARTICLE_ID
         AND b.BATCH_ID   = d.BATCH_ID
    ) rb
    WHERE rb.RESERVED_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
    CREATE TEMPORARY TABLE tmp_res_shortfall (
        ORDER_ID   VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        DEMAND_QTY BIGINT NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        SHORT_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_shortfall (ORDER_ID, ARTICLE_ID, BATCH_ID, DEMAND_QTY, RESERVED_QTY, SHORT_QTY)
    SELECT
        d.ORDER_ID,
        d.ARTICLE_ID,
        d.BATCH_ID,
        d.DEMAND_QTY,
        COALESCE(a.got,0) AS RESERVED_QTY,
        GREATEST(d.DEMAND_QTY - COALESCE(a.got,0), 0) AS SHORT_QTY
    FROM tmp_child_demand d
    LEFT JOIN (
        SELECT ORDER_ID, ARTICLE_ID, BATCH_ID, SUM(RESERVED_QTY) AS got
          FROM tmp_res_alloc_child
         GROUP BY ORDER_ID, ARTICLE_ID, BATCH_ID
    ) a
      ON a.ORDER_ID = d.ORDER_ID
     AND a.ARTICLE_ID = d.ARTICLE_ID
     AND a.BATCH_ID = d.BATCH_ID
    WHERE COALESCE(a.got,0) < d.DEMAND_QTY;

END IF;


	
    

    IF v_is_dry_run = 0 THEN

        UPDATE wms_to_wcs_order_level_pre_staged_data p
        JOIN tmp_parent_orders t
          ON t.PRE_STAGED_REQ_ID = p.WMS_ORDER_REQUEST_DATA_ID
        SET p.IS_STAGED = 1,
            p.UPDATED_TIMESTAMP = CURRENT_TIMESTAMP(3),
            p.UPDATED_BY = 'SPLIT-OPS-V6';
    END IF;

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='2',
           ORDERSPLIT_ENDTIME = NOW(),
           RULE_STATS = JSON_OBJECT(
               'RULE_ID', v_rule_id,
               'RULE_LOG_ID', v_ruleLog_id,
               'RUN_PRIORITY', v_run_priority,
               'DRY_RUN', v_is_dry_run,
               'RESERVATION_KEY', v_reservation_key,
               'PARENTS_FOUND', v_parent_cnt,
               'LINES_CONSIDERED', v_line_cnt,
               'CHILD_ORDERS_CREATED', v_child_cnt,
               'MAX_ORDER_LINES_PER_ORDER', v_max_lines,
               'MAX_QUANTITY_PER_ORDER', v_max_qty,
               'TOL_LINES', v_tol_lines,
               'TOL_QTY', v_tol_qty,
               'HARD_LINES', v_hard_lines,
               'HARD_QTY', v_hard_qty,
               'SUSPEND_SHORT_LINES', v_suspend_short_lines,
               'CATEGORY_DEFAULT', 'FOOD',
               'NAMING', 'PARENT_ORDER_ID parent; ORDER_ID child/sub; SUB_ORDER_ID NOT USED',
               'STATION_PREF', JSON_OBJECT(
                   'MODE_USED', v_station_mode,
                   'USER_STATION_CNT', v_user_station_cnt,
                   'STATION_BIAS_ENABLED', v_use_station_bias
               ),
               'VALIDATIONS', JSON_OBJECT(
                   'tmp_lines', v_cnt_lines,
                   'tmp_lines_cat', v_cnt_lines_cat,
                   'tmp_line_assign', v_cnt_line_assign,
                   'tmp_ranked_lines', v_cnt_ranked,
                   'tmp_final_map', v_cnt_final,
                   'db_child_lines', v_cnt_db_child_lines
               ),
               'SUPPLY_CAP', JSON_OBJECT(
                   'ENABLED', 1,
                   'NOTE', 'Allocator decrements per SKU/BATCH/CLUSTER; assigns dominant cluster; NO_INVENTORY lines suspended'
               ),
               'RESERVATION', JSON_OBJECT(
                   'TTL_MINUTES', v_res_ttl_minutes,
                   'BLOCKED_LOCATION_EXCLUDED', 1,
                   'AUDIT_GRANULARITY', 'ORDER_ID+SKU/BATCH+BIN'
               )
           )
     WHERE ID = v_ruleLog_id;

    

    COMMIT;
    DO RELEASE_LOCK(v_lock_key);

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
        DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
        DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
        DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
        DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
        DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
		DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc_sum;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster_weight;
DROP TEMPORARY TABLE IF EXISTS tmp_group_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_group_flags;

    END;


SELECT
    v_rule_id AS RULE_ID,
    v_ruleLog_id AS RULE_LOG_ID,
    v_reservation_key AS RESERVATION_KEY,
    v_parent_cnt AS PARENTS_PROCESSED,
    v_line_cnt AS LINES_CONSIDERED,
    v_child_cnt AS CHILD_ORDERS_CREATED;



END sp_main */$$
DELIMITER ;

/* Procedure structure for procedure `sp_split_orders_ops_v3` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_split_orders_ops_v3` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sp_split_orders_ops_v3`()
sp_main: BEGIN

    

    
    DECLARE v_max_lines INT DEFAULT 50;
    DECLARE v_max_qty   INT DEFAULT 500;

    
    DECLARE v_tol_lines INT DEFAULT 10;
    DECLARE v_tol_qty   INT DEFAULT 100;

    
    DECLARE v_hard_lines INT DEFAULT 60;
    DECLARE v_hard_qty   INT DEFAULT 600;

    
    DECLARE v_suspend_short_lines INT DEFAULT 0;

    
    DECLARE v_rule_id INT DEFAULT NULL;
    DECLARE v_ruleLog_id INT DEFAULT NULL;
    DECLARE v_rule_defination TEXT;

    
    DECLARE v_lock_ok INT DEFAULT 0;

    
    DECLARE v_parent_cnt INT DEFAULT 0;
    DECLARE v_line_cnt   INT DEFAULT 0;
    DECLARE v_child_cnt  INT DEFAULT 0;
    DECLARE v_short_cnt  INT DEFAULT 0;

    
    DECLARE v_batch_quoted TEXT;

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DO RELEASE_LOCK(CONCAT('SPLIT_', IFNULL(@batch_picklist_code,'')));
        RESIGNAL;
    END;

    
    SET v_max_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_ORDER_LINES_PER_ORDER'
            AND IS_ACTIVE = 1
          ORDER BY UPDATED_ON DESC
          LIMIT 1),
        50
    );

    SET v_max_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_QUANTITY_PER_ORDER'
            AND IS_ACTIVE = 1
          ORDER BY UPDATED_ON DESC
          LIMIT 1),
        500
    );

    
    SET v_tol_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_LINES'
            AND IS_ACTIVE = 1
          ORDER BY UPDATED_ON DESC
          LIMIT 1),
        v_tol_lines
    );

    SET v_tol_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_QTY'
            AND IS_ACTIVE = 1
          ORDER BY UPDATED_ON DESC
          LIMIT 1),
        v_tol_qty
    );

    SET v_suspend_short_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'SUSPEND_SHORT_LINES'
            AND IS_ACTIVE = 1
          ORDER BY UPDATED_ON DESC
          LIMIT 1),
        0
    );

    SET v_hard_lines = v_max_lines + v_tol_lines;
    SET v_hard_qty   = v_max_qty   + v_tol_qty;

    
    SELECT ID, RULE_ID
      INTO v_ruleLog_id, v_rule_id
    FROM picklist_split_order_master
    WHERE IS_PROCESSED='0'
    ORDER BY ID
    LIMIT 1;

    IF v_rule_id IS NULL THEN
        SELECT 'NO_RULE_TO_PROCESS' AS STATUS;
        LEAVE sp_main;
    END IF;

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='1',
           ORDERSPLIT_STARTTIME = NOW()
     WHERE ID = v_ruleLog_id;

    SELECT FILTER_CONDITION
      INTO v_rule_defination
    FROM pick_rule_master
    WHERE PICK_RULE_ID = v_rule_id
    ORDER BY PICK_RULE_ID
    LIMIT 1;

    IF v_rule_defination IS NULL OR LENGTH(v_rule_defination) < 3 THEN
        UPDATE picklist_split_order_master
           SET IS_PROCESSED='2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        SELECT 'NO_RULE_DEFINITION_FOUND' AS STATUS, v_rule_id AS RULE_ID;
        LEAVE sp_main;
    END IF;

    
    SET v_rule_defination = LEFT(v_rule_defination, LENGTH(v_rule_defination)-1);

    
    SET @batch_picklist_code := NULL;

    SET @sql = CONCAT(
        'SELECT BATCH_PICKLIST_CODE INTO @batch_picklist_code
           FROM wms_to_wcs_order_level_pre_staged_data
          WHERE PARENT_ORDER_ID IN (', v_rule_defination, ')
          LIMIT 1'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    IF @batch_picklist_code IS NULL OR @batch_picklist_code = '' THEN
        UPDATE picklist_split_order_master
           SET IS_PROCESSED='2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        SELECT 'NO_BATCH_PICKLIST_CODE_FOUND' AS STATUS;
        LEAVE sp_main;
    END IF;

    
    SELECT GET_LOCK(CONCAT('SPLIT_', @batch_picklist_code), 2) INTO v_lock_ok;
    IF v_lock_ok <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Split job already running for this BATCH_PICKLIST_CODE';
    END IF;

    SET v_batch_quoted = QUOTE(@batch_picklist_code);

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
    CREATE TEMPORARY TABLE tmp_parent_orders (
        PRE_STAGED_REQ_ID BIGINT NOT NULL,
        PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
        ORDER_TYPE        VARCHAR(100) NOT NULL,
        PRIMARY KEY (PRE_STAGED_REQ_ID),
        KEY (PARENT_ORDER_ID)
    ) ENGINE=InnoDB;

    
    SET @sql = CONCAT(
        'INSERT INTO tmp_parent_orders (PRE_STAGED_REQ_ID, PARENT_ORDER_ID, ORDER_TYPE)
         SELECT WMS_ORDER_REQUEST_DATA_ID,
                PARENT_ORDER_ID,
                COALESCE(NULLIF(PICKING_TYPE,''''),
                         NULLIF(ORDER_CATEGORY,''''),
                         ''PICK'') AS ORDER_TYPE
           FROM wms_to_wcs_order_level_pre_staged_data
          WHERE BATCH_PICKLIST_CODE = ', v_batch_quoted, '
            AND ORDER_REQUEST_STATUS = ''PENDING''
            AND IFNULL(IS_STAGED,0) = 0
            AND PARENT_ORDER_ID IN (', v_rule_defination, ')'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    SELECT COUNT(*) INTO v_parent_cnt FROM tmp_parent_orders;

    IF v_parent_cnt = 0 THEN
        DO RELEASE_LOCK(CONCAT('SPLIT_', @batch_picklist_code));

        UPDATE picklist_split_order_master
           SET IS_PROCESSED='2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        SELECT
            @batch_picklist_code AS BATCH_PICKLIST_CODE,
            'NO_PARENTS_TO_SPLIT' AS STATUS,
            v_max_lines AS MAX_ORDER_LINES_PER_ORDER,
            v_max_qty   AS MAX_QUANTITY_PER_ORDER,
            v_tol_lines AS TOL_LINES,
            v_tol_qty   AS TOL_QTY;
        LEAVE sp_main;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_lines;
    CREATE TEMPORARY TABLE tmp_lines (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID)
    ) ENGINE=InnoDB;

    INSERT INTO tmp_lines
    SELECT
        l.PARENT_ORDER_ID,
        l.ORDER_LINE_ID,
        l.ARTICLE_ID,
        l.BATCH_ID,
        l.QUANTITY,
        l.DISPLAY_OPERATOR_INSTRUCTION
    FROM wms_to_wcs_order_line_level_pre_staged_data l
    JOIN tmp_parent_orders p
      ON p.PARENT_ORDER_ID = l.PARENT_ORDER_ID
    WHERE IFNULL(l.ORDER_LINE_PROCESS_STATUS,'PENDING') <> 'DELETED';

    SELECT COUNT(*) INTO v_line_cnt FROM tmp_lines;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_parent_stats;
    CREATE TEMPORARY TABLE tmp_parent_stats (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        LINE_CNT INT NOT NULL,
        TOTAL_QTY INT NOT NULL,
        NEED_SPLIT INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID)
    ) ENGINE=InnoDB;

    INSERT INTO tmp_parent_stats (PARENT_ORDER_ID, LINE_CNT, TOTAL_QTY, NEED_SPLIT)
    SELECT
        PARENT_ORDER_ID,
        COUNT(*) AS LINE_CNT,
        SUM(QUANTITY) AS TOTAL_QTY,
        CASE
            WHEN COUNT(*) > v_hard_lines OR SUM(QUANTITY) > v_hard_qty THEN 1
            ELSE 0
        END AS NEED_SPLIT
    FROM tmp_lines
    GROUP BY PARENT_ORDER_ID;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_split_all;
    CREATE TEMPORARY TABLE tmp_split_all (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        SPLIT_GROUP INT NOT NULL,
        IS_SUSPENDED_GROUP INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (PARENT_ORDER_ID, SPLIT_GROUP)
    ) ENGINE=InnoDB;

    
    INSERT INTO tmp_split_all
    SELECT
        tl.PARENT_ORDER_ID,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION,
        1 AS SPLIT_GROUP,
        0 AS IS_SUSPENDED_GROUP
    FROM tmp_lines tl
    JOIN tmp_parent_stats ps
      ON ps.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
    WHERE ps.NEED_SPLIT = 0;

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_need_split;
    CREATE TEMPORARY TABLE tmp_need_split (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID)
    ) ENGINE=InnoDB;

    INSERT INTO tmp_need_split
    SELECT PARENT_ORDER_ID
    FROM tmp_parent_stats
    WHERE NEED_SPLIT = 1;

    
    IF (SELECT COUNT(*) FROM tmp_need_split) > 0 THEN

        
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_list;
        CREATE TEMPORARY TABLE tmp_sku_list (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, ARTICLE_ID, BATCH_ID),
            KEY (ARTICLE_ID, BATCH_ID)
        ) ENGINE=InnoDB;

        INSERT INTO tmp_sku_list
        SELECT DISTINCT tl.PARENT_ORDER_ID, tl.ARTICLE_ID, tl.BATCH_ID
        FROM tmp_lines tl
        JOIN tmp_need_split ns ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
        WHERE tl.ARTICLE_ID IS NOT NULL AND tl.BATCH_ID IS NOT NULL;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
        CREATE TEMPORARY TABLE tmp_sku_global (
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            PRIMARY KEY (ARTICLE_ID, BATCH_ID)
        ) ENGINE=InnoDB;

        INSERT INTO tmp_sku_global
        SELECT DISTINCT ARTICLE_ID, BATCH_ID
        FROM tmp_sku_list;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
        CREATE TEMPORARY TABLE tmp_inv_bin (
            BIN_ID INT NOT NULL,
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            AVAIL_QTY  INT NOT NULL,
            LAST_TS    DATETIME(3) NULL,
            PRIMARY KEY (BIN_ID, ARTICLE_ID, BATCH_ID),
            KEY (ARTICLE_ID, BATCH_ID),
            KEY (BIN_ID)
        ) ENGINE=InnoDB;

        INSERT INTO tmp_inv_bin
        SELECT
            lim.BIN_ID,
            lim.ARTICLE_ID,
            lim.BATCH_ID,
            CAST(SUM(GREATEST(lim.QUANTITY - lim.VIRTUAL_QUANTITY_TO_PICK, 0)) AS SIGNED) AS AVAIL_QTY,
            MAX(lim.UPDATED_TIMESTAMP) AS LAST_TS
        FROM live_inventory_master lim
        JOIN tmp_sku_global sg
          ON sg.ARTICLE_ID = lim.ARTICLE_ID
         AND sg.BATCH_ID   = lim.BATCH_ID
        WHERE lim.IS_ACTIVE = 1
        GROUP BY lim.BIN_ID, lim.ARTICLE_ID, lim.BATCH_ID
        HAVING AVAIL_QTY > 0;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_bin_hits;
        CREATE TEMPORARY TABLE tmp_bin_hits (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            BIN_ID INT NOT NULL,
            HIT_CNT INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, BIN_ID)
        ) ENGINE=InnoDB;

        INSERT INTO tmp_bin_hits
        SELECT
            s.PARENT_ORDER_ID,
            ib.BIN_ID,
            COUNT(*) AS HIT_CNT
        FROM tmp_sku_list s
        JOIN tmp_inv_bin ib
          ON ib.ARTICLE_ID = s.ARTICLE_ID
         AND ib.BATCH_ID   = s.BATCH_ID
        GROUP BY s.PARENT_ORDER_ID, ib.BIN_ID;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_line_metrics;
        CREATE TEMPORARY TABLE tmp_line_metrics (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            ORDER_LINE_ID VARCHAR(36) NOT NULL,
            DOMINANT_BIN_ID INT NULL,
            DOMINANT_HIT_CNT INT NOT NULL,
            TOTAL_AVAIL INT NOT NULL,
            REQ_QTY INT NOT NULL,
            SHORT_FLAG INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID)
        ) ENGINE=InnoDB;

        INSERT INTO tmp_line_metrics
        WITH candidate_bins AS (
            SELECT
                tl.PARENT_ORDER_ID,
                tl.ORDER_LINE_ID,
                tl.QUANTITY AS REQ_QTY,
                ib.BIN_ID,
                COALESCE(bh.HIT_CNT,0) AS HIT_CNT,
                ib.AVAIL_QTY,
                ib.LAST_TS,
                ROW_NUMBER() OVER (
                    PARTITION BY tl.PARENT_ORDER_ID, tl.ORDER_LINE_ID
                    ORDER BY COALESCE(bh.HIT_CNT,0) DESC, ib.AVAIL_QTY DESC, ib.LAST_TS DESC, ib.BIN_ID
                ) AS rn,
                SUM(ib.AVAIL_QTY) OVER (
                    PARTITION BY tl.PARENT_ORDER_ID, tl.ORDER_LINE_ID
                ) AS total_avail
            FROM tmp_lines tl
            JOIN tmp_need_split ns
              ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
            JOIN tmp_inv_bin ib
              ON ib.ARTICLE_ID = tl.ARTICLE_ID AND ib.BATCH_ID = tl.BATCH_ID
            LEFT JOIN tmp_bin_hits bh
              ON bh.PARENT_ORDER_ID = tl.PARENT_ORDER_ID AND bh.BIN_ID = ib.BIN_ID
        )
        SELECT
            cb.PARENT_ORDER_ID,
            cb.ORDER_LINE_ID,
            MAX(CASE WHEN cb.rn = 1 THEN cb.BIN_ID END)  AS DOMINANT_BIN_ID,
            MAX(CASE WHEN cb.rn = 1 THEN cb.HIT_CNT END) AS DOMINANT_HIT_CNT,
            MAX(cb.total_avail) AS TOTAL_AVAIL,
            MAX(cb.REQ_QTY)     AS REQ_QTY,
            CASE WHEN MAX(cb.total_avail) < MAX(cb.REQ_QTY) THEN 1 ELSE 0 END AS SHORT_FLAG
        FROM candidate_bins cb
        GROUP BY cb.PARENT_ORDER_ID, cb.ORDER_LINE_ID;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_lines_enriched;
        CREATE TEMPORARY TABLE tmp_lines_enriched (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
            ARTICLE_ID      VARCHAR(200) NULL,
            BATCH_ID        VARCHAR(200) NULL,
            QUANTITY        INT NOT NULL,
            DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
            DOMINANT_BIN_ID INT NULL,
            DOMINANT_HIT_CNT INT NOT NULL,
            SHORT_FLAG INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
            KEY (PARENT_ORDER_ID),
            KEY (DOMINANT_BIN_ID)
        ) ENGINE=InnoDB;

        INSERT INTO tmp_lines_enriched
        SELECT
            tl.PARENT_ORDER_ID,
            tl.ORDER_LINE_ID,
            tl.ARTICLE_ID,
            tl.BATCH_ID,
            tl.QUANTITY,
            tl.DISPLAY_OPERATOR_INSTRUCTION,
            lm.DOMINANT_BIN_ID,
            COALESCE(lm.DOMINANT_HIT_CNT,0) AS DOMINANT_HIT_CNT,
            COALESCE(lm.SHORT_FLAG,1) AS SHORT_FLAG
        FROM tmp_lines tl
        JOIN tmp_need_split ns ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
        LEFT JOIN tmp_line_metrics lm
          ON lm.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND lm.ORDER_LINE_ID   = tl.ORDER_LINE_ID;

        
        IF v_suspend_short_lines = 0 THEN
            UPDATE tmp_lines_enriched
               SET SHORT_FLAG = 0;
        END IF;

        SELECT COUNT(*) INTO v_short_cnt
        FROM tmp_lines_enriched
        WHERE SHORT_FLAG = 1;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_norm_plan;
        CREATE TEMPORARY TABLE tmp_norm_plan (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            LINE_CNT INT NOT NULL,
            TOTAL_QTY INT NOT NULL,
            GRP_CNT INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID)
        ) ENGINE=InnoDB;

        INSERT INTO tmp_norm_plan
        SELECT
            PARENT_ORDER_ID,
            COUNT(*) AS LINE_CNT,
            SUM(QUANTITY) AS TOTAL_QTY,
            GREATEST(
                1,
                (COUNT(*) + v_hard_lines - 1) DIV v_hard_lines,
                (SUM(QUANTITY) + v_hard_qty - 1) DIV v_hard_qty
            ) AS GRP_CNT
        FROM tmp_lines_enriched
        WHERE SHORT_FLAG = 0
        GROUP BY PARENT_ORDER_ID;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_ranked_normal;
        CREATE TEMPORARY TABLE tmp_ranked_normal (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
            ARTICLE_ID      VARCHAR(200) NULL,
            BATCH_ID        VARCHAR(200) NULL,
            QUANTITY        INT NOT NULL,
            DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
            rn INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
            KEY (PARENT_ORDER_ID, rn)
        ) ENGINE=InnoDB;

        INSERT INTO tmp_ranked_normal
        SELECT
            tle.PARENT_ORDER_ID,
            tle.ORDER_LINE_ID,
            tle.ARTICLE_ID,
            tle.BATCH_ID,
            tle.QUANTITY,
            tle.DISPLAY_OPERATOR_INSTRUCTION,
            ROW_NUMBER() OVER (
                PARTITION BY tle.PARENT_ORDER_ID
                ORDER BY
                    COALESCE(tle.DOMINANT_BIN_ID, 2147483647),
                    tle.DOMINANT_HIT_CNT DESC,
                    tle.QUANTITY DESC,
                    tle.ORDER_LINE_ID
            ) AS rn
        FROM tmp_lines_enriched tle
        WHERE tle.SHORT_FLAG = 0;

        
        INSERT INTO tmp_split_all
        SELECT
            r.PARENT_ORDER_ID,
            r.ORDER_LINE_ID,
            r.ARTICLE_ID,
            r.BATCH_ID,
            r.QUANTITY,
            r.DISPLAY_OPERATOR_INSTRUCTION,
            1 + ((r.rn - 1) * p.GRP_CNT) DIV p.LINE_CNT AS SPLIT_GROUP,
            0 AS IS_SUSPENDED_GROUP
        FROM tmp_ranked_normal r
        JOIN tmp_norm_plan p
          ON p.PARENT_ORDER_ID = r.PARENT_ORDER_ID;

        
        IF v_suspend_short_lines = 1 THEN

            DROP TEMPORARY TABLE IF EXISTS tmp_short_plan;
            CREATE TEMPORARY TABLE tmp_short_plan (
                PARENT_ORDER_ID VARCHAR(100) NOT NULL,
                LINE_CNT INT NOT NULL,
                TOTAL_QTY INT NOT NULL,
                GRP_CNT INT NOT NULL,
                OFFSET_G INT NOT NULL,
                PRIMARY KEY (PARENT_ORDER_ID)
            ) ENGINE=InnoDB;

            INSERT INTO tmp_short_plan
            SELECT
                s.PARENT_ORDER_ID,
                COUNT(*) AS LINE_CNT,
                SUM(s.QUANTITY) AS TOTAL_QTY,
                GREATEST(
                    1,
                    (COUNT(*) + v_hard_lines - 1) DIV v_hard_lines,
                    (SUM(s.QUANTITY) + v_hard_qty - 1) DIV v_hard_qty
                ) AS GRP_CNT,
                COALESCE(n.GRP_CNT, 0) AS OFFSET_G
            FROM tmp_lines_enriched s
            LEFT JOIN tmp_norm_plan n
              ON n.PARENT_ORDER_ID = s.PARENT_ORDER_ID
            WHERE s.SHORT_FLAG = 1
            GROUP BY s.PARENT_ORDER_ID;

            DROP TEMPORARY TABLE IF EXISTS tmp_ranked_short;
            CREATE TEMPORARY TABLE tmp_ranked_short (
                PARENT_ORDER_ID VARCHAR(100) NOT NULL,
                ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
                ARTICLE_ID      VARCHAR(200) NULL,
                BATCH_ID        VARCHAR(200) NULL,
                QUANTITY        INT NOT NULL,
                DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
                rn INT NOT NULL,
                PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
                KEY (PARENT_ORDER_ID, rn)
            ) ENGINE=InnoDB;

            INSERT INTO tmp_ranked_short
            SELECT
                tle.PARENT_ORDER_ID,
                tle.ORDER_LINE_ID,
                tle.ARTICLE_ID,
                tle.BATCH_ID,
                tle.QUANTITY,
                tle.DISPLAY_OPERATOR_INSTRUCTION,
                ROW_NUMBER() OVER (
                    PARTITION BY tle.PARENT_ORDER_ID
                    ORDER BY tle.QUANTITY DESC, tle.ORDER_LINE_ID
                ) AS rn
            FROM tmp_lines_enriched tle
            WHERE tle.SHORT_FLAG = 1;

            INSERT INTO tmp_split_all
            SELECT
                r.PARENT_ORDER_ID,
                r.ORDER_LINE_ID,
                r.ARTICLE_ID,
                r.BATCH_ID,
                r.QUANTITY,
                r.DISPLAY_OPERATOR_INSTRUCTION,
                sp.OFFSET_G + (1 + ((r.rn - 1) * sp.GRP_CNT) DIV sp.LINE_CNT) AS SPLIT_GROUP,
                1 AS IS_SUSPENDED_GROUP
            FROM tmp_ranked_short r
            JOIN tmp_short_plan sp
              ON sp.PARENT_ORDER_ID = r.PARENT_ORDER_ID;

        END IF;

    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
    CREATE TEMPORARY TABLE tmp_child_orders (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        SPLIT_GROUP INT NOT NULL,
        ORDER_TYPE VARCHAR(100) NOT NULL,
        CHILD_ORDER_ID VARCHAR(100) NOT NULL,
        CHILD_STATUS ENUM('PENDING','ORDER_SUSPENDED') NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, SPLIT_GROUP),
        KEY (CHILD_ORDER_ID)
    ) ENGINE=InnoDB;

    
    INSERT INTO tmp_child_orders
    SELECT
        po.PARENT_ORDER_ID,
        sa.SPLIT_GROUP,
        po.ORDER_TYPE,
        CONCAT(po.PARENT_ORDER_ID, '-', LPAD(sa.SPLIT_GROUP, 3, '0')) AS CHILD_ORDER_ID,
        CASE WHEN MAX(sa.IS_SUSPENDED_GROUP) = 1 THEN 'ORDER_SUSPENDED' ELSE 'PENDING' END AS CHILD_STATUS
    FROM tmp_parent_orders po
    JOIN tmp_split_all sa
      ON sa.PARENT_ORDER_ID = po.PARENT_ORDER_ID
    GROUP BY po.PARENT_ORDER_ID, sa.SPLIT_GROUP, po.ORDER_TYPE;

    START TRANSACTION;

    
    INSERT INTO wms_to_wcs_order_request_data
        (PARENT_ORDER_ID, ORDER_TYPE, ORDER_ID, ORDER_REQUEST_STATUS, INSERTED_TIMESTAMP, INSERTED_BY)
    SELECT
        co.PARENT_ORDER_ID,
        'FOOD',
        co.CHILD_ORDER_ID,
        co.CHILD_STATUS,
        CURRENT_TIMESTAMP(3),
        'BACKEND-SERVICE'
    FROM tmp_child_orders co
    WHERE NOT EXISTS (
        SELECT 1
        FROM wms_to_wcs_order_request_data r
        WHERE r.ORDER_ID = co.CHILD_ORDER_ID
    );

    SELECT COUNT(*) INTO v_child_cnt FROM tmp_child_orders;

    
    INSERT INTO wms_to_wcs_order_line_request_data
        (WMS_ORDER_REQUEST_DATA_ID, ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, BATCH_ID,
         DISPLAY_OPERATOR_INSTRUCTION, ORDER_LINE_PROCESS_STATUS, INSERTED_TIMESTAMP, INSERTED_BY)
    SELECT
        r.WMS_ORDER_REQUEST_DATA_ID,
        r.ORDER_ID,
        sa.ORDER_LINE_ID,
        sa.ARTICLE_ID,
        sa.QUANTITY,
        sa.BATCH_ID,
        sa.DISPLAY_OPERATOR_INSTRUCTION,
        'PENDING',
        CURRENT_TIMESTAMP(3),
        'BACKEND-SERVICE'
    FROM tmp_split_all sa
    JOIN tmp_child_orders co
      ON co.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND co.SPLIT_GROUP     = sa.SPLIT_GROUP
    JOIN wms_to_wcs_order_request_data r
      ON r.ORDER_ID = co.CHILD_ORDER_ID
    WHERE NOT EXISTS (
        SELECT 1
        FROM wms_to_wcs_order_line_request_data lr
        WHERE lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID
          AND lr.ORDER_LINE_ID = sa.ORDER_LINE_ID
    );

    
    UPDATE wms_to_wcs_order_level_pre_staged_data p
    JOIN tmp_parent_orders t
      ON t.PRE_STAGED_REQ_ID = p.WMS_ORDER_REQUEST_DATA_ID
    SET p.IS_STAGED = 1,
        p.UPDATED_TIMESTAMP = CURRENT_TIMESTAMP(3),
        p.UPDATED_BY = 'SPLIT-OPS-V3';

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='2',
           ORDERSPLIT_ENDTIME = NOW()
     WHERE ID = v_ruleLog_id;

    COMMIT;

    DO RELEASE_LOCK(CONCAT('SPLIT_', @batch_picklist_code));

    
    SELECT
        @batch_picklist_code AS BATCH_PICKLIST_CODE,
        v_parent_cnt AS PARENTS_PROCESSED,
        v_line_cnt   AS LINES_CONSIDERED,
        v_child_cnt  AS CHILD_ORDERS_CREATED,
        v_short_cnt  AS SHORT_LINES_FLAGGED,
        v_max_lines  AS MAX_ORDER_LINES,
        v_max_qty    AS MAX_ORDER_QTY,
        v_tol_lines  AS TOL_LINES,
        v_tol_qty    AS TOL_QTY,
        v_hard_lines AS HARD_LINES,
        v_hard_qty   AS HARD_QTY,
        v_suspend_short_lines AS SUSPEND_SHORT_LINES;

END sp_main */$$
DELIMITER ;

/* Procedure structure for procedure `sp_split_orders_ops_v4` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_split_orders_ops_v4` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sp_split_orders_ops_v4`()
sp_main: BEGIN

    

    
    DECLARE v_max_lines INT DEFAULT 50;
    DECLARE v_max_qty   INT DEFAULT 500;

    
    DECLARE v_tol_lines INT DEFAULT 10;
    DECLARE v_tol_qty   INT DEFAULT 100;

    
    DECLARE v_hard_lines INT DEFAULT 60;
    DECLARE v_hard_qty   INT DEFAULT 600;

    
    DECLARE v_suspend_short_lines INT DEFAULT 0;

    
    DECLARE v_rule_id INT DEFAULT NULL;
    DECLARE v_ruleLog_id INT DEFAULT NULL;
    DECLARE v_rule_defination TEXT;

    
    DECLARE v_lock_ok INT DEFAULT 0;

    
    DECLARE v_parent_cnt INT DEFAULT 0;
    DECLARE v_line_cnt   INT DEFAULT 0;
    DECLARE v_child_cnt  INT DEFAULT 0;
    DECLARE v_short_cnt  INT DEFAULT 0;

    
    DECLARE v_batch_quoted TEXT;

    
    DECLARE v_pre_lines INT DEFAULT 0;
    DECLARE v_post_lines INT DEFAULT 0;
    DECLARE v_missing_lines INT DEFAULT 0;
    DECLARE v_pre_qty BIGINT DEFAULT 0;
    DECLARE v_post_qty BIGINT DEFAULT 0;
    DECLARE v_errmsg TEXT DEFAULT '';

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DO RELEASE_LOCK(CONCAT('SPLIT_', IFNULL(@batch_picklist_code,'')));
        RESIGNAL;
    END;

    
    SET v_max_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_ORDER_LINES_PER_ORDER'
            AND IS_ACTIVE = 1
          LIMIT 1),
        50
    );

    SET v_max_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_QUANTITY_PER_ORDER'
            AND IS_ACTIVE = 1
          LIMIT 1),
        500
    );

    SET v_tol_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_LINES'
            AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_lines
    );

    SET v_tol_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_QTY'
            AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_qty
    );

    SET v_suspend_short_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'SUSPEND_SHORT_LINES'
            AND IS_ACTIVE = 1
          LIMIT 1),
        0
    );

    SET v_hard_lines = v_max_lines + v_tol_lines;
    SET v_hard_qty   = v_max_qty   + v_tol_qty;

    
    SELECT ID, RULE_ID
      INTO v_ruleLog_id, v_rule_id
    FROM picklist_split_order_master
    WHERE IS_PROCESSED='0'
    ORDER BY ID
    LIMIT 1;

    IF v_rule_id IS NULL THEN
        SELECT 'NO_RULE_TO_PROCESS' AS STATUS;
        LEAVE sp_main;
    END IF;

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='1',
           ORDERSPLIT_STARTTIME = NOW()
     WHERE ID = v_ruleLog_id;

    SELECT FILTER_CONDITION
      INTO v_rule_defination
    FROM pick_rule_master
    WHERE PICK_RULE_ID = v_rule_id
    ORDER BY PICK_RULE_ID
    LIMIT 1;

    IF v_rule_defination IS NULL OR LENGTH(v_rule_defination) < 3 THEN
        UPDATE picklist_split_order_master
           SET IS_PROCESSED='2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        SELECT 'NO_RULE_DEFINITION_FOUND' AS STATUS, v_rule_id AS RULE_ID;
        LEAVE sp_main;
    END IF;

    
    SET v_rule_defination = LEFT(v_rule_defination, LENGTH(v_rule_defination)-1);

    
    

     
    
    SELECT GET_LOCK(CONCAT('SPLIT_',v_rule_id), 2) INTO v_lock_ok;
    IF v_lock_ok <> 1 THEN
        SET v_errmsg = 'Split job already running for this BATCH_PICKLIST_CODE';
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

   

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
    CREATE TEMPORARY TABLE tmp_parent_orders (
        PRE_STAGED_REQ_ID BIGINT NOT NULL,
        PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
        ORDER_TYPE        VARCHAR(100) NOT NULL,
        PRIMARY KEY (PRE_STAGED_REQ_ID),
        KEY (PARENT_ORDER_ID)
    ) ENGINE=INNODB;

    
   
    
     SET @sql = CONCAT(
        'INSERT INTO tmp_parent_orders (PRE_STAGED_REQ_ID, PARENT_ORDER_ID, ORDER_TYPE)
         SELECT WMS_ORDER_REQUEST_DATA_ID,
                PARENT_ORDER_ID,
                COALESCE(NULLIF(PICKING_TYPE,''''), NULLIF(ORDER_CATEGORY,''''), ''PICK'') AS ORDER_TYPE
           FROM wms_to_wcs_order_level_pre_staged_data
          WHERE IFNULL(IS_STAGED,0) = 0
            AND PARENT_ORDER_ID IN (', v_rule_defination, ')'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    SELECT COUNT(*) INTO v_parent_cnt FROM tmp_parent_orders;

    IF v_parent_cnt = 0 THEN
        DO RELEASE_LOCK(CONCAT('SPLIT_', v_rule_id));

        UPDATE picklist_split_order_master
           SET IS_PROCESSED='2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        SELECT
            @batch_picklist_code AS BATCH_PICKLIST_CODE,
            'NO_PARENTS_TO_SPLIT' AS STATUS,
            v_max_lines AS MAX_ORDER_LINES_PER_ORDER,
            v_max_qty   AS MAX_QUANTITY_PER_ORDER,
            v_tol_lines AS TOL_LINES,
            v_tol_qty   AS TOL_QTY;
        LEAVE sp_main;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_lines;
    CREATE TEMPORARY TABLE tmp_lines (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines
    SELECT
        l.PARENT_ORDER_ID,
        l.ORDER_LINE_ID,
        l.ARTICLE_ID,
        l.BATCH_ID,
        l.QUANTITY,
        l.DISPLAY_OPERATOR_INSTRUCTION
    FROM wms_to_wcs_order_line_level_pre_staged_data l
    JOIN tmp_parent_orders p
      ON p.PARENT_ORDER_ID = l.PARENT_ORDER_ID
    WHERE IFNULL(l.ORDER_LINE_PROCESS_STATUS,'PENDING') <> 'DELETED';

    SELECT COUNT(*) INTO v_line_cnt FROM tmp_lines;

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_article_list;
    CREATE TEMPORARY TABLE tmp_article_list (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        PRIMARY KEY (ARTICLE_ID)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_article_list (ARTICLE_ID)
    SELECT DISTINCT ARTICLE_ID
    FROM tmp_lines
    WHERE ARTICLE_ID IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
    CREATE TEMPORARY TABLE tmp_line_category (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (ARTICLE_ID),
        KEY (CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_category (ARTICLE_ID, CLIENT_ORDER_TYPE)
    SELECT
        al.ARTICLE_ID,
        COALESCE(NULLIF(cm.CLIENT_ORDER_TYPE,''), 'FOOD') AS CLIENT_ORDER_TYPE
    FROM tmp_article_list al
    LEFT JOIN sku_master sm
      ON sm.SKU_ID = al.ARTICLE_ID
    LEFT JOIN category_master cm
      ON cm.CATEGORY_ID = sm.CATEGORY;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
    CREATE TEMPORARY TABLE tmp_lines_cat (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines_cat
    SELECT
        tl.PARENT_ORDER_ID,
        COALESCE(lc.CLIENT_ORDER_TYPE, 'FOOD') AS CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION
    FROM tmp_lines tl
    LEFT JOIN tmp_line_category lc
      ON lc.ARTICLE_ID = tl.ARTICLE_ID;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_bucket_stats;
    CREATE TEMPORARY TABLE tmp_bucket_stats (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        LINE_CNT INT NOT NULL,
        TOTAL_QTY INT NOT NULL,
        NEED_SPLIT INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_bucket_stats (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, LINE_CNT, TOTAL_QTY, NEED_SPLIT)
    SELECT
        PARENT_ORDER_ID,
        CLIENT_ORDER_TYPE,
        COUNT(*) AS LINE_CNT,
        SUM(QUANTITY) AS TOTAL_QTY,
        CASE
            WHEN COUNT(*) > v_hard_lines OR SUM(QUANTITY) > v_hard_qty THEN 1
            ELSE 0
        END AS NEED_SPLIT
    FROM tmp_lines_cat
    GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_split_all;
    CREATE TEMPORARY TABLE tmp_split_all (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        SPLIT_GROUP INT NOT NULL,
        IS_SUSPENDED_GROUP INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_split_all
    SELECT
        tl.PARENT_ORDER_ID,
        tl.CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION,
        1 AS SPLIT_GROUP,
        0 AS IS_SUSPENDED_GROUP
    FROM tmp_lines_cat tl
    JOIN tmp_bucket_stats bs
      ON bs.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND bs.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
    WHERE bs.NEED_SPLIT = 0;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_need_split;
    CREATE TEMPORARY TABLE tmp_need_split (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_need_split
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE
    FROM tmp_bucket_stats
    WHERE NEED_SPLIT = 1;

    IF (SELECT COUNT(*) FROM tmp_need_split) > 0 THEN

        
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_list;
        CREATE TEMPORARY TABLE tmp_sku_list (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ARTICLE_ID, BATCH_ID),
            KEY (ARTICLE_ID, BATCH_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_sku_list
        SELECT DISTINCT tl.PARENT_ORDER_ID, tl.CLIENT_ORDER_TYPE, tl.ARTICLE_ID, tl.BATCH_ID
        FROM tmp_lines_cat tl
        JOIN tmp_need_split ns
          ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND ns.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
        WHERE tl.ARTICLE_ID IS NOT NULL AND tl.BATCH_ID IS NOT NULL;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
        CREATE TEMPORARY TABLE tmp_sku_global (
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            PRIMARY KEY (ARTICLE_ID, BATCH_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_sku_global
        SELECT DISTINCT ARTICLE_ID, BATCH_ID
        FROM tmp_sku_list;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
        CREATE TEMPORARY TABLE tmp_inv_bin (
            BIN_ID INT NOT NULL,
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            AVAIL_QTY  INT NOT NULL,
            LAST_TS    DATETIME(3) NULL,
            PRIMARY KEY (BIN_ID, ARTICLE_ID, BATCH_ID),
            KEY (ARTICLE_ID, BATCH_ID),
            KEY (BIN_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_inv_bin
        SELECT
            lim.BIN_ID,
            lim.ARTICLE_ID,
            lim.BATCH_ID,
            CAST(SUM(GREATEST(lim.QUANTITY - lim.VIRTUAL_QUANTITY_TO_PICK, 0)) AS SIGNED) AS AVAIL_QTY,
            MAX(lim.UPDATED_TIMESTAMP) AS LAST_TS
        FROM live_inventory_master lim
        JOIN tmp_sku_global sg
          ON sg.ARTICLE_ID = lim.ARTICLE_ID
         AND sg.BATCH_ID   = lim.BATCH_ID
        WHERE lim.IS_ACTIVE = 1
        GROUP BY lim.BIN_ID, lim.ARTICLE_ID, lim.BATCH_ID
        HAVING AVAIL_QTY > 0;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_bin_hits;
        CREATE TEMPORARY TABLE tmp_bin_hits (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            BIN_ID INT NOT NULL,
            HIT_CNT INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, BIN_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_bin_hits
        SELECT
            s.PARENT_ORDER_ID,
            s.CLIENT_ORDER_TYPE,
            ib.BIN_ID,
            COUNT(*) AS HIT_CNT
        FROM tmp_sku_list s
        JOIN tmp_inv_bin ib
          ON ib.ARTICLE_ID = s.ARTICLE_ID
         AND ib.BATCH_ID   = s.BATCH_ID
        GROUP BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE, ib.BIN_ID;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_line_metrics;
        CREATE TEMPORARY TABLE tmp_line_metrics (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ORDER_LINE_ID VARCHAR(36) NOT NULL,
            DOMINANT_BIN_ID INT NULL,
            DOMINANT_HIT_CNT INT NOT NULL,
            TOTAL_AVAIL INT NOT NULL,
            REQ_QTY INT NOT NULL,
            SHORT_FLAG INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_line_metrics
        WITH candidate_bins AS (
            SELECT
                tl.PARENT_ORDER_ID,
                tl.CLIENT_ORDER_TYPE,
                tl.ORDER_LINE_ID,
                tl.QUANTITY AS REQ_QTY,
                ib.BIN_ID,
                COALESCE(bh.HIT_CNT,0) AS HIT_CNT,
                ib.AVAIL_QTY,
                ib.LAST_TS,
                ROW_NUMBER() OVER (
                    PARTITION BY tl.PARENT_ORDER_ID, tl.CLIENT_ORDER_TYPE, tl.ORDER_LINE_ID
                    ORDER BY COALESCE(bh.HIT_CNT,0) DESC, ib.AVAIL_QTY DESC, ib.LAST_TS DESC, ib.BIN_ID
                ) AS rn,
                SUM(ib.AVAIL_QTY) OVER (
                    PARTITION BY tl.PARENT_ORDER_ID, tl.CLIENT_ORDER_TYPE, tl.ORDER_LINE_ID
                ) AS total_avail
            FROM tmp_lines_cat tl
            JOIN tmp_need_split ns
              ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
             AND ns.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
            JOIN tmp_inv_bin ib
              ON ib.ARTICLE_ID = tl.ARTICLE_ID AND ib.BATCH_ID = tl.BATCH_ID
            LEFT JOIN tmp_bin_hits bh
              ON bh.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
             AND bh.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
             AND bh.BIN_ID = ib.BIN_ID
        )
        SELECT
            cb.PARENT_ORDER_ID,
            cb.CLIENT_ORDER_TYPE,
            cb.ORDER_LINE_ID,
            MAX(CASE WHEN cb.rn = 1 THEN cb.BIN_ID END)  AS DOMINANT_BIN_ID,
            MAX(CASE WHEN cb.rn = 1 THEN cb.HIT_CNT END) AS DOMINANT_HIT_CNT,
            MAX(cb.total_avail) AS TOTAL_AVAIL,
            MAX(cb.REQ_QTY)     AS REQ_QTY,
            CASE WHEN MAX(cb.total_avail) < MAX(cb.REQ_QTY) THEN 1 ELSE 0 END AS SHORT_FLAG
        FROM candidate_bins cb
        GROUP BY cb.PARENT_ORDER_ID, cb.CLIENT_ORDER_TYPE, cb.ORDER_LINE_ID;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_lines_enriched;
        CREATE TEMPORARY TABLE tmp_lines_enriched (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
            ARTICLE_ID      VARCHAR(200) NULL,
            BATCH_ID        VARCHAR(200) NULL,
            QUANTITY        INT NOT NULL,
            DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
            DOMINANT_BIN_ID INT NULL,
            DOMINANT_HIT_CNT INT NOT NULL,
            SHORT_FLAG INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
            KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
            KEY (DOMINANT_BIN_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_lines_enriched
        SELECT
            tl.PARENT_ORDER_ID,
            tl.CLIENT_ORDER_TYPE,
            tl.ORDER_LINE_ID,
            tl.ARTICLE_ID,
            tl.BATCH_ID,
            tl.QUANTITY,
            tl.DISPLAY_OPERATOR_INSTRUCTION,
            lm.DOMINANT_BIN_ID,
            COALESCE(lm.DOMINANT_HIT_CNT,0) AS DOMINANT_HIT_CNT,
            COALESCE(lm.SHORT_FLAG,1) AS SHORT_FLAG
        FROM tmp_lines_cat tl
        JOIN tmp_need_split ns
          ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND ns.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
        LEFT JOIN tmp_line_metrics lm
          ON lm.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND lm.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
         AND lm.ORDER_LINE_ID   = tl.ORDER_LINE_ID;

        IF v_suspend_short_lines = 0 THEN
            UPDATE tmp_lines_enriched
               SET SHORT_FLAG = 0;
        END IF;

        SELECT COUNT(*) INTO v_short_cnt
        FROM tmp_lines_enriched
        WHERE SHORT_FLAG = 1;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_norm_plan;
        CREATE TEMPORARY TABLE tmp_norm_plan (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            LINE_CNT INT NOT NULL,
            TOTAL_QTY INT NOT NULL,
            GRP_CNT INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
        ) ENGINE=INNODB;

        INSERT INTO tmp_norm_plan
        SELECT
            PARENT_ORDER_ID,
            CLIENT_ORDER_TYPE,
            COUNT(*) AS LINE_CNT,
            SUM(QUANTITY) AS TOTAL_QTY,
            GREATEST(
                1,
                (COUNT(*) + v_hard_lines - 1) DIV v_hard_lines,
                (SUM(QUANTITY) + v_hard_qty - 1) DIV v_hard_qty
            ) AS GRP_CNT
        FROM tmp_lines_enriched
        WHERE SHORT_FLAG = 0
        GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_ranked_normal;
        CREATE TEMPORARY TABLE tmp_ranked_normal (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
            ARTICLE_ID      VARCHAR(200) NULL,
            BATCH_ID        VARCHAR(200) NULL,
            QUANTITY        INT NOT NULL,
            DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
            rn INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
            KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, rn)
        ) ENGINE=INNODB;

        INSERT INTO tmp_ranked_normal
        SELECT
            tle.PARENT_ORDER_ID,
            tle.CLIENT_ORDER_TYPE,
            tle.ORDER_LINE_ID,
            tle.ARTICLE_ID,
            tle.BATCH_ID,
            tle.QUANTITY,
            tle.DISPLAY_OPERATOR_INSTRUCTION,
            ROW_NUMBER() OVER (
                PARTITION BY tle.PARENT_ORDER_ID, tle.CLIENT_ORDER_TYPE
                ORDER BY
                    COALESCE(tle.DOMINANT_BIN_ID, 2147483647),
                    tle.DOMINANT_HIT_CNT DESC,
                    tle.QUANTITY DESC,
                    tle.ORDER_LINE_ID
            ) AS rn
        FROM tmp_lines_enriched tle
        WHERE tle.SHORT_FLAG = 0;

        
        INSERT INTO tmp_split_all
        SELECT
            r.PARENT_ORDER_ID,
            r.CLIENT_ORDER_TYPE,
            r.ORDER_LINE_ID,
            r.ARTICLE_ID,
            r.BATCH_ID,
            r.QUANTITY,
            r.DISPLAY_OPERATOR_INSTRUCTION,
            1 + ((r.rn - 1) * p.GRP_CNT) DIV p.LINE_CNT AS SPLIT_GROUP,
            0 AS IS_SUSPENDED_GROUP
        FROM tmp_ranked_normal r
        JOIN tmp_norm_plan p
          ON p.PARENT_ORDER_ID = r.PARENT_ORDER_ID
         AND p.CLIENT_ORDER_TYPE = r.CLIENT_ORDER_TYPE;

        
        IF v_suspend_short_lines = 1 THEN

            DROP TEMPORARY TABLE IF EXISTS tmp_short_plan;
            CREATE TEMPORARY TABLE tmp_short_plan (
                PARENT_ORDER_ID VARCHAR(100) NOT NULL,
                CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
                LINE_CNT INT NOT NULL,
                TOTAL_QTY INT NOT NULL,
                GRP_CNT INT NOT NULL,
                OFFSET_G INT NOT NULL,
                PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
            ) ENGINE=INNODB;

            INSERT INTO tmp_short_plan
            SELECT
                s.PARENT_ORDER_ID,
                s.CLIENT_ORDER_TYPE,
                COUNT(*) AS LINE_CNT,
                SUM(s.QUANTITY) AS TOTAL_QTY,
                GREATEST(
                    1,
                    (COUNT(*) + v_hard_lines - 1) DIV v_hard_lines,
                    (SUM(s.QUANTITY) + v_hard_qty - 1) DIV v_hard_qty
                ) AS GRP_CNT,
                COALESCE(n.GRP_CNT, 0) AS OFFSET_G
            FROM tmp_lines_enriched s
            LEFT JOIN tmp_norm_plan n
              ON n.PARENT_ORDER_ID = s.PARENT_ORDER_ID
             AND n.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
            WHERE s.SHORT_FLAG = 1
            GROUP BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE;

            DROP TEMPORARY TABLE IF EXISTS tmp_ranked_short;
            CREATE TEMPORARY TABLE tmp_ranked_short (
                PARENT_ORDER_ID VARCHAR(100) NOT NULL,
                CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
                ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
                ARTICLE_ID      VARCHAR(200) NULL,
                BATCH_ID        VARCHAR(200) NULL,
                QUANTITY        INT NOT NULL,
                DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
                rn INT NOT NULL,
                PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
                KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, rn)
            ) ENGINE=INNODB;

            INSERT INTO tmp_ranked_short
            SELECT
                tle.PARENT_ORDER_ID,
                tle.CLIENT_ORDER_TYPE,
                tle.ORDER_LINE_ID,
                tle.ARTICLE_ID,
                tle.BATCH_ID,
                tle.QUANTITY,
                tle.DISPLAY_OPERATOR_INSTRUCTION,
                ROW_NUMBER() OVER (
                    PARTITION BY tle.PARENT_ORDER_ID, tle.CLIENT_ORDER_TYPE
                    ORDER BY tle.QUANTITY DESC, tle.ORDER_LINE_ID
                ) AS rn
            FROM tmp_lines_enriched tle
            WHERE tle.SHORT_FLAG = 1;

            INSERT INTO tmp_split_all
            SELECT
                r.PARENT_ORDER_ID,
                r.CLIENT_ORDER_TYPE,
                r.ORDER_LINE_ID,
                r.ARTICLE_ID,
                r.BATCH_ID,
                r.QUANTITY,
                r.DISPLAY_OPERATOR_INSTRUCTION,
                sp.OFFSET_G + (1 + ((r.rn - 1) * sp.GRP_CNT) DIV sp.LINE_CNT) AS SPLIT_GROUP,
                1 AS IS_SUSPENDED_GROUP
            FROM tmp_ranked_short r
            JOIN tmp_short_plan sp
              ON sp.PARENT_ORDER_ID = r.PARENT_ORDER_ID
             AND sp.CLIENT_ORDER_TYPE = r.CLIENT_ORDER_TYPE;

        END IF;

    END IF;

    

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_pre_lines, v_pre_qty
    FROM tmp_lines;

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_post_lines, v_post_qty
    FROM tmp_split_all;

    IF v_pre_lines <> v_post_lines OR v_pre_qty <> v_post_qty THEN
        SET v_errmsg = CONCAT(
            'SPLIT_VALIDATION_FAILED: PRE_LINES=', v_pre_lines,
            ', POST_LINES=', v_post_lines,
            ', PRE_QTY=', v_pre_qty,
            ', POST_QTY=', v_post_qty
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    
    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_lines tl
    LEFT JOIN tmp_split_all sa
      ON sa.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND sa.ORDER_LINE_ID   = tl.ORDER_LINE_ID
    WHERE sa.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('SPLIT_VALIDATION_FAILED: MISSING_LINES=', v_missing_lines);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
    CREATE TEMPORARY TABLE tmp_cat_seq (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        CAT_SEQ INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
        KEY (PARENT_ORDER_ID, CAT_SEQ)
    ) ENGINE=INNODB;

    INSERT INTO tmp_cat_seq (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CAT_SEQ)
    SELECT
        x.PARENT_ORDER_ID,
        x.CLIENT_ORDER_TYPE,
        ROW_NUMBER() OVER (PARTITION BY x.PARENT_ORDER_ID ORDER BY x.CLIENT_ORDER_TYPE) AS CAT_SEQ
    FROM (
        SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE
        FROM tmp_lines_cat
    ) X;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_bucket_groupmax;
    CREATE TEMPORARY TABLE tmp_bucket_groupmax (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        MAX_GRP INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_bucket_groupmax
    SELECT
        PARENT_ORDER_ID,
        CLIENT_ORDER_TYPE,
        MAX(SPLIT_GROUP) AS MAX_GRP
    FROM tmp_split_all
    GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;

    DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
    CREATE TEMPORARY TABLE tmp_child_orders (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        CAT_SEQ INT NOT NULL,
        SPLIT_GROUP INT NOT NULL,
        CHILD_ORDER_ID VARCHAR(100) NOT NULL,
        CHILD_STATUS ENUM('PENDING','ORDER_SUSPENDED') NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP),
        KEY (CHILD_ORDER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_child_orders
    SELECT
        sa.PARENT_ORDER_ID,
        sa.CLIENT_ORDER_TYPE,
        cs.CAT_SEQ,
        sa.SPLIT_GROUP,
        CASE
            WHEN bg.MAX_GRP = 1
                THEN CONCAT(sa.PARENT_ORDER_ID, '-', cs.CAT_SEQ)
            ELSE CONCAT(sa.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', LPAD(sa.SPLIT_GROUP, 3, '0'))
        END AS CHILD_ORDER_ID,
        CASE WHEN MAX(sa.IS_SUSPENDED_GROUP) = 1 THEN 'ORDER_SUSPENDED' ELSE 'PENDING' END AS CHILD_STATUS
    FROM tmp_split_all sa
    JOIN tmp_cat_seq cs
      ON cs.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND cs.CLIENT_ORDER_TYPE = sa.CLIENT_ORDER_TYPE
    JOIN tmp_bucket_groupmax bg
      ON bg.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND bg.CLIENT_ORDER_TYPE = sa.CLIENT_ORDER_TYPE
    GROUP BY sa.PARENT_ORDER_ID, sa.CLIENT_ORDER_TYPE, cs.CAT_SEQ, sa.SPLIT_GROUP, bg.MAX_GRP;

    START TRANSACTION;

    
    INSERT INTO wms_to_wcs_order_request_data
        (PARENT_ORDER_ID, ORDER_TYPE, ORDER_ID, ORDER_REQUEST_STATUS, INSERTED_TIMESTAMP, INSERTED_BY)
    SELECT
        co.PARENT_ORDER_ID,
        co.CLIENT_ORDER_TYPE,
        co.CHILD_ORDER_ID,
        co.CHILD_STATUS,
        CURRENT_TIMESTAMP(3),
        'BACKEND-SERVICE'
    FROM tmp_child_orders co
    WHERE NOT EXISTS (
        SELECT 1
        FROM wms_to_wcs_order_request_data r
        WHERE r.ORDER_ID = co.CHILD_ORDER_ID
    );

    SELECT COUNT(*) INTO v_child_cnt FROM tmp_child_orders;

    
    INSERT INTO wms_to_wcs_order_line_request_data
        (WMS_ORDER_REQUEST_DATA_ID, ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, BATCH_ID,
         DISPLAY_OPERATOR_INSTRUCTION, ORDER_LINE_PROCESS_STATUS, INSERTED_TIMESTAMP, INSERTED_BY)
    SELECT
        r.WMS_ORDER_REQUEST_DATA_ID,
        r.ORDER_ID,
        sa.ORDER_LINE_ID,
        sa.ARTICLE_ID,
        sa.QUANTITY,
        sa.BATCH_ID,
        sa.DISPLAY_OPERATOR_INSTRUCTION,
        'PENDING',
        CURRENT_TIMESTAMP(3),
        'BACKEND-SERVICE'
    FROM tmp_split_all sa
    JOIN tmp_child_orders co
      ON co.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND co.CLIENT_ORDER_TYPE = sa.CLIENT_ORDER_TYPE
     AND co.SPLIT_GROUP     = sa.SPLIT_GROUP
    JOIN wms_to_wcs_order_request_data r
      ON r.ORDER_ID = co.CHILD_ORDER_ID
    WHERE NOT EXISTS (
        SELECT 1
        FROM wms_to_wcs_order_line_request_data lr
        WHERE lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID
          AND lr.ORDER_LINE_ID = sa.ORDER_LINE_ID
    );

    
    UPDATE wms_to_wcs_order_level_pre_staged_data p
    JOIN tmp_parent_orders t
      ON t.PRE_STAGED_REQ_ID = p.WMS_ORDER_REQUEST_DATA_ID
    SET p.IS_STAGED = 1,
        p.UPDATED_TIMESTAMP = CURRENT_TIMESTAMP(3),
        p.UPDATED_BY = 'SPLIT-OPS-V3';

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='2',
           ORDERSPLIT_ENDTIME = NOW(),
            RULE_STATS = JSON_OBJECT(
            'RULE_ID', v_rule_id,
            'PARENTS_FOUND', v_parent_cnt,
            'LINES_CONSIDERED', v_line_cnt,
            'CHILD_ORDERS_CREATED', v_child_cnt,
            'SHORT_LINES_FLAGGED', v_short_cnt,
            'MAX_ORDER_LINES_PER_ORDER', v_max_lines,
            'MAX_QUANTITY_PER_ORDER', v_max_qty,
            'TOL_LINES', v_tol_lines,
            'TOL_QTY', v_tol_qty,
            'HARD_LINES', v_hard_lines,
            'HARD_QTY', v_hard_qty,
            'SUSPEND_SHORT_LINES', v_suspend_short_lines,
            'CATEGORY_DEFAULT', 'FOOD'
        )
     WHERE ID = v_ruleLog_id;

    COMMIT;

    DO RELEASE_LOCK(CONCAT('SPLIT_', v_rule_id));

    
    SELECT
        v_rule_id AS RULE_ID,
        v_parent_cnt AS PARENTS_PROCESSED,
        v_line_cnt   AS LINES_CONSIDERED,
        v_child_cnt  AS CHILD_ORDERS_CREATED,
        v_short_cnt  AS SHORT_LINES_FLAGGED,
        v_max_lines  AS MAX_ORDER_LINES,
        v_max_qty    AS MAX_ORDER_QTY,
        v_tol_lines  AS TOL_LINES,
        v_tol_qty    AS TOL_QTY,
        v_hard_lines AS HARD_LINES,
        v_hard_qty   AS HARD_QTY,
        v_suspend_short_lines AS SUSPEND_SHORT_LINES;

END sp_main */$$
DELIMITER ;

/* Procedure structure for procedure `sp_split_orders_ops_v5` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_split_orders_ops_v5` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sp_split_orders_ops_v5`()
sp_main: BEGIN

    

    
    DECLARE v_max_lines INT DEFAULT 50;
    DECLARE v_max_qty   INT DEFAULT 500;

    
    DECLARE v_tol_lines INT DEFAULT 10;
    DECLARE v_tol_qty   INT DEFAULT 100;

    
    DECLARE v_hard_lines INT DEFAULT 60;
    DECLARE v_hard_qty   INT DEFAULT 600;

    
    DECLARE v_suspend_short_lines INT DEFAULT 0;

    
    DECLARE v_rule_id INT DEFAULT NULL;
    DECLARE v_ruleLog_id INT DEFAULT NULL;
    DECLARE v_rule_defination TEXT;

    
    DECLARE v_lock_ok INT DEFAULT 0;

    
    DECLARE v_parent_cnt INT DEFAULT 0;
    DECLARE v_line_cnt   INT DEFAULT 0;
    DECLARE v_child_cnt  INT DEFAULT 0;
    DECLARE v_short_cnt  INT DEFAULT 0;

    
    DECLARE v_batch_quoted TEXT;

    
    DECLARE v_pre_lines INT DEFAULT 0;
    DECLARE v_post_lines INT DEFAULT 0;
    DECLARE v_missing_lines INT DEFAULT 0;
    DECLARE v_pre_qty BIGINT DEFAULT 0;
    DECLARE v_post_qty BIGINT DEFAULT 0;
    DECLARE v_errmsg TEXT DEFAULT '';

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        
        IF v_lock_ok = 1 AND v_rule_id IS NOT NULL THEN
            DO RELEASE_LOCK(CONCAT('SPLIT_', v_rule_id));
        END IF;
        RESIGNAL;
    END;

    
    SET v_max_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_ORDER_LINES_PER_ORDER'
            AND IS_ACTIVE = 1
          LIMIT 1),
        50
    );

    SET v_max_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_QUANTITY_PER_ORDER'
            AND IS_ACTIVE = 1
          LIMIT 1),
        500
    );

    SET v_tol_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_LINES'
            AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_lines
    );

    SET v_tol_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_QTY'
            AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_qty
    );

    SET v_suspend_short_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'SUSPEND_SHORT_LINES'
            AND IS_ACTIVE = 1
          LIMIT 1),
        0
    );

    SET v_hard_lines = v_max_lines + v_tol_lines;
    SET v_hard_qty   = v_max_qty   + v_tol_qty;

    
    SELECT ID, RULE_ID
      INTO v_ruleLog_id, v_rule_id
    FROM picklist_split_order_master
    WHERE IS_PROCESSED='0'
    ORDER BY ID
    LIMIT 1;

    IF v_rule_id IS NULL THEN
        SELECT 'NO_RULE_TO_PROCESS' AS STATUS;
        LEAVE sp_main;
    END IF;

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='1',
           ORDERSPLIT_STARTTIME = NOW()
     WHERE ID = v_ruleLog_id;

    SELECT FILTER_CONDITION
      INTO v_rule_defination
    FROM pick_rule_master
    WHERE PICK_RULE_ID = v_rule_id
    ORDER BY PICK_RULE_ID
    LIMIT 1;

    IF v_rule_defination IS NULL OR LENGTH(v_rule_defination) < 3 THEN
        UPDATE picklist_split_order_master
           SET IS_PROCESSED='2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        SELECT 'NO_RULE_DEFINITION_FOUND' AS STATUS, v_rule_id AS RULE_ID;
        LEAVE sp_main;
    END IF;

    
    SET v_rule_defination = LEFT(v_rule_defination, LENGTH(v_rule_defination)-1);

    
    SELECT GET_LOCK(CONCAT('SPLIT_', v_rule_id), 2) INTO v_lock_ok;
    IF v_lock_ok <> 1 THEN
        SET v_errmsg = CONCAT('Split job already running for RULE_ID=', v_rule_id);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
    CREATE TEMPORARY TABLE tmp_parent_orders (
        PRE_STAGED_REQ_ID BIGINT NOT NULL,
        PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
        ORDER_TYPE        VARCHAR(100) NOT NULL,
        PRIMARY KEY (PRE_STAGED_REQ_ID),
        KEY (PARENT_ORDER_ID)
    ) ENGINE=INNODB;

    
    SET @sql = CONCAT(
        'INSERT INTO tmp_parent_orders (PRE_STAGED_REQ_ID, PARENT_ORDER_ID, ORDER_TYPE)
         SELECT WMS_ORDER_REQUEST_DATA_ID,
                PARENT_ORDER_ID,
                COALESCE(NULLIF(PICKING_TYPE,''''), NULLIF(ORDER_CATEGORY,''''), ''PICK'') AS ORDER_TYPE
           FROM wms_to_wcs_order_level_pre_staged_data
          WHERE IFNULL(IS_STAGED,0) = 0
            AND PARENT_ORDER_ID IN (', v_rule_defination, ')'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    SELECT COUNT(*) INTO v_parent_cnt FROM tmp_parent_orders;

    IF v_parent_cnt = 0 THEN
        DO RELEASE_LOCK(CONCAT('SPLIT_', v_rule_id));

        UPDATE picklist_split_order_master
           SET IS_PROCESSED='2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        SELECT
            NULL AS BATCH_PICKLIST_CODE,
            'NO_PARENTS_TO_SPLIT' AS STATUS,
            v_max_lines AS MAX_ORDER_LINES_PER_ORDER,
            v_max_qty   AS MAX_QUANTITY_PER_ORDER,
            v_tol_lines AS TOL_LINES,
            v_tol_qty   AS TOL_QTY;
        LEAVE sp_main;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_lines;
    CREATE TEMPORARY TABLE tmp_lines (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines
    SELECT
        l.PARENT_ORDER_ID,
        l.ORDER_LINE_ID,
        l.ARTICLE_ID,
        l.BATCH_ID,
        l.QUANTITY,
        l.DISPLAY_OPERATOR_INSTRUCTION
    FROM wms_to_wcs_order_line_level_pre_staged_data l
    JOIN tmp_parent_orders p
      ON p.PARENT_ORDER_ID = l.PARENT_ORDER_ID
    WHERE IFNULL(l.ORDER_LINE_PROCESS_STATUS,'PENDING') <> 'DELETED';

    SELECT COUNT(*) INTO v_line_cnt FROM tmp_lines;

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_article_list;
    CREATE TEMPORARY TABLE tmp_article_list (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        PRIMARY KEY (ARTICLE_ID)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_article_list (ARTICLE_ID)
    SELECT DISTINCT ARTICLE_ID
    FROM tmp_lines
    WHERE ARTICLE_ID IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
    CREATE TEMPORARY TABLE tmp_line_category (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (ARTICLE_ID),
        KEY (CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_category (ARTICLE_ID, CLIENT_ORDER_TYPE)
    SELECT
        al.ARTICLE_ID,
        COALESCE(NULLIF(cm.CLIENT_ORDER_TYPE,''), 'FOOD') AS CLIENT_ORDER_TYPE
    FROM tmp_article_list al
    LEFT JOIN sku_master sm
      ON sm.SKU_ID = al.ARTICLE_ID
    LEFT JOIN category_master cm
      ON cm.CATEGORY_ID = sm.CATEGORY;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
    CREATE TEMPORARY TABLE tmp_lines_cat (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines_cat
    SELECT
        tl.PARENT_ORDER_ID,
        COALESCE(lc.CLIENT_ORDER_TYPE, 'FOOD') AS CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION
    FROM tmp_lines tl
    LEFT JOIN tmp_line_category lc
      ON lc.ARTICLE_ID = tl.ARTICLE_ID;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_bucket_stats;
    CREATE TEMPORARY TABLE tmp_bucket_stats (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        LINE_CNT INT NOT NULL,
        TOTAL_QTY INT NOT NULL,
        NEED_SPLIT INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_bucket_stats (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, LINE_CNT, TOTAL_QTY, NEED_SPLIT)
    SELECT
        PARENT_ORDER_ID,
        CLIENT_ORDER_TYPE,
        COUNT(*) AS LINE_CNT,
        SUM(QUANTITY) AS TOTAL_QTY,
        CASE
            WHEN COUNT(*) > v_hard_lines OR SUM(QUANTITY) > v_hard_qty THEN 1
            ELSE 0
        END AS NEED_SPLIT
    FROM tmp_lines_cat
    GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_split_all;
    CREATE TEMPORARY TABLE tmp_split_all (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        SPLIT_GROUP INT NOT NULL,
        IS_SUSPENDED_GROUP INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_split_all
    SELECT
        tl.PARENT_ORDER_ID,
        tl.CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION,
        1 AS SPLIT_GROUP,
        0 AS IS_SUSPENDED_GROUP
    FROM tmp_lines_cat tl
    JOIN tmp_bucket_stats bs
      ON bs.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND bs.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
    WHERE bs.NEED_SPLIT = 0;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_need_split;
    CREATE TEMPORARY TABLE tmp_need_split (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_need_split
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE
    FROM tmp_bucket_stats
    WHERE NEED_SPLIT = 1;

    IF (SELECT COUNT(*) FROM tmp_need_split) > 0 THEN

        
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_list;
        CREATE TEMPORARY TABLE tmp_sku_list (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ARTICLE_ID, BATCH_ID),
            KEY (ARTICLE_ID, BATCH_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_sku_list
        SELECT DISTINCT tl.PARENT_ORDER_ID, tl.CLIENT_ORDER_TYPE, tl.ARTICLE_ID, tl.BATCH_ID
        FROM tmp_lines_cat tl
        JOIN tmp_need_split ns
          ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND ns.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
        WHERE tl.ARTICLE_ID IS NOT NULL AND tl.BATCH_ID IS NOT NULL;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
        CREATE TEMPORARY TABLE tmp_sku_global (
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            PRIMARY KEY (ARTICLE_ID, BATCH_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_sku_global
        SELECT DISTINCT ARTICLE_ID, BATCH_ID
        FROM tmp_sku_list;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
        CREATE TEMPORARY TABLE tmp_inv_bin (
            BIN_ID INT NOT NULL,
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            AVAIL_QTY  INT NOT NULL,
            LAST_TS    DATETIME(3) NULL,
            PRIMARY KEY (BIN_ID, ARTICLE_ID, BATCH_ID),
            KEY (ARTICLE_ID, BATCH_ID),
            KEY (BIN_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_inv_bin
        SELECT
            lim.BIN_ID,
            lim.ARTICLE_ID,
            lim.BATCH_ID,
            CAST(SUM(GREATEST(lim.QUANTITY - lim.VIRTUAL_QUANTITY_TO_PICK, 0)) AS SIGNED) AS AVAIL_QTY,
            MAX(lim.UPDATED_TIMESTAMP) AS LAST_TS
        FROM live_inventory_master lim
        JOIN tmp_sku_global sg
          ON sg.ARTICLE_ID = lim.ARTICLE_ID
         AND sg.BATCH_ID   = lim.BATCH_ID
        WHERE lim.IS_ACTIVE = 1
        GROUP BY lim.BIN_ID, lim.ARTICLE_ID, lim.BATCH_ID
        HAVING AVAIL_QTY > 0;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_bin_hits;
        CREATE TEMPORARY TABLE tmp_bin_hits (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            BIN_ID INT NOT NULL,
            HIT_CNT INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, BIN_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_bin_hits
        SELECT
            s.PARENT_ORDER_ID,
            s.CLIENT_ORDER_TYPE,
            ib.BIN_ID,
            COUNT(*) AS HIT_CNT
        FROM tmp_sku_list s
        JOIN tmp_inv_bin ib
          ON ib.ARTICLE_ID = s.ARTICLE_ID
         AND ib.BATCH_ID   = s.BATCH_ID
        GROUP BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE, ib.BIN_ID;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_line_metrics;
        CREATE TEMPORARY TABLE tmp_line_metrics (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ORDER_LINE_ID VARCHAR(36) NOT NULL,
            DOMINANT_BIN_ID INT NULL,
            DOMINANT_HIT_CNT INT NOT NULL,
            TOTAL_AVAIL INT NOT NULL,
            REQ_QTY INT NOT NULL,
            SHORT_FLAG INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_line_metrics
        WITH candidate_bins AS (
            SELECT
                tl.PARENT_ORDER_ID,
                tl.CLIENT_ORDER_TYPE,
                tl.ORDER_LINE_ID,
                tl.QUANTITY AS REQ_QTY,
                ib.BIN_ID,
                COALESCE(bh.HIT_CNT,0) AS HIT_CNT,
                ib.AVAIL_QTY,
                ib.LAST_TS,
                ROW_NUMBER() OVER (
                    PARTITION BY tl.PARENT_ORDER_ID, tl.CLIENT_ORDER_TYPE, tl.ORDER_LINE_ID
                    ORDER BY COALESCE(bh.HIT_CNT,0) DESC, ib.AVAIL_QTY DESC, ib.LAST_TS DESC, ib.BIN_ID
                ) AS rn,
                SUM(ib.AVAIL_QTY) OVER (
                    PARTITION BY tl.PARENT_ORDER_ID, tl.CLIENT_ORDER_TYPE, tl.ORDER_LINE_ID
                ) AS total_avail
            FROM tmp_lines_cat tl
            JOIN tmp_need_split ns
              ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
             AND ns.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
            JOIN tmp_inv_bin ib
              ON ib.ARTICLE_ID = tl.ARTICLE_ID AND ib.BATCH_ID = tl.BATCH_ID
            LEFT JOIN tmp_bin_hits bh
              ON bh.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
             AND bh.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
             AND bh.BIN_ID = ib.BIN_ID
        )
        SELECT
            cb.PARENT_ORDER_ID,
            cb.CLIENT_ORDER_TYPE,
            cb.ORDER_LINE_ID,
            MAX(CASE WHEN cb.rn = 1 THEN cb.BIN_ID END)  AS DOMINANT_BIN_ID,
            MAX(CASE WHEN cb.rn = 1 THEN cb.HIT_CNT END) AS DOMINANT_HIT_CNT,
            MAX(cb.total_avail) AS TOTAL_AVAIL,
            MAX(cb.REQ_QTY)     AS REQ_QTY,
            CASE WHEN MAX(cb.total_avail) < MAX(cb.REQ_QTY) THEN 1 ELSE 0 END AS SHORT_FLAG
        FROM candidate_bins cb
        GROUP BY cb.PARENT_ORDER_ID, cb.CLIENT_ORDER_TYPE, cb.ORDER_LINE_ID;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_lines_enriched;
        CREATE TEMPORARY TABLE tmp_lines_enriched (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
            ARTICLE_ID      VARCHAR(200) NULL,
            BATCH_ID        VARCHAR(200) NULL,
            QUANTITY        INT NOT NULL,
            DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
            DOMINANT_BIN_ID INT NULL,
            DOMINANT_HIT_CNT INT NOT NULL,
            SHORT_FLAG INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
            KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
            KEY (DOMINANT_BIN_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_lines_enriched
        SELECT
            tl.PARENT_ORDER_ID,
            tl.CLIENT_ORDER_TYPE,
            tl.ORDER_LINE_ID,
            tl.ARTICLE_ID,
            tl.BATCH_ID,
            tl.QUANTITY,
            tl.DISPLAY_OPERATOR_INSTRUCTION,
            lm.DOMINANT_BIN_ID,
            COALESCE(lm.DOMINANT_HIT_CNT,0) AS DOMINANT_HIT_CNT,
            COALESCE(lm.SHORT_FLAG,1) AS SHORT_FLAG
        FROM tmp_lines_cat tl
        JOIN tmp_need_split ns
          ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND ns.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
        LEFT JOIN tmp_line_metrics lm
          ON lm.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND lm.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
         AND lm.ORDER_LINE_ID   = tl.ORDER_LINE_ID;

        IF v_suspend_short_lines = 0 THEN
            UPDATE tmp_lines_enriched
               SET SHORT_FLAG = 0;
        END IF;

        SELECT COUNT(*) INTO v_short_cnt
        FROM tmp_lines_enriched
        WHERE SHORT_FLAG = 1;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_norm_plan;
        CREATE TEMPORARY TABLE tmp_norm_plan (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            LINE_CNT INT NOT NULL,
            TOTAL_QTY INT NOT NULL,
            GRP_CNT INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
        ) ENGINE=INNODB;

        
        INSERT INTO tmp_norm_plan
        SELECT
            PARENT_ORDER_ID,
            CLIENT_ORDER_TYPE,
            COUNT(*) AS LINE_CNT,
            SUM(QUANTITY) AS TOTAL_QTY,
            CASE
                WHEN ((COUNT(*) + v_max_lines - 1) DIV v_max_lines) >= ((SUM(QUANTITY) + v_max_qty - 1) DIV v_max_qty)
                    THEN ((COUNT(*) + v_max_lines - 1) DIV v_max_lines)
                ELSE ((SUM(QUANTITY) + v_max_qty - 1) DIV v_max_qty)
            END AS GRP_CNT
        FROM tmp_lines_enriched
        WHERE SHORT_FLAG = 0
        GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_ranked_normal;
        CREATE TEMPORARY TABLE tmp_ranked_normal (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
            ARTICLE_ID      VARCHAR(200) NULL,
            BATCH_ID        VARCHAR(200) NULL,
            QUANTITY        INT NOT NULL,
            DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
            rn INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
            KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, rn)
        ) ENGINE=INNODB;

        INSERT INTO tmp_ranked_normal
        SELECT
            tle.PARENT_ORDER_ID,
            tle.CLIENT_ORDER_TYPE,
            tle.ORDER_LINE_ID,
            tle.ARTICLE_ID,
            tle.BATCH_ID,
            tle.QUANTITY,
            tle.DISPLAY_OPERATOR_INSTRUCTION,
            ROW_NUMBER() OVER (
                PARTITION BY tle.PARENT_ORDER_ID, tle.CLIENT_ORDER_TYPE
                ORDER BY
                    COALESCE(tle.DOMINANT_BIN_ID, 2147483647),
                    tle.DOMINANT_HIT_CNT DESC,
                    tle.QUANTITY DESC,
                    tle.ORDER_LINE_ID
            ) AS rn
        FROM tmp_lines_enriched tle
        WHERE tle.SHORT_FLAG = 0;

        
        INSERT INTO tmp_split_all
        SELECT
            r.PARENT_ORDER_ID,
            r.CLIENT_ORDER_TYPE,
            r.ORDER_LINE_ID,
            r.ARTICLE_ID,
            r.BATCH_ID,
            r.QUANTITY,
            r.DISPLAY_OPERATOR_INSTRUCTION,
            1 + ((r.rn - 1) * p.GRP_CNT) DIV p.LINE_CNT AS SPLIT_GROUP,
            0 AS IS_SUSPENDED_GROUP
        FROM tmp_ranked_normal r
        JOIN tmp_norm_plan p
          ON p.PARENT_ORDER_ID = r.PARENT_ORDER_ID
         AND p.CLIENT_ORDER_TYPE = r.CLIENT_ORDER_TYPE;

        
        IF v_suspend_short_lines = 1 THEN

            DROP TEMPORARY TABLE IF EXISTS tmp_short_plan;
            CREATE TEMPORARY TABLE tmp_short_plan (
                PARENT_ORDER_ID VARCHAR(100) NOT NULL,
                CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
                LINE_CNT INT NOT NULL,
                TOTAL_QTY INT NOT NULL,
                GRP_CNT INT NOT NULL,
                OFFSET_G INT NOT NULL,
                PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
            ) ENGINE=INNODB;

            
            INSERT INTO tmp_short_plan
            SELECT
                s.PARENT_ORDER_ID,
                s.CLIENT_ORDER_TYPE,
                COUNT(*) AS LINE_CNT,
                SUM(s.QUANTITY) AS TOTAL_QTY,
                CASE
                    WHEN ((COUNT(*) + v_max_lines - 1) DIV v_max_lines) >= ((SUM(s.QUANTITY) + v_max_qty - 1) DIV v_max_qty)
                        THEN ((COUNT(*) + v_max_lines - 1) DIV v_max_lines)
                    ELSE ((SUM(s.QUANTITY) + v_max_qty - 1) DIV v_max_qty)
                END AS GRP_CNT,
                COALESCE(n.GRP_CNT, 0) AS OFFSET_G
            FROM tmp_lines_enriched s
            LEFT JOIN tmp_norm_plan n
              ON n.PARENT_ORDER_ID = s.PARENT_ORDER_ID
             AND n.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
            WHERE s.SHORT_FLAG = 1
            GROUP BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE;

            DROP TEMPORARY TABLE IF EXISTS tmp_ranked_short;
            CREATE TEMPORARY TABLE tmp_ranked_short (
                PARENT_ORDER_ID VARCHAR(100) NOT NULL,
                CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
                ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
                ARTICLE_ID      VARCHAR(200) NULL,
                BATCH_ID        VARCHAR(200) NULL,
                QUANTITY        INT NOT NULL,
                DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
                rn INT NOT NULL,
                PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
                KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, rn)
            ) ENGINE=INNODB;

            INSERT INTO tmp_ranked_short
            SELECT
                tle.PARENT_ORDER_ID,
                tle.CLIENT_ORDER_TYPE,
                tle.ORDER_LINE_ID,
                tle.ARTICLE_ID,
                tle.BATCH_ID,
                tle.QUANTITY,
                tle.DISPLAY_OPERATOR_INSTRUCTION,
                ROW_NUMBER() OVER (
                    PARTITION BY tle.PARENT_ORDER_ID, tle.CLIENT_ORDER_TYPE
                    ORDER BY tle.QUANTITY DESC, tle.ORDER_LINE_ID
                ) AS rn
            FROM tmp_lines_enriched tle
            WHERE tle.SHORT_FLAG = 1;

            INSERT INTO tmp_split_all
            SELECT
                r.PARENT_ORDER_ID,
                r.CLIENT_ORDER_TYPE,
                r.ORDER_LINE_ID,
                r.ARTICLE_ID,
                r.BATCH_ID,
                r.QUANTITY,
                r.DISPLAY_OPERATOR_INSTRUCTION,
                sp.OFFSET_G + (1 + ((r.rn - 1) * sp.GRP_CNT) DIV sp.LINE_CNT) AS SPLIT_GROUP,
                1 AS IS_SUSPENDED_GROUP
            FROM tmp_ranked_short r
            JOIN tmp_short_plan sp
              ON sp.PARENT_ORDER_ID = r.PARENT_ORDER_ID
             AND sp.CLIENT_ORDER_TYPE = r.CLIENT_ORDER_TYPE;

        END IF;

    END IF;

    

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_pre_lines, v_pre_qty
    FROM tmp_lines;

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_post_lines, v_post_qty
    FROM tmp_split_all;

    IF v_pre_lines <> v_post_lines OR v_pre_qty <> v_post_qty THEN
        SET v_errmsg = CONCAT(
            'SPLIT_VALIDATION_FAILED: PRE_LINES=', v_pre_lines,
            ', POST_LINES=', v_post_lines,
            ', PRE_QTY=', v_pre_qty,
            ', POST_QTY=', v_post_qty
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    
    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_lines tl
    LEFT JOIN tmp_split_all sa
      ON sa.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND sa.ORDER_LINE_ID   = tl.ORDER_LINE_ID
    WHERE sa.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('SPLIT_VALIDATION_FAILED: MISSING_LINES=', v_missing_lines);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
    CREATE TEMPORARY TABLE tmp_cat_seq (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        CAT_SEQ INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
        KEY (PARENT_ORDER_ID, CAT_SEQ)
    ) ENGINE=INNODB;

    INSERT INTO tmp_cat_seq (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CAT_SEQ)
    SELECT
        x.PARENT_ORDER_ID,
        x.CLIENT_ORDER_TYPE,
        ROW_NUMBER() OVER (PARTITION BY x.PARENT_ORDER_ID ORDER BY x.CLIENT_ORDER_TYPE) AS CAT_SEQ
    FROM (
        SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE
        FROM tmp_lines_cat
    ) X;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_bucket_groupmax;
    CREATE TEMPORARY TABLE tmp_bucket_groupmax (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        MAX_GRP INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_bucket_groupmax
    SELECT
        PARENT_ORDER_ID,
        CLIENT_ORDER_TYPE,
        MAX(SPLIT_GROUP) AS MAX_GRP
    FROM tmp_split_all
    GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;

    DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
    CREATE TEMPORARY TABLE tmp_child_orders (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        CAT_SEQ INT NOT NULL,
        SPLIT_GROUP INT NOT NULL,
        CHILD_ORDER_ID VARCHAR(100) NOT NULL,
        CHILD_STATUS ENUM('PENDING','ORDER_SUSPENDED') NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP),
        KEY (CHILD_ORDER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_child_orders
    SELECT
        sa.PARENT_ORDER_ID,
        sa.CLIENT_ORDER_TYPE,
        cs.CAT_SEQ,
        sa.SPLIT_GROUP,
        CASE
            WHEN bg.MAX_GRP = 1
                THEN CONCAT(sa.PARENT_ORDER_ID, '-', cs.CAT_SEQ)
            ELSE CONCAT(sa.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', LPAD(sa.SPLIT_GROUP, 3, '0'))
        END AS CHILD_ORDER_ID,
        CASE WHEN MAX(sa.IS_SUSPENDED_GROUP) = 1 THEN 'ORDER_SUSPENDED' ELSE 'PENDING' END AS CHILD_STATUS
    FROM tmp_split_all sa
    JOIN tmp_cat_seq cs
      ON cs.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND cs.CLIENT_ORDER_TYPE = sa.CLIENT_ORDER_TYPE
    JOIN tmp_bucket_groupmax bg
      ON bg.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND bg.CLIENT_ORDER_TYPE = sa.CLIENT_ORDER_TYPE
    GROUP BY sa.PARENT_ORDER_ID, sa.CLIENT_ORDER_TYPE, cs.CAT_SEQ, sa.SPLIT_GROUP, bg.MAX_GRP;

    START TRANSACTION;

    
    INSERT INTO wms_to_wcs_order_request_data
        (PARENT_ORDER_ID, ORDER_TYPE, ORDER_ID, ORDER_REQUEST_STATUS, INSERTED_TIMESTAMP, INSERTED_BY)
    SELECT
        co.PARENT_ORDER_ID,
        co.CLIENT_ORDER_TYPE,
        co.CHILD_ORDER_ID,
        co.CHILD_STATUS,
        CURRENT_TIMESTAMP(3),
        'BACKEND-SERVICE'
    FROM tmp_child_orders co
    WHERE NOT EXISTS (
        SELECT 1
        FROM wms_to_wcs_order_request_data r
        WHERE r.ORDER_ID = co.CHILD_ORDER_ID
    );

    SELECT COUNT(*) INTO v_child_cnt FROM tmp_child_orders;

    
    INSERT INTO wms_to_wcs_order_line_request_data
        (WMS_ORDER_REQUEST_DATA_ID, ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, BATCH_ID,
         DISPLAY_OPERATOR_INSTRUCTION, ORDER_LINE_PROCESS_STATUS, INSERTED_TIMESTAMP, INSERTED_BY)
    SELECT
        r.WMS_ORDER_REQUEST_DATA_ID,
        r.ORDER_ID,
        sa.ORDER_LINE_ID,
        sa.ARTICLE_ID,
        sa.QUANTITY,
        sa.BATCH_ID,
        sa.DISPLAY_OPERATOR_INSTRUCTION,
        'PENDING',
        CURRENT_TIMESTAMP(3),
        'BACKEND-SERVICE'
    FROM tmp_split_all sa
    JOIN tmp_child_orders co
      ON co.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND co.CLIENT_ORDER_TYPE = sa.CLIENT_ORDER_TYPE
     AND co.SPLIT_GROUP     = sa.SPLIT_GROUP
    JOIN wms_to_wcs_order_request_data r
      ON r.ORDER_ID = co.CHILD_ORDER_ID
    WHERE NOT EXISTS (
        SELECT 1
        FROM wms_to_wcs_order_line_request_data lr
        WHERE lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID
          AND lr.ORDER_LINE_ID = sa.ORDER_LINE_ID
    );

    
    UPDATE wms_to_wcs_order_level_pre_staged_data p
    JOIN tmp_parent_orders t
      ON t.PRE_STAGED_REQ_ID = p.WMS_ORDER_REQUEST_DATA_ID
    SET p.IS_STAGED = 1,
        p.UPDATED_TIMESTAMP = CURRENT_TIMESTAMP(3),
        p.UPDATED_BY = 'SPLIT-OPS-V4';

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='2',
           ORDERSPLIT_ENDTIME = NOW(),
           RULE_STATS = JSON_OBJECT(
            'RULE_ID', v_rule_id,
            'PARENTS_FOUND', v_parent_cnt,
            'LINES_CONSIDERED', v_line_cnt,
            'CHILD_ORDERS_CREATED', v_child_cnt,
            'SHORT_LINES_FLAGGED', v_short_cnt,
            'MAX_ORDER_LINES_PER_ORDER', v_max_lines,
            'MAX_QUANTITY_PER_ORDER', v_max_qty,
            'TOL_LINES', v_tol_lines,
            'TOL_QTY', v_tol_qty,
            'HARD_LINES', v_hard_lines,
            'HARD_QTY', v_hard_qty,
            'SUSPEND_SHORT_LINES', v_suspend_short_lines,
            'CATEGORY_DEFAULT', 'FOOD',
            'GROUP_CNT_RULE', 'MAX(ceil(lines/limit), ceil(qty/limit))'
        )
     WHERE ID = v_ruleLog_id;

    COMMIT;

    DO RELEASE_LOCK(CONCAT('SPLIT_', v_rule_id));

    
    SELECT
        v_rule_id AS RULE_ID,
        v_parent_cnt AS PARENTS_PROCESSED,
        v_line_cnt   AS LINES_CONSIDERED,
        v_child_cnt  AS CHILD_ORDERS_CREATED,
        v_short_cnt  AS SHORT_LINES_FLAGGED,
        v_max_lines  AS MAX_ORDER_LINES,
        v_max_qty    AS MAX_ORDER_QTY,
        v_tol_lines  AS TOL_LINES,
        v_tol_qty    AS TOL_QTY,
        v_hard_lines AS HARD_LINES,
        v_hard_qty   AS HARD_QTY,
        v_suspend_short_lines AS SUSPEND_SHORT_LINES;

END sp_main */$$
DELIMITER ;

/* Procedure structure for procedure `sp_split_orders_ops_v5_12012026` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_split_orders_ops_v5_12012026` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sp_split_orders_ops_v5_12012026`()
sp_main: BEGIN

    

    
    DECLARE v_max_lines INT DEFAULT 50;
    DECLARE v_max_qty   INT DEFAULT 500;

    
    DECLARE v_tol_lines INT DEFAULT 10;
    DECLARE v_tol_qty   INT DEFAULT 100;

    
    DECLARE v_hard_lines INT DEFAULT 60;
    DECLARE v_hard_qty   INT DEFAULT 600;

    
    DECLARE v_suspend_short_lines INT DEFAULT 0;

    
    DECLARE v_rule_id INT DEFAULT NULL;
    DECLARE v_ruleLog_id INT DEFAULT NULL;
    DECLARE v_rule_defination TEXT;

    
    DECLARE v_lock_ok INT DEFAULT 0;

    
    DECLARE v_parent_cnt INT DEFAULT 0;
    DECLARE v_line_cnt   INT DEFAULT 0;
    DECLARE v_child_cnt  INT DEFAULT 0;
    DECLARE v_short_cnt  INT DEFAULT 0;

    
    DECLARE v_batch_quoted TEXT;

    
    DECLARE v_pre_lines INT DEFAULT 0;
    DECLARE v_post_lines INT DEFAULT 0;
    DECLARE v_missing_lines INT DEFAULT 0;
    DECLARE v_pre_qty BIGINT DEFAULT 0;
    DECLARE v_post_qty BIGINT DEFAULT 0;
    DECLARE v_errmsg TEXT DEFAULT '';

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        
        IF v_lock_ok = 1 AND v_rule_id IS NOT NULL THEN
            DO RELEASE_LOCK(CONCAT('SPLIT_', v_rule_id));
        END IF;
        RESIGNAL;
    END;

    
    SET v_max_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_ORDER_LINES_PER_ORDER'
            AND IS_ACTIVE = 1
          LIMIT 1),
        50
    );

    SET v_max_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_QUANTITY_PER_ORDER'
            AND IS_ACTIVE = 1
          LIMIT 1),
        500
    );

    SET v_tol_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_LINES'
            AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_lines
    );

    SET v_tol_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_QTY'
            AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_qty
    );

    SET v_suspend_short_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'SUSPEND_SHORT_LINES'
            AND IS_ACTIVE = 1
          LIMIT 1),
        0
    );

    SET v_hard_lines = v_max_lines + v_tol_lines;
    SET v_hard_qty   = v_max_qty   + v_tol_qty;

    
    SELECT ID, RULE_ID
      INTO v_ruleLog_id, v_rule_id
    FROM picklist_split_order_master
    WHERE IS_PROCESSED='0'
    ORDER BY ID
    LIMIT 1;

    IF v_rule_id IS NULL THEN
        SELECT 'NO_RULE_TO_PROCESS' AS STATUS;
        LEAVE sp_main;
    END IF;

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='1',
           ORDERSPLIT_STARTTIME = NOW()
     WHERE ID = v_ruleLog_id;

    SELECT FILTER_CONDITION
      INTO v_rule_defination
    FROM pick_rule_master
    WHERE PICK_RULE_ID = v_rule_id
    ORDER BY PICK_RULE_ID
    LIMIT 1;

    IF v_rule_defination IS NULL OR LENGTH(v_rule_defination) < 3 THEN
        UPDATE picklist_split_order_master
           SET IS_PROCESSED='2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        SELECT 'NO_RULE_DEFINITION_FOUND' AS STATUS, v_rule_id AS RULE_ID;
        LEAVE sp_main;
    END IF;

    
    SET v_rule_defination = LEFT(v_rule_defination, LENGTH(v_rule_defination)-1);

    
    SELECT GET_LOCK(CONCAT('SPLIT_', v_rule_id), 2) INTO v_lock_ok;
    IF v_lock_ok <> 1 THEN
        SET v_errmsg = CONCAT('Split job already running for RULE_ID=', v_rule_id);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
    CREATE TEMPORARY TABLE tmp_parent_orders (
        PRE_STAGED_REQ_ID BIGINT NOT NULL,
        PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
        ORDER_TYPE        VARCHAR(100) NOT NULL,
        PRIMARY KEY (PRE_STAGED_REQ_ID),
        KEY (PARENT_ORDER_ID)
    ) ENGINE=INNODB;

    
    SET @sql = CONCAT(
        'INSERT INTO tmp_parent_orders (PRE_STAGED_REQ_ID, PARENT_ORDER_ID, ORDER_TYPE)
         SELECT WMS_ORDER_REQUEST_DATA_ID,
                PARENT_ORDER_ID,
                COALESCE(NULLIF(PICKING_TYPE,''''), NULLIF(ORDER_CATEGORY,''''), ''PICK'') AS ORDER_TYPE
           FROM wms_to_wcs_order_level_pre_staged_data
          WHERE IFNULL(IS_STAGED,0) = 0
            AND PARENT_ORDER_ID IN (', v_rule_defination, ')'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    SELECT COUNT(*) INTO v_parent_cnt FROM tmp_parent_orders;

    IF v_parent_cnt = 0 THEN
        DO RELEASE_LOCK(CONCAT('SPLIT_', v_rule_id));

        UPDATE picklist_split_order_master
           SET IS_PROCESSED='2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        SELECT
            NULL AS BATCH_PICKLIST_CODE,
            'NO_PARENTS_TO_SPLIT' AS STATUS,
            v_max_lines AS MAX_ORDER_LINES_PER_ORDER,
            v_max_qty   AS MAX_QUANTITY_PER_ORDER,
            v_tol_lines AS TOL_LINES,
            v_tol_qty   AS TOL_QTY;
        LEAVE sp_main;
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_lines;
    CREATE TEMPORARY TABLE tmp_lines (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines
    SELECT
        l.PARENT_ORDER_ID,
        l.ORDER_LINE_ID,
        l.ARTICLE_ID,
        l.BATCH_ID,
        l.QUANTITY,
        l.DISPLAY_OPERATOR_INSTRUCTION
    FROM wms_to_wcs_order_line_level_pre_staged_data l
    JOIN tmp_parent_orders p
      ON p.PARENT_ORDER_ID = l.PARENT_ORDER_ID
    WHERE IFNULL(l.ORDER_LINE_PROCESS_STATUS,'PENDING') <> 'DELETED';

    SELECT COUNT(*) INTO v_line_cnt FROM tmp_lines;

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_article_list;
    CREATE TEMPORARY TABLE tmp_article_list (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        PRIMARY KEY (ARTICLE_ID)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_article_list (ARTICLE_ID)
    SELECT DISTINCT ARTICLE_ID
    FROM tmp_lines
    WHERE ARTICLE_ID IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
    CREATE TEMPORARY TABLE tmp_line_category (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (ARTICLE_ID),
        KEY (CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_category (ARTICLE_ID, CLIENT_ORDER_TYPE)
    SELECT
        al.ARTICLE_ID,
        COALESCE(NULLIF(cm.CLIENT_ORDER_TYPE,''), 'FOOD') AS CLIENT_ORDER_TYPE
    FROM tmp_article_list al
    LEFT JOIN sku_master sm
      ON sm.SKU_ID = al.ARTICLE_ID
    LEFT JOIN category_master cm
      ON cm.CATEGORY_ID = sm.CATEGORY;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
    CREATE TEMPORARY TABLE tmp_lines_cat (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines_cat
    SELECT
        tl.PARENT_ORDER_ID,
        COALESCE(lc.CLIENT_ORDER_TYPE, 'FOOD') AS CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION
    FROM tmp_lines tl
    LEFT JOIN tmp_line_category lc
      ON lc.ARTICLE_ID = tl.ARTICLE_ID;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_bucket_stats;
    CREATE TEMPORARY TABLE tmp_bucket_stats (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        LINE_CNT INT NOT NULL,
        TOTAL_QTY INT NOT NULL,
        NEED_SPLIT INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_bucket_stats (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, LINE_CNT, TOTAL_QTY, NEED_SPLIT)
    SELECT
        PARENT_ORDER_ID,
        CLIENT_ORDER_TYPE,
        COUNT(*) AS LINE_CNT,
        SUM(QUANTITY) AS TOTAL_QTY,
        CASE
            WHEN COUNT(*) > v_hard_lines OR SUM(QUANTITY) > v_hard_qty THEN 1
            ELSE 0
        END AS NEED_SPLIT
    FROM tmp_lines_cat
    GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_split_all;
    CREATE TEMPORARY TABLE tmp_split_all (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        SPLIT_GROUP INT NOT NULL,
        IS_SUSPENDED_GROUP INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_split_all
    SELECT
        tl.PARENT_ORDER_ID,
        tl.CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION,
        1 AS SPLIT_GROUP,
        0 AS IS_SUSPENDED_GROUP
    FROM tmp_lines_cat tl
    JOIN tmp_bucket_stats bs
      ON bs.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND bs.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
    WHERE bs.NEED_SPLIT = 0;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_need_split;
    CREATE TEMPORARY TABLE tmp_need_split (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_need_split
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE
    FROM tmp_bucket_stats
    WHERE NEED_SPLIT = 1;

    IF (SELECT COUNT(*) FROM tmp_need_split) > 0 THEN

        
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_list;
        CREATE TEMPORARY TABLE tmp_sku_list (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ARTICLE_ID, BATCH_ID),
            KEY (ARTICLE_ID, BATCH_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_sku_list
        SELECT DISTINCT tl.PARENT_ORDER_ID, tl.CLIENT_ORDER_TYPE, tl.ARTICLE_ID, tl.BATCH_ID
        FROM tmp_lines_cat tl
        JOIN tmp_need_split ns
          ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND ns.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
        WHERE tl.ARTICLE_ID IS NOT NULL AND tl.BATCH_ID IS NOT NULL;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
        CREATE TEMPORARY TABLE tmp_sku_global (
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            PRIMARY KEY (ARTICLE_ID, BATCH_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_sku_global
        SELECT DISTINCT ARTICLE_ID, BATCH_ID
        FROM tmp_sku_list;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
        CREATE TEMPORARY TABLE tmp_inv_bin (
            BIN_ID INT NOT NULL,
            ARTICLE_ID VARCHAR(200) NOT NULL,
            BATCH_ID   VARCHAR(200) NOT NULL,
            AVAIL_QTY  INT NOT NULL,
            LAST_TS    DATETIME(3) NULL,
            PRIMARY KEY (BIN_ID, ARTICLE_ID, BATCH_ID),
            KEY (ARTICLE_ID, BATCH_ID),
            KEY (BIN_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_inv_bin
        SELECT
            lim.BIN_ID,
            lim.ARTICLE_ID,
            lim.BATCH_ID,
            CAST(SUM(GREATEST(lim.QUANTITY - lim.VIRTUAL_QUANTITY_TO_PICK, 0)) AS SIGNED) AS AVAIL_QTY,
            MAX(lim.UPDATED_TIMESTAMP) AS LAST_TS
        FROM live_inventory_master lim
        JOIN tmp_sku_global sg
          ON sg.ARTICLE_ID = lim.ARTICLE_ID
         AND sg.BATCH_ID   = lim.BATCH_ID
        WHERE lim.IS_ACTIVE = 1
        GROUP BY lim.BIN_ID, lim.ARTICLE_ID, lim.BATCH_ID
        HAVING AVAIL_QTY > 0;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_bin_hits;
        CREATE TEMPORARY TABLE tmp_bin_hits (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            BIN_ID INT NOT NULL,
            HIT_CNT INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, BIN_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_bin_hits
        SELECT
            s.PARENT_ORDER_ID,
            s.CLIENT_ORDER_TYPE,
            ib.BIN_ID,
            COUNT(*) AS HIT_CNT
        FROM tmp_sku_list s
        JOIN tmp_inv_bin ib
          ON ib.ARTICLE_ID = s.ARTICLE_ID
         AND ib.BATCH_ID   = s.BATCH_ID
        GROUP BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE, ib.BIN_ID;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_line_metrics;
        CREATE TEMPORARY TABLE tmp_line_metrics (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ORDER_LINE_ID VARCHAR(36) NOT NULL,
            DOMINANT_BIN_ID INT NULL,
            DOMINANT_HIT_CNT INT NOT NULL,
            TOTAL_AVAIL INT NOT NULL,
            REQ_QTY INT NOT NULL,
            SHORT_FLAG INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_line_metrics
        WITH candidate_bins AS (
            SELECT
                tl.PARENT_ORDER_ID,
                tl.CLIENT_ORDER_TYPE,
                tl.ORDER_LINE_ID,
                tl.QUANTITY AS REQ_QTY,
                ib.BIN_ID,
                COALESCE(bh.HIT_CNT,0) AS HIT_CNT,
                ib.AVAIL_QTY,
                ib.LAST_TS,
                ROW_NUMBER() OVER (
                    PARTITION BY tl.PARENT_ORDER_ID, tl.CLIENT_ORDER_TYPE, tl.ORDER_LINE_ID
                    ORDER BY COALESCE(bh.HIT_CNT,0) DESC, ib.AVAIL_QTY DESC, ib.LAST_TS DESC, ib.BIN_ID
                ) AS rn,
                SUM(ib.AVAIL_QTY) OVER (
                    PARTITION BY tl.PARENT_ORDER_ID, tl.CLIENT_ORDER_TYPE, tl.ORDER_LINE_ID
                ) AS total_avail
            FROM tmp_lines_cat tl
            JOIN tmp_need_split ns
              ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
             AND ns.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
            JOIN tmp_inv_bin ib
              ON ib.ARTICLE_ID = tl.ARTICLE_ID AND ib.BATCH_ID = tl.BATCH_ID
            LEFT JOIN tmp_bin_hits bh
              ON bh.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
             AND bh.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
             AND bh.BIN_ID = ib.BIN_ID
        )
        SELECT
            cb.PARENT_ORDER_ID,
            cb.CLIENT_ORDER_TYPE,
            cb.ORDER_LINE_ID,
            MAX(CASE WHEN cb.rn = 1 THEN cb.BIN_ID END)  AS DOMINANT_BIN_ID,
            MAX(CASE WHEN cb.rn = 1 THEN cb.HIT_CNT END) AS DOMINANT_HIT_CNT,
            MAX(cb.total_avail) AS TOTAL_AVAIL,
            MAX(cb.REQ_QTY)     AS REQ_QTY,
            CASE WHEN MAX(cb.total_avail) < MAX(cb.REQ_QTY) THEN 1 ELSE 0 END AS SHORT_FLAG
        FROM candidate_bins cb
        GROUP BY cb.PARENT_ORDER_ID, cb.CLIENT_ORDER_TYPE, cb.ORDER_LINE_ID;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_lines_enriched;
        CREATE TEMPORARY TABLE tmp_lines_enriched (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
            ARTICLE_ID      VARCHAR(200) NULL,
            BATCH_ID        VARCHAR(200) NULL,
            QUANTITY        INT NOT NULL,
            DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
            DOMINANT_BIN_ID INT NULL,
            DOMINANT_HIT_CNT INT NOT NULL,
            SHORT_FLAG INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
            KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
            KEY (DOMINANT_BIN_ID)
        ) ENGINE=INNODB;

        INSERT INTO tmp_lines_enriched
        SELECT
            tl.PARENT_ORDER_ID,
            tl.CLIENT_ORDER_TYPE,
            tl.ORDER_LINE_ID,
            tl.ARTICLE_ID,
            tl.BATCH_ID,
            tl.QUANTITY,
            tl.DISPLAY_OPERATOR_INSTRUCTION,
            lm.DOMINANT_BIN_ID,
            COALESCE(lm.DOMINANT_HIT_CNT,0) AS DOMINANT_HIT_CNT,
            COALESCE(lm.SHORT_FLAG,1) AS SHORT_FLAG
        FROM tmp_lines_cat tl
        JOIN tmp_need_split ns
          ON ns.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND ns.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
        LEFT JOIN tmp_line_metrics lm
          ON lm.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
         AND lm.CLIENT_ORDER_TYPE = tl.CLIENT_ORDER_TYPE
         AND lm.ORDER_LINE_ID   = tl.ORDER_LINE_ID;

        IF v_suspend_short_lines = 0 THEN
            UPDATE tmp_lines_enriched
               SET SHORT_FLAG = 0;
        END IF;

        SELECT COUNT(*) INTO v_short_cnt
        FROM tmp_lines_enriched
        WHERE SHORT_FLAG = 1;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_norm_plan;
        CREATE TEMPORARY TABLE tmp_norm_plan (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            LINE_CNT INT NOT NULL,
            TOTAL_QTY INT NOT NULL,
            GRP_CNT INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
        ) ENGINE=INNODB;

        
        INSERT INTO tmp_norm_plan
        SELECT
            PARENT_ORDER_ID,
            CLIENT_ORDER_TYPE,
            COUNT(*) AS LINE_CNT,
            SUM(QUANTITY) AS TOTAL_QTY,
            CASE
                WHEN ((COUNT(*) + v_max_lines - 1) DIV v_max_lines) >= ((SUM(QUANTITY) + v_max_qty - 1) DIV v_max_qty)
                    THEN ((COUNT(*) + v_max_lines - 1) DIV v_max_lines)
                ELSE ((SUM(QUANTITY) + v_max_qty - 1) DIV v_max_qty)
            END AS GRP_CNT
        FROM tmp_lines_enriched
        WHERE SHORT_FLAG = 0
        GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;

        
        DROP TEMPORARY TABLE IF EXISTS tmp_ranked_normal;
        CREATE TEMPORARY TABLE tmp_ranked_normal (
            PARENT_ORDER_ID VARCHAR(100) NOT NULL,
            CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
            ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
            ARTICLE_ID      VARCHAR(200) NULL,
            BATCH_ID        VARCHAR(200) NULL,
            QUANTITY        INT NOT NULL,
            DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
            rn INT NOT NULL,
            PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
            KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, rn)
        ) ENGINE=INNODB;

        INSERT INTO tmp_ranked_normal
        SELECT
            tle.PARENT_ORDER_ID,
            tle.CLIENT_ORDER_TYPE,
            tle.ORDER_LINE_ID,
            tle.ARTICLE_ID,
            tle.BATCH_ID,
            tle.QUANTITY,
            tle.DISPLAY_OPERATOR_INSTRUCTION,
            ROW_NUMBER() OVER (
                PARTITION BY tle.PARENT_ORDER_ID, tle.CLIENT_ORDER_TYPE
                ORDER BY
                    COALESCE(tle.DOMINANT_BIN_ID, 2147483647),
                    tle.DOMINANT_HIT_CNT DESC,
                    tle.QUANTITY DESC,
                    tle.ORDER_LINE_ID
            ) AS rn
        FROM tmp_lines_enriched tle
        WHERE tle.SHORT_FLAG = 0;

        
        INSERT INTO tmp_split_all
        SELECT
            r.PARENT_ORDER_ID,
            r.CLIENT_ORDER_TYPE,
            r.ORDER_LINE_ID,
            r.ARTICLE_ID,
            r.BATCH_ID,
            r.QUANTITY,
            r.DISPLAY_OPERATOR_INSTRUCTION,
            1 + ((r.rn - 1) * p.GRP_CNT) DIV p.LINE_CNT AS SPLIT_GROUP,
            0 AS IS_SUSPENDED_GROUP
        FROM tmp_ranked_normal r
        JOIN tmp_norm_plan p
          ON p.PARENT_ORDER_ID = r.PARENT_ORDER_ID
         AND p.CLIENT_ORDER_TYPE = r.CLIENT_ORDER_TYPE;

        
        IF v_suspend_short_lines = 1 THEN

            DROP TEMPORARY TABLE IF EXISTS tmp_short_plan;
            CREATE TEMPORARY TABLE tmp_short_plan (
                PARENT_ORDER_ID VARCHAR(100) NOT NULL,
                CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
                LINE_CNT INT NOT NULL,
                TOTAL_QTY INT NOT NULL,
                GRP_CNT INT NOT NULL,
                OFFSET_G INT NOT NULL,
                PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
            ) ENGINE=INNODB;

            
            INSERT INTO tmp_short_plan
            SELECT
                s.PARENT_ORDER_ID,
                s.CLIENT_ORDER_TYPE,
                COUNT(*) AS LINE_CNT,
                SUM(s.QUANTITY) AS TOTAL_QTY,
                CASE
                    WHEN ((COUNT(*) + v_max_lines - 1) DIV v_max_lines) >= ((SUM(s.QUANTITY) + v_max_qty - 1) DIV v_max_qty)
                        THEN ((COUNT(*) + v_max_lines - 1) DIV v_max_lines)
                    ELSE ((SUM(s.QUANTITY) + v_max_qty - 1) DIV v_max_qty)
                END AS GRP_CNT,
                COALESCE(n.GRP_CNT, 0) AS OFFSET_G
            FROM tmp_lines_enriched s
            LEFT JOIN tmp_norm_plan n
              ON n.PARENT_ORDER_ID = s.PARENT_ORDER_ID
             AND n.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
            WHERE s.SHORT_FLAG = 1
            GROUP BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE;

            DROP TEMPORARY TABLE IF EXISTS tmp_ranked_short;
            CREATE TEMPORARY TABLE tmp_ranked_short (
                PARENT_ORDER_ID VARCHAR(100) NOT NULL,
                CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
                ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
                ARTICLE_ID      VARCHAR(200) NULL,
                BATCH_ID        VARCHAR(200) NULL,
                QUANTITY        INT NOT NULL,
                DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
                rn INT NOT NULL,
                PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
                KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, rn)
            ) ENGINE=INNODB;

            INSERT INTO tmp_ranked_short
            SELECT
                tle.PARENT_ORDER_ID,
                tle.CLIENT_ORDER_TYPE,
                tle.ORDER_LINE_ID,
                tle.ARTICLE_ID,
                tle.BATCH_ID,
                tle.QUANTITY,
                tle.DISPLAY_OPERATOR_INSTRUCTION,
                ROW_NUMBER() OVER (
                    PARTITION BY tle.PARENT_ORDER_ID, tle.CLIENT_ORDER_TYPE
                    ORDER BY tle.QUANTITY DESC, tle.ORDER_LINE_ID
                ) AS rn
            FROM tmp_lines_enriched tle
            WHERE tle.SHORT_FLAG = 1;

            INSERT INTO tmp_split_all
            SELECT
                r.PARENT_ORDER_ID,
                r.CLIENT_ORDER_TYPE,
                r.ORDER_LINE_ID,
                r.ARTICLE_ID,
                r.BATCH_ID,
                r.QUANTITY,
                r.DISPLAY_OPERATOR_INSTRUCTION,
                sp.OFFSET_G + (1 + ((r.rn - 1) * sp.GRP_CNT) DIV sp.LINE_CNT) AS SPLIT_GROUP,
                1 AS IS_SUSPENDED_GROUP
            FROM tmp_ranked_short r
            JOIN tmp_short_plan sp
              ON sp.PARENT_ORDER_ID = r.PARENT_ORDER_ID
             AND sp.CLIENT_ORDER_TYPE = r.CLIENT_ORDER_TYPE;

        END IF;

    END IF;

    

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_pre_lines, v_pre_qty
    FROM tmp_lines;

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_post_lines, v_post_qty
    FROM tmp_split_all;

    IF v_pre_lines <> v_post_lines OR v_pre_qty <> v_post_qty THEN
        SET v_errmsg = CONCAT(
            'SPLIT_VALIDATION_FAILED: PRE_LINES=', v_pre_lines,
            ', POST_LINES=', v_post_lines,
            ', PRE_QTY=', v_pre_qty,
            ', POST_QTY=', v_post_qty
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    
    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_lines tl
    LEFT JOIN tmp_split_all sa
      ON sa.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND sa.ORDER_LINE_ID   = tl.ORDER_LINE_ID
    WHERE sa.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('SPLIT_VALIDATION_FAILED: MISSING_LINES=', v_missing_lines);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    

    
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
    CREATE TEMPORARY TABLE tmp_cat_seq (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        CAT_SEQ INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
        KEY (PARENT_ORDER_ID, CAT_SEQ)
    ) ENGINE=INNODB;

    INSERT INTO tmp_cat_seq (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CAT_SEQ)
    SELECT
        x.PARENT_ORDER_ID,
        x.CLIENT_ORDER_TYPE,
        ROW_NUMBER() OVER (PARTITION BY x.PARENT_ORDER_ID ORDER BY x.CLIENT_ORDER_TYPE) AS CAT_SEQ
    FROM (
        SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE
        FROM tmp_lines_cat
    ) X;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_bucket_groupmax;
    CREATE TEMPORARY TABLE tmp_bucket_groupmax (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        MAX_GRP INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_bucket_groupmax
    SELECT
        PARENT_ORDER_ID,
        CLIENT_ORDER_TYPE,
        MAX(SPLIT_GROUP) AS MAX_GRP
    FROM tmp_split_all
    GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;

    DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
    CREATE TEMPORARY TABLE tmp_child_orders (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        CAT_SEQ INT NOT NULL,
        SPLIT_GROUP INT NOT NULL,
        CHILD_ORDER_ID VARCHAR(100) NOT NULL,
        CHILD_STATUS ENUM('PENDING','ORDER_SUSPENDED') NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SPLIT_GROUP),
        KEY (CHILD_ORDER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_child_orders
    SELECT
        sa.PARENT_ORDER_ID,
        sa.CLIENT_ORDER_TYPE,
        cs.CAT_SEQ,
        sa.SPLIT_GROUP,
        CASE
            WHEN bg.MAX_GRP = 1
                THEN CONCAT(sa.PARENT_ORDER_ID, '-', cs.CAT_SEQ)
            ELSE CONCAT(sa.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', LPAD(sa.SPLIT_GROUP, 3, '0'))
        END AS CHILD_ORDER_ID,
        CASE WHEN MAX(sa.IS_SUSPENDED_GROUP) = 1 THEN 'ORDER_SUSPENDED' ELSE 'PENDING' END AS CHILD_STATUS
    FROM tmp_split_all sa
    JOIN tmp_cat_seq cs
      ON cs.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND cs.CLIENT_ORDER_TYPE = sa.CLIENT_ORDER_TYPE
    JOIN tmp_bucket_groupmax bg
      ON bg.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND bg.CLIENT_ORDER_TYPE = sa.CLIENT_ORDER_TYPE
    GROUP BY sa.PARENT_ORDER_ID, sa.CLIENT_ORDER_TYPE, cs.CAT_SEQ, sa.SPLIT_GROUP, bg.MAX_GRP;

    START TRANSACTION;

    
    INSERT INTO wms_to_wcs_order_request_data
        (PARENT_ORDER_ID, ORDER_TYPE, ORDER_ID, ORDER_REQUEST_STATUS, INSERTED_TIMESTAMP, INSERTED_BY)
    SELECT
        co.PARENT_ORDER_ID,
        co.CLIENT_ORDER_TYPE,
        co.CHILD_ORDER_ID,
        co.CHILD_STATUS,
        CURRENT_TIMESTAMP(3),
        'BACKEND-SERVICE'
    FROM tmp_child_orders co
    WHERE NOT EXISTS (
        SELECT 1
        FROM wms_to_wcs_order_request_data r
        WHERE r.ORDER_ID = co.CHILD_ORDER_ID
    );

    SELECT COUNT(*) INTO v_child_cnt FROM tmp_child_orders;

    
    INSERT INTO wms_to_wcs_order_line_request_data
        (WMS_ORDER_REQUEST_DATA_ID, ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, BATCH_ID,
         DISPLAY_OPERATOR_INSTRUCTION, ORDER_LINE_PROCESS_STATUS, INSERTED_TIMESTAMP, INSERTED_BY)
    SELECT
        r.WMS_ORDER_REQUEST_DATA_ID,
        r.ORDER_ID,
        sa.ORDER_LINE_ID,
        sa.ARTICLE_ID,
        sa.QUANTITY,
        sa.BATCH_ID,
        sa.DISPLAY_OPERATOR_INSTRUCTION,
        'PENDING',
        CURRENT_TIMESTAMP(3),
        'BACKEND-SERVICE'
    FROM tmp_split_all sa
    JOIN tmp_child_orders co
      ON co.PARENT_ORDER_ID = sa.PARENT_ORDER_ID
     AND co.CLIENT_ORDER_TYPE = sa.CLIENT_ORDER_TYPE
     AND co.SPLIT_GROUP     = sa.SPLIT_GROUP
    JOIN wms_to_wcs_order_request_data r
      ON r.ORDER_ID = co.CHILD_ORDER_ID
    WHERE NOT EXISTS (
        SELECT 1
        FROM wms_to_wcs_order_line_request_data lr
        WHERE lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID
          AND lr.ORDER_LINE_ID = sa.ORDER_LINE_ID
    );

    
    UPDATE wms_to_wcs_order_level_pre_staged_data p
    JOIN tmp_parent_orders t
      ON t.PRE_STAGED_REQ_ID = p.WMS_ORDER_REQUEST_DATA_ID
    SET p.IS_STAGED = 1,
        p.UPDATED_TIMESTAMP = CURRENT_TIMESTAMP(3),
        p.UPDATED_BY = 'SPLIT-OPS-V4';

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='2',
           ORDERSPLIT_ENDTIME = NOW(),
           RULE_STATS = JSON_OBJECT(
            'RULE_ID', v_rule_id,
            'PARENTS_FOUND', v_parent_cnt,
            'LINES_CONSIDERED', v_line_cnt,
            'CHILD_ORDERS_CREATED', v_child_cnt,
            'SHORT_LINES_FLAGGED', v_short_cnt,
            'MAX_ORDER_LINES_PER_ORDER', v_max_lines,
            'MAX_QUANTITY_PER_ORDER', v_max_qty,
            'TOL_LINES', v_tol_lines,
            'TOL_QTY', v_tol_qty,
            'HARD_LINES', v_hard_lines,
            'HARD_QTY', v_hard_qty,
            'SUSPEND_SHORT_LINES', v_suspend_short_lines,
            'CATEGORY_DEFAULT', 'FOOD',
            'GROUP_CNT_RULE', 'MAX(ceil(lines/limit), ceil(qty/limit))'
        )
     WHERE ID = v_ruleLog_id;

    COMMIT;

    DO RELEASE_LOCK(CONCAT('SPLIT_', v_rule_id));

    
    SELECT
        v_rule_id AS RULE_ID,
        v_parent_cnt AS PARENTS_PROCESSED,
        v_line_cnt   AS LINES_CONSIDERED,
        v_child_cnt  AS CHILD_ORDERS_CREATED,
        v_short_cnt  AS SHORT_LINES_FLAGGED,
        v_max_lines  AS MAX_ORDER_LINES,
        v_max_qty    AS MAX_ORDER_QTY,
        v_tol_lines  AS TOL_LINES,
        v_tol_qty    AS TOL_QTY,
        v_hard_lines AS HARD_LINES,
        v_hard_qty   AS HARD_QTY,
        v_suspend_short_lines AS SUSPEND_SHORT_LINES;

END sp_main */$$
DELIMITER ;

/* Procedure structure for procedure `sp_split_orders_ops_v9` */

/*!50003 DROP PROCEDURE IF EXISTS  `sp_split_orders_ops_v9` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sp_split_orders_ops_v9`()
sp_main: BEGIN

    
    DECLARE v_max_lines INT DEFAULT 50;
    DECLARE v_max_qty   INT DEFAULT 500;
    DECLARE v_tol_lines INT DEFAULT 10;
    DECLARE v_tol_qty   INT DEFAULT 100;

    DECLARE v_hard_lines INT DEFAULT 60;
    DECLARE v_hard_qty   INT DEFAULT 600;

    DECLARE v_suspend_short_lines INT DEFAULT 0;  
    DECLARE v_res_ttl_minutes INT DEFAULT 30;

    
    DECLARE v_ruleLog_id BIGINT DEFAULT NULL;
    DECLARE v_rule_id BIGINT DEFAULT NULL;
    DECLARE v_rule_defination TEXT DEFAULT NULL;

    
    DECLARE v_lock_ok INT DEFAULT 0;
    DECLARE v_lock_key VARCHAR(128) DEFAULT NULL;

    
    DECLARE v_reservation_key VARCHAR(64) DEFAULT NULL;

    
    DECLARE v_station_mode ENUM('FINAL','INITIAL') DEFAULT NULL;
    DECLARE v_user_station_cnt BIGINT DEFAULT 0;

    
    DECLARE v_run_priority ENUM('INITIAL','FINAL') DEFAULT 'FINAL';
    DECLARE v_is_dry_run INT DEFAULT 0;

    
    DECLARE v_parent_cnt BIGINT DEFAULT 0;
    DECLARE v_line_cnt BIGINT DEFAULT 0;
    DECLARE v_child_cnt BIGINT DEFAULT 0;

    
    DECLARE v_cnt_lines BIGINT DEFAULT 0;
    DECLARE v_cnt_lines_cat BIGINT DEFAULT 0;
    DECLARE v_cnt_line_assign BIGINT DEFAULT 0;
    DECLARE v_cnt_ranked BIGINT DEFAULT 0;
    DECLARE v_cnt_final BIGINT DEFAULT 0;
    DECLARE v_cnt_db_child_lines BIGINT DEFAULT 0;

    DECLARE v_pre_lines BIGINT DEFAULT 0;
    DECLARE v_post_lines BIGINT DEFAULT 0;
    DECLARE v_pre_qty BIGINT DEFAULT 0;
    DECLARE v_post_qty BIGINT DEFAULT 0;
    DECLARE v_missing_lines BIGINT DEFAULT 0;

    DECLARE v_errmsg TEXT DEFAULT '';

    
    DECLARE v_has_or_cluster INT DEFAULT 0;
    DECLARE v_has_ol_cluster INT DEFAULT 0;

    DECLARE v_has_reco_col INT DEFAULT 0;   
    DECLARE v_has_reco1 INT DEFAULT 0;      
    DECLARE v_has_reco2 INT DEFAULT 0;      
    DECLARE v_has_reco1_alt INT DEFAULT 0;  
    DECLARE v_has_reco2_alt INT DEFAULT 0;  

    DECLARE v_has_hw_station INT DEFAULT 0;
    DECLARE v_has_hw_wave_status INT DEFAULT 0;

    
    DECLARE v_sku   VARCHAR(200) DEFAULT NULL;
    DECLARE v_batch VARCHAR(200) DEFAULT NULL;

    DECLARE v_rn INT DEFAULT 0;
    DECLARE v_maxrn INT DEFAULT 0;

    DECLARE v_line_parent VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_cat    VARCHAR(100) DEFAULT NULL;
    DECLARE v_line_id     VARCHAR(36)  DEFAULT NULL;
    DECLARE v_line_qty    INT DEFAULT 0;

    DECLARE v_pick_cluster VARCHAR(50) DEFAULT NULL;

    DECLARE v_need BIGINT DEFAULT 0;
    DECLARE v_total_rem BIGINT DEFAULT 0;

    DECLARE v_crn INT DEFAULT 0;
    DECLARE v_cmax INT DEFAULT 0;
    DECLARE v_cur_cluster VARCHAR(50) DEFAULT NULL;
    DECLARE v_cur_rem BIGINT DEFAULT 0;
    DECLARE v_alloc BIGINT DEFAULT 0;

    
    DECLARE v_balance_mode INT DEFAULT 1;   
    DECLARE v_k1_pool INT DEFAULT 1;        

    
    DECLARE v_use_station_bias INT DEFAULT 0;   
    DECLARE v_near_aisle_window INT DEFAULT 1;  
    DECLARE v_min_pref_aisle INT DEFAULT NULL;
    DECLARE v_max_pref_aisle INT DEFAULT NULL;

    DECLARE v_total_lines_all BIGINT DEFAULT 0;
    DECLARE v_total_qty_all BIGINT DEFAULT 0;
    DECLARE v_total_lines_pickable BIGINT DEFAULT 0;
    DECLARE v_total_qty_pickable BIGINT DEFAULT 0;
    DECLARE v_alloc_qty_total BIGINT DEFAULT 0;
    DECLARE v_alloc_lines_total BIGINT DEFAULT 0;
    
	    
    DECLARE v_tmp_user_stations_ready INT DEFAULT 0;
        
    DECLARE v_lock_wait_seconds INT DEFAULT -1;

    
    DECLARE v_station_pref_consumed INT DEFAULT 0;

    
    DECLARE v_job_id BIGINT DEFAULT NULL;
    DECLARE v_job_rule_id BIGINT DEFAULT NULL;
    DECLARE v_job_priority ENUM('INITIAL','FINAL') DEFAULT NULL;



    
       
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;

        
        IF v_rule_id IS NOT NULL
           AND v_station_mode IS NOT NULL
           AND v_user_station_cnt > 0
           AND v_tmp_user_stations_ready = 1
        THEN
            UPDATE picklist_split_station_pref p
            JOIN tmp_user_stations t
              ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
            SET p.IS_PROCESSED = 0
            WHERE p.RULE_ID = v_rule_id
              AND p.PRIORITY = v_station_mode
              AND p.IS_PROCESSED = 1;
        END IF;

        
        IF v_ruleLog_id IS NOT NULL THEN
            UPDATE picklist_split_order_master
               SET IS_PROCESSED = '0',
                   ORDERSPLIT_ENDTIME = NOW()
             WHERE ID = v_ruleLog_id;
        END IF;

        
        
DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;

DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;       
DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;     
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;      

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
DROP TEMPORARY TABLE IF EXISTS tmp_final_map;

DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2;

DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;

DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;

DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;

        
        IF v_lock_ok = 1 AND v_lock_key IS NOT NULL THEN
            DO RELEASE_LOCK(v_lock_key);
        END IF;

        RESIGNAL;
    END;


    

    SET v_max_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_ORDER_LINES_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_lines
    );

    SET v_max_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'MAX_QUANTITY_PER_ORDER' AND IS_ACTIVE = 1
          LIMIT 1),
        v_max_qty
    );

    SET v_near_aisle_window = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_NEAR_AISLE_WINDOW' AND IS_ACTIVE = 1
          LIMIT 1),
        v_near_aisle_window
    );
    SET v_near_aisle_window = GREATEST(v_near_aisle_window, 0);

    SET v_tol_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_lines
    );

    SET v_tol_qty = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_TOL_QTY' AND IS_ACTIVE = 1
          LIMIT 1),
        v_tol_qty
    );

    SET v_suspend_short_lines = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'SUSPEND_SHORT_LINES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_suspend_short_lines
    );

    SET v_res_ttl_minutes = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'RESERVATION_TTL_MINUTES' AND IS_ACTIVE = 1
          LIMIT 1),
        v_res_ttl_minutes
    );

    SET v_balance_mode = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_BALANCE_MODE' AND IS_ACTIVE = 1
          LIMIT 1),
        v_balance_mode
    );

    SET v_k1_pool = COALESCE(
        (SELECT CAST(KEY_VALUE AS UNSIGNED)
           FROM master_config
          WHERE KEY_NAME = 'ORDER_SPLIT_K1_POOL' AND IS_ACTIVE = 1
          LIMIT 1),
        v_k1_pool
    );
    SET v_k1_pool = GREATEST(v_k1_pool, 1);

        
    SET v_max_lines = GREATEST(v_max_lines, 1);
    SET v_max_qty   = GREATEST(v_max_qty,   1);
    SET v_tol_lines = GREATEST(v_tol_lines, 0);
    SET v_tol_qty   = GREATEST(v_tol_qty,   0);

    SET v_hard_lines = v_max_lines + v_tol_lines;
    SET v_hard_qty   = v_max_qty   + v_tol_qty;


    

    SELECT COUNT(*) INTO v_has_or_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_ol_cluster
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'wms_to_wcs_order_line_request_data'
       AND COLUMN_NAME  = 'CLUSTER_ID';

    SELECT COUNT(*) INTO v_has_reco_col
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'RECOMMENDATION';

    SELECT COUNT(*) INTO v_has_reco1
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_1';

    SELECT COUNT(*) INTO v_has_reco2
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendations_2';

    SELECT COUNT(*) INTO v_has_reco1_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_1';

    SELECT COUNT(*) INTO v_has_reco2_alt
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'picklist_split_order_master'
       AND COLUMN_NAME  = 'recommendation_2';

    SELECT COUNT(*) INTO v_has_hw_station
      FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master';

    SELECT COUNT(*) INTO v_has_hw_wave_status
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME   = 'hw_station_master'
       AND COLUMN_NAME  = 'wave_status';

          

    job_pick: LOOP

        SET v_job_id = NULL;
        SET v_job_rule_id = NULL;
        SET v_job_priority = NULL;

        
        SELECT
            ID,
            RULE_ID,
            CASE
                WHEN COALESCE(NULLIF(PRIORITY,''),'FINAL') IN ('FINAL','INITIAL')
                    THEN COALESCE(NULLIF(PRIORITY,''),'FINAL')
                ELSE 'FINAL'
            END
          INTO v_job_id, v_job_rule_id, v_job_priority
        FROM picklist_split_order_master
        WHERE IS_PROCESSED = '0'
        ORDER BY ID DESC
        LIMIT 1;

        IF v_job_id IS NULL OR v_job_rule_id IS NULL THEN
            SELECT 'NO_RULE_TO_PROCESS' AS STATUS;
            LEAVE sp_main;
        END IF;

        
        SET v_lock_key = CONCAT('SPLIT_CLUSTER_', v_job_rule_id);
        SELECT GET_LOCK(v_lock_key, v_lock_wait_seconds) INTO v_lock_ok;

        IF v_lock_ok IS NULL THEN
            SET v_errmsg = CONCAT('GET_LOCK_ERROR: key=', v_lock_key);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        ELSEIF v_lock_ok = 0 THEN
            
            SET v_errmsg = CONCAT('Split job already running (lock timeout) for RULE_ID=', v_job_rule_id);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
        END IF;

        
        START TRANSACTION;

        SELECT
            ID,
            RULE_ID,
            v_job_priority
          INTO v_ruleLog_id, v_rule_id, v_run_priority
        FROM picklist_split_order_master
        WHERE ID = v_job_id
          AND IS_PROCESSED = '0'
        FOR UPDATE SKIP LOCKED;

        
        IF v_ruleLog_id IS NULL OR v_rule_id IS NULL THEN
            ROLLBACK;
            DO RELEASE_LOCK(v_lock_key);
            SET v_lock_ok = 0;
            ITERATE job_pick;
        END IF;

        LEAVE job_pick;
    END LOOP;

    
    SET v_is_dry_run = CASE WHEN v_run_priority = 'INITIAL' THEN 1 ELSE 0 END;

    
    IF v_is_dry_run = 1 THEN
        SET v_balance_mode = 0;
        SET v_k1_pool      = 1;
    END IF;



        

    SELECT FILTER_CONDITION
      INTO v_rule_defination
    FROM pick_rule_master
    WHERE PICK_RULE_ID = v_rule_id
    LIMIT 1;

    IF v_rule_defination IS NULL OR LENGTH(v_rule_defination) < 3 THEN
        
        UPDATE picklist_split_order_master
           SET IS_PROCESSED = '2',
               ORDERSPLIT_ENDTIME = NOW()
         WHERE ID = v_ruleLog_id;

        COMMIT;
        DO RELEASE_LOCK(v_lock_key);

        SELECT 'NO_RULE_DEFINITION_FOUND' AS STATUS, v_rule_id AS RULE_ID;
        LEAVE sp_main;
    END IF;

    
    SET v_rule_defination = LEFT(v_rule_defination, LENGTH(v_rule_defination)-1);


    

SET v_station_mode = NULL;
SET v_user_station_cnt = 0;
SET v_station_pref_consumed = 0;   


IF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'FINAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'FINAL';
ELSEIF EXISTS (
    SELECT 1
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND IS_PROCESSED = 0
       AND PRIORITY = 'INITIAL'
     LIMIT 1
) THEN
    SET v_station_mode = 'INITIAL';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
CREATE TEMPORARY TABLE tmp_user_stations (
    STATION_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (STATION_ID)
) ENGINE=INNODB;

SET v_tmp_user_stations_ready = 1;

IF v_station_mode IS NOT NULL THEN

    
    INSERT IGNORE INTO tmp_user_stations (STATION_ID)
    SELECT CAST(STATION_ID AS CHAR(50))
      FROM picklist_split_station_pref
     WHERE RULE_ID = v_rule_id
       AND PRIORITY = v_station_mode
       AND IS_PROCESSED = 0
     ORDER BY STATION_ID
     FOR UPDATE;

    SELECT COUNT(*) INTO v_user_station_cnt FROM tmp_user_stations;

END IF;


SET v_use_station_bias =
    CASE
        WHEN v_is_dry_run = 0 AND v_user_station_cnt > 0 AND v_has_hw_station = 1 THEN 1
        ELSE 0
    END;



DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
CREATE TEMPORARY TABLE tmp_pref_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
CREATE TEMPORARY TABLE tmp_near_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_pref_clusters (CLUSTER_ID)
    SELECT DISTINCT CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.CLUSTER_ID IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
    CREATE TEMPORARY TABLE tmp_pref_aisle_num (
        AISLE_NUM INT NOT NULL,
        PRIMARY KEY (AISLE_NUM)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_pref_aisle_num (AISLE_NUM)
    SELECT DISTINCT
           CAST(
               NULLIF(
                   REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                   ''
               ) AS UNSIGNED
           ) AS AISLE_NUM
      FROM cluster_aisle_mapping cam
      JOIN tmp_pref_clusters pc
        ON pc.CLUSTER_ID = cam.CLUSTER_ID
     WHERE cam.AISLE_NUMBER IS NOT NULL;

    
    SELECT MIN(AISLE_NUM), MAX(AISLE_NUM)
      INTO v_min_pref_aisle, v_max_pref_aisle
      FROM tmp_pref_aisle_num;

    IF v_min_pref_aisle IS NOT NULL AND v_max_pref_aisle IS NOT NULL THEN

        
        INSERT IGNORE INTO tmp_near_clusters (CLUSTER_ID)
        SELECT DISTINCT cam.CLUSTER_ID
          FROM cluster_aisle_mapping cam
         WHERE cam.CLUSTER_ID IS NOT NULL
           AND cam.AISLE_NUMBER IS NOT NULL
           AND CAST(
                   NULLIF(
                       REGEXP_REPLACE(CAST(cam.AISLE_NUMBER AS CHAR(50)), '[^0-9]', ''),
                       ''
                   ) AS UNSIGNED
               ) BETWEEN (v_min_pref_aisle - v_near_aisle_window)
                   AND (v_max_pref_aisle + v_near_aisle_window);

        
        DELETE n
          FROM tmp_near_clusters n
          JOIN tmp_pref_clusters p
            ON p.CLUSTER_ID = n.CLUSTER_ID;

    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;

END IF;


      

DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
CREATE TEMPORARY TABLE tmp_parent_orders (
    PRE_STAGED_REQ_ID BIGINT NOT NULL,
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    ORDER_TYPE        VARCHAR(100) NOT NULL,
    PRIMARY KEY (PRE_STAGED_REQ_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;


IF v_rule_defination IS NULL OR LENGTH(TRIM(v_rule_defination)) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULE_DEFINITION_EMPTY';
END IF;

SET @sql = CONCAT(
    'INSERT INTO tmp_parent_orders (PRE_STAGED_REQ_ID, PARENT_ORDER_ID, ORDER_TYPE)
     SELECT WMS_ORDER_REQUEST_DATA_ID,
            PARENT_ORDER_ID,
            COALESCE(NULLIF(PICKING_TYPE, ''''), NULLIF(ORDER_CATEGORY, ''''), ''PICK'') AS ORDER_TYPE
       FROM wms_to_wcs_order_level_pre_staged_data
      WHERE IFNULL(IS_STAGED,0) = 0
        AND PARENT_ORDER_ID IN (', v_rule_defination, ')'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT COUNT(*) INTO v_parent_cnt FROM tmp_parent_orders;

IF v_parent_cnt = 0 THEN

    
    IF v_station_pref_consumed = 1
       AND v_rule_id IS NOT NULL
       AND v_station_mode IS NOT NULL
       AND v_tmp_user_stations_ready = 1
    THEN
        UPDATE picklist_split_station_pref p
        JOIN tmp_user_stations t
          ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
        SET p.IS_PROCESSED = 0
        WHERE p.RULE_ID = v_rule_id
          AND p.PRIORITY = v_station_mode
          AND p.IS_PROCESSED = 1;

        SET v_station_pref_consumed = 0;
    END IF;

    
    UPDATE picklist_split_order_master
       SET IS_PROCESSED = '2',
           ORDERSPLIT_ENDTIME = NOW()
     WHERE ID = v_ruleLog_id;

    COMMIT;

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
    END;

    DO RELEASE_LOCK(v_lock_key);

    SELECT 'NO_PARENTS_TO_SPLIT' AS STATUS, v_rule_id AS RULE_ID;
    LEAVE sp_main;
END IF;


UPDATE picklist_split_order_master
   SET IS_PROCESSED = '1',
       ORDERSPLIT_STARTTIME = NOW()
 WHERE ID = v_ruleLog_id
   AND IS_PROCESSED = '0';

IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RULELOG_NOT_IN_STARTABLE_STATE';
END IF;


IF v_station_mode IS NOT NULL
   AND v_user_station_cnt > 0
   AND v_tmp_user_stations_ready = 1
THEN
    UPDATE picklist_split_station_pref p
    JOIN tmp_user_stations t
      ON CAST(t.STATION_ID AS CHAR(50)) = CAST(p.STATION_ID AS CHAR(50))
    SET p.IS_PROCESSED = 1
    WHERE p.RULE_ID = v_rule_id
      AND p.PRIORITY = v_station_mode
      AND p.IS_PROCESSED = 0;

    SET v_station_pref_consumed = 1;
END IF;


SET v_reservation_key = CONCAT('SPLIT_', v_ruleLog_id, '_', REPLACE(UUID(),'-',''));



DROP TEMPORARY TABLE IF EXISTS tmp_lines;
CREATE TEMPORARY TABLE tmp_lines (
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
    ARTICLE_ID      VARCHAR(200) NULL,
    BATCH_ID        VARCHAR(200) NULL,
    QUANTITY        INT NOT NULL,
    DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, ORDER_LINE_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_lines
SELECT
    l.PARENT_ORDER_ID,
    l.ORDER_LINE_ID,
    l.ARTICLE_ID,
    l.BATCH_ID,
    l.QUANTITY,
    l.DISPLAY_OPERATOR_INSTRUCTION
FROM wms_to_wcs_order_line_level_pre_staged_data l
JOIN tmp_parent_orders p
  ON p.PARENT_ORDER_ID = l.PARENT_ORDER_ID
WHERE IFNULL(l.ORDER_LINE_PROCESS_STATUS,'PENDING') <> 'DELETED';

SELECT COUNT(*) INTO v_line_cnt FROM tmp_lines;

IF v_line_cnt = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'NO_LINES_FOUND_FOR_SELECTED_PARENTS';
END IF;


    

    DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
    CREATE TEMPORARY TABLE tmp_line_category (
        ARTICLE_ID VARCHAR(200) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        PRIMARY KEY (ARTICLE_ID),
        KEY (CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_category (ARTICLE_ID, CLIENT_ORDER_TYPE)
    SELECT
        al.ARTICLE_ID,
        COALESCE(NULLIF(cm.CLIENT_ORDER_TYPE,''), 'FOOD') AS CLIENT_ORDER_TYPE
    FROM (SELECT DISTINCT ARTICLE_ID FROM tmp_lines WHERE ARTICLE_ID IS NOT NULL) al
    LEFT JOIN sku_master sm
      ON sm.SKU_ID = al.ARTICLE_ID
    LEFT JOIN category_master cm
      ON cm.CATEGORY_ID = sm.CATEGORY;

    DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
    CREATE TEMPORARY TABLE tmp_lines_cat (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID   VARCHAR(36)  NOT NULL,
        ARTICLE_ID      VARCHAR(200) NULL,
        BATCH_ID        VARCHAR(200) NULL,
        QUANTITY        INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_lines_cat
    SELECT
        tl.PARENT_ORDER_ID,
        COALESCE(lc.CLIENT_ORDER_TYPE, 'FOOD') AS CLIENT_ORDER_TYPE,
        tl.ORDER_LINE_ID,
        tl.ARTICLE_ID,
        tl.BATCH_ID,
        tl.QUANTITY,
        tl.DISPLAY_OPERATOR_INSTRUCTION
    FROM tmp_lines tl
    LEFT JOIN tmp_line_category lc
      ON lc.ARTICLE_ID = tl.ARTICLE_ID;

    
    SELECT COUNT(*) INTO v_cnt_lines     FROM tmp_lines;
    SELECT COUNT(*) INTO v_cnt_lines_cat FROM tmp_lines_cat;

    IF v_cnt_lines_cat <> v_cnt_lines THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_CATEGORY: tmp_lines=', v_cnt_lines,
                              ', tmp_lines_cat=', v_cnt_lines_cat);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

 


DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
CREATE TEMPORARY TABLE tmp_aisle_cluster_raw (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER, CLUSTER_ID),
    KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster_raw (AISLE_NUMBER, CLUSTER_ID)
SELECT DISTINCT AISLE_NUMBER, CLUSTER_ID
  FROM cluster_aisle_mapping
 WHERE AISLE_NUMBER IS NOT NULL
   AND CLUSTER_ID IS NOT NULL;

IF (SELECT COUNT(*) FROM tmp_aisle_cluster_raw) = 0 THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: cluster_aisle_mapping has no AISLE_NUMBER->CLUSTER_ID rows';
END IF;

IF EXISTS (
    SELECT 1
      FROM (
            SELECT AISLE_NUMBER, COUNT(*) AS c
              FROM tmp_aisle_cluster_raw
             GROUP BY AISLE_NUMBER
            HAVING c > 1
      ) X
    LIMIT 1
) THEN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'CONFIG_ERROR: AISLE_NUMBER maps to multiple CLUSTER_ID in cluster_aisle_mapping';
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
CREATE TEMPORARY TABLE tmp_aisle_cluster (
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    PRIMARY KEY (AISLE_NUMBER),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_aisle_cluster (AISLE_NUMBER, CLUSTER_ID)
SELECT AISLE_NUMBER, CLUSTER_ID
  FROM tmp_aisle_cluster_raw;




DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
CREATE TEMPORARY TABLE tmp_sku_global (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_global
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_lines_cat
 WHERE ARTICLE_ID IS NOT NULL AND BATCH_ID IS NOT NULL;

DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
CREATE TEMPORARY TABLE tmp_inv_bin (
    BIN_ID INT NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    AISLE_NUMBER VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    AVAIL_QTY BIGINT NOT NULL,
    LAST_TS DATETIME(3) NULL,
    PRIMARY KEY (BIN_ID, ARTICLE_ID, BATCH_ID),

    KEY (ARTICLE_ID, BATCH_ID),
    KEY (CLUSTER_ID),
    KEY (AISLE_NUMBER),

    
    KEY idx_ab_cluster (ARTICLE_ID, BATCH_ID, CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_inv_bin (BIN_ID, ARTICLE_ID, BATCH_ID, AISLE_NUMBER, CLUSTER_ID, AVAIL_QTY, LAST_TS)
SELECT
    lim.BIN_ID,
    lim.ARTICLE_ID,
    lim.BATCH_ID,
    lmst.AISLE_NUMBER,
    ac.CLUSTER_ID,
    GREATEST(
        CAST(SUM(GREATEST(lim.QUANTITY - lim.VIRTUAL_QUANTITY_TO_PICK, 0)) AS SIGNED),
        0
    ) AS AVAIL_QTY,
    MAX(lim.UPDATED_TIMESTAMP) AS LAST_TS
FROM live_inventory_master lim
JOIN tmp_sku_global sg
  ON sg.ARTICLE_ID = lim.ARTICLE_ID
 AND sg.BATCH_ID   = lim.BATCH_ID
JOIN store_bin_master sb
  ON sb.BIN_ID = lim.BIN_ID
JOIN location_master lmst
  ON lmst.LOCATION_ID = sb.LOCATION_ID
LEFT JOIN location_block_master lb
  ON lb.LOCATION_ID = sb.LOCATION_ID
JOIN tmp_aisle_cluster ac
  ON ac.AISLE_NUMBER = lmst.AISLE_NUMBER
WHERE lim.IS_ACTIVE = 1
  AND lim.BIN_ID IS NOT NULL
  AND lmst.AISLE_NUMBER IS NOT NULL
  AND lb.LOCATION_ID IS NULL
GROUP BY lim.BIN_ID, lim.ARTICLE_ID, lim.BATCH_ID, lmst.AISLE_NUMBER, ac.CLUSTER_ID
HAVING AVAIL_QTY > 0;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
CREATE TEMPORARY TABLE tmp_cluster_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply (ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY)
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUM(AVAIL_QTY) AS SUPPLY_QTY
  FROM tmp_inv_bin
 GROUP BY ARTICLE_ID, BATCH_ID, CLUSTER_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
CREATE TEMPORARY TABLE tmp_sku_total_supply (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_SUPPLY BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_total_supply
SELECT ARTICLE_ID, BATCH_ID, SUM(SUPPLY_QTY) AS TOTAL_SUPPLY
  FROM tmp_cluster_supply
 GROUP BY ARTICLE_ID, BATCH_ID;




DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
CREATE TEMPORARY TABLE tmp_final_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    CL_NUM     INT NULL,
    PRIMARY KEY (CLUSTER_ID),
    KEY (CL_NUM)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
CREATE TEMPORARY TABLE tmp_cluster_snap_map (
    SRC_CLUSTER_ID      VARCHAR(50) NOT NULL,
    SNAPPED_CLUSTER_ID  VARCHAR(50) NOT NULL,
    PRIMARY KEY (SRC_CLUSTER_ID),
    KEY (SNAPPED_CLUSTER_ID)
) ENGINE=INNODB;


DROP TEMPORARY TABLE IF EXISTS tmp_final_cluster_default;
CREATE TEMPORARY TABLE tmp_final_cluster_default (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_use_station_bias = 1 THEN

    
    INSERT IGNORE INTO tmp_final_clusters (CLUSTER_ID, CL_NUM)
    SELECT
        pc.CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(pc.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS CL_NUM
    FROM tmp_pref_clusters pc
    WHERE pc.CLUSTER_ID IS NOT NULL;

    
    IF (SELECT COUNT(*) FROM tmp_final_clusters) = 0 THEN
        SET v_use_station_bias = 0;
    END IF;

    
    IF v_use_station_bias = 1 THEN
        INSERT INTO tmp_final_cluster_default (CLUSTER_ID)
        SELECT fc.CLUSTER_ID
          FROM tmp_final_clusters fc
         ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
         LIMIT 1;
    END IF;

    

    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;
    CREATE TEMPORARY TABLE tmp_supply_clusters (
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        SRC_NUM        INT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID),
        KEY (SRC_NUM)
    ) ENGINE=INNODB;

    INSERT INTO tmp_supply_clusters (SRC_CLUSTER_ID, SRC_NUM)
    SELECT DISTINCT
        cs.CLUSTER_ID AS SRC_CLUSTER_ID,
        CAST(NULLIF(REGEXP_REPLACE(cs.CLUSTER_ID, '[^0-9]', ''), '') AS UNSIGNED) AS SRC_NUM
    FROM tmp_cluster_supply cs;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    CREATE TEMPORARY TABLE tmp_snap_candidates (
        SRC_CLUSTER_ID   VARCHAR(50) NOT NULL,
        CAND_CLUSTER_ID  VARCHAR(50) NOT NULL,
        RN               INT NOT NULL,
        PRIMARY KEY (SRC_CLUSTER_ID, RN),
        KEY (CAND_CLUSTER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_snap_candidates (SRC_CLUSTER_ID, CAND_CLUSTER_ID, RN)
    SELECT
        sc.SRC_CLUSTER_ID,
        fc.CLUSTER_ID AS CAND_CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY sc.SRC_CLUSTER_ID
            ORDER BY
                ABS(COALESCE(fc.CL_NUM,0) - COALESCE(sc.SRC_NUM,0)),
                
                CASE WHEN COALESCE(fc.CL_NUM,0) >= COALESCE(sc.SRC_NUM,0) THEN 0 ELSE 1 END,
                COALESCE(fc.CL_NUM,0),
                fc.CLUSTER_ID
        ) AS RN
    FROM tmp_supply_clusters sc
    JOIN tmp_final_clusters fc
      ON 1=1;

    
    INSERT IGNORE INTO tmp_cluster_snap_map (SRC_CLUSTER_ID, SNAPPED_CLUSTER_ID)
    SELECT
        sc.SRC_CLUSTER_ID,
        CASE
            WHEN fc_same.CLUSTER_ID IS NOT NULL THEN sc.SRC_CLUSTER_ID
            ELSE COALESCE(c.CAND_CLUSTER_ID, d.CLUSTER_ID)
        END AS SNAPPED_CLUSTER_ID
    FROM tmp_supply_clusters sc
    LEFT JOIN tmp_final_clusters fc_same
      ON fc_same.CLUSTER_ID = sc.SRC_CLUSTER_ID
    LEFT JOIN tmp_snap_candidates c
      ON c.SRC_CLUSTER_ID = sc.SRC_CLUSTER_ID
     AND c.RN = 1
    LEFT JOIN tmp_final_cluster_default d
      ON 1=1;

    DROP TEMPORARY TABLE IF EXISTS tmp_snap_candidates;
    DROP TEMPORARY TABLE IF EXISTS tmp_supply_clusters;

END IF;


    

    DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
    CREATE TEMPORARY TABLE tmp_line_cluster_candidates (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID VARCHAR(36) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        CLUSTER_ID VARCHAR(50)  NOT NULL,
        SUPPLY_QTY BIGINT NOT NULL,
        C_RANK INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, CLUSTER_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, C_RANK)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_cluster_candidates
    SELECT
        lc.PARENT_ORDER_ID,
        lc.CLIENT_ORDER_TYPE,
        lc.ORDER_LINE_ID,
        lc.ARTICLE_ID,
        lc.BATCH_ID,
        cs.CLUSTER_ID,
        cs.SUPPLY_QTY,
        ROW_NUMBER() OVER (
            PARTITION BY lc.PARENT_ORDER_ID, lc.CLIENT_ORDER_TYPE, lc.ORDER_LINE_ID
            ORDER BY cs.SUPPLY_QTY DESC, cs.CLUSTER_ID
        ) AS C_RANK
    FROM tmp_lines_cat lc
    JOIN tmp_cluster_supply cs
      ON cs.ARTICLE_ID = lc.ARTICLE_ID
     AND cs.BATCH_ID   = lc.BATCH_ID;

    DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
    CREATE TEMPORARY TABLE tmp_line_assign (
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        ORDER_LINE_ID VARCHAR(36) NOT NULL,
        ARTICLE_ID VARCHAR(200) NULL,
        BATCH_ID   VARCHAR(200) NULL,
        QUANTITY   INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

        ASSIGNED_CLUSTER_ID VARCHAR(50) NULL,
        ASSIGNED_RANK INT NOT NULL DEFAULT 0,

        SHORT_FLAG_SCHEMA INT NOT NULL DEFAULT 0,
        SHORT_FLAG_SUPPLY INT NOT NULL DEFAULT 0,
        SHORT_FLAG INT NOT NULL DEFAULT 0,

        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (ARTICLE_ID, BATCH_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_line_assign
    SELECT
        lc.PARENT_ORDER_ID,
        lc.CLIENT_ORDER_TYPE,
        lc.ORDER_LINE_ID,
        lc.ARTICLE_ID,
        lc.BATCH_ID,
        lc.QUANTITY,
        lc.DISPLAY_OPERATOR_INSTRUCTION,
        NULL, 0,
        0, 0, 0
    FROM tmp_lines_cat lc;

    UPDATE tmp_line_assign la
    LEFT JOIN tmp_sku_total_supply ts
      ON ts.ARTICLE_ID = la.ARTICLE_ID
     AND ts.BATCH_ID   = la.BATCH_ID
    SET la.SHORT_FLAG_SCHEMA = CASE
        WHEN la.ARTICLE_ID IS NULL OR la.BATCH_ID IS NULL THEN 1
        WHEN ts.TOTAL_SUPPLY IS NULL THEN 1
        ELSE 0
    END;

    SELECT COUNT(*) INTO v_cnt_line_assign FROM tmp_line_assign;
    IF v_cnt_line_assign <> v_cnt_lines_cat THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_ASSIGN: tmp_lines_cat=', v_cnt_lines_cat,
                              ', tmp_line_assign=', v_cnt_line_assign);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
CREATE TEMPORARY TABLE tmp_bucket_k (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    TOTAL_LINES         BIGINT NOT NULL,
    TOTAL_QTY           BIGINT NOT NULL,
    K                   INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_k (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, TOTAL_LINES, TOTAL_QTY, K)
SELECT
    la.PARENT_ORDER_ID,
    la.CLIENT_ORDER_TYPE,
    COUNT(*) AS TOTAL_LINES,
    COALESCE(SUM(la.QUANTITY),0) AS TOTAL_QTY,
    GREATEST(
        1,
        IF(v_max_lines > 0, CEIL(COUNT(*) / v_max_lines), 1),
        IF(v_max_qty   > 0, CEIL(COALESCE(SUM(la.QUANTITY),0) / v_max_qty), 1)
    ) AS K
FROM tmp_line_assign la
GROUP BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
CREATE TEMPORARY TABLE tmp_bucket_cluster_score (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    BEST_LINE_CNT       BIGINT NOT NULL,
    BEST_QTY_FIT        BIGINT NOT NULL,
    SCORE               DECIMAL(30,0) NOT NULL,
    SCORE_RANK          INT NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, SCORE_RANK),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_cluster_score
SELECT
    x.PARENT_ORDER_ID,
    x.CLIENT_ORDER_TYPE,
    x.CLUSTER_ID,
    x.BEST_LINE_CNT,
    x.BEST_QTY_FIT,
    (x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT AS SCORE,
    ROW_NUMBER() OVER (
        PARTITION BY x.PARENT_ORDER_ID, x.CLIENT_ORDER_TYPE
        ORDER BY ((x.BEST_LINE_CNT * 1000000000000) + x.BEST_QTY_FIT) DESC, x.CLUSTER_ID
    ) AS SCORE_RANK
FROM (
    SELECT
        c.PARENT_ORDER_ID,
        c.CLIENT_ORDER_TYPE,
        c.CLUSTER_ID,
        SUM(CASE WHEN c.C_RANK = 1 THEN 1 ELSE 0 END) AS BEST_LINE_CNT,
        SUM(CASE
                WHEN c.C_RANK = 1 THEN LEAST(c.SUPPLY_QTY, la.QUANTITY)
                ELSE 0
            END) AS BEST_QTY_FIT
    FROM tmp_line_cluster_candidates c
    JOIN tmp_line_assign la
      ON la.PARENT_ORDER_ID = c.PARENT_ORDER_ID
     AND la.CLIENT_ORDER_TYPE = c.CLIENT_ORDER_TYPE
     AND la.ORDER_LINE_ID = c.ORDER_LINE_ID
    GROUP BY c.PARENT_ORDER_ID, c.CLIENT_ORDER_TYPE, c.CLUSTER_ID
) X;

DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
CREATE TEMPORARY TABLE tmp_allowed_clusters (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
SELECT
    s.PARENT_ORDER_ID,
    s.CLIENT_ORDER_TYPE,
    s.CLUSTER_ID
FROM tmp_bucket_cluster_score s
JOIN tmp_bucket_k k
  ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
 AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
WHERE s.SCORE_RANK <= CASE
    WHEN v_balance_mode = 1 AND k.K = 1 THEN GREATEST(k.K, v_k1_pool)
    ELSE k.K
END;

IF (SELECT COUNT(*) FROM tmp_allowed_clusters) = 0 THEN
    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
      FROM tmp_bucket_cluster_score;
END IF;


IF v_use_station_bias = 1 THEN

    DELETE ac
      FROM tmp_allowed_clusters ac
      LEFT JOIN tmp_final_clusters fc
        ON fc.CLUSTER_ID = ac.CLUSTER_ID
     WHERE fc.CLUSTER_ID IS NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
    CREATE TEMPORARY TABLE tmp_empty_buckets (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT IGNORE INTO tmp_empty_buckets (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    SELECT bk.PARENT_ORDER_ID, bk.CLIENT_ORDER_TYPE
      FROM tmp_bucket_k bk
      LEFT JOIN tmp_allowed_clusters ac2
        ON ac2.PARENT_ORDER_ID   = bk.PARENT_ORDER_ID
       AND ac2.CLIENT_ORDER_TYPE = bk.CLIENT_ORDER_TYPE
     WHERE ac2.PARENT_ORDER_ID IS NULL;

    INSERT IGNORE INTO tmp_allowed_clusters (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT eb.PARENT_ORDER_ID, eb.CLIENT_ORDER_TYPE, fc2.CLUSTER_ID
      FROM tmp_empty_buckets eb
      CROSS JOIN tmp_final_clusters fc2;

    DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
CREATE TEMPORARY TABLE tmp_bucket_choice (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CHOSEN_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CHOSEN_CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_bucket_choice
SELECT
    PARENT_ORDER_ID,
    CLIENT_ORDER_TYPE,
    MAX(CASE WHEN rn = 1 + MOD(bucket_hash, pool_cnt) THEN CLUSTER_ID END) AS CHOSEN_CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK, s.CLUSTER_ID
        ) AS rn,
        COUNT(*) OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
        ) AS pool_cnt,
        CRC32(CONCAT(s.PARENT_ORDER_ID,'|',s.CLIENT_ORDER_TYPE)) AS bucket_hash
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
      AND s.SCORE_RANK <= v_k1_pool
) X
GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE;


INSERT IGNORE INTO tmp_bucket_choice (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CHOSEN_CLUSTER_ID)
SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
FROM (
    SELECT
        s.PARENT_ORDER_ID,
        s.CLIENT_ORDER_TYPE,
        s.CLUSTER_ID,
        ROW_NUMBER() OVER (
            PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
            ORDER BY s.SCORE_RANK, s.CLUSTER_ID
        ) AS rn
    FROM tmp_bucket_cluster_score s
    JOIN tmp_bucket_k k
      ON k.PARENT_ORDER_ID   = s.PARENT_ORDER_ID
     AND k.CLIENT_ORDER_TYPE = s.CLIENT_ORDER_TYPE
    WHERE v_balance_mode = 1
      AND k.K = 1
) z
WHERE rn = 1;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_bucket_choice bc
    LEFT JOIN tmp_cluster_snap_map sm
      ON sm.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID
    SET bc.CHOSEN_CLUSTER_ID = COALESCE(sm.SNAPPED_CLUSTER_ID, bc.CHOSEN_CLUSTER_ID);
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
CREATE TEMPORARY TABLE tmp_final_first_cluster (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_final_first_cluster (CLUSTER_ID)
    SELECT fc.CLUSTER_ID
      FROM tmp_final_clusters fc
     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
     LIMIT 1;
END IF;

DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
CREATE TEMPORARY TABLE tmp_bucket_top_final (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    CLUSTER_ID          VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN
    INSERT INTO tmp_bucket_top_final (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID
    FROM (
        SELECT
            s.PARENT_ORDER_ID,
            s.CLIENT_ORDER_TYPE,
            s.CLUSTER_ID,
            ROW_NUMBER() OVER (
                PARTITION BY s.PARENT_ORDER_ID, s.CLIENT_ORDER_TYPE
                ORDER BY s.SCORE_RANK, s.CLUSTER_ID
            ) AS rn
        FROM tmp_bucket_cluster_score s
        JOIN tmp_final_clusters fcx
          ON fcx.CLUSTER_ID = s.CLUSTER_ID
    ) q
    WHERE rn = 1;
END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
CREATE TEMPORARY TABLE tmp_bucket_fallback (
    PARENT_ORDER_ID       VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE     VARCHAR(100) NOT NULL,
    FALLBACK_CLUSTER_ID   VARCHAR(50)  NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (FALLBACK_CLUSTER_ID)
) ENGINE=INNODB;

IF v_use_station_bias = 1 THEN

    INSERT INTO tmp_bucket_fallback (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, FALLBACK_CLUSTER_ID)
    SELECT
        k.PARENT_ORDER_ID,
        k.CLIENT_ORDER_TYPE,
        COALESCE(bc.CHOSEN_CLUSTER_ID, topf.CLUSTER_ID, firstf.CLUSTER_ID) AS FALLBACK_CLUSTER_ID
    FROM tmp_bucket_k k
    LEFT JOIN tmp_bucket_choice bc
      ON bc.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND bc.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    LEFT JOIN tmp_bucket_top_final topf
      ON topf.PARENT_ORDER_ID   = k.PARENT_ORDER_ID
     AND topf.CLIENT_ORDER_TYPE = k.CLIENT_ORDER_TYPE
    CROSS JOIN tmp_final_first_cluster firstf;

END IF;


DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;

DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
CREATE TEMPORARY TABLE tmp_parent_cluster_load (
    PARENT_ORDER_ID   VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    CLUSTER_ID        VARCHAR(50)  NOT NULL,
    LINE_CNT          BIGINT NOT NULL DEFAULT 0,
    QTY_CNT           BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
) ENGINE=INNODB;


     

DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
CREATE TEMPORARY TABLE tmp_cluster_supply_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    CLUSTER_ID VARCHAR(50)  NOT NULL,
    SUPPLY_QTY BIGINT NOT NULL,
    REM_QTY    BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID, CLUSTER_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_cluster_supply_rem
SELECT ARTICLE_ID, BATCH_ID, CLUSTER_ID, SUPPLY_QTY, SUPPLY_QTY
  FROM tmp_cluster_supply;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
CREATE TEMPORARY TABLE tmp_sku_rem (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    TOTAL_REM  BIGINT NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_sku_rem (ARTICLE_ID, BATCH_ID, TOTAL_REM)
SELECT ARTICLE_ID, BATCH_ID, SUM(REM_QTY) AS TOTAL_REM
  FROM tmp_cluster_supply_rem
 GROUP BY ARTICLE_ID, BATCH_ID;

DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
CREATE TEMPORARY TABLE tmp_line_alloc (
    PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
    ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
    ARTICLE_ID          VARCHAR(200) NOT NULL,
    BATCH_ID            VARCHAR(200) NOT NULL,
    SRC_CLUSTER_ID      VARCHAR(50)  NOT NULL,
    ALLOC_QTY           BIGINT       NOT NULL,
    PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, SRC_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID),
    KEY (SRC_CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
CREATE TEMPORARY TABLE tmp_sku_queue (
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    PRIMARY KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT IGNORE INTO tmp_sku_queue
SELECT DISTINCT ARTICLE_ID, BATCH_ID
  FROM tmp_line_assign
 WHERE SHORT_FLAG_SCHEMA = 0
   AND ARTICLE_ID IS NOT NULL
   AND BATCH_ID IS NOT NULL;


DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
CREATE TEMPORARY TABLE tmp_sku_line_queue (
    RN INT NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    ORDER_LINE_ID VARCHAR(36) NOT NULL,
    QUANTITY INT NOT NULL,
    PRIMARY KEY (RN),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE),
    KEY (ORDER_LINE_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
CREATE TEMPORARY TABLE tmp_line_cluster_seq (
    RN INT NOT NULL,
    CLUSTER_ID VARCHAR(50) NOT NULL,
    REM_QTY BIGINT NOT NULL,
    PRIMARY KEY (RN),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

sku_loop: WHILE EXISTS (SELECT 1 FROM tmp_sku_queue LIMIT 1) DO

    SELECT ARTICLE_ID, BATCH_ID
      INTO v_sku, v_batch
      FROM tmp_sku_queue
      LIMIT 1;

    DELETE FROM tmp_sku_queue
     WHERE ARTICLE_ID = v_sku
       AND BATCH_ID   = v_batch;

    TRUNCATE TABLE tmp_sku_line_queue;

    
    INSERT INTO tmp_sku_line_queue (RN, PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY)
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE, la.QUANTITY DESC, la.ORDER_LINE_ID
        ) AS RN,
        la.PARENT_ORDER_ID,
        la.CLIENT_ORDER_TYPE,
        la.ORDER_LINE_ID,
        la.QUANTITY
    FROM tmp_line_assign la
    WHERE la.SHORT_FLAG_SCHEMA = 0
      AND la.ARTICLE_ID = v_sku
      AND la.BATCH_ID   = v_batch;

    SELECT COALESCE(MAX(RN),0) INTO v_maxrn FROM tmp_sku_line_queue;
    SET v_rn = 1;

    line_loop: WHILE v_rn <= v_maxrn DO

        SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID, QUANTITY
          INTO v_line_parent, v_line_cat, v_line_id, v_line_qty
          FROM tmp_sku_line_queue
         WHERE RN = v_rn;

        
        DELETE FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        SELECT COALESCE(TOTAL_REM,0)
          INTO v_total_rem
          FROM tmp_sku_rem
         WHERE ARTICLE_ID = v_sku
           AND BATCH_ID   = v_batch;

        
        IF v_total_rem <= 0 THEN

            IF v_use_station_bias = 1 THEN
                
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;

                
                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        TRUNCATE TABLE tmp_line_cluster_seq;

        
        INSERT INTO tmp_line_cluster_seq (RN, CLUSTER_ID, REM_QTY)
        SELECT
            ROW_NUMBER() OVER (
                ORDER BY
                    
                    CASE
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND csr.CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                        WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                        ELSE 2
                    END,
                    
                    CASE
                        WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                        WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                        WHEN v_use_station_bias = 1 THEN 2
                        ELSE 3
                    END,
                    
                    CASE WHEN ac.CLUSTER_ID IS NOT NULL THEN 0 ELSE 1 END,
                    
                    COALESCE(bcs.SCORE_RANK, 999999),
                    
                    COALESCE(pcl.LINE_CNT,0) DESC,
                    COALESCE(pcl.QTY_CNT,0)  DESC,
                    
                    csr.REM_QTY DESC,
                    csr.CLUSTER_ID
            ) AS RN,
            csr.CLUSTER_ID,
            csr.REM_QTY
        FROM tmp_cluster_supply_rem csr
        LEFT JOIN tmp_allowed_clusters ac
          ON ac.PARENT_ORDER_ID   = v_line_parent
         AND ac.CLIENT_ORDER_TYPE = v_line_cat
         AND ac.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = v_line_parent
         AND bcs.CLIENT_ORDER_TYPE = v_line_cat
         AND bcs.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_bucket_choice bc
          ON bc.PARENT_ORDER_ID   = v_line_parent
         AND bc.CLIENT_ORDER_TYPE = v_line_cat
        LEFT JOIN tmp_parent_cluster_load pcl
          ON pcl.PARENT_ORDER_ID   = v_line_parent
         AND pcl.CLIENT_ORDER_TYPE = v_line_cat
         AND pcl.CLUSTER_ID        = csr.CLUSTER_ID
        LEFT JOIN tmp_pref_clusters pfc
          ON pfc.CLUSTER_ID = csr.CLUSTER_ID
        LEFT JOIN tmp_near_clusters nfc
          ON nfc.CLUSTER_ID = csr.CLUSTER_ID
        WHERE csr.ARTICLE_ID = v_sku
          AND csr.BATCH_ID   = v_batch
          AND csr.REM_QTY   > 0;

        SELECT COALESCE(MAX(RN),0) INTO v_cmax FROM tmp_line_cluster_seq;

        
        SET v_need = v_line_qty;
        SET v_crn  = 1;

        cluster_loop: WHILE v_need > 0 AND v_crn <= v_cmax DO

            SELECT CLUSTER_ID, REM_QTY
              INTO v_cur_cluster, v_cur_rem
              FROM tmp_line_cluster_seq
             WHERE RN = v_crn;

            SET v_alloc = LEAST(v_cur_rem, v_need);

            IF v_alloc > 0 THEN

                INSERT INTO tmp_line_alloc (
                    PARENT_ORDER_ID, CLIENT_ORDER_TYPE, ORDER_LINE_ID,
                    ARTICLE_ID, BATCH_ID, SRC_CLUSTER_ID, ALLOC_QTY
                )
                VALUES (
                    v_line_parent, v_line_cat, v_line_id,
                    v_sku, v_batch, v_cur_cluster, v_alloc
                )
                ON DUPLICATE KEY UPDATE
                    ALLOC_QTY = ALLOC_QTY + VALUES(ALLOC_QTY);

                UPDATE tmp_cluster_supply_rem
                   SET REM_QTY = REM_QTY - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch
                   AND CLUSTER_ID = v_cur_cluster;

                
                UPDATE tmp_sku_rem
                   SET TOTAL_REM = TOTAL_REM - v_alloc
                 WHERE ARTICLE_ID = v_sku
                   AND BATCH_ID   = v_batch;

                SET v_need = v_need - v_alloc;

            END IF;

            SET v_crn = v_crn + 1;
        END WHILE;

        
        SELECT COALESCE(SUM(ALLOC_QTY),0)
          INTO v_alloc
          FROM tmp_line_alloc
         WHERE PARENT_ORDER_ID   = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID     = v_line_id;

        
        IF v_alloc <= 0 THEN

            IF v_use_station_bias = 1 THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;

                IF v_pick_cluster IS NULL THEN
                    SELECT fc.CLUSTER_ID
                      INTO v_pick_cluster
                      FROM tmp_final_clusters fc
                     ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                     LIMIT 1;
                END IF;

                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;

            ELSE
                UPDATE tmp_line_assign
                   SET ASSIGNED_CLUSTER_ID = 'NO_INVENTORY',
                       ASSIGNED_RANK = 0,
                       SHORT_FLAG_SUPPLY = 1
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                   AND ORDER_LINE_ID = v_line_id;
            END IF;

            SET v_rn = v_rn + 1;
            ITERATE line_loop;
        END IF;

        
        SET v_pick_cluster = NULL;

        
        SELECT la.SRC_CLUSTER_ID
          INTO v_pick_cluster
          FROM tmp_line_alloc la
          JOIN tmp_allowed_clusters ac
            ON ac.PARENT_ORDER_ID   = v_line_parent
           AND ac.CLIENT_ORDER_TYPE = v_line_cat
           AND ac.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_cluster_score bcs
            ON bcs.PARENT_ORDER_ID   = v_line_parent
           AND bcs.CLIENT_ORDER_TYPE = v_line_cat
           AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_bucket_choice bc
            ON bc.PARENT_ORDER_ID   = v_line_parent
           AND bc.CLIENT_ORDER_TYPE = v_line_cat
          LEFT JOIN tmp_pref_clusters pfc
            ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
          LEFT JOIN tmp_near_clusters nfc
            ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
         WHERE la.PARENT_ORDER_ID   = v_line_parent
           AND la.CLIENT_ORDER_TYPE = v_line_cat
           AND la.ORDER_LINE_ID     = v_line_id
         ORDER BY
            la.ALLOC_QTY DESC,
            CASE
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                ELSE 2
            END,
            CASE
                WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                WHEN v_use_station_bias = 1 THEN 2
                ELSE 3
            END,
            COALESCE(bcs.SCORE_RANK, 999999),
            la.SRC_CLUSTER_ID
         LIMIT 1;

        
        IF v_pick_cluster IS NULL THEN
            SELECT la.SRC_CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_line_alloc la
              LEFT JOIN tmp_bucket_cluster_score bcs
                ON bcs.PARENT_ORDER_ID   = v_line_parent
               AND bcs.CLIENT_ORDER_TYPE = v_line_cat
               AND bcs.CLUSTER_ID        = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_bucket_choice bc
                ON bc.PARENT_ORDER_ID   = v_line_parent
               AND bc.CLIENT_ORDER_TYPE = v_line_cat
              LEFT JOIN tmp_pref_clusters pfc
                ON pfc.CLUSTER_ID = la.SRC_CLUSTER_ID
              LEFT JOIN tmp_near_clusters nfc
                ON nfc.CLUSTER_ID = la.SRC_CLUSTER_ID
             WHERE la.PARENT_ORDER_ID   = v_line_parent
               AND la.CLIENT_ORDER_TYPE = v_line_cat
               AND la.ORDER_LINE_ID     = v_line_id
             ORDER BY
                la.ALLOC_QTY DESC,
                CASE
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL AND la.SRC_CLUSTER_ID = bc.CHOSEN_CLUSTER_ID THEN 0
                    WHEN bc.CHOSEN_CLUSTER_ID IS NOT NULL THEN 1
                    ELSE 2
                END,
                CASE
                    WHEN v_use_station_bias = 1 AND pfc.CLUSTER_ID IS NOT NULL THEN 0
                    WHEN v_use_station_bias = 1 AND nfc.CLUSTER_ID IS NOT NULL THEN 1
                    WHEN v_use_station_bias = 1 THEN 2
                    ELSE 3
                END,
                COALESCE(bcs.SCORE_RANK, 999999),
                la.SRC_CLUSTER_ID
             LIMIT 1;
        END IF;

        
        IF v_pick_cluster IS NULL THEN
            SELECT csr.CLUSTER_ID
              INTO v_pick_cluster
              FROM tmp_cluster_supply_rem csr
             WHERE csr.ARTICLE_ID = v_sku
               AND csr.BATCH_ID = v_batch
             ORDER BY csr.REM_QTY DESC, csr.CLUSTER_ID
             LIMIT 1;
        END IF;

        
        IF v_use_station_bias = 1
           AND v_pick_cluster IS NOT NULL
        THEN
            SELECT COALESCE(sm.SNAPPED_CLUSTER_ID, v_pick_cluster)
              INTO v_pick_cluster
              FROM tmp_cluster_snap_map sm
             WHERE sm.SRC_CLUSTER_ID = v_pick_cluster
             LIMIT 1;

            
            IF v_pick_cluster IS NULL THEN
                SELECT COALESCE(FALLBACK_CLUSTER_ID, NULL)
                  INTO v_pick_cluster
                  FROM tmp_bucket_fallback
                 WHERE PARENT_ORDER_ID = v_line_parent
                   AND CLIENT_ORDER_TYPE = v_line_cat
                 LIMIT 1;
            END IF;

            IF v_pick_cluster IS NULL THEN
                SELECT fc.CLUSTER_ID
                  INTO v_pick_cluster
                  FROM tmp_final_clusters fc
                 ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
                 LIMIT 1;
            END IF;
        END IF;

        
        UPDATE tmp_line_assign
           SET ASSIGNED_CLUSTER_ID = v_pick_cluster,
               ASSIGNED_RANK = 1,
               SHORT_FLAG_SUPPLY = CASE WHEN v_alloc < v_line_qty THEN 1 ELSE 0 END
         WHERE PARENT_ORDER_ID = v_line_parent
           AND CLIENT_ORDER_TYPE = v_line_cat
           AND ORDER_LINE_ID = v_line_id;

        
        INSERT INTO tmp_parent_cluster_load (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, LINE_CNT, QTY_CNT)
        VALUES (v_line_parent, v_line_cat, v_pick_cluster, 1, v_line_qty)
        ON DUPLICATE KEY UPDATE
            LINE_CNT = LINE_CNT + 1,
            QTY_CNT  = QTY_CNT  + VALUES(QTY_CNT);

        SET v_rn = v_rn + 1;
    END WHILE;

END WHILE;


IF v_use_station_bias = 1 THEN
    UPDATE tmp_line_assign la
    LEFT JOIN tmp_bucket_fallback bf
      ON bf.PARENT_ORDER_ID = la.PARENT_ORDER_ID
     AND bf.CLIENT_ORDER_TYPE = la.CLIENT_ORDER_TYPE
    SET la.ASSIGNED_CLUSTER_ID = COALESCE(
            bf.FALLBACK_CLUSTER_ID,
            (SELECT fc.CLUSTER_ID
               FROM tmp_final_clusters fc
              ORDER BY COALESCE(fc.CL_NUM,0), fc.CLUSTER_ID
              LIMIT 1)
        ),
        la.ASSIGNED_RANK = 0
    WHERE la.SHORT_FLAG_SCHEMA = 1
      AND la.ASSIGNED_CLUSTER_ID IS NULL;
END IF;

UPDATE tmp_line_assign
   SET SHORT_FLAG = GREATEST(SHORT_FLAG_SCHEMA, SHORT_FLAG_SUPPLY);




        

    DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
    CREATE TEMPORARY TABLE tmp_cluster_plan (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        LINE_CNT            BIGINT NOT NULL,
        TOTAL_QTY           BIGINT NOT NULL,
        GRP_CNT             INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_cluster_plan
    SELECT
        la.PARENT_ORDER_ID,
        la.CLIENT_ORDER_TYPE,
        COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY') AS CLUSTER_ID,
        COUNT(*) AS LINE_CNT,
        COALESCE(SUM(la.QUANTITY),0) AS TOTAL_QTY,
        GREATEST(
            IF(v_max_lines > 0, (COUNT(*) + v_max_lines - 1) DIV v_max_lines, 1),
            IF(v_max_qty   > 0, (COALESCE(SUM(la.QUANTITY),0) + v_max_qty - 1) DIV v_max_qty, 1)
        ) AS GRP_CNT
    FROM tmp_line_assign la
    GROUP BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE, COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY');

    DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
    CREATE TEMPORARY TABLE tmp_ranked_lines (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
        ARTICLE_ID          VARCHAR(200) NULL,
        BATCH_ID            VARCHAR(200) NULL,
        QUANTITY            INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

        
        SHORT_FLAG          INT NOT NULL,   
        NO_INV_FLAG         INT NOT NULL,   

        RN BIGINT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, RN)
    ) ENGINE=INNODB;

    
    INSERT INTO tmp_ranked_lines
    SELECT
        la.PARENT_ORDER_ID,
        la.CLIENT_ORDER_TYPE,
        COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY') AS CLUSTER_ID,
        la.ORDER_LINE_ID,
        la.ARTICLE_ID,
        la.BATCH_ID,
        la.QUANTITY,
        la.DISPLAY_OPERATOR_INSTRUCTION,

        
        CASE
            WHEN COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = 'NO_INVENTORY' THEN 0
            WHEN la.SHORT_FLAG_SUPPLY = 1 THEN 1
            ELSE 0
        END AS SHORT_FLAG,

        CASE
            WHEN COALESCE(la.ASSIGNED_CLUSTER_ID,'NO_INVENTORY') = 'NO_INVENTORY' THEN 1
            ELSE 0
        END AS NO_INV_FLAG,

        ROW_NUMBER() OVER (
            PARTITION BY la.PARENT_ORDER_ID, la.CLIENT_ORDER_TYPE, COALESCE(la.ASSIGNED_CLUSTER_ID, 'NO_INVENTORY')
            ORDER BY la.QUANTITY DESC, la.ARTICLE_ID, la.ORDER_LINE_ID
        ) AS RN
    FROM tmp_line_assign la;

    SELECT COUNT(*) INTO v_cnt_ranked FROM tmp_ranked_lines;
    IF v_cnt_ranked <> v_cnt_line_assign THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_RANKING: tmp_line_assign=', v_cnt_line_assign,
                              ', tmp_ranked_lines=', v_cnt_ranked);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
    CREATE TEMPORARY TABLE tmp_final_map (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        ORDER_LINE_ID       VARCHAR(36)  NOT NULL,
        ARTICLE_ID          VARCHAR(200) NULL,
        BATCH_ID            VARCHAR(200) NULL,
        QUANTITY            INT NOT NULL,
        DISPLAY_OPERATOR_INSTRUCTION TEXT NULL,

        SPLIT_GROUP         INT NOT NULL,

        
        IS_SUSPENDED_GROUP  INT NOT NULL,   
        IS_SHORT_LINE       INT NOT NULL,   

        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, ORDER_LINE_ID),
        UNIQUE KEY uq_parent_line (PARENT_ORDER_ID, ORDER_LINE_ID),
        KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP)
    ) ENGINE=INNODB;

    INSERT INTO tmp_final_map
    SELECT
        r.PARENT_ORDER_ID,
        r.CLIENT_ORDER_TYPE,
        r.CLUSTER_ID,
        r.ORDER_LINE_ID,
        r.ARTICLE_ID,
        r.BATCH_ID,
        r.QUANTITY,
        r.DISPLAY_OPERATOR_INSTRUCTION,

        1 + ((r.RN - 1) * p.GRP_CNT) DIV p.LINE_CNT AS SPLIT_GROUP,

        
        r.NO_INV_FLAG AS IS_SUSPENDED_GROUP,

        
        r.SHORT_FLAG AS IS_SHORT_LINE
    FROM tmp_ranked_lines r
    JOIN tmp_cluster_plan p
      ON p.PARENT_ORDER_ID   = r.PARENT_ORDER_ID
     AND p.CLIENT_ORDER_TYPE = r.CLIENT_ORDER_TYPE
     AND p.CLUSTER_ID        = r.CLUSTER_ID;

    SELECT COUNT(*) INTO v_cnt_final FROM tmp_final_map;
    IF v_cnt_final <> v_cnt_ranked THEN
        SET v_errmsg = CONCAT('LINE_LOSS_AFTER_FINAL_MAP: tmp_ranked_lines=', v_cnt_ranked,
                              ', tmp_final_map=', v_cnt_final);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;


    

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_pre_lines, v_pre_qty
    FROM tmp_lines;

    SELECT COUNT(*), COALESCE(SUM(QUANTITY),0)
      INTO v_post_lines, v_post_qty
    FROM tmp_final_map;

    IF v_pre_lines <> v_post_lines OR v_pre_qty <> v_post_qty THEN
        SET v_errmsg = CONCAT(
            'CONSERVATION_FAILED: PRE_LINES=', v_pre_lines,
            ', POST_LINES=', v_post_lines,
            ', PRE_QTY=', v_pre_qty,
            ', POST_QTY=', v_post_qty
        );
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_lines tl
    LEFT JOIN tmp_final_map fm
      ON fm.PARENT_ORDER_ID = tl.PARENT_ORDER_ID
     AND fm.ORDER_LINE_ID   = tl.ORDER_LINE_ID
    WHERE fm.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('MISSING_LINES_IN_OUTPUT=', v_missing_lines);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

        

    DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
    CREATE TEMPORARY TABLE tmp_cat_seq (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CAT_SEQ             INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE)
    ) ENGINE=INNODB;

    INSERT INTO tmp_cat_seq
    SELECT
        x.PARENT_ORDER_ID,
        x.CLIENT_ORDER_TYPE,
        ROW_NUMBER() OVER (PARTITION BY x.PARENT_ORDER_ID ORDER BY x.CLIENT_ORDER_TYPE) AS CAT_SEQ
    FROM (SELECT DISTINCT PARENT_ORDER_ID, CLIENT_ORDER_TYPE FROM tmp_lines_cat) X;

    DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
    CREATE TEMPORARY TABLE tmp_groupmax (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        MAX_GRP             INT NOT NULL,
        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_groupmax
    SELECT PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, MAX(SPLIT_GROUP) AS MAX_GRP
      FROM tmp_final_map
     GROUP BY PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID;

    DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
    CREATE TEMPORARY TABLE tmp_child_orders (
        PARENT_ORDER_ID     VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE   VARCHAR(100) NOT NULL,
        CLUSTER_ID          VARCHAR(50)  NOT NULL,
        SPLIT_GROUP         INT NOT NULL,
        CHILD_ORDER_ID      VARCHAR(180) NOT NULL,
        CHILD_STATUS        ENUM('PENDING','ORDER_SUSPENDED') NOT NULL,

        
        HAS_SHORT_LINES     INT NOT NULL DEFAULT 0,  
        HAS_NO_INV_LINES    INT NOT NULL DEFAULT 0,  

        PRIMARY KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, CLUSTER_ID, SPLIT_GROUP),
        KEY (CHILD_ORDER_ID),
        KEY (CHILD_STATUS)
    ) ENGINE=INNODB;

    INSERT INTO tmp_child_orders
    SELECT
        fm.PARENT_ORDER_ID,
        fm.CLIENT_ORDER_TYPE,
        fm.CLUSTER_ID,
        fm.SPLIT_GROUP,

        CASE
            WHEN gm.MAX_GRP = 1 THEN
                CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID)
            ELSE
                CONCAT(fm.PARENT_ORDER_ID, '-', cs.CAT_SEQ, '-', fm.CLUSTER_ID, '-', LPAD(fm.SPLIT_GROUP, 3, '0'))
        END AS CHILD_ORDER_ID,

        
        CASE
            WHEN MAX(fm.IS_SUSPENDED_GROUP) = 1 THEN 'ORDER_SUSPENDED'
            ELSE 'PENDING'
        END AS CHILD_STATUS,

        
        CASE WHEN MAX(fm.IS_SHORT_LINE) = 1 THEN 1 ELSE 0 END AS HAS_SHORT_LINES,
        CASE WHEN MAX(fm.IS_SUSPENDED_GROUP) = 1 THEN 1 ELSE 0 END AS HAS_NO_INV_LINES

    FROM tmp_final_map fm
    JOIN tmp_cat_seq cs
      ON cs.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
     AND cs.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
    JOIN tmp_groupmax gm
      ON gm.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
     AND gm.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
     AND gm.CLUSTER_ID        = fm.CLUSTER_ID
    GROUP BY
        fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.SPLIT_GROUP,
        gm.MAX_GRP, cs.CAT_SEQ;

    SELECT COUNT(*) INTO v_child_cnt FROM tmp_child_orders;


	

SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_all,
        v_total_qty_all
    FROM tmp_line_assign;
    
    SELECT
        COUNT(*),
        COALESCE(SUM(QUANTITY),0)
    INTO
        v_total_lines_pickable,
        v_total_qty_pickable
    FROM tmp_line_assign
    WHERE SHORT_FLAG_SCHEMA = 0
      AND COALESCE(ASSIGNED_CLUSTER_ID,'NO_INVENTORY') <> 'NO_INVENTORY';

    SELECT
        COALESCE(SUM(a.ALLOC_QTY),0),
        COALESCE(COUNT(DISTINCT CONCAT(a.PARENT_ORDER_ID,'|',a.CLIENT_ORDER_TYPE,'|',a.ORDER_LINE_ID)),0)
    INTO
        v_alloc_qty_total,
        v_alloc_lines_total
    FROM tmp_line_alloc a;

DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
CREATE TEMPORARY TABLE tmp_reco1 (
    STATION_ID VARCHAR(50) NOT NULL,
    CLUSTER_ID VARCHAR(50) NULL,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
CREATE TEMPORARY TABLE tmp_reco2 (
    STATION_ID   VARCHAR(50) NOT NULL,
    CLUSTER_ID   VARCHAR(50) NULL,
    IS_SELECTED  INT NOT NULL DEFAULT 0,
    IS_NO_WAVE   INT NOT NULL DEFAULT 0,
    PRIMARY KEY (STATION_ID),
    KEY (CLUSTER_ID),
    KEY (IS_NO_WAVE, IS_SELECTED)
) ENGINE=INNODB;

DROP TEMPORARY TABLE IF EXISTS tmp_reco2_avail_clusters;
CREATE TEMPORARY TABLE tmp_reco2_avail_clusters (
    CLUSTER_ID VARCHAR(50) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


IF v_has_hw_station = 0 THEN

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT STATION_ID, NULL
      FROM tmp_user_stations;

    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT STATION_ID, NULL, 1, 0
      FROM tmp_user_stations;

ELSE

    
    INSERT IGNORE INTO tmp_reco1 (STATION_ID, CLUSTER_ID)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50))
      FROM hw_station_master hs
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
    SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
           CAST(hs.CLUSTER_ID AS CHAR(50)),
           1 AS IS_SELECTED,
           0 AS IS_NO_WAVE
      FROM tmp_user_stations us
      JOIN hw_station_master hs
        ON CAST(hs.STATION_ID AS CHAR(50)) = CAST(us.STATION_ID AS CHAR(50))
     WHERE hs.STATION_ID IS NOT NULL
       AND hs.CLUSTER_ID IS NOT NULL;

    
    IF v_has_hw_wave_status = 1 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT DISTINCT CAST(hs.STATION_ID AS CHAR(50)),
               CAST(hs.CLUSTER_ID AS CHAR(50)),
               0 AS IS_SELECTED,
               1 AS IS_NO_WAVE
          FROM hw_station_master hs
         WHERE hs.STATION_ID IS NOT NULL
           AND hs.CLUSTER_ID IS NOT NULL
           AND LOWER(REPLACE(COALESCE(hs.wave_status,''),' ','_')) IN ('no_wave','nowave','no-wave');
    END IF;

    
    IF v_user_station_cnt = 0 AND v_has_hw_wave_status = 0 THEN
        INSERT IGNORE INTO tmp_reco2 (STATION_ID, CLUSTER_ID, IS_SELECTED, IS_NO_WAVE)
        SELECT STATION_ID, CLUSTER_ID, 0, 0 FROM tmp_reco1;
    END IF;

END IF;


INSERT IGNORE INTO tmp_reco2_avail_clusters (CLUSTER_ID)
SELECT DISTINCT COALESCE(CLUSTER_ID,'?')
  FROM tmp_reco2
 WHERE CLUSTER_ID IS NOT NULL;



DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
CREATE TEMPORARY TABLE tmp_job_cluster_stats (
    CLUSTER_ID   VARCHAR(50) NOT NULL,
    ORDER_LINES  BIGINT NOT NULL,
    ORDER_QTY    BIGINT NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;

INSERT INTO tmp_job_cluster_stats (CLUSTER_ID, ORDER_LINES, ORDER_QTY)
SELECT
    co.CLUSTER_ID,
    COUNT(DISTINCT co.CHILD_ORDER_ID) AS ORDER_LINES,
    COALESCE(SUM(fm.QUANTITY),0)      AS ORDER_QTY
FROM tmp_child_orders co
LEFT JOIN tmp_final_map fm
  ON fm.PARENT_ORDER_ID   = co.PARENT_ORDER_ID
 AND fm.CLIENT_ORDER_TYPE = co.CLIENT_ORDER_TYPE
 AND fm.CLUSTER_ID        = co.CLUSTER_ID
 AND fm.SPLIT_GROUP       = co.SPLIT_GROUP

WHERE co.CLUSTER_ID <> 'NO_INVENTORY'
GROUP BY co.CLUSTER_ID;



DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco1_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco1_total_lines,
    @reco1_total_qty
FROM tmp_job_cluster_stats js;


INSERT INTO tmp_reco1_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID ORDER BY r.STATION_ID SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco1_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco1_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco1_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco1_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco1 r
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
CREATE TEMPORARY TABLE tmp_reco2_cluster_stats (
    CLUSTER_ID    VARCHAR(50) NOT NULL,
    STATIONS_CSV  TEXT NOT NULL,
    STATION_CNT   BIGINT NOT NULL,
    ORDER_LINES   BIGINT NOT NULL,
    PCT_LINES     DECIMAL(10,2) NOT NULL,
    ORDER_QTY     BIGINT NOT NULL,
    PCT_QTY       DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (CLUSTER_ID)
) ENGINE=INNODB;


SELECT
    COALESCE(SUM(js.ORDER_LINES),0),
    COALESCE(SUM(js.ORDER_QTY),0)
INTO
    @reco2_total_lines,
    @reco2_total_qty
FROM tmp_job_cluster_stats js
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = js.CLUSTER_ID;


INSERT INTO tmp_reco2_cluster_stats
SELECT
    COALESCE(r.CLUSTER_ID,'?') AS CLUSTER_ID,

    
    COALESCE(GROUP_CONCAT(DISTINCT r.STATION_ID
                          ORDER BY r.IS_NO_WAVE DESC, r.IS_SELECTED DESC, r.STATION_ID
                          SEPARATOR ','), '') AS STATIONS_CSV,
    COALESCE(COUNT(DISTINCT r.STATION_ID),0) AS STATION_CNT,

    COALESCE(js.ORDER_LINES,0) AS ORDER_LINES,
    CASE
        WHEN COALESCE(@reco2_total_lines,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_LINES,0) * 100.0) / @reco2_total_lines, 2)
    END AS PCT_LINES,

    COALESCE(js.ORDER_QTY,0) AS ORDER_QTY,
    CASE
        WHEN COALESCE(@reco2_total_qty,0) = 0 THEN 0.00
        ELSE ROUND((COALESCE(js.ORDER_QTY,0) * 100.0) / @reco2_total_qty, 2)
    END AS PCT_QTY

FROM tmp_reco2 r
JOIN tmp_reco2_avail_clusters ac
  ON ac.CLUSTER_ID = r.CLUSTER_ID
LEFT JOIN tmp_job_cluster_stats js
  ON js.CLUSTER_ID = r.CLUSTER_ID
GROUP BY COALESCE(r.CLUSTER_ID,'?'), js.ORDER_LINES, js.ORDER_QTY;



SET @reco1_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco1_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);

SET @reco2_cluster_json := (
    SELECT COALESCE(JSON_ARRAYAGG(j), JSON_ARRAY())
    FROM (
        SELECT JSON_OBJECT(
            'CLUSTER_ID',   CLUSTER_ID,
            'STATION_ID', STATIONS_CSV,
            'STATION_CNT',  STATION_CNT,
            'ORDER_LINES',  ORDER_LINES,
            '%_LINES',      PCT_LINES,
            'ORDER_QTY',    ORDER_QTY,
            '%_QTY',        PCT_QTY
        ) AS j
        FROM tmp_reco2_cluster_stats
        ORDER BY ORDER_LINES DESC, CLUSTER_ID
    ) X
);



IF v_has_reco1 = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2 = 1 THEN
    UPDATE picklist_split_order_master
      SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco1_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_1 = CAST(@reco1_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco2_alt = 1 THEN
    UPDATE picklist_split_order_master
       SET recommendation_2 = CAST(@reco2_cluster_json AS JSON)
     WHERE ID = v_ruleLog_id;
END IF;

IF v_has_reco_col = 1 THEN
   UPDATE picklist_split_order_master
SET RECOMMENDATION = JSON_OBJECT(
    'RECOMMENDATION_1_ALL_STATIONS', CAST(@reco1_cluster_json AS JSON),
    'RECOMMENDATION_2_SELECTED_PLUS_NO_WAVE', CAST(@reco2_cluster_json AS JSON),

    'STATION_PREF_MODE', v_station_mode,
    'USER_SELECTED_STATIONS', (
        SELECT COALESCE(GROUP_CONCAT(STATION_ID ORDER BY STATION_ID SEPARATOR ','), '')
        FROM tmp_user_stations
    ),
    'RULE_ID', v_rule_id,
    'RULE_LOG_ID', v_ruleLog_id,
    'TOTAL_INITIAL_ORDERS', v_parent_cnt,
    'TOTAL_SPLIT_ORDERS', v_child_cnt,

    'INITIAL_ORDER_LINES', v_line_cnt,
    'AFTER_ALLOCATION_ORDER_LINES', v_cnt_final,

    'TOTAL_LINES_PICKABLE', v_total_lines_pickable,

    
    'TOTAL_QTY_ALL', v_pre_qty,
    'TOTAL_QTY_PICKABLE', v_total_qty_pickable,

    
    'ALLOC_QTY_TOTAL', v_post_qty,
    'ALLOC_LINES_TOTAL', v_alloc_lines_total,

    'NOTES', JSON_OBJECT(
        'PARENT_FIELD', 'PARENT_ORDER_ID',
        'CHILD_FIELD', 'ORDER_ID',
        'SUB_ORDER_ID', 'NOT_USED',
        'RESERVATION_KEY', v_reservation_key,
        'RESERVATION_TTL_MINUTES', v_res_ttl_minutes
    )
)
WHERE ID = v_ruleLog_id;

END IF;

    

IF v_is_dry_run = 0 THEN

    
    SET @or_cols = 'PARENT_ORDER_ID, ORDER_TYPE, ORDER_ID, ORDER_REQUEST_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @or_sel  = 'co.PARENT_ORDER_ID, co.CLIENT_ORDER_TYPE, co.CHILD_ORDER_ID, co.CHILD_STATUS, CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_or_cluster = 1 THEN
        SET @or_cols = CONCAT(@or_cols, ', CLUSTER_ID');
        SET @or_sel  = CONCAT(@or_sel,  ', co.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_request_data (', @or_cols, ') ',
        'SELECT ', @or_sel, ' ',
        '  FROM tmp_child_orders co ',
        '  LEFT JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        ' WHERE r.ORDER_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SET @line_cols = 'WMS_ORDER_REQUEST_DATA_ID, ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, BATCH_ID, DISPLAY_OPERATOR_INSTRUCTION, ORDER_LINE_PROCESS_STATUS, INSERTED_TIMESTAMP, INSERTED_BY';
    SET @line_sel  = 'r.WMS_ORDER_REQUEST_DATA_ID, r.ORDER_ID, fm.ORDER_LINE_ID, fm.ARTICLE_ID, fm.QUANTITY, fm.BATCH_ID, fm.DISPLAY_OPERATOR_INSTRUCTION, ''PENDING'', CURRENT_TIMESTAMP(3), ''BACKEND-SERVICE''';

    IF v_has_ol_cluster = 1 THEN
        SET @line_cols = CONCAT(@line_cols, ', CLUSTER_ID');
        SET @line_sel  = CONCAT(@line_sel,  ', fm.CLUSTER_ID');
    END IF;

    SET @sql = CONCAT(
        'INSERT INTO wms_to_wcs_order_line_request_data (', @line_cols, ') ',
        'SELECT ', @line_sel, ' ',
        '  FROM tmp_final_map fm ',
        '  JOIN tmp_child_orders co ',
        '    ON co.PARENT_ORDER_ID = fm.PARENT_ORDER_ID ',
        '   AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE ',
        '   AND co.CLUSTER_ID = fm.CLUSTER_ID ',
        '   AND co.SPLIT_GROUP = fm.SPLIT_GROUP ',
        '  JOIN wms_to_wcs_order_request_data r ',
        '    ON r.ORDER_ID = co.CHILD_ORDER_ID ',
        '  LEFT JOIN wms_to_wcs_order_line_request_data lr ',
        '    ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID ',
        '   AND lr.ORDER_LINE_ID = fm.ORDER_LINE_ID ',
        ' WHERE lr.ORDER_LINE_ID IS NULL'
    );

    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

    
    SELECT COUNT(*) INTO v_missing_lines
    FROM tmp_final_map fm
    JOIN tmp_child_orders co
      ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
     AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
     AND co.CLUSTER_ID        = fm.CLUSTER_ID
     AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
    JOIN wms_to_wcs_order_request_data r
      ON r.ORDER_ID = co.CHILD_ORDER_ID
    LEFT JOIN wms_to_wcs_order_line_request_data lr
      ON lr.WMS_ORDER_REQUEST_DATA_ID = r.WMS_ORDER_REQUEST_DATA_ID
     AND lr.ORDER_LINE_ID            = fm.ORDER_LINE_ID
    WHERE lr.ORDER_LINE_ID IS NULL;

    IF v_missing_lines > 0 THEN
        SET v_errmsg = CONCAT('DB_WRITE_MISSING_LINES=', v_missing_lines, ' (expected all tmp_final_map lines in DB)');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_errmsg;
    END IF;

    
    SELECT COUNT(*) INTO v_cnt_db_child_lines
    FROM wms_to_wcs_order_line_request_data lr
    JOIN wms_to_wcs_order_request_data r
      ON r.WMS_ORDER_REQUEST_DATA_ID = lr.WMS_ORDER_REQUEST_DATA_ID
    JOIN tmp_child_orders co
      ON co.CHILD_ORDER_ID = r.ORDER_ID;

ELSE
    SET v_cnt_db_child_lines = 0;
END IF;



DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
CREATE TEMPORARY TABLE tmp_child_demand (
    ORDER_ID VARCHAR(180) NOT NULL,
    PARENT_ORDER_ID VARCHAR(100) NOT NULL,
    CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
    DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,
    ARTICLE_ID VARCHAR(200) NOT NULL,
    BATCH_ID   VARCHAR(200) NOT NULL,
    DEMAND_QTY BIGINT NOT NULL,
    PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
    KEY (PARENT_ORDER_ID, CLIENT_ORDER_TYPE, DEMAND_CLUSTER_ID),
    KEY (ARTICLE_ID, BATCH_ID)
) ENGINE=INNODB;

INSERT INTO tmp_child_demand
SELECT
    co.CHILD_ORDER_ID AS ORDER_ID,
    fm.PARENT_ORDER_ID,
    fm.CLIENT_ORDER_TYPE,
    fm.CLUSTER_ID AS DEMAND_CLUSTER_ID,
    fm.ARTICLE_ID,
    fm.BATCH_ID,
    SUM(fm.QUANTITY) AS DEMAND_QTY
FROM tmp_final_map fm
JOIN tmp_child_orders co
  ON co.PARENT_ORDER_ID   = fm.PARENT_ORDER_ID
 AND co.CLIENT_ORDER_TYPE = fm.CLIENT_ORDER_TYPE
 AND co.CLUSTER_ID        = fm.CLUSTER_ID
 AND co.SPLIT_GROUP       = fm.SPLIT_GROUP
WHERE fm.IS_SUSPENDED_GROUP = 0
  AND fm.ARTICLE_ID IS NOT NULL
  AND fm.BATCH_ID IS NOT NULL
  AND fm.CLUSTER_ID <> 'NO_INVENTORY'
  AND co.CHILD_STATUS = 'PENDING'
GROUP BY co.CHILD_ORDER_ID, fm.PARENT_ORDER_ID, fm.CLIENT_ORDER_TYPE, fm.CLUSTER_ID, fm.ARTICLE_ID, fm.BATCH_ID;

IF (SELECT COUNT(*) FROM tmp_child_demand) > 0 THEN

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
    CREATE TEMPORARY TABLE tmp_res_need_clusters (
        ORDER_ID         VARCHAR(180) NOT NULL,
        ARTICLE_ID       VARCHAR(200) NOT NULL,
        BATCH_ID         VARCHAR(200) NOT NULL,
        CLUSTER_ID       VARCHAR(50)  NOT NULL,
        DEMAND_QTY       BIGINT NOT NULL,
        PRIORITY         INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,
        CLUSTER_SUPPLY   BIGINT NOT NULL,
        CUM_SUPPLY_PREV  BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID),
        KEY idx_need (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_need_clusters
        (ORDER_ID, ARTICLE_ID, BATCH_ID, CLUSTER_ID, DEMAND_QTY, PRIORITY, SRC_CLUSTER_RANK, CLUSTER_SUPPLY, CUM_SUPPLY_PREV)
    SELECT
        z.ORDER_ID,
        z.ARTICLE_ID,
        z.BATCH_ID,
        z.CLUSTER_ID,
        z.DEMAND_QTY,
        z.PRIORITY,
        z.SRC_CLUSTER_RANK,
        z.CLUSTER_SUPPLY,
        COALESCE(z.cum_supply_prev, 0) AS CUM_SUPPLY_PREV
    FROM (
        SELECT
            d.ORDER_ID,
            d.PARENT_ORDER_ID,
            d.CLIENT_ORDER_TYPE,
            d.DEMAND_CLUSTER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            d.DEMAND_QTY,

            cs.CLUSTER_ID,
            cs.SUPPLY_QTY AS CLUSTER_SUPPLY,

            CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END AS PRIORITY,
            COALESCE(bcs.SCORE_RANK, 999999) AS SRC_CLUSTER_RANK,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
            ) AS cum_supply,

            SUM(cs.SUPPLY_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY
                    CASE WHEN cs.CLUSTER_ID = d.DEMAND_CLUSTER_ID THEN 0 ELSE 1 END,
                    COALESCE(bcs.SCORE_RANK, 999999),
                    cs.CLUSTER_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_supply_prev

        FROM tmp_child_demand d
        JOIN tmp_cluster_supply cs
          ON cs.ARTICLE_ID = d.ARTICLE_ID
         AND cs.BATCH_ID   = d.BATCH_ID
        LEFT JOIN tmp_bucket_cluster_score bcs
          ON bcs.PARENT_ORDER_ID   = d.PARENT_ORDER_ID
         AND bcs.CLIENT_ORDER_TYPE = d.CLIENT_ORDER_TYPE
         AND bcs.CLUSTER_ID        = cs.CLUSTER_ID
    ) z
    WHERE COALESCE(z.cum_supply_prev, 0) < z.DEMAND_QTY;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
    CREATE TEMPORARY TABLE tmp_res_bins (
        ORDER_ID VARCHAR(180) NOT NULL,
        PARENT_ORDER_ID VARCHAR(100) NOT NULL,
        CLIENT_ORDER_TYPE VARCHAR(100) NOT NULL,
        DEMAND_CLUSTER_ID VARCHAR(50) NOT NULL,

        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,

        AVAIL_QTY BIGINT NOT NULL,
        LAST_TS DATETIME(3) NULL,

        PRIORITY INT NOT NULL,
        SRC_CLUSTER_RANK INT NOT NULL,

        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY idx_rank (ORDER_ID, ARTICLE_ID, BATCH_ID, PRIORITY, SRC_CLUSTER_RANK),
        KEY (BIN_ID),
        KEY (ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_bins
    SELECT
        d.ORDER_ID,
        d.PARENT_ORDER_ID,
        d.CLIENT_ORDER_TYPE,
        d.DEMAND_CLUSTER_ID,

        ib.CLUSTER_ID AS SRC_CLUSTER_ID,
        ib.ARTICLE_ID,
        ib.BATCH_ID,
        ib.BIN_ID,
        ib.AISLE_NUMBER,

        ib.AVAIL_QTY,
        ib.LAST_TS,

        nc.PRIORITY,
        nc.SRC_CLUSTER_RANK
    FROM tmp_child_demand d
    JOIN tmp_res_need_clusters nc
      ON nc.ORDER_ID   = d.ORDER_ID
     AND nc.ARTICLE_ID = d.ARTICLE_ID
     AND nc.BATCH_ID   = d.BATCH_ID
    
    JOIN tmp_inv_bin ib
      ON ib.ARTICLE_ID = d.ARTICLE_ID
     AND ib.BATCH_ID   = d.BATCH_ID
     AND ib.CLUSTER_ID = nc.CLUSTER_ID
    WHERE ib.AVAIL_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
    CREATE TEMPORARY TABLE tmp_res_alloc_child (
        ORDER_ID VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        BIN_ID INT NOT NULL,
        AISLE_NUMBER VARCHAR(50) NOT NULL,
        SRC_CLUSTER_ID VARCHAR(50) NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID, BIN_ID),
        KEY (BIN_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_alloc_child
    SELECT
        rb.ORDER_ID,
        rb.ARTICLE_ID,
        rb.BATCH_ID,
        rb.BIN_ID,
        rb.AISLE_NUMBER,
        rb.SRC_CLUSTER_ID,
        rb.RESERVED_QTY
    FROM (
        SELECT
            d.ORDER_ID,
            d.ARTICLE_ID,
            d.BATCH_ID,
            b.BIN_ID,
            b.AISLE_NUMBER,
            b.SRC_CLUSTER_ID,
            b.AVAIL_QTY,
            b.LAST_TS,
            d.DEMAND_QTY,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
            ) AS cum_avail,

            SUM(b.AVAIL_QTY) OVER (
                PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
            ) AS cum_avail_prev,

            LEAST(
                b.AVAIL_QTY,
                GREATEST(d.DEMAND_QTY - COALESCE(
                    SUM(b.AVAIL_QTY) OVER (
                        PARTITION BY d.ORDER_ID, d.ARTICLE_ID, d.BATCH_ID
                        ORDER BY b.PRIORITY ASC, b.SRC_CLUSTER_RANK ASC, b.AVAIL_QTY DESC, b.LAST_TS DESC, b.BIN_ID
                        ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                    ), 0
                ), 0)
            ) AS RESERVED_QTY

        FROM tmp_child_demand d
        JOIN tmp_res_bins b
          ON b.ORDER_ID   = d.ORDER_ID
         AND b.ARTICLE_ID = d.ARTICLE_ID
         AND b.BATCH_ID   = d.BATCH_ID
    ) rb
    WHERE rb.RESERVED_QTY > 0;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
    CREATE TEMPORARY TABLE tmp_res_shortfall (
        ORDER_ID   VARCHAR(180) NOT NULL,
        ARTICLE_ID VARCHAR(200) NOT NULL,
        BATCH_ID   VARCHAR(200) NOT NULL,
        DEMAND_QTY BIGINT NOT NULL,
        RESERVED_QTY BIGINT NOT NULL,
        SHORT_QTY BIGINT NOT NULL,
        PRIMARY KEY (ORDER_ID, ARTICLE_ID, BATCH_ID),
        KEY (ORDER_ID)
    ) ENGINE=INNODB;

    INSERT INTO tmp_res_shortfall (ORDER_ID, ARTICLE_ID, BATCH_ID, DEMAND_QTY, RESERVED_QTY, SHORT_QTY)
    SELECT
        d.ORDER_ID,
        d.ARTICLE_ID,
        d.BATCH_ID,
        d.DEMAND_QTY,
        COALESCE(a.got,0) AS RESERVED_QTY,
        GREATEST(d.DEMAND_QTY - COALESCE(a.got,0), 0) AS SHORT_QTY
    FROM tmp_child_demand d
    LEFT JOIN (
        SELECT ORDER_ID, ARTICLE_ID, BATCH_ID, SUM(RESERVED_QTY) AS got
          FROM tmp_res_alloc_child
         GROUP BY ORDER_ID, ARTICLE_ID, BATCH_ID
    ) a
      ON a.ORDER_ID = d.ORDER_ID
     AND a.ARTICLE_ID = d.ARTICLE_ID
     AND a.BATCH_ID = d.BATCH_ID
    WHERE COALESCE(a.got,0) < d.DEMAND_QTY;

END IF;


	
    

    IF v_is_dry_run = 0 THEN

        UPDATE wms_to_wcs_order_level_pre_staged_data p
        JOIN tmp_parent_orders t
          ON t.PRE_STAGED_REQ_ID = p.WMS_ORDER_REQUEST_DATA_ID
        SET p.IS_STAGED = 1,
            p.UPDATED_TIMESTAMP = CURRENT_TIMESTAMP(3),
            p.UPDATED_BY = 'SPLIT-OPS-V6';
    END IF;

    UPDATE picklist_split_order_master
       SET IS_PROCESSED='2',
           ORDERSPLIT_ENDTIME = NOW(),
           RULE_STATS = JSON_OBJECT(
               'RULE_ID', v_rule_id,
               'RULE_LOG_ID', v_ruleLog_id,
               'RUN_PRIORITY', v_run_priority,
               'DRY_RUN', v_is_dry_run,
               'RESERVATION_KEY', v_reservation_key,
               'PARENTS_FOUND', v_parent_cnt,
               'LINES_CONSIDERED', v_line_cnt,
               'CHILD_ORDERS_CREATED', v_child_cnt,
               'MAX_ORDER_LINES_PER_ORDER', v_max_lines,
               'MAX_QUANTITY_PER_ORDER', v_max_qty,
               'TOL_LINES', v_tol_lines,
               'TOL_QTY', v_tol_qty,
               'HARD_LINES', v_hard_lines,
               'HARD_QTY', v_hard_qty,
               'SUSPEND_SHORT_LINES', v_suspend_short_lines,
               'CATEGORY_DEFAULT', 'FOOD',
               'NAMING', 'PARENT_ORDER_ID parent; ORDER_ID child/sub; SUB_ORDER_ID NOT USED',
               'STATION_PREF', JSON_OBJECT(
                   'MODE_USED', v_station_mode,
                   'USER_STATION_CNT', v_user_station_cnt,
                   'STATION_BIAS_ENABLED', v_use_station_bias
               ),
               'VALIDATIONS', JSON_OBJECT(
                   'tmp_lines', v_cnt_lines,
                   'tmp_lines_cat', v_cnt_lines_cat,
                   'tmp_line_assign', v_cnt_line_assign,
                   'tmp_ranked_lines', v_cnt_ranked,
                   'tmp_final_map', v_cnt_final,
                   'db_child_lines', v_cnt_db_child_lines
               ),
               'SUPPLY_CAP', JSON_OBJECT(
                   'ENABLED', 1,
                   'NOTE', 'Allocator decrements per SKU/BATCH/CLUSTER; assigns dominant cluster; NO_INVENTORY lines suspended'
               ),
               'RESERVATION', JSON_OBJECT(
                   'TTL_MINUTES', v_res_ttl_minutes,
                   'BLOCKED_LOCATION_EXCLUDED', 1,
                   'AUDIT_GRANULARITY', 'ORDER_ID+SKU/BATCH+BIN'
               )
           )
     WHERE ID = v_ruleLog_id;

    

    COMMIT;
    DO RELEASE_LOCK(v_lock_key);

    
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;

        SET v_tmp_user_stations_ready = 0;

        DROP TEMPORARY TABLE IF EXISTS tmp_user_stations;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_choice;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_category;
        DROP TEMPORARY TABLE IF EXISTS tmp_lines_cat;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster_raw;
        DROP TEMPORARY TABLE IF EXISTS tmp_aisle_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_global;
        DROP TEMPORARY TABLE IF EXISTS tmp_inv_bin;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_total_supply;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_snap_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_fallback;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_candidates;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_assign;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_k;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_cluster_score;
        DROP TEMPORARY TABLE IF EXISTS tmp_allowed_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_parent_cluster_load;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_supply_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_rem;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_alloc;
        DROP TEMPORARY TABLE IF EXISTS tmp_line_cluster_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_sku_line_queue;
        DROP TEMPORARY TABLE IF EXISTS tmp_cluster_plan;
        DROP TEMPORARY TABLE IF EXISTS tmp_ranked_lines;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_map;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_seq;
        DROP TEMPORARY TABLE IF EXISTS tmp_groupmax;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_orders;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2;
        DROP TEMPORARY TABLE IF EXISTS tmp_job_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco1_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_reco2_cluster_stats;
        DROP TEMPORARY TABLE IF EXISTS tmp_child_demand;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_need_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_bins;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_alloc_child;
        DROP TEMPORARY TABLE IF EXISTS tmp_res_shortfall;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_near_clusters;
        DROP TEMPORARY TABLE IF EXISTS tmp_pref_aisle_num;
        DROP TEMPORARY TABLE IF EXISTS tmp_empty_buckets;
        DROP TEMPORARY TABLE IF EXISTS tmp_final_first_cluster;
        DROP TEMPORARY TABLE IF EXISTS tmp_bucket_top_final;
    END;


SELECT
    v_rule_id AS RULE_ID,
    v_ruleLog_id AS RULE_LOG_ID,
    v_reservation_key AS RESERVATION_KEY,
    v_parent_cnt AS PARENTS_PROCESSED,
    v_line_cnt AS LINES_CONSIDERED,
    v_child_cnt AS CHILD_ORDERS_CREATED;



END sp_main */$$
DELIMITER ;

/* Procedure structure for procedure `Test_Auto_home` */

/*!50003 DROP PROCEDURE IF EXISTS  `Test_Auto_home` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `Test_Auto_home`()
BEGIN
		UPDATE `teleoperation_bool_data` SET `Auto Home Call Bit` = 0;
		SELECT SLEEP(2);
		UPDATE `teleoperation_bool_data` SET `Auto Home Call Bit` = 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `Test_Auto_start` */

/*!50003 DROP PROCEDURE IF EXISTS  `Test_Auto_start` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `Test_Auto_start`()
BEGIN
		UPDATE `teleoperation_bool_data` SET `Auto Start Bit` = 0;
		select sleep(2);
		UPDATE `teleoperation_bool_data` SET `Auto Start Bit` = 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_checkbotonhome` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_checkbotonhome` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_checkbotonhome`(
    IN botID VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    SELECT 
        CASE 
            WHEN `TYPE` = 'home' THEN 1
            ELSE 0
        END AS is_home
    FROM `subcontroller_reservations_master` 
    WHERE `BOT_ID` = botID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_DeleteFromControllerReservations` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_DeleteFromControllerReservations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_DeleteFromControllerReservations`(
	in locationID INT,
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		delete from `controller_reservations_master` where `LOCATION_ID` = locationID and `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_DeleteFutureTask` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_DeleteFutureTask` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_DeleteFutureTask`(
	in task_id_ int
    )
BEGIN
		UPDATE `order_bin_mapping` SET `STATUS`= 'PENDING', `INSERTED_TIMESTAMP` = NOW() WHERE `BOT_ID` = (SELECT `BOT_ID` FROM `task_master` WHERE `TASK_ID` = task_id_);
		DELETE FROM `task_master` WHERE `TASK_ID` = task_id_;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_DeleteLastStepOfTaskDetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_DeleteLastStepOfTaskDetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_DeleteLastStepOfTaskDetail`(
	in taskDetailID int
    )
BEGIN
		DECLARE _step_id INT;
		 DECLARE EXIT HANDLER FOR SQLEXCEPTION 
		    BEGIN
			-- If any error occurs, rollback the transaction
			ROLLBACK;
			SIGNAL SQLSTATE '45000' 
			SET MESSAGE_TEXT = 'Some Error occurred';
		    END;
		    -- Start transaction
		    START TRANSACTION;
		SELECT ID INTO _step_id  FROM `steps` WHERE `TASK_DETAIL_ID` = taskDetailID ORDER BY `COUNTER` DESC LIMIT 1;
		
		DELETE FROM `steps` 
		WHERE `ID` = _step_id;
		update `task_detail` set `COUNT_OF_STEPS` = `COUNT_OF_STEPS` - 1 where `TASK_DETAIL_ID` = taskDetailID;
		
		  COMMIT;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_DeleteTaskDetailsLeaveLast` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_DeleteTaskDetailsLeaveLast` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_DeleteTaskDetailsLeaveLast`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in avoidTaskDetail int
    )
BEGIN
		delete from `task_detail` WHERE `BOT_ID` = botID AND `STATUS` = 'PENDING' AND `TASK_DETAIL_ID` != avoidTaskDetail;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_GetAllReturnAisleBotCounts` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_GetAllReturnAisleBotCounts` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_GetAllReturnAisleBotCounts`()
BEGIN
    SELECT 
        LOCATION_ID AS ReturnAisleID,
        COUNT(*) AS BotCount
    FROM 
        controller_reservations_master
    WHERE 
        TYPE = 'RETURN_AISLE_ENTRY' 
    GROUP BY 
        LOCATION_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_IfAnyTaskAvailable` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_IfAnyTaskAvailable` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_IfAnyTaskAvailable`(
    )
BEGIN
		select `ORDER_BIN_ID` FROM `order_bin_mapping` WHERE `STATUS`='PENDING';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_InsertInControllerReservation` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_InsertInControllerReservation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_InsertInControllerReservation`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in locationID int,
	in destinationID int,
	in locationType varchar(100)
    )
BEGIN
		insert into `controller_reservations_master` (`LOCATION_ID`,`TYPE`,`BOT_ID`,`DESTINATION_ID`,`INSERTED_TIMESTAMP`) 
		values (locationID,locationType,botID,destinationID, now());
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_InsertInSubControllerReservation` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_InsertInSubControllerReservation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_InsertInSubControllerReservation`(
	in locationID int,
	IN locationType varchar(100)
    )
BEGIN
		insert into `subcontroller_reservations_master` (`LOCATION_ID`, `TYPE`) values (locationID, locationType);
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_InsertTaskDeatilReturnID` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_InsertTaskDeatilReturnID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_InsertTaskDeatilReturnID`(
	in taskMasterID int,
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in startLocationID int,
	in endLocationID int,
	in startPickPutSide varchar(50),
	in startZ double, 
	in endPickPutSide varchar(50),
	in endZ double, 
	in curStatus varchar(100),
	in taskDetailType varchar(50),
	in isTowerBuffer tinyint	
    )
BEGIN
		INSERT INTO `task_detail`(`TASK_MASTER_ID`,`BOT_ID`,`START_LOCATION_ID`,`END_LOCATION_ID`,`START_PICK_PUT_SIDE`,`START_Z`,`END_PICK_PUT_SIDE`,`END_Z`,
		`STATUS`,`UPDATED_TIMESTAMP`,`TASK_DETAIL_TYPE`,`IS_TOWER_BUFFER`,`INSERTED_TIMESTAMP`) VALUES 
		(taskMasterID, botID, startLocationID, endLocationID, startPickPutSide, startZ, endPickPutSide, endZ, curStatus, NOW(), taskDetailType, isTowerBuffer, now());
		
		 SELECT LAST_INSERT_ID() AS LAST_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_InsertTaskDeatilReturnIDRecovery` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_InsertTaskDeatilReturnIDRecovery` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_InsertTaskDeatilReturnIDRecovery`(
        in taskDetailId int,
	IN taskMasterID INT,
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN startLocationID INT,
	IN endLocationID INT,
	IN startPickPutSide VARCHAR(50),
	IN startZ DOUBLE, 
	IN endPickPutSide VARCHAR(50),
	IN endZ DOUBLE, 
	IN curStatus VARCHAR(100),
	IN taskDetailType VARCHAR(50),
	IN isTowerBuffer TINYINT	
    )
BEGIN
		INSERT INTO `task_detail`(`TASK_DETAIL_ID`,`TASK_MASTER_ID`,`BOT_ID`,`START_LOCATION_ID`,`END_LOCATION_ID`,`START_PICK_PUT_SIDE`,`START_Z`,`END_PICK_PUT_SIDE`,`END_Z`,
		`STATUS`,`UPDATED_TIMESTAMP`,`TASK_DETAIL_TYPE`,`IS_TOWER_BUFFER`,`INSERTED_TIMESTAMP`) VALUES 
		(taskDetailId, taskMasterID, botID, startLocationID, endLocationID, startPickPutSide, startZ, endPickPutSide, endZ, curStatus, NOW(), taskDetailType, isTowerBuffer, NOW());
		
		select taskDetailId as LAST_ID;
		 -- SELECT LAST_INSERT_ID() AS LAST_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_InsertTaskMasterReturnID` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_InsertTaskMasterReturnID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_InsertTaskMasterReturnID`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in fromLocationID int,
	in destinationLocationID INT,
	IN curStatus varchar(100), 
	in taskType VARCHAR(100)
    )
BEGIN
		INSERT INTO `task_master`(`BOT_ID`,`FROM_LOCATION_ID`,`DESTINATION_LOCATION_ID`,`STATUS`,`TASK_TYPE`,`INSERTED_TIMESTAMP`) VALUES 
		(botID, fromLocationID, destinationLocationID, curStatus, taskType, now());
		
		 SELECT LAST_INSERT_ID() AS LAST_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectAllAllocatedBinsByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectAllAllocatedBinsByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectAllAllocatedBinsByStationId`(in p_stationId int)
BEGIN
		select * from `order_bin_mapping`
		where `STATION_ID` = p_stationId
		and `STATUS` not in ('PENDING', 'TASK_COMPLETED', 'OPERATION_COMPLETED'); 
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectAllBotOnSubController` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectAllBotOnSubController` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectAllBotOnSubController`(
	in locationID int
    )
BEGIN
		select * 
		from `subcontroller_reservations_master` 
		where `LOCATION_ID` = locationID 
		and `BOT_ID` is not null;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectAllBotsOnController` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectAllBotsOnController` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectAllBotsOnController`(
	in locationID int
    )
BEGIN
		select * from `controller_reservations_master` where `LOCATION_ID` = locationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectAllocatedRobotsAtStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectAllocatedRobotsAtStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectAllocatedRobotsAtStation`(
	IN stationID INT
    )
BEGIN
		SELECT COUNT(`ORDER_BIN_ID`) FROM `order_bin_mapping` WHERE `STATION_ID` = stationID 
		AND BOT_ID IS NOT NULL AND TYPE IN ('RACK_PICK', 'STATION_PICK') AND STATUS != 'TASK_COMPLETED';
	
	/*
	select count(`ORDER_BIN_ID`) from `order_bin_mapping` where `STATION_ID` = stationID AND BOT_ID IS NOT NULL AND `TYPE` = 'RACK_PICK' and `STATUS` in ('TASK_ALLOCATED', 'BIN_PICKED', 'PENDING');*/
	
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectAllPendingStationToStationWithStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectAllPendingStationToStationWithStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectAllPendingStationToStationWithStationId`(IN p_stationId INT)
BEGIN
	if (p_stationId > 0) Then
		SELECT COUNT(`ORDER_BIN_ID`) FROM `order_bin_mapping`
		WHERE `STATION_ID` = p_stationId and type = 'RACK_PICK'
		AND `STATUS` IN ('PENDING');
	ELSE
		SELECT COUNT(`ORDER_BIN_ID`) FROM `order_bin_mapping`
		WHERE TYPE = 'RACK_PICK'
		AND `STATUS` IN ('PENDING');
	END IF;
	
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectAllRobotsComingToStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectAllRobotsComingToStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectAllRobotsComingToStationId`(in p_stationId int)
BEGIN
		select count(`ORDER_BIN_ID`) from `order_bin_mapping`
		where `STATION_ID` = p_stationId
		and `STATUS` in ('TASK_ALLOCATED', 'BIN_PICKED'); 
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectAllStationMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectAllStationMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectAllStationMaster`()
BEGIN
    SELECT * FROM `hw_station_master`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectBinByStoreLocationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectBinByStoreLocationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectBinByStoreLocationId`(
    IN p_locationId INT)
BEGIN		
		SELECT IFNULL ((SELECT `BIN_ID` FROM `store_bin_master` WHERE `LOCATION_ID` = p_locationId),0) AS BIN_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectBinLocationByOrderBinID` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectBinLocationByOrderBinID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectBinLocationByOrderBinID`(
	IN order_bin_id_ int
    )
BEGIN
		select obm.`BIN_ID`, sbm.`LOCATION_ID` from `order_bin_mapping` as obm
		left join `store_bin_master` as sbm on sbm.BIN_ID = obm.BIN_ID where obm.`ORDER_BIN_ID` = order_bin_id_;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectBufferCurSubControllerOfBotID` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectBufferCurSubControllerOfBotID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectBufferCurSubControllerOfBotID`(
    in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    SELECT `LOCATION_ID` , `IS_BUFFER`, `DESTINATION_ID`
    FROM `subcontroller_reservations_master` 
    WHERE `BOT_ID` = botID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectBufferParkingLevelConfig` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectBufferParkingLevelConfig` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectBufferParkingLevelConfig`()
BEGIN
		SELECT `TOWER_PARKING_Z` FROM `config_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectCurControllerOfBotID` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectCurControllerOfBotID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectCurControllerOfBotID`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		SELECT `LOCATION_ID` FROM `controller_reservations_master` WHERE `BOT_ID` = botID AND TYPE IN ('AISLE_ENTRY','RETURN_AISLE_ENTRY');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectMaxRobotsAllowedOnStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectMaxRobotsAllowedOnStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectMaxRobotsAllowedOnStation`(
	in stationID int
    )
BEGIN
		select `BOT_COUNT_CURRENT` from `wave_station_rule_mapping` where `STATION_ID` = stationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectMaxVelocity` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectMaxVelocity` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectMaxVelocity`()
BEGIN
		SELECT MAX(`VELOCITY`) AS velocity FROM `store_bin_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectOrderBinMappingWithStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectOrderBinMappingWithStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectOrderBinMappingWithStatus`(
	in stationID int
    )
BEGIN
		select COUNT(`ORDER_BIN_ID`) from `order_bin_mapping` where 
		`STATION_ID` = 'stationID' and status = 'POST_ON_STATION';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectPendingTaskDetailsWithNoSteps` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectPendingTaskDetailsWithNoSteps` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectPendingTaskDetailsWithNoSteps`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select * from `task_detail` where `STATUS` = 'PENDING' AND `BOT_ID` = botID and `IS_STEPS_INSERTED` = 0;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectPendingTaskMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectPendingTaskMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectPendingTaskMaster`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		Select * from `task_master` where `BOT_ID` = botID AND `STATUS` in ('PENDING') AND TASK_TYPE IN ('BIN_STORE_TO_ZONE');
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectRackOrderBinFromID` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectRackOrderBinFromID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectRackOrderBinFromID`(
	in orderBinID int
    )
BEGIN
		SELECT `BIN_ID`, `STATION_ID` FROM `order_bin_mapping` WHERE `ORDER_BIN_ID` = orderBinID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectReservationWithBothID` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectReservationWithBothID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectReservationWithBothID`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select `LOCATION_ID`, `TYPE`, `DESTINATION_ID` from `controller_reservations_master` where `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectStationConfig` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectStationConfig` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectStationConfig`(
	in StationID int
    )
BEGIN
		select * from `hw_station_master` where `STATION_ID` = StationID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `tm_SelectStationHomesConfig` */

/*!50003 DROP PROCEDURE IF EXISTS  `tm_SelectStationHomesConfig` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `tm_SelectStationHomesConfig`(
    IN StationID INT
)
BEGIN
	SELECT `ASSOCIATED_HOME_1`,`ASSOCIATED_HOME_2` FROM `hw_station_master` WHERE `STATION_ID` = StationID;
END */$$
DELIMITER ;