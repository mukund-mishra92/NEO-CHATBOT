
------------------------------------------------------------------------------------------------------------------------
/* Procedure structure for procedure `rm_SelectAutoRecoveryCmpBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectAutoRecoveryCmpBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectAutoRecoveryCmpBit`(
	in botID varchar(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select `Auto Recovery Complete` from `teleoperation_bool_data` WHERE `bot_id` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectBarcodeAndItsXAndYStep` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectBarcodeAndItsXAndYStep` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectBarcodeAndItsXAndYStep`(
   
   
  IN barcodeTag VARCHAR(10)
)
BEGIN
  SELECT
    `BARCODE_NUMBER` AS `BarcodeTag`,
    `X`              AS `XBarcode`,
    `Y`              AS `YBarcode`
  FROM
    `location_master`
  WHERE
    `IS_BARCODE` = 1
    
    and `BARCODE_NUMBER` = barcodeTag;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectBotlocation` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectBotlocation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectBotlocation`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
    SELECT `GRIDX`,`GRIDY`,`GRIDZ` from `bot_master` bm
    WHERE bm.`BOT_ID` = bot_id_ and bm.status="ENABLED";
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectBotMasterWithBotID` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectBotMasterWithBotID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectBotMasterWithBotID`(
	in botID varchar(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select * from `bot_master` where `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectBotXYZ` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectBotXYZ` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectBotXYZ`(IN _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
             
             select `GRIDX`,`GRIDY`,`GRIDZ` from `bot_master` WHERE `bot_id` = _bot_id;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectChargingBitWithBot` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectChargingBitWithBot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectChargingBitWithBot`(in botID varchar(50))
BEGIN
		select `CHARGING_BIT` from `bot_master` where `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectConfigMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectConfigMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectConfigMaster`(
    )
BEGIN
		select * from `config_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectCountOfStepsAlreadySent` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectCountOfStepsAlreadySent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectCountOfStepsAlreadySent`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select count(ID) from steps where `BOT_ID` = botID and LAST_SENT_TIMESTAMP is not null;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectCountOfStepsNeedsSent` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectCountOfStepsNeedsSent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectCountOfStepsNeedsSent`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select count(ID) from steps where `BOT_ID` = botID and LAST_SENT_TIMESTAMP is null;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectCurPendingTaskOnBot` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectCurPendingTaskOnBot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectCurPendingTaskOnBot`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select * from `task_master` where `BOT_ID` = botID and `STATUS` = 'PENDING';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectCurrentProcessingTask` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectCurrentProcessingTask` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectCurrentProcessingTask`(
	IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
	SELECT * FROM task_master where status = 'PROCESSING' AND BOT_ID = bot_id_ limit 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectCurrentProcessingTaskDetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectCurrentProcessingTaskDetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectCurrentProcessingTaskDetail`(
	IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select * from `task_detail` where BOT_ID = bot_id_ and `STATUS` = 'PROCESSING' ORDER BY `TASK_DETAIL_ID` LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectFutureTaskDetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectFutureTaskDetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectFutureTaskDetail`(
	IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select * from `task_detail` where `BOT_ID` = bot_id_ and `STATUS` = 'PENDING' ORDER BY `TASK_DETAIL_ID` LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectIPDetailForBotID` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectIPDetailForBotID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectIPDetailForBotID`(
	in _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		SELECT `IP`,`PORT`,`SIM_PORT` FROM `bot_master` WHERE `BOT_ID`=_bot_id;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectMaxStepCount` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectMaxStepCount` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectMaxStepCount`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		SELECT MAX(`COUNTER`) from `steps` where `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectMostRecentTaskDetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectMostRecentTaskDetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectMostRecentTaskDetail`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select `TASK_DETAIL_ID`,`TASK_MASTER_ID`,`BOT_ID`,`START_LOCATION_ID`,`END_LOCATION_ID`,`START_PICK_PUT_SIDE`,`START_Z`,`END_PICK_PUT_SIDE`,`END_Z`,`START_TIME`,`END_TIME`
		,`STATUS`,`TASK_DETAIL_TYPE`,`IS_TOWER_BUFFER`,`IS_STEPS_INSERTED`,`COUNT_OF_STEPS`,`COUNT_OF_STEPS_SENT` from `task_detail` where `BOT_ID` = botID and `STATUS` = 'PENDING' 
		ORDER BY `TASK_DETAIL_ID` DESC LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectNextStepWithCounter` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectNextStepWithCounter` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectNextStepWithCounter`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in curcounter int
    )
BEGIN
		SELECT PICK_PUT FROM steps WHERE COUNTER = (curcounter + 1) and BOT_ID = botID LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectPathInsertedOfTaskDetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectPathInsertedOfTaskDetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectPathInsertedOfTaskDetail`(
	in taskDetailID int
    )
BEGIN
		SELECT `IS_STEPS_INSERTED` FROM `task_detail` WHERE `TASK_DETAIL_ID` = taskDetailID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectPropertyInfoFromProperty` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectPropertyInfoFromProperty` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectPropertyInfoFromProperty`(
  IN `property` INT
)
BEGIN
  SELECT
    
    CASE 
      WHEN `FRONT_LIDAR`  = 1 THEN 1
      WHEN `REAR_LIDAR`   = 1 THEN 2
      WHEN `BOTTOM_LIDAR` = 1 THEN 3
      ELSE NULL
    END AS `LIDARNO`,
    
    
    CASE 
      WHEN `FRONT_LIDAR`  = 1 THEN `FRONT_LIDAR_ZONE`
      WHEN `REAR_LIDAR`   = 1 THEN `REAR_LIDAR_ZONE`
      WHEN `BOTTOM_LIDAR` = 1 THEN `BOTTOM_LIDAR_ZONE`
      ELSE NULL
    END AS `ZONENO`,
    
    `PROPERTY_TYPE` AS `TYPE`
  FROM
    `lidar_bifurcation_table`
  WHERE
    `PROPERTY_NUMBER` = property;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectPropertyOfHomes` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectPropertyOfHomes` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectPropertyOfHomes`(
    )
BEGIN
		SELECT `PROPERTY_DESCRIPTION` FROM location_master WHERE `TYPE` = 'HOME' ORDER BY `PROPERTY_DESCRIPTION` DESC;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectSendMaitenanceBitWithBot` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectSendMaitenanceBitWithBot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectSendMaitenanceBitWithBot`(in botID varchar(50))
BEGIN
		select `BOT_TO_MAINTENANCE_BIT` from `bot_master` where `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectStepIDWithLastWaypointCounter` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectStepIDWithLastWaypointCounter` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectStepIDWithLastWaypointCounter`(
	in _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in lastExecutedWaypointIndex int,
	IN _task_detail_id INT
    )
BEGIN
		SELECT ID FROM `steps` WHERE `TASK_DETAIL_ID` = _task_detail_id AND COUNTER = lastExecutedWaypointIndex  AND IS_COMPLETED = 0 AND `LAST_SENT_TIMESTAMP` IS NOT NULL and `BOT_ID`= _bot_id;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectStepsFromTaskDetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectStepsFromTaskDetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectStepsFromTaskDetail`(
	IN taskDetailID INT
    )
BEGIN
		SELECT `PROPERTY` FROM `steps` WHERE `TASK_DETAIL_ID` = taskDetailID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectTaskDetailsLessThanTaskDetailID` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectTaskDetailsLessThanTaskDetailID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectTaskDetailsLessThanTaskDetailID`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	IN taskDetailID INT
    )
BEGIN
		select `TASK_DETAIL_ID`,`END_LOCATION_ID`,`IS_STEPS_INSERTED`,`COUNT_OF_STEPS`,`COUNT_OF_STEPS_SENT` from `task_detail` where `BOT_ID` = botID and `TASK_DETAIL_ID` < taskDetailID and status = 'PROCESSING';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectTaskDetailWithStepsNotSent` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectTaskDetailWithStepsNotSent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectTaskDetailWithStepsNotSent`(
	in botID varchar(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		select `COUNT_OF_STEPS`,`COUNT_OF_STEPS_SENT`,`TASK_DETAIL_ID`  from `task_detail` WHERE `BOT_ID` = botID AND status <> "COMPLETED" and `IS_STEPS_INSERTED` = 1 AND `COUNT_OF_STEPS` > `COUNT_OF_STEPS_SENT` ORDER BY `TASK_DETAIL_ID` LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SelectZInMMWithZ` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SelectZInMMWithZ` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SelectZInMMWithZ`(
    IN p_z double
)
BEGIN
    SELECT `Z_ABSOLUTE_VALUE`
    FROM `location_master`
    WHERE `Z` = p_z
    LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SetAutoManualStatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SetAutoManualStatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SetAutoManualStatus`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci, in _status vARCHAR(50))
BEGIN
		update bot_master set `AUTO_MANUAL` = _status where BOT_ID = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SetRecoverybit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SetRecoverybit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SetRecoverybit`(
    IN botId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
update bot_master set RECOVERY_BIT=1 WHERE BOT_ID = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SetUpAuto` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SetUpAuto` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SetUpAuto`(IN AutoRecoveryAcknowledgement INT,IN EdgePresentOrNot INT, IN _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
               UPDATE `teleoperation_bool_data` SET `Auto Recovery Acknowledgement` = AutoRecoveryAcknowledgement,
                        `Auto Recovery End Edge` = EdgePresentOrNot WHERE `bot_id` = _bot_id;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SliderAutoRecoveryAcknowledgement` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SliderAutoRecoveryAcknowledgement` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SliderAutoRecoveryAcknowledgement`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		update`teleoperation_bool_data` SET `slider_recovery_acknowledge` = '1' where bot_id = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_sliderAutoRecoveryBitZero` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_sliderAutoRecoveryBitZero` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_sliderAutoRecoveryBitZero`(in botId varchar(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		update `teleoperation_bool_data` set `slider_recovery_acknowledge` = '0' , `slider_recovery_fail_acknowledge` = '0' where bot_id = botId; 
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_SliderAutoRecoveryfailAcknowledgement` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_SliderAutoRecoveryfailAcknowledgement` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_SliderAutoRecoveryfailAcknowledgement`(IN botId VARCHAR(50))
BEGIN
		UPDATE`teleoperation_bool_data` SET `slider_recovery_fail_acknowledge` = '1' WHERE bot_id = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_StepsCompletedWithDetailID` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_StepsCompletedWithDetailID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_StepsCompletedWithDetailID`(
	IN task_detail_id_ int
    )
BEGIN
		select count(ID) from steps where `TASK_DETAIL_ID` = task_detail_id_ and IS_COMPLETED = 0;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateBotMasterComms` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateBotMasterComms` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateBotMasterComms`(
	IN agentId VARCHAR(50),
	IN barcodeTagNumber INT,
	IN sliderPositionMM DOUBLE,
	IN lidarZoneNumber INT,
	IN xCoordinateAgent INT,
	IN yCoordinateAgent INT,
	IN zcoordinateAgentScaled DOUBLE, 
	IN activeAxis INT, 
	IN loadStatusBar VARCHAR(50),
	IN voltPercentageAGent INT,
	IN alarmCodeAgent INT, 
	IN alarmType VARCHAR(50),
	IN communicationCounter INT,
	IN ahRemainingPercentage INT,
	IN activityRequestBool INT,
	IN ahRemainingNormal INT
    )
BEGIN
	UPDATE bot_master 
	SET 
	    `GRIDX` = IF(`GRIDX` != xCoordinateAgent, xCoordinateAgent, `GRIDX`),
	    `GRIDY` = IF(`GRIDY` != yCoordinateAgent, yCoordinateAgent, `GRIDY`),
	    `GRIDZ` = IF(`GRIDZ` != zcoordinateAgentScaled, zcoordinateAgentScaled, `GRIDZ`),
	    `ACTIVE_AXIS` = IF(`ACTIVE_AXIS` != activeAxis, activeAxis, `ACTIVE_AXIS`),
	    `BARCODE_TAG_NUMBER` = barcodeTagNumber,
	    `SLIDER_POSITION` =sliderPositionMM ,
	    `LIDAR_ZONE_NUMBER` = lidarZoneNumber,
	    `LOAD_CONDITION` = IF(`LOAD_CONDITION` != loadStatusBar, loadStatusBar, `LOAD_CONDITION`),
	    `BATTERY` = IF(`BATTERY` != ahRemainingPercentage, ahRemainingPercentage, `BATTERY`),
	    `ALARM` = IF(`ALARM` != alarmCodeAgent, alarmCodeAgent, `ALARM`),
	    `ALARM_TYPE`= alarmType,
	    `COUNTER` = IF(`COUNTER` != communicationCounter, communicationCounter, `COUNTER`),
	    `AH_REMAINING_PERCENTAGE` = IF(`AH_REMAINING_PERCENTAGE` != ahRemainingPercentage, ahRemainingPercentage, `AH_REMAINING_PERCENTAGE`),
	    `BATTERY_VOLTS` = IF(`BATTERY_VOLTS` != voltPercentageAgent, voltPercentageAgent, `BATTERY_VOLTS`),
	    `ACTIVITY_REQUEST` = IF(`ACTIVITY_REQUEST` != activityRequestBool, activityRequestBool, `ACTIVITY_REQUEST`),
	    `AH_REMAINING_NORMAL` = IF(`AH_REMAINING_NORMAL` != ahRemainingNormal, ahRemainingNormal, `AH_REMAINING_NORMAL`),
	    `UPDATED_TIMESTAMP` = CURRENT_TIMESTAMP(3)
	WHERE 
	    `BOT_ID` = CONVERT(agentId USING latin1) COLLATE latin1_swedish_ci 
	  AND (
		`GRIDX` != xCoordinateAgent 
		OR `GRIDY` != yCoordinateAgent
		OR `GRIDZ` != zcoordinateAgentScaled
		OR `ACTIVE_AXIS` != activeAxis
		OR `BARCODE_TAG_NUMBER` != barcodeTagNumber
		OR `SLIDER_POSITION` != sliderPositionMM
		OR `LIDAR_ZONE_NUMBER` != lidarZoneNumber
		OR `LOAD_CONDITION` != loadStatusBar
		OR `BATTERY` != ahRemainingPercentage
		OR `ALARM` != alarmCodeAgent
		OR `ALARM_TYPE` != alarmType
		OR `COUNTER` != communicationCounter
		OR `AH_REMAINING_PERCENTAGE` != ahRemainingPercentage
		OR `BATTERY_VOLTS` != voltPercentageAgent
		OR `ACTIVITY_REQUEST` != activityRequestBool
		OR `AH_REMAINING_NORMAL` != ahRemainingNormal
	    )
	LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateBotMasterComms_backup` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateBotMasterComms_backup` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateBotMasterComms_backup`(
	in agentId VARCHAR(50),
	in xCoordinateAgent int,
	in yCoordinateAgent int,
	IN zcoordinateAgentScaled DOUBLE, 
	IN activeAxis INT, 
	IN loadStatusBar VARCHAR(50),
	IN voltPercentageAGent INT,
	IN alarmCodeAgent INT, 
	IN communicationCounter INT,
	IN ahRemainingPercentage INT,
	IN activityRequestBool INT,
	in ahRemainingNormal int
    )
BEGIN
		UPDATE bot_master 
		SET 
			`GRIDX` = xCoordinateAgent,`GRIDY`= yCoordinateAgent,`GRIDZ`= zcoordinateAgentScaled, 
	                `ACTIVE_AXIS`= activeAxis, 
	                `LOAD_CONDITION`= loadStatusBar,
                        `BATTERY`= ahRemainingPercentage,
                        `ALARM`= alarmCodeAgent,
                        `COUNTER`= communicationCounter,
                        `AH_REMAINING_PERCENTAGE` = ahRemainingPercentage,
                        `BATTERY_VOLTS` = voltPercentageAGent,
                        `ACTIVITY_REQUEST`  =  activityRequestBool,
                        `AH_REMAINING_NORMAL` = ahRemainingNormal,
                        `UPDATED_TIMESTAMP` = CURRENT_TIMESTAMP(3)
	         WHERE 
			BOT_ID = CONVERT(agentId USING latin1) COLLATE latin1_swedish_ci;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateCalibrationbit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateCalibrationbit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateCalibrationbit`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
                UPDATE teleoperation_bool_data SET `Auto Calibration Start` = '0' WHERE BOT_ID= bot_id_;
              UPDATE teleoperation_bool_data_feedback SET `Auto Calibration On` = '0',`Auto Calibration Done` = '0' WHERE BOT_ID= bot_id_;
              
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateCalibrationrecord` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateCalibrationrecord` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateCalibrationrecord`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
UPDATE dashboard_bot_master SET AUTO_CALIBRATION_DONE_TIMESTAMP = current_timestamp(3) where BOT_ID=bot_id_;
              INSERT INTO `auto_calibration_logs` (`BOT_ID`, `COMPLETED_TIMESTAMP`)
VALUES (bot_id_, NOW(3));
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateCalibrationtaskstatus` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateCalibrationtaskstatus` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateCalibrationtaskstatus`(IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
	      UPDATE `task_detail` SET STATUS='COMPLETED' WHERE BOT_ID= bot_id_ AND `TASK_MASTER_ID` IN (SELECT `TASK_ID` FROM `task_master` WHERE BOT_ID= bot_id_ AND `task_type` = 'BOT_AUTO_CALIBRATION');
               update `task_master` set STATUS='COMPLETED' WHERE BOT_ID= bot_id_ AND `task_type` = 'BOT_AUTO_CALIBRATION';   
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateCompleteStepsForTaskDetail` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateCompleteStepsForTaskDetail` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateCompleteStepsForTaskDetail`(
    in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN taskDetailID INT    
    )
BEGIN
		UPDATE `steps` SET `IS_COMPLETED` = 1, `IS_COMPLETED_TIMESTAMP` = NOW() WHERE `BOT_ID` = botID AND `TASK_DETAIL_ID` = taskDetailID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateCompleteStepsLessThanTaskDetailID` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateCompleteStepsLessThanTaskDetailID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateCompleteStepsLessThanTaskDetailID`(
    in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    in taskDetailID int
    )
BEGIN
	update `steps` set `IS_COMPLETED` = 1, `IS_COMPLETED_TIMESTAMP` = NOW() WHERE `TASK_DETAIL_ID` < taskDetailID and `BOT_ID` = botID;	
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateGearBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateGearBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `rm_UpdateGearBit`(IN botId VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
                UPDATE teleoperation_bool_data SET `Gearbox_Health_Check_Start` = '0' WHERE BOT_ID= botId;
              UPDATE teleoperation_bool_data_feedback SET `Gear Box Health Check Completed` = '0' WHERE BOT_ID= botId;
             
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateLastStepSendNull` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateLastStepSendNull` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateLastStepSendNull`(
	in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci
    )
BEGIN
		UPDATE `steps` SET `LAST_SEND_TIMESTAMP` = NULL WHERE `BOT_ID` = botID AND `IS_COMPLETED` = 0;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateLoadNonRecoveryBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateLoadNonRecoveryBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateLoadNonRecoveryBit`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		UPDATE bot_master SET LOAD_NON_RECOVERY_BIT = 0 WHERE bot_id = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateMaintenanceTaskMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateMaintenanceTaskMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateMaintenanceTaskMaster`(
    IN p_maintenanceId INT,    
    IN p_binId         VARCHAR(50),
    IN p_taskCreated   TINYINT(1)
)
BEGIN
    UPDATE `maintenance_task_master`
    SET         
        `BIN_BARCODE_SCANNED` = p_binId,        
        `TASK_DONE` = p_taskCreated
    WHERE 
        `MAINTENANCE_ID` = p_maintenanceId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateNonRecoveryBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateNonRecoveryBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateNonRecoveryBit`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		update bot_master set NON_RECOVERY_BIT = 0 WHERE bot_id = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_Updaterecoverybit` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_Updaterecoverybit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_Updaterecoverybit`(
    IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
update bot_master set RECOVERY_BIT=0 WHERE BOT_ID = CONVERT(bot_id_ USING latin1) COLLATE latin1_swedish_ci;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_updateRecoveryTimestampOnError` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_updateRecoveryTimestampOnError` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_updateRecoveryTimestampOnError`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		update bot_alarm_log set RECOVERY_TIMESTAMP = now() where BOT_ID = botId and RECOVERY_TIMESTAMP IS null;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateSendMaitenanceBitWithBot` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateSendMaitenanceBitWithBot` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateSendMaitenanceBitWithBot`(in botID varchar(50))
BEGIN
		update `bot_master` set `BOT_TO_MAINTENANCE_BIT` = 0 where `BOT_ID` = botID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateStepsCompletedWithID` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateStepsCompletedWithID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateStepsCompletedWithID`(
	in _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in completedStepId int,
	IN _task_detail_id INT
    )
BEGIN
		UPDATE `steps` SET `IS_COMPLETED`=1, `IS_COMPLETED_TIMESTAMP` = NOW() WHERE  `TASK_DETAIL_ID` = _task_detail_id AND ID <= completedStepId AND `LAST_SENT_TIMESTAMP` IS NOT NULL AND `IS_COMPLETED`=0 and `BOT_ID`= _bot_id;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateStepsLastSend` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateStepsLastSend` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateStepsLastSend`(
	in _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
	in _task_detail int,
	in _counter int,
	in _x int,
	in _y int,
	IN _z double
    )
BEGIN
		UPDATE steps SET LAST_SENT_TIMESTAMP = NOW()
		WHERE `TASK_DETAIL_ID` = _task_detail AND X = _x AND Y = _y AND Z = _z 
		AND BOT_ID= _bot_id ;
		
		update `task_detail` set `COUNT_OF_STEPS_SENT` = _counter 
		where `TASK_DETAIL_ID` = _task_detail;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateTaskDetailCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateTaskDetailCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateTaskDetailCompleted`(
	IN task_detail_id_ int
    )
BEGIN
		UPDATE `task_detail` SET `STATUS` = 'COMPLETED' WHERE `TASK_DETAIL_ID` = task_detail_id_;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateTaskdetailsforfuturesteps` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateTaskdetailsforfuturesteps` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateTaskdetailsforfuturesteps`(
    IN bot_id_ VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN taskDetailID INT
    )
BEGIN
     
    UPDATE steps
    SET 
        LAST_SENT_TIMESTAMP = NULL,
        IS_COMPLETED_TIMESTAMP = NULL,
        INSERT_TIME = NULL
    WHERE 
        TASK_DETAIL_ID > taskDetailID 
        AND BOT_ID = CONVERT(bot_id_ USING latin1) COLLATE latin1_swedish_ci ;
    
    UPDATE task_detail
    SET 
        
        COUNT_OF_STEPS_SENT = 0
    WHERE 
        TASK_DETAIL_ID > taskDetailID 
        AND BOT_ID = CONVERT(bot_id_ USING latin1) COLLATE latin1_swedish_ci and COUNT_OF_STEPS_SENT!=0;
         
     update bot_master set RECOVERY_BIT=0 WHERE BOT_ID = CONVERT(bot_id_ USING latin1) COLLATE latin1_swedish_ci and RECOVERY_BIT!=0;
     UPDATE `teleoperation_bool_data` SET `Auto Start Bit` = 1       
     WHERE BOT_ID = CONVERT(bot_id_ USING latin1) COLLATE latin1_swedish_ci 
     AND `Auto Start Bit`=0;
     
     UPDATE bot_master SET AUTO_MANUAL='auto' WHERE BOT_ID = bot_id_ AND  AUTO_MANUAL!='auto';
END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateTaskDetailStepsInserted` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateTaskDetailStepsInserted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateTaskDetailStepsInserted`(
	in taskDetailID int
    )
BEGIN
		UPDATE `task_detail` SET `IS_STEPS_INSERTED` = '1', `COUNT_OF_STEPS` = (SELECT COUNT(`ID`) from `steps` where `TASK_DETAIL_ID` = taskDetailID) WHERE `TASK_DETAIL_ID` = taskDetailID;
				 
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateTaskDetailStepsOnActivityRequest` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateTaskDetailStepsOnActivityRequest` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateTaskDetailStepsOnActivityRequest`(in botID varchar(10)  CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		declare taskId int;
		
	    
	    select TASK_DETAIL_ID into taskId from steps where BOT_ID = botId and IS_COMPLETED = 0 and LAST_SENT_TIMESTAMP is not null order by TASK_DETAIL_ID limit 1;
	    
	    UPDATE steps
	    SET 
		LAST_SENT_TIMESTAMP = NULL,
		IS_COMPLETED_TIMESTAMP = NULL,
		INSERT_TIME = NULL
	    WHERE 
		TASK_DETAIL_ID >= taskId 
	    AND BOT_ID = botId;
	    
	    UPDATE task_detail
	    SET 
		
		COUNT_OF_STEPS_SENT = 0
	    WHERE 
		TASK_DETAIL_ID >= taskId 
		AND BOT_ID = botId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateTaskDetailToProcessing` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateTaskDetailToProcessing` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateTaskDetailToProcessing`(
	IN task_detail_id_ int
    )
BEGIN
		UPDATE `task_detail` SET `STATUS` = 'PROCESSING' WHERE `TASK_DETAIL_ID` = task_detail_id_;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateTaskMasterCompleted` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateTaskMasterCompleted` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateTaskMasterCompleted`(
	IN task_id_ int
    )
BEGIN
		UPDATE `task_master` SET `STATUS` = 'COMPLETED' WHERE `TASK_ID` = task_id_;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateTeleOperationDataFeedbackAutoMode` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateTeleOperationDataFeedbackAutoMode` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateTeleOperationDataFeedbackAutoMode`(IN _dataConvertedToBool VARCHAR(255), in _bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		DECLARE no_alarm_feedback CHAR(1);
		DECLARE auto_manual_status VARCHAR(10);
		SET no_alarm_feedback = SUBSTRING(_dataConvertedToBool, 3, 1); 
		    
		    UPDATE `teleoperation_bool_data_feedback`
		    SET 
			`Home OK Feedback` = SUBSTRING(_dataConvertedToBool, 8, 1),
			`Auto Home Being Feedback` = SUBSTRING(_dataConvertedToBool, 7, 1),
			`Auto Start Feedback` = SUBSTRING(_dataConvertedToBool, 6, 1),
			`Global Pause Feedback` = SUBSTRING(_dataConvertedToBool, 5, 1),
			`Emergency Stop Feedback` = SUBSTRING(_dataConvertedToBool, 4, 1),
			`No Alarm Feedback` = no_alarm_feedback,
			`Auto Recovery Request Bit` = SUBSTRING(_dataConvertedToBool, 1, 1),
			`Auto Recovery Done Bit` = SUBSTRING(_dataConvertedToBool, 16, 1),
			`Wheel Diff Auto Correct` = SUBSTRING(_dataConvertedToBool, 15, 1),
			`Auto Calibration On` = SUBSTRING(_dataConvertedToBool, 14, 1),
			`Auto Calibration Done` = SUBSTRING(_dataConvertedToBool, 13, 1),
			`cur_step_completed` = SUBSTRING(_dataConvertedToBool, 12, 1)
		    WHERE bot_id = _bot_id;
		    
		    SELECT auto_manual 
		    INTO auto_manual_status 
		    FROM bot_master 
		    WHERE bot_id = _bot_id;
		    
		    IF auto_manual_status = 'auto' AND no_alarm_feedback = '1' THEN
		    BEGIN 
			UPDATE `teleoperation_bool_data` SET `Auto Home Call Bit` = '0' WHERE bot_id = _bot_id;
			UPDATE `teleoperation_bool_data` SET `Auto Start Bit` = '0' WHERE bot_id = _bot_id;
		    END;
		    END IF;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateTeleportationDataFeedbackAutoMode` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateTeleportationDataFeedbackAutoMode` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateTeleportationDataFeedbackAutoMode`(IN _dataConvertedToBool VARCHAR(255), IN _bot_id VARCHAR(50))
BEGIN
		DECLARE no_alarm_feedback CHAR(1);
		DECLARE auto_manual_status VARCHAR(10);
		SET no_alarm_feedback = SUBSTRING(_dataConvertedToBool, 3, 1); 
		    
		    UPDATE `teleoperation_bool_data_feedback`
		    SET 
			`Home OK Feedback` = SUBSTRING(_dataConvertedToBool, 8, 1),
			`Auto Home Being Feedback` = SUBSTRING(_dataConvertedToBool, 7, 1),
			`Auto Start Feedback` = SUBSTRING(_dataConvertedToBool, 6, 1),
			`Global Pause Feedback` = SUBSTRING(_dataConvertedToBool, 5, 1),
			`Emergency Stop Feedback` = SUBSTRING(_dataConvertedToBool, 4, 1),
			`No Alarm Feedback` = no_alarm_feedback,
			`Auto Recovery Request Bit` = SUBSTRING(_dataConvertedToBool, 1, 1),
			`Auto Recovery Done Bit` = SUBSTRING(_dataConvertedToBool, 16, 1),
			`Wheel Diff Auto Correct` = SUBSTRING(_dataConvertedToBool, 15, 1),
			`Auto Calibration On` = SUBSTRING(_dataConvertedToBool, 14, 1),
			`Auto Calibration Done` = SUBSTRING(_dataConvertedToBool, 13, 1),
			`Gear Box Health Check Completed` = SUBSTRING(_dataConvertedToBool, 12, 1),
			`Slider recovery` = SUBSTRING(_dataConvertedToBool, 11, 1),
			`Slider Recovery Fail` = SUBSTRING(_dataConvertedToBool, 10, 1),
			`Bot Stop Due To Lidar Obstacle` = SUBSTRING(_dataConvertedToBool, 9, 1),
			`Front Right Finger Actuator Open` = SUBSTRING(_dataConvertedToBool, 24, 1),
			`Front Left Finger Actuator Open` = SUBSTRING(_dataConvertedToBool, 23, 1),
			`Rear Right Finger Actuator Open` = SUBSTRING(_dataConvertedToBool, 22, 1),
			`Rear Left Finger Actuator Open` = SUBSTRING(_dataConvertedToBool, 21, 1),
			`Front Right Finger Actuator Close` = SUBSTRING(_dataConvertedToBool, 20, 1),
			`Front Left Finger Actuator Close` = SUBSTRING(_dataConvertedToBool, 19, 1),
			`Rear Right Finger Actuator Close` = SUBSTRING(_dataConvertedToBool, 18, 1),
			`Rear Left Finger Actuator Close` = SUBSTRING(_dataConvertedToBool, 17, 1)
		    WHERE bot_id = _bot_id;
		    
		    SELECT auto_manual 
		    INTO auto_manual_status 
		    FROM bot_master 
		    WHERE bot_id = _bot_id;
		    
		    IF auto_manual_status = 'auto' AND no_alarm_feedback = '1' THEN
		    BEGIN 
			UPDATE `teleoperation_bool_data` SET `Auto Home Call Bit` = '0' WHERE bot_id = _bot_id;
			UPDATE `teleoperation_bool_data` SET `Auto Start Bit` = '0' WHERE bot_id = _bot_id;
		    END;
		    END IF;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `rm_UpdateTeleportationDataFeedbackManualMode` */

/*!50003 DROP PROCEDURE IF EXISTS  `rm_UpdateTeleportationDataFeedbackManualMode` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `rm_UpdateTeleportationDataFeedbackManualMode`( dataConvertedTobool VARCHAR(255), _bot_id VARCHAR(50), data_from_plc_numeric TEXT)
BEGIN
		UPDATE`teleoperation_bool_data_feedback`
SET
  
 `spare1` = SUBSTRING(dataConvertedToBool, 8, 1),        
 `Emergency Stop Feedback` = SUBSTRING(dataConvertedToBool, 7, 1),  
 `Alarm On Feedback` = SUBSTRING(dataConvertedToBool, 6, 1),        
 `Z-Jog Operation Limits Overwrite Confirm` = SUBSTRING(dataConvertedToBool, 5, 1),  
 `Home OK` = SUBSTRING(dataConvertedToBool, 4, 1),                     
 `Camera Contorl Code Present Feedback` = SUBSTRING(dataConvertedToBool, 3, 1), 
 `Global Pause Feedback` = SUBSTRING(dataConvertedToBool, 2, 1),       
 `Front Right Finger Actuator Open` = SUBSTRING(dataConvertedToBool, 1, 1),      
  
 `Front Left Finger Actuator Open` = SUBSTRING(dataConvertedToBool, 16, 1),  
 `Rear Right Finger Actuator Open` = SUBSTRING(dataConvertedToBool, 15, 1), 
 `Rear Left Finger Actuator Open` = SUBSTRING(dataConvertedToBool, 14, 1),  
 `Front Right Wheel Servo Healthy Status` = SUBSTRING(dataConvertedToBool, 13, 1), 
 `Front Left Wheel Servo Healthy Status` = SUBSTRING(dataConvertedToBool, 12, 1),  
 `Rear Right Wheel Servo Healthy Status` = SUBSTRING(dataConvertedToBool, 11, 1),  
 `Rear Left Wheel Servo Healthy Status` = SUBSTRING(dataConvertedToBool, 10, 1),   
 `Y-Axis Servo Healthy Status` = SUBSTRING(dataConvertedToBool, 9, 1),            
  
 `Lift-Axis Servo Healthy Status` = SUBSTRING(dataConvertedToBool, 24, 1),   
 `Slider-Axis Servo Healthy Status` = SUBSTRING(dataConvertedToBool, 23, 1), 
 `spare2` = SUBSTRING(dataConvertedToBool, 22, 1),   
 `spare3` = SUBSTRING(dataConvertedToBool, 21, 1),   
 `spare4` = SUBSTRING(dataConvertedToBool, 20, 1),   
 `spare5` = SUBSTRING(dataConvertedToBool, 19, 1),   
 `spare6` = SUBSTRING(dataConvertedToBool, 18, 1),   
 `spare7` = SUBSTRING(dataConvertedToBool, 17, 1),   
  
 `Front Lidar Healthy` = SUBSTRING(dataConvertedToBool, 32, 1),     
 `Front Lidar Alert` = SUBSTRING(dataConvertedToBool, 31, 1),       
 `Emergency Stop AT BOT` = SUBSTRING(dataConvertedToBool, 30, 1),   
 `Axis Change Home Sensor` = SUBSTRING(dataConvertedToBool, 29, 1), 
 `Bin Presence Sensor` = SUBSTRING(dataConvertedToBool, 28, 1),     
 `spare8` = SUBSTRING(dataConvertedToBool, 27, 1),   
 `spare9` = SUBSTRING(dataConvertedToBool, 26, 1),   
 `Front Lidar Danger` = SUBSTRING(dataConvertedToBool, 25, 1),      
  
 `Slide Right Zero Position Sensor` = SUBSTRING(dataConvertedToBool, 40, 1),   
 `Front Lidar Warning` = SUBSTRING(dataConvertedToBool, 39, 1),                
 `Top Sensor Alert` = SUBSTRING(dataConvertedToBool, 38, 1),                   
 `Top Sensor Danger` = SUBSTRING(dataConvertedToBool, 37, 1),                  
 `Slide Left Zero Position Sensor` = SUBSTRING(dataConvertedToBool, 36, 1),    
 `spare10` = SUBSTRING(dataConvertedToBool, 35, 1),   
 `spare11` = SUBSTRING(dataConvertedToBool, 34, 1),   
 `Rear Lidar Healthy` = SUBSTRING(dataConvertedToBool, 33, 1),                 
  
 `Rear Lidar Danger` = SUBSTRING(dataConvertedToBool, 48, 1),  
 `Rear Lidar Alert` = SUBSTRING(dataConvertedToBool, 47, 1),   
 `Rear Lidar Warning` = SUBSTRING(dataConvertedToBool, 46, 1), 
 `Bottom Lidar Healthy` = SUBSTRING(dataConvertedToBool, 45, 1),
 `Bottom Lidar Danger` = SUBSTRING(dataConvertedToBool, 44, 1), 
 `Bottom Lidar Alert` = SUBSTRING(dataConvertedToBool, 43, 1),  
 `Bottom Lidar Warning` = SUBSTRING(dataConvertedToBool, 42, 1),
 `spare12` = SUBSTRING(dataConvertedToBool, 41, 1),   
  
 `Battery remaining SOC (% goes below 20)` = SUBSTRING(dataConvertedToBool, 56, 1),  
 `Bot gets bin pick task from server and it has already loaded` = SUBSTRING(dataConvertedToBool, 55, 1),  
 `PLC hardware failure` = SUBSTRING(dataConvertedToBool, 54, 1),  
 `EtherCat hardware/connection failure` = SUBSTRING(dataConvertedToBool, 53, 1),  
 `Front wheel right servo is in error` = SUBSTRING(dataConvertedToBool, 52, 1),  
 `Front wheel left servo is in error` = SUBSTRING(dataConvertedToBool, 51, 1),  
 `Rear wheel right servo is in error` = SUBSTRING(dataConvertedToBool, 50, 1),  
 `Rear wheel left servo is in error` = SUBSTRING(dataConvertedToBool, 49, 1),  
  
 `Y-axis servo is in error` = SUBSTRING(dataConvertedToBool, 64, 1),  
 `Lift-axis servo is in error` = SUBSTRING(dataConvertedToBool, 63, 1),  
 `Slider-axis servo is in error` = SUBSTRING(dataConvertedToBool, 62, 1),  
 `Soft Emergency stop by Server` = SUBSTRING(dataConvertedToBool, 61, 1),  
 `Y-axis servo does not move after getting move command` = SUBSTRING(dataConvertedToBool, 60, 1),  
 `X-axis servo does not move after getting move command` = SUBSTRING(dataConvertedToBool, 59, 1),  
 `Z-axis servo does not move after getting move command` = SUBSTRING(dataConvertedToBool, 58, 1),  
 `Lift-axis servo does not move after getting move command` = SUBSTRING(dataConvertedToBool, 57, 1),  
  
 `Slider-axis servo does not move after getting move command` = SUBSTRING(dataConvertedToBool, 72, 1),  
 `Liftaxis does not achieve middle position during XZ axis change` = SUBSTRING(dataConvertedToBool, 71, 1),  
 `Liftaxis does not achieve Y-position during XY axis change` = SUBSTRING(dataConvertedToBool, 70, 1),  
 `Liftaxis does not achieve X-position during XY/XZ axis change` = SUBSTRING(dataConvertedToBool, 69, 1),  
 `Liftaxis does not achieve Z-position during XZ axis change` = SUBSTRING(dataConvertedToBool, 68, 1), 
 `Battery voltage goes below 45V`                                 = SUBSTRING(dataConvertedToBool, 67, 1),  
 `spare14`                                                        = SUBSTRING(dataConvertedToBool, 66, 1),  
 `Scanner is not responsing to PLC (wiring/hardware)`           = SUBSTRING(dataConvertedToBool, 65, 1),  
  
 `Server is not responsing to PLC (Wi-Fi/wiring/hardware)`      = SUBSTRING(dataConvertedToBool, 80, 1),  
 `BMS is not responsing to PLC (wiring/hardware)`               = SUBSTRING(dataConvertedToBool, 79, 1),  
 `EtherCat Node-1 hardware/connection failure`                   = SUBSTRING(dataConvertedToBool, 78, 1),  
 `EtherCat Node-2 hardware/connection failure`                   = SUBSTRING(dataConvertedToBool, 77, 1),  
 `EtherCat Node-3 hardware/connection failure`                   = SUBSTRING(dataConvertedToBool, 76, 1),  
 `EtherCat Node-4 hardware/connection failure`                   = SUBSTRING(dataConvertedToBool, 75, 1),  
 `EtherCat Node-5 hardware/connection failure`                   = SUBSTRING(dataConvertedToBool, 74, 1),  
 `EtherCat Node-6 hardware/connection failure`                   = SUBSTRING(dataConvertedToBool, 73, 1),  
  
 `EtherCat Node-7 hardware/connection failure`                   = SUBSTRING(dataConvertedToBool, 88, 1),  
 `Difference of all 4 wheel >12mm during Z-axis Move` = SUBSTRING(dataConvertedToBool, 87, 1),  
 `Bottom lidar hardware/connection failure`                      = SUBSTRING(dataConvertedToBool, 86, 1),  
 `Bot has achieved near 0 position window during Y-movement`  = SUBSTRING(dataConvertedToBool, 85, 1),  
 `Bot has not achieved near 0 position window during X-movement` = SUBSTRING(dataConvertedToBool, 84, 1),  
 `Bot has not achieved near 0 position window during axis change` = SUBSTRING(dataConvertedToBool, 83, 1),  
 `Immediate stop not confirmed during Y axis movement` = SUBSTRING(dataConvertedToBool, 82, 1),  
 `Immediate stop not confirmed during X axis movement`= SUBSTRING(dataConvertedToBool, 81, 1),  
  
 `Gearout not confirmed on gearout command`                      = SUBSTRING(dataConvertedToBool, 96, 1),  
 `Position overwrite not confirmed on overwrite command`         = SUBSTRING(dataConvertedToBool, 95, 1),  
 `Z position >2mm detected on X/Y move`                        = SUBSTRING(dataConvertedToBool, 94, 1),  
 `>1 step gets with highway property from server`              = SUBSTRING(dataConvertedToBool, 93, 1),  
 `Break release not confirmed engage/disengage on XZ axis change` = SUBSTRING(dataConvertedToBool, 92, 1),  
 `Break enable not confirmed engage/disengage on XZ axis change`  = SUBSTRING(dataConvertedToBool, 91, 1),  
 `Front lidar hardware/connection failure`                       = SUBSTRING(dataConvertedToBool, 90, 1),  
 `Rear lidar hardware/connection failure`                        = SUBSTRING(dataConvertedToBool, 89, 1),  
  
 `Track limit overshoot`                                         = SUBSTRING(dataConvertedToBool, 104, 1),  
 `Scanner detects different code than actual`                    = SUBSTRING(dataConvertedToBool, 103, 1),  
 `Bot gets bin put task from server and there is no bin over Bot` = SUBSTRING(dataConvertedToBool, 102, 1), 
 `Bin presence sensor not detected after BOT loaded`             = SUBSTRING(dataConvertedToBool, 101, 1), 
 `Bin presence sensor detected after BOT unloaded`               = SUBSTRING(dataConvertedToBool, 100, 1), 
 `Rear Right Actuator position does not achieve its target`      = SUBSTRING(dataConvertedToBool, 99, 1), 
 `Rear Left Actuator position does not achieve its target`       = SUBSTRING(dataConvertedToBool, 98, 1), 
 `Front Right Actuator position does not achieve its target`     = SUBSTRING(dataConvertedToBool, 97, 1), 
  
 `Front Left Actuator position does not achieve its target`      = SUBSTRING(dataConvertedToBool, 112, 1), 
 `Slider has not achieved its Rear position`                     = SUBSTRING(dataConvertedToBool, 111, 1), 
 `Slider has not achieved its Front position`                    = SUBSTRING(dataConvertedToBool, 110, 1), 
 `Slider has not achieved its Zero position`                     = SUBSTRING(dataConvertedToBool, 109, 1), 
 `Slider has not achieved its Target position`                   = SUBSTRING(dataConvertedToBool, 108, 1), 
 `Lift axis has not achieved its Target position`                = SUBSTRING(dataConvertedToBool, 107, 1), 
 `Z-axis position is wrong for slider operation`                 = SUBSTRING(dataConvertedToBool, 106, 1), 
 `Lidar has not detected bin at rack during pick operation`      = SUBSTRING(dataConvertedToBool, 105, 1), 
  
 `Lidar detects bin at rack during put operation`                = SUBSTRING(dataConvertedToBool, 120, 1), 
 `Bot has not detected barcode during Y-axis`                    = SUBSTRING(dataConvertedToBool, 119, 1), 
 `Bot has not detected barcode during X-axis`                    = SUBSTRING(dataConvertedToBool, 118, 1), 
 `Bot has not achieved Y=0 position at junction`               = SUBSTRING(dataConvertedToBool, 117, 1), 
 `Bot has not achieved X=0 position at junction`               = SUBSTRING(dataConvertedToBool, 116, 1), 
 `Barcode Scanner has Error or Warning`                          = SUBSTRING(dataConvertedToBool, 115, 1), 
 `spare15`                                                        = SUBSTRING(dataConvertedToBool, 114, 1), 
 `>1 coordinates difference detected from server`               = SUBSTRING(dataConvertedToBool, 113, 1), 
  
 `Gearin is not achieved for X movement`                        = SUBSTRING(dataConvertedToBool, 128, 1), 
 `Gearin/Group enable has not been done for Z movement`         = SUBSTRING(dataConvertedToBool, 127, 1), 
 `spare16`                                                        = SUBSTRING(dataConvertedToBool, 126, 1), 
 `spare17`                                                        = SUBSTRING(dataConvertedToBool, 125, 1), 
 `Finger Servo torque overwrite/feedback error`                = SUBSTRING(dataConvertedToBool, 124, 1), 
 `Right side slider not reached zero position`                   = SUBSTRING(dataConvertedToBool, 123, 1), 
 `Left side slider not reached zero position`                    = SUBSTRING(dataConvertedToBool, 122, 1), 
 `spare18`                                                        = SUBSTRING(dataConvertedToBool, 121, 1), 
  
 `spare19` = SUBSTRING(dataConvertedToBool, 136, 1),  
 `spare20` = SUBSTRING(dataConvertedToBool, 135, 1),  
 `spare21` = SUBSTRING(dataConvertedToBool, 134, 1),  
 `spare22` = SUBSTRING(dataConvertedToBool, 133, 1),  
 `spare23` = SUBSTRING(dataConvertedToBool, 132, 1),  
 `spare24` = SUBSTRING(dataConvertedToBool, 131, 1),  
 `spare25` = SUBSTRING(dataConvertedToBool, 130, 1),  
 `spare26` = SUBSTRING(dataConvertedToBool, 129, 1),  
  
 `spare27` = SUBSTRING(dataConvertedToBool, 144, 1),  
 `spare28` = SUBSTRING(dataConvertedToBool, 143, 1),  
 `spare29` = SUBSTRING(dataConvertedToBool, 142, 1),  
 `spare30` = SUBSTRING(dataConvertedToBool, 141, 1),  
 `spare31` = SUBSTRING(dataConvertedToBool, 140, 1),  
 `spare32` = SUBSTRING(dataConvertedToBool, 139, 1),  
 `spare33` = SUBSTRING(dataConvertedToBool, 138, 1),  
 `spare34` = SUBSTRING(dataConvertedToBool, 137, 1)   
WHERE`bot_id` = _bot_id;
		
		UPDATE`teleoperation_numeric_data_feedback`
SET
   `Control Code No of Camera` = SUBSTRING(data_from_plc_numeric, 1, 8),
   `X-Axis Co-ordinate of Control Code` = SUBSTRING(data_from_plc_numeric, 9, 8),
   `Y-Axis Co-ordinate of Control Code` = SUBSTRING(data_from_plc_numeric, 17, 8),
   `Z-Axis Co-ordinate of Control Code` = SUBSTRING(data_from_plc_numeric, 25, 8),
   `Y-Axis Actual Velocity` = SUBSTRING(data_from_plc_numeric, 33, 8),
   `X-Axis Actual Velocity` = SUBSTRING(data_from_plc_numeric, 41, 8),
   `Lift-Axis Actual Velocity` = SUBSTRING(data_from_plc_numeric, 49, 8),
   `Slider-Axis Actual Velocity` = SUBSTRING(data_from_plc_numeric, 57, 8),
   `Y-Axis Actual Position` = SUBSTRING(data_from_plc_numeric, 65, 8),
   `X-Axis Actual Position` = SUBSTRING(data_from_plc_numeric, 73, 8),
   `Z-Axis Actual Position` = SUBSTRING(data_from_plc_numeric, 81, 8),
   `Lift-Axis Actual Position` = SUBSTRING(data_from_plc_numeric, 89, 8),
   `Slider-Axis Actual Position` = SUBSTRING(data_from_plc_numeric, 97, 8),
   `Front Right Wheel Servo Current` = SUBSTRING(data_from_plc_numeric, 105, 8),
   `Front Left Wheel Servo Current` = SUBSTRING(data_from_plc_numeric, 113, 8),
   `Rear Right Wheel Servo Current` = SUBSTRING(data_from_plc_numeric, 121, 8),
   `Rear Left Wheel Servo Current` = SUBSTRING(data_from_plc_numeric, 129, 8),
   `Y-Axis Servo Current` = SUBSTRING(data_from_plc_numeric, 137, 8),
   `Lift-Axis Servo Current` = SUBSTRING(data_from_plc_numeric, 145, 8),
   `Slider-Axis Servo Current` = SUBSTRING(data_from_plc_numeric, 153, 8),
   `Y-Axis Servo Accumulation Position` = SUBSTRING(data_from_plc_numeric, 161, 8),
   `X-Axis Servo Accumulation Position` = SUBSTRING(data_from_plc_numeric, 169, 8),
   `Z-Axis Servo Accumulation Position` = SUBSTRING(data_from_plc_numeric, 177, 8),
   `Z-Axis Halt Time` = SUBSTRING(data_from_plc_numeric, 185, 8),
   `X-Axis Position of Control Code` = SUBSTRING(data_from_plc_numeric, 193, 8),
   `Y-Axis Position of Control Code` = SUBSTRING(data_from_plc_numeric, 201, 8),
   `Angle of Control Code` = SUBSTRING(data_from_plc_numeric, 209, 8),
   `Battery Voltage` = SUBSTRING(data_from_plc_numeric, 217, 8),
   `Battery Remaining AH` = SUBSTRING(data_from_plc_numeric, 225, 8),
   `FWR Servo Error Code` = SUBSTRING(data_from_plc_numeric, 233, 8),
   `FWL Servo Error Code` = SUBSTRING(data_from_plc_numeric, 241, 8),
   `RWR Servo Error Code` = SUBSTRING(data_from_plc_numeric, 249, 8),
   `RWL Servo Error Code` = SUBSTRING(data_from_plc_numeric, 257, 8),
   `Y-Axis Servo Error Code` = SUBSTRING(data_from_plc_numeric, 265, 8),
   `Axis Change Servo Error Code` = SUBSTRING(data_from_plc_numeric, 273, 8),
   `Slider Servo Error Code` = SUBSTRING(data_from_plc_numeric, 281, 8),
   `Front Wheel Right Servo Max Current` = SUBSTRING(data_from_plc_numeric, 289, 8),
   `Front Wheel Left Servo Max Current` = SUBSTRING(data_from_plc_numeric, 297, 8),
   `Rear Wheel Right Servo Max Current` = SUBSTRING(data_from_plc_numeric, 305, 8),
   `Rear Wheel Left Servo Max Current` = SUBSTRING(data_from_plc_numeric, 313, 8),
   `Y-Axis Servo Max Current` = SUBSTRING(data_from_plc_numeric, 321, 8),
   `Axis Change Servo Max Current` = SUBSTRING(data_from_plc_numeric, 329, 8),
   `Slider Servo Max Current` = SUBSTRING(data_from_plc_numeric, 337, 8),
   `Max Wheel Difference` = SUBSTRING(data_from_plc_numeric, 345, 8),
   `Wheel Difference At Error` = SUBSTRING(data_from_plc_numeric, 353, 8)
		    WHERE`bot_id` = _bot_id;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `RunInLoop` */

/*!50003 DROP PROCEDURE IF EXISTS  `RunInLoop` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `RunInLoop`(IN p_waveId VARCHAR(200), IN p_timer INT)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE current_wave_status VARCHAR(50);
    
    UPDATE `stock_audit_wave_order_master`
    SET `UPDATED_SKU_ID` = `SKU_ID`,
        `UPDATED_BATCH_ID` = `BATCH_ID`,
        `UPDATED_QUANTITY` = `EXPECTED_QUANTITY`  
    WHERE `WAVE_ID` = p_waveId;
    UPDATE `hw_station_master`
    SET `WAVE_STATUS` = 'WAVE_LIVE'
    WHERE `WAVE_ID` = p_waveId;
    
    WHILE NOT done DO
        
        SELECT IFNULL((
    SELECT IFNULL(`WAVE_STATUS`, 'NO_WAVE') 
    FROM `hw_station_master`
    WHERE `WAVE_ID` = p_waveId
    LIMIT 1
), 'NO_WAVE') INTO current_wave_status;
        
        IF current_wave_status <> 'WAVE_LIVE' THEN
            SET done = TRUE;
        ELSE
            
            UPDATE `stock_audit_wave_order_master`
            SET `STATUS` = 'AUDIT_COMPLETED'
            WHERE `STATUS` = 'AUDIT_STARTED'
              AND `WAVE_ID` = p_waveId;
            
            DO SLEEP(p_timer);
        END IF;
    END WHILE;
END */$$
DELIMITER ;

/* Procedure structure for procedure `SelectAllBinInfoMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `SelectAllBinInfoMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `SelectAllBinInfoMaster`()
BEGIN
		SELECT * FROM `bin_info_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `SelectAllChargingStationMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `SelectAllChargingStationMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `SelectAllChargingStationMaster`()
BEGIN
		SELECT * FROM `hw_charging_station_master` ;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `SelectAllStationHomeMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `SelectAllStationHomeMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `SelectAllStationHomeMaster`(
    )
BEGIN
		select * from `station_home_master` ORDER BY station_id ASC, id DESC;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `SelectAllStationMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `SelectAllStationMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `SelectAllStationMaster`()
BEGIN
		select * from `hw_station_master`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `SelectArticleInBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `SelectArticleInBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `SelectArticleInBin`(
	in BIN_ID INT
    )
BEGIN
		SELECT * FROM `live_inventory_master` where `BIN_ID` = BIN_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `SelectAssignedStations` */

/*!50003 DROP PROCEDURE IF EXISTS  `SelectAssignedStations` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `SelectAssignedStations`(
	in WAVE_ID VARCHAR(200)
    )
BEGIN
		SELECT `STATION_ID` FROM `hw_station_master` WHERE `WAVE_ID` = WAVE_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `SelectScannerFromParent` */

/*!50003 DROP PROCEDURE IF EXISTS  `SelectScannerFromParent` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `SelectScannerFromParent`(
	in PARENT_ID VARCHAR(200)
    )
BEGIN
		SELECT * FROM `hw_scanner_master` where `PARENT_ID` = PARENT_ID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `SelectStationSelectionWithWaveID` */

/*!50003 DROP PROCEDURE IF EXISTS  `SelectStationSelectionWithWaveID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `SelectStationSelectionWithWaveID`(
	in WAVE_ID VARCHAR(200)
    )
BEGIN
		SELECT `STATUS` FROM `wave_master` WHERE `WAVE_ID` = WAVE_ID AND `STATUS`='STATION_SELECTION';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_ChargingBitStatesOrderedByLocationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_ChargingBitStatesOrderedByLocationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_ChargingBitStatesOrderedByLocationId`()
BEGIN
    SELECT SLIDING_DOOR_1_OPEN
    FROM hw_charging_station_master
    ORDER BY LOCATION_ID DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_ConveyorGetLastMessage` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_ConveyorGetLastMessage` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_ConveyorGetLastMessage`(
	IN p_conveyorID INT
    )
BEGIN
		SELECT `LAST_MSG_SENT` FROM `hw_conveyor_master` 
		WHERE `CONVEYOR_ID` = p_conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_ConveyorGetOnStationBin` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_ConveyorGetOnStationBin` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_ConveyorGetOnStationBin`(
	IN p_conveyorID INT
    )
BEGIN
		SELECT COALESCE(`BIN_ON_STATION`,0) FROM `hw_conveyor_master` 
		WHERE `CONVEYOR_ID` = p_conveyorID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetAllConveyorLastMsg` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetAllConveyorLastMsg` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetAllConveyorLastMsg`()
BEGIN
		select `PARENT_ID`, LAST_MSG_RECEIVED from `hw_conveyor_master` group by `PARENT_ID`;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetBarcodeByBinId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetBarcodeByBinId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetBarcodeByBinId`(in p_binId varchar(200))
BEGIN
		select `BIN_BARCODE` from `bin_info_master` where `BIN_ID` = p_binId limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetBarcodeOfConveyorStation` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetBarcodeOfConveyorStation` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetBarcodeOfConveyorStation`(
	IN p_parentId INT
    )
BEGIN
		select `BARCODE_ON_STATION_SCAN`,`BARCODE_ON_PICK_SCAN`  from `hw_conveyor_master` where `PARENT_ID` = p_parentId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetBinBarcodeRegex` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetBinBarcodeRegex` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetBinBarcodeRegex`()
BEGIN
    select KEY_VALUE from master_config where KEY_NAME = 'BIN_BARCODE_REGEX' limit 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetBinIdByBarcode` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetBinIdByBarcode` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetBinIdByBarcode`(in p_barcode varchar(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci)
BEGIN
		select `BIN_ID` from `bin_info_master` where `BIN_BARCODE` = p_barcode limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetBotLocationIdsForCharging` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetBotLocationIdsForCharging` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetBotLocationIdsForCharging`()
BEGIN
    DECLARE v_xPad INT DEFAULT 1; 
    DECLARE v_yPad INT DEFAULT 1; 
    
    SELECT DISTINCT lm.LOCATION_ID
    FROM hw_charging_station_master hcsm
    JOIN location_master lm ON hcsm.LOCATION_ID = lm.LOCATION_ID
    JOIN bot_master bm 
        ON bm.GRIDX BETWEEN (lm.X - 1) AND (lm.X + 1)
       AND bm.GRIDY BETWEEN (lm.Y - 1) AND (lm.Y + 1)
    JOIN teleoperation_bool_data tbd ON bm.BOT_ID = tbd.BOT_ID
    WHERE bm.CHARGING_BIT = 1
      AND bm.CAN_AUTOCHARGE = 1
      AND tbd.BATTERY_AUTO_CHARGING = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetChargingStationGlobalPause` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetChargingStationGlobalPause` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetChargingStationGlobalPause`(
	IN p_hardwareId INT
    )
BEGIN
		SELECT `GLOBAL_PAUSE` FROM `hw_charging_station_master` WHERE `STATION_ID` = p_hardwareId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetConveyorBinOnPickAckByParentId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetConveyorBinOnPickAckByParentId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetConveyorBinOnPickAckByParentId`(
	IN p_parentID INT
    )
BEGIN
		select `BIN_ON_PICK_ACK`
		from `hw_conveyor_master` 
		WHERE `PARENT_ID` = p_parentID
		limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetConveyorCounterByConveyorId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetConveyorCounterByConveyorId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetConveyorCounterByConveyorId`(
	IN p_hardwareId INT
    )
BEGIN
	select `COUNTER` 
	from `hw_conveyor_master`
	WHERE `CONVEYOR_ID` = p_hardwareId 
	limit 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetConveyorDataByConveyorId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetConveyorDataByConveyorId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetConveyorDataByConveyorId`(
	IN p_conveyorId INT  )
BEGIN
		select * from `hw_conveyor_master` WHERE `CONVEYOR_ID` = p_conveyorId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetConveyorDataByParentId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetConveyorDataByParentId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetConveyorDataByParentId`(
	in p_parentID int
    )
BEGIN
		select * from `hw_conveyor_master` where  `PARENT_ID` = p_parentID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetConveyorLastMsg` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetConveyorLastMsg` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetConveyorLastMsg`(
	IN p_parentID INT    )
BEGIN
		select LAST_MSG_RECEIVED from `hw_conveyor_master` WHERE `PARENT_ID` = p_parentID;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetConveyorMutliplexerConfiguration` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetConveyorMutliplexerConfiguration` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetConveyorMutliplexerConfiguration`(
	IN p_hardwareId INT
    )
BEGIN
	SELECT `IP`,`PORT`,`MAKE`,`REGISTER_WRITE_ADDRESS`,`REGISTER_READ_ADDRESS`,`REGISTER_READ_LENGTH`
	FROM `hw_conveyor_mux_master`
	WHERE `MUX_ID` = p_hardwareId
	limit 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetConveyorRegisterReadAddress` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetConveyorRegisterReadAddress` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetConveyorRegisterReadAddress`()
BEGIN
    SELECT KEY_VALUE FROM master_config WHERE KEY_NAME = 'CONVEYOR_READ_ADDRESS' LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetConveyorRegisterReadLength` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetConveyorRegisterReadLength` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetConveyorRegisterReadLength`()
BEGIN
    SELECT KEY_VALUE FROM master_config WHERE KEY_NAME = 'CONVEYOR_READ_STRING_LENGTH' LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetConveyorRegisterWriteAddress` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetConveyorRegisterWriteAddress` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetConveyorRegisterWriteAddress`()
BEGIN
    SELECT KEY_VALUE FROM master_config WHERE KEY_NAME = 'CONVEYOR_WRITE_ADDRESS' LIMIT 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetCurtainLightGlobalPause` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetCurtainLightGlobalPause` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetCurtainLightGlobalPause`(
	IN p_state INT,
	IN p_hardwareId INT
    )
BEGIN
		SELECT `GLOBAL_PAUSE` FROM `hw_curtain_light_master` WHERE `LIGHT_ID` = p_hardwareId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetCurtainLightGlobalPauseByParentId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetCurtainLightGlobalPauseByParentId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetCurtainLightGlobalPauseByParentId`(
	IN p_parentId INT
    )
BEGIN
		SELECT `GLOBAL_PAUSE` FROM `hw_curtain_light_master` WHERE `PARENT_ID` = p_parentId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetCurtainLightLastSentBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetCurtainLightLastSentBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetCurtainLightLastSentBit`(
	IN p_hardwareId INT
    )
BEGIN
		select LAST_SENT_BITS from `hw_curtain_light_master` 
		WHERE `LIGHT_ID` = p_hardwareId limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetCurtainLightsParentStationPosition` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetCurtainLightsParentStationPosition` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sm_GetCurtainLightsParentStationPosition`(
	IN p_parentId INT
    )
BEGIN
		SELECT 
    CASE 
        WHEN lm.X > 0 THEN TRUE 
        ELSE FALSE 
    END AS result
FROM hw_station_master hsm
JOIN location_master lm 
    ON hsm.LOCATION_ID = lm.LOCATION_ID
WHERE hsm.STATION_ID = p_parentId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetDistinctConveyorDetails` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetDistinctConveyorDetails` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetDistinctConveyorDetails`()
BEGIN
    SELECT DISTINCT `PARENT_ID`,`IP`, `PORT`, `MAKE`
    FROM `hw_conveyor_master`;	
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetLiveStationByWaveId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetLiveStationByWaveId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetLiveStationByWaveId`(IN p_waveId VARCHAR(200))
BEGIN
SELECT STATION_ID FROM `hw_station_master` WHERE `WAVE_ID` = p_waveId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetMaintenanceMultiplexerList` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetMaintenanceMultiplexerList` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetMaintenanceMultiplexerList`()
BEGIN
    SELECT `id`
    FROM `hw_maintenance_scanner_multiplexer_master`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetMultiplexerIdByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetMultiplexerIdByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetMultiplexerIdByStationId`(in p_stationId int)
BEGIN
    SELECT `CONVEYOR_MUX_ID`
    FROM `hw_conveyor_master`
    where `PARENT_ID` = p_stationId
    limit 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetMultiplexerList` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetMultiplexerList` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetMultiplexerList`()
BEGIN
    SELECT `MUX_ID`
    FROM `hw_conveyor_mux_master`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetMuxAutoBoolByConveyorId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetMuxAutoBoolByConveyorId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `sm_GetMuxAutoBoolByConveyorId`(
	IN p_conveyorId INT  )
BEGIN
		select `AUTO_BOOL` 
		from `hw_conveyor_mux_master` 
		WHERE `MUX_ID` = p_conveyorId
		limit 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetNoReadMessageOnDisplay` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetNoReadMessageOnDisplay` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetNoReadMessageOnDisplay`(in p_parentId int)
BEGIN
		select NOREAD_MESSAGE
		from `hw_display_master`
		where `PARENT_ID` = p_parentId;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetOnStationBinIdByBarcode` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetOnStationBinIdByBarcode` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetOnStationBinIdByBarcode`(in p_barcode varchar(200), IN p_stationId INT)
BEGIN
		SELECT bim.`BIN_ID` FROM `bin_info_master` bim
		JOIN `order_bin_mapping` obm 
		ON bim.`BIN_ID` = obm.`BIN_ID`
		WHERE bim.`BIN_BARCODE` = p_barcode 
		AND obm.`TYPE` = 'RACK_PICK'
		AND obm.`STATUS` = 'PRE_ON_STATION'
		AND obm.`STATION_ID` = p_stationId
		LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `sm_GetOnStationOrderBinIdByStationId` */

/*!50003 DROP PROCEDURE IF EXISTS  `sm_GetOnStationOrderBinIdByStationId` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `sm_GetOnStationOrderBinIdByStationId`(
	in p_stationId int
    )
BEGIN
	SELECT `ORDER_BIN_ID`, `BIN_ID` 
	FROM `order_bin_mapping` 
	WHERE `STATION_ID` = p_stationId
	AND `STATUS` = 'ON_STATION';
END */$$
DELIMITER ;
