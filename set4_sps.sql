
------------------------------------------------------------------------------------------------------------------------
/* Procedure structure for procedure `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STOCK_AUDIT_WAVE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STOCK_AUDIT_WAVE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STOCK_AUDIT_WAVE`(IN Parameters JSON)
BEGIN
    DECLARE _validationFailed INT DEFAULT 0;
    DECLARE waveId VARCHAR(50);
    DECLARE waveType VARCHAR(50);
    DECLARE waveUniqueId INT;
    DECLARE tableName VARCHAR(20);
    DECLARE sqlQuery VARCHAR(1000);
    DECLARE backendWaveId VARCHAR(200);
    SET waveId = Parameters ->> '$.WaveName';
    SET waveType = Parameters ->> '$.WaveType';
    SET waveUniqueId = Parameters ->> '$.UploadedWaveId';
    
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
    CREATE TEMPORARY TABLE tmp_invalidRowinWaveData (
        ID INT, 
        _message VARCHAR(2000)
    );
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message)
    SELECT 
        ID, 
        CASE
            WHEN COALESCE(`BIN_ID`, '') = '' AND COALESCE(`SKU_ID`, '') = '' THEN 
                'Both SKU_ID and BIN_ID cannot be NULL.'
        END AS _message
    FROM `stock_audit_wave_wms_data_dsb_upload_validation`
    WHERE UPLOADED_WAVE_ID = waveUniqueId
    AND (
        (COALESCE(`BIN_ID`, '') = '' AND COALESCE(`SKU_ID`, '') = '') 
    );
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message) 
    SELECT A.ID, 'SKU_ID not present in sku_master'
    FROM `stock_audit_wave_wms_data_dsb_upload_validation` A 
    LEFT JOIN `sku_master` B ON A.SKU_ID = B.SKU_ID 
    WHERE B.SKU_ID IS NULL AND A.SKU_ID IS NOT NULL
    AND A.UPLOADED_WAVE_ID = waveUniqueId;
    
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message) 
    SELECT DISTINCT A.ID, 'BIN_ID not present in bin_info_master'
    FROM `stock_audit_wave_wms_data_dsb_upload_validation` A 
    LEFT JOIN `bin_info_master` B ON A.`BIN_ID` = B.`BIN_ID` 
    WHERE B.`BIN_ID` IS NULL AND A.`BIN_ID` IS NOT NULL
    AND A.UPLOADED_WAVE_ID = waveUniqueId;
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message) 
    SELECT DISTINCT A.ID, 'BIN_SEGEMENT not present in bin_info_master'
    FROM `stock_audit_wave_wms_data_dsb_upload_validation` A 
    LEFT JOIN `bin_info_master` B ON A.`BIN_ID` = B.`BIN_ID` 
    WHERE B.`BIN_ID` IS NOT NULL AND B.`BIN_SEGMENTS`< A.`BIN_SEGMENT_NO` AND A.`BIN_ID` IS NOT NULL AND A.BIN_SEGMENT_NO IS NOT NULL
    AND A.UPLOADED_WAVE_ID = waveUniqueId;
    
    
    IF EXISTS (SELECT 1 FROM tmp_invalidRowinWaveData) THEN
        SET _validationFailed = 1;
        
        UPDATE `stock_audit_wave_wms_data_dsb_upload_validation` C
        INNER JOIN (
            SELECT ID, GROUP_CONCAT(_message SEPARATOR ' ') AS _message
            FROM tmp_invalidRowinWaveData
            GROUP BY ID
        ) T ON T.ID = C.ID
        SET C.`VALIDATION_MESSAGE` = T._message;
    END IF;
    
    
    IF _validationFailed = 1 THEN
        UPDATE `dashboard_wave_upload_status` 
        SET `STATUS` = 'Failed' 
        WHERE ID = waveUniqueId;
    ELSE
        UPDATE `dashboard_wave_upload_status` 
        SET `STATUS` = 'Insertion In Progress' 
        WHERE ID = waveUniqueId;
        
   
   
         CALL DSB_WAVE_DATA_INSERT_CONFIG_INTO_TABLES(Parameters);
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STORAGE_REQUEST` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STORAGE_REQUEST` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STORAGE_REQUEST`(IN Parameters JSON)
BEGIN
    DECLARE _validationFailed INT DEFAULT 0;
    DECLARE updatedBy VARCHAR(200);
    DECLARE waveUniqueId INT;
    DECLARE v_errorMessage TEXT;
    DECLARE v_storageRequestPalletData INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
         GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;  
        ROLLBACK;  
        SELECT 0 AS Success, 'FAILED DUE TO ERROR' AS Message, v_errorMessage AS DESCRIPTION;
    END;
    SET waveUniqueId = Parameters ->> '$.UploadedWaveId';
    SET updatedBy = Parameters ->> '$.UpdatedBy';
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
    CREATE TEMPORARY TABLE tmp_invalidRowinWaveData(ID INT, _message VARCHAR(2000));
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message)
    SELECT 
        ID,
        CONCAT(
            CASE WHEN COALESCE(TRIM(ArticleId), '') = '' THEN 'ArticleId is null or empty. ' ELSE '' END,
            CASE WHEN Quantity IS NULL OR Quantity <= 0 THEN 'Quantity is null or zero. ' ELSE '' END,
            CASE WHEN COALESCE(TRIM(StorageId), '') = '' THEN 'StorageId is null or empty. ' ELSE '' END,
            CASE WHEN COALESCE(TRIM(gln), '') = '' THEN 'gln is null or empty. ' ELSE '' END,
            CASE WHEN COALESCE(TRIM(`StorageRequestId`), '') = '' THEN 'StorageRequestId is null or empty. ' ELSE '' END,
            CASE WHEN COALESCE(TRIM(`PalletId`), '') = '' THEN 'Pallet is null or empty. ' ELSE '' END,
            CASE WHEN COALESCE(TRIM(CountryOfOrigin), '') = '' THEN 'CountryOfOrigin is null or empty. ' ELSE '' END,
            CASE WHEN ExpirationDate IS NULL THEN 'ExpirationDate is null. ' ELSE '' END,
            CASE WHEN Mrp IS NULL OR Mrp <= 0 THEN 'Mrp is null or zero. ' ELSE '' END
        ) AS _message
    FROM storage_request_wms_data_dsb_upload_validation
    WHERE UPLOADED_WAVE_ID = waveUniqueId AND (
        COALESCE(TRIM(ArticleId), '') = '' OR
        Quantity IS NULL OR Quantity <= 0 OR
        COALESCE(TRIM(StorageId), '') = '' OR
        COALESCE(TRIM(gln), '') = '' OR
        COALESCE(TRIM(`StorageRequestId`), '') = '' OR
        COALESCE(TRIM(`PalletId`), '') = '' OR
        COALESCE(TRIM(CountryOfOrigin), '') = '' OR
        ExpirationDate IS NULL OR
        Mrp IS NULL OR Mrp <= 0
    );
    
    INSERT INTO tmp_invalidRowinWaveData(ID, _message)
    SELECT A.ID, 'ArticleId does not exist in SKU master.'
    FROM storage_request_wms_data_dsb_upload_validation AS A
    LEFT JOIN sku_master AS B ON A.ArticleId = B.SKU_ID
    WHERE B.SKU_ID IS NULL AND A.UPLOADED_WAVE_ID = waveUniqueId;
    
    INSERT INTO tmp_invalidRowinWaveData(ID, _message)
    SELECT  DISTINCT sr.ID, CONCAT('StorageId ', sr.StorageId, ' is already processed')
    FROM storage_request_wms_data_dsb_upload_validation sr
    INNER JOIN wms_to_wcs_storage_request_data wsrpd ON sr.StorageId = wsrpd.STORAGE_ID
    WHERE sr.UPLOADED_WAVE_ID = waveUniqueId;
    
     INSERT INTO tmp_invalidRowinWaveData(ID, _message)
    SELECT  DISTINCT sr.ID, CONCAT('StorageRequestId ', sr.`StorageRequestId`, ' is already processed or in process')
    FROM storage_request_wms_data_dsb_upload_validation sr
    INNER JOIN `wms_to_wcs_storage_request_pallet_data` wsrpd ON sr.StorageRequestId = wsrpd.`STORAGE_REQUEST_ID`
    WHERE wsrpd.`PALLET_SCANNED`=1 AND  sr.UPLOADED_WAVE_ID = waveUniqueId;
    
    INSERT INTO tmp_invalidRowinWaveData(ID, _message)
    SELECT  DISTINCT sr.ID, CONCAT('PalletId  ', sr.`PalletId`, ' is already in use by system')
    FROM storage_request_wms_data_dsb_upload_validation sr
    INNER JOIN `wms_to_wcs_storage_request_pallet_data` wsrpd ON sr.PalletId = wsrpd.`PALLET_ID`
    WHERE wsrpd.`STORAGE_REQUEST_STATUS`='PENDING' AND  sr.UPLOADED_WAVE_ID = waveUniqueId;
    
    INSERT INTO tmp_invalidRowinWaveData(ID, _message)
    SELECT  DISTINCT sr.ID, CONCAT('StorageId ', sr.StorageId, ' is repeated ')
    FROM storage_request_wms_data_dsb_upload_validation sr
    INNER JOIN storage_request_wms_data_dsb_upload_validation wsrpd ON sr.StorageId = wsrpd.StorageId
    WHERE sr.UPLOADED_WAVE_ID = waveUniqueId AND wsrpd.UPLOADED_WAVE_ID = waveUniqueId AND sr.`ROW_NUMBER` <> wsrpd.ROW_NUMBER;
    
    
    INSERT INTO tmp_invalidRowinWaveData(ID, _message)
    SELECT  DISTINCT sr.ID, CONCAT('palletId ', sr.`PalletId`, ' repeated in StorageRequestId ' ,sr.`StorageRequestId` ,' AND ', wsrpd.`StorageRequestId`)
    FROM storage_request_wms_data_dsb_upload_validation sr
    INNER JOIN storage_request_wms_data_dsb_upload_validation wsrpd ON sr.`PalletId` = wsrpd.`PalletId`
    WHERE sr.UPLOADED_WAVE_ID = waveUniqueId AND wsrpd.UPLOADED_WAVE_ID = waveUniqueId AND sr.`StorageRequestId` <> wsrpd.`StorageRequestId`;
    
    
    IF EXISTS (SELECT 1 FROM tmp_invalidRowinWaveData) THEN
        SET _validationFailed = 1;
        
        UPDATE storage_request_wms_data_dsb_upload_validation AS C
        INNER JOIN (
            SELECT ID, GROUP_CONCAT(_message SEPARATOR ' | ') AS _message
            FROM tmp_invalidRowinWaveData
            GROUP BY ID
        ) T ON T.ID = C.ID
        SET C.VALIDATION_MESSAGE = T._message;
        
        UPDATE dashboard_wave_upload_status SET STATUS = 'Failed'
        WHERE ID = waveUniqueId;
        SELECT 0 AS SUCCESS, 'Validation Failed' AS MESSAGE, 'One or more validation errors occurred.' AS DESCRIPTION;
    ELSE
        START TRANSACTION;
        
        INSERT IGNORE INTO wms_to_wcs_storage_request_pallet_data (
            STORAGE_REQUEST_ID,GLN, PALLET_ID, STORAGE_REQUEST_STATUS
        )
        SELECT DISTINCT  StorageRequestId,gln, PalletId, 'PENDING'
        FROM storage_request_wms_data_dsb_upload_validation
        WHERE UPLOADED_WAVE_ID = waveUniqueId;
        
        
        INSERT IGNORE INTO sku_batch_master (
            SKU_ID, CLIENT_BATCH_ID, BATCH_ID, MRP, EXPIRY_DATE,GLN, COUNTRY_OF_ORIGIN
        )
        SELECT DISTINCT
            ArticleId, BatchNumber, UUID(), Mrp, ExpirationDate,gln ,CountryOfOrigin
        FROM storage_request_wms_data_dsb_upload_validation
        WHERE UPLOADED_WAVE_ID = waveUniqueId;
        
        INSERT INTO wms_to_wcs_storage_request_data (
            WMS_STORAGE_REQUEST_PALLET_DATA_ID, STORAGE_REQUEST_ID, STORAGE_ID,
            ARTICLE_ID, QUANTITY, BATCH_ID, PAYLOAD_ID
        )
        SELECT 
            wwsrpd.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`,
            StorageRequestId,
            StorageId,
            ArticleId,
            Quantity,
            sbm.BATCH_ID,
            NULL
        FROM storage_request_wms_data_dsb_upload_validation srd
        INNER JOIN wms_to_wcs_storage_request_pallet_data wwsrpd 
        ON wwsrpd.`STORAGE_REQUEST_ID` = srd.`StorageRequestId`
        INNER JOIN sku_batch_master sbm
            ON srd.ArticleId = sbm.SKU_ID
            AND srd.ExpirationDate = sbm.EXPIRY_DATE
            AND srd.Mrp = sbm.MRP
            AND srd.gln=sbm.GLN
        WHERE srd.UPLOADED_WAVE_ID = waveUniqueId;
        COMMIT;
        UPDATE dashboard_wave_upload_status SET STATUS = 'Uploaded Successfully'
        WHERE ID = waveUniqueId;
        SELECT 1 AS Success, "Uploaded Successfully" AS STATUS, '' AS DESCRIPTION;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_VALIDATION_FAILED` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_VALIDATION_FAILED` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_VALIDATION_FAILED`(IN Parameters VARCHAR(50))
BEGIN
    DECLARE waveType VARCHAR(50);
    DECLARE IDnumber INT;
    SELECT `WAVE_TYPE`, `ID` INTO waveType, IDnumber 
    FROM `dashboard_wave_upload_status` 
    WHERE `CLIENT_WAVE_ID` = Parameters order By `INSERTED_ON` DESC limit 1;
    IF waveType = 'put_wave' THEN 
        SELECT row_num  AS 'ROW_NUMBER', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                `ROW_NUMBER` as row_num,
                `VALIDATION_MESSAGE`
            FROM `put_wave_wms_data_dsb_upload_validation` 
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
    ELSEIF waveType = 'pick_wave' THEN 
        SELECT row_num  AS 'ROW_NUMBER', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                `ROW_NUMBER` AS row_num,
                `VALIDATION_MESSAGE` 
            FROM `pick_wave_wms_data_dsb_upload_validation` 
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
    ELSEIF waveType = 'sku_master' THEN 
        SELECT row_num AS 'ROW_NUMBER', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                `ROW_NUMBER` AS row_num,
                `VALIDATION_MESSAGE` 
            FROM `sku_master_dsb_upload_validation`
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
 
    ELSEIF waveType = 'sku_ean_mapping' THEN 
        SELECT row_num AS 'ROW_NUMBER', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                `ROW_NUMBER` AS row_num,
                `VALIDATION_MESSAGE`
                
            FROM `sku_ean_mapping_dsb_upload_validation`
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
      
      ELSEIF waveType = 'prepare_orders' THEN 
        SELECT row_num AS 'ROW_NUMBER', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                `ROW_NUMBER` AS row_num,
                `VALIDATION_MESSAGE`
                
            FROM `prepare_orders_wms_data_dsb_upload_validation`
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
       
       ELSEIF waveType = 'storage_request' THEN 
        SELECT row_num AS 'ROW_NUMBER', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                `ROW_NUMBER` AS row_num,
                `VALIDATION_MESSAGE`
                
            FROM `storage_request_wms_data_dsb_upload_validation`
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
        
      ELSEIF waveType = 'stock_audit_by_bin_id_new' OR waveType = 'stock_audit_by_sku_id_new' OR waveType = 'stock_audit_by_random_new' OR waveType = 'stock_audit' THEN
        SELECT row_num  AS 'ROW_NUMBER', VALIDATION_MESSAGE 
        FROM (
            SELECT 
                `ROW_NUMBER` AS row_num,
                `VALIDATION_MESSAGE`
            FROM `stock_audit_wave_wms_data_dsb_upload_validation`
            WHERE `UPLOADED_WAVE_ID` = IDnumber
        ) TT 
        WHERE validation_message IS NOT NULL;
    END IF;
    delete from `pick_wave_wms_data_dsb_upload_validation` where `UPLOADED_WAVE_ID`=IDnumber;
    DELETE FROM `put_wave_wms_data_dsb_upload_validation` WHERE `UPLOADED_WAVE_ID`=IDnumber;
    DELETE FROM `sku_ean_mapping_dsb_upload_validation` WHERE `UPLOADED_WAVE_ID`=IDnumber;
    DELETE FROM `sku_master_dsb_upload_validation` WHERE `UPLOADED_WAVE_ID`=IDnumber;
    DELETE FROM `stock_audit_wave_wms_data_dsb_upload_validation` WHERE `UPLOADED_WAVE_ID`=IDnumber;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_USER_DELETE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_USER_DELETE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_USER_DELETE`(IN Parameters JSON)
BEGIN
    
    DECLARE p_user_id INT;
    DECLARE p_role_id INT;
    
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255) DEFAULT 'Deleted successfully';
    
    SET p_user_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id')) AS UNSIGNED);
    SET p_role_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.role_id')) AS UNSIGNED);
    
    IF NOT EXISTS (SELECT 1 FROM dashboard_user_master WHERE USER_ID = p_user_id) THEN
        SET Success = 0;
        SET Result = 'User Not Exists';
    ELSE
        
        IF p_role_id <> 0 THEN
            DELETE FROM dashboard_user_role_setting_mapping
            WHERE USER_ID = p_user_id AND ROLE_ID = p_role_id;
        ELSE
            
            DELETE FROM dashboard_user_role_setting_mapping
            WHERE USER_ID = p_user_id;
            DELETE FROM dashboard_user_master
            WHERE USER_ID = p_user_id;
        END IF;
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_USER_DETAILS_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_USER_DETAILS_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_USER_DETAILS_GET`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_user_id INT;
    DECLARE p_role_id INT;
    
    SET p_user_id  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id'));
    SET p_role_id  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.role_id'));
    
    SELECT 
        dum.USER_ID,
        dum.USER_NAME,
        dum.USER_FULL_NAME,
        drm.ROLE_ID,
        drm.ROLE_NAME,
        dursm.IS_LOCKED,
        dursm.IS_LOCKED_TIMESTAMP,
        dursm.GRID_SHOW_TOOLTIP,
        dursm.CS_GRIDX,
        dursm.CS_GRIDY,
        dursm.DEFAULT_LANGUAGE
    FROM dashboard_user_master dum
    INNER JOIN dashboard_user_role_setting_mapping dursm 
        ON dursm.USER_ID = dum.USER_ID
    INNER JOIN dashboard_role_master drm 
        ON drm.ROLE_ID = dursm.ROLE_ID
    WHERE dursm.USER_ID = p_user_id
      AND dursm.ROLE_ID = p_role_id;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_USER_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_USER_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_USER_INSERT`(IN Parameters JSON)
BEGIN
    
    DECLARE p_user_id INT;
    DECLARE p_user_name VARCHAR(45);
    DECLARE p_user_full_name VARCHAR(100);
    DECLARE p_password VARCHAR(100);
    DECLARE p_is_locked TINYINT;
    DECLARE p_updated_by VARCHAR(45);
    DECLARE p_inserted_by VARCHAR(45);
    DECLARE p_user_is_active TINYINT;
    DECLARE p_role_is_active TINYINT;
    DECLARE p_show_grid_tooltip TINYINT;
    
    DECLARE v_seed BIGINT;
    DECLARE v_lcv TINYINT;
    DECLARE v_salt VARCHAR(50);
    DECLARE v_password_with_salt VARCHAR(256);
    DECLARE Success INT DEFAULT 1;
    DECLARE Result VARCHAR(255) DEFAULT 'Operation completed successfully';
    
    SET p_user_id           = CAST(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.user_id')) AS UNSIGNED);
    SET p_user_name         = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.user_name'));
    SET p_user_full_name    = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.user_full_name'));
    SET p_password          = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.password'));
    SET p_is_locked         = CAST(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.is_locked')) AS UNSIGNED);
    SET p_user_is_active    = CAST(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.user_is_active')) AS UNSIGNED);
    SET p_role_is_active    = CAST(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.role_is_active')) AS UNSIGNED);
    SET p_show_grid_tooltip = CAST(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.show_grid_tooltip')) AS UNSIGNED);
    SET p_updated_by        = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.updated_by'));
    
    DROP TEMPORARY TABLE IF EXISTS temp_role_id;
    CREATE TEMPORARY TABLE temp_role_id (role_id INT);
    INSERT INTO temp_role_id
    SELECT TRIM(JSON_UNQUOTE(j.value))
    FROM JSON_TABLE(
        JSON_EXTRACT(parameters, '$.role_id'),
        '$[*]' COLUMNS (value JSON PATH '$')
    ) AS j;
    
    IF p_password IS NOT NULL AND p_password != '' THEN
        SET v_seed = UNIX_TIMESTAMP(NOW());
        SET v_lcv = 1;
        SET v_salt = CHAR(FLOOR(RAND(v_seed) * 94) + 33);
        WHILE v_lcv < 25 DO
            SET v_salt = CONCAT(v_salt, CHAR(FLOOR(RAND() * 94) + 33));
            SET v_lcv = v_lcv + 1;
        END WHILE;
        SET v_password_with_salt = MD5(CONCAT(p_password, v_salt));
    END IF;
    START TRANSACTION;
    
    IF p_user_id = 0 THEN
        IF EXISTS (SELECT 1 FROM dashboard_user_master WHERE USER_NAME = p_user_name) THEN
            SET Success = 0;
            SET Result = 'UserName Already Exists';
        ELSE
            INSERT INTO dashboard_user_master (
                USER_NAME, USER_FULL_NAME, SALT, USER_PASSWORD,
                IS_ACTIVE, INSERTED_BY, UPDATED_BY
            ) VALUES (
                p_user_name, p_user_full_name, v_salt, v_password_with_salt,
                p_user_is_active, p_updated_by, p_updated_by
            );
            SELECT USER_ID INTO p_user_id
            FROM dashboard_user_master
            WHERE USER_NAME = p_user_name;
            INSERT INTO dashboard_user_role_setting_mapping (
                USER_ID, ROLE_ID, IS_LOCKED, IS_LOCKED_TIMESTAMP,
                GRID_SHOW_TOOLTIP, IS_ACTIVE,
                INSERTED_BY, UPDATED_BY
            )
            SELECT
                p_user_id, role_id, p_is_locked, NOW(),
                p_show_grid_tooltip, p_role_is_active,
                p_updated_by, p_updated_by
            FROM temp_role_id;
        END IF;
    ELSE
        
        UPDATE dashboard_user_master
        SET 
            USER_NAME = COALESCE(p_user_name, USER_NAME),
            USER_FULL_NAME = COALESCE(p_user_full_name, USER_FULL_NAME),
            IS_ACTIVE = COALESCE(p_user_is_active, IS_ACTIVE),
            UPDATED_BY = COALESCE(p_updated_by, UPDATED_BY),
            SALT = IF(p_password IS NOT NULL AND p_password != '', v_salt, SALT),
            USER_PASSWORD = IF(p_password IS NOT NULL AND p_password != '', v_password_with_salt, USER_PASSWORD)
        WHERE USER_ID = p_user_id;
        UPDATE dashboard_user_role_setting_mapping
        SET 
            IS_LOCKED = COALESCE(p_is_locked, IS_LOCKED),
            IS_LOCKED_TIMESTAMP = NOW(),
            GRID_SHOW_TOOLTIP = COALESCE(p_show_grid_tooltip, GRID_SHOW_TOOLTIP),
            IS_ACTIVE = COALESCE(p_user_is_active, IS_ACTIVE),
            UPDATED_BY = COALESCE(p_updated_by, UPDATED_BY)
        WHERE 
            USER_ID = p_user_id AND ROLE_ID IN (SELECT role_id FROM temp_role_id);
    END IF;
    COMMIT;
    
    SELECT Success, Result;
    
    DROP TEMPORARY TABLE IF EXISTS temp_role_id;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_USER_LOGIN_LATEST_DETAILS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_USER_LOGIN_LATEST_DETAILS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_USER_LOGIN_LATEST_DETAILS`(
  IN Parameters JSON
)
BEGIN
  
  DECLARE p_user_id  INT;
  DECLARE p_role_id  INT;
  
  DECLARE v_session_id         INT      DEFAULT 0;
  DECLARE v_dashboard_updated  BOOLEAN  DEFAULT FALSE;
  DECLARE v_dashboard_default_updated_text VARCHAR(255) DEFAULT NULL;
  DECLARE v_dashboard_last_updated_text    VARCHAR(255) DEFAULT NULL;
  DECLARE v_user_name   VARCHAR(50);
  DECLARE v_station_id  INT       DEFAULT NULL;
  DECLARE v_show_short_put  BOOLEAN DEFAULT FALSE;
  DECLARE v_short_put_count INT      DEFAULT 0;
  DECLARE v_wave_id     VARCHAR(50) DEFAULT NULL;
  DECLARE v_wave_type   VARCHAR(50) DEFAULT NULL;
  
  SET p_user_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id')) AS UNSIGNED);
  SET p_role_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.role_id')) AS UNSIGNED);
  
  IF EXISTS (
    SELECT 1
    FROM dashboard_user_master AS dum
    JOIN dashboard_user_role_setting_mapping AS rsm
      ON dum.USER_ID = rsm.USER_ID
    JOIN dashboard_log_user_login_attempts AS dlla
      ON dlla.USER_ID = dum.USER_ID
    WHERE dum.USER_ID = p_user_id
      AND rsm.ROLE_ID = p_role_id
      AND dlla.ROLE_ID = p_role_id
  ) THEN
    
    SELECT ID
      INTO v_session_id
    FROM dashboard_log_user_login_attempts
    WHERE USER_ID = p_user_id
      AND ROLE_ID = p_role_id
      AND STATUS  = 'SUCCEED'
    ORDER BY ID DESC
    LIMIT 1;
    
    SELECT DASHBOARD_UPDATED
      INTO v_dashboard_updated
    FROM dashboard_user_role_setting_mapping
    WHERE USER_ID = p_user_id
      AND ROLE_ID = p_role_id;
    IF (v_dashboard_updated = 1) THEN
      SELECT KEY_VALUE
        INTO v_dashboard_default_updated_text
      FROM master_config
      WHERE KEY_NAME = 'DSB_DEFAULT_DASHBOARD_UPDATES_TEXT'
      LIMIT 1;
      SELECT KEY_VALUE
        INTO v_dashboard_last_updated_text
      FROM master_config
      WHERE KEY_NAME = 'DSB_LAST_DASHBOARD_UPDATES_TEXT'
      LIMIT 1;
    ELSE
      SET v_dashboard_default_updated_text = '';
      SET v_dashboard_last_updated_text    = '';
    END IF;
    
    SELECT COALESCE(
             CASE WHEN LOWER(KEY_VALUE) IN ('1') THEN 1 ELSE 0 END,
             0
           )
      INTO v_show_short_put
    FROM master_config
    WHERE KEY_NAME = 'DSB_OPERATOR_SPR_VIEW_ENABLED'
    LIMIT 1;
    
    IF v_show_short_put = TRUE AND p_role_id IN (1, 8) THEN
      
      SELECT
        hsm.STATION_ID,
        hsm.WAVE_ID,
        wm.WAVE_TYPE,
        dum.USER_NAME
      INTO
        v_station_id,
        v_wave_id,
        v_wave_type,
        v_user_name
      FROM dashboard_user_master AS dum
      JOIN hw_station_master AS hsm
        ON hsm.LOGGED_IN_USER_ID = dum.USER_NAME
      LEFT JOIN wave_master AS wm
        ON wm.WAVE_ID = hsm.WAVE_ID
      WHERE dum.USER_ID = p_user_id
      LIMIT 1;
      
      IF UPPER(v_wave_type) = 'PUT' THEN
        SELECT COALESCE(SUM(cnt), 0)
          INTO v_short_put_count
        FROM (
          SELECT COUNT(*) AS cnt
          FROM short_put_wave_reason AS spwr
          JOIN put_wave_order_master AS pwm
            ON pwm.PUT_ORDER_ID = spwr.PUT_ORDER_ID
          WHERE pwm.WAVE_ID = v_wave_id
            AND pwm.STATION_ID = v_station_id
            AND spwr.RE_ATTEMPT_FLAG = 0
            AND pwm.SHORT_PUT_QUANTITY > 0
          UNION ALL
          SELECT COUNT(*) AS cnt
          FROM short_put_wave_reason AS spwr
          JOIN put_wave_order_master_archive AS pwma
            ON pwma.PUT_ORDER_ID = spwr.PUT_ORDER_ID
          WHERE pwma.WAVE_ID = v_wave_id
            AND pwma.STATION_ID = v_station_id
            AND spwr.RE_ATTEMPT_FLAG = 0
            AND pwma.SHORT_PUT_QUANTITY > 0
            AND pwma.INSERTED_TIMESTAMP >= NOW() - INTERVAL 1 DAY
        ) AS combined_counts;
      END IF;
    ELSE
      
      SET v_wave_id         = 'NA';
      SET v_wave_type       = 'NA';
      SET v_short_put_count = 0;
    END IF;
    
    SELECT
      v_session_id        AS `SESSION_ID`,
      v_dashboard_updated AS `DASHBOARD_UPDATED`,
      CONCAT(v_dashboard_last_updated_text, ' ', v_dashboard_default_updated_text) AS `DASHBOARD_UPDATED_TEXT`,
      v_wave_id           AS `WAVE_ID`,
      v_wave_type         AS `WAVE_TYPE`,
      v_short_put_count   AS `SHORT_PUT_COUNT`;
  ELSE
    
    SELECT
      0 AS `Success`,
      'User Not Found' AS `Message`;
  END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_USER_LOGIN_ROLE_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_USER_LOGIN_ROLE_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_USER_LOGIN_ROLE_GET_ALL`()
BEGIN
    SELECT 
        ROLE_ID,
        ROLE_NAME
    FROM 
        dashboard_role_master
    WHERE 
        IS_ACTIVE = 1
        ORDER BY SEQUENCE ASC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_USER_LOGIN_VALIDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_USER_LOGIN_VALIDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_USER_LOGIN_VALIDATE`(
    IN Parameters JSON
)
proc: BEGIN
    
    DECLARE p_user_name              VARCHAR(50);
    DECLARE p_password               VARCHAR(255);
    DECLARE p_role_id                INT;
    DECLARE p_ip_address             VARCHAR(45);
    DECLARE p_device_info            VARCHAR(255);
    DECLARE p_override_login         TINYINT(1) DEFAULT 0;
    DECLARE p_override_login_confirm TINYINT(1) DEFAULT 0;
    
    DECLARE v_user_id               INT DEFAULT 0;
    DECLARE v_user_full_name        VARCHAR(100);
    DECLARE v_role_name             VARCHAR(50);
    DECLARE v_user_password         VARCHAR(255);
    DECLARE v_user_salt             VARCHAR(255);
    DECLARE v_user_is_locked        INT DEFAULT 0;     
    DECLARE v_user_locked_timestamp DATETIME;          
    DECLARE v_user_login_timestamp  DATETIME;
    DECLARE v_user_logout_timestamp DATETIME;
    DECLARE v_user_active           INT DEFAULT 0;
    DECLARE v_role_active           INT DEFAULT 0;
    DECLARE v_user_default_lock_period INT DEFAULT 1;  
    DECLARE v_user_lock_max            INT DEFAULT 1;  
    DECLARE v_session_id INT DEFAULT 0;
    DECLARE v_station_id INT DEFAULT 0;
    DECLARE Success    INT DEFAULT 0;
    DECLARE Result     VARCHAR(255) DEFAULT '';
    DECLARE StatusCode INT DEFAULT 0;
    
    DECLARE v_not_found TINYINT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = 1;
    
    SET p_user_name   = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    SET p_password    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_password'));
    SET p_role_id     = COALESCE(
                            CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.role_id')), '') AS UNSIGNED),
                            0
                        );
    SET p_ip_address  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ip_address'));
    SET p_device_info = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.device_info'));
    SET p_override_login =
        IF(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.override_login')) = 'true', 1, 0);
    SET p_override_login_confirm =
        IF(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.override_login_confirm')) = 'true', 1, 0);
    
    IF p_user_name IS NULL OR p_user_name = '' THEN
        SET Success = 0;
        SET Result  = 'Please provide User Name to login.';
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    IF p_password IS NULL OR p_password = '' THEN
        SET Success = 0;
        SET Result  = 'Please provide User Password to login.';
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    IF p_role_id = 0 THEN
        SET Success = 0;
        SET Result  = 'Please provide User Role to login.';
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    
    SET v_not_found = 0;
    SET v_user_id = 0;
    SET v_user_active = 0;
    SELECT
        USER_ID,
        USER_FULL_NAME,
        USER_PASSWORD,
        SALT,
        IS_ACTIVE
    INTO
        v_user_id,
        v_user_full_name,
        v_user_password,
        v_user_salt,
        v_user_active
    FROM dashboard_user_master
    WHERE USER_NAME = p_user_name
    LIMIT 1;
    IF v_not_found = 1 OR v_user_id IS NULL OR v_user_id = 0 THEN
        SET Success = 0;
        SET Result  = CONCAT(p_user_name, ' does not exist. Please login with correct username.');
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    IF v_user_active IS NULL OR v_user_active = 0 THEN
        SET Success = 0;
        SET Result  = CONCAT(p_user_name, ' is not active. Please contact admin.');
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM dashboard_role_master WHERE ROLE_ID = p_role_id) THEN
        SET Success = 0;
        SET Result  = 'Role is not found. Please login with correct role.';
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    
    SET v_not_found = 0;
    SET v_role_name = NULL;
    SELECT ROLE_NAME
    INTO v_role_name
    FROM dashboard_role_master
    WHERE ROLE_ID = p_role_id
    LIMIT 1;
    IF v_not_found = 1 OR v_role_name IS NULL OR v_role_name = '' THEN
        SET v_role_name = 'selected role';
    END IF;
    
    IF NOT EXISTS (
        SELECT 1
        FROM dashboard_user_role_setting_mapping
        WHERE USER_ID = v_user_id
          AND ROLE_ID = p_role_id
    ) THEN
        SET Success = 0;
        SET Result  = CONCAT(p_user_name, ' does not authorize with ', v_role_name, '. Please login with correct role.');
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    
    SET v_not_found = 0;
    SELECT
        IS_ACTIVE,
        IS_LOCKED,
        IS_LOCKED_TIMESTAMP,
        LOGIN_TIMESTAMP,
        LOGOUT_TIMESTAMP
    INTO
        v_role_active,
        v_user_is_locked,
        v_user_locked_timestamp,
        v_user_login_timestamp,
        v_user_logout_timestamp
    FROM dashboard_user_role_setting_mapping
    WHERE USER_ID = v_user_id
      AND ROLE_ID = p_role_id
    LIMIT 1;
    IF v_not_found = 1 THEN
        SET Success = 0;
        SET Result  = 'User-role mapping not found.';
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    SET v_role_active    = COALESCE(v_role_active, 0);
    SET v_user_is_locked = COALESCE(v_user_is_locked, 0);
    IF v_role_active = 0 THEN
        SET Success = 0;
        SET Result  = CONCAT(p_user_name, ' with ', v_role_name, ' is not active. Please contact admin.');
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    
    SET v_not_found = 0;
    SELECT CAST(KEY_VALUE AS UNSIGNED)
    INTO v_user_default_lock_period
    FROM master_config
    WHERE KEY_NAME = 'DSB_DEFAULT_USER_LOCK_PERIOD'
    LIMIT 1;
    IF v_not_found = 1 OR v_user_default_lock_period IS NULL OR v_user_default_lock_period = 0 THEN
        SET v_user_default_lock_period = 1;
    END IF;
    SET v_not_found = 0;
    SELECT CAST(KEY_VALUE AS UNSIGNED)
    INTO v_user_lock_max
    FROM master_config
    WHERE KEY_NAME = 'DSB_DEFAULT_USER_LOCK_MAX'
    LIMIT 1;
    IF v_not_found = 1 OR v_user_lock_max IS NULL OR v_user_lock_max = 0 THEN
        SET v_user_lock_max = 5;
    END IF;
    
    IF v_user_is_locked >= v_user_lock_max THEN
        SET Success = 0;
        SET Result  = 'You have crossed maximum login attempts. Please contact admin.';
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
    
    IF v_user_password = MD5(CONCAT(p_password, v_user_salt)) THEN
        
        IF p_override_login = 1 AND p_override_login_confirm = 0 THEN
            INSERT INTO dashboard_log_user_login_attempts
                (USER_ID, ROLE_ID, IP_ADDRESS, DEVICE_INFO, STATUS)
            VALUES
                (v_user_id, p_role_id, p_ip_address, p_device_info, 'CANCELLED');
            SET Success = 0;
            SET Result  = 'Login Request Cancelled Successfully';
            SELECT Success, Result, StatusCode;
            LEAVE proc;
        END IF;
        
        IF p_override_login = 0
           AND (v_user_logout_timestamp IS NULL OR v_user_login_timestamp > v_user_logout_timestamp) THEN
            SET Success    = 0;
            SET Result     = 'You are already logged in or forgot to logout last time.';
            SET StatusCode = 409;
            SELECT Success, Result, StatusCode;
            LEAVE proc;
        END IF;
        
        INSERT INTO dashboard_log_user_login_attempts
            (USER_ID, ROLE_ID, IP_ADDRESS, DEVICE_INFO, STATUS)
        VALUES
            (v_user_id, p_role_id, p_ip_address, p_device_info, 'SUCCEED');
        SET v_session_id = LAST_INSERT_ID();
        UPDATE dashboard_user_role_setting_mapping
        SET LOGIN_TIMESTAMP = NOW(),
            IS_LOCKED = 0
        WHERE USER_ID = v_user_id
          AND ROLE_ID = p_role_id;
        
        UPDATE dashboard_bot_master
        SET LOCK_BY = NULL,
            UNLOCK_BY = p_user_name
        WHERE LOCK_BY = p_user_name;
        UPDATE dashboard_bot_master
        SET REQUEST_BY = NULL
        WHERE REQUEST_BY = p_user_name;
        
        IF p_ip_address IS NOT NULL
           AND EXISTS (SELECT 1 FROM hw_display_master WHERE IP = p_ip_address) THEN
            SELECT PARENT_ID
            INTO v_station_id
            FROM hw_display_master
            WHERE IP = p_ip_address
            LIMIT 1;
        ELSE
            SET v_station_id = 0;
        END IF;
        
        SELECT
            v_user_id        AS USER_ID,
            p_user_name      AS USER_NAME,
            v_user_full_name AS USER_FULL_NAME,
            p_role_id        AS ROLE_ID,
            v_role_name      AS ROLE_NAME,
            (
                SELECT MENU_PATH
                FROM dashboard_menu_master
                WHERE MENU_ID = (
                    SELECT REDIRECT_URL
                    FROM dashboard_role_master
                    WHERE ROLE_ID = p_role_id
                    LIMIT 1
                )
                LIMIT 1
            )                AS REDIRECT_URL,
            v_session_id     AS SESSION_ID,
            v_station_id     AS STATION_ID;
    ELSE
        
        UPDATE dashboard_user_role_setting_mapping
        SET IS_LOCKED = CASE
                            WHEN v_user_locked_timestamp IS NULL THEN 1
                            WHEN TIMESTAMPDIFF(SECOND, v_user_locked_timestamp, NOW())
                                 >= (v_user_default_lock_period * GREATEST(v_user_is_locked, 1) * 60)
                            THEN 1
                            ELSE v_user_is_locked + 1
                        END,
            IS_LOCKED_TIMESTAMP = NOW()
        WHERE USER_ID = v_user_id
          AND ROLE_ID = p_role_id;
        INSERT INTO dashboard_log_user_login_attempts
            (USER_ID, ROLE_ID, IP_ADDRESS, DEVICE_INFO, STATUS)
        VALUES
            (v_user_id, p_role_id, p_ip_address, p_device_info, 'FAILED');
        SET Success    = 0;
        SET StatusCode = 401;
        SET Result     = 'Invalid password. Please try again.';
        SELECT Success, Result, StatusCode;
        LEAVE proc;
    END IF;
END proc */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_USER_LOGOUT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_USER_LOGOUT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_USER_LOGOUT`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_user_id INT;
    DECLARE p_role_id INT;
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(255) DEFAULT '';
    
    SET p_user_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id'));
    SET p_role_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.role_id'));
    
    IF EXISTS (SELECT 1 FROM dashboard_user_master WHERE USER_ID = p_user_id) THEN
        
        
        UPDATE dashboard_user_role_setting_mapping
        SET 
            LOGOUT_TIMESTAMP = NOW(),
            DASHBOARD_UPDATED = 0
        WHERE 
            USER_ID = p_user_id 
            AND ROLE_ID = p_role_id;
            
        SET Success = 1;
        SET Result = 'Logout Successfully';
    
    ELSE
        
        SET Success = 0;
        SET Result = 'User Not Found';
        
    END IF;
    
    SELECT Success, Result;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_COMPLETE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_COMPLETE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_COMPLETE`(IN Parameters JSON)
BEGIN
    
    DECLARE err_msg TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 err_msg = MESSAGE_TEXT;
        SELECT 0 AS Success, CONCAT('SQL Error: ', err_msg) AS Result;
    END;
    
    START TRANSACTION;
    
    CREATE TEMPORARY TABLE IF NOT EXISTS TempStationWaves (
        station_id INT,
        wave_id VARCHAR(100),
        user_name VARCHAR(50)
    );
    
    INSERT INTO TempStationWaves (station_id, wave_id, user_name)
    SELECT 
        station_id, 
        wave_id,
        user_name
    FROM JSON_TABLE(
        Parameters, 
        '$[*]' COLUMNS (
            station_id INT PATH '$.station_id',
            wave_id    VARCHAR(50) PATH '$.wave_id',
            user_name  VARCHAR(50) PATH '$.user_name'
        )
    ) AS jt;
    
    UPDATE wave_master wm
    JOIN TempStationWaves ts ON wm.WAVE_ID = ts.wave_id
    SET wm.IS_STOPPED = 1, wm.COMPLETED_BY = ts.user_name, wm.COMPLETED_TIMESTAMP = NOW();
    
    UPDATE dashboard_log_wave_process dlog
    JOIN TempStationWaves ts ON dlog.WAVE_ID = ts.wave_id AND dlog.STATION_ID = ts.station_id
    SET dlog.COMPLETED_BY = ts.user_name,
        dlog.COMPLETED_TIMESTAMP = NOW();
    
    DROP TEMPORARY TABLE IF EXISTS TempStationWaves;
    
    COMMIT;
    
    SELECT 1 AS Success, 'Wave(s) marked as completed successfully.' AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_DATA_CHECK_IF_EXISTS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_DATA_CHECK_IF_EXISTS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_DATA_CHECK_IF_EXISTS`(in Parameters Varchar(50))
BEGIN
		 DECLARE Result INT DEFAULT 0;
	
		 IF EXISTS (SELECT * FROM dashboard_wave_upload_status WHERE wave_id = Parameters) THEN 
			SET Result=1;		
		 ELSE
			SET Result=0;		
		 END IF;
		 SELECT Result;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_DATA_GET_TARGET_TABLE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_DATA_GET_TARGET_TABLE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_DATA_GET_TARGET_TABLE`(in Parameters varchar(50))
BEGIN
	if Parameters = 'PUT' then 
		select 'put_wave_wms_data_validation' as Result;
	elseif Parameters = 'PICK' THEN 
		select 'pick_wave_wms_data_validation' AS Result;
	ELSEIF Parameters = 'article_master' THEN 
		select 'article_master_validation' AS Result;
	end if;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_DATA_INSERT_CONFIG_INTO_TABLES` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_DATA_INSERT_CONFIG_INTO_TABLES` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_DATA_INSERT_CONFIG_INTO_TABLES`(IN Parameters JSON)
BEGIN
    
    DECLARE waveId VARCHAR(255);
    DECLARE waveType VARCHAR(50);
    DECLARE uploadWaveId INT;
    DECLARE backendWaveId VARCHAR(200);
    DECLARE updatedBy VARCHAR(200);
    
    
    
        
        
    
 
    
    
    
    
    SET waveId = Parameters ->> '$.WaveId';
    SET waveType = Parameters ->> '$.WaveType';
    SET uploadWaveId = Parameters ->> '$.UploadedWaveId';
    SET updatedBy = Parameters ->> '$.UpdatedBy';
    
    
    SELECT WAVE_ID INTO backendWaveId 
    FROM `dashboard_wave_upload_status` 
    WHERE `ID` = uploadWaveId;
    
    
    INSERT INTO wave_master (`WAVE_ID`, `CLIENT_WAVE_ID`, `WAVE_TYPE`, `WAVE_STATUS`, `IS_ACTIVE`)
    SELECT 
        backendWaveId, 
        waveId,
        CASE 
            WHEN waveType = 'pick_wave' THEN 'PICK'
            WHEN waveType = 'put_wave' THEN 'PUT'
            WHEN waveType = 'stock_audit' THEN 'STOCK_AUDIT'
            ELSE waveType
        END AS waveType,
        'PENDING', 0;
    
    
    IF waveType = 'put_wave' THEN 
        
        INSERT IGNORE INTO `sku_batch_master` (
            
            SKU_ID, 
            BATCH_ID, 
            MRP, 
            EXPIRY_DATE
        )
        SELECT 
            
            A.SKU_ID, 
            UUID() AS BATCH_ID, 
            A.MRP, 
            A.EXPIRY_DATE
        FROM `put_wave_wms_data_dsb_upload_validation` AS A 
        WHERE A.`UPLOADED_WAVE_ID` = uploadWaveId;
        
        
        INSERT INTO `put_wave_wms_data` (`WAVE_ID`, `SKU_ID`, `BATCH_ID`, `QUANTITY`, `MRP`, `EXPIRY_DATE`)
        SELECT 
            backendWaveId, 
            A.`SKU_ID`, 
            B.`BATCH_ID`, 
            A.`QUANTITY`, 
            A.`MRP`, 
            A.`EXPIRY_DATE`
        FROM `put_wave_wms_data_dsb_upload_validation` AS A
        INNER JOIN `sku_batch_master` AS B 
            ON (B.`MRP` = A.MRP AND B.`EXPIRY_DATE` = A.`EXPIRY_DATE` AND B.`SKU_ID` = A.`SKU_ID`)
        WHERE A.`UPLOADED_WAVE_ID` = uploadWaveId;
    ELSEIF waveType = 'pick_wave' THEN 
        
        INSERT INTO `pick_wave_wms_data` (`WAVE_ID`, `ORDER_ID`, `SKU_ID`, `BATCH_ID`, `QUANTITY`, `MRP`, `EXPIRY_DATE`, `PRIORITY`)
        SELECT 
            backendWaveId, 
            A.`ORDER_ID`, 
            A.`SKU_ID`, 
            B.`BATCH_ID`, 
            A.`QUANTITY`, 
            A.`MRP`, 
            A.`EXPIRY_DATE`, 
            A.`PRIORITY`
        FROM `pick_wave_wms_data_dsb_upload_validation` AS A
        INNER JOIN `sku_batch_master` AS B 
            ON (B.`MRP` = A.MRP AND B.`EXPIRY_DATE` = A.`EXPIRY_DATE` AND B.`SKU_ID` = A.`SKU_ID`)
        WHERE A.`UPLOADED_WAVE_ID` = uploadWaveId;
    ELSEIF waveType = 'stock_audit' THEN
        
        INSERT INTO `stock_audit_wave_wms_data` (`WAVE_ID`, `BIN_ID`, `BIN_SEGMENT_NO`, `SKU_ID`, `BATCH_ID`)
        SELECT 
            backendWaveId, 
            `BIN_ID`, 
            `SEGMENT_NO`, 
            `ARTICLE_ID`, 
            `BATCH_ID`
        FROM (
            SELECT 
                l.`BIN_ID`, 
                l.`SEGMENT_NO`, 
                l.`ARTICLE_ID`, 
                l.`BATCH_ID`
            FROM `stock_audit_wave_wms_data_dsb_upload_validation` AS `s`
            INNER JOIN `live_inventory_master` AS `l`
                ON `s`.`BIN_ID` = `l`.`BIN_ID`
            WHERE (`s`.`SKU_ID` IS NULL) AND (`s`.`BIN_SEGMENT_NO` IS NULL) AND s.UPLOADED_WAVE_ID = uploadWaveId
            
            UNION
            
            SELECT 
                l.`BIN_ID`, 
                l.`SEGMENT_NO`, 
                l.`ARTICLE_ID`, 
                l.`BATCH_ID`
            FROM `stock_audit_wave_wms_data_dsb_upload_validation` AS `s`
            INNER JOIN `live_inventory_master` AS `l`
                ON `s`.`SKU_ID` = `l`.`ARTICLE_ID`
            WHERE (`s`.`BIN_ID` IS NULL) AND s.UPLOADED_WAVE_ID = uploadWaveId
            
            UNION
            
            SELECT 
                l.`BIN_ID`, 
                l.`SEGMENT_NO`, 
                l.`ARTICLE_ID`, 
                l.`BATCH_ID`
            FROM `stock_audit_wave_wms_data_dsb_upload_validation` AS `s`
            INNER JOIN `live_inventory_master` AS `l`
                ON `s`.`BIN_ID` = `l`.`BIN_ID` AND s.`BIN_SEGMENT_NO` = l.`SEGMENT_NO`
            WHERE (`s`.`SKU_ID` IS NULL) AND s.UPLOADED_WAVE_ID = uploadWaveId
        ) AS combined_data;
    END IF;
    
    
    UPDATE wave_master 
    SET `WAVE_STATUS` = 'PENDING', IS_ACTIVE = 1,
    INSERTED_TIMESTAMP = NOW(), `INSERTED_BY` = updatedBy, `UPDATED_BY` = updatedBy
    WHERE `WAVE_ID` = backendWaveId;
    
    
    UPDATE dashboard_wave_upload_status 
    SET `STATUS` = 'Uploaded Successfully', IS_ACTIVE = 1
    WHERE `ID` = uploadWaveId;
    
    DELETE FROM `stock_audit_wave_wms_data_dsb_upload_validation` WHERE `UPLOADED_WAVE_ID` = uploadWaveId;
    DELETE FROM `pick_wave_wms_data_dsb_upload_validation` WHERE `UPLOADED_WAVE_ID` = uploadWaveId;
    DELETE FROM `put_wave_wms_data_dsb_upload_validation` WHERE `UPLOADED_WAVE_ID` = uploadWaveId;
    
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_DATA_LOAD_AND_VALIDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_DATA_LOAD_AND_VALIDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_DATA_LOAD_AND_VALIDATE`(IN Parameters JSON)
BEGIN
	
	DECLARE _validationFailed INT;
	
	DECLARE waveId VARCHAR(50);
	DECLARE waveType VARCHAR(50);
	DECLARE waveUniqueId INT;
	DECLARE tableName VARCHAR(20);
	DECLARE sqlQuery VARCHAR(1000);
	
	SET waveId = Parameters ->> '$.WaveName';
	SET waveType = Parameters ->> '$.WaveType';
	SET _validationFailed = 0;
	
	
	
	IF waveType ='ARTICLE_MASTER' then
		
		 call DSB_ARTICLE_WAVE_DATA_LOAD_AND_VALIDATE(Parameters);
		
	ELSE
	
	
		DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
		CREATE TEMPORARY TABLE tmp_invalidRowinWaveData(ID INT, _message VARCHAR(2000)); 
		
		SELECT ID INTO waveUniqueId FROM `dashboard_wave_upload_status` WHERE `WAVE_ID` = waveId;
		
		IF waveType = 'PUT' THEN 
			
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT ID, 'Wave id cannot be null'
				FROM put_wave_wms_data_validation C  
				WHERE C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`WAVE_ID` IS NULL OR C.`WAVE_ID` = '');
			END IF;
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT ID, 'SKU ID cannot be null'
				FROM put_wave_wms_data_validation C  
				WHERE C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`SKU_ID` IS NULL OR C.`SKU_ID` = '');
			END IF;
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT ID, 'Batch No cannot be null'
				FROM put_wave_wms_data_validation C  
				WHERE C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`BATCH_NO` IS NULL OR C.`BATCH_NO` = '');
			END IF;
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT ID, 'MRP cannot be null'
				FROM put_wave_wms_data_validation C  
				WHERE C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`MRP` IS NULL);
			END IF;
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT ID, 'Expiry date cannot be null'
				FROM put_wave_wms_data_validation C  
				WHERE C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`EXPIRY_DATE` IS NULL );
			END IF;
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT ID, 'Quantity cannot be null'
				FROM put_wave_wms_data_validation C  
				WHERE C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`QUANTITY` IS NULL OR C.`QUANTITY` = 0);
			END IF;
			
			
			
			IF EXISTS (SELECT ID FROM tmp_invalidRowinWaveData) THEN
				SET _validationFailed = 1;
				UPDATE `put_wave_wms_data_validation` C 
				INNER JOIN (
				    SELECT ID, GROUP_CONCAT(_message) AS _message
				    FROM tmp_invalidRowinWaveData
				    GROUP BY ID
				) T ON T.ID = C.ID
				SET C.`VALIDATION_MESSAGE` = T._message;
			END IF;
			
		ELSEIF waveType = 'PICK' THEN 
			
			IF _validationFailed =0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message) 
				SELECT ID,'Wave id cannot be null' 
				FROM pick_wave_wms_data_validation C
				WHERE  C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`WAVE_ID` IS NULL OR C.`WAVE_ID`='');
			END IF;
			IF _validationFailed =0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message) 
				SELECT ID,'Wave id is not same as other fields' 
				FROM pick_wave_wms_data_validation C
				WHERE  C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`WAVE_ID` <> waveId);
			END IF;
			
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT C.ID, 'Article id cannot be null'
				FROM pick_wave_wms_data_validation C  
				WHERE  C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`SKU_ID` IS NULL OR C.`SKU_ID` = '');
			END IF;
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT C.ID, 'Batch No cannot be null'
				FROM pick_wave_wms_data_validation C  
				WHERE  C.`UPLOADED_WAVE_ID` = waveUniqueId AND (C.`BATCH_NO` IS NULL OR C.`BATCH_NO` = '');
			END IF;
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT ID, 'Quantity cannot be null'
				FROM pick_wave_wms_data_validation C  
				WHERE  C.`UPLOADED_WAVE_ID` = waveUniqueId  AND (C.`QUANTITY` IS NULL OR C.`QUANTITY` = 0);
			END IF;
			IF _validationFailed = 0 THEN
				INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				SELECT ID, 'Priority cannot be null'
				FROM pick_wave_wms_data_validation C  
				WHERE  C.`UPLOADED_WAVE_ID` = waveUniqueId  AND (C.`PRIORITY` IS NULL OR C.`PRIORITY` = 0);
			END IF;
			IF _validationFailed = 0 THEN
				    INSERT INTO tmp_invalidRowinWaveData(ID, _message)
				    SELECT DISTINCT o1.ID, 'Order has same SKU ID and Batch Number'
				    FROM pick_wave_wms_data_validation AS o1
				    JOIN pick_wave_wms_data_validation AS o2
				      ON (o1.ORDER_ID = o2.ORDER_ID AND o1.UPLOADED_WAVE_ID = o2.UPLOADED_WAVE_ID )
				      AND o1.SKU_ID = o2.SKU_ID AND o1.`BATCH_NO`=o2.`BATCH_NO`
				      AND o1.ID <> o2.ID
				    WHERE  o1.`UPLOADED_WAVE_ID` = waveUniqueId ;
			END IF;
			
			
			IF EXISTS (SELECT ID FROM tmp_invalidRowinWaveData) THEN
				SET _validationFailed = 1;
				UPDATE `pick_wave_wms_data_validation` C 
				INNER JOIN (
				    SELECT ID, GROUP_CONCAT(_message) AS _message
				    FROM tmp_invalidRowinWaveData
				    GROUP BY ID
				) T ON T.ID = C.ID
				SET C.`VALIDATION_MESSAGE` = T._message;
			END IF;
		END IF;	
		
		 DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
			IF _validationFailed = 1 THEN
			UPDATE `dashboard_wave_upload_status` SET `STATUS` = 'Failed' WHERE wave_id = waveId;
			 
			ELSE
			UPDATE `dashboard_wave_upload_status` SET `STATUS` = 'Insertion In Progress' WHERE wave_id = waveId;
			CALL DSB_WAVE_DATA_INSERT_CONFIG_INTO_TABLES(Parameters);
			END IF;
		END IF;
		SELECT STATUS FROM `dashboard_wave_upload_status` WHERE wave_id = waveId;
		 
	
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_DATA_VALIDATION_FAIL_DATA` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_DATA_VALIDATION_FAIL_DATA` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_DATA_VALIDATION_FAIL_DATA`(in Parameters varchar(50))
BEGIN
	declare waveType varchar(50);
	DEclare IDnumber int;
	
	SELECT `WAVE_TYPE`, `ID` INTO waveType, IDnumber 
	FROM `dashboard_wave_upload_status` 
	WHERE `WAVE_ID` = Parameters;
	IF waveType = 'PUT' THEN 
		SELECT row_num +1 AS 'ROW_NUMBER', VALIDATION_MESSAGE FROM(
		SELECT ID AS modified_ID,
		`VALIDATION_MESSAGE`,
		ROW_NUMBER() OVER (PARTITION BY uploaded_wave_id ORDER BY id ASC) AS ROW_NUM
		FROM `put_wave_wms_data_validation` 
		WHERE  `UPLOADED_WAVE_ID` = IDnumber
		)TT WHERE validation_message IS NOT NULL;
	ELSEIF waveType = 'PICK' THEN 
	SELECT row_num +1  AS 'ROW_NUMBER', VALIDATION_MESSAGE FROM(
		SELECT ID AS modified_ID,
		`VALIDATION_MESSAGE`,
		ROW_NUMBER() OVER (PARTITION BY uploaded_wave_id ORDER BY id ASC) AS ROW_NUM
		FROM `pick_wave_wms_data_validation` 
		WHERE  `UPLOADED_WAVE_ID` = IDnumber
		)TT WHERE validation_message IS NOT NULL;
		
	ELSEIF waveType = 'ARTICLE_MASTER' THEN 
		SELECT row_num +1  AS 'ROW_NUMBER', VALIDATION_MESSAGE FROM(
		SELECT ID AS modified_ID,
		`VALIDATION_MESSAGE`,
		ROW_NUMBER() OVER (PARTITION BY uploaded_wave_id ORDER BY id ASC) AS ROW_NUM
		FROM `article_master_validation` 
		WHERE  `UPLOADED_WAVE_ID` = IDnumber
		)TT WHERE validation_message IS NOT NULL;
	END IF;
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_PREPARE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_PREPARE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_PREPARE`(
    IN Parameters JSON
)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE total INT;

    DECLARE p_station_id INT;
    DECLARE p_wave_id VARCHAR(50);
    DECLARE p_wave_type VARCHAR(50);
    DECLARE p_pick_rule_id_current INT;
    DECLARE p_bot_count_current INT;
    DECLARE raw_pick_rule_id VARCHAR(100);
    DECLARE p_user_name VARCHAR(50);

    
    DECLARE v_pick_rule_id_default INT;
    DECLARE v_default_filter TEXT;
    DECLARE v_current_filter TEXT;
    DECLARE v_new_filter TEXT;
    DECLARE v_new_pick_rule_id INT;

    
    DECLARE v_err_sqlstate CHAR(5) DEFAULT NULL;
    DECLARE v_err_code INT DEFAULT NULL;
    DECLARE v_err_msg TEXT DEFAULT NULL;

    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_err_sqlstate = RETURNED_SQLSTATE,
            v_err_code     = MYSQL_ERRNO,
            v_err_msg      = MESSAGE_TEXT;

        ROLLBACK;

        
        SELECT
            0 AS Success,
            CONCAT(
                'SQLSTATE=', COALESCE(v_err_sqlstate,'NULL'),
                ', ERRNO=', COALESCE(v_err_code,'NULL'),
                ', MSG=', COALESCE(v_err_msg,'NULL'),
                ', i=', i,
                ', station_id=', COALESCE(p_station_id,'NULL'),
                ', wave_id=', COALESCE(p_wave_id,'NULL'),
                ', wave_type=', COALESCE(p_wave_type,'NULL')
            ) AS Result;
    END;

    START TRANSACTION;

    SET total = COALESCE(JSON_LENGTH(Parameters), 0);

    IF total = 0 THEN
        ROLLBACK;
        SELECT 0 AS Success, 'No items to process' AS Result;
    ELSE
        WHILE i < total DO

            SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].station_id'))) AS UNSIGNED);
            SET p_wave_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].wave_id')));
            SET p_wave_type = UPPER(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].wave_type'))));
            SET p_bot_count_current = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].bot_count_current'))) AS UNSIGNED);
            SET raw_pick_rule_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].pick_rule_id_current')));
            SET p_user_name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].user_name')));

            IF raw_pick_rule_id IS NULL OR raw_pick_rule_id = 'null' THEN
                SET p_pick_rule_id_current = NULL;
            ELSE
                SET p_pick_rule_id_current = CAST(raw_pick_rule_id AS UNSIGNED);
            END IF;

            
            IF i = 0 THEN
                IF p_wave_type = 'STOCK_AUDIT' THEN
                    INSERT INTO wave_master
                        (WAVE_ID, CLIENT_WAVE_ID, WAVE_TYPE, WAVE_STATUS, IS_ACTIVE, INSERTED_BY, UPDATED_BY)
                    VALUES
                        (p_wave_id, p_wave_id, p_wave_type, 'STATION_SELECTED', 1, p_user_name, p_user_name);

                    INSERT INTO stock_audit_wave_wms_data
                        (WAVE_ID, BIN_ID, BIN_SEGMENT_NO, SKU_ID, BATCH_ID, LEFT_OVER)
                    SELECT
                        WAVE_ID, BIN_ID, BIN_SEGMENT_NO, SKU_ID, BATCH_ID, 0
                    FROM stock_audit_wave_wms_data_dsb_temp
                    WHERE WAVE_ID = p_wave_id;

                    UPDATE dashboard_wave_upload_status
                    SET STATUS = 'Upload Successfully'
                    WHERE WAVE_ID = p_wave_id;

                    DELETE FROM stock_audit_wave_wms_data_dsb_temp
                    WHERE WAVE_ID = p_wave_id;
                END IF;

                IF p_wave_type = 'PICK' THEN
                    INSERT INTO picklist_split_order_master
                        (RULE_ID, IS_PROCESSED, PRIORITY, INSERTED_BY, INSERTED_TIMESTAMP)
                    VALUES
                        (p_pick_rule_id_current, "0", "FINAL", p_user_name, NOW());
                END IF;
            END IF;

            
            IF EXISTS (
                SELECT 1
                FROM hw_station_master
                WHERE STATION_ID = p_station_id
                  AND WAVE_ID IS NULL
            ) THEN

                IF p_wave_type <> 'STOCK_AUDIT' THEN
                    
                    INSERT INTO wave_master
                        (WAVE_ID, CLIENT_WAVE_ID, WAVE_TYPE, WAVE_STATUS, IS_ACTIVE, INSERTED_BY, UPDATED_BY)
                    VALUES
                        (p_wave_id, p_wave_id, p_wave_type, 'STATION_SELECTED', 1, p_user_name, p_user_name);
                END IF;

                IF p_wave_type = 'PICK' THEN
                    INSERT INTO picklist_split_station_pref
                        (RULE_ID, STATION_ID, IS_PROCESSED, PRIORITY, INSERTED_BY, INSERTED_TIMESTAMP)
                    VALUES
                        (p_pick_rule_id_current, p_station_id, "0", "FINAL", p_user_name, NOW());
                END IF;

                UPDATE hw_station_master
                SET WAVE_ID = p_wave_id,
                    WAVE_STATUS = 'WAITING_OPERATOR'
                WHERE STATION_ID = p_station_id;

                
                IF p_wave_type = 'PICK' AND p_pick_rule_id_current IS NOT NULL THEN

                    SET v_pick_rule_id_default = (
                        SELECT PICK_RULE_ID_DEFAULT
                        FROM wave_station_rule_mapping
                        WHERE STATION_ID = p_station_id
                        LIMIT 1
                    );

                    SET v_default_filter = NULL;
                    SET v_current_filter = NULL;

                    IF v_pick_rule_id_default IS NOT NULL THEN
                        SET v_default_filter = (
                            SELECT FILTER_CONDITION
                            FROM pick_rule_master
                            WHERE PICK_RULE_ID = v_pick_rule_id_default
                            LIMIT 1
                        );
                    END IF;

                    SET v_current_filter = (
                        SELECT FILTER_CONDITION
                        FROM pick_rule_master
                        WHERE PICK_RULE_ID = p_pick_rule_id_current
                        LIMIT 1
                    );

                    IF v_default_filter IS NOT NULL THEN
                        SET v_default_filter = TRIM(TRAILING ';' FROM TRIM(v_default_filter));
                    END IF;

                    IF v_current_filter IS NOT NULL THEN
                        SET v_current_filter = TRIM(TRAILING ';' FROM TRIM(v_current_filter));
                    END IF;

                    IF v_default_filter IS NULL OR TRIM(v_default_filter) = '' THEN
                        SET v_new_filter = v_current_filter;
                    ELSEIF v_current_filter IS NULL OR TRIM(v_current_filter) = '' THEN
                        SET v_new_filter = v_default_filter;
                    ELSE
                        SET v_new_filter = CONCAT(
                            v_default_filter,
                            ' AND parent_order_id IN (',
                            v_current_filter,
                            ')'
                        );
                    END IF;

                    IF v_new_filter IS NULL OR TRIM(v_new_filter) = '' THEN
                        SIGNAL SQLSTATE '45000'
                            SET MESSAGE_TEXT = 'Merged PICK rule query is empty (check pick_rule_master.FILTER_CONDITION)';
                    END IF;

                    INSERT INTO pick_rule_master
                        (RULE_NAME, FILTER_CONDITION, DSB_FILTER_CONDITION, INSERTED_BY, INSERTED_TIMESTAMP)
                    VALUES
                        (UUID(),v_new_filter, v_new_filter, p_user_name, NOW());

                    SET v_new_pick_rule_id = LAST_INSERT_ID();

                    UPDATE wave_station_rule_mapping
                    SET BOT_COUNT_CURRENT = p_bot_count_current,
                        PICK_RULE_ID_CURRENT = v_new_pick_rule_id
                    WHERE STATION_ID = p_station_id;

                ELSE
                    UPDATE wave_station_rule_mapping
                    SET BOT_COUNT_CURRENT = p_bot_count_current
                    WHERE STATION_ID = p_station_id;
                END IF;

                INSERT INTO dashboard_log_wave_process
                    (WAVE_ID, WAVE_TYPE, WAVE_STATUS, CREATED_BY, STATION_ID)
                VALUES
                    (p_wave_id, p_wave_type, 'STATION_SELECTED', p_user_name, p_station_id);

            ELSE
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'Station ID not found or Wave already exists';
            END IF;

            SET i = i + 1;

        END WHILE;

        COMMIT;
        SELECT 1 AS Success, 'Wave Created Successfully' AS Result;
    END IF;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_RUN` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_RUN` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_RUN`(IN Parameters JSON)
BEGIN
    
    DECLARE p_wave_id     VARCHAR(100);
    DECLARE p_station_id  INT;
    DECLARE p_user_name   VARCHAR(100);
    
    DECLARE v_wave_type   VARCHAR(50);
    DECLARE v_wave_status VARCHAR(200);
    
    DECLARE Success INT DEFAULT 1;
    DECLARE Result  VARCHAR(255) DEFAULT '';
    
    DECLARE err_msg TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 err_msg = MESSAGE_TEXT;
        SELECT 0 AS Success, CONCAT('SQL Error: ', err_msg) AS Result;
    END;
    
    SET p_wave_id     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_station_id  = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
    SET p_user_name   = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    
    START TRANSACTION;
    
    IF EXISTS (
        SELECT 1 
        FROM wave_master 
        WHERE WAVE_ID = p_wave_id
    ) THEN
        
        SELECT WAVE_TYPE, WAVE_STATUS 
        INTO v_wave_type, v_wave_status
        FROM wave_master
        WHERE WAVE_ID = p_wave_id;
        
        IF v_wave_status IN ('STATION_SELECTED', 'PROCESSING') THEN
            
            UPDATE wave_master
            SET START_TIMESTAMP = NOW(), STARTED_BY = p_user_name
            WHERE WAVE_ID = p_wave_id;
            IF ROW_COUNT() > 0 THEN
                
                UPDATE hw_station_master
                SET 
                    WAVE_STATUS = 'WAVE_LIVE',
                    LOGGED_IN_USER_ID = p_user_name
                WHERE STATION_ID = p_station_id;
                
			IF(v_wave_type <> 'STOCK_AUDIT') THEN
				
				UPDATE dashboard_log_wave_process
				SET RUN_BY = p_user_name,
				    RUN_TIMESTAMP = NOW()
				WHERE WAVE_ID = p_wave_id AND STATION_ID = p_station_id;
				IF ROW_COUNT() > 0 THEN
				    SET Success = 1;
				    SET Result  = CONCAT(v_wave_type, ' Wave Started Successfully');
				ELSE
				    SET Success = 0;
				    SET Result  = 'Failed to update wave log table';
				    ROLLBACK;
				    SELECT Success, Result;
				END IF;
			END IF;
            ELSE
                SET Success = 0;
                SET Result  = 'Failed to update wave start time';
                ROLLBACK;
                SELECT Success, Result;
            END IF;
        ELSE
            SET Success = 0;
            SET Result  = 'Wave status is not PROCESSING or STATION_SELECTED';
            ROLLBACK;
            SELECT Success, Result;
        END IF;
    ELSE
        SET Success = 0;
        SET Result  = 'Wave ID does not exist';
        ROLLBACK;
        SELECT Success, Result;
    END IF;
    
    COMMIT;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_STATION_RULE_MAPPING_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_STATION_RULE_MAPPING_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_STATION_RULE_MAPPING_GET_ALL`()
BEGIN
    SELECT 
        wsrm.IS_ACTIVE,
        wsrm.WAVE_STATION_RULE_MAPPING_ID,
        wsrm.STATION_ID,
        hsm.STATION_ALIAS_NAME,
        wsrm.PICK_RULE_ID_DEFAULT,
        prm_d.RULE_NAME AS PICK_RULE_NAME_DEFAULT,
        prm_d.DSB_FILTER_CONDITION AS PICK_RULE_FILTER_CONDITION_DEFAULT,
        wsrm.PICK_RULE_ID_CURRENT,
        prm_c.RULE_NAME AS PICK_RULE_NAME_CURRENT,
        prm_c.DSB_FILTER_CONDITION AS PICK_RULE_FILTER_CONDITION_CURRENT,
        wsrm.BOT_COUNT_DEFAULT,
        wsrm.BOT_COUNT_CURRENT, 
        wsrm.INSERTED_TIMESTAMP, 
        wsrm.INSERTED_BY, 
        wsrm.UPDATED_TIMESTAMP, 
        wsrm.UPDATED_BY 
    FROM wave_station_rule_mapping wsrm
    LEFT JOIN hw_station_master hsm
	ON wsrm.STATION_ID = hsm.STATION_ID
    LEFT JOIN pick_rule_master prm_d 
        ON wsrm.PICK_RULE_ID_DEFAULT = prm_d.PICK_RULE_ID
    LEFT JOIN pick_rule_master prm_c 
        ON wsrm.PICK_RULE_ID_CURRENT = prm_c.PICK_RULE_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_STATION_RULE_MAPPING_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_STATION_RULE_MAPPING_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_STATION_RULE_MAPPING_INSERT`(
    IN Parameters JSON
)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE total INT;
    DECLARE p_wave_station_rule_mapping_id INT;
    DECLARE p_station_id INT;
    DECLARE p_pick_rule_id_default INT;
    DECLARE p_pick_rule_id_current INT;
    DECLARE p_bot_count_default INT;
    DECLARE p_bot_count_current INT;
    DECLARE p_is_active INT;
    DECLARE p_user_name VARCHAR(100);
    DECLARE insertErrors TEXT DEFAULT '';
    DECLARE rowSuccess INT DEFAULT 1;
    DECLARE err_msg TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 err_msg = MESSAGE_TEXT;
        SELECT 0 AS Success, CONCAT('SQL Error: ', err_msg) AS Result;
    END;
    START TRANSACTION;
    SET total = JSON_LENGTH(Parameters);
    WHILE i < total DO
        
        SET p_wave_station_rule_mapping_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].wave_station_rule_mapping_id'))) AS UNSIGNED);      
        SET p_station_id                   = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].station_id'))) AS UNSIGNED); 
        SET p_pick_rule_id_default         = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].pick_rule_id_default'))) AS UNSIGNED);       
        SET p_pick_rule_id_current         = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].pick_rule_id_current'))) AS UNSIGNED);        
        SET p_bot_count_default            = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].bot_count_default'))) AS UNSIGNED);       
        SET p_bot_count_current            = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].bot_count_current'))) AS UNSIGNED);      
        SET p_is_active                    = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].is_active'))) AS UNSIGNED);      
        SET p_user_name                   = JSON_UNQUOTE(JSON_EXTRACT(Parameters, CONCAT('$[', i, '].user_name')));
        
        IF EXISTS (
            SELECT 1 FROM wave_station_rule_mapping WHERE WAVE_STATION_RULE_MAPPING_ID = p_wave_station_rule_mapping_id
        ) THEN
            UPDATE wave_station_rule_mapping
            SET 
                PICK_RULE_ID_DEFAULT = p_pick_rule_id_default,
                PICK_RULE_ID_CURRENT = p_pick_rule_id_current,
                BOT_COUNT_DEFAULT    = p_bot_count_default,
                BOT_COUNT_CURRENT    = p_bot_count_current,
                IS_ACTIVE            = p_is_active,
                UPDATED_BY           = p_user_name
            WHERE WAVE_STATION_RULE_MAPPING_ID = p_wave_station_rule_mapping_id;
        ELSE
            
            IF EXISTS (
                SELECT 1 FROM wave_station_rule_mapping WHERE STATION_ID = p_station_id
            ) THEN
                SET rowSuccess = 0;
                SET insertErrors = CONCAT(insertErrors, 'Mapping already exists for station_id ', p_station_id, '. ');
            ELSE
                INSERT INTO wave_station_rule_mapping (
                    STATION_ID,
                    PICK_RULE_ID_DEFAULT,
                    PICK_RULE_ID_CURRENT,
                    BOT_COUNT_DEFAULT,
                    BOT_COUNT_CURRENT,
                    IS_ACTIVE,
                    INSERTED_BY,
                    INSERTED_TIMESTAMP,
                    UPDATED_BY
                ) VALUES (
                    p_station_id,
                    p_pick_rule_id_default,
                    p_pick_rule_id_current,
                    p_bot_count_default,
                    p_bot_count_current,
                    p_is_active,
                    p_user_name,
                    NOW(),
                    p_user_name
                );
            END IF;
        END IF;
        SET i = i + 1;
    END WHILE;
    COMMIT;
    
    IF rowSuccess = 1 THEN
        SELECT 1 AS Success, 'Mapping Done Successfully' AS Result;
    ELSE
        SELECT 0 AS Success, 'Error(s) occurred' AS Result, insertErrors AS ErrorList;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_STOP` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_STOP` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_STOP`(IN Parameters JSON)
BEGIN
    
    CREATE TEMPORARY TABLE IF NOT EXISTS TempStationWaves (
        station_id INT,
        wave_id VARCHAR(200)
    );
    
    INSERT INTO TempStationWaves (station_id, wave_id)
    SELECT 
        station_id, 
        wave_id
    FROM JSON_TABLE(
        Parameters, 
        '$[*]' COLUMNS (
            station_id INT PATH '$.station_id',
            wave_id    VARCHAR(200) PATH '$.wave_id'
        )
    ) AS jt;
    
    UPDATE wave_master wm
    JOIN TempStationWaves ts ON wm.WAVE_ID = ts.wave_id
    SET wm.IS_STOPPED = 1;
    
    DROP TEMPORARY TABLE IF EXISTS TempStationWaves;
    
    SELECT 1 AS Success, 'Wave Stopped Successfully!' AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_SUSPEND` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_SUSPEND` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_SUSPEND`(IN Parameters JSON)
BEGIN
    
    DECLARE err_msg TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 err_msg = MESSAGE_TEXT;
        SELECT 0 AS Success, CONCAT('SQL Error: ', err_msg) AS Result;
    END;
    
    START TRANSACTION;
    
    CREATE TEMPORARY TABLE IF NOT EXISTS TempStationWaves (
        station_id INT,
        wave_id VARCHAR(100),
        user_name VARCHAR(50)
    );
    
    INSERT INTO TempStationWaves (station_id, wave_id, user_name)
    SELECT 
        station_id, 
        wave_id,
        user_name
    FROM JSON_TABLE(
        Parameters, 
        '$[*]' COLUMNS (
            station_id INT PATH '$.station_id',
            wave_id    VARCHAR(50) PATH '$.wave_id',
            user_name  VARCHAR(50) PATH '$.user_name'
        )
    ) AS jt;
    
    UPDATE wave_master wm
    JOIN TempStationWaves ts ON wm.WAVE_ID = ts.wave_id
    SET wm.IS_CANCELLED = 1, wm.CANCELLED_TIMESTAMP = NOW(), wm.CANCELLED_BY = ts.user_name;
    
    UPDATE dashboard_log_wave_process dlog
    JOIN TempStationWaves ts ON dlog.WAVE_ID = ts.wave_id AND dlog.STATION_ID = ts.station_id
    SET dlog.CANCELLED_BY = ts.user_name,
        dlog.CANCELLED_TIMESTAMP = NOW();
    
    DROP TEMPORARY TABLE IF EXISTS TempStationWaves;
    
    COMMIT;
    
    SELECT 1 AS Success, 'Wave(s) marked as cancelled successfully.' AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WAVE_UPLOAD_DATA_UPLOAD_STATUS_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WAVE_UPLOAD_DATA_UPLOAD_STATUS_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WAVE_UPLOAD_DATA_UPLOAD_STATUS_GET`(IN Parameters VARCHAR(50))
BEGIN
    IF EXISTS (SELECT * FROM `dashboard_wave_upload_status` WHERE `WAVE_ID` = Parameters) THEN 
        SELECT 'Validation Pending' AS STATUS 
        FROM `dashboard_wave_upload_status` 
        WHERE `WAVE_ID` = Parameters;
    ELSE 
        SELECT STATUS 
        FROM `dashboard_wave_upload_status` 
        WHERE `WAVE_ID` = Parameters;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_WEB_SOCKET_GET_NAME_WITH_TIMER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_WEB_SOCKET_GET_NAME_WITH_TIMER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_WEB_SOCKET_GET_NAME_WITH_TIMER`()
BEGIN
	SELECT `FUNCTION_NAME`,`TIMER`,IS_GLOBAL FROM `dashboard_ws_function_timer_master` WHERE
	`IS_ACTIVE`=1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_BIN_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_BIN_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_BIN_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    CombinedWave AS (
        SELECT ORDER_BIN_ID
        FROM pick_wave_order_master
        WHERE STATUS <> 'PENDING'
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        
        UNION ALL
        
        SELECT ORDER_BIN_ID
        FROM pick_wave_order_master_archive
        WHERE STATUS <> 'PENDING'
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        
        UNION ALL
        
        SELECT ORDER_BIN_ID
        FROM put_wave_order_master_archive
        WHERE STATUS <> 'PENDING'
          AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        
        UNION ALL
        
        SELECT ORDER_BIN_ID
        FROM put_wave_order_master
        WHERE STATUS <> 'PENDING'
          AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ),
    BaseResults AS (
        SELECT
            ORDER_BIN_ID,
            BIN_ID,
            STATION_ID,
            MAX(CASE WHEN STATUS = 'BIN_PICKED'     THEN BOT_ID            END) AS TASK_ALLOCATED_BOT_ID,
            MAX(CASE WHEN STATUS = 'PRE_ON_STATION' THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
            MAX(CASE WHEN STATUS = 'ON_STATION'     THEN UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
        FROM order_bin_mapping_log
        WHERE TYPE = 'RACK_PICK'
          AND ORDER_BIN_ID IN (SELECT ORDER_BIN_ID FROM CombinedWave)
        GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID
    ),
    Sequenced AS (
        SELECT
            STATION_ID,
            ORDER_BIN_ID,
            ON_STATION_TIMESTAMP,
            LEAD(ON_STATION_TIMESTAMP)
                OVER (PARTITION BY STATION_ID ORDER BY ON_STATION_TIMESTAMP) AS next_on_station_ts
        FROM BaseResults
        WHERE ON_STATION_TIMESTAMP IS NOT NULL
    ),
    WithDiff AS (
        SELECT
            STATION_ID,
            ORDER_BIN_ID,
            ON_STATION_TIMESTAMP,
            GREATEST(
                0,
                LEAST(600, TIMESTAMPDIFF(SECOND, ON_STATION_TIMESTAMP, next_on_station_ts))
            ) AS filtered_time_diff_seconds
        FROM Sequenced
    ),
    PerHour AS (
        SELECT
            STATION_ID,
            DATE_FORMAT(ON_STATION_TIMESTAMP, '%Y-%m-%d %H:00:00') AS hour_slot,
            SUM(filtered_time_diff_seconds) AS active_seconds_in_hour
        FROM WithDiff
        GROUP BY STATION_ID, hour_slot
    ),
    StationHourAgg AS (
        SELECT
            STATION_ID,
            COUNT(*) AS active_hours,
            SUM(LEAST(active_seconds_in_hour, 3600)) AS total_active_seconds
        FROM PerHour
        GROUP BY STATION_ID
    )
    
    SELECT
        wd.STATION_ID,

        
        

        COUNT(DISTINCT wd.ORDER_BIN_ID) AS BINS,

        
        ROUND(
            (sha.total_active_seconds / 60.0) / NULLIF(sha.active_hours, 0), 
            2
        ) AS AVG_ACTIVE_MIN_PER_HOUR,

        
        ROUND(
            sha.total_active_seconds / 3600.0,
            2
        ) AS ACTIVE_HOURS,

        
        ROUND(
            COUNT(DISTINCT wd.ORDER_BIN_ID) / NULLIF(sha.total_active_seconds / 3600.0, 0),
            2
        ) AS BINS_PER_HOUR

    FROM WithDiff wd
    JOIN StationHourAgg SHA
      ON sha.STATION_ID = wd.STATION_ID

    GROUP BY
        wd.STATION_ID,
        sha.total_active_seconds,
        sha.active_hours

    ORDER BY wd.STATION_ID;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_BIN_PER_HOUR_PER_STATION_1` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_BIN_PER_HOUR_PER_STATION_1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_BIN_PER_HOUR_PER_STATION_1`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    CombinedWave AS (
        SELECT ORDER_BIN_ID
        FROM pick_wave_order_master
        WHERE STATUS <> 'PENDING'
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
 
        UNION ALL
 
        SELECT ORDER_BIN_ID
        FROM pick_wave_order_master_archive
        WHERE STATUS <> 'PENDING'
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
 
        UNION ALL
 
        SELECT ORDER_BIN_ID
        FROM put_wave_order_master_archive
        WHERE STATUS <> 'PENDING'
          AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
 
        UNION ALL
 
        SELECT ORDER_BIN_ID
        FROM put_wave_order_master
        WHERE STATUS <> 'PENDING'
          AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ),
    BaseResults AS (
        
        SELECT
            ORDER_BIN_ID,
            BIN_ID,
            STATION_ID,
            MAX(CASE WHEN STATUS = 'BIN_PICKED'     THEN BOT_ID            END) AS TASK_ALLOCATED_BOT_ID,
            MAX(CASE WHEN STATUS = 'PRE_ON_STATION' THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
            MAX(CASE WHEN STATUS = 'ON_STATION'     THEN UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
        FROM order_bin_mapping_log
        WHERE TYPE = 'RACK_PICK'
          AND ORDER_BIN_ID IN (SELECT DISTINCT ORDER_BIN_ID FROM CombinedWave)
        GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID
    ),
    Sequenced AS (
        
        SELECT
            STATION_ID,
            ORDER_BIN_ID,
            ON_STATION_TIMESTAMP,
            LEAD(ON_STATION_TIMESTAMP)
                OVER (PARTITION BY STATION_ID ORDER BY ON_STATION_TIMESTAMP) AS next_on_station_ts
        FROM BaseResults
        WHERE ON_STATION_TIMESTAMP IS NOT NULL
    ),
    WithDiff AS (
        
        SELECT
            STATION_ID,
            ORDER_BIN_ID,
            ON_STATION_TIMESTAMP,
            GREATEST(
                0,
                LEAST(600, TIMESTAMPDIFF(SECOND, ON_STATION_TIMESTAMP, next_on_station_ts))
            ) AS filtered_time_diff_seconds
        FROM Sequenced
    ),
    PerHour AS (
        
        SELECT
            STATION_ID,
            DATE_FORMAT(ON_STATION_TIMESTAMP, '%Y-%m-%d %H:00:00') AS hour_slot,
            SUM(filtered_time_diff_seconds) AS active_seconds_in_hour
        FROM WithDiff
        GROUP BY STATION_ID, hour_slot
    ),
    StationHourAgg AS (
        
        SELECT
            STATION_ID,
            COUNT(*) AS active_hours,
            SUM(LEAST(active_seconds_in_hour, 3600)) AS total_active_seconds
        FROM PerHour
        GROUP BY STATION_ID
    )
    SELECT
        wd.STATION_ID,
 
        
        (SUM(CASE WHEN filtered_time_diff_seconds > 0 THEN 1 ELSE 0 END) * 3600)
            / NULLIF(SUM(filtered_time_diff_seconds), 0) AS BIN_PER_HOUR,
 
        COUNT(DISTINCT wd.ORDER_BIN_ID) AS DISTINCT_BINS,
 
        
        ROUND(
            (sha.total_active_seconds / 60.0) / NULLIF(sha.active_hours, 0),
            2
        ) AS AVG_ACTIVE_MIN_PER_HOUR,
 
        
      ROUND(
    (
        (SUM(CASE WHEN filtered_time_diff_seconds > 0 THEN 1 ELSE 0 END) * 3600)
        / NULLIF(SUM(filtered_time_diff_seconds), 0)
    )
    /
    (
        ROUND(
            (sha.total_active_seconds / 60.0) / NULLIF(sha.active_hours, 0),
            2
        )
    )
    * 60.0,
    2
) AS BINS_PER_60MIN
 
    FROM WithDiff wd
    JOIN StationHourAgg sha
      ON sha.STATION_ID = wd.STATION_ID
    GROUP BY
        wd.STATION_ID,
        sha.total_active_seconds,
        sha.active_hours
    ORDER BY wd.STATION_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_BIN_PER_HOUR_PER_STATION_OLD` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_BIN_PER_HOUR_PER_STATION_OLD` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_BIN_PER_HOUR_PER_STATION_OLD`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    CombinedWave AS (
        SELECT ORDER_BIN_ID
        FROM pick_wave_order_master
        WHERE STATUS <> 'PENDING'
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT ORDER_BIN_ID
        FROM pick_wave_order_master_archive
        WHERE STATUS <> 'PENDING'
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT ORDER_BIN_ID
        FROM put_wave_order_master_archive
        WHERE STATUS <> 'PENDING'
          AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT ORDER_BIN_ID
        FROM put_wave_order_master
        WHERE STATUS <> 'PENDING'
          AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ),
    BaseResults AS (
        
        SELECT
            ORDER_BIN_ID,
            BIN_ID,
            STATION_ID,
            MAX(CASE WHEN STATUS = 'BIN_PICKED'     THEN BOT_ID            END) AS TASK_ALLOCATED_BOT_ID,
            MAX(CASE WHEN STATUS = 'PRE_ON_STATION' THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
            MAX(CASE WHEN STATUS = 'ON_STATION'     THEN UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
        FROM order_bin_mapping_log
        WHERE TYPE = 'RACK_PICK'
          AND ORDER_BIN_ID IN (SELECT DISTINCT ORDER_BIN_ID FROM CombinedWave)
        GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID
    ),
    Sequenced AS (
        
        SELECT
            STATION_ID,
            ORDER_BIN_ID,
            ON_STATION_TIMESTAMP,
            LEAD(ON_STATION_TIMESTAMP)
                OVER (PARTITION BY STATION_ID ORDER BY ON_STATION_TIMESTAMP) AS next_on_station_ts
        FROM BaseResults
        WHERE ON_STATION_TIMESTAMP IS NOT NULL
    ),
    WithDiff AS (
        
        SELECT
            STATION_ID,
            ORDER_BIN_ID,
            GREATEST(0,
                LEAST(600, TIMESTAMPDIFF(SECOND, ON_STATION_TIMESTAMP, next_on_station_ts))
            ) AS filtered_time_diff_seconds
        FROM Sequenced
    )
    SELECT
        STATION_ID,
        (SUM(CASE WHEN filtered_time_diff_seconds > 0 THEN 1 ELSE 0 END) * 3600)
        / NULLIF(SUM(filtered_time_diff_seconds), 0) AS `BIN_PER_HOUR`,
        COUNT(DISTINCT ORDER_BIN_ID) AS `DISTINCT_BINS`
    FROM WithDiff
    GROUP BY STATION_ID
    ORDER BY STATION_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_BIN_PRESENTATION_PER_BOT_PER_HOUR` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_BIN_PRESENTATION_PER_BOT_PER_HOUR` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_BIN_PRESENTATION_PER_BOT_PER_HOUR`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH all_datas AS (
        WITH ordered_reservations AS (
            SELECT 
                LOG_ID,
                BOT_ID,
                TYPE AS `CURRENT_TYPE`,
                LOGGED_TIMESTAMP AS `CURRENT_TIMESTAMP`,
                LEAD(TYPE) OVER (PARTITION BY BOT_ID ORDER BY LOGGED_TIMESTAMP) AS NEXT_TYPE,
                LEAD(LOGGED_TIMESTAMP) OVER (PARTITION BY BOT_ID ORDER BY LOGGED_TIMESTAMP) AS NEXT_TIMESTAMP
            FROM subcontroller_reservations_master_log
            WHERE IS_BUFFER = 0
              AND LOGGED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        )
        SELECT
            BOT_ID,
            CURRENT_TYPE,
            `CURRENT_TIMESTAMP` AS CUR_TIMESTAMP,
            CASE 
                WHEN CURRENT_TYPE = 'STATION' THEN 1
                ELSE 0
            END AS DATA_QUANTUM,
            NEXT_TYPE,
            NEXT_TIMESTAMP,
            CASE
                WHEN CURRENT_TYPE LIKE '%TOWER%'   AND NEXT_TYPE LIKE 'STATION'   THEN TIMESTAMPDIFF(SECOND, `CURRENT_TIMESTAMP`, NEXT_TIMESTAMP)
                WHEN CURRENT_TYPE LIKE '%STATION%' AND NEXT_TYPE LIKE '%TOWER%'   THEN TIMESTAMPDIFF(SECOND, `CURRENT_TIMESTAMP`, NEXT_TIMESTAMP)
                WHEN CURRENT_TYPE LIKE '%TOWER%'   AND NEXT_TYPE LIKE '%TOWER%'   THEN TIMESTAMPDIFF(SECOND, `CURRENT_TIMESTAMP`, NEXT_TIMESTAMP)
                WHEN CURRENT_TYPE LIKE '%TOWER%'   AND NEXT_TYPE LIKE '%HOME%'    THEN TIMESTAMPDIFF(SECOND, `CURRENT_TIMESTAMP`, NEXT_TIMESTAMP)
                ELSE 0
            END AS TIME_TAKEN
        FROM ordered_reservations
        WHERE CURRENT_TYPE IS NOT NULL 
          AND NEXT_TYPE IS NOT NULL
        HAVING TIME_TAKEN < 300
    ),
    stations AS (
        SELECT BOT_ID
        FROM bot_master
    ),
    agg AS (
        SELECT
            d.BOT_ID,
            HOUR(d.CUR_TIMESTAMP) AS hr,
            ROUND((SUM(d.DATA_QUANTUM) / SUM(d.TIME_TAKEN)) * 3600, 2) AS total_qty
        FROM all_datas d
        GROUP BY d.BOT_ID, HOUR(d.CUR_TIMESTAMP)
    )
    SELECT
        CAST(s.BOT_ID AS CHAR) AS BOT_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.total_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.total_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.total_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.total_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.total_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.total_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.total_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.total_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.total_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.total_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.total_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.total_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.total_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.total_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.total_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.total_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.total_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.total_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.total_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.total_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.total_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.total_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.total_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.total_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.BOT_ID = s.BOT_ID
    GROUP BY s.BOT_ID
    ORDER BY CAST(s.BOT_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_BOT_BEST_15MIN_X4_PER_HOUR` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_BOT_BEST_15MIN_X4_PER_HOUR` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_BOT_BEST_15MIN_X4_PER_HOUR`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_order_bin;
    CREATE TEMPORARY TABLE tmp_wave_order_bin (
        order_bin_id BIGINT PRIMARY KEY
    ) ENGINE=InnoDB;

    INSERT IGNORE INTO tmp_wave_order_bin(order_bin_id)
    SELECT order_bin_id
    FROM pick_wave_order_master
    WHERE STATUS NOT IN ('PENDING')
      AND PICK_TIMESTAMP >= p_start_date_time AND PICK_TIMESTAMP < p_end_date_time;

    INSERT IGNORE INTO tmp_wave_order_bin(order_bin_id)
    SELECT order_bin_id
    FROM pick_wave_order_master_archive
    WHERE STATUS NOT IN ('PENDING')
      AND PICK_TIMESTAMP >= p_start_date_time AND PICK_TIMESTAMP < p_end_date_time;

    INSERT IGNORE INTO tmp_wave_order_bin(order_bin_id)
    SELECT order_bin_id
    FROM put_wave_order_master
    WHERE STATUS NOT IN ('PENDING')
      AND PUT_TIMESTAMP >= p_start_date_time AND PUT_TIMESTAMP < p_end_date_time;

    INSERT IGNORE INTO tmp_wave_order_bin(order_bin_id)
    SELECT order_bin_id
    FROM put_wave_order_master_archive
    WHERE STATUS NOT IN ('PENDING')
      AND PUT_TIMESTAMP >= p_start_date_time AND PUT_TIMESTAMP < p_end_date_time;

    
    SET @picked_lookback_minutes := 180;  

    WITH RECURSIVE
    PreOnAgg AS (
        SELECT
            l.ORDER_BIN_ID,
            l.BIN_ID,
            l.STATION_ID,
            MAX(l.UPDATED_TIMESTAMP) AS EVENT_TS
        FROM order_bin_mapping_log l
        JOIN tmp_wave_order_bin t
          ON t.order_bin_id = l.ORDER_BIN_ID
        WHERE l.TYPE   = 'RACK_PICK'
          AND l.STATUS = 'PRE_ON_STATION'
          AND l.UPDATED_TIMESTAMP >= p_start_date_time
          AND l.UPDATED_TIMESTAMP <  p_end_date_time
        GROUP BY l.ORDER_BIN_ID, l.BIN_ID, l.STATION_ID
    ),
    PickedAgg AS (
        SELECT
            l.ORDER_BIN_ID,
            l.BIN_ID,
            l.STATION_ID,
            MAX(l.BOT_ID) AS BOT_ID
        FROM order_bin_mapping_log l
        JOIN tmp_wave_order_bin t
          ON t.order_bin_id = l.ORDER_BIN_ID
        WHERE l.TYPE   = 'RACK_PICK'
          AND l.STATUS = 'BIN_PICKED'
          AND l.UPDATED_TIMESTAMP >= (p_start_date_time - INTERVAL @picked_lookback_minutes MINUTE)
          AND l.UPDATED_TIMESTAMP <  p_end_date_time
        GROUP BY l.ORDER_BIN_ID, l.BIN_ID, l.STATION_ID
    ),
    Events AS (
        SELECT
            pk.BOT_ID,
            po.EVENT_TS,
            TIMESTAMP(DATE(po.EVENT_TS), MAKETIME(HOUR(po.EVENT_TS), 0, 0)) AS hour_start,
            HOUR(po.EVENT_TS)   AS hour_of_day,
            MINUTE(po.EVENT_TS) AS minute_of_hour
        FROM PreOnAgg po
        JOIN PickedAgg pk
          ON pk.ORDER_BIN_ID = po.ORDER_BIN_ID
         AND pk.BIN_ID       = po.BIN_ID
         AND pk.STATION_ID   = po.STATION_ID
        WHERE pk.BOT_ID IS NOT NULL
    ),
    BotHourBlocks AS (
        SELECT DISTINCT BOT_ID, hour_start, hour_of_day
        FROM Events
    ),
    MinuteCounts AS (
        SELECT
            BOT_ID,
            hour_start,
            hour_of_day,
            minute_of_hour,
            COUNT(*) AS cnt
        FROM Events
        GROUP BY BOT_ID, hour_start, hour_of_day, minute_of_hour
    ),
    SeqMinute AS (
        SELECT 0 AS m
        UNION ALL
        SELECT m + 1 FROM SeqMinute WHERE m < 59
    ),
    MinuteGrid AS (
        SELECT
            bhb.BOT_ID,
            bhb.hour_start,
            bhb.hour_of_day,
            sm.m AS minute_of_hour,
            COALESCE(mc.cnt, 0) AS cnt
        FROM BotHourBlocks bhb
        CROSS JOIN SeqMinute sm
        LEFT JOIN MinuteCounts mc
          ON mc.BOT_ID = bhb.BOT_ID
         AND mc.hour_start = bhb.hour_start
         AND mc.minute_of_hour = sm.m
    ),
    Rolling AS (
        SELECT
            BOT_ID,
            hour_start,
            hour_of_day,
            minute_of_hour,
            SUM(cnt) OVER (
                PARTITION BY BOT_ID, hour_start
                ORDER BY minute_of_hour
                ROWS BETWEEN 14 PRECEDING AND CURRENT ROW
            ) AS roll15
        FROM MinuteGrid
    ),
    BestPerHourBlock AS (
        SELECT
            BOT_ID,
            hour_of_day,
            (MAX(roll15) * 4) AS best15_x4
        FROM Rolling
        WHERE minute_of_hour >= 14
        GROUP BY BOT_ID, hour_start, hour_of_day
    ),
    BestPerHourOfDay AS (
        SELECT
            BOT_ID,
            hour_of_day,
            MAX(best15_x4) AS best15_x4
        FROM BestPerHourBlock
        GROUP BY BOT_ID, hour_of_day
    )
    SELECT
        BOT_ID AS `BOT_ID`,
        SUM(CASE WHEN hour_of_day =  0 THEN best15_x4 ELSE 0 END) AS `H00`,
        SUM(CASE WHEN hour_of_day =  1 THEN best15_x4 ELSE 0 END) AS `H01`,
        SUM(CASE WHEN hour_of_day =  2 THEN best15_x4 ELSE 0 END) AS `H02`,
        SUM(CASE WHEN hour_of_day =  3 THEN best15_x4 ELSE 0 END) AS `H03`,
        SUM(CASE WHEN hour_of_day =  4 THEN best15_x4 ELSE 0 END) AS `H04`,
        SUM(CASE WHEN hour_of_day =  5 THEN best15_x4 ELSE 0 END) AS `H05`,
        SUM(CASE WHEN hour_of_day =  6 THEN best15_x4 ELSE 0 END) AS `H06`,
        SUM(CASE WHEN hour_of_day =  7 THEN best15_x4 ELSE 0 END) AS `H07`,
        SUM(CASE WHEN hour_of_day =  8 THEN best15_x4 ELSE 0 END) AS `H08`,
        SUM(CASE WHEN hour_of_day =  9 THEN best15_x4 ELSE 0 END) AS `H09`,
        SUM(CASE WHEN hour_of_day = 10 THEN best15_x4 ELSE 0 END) AS `H10`,
        SUM(CASE WHEN hour_of_day = 11 THEN best15_x4 ELSE 0 END) AS `H11`,
        SUM(CASE WHEN hour_of_day = 12 THEN best15_x4 ELSE 0 END) AS `H12`,
        SUM(CASE WHEN hour_of_day = 13 THEN best15_x4 ELSE 0 END) AS `H13`,
        SUM(CASE WHEN hour_of_day = 14 THEN best15_x4 ELSE 0 END) AS `H14`,
        SUM(CASE WHEN hour_of_day = 15 THEN best15_x4 ELSE 0 END) AS `H15`,
        SUM(CASE WHEN hour_of_day = 16 THEN best15_x4 ELSE 0 END) AS `H16`,
        SUM(CASE WHEN hour_of_day = 17 THEN best15_x4 ELSE 0 END) AS `H17`,
        SUM(CASE WHEN hour_of_day = 18 THEN best15_x4 ELSE 0 END) AS `H18`,
        SUM(CASE WHEN hour_of_day = 19 THEN best15_x4 ELSE 0 END) AS `H19`,
        SUM(CASE WHEN hour_of_day = 20 THEN best15_x4 ELSE 0 END) AS `H20`,
        SUM(CASE WHEN hour_of_day = 21 THEN best15_x4 ELSE 0 END) AS `H21`,
        SUM(CASE WHEN hour_of_day = 22 THEN best15_x4 ELSE 0 END) AS `H22`,
        SUM(CASE WHEN hour_of_day = 23 THEN best15_x4 ELSE 0 END) AS `H23`
    FROM BestPerHourOfDay
    GROUP BY BOT_ID
    ORDER BY BOT_ID;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_BOT_TASKS_PER_HOUR` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_BOT_TASKS_PER_HOUR` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_BOT_TASKS_PER_HOUR`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    CombinedWave AS (       
        SELECT order_bin_id
        FROM pick_wave_order_master
        WHERE STATUS NOT IN ('PENDING')
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT order_bin_id
        FROM pick_wave_order_master_archive
        WHERE STATUS NOT IN ('PENDING')
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT order_bin_id
        FROM put_wave_order_master_archive
        WHERE STATUS NOT IN ('PENDING')
          AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT order_bin_id
        FROM put_wave_order_master
        WHERE STATUS NOT IN ('PENDING')
          AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ),
    HourlyData AS (         
        SELECT
            TASK_ALLOCATED_BOT_ID,
            HOUR(PRE_ON_STATION_TIMESTAMP) AS hour_of_day,
            COUNT(*) AS task_count
        FROM (
            SELECT
                ORDER_BIN_ID,
                BIN_ID,
                STATION_ID,
                MAX(CASE WHEN STATUS = 'BIN_PICKED'      THEN BOT_ID            END) AS TASK_ALLOCATED_BOT_ID,
                MAX(CASE WHEN STATUS = 'PRE_ON_STATION'  THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP
            FROM order_bin_mapping_log
            WHERE TYPE = 'RACK_PICK'
              AND ORDER_BIN_ID IN (SELECT DISTINCT ORDER_BIN_ID FROM CombinedWave)
            GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID
        ) X
        WHERE TASK_ALLOCATED_BOT_ID IS NOT NULL
        GROUP BY TASK_ALLOCATED_BOT_ID, hour_of_day
    )
    SELECT
        TASK_ALLOCATED_BOT_ID AS `BOT_ID`,
        SUM(CASE WHEN hour_of_day =  0 THEN task_count ELSE 0 END) AS `H00`,
        SUM(CASE WHEN hour_of_day =  1 THEN task_count ELSE 0 END) AS `H01`,
        SUM(CASE WHEN hour_of_day =  2 THEN task_count ELSE 0 END) AS `H02`,
        SUM(CASE WHEN hour_of_day =  3 THEN task_count ELSE 0 END) AS `H03`,
        SUM(CASE WHEN hour_of_day =  4 THEN task_count ELSE 0 END) AS `H04`,
        SUM(CASE WHEN hour_of_day =  5 THEN task_count ELSE 0 END) AS `H05`,
        SUM(CASE WHEN hour_of_day =  6 THEN task_count ELSE 0 END) AS `H06`,
        SUM(CASE WHEN hour_of_day =  7 THEN task_count ELSE 0 END) AS `H07`,
        SUM(CASE WHEN hour_of_day =  8 THEN task_count ELSE 0 END) AS `H08`,
        SUM(CASE WHEN hour_of_day =  9 THEN task_count ELSE 0 END) AS `H09`,
        SUM(CASE WHEN hour_of_day = 10 THEN task_count ELSE 0 END) AS `H10`,
        SUM(CASE WHEN hour_of_day = 11 THEN task_count ELSE 0 END) AS `H11`,
        SUM(CASE WHEN hour_of_day = 12 THEN task_count ELSE 0 END) AS `H12`,
        SUM(CASE WHEN hour_of_day = 13 THEN task_count ELSE 0 END) AS `H13`,
        SUM(CASE WHEN hour_of_day = 14 THEN task_count ELSE 0 END) AS `H14`,
        SUM(CASE WHEN hour_of_day = 15 THEN task_count ELSE 0 END) AS `H15`,
        SUM(CASE WHEN hour_of_day = 16 THEN task_count ELSE 0 END) AS `H16`,
        SUM(CASE WHEN hour_of_day = 17 THEN task_count ELSE 0 END) AS `H17`,
        SUM(CASE WHEN hour_of_day = 18 THEN task_count ELSE 0 END) AS `H18`,
        SUM(CASE WHEN hour_of_day = 19 THEN task_count ELSE 0 END) AS `H19`,
        SUM(CASE WHEN hour_of_day = 20 THEN task_count ELSE 0 END) AS `H20`,
        SUM(CASE WHEN hour_of_day = 21 THEN task_count ELSE 0 END) AS `H21`,
        SUM(CASE WHEN hour_of_day = 22 THEN task_count ELSE 0 END) AS `H22`,
        SUM(CASE WHEN hour_of_day = 23 THEN task_count ELSE 0 END) AS `H23`
    FROM HourlyData
    GROUP BY TASK_ALLOCATED_BOT_ID
    ORDER BY TASK_ALLOCATED_BOT_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_BOT_TIME_SPEND_ON_HOME_BUFFER_LOADED` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_BOT_TIME_SPEND_ON_HOME_BUFFER_LOADED` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_BOT_TIME_SPEND_ON_HOME_BUFFER_LOADED`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH all_datas AS (
        WITH ordered_reservations AS (
            SELECT 
                LOG_ID,
                BOT_ID,
                TYPE AS `CURRENT_TYPE`,
                IS_BUFFER,
                LOGGED_TIMESTAMP AS `CURRENT_TIMESTAMP`,
                LEAD(TYPE) OVER (PARTITION BY BOT_ID ORDER BY LOGGED_TIMESTAMP) AS NEXT_TYPE,
                LEAD(LOGGED_TIMESTAMP) OVER (PARTITION BY BOT_ID ORDER BY LOGGED_TIMESTAMP) AS NEXT_TIMESTAMP
            FROM subcontroller_reservations_master_log
            WHERE LOGGED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        )
        SELECT
            BOT_ID,
            `CURRENT_TIMESTAMP` AS CUR_TIMESTAMP,
            CASE
                WHEN NEXT_TYPE LIKE 'STATION%'   THEN TIMESTAMPDIFF(SECOND, `CURRENT_TIMESTAMP`, NEXT_TIMESTAMP)
                ELSE 0
            END AS DATA_QUANTUM
        FROM ordered_reservations
        WHERE CURRENT_TYPE IS NOT NULL 
        AND IS_BUFFER = 1
        AND NEXT_TYPE IS NOT NULL
    ),
    stations AS (
        SELECT BOT_ID
        FROM bot_master
    ),
    agg AS (
        SELECT
            d.BOT_ID,
            HOUR(d.CUR_TIMESTAMP) AS hr,
            CASE WHEN SUM(d.DATA_QUANTUM)>60 
            THEN 60 
            ELSE SUM(d.DATA_QUANTUM) END AS total_qty
        FROM all_datas d
        GROUP BY d.BOT_ID, HOUR(d.CUR_TIMESTAMP)
    )
    SELECT
        CAST(s.BOT_ID AS CHAR) AS BOT_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.total_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.total_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.total_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.total_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.total_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.total_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.total_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.total_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.total_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.total_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.total_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.total_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.total_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.total_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.total_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.total_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.total_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.total_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.total_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.total_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.total_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.total_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.total_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.total_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.BOT_ID = s.BOT_ID
    GROUP BY s.BOT_ID
    ORDER BY CAST(s.BOT_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_BOT_TIME_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_BOT_TIME_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_BOT_TIME_SUMMARY`(
    IN p_start_date_time VARCHAR(50)CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN p_end_date_time VARCHAR(50)CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
select   A.BOT_ID,

round((24*60-ifnull(Time_To_sec(A.BOT_TASK_TIME)/60,0)),2) 'NO TASK',
round(TIME_TO_SEC(A.BOT_ALARM_TIME)/60,2)'ERROR TIME',
Case when Time_To_Sec(A.OBSTACLE_TIME)>60 then round(TIME_TO_SEC(A.OBSTACLE_TIME)/60,2) else 0 end 'OBSTACLE TIME>1 MINUTE',
case when(round(TIME_TO_SEC(A.BOT_AT_HOME)/60,2)-ROUND(TIME_TO_SEC(A.BOT_ALARM_TIME)/60,2))>1 then
(ROUND(TIME_TO_SEC(A.BOT_AT_HOME)/60,2)-ROUND(TIME_TO_SEC(A.BOT_ALARM_TIME)/60,2))
else 0 end 'BOT_AT_HOME>1 MINUTE',
A.BOT_AT_STATION as 'BOT AT STATION >15 SEC',
round(TIME_TO_SEC(A.BOT_HOME_TO_MAINTENANCE)/60,2) as BOT_HOME_TO_MAINTENANCE



from (
	SELECT  BM.BOT_ID, 
	ifnull(BAT.TaskExecutionTime_TASK,0) 'BOT_TASK_TIME',
	IFNULL(BAU.TaskExecutionTime_AUTO,0) 'AUTO_TASK_EXECUTION_TIME',
	IFNULL(BAM.TaskExecutionTime_MANUAL,0) 'MANUAL_TASK_EXECUTION_TIME',
	IFNULL(BTC.TaskExecutionTime_CHARG,0)'CHARGING_TASK_EXECUTION_TIME',
	IFNULL(BTOM.TaskExecutionTime_MAIN,0) 'MAINTENANCE_TASK_EXECUTION_TIME',
	IFNULL(BIACH.Bot_Obstacle_AT_CHARGING,0) 'OBSTACLE_AT_CHARGING_POINT', 
	IFNULL(BOASE.Bot_Obstacle_AT_BOASE,0)  'OBSTACLE_AT_STATION_ENTRY', 
	IFNULL(BOAMP.Bot_Obstacle_AT_BOAMP,0) 'OBSTACLE_AT_MAINTENANCE_PICK',
	IFNULL(BOAOTH.Bot_Obstacle_AT_BOAOTH,0) 'OBSTACLE_AT_OTHER_POINTS', 
	SEC_TO_TIME(TIME_TO_SEC(IFNULL(BIACH.Bot_Obstacle_AT_CHARGING,0))+
	TIME_TO_SEC(IFNULL(BOASE.Bot_Obstacle_AT_BOASE,0))+
	TIME_TO_SEC(IFNULL(BOAMP.Bot_Obstacle_AT_BOAMP,0))+
	TIME_TO_SEC(IFNULL(BOAOTH.Bot_Obstacle_AT_BOAOTH,0)))  'OBSTACLE_TIME',
	IFNULL(BIALM.BOAT_IN_ALARM,0) 'BOT_ALARM_TIME', 
	IFNULL(WBU.Waittime_0,0) 'WAITING_AT_HOME(BUFFER 0)',
	IFNULL(WBU1.Waittime_1,0) 'WAITING_AT_HOME(BUFFER 1)',
	IFNULL(WBUH.Waittime_H,0) 'BOT_AT_HOME',
	IFNULL(BHTM.BOT_HOME_TO_MAINTENANCE,0) 'BOT_HOME_TO_MAINTENANCE',
	IFNULL(BASTS.BOT_AT_STATION,0) 'BOT_AT_STATION'		
	FROM `bot_master` BM 
	LEFT  OUTER JOIN (
		SELECT A.BOT_ID, SEC_TO_TIME(TaskExecutionTimeinSeconds_TASK) TaskExecutionTime_TASK FROM (
			SELECT BOT_ID,SUM(TIMESTAMPDIFF(SECOND,LOGGED_TIMESTAMP,NextLogTime)) TaskExecutionTimeinSeconds_TASK 
			FROM (
				SELECT  A.*,LEAD(LOGGED_TIMESTAMP,1)OVER (PARTITION BY BOT_ID,TASK_ID ORDER BY TASK_ID,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END,LOGGED_TIMESTAMP) AS NextLogTime  
				FROM (
					SELECT BOT_ID, 'TASK(AUTO)' TASK_Name,TASK_TYPE,`TASK_ID`,STATUS,`LOGGED_TIMESTAMP`
					FROM `task_master_log` WHERE `LOGGED_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
					
					AND STATUS IN ('PROCESSING','COMPLETED')
					ORDER BY TASK_ID ,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END 
				) A
			) A WHERE A.NextLogTime IS NOT NULL
			GROUP BY BOT_ID
		) A
	) BAT ON BAT.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT A.BOT_ID, SEC_TO_TIME(TaskExecutionTimeinSeconds_AU) TaskExecutionTime_AUTO FROM (
			SELECT BOT_ID,SUM(TIMESTAMPDIFF(SECOND,LOGGED_TIMESTAMP,NextLogTime)) TaskExecutionTimeinSeconds_AU 
			FROM (
				SELECT  A.*,LEAD(LOGGED_TIMESTAMP,1)OVER (PARTITION BY BOT_ID,TASK_ID ORDER BY TASK_ID,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END,LOGGED_TIMESTAMP) AS NextLogTime  
				FROM (
					SELECT BOT_ID, 'TASK(AUTO)' TASK_Name,TASK_TYPE,`TASK_ID`,STATUS,`LOGGED_TIMESTAMP`
					FROM `task_master_log` WHERE `LOGGED_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
					AND `TASK_TYPE` IN ('BIN_FROM_ZONE','BIN_STORE_TO_ZONE','BIN_ZONE_TO_STORE','STATION_TO_STATION')
					AND STATUS IN ('PROCESSING','COMPLETED')
					ORDER BY TASK_ID ,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END 
				) A
			) A WHERE A.NextLogTime IS NOT NULL
			GROUP BY BOT_ID
		) A
	) BAU ON BAU.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT A.BOT_ID, SEC_TO_TIME(TaskExecutionTimeinSeconds_MA) TaskExecutionTime_MANUAL FROM (
			SELECT BOT_ID,SUM(TIMESTAMPDIFF(SECOND,LOGGED_TIMESTAMP,NextLogTime)) TaskExecutionTimeinSeconds_MA 
			FROM (
				SELECT  A.*,LEAD(LOGGED_TIMESTAMP,1)OVER (PARTITION BY BOT_ID,TASK_ID ORDER BY TASK_ID,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END,LOGGED_TIMESTAMP) AS NextLogTime  
				FROM (
					SELECT BOT_ID, 'TASK(AUTO)' TASK_Name,TASK_TYPE,`TASK_ID`,STATUS,`LOGGED_TIMESTAMP`
					FROM `task_master_log` WHERE `LOGGED_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
					AND `TASK_TYPE` IN ('MANUAL')
					AND STATUS IN ('PROCESSING','COMPLETED')
					ORDER BY TASK_ID ,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END 
				) A
			) A WHERE A.NextLogTime IS NOT NULL
			GROUP BY BOT_ID
		) A
	)BAM ON BAM.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT A.BOT_ID, SEC_TO_TIME(TaskExecutionTimeinSeconds_CHARG) TaskExecutionTime_CHARG FROM (
			SELECT BOT_ID,SUM(TIMESTAMPDIFF(SECOND,LOGGED_TIMESTAMP,NextLogTime)) TaskExecutionTimeinSeconds_CHARG
			FROM (
				SELECT  A.*,LEAD(LOGGED_TIMESTAMP,1)OVER (PARTITION BY BOT_ID,TASK_ID ORDER BY TASK_ID,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END,LOGGED_TIMESTAMP) AS NextLogTime  
				FROM (
					SELECT BOT_ID, 'TASK(AUTO)' TASK_Name,TASK_TYPE,`TASK_ID`,STATUS,`LOGGED_TIMESTAMP`
					FROM `task_master_log` WHERE `LOGGED_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
					AND `TASK_TYPE` IN ('BOT_TO_CHARGING')
					AND STATUS IN ('PROCESSING','COMPLETED')
					ORDER BY TASK_ID ,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END 
				) A
			) A WHERE A.NextLogTime IS NOT NULL
			GROUP BY BOT_ID
		) A
	)BTC ON BTC.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT A.BOT_ID, SEC_TO_TIME(TaskExecutionTimeinSeconds_MAIN) TaskExecutionTime_MAIN FROM (
			SELECT BOT_ID,SUM(TIMESTAMPDIFF(SECOND,LOGGED_TIMESTAMP,NextLogTime)) TaskExecutionTimeinSeconds_MAIN
			FROM (
				SELECT  A.*,LEAD(LOGGED_TIMESTAMP,1)OVER (PARTITION BY BOT_ID,TASK_ID ORDER BY TASK_ID,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END,LOGGED_TIMESTAMP) AS NextLogTime  
				FROM (
					SELECT BOT_ID, 'TASK(AUTO)' TASK_Name,TASK_TYPE,`TASK_ID`,STATUS,`LOGGED_TIMESTAMP`
					FROM `task_master_log` WHERE `LOGGED_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
					AND `TASK_TYPE` IN ('BOT_TO_MAINTENANCE')
					AND STATUS IN ('PROCESSING','COMPLETED')
					ORDER BY TASK_ID ,CASE  WHEN STATUS='PROCESSING' THEN 1 ELSE 2 END 
				) A
			) A WHERE A.NextLogTime IS NOT NULL
			GROUP BY BOT_ID
		) A
	)BTOM ON BTOM.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT  BOA.`BOT_ID`,SEC_TO_TIME(SUM(TIMESTAMPDIFF(SECOND,BOA.`OBSTACLE_DETECTION_TIMESTAMP`,BOA.`OBSTACLE_REMOVAL_TIMESTAMP`))) Bot_Obstacle_AT_CHARGING
		FROM `bot_obstacle_log_archive` BOA
		INNER JOIN  Location_master LM ON LM.`BARCODE_NUMBER`=BOA.BARCODE_NUMBER 
		WHERE BOA.`OBSTACLE_DETECTION_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
		AND  LM.TYPE IN ('CHARGING_STATION_ENTRY')
		and TIMESTAMPDIFF(SECOND,BOA.`OBSTACLE_DETECTION_TIMESTAMP`,BOA.`OBSTACLE_REMOVAL_TIMESTAMP`)>60
		GROUP BY BOA.BOT_ID
	) BIACH ON BIACH.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT  BOA.`BOT_ID`,SEC_TO_TIME(SUM(TIMESTAMPDIFF(SECOND,BOA.`OBSTACLE_DETECTION_TIMESTAMP`,BOA.`OBSTACLE_REMOVAL_TIMESTAMP`))) Bot_Obstacle_AT_BOASE
		FROM `bot_obstacle_log_archive` BOA
		INNER JOIN  Location_master LM ON LM.`BARCODE_NUMBER`=BOA.BARCODE_NUMBER 
		WHERE BOA.`OBSTACLE_DETECTION_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
		AND  LM.TYPE IN ('STATION_ENTRY_CONVEYOR')
		and TIMESTAMPDIFF(SECOND,BOA.`OBSTACLE_DETECTION_TIMESTAMP`,BOA.`OBSTACLE_REMOVAL_TIMESTAMP`)>60
		GROUP BY BOA.BOT_ID
	) BOASE ON BOASE.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT  BOA.`BOT_ID`,SEC_TO_TIME(SUM(TIMESTAMPDIFF(SECOND,BOA.`OBSTACLE_DETECTION_TIMESTAMP`,BOA.`OBSTACLE_REMOVAL_TIMESTAMP`))) Bot_Obstacle_AT_BOAMP
		FROM `bot_obstacle_log_archive` BOA
		INNER JOIN  Location_master LM ON LM.`BARCODE_NUMBER`=BOA.BARCODE_NUMBER 
		WHERE BOA.`OBSTACLE_DETECTION_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
		AND  LM.TYPE IN ('MAINTENANCE_PICK')
		and TIMESTAMPDIFF(SECOND,BOA.`OBSTACLE_DETECTION_TIMESTAMP`,BOA.`OBSTACLE_REMOVAL_TIMESTAMP`)>60
		GROUP BY BOA.BOT_ID
	) BOAMP ON BOAMP.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT  BOA.`BOT_ID`,SEC_TO_TIME(SUM(TIMESTAMPDIFF(SECOND,BOA.`OBSTACLE_DETECTION_TIMESTAMP`,BOA.`OBSTACLE_REMOVAL_TIMESTAMP`))) Bot_Obstacle_AT_BOAOTH
		FROM `bot_obstacle_log_archive` BOA
		INNER JOIN  Location_master LM ON LM.`BARCODE_NUMBER`=BOA.BARCODE_NUMBER 
		WHERE BOA.`OBSTACLE_DETECTION_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
		AND  LM.TYPE NOT IN ('MAINTENANCE_PICK','STATION_ENTRY_CONVEYOR','CHARGING_STATION_ENTRY')
		and TIMESTAMPDIFF(SECOND,BOA.`OBSTACLE_DETECTION_TIMESTAMP`,BOA.`OBSTACLE_REMOVAL_TIMESTAMP`)>60
		GROUP BY BOA.BOT_ID
	) BOAOTH ON BOAOTH.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		
		
		SELECT  BOT_ID ,SEC_TO_TIME(SUM(TIMESTAMPDIFF(SECOND,INSERTED_TIMESTAMP ,`RECOVERY_TIMESTAMP`))) BOAT_IN_ALARM  
			FROM (	
				SELECT BOT_ID,MAX(INSERTED_TIMESTAMP) AS INSERTED_TIMESTAMP,RECOVERY_TIMESTAMP
				FROM `bot_alarm_log`
				WHERE  INSERTED_TIMESTAMP between p_start_date_time AND p_end_date_time
				AND ALARM_CODE NOT IN ('12')
				GROUP BY BOT_ID,RECOVERY_TIMESTAMP
			) A		
		GROUP BY BOT_ID
	) BIALM ON BIALM.BOT_ID=BM.BOT_ID 
	LEFT  OUTER JOIN (
	SELECT  A.BOT_ID,SEC_TO_TIME(SUM(Waittime)) AS Waittime_0 FROM (
		SELECT  A.BOT_ID,TIMESTAMPDIFF(SECOND,A.INSERTED_TIMESTAMP,NextINSERTED_TIMESTAMP) Waittime
		FROM (
			SELECT A.*,LEAD(INSERTED_TIMESTAMP,1) OVER(PARTITION BY BOT_ID ORDER BY LRank) AS NextINSERTED_TIMESTAMP ,
			LEAD(LRank,1) OVER(PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS NextRank 
			  FROM (
				SELECT  BOT_ID,TYPE,INSERTED_TIMESTAMP,ROW_NUMBER() OVER(PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS LRank
				FROM (
					SELECT  BOT_ID, TYPE,INSERTED_TIMESTAMP 
					FROM `subcontroller_reservations_master_log`
					WHERE `IS_BUFFER` = 0
					AND `INSERTED_TIMESTAMP`BETWEEN p_start_date_time AND p_end_date_time
					
					ORDER BY  INSERTED_TIMESTAMP
				) A
			) A 
		) A WHERE A.TYPE IN ('HOME','STATION_HOME')
	) A 
	GROUP BY A.BOT_ID
	) WBU ON WBU.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT  A.BOT_ID,SEC_TO_TIME(SUM(Waittime)) AS Waittime_1 FROM (
			SELECT  A.BOT_ID,TIMESTAMPDIFF(SECOND,A.INSERTED_TIMESTAMP,NextINSERTED_TIMESTAMP) Waittime
			FROM (
				SELECT A.*,LEAD(INSERTED_TIMESTAMP,1) OVER(PARTITION BY BOT_ID ORDER BY LRank) AS NextINSERTED_TIMESTAMP ,
				LEAD(LRank,1) OVER(PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS NextRank ,
				LEAD(IS_BUFFER,1) OVER(PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS NextIS_BUFFER 
				  FROM (
					SELECT  BOT_ID,TYPE,IS_BUFFER,INSERTED_TIMESTAMP,ROW_NUMBER() OVER(PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS LRank
					FROM (
						SELECT  BOT_ID, IS_BUFFER,TYPE,INSERTED_TIMESTAMP 
						FROM `subcontroller_reservations_master_log`
						WHERE  `INSERTED_TIMESTAMP` BETWEEN p_start_date_time AND p_end_date_time
						ORDER BY  INSERTED_TIMESTAMP
					) A
				) A 
			    ) A WHERE A.TYPE IN ('HOME','STATION_HOME') AND A.IS_BUFFER=1 AND A.NextIS_BUFFER=0
			) A 
			GROUP BY A.BOT_ID
	) WBU1 ON WBU1.BOT_ID=BM.BOT_ID
	LEFT  OUTER JOIN (
		SELECT  A.BOT_ID,SEC_TO_TIME(SUM(Waittime)) AS Waittime_H FROM (
			SELECT  A.BOT_ID,TIMESTAMPDIFF(SECOND,A.INSERTED_TIMESTAMP,NextINSERTED_TIMESTAMP) Waittime
			FROM (
				SELECT A.*,LEAD(INSERTED_TIMESTAMP,1) OVER(PARTITION BY BOT_ID ORDER BY LRank) AS NextINSERTED_TIMESTAMP ,
				LEAD(LRank,1) OVER(PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS NextRank ,
				LEAD(IS_BUFFER,1) OVER(PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS NextIS_BUFFER 
				  FROM (
					SELECT  BOT_ID,TYPE,IS_BUFFER,INSERTED_TIMESTAMP,ROW_NUMBER() OVER(PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS LRank
					FROM (
						SELECT  BOT_ID, IS_BUFFER,TYPE,INSERTED_TIMESTAMP 
						FROM `subcontroller_reservations_master_log`
						WHERE  `INSERTED_TIMESTAMP` BETWEEN p_start_date_time AND p_end_date_time
						ORDER BY  INSERTED_TIMESTAMP
					) A
				) A 
			    ) A WHERE A.TYPE IN ('HOME') AND A.IS_BUFFER=1 AND A.NextIS_BUFFER=0
			) A 
			GROUP BY A.BOT_ID
	) WBUH ON WBUH.BOT_ID=BM.BOT_ID
	Left  outer Join 
	(
		SELECT  A.BOT_ID,SEC_TO_TIME(SUM(BOT_HOME_TO_MAINTENANCE)) AS BOT_HOME_TO_MAINTENANCE 
		FROM (
			SELECT A.BOT_ID ,Timestampdiff(Second,LOGGED_TIMESTAMP,NextLOGGED_TIMESTAMP) as 'BOT_HOME_TO_MAINTENANCE' 
			FROM (
				SELECT A.BOT_ID,A.LOGGED_TIMESTAMP ,A.TYPE,A.DESTINATION_ID  ,
				LEAD(A.LOGGED_TIMESTAMP,1) OVER(PARTITION BY A.BOT_ID ORDER BY A.LOGGED_TIMESTAMP) AS NextLOGGED_TIMESTAMP,
				LEAD(A.DESTINATION_ID,1) OVER(PARTITION BY A.BOT_ID ORDER BY A.LOGGED_TIMESTAMP) AS NextDESTINATION_ID
				FROM subcontroller_reservations_master_log A 
				WHERE  IS_BUFFER=1 
				AND A.LOGGED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
				ORDER BY `LOGGED_TIMESTAMP`
			) A
			INNER JOIN `location_master` LM  ON LM.LOCATION_ID=A.NextDESTINATION_ID  
			WHERE A.TYPE='HOME' AND   LM.TYPE LIKE '%MAINTENANCE%'
			ORDER BY A.BOT_ID,A.LOGGED_TIMESTAMP
		)A
	) BHTM on BHTM.BOT_ID=BM.BOT_ID
	Left  outer Join (
		SELECT  A.BOT_ID,ROUND(SUM(A.BOT_AT_STATION)/60,2) AS BOT_AT_STATION,COUNT(A.BOT_AT_STATION)
		FROM (
			SELECT A.BOT_ID,TIMESTAMPDIFF(SECOND,A.IS_COMPLETED_TIMESTAMP,A.NextCOMPLETED_TIMESTAMP) AS 'BOT_AT_STATION'
			FROM (
				SELECT `BOT_ID`,`IS_COMPLETED_TIMESTAMP`,`PICK_PUT`,LM.`TYPE`,
				LEAD(S.IS_COMPLETED_TIMESTAMP,1) OVER(PARTITION BY BOT_ID ORDER BY IS_COMPLETED_TIMESTAMP) AS NextCOMPLETED_TIMESTAMP,
				LEAD(LM.TYPE,1) OVER(PARTITION BY BOT_ID ORDER BY IS_COMPLETED_TIMESTAMP) AS NextTYPE
				FROM `steps_archive` S
				INNER JOIN Location_master  LM  ON LM.`X`=S.`X` AND  LM.`Y`=S.`Y` AND  LM.`Z`=S.Z
				WHERE LM.TYPE IN( 'STATION_ENTRY','STATION') 
				AND  `IS_COMPLETED_TIMESTAMP` BETWEEN p_start_date_time AND p_end_date_time
			) A WHERE A.TYPE='STATION_ENTRY' AND  A.NextTYPE='STATION'
		) A WHERE A.BOT_AT_STATION>15
		GROUP BY A.BOT_ID
	) BASTS on BASTS.BOT_ID=BM.BOT_ID
) A
ORDER BY A.BOT_ID,TIME_TO_SEC(A.BOT_TASK_TIME) DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_BOT_TIME_SUMMARY_1` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_BOT_TIME_SUMMARY_1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_BOT_TIME_SUMMARY_1`(
    IN p_start_date_time VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN p_end_date_time   VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci
)
BEGIN
    DECLARE v_start DATETIME;
    DECLARE v_end   DATETIME;

    
    SET v_start = CAST(p_start_date_time AS DATETIME);
    SET v_end   = CAST(p_end_date_time   AS DATETIME);

    
    IF v_start IS NULL OR v_end IS NULL OR v_start >= v_end THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid start/end datetime';
    END IF;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_task_log;
    CREATE TEMPORARY TABLE tmp_task_log
    AS
    SELECT BOT_ID, TASK_ID, TASK_TYPE, STATUS, LOGGED_TIMESTAMP
    FROM task_master_log
    WHERE LOGGED_TIMESTAMP BETWEEN v_start AND v_end
      AND STATUS IN ('PROCESSING','COMPLETED');

    CREATE INDEX ix_tmp_task_log_1 ON tmp_task_log (BOT_ID, TASK_ID, STATUS, LOGGED_TIMESTAMP);
    CREATE INDEX ix_tmp_task_log_2 ON tmp_task_log (TASK_TYPE);

    
    DROP TEMPORARY TABLE IF EXISTS tmp_task_dur;
    CREATE TEMPORARY TABLE tmp_task_dur
    AS
    SELECT
        BOT_ID,
        TASK_ID,
        MAX(TASK_TYPE) AS TASK_TYPE,
        MIN(CASE WHEN STATUS='PROCESSING' THEN LOGGED_TIMESTAMP END) AS ts_start,
        MAX(CASE WHEN STATUS='COMPLETED'  THEN LOGGED_TIMESTAMP END) AS ts_end
    FROM tmp_task_log
    GROUP BY BOT_ID, TASK_ID;

    CREATE INDEX ix_tmp_task_dur_1 ON tmp_task_dur (BOT_ID);

    
    DROP TEMPORARY TABLE IF EXISTS tmp_task_bot_sum;
    CREATE TEMPORARY TABLE tmp_task_bot_sum
    AS
    SELECT
        BOT_ID,
        SUM(CASE
              WHEN ts_start IS NOT NULL AND ts_end IS NOT NULL AND ts_end > ts_start
              THEN TIMESTAMPDIFF(SECOND, ts_start, ts_end) ELSE 0 END
        ) AS sec_task_all,

        SUM(CASE
              WHEN TASK_TYPE IN ('BIN_FROM_ZONE','BIN_STORE_TO_ZONE','BIN_ZONE_TO_STORE','STATION_TO_STATION')
               AND ts_start IS NOT NULL AND ts_end IS NOT NULL AND ts_end > ts_start
              THEN TIMESTAMPDIFF(SECOND, ts_start, ts_end) ELSE 0 END
        ) AS sec_task_auto,

        SUM(CASE
              WHEN TASK_TYPE IN ('MANUAL')
               AND ts_start IS NOT NULL AND ts_end IS NOT NULL AND ts_end > ts_start
              THEN TIMESTAMPDIFF(SECOND, ts_start, ts_end) ELSE 0 END
        ) AS sec_task_manual,

        SUM(CASE
              WHEN TASK_TYPE IN ('BOT_TO_CHARGING')
               AND ts_start IS NOT NULL AND ts_end IS NOT NULL AND ts_end > ts_start
              THEN TIMESTAMPDIFF(SECOND, ts_start, ts_end) ELSE 0 END
        ) AS sec_task_charging,

        SUM(CASE
              WHEN TASK_TYPE IN ('BOT_TO_MAINTENANCE')
               AND ts_start IS NOT NULL AND ts_end IS NOT NULL AND ts_end > ts_start
              THEN TIMESTAMPDIFF(SECOND, ts_start, ts_end) ELSE 0 END
        ) AS sec_task_maintenance

    FROM tmp_task_dur
    GROUP BY BOT_ID;

    CREATE INDEX ix_tmp_task_bot_sum_1 ON tmp_task_bot_sum (BOT_ID);


    
    DROP TEMPORARY TABLE IF EXISTS tmp_obstacle_bot_sum;
    CREATE TEMPORARY TABLE tmp_obstacle_bot_sum
    AS
    SELECT
        BOA.BOT_ID,
        SUM(CASE WHEN LM.TYPE='CHARGING_STATION_ENTRY' THEN TIMESTAMPDIFF(SECOND, BOA.OBSTACLE_DETECTION_TIMESTAMP, BOA.OBSTACLE_REMOVAL_TIMESTAMP) ELSE 0 END) AS sec_obs_charging,
        SUM(CASE WHEN LM.TYPE='STATION_ENTRY_CONVEYOR' THEN TIMESTAMPDIFF(SECOND, BOA.OBSTACLE_DETECTION_TIMESTAMP, BOA.OBSTACLE_REMOVAL_TIMESTAMP) ELSE 0 END) AS sec_obs_station_entry,
        SUM(CASE WHEN LM.TYPE='MAINTENANCE_PICK' THEN TIMESTAMPDIFF(SECOND, BOA.OBSTACLE_DETECTION_TIMESTAMP, BOA.OBSTACLE_REMOVAL_TIMESTAMP) ELSE 0 END) AS sec_obs_maintenance_pick,
        SUM(CASE WHEN LM.TYPE NOT IN ('MAINTENANCE_PICK','STATION_ENTRY_CONVEYOR','CHARGING_STATION_ENTRY')
                 THEN TIMESTAMPDIFF(SECOND, BOA.OBSTACLE_DETECTION_TIMESTAMP, BOA.OBSTACLE_REMOVAL_TIMESTAMP) ELSE 0 END) AS sec_obs_other
    FROM bot_obstacle_log_archive BOA
    INNER JOIN location_master LM
        ON LM.BARCODE_NUMBER = BOA.BARCODE_NUMBER
    WHERE BOA.OBSTACLE_DETECTION_TIMESTAMP BETWEEN v_start AND v_end
      AND BOA.OBSTACLE_REMOVAL_TIMESTAMP IS NOT NULL
      AND TIMESTAMPDIFF(SECOND, BOA.OBSTACLE_DETECTION_TIMESTAMP, BOA.OBSTACLE_REMOVAL_TIMESTAMP) > 60
    GROUP BY BOA.BOT_ID;

    CREATE INDEX ix_tmp_obstacle_bot_sum_1 ON tmp_obstacle_bot_sum (BOT_ID);


    
    DROP TEMPORARY TABLE IF EXISTS tmp_alarm_bot_sum;
    CREATE TEMPORARY TABLE tmp_alarm_bot_sum
    AS
    SELECT
        BOT_ID,
        SUM(TIMESTAMPDIFF(SECOND, inserted_ts, RECOVERY_TIMESTAMP)) AS sec_alarm
    FROM (
        SELECT
            BOT_ID,
            MAX(INSERTED_TIMESTAMP) AS inserted_ts,
            RECOVERY_TIMESTAMP
        FROM bot_alarm_log
        WHERE INSERTED_TIMESTAMP BETWEEN v_start AND v_end
          AND ALARM_CODE NOT IN ('12')
          AND RECOVERY_TIMESTAMP IS NOT NULL
        GROUP BY BOT_ID, RECOVERY_TIMESTAMP
    ) x
    GROUP BY BOT_ID;

    CREATE INDEX ix_tmp_alarm_bot_sum_1 ON tmp_alarm_bot_sum (BOT_ID);


    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_log;
    CREATE TEMPORARY TABLE tmp_res_log
    AS
    SELECT
        BOT_ID, TYPE, IS_BUFFER, INSERTED_TIMESTAMP, LOGGED_TIMESTAMP, DESTINATION_ID
    FROM subcontroller_reservations_master_log
    WHERE INSERTED_TIMESTAMP BETWEEN v_start AND v_end;

    CREATE INDEX ix_tmp_res_log_1 ON tmp_res_log (BOT_ID, INSERTED_TIMESTAMP);
    CREATE INDEX ix_tmp_res_log_2 ON tmp_res_log (TYPE, IS_BUFFER);

    
    DROP TEMPORARY TABLE IF EXISTS tmp_res_seq;
    CREATE TEMPORARY TABLE tmp_res_seq
    AS
    SELECT
        BOT_ID,
        TYPE,
        IS_BUFFER,
        INSERTED_TIMESTAMP,
        LOGGED_TIMESTAMP,
        DESTINATION_ID,
        LEAD(INSERTED_TIMESTAMP) OVER (PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS next_inserted_ts,
        LEAD(IS_BUFFER)          OVER (PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS next_is_buffer,
        LEAD(DESTINATION_ID)     OVER (PARTITION BY BOT_ID ORDER BY INSERTED_TIMESTAMP) AS next_destination_id
    FROM tmp_res_log;

    CREATE INDEX ix_tmp_res_seq_1 ON tmp_res_seq (BOT_ID);

    
    DROP TEMPORARY TABLE IF EXISTS tmp_wait_bot_sum;
    CREATE TEMPORARY TABLE tmp_wait_bot_sum
    AS
    SELECT
        BOT_ID,
        SUM(CASE
              WHEN TYPE IN ('HOME','STATION_HOME') AND IS_BUFFER=0 AND next_inserted_ts IS NOT NULL
              THEN TIMESTAMPDIFF(SECOND, INSERTED_TIMESTAMP, next_inserted_ts) ELSE 0 END
        ) AS sec_wait_buf0,

        SUM(CASE
              WHEN TYPE IN ('HOME','STATION_HOME') AND IS_BUFFER=1 AND next_is_buffer=0 AND next_inserted_ts IS NOT NULL
              THEN TIMESTAMPDIFF(SECOND, INSERTED_TIMESTAMP, next_inserted_ts) ELSE 0 END
        ) AS sec_wait_buf1_station_home,

        SUM(CASE
              WHEN TYPE IN ('HOME') AND IS_BUFFER=1 AND next_is_buffer=0 AND next_inserted_ts IS NOT NULL
              THEN TIMESTAMPDIFF(SECOND, INSERTED_TIMESTAMP, next_inserted_ts) ELSE 0 END
        ) AS sec_bot_at_home
    FROM tmp_res_seq
    GROUP BY BOT_ID;

    CREATE INDEX ix_tmp_wait_bot_sum_1 ON tmp_wait_bot_sum (BOT_ID);

    
    DROP TEMPORARY TABLE IF EXISTS tmp_home_to_maint_bot_sum;
    CREATE TEMPORARY TABLE tmp_home_to_maint_bot_sum
    AS
    SELECT
        r.BOT_ID,
        SUM(CASE
              WHEN r.TYPE='HOME'
               AND r.IS_BUFFER=1
               AND r.next_destination_id IS NOT NULL
               AND lm.TYPE LIKE '%MAINTENANCE%'
               AND r.next_inserted_ts IS NOT NULL
              THEN TIMESTAMPDIFF(SECOND, r.LOGGED_TIMESTAMP, r.next_inserted_ts) ELSE 0 END
        ) AS sec_home_to_maint
    FROM tmp_res_seq r
    INNER JOIN location_master lm
        ON lm.LOCATION_ID = r.next_destination_id
    GROUP BY r.BOT_ID;

    CREATE INDEX ix_tmp_home_to_maint_bot_sum_1 ON tmp_home_to_maint_bot_sum (BOT_ID);


    
    DROP TEMPORARY TABLE IF EXISTS tmp_steps;
    CREATE TEMPORARY TABLE tmp_steps
    AS
    SELECT
        S.BOT_ID,
        S.IS_COMPLETED_TIMESTAMP,
        LM.TYPE,
        LEAD(LM.TYPE) OVER (PARTITION BY S.BOT_ID ORDER BY S.IS_COMPLETED_TIMESTAMP) AS next_type,
        LEAD(S.IS_COMPLETED_TIMESTAMP) OVER (PARTITION BY S.BOT_ID ORDER BY S.IS_COMPLETED_TIMESTAMP) AS next_ts
    FROM steps_archive S
    INNER JOIN location_master LM
        ON LM.X=S.X AND LM.Y=S.Y AND LM.Z=S.Z
    WHERE S.IS_COMPLETED_TIMESTAMP BETWEEN v_start AND v_end
      AND LM.TYPE IN ('STATION_ENTRY','STATION');

    CREATE INDEX ix_tmp_steps_1 ON tmp_steps (BOT_ID);

    DROP TEMPORARY TABLE IF EXISTS tmp_station_bot_sum;
    CREATE TEMPORARY TABLE tmp_station_bot_sum
    AS
    SELECT
        BOT_ID,
        SUM(CASE
              WHEN TYPE='STATION_ENTRY' AND next_type='STATION' AND next_ts IS NOT NULL
              THEN TIMESTAMPDIFF(SECOND, IS_COMPLETED_TIMESTAMP, next_ts) ELSE 0 END
        ) AS sec_station_raw
    FROM tmp_steps
    GROUP BY BOT_ID;

    CREATE INDEX ix_tmp_station_bot_sum_1 ON tmp_station_bot_sum (BOT_ID);


    
    SELECT
        BM.BOT_ID,

        
        ROUND(
            (24*60) - IFNULL( (IFNULL(t.sec_task_all,0) / 60), 0 ),
            2
        ) AS `NO TASK`,

        ROUND(IFNULL(a.sec_alarm,0)/60, 2) AS `ERROR TIME`,

        
        ROUND(
            IFNULL(o.sec_obs_charging,0)
          + IFNULL(o.sec_obs_station_entry,0)
          + IFNULL(o.sec_obs_maintenance_pick,0)
          + IFNULL(o.sec_obs_other,0)
        / 60, 2) AS `OBSTACLE TIME>1 MINUTE`,

        
        CASE
            WHEN ((IFNULL(w.sec_bot_at_home,0) - IFNULL(a.sec_alarm,0))/60) > 1
            THEN ROUND((IFNULL(w.sec_bot_at_home,0) - IFNULL(a.sec_alarm,0))/60, 2)
            ELSE 0
        END AS `BOT_AT_HOME>1 MINUTE`,

        
        ROUND(
            CASE WHEN IFNULL(s.sec_station_raw,0) > 15 THEN IFNULL(s.sec_station_raw,0) ELSE 0 END
        / 60, 2) AS `BOT AT STATION >15 SEC`,

        ROUND(IFNULL(h.sec_home_to_maint,0)/60, 2) AS BOT_HOME_TO_MAINTENANCE

    FROM bot_master BM
    LEFT JOIN tmp_task_bot_sum t ON t.BOT_ID = BM.BOT_ID
    LEFT JOIN tmp_obstacle_bot_sum o ON o.BOT_ID = BM.BOT_ID
    LEFT JOIN tmp_alarm_bot_sum a ON a.BOT_ID = BM.BOT_ID
    LEFT JOIN tmp_wait_bot_sum w ON w.BOT_ID = BM.BOT_ID
    LEFT JOIN tmp_home_to_maint_bot_sum h ON h.BOT_ID = BM.BOT_ID
    LEFT JOIN tmp_station_bot_sum s ON s.BOT_ID = BM.BOT_ID
    ORDER BY BM.BOT_ID;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_EACHES_PER_BIN_PRESENTATION_AVG_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_EACHES_PER_BIN_PRESENTATION_AVG_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_EACHES_PER_BIN_PRESENTATION_AVG_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    all_datas AS (
        SELECT
            STATION_ID,
            MIN(PICK_START_TIMESTAMP) AS CUR_TIMESTAMP,     
            SUM(PICKED_QUANTITY)      AS DATA_QUANTUM       
        FROM pick_wave_order_master
        WHERE PICK_START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_BIN_ID, STATION_ID
        HAVING CUR_TIMESTAMP IS NOT NULL AND DATA_QUANTUM > 0
        UNION ALL
        SELECT
            STATION_ID,
            MIN(PICK_START_TIMESTAMP) AS CUR_TIMESTAMP,
            SUM(PICKED_QUANTITY)      AS DATA_QUANTUM
        FROM pick_wave_order_master_archive
        WHERE PICK_START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_BIN_ID, STATION_ID
        HAVING CUR_TIMESTAMP IS NOT NULL AND DATA_QUANTUM > 0
    ),
    stations AS (
        SELECT STATION_ID FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.CUR_TIMESTAMP) AS hr,
            SUM(d.DATA_QUANTUM)/COUNT(d.DATA_QUANTUM) AS avg_eaches
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.CUR_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.avg_eaches END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.avg_eaches END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.avg_eaches END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.avg_eaches END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.avg_eaches END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.avg_eaches END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.avg_eaches END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.avg_eaches END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.avg_eaches END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.avg_eaches END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.avg_eaches END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.avg_eaches END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.avg_eaches END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.avg_eaches END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.avg_eaches END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.avg_eaches END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.avg_eaches END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.avg_eaches END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.avg_eaches END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.avg_eaches END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.avg_eaches END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.avg_eaches END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.avg_eaches END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.avg_eaches END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_EMAIL_CONFIG_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_EMAIL_CONFIG_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_EMAIL_CONFIG_GET`()
BEGIN
  
  SELECT KEY_NAME, KEY_VALUE
  FROM master_config
  WHERE KEY_NAME IN (
    'FALCON_LINK_WEBSITE',
    'FALCON_LOGO_URL',
    'FALCON_FULL_NAME',
    'LOCATION_NAME',
    'LOCATION_ID',
    'TOOL_NUMBER',
    'SMTP_SERVER',
    'SMTP_PORT',
    'SMTP_USERNAME',
    'SMTP_PASSWORD'
  ) AND IS_ACTIVE = 1
  ORDER BY KEY_NAME;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_EMAIL_RECIPIENT_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_EMAIL_RECIPIENT_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_EMAIL_RECIPIENT_GET`(
    IN p_email_id INT
)
BEGIN
    SELECT
        esrm_rec.RECIPIENT_TYPE,
        esrm_rec.RECIPIENT_EMAIL     
    FROM
        email_service_recipient_master AS esrm_rec
        LEFT JOIN email_service_runtime_master AS esrm_run
            ON esrm_run.EMAIL_MASTER_ID = esrm_rec.EMAIL_ID
    WHERE
        esrm_run.EMAIL_MASTER_ID = p_email_id
        AND esrm_run.IS_ACTIVE = 1
        AND esrm_rec.IS_ACTIVE = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_EMAIL_REPORT_CONFIG_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_EMAIL_REPORT_CONFIG_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_EMAIL_REPORT_CONFIG_GET`(
 IN p_email_id INT
)
BEGIN
    SELECT 
        NAME, SP_NAME, MODEL_NAME, INCLUDE_CSV, PARAMETERS_JSON
    FROM 
        email_service_report_master
    WHERE 
    EMAIL_ID = p_email_id AND
        IS_ACTIVE = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_EMAIL_RUNTIMES_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_EMAIL_RUNTIMES_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_EMAIL_RUNTIMES_GET`()
BEGIN
    
    SELECT
        EMAIL_MASTER_ID,
        EMAIL_TIME,
        EMAIL_TYPE,
        EMAIL_SUBJECT,
        ZIP_FILE_NAME
    FROM
        email_service_runtime_master
    WHERE
        IS_ACTIVE = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_LIVE_INVENTORY` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_LIVE_INVENTORY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_LIVE_INVENTORY`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    SELECT
        COUNT(DISTINCT lim.ARTICLE_ID) AS `DISTINCT_SKU`,
        SUM(lim.QUANTITY) AS `TOTAL_QUANTITY`,
        COUNT(DISTINCT lim.BIN_ID) AS `DISTINCT_BINS`,
        COUNT(DISTINCT lim.BIN_ID, COALESCE(lim.SEGMENT_NO, -1)) AS `DISTINCT_BIN_SEGMENT_PAIRS`
    FROM live_inventory_master AS lim
    WHERE lim.QUANTITY > 0;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_OPERATIONAL` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_OPERATIONAL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_OPERATIONAL`(
    IN p_start_date_time VARCHAR(50),
    IN p_end_date_time VARCHAR(50)
)
BEGIN
    WITH RelevantWaves AS (
        SELECT wave_id, wave_type
        FROM wave_master
        WHERE START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        
        UNION ALL
        
        SELECT wave_id, wave_type
        FROM wave_master_archive
        WHERE START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ),
    RelevantBins AS (
        SELECT tw.wave_type, tw.wave_id, pom.order_bin_id
        FROM put_wave_order_master pom
        INNER JOIN RelevantWaves tw ON pom.wave_id = tw.wave_id
        
        UNION 
        
        SELECT tw.wave_type, tw.wave_id, poma.order_bin_id
        FROM put_wave_order_master_archive poma
        INNER JOIN RelevantWaves tw ON poma.wave_id = tw.wave_id
        
        UNION 
        
        SELECT tw.wave_type, tw.wave_id, pickom.order_bin_id
        FROM pick_wave_order_master pickom
        INNER JOIN RelevantWaves tw ON pickom.wave_id = tw.wave_id
        
        UNION 
        
        SELECT tw.wave_type, tw.wave_id, pickoma.order_bin_id
        FROM pick_wave_order_master_archive pickoma
        INNER JOIN RelevantWaves tw ON pickoma.wave_id = tw.wave_id
    )
    
    SELECT
        rb.wave_type AS 'WAVE_TYPE',
        COUNT(DISTINCT rb.wave_id) AS 'TOTAL_WAVES',
        COUNT(DISTINCT obl.bot_id) AS 'TOTAL_BOTS',
        COUNT(DISTINCT obl.station_id) AS 'TOTAL_STATIONS'
    FROM RelevantBins rb
    INNER JOIN order_bin_mapping_log obl
        ON rb.order_bin_id = obl.order_bin_id
    GROUP BY rb.wave_type;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_OPERATOR_AVG_TIME_PER_HOUR_PER_STATION_PER_BIN` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_OPERATOR_AVG_TIME_PER_HOUR_PER_STATION_PER_BIN` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_OPERATOR_AVG_TIME_PER_HOUR_PER_STATION_PER_BIN`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    all_datas AS (
        SELECT 
            STATION_ID,
            TIMESTAMPDIFF(SECOND, MIN(PICK_START_TIMESTAMP), MAX(PICK_TIMESTAMP)) AS DATA_QUANTUM,
            MIN(PICK_START_TIMESTAMP) AS CUR_TIMESTAMP,
            MAX(PICK_TIMESTAMP) AS MAX_TIME
        FROM pick_wave_order_master
        WHERE PICK_START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_BIN_ID, STATION_ID
        HAVING CUR_TIMESTAMP IS NOT NULL 
           AND MAX_TIME IS NOT NULL
           AND DATA_QUANTUM <= 600
        UNION ALL
        SELECT 
            STATION_ID,
            TIMESTAMPDIFF(SECOND, MIN(PICK_START_TIMESTAMP), MAX(PICK_TIMESTAMP)) AS DATA_QUANTUM,
            MIN(PICK_START_TIMESTAMP) AS CUR_TIMESTAMP,
            MAX(PICK_TIMESTAMP) AS MAX_TIME
        FROM pick_wave_order_master_archive
        WHERE PICK_START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_BIN_ID, STATION_ID
        HAVING CUR_TIMESTAMP IS NOT NULL 
           AND MAX_TIME IS NOT NULL
           AND DATA_QUANTUM <= 600
    ),
    stations AS (
        SELECT STATION_ID
        FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.CUR_TIMESTAMP) AS hr,
            SUM(d.DATA_QUANTUM)/COUNT(d.DATA_QUANTUM)  AS avg_secs
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.CUR_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.avg_secs END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.avg_secs END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.avg_secs END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.avg_secs END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.avg_secs END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.avg_secs END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.avg_secs END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.avg_secs END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.avg_secs END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.avg_secs END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.avg_secs END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.avg_secs END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.avg_secs END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.avg_secs END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.avg_secs END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.avg_secs END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.avg_secs END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.avg_secs END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.avg_secs END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.avg_secs END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.avg_secs END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.avg_secs END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.avg_secs END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.avg_secs END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_ORDER_PER_SEGMENT_AVG_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_ORDER_PER_SEGMENT_AVG_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_ORDER_PER_SEGMENT_AVG_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    
    WITH all_datas AS (
        SELECT 
            STATION_ID,
            PICK_START_TIMESTAMP AS CUR_TIMESTAMP,
            COUNT(PICK_ORDER_ID) AS DATA_QUANTUM
        FROM pick_wave_order_master
        WHERE PICK_START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_BIN_ID, BIN_SEGMENT_NO
        HAVING CUR_TIMESTAMP IS NOT NULL
        UNION ALL
        SELECT 
            STATION_ID,
            PICK_START_TIMESTAMP AS CUR_TIMESTAMP,
            COUNT(PICK_ORDER_ID) AS DATA_QUANTUM
        FROM pick_wave_order_master_archive
        WHERE PICK_START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_BIN_ID, BIN_SEGMENT_NO
        HAVING CUR_TIMESTAMP IS NOT NULL
    ),
    stations AS (
        SELECT STATION_ID
        FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.CUR_TIMESTAMP) AS hr,
            SUM(d.DATA_QUANTUM) / COUNT(d.DATA_QUANTUM) AS total_qty
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.CUR_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.total_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.total_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.total_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.total_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.total_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.total_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.total_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.total_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.total_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.total_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.total_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.total_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.total_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.total_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.total_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.total_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.total_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.total_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.total_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.total_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.total_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.total_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.total_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.total_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_PICK_BIN_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_PICK_BIN_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_PICK_BIN_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    all_datas AS (
        SELECT pwom.STATION_ID, obm.ORDER_BIN_ID, obm.UPDATED_TIMESTAMP AS `PICK_TIMESTAMP`
        FROM pick_wave_order_master pwom
        JOIN order_bin_mapping_log obm 
        ON obm.ORDER_BIN_ID = pwom.ORDER_BIN_ID
        WHERE obm.UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        AND obm.STATUS = 'ON_STATION'
        GROUP BY obm.ORDER_BIN_ID, obm.UPDATED_TIMESTAMP
        UNION ALL
        SELECT pwom.STATION_ID, obm.ORDER_BIN_ID, obm.UPDATED_TIMESTAMP AS `PICK_TIMESTAMP`
        FROM pick_wave_order_master_archive pwom
        JOIN order_bin_mapping_log obm 
        ON obm.ORDER_BIN_ID = pwom.ORDER_BIN_ID
        WHERE obm.UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        AND obm.STATUS = 'ON_STATION'
        GROUP BY obm.ORDER_BIN_ID, obm.UPDATED_TIMESTAMP
    ),
    stations AS (
        SELECT STATION_ID
        FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.PICK_TIMESTAMP) AS hr,
            COUNT(DISTINCT(d.ORDER_BIN_ID)) AS total_qty
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.PICK_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.total_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.total_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.total_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.total_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.total_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.total_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.total_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.total_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.total_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.total_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.total_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.total_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.total_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.total_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.total_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.total_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.total_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.total_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.total_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.total_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.total_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.total_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.total_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.total_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_PICK_BIN_SEGMENT_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_PICK_BIN_SEGMENT_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_PICK_BIN_SEGMENT_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    all_datas AS (
        SELECT STATION_ID, CONCAT(BIN_ID,'-',`BIN_SEGMENT_NO`,'-',`PICK_START_TIMESTAMP`) AS 'BIN', PICK_TIMESTAMP
        FROM pick_wave_order_master
        WHERE PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT STATION_ID, CONCAT(BIN_ID,'-',`BIN_SEGMENT_NO`,'-',`PICK_START_TIMESTAMP`) AS 'BIN', PICK_TIMESTAMP
        FROM pick_wave_order_master_archive
        WHERE PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ),
    stations AS (
        SELECT STATION_ID
        FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.PICK_TIMESTAMP) AS hr,
            COUNT(DISTINCT(d.BIN)) AS total_qty
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.PICK_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.total_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.total_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.total_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.total_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.total_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.total_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.total_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.total_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.total_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.total_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.total_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.total_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.total_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.total_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.total_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.total_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.total_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.total_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.total_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.total_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.total_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.total_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.total_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.total_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_PICK_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_PICK_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_PICK_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    all_datas AS (
        SELECT STATION_ID, PICKED_QUANTITY, PICK_TIMESTAMP
        FROM pick_wave_order_master
        WHERE PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT STATION_ID, PICKED_QUANTITY, PICK_TIMESTAMP
        FROM pick_wave_order_master_archive
        WHERE PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ),
    stations AS (
        SELECT STATION_ID
        FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.PICK_TIMESTAMP) AS hr,
            SUM(d.PICKED_QUANTITY) AS total_qty
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.PICK_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.total_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.total_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.total_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.total_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.total_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.total_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.total_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.total_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.total_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.total_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.total_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.total_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.total_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.total_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.total_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.total_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.total_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.total_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.total_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.total_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.total_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.total_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.total_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.total_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_PUT_BIN_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_PUT_BIN_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_PUT_BIN_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    all_datas AS (
        SELECT pwom.STATION_ID, obm.ORDER_BIN_ID, obm.UPDATED_TIMESTAMP AS `PUT_TIMESTAMP`
        FROM put_wave_order_master pwom
        JOIN order_bin_mapping_log obm 
        ON obm.ORDER_BIN_ID = pwom.ORDER_BIN_ID
        WHERE obm.UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        AND obm.STATUS = 'ON_STATION'
        GROUP BY obm.ORDER_BIN_ID, obm.UPDATED_TIMESTAMP
        UNION ALL
         SELECT pwom.STATION_ID, obm.ORDER_BIN_ID, obm.UPDATED_TIMESTAMP AS `PUT_TIMESTAMP`
        FROM put_wave_order_master_archive pwom
        JOIN order_bin_mapping_log obm 
        ON obm.ORDER_BIN_ID = pwom.ORDER_BIN_ID
        WHERE obm.UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        AND obm.STATUS = 'ON_STATION'
        GROUP BY obm.ORDER_BIN_ID, obm.UPDATED_TIMESTAMP
    ),
    stations AS (
        SELECT STATION_ID
        FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.PUT_TIMESTAMP) AS hr,
            COUNT(DISTINCT(d.ORDER_BIN_ID)) AS total_qty
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.PUT_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.total_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.total_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.total_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.total_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.total_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.total_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.total_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.total_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.total_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.total_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.total_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.total_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.total_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.total_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.total_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.total_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.total_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.total_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.total_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.total_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.total_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.total_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.total_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.total_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_PUT_BIN_SEGMENT_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_PUT_BIN_SEGMENT_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_PUT_BIN_SEGMENT_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    all_datas AS (
        SELECT STATION_ID, CONCAT(BIN_ID,'-',`BIN_SEGMENT_NO`,'-',`PUT_START_TIMESTAMP`) AS 'BIN', PUT_TIMESTAMP
        FROM put_wave_order_master
        WHERE PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT STATION_ID, CONCAT(BIN_ID,'-',`BIN_SEGMENT_NO`,'-',`PUT_START_TIMESTAMP`) AS 'BIN', PUT_TIMESTAMP
        FROM put_wave_order_master_archive
        WHERE PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ),
    stations AS (
        SELECT STATION_ID
        FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.PUT_TIMESTAMP) AS hr,
            COUNT(DISTINCT(d.BIN)) AS total_qty
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.PUT_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.total_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.total_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.total_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.total_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.total_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.total_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.total_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.total_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.total_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.total_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.total_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.total_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.total_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.total_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.total_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.total_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.total_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.total_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.total_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.total_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.total_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.total_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.total_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.total_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_PUT_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_PUT_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_PUT_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    all_datas AS (
        SELECT STATION_ID, PUT_QUANTITY, PUT_TIMESTAMP
        FROM put_wave_order_master
        WHERE PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT STATION_ID, PUT_QUANTITY, PUT_TIMESTAMP
        FROM put_wave_order_master_archive
        WHERE PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ),
    stations AS (
        SELECT STATION_ID
        FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.PUT_TIMESTAMP) AS hr,
            SUM(d.PUT_QUANTITY) AS total_qty
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.PUT_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.total_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.total_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.total_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.total_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.total_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.total_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.total_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.total_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.total_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.total_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.total_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.total_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.total_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.total_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.total_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.total_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.total_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.total_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.total_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.total_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.total_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.total_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.total_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.total_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_SKU_BIN_PRESENTATION_AVG_PER_HOUR_PER_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_SKU_BIN_PRESENTATION_AVG_PER_HOUR_PER_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_SKU_BIN_PRESENTATION_AVG_PER_HOUR_PER_STATION`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    WITH
    all_datas AS (
        SELECT 
            STATION_ID,
            
            MIN(PICK_START_TIMESTAMP) AS CUR_TIMESTAMP,
            COUNT(DISTINCT BATCH_ID)   AS DATA_QUANTUM
        FROM pick_wave_order_master
        WHERE PICK_START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_BIN_ID, STATION_ID
        HAVING CUR_TIMESTAMP IS NOT NULL
        UNION ALL
        SELECT 
            STATION_ID,
            MIN(PICK_START_TIMESTAMP) AS CUR_TIMESTAMP,
            COUNT(DISTINCT BATCH_ID)   AS DATA_QUANTUM
        FROM pick_wave_order_master_archive
        WHERE PICK_START_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_BIN_ID, STATION_ID
        HAVING CUR_TIMESTAMP IS NOT NULL
    ),
    stations AS (
        SELECT STATION_ID
        FROM hw_station_master
    ),
    agg AS (
        SELECT
            d.STATION_ID,
            HOUR(d.CUR_TIMESTAMP) AS hr,
            SUM(d.DATA_QUANTUM)/COUNT(d.DATA_QUANTUM)  AS avg_qty
        FROM all_datas d
        GROUP BY d.STATION_ID, HOUR(d.CUR_TIMESTAMP)
    )
    SELECT
        CAST(s.STATION_ID AS CHAR) AS STATION_ID,
        COALESCE(SUM(CASE WHEN a.hr =  0 THEN a.avg_qty END), 0) AS `H00`,
        COALESCE(SUM(CASE WHEN a.hr =  1 THEN a.avg_qty END), 0) AS `H01`,
        COALESCE(SUM(CASE WHEN a.hr =  2 THEN a.avg_qty END), 0) AS `H02`,
        COALESCE(SUM(CASE WHEN a.hr =  3 THEN a.avg_qty END), 0) AS `H03`,
        COALESCE(SUM(CASE WHEN a.hr =  4 THEN a.avg_qty END), 0) AS `H04`,
        COALESCE(SUM(CASE WHEN a.hr =  5 THEN a.avg_qty END), 0) AS `H05`,
        COALESCE(SUM(CASE WHEN a.hr =  6 THEN a.avg_qty END), 0) AS `H06`,
        COALESCE(SUM(CASE WHEN a.hr =  7 THEN a.avg_qty END), 0) AS `H07`,
        COALESCE(SUM(CASE WHEN a.hr =  8 THEN a.avg_qty END), 0) AS `H08`,
        COALESCE(SUM(CASE WHEN a.hr =  9 THEN a.avg_qty END), 0) AS `H09`,
        COALESCE(SUM(CASE WHEN a.hr = 10 THEN a.avg_qty END), 0) AS `H10`,
        COALESCE(SUM(CASE WHEN a.hr = 11 THEN a.avg_qty END), 0) AS `H11`,
        COALESCE(SUM(CASE WHEN a.hr = 12 THEN a.avg_qty END), 0) AS `H12`,
        COALESCE(SUM(CASE WHEN a.hr = 13 THEN a.avg_qty END), 0) AS `H13`,
        COALESCE(SUM(CASE WHEN a.hr = 14 THEN a.avg_qty END), 0) AS `H14`,
        COALESCE(SUM(CASE WHEN a.hr = 15 THEN a.avg_qty END), 0) AS `H15`,
        COALESCE(SUM(CASE WHEN a.hr = 16 THEN a.avg_qty END), 0) AS `H16`,
        COALESCE(SUM(CASE WHEN a.hr = 17 THEN a.avg_qty END), 0) AS `H17`,
        COALESCE(SUM(CASE WHEN a.hr = 18 THEN a.avg_qty END), 0) AS `H18`,
        COALESCE(SUM(CASE WHEN a.hr = 19 THEN a.avg_qty END), 0) AS `H19`,
        COALESCE(SUM(CASE WHEN a.hr = 20 THEN a.avg_qty END), 0) AS `H20`,
        COALESCE(SUM(CASE WHEN a.hr = 21 THEN a.avg_qty END), 0) AS `H21`,
        COALESCE(SUM(CASE WHEN a.hr = 22 THEN a.avg_qty END), 0) AS `H22`,
        COALESCE(SUM(CASE WHEN a.hr = 23 THEN a.avg_qty END), 0) AS `H23`
    FROM stations s
    LEFT JOIN agg a ON a.STATION_ID = s.STATION_ID
    GROUP BY s.STATION_ID
    ORDER BY CAST(s.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_STATION_BEST_15MIN_X4_PER_HOUR` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_STATION_BEST_15MIN_X4_PER_HOUR` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_STATION_BEST_15MIN_X4_PER_HOUR`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_wave_order_bin;
    CREATE TEMPORARY TABLE tmp_wave_order_bin (
        order_bin_id BIGINT PRIMARY KEY
    ) ENGINE=InnoDB;

    INSERT IGNORE INTO tmp_wave_order_bin(order_bin_id)
    SELECT order_bin_id
    FROM pick_wave_order_master
    WHERE STATUS NOT IN ('PENDING')
      AND PICK_TIMESTAMP >= p_start_date_time AND PICK_TIMESTAMP < p_end_date_time;

    INSERT IGNORE INTO tmp_wave_order_bin(order_bin_id)
    SELECT order_bin_id
    FROM pick_wave_order_master_archive
    WHERE STATUS NOT IN ('PENDING')
      AND PICK_TIMESTAMP >= p_start_date_time AND PICK_TIMESTAMP < p_end_date_time;

    INSERT IGNORE INTO tmp_wave_order_bin(order_bin_id)
    SELECT order_bin_id
    FROM put_wave_order_master
    WHERE STATUS NOT IN ('PENDING')
      AND PUT_TIMESTAMP >= p_start_date_time AND PUT_TIMESTAMP < p_end_date_time;

    INSERT IGNORE INTO tmp_wave_order_bin(order_bin_id)
    SELECT order_bin_id
    FROM put_wave_order_master_archive
    WHERE STATUS NOT IN ('PENDING')
      AND PUT_TIMESTAMP >= p_start_date_time AND PUT_TIMESTAMP < p_end_date_time;

    WITH RECURSIVE
    PreOnAgg AS (
        SELECT
            l.ORDER_BIN_ID,
            l.BIN_ID,
            l.STATION_ID,
            MAX(l.UPDATED_TIMESTAMP) AS EVENT_TS
        FROM order_bin_mapping_log l
        JOIN tmp_wave_order_bin t
          ON t.order_bin_id = l.ORDER_BIN_ID
        WHERE l.TYPE   = 'RACK_PICK'
          AND l.STATUS = 'PRE_ON_STATION'
          AND l.UPDATED_TIMESTAMP >= p_start_date_time
          AND l.UPDATED_TIMESTAMP <  p_end_date_time
        GROUP BY l.ORDER_BIN_ID, l.BIN_ID, l.STATION_ID
    ),
    Events AS (
        SELECT
            STATION_ID,
            EVENT_TS,
            TIMESTAMP(DATE(EVENT_TS), MAKETIME(HOUR(EVENT_TS), 0, 0)) AS hour_start,
            HOUR(EVENT_TS)   AS hour_of_day,
            MINUTE(EVENT_TS) AS minute_of_hour
        FROM PreOnAgg
        WHERE STATION_ID IS NOT NULL AND EVENT_TS IS NOT NULL
    ),
    StationHourBlocks AS (
        SELECT DISTINCT STATION_ID, hour_start, hour_of_day
        FROM Events
    ),
    MinuteCounts AS (
        SELECT
            STATION_ID,
            hour_start,
            hour_of_day,
            minute_of_hour,
            COUNT(*) AS cnt
        FROM Events
        GROUP BY STATION_ID, hour_start, hour_of_day, minute_of_hour
    ),
    SeqMinute AS (
        SELECT 0 AS m
        UNION ALL
        SELECT m + 1 FROM SeqMinute WHERE m < 59
    ),
    MinuteGrid AS (
        SELECT
            shb.STATION_ID,
            shb.hour_start,
            shb.hour_of_day,
            sm.m AS minute_of_hour,
            COALESCE(mc.cnt, 0) AS cnt
        FROM StationHourBlocks shb
        CROSS JOIN SeqMinute sm
        LEFT JOIN MinuteCounts mc
          ON mc.STATION_ID = shb.STATION_ID
         AND mc.hour_start = shb.hour_start
         AND mc.minute_of_hour = sm.m
    ),
    Rolling AS (
        SELECT
            STATION_ID,
            hour_start,
            hour_of_day,
            minute_of_hour,
            SUM(cnt) OVER (
                PARTITION BY STATION_ID, hour_start
                ORDER BY minute_of_hour
                ROWS BETWEEN 14 PRECEDING AND CURRENT ROW
            ) AS roll15
        FROM MinuteGrid
    ),
    BestPerHourBlock AS (
        SELECT
            STATION_ID,
            hour_of_day,
            (MAX(roll15) * 4) AS best15_x4
        FROM Rolling
        WHERE minute_of_hour >= 14
        GROUP BY STATION_ID, hour_start, hour_of_day
    ),
    BestPerHourOfDay AS (
        SELECT
            STATION_ID,
            hour_of_day,
            MAX(best15_x4) AS best15_x4
        FROM BestPerHourBlock
        GROUP BY STATION_ID, hour_of_day
    )
    SELECT
        STATION_ID AS `STATION_ID`,
        SUM(CASE WHEN hour_of_day =  0 THEN best15_x4 ELSE 0 END) AS `H00`,
        SUM(CASE WHEN hour_of_day =  1 THEN best15_x4 ELSE 0 END) AS `H01`,
        SUM(CASE WHEN hour_of_day =  2 THEN best15_x4 ELSE 0 END) AS `H02`,
        SUM(CASE WHEN hour_of_day =  3 THEN best15_x4 ELSE 0 END) AS `H03`,
        SUM(CASE WHEN hour_of_day =  4 THEN best15_x4 ELSE 0 END) AS `H04`,
        SUM(CASE WHEN hour_of_day =  5 THEN best15_x4 ELSE 0 END) AS `H05`,
        SUM(CASE WHEN hour_of_day =  6 THEN best15_x4 ELSE 0 END) AS `H06`,
        SUM(CASE WHEN hour_of_day =  7 THEN best15_x4 ELSE 0 END) AS `H07`,
        SUM(CASE WHEN hour_of_day =  8 THEN best15_x4 ELSE 0 END) AS `H08`,
        SUM(CASE WHEN hour_of_day =  9 THEN best15_x4 ELSE 0 END) AS `H09`,
        SUM(CASE WHEN hour_of_day = 10 THEN best15_x4 ELSE 0 END) AS `H10`,
        SUM(CASE WHEN hour_of_day = 11 THEN best15_x4 ELSE 0 END) AS `H11`,
        SUM(CASE WHEN hour_of_day = 12 THEN best15_x4 ELSE 0 END) AS `H12`,
        SUM(CASE WHEN hour_of_day = 13 THEN best15_x4 ELSE 0 END) AS `H13`,
        SUM(CASE WHEN hour_of_day = 14 THEN best15_x4 ELSE 0 END) AS `H14`,
        SUM(CASE WHEN hour_of_day = 15 THEN best15_x4 ELSE 0 END) AS `H15`,
        SUM(CASE WHEN hour_of_day = 16 THEN best15_x4 ELSE 0 END) AS `H16`,
        SUM(CASE WHEN hour_of_day = 17 THEN best15_x4 ELSE 0 END) AS `H17`,
        SUM(CASE WHEN hour_of_day = 18 THEN best15_x4 ELSE 0 END) AS `H18`,
        SUM(CASE WHEN hour_of_day = 19 THEN best15_x4 ELSE 0 END) AS `H19`,
        SUM(CASE WHEN hour_of_day = 20 THEN best15_x4 ELSE 0 END) AS `H20`,
        SUM(CASE WHEN hour_of_day = 21 THEN best15_x4 ELSE 0 END) AS `H21`,
        SUM(CASE WHEN hour_of_day = 22 THEN best15_x4 ELSE 0 END) AS `H22`,
        SUM(CASE WHEN hour_of_day = 23 THEN best15_x4 ELSE 0 END) AS `H23`
    FROM BestPerHourOfDay
    GROUP BY STATION_ID
    ORDER BY STATION_ID;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_STATION_TO_STATION_BOT_TASKS_PERCENTAGE` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_STATION_TO_STATION_BOT_TASKS_PERCENTAGE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_STATION_TO_STATION_BOT_TASKS_PERCENTAGE`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    
    SELECT 
        CAST(tm.BOT_ID AS CHAR) AS BOT_ID,
        ROUND(
            100 * SUM(CASE WHEN tm.TASK_TYPE = 'STATION_TO_STATION' THEN 1 ELSE 0 END)
            / NULLIF(COUNT(tm.TASK_ID), 0), 2
        ) AS BOT_TASKS_PERCENTAGE,
        MAX(tm.LOGGED_TIMESTAMP) AS TIMESTAMP
    FROM task_master_log tm
    JOIN hw_station_master hsm 
      ON hsm.LOCATION_ID = tm.DESTINATION_LOCATION_ID
    WHERE tm.STATUS = 'COMPLETED'
      AND tm.TASK_TYPE IN ('BIN_STORE_TO_ZONE', 'STATION_TO_STATION')
      AND tm.LOGGED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    GROUP BY tm.BOT_ID
    ORDER BY CAST(tm.BOT_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_STATION_TO_STATION_TASKS_PERCENTAGE` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_STATION_TO_STATION_TASKS_PERCENTAGE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_STATION_TO_STATION_TASKS_PERCENTAGE`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    
    SELECT 
        CAST(hsm.STATION_ID AS CHAR) AS STATION_ID,
        ROUND(
            100 * SUM(CASE WHEN tm.TASK_TYPE = 'STATION_TO_STATION' THEN 1 ELSE 0 END)
            / NULLIF(COUNT(tm.TASK_ID), 0), 2
        ) AS TASKS_PERCENTAGE,            
        MAX(tm.LOGGED_TIMESTAMP)    AS TIMESTAMP 
    FROM task_master_log tm
    JOIN hw_station_master hsm 
      ON hsm.LOCATION_ID = tm.DESTINATION_LOCATION_ID
    WHERE tm.STATUS = 'COMPLETED'
      AND tm.TASK_TYPE IN ('BIN_STORE_TO_ZONE', 'STATION_TO_STATION')
      AND tm.LOGGED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    GROUP BY hsm.STATION_ID
    ORDER BY CAST(hsm.STATION_ID AS UNSIGNED);
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_WAVE_PICK_BIN_LEVEL_DATA` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_WAVE_PICK_BIN_LEVEL_DATA` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_WAVE_PICK_BIN_LEVEL_DATA`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format     VARCHAR(50);
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    WITH
    CombinedPickWave AS (
        SELECT
            PICK_ORDER_ID, WAVE_ID, ORDER_ID, ORDER_LINE_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO,
            SKU_ID, BATCH_ID, STATION_ID, EXPECTED_QUANTITY, PICKED_QUANTITY, SHORT_PICK_QUANTITY,
            PICK_START_TIMESTAMP, PICK_TIMESTAMP, PICK_BY
        FROM pick_wave_order_master
        WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED')
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
          AND PICKED_QUANTITY > 0
        UNION ALL
        SELECT
            PICK_ORDER_ID, WAVE_ID, ORDER_ID, ORDER_LINE_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO,
            SKU_ID, BATCH_ID, STATION_ID, EXPECTED_QUANTITY, PICKED_QUANTITY, SHORT_PICK_QUANTITY,
            PICK_START_TIMESTAMP, PICK_TIMESTAMP, PICK_BY
        FROM pick_wave_order_master_archive
        WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED')
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
          AND PICKED_QUANTITY > 0
    ),
    CombinedMappingLog AS (
        SELECT
            ORDER_BIN_ID, BIN_ID, STATION_ID,
            MAX(CASE WHEN STATUS = 'BIN_PICKED'     THEN BOT_ID            END) AS TASK_ALLOCATED_BOT_ID,
            MAX(CASE WHEN STATUS = 'PRE_ON_STATION' THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
            MAX(CASE WHEN STATUS = 'ON_STATION'     THEN UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
        FROM order_bin_mapping_log
        WHERE TYPE = 'RACK_PICK'
          AND ORDER_BIN_ID IN (SELECT DISTINCT ORDER_BIN_ID FROM CombinedPickWave)
        GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID
    ),
    BatchPickDetails AS (
        SELECT DISTINCT BATCH_PICKLIST_CODE, PARENT_ORDER_ID
        FROM wms_to_wcs_order_level_pre_staged_data
        WHERE PARENT_ORDER_ID IN (SELECT DISTINCT ORDER_ID FROM CombinedPickWave)
    )
    SELECT
        cpw.WAVE_ID                                AS `WAVE ID`,
        cpw.STATION_ID                             AS `STATION ID`,
        bpd.BATCH_PICKLIST_CODE                    AS `BATCH PICKLIST CODE`,
        cpw.ORDER_ID                               AS `ORDER ID`,
        cpw.SKU_ID                                 AS `SKU ID`,
        cpw.BIN_ID                                 AS `BIN ID`,
        cpw.BIN_SEGMENT_NO                         AS `BIN SEGMENT NO`,
        sbm.MRP                                    AS `MRP`,
        DATE_FORMAT(sbm.EXPIRY_DATE, v_date_format)            AS `EXPIRY`,
        cpw.EXPECTED_QUANTITY                      AS `EXPECTED QUANTITY`,
        cpw.PICKED_QUANTITY                        AS `PICKED QUANTITY`,
        cpw.SHORT_PICK_QUANTITY                    AS `SHORT PICK QUANTITY`,
        DATE_FORMAT(cml.ON_STATION_TIMESTAMP,  v_datetime_format) AS `ON STATION TIME`,
        DATE_FORMAT(cpw.PICK_START_TIMESTAMP,  v_datetime_format) AS `PICK STARTED TIME`,
        DATE_FORMAT(cpw.PICK_TIMESTAMP,        v_datetime_format) AS `PICK END TIME`,
        TIMESTAMPDIFF(SECOND, cpw.PICK_START_TIMESTAMP, cpw.PICK_TIMESTAMP) AS `DIFFERENCE (IN SECS)`,
        cpw.PICK_BY                                AS `PICK BY`,
        cml.TASK_ALLOCATED_BOT_ID                  AS `BIN PUT BOT ID`,
        DATE_FORMAT(cml.PRE_ON_STATION_TIMESTAMP, v_datetime_format) AS `BIN PUT TIME`
    FROM CombinedPickWave cpw
    JOIN CombinedMappingLog cml ON cpw.ORDER_BIN_ID = cml.ORDER_BIN_ID
    JOIN sku_batch_master sbm   ON cpw.BATCH_ID     = sbm.BATCH_ID
    JOIN BatchPickDetails bpd   ON cpw.ORDER_ID     = bpd.PARENT_ORDER_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_WAVE_PUT_BIN_LEVEL_DATA` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_WAVE_PUT_BIN_LEVEL_DATA` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_WAVE_PUT_BIN_LEVEL_DATA`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format     VARCHAR(50);
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    WITH
    CombinedPutWave AS (
        SELECT
            WAVE_ID,
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            SKU_ID,
            BATCH_ID,
            ORDER_BIN_ID,
            BIN_ID,
            BIN_SEGMENT_NO,
            STATION_ID,
            EXPECTED_QUANTITY,
            PUT_QUANTITY,
            SHORT_PUT_QUANTITY,
            PUT_START_TIMESTAMP,
            PUT_TIMESTAMP,
            PUT_BY
        FROM put_wave_order_master
        WHERE PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
          AND PUT_QUANTITY > 0
          AND STATUS NOT IN ('PENDING','PUT_STARTED')
        UNION ALL
        SELECT
            WAVE_ID,
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            SKU_ID,
            BATCH_ID,
            ORDER_BIN_ID,
            BIN_ID,
            BIN_SEGMENT_NO,
            STATION_ID,
            EXPECTED_QUANTITY,
            PUT_QUANTITY,
            SHORT_PUT_QUANTITY,
            PUT_START_TIMESTAMP,
            PUT_TIMESTAMP,
            PUT_BY
        FROM put_wave_order_master_archive
        WHERE PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
          AND PUT_QUANTITY > 0
          AND STATUS NOT IN ('PENDING','PUT_STARTED')
    ),
    order_bins AS (
        SELECT DISTINCT ORDER_BIN_ID
        FROM CombinedPutWave
    ),
    CombinedMappingLog AS (
        SELECT
            obml.ORDER_BIN_ID,
            obml.BIN_ID,
            obml.STATION_ID,
            MAX(CASE WHEN obml.STATUS = 'BIN_PICKED'   THEN obml.BOT_ID END)           AS TASK_ALLOCATED_BOT_ID,
            MAX(CASE WHEN obml.STATUS = 'PRE_ON_STATION' THEN obml.UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
            MAX(CASE WHEN obml.STATUS = 'ON_STATION'     THEN obml.UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
        FROM order_bin_mapping_log obml
        INNER JOIN order_bins ob
                ON ob.ORDER_BIN_ID = obml.ORDER_BIN_ID
        WHERE obml.TYPE = 'RACK_PICK'
        GROUP BY obml.ORDER_BIN_ID, obml.BIN_ID, obml.STATION_ID
    )
    SELECT
        b.WAVE_ID                                  AS `WAVE ID`,
        b.STATION_ID                                AS `STATION ID`,
        b.STORAGE_REQUEST_ID                        AS `STORAGE REQUEST ID`,
        b.SKU_ID                                    AS `SKU ID`,
        b.BIN_ID                                    AS `BIN ID`,
        b.BIN_SEGMENT_NO                            AS `BIN SEGMENT NO`,
        sbm.mrp                                     AS `MRP`,
        DATE_FORMAT(sbm.expiry_date, v_date_format) AS `EXPIRY`,
        b.EXPECTED_QUANTITY                         AS `EXPECTED QUANTITY`,
        b.PUT_QUANTITY                              AS `PUT QUANTITY`,
        b.SHORT_PUT_QUANTITY                        AS `SHORT PUT QUANTITY`,
        DATE_FORMAT(o.ON_STATION_TIMESTAMP,  v_datetime_format) AS `ON STATION TIME`,
        DATE_FORMAT(b.PUT_START_TIMESTAMP,   v_datetime_format) AS `PUT STARTED TIME`,
        DATE_FORMAT(b.PUT_TIMESTAMP,         v_datetime_format) AS `PUT COMPLETED TIME`,
        TIMESTAMPDIFF(SECOND, b.PUT_START_TIMESTAMP, b.PUT_TIMESTAMP) AS `DIFFERENCE (IN SECS)`,
        b.PUT_BY                                    AS `PUT BY`,
        o.TASK_ALLOCATED_BOT_ID                     AS `BIN PUT BOT ID`,
        DATE_FORMAT(o.PRE_ON_STATION_TIMESTAMP, v_datetime_format) AS `BIN PUT TIME`
    FROM CombinedPutWave b
    INNER JOIN CombinedMappingLog o
            ON b.ORDER_BIN_ID = o.ORDER_BIN_ID
           AND b.BIN_ID       = o.BIN_ID
           AND b.STATION_ID   = o.STATION_ID
    LEFT JOIN sku_batch_master sbm
           ON b.BATCH_ID = sbm.BATCH_ID
    ORDER BY b.WAVE_ID, b.STATION_ID, b.BIN_ID, b.BIN_SEGMENT_NO;
END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_WMS_API_ERROR_COUNT` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_WMS_API_ERROR_COUNT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_WMS_API_ERROR_COUNT`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN

    SELECT
        am.API_ALIAS_NAME,
        wtwp.HTTP_STATUS,
        COUNT(*) AS FAILURES,
        DATE_FORMAT(MIN(wtwp.INSERTED_TIMESTAMP), DSB_GET_DATE_FORMAT('dateTime')) AS `FIRST_FAILURE_TIME`,
        DATE_FORMAT(MAX(wtwp.INSERTED_TIMESTAMP), DSB_GET_DATE_FORMAT('dateTime')) AS `LAST_FAILURE_TIME`
    FROM wcs_to_wms_payload wtwp
    LEFT JOIN api_master am 
        ON am.API_ID = wtwp.API_ID
    WHERE wtwp.HTTP_STATUS <> 200
      AND wtwp.INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    GROUP BY 
        am.API_ALIAS_NAME, 
        wtwp.HTTP_STATUS
    ORDER BY 
        MAX(wtwp.INSERTED_TIMESTAMP) DESC;

END */$$
DELIMITER ;

/* Procedure structure for procedure `ES_WMS_API_ERROR_LIST` */

/*!50003 DROP PROCEDURE IF EXISTS  `ES_WMS_API_ERROR_LIST` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `ES_WMS_API_ERROR_LIST`(
    IN p_start_date_time DATETIME,
    IN p_end_date_time   DATETIME
)
BEGIN

    SELECT
      am.API_ALIAS_NAME,
      wtwp.PAYLOAD_ID,
      wtwp.HTTP_STATUS,
      wtwp.JSON_REQUEST,
      wtwp.JSON_RESPONSE,
      wtwp.INSERTED_TIMESTAMP
  FROM wcs_to_wms_payload wtwp
  LEFT JOIN api_master am ON am.API_ID = wtwp.API_ID
  WHERE wtwp.HTTP_STATUS <> 200
    AND wtwp.INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
  ORDER BY wtwp.INSERTED_TIMESTAMP DESC;

END */$$
DELIMITER ;

/* Procedure structure for procedure `FMS_BOT_ALLOCATION_FOR_STATION_V1` */

/*!50003 DROP PROCEDURE IF EXISTS  `FMS_BOT_ALLOCATION_FOR_STATION_V1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `FMS_BOT_ALLOCATION_FOR_STATION_V1`()
BEGIN
		DECLARE V_NoBot INT;
		DECLARE	V_AllocatedPBotsPerStation INT;
		DECLARE	V_PendingBots INT;
		DECLARE	V_PickStation INT;
		DECLARE	V_PutStation INT;
		DECLARE	V_ActiveStation INT;
		
		DROP TEMPORARY TABLE IF EXISTS tmp_wave_station_rule_mapping;
		CREATE TEMPORARY TABLE  tmp_wave_station_rule_mapping
		SELECT  * FROM wave_station_rule_mapping;
		
		DROP TEMPORARY TABLE IF EXISTS  tmp_wave_stationlist;
		CREATE TEMPORARY TABLE tmp_wave_stationlist(STATION_ID INT);
		INSERT INTO tmp_wave_stationlist(STATION_ID)
		SELECT WR.STATION_ID 
		FROM tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		WHERE W.WAVE_TYPE='PUT' AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE';
		
		SELECT  COUNT(`BOT_ID`)  FROM `bot_master` WHERE `AUTO_MANUAL`='auto' AND `STATUS`='ENABLED'
		INTO V_NoBot;
		
		SELECT  COUNT(`STATION_ID`) FROM `hw_station_master` WHERE `STATUS`='ENABLED' AND `WAVE_STATUS`='WAVE_LIVE'
		INTO V_ActiveStation;
		
		
		
		UPDATE tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON  HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		SET WR.`BOT_COUNT_CURRENT`=CASE  WHEN  FLOOR(V_NoBot/V_ActiveStation)>=
		CASE WHEN W.WAVE_TYPE='PUT' THEN `MIN_BOT_COUNT_PUT` ELSE `MIN_BOT_COUNT_PICK` END  THEN CASE WHEN W.WAVE_TYPE='PUT' THEN `MIN_BOT_COUNT_PUT` ELSE `MIN_BOT_COUNT_PICK` END ELSE 1 END 
		WHERE  W.WAVE_TYPE IN ('PICK','PUT') AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE';	
		
		SELECT (V_NoBot-SUM(BOT_COUNT_CURRENT)) FROM tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON  HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		WHERE  W.WAVE_TYPE IN ('PICK','PUT') AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE'
		INTO V_PendingBots;
		
		SELECT  COUNT(HS.`STATION_ID`) FROM  tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON  HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		WHERE W.WAVE_TYPE IN ('PICK') AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE'
		INTO V_PickStation;
		
		SET V_AllocatedPBotsPerStation=FLOOR(V_PendingBots/V_PickStation);
		
		UPDATE tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON  HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		SET WR.`BOT_COUNT_CURRENT`=
		CASE WHEN (WR.BOT_COUNT_CURRENT+V_AllocatedPBotsPerStation)<=`MIN_BOT_COUNT_PICK` THEN MIN_BOT_COUNT_PICK
		ELSE CASE WHEN (WR.BOT_COUNT_CURRENT+V_AllocatedPBotsPerStation)>=`MAX_BOT_COUNT_PICK` THEN  MAX_BOT_COUNT_PICK
		ELSE (WR.BOT_COUNT_CURRENT+V_AllocatedPBotsPerStation) END END
		WHERE  W.WAVE_TYPE IN ('PICK') AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE';		
		
		SELECT (V_NoBot-SUM(BOT_COUNT_CURRENT)) FROM tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON  HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		WHERE  W.WAVE_TYPE IN ('PICK','PUT') AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE'
		INTO V_PendingBots;			
		
		SELECT  COUNT(HS.`STATION_ID`) FROM  tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON  HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		WHERE W.WAVE_TYPE IN ('PUT') AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE'
		INTO V_PutStation;
		
		SET V_AllocatedPBotsPerStation=FLOOR(V_PendingBots/V_PutStation);
		
		UPDATE tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON  HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		SET WR.`BOT_COUNT_CURRENT`=
		CASE WHEN (WR.BOT_COUNT_CURRENT+V_AllocatedPBotsPerStation)<=`MIN_BOT_COUNT_PUT` THEN MIN_BOT_COUNT_PUT
		ELSE CASE WHEN (WR.BOT_COUNT_CURRENT+V_AllocatedPBotsPerStation)>=`MAX_BOT_COUNT_PUT` THEN  MAX_BOT_COUNT_PUT
		ELSE (WR.BOT_COUNT_CURRENT+V_AllocatedPBotsPerStation) END END
		WHERE  W.WAVE_TYPE IN ('PUT') AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE';
		
		SELECT (V_NoBot-SUM(BOT_COUNT_CURRENT)) FROM tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON  HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		WHERE  W.WAVE_TYPE IN ('PICK','PUT') AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE'
		INTO V_PendingBots;	
		
		IF V_PendingBots>0 THEN
			UPDATE tmp_wave_station_rule_mapping WR
			INNER JOIN (
					SELECT STATION_ID ,ROW_NUMBER() OVER(ORDER BY STATION_ID) AS SRank  
					FROM tmp_wave_stationlist
			 ) HS ON HS. STATION_ID=WR.STATION_ID
			INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
			SET WR.`BOT_COUNT_CURRENT`=
			CASE WHEN  (WR.BOT_COUNT_CURRENT+(CASE WHEN V_PendingBots>V_PutStation THEN FLOOR(V_PendingBots/V_PutStation) ELSE 1 END))>WR.UPPER_BOT_COUNT_PUT THEN WR.UPPER_BOT_COUNT_PUT
			ELSE (WR.BOT_COUNT_CURRENT+(CASE WHEN V_PendingBots>V_PutStation THEN FLOOR(V_PendingBots/V_PutStation) ELSE 1 END)) END 
			WHERE  W.WAVE_TYPE IN ('PUT') AND  HS.SRank<=V_PendingBots;
		END IF;
		SELECT  WR.WAVE_ID,W.WAVE_TYPE,WR.STATION_ID,WR.BOT_COUNT_CURRENT,WR.`BOT_COUNT_DEFAULT`,MAX_BOT_COUNT_PICK,MIN_BOT_COUNT_PICK,MAX_BOT_COUNT_PUT,MIN_BOT_COUNT_PUT,UPPER_BOT_COUNT_PUT
		FROM  tmp_wave_station_rule_mapping WR
		INNER JOIN hw_station_master HS ON  HS.STATION_ID=WR.STATION_ID
		INNER JOIN wave_master W  ON W.Wave_ID=WR.Wave_ID
		WHERE W.WAVE_TYPE IN ('PICK','PUT') AND HS.`STATUS`='ENABLED' AND HS.`WAVE_STATUS`='WAVE_LIVE';
	END */$$
DELIMITER ;

/* Procedure structure for procedure `GetAll1000sChunksAvgBinPPB_ByWave` */

/*!50003 DROP PROCEDURE IF EXISTS  `GetAll1000sChunksAvgBinPPB_ByWave` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `GetAll1000sChunksAvgBinPPB_ByWave`(
    IN in_wave_id VARCHAR(100)
)
BEGIN
    
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_station_id INT;
    DECLARE v_time DOUBLE;
    DECLARE v_bin_ppb DOUBLE;
    DECLARE total_time DOUBLE DEFAULT 0;
    DECLARE weighted_sum DOUBLE DEFAULT 0;
    DECLARE block_no INT DEFAULT 1;
    DECLARE station_list TEXT DEFAULT '';
    
    DECLARE cur CURSOR FOR 
        SELECT station_id, time_seconds, bin_presentation_per_bot 
        FROM temp_station_data;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    DROP TEMPORARY TABLE IF EXISTS temp_station_data;
    CREATE TEMPORARY TABLE temp_station_data (
        station_id INT,
        time_seconds DOUBLE,
        bin_presentation_per_bot DOUBLE
    );
    DROP TEMPORARY TABLE IF EXISTS result_blocks;
    CREATE TEMPORARY TABLE result_blocks (
        block_no INT,
        total_time DOUBLE,
        avg_bin_presentation_per_bot DOUBLE,
        station_ids TEXT
    );
    
    INSERT INTO temp_station_data (station_id, time_seconds, bin_presentation_per_bot)
    SELECT 
        s.station_id,
        ROUND(TIMESTAMPDIFF(SECOND, MIN(updated_timestamp), MAX(updated_timestamp)), 2) AS time_diff,
        (COUNT(DISTINCT bin_id)*3600 / 
         ROUND(TIMESTAMPDIFF(SECOND, MIN(updated_timestamp), MAX(updated_timestamp)), 2)) / 
         (SELECT BOT_COUNT_CURRENT FROM wave_station_rule_mapping WHERE station_id = s.station_id) AS bin_presentation_per_bot
    FROM stock_audit_wave_order_master s
    WHERE s.wave_id = in_wave_id 
      AND s.STATUS = 'AUDIT_COMPLETED'
    GROUP BY s.station_id
    ORDER BY bin_presentation_per_bot DESC;
    
    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_station_id, v_time, v_bin_ppb;
        IF done THEN
            IF total_time >= 1000 THEN
                INSERT INTO result_blocks (block_no, total_time, avg_bin_presentation_per_bot, station_ids)
                VALUES (block_no, total_time, ROUND(weighted_sum / total_time, 4), station_list);
            END IF;
            LEAVE read_loop;
        END IF;
        SET total_time = total_time + v_time;
        SET weighted_sum = weighted_sum + (v_time * v_bin_ppb);
        SET station_list = CONCAT_WS(' ', station_list, v_station_id);
        IF total_time >= 1000 THEN
            INSERT INTO result_blocks (block_no, total_time, avg_bin_presentation_per_bot, station_ids)
            VALUES (block_no, total_time, ROUND(weighted_sum / total_time, 4), station_list);
            
            SET block_no = block_no + 1;
            SET total_time = 0;
            SET weighted_sum = 0;
            SET station_list = '';
        END IF;
    END LOOP;
    CLOSE cur;
    
    SELECT * FROM result_blocks ORDER BY block_no;
END */$$
DELIMITER ;

/* Procedure structure for procedure `GetAllArticleMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `GetAllArticleMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `GetAllArticleMaster`()
BEGIN
		Select * from neo.article_master;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `GetAllLocationMaster` */

/*!50003 DROP PROCEDURE IF EXISTS  `GetAllLocationMaster` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `GetAllLocationMaster`()
BEGIN
		SELECT * from location_master;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `GetAllLocationMasterJson` */

/*!50003 DROP PROCEDURE IF EXISTS  `GetAllLocationMasterJson` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `GetAllLocationMasterJson`()
BEGIN
 
    SELECT JSON_ARRAYAGG(
        JSON_OBJECT(
            'LOCATION_ID', LOCATION_ID,
            'X', X,
            'Y', Y,
            'Z', Z,
            'TYPE', TYPE,
            'XP', XP,
            'XN', XN,
            'YP', YP,
            'YN', YN,
            'ZP', ZP,
            'ZN', ZN,
            'PROPERTY_DESCRIPTION', PROPERTY_DESCRIPTION,
            'IS_BARCODE', IS_BARCODE
        )
    ) 
    FROM location_master;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `GetBotIdByRecoveryBit` */

/*!50003 DROP PROCEDURE IF EXISTS  `GetBotIdByRecoveryBit` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `GetBotIdByRecoveryBit`()
BEGIN
    SELECT bot_id FROM `bot`.`bot_master` WHERE `recovery_bit` = '1';
END */$$
DELIMITER ;

/* Procedure structure for procedure `GetLocationIDWithLimitXY` */

/*!50003 DROP PROCEDURE IF EXISTS  `GetLocationIDWithLimitXY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `GetLocationIDWithLimitXY`(
	in Y INT,
	IN X int
    )
BEGIN
		select * from `location_master` where `TYPE` = 'RETURN_AISLE_ENTRY' and `Y`= y and `X` < x ORDER BY `X` LIMIT 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `GET_STATION_ID_FOR_LIVE_WAVE` */

/*!50003 DROP PROCEDURE IF EXISTS  `GET_STATION_ID_FOR_LIVE_WAVE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `GET_STATION_ID_FOR_LIVE_WAVE`(IN waveId VARCHAR(36))
BEGIN
    
    IF EXISTS (SELECT 1 FROM wave_master WHERE wave_id = waveId) THEN
        
        SELECT DISTINCT station_id 
        FROM `stock_audit_wave_order_master` 
        WHERE wave_id = waveId
        UNION
        SELECT DISTINCT station_id 
        FROM `put_wave_order_master` 
        WHERE wave_id = waveId
        UNION
        SELECT DISTINCT station_id 
        FROM `pick_wave_order_master` 
        WHERE wave_id = waveId;
   
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `Get_StoreToZone_TaskGap` */

/*!50003 DROP PROCEDURE IF EXISTS  `Get_StoreToZone_TaskGap` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `Get_StoreToZone_TaskGap`(
    IN in_bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN in_timestamp1 TIMESTAMP(3),
    IN in_timestamp2 TIMESTAMP(3)
)
BEGIN
    DECLARE time1 TIMESTAMP(3);
    DECLARE time2 TIMESTAMP(3);
   
   
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_store_tasks AS
    SELECT 
        LOGGED_TIMESTAMP
    FROM task_master_log
    WHERE BOT_ID = in_bot_id
      AND TASK_TYPE = 'BIN_STORE_TO_ZONE'
      AND STATUS = 'PROCESSING'
      AND LOGGED_TIMESTAMP >= in_timestamp1
      AND LOGGED_TIMESTAMP <= in_timestamp2
    ORDER BY LOGGED_TIMESTAMP ASC
    LIMIT 2;
    IF (SELECT COUNT(*) FROM temp_store_tasks) = 2 THEN
        SELECT LOGGED_TIMESTAMP INTO time1 
        FROM temp_store_tasks ORDER BY LOGGED_TIMESTAMP ASC LIMIT 1;
        SELECT LOGGED_TIMESTAMP INTO time2 
        FROM temp_store_tasks ORDER BY LOGGED_TIMESTAMP DESC LIMIT 1;
        SELECT ROUND(TIMESTAMPDIFF(SECOND, time1, time2) / 60, 2) AS Time_Difference_Minutes;
        
     ELSE
         SELECT 'Not enough STORE_TO_ZONE tasks found, PLEASE CHOOSE DIFFRENT TIME STAMPS' AS Message;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS temp_store_tasks;
END */$$
DELIMITER ;

/* Procedure structure for procedure `Get_StoreToZone_TaskGapsList` */

/*!50003 DROP PROCEDURE IF EXISTS  `Get_StoreToZone_TaskGapsList` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `Get_StoreToZone_TaskGapsList`(
    IN in_bot_id VARCHAR(10) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
    IN in_timestamp1 TIMESTAMP(3),
    IN in_timestamp2 TIMESTAMP(3)
)
BEGIN
    
    DROP TEMPORARY TABLE IF EXISTS temp_store_tasks;
    DROP TEMPORARY TABLE IF EXISTS temp_with_index1;
    DROP TEMPORARY TABLE IF EXISTS temp_with_index2;
   
    CREATE TEMPORARY TABLE temp_store_tasks AS
    SELECT 
        LOGGED_TIMESTAMP
    FROM task_master_log
    WHERE BOT_ID = in_bot_id
      AND TASK_TYPE = 'BIN_STORE_TO_ZONE'
      AND STATUS = 'PROCESSING'
      AND LOGGED_TIMESTAMP BETWEEN in_timestamp1 AND in_timestamp2
      AND LOGGED_TIMESTAMP IS NOT NULL
    ORDER BY LOGGED_TIMESTAMP ASC;
   
    SET @row1 := 0;
    CREATE TEMPORARY TABLE temp_with_index1 AS
    SELECT 
        (@row1 := @row1 + 1) AS row_num,
        LOGGED_TIMESTAMP
    FROM temp_store_tasks;
    SET @row2 := 0;
    CREATE TEMPORARY TABLE temp_with_index2 AS
    SELECT 
        (@row2 := @row2 + 1) AS row_num,
        LOGGED_TIMESTAMP
    FROM temp_store_tasks;
    
    SELECT 
        t1.LOGGED_TIMESTAMP AS First_Task_Time,
        t2.LOGGED_TIMESTAMP AS Second_Task_Time,
        ROUND(TIMESTAMPDIFF(SECOND, t1.LOGGED_TIMESTAMP, t2.LOGGED_TIMESTAMP) / 60, 2) AS Time_Difference_Minutes
    FROM temp_with_index1 t1
    JOIN temp_with_index2 t2 ON t1.row_num = t2.row_num - 1;
    DROP TEMPORARY TABLE IF EXISTS temp_store_tasks;
    DROP TEMPORARY TABLE IF EXISTS temp_with_index1;
    DROP TEMPORARY TABLE IF EXISTS temp_with_index2;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INSERT_ERROR_LOG` */

/*!50003 DROP PROCEDURE IF EXISTS  `INSERT_ERROR_LOG` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INSERT_ERROR_LOG`(IN Parameters JSON)
BEGIN
	DECLARE soureceApplication VARCHAR(50);
	DECLARE `endpoint` VARCHAR(255);
	DECLARE classMethodName VARCHAR(500);
	DECLARE errorCode INT;
	DECLARE errorMessage TEXT;
	DECLARE errorStackTrace TEXT;
	DECLARE errorDescription TEXT;
	
	SET soureceApplication = Parameters ->> '$.SourceApplication';
	SET `endpoint` = Parameters ->> '$.Endpoint';
	SET classMethodName = Parameters ->>'$.ClassMethodName';
	SET errorCode = Parameters ->> '$.ErrorCode';
	SET errorMessage = Parameters ->>'$.ErrorMessage';
	SET errorStackTrace = Parameters ->>'$.ErrorStackTrace';
	SET errorDescription = Parameters ->> '$.ErrorDescription';
	
	INSERT INTO `integration_error_logs`(SOURCE_APPLICATION, ENDPOINT, CLASS_METHOD_NAME, ERROR_CODE, ERROR_MESSAGE, ERROR_STACKTRACE, ERROR_DESCRIPTION) 
	VALUES (soureceApplication, `endpoint`, classMethodName, errorCode, errorMessage, errorStackTrace, errorDescription);
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_API_CRON_UPDATE_PAYLOAD_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_API_CRON_UPDATE_PAYLOAD_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_API_CRON_UPDATE_PAYLOAD_STATUS`(IN PayloadId varchar(50),IN Success BOOL)
BEGIN
	DECLARE is_processed INT DEFAULT -1;
	
	DECLARE i INT DEFAULT 0;
	
	
	IF (Success) THEN
		SET is_processed=-2;
	END IF;
		UPDATE `wcs_to_wms_payload` SET
		`IS_PROCESSED`=is_processed,
		`NO_OF_ATTEMPTS`=NO_OF_ATTEMPTS+1,
		`PROCESSED_TIMESTAMP`=NOW()
		 WHERE PAYLOAD_ID=PayloadId;
		 
		
	 
	
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_API_EVENT_PROCESS_EAN_PAYLOADS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_API_EVENT_PROCESS_EAN_PAYLOADS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_API_EVENT_PROCESS_EAN_PAYLOADS`()
BEGIN
	
		Declare eanPayload json;
		select JSON_ARRAYAGG(json_object('PAYLOAD_ID',`PAYLOAD_ID`,'DATA',`JSON_REQUEST`)) into eanPayload 
		from `wms_to_wcs_payload` where `API_ID`=324 and `IS_PROCESSED`=0
		and `INSERTED_TIMESTAMP`< date_add(now(),interval -2 minute);
		
		if eanPayload is not null then
			Drop temporary table  if exists _tmpEandata;
			Create temporary table _tmpEandata
			(
			  PAYLOAD_ID VARCHAR(64),
			  Gln varchar(64),
			  Width decimal(10,2),
			  Height decimal(10,2),
			  LENGTH decimal(10,2),
			  Weight decimal(10,2),
			  Category varchar(30),
			  ImageUrl varchar(1000),
			  Velocity int ,
			  ArticleId varchar(255),
			  ArticleName varchar(300),
			  MaxBinStorage int,
			  MinBinStorage int,
			  MinSegmentSize int,	
			  ArticleDescription varchar(1000),
			  MaxQuantityStorage int ,
			  MaxQuantityPerSegment int,
			  Ean varchar(255),
			  index(PAYLOAD_ID),
			  index(Category),
			  index(ArticleId),
			  index(Ean)
			) Engine=memory;
			
			insert into _tmpEandata(PAYLOAD_ID,Gln,Width,Height,LENGTH,Weight,Category,ImageUrl,Velocity,ArticleId,
			ArticleName,MaxBinStorage,MinBinStorage,MinSegmentSize,ArticleDescription,MaxQuantityStorage,
			MaxQuantityPerSegment,Ean)
			SELECT jt.PAYLOAD_ID,jt.Gln,jt.Width,jt.Height,jt.LENGTH,jt.Weight,jt.Category,jt.ImageUrl,jt.Velocity,jt.ArticleId,
			jt.ArticleName,jt.MaxBinStorage,jt.MinBinStorage,IFNULL(jt.MinSegmentSize,1) AS MinSegmentSize
			,jt.ArticleDescription,jt.MaxQuantityStorage,
			IFNULL(jt.MaxQuantityPerSegment,1) MaxQuantityPerSegment,je.Ean
			FROM JSON_TABLE(
			  eanPayload,
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
			    MinBinStorage INT PATH  '$.DATA.MinBinStorage',
			    MinSegmentSize INT PATH '$.DATA.MinSegmentSize',
			    ArticleDescription VARCHAR(1000) PATH '$.DATA.ArticleDescription',
			    MaxQuantityStorage INT PATH '$.DATA.MaxQuantityStorage',
			    MaxQuantityPerSegment INT PATH '$.DATA.MaxQuantityPerSegment',
			    EanList JSON PATH '$.DATA.EanList' 
			  )
			) AS jt,
			JSON_TABLE(jt.EanList ,'$[*]' COLUMNS(
				Ean VARCHAR(255) PATH '$'
			)) je;
			
			insert into `category_master`(`CATEGORY_NAME`)
			select  distinct jt.Category from _tmpEandata jt
			Left  outer Join category_master c on c.`CATEGORY_NAME`=jt.Category
			where c.`CATEGORY_ID` is null;
			
			
			update  sku_master sm
			inner Join _tmpEandata p on sm.SKU_ID=p.ArticleId
			INNER JOIN category_master c ON c.`CATEGORY_NAME`=p.Category
			set sm.SKU_NAME = IFNULL(P.ArticleName, sm.SKU_NAME),
			SM.VELOCITY = IFNULL(P.Velocity, SM.VELOCITY),
			SM.CATEGORY = IFNULL(C.CATEGORY_ID, SM.CATEGORY),
			MIN_SEGMENT_SIZE = IFNULL(P.MinSegmentSize, MIN_SEGMENT_SIZE),
			MAX_QUANTITY_PER_SEGMENT = IFNULL(P.MaxQuantityPerSegment, MAX_QUANTITY_PER_SEGMENT),
			SM.LENGTH = IFNULL(P.LENGTH, SM.LENGTH),
			SM.WIDTH = IFNULL(P.Width, SM.WIDTH),
			SM.HEIGHT = IFNULL(P.Height, SM.HEIGHT),
			SM.WEIGHT_OF_EACH_SKU = IFNULL(p.Weight, WEIGHT_OF_EACH_SKU),
			SM.IMAGE_URL = IFNULL(P.ImageUrl, SM.IMAGE_URL);
			
			INSERT INTO `sku_master` (
				SKU_ID, SKU_NAME, VELOCITY, CATEGORY, MIN_SEGMENT_SIZE, 
				MAX_QUANTITY_PER_SEGMENT,  `LENGTH`, `WIDTH`, `HEIGHT`, 
				WEIGHT_OF_EACH_SKU, IMAGE_URL, 
				IS_ACTIVE, INSERTED_BY, UPDATED_BY
				) 
			SELECT distinct JT.ArticleId, JT.ArticleName,JT.Velocity,C.CATEGORY_ID ,JT.MinSegmentSize ,
			JT.MaxQuantityPerSegment,JT.LENGTH,JT.WIDTH,JT.HEIGHT,JT.Weight,
			COALESCE(JT.ImageUrl, 'no-image-found.png'),1,'BACKEND','BACKEND'
			FROM _tmpEandata jt
			INNER JOIN category_master c ON c.`CATEGORY_NAME`=jt.Category
			lEFT  OUTER JOIN sku_master sm ON SM.SKU_ID=jt.ArticleId
			WHERE sm.SKU_ID IS NULL;
			
			
			INSERT IGNORE INTO sku_ean_mapping (SKU_ID, EAN_ID, GLN)
			SELECT jt.ArticleId, jt.Ean, jt.Gln FROM _tmpEandata jt; 
			
			update  wms_to_wcs_payload p
			inner Join  _tmpEandata tp  on tp.PAYLOAD_ID=p.PAYLOAD_ID 
			set p.`IS_PROCESSED`=1,p.`PROCESSED_TIMESTAMP`=now()
			WHERE p.`API_ID`=324 AND p.IS_PROCESSED=0;
		end if;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_API_INSERT_WCS_TO_WMS_PAYLOAD` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_API_INSERT_WCS_TO_WMS_PAYLOAD` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_API_INSERT_WCS_TO_WMS_PAYLOAD`(IN Parameter1 JSON)
BEGIN
        DECLARE ApiId BIGINT;
	DECLARE ApiSource VARCHAR(100);
	DECLARE JsonRequest JSON;
	DECLARE JsonResponse text;
	DECLARE HttpStatus INT;
	DECLARE IdempotencyKey varchar(50);
	SET JsonRequest = Parameter1 ->> '$.JsonRequest';
	SET IdempotencyKey = Parameter1 ->> '$.IdempotencyId';
	SET ApiId = Parameter1 ->> '$.ApiId';
	SET ApiSource = Parameter1->> '$.ApiSource';
	SET JsonResponse = Parameter1 ->> '$.JsonResponse';
	SET HttpStatus = Parameter1 ->> '$.HttpStatusCode';
	
	
	INSERT INTO `wcs_to_wms_payload` (`PAYLOAD_ID`,API_ID, API_SOURCE, JSON_REQUEST, JSON_RESPONSE, HTTP_STATUS,`INSERTED_BY`)
	 VALUES (IdempotencyKey,ApiId, ApiSource, JsonRequest, JsonResponse, HttpStatus,"BACKEND");
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_API_INSERT_WMS_TO_WCS_PAYLOAD` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_API_INSERT_WMS_TO_WCS_PAYLOAD` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_API_INSERT_WMS_TO_WCS_PAYLOAD`(IN Parameter1 JSON)
BEGIN
        DECLARE ApiId BIGINT;
	DECLARE ApiSource VARCHAR(100);
	DECLARE JsonRequest JSON;
	DECLARE JsonResponse JSON;
	DECLARE HttpStatus INT;
	DECLARE IdempotencyKey varchar(50);
	SET JsonRequest = Parameter1 ->> '$.JsonRequest';
	SET IdempotencyKey = Parameter1 ->> '$.IdempotencyId';
	SET ApiId = Parameter1 ->> '$.ApiId';
	SET ApiSource = Parameter1->> '$.ApiSource';
	SET JsonResponse = Parameter1 ->> '$.JsonResponse';
	SET HttpStatus = Parameter1 ->> '$.HttpStatusCode';
	
	
	INSERT INTO wms_to_wcs_payload(`IDEMPOTENCY_KEY`,API_ID, API_SOURCE, JSON_REQUEST, JSON_RESPONSE, HTTP_STATUS,`INSERTED_BY`)
	 VALUES (IdempotencyKey,ApiId, ApiSource, JsonRequest, JsonResponse, HttpStatus,"BACKEND");
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_API_SERVICE_UPDATE_STORAGE_IDEMPOTENCY` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_API_SERVICE_UPDATE_STORAGE_IDEMPOTENCY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_API_SERVICE_UPDATE_STORAGE_IDEMPOTENCY`(IN Parameters JSON)
BEGIN
   
    DECLARE StorageRequestId VARCHAR(100);
    DECLARE PayloadId VARCHAR(50);
    
    
    SET StorageRequestId         = Parameters ->> '$.StorageRequestId';
    SET PayloadId      = Parameters ->> '$.PayloadId';
    
    UPDATE `wms_to_wcs_storage_request_pallet_data` SET `REQUEST_PAYLOAD_ID` =PayloadId WHERE  StorageRequestId=`STORAGE_REQUEST_ID` ;
    
    SELECT 1;
   
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_API_UPDATE_PAGINATED_PAYLOAD_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_API_UPDATE_PAGINATED_PAYLOAD_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_API_UPDATE_PAGINATED_PAYLOAD_STATUS`(IN PayloadId VARCHAR(50),IN JsonResponse TEXT,IN HttpStatus INT,IN Success BOOL)
BEGIN
	DECLARE is_processed INT DEFAULT 0;
	
	DECLARE i INT DEFAULT 0;
	
	
	IF (Success) THEN
		SET is_processed=1;
	END IF;
		UPDATE `wcs_to_wms_payload` SET
		`JSON_RESPONSE`=JsonResponse,
		`HTTP_STATUS`=HttpStatus,
		`IS_PROCESSED`=is_processed,
		`NO_OF_ATTEMPTS`=NO_OF_ATTEMPTS+1,
		`PROCESSED_TIMESTAMP`=NOW()
		 WHERE PAYLOAD_ID=PayloadId;
		 
		 UPDATE `pageno_wave_payload_mapping` 
		 SET `TOTAL_ATTEMPTS`=`TOTAL_ATTEMPTS`+1 where `PAYLOAD_ID`=PayloadId;
		 
		   UPDATE `wcs_to_wms_payload` SET `IS_ACTIVE` = 0 
    WHERE `NO_OF_ATTEMPTS` > 2 AND `IS_PROCESSED` = 0;
	 
	
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_API_UPDATE_PAYLOAD_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_API_UPDATE_PAYLOAD_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_API_UPDATE_PAYLOAD_STATUS`(IN PayloadId varchar(50),IN JsonResponse text,IN HttpStatus INT,IN Success BOOL)
BEGIN
	DECLARE is_processed INT DEFAULT 0;
	
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
		 
		  UPDATE `wcs_to_wms_payload` SET `IS_ACTIVE` = 0 
    WHERE `NO_OF_ATTEMPTS` > 2 AND `IS_PROCESSED` = 0;
	 
	
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_ARCHIVING_SERVICE` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_ARCHIVING_SERVICE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_ARCHIVING_SERVICE`()
BEGIN
    DECLARE batch_size INT DEFAULT 5000;
    DECLARE records_affected INT;
    DECLARE CURRENT_TIME1 DATETIME;
    SET CURRENT_TIME1 = NOW();
    
    REPEAT
        START TRANSACTION;
        
        INSERT INTO wms_to_wcs_payload_archive (
	    PAYLOAD_ID,
	    IDEMPOTENCY_KEY,
	    API_ID,
	    API_SOURCE,
	    JSON_REQUEST,
	    JSON_RESPONSE,
	    HTTP_STATUS,
	    INSERTED_TIMESTAMP,
	    INSERTED_BY,
	    UPDATED_TIMESTAMP,
	    IS_PROCESSED,
	    NO_OF_ATTEMPTS,
	    PROCESSED_TIMESTAMP,
	    ASYNC_PAYLOAD_ID
	)
	SELECT
	    PAYLOAD_ID,
	    IDEMPOTENCY_KEY,
	    API_ID,
	    API_SOURCE,
	    JSON_REQUEST,
	    JSON_RESPONSE,
	    HTTP_STATUS,
	    INSERTED_TIMESTAMP,
	    INSERTED_BY,
	    UPDATED_TIMESTAMP,
	    IS_PROCESSED,
	    NO_OF_ATTEMPTS,
	    PROCESSED_TIMESTAMP,
	    ASYNC_PAYLOAD_ID
	
	FROM wms_to_wcs_payload
	WHERE INSERTED_TIMESTAMP < NOW() - INTERVAL 3 hour
	ORDER BY INSERTED_TIMESTAMP ASC
	LIMIT batch_size;
	
	  SET records_affected = ROW_COUNT();
	 
        DELETE FROM wms_to_wcs_payload
        WHERE INSERTED_TIMESTAMP < NOW() - INTERVAL 3 HOUR
        ORDER BY INSERTED_TIMESTAMP ASC
        LIMIT batch_size;
        COMMIT;
        DO SLEEP(0.5);
    UNTIL records_affected = 0 END REPEAT;
    
    REPEAT
        START TRANSACTION;
        
        INSERT INTO wcs_to_wms_payload_archive (
            PAYLOAD_ID,
            IDEMPOTENCY_KEY,
            API_ID,
            API_HEADERS,
            TOPIC,
            API_SOURCE,
            JSON_REQUEST,
            JSON_RESPONSE,
            HTTP_STATUS,
            INSERT_TIMESTAMP,
            INSERTED_BY,
            IS_PROCESSED,
            NO_OF_ATTEMPTS,
            PROCESSED_TIMESTAMP,
            IS_ACTIVE,
            archived_at
        )
        SELECT
            PAYLOAD_ID,
            IDEMPOTENCY_KEY,
            API_ID,
            API_HEADERS,
            TOPIC,
            API_SOURCE,
            JSON_REQUEST,
            JSON_RESPONSE,
            HTTP_STATUS,
            INSERT_TIMESTAMP,
            INSERTED_BY,
            IS_PROCESSED,
            NO_OF_ATTEMPTS,
            PROCESSED_TIMESTAMP,
            IS_ACTIVE,
            NOW()
        FROM wcs_to_wms_payload
        WHERE INSERT_TIMESTAMP < NOW() - INTERVAL 5 DAY
        ORDER BY INSERT_TIMESTAMP ASC
        LIMIT batch_size;
        SET records_affected = ROW_COUNT();
        
        DELETE FROM wcs_to_wms_payload
        WHERE INSERT_TIMESTAMP < NOW() - INTERVAL 5 DAY
        ORDER BY INSERT_TIMESTAMP ASC
        LIMIT batch_size;
        COMMIT;
        DO SLEEP(0.5);
    UNTIL records_affected = 0 END REPEAT;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_ARCHIVING_SERVICE_PAYLOAD_TABLE` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_ARCHIVING_SERVICE_PAYLOAD_TABLE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_ARCHIVING_SERVICE_PAYLOAD_TABLE`()
BEGIN
    DECLARE batch_size INT DEFAULT 1000;
    DECLARE records_affected INT;
    DECLARE CURRENT_TIME1 DATETIME;
       SET CURRENT_TIME1 = NOW();
    
    
    START TRANSACTION;
    
    
    INSERT INTO wms_to_wcs_payload_archive (
        PAYLOAD_ID,
        IDEMPOTENCY_KEY,
        API_ID,
        API_SOURCE,
        JSON_REQUEST,
        JSON_RESPONSE,
        HTTP_STATUS,
        `INSERTED_TIMESTAMP`,
        INSERTED_BY,
        IS_PROCESSED,
        NO_OF_ATTEMPTS,
        PROCESSED_TIMESTAMP,
        `ASYNC_PAYLOAD_ID`
    )
    SELECT
        PAYLOAD_ID,
        IDEMPOTENCY_KEY,
        API_ID,
        API_SOURCE,
        JSON_REQUEST,
        JSON_RESPONSE,
        HTTP_STATUS,
        INSERTED_TIMESTAMP,
        INSERTED_BY,
        IS_PROCESSED,
        NO_OF_ATTEMPTS,
        PROCESSED_TIMESTAMP,
        `ASYNC_PAYLOAD_ID`
    FROM wms_to_wcs_payload
    WHERE INSERTED_TIMESTAMP < CURRENT_TIME1  - INTERVAL 24 HOUR
    ORDER BY INSERTED_TIMESTAMP ASC
    LIMIT batch_size;
    
  
    
    
    DELETE FROM wms_to_wcs_payload
    WHERE INSERTED_TIMESTAMP < CURRENT_TIME1  - INTERVAL 24 HOUR
    ORDER BY INSERTED_TIMESTAMP ASC
    LIMIT batch_size;
    
    COMMIT;
    
    
    START TRANSACTION;
    
    
    INSERT INTO wcs_to_wms_payload_archive (
        PAYLOAD_ID,
        IDEMPOTENCY_KEY,
        API_ID,
        API_HEADERS,
        TOPIC,
        API_SOURCE,
        JSON_REQUEST,
        JSON_RESPONSE,
        HTTP_STATUS,
        INSERTED_TIMESTAMP,
        INSERTED_BY,
        IS_PROCESSED,
        NO_OF_ATTEMPTS,
        PROCESSED_TIMESTAMP,
        IS_ACTIVE
    )
    SELECT
        PAYLOAD_ID,
        IDEMPOTENCY_KEY,
        API_ID,
        API_HEADERS,
        TOPIC,
        API_SOURCE,
        JSON_REQUEST,
        JSON_RESPONSE,
        HTTP_STATUS,
        INSERTED_TIMESTAMP,
        INSERTED_BY,
        IS_PROCESSED,
        NO_OF_ATTEMPTS,
        PROCESSED_TIMESTAMP,
        IS_ACTIVE
    FROM wcs_to_wms_payload
    WHERE INSERTED_TIMESTAMP < CURRENT_TIME1 - INTERVAL 3 DAY
    AND (  IS_PROCESSED= 1  OR  api_id  IN (304,306))
    ORDER BY INSERTED_TIMESTAMP ASC
    LIMIT batch_size;
   
    
    
    DELETE FROM wcs_to_wms_payload
    WHERE INSERTED_TIMESTAMP < CURRENT_TIME1 - INTERVAL 3 DAY
     AND (  IS_PROCESSED= 1  OR  api_id  IN (304,306))
    ORDER BY INSERTED_TIMESTAMP ASC
    LIMIT batch_size;
    
    COMMIT;
    
    
    SELECT  1 AS SUCCESS, ' Archived' AS MESSAGE;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_ASYNC_WCS_PARTIAL_UPDATE_PAYLOAD_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_ASYNC_WCS_PARTIAL_UPDATE_PAYLOAD_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_ASYNC_WCS_PARTIAL_UPDATE_PAYLOAD_STATUS`(IN PayloadId varchar(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci,IN Success BOOL)
BEGIN
	DECLARE is_processed INT DEFAULT -1;
	
	DECLARE i INT DEFAULT 0;
	
	
	IF (Success) THEN
		SET is_processed=-2;
	END IF;
		UPDATE `wcs_to_wms_payload` SET
		`IS_PROCESSED`=is_processed,
		`PROCESSED_TIMESTAMP`=NOW()
		 WHERE PAYLOAD_ID=PayloadId;
		 
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_ASYNC_WMS_UPDATE_PAYLOAD_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_ASYNC_WMS_UPDATE_PAYLOAD_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_ASYNC_WMS_UPDATE_PAYLOAD_STATUS`(IN PayloadId varchar(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci,IN Success BOOL)
BEGIN
	DECLARE is_processed INT DEFAULT 0;
	
	DECLARE i INT DEFAULT 0;
	
	
	IF (Success) THEN
		SET is_processed=1;
	END IF;
		UPDATE `wcs_to_wms_payload` SET
		`IS_PROCESSED`=is_processed,
		`PROCESSED_TIMESTAMP`=NOW()
		 WHERE PAYLOAD_ID=PayloadId;
		 
      select 1 as SUCCESS;
		
	 
	
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_GET_PICK_INCOMPLETED_ORDER_LINE_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_GET_PICK_INCOMPLETED_ORDER_LINE_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_GET_PICK_INCOMPLETED_ORDER_LINE_ID`()
BEGIN
    
	
        SELECT  DISTINCT wwplrd.ORDER_LINE_ID
	FROM `wms_to_wcs_order_line_level_pre_staged_data`  wwplrd
	INNER JOIN `wms_to_wcs_order_level_pre_staged_data` b ON
	b.`WMS_ORDER_REQUEST_DATA_ID`=wwplrd.`WMS_ORDER_REQUEST_DATA_ID`
	
	WHERE wwplrd.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL
	 AND b.`ORDER_REQUEST_STATUS` <>'DELETED'
	  AND wwplrd.`ORDER_LINE_PROCESS_STATUS` = 'ORDERLINE_COMPLETED'
	   
	LIMIT 100 ; 
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_GET_PICK_STOCK_ADJUSTMENT_PAYLOAD` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_GET_PICK_STOCK_ADJUSTMENT_PAYLOAD` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_GET_PICK_STOCK_ADJUSTMENT_PAYLOAD`(IN Parameters JSON)
BEGIN
    DECLARE order_lineid VARCHAR(50);
    DECLARE v_errorMessage VARCHAR(255); 
    DECLARE TimerCounter INT DEFAULT 1000;
     DECLARE _gln VARCHAR(50);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION  
    BEGIN  
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;  
        ROLLBACK;  
        SELECT 0 AS SUCCESS, 'FAILED DUE TO ERROR' AS MESSAGE, v_errorMessage AS DESCRIPTION;  
    END;
    
    SET order_lineid = Parameters ->>'$.sourceId';
    START TRANSACTION;
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    DROP TEMPORARY TABLE IF EXISTS reasontable;
    
    SELECT KEY_VALUE INTO @IntegrationTimeCounter FROM `master_config` WHERE KEY_NAME='INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    
    CREATE TEMPORARY TABLE TempPayloads (
        `id` VARCHAR(36),
        `payload_id` CHAR(36),
        headers JSON,
        `json_output` JSON,
        INDEX(`id`)
    );
    
    
    CREATE TEMPORARY TABLE reasontable (
        `quantity` INT,
        `reason` VARCHAR(36),
        `timestamp` DATETIME,
        `user_by` VARCHAR(36)
    );
    
    
    SELECT p.gln INTO _gln
	FROM `wms_to_wcs_order_level_pre_staged_data` p
	JOIN `wms_to_wcs_order_line_level_pre_staged_data` d
	  ON p.`PARENT_ORDER_ID` = d.`PARENT_ORDER_ID`
	WHERE d.`ORDER_LINE_ID` = order_lineid
	LIMIT 1;
	
	
	
   set @discrepancy_quantity=0;
    
    INSERT INTO reasontable (quantity, reason, TIMESTAMP, user_by)
	SELECT 
	    SUM(LEFT_OVER) AS total_leftover,
	    'NOT_FOUND_IN_INVENTORY' AS reason,
	    MAX(INSERTED_TIMESTAMP) AS latest_timestamp,
	    'SYSTEM' AS user_by
	FROM (
	    SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP
	    FROM pick_wave_wms_data
	    WHERE ORDER_LINE_ID = order_lineid
	    UNION ALL
	    SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP
	    FROM pick_wave_wms_data_archive
	    WHERE ORDER_LINE_ID = order_lineid
	) AS combined_data
	GROUP BY ORDER_LINE_ID
	HAVING SUM(LEFT_OVER) > 0;
    
     start transaction;
    
    IF EXISTS (SELECT 1 FROM reasontable) THEN
        SET @discrepancy_quantity = (SELECT SUM(quantity) FROM reasontable);
	
	INSERT INTO TempPayloads (id, `payload_id`,headers, `json_output`)  
	VALUES (
	    order_lineid,
	    UUID(),
	     JSON_OBJECT(
		@glnHeader,`_gln`),
	    JSON_OBJECT(
		'Gln', _gln,
		'Process', 'PICK',
		'SourceId', order_lineid,
		'DiscrepancyQuantity', @discrepancy_quantity,
		'CauseList',  ( SELECT JSON_ARRAYAGG(
		JSON_OBJECT(
		    'DiscrepancyQuantity', quantity,
		    'Cause', reason,
		    'UserId', user_by,
		    'EventTimestamp', TIMESTAMP
		)
		
	    )
	    FROM reasontable
	    )
	    )
	);
          ELSE
		     UPDATE  `wms_to_wcs_order_line_level_pre_staged_data` C
	    SET C.`STOCK_ADJUSTMENT_PAYLOAD_ID` = 'not_required'
	    WHERE C.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL AND `ORDER_LINE_ID`=order_lineid;
            
    END IF;
    
    
    INSERT INTO `wcs_to_wms_payload` (`PAYLOAD_ID`,API_HEADERS, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`,headers, '315', 'cronJob', `json_output`
    FROM TempPayloads;
    
      UPDATE `wms_to_wcs_order_line_level_pre_staged_data` 
      set `STOCK_ADJUSTMENT_QUANTITY` = @discrepancy_quantity
      where `ORDER_LINE_ID`=order_lineid;
    
    
    UPDATE `wms_to_wcs_order_line_level_pre_staged_data`  C
    JOIN TempPayloads T ON C.`ORDER_LINE_ID` = T.id
    SET C.`STOCK_ADJUSTMENT_PAYLOAD_ID` = T.`payload_id`
    WHERE C.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL;
    COMMIT;
    
    commit; 
    
    SELECT 1 AS SUCCESS, 'PAYLOAD SUCCESSFULLY CREATED' AS MESSAGE;
   
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_GET_PICK_STOCK_ADJUSTMENT_PAYLOAD_FETCH` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_GET_PICK_STOCK_ADJUSTMENT_PAYLOAD_FETCH` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_GET_PICK_STOCK_ADJUSTMENT_PAYLOAD_FETCH`()
BEGIN
    
    
     SELECT KEY_VALUE INTO @InfiniteRetryAttemtps FROM `master_config` WHERE KEY_NAME='INTEGRATION_INFINITE_RETRY_TIMER';
    
     
    SELECT *
	FROM `wcs_to_wms_payload` wcs
	WHERE wcs.`API_ID` = 315
	  AND wcs.`IS_PROCESSED` <> 1
	  AND (wcs.http_status IS NULL OR wcs.http_status NOT IN (400, 422))

	  
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

/* Procedure structure for procedure `INT_CRON_GET_PICK_VALIDATION_FETCH` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_GET_PICK_VALIDATION_FETCH` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_GET_PICK_VALIDATION_FETCH`()
BEGIN
    
    
    SELECT *
    FROM `wcs_to_wms_payload` wcs
    WHERE (wcs.`API_ID` = '3' 
      AND wcs.`IS_PROCESSED` <> 1
      AND (
          wcs.`NO_OF_ATTEMPTS` = 0 
          OR (
              wcs.`NO_OF_ATTEMPTS` < 5
              AND wcs.`PROCESSED_TIMESTAMP` < DATE_ADD(CURRENT_TIMESTAMP(), INTERVAL -5 SECOND)
          )
      ))
    LIMIT 500;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_GET_PUT_INCOMPLETED_ORDER_LINE_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_GET_PUT_INCOMPLETED_ORDER_LINE_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_GET_PUT_INCOMPLETED_ORDER_LINE_ID`()
BEGIN
    
	
    select distinct `ORDER_LINE_ID`  
    from `wms_to_wcs_order_line_request_data` wwplrd
    INNER JOIN `wms_to_wcs_order_request_data` wword on wword.`WMS_ORDER_REQUEST_DATA_ID`=wwplrd.`WMS_ORDER_REQUEST_DATA_ID`
    
     where wword.`ORDER_REQUEST_STATUS`='ORDER_PICK_COMPLETED'
     
      AND `STOCK_ADJUSTMENT_PAYLOAD_ID` is NULL AND
      wword.`ORDER_REQUEST_COMPLETED_PAYLOAD`is NULL ;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_GET_PUT_INCOMPLETED_STORAGE_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_GET_PUT_INCOMPLETED_STORAGE_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_GET_PUT_INCOMPLETED_STORAGE_ID`()
BEGIN
    
	
    select distinct `STORAGE_ID`  from `wms_to_wcs_storage_request_data`  wwsrd
    inner join `wms_to_wcs_storage_request_pallet_data`  wwsrpd
    On wwsrd.`STORAGE_REQUEST_ID`=wwsrpd.`STORAGE_REQUEST_ID`
    where `STOCK_ADJUSTMENT_PAYLOAD_ID` is  NULL AND `PALLET_COMPLETION`=1;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_GET_PUT_STOCK_ADJUSTMENT_PAYLOAD` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_GET_PUT_STOCK_ADJUSTMENT_PAYLOAD` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_GET_PUT_STOCK_ADJUSTMENT_PAYLOAD`(IN Parameters JSON)
BEGIN
    DECLARE _storage_id VARCHAR(50);
    DECLARE _gln VARCHAR(50);
    DECLARE _integration_time_counter VARCHAR(50);
    DECLARE _gln_header VARCHAR(50);
    DECLARE total_put_quantity INT DEFAULT 0;
    DECLARE total_short_quantity INT DEFAULT 0;
    DECLARE total_quantity INT DEFAULT 0;
    DECLARE discrepancy_quantity INT DEFAULT 0;
    
    SELECT KEY_VALUE INTO _integration_time_counter FROM `master_config` WHERE KEY_NAME='INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO _gln_header FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    SET _storage_id = Parameters ->> '$.sourceId';
    START TRANSACTION;
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    DROP TEMPORARY TABLE IF EXISTS reasontable;
    CREATE TEMPORARY TABLE TempPayloads (
        `id` VARCHAR(36),
        `payload_id` CHAR(36),
        headers JSON,
        `stock_adjustment_quantity` INT,
        `json_output` JSON,
        INDEX(`id`)
    );
    CREATE TEMPORARY TABLE reasontable (
        `quantity` INT,
        `reason` VARCHAR(36),
        `timestamp` DATETIME,
        `user_by` VARCHAR(36)
    );
    
    SELECT p.gln INTO _gln
    FROM `wms_to_wcs_storage_request_pallet_data` p
    JOIN `wms_to_wcs_storage_request_data` d ON p.`STORAGE_REQUEST_ID` = d.`STORAGE_REQUEST_ID`
    WHERE d.`STORAGE_ID` = _storage_id
    LIMIT 1;
    
    INSERT INTO reasontable (quantity, reason, TIMESTAMP, user_by)
    SELECT 
        SUM(LEFT_OVER), 
        'NO_SPACE_IN_INVENTORY', 
        MAX(INSERTED_TIMESTAMP), 
        'SYSTEM'
    FROM (
        SELECT LEFT_OVER, INSERTED_TIMESTAMP, STORAGE_ID 
        FROM put_wave_wms_data WHERE STORAGE_ID = _storage_id
        UNION ALL
        SELECT LEFT_OVER, INSERTED_TIMESTAMP, STORAGE_ID 
        FROM put_wave_wms_data_archive WHERE STORAGE_ID = _storage_id
    ) combined_data
    GROUP BY STORAGE_ID
    HAVING SUM(LEFT_OVER) > 0;
    
    INSERT INTO reasontable (quantity, reason, TIMESTAMP, user_by)
    SELECT 
        (r.`SHORT_PUT_QUANTITY` - r.`RE_ATTEMPT_QUANTITY`), 
        r.`REASON`, 
        r.`INSERTED_TIMESTAMP`, 
        r.`INSERTED_BY`
    FROM `short_put_wave_reason` r
    INNER JOIN (
        SELECT `PUT_ORDER_ID` FROM `put_wave_order_master` WHERE `STORAGE_ID` = _storage_id
        UNION ALL
        SELECT `PUT_ORDER_ID` FROM `put_wave_order_master_archive` WHERE `STORAGE_ID` = _storage_id
    ) combined_orders ON r.`PUT_ORDER_ID` = combined_orders.`PUT_ORDER_ID`
    WHERE (r.`SHORT_PUT_QUANTITY` - r.`RE_ATTEMPT_QUANTITY`) > 0;
    
    IF EXISTS (SELECT 1 FROM reasontable) THEN
        SELECT SUM(quantity) INTO discrepancy_quantity FROM reasontable;
        INSERT INTO TempPayloads (`id`, `payload_id`, headers,stock_adjustment_quantity, `json_output`)  
        SELECT 
            _storage_id,
            UUID(),
            JSON_OBJECT(_gln_header, _gln),
            discrepancy_quantity,
            JSON_OBJECT(
                'Gln', _gln,
                'Process', 'PUT',
                'SourceId', _storage_id,
                'DiscrepancyQuantity', discrepancy_quantity,
                'CauseList', (
                    SELECT JSON_ARRAYAGG(
                        JSON_OBJECT(
                            'DiscrepancyQuantity', quantity,
                            'Cause', reason,
                            'UserId', user_by,
                            'EventTimestamp', TIMESTAMP
                        )
                    )
                    FROM reasontable
                )
            );
    ELSE
        UPDATE `wms_to_wcs_storage_request_data`
        SET `STOCK_ADJUSTMENT_PAYLOAD_ID` = 'not_required' ,`STOCK_ADJUSTMENT_QUANTITY` =0
        WHERE `STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL AND `STORAGE_ID` = _storage_id;
    END IF;
    
   
    SELECT IFNULL(SUM(x.put_qty), 0)
          INTO total_put_quantity
        FROM (
            SELECT PUT_ORDER_ID, MAX(PUT_QUANTITY) AS put_qty
            FROM (
                SELECT distinct PUT_ORDER_ID, PUT_QUANTITY
                FROM put_wave_order_master
                WHERE STORAGE_ID = _storage_id

                UNION ALL

                SELECT distinct PUT_ORDER_ID, PUT_QUANTITY
                FROM put_wave_order_master_archive
                WHERE STORAGE_ID = _storage_id
            ) all_puts
            GROUP BY PUT_ORDER_ID
        ) X;
        
    
    SELECT IFNULL(SUM(quantity), 0) INTO total_short_quantity FROM reasontable;
    
    
     SELECT A.QUANTITY INTO total_quantity 
        FROM (
		SELECT IFNULL(QUANTITY, 0) QUANTITY,INSERT_TIMESTAMP 
		FROM wms_to_wcs_storage_request_data
		WHERE STORAGE_ID = _storage_id        
		UNION ALL 
		SELECT QUANTITY,INSERT_TIMESTAMP 
		FROM wms_to_wcs_storage_request_data_Archive
		WHERE STORAGE_ID = _storage_id
        ) A
        ORDER BY insert_timestamp ASC
        LIMIT 1;
        
        
   
    
    IF (total_put_quantity + total_short_quantity <> total_quantity) THEN
        UPDATE `wms_to_wcs_storage_request_data` C
        JOIN TempPayloads T ON C.`STORAGE_ID` = T.`id`
        SET C.`STOCK_ADJUSTMENT_PAYLOAD_ID` = 'Quantity Mistach' ,C.`STOCK_ADJUSTMENT_QUANTITY` = T.stock_adjustment_quantity
        WHERE C.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL;
    ELSE
        
        INSERT IGNORE INTO `wcs_to_wms_payload` (`PAYLOAD_ID`, `API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
        SELECT `payload_id`, headers, '323', 'cronJob', `json_output`
        FROM TempPayloads;
        
        UPDATE `wms_to_wcs_storage_request_data` C
        JOIN TempPayloads T ON C.`STORAGE_ID` = T.`id`
        SET C.`STOCK_ADJUSTMENT_PAYLOAD_ID` = T.`payload_id`,C.`STOCK_ADJUSTMENT_QUANTITY` = T.stock_adjustment_quantity
        WHERE C.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL;
    END IF;
    COMMIT;
    SELECT 1 AS SUCCESS, 'PAYLOAD SUCCESSFULLY CREATED' AS MESSAGE;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_GET_PUT_STOCK_ADJUSTMENT_PAYLOAD_FETCH` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_GET_PUT_STOCK_ADJUSTMENT_PAYLOAD_FETCH` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_GET_PUT_STOCK_ADJUSTMENT_PAYLOAD_FETCH`()
BEGIN
    
    
      SELECT KEY_VALUE INTO @InfiniteRetryAttemtps FROM `master_config` WHERE KEY_NAME='INTEGRATION_INFINITE_RETRY_TIMER';
    
    SELECT *
    FROM `wcs_to_wms_payload` wcs
    WHERE wcs.`API_ID` = '323' 
      AND wcs.`IS_PROCESSED` <> 1
      AND (wcs.http_status IS NULL OR wcs.http_status NOT IN (400, 422))

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

/* Procedure structure for procedure `INT_CRON_GET_PUT_STOCK_ADJUSTMENT_PAYLOAD_v1` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_GET_PUT_STOCK_ADJUSTMENT_PAYLOAD_v1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `INT_CRON_GET_PUT_STOCK_ADJUSTMENT_PAYLOAD_v1`(IN Parameters JSON)
BEGIN
    DECLARE _storage_id VARCHAR(50);
    DECLARE _gln VARCHAR(50);
   
    
    SELECT KEY_VALUE INTO @IntegrationTimeCounter FROM `master_config` WHERE KEY_NAME='INTEGRATION_RETRY_TIMER';
    SELECT KEY_VALUE INTO @glnHeader FROM `master_config` WHERE KEY_NAME='INTEGRATION_GLN_HEADER';
    
    
    
    SET _storage_id = Parameters ->>'$.sourceId';
    
  
    START TRANSACTION;
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    DROP TEMPORARY TABLE IF EXISTS reasontable;
  
    
    CREATE TEMPORARY TABLE TempPayloads (
        `id` VARCHAR(36),
        `payload_id` CHAR(36),
        headers JSON,
        `json_output` JSON,
        INDEX(`id`)
    );
    
    CREATE TEMPORARY TABLE reasontable (
        `quantity` INT,
        `reason` VARCHAR(36),
        `timestamp` DATETIME,
        `user_by` VARCHAR(36)
    );
    
    SELECT p.gln INTO _gln
	FROM `wms_to_wcs_storage_request_pallet_data` p
	JOIN `wms_to_wcs_storage_request_data` d
	  ON p.`STORAGE_REQUEST_ID` = d.`STORAGE_REQUEST_ID`
	WHERE d.`STORAGE_ID` = _storage_id
	LIMIT 1;
    
 INSERT INTO reasontable (quantity, reason, TIMESTAMP, user_by)
	SELECT 
	    SUM(LEFT_OVER), 
	    'NO_SPACE_IN_INVENTORY', 
	    MAX(INSERTED_TIMESTAMP), 
	    'SYSTEM'
	FROM (
	    SELECT LEFT_OVER, INSERTED_TIMESTAMP, STORAGE_ID 
	    FROM put_wave_wms_data
	    WHERE STORAGE_ID = _storage_id
	    UNION ALL
	    SELECT LEFT_OVER, INSERTED_TIMESTAMP, STORAGE_ID 
	    FROM put_wave_wms_data_archive
	    WHERE STORAGE_ID = _storage_id
	) combined_data
	GROUP BY STORAGE_ID
	HAVING SUM(LEFT_OVER) > 0;
    
    
    INSERT INTO reasontable (quantity, reason, TIMESTAMP, user_by)
	SELECT 
	    (r.`SHORT_PUT_QUANTITY` - r.`RE_ATTEMPT_QUANTITY`), 
	    r.`REASON`, 
	    r.`INSERTED_TIMESTAMP`, 
	    r.`INSERTED_BY`
	FROM `short_put_wave_reason` r
	INNER JOIN (
	    SELECT `PUT_ORDER_ID`, `STORAGE_ID` 
	    FROM `put_wave_order_master`
	    WHERE `STORAGE_ID` = _storage_id
	    UNION ALL
	    SELECT `PUT_ORDER_ID`, `STORAGE_ID` 
	    FROM `put_wave_order_master_archive`
	    WHERE `STORAGE_ID` = _storage_id
	) combined_orders ON r.`PUT_ORDER_ID` = combined_orders.`PUT_ORDER_ID`
	WHERE 
	    (r.`SHORT_PUT_QUANTITY` - r.`RE_ATTEMPT_QUANTITY`) > 0;
      
    IF EXISTS (SELECT 1 FROM reasontable) THEN
        SET @discrepancy_quantity = (SELECT SUM(quantity) FROM reasontable);
        
        INSERT INTO TempPayloads (`id`, `payload_id`, headers,`json_output`)  
        SELECT 
            _storage_id,
            UUID(),
            JSON_OBJECT(
		@glnHeader,`_gln`),
            JSON_OBJECT(
                'Gln', _gln,
                'Process', 'PUT',
                'SourceId', _storage_id,
                'DiscrepancyQuantity', @discrepancy_quantity ,
                'CauseList', (
                    SELECT JSON_ARRAYAGG(
                        JSON_OBJECT(
                            'DiscrepancyQuantity', quantity,
                            'Cause', reason,
                            'UserId', user_by,
                            'EventTimestamp', TIMESTAMP
                        )
                    )
                    FROM reasontable
                )
            );
            else
		     UPDATE `wms_to_wcs_storage_request_data`  C
	    SET C.`STOCK_ADJUSTMENT_PAYLOAD_ID` = 'not_required'
	    WHERE C.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL and `STORAGE_ID`=_storage_id;
            
    END IF;
    
   
    
    INSERT IGNORE INTO `wcs_to_wms_payload` (`PAYLOAD_ID`,`API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`, headers, '323', 'cronJob', `json_output`
    FROM TempPayloads;
    
    
    UPDATE `wms_to_wcs_storage_request_data`  C
    JOIN TempPayloads T ON C.`STORAGE_ID` = T.`id`
    SET C.`STOCK_ADJUSTMENT_PAYLOAD_ID` = T.`payload_id`
    WHERE C.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL;
    COMMIT;
    
    SELECT 1 AS SUCCESS, 'PAYLOAD SUCCESSFULLY CREATED' AS MESSAGE;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYNC_FETCH_CONFIG` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYNC_FETCH_CONFIG` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYNC_FETCH_CONFIG`()
BEGIN
SELECT `KEY_NAME`,`KEY_VALUE` FROM `master_config` WHERE 
	key_NAME IN (
		'INTEGRATION_INVENTORY_SYN_DELAY_WAVE_COMPLETION_CHECK',
		'INTEGRATION_INVENTORY_SYN_DELAY_API_REQUEST_CHECK',
		'INTEGRATION_INVENTORY_SYN_DELAY_WMS_ACK',
		'INTEGRATION_INVENTORY_SYNC_TIME_AVAILBALE',
		'INTEGRATION_INVENTORY_SYNC_PAGE_SIZE',
		'INTEGRATION_INVENTORY_SYNC_CRON_EXPRESSION',
		'INTEGRATION_INVENTORY_SYNC_STATUS',
		'INTEGRATION_INVENTORY_SYNC_WCS_MIN_PAYLOAD_CREATION_TIME',
		'INTEGRATION_INVENTORY_SYN_WAIT_API_REQUEST',
		'INTEGRATION_INVENTORY_SYN_WAIT_WMS_ACK'
	);
	END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYNC_FETCH_DETAIL` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYNC_FETCH_DETAIL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYNC_FETCH_DETAIL`(IN Parameters JSON)
BEGIN
    
    DECLARE _gln VARCHAR(50);
    
    SET _gln = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.Gln'));
    
    
    SELECT 
        b.`SKU_ID` as SkuId,
        b.`CLIENT_BATCH_ID` as ClientBatchId,
        b.`BATCH_ID`  as BatchId,
        SUM(a.`QUANTITY`) - sum(`VIRTUAL_QUANTITY_TO_PICK`) AS Quantity
    FROM `live_inventory_master` a
    INNER JOIN `sku_batch_master` b 
        ON a.`BATCH_ID` = b.`BATCH_ID`
    WHERE b.`GLN` = _gln and b.`CLIENT_BATCH_ID` IS NOT null
  
    GROUP BY a.`BATCH_ID` 
    having SUM(a.`QUANTITY`) - SUM(`VIRTUAL_QUANTITY_TO_PICK`)>0;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYNC_MAIN_LOG` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYNC_MAIN_LOG` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYNC_MAIN_LOG`(IN parameters JSON)
BEGIN
    
    
    
    DECLARE _inventorySyncMainId VARCHAR(100);
    DECLARE _reason VARCHAR(100);
    DECLARE _startTime DATETIME;
    DECLARE _waveCompletionTime DATETIME;
    DECLARE _comments TEXT;
    DECLARE _status VARCHAR(50);
    DECLARE _dashboardWaveDisable INT;
    DECLARE _inventorySyncGlnModels JSON;
    DECLARE _recordExists INT DEFAULT 0;
    
    
    
    SET _inventorySyncMainId     = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.InventorySyncMainId'));
    SET _reason     = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.Reason'));
    SET _startTime               = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.StartTime')), NOW());
    SET _waveCompletionTime      = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.WaveCompletionTime'));
    SET _comments                = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.Comments'));
    SET _status                  = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.Status')), 'PENDING');
    SET _dashboardWaveDisable     = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.DashboardWaveDisable')), 0);
    
    
    
    SELECT COUNT(*) INTO _recordExists
    FROM `inventory_sync_master`
    WHERE `INVENTORY_SYNC_MASTER_ID` = _inventorySyncMainId;
    
    update `master_config` set `KEY_VALUE` = _dashboardWaveDisable where `KEY_NAME` = 'INTEGRATION_INVENTORY_SYNC_STATUS' ;
    
    
    
    IF _recordExists > 0 THEN
        UPDATE `inventory_sync_master`
        SET 
            `STATUS` = _status,
            `REASON`=_reason,
            `COMMENTS` = _comments,
            `COMPLETED_TIMESTAMP` = _waveCompletionTime,
            `UDPATED_BY` = 'SYSTEM'
        WHERE `INVENTORY_SYNC_MASTER_ID` = _inventorySyncMainId;
    ELSE
        INSERT INTO `inventory_sync_master`
            (`INVENTORY_SYNC_MASTER_ID`, `STATUS`,REASON, `COMMENTS`, `INSERTED_BY`)
        VALUES
            (_inventorySyncMainId, _status,_reason, _comments, 'SYSTEM');
    END IF;
    
    
    
    SELECT  1 as SUCCESS;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYN_ALL_UNQIUE_GLN` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYN_ALL_UNQIUE_GLN` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYN_ALL_UNQIUE_GLN`()
BEGIN
  
  select  distinct `GLN`  from `live_inventory_master` a inner join sku_batch_master b 
  on a.`BATCH_ID`=b.`BATCH_ID` where b.gln is not null  ;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYN_API_REQUEST_PENDING` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYN_API_REQUEST_PENDING` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYN_API_REQUEST_PENDING`()
BEGIN
    DECLARE pending_count INT DEFAULT 0;
    
    SELECT 
        COUNT(*) INTO pending_count
    FROM (
        
        SELECT `BATCH_ID`
        FROM `put_wave_order_master_archive`
        WHERE `BIN_TRANSFER_PAYLOAD_ID` IS NULL and PUT_QUANTITY<>0
        UNION ALL
        
        SELECT a.`BATCH_ID`
        FROM `put_wave_order_master_archive` a
        INNER JOIN `wcs_to_wms_payload` b 
            ON a.`BIN_TRANSFER_PAYLOAD_ID` = b.`PAYLOAD_ID`
        WHERE b.`IS_PROCESSED` = 0
        UNION ALL
        
        SELECT `BATCH_ID`
        FROM `wms_to_wcs_order_line_level_pre_staged_data`
        WHERE `STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL
          AND `ORDER_LINE_PROCESS_STATUS` = 'ORDER_LINE_COMPLETED'
        UNION ALL
        
        SELECT a.`BATCH_ID`
        FROM `wms_to_wcs_storage_request_data` a
        INNER JOIN `wms_to_wcs_storage_request_pallet_data` b 
            ON a.`STORAGE_REQUEST_ID` = b.`STORAGE_REQUEST_ID`
        WHERE a.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL and b.`STORAGE_REQUEST_STATUS` = 'PALLET_COMPLETED'
    
    ) AS pending_data;
    
    IF pending_count > 0 THEN
        SELECT 1 AS SUCCESS;
    ELSE
        SELECT 0 AS SUCCESS;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYN_CHECK_WMS_ACK_RECIVED` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYN_CHECK_WMS_ACK_RECIVED` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYN_CHECK_WMS_ACK_RECIVED`(IN parameters JSON)
BEGIN
    
    
    
    DECLARE _inventorySyncMainId VARCHAR(100);
    DECLARE _startTime DATETIME;
    DECLARE _waveCompletionTime DATETIME;
    DECLARE _comments TEXT;
    DECLARE _status VARCHAR(50);
    DECLARE _dashboardWaveDisable INT;
    DECLARE _inventorySyncGlnModels JSON;
    DECLARE _recordExists INT DEFAULT 0;
    
    
    
    SET _inventorySyncMainId = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.InventorySyncMainId'));
    
    
    
    IF EXISTS (
        SELECT 1 
        FROM `inventory_sync_master` a
        INNER JOIN `inventory_sync_gln_mapping` b 
            ON a.`INVENTORY_SYNC_MASTER_ID` = b.`INVENTORY_SYNC_MASTER_ID`
        WHERE b.`TOTAL_PAGES` > 0 
          AND b.`STATUS` <> 'COMPLETED' and b.`STATUS` <> 'PARTIAL_COMPLETED'
    ) THEN
        SELECT 0 AS SUCCESS;
    ELSE
        SELECT 1 AS SUCCESS;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYN_FLAGGED_BATCH_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYN_FLAGGED_BATCH_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYN_FLAGGED_BATCH_ID`()
BEGIN
    
    DROP TEMPORARY TABLE IF EXISTS flaggedBatchId;
    
    CREATE TEMPORARY TABLE flaggedBatchId (
        batchId VARCHAR(100) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        reason  VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        INDEX idx_batchId (batchId)
    );
    
    INSERT INTO flaggedBatchId (batchId, reason)
    SELECT `BATCH_ID`, 'PUT_BIN_TRANSFER_PENDING'
    FROM `put_wave_order_master_archive`
    WHERE `BIN_TRANSFER_PAYLOAD_ID` IS NULL AND PUT_QUANTITY<>0 ;
    
    INSERT INTO flaggedBatchId (batchId, reason)
    SELECT a.`BATCH_ID`, 'PUT_BIN_TRANSFER_PENDING'
    FROM `put_wave_order_master_archive` a
    INNER JOIN `wcs_to_wms_payload` b 
        ON a.`BIN_TRANSFER_PAYLOAD_ID` = b.`PAYLOAD_ID`
    WHERE b.`IS_PROCESSED` <> 1;
    
   
    
    INSERT INTO flaggedBatchId (batchId, reason)
    SELECT `BATCH_ID`, 'PICK_STOCK_ADJUSTMENT_PENDING'
    FROM `wms_to_wcs_order_line_level_pre_staged_data`
    WHERE `STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL
      AND `ORDER_LINE_PROCESS_STATUS` = 'ORDER_LINE_COMPLETED';
    
    INSERT INTO flaggedBatchId (batchId, reason)
    SELECT a.`BATCH_ID`, 'PICK_STOCK_ADJUSTMENT_PENDING'
    FROM `wms_to_wcs_order_line_level_pre_staged_data` a
    INNER JOIN `wcs_to_wms_payload` b 
        ON a.`STOCK_ADJUSTMENT_PAYLOAD_ID` = b.`PAYLOAD_ID`
    WHERE   b.`IS_PROCESSED` <>1
      AND a.`ORDER_LINE_PROCESS_STATUS` = 'ORDER_LINE_COMPLETED';
    
   
    
    INSERT INTO flaggedBatchId (batchId, reason)
    SELECT a.`BATCH_ID`, 'PUT_STOCK_ADJUSTMENT_PENDING'
    FROM `wms_to_wcs_storage_request_data` a
    INNER JOIN `wms_to_wcs_storage_request_pallet_data` b 
        ON a.`STORAGE_REQUEST_ID` = b.`STORAGE_REQUEST_ID`
    WHERE  b.`STORAGE_REQUEST_STATUS` = 'PALLET_COMPLETED'
    and a.`STOCK_ADJUSTMENT_PAYLOAD_ID` IS NULL;
    
    
    INSERT INTO flaggedBatchId (batchId, reason)
    SELECT a.`BATCH_ID`, 'PUT_STOCK_ADJUSTMENT_PENDING'
    FROM `wms_to_wcs_storage_request_data` a
    INNER JOIN `wms_to_wcs_storage_request_pallet_data` b 
        ON a.`STORAGE_REQUEST_ID` = b.`STORAGE_REQUEST_ID`
    INNER JOIN `wcs_to_wms_payload` c 
        ON a.`STOCK_ADJUSTMENT_PAYLOAD_ID` = c.`PAYLOAD_ID`
    WHERE b.`STORAGE_REQUEST_STATUS` = 'PALLET_COMPLETED'
      AND c.`IS_PROCESSED` <> 1;
    
  
    
    
    select batchId, reason from flaggedBatchId ;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYN_GLN_LOG` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYN_GLN_LOG` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYN_GLN_LOG`(IN parameters JSON)
BEGIN
    
    
    
    DECLARE _inventorySyncGlnId VARCHAR(100);
    DECLARE _gln VARCHAR(100);
    DECLARE _inventorySyncMainId VARCHAR(100);
    DECLARE _totalPages INT;
    DECLARE _comment TEXT;
    DECLARE _status VARCHAR(50);
    DECLARE _neoSyncPreparationTimestamp DATETIME;
    DECLARE _waveCompletionTime DATETIME;
    DECLARE _recordExists INT DEFAULT 0;
    
    
    
    SET _inventorySyncGlnId          = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.InventorySyncGlnId')), UUID());
    SET _gln                         = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.Gln'));
    SET _inventorySyncMainId         = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.InventorySyncMainId'));
    SET _totalPages                  = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.TotalPages')), 0);
    SET _comment                     = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.Comment'));
    SET _status                      = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.Status')), 'PENDING');
    SET _neoSyncPreparationTimestamp = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.NeoSyncPreparationTimestamp'));
    SET _waveCompletionTime          = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.WaveCompletionTime'));
    
    
    
    SELECT COUNT(*) INTO _recordExists
    FROM `inventory_sync_gln_mapping`
    WHERE `INVENTORY_SYN_GLN_MAPPING_ID` = _inventorySyncGlnId;
    
    
    
    IF _recordExists > 0 THEN
        UPDATE `inventory_sync_gln_mapping`
        SET 
            `STATUS` = ifNULL (_status,`STATUS`),
            `COMMENTS` = IFNULL(_comment,COMMENTS),
            `NEO_SYNC_PREPARATION_TIMESTAMP` = IFNULL(_neoSyncPreparationTimestamp,NEO_SYNC_PREPARATION_TIMESTAMP),
            `TOTAL_PAGES` = IFNULL(_totalPages,TOTAL_PAGES),
             `COMPLETION_TIMESTAMP`= IFNULL(_waveCompletionTime,COMPLETION_TIMESTAMP),
            `UPDATED_BY` = IFNULL('SYSTEM',UPDATED_BY)
            
        WHERE `INVENTORY_SYN_GLN_MAPPING_ID` = _inventorySyncGlnId;
    ELSE
        INSERT INTO `inventory_sync_gln_mapping`
            (
                `INVENTORY_SYN_GLN_MAPPING_ID`,
                `INVENTORY_SYNC_MASTER_ID`,
                `GLN`,
                `STATUS`,
                `COMMENTS`,
                `TOTAL_PAGES`,
                `INSERTED_BY`
            )
        VALUES
            (
                _inventorySyncGlnId,
                _inventorySyncMainId,
                _gln,
                _status,
                _comment,
                _totalPages,
                'SYSTEM'
              
            );
    END IF;
    
    
    
    SELECT 
        1 AS SUCCESS;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYN_PAGE_LOG` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYN_PAGE_LOG` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYN_PAGE_LOG`(IN parameters JSON)
BEGIN
    
    
    
    DECLARE _inventorySyncPageId VARCHAR(50);
    DECLARE _inventorySyncGlnId VARCHAR(50);
    DECLARE _inventorySyncMainId VARCHAR(50);
    DECLARE _pageNumber INT;
    DECLARE _totalPages INT;
    DECLARE _pageIdempotencyKey VARCHAR(100);
    DECLARE _recordExists INT DEFAULT 0;
    
    
    
    SET _inventorySyncPageId     = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.InventorySyncPageId'));
    SET _inventorySyncGlnId      = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.InventorySyncGlnId'));
    SET _inventorySyncMainId     = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.InventorySyncMainId'));
    SET _pageIdempotencyKey      = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.PageIdempotencyKey'));
    SET _pageNumber              = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.PageDetails.PageNumber'));
    SET _totalPages              = JSON_UNQUOTE(JSON_EXTRACT(parameters, '$.PageDetails.TotalPages'));
    
    
    
    SELECT COUNT(*) INTO _recordExists
    FROM `inventory_sync_gln_payload_mapping`
    WHERE `INVENTORY_SYNC_GLN_PAYLOAD_MAPPING_ID` = _inventorySyncPageId;
    
    
    
    IF _recordExists > 0 THEN
    
        UPDATE `inventory_sync_gln_payload_mapping`
        SET
            `PAGE_NUMBER` = _pageNumber,
            `TOTAL_PAGES` = _totalPages,
            `PAYLOAD_ID` = _pageIdempotencyKey
            
        WHERE `INVENTORY_SYNC_GLN_PAYLOAD_MAPPING_ID` = _inventorySyncPageId;
    ELSE
        INSERT INTO `inventory_sync_gln_payload_mapping`
            (
                `INVENTORY_SYNC_GLN_PAYLOAD_MAPPING_ID`,
                `INVENTORY_SYNC_MASTER_ID`,
                `INVENTORY_SYNC_GLN_MAPPING_ID`,
                `PAGE_NUMBER`,
                `TOTAL_PAGES`,
                `PAYLOAD_ID`
         
            )
        VALUES
            (
                _inventorySyncPageId,
                _inventorySyncMainId,
                _inventorySyncGlnId,
                _pageNumber,
                _totalPages,
                _pageIdempotencyKey
            );
    END IF;
    
    
    
    SELECT 
        1 AS SUCCESS;
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYN_PAYLOAD_FETCH` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYN_PAYLOAD_FETCH` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYN_PAYLOAD_FETCH`()
BEGIN
    
    
    SELECT *
    FROM `wcs_to_wms_payload` wcs
    WHERE wcs.`API_ID` = 329 
      AND (wcs.IS_PROCESSED <> 1 OR wcs.IS_PROCESSED IS NULL)
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

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYN_WAVE_RUNNING_CHECK` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYN_WAVE_RUNNING_CHECK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYN_WAVE_RUNNING_CHECK`()
BEGIN
	 DECLARE running_count INT DEFAULT 0;
	 
	 
	 SELECT COUNT(*) INTO running_count  FROM `hw_station_master` a INNER JOIN 
`wave_master` b  ON a.`WAVE_ID`=b.`WAVE_ID`
WHERE `STATUS` = 'ENABLED' AND b.`WAVE_TYPE` IN ('PICK','PUT','STOCK_AUDIT');   
 
 
    IF running_count = 0 THEN
        SELECT 1 AS SUCCESS;
    ELSE
        SELECT 0 AS SUCCESS;
    END IF;
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_INVENTORY_SYN_WAVE_RUNNING_CHECK_TEST` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_INVENTORY_SYN_WAVE_RUNNING_CHECK_TEST` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_INVENTORY_SYN_WAVE_RUNNING_CHECK_TEST`()
BEGIN
	 DECLARE running_count INT DEFAULT 0;
	 
	 
	 SELECT COUNT(*) INTO running_count  FROM `hw_station_master` a INNER JOIN 
`wave_master` b  ON a.`WAVE_ID`=b.`WAVE_ID`
WHERE `STATUS` = 'ENABLED' AND b.`WAVE_TYPE` IN ('PICK','PUT','STOCK_AUDIT');   
 
    IF running_count = 0 THEN
        SELECT 1 AS SUCCESS;
    ELSE
        SELECT 0 AS SUCCESS;
    END IF;
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `INT_CRON_PICK_ORDER_REQUEST_COMPLETED_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `INT_CRON_PICK_ORDER_REQUEST_COMPLETED_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `INT_CRON_PICK_ORDER_REQUEST_COMPLETED_STATUS`()
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
		'Status', 'NEO_PICKING_COMPLETED', 
		'EventTimestamp', wm.`UPDATED_TIMESTAMP`
	    )
	
		FROM `wms_to_wcs_order_level_pre_staged_data` wm
		WHERE wm.ORDER_REQUEST_STATUS = 'ORDER_PICK_COMPLETED'
		  AND wm.ORDER_REQUEST_COMPLETED_PAYLOAD IS NULL
		  AND NOT EXISTS (
		      SELECT 1
		      FROM `wms_to_wcs_order_line_level_pre_staged_data` l
		      WHERE l.`PARENT_ORDER_ID` = wm.`PARENT_ORDER_ID`
			AND l.STOCK_ADJUSTMENT_PAYLOAD_ID IS NULL
		  )
		  AND NOT EXISTS (
		      SELECT 1
		      FROM `wms_to_wcs_order_line_level_pre_staged_data` l2
		      JOIN wcs_to_wms_payload p ON l2.STOCK_ADJUSTMENT_PAYLOAD_ID = p.PAYLOAD_ID
		      WHERE l2.`PARENT_ORDER_ID` = wm.`PARENT_ORDER_ID`
			AND p.IS_PROCESSED <> 1
		  )
		LIMIT 500;
    START TRANSACTION;
    
     INSERT IGNORE INTO `wcs_to_wms_payload` (`PAYLOAD_ID`,`API_HEADERS`, `API_ID`, `API_SOURCE`, `JSON_REQUEST`)
    SELECT `payload_id`,headers, '309', 'cronJob', `json_output`
    FROM TempPayloads;
    
        UPDATE `wms_to_wcs_order_level_pre_staged_data` AS C
    INNER JOIN TempPayloads AS T ON C.`WMS_ORDER_REQUEST_DATA_ID` = T.`id`
    SET C.`ORDER_REQUEST_COMPLETED_PAYLOAD` = T.`payload_id`;
    
    COMMIT;
    
    DROP TEMPORARY TABLE IF EXISTS TempPayloads;
    
    
    SELECT *
	FROM `wcs_to_wms_payload` wcs
	WHERE wcs.`API_ID` = 309
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