
/* Procedure structure for procedure `DSB_PAGINATED_DATA_PUT_WAVE_ANALYSIS_BY_DATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_PUT_WAVE_ANALYSIS_BY_DATE` */;
DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_PUT_WAVE_ANALYSIS_BY_DATE`(IN Parameters JSON)
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
        SET v_sorting = ' ORDER BY `STORAGE REQUEST ID` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    
    
    SET v_base_query = CONCAT("
        WITH 
        put_level AS (
            SELECT DISTINCT storage_request_id 
            FROM (
                SELECT storage_request_id 
                FROM put_wave_order_master 
                WHERE put_timestamp BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
                
                UNION
                
                SELECT storage_request_id 
                FROM put_wave_order_master_archive 
                WHERE put_timestamp BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
            ) sub
        ),
        sto AS (
            SELECT 
                combined.`PALLET_ID`,
                MIN(combined.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`) AS `WMS_STORAGE_REQUEST_PALLET_DATA_ID`,
                combined.`STORAGE_REQUEST_ID`
            FROM (
                SELECT 
                    wspd.`PALLET_ID`,
                    wspd.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`,
                    wspd.`STORAGE_REQUEST_ID` 
                FROM `wms_to_wcs_storage_request_pallet_data` wspd
                JOIN put_level pl ON pl.storage_request_id = wspd.`STORAGE_REQUEST_ID`
                
                UNION ALL
                
                SELECT 
                    wspda.`PALLET_ID`,
                    wspda.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`,
                    wspda.`STORAGE_REQUEST_ID`
                FROM `wms_to_wcs_storage_request_pallet_data_archive` wspda
                JOIN put_level pl ON pl.storage_request_id = wspda.`STORAGE_REQUEST_ID`
            ) combined
            GROUP BY combined.`PALLET_ID`, combined.`STORAGE_REQUEST_ID`
        ),
        stor AS (
            SELECT 
                sto.`PALLET_ID`,
                ss.`STORAGE_REQUEST_ID`,
                ss.`STORAGE_ID`,
                ss.`ARTICLE_ID`,
                ss.`quantity`
            FROM `wms_to_wcs_storage_request_data` ss 
            JOIN sto ON sto.`WMS_STORAGE_REQUEST_PALLET_DATA_ID` = ss.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`
            
            UNION ALL
            
            SELECT 
                sto.`PALLET_ID`,
                ssa.`STORAGE_REQUEST_ID`,
                ssa.`STORAGE_ID`,
                ssa.`ARTICLE_ID`,
                ssa.`quantity`
            FROM `wms_to_wcs_storage_request_data_archive` ssa
            JOIN sto ON sto.`WMS_STORAGE_REQUEST_PALLET_DATA_ID` = ssa.`WMS_STORAGE_REQUEST_PALLET_DATA_ID`
        ),
        sku_mast AS (
            SELECT 
                sm.ROS, 
                sm.sku_classification,
                sm.sku_id,
                sm.`MIN_SEGMENT_SIZE`,
                sm.`MAX_QUANTITY_PER_SEGMENT`
            FROM sku_master sm 
            JOIN stor s ON s.ARTICLE_ID = sm.sku_id
        ),
        bin_details AS (
            SELECT 
                COUNT(DISTINCT pwom.bin_id) AS bin_count,
                COUNT(DISTINCT pwom.bin_segment_no) AS segment_count,
                pwom.sku_id, 
                pwom.storage_id, 
                pwom.storage_request_id 
            FROM put_wave_order_master pwom
            JOIN stor ON pwom.storage_id = stor.storage_id 
                AND pwom.storage_request_id = stor.storage_request_id
            GROUP BY pwom.sku_id, pwom.storage_id, pwom.storage_request_id
            
            UNION ALL
            
            SELECT 
                COUNT(DISTINCT pwoma.bin_id) AS bin_count,
                COUNT(DISTINCT pwoma.bin_segment_no) AS segment_count,
                pwoma.sku_id, 
                pwoma.storage_id, 
                pwoma.storage_request_id 
            FROM put_wave_order_master_archive pwoma
            JOIN stor ON pwoma.storage_id = stor.storage_id 
                AND pwoma.storage_request_id = stor.storage_request_id
            GROUP BY pwoma.sku_id, pwoma.storage_id, pwoma.storage_request_id
        )
        SELECT 
            stor.PALLET_ID                                                AS 'PALLET ID',
            stor.STORAGE_REQUEST_ID                                       AS 'STORAGE REQUEST ID',
            stor.STORAGE_ID                                               AS 'STORAGE ID',
            stor.ARTICLE_ID                                               AS 'SKU ID',
            stor.quantity                                                 AS 'TOTAL QUANTITY TO BE KEPT',
            COALESCE(sku_mast.ROS, 0)                                     AS 'RATE OF SALE',
            ROUND((COALESCE(sku_mast.ROS, 0) * 60) / 100, 2)             AS '60% ROS',
            ROUND(stor.quantity / NULLIF(bd.bin_count, 0), 2)            AS 'TOTAL AVG QUANTITY KEPT IN 1 BIN',
            ROUND(stor.quantity / NULLIF(bd.segment_count, 0), 2)        AS 'TOTAL AVG QUANTITY KEPT IN 1 BIN SEGMENT',
            COALESCE(sku_mast.sku_classification, '')                     AS 'SKU CLASSIFICATION',
            COALESCE(sku_mast.MAX_QUANTITY_PER_SEGMENT, 0)               AS 'MAX QUANTITY PER BIN (THEORETICAL)',
            COALESCE(bd.bin_count, 0)                                     AS 'ACTUAL BIN USED',
            COALESCE(bd.segment_count, 0)                                 AS 'ACTUAL BIN SEGMENT USED',
            COALESCE(sku_mast.MIN_SEGMENT_SIZE, 0)                       AS 'MINIMUM SEGMENT SIZE'
        FROM stor
        LEFT JOIN sku_mast ON stor.ARTICLE_ID = sku_mast.sku_id
        LEFT JOIN bin_details bd ON stor.ARTICLE_ID = bd.sku_id 
            AND stor.storage_id = bd.storage_id 
            AND stor.storage_request_id = bd.storage_request_id
        GROUP BY 
            stor.PALLET_ID,
            stor.STORAGE_REQUEST_ID,
            stor.STORAGE_ID,
            stor.ARTICLE_ID,
            stor.quantity,
            sku_mast.ROS,
            sku_mast.sku_classification,
            sku_mast.MAX_QUANTITY_PER_SEGMENT,
            bd.bin_count,
            bd.segment_count,
            sku_mast.MIN_SEGMENT_SIZE
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_SHORT_PUT_LIST` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_SHORT_PUT_LIST` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_SHORT_PUT_LIST`(IN Parameters JSON)
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
    DECLARE p_wave_id VARCHAR(100);
    DECLARE p_station_id INT;
    
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
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters  = Parameters ->> '$.report_extra_parameters';
    SET p_wave_id     = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    SET p_station_id  = CAST(JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.station_id')) AS UNSIGNED);
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF p_sorting_column_name IS NULL OR p_sorting_column_name = '' 
       OR p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '' THEN
        SET v_sorting = ' ORDER BY `INSERTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY ', '`', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    SET v_base_query = CONCAT(
        "SELECT 
	    sm.SKU_NAME AS 'SKU NAME',
            spwr.SHORT_PUT_QUANTITY AS 'SHORT PUT QUANTITY',
            spwr.REASON AS 'REASON',
            pwm.STORAGE_ID AS 'STORAGE ID',
            pwm.PUT_ORDER_ID as 'PUT ORDER ID',
            spwr.SHORT_PUT_WAVE_REASON_ID as 'SHORT PUT WAVE REASON ID',            
            DATE_FORMAT(spwr.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME'
        FROM 
            short_put_wave_reason AS spwr
        INNER JOIN 
            put_wave_order_master AS pwm ON pwm.PUT_ORDER_ID = spwr.PUT_ORDER_ID
        LEFT JOIN 
            sku_master AS sm ON pwm.SKU_ID = sm.SKU_ID
        WHERE 
            pwm.WAVE_ID = '", p_wave_id, "' 
            AND pwm.STATION_ID = '", p_station_id, "'
            AND spwr.REASON <> 'NO_SPACE_IN_BIN'
            AND spwr.RE_ATTEMPT_FLAG = 0 
            AND pwm.SHORT_PUT_QUANTITY > 0 ", 
        p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_SKU_EAN_MAPPING` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_SKU_EAN_MAPPING` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_SKU_EAN_MAPPING`(IN Parameters JSON)
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
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number                 = Parameters ->> '$.page_number';
    SET p_rows_per_page              = Parameters ->> '$.rows_per_page';
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
        SET v_sorting = ' ORDER BY `UPDATED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY ', '`', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition = '' OR p_filter_condition IS NULL THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    
    SET p_table_unique_identifier           = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.report_extra_parameters'));
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    SET v_base_query = CONCAT(
        "SELECT
            sem.ID AS ID,
            sm.SKU_ID AS 'SKU ID', 
            sm.SKU_NAME AS 'SKU NAME',
            sem.EAN_ID AS 'EAN ID',
            sem.INSERTED_BY AS 'INSERTED BY',
            DATE_FORMAT(sem.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
            sem.UPDATED_BY AS 'UPDATED BY',
            DATE_FORMAT(sem.UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME'
         FROM sku_ean_mapping AS sem 
         INNER JOIN sku_master sm ON sem.SKU_ID = sm.SKU_ID",
         p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, 
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_SKU_MASTER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_SKU_MASTER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_SKU_MASTER`(IN Parameters JSON)
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
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number              = Parameters ->> '$.page_number';
    SET p_rows_per_page           = Parameters ->> '$.rows_per_page';
    SET p_user_id                 = Parameters ->> '$.user_id';
    SET p_user_name               = Parameters ->> '$.user_name';
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    SET p_page_zero_metadata_flag = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag              = Parameters ->> '$.count';
    SET p_filter_condition        = Parameters ->> '$.filter_data';
    SET p_select_clause           = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name     = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby  = Parameters ->> '$.sorting_column_orderby';
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `UPDATED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY ', '`', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition = '' OR p_filter_condition IS NULL THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    SET p_table_unique_identifier       = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.report_extra_parameters'));
    
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    SET v_base_query = CONCAT(
        "SELECT 
            sm.SKU_ID AS 'SKU ID',
            sm.SKU_NAME AS 'SKU NAME',
            sm.VELOCITY AS 'VELOCITY',
            cm.CATEGORY_ID AS 'CATEGORY ID',
            cm.CATEGORY_NAME AS 'CATEGORY NAME',
            sm.MIN_SEGMENT_SIZE AS 'MIN SEGMENT SIZE',
            sm.MAX_QUANTITY_PER_SEGMENT AS 'MAX QUANTITY PER SEGMENT',
            sm.HEIGHT AS 'HEIGHT (MM)',
            sm.LENGTH AS 'LENGTH (MM)',
            sm.WIDTH AS 'WIDTH (MM)',
            sm.WEIGHT_OF_EACH_SKU AS 'WEIGHT (GRAMS)',
            DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL) AS 'IMAGE URL',
            sm.INSERTED_BY AS 'INSERTED BY',
            DATE_FORMAT(sm.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
            sm.UPDATED_BY AS 'UPDATED BY',
            DATE_FORMAT(sm.UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME'
         FROM sku_master sm
         LEFT JOIN category_master cm ON cm.CATEGORY_ID = sm.CATEGORY",
         p_filter_condition
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_SYSTEM_LEVEL_BIN_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_SYSTEM_LEVEL_BIN_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_SYSTEM_LEVEL_BIN_SUMMARY`(IN Parameters JSON)
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
    DECLARE v_bin_volume DECIMAL(15,3) DEFAULT 0;
    
    DECLARE v_total_bins INT DEFAULT 0;
    DECLARE v_empty_bins INT DEFAULT 0;
    DECLARE v_fully_utilized_bins INT DEFAULT 0;
    DECLARE v_partially_utilized_bins INT DEFAULT 0;
    DECLARE v_total_volume_capacity DECIMAL(15,3) DEFAULT 0;
    DECLARE v_total_volume_used DECIMAL(15,3) DEFAULT 0;
    DECLARE v_avg_utilization DECIMAL(5,2) DEFAULT 0;
    
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
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    SET v_bin_volume = 81 * 57 * 42.5 * 0.95; 
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY METRIC_ORDER ASC';
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
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_bin_analysis;
    CREATE TEMPORARY TABLE temp_bin_analysis (
        BIN_ID INT,
        total_quantity INT DEFAULT 0,
        total_volume_used DECIMAL(15,3) DEFAULT 0,
        utilization_percentage DECIMAL(5,2) DEFAULT 0,
        bin_status ENUM('EMPTY', 'PARTIALLY_UTILIZED', 'FULLY_UTILIZED') DEFAULT 'EMPTY'
    );
    
    INSERT INTO temp_bin_analysis (BIN_ID, total_quantity, total_volume_used)
    SELECT 
        bim.BIN_ID,
        COALESCE(SUM(lim.QUANTITY), 0) AS total_quantity,
        COALESCE(SUM(lim.QUANTITY * COALESCE((sm.LENGTH * sm.WIDTH * sm.HEIGHT) / 1000, 0)), 0) AS total_volume_used
    FROM bin_info_master bim
    LEFT JOIN live_inventory_master lim ON bim.BIN_ID = lim.BIN_ID 
        AND (lim.IS_ACTIVE IS NULL OR lim.IS_ACTIVE = 1)
    LEFT JOIN sku_master sm ON lim.ARTICLE_ID = sm.SKU_ID 
        AND (sm.IS_ACTIVE IS NULL OR sm.IS_ACTIVE = 1)
    GROUP BY bim.BIN_ID;
    
    UPDATE temp_bin_analysis 
    SET 
        utilization_percentage = (total_volume_used / v_bin_volume) * 100,
        bin_status = CASE 
            WHEN total_volume_used = 0 THEN 'EMPTY'
            WHEN (total_volume_used / v_bin_volume) * 100 >= 90 THEN 'FULLY_UTILIZED'
            ELSE 'PARTIALLY_UTILIZED'
        END;
    
    SELECT COUNT(*) INTO v_total_bins FROM bin_info_master;
    SELECT COUNT(*) INTO v_empty_bins 
    FROM temp_bin_analysis 
    WHERE bin_status = 'EMPTY';
    SELECT COUNT(*) INTO v_fully_utilized_bins 
    FROM temp_bin_analysis 
    WHERE bin_status = 'FULLY_UTILIZED';
    SELECT COUNT(*) INTO v_partially_utilized_bins 
    FROM temp_bin_analysis 
    WHERE bin_status = 'PARTIALLY_UTILIZED';
    
    SET v_total_volume_capacity = v_total_bins * v_bin_volume;
    
    SELECT COALESCE(SUM(total_volume_used), 0) INTO v_total_volume_used 
    FROM temp_bin_analysis;
    
    IF v_total_volume_capacity > 0 THEN
        SET v_avg_utilization = (v_total_volume_used / v_total_volume_capacity) * 100;
    END IF;
    
    SET v_base_query = CONCAT(
        "SELECT 
            system_metrics.metric_name AS 'METRIC',
            system_metrics.metric_value AS 'VALUE',
            system_metrics.metric_order AS 'METRIC_ORDER'
        FROM (
            SELECT 'Total Bins' as metric_name, CAST(", v_total_bins, " AS CHAR) as metric_value, 1 as metric_order
            UNION ALL
            SELECT 'Fully Utilized Bins' as metric_name, CAST(", v_fully_utilized_bins, " AS CHAR) as metric_value, 2 as metric_order
            UNION ALL
            SELECT 'Partially Utilized Bins' as metric_name, CAST(", v_partially_utilized_bins, " AS CHAR) as metric_value, 3 as metric_order
            UNION ALL
            SELECT 'Empty Bins' as metric_name, CAST(", v_empty_bins, " AS CHAR) as metric_value, 4 as metric_order
            UNION ALL
            SELECT 'Average Bin Utilization %' as metric_name, CONCAT(ROUND(", v_avg_utilization, ", 1), '%') as metric_value, 5 as metric_order
            UNION ALL
            SELECT 'Total Volume Capacity' as metric_name, FORMAT(", v_total_volume_capacity, ", 0) as metric_value, 6 as metric_order
            UNION ALL
            SELECT 'Total Volume Used' as metric_name, FORMAT(", v_total_volume_used, ", 0) as metric_value, 7 as metric_order
        ) system_metrics",
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
    
    DROP TEMPORARY TABLE temp_bin_analysis;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_TOWER_DETAILS_BY_X_Y` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_TOWER_DETAILS_BY_X_Y` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_TOWER_DETAILS_BY_X_Y`(IN Parameters JSON)
BEGIN
    DECLARE p_page_number             INT;
    DECLARE p_rows_per_page           INT;
    DECLARE p_download_flag           BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag              INT;
    DECLARE p_filter_condition        VARCHAR(2000) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE p_select_clause           TEXT;
    DECLARE p_sorting_column_name     VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE p_sorting_column_orderby  VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE p_user_id                 VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_user_name               VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_table_unique_identifier VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_x                       INT;
    DECLARE p_y                       INT;
    DECLARE v_sorting         VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_base_query      TEXT;
    DECLARE v_total_rows      INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
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
    SET p_report_extra_parameters = JSON_EXTRACT(Parameters, '$.report_extra_parameters');
    SET p_x                       = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.x'));
    SET p_y                       = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.y'));
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `BIN ID` IS NULL, `LAST UPDATED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    DROP TEMPORARY TABLE IF EXISTS latest_log;
    CREATE TEMPORARY TABLE latest_log (
        BOT_ID VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci,
        END_LOCATION_ID INT,
        LOGGED_TIMESTAMP DATETIME,
        PRIMARY KEY (END_LOCATION_ID)
    );
    INSERT INTO latest_log (BOT_ID, END_LOCATION_ID, LOGGED_TIMESTAMP)
    SELECT 
        ranked.BOT_ID,
        ranked.END_LOCATION_ID,
        ranked.LOGGED_TIMESTAMP
    FROM (
        SELECT 
            tdl.BOT_ID,
            tdl.END_LOCATION_ID,
            tdl.LOGGED_TIMESTAMP,
            ROW_NUMBER() OVER (PARTITION BY tdl.END_LOCATION_ID ORDER BY tdl.LOGGED_TIMESTAMP DESC) AS rn
        FROM task_detail_log tdl
        JOIN task_master_log tml ON tml.TASK_ID = tdl.TASK_MASTER_ID
        WHERE tdl.LOGGED_TIMESTAMP >= CONCAT(DATE(DATE_ADD(NOW(),INTERVAL -1 DAY)) ,' 00:00:00') 
            AND tml.STATUS = 'COMPLETED'
            AND tdl.END_PICK_PUT_SIDE = 'PUT'
    ) AS ranked
    WHERE ranked.rn = 1;
    SET v_base_query = CONCAT(
        "SELECT 
            lm.LOCATION_ID AS 'LOCATION ID',
            CONCAT('Level ', (lm.Z + 1)) AS 'LEVEL',
            lm.Z AS 'Z',
            sbm.BIN_ID AS 'BIN ID',
            CASE WHEN sbm.BIN_ID IS NOT NULL THEN ll.BOT_ID ELSE NULL END AS 'BOT ID',
            CASE WHEN sbm.BIN_ID IS NOT NULL THEN DATE_FORMAT(ll.LOGGED_TIMESTAMP, '", v_datetime_format, "') ELSE NULL END AS 'LAST UPDATED TIME'
        FROM store_bin_master sbm
        LEFT JOIN location_master lm ON lm.LOCATION_ID = sbm.LOCATION_ID
        LEFT JOIN latest_log ll ON ll.END_LOCATION_ID = sbm.LOCATION_ID
        WHERE lm.X = ", p_x, " AND lm.Y = ", p_y, p_filter_condition, " "
    );
    SET v_paginated_query = CONCAT(
        'SELECT ', p_select_clause,
        ' FROM (', v_base_query, ') AS subquery ',
        v_sorting,
        ' LIMIT ', p_page_number * p_rows_per_page, ', ', p_rows_per_page
    );
    SET @countQuery = CONCAT('SELECT COUNT(1) INTO @rowCount FROM (', v_base_query, ') AS t');
    PREPARE stmt FROM @countQuery;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
    SET v_total_rows = @rowCount;
    IF p_count_flag = 1 THEN
        SELECT v_total_rows AS `TOTAL_ROWS`;
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_USERS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_USERS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_USERS`(IN Parameters JSON)
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
    DECLARE p_role_id INT; 
    
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
        IF p_user_name = 'falcon_superadmin' THEN
            SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
        ELSE
            SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
        END IF;
    END IF;
    SET p_table_unique_identifier           = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.report_extra_parameters'));
    SET p_role_id = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.role_id'));
    
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    IF p_user_name = 'falcon_superadmin' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                dum.IS_ACTIVE AS 'USER STATUS',
                dursm.IS_ACTIVE AS 'ROLE STATUS',
                dum.USER_ID AS 'USER ID',
                dum.USER_NAME AS 'USER NAME',
                dum.USER_FULL_NAME AS 'USER FULL NAME',
                drm.ROLE_ID AS 'ROLE ID',
                drm.ROLE_NAME AS 'ROLE NAME',
                DATE_FORMAT(dursm.LOGIN_TIMESTAMP, '", v_datetime_format, "') AS 'LOGIN TIME',
                DATE_FORMAT(dursm.LOGOUT_TIMESTAMP, '", v_datetime_format, "') AS 'LOGOUT TIME',
                dursm.IS_LOCKED AS 'IS LOCKED',
                DATE_FORMAT(dursm.IS_LOCKED_TIMESTAMP, '", v_datetime_format, "') AS 'IS LOCKED TIME',
                dursm.GRID_SHOW_TOOLTIP AS 'SHOW GRID TOOLTIP',
                DATE_FORMAT(dum.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
                dum.INSERTED_BY AS 'INSERTED BY',
                DATE_FORMAT(dum.UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME',
                dum.UPDATED_BY AS 'UPDATED BY'
             FROM dashboard_user_master dum
             LEFT JOIN dashboard_user_role_setting_mapping dursm ON dursm.USER_ID = dum.USER_ID
             LEFT JOIN dashboard_role_master drm ON dursm.ROLE_ID = drm.ROLE_ID",
             p_filter_condition
        );
    ELSE
        SET v_base_query = CONCAT(
            "SELECT 
                dum.IS_ACTIVE AS 'USER STATUS',
                dursm.IS_ACTIVE AS 'ROLE STATUS',
                dum.USER_ID AS 'USER ID',
                dum.USER_NAME AS 'USER NAME',
                dum.USER_FULL_NAME AS 'USER FULL NAME',
                drm.ROLE_ID AS 'ROLE ID',
                drm.ROLE_NAME AS 'ROLE NAME',
                DATE_FORMAT(dursm.LOGIN_TIMESTAMP, '", v_datetime_format, "') AS 'LOGIN TIME',
                DATE_FORMAT(dursm.LOGOUT_TIMESTAMP, '", v_datetime_format, "') AS 'LOGOUT TIME',
                dursm.IS_LOCKED AS 'IS LOCKED',
                DATE_FORMAT(dursm.IS_LOCKED_TIMESTAMP, '", v_datetime_format, "') AS 'IS LOCKED TIME',
                dursm.GRID_SHOW_TOOLTIP AS 'SHOW GRID TOOLTIP',
                DATE_FORMAT(dum.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
                dum.INSERTED_BY AS 'INSERTED BY',
                DATE_FORMAT(dum.UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME',
                dum.UPDATED_BY AS 'UPDATED BY'
             FROM dashboard_user_master dum
             LEFT JOIN dashboard_user_role_setting_mapping dursm ON dursm.USER_ID = dum.USER_ID
             LEFT JOIN dashboard_role_master drm ON dursm.ROLE_ID = drm.ROLE_ID
             WHERE (
                 (", p_role_id, " = 1 AND drm.ROLE_ID IN (SELECT ROLE_ID FROM dashboard_role_master WHERE ROLE_ID <> 1)) OR
                 (", p_role_id, " = 4 AND drm.ROLE_ID IN (5,8)) OR
                 (", p_role_id, " NOT IN (1,4) AND dursm.USER_ID = 0)
             )",
             p_filter_condition
        );
    END IF;
    
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_BIN_LOADING_ORDERS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_BIN_LOADING_ORDERS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_BIN_LOADING_ORDERS`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number               INT;
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
    DECLARE p_report_extra_parameters  JSON;
    DECLARE p_wave_id                  VARCHAR(50);
    DECLARE p_wave_status              VARCHAR(50);
    
    DECLARE v_sorting           VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format   VARCHAR(50);
    DECLARE v_date_format       VARCHAR(50);
    DECLARE v_base_query        TEXT;
    DECLARE v_total_rows        INT DEFAULT 0;
    DECLARE v_paginated_query   TEXT;
    
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
    SET p_report_extra_parameters  = Parameters ->> '$.report_extra_parameters';
    SET p_wave_id                  = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF p_sorting_column_name IS NULL OR p_sorting_column_name = ''
       OR p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '' THEN
        SET v_sorting = ' ORDER BY `UPDATED TIME` DESC';
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
    
    SET v_base_query = CONCAT(
        "SELECT 
            BIN_ID AS 'BIN ID',
            BIN_BARCODE AS 'BIN BARCODE',
            BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
            ORDER_BIN_ID AS 'ORDER BIN ID',
            STATION_ID AS 'STATION ID',
            STATUS AS 'BIN STATUS',
            INSERTED_TIMESTAMP AS 'INSERTED TIME',
            UPDATED_TIMESTAMP AS 'UPDATED TIME',
            UPDATED_BY AS 'UPDATED BY'
        FROM 
            bin_loading_wave_order_master
        WHERE 
            WAVE_ID = '", p_wave_id, "' ", p_filter_condition
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_GENERIC` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_GENERIC` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_GENERIC`(IN Parameters JSON)
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
    DECLARE p_report_name VARCHAR(255);
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_start_date_time VARCHAR(50);
    DECLARE p_end_date_time VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    DECLARE v_wave_condition TEXT;
    
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
    
    IF p_report_name = 'PAGINATED_PICK_WAVE' THEN
        SET v_wave_condition = "WAVE_TYPE = 'PICK'";
    ELSEIF p_report_name = 'PAGINATED_PUT_WAVE' THEN
        SET v_wave_condition = "WAVE_TYPE = 'PUT'";
    ELSEIF p_report_name = 'PAGINATED_STOCK_AUDIT_WAVE' THEN
        SET v_wave_condition = "WAVE_TYPE = 'STOCK_AUDIT'";
    ELSEIF p_report_name = 'PAGINATED_BIN_LOADING_WAVE' THEN
        SET v_wave_condition = "WAVE_TYPE = 'BIN_LOADING'";
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid report name for wave data.';
    END IF;
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `UPDATED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = CONCAT(" AND INSERTED_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'");
    ELSE
        SET p_filter_condition = CONCAT(" AND INSERTED_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "' AND ", p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    SET v_base_query = CONCAT(
        "SELECT
            WAVE_ID AS 'WAVE ID', 
            WAVE_TYPE AS 'WAVE TYPE',
            WAVE_STATUS AS 'WAVE STATUS',
            DATE_FORMAT(START_TIMESTAMP, '", v_datetime_format, "') AS 'START TIME',
            DATE_FORMAT(COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'COMPLETED TIME',
            DATE_FORMAT(CANCELLED_TIMESTAMP, '", v_datetime_format, "') AS 'SUSPENDED TIME',
            INSERTED_BY AS 'INSERTED BY', 
            DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
            UPDATED_BY AS 'UPDATED BY', 
            DATE_FORMAT(UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME'
        FROM wave_master
        WHERE IS_ACTIVE = 1 AND (", v_wave_condition, ")", p_filter_condition,
        
        " UNION ALL
        SELECT
            WAVE_ID AS 'WAVE ID', 
            WAVE_TYPE AS 'WAVE TYPE',
            WAVE_STATUS AS 'WAVE STATUS',
            DATE_FORMAT(START_TIMESTAMP, '", v_datetime_format, "') AS 'START TIME',
            DATE_FORMAT(COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'COMPLETED TIME',
            DATE_FORMAT(CANCELLED_TIMESTAMP, '", v_datetime_format, "') AS 'SUSPENDED TIME',
            INSERTED_BY AS 'INSERTED BY', 
            DATE_FORMAT(INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
            UPDATED_BY AS 'UPDATED BY', 
            DATE_FORMAT(UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME'
        FROM wave_master_archive
        WHERE IS_ACTIVE = 1 AND (", v_wave_condition, ")", p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL`(IN Parameters JSON)
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
    DECLARE p_wave_id VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
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
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET p_table_unique_identifier         = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters   = Parameters ->> '$.report_extra_parameters';
    SET p_wave_id                   = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    SET v_base_query = CONCAT(
        "SELECT 
            pwm.ORDER_ID AS 'ORDER ID',
            pwm.SKU_ID AS 'SKU ID',
            sbm.MRP AS 'MRP',
            pwm.BIN_ID AS 'BIN ID',
            pwm.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
            DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
            pwm.EXPECTED_QUANTITY AS 'EXPECTED QUANTITY',
            pwm.STATION_ID AS 'STATION ID',
            pwm.PICKED_QUANTITY AS 'PICK QUANTITY',
            pwm.SHORT_PICK_QUANTITY AS 'SHORT PICK QUANTITY',
            pwm.PICK_TIMESTAMP AS 'PICK END TIME',
            obm.LOGGED_TIMESTAMP AS 'BIN ON STATION'
        FROM pick_wave_order_master_archive pwm
        INNER JOIN wave_master_archive wma ON pwm.WAVE_ID = wma.WAVE_ID
        INNER JOIN sku_batch_master sbm ON sbm.BATCH_ID = pwm.BATCH_ID
        INNER JOIN order_bin_mapping_log obm ON obm.ORDER_BIN_ID = pwm.ORDER_BIN_ID
        WHERE wma.WAVE_ID = '", p_wave_id, "' AND obm.STATUS = 'ON_STATION'", 
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL_BY_DATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL_BY_DATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL_BY_DATE`(IN Parameters JSON)
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
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    
    IF p_sorting_column_name IS NULL OR p_sorting_column_name = '' THEN
        SET v_sorting = ' ORDER BY `PICK END TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    
    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_pick_wave;
    CREATE TEMPORARY TABLE temp_pick_wave AS
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
        SKU_ID, BATCH_ID, STATION_ID, 
        MAX(EXPECTED_QUANTITY) AS EXPECTED_QUANTITY, 
        MAX(PICKED_QUANTITY) AS PICKED_QUANTITY, 
        MAX(SHORT_PICK_QUANTITY) AS SHORT_PICK_QUANTITY,
        MAX(PICK_START_TIMESTAMP) AS PICK_START_TIMESTAMP, 
        MAX(PICK_TIMESTAMP) AS PICK_TIMESTAMP, 
        MAX(PICK_BY) AS PICK_BY
    FROM pick_wave_order_master_archive
    WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED')
      AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
      AND PICKED_QUANTITY > 0
    GROUP BY PICK_ORDER_ID, WAVE_ID, ORDER_ID, ORDER_LINE_ID, ORDER_BIN_ID, BIN_ID, 
             BIN_SEGMENT_NO, SKU_ID, BATCH_ID, STATION_ID;

    
    ALTER TABLE temp_pick_wave 
        ADD INDEX idx_order_bin_id (ORDER_BIN_ID),
        ADD INDEX idx_order_id (ORDER_ID),
        ADD INDEX idx_batch_id (BATCH_ID),
        ADD INDEX idx_order_line_id (ORDER_LINE_ID),
        ADD INDEX idx_pick_timestamp (PICK_TIMESTAMP);

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_order_bin_ids;
    CREATE TEMPORARY TABLE temp_order_bin_ids AS
    SELECT DISTINCT ORDER_BIN_ID FROM temp_pick_wave;

    ALTER TABLE temp_order_bin_ids ADD INDEX idx_order_bin_id (ORDER_BIN_ID);

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_order_line_ids;
    CREATE TEMPORARY TABLE temp_order_line_ids AS
    SELECT DISTINCT ORDER_LINE_ID FROM temp_pick_wave;

    ALTER TABLE temp_order_line_ids ADD INDEX idx_order_line_id (ORDER_LINE_ID);

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_order_ids;
    CREATE TEMPORARY TABLE temp_order_ids AS
    SELECT DISTINCT ORDER_ID FROM temp_pick_wave;

    ALTER TABLE temp_order_ids ADD INDEX idx_order_id (ORDER_ID);

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_mapping_log;
    CREATE TEMPORARY TABLE temp_mapping_log AS
    SELECT
        ORDER_BIN_ID, BIN_ID, STATION_ID,
        MAX(CASE WHEN STATUS = 'BIN_PICKED' THEN BOT_ID END) AS TASK_ALLOCATED_BOT_ID,
        MAX(CASE WHEN STATUS = 'PRE_ON_STATION' THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
        MAX(CASE WHEN STATUS = 'ON_STATION' THEN UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
    FROM order_bin_mapping_log
    WHERE TYPE = 'RACK_PICK'
      AND ORDER_BIN_ID IN (SELECT ORDER_BIN_ID FROM temp_order_bin_ids)
    GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID;

    ALTER TABLE temp_mapping_log 
        ADD INDEX idx_order_bin_id (ORDER_BIN_ID);

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_order_lines_part1;
    CREATE TEMPORARY TABLE temp_order_lines_part1 AS
    SELECT DISTINCT wtw.ORDER_LINE_ID, wtw.parent_order_id 
    FROM wms_to_wcs_order_line_level_pre_staged_data wtw
    INNER JOIN temp_order_line_ids toli ON wtw.ORDER_LINE_ID = toli.ORDER_LINE_ID;

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_order_lines_part2;
    CREATE TEMPORARY TABLE temp_order_lines_part2 AS
    SELECT DISTINCT wtw.ORDER_LINE_ID, wtw.parent_order_id 
    FROM wms_to_wcs_order_line_level_pre_staged_data_archive wtw
    INNER JOIN temp_order_line_ids toli ON wtw.ORDER_LINE_ID = toli.ORDER_LINE_ID;

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_order_lines;
    CREATE TEMPORARY TABLE temp_order_lines AS
    SELECT * FROM temp_order_lines_part1
    UNION ALL
    SELECT * FROM temp_order_lines_part2;

    ALTER TABLE temp_order_lines 
        ADD INDEX idx_order_line_id (ORDER_LINE_ID),
        ADD INDEX idx_parent_order_id (parent_order_id);

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_parent_order_ids;
    CREATE TEMPORARY TABLE temp_parent_order_ids AS
    SELECT DISTINCT parent_order_id FROM temp_order_lines;

    ALTER TABLE temp_parent_order_ids ADD INDEX idx_parent_order_id (parent_order_id);

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_batch_pick_part1;
    CREATE TEMPORARY TABLE temp_batch_pick_part1 AS
    SELECT BATCH_PICKLIST_CODE, PARENT_ORDER_ID
    FROM wms_to_wcs_order_level_pre_staged_data
    WHERE PARENT_ORDER_ID IN (SELECT parent_order_id FROM temp_parent_order_ids)
    GROUP BY BATCH_PICKLIST_CODE, PARENT_ORDER_ID;

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_batch_pick_part2;
    CREATE TEMPORARY TABLE temp_batch_pick_part2 AS
    SELECT BATCH_PICKLIST_CODE, PARENT_ORDER_ID
    FROM wms_to_wcs_order_level_pre_staged_data_archive
    WHERE PARENT_ORDER_ID IN (SELECT parent_order_id FROM temp_parent_order_ids)
    GROUP BY BATCH_PICKLIST_CODE, PARENT_ORDER_ID;

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_batch_pick;
    CREATE TEMPORARY TABLE temp_batch_pick AS
    SELECT * FROM temp_batch_pick_part1
    UNION ALL
    SELECT * FROM temp_batch_pick_part2;

    ALTER TABLE temp_batch_pick 
        ADD INDEX idx_parent_order_id (PARENT_ORDER_ID);

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_distinct_orders;
    CREATE TEMPORARY TABLE temp_distinct_orders AS
    SELECT DISTINCT w.order_id, w.order_type 
    FROM wms_to_wcs_order_request_data w
    INNER JOIN temp_order_ids toi ON w.order_id = toi.ORDER_ID;

    ALTER TABLE temp_distinct_orders 
        ADD INDEX idx_order_id (order_id);

    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_final_results;
    CREATE TEMPORARY TABLE temp_final_results AS
    SELECT
        cpw.WAVE_ID AS 'WAVE ID',
        cpw.STATION_ID AS 'STATION ID',
        bpd.BATCH_PICKLIST_CODE AS 'BATCH PICKLIST CODE',
        cpw.ORDER_ID AS 'ORDER ID',
        doi.order_type AS 'ORDER TYPE',
        cpw.SKU_ID AS 'SKU ID',
        cpw.BIN_ID AS 'BIN ID',
        cpw.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
        sbm.MRP AS 'MRP',
        DATE_FORMAT(sbm.EXPIRY_DATE, v_date_format) AS 'EXPIRY',
        cpw.EXPECTED_QUANTITY AS 'EXPECTED QUANTITY',
        cpw.PICKED_QUANTITY AS 'PICK QUANTITY',
        cpw.SHORT_PICK_QUANTITY AS 'SHORT PICK QUANTITY',
        DATE_FORMAT(
            CASE 
                WHEN cml.ON_STATION_TIMESTAMP < cpw.PICK_START_TIMESTAMP 
                THEN cml.ON_STATION_TIMESTAMP 
                ELSE cpw.PICK_START_TIMESTAMP 
            END, 
            v_datetime_format
        ) AS 'ON STATION TIME',
        DATE_FORMAT(cpw.PICK_START_TIMESTAMP, v_datetime_format) AS 'PICK STARTED TIME',
        DATE_FORMAT(cpw.PICK_TIMESTAMP, v_datetime_format) AS 'PICK END TIME',
        TIMESTAMPDIFF(SECOND, cpw.PICK_START_TIMESTAMP, cpw.PICK_TIMESTAMP) AS 'DIFFERENCE (IN SECS)',
        cpw.PICK_BY AS 'PICK BY',
        cml.TASK_ALLOCATED_BOT_ID AS 'BIN PUT BOT ID',
        DATE_FORMAT(cml.PRE_ON_STATION_TIMESTAMP, v_datetime_format) AS 'BIN PUT TIME'
    FROM temp_pick_wave cpw
    JOIN temp_mapping_log cml ON cpw.ORDER_BIN_ID = cml.ORDER_BIN_ID
    JOIN temp_distinct_orders doi ON cpw.ORDER_ID = doi.order_id
    JOIN sku_batch_master sbm ON cpw.BATCH_ID = sbm.BATCH_ID
    JOIN temp_order_lines oli ON cpw.ORDER_LINE_ID = oli.ORDER_LINE_ID
    JOIN temp_batch_pick bpd ON oli.parent_order_id = bpd.PARENT_ORDER_ID;
    
    
    
    
    SET @countQuery = CONCAT("SELECT COUNT(*) INTO @rowCount FROM temp_final_results", p_filter_condition);
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
            SET v_paginated_query = CONCAT(
                "SELECT ", p_select_clause, 
                " FROM temp_final_results", 
                p_filter_condition,
                v_sorting, 
                " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
            );
            SET @finalQuery = v_paginated_query;
        END IF;
        
        PREPARE stmt FROM @finalQuery;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
    
    
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_pick_wave;
    DROP TEMPORARY TABLE IF EXISTS temp_order_bin_ids;
    DROP TEMPORARY TABLE IF EXISTS temp_order_line_ids;
    DROP TEMPORARY TABLE IF EXISTS temp_order_ids;
    DROP TEMPORARY TABLE IF EXISTS temp_mapping_log;
    DROP TEMPORARY TABLE IF EXISTS temp_order_lines_part1;
    DROP TEMPORARY TABLE IF EXISTS temp_order_lines_part2;
    DROP TEMPORARY TABLE IF EXISTS temp_order_lines;
    DROP TEMPORARY TABLE IF EXISTS temp_parent_order_ids;
    DROP TEMPORARY TABLE IF EXISTS temp_batch_pick_part1;
    DROP TEMPORARY TABLE IF EXISTS temp_batch_pick_part2;
    DROP TEMPORARY TABLE IF EXISTS temp_batch_pick;
    DROP TEMPORARY TABLE IF EXISTS temp_distinct_orders;
    DROP TEMPORARY TABLE IF EXISTS temp_final_results;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL_BY_DATE_OLD` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL_BY_DATE_OLD` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_BIN_LEVEL_BY_DATE_OLD`(IN Parameters JSON)
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
    DECLARE p_start_date_time VARCHAR(50);
    DECLARE p_end_date_time VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
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
    SET p_table_unique_identifier         = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `PICK END TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY ', '`', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = " ";
    ELSE
        SET p_filter_condition = CONCAT(" AND ", p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    DROP TEMPORARY TABLE IF EXISTS t_start_time;
    CREATE TEMPORARY TABLE t_start_time AS
        SELECT 
            a.ORDER_LINE_ID, 
            SUM(a.LEFT_OVER) AS LEFT_OVER,
            MIN(a.INSERTED_TIMESTAMP) AS INSERTED_TIMESTAMP
        FROM (
            SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP 
            FROM pick_wave_wms_data
            WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
            UNION ALL
            SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP 
            FROM pick_wave_wms_data_archive
            WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        ) a
        GROUP BY a.ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS t_complete_time;
    CREATE TEMPORARY TABLE t_complete_time AS
        SELECT ORDER_LINE_ID, MAX(UPDATED_TIMESTAMP) AS COMPLETE_TIME
        FROM wms_to_wcs_order_line_level_pre_staged_data
        WHERE UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_LINE_ID
        UNION ALL
        SELECT ORDER_LINE_ID, MAX(UPDATED_TIMESTAMP) AS COMPLETE_TIME
        FROM wms_to_wcs_order_line_level_pre_staged_data_archive
        WHERE UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS t;
    CREATE TEMPORARY TABLE t (
        WMS_ORDER_REQUEST_DATA_ID BIGINT,
        BATCH_PICKLIST_CODE VARCHAR(100),
        ORDER_ID VARCHAR(100),
        ORDER_LINE_ID VARCHAR(100),
        ARTICLE_ID VARCHAR(100),
        BATCH_ID varchar(100),
        QUANTITY INT,
        LEFT_OVER INT,
        START_TIME DATETIME,
        COMPLETE_TIME DATETIME
    );
    
    INSERT INTO t
    SELECT 
        MIN(wtword.WMS_ORDER_REQUEST_DATA_ID),
        wtword.BATCH_PICKLIST_CODE,
        wtword.ORDER_ID,
        wtwolrd.ORDER_LINE_ID,
        wtwolrd.ARTICLE_ID,
        wtwolrd.BATCH_ID,
        wtwolrd.QUANTITY,
        tst.LEFT_OVER,
        tst.INSERTED_TIMESTAMP,
        tct.COMPLETE_TIME
    FROM wms_to_wcs_order_level_pre_staged_data wtword
    JOIN wms_to_wcs_order_line_level_pre_staged_data wtwolrd 
        ON wtwolrd.WMS_ORDER_REQUEST_DATA_ID = wtword.WMS_ORDER_REQUEST_DATA_ID
    JOIN t_start_time tst 
        ON tst.ORDER_LINE_ID = wtwolrd.ORDER_LINE_ID
    LEFT JOIN t_complete_time tct 
        ON tct.ORDER_LINE_ID = wtwolrd.ORDER_LINE_ID
    
    GROUP BY wtword.BATCH_PICKLIST_CODE, wtword.ORDER_ID, wtwolrd.ORDER_LINE_ID;
    
    INSERT INTO t
    SELECT 
        MIN(wtworda.WMS_ORDER_REQUEST_DATA_ID),
        wtworda.BATCH_PICKLIST_CODE,
        wtworda.ORDER_ID,
        wtwolrda.ORDER_LINE_ID,
        wtwolrda.ARTICLE_ID,
        wtwolrda.BATCH_ID,
        wtwolrda.QUANTITY,
        tst.LEFT_OVER,
        tst.INSERTED_TIMESTAMP,
        tct.COMPLETE_TIME
    FROM wms_to_wcs_order_level_pre_staged_data_archive wtworda
    JOIN wms_to_wcs_order_line_level_pre_staged_data_archive wtwolrda
        ON wtwolrda.WMS_ORDER_REQUEST_DATA_ID = wtworda.WMS_ORDER_REQUEST_DATA_ID
    JOIN t_start_time tst 
        ON tst.ORDER_LINE_ID = wtwolrda.ORDER_LINE_ID
    LEFT JOIN t_complete_time tct 
        ON tct.ORDER_LINE_ID = wtwolrda.ORDER_LINE_ID
    
    GROUP BY wtworda.BATCH_PICKLIST_CODE, wtworda.ORDER_ID, wtwolrda.ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS total_pick;
    CREATE TEMPORARY TABLE total_pick AS
        SELECT 
            b.WAVE_ID,
            t.ORDER_LINE_ID,
            b.BIN_ID,
            b.BIN_SEGMENT_NO, 
            b.STATION_ID,
            b.ORDER_BIN_ID,
            COALESCE(SUM(b.EXPECTED_QUANTITY), 0) AS EXPECTED_QUANTITY,
            COALESCE(SUM(b.PICKED_QUANTITY), 0) AS TOTAL_PICKED,
            b.PICK_START_TIMESTAMP,
            b.PICK_TIMESTAMP,
            b.PICK_BY
        FROM t
        LEFT JOIN (
            SELECT WAVE_ID, ORDER_LINE_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATION_ID, EXPECTED_QUANTITY,  PICKED_QUANTITY, PICK_START_TIMESTAMP, PICK_TIMESTAMP, PICK_BY
            FROM pick_wave_order_master 
            WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED') AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
            UNION ALL
            SELECT WAVE_ID, ORDER_LINE_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATION_ID, EXPECTED_QUANTITY, PICKED_QUANTITY, PICK_START_TIMESTAMP, PICK_TIMESTAMP, PICK_BY
            FROM pick_wave_order_master_archive 
            WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED') AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        ) b ON b.ORDER_LINE_ID = t.ORDER_LINE_ID
        GROUP BY t.ORDER_LINE_ID, b.BIN_ID, b.BIN_SEGMENT_NO,b.PICK_START_TIMESTAMP;
    
    DROP TEMPORARY TABLE IF EXISTS total_lpns;
    CREATE TEMPORARY TABLE total_lpns AS
        SELECT 
            t.ORDER_LINE_ID, 
            c.LPN_BARCODE
        FROM t
        LEFT JOIN (
            SELECT pwom.ORDER_LINE_ID,  GROUP_CONCAT(DISTINCT lm.LPN_BARCODE) AS LPN_BARCODE
            FROM pick_wave_order_master pwom
            JOIN lpn_pick_wave_order_mapping lpwom ON lpwom.PICK_ORDER_ID = pwom.PICK_ORDER_ID
            JOIN lpn_master lm ON lm.LPN_ID = lpwom.LPN_ID
            WHERE ORDER_LINE_ID IS NOT NULL
            GROUP BY pwom.ORDER_LINE_ID
            UNION ALL
            SELECT pwoma.ORDER_LINE_ID, GROUP_CONCAT(DISTINCT lm.LPN_BARCODE) AS LPN_BARCODE
            FROM pick_wave_order_master_archive pwoma
            JOIN lpn_pick_wave_order_mapping_archive lpwoma ON lpwoma.PICK_ORDER_ID = pwoma.PICK_ORDER_ID
            JOIN lpn_master lm ON lm.LPN_ID = lpwoma.LPN_ID
            WHERE ORDER_LINE_ID IS NOT NULL
            GROUP BY pwoma.ORDER_LINE_ID
        ) c ON c.ORDER_LINE_ID = t.ORDER_LINE_ID;
        
    
    SET v_base_query = CONCAT(
        "SELECT
            b.WAVE_ID AS 'WAVE ID',
            b.STATION_ID AS 'STATION ID',
            t.BATCH_PICKLIST_CODE AS 'BATCH PICKLIST CODE',
            t.ORDER_ID AS 'ORDER ID',
            t.ARTICLE_ID AS 'SKU ID',
            b.BIN_ID AS 'BIN ID',
            b.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
            sbm.MRP AS 'MRP',
            DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
            COALESCE(b.EXPECTED_QUANTITY, 0) AS 'EXPECTED QUANTITY',
            COALESCE(b.TOTAL_PICKED, 0) AS 'PICK QUANTITY',
            COALESCE(t.LEFT_OVER, 0) AS 'SHORT PICK QUANTITY',
            DATE_FORMAT(obml.LOGGED_TIMESTAMP, '", v_datetime_format, "') AS 'ON STATION TIME',
            DATE_FORMAT(b.PICK_START_TIMESTAMP, '", v_datetime_format, "') AS 'PICK STARTED TIME',
            DATE_FORMAT(b.PICK_TIMESTAMP, '", v_datetime_format, "') AS 'PICK END TIME',
            TIMESTAMPDIFF(SECOND, b.PICK_START_TIMESTAMP, b.PICK_TIMESTAMP) AS 'DIFFERENCE (IN SECS)',
            b.PICK_BY AS 'PICK BY'
        FROM t
        LEFT JOIN total_pick b ON b.ORDER_LINE_ID = t.ORDER_LINE_ID
        LEFT JOIN total_lpns c ON c.ORDER_LINE_ID = t.ORDER_LINE_ID
        LEFT JOIN sku_batch_master sbm ON sbm.BATCH_ID = t.BATCH_ID
        LEFT JOIN order_bin_mapping_log obml ON obml.ORDER_BIN_ID = b.ORDER_BIN_ID
        WHERE obml.STATUS = 'ON_STATION'", p_filter_condition, "
        GROUP BY t.BATCH_PICKLIST_CODE, t.ORDER_ID, t.ORDER_LINE_ID, b.BIN_ID,b.BIN_SEGMENT_NO,b.PICK_START_TIMESTAMP"
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_ORDERS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_ORDERS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_ORDERS`(IN Parameters JSON)
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
    DECLARE p_wave_id VARCHAR(50);
    DECLARE p_wave_status VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
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
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = '';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY ', '`', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET p_table_unique_identifier       = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_wave_id                 = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    IF p_wave_id IS NOT NULL AND p_wave_id != '' THEN
        SELECT WAVE_STATUS INTO p_wave_status FROM wave_master WHERE WAVE_ID = p_wave_id;
        
        IF p_wave_status NOT IN ('COMPLETED', 'PROCESSING') THEN
            IF p_table_unique_identifier = 'report_wave_pick_orders' THEN
                SET p_table_unique_identifier = 'report_wave_pick_orders_wms';
            END IF;
        END IF;
    END IF;
    
    IF p_table_unique_identifier = 'report_wave_pick_orders_wms' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                pwwd.WAVE_MASTER_ID AS 'ID',
                wm.WAVE_ID AS 'WAVE ID',
                pwwd.ORDER_ID AS 'ORDER ID',
                pwwd.SKU_ID AS 'SKU ID',
                pwwd.BATCH_ID AS 'BATCH ID',
                pwwd.QUANTITY, 
                pwwd.MRP, 
                DATE_FORMAT(pwwd.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
                pwwd.LEFT_OVER AS 'LEFT OVER',
                pwwd.PRIORITY
             FROM pick_wave_wms_data AS pwwd
             INNER JOIN wave_master AS wm ON pwwd.WAVE_ID = wm.WAVE_ID
             WHERE pwwd.WAVE_ID = '", p_wave_id, "' ", p_filter_condition
        );
    ELSEIF p_table_unique_identifier = 'report_wave_pick_orders' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                wm.WAVE_ID AS 'WAVE ID',
                pvom.STATION_ID AS 'STATION ID',
                pvom.ORDER_ID AS 'ORDER ID',
                pvom.SKU_ID AS 'SKU ID',
                sbm.CLIENT_BATCH_ID AS 'BATCH ID',
                CASE 
                    WHEN ROW_NUMBER() OVER (PARTITION BY lpwom.PICK_ORDER_ID ORDER BY lpwom.LPN_ID DESC) = 1 
                        THEN lpwom.PICKED_QUANTITY + pvom.SHORT_PICK_QUANTITY 
                    ELSE lpwom.PICKED_QUANTITY 
                END AS 'EXPECTED QUANTITY',
                lpwom.PICKED_QUANTITY AS 'ACTUAL PICK QUANTITY',
                CASE 
                    WHEN ROW_NUMBER() OVER (PARTITION BY lpwom.PICK_ORDER_ID ORDER BY lpwom.LPN_ID DESC) = 1 
                        THEN pvom.SHORT_PICK_QUANTITY 
                    ELSE 0 
                END AS 'SHORT PICK QUANTITY',
                lpn.LPN_BARCODE AS 'LPN BARCODE',
                ROW_NUMBER() OVER(PARTITION BY lpwom.PICK_ORDER_ID ORDER BY lpwom.LPN_ID) AS 'LOT LPN COUNT',
                COUNT(lpwom.LPN_ID) OVER(PARTITION BY lpwom.PICK_ORDER_ID) AS 'LPN COUNT',
                DATE_FORMAT(pvom.PICK_TIMESTAMP, '", v_datetime_format, "') AS 'PICK TIME',
                pvom.PICK_BY AS 'PICK BY USER',
                DATE_FORMAT(wm.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'WAVE INSERTED TIME',
                DATE_FORMAT(wm.START_TIMESTAMP, '", v_datetime_format, "') AS 'WAVE START TIME',
                DATE_FORMAT(wm.COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'WAVE COMPLETED TIME',
                DATE_FORMAT(wm.CANCELLED_TIMESTAMP, '", v_datetime_format, "') AS 'WAVE CANCELLED TIME'
             FROM pick_wave_order_master AS pvom
             INNER JOIN wave_master AS wm ON pvom.WAVE_ID = wm.WAVE_ID
             INNER JOIN sku_batch_master AS sbm ON pvom.BATCH_ID = sbm.BATCH_ID
             LEFT JOIN lpn_pick_wave_order_mapping AS lpwom ON lpwom.PICK_ORDER_ID = pvom.PICK_ORDER_ID
             LEFT JOIN lpn_master AS lpn ON lpn.LPN_ID = lpwom.LPN_ID
             LEFT JOIN (
                 SELECT ORDER_ID, MAX(PRIORITY) AS PRIORITY
                 FROM pick_wave_wms_data
                 GROUP BY ORDER_ID
             ) AS priority_map ON pvom.ORDER_ID = priority_map.ORDER_ID
             WHERE pvom.WAVE_ID = '", p_wave_id, "' ", p_filter_condition,
             
             " UNION ALL 
             SELECT 
                wm.WAVE_ID AS 'WAVE ID',
                pvom.STATION_ID AS 'STATION ID',
                pvom.ORDER_ID AS 'ORDER ID',
                pvom.SKU_ID AS 'SKU ID',
                sbm.CLIENT_BATCH_ID AS 'BATCH ID',
                CASE 
                    WHEN ROW_NUMBER() OVER (PARTITION BY lpwom.PICK_ORDER_ID ORDER BY lpwom.LPN_ID DESC) = 1 
                        THEN lpwom.PICKED_QUANTITY + pvom.SHORT_PICK_QUANTITY 
                    ELSE lpwom.PICKED_QUANTITY 
                END AS 'EXPECTED QUANTITY',
                lpwom.PICKED_QUANTITY AS 'ACTUAL PICK QUANTITY',
                CASE 
                    WHEN ROW_NUMBER() OVER (PARTITION BY lpwom.PICK_ORDER_ID ORDER BY lpwom.LPN_ID DESC) = 1 
                        THEN pvom.SHORT_PICK_QUANTITY 
                    ELSE 0 
                END AS 'SHORT PICK QUANTITY',
                lpn.LPN_BARCODE AS 'LPN BARCODE',
                ROW_NUMBER() OVER(PARTITION BY lpwom.PICK_ORDER_ID ORDER BY lpwom.LPN_ID) AS 'LOT LPN COUNT',
                COUNT(lpwom.LPN_ID) OVER(PARTITION BY lpwom.PICK_ORDER_ID) AS 'LPN COUNT',
                DATE_FORMAT(pvom.PICK_TIMESTAMP, '", v_datetime_format, "') AS 'PICK TIME',
                pvom.PICK_BY AS 'PICK BY USER',
                DATE_FORMAT(wm.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'WAVE INSERTED TIME',
                DATE_FORMAT(wm.START_TIMESTAMP, '", v_datetime_format, "') AS 'WAVE START TIME',
                DATE_FORMAT(wm.COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'WAVE COMPLETED TIME',
                DATE_FORMAT(wm.CANCELLED_TIMESTAMP, '", v_datetime_format, "') AS 'WAVE CANCELLED TIME'
             FROM pick_wave_order_master_archive AS pvom
             INNER JOIN wave_master_archive AS wm ON pvom.WAVE_ID = wm.WAVE_ID
             INNER JOIN sku_batch_master AS sbm ON pvom.BATCH_ID = sbm.BATCH_ID
             LEFT JOIN lpn_pick_wave_order_mapping_archive AS lpwom ON lpwom.PICK_ORDER_ID = pvom.PICK_ORDER_ID
             LEFT JOIN lpn_master AS lpn ON lpn.LPN_ID = lpwom.LPN_ID
             LEFT JOIN (
                 SELECT ORDER_ID, MAX(PRIORITY) AS PRIORITY
                 FROM pick_wave_wms_data
                 GROUP BY ORDER_ID
             ) AS priority_map ON pvom.ORDER_ID = priority_map.ORDER_ID
             WHERE pvom.WAVE_ID = '", p_wave_id, "' ", p_filter_condition
        );
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_LPN_LEVEL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_LPN_LEVEL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_LPN_LEVEL_SUMMARY`(IN Parameters JSON)
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
    DECLARE p_batch_picklist_code VARCHAR(50);
    
    
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
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_batch_picklist_code     = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.batch_picklist_code'));
    
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    
    IF p_batch_picklist_code IS NULL OR p_batch_picklist_code = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BATCH_PICKLIST_CODE is required';
    END IF;
    
    
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
            lm.LPN_BARCODE AS 'LPN BARCODE',
            wtwolps.PARENT_ORDER_ID AS 'ORDER ID',
            pwom.ORDER_LINE_ID AS 'ORDER LINE ID',
            pwom.SKU_ID AS 'SKU ID',
            lpwom.PICKED_QUANTITY AS 'PICKED EACHES',
            DATE_FORMAT(lm.LPN_OPEN_TIMESTAMP, '", v_datetime_format, "') AS 'LPN OPENED TIME',
            DATE_FORMAT(lm.LPN_CLOSE_TIMESTAMP, '", v_datetime_format, "') AS 'LPN CLOSED TIME'
        FROM lpn_master lm
        JOIN lpn_pick_wave_order_mapping lpwom 
            ON lpwom.LPN_ID = lm.LPN_ID
        JOIN pick_wave_order_master pwom 
            ON pwom.PICK_ORDER_ID = lpwom.PICK_ORDER_ID
        JOIN wms_to_wcs_order_line_level_pre_staged_data wtwordl 
            ON wtwordl.ORDER_LINE_ID = pwom.ORDER_LINE_ID
        JOIN wms_to_wcs_order_level_pre_staged_data wtwolps 
            ON wtwolps.parent_order_id = wtwordl.parent_order_id
        WHERE wtwolps.BATCH_PICKLIST_CODE = '", p_batch_picklist_code, "'
          ", p_filter_condition, "
        GROUP BY pwom.ORDER_LINE_ID, lm.LPN_BARCODE
        
        UNION ALL
        
        SELECT 
            lm.LPN_BARCODE AS 'LPN BARCODE',
            wtwolps.PARENT_ORDER_ID AS 'PARENT ORDER ID',
            pwom.ORDER_LINE_ID AS 'ORDER LINE ID',
            pwom.SKU_ID AS 'SKU ID',
            lpwom.PICKED_QUANTITY AS 'PICKED EACHES',
            DATE_FORMAT(lm.LPN_OPEN_TIMESTAMP, '", v_datetime_format, "') AS 'LPN OPENED TIME',
            DATE_FORMAT(lm.LPN_CLOSE_TIMESTAMP, '", v_datetime_format, "') AS 'LPN CLOSED TIME'
        FROM lpn_master lm
        JOIN lpn_pick_wave_order_mapping_archive lpwom 
            ON lpwom.LPN_ID = lm.LPN_ID
        JOIN pick_wave_order_master_archive pwom 
            ON pwom.PICK_ORDER_ID = lpwom.PICK_ORDER_ID
        JOIN wms_to_wcs_order_line_level_pre_staged_data wtwordl 
            ON wtwordl.ORDER_LINE_ID = pwom.ORDER_LINE_ID
        JOIN wms_to_wcs_order_level_pre_staged_data wtwolps 
            ON wtwolps.parent_order_id = wtwordl.parent_order_id
        WHERE wtwolps.BATCH_PICKLIST_CODE = '", p_batch_picklist_code, "'
          ", p_filter_condition, "
        GROUP BY pwom.ORDER_LINE_ID, lm.LPN_BARCODE"
    );
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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
                p_table_unique_identifier,
                p_user_id,
                p_page_number,
                p_rows_per_page,
                v_total_rows
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LEVEL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LEVEL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LEVEL_SUMMARY`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number             INT;
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
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_start_date_time         VARCHAR(50);
    DECLARE p_end_date_time           VARCHAR(50);
    DECLARE p_batch_picklist_code     VARCHAR(50);
    
    DECLARE v_sorting         VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_base_query      TEXT;
    DECLARE v_total_rows      INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    
    SET p_page_number             = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.page_number'));
    SET p_rows_per_page           = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.rows_per_page'));
    SET p_user_id                 = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id'));
    SET p_user_name               = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    SET p_page_zero_metadata_flag = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.page_zero_metadata_flag'));
    SET p_count_flag              = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.count'));
    SET p_filter_condition        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.filter_data'));
    SET p_select_clause           = COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.select_clause')), ''), '*');
    SET p_sorting_column_name     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sorting_column_name'));
    SET p_sorting_column_orderby  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sorting_column_orderby'));
    SET p_table_unique_identifier = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.table_unique_identifier'));
    SET p_report_extra_parameters = JSON_EXTRACT(Parameters, '$.report_extra_parameters');
    SET p_batch_picklist_code     = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.batch_picklist_code'));
    
    
    SET p_download_flag = (JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true');
    
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
        OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(" WHERE ", p_filter_condition);
    ELSE
        SET p_filter_condition = " ";
    END IF;
    
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    
    SET v_base_query = CONCAT("
        WITH
        -- Step 1: Get parent order IDs for the specific batch
        batch_order_ids AS (
            SELECT DISTINCT parent_order_id
            FROM wms_to_wcs_order_level_pre_staged_data
            WHERE batch_picklist_code = '", p_batch_picklist_code, "'
            UNION
            SELECT DISTINCT parent_order_id
            FROM wms_to_wcs_order_level_pre_staged_data_archive
            WHERE batch_picklist_code = '", p_batch_picklist_code, "'
        ),
        
        -- Step 2: Get batch data combined with parent order IDs
        batch_data_combined AS (
            SELECT DISTINCT
                parent_order_id,
                batch_picklist_code
            FROM wms_to_wcs_order_level_pre_staged_data
            WHERE batch_picklist_code = '", p_batch_picklist_code, "'
                AND parent_order_id IN (SELECT parent_order_id FROM batch_order_ids)
            UNION ALL
            SELECT DISTINCT
                parent_order_id,
                batch_picklist_code
            FROM wms_to_wcs_order_level_pre_staged_data_archive
            WHERE batch_picklist_code = '", p_batch_picklist_code, "'
                AND parent_order_id IN (SELECT parent_order_id FROM batch_order_ids)
        ),
        
        -- Step 3: Get order line data summary from pre-staged data
        order_line_data_summary AS (
            SELECT
                PL.order_line_id,
                PL.article_id,
                PL.quantity,
                PS.parent_order_id,
                PS.batch_picklist_code
            FROM wms_to_wcs_order_line_level_pre_staged_data PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = PS.parent_order_id
                AND bdc.batch_picklist_code = PS.batch_picklist_code
            UNION ALL
            SELECT
                PL.order_line_id,
                PL.article_id,
                PL.quantity,
                PS.parent_order_id,
                PS.batch_picklist_code 
            FROM wms_to_wcs_order_line_level_pre_staged_data_archive PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data_archive PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = PS.parent_order_id
                AND bdc.batch_picklist_code = PS.batch_picklist_code
        ),
        
        -- Step 4: Archive without duplicate PWWDA
        arc_without_duplicate_pwwda AS (
            SELECT DISTINCT
                W.wave_id,
                W.order_line_id,
                W.left_over,
                W.inserted_timestamp
            FROM pick_wave_wms_data_archive W
            INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
        ),
        
        -- Step 5: Get WMS data summary (start times and left over quantities)
        wms_data_summary AS (
            SELECT
                order_line_id,
                SUM(total_left_over) AS total_leftover,
                MIN(first_inserted_timestamp) AS first_inserted_timestamp
            FROM (
                SELECT
                    W.order_line_id,
                    W.left_over AS total_left_over,
                    W.inserted_timestamp AS first_inserted_timestamp
                FROM pick_wave_wms_data W
                INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
                UNION ALL
                SELECT
                    order_line_id,
                    left_over AS total_left_over,
                    inserted_timestamp AS first_inserted_timestamp
                FROM arc_without_duplicate_pwwda
            ) AS combined
            GROUP BY order_line_id
        ),
        
        -- Step 6: Archive without duplicate PWOMA
        arc_without_duplicate_pwoma AS (
            SELECT DISTINCT
                W.pick_order_id,
                W.order_line_id,
                W.order_id,
                W.picked_quantity,
                W.pick_start_timestamp,
                W.pick_timestamp
            FROM pick_wave_order_master_archive W
            INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
        ),
        
        -- Step 7: Get pick wave order master summary
        pick_wave_order_master_summary AS (
            SELECT 
                order_line_id,
                order_id,
                SUM(total_picked_quantity) AS total_picked_quantity, 
                MIN(min_time) AS min_time_start, 
                MAX(max_time) AS max_pick_time
            FROM (
                SELECT
                    W.order_line_id,
                    W.order_id,
                    SUM(picked_quantity) AS total_picked_quantity,
                    MIN(pick_start_timestamp) AS min_time,
                    MAX(pick_timestamp) AS max_time
                FROM pick_wave_order_master W
                INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
                GROUP BY W.order_line_id, W.order_id
                
                UNION ALL
                
                SELECT
                    W.order_line_id,
                    W.order_id,
                    SUM(picked_quantity) AS total_picked_quantity,
                    MIN(pick_start_timestamp) AS min_time,
                    MAX(pick_timestamp) AS max_time
                FROM arc_without_duplicate_pwoma W
                GROUP BY W.order_line_id, W.order_id
            ) combined
            GROUP BY order_id, order_line_id
        ),
        
        -- Step 8: LPN mapping
        lpn_mapping AS (
            SELECT W.pick_order_id, W.order_line_id, W.order_id
            FROM pick_wave_order_master W
            INNER JOIN pick_wave_order_master_summary A ON A.order_line_id = W.order_line_id
            UNION ALL
            SELECT W.pick_order_id, W.order_line_id, W.order_id
            FROM pick_wave_order_master_archive W
            INNER JOIN pick_wave_order_master_summary A ON A.order_line_id = W.order_line_id
        ),
        
        -- Step 9: LPN count by parent order
        lpn_count_by_parent_order AS (
            SELECT
                ols.parent_order_id,
                COUNT(DISTINCT combined.lpn_id) AS lpn_count
            FROM order_line_data_summary ols
            LEFT JOIN (
                SELECT
                    ll.pick_order_id,
                    lmm.order_line_id,
                    ll.lpn_id
                FROM lpn_pick_wave_order_mapping ll
                INNER JOIN lpn_master lm ON ll.lpn_id = lm.lpn_id
                INNER JOIN lpn_mapping lmm ON lmm.pick_order_id = ll.pick_order_id
                UNION ALL
                SELECT
                    ll.pick_order_id,
                    lmm.order_line_id,
                    ll.lpn_id
                FROM lpn_pick_wave_order_mapping_archive ll
                INNER JOIN lpn_master lm ON ll.lpn_id = lm.lpn_id
                INNER JOIN lpn_mapping lmm ON lmm.pick_order_id = ll.pick_order_id
            ) combined ON combined.order_line_id = ols.order_line_id
            GROUP BY ols.parent_order_id
        ),
        
        -- Step 10: Order completion times - only include orders where ALL order lines are completed
        order_completion_times AS (
            SELECT
                W.parent_order_id,
                MAX(W.updated_timestamp) AS complete_time
            FROM wms_to_wcs_order_level_pre_staged_data W
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = W.parent_order_id
                AND bdc.batch_picklist_code = W.batch_picklist_code
            WHERE W.batch_picklist_code = '", p_batch_picklist_code, "'
            GROUP BY W.parent_order_id
            HAVING SUM(W.order_request_status IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
            
            UNION ALL
            
            SELECT
                W.parent_order_id,
                MAX(W.updated_timestamp) AS complete_time
            FROM wms_to_wcs_order_level_pre_staged_data_archive W
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = W.parent_order_id
                AND bdc.batch_picklist_code = W.batch_picklist_code
            WHERE W.batch_picklist_code = '", p_batch_picklist_code, "'
            GROUP BY W.parent_order_id
            HAVING SUM(W.order_request_status IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
        ),
        
        -- Step 11: Order complete data
        order_complete_data AS (
            SELECT
                ols.batch_picklist_code,
                ols.parent_order_id,
                ols.order_line_id,
                ols.article_id,
                ols.quantity,
                pwm.total_picked_quantity AS picked_quantity,
                wms.total_leftover AS leftover,
                wms.first_inserted_timestamp AS start_time,
                pwm.max_pick_time AS complete_time
            FROM order_line_data_summary ols
            LEFT JOIN pick_wave_order_master_summary pwm ON ols.order_line_id = pwm.order_line_id
            LEFT JOIN wms_data_summary wms ON ols.order_line_id = wms.order_line_id
        )
        
        -- Final SELECT - Order Level Details by Parent Order ID
        SELECT
            CASE
                WHEN (
                    COALESCE(SUM(ocd.picked_quantity), 0) + COALESCE(SUM(ocd.leftover), 0)
                ) = COALESCE(SUM(ocd.quantity), 0)
                AND oct.complete_time IS NOT NULL THEN 'COMPLETE'
                WHEN oct.complete_time IS NULL THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS `STATUS`,
            ocd.parent_order_id AS `ORDER ID`,
            COUNT(DISTINCT ocd.order_line_id) AS `TOTAL ORDER LINE(s)`,
            COUNT(DISTINCT ocd.article_id) AS `DISTINCT SKU(s)`,
            COALESCE(SUM(ocd.quantity), 0) AS `EXPECTED EACHES`,
            COALESCE(SUM(ocd.picked_quantity), 0) AS `PICKED EACHES`,
            COALESCE(SUM(ocd.leftover), 0) AS `TOTAL STOCK ADJUSTMENT`,
            (COALESCE(SUM(ocd.picked_quantity), 0) + COALESCE(SUM(ocd.leftover), 0)) AS `OVERALL PICKED EACHES`,
            (COALESCE(SUM(ocd.quantity), 0) - (COALESCE(SUM(ocd.picked_quantity), 0) + COALESCE(SUM(ocd.leftover), 0))) AS `PENDING EACHES`,
            COALESCE(lcs.lpn_count, 0) AS `TOTAL LPN(s)`,
            DATE_FORMAT(MIN(ocd.start_time), '", v_datetime_format, "') AS `STARTED TIME`,
            DATE_FORMAT(oct.complete_time, '", v_datetime_format, "') AS `COMPLETED TIME`
        FROM order_complete_data ocd
        LEFT JOIN lpn_count_by_parent_order lcs ON ocd.parent_order_id = lcs.parent_order_id
        LEFT JOIN order_completion_times oct ON ocd.parent_order_id = oct.parent_order_id
        ", p_filter_condition, "
        GROUP BY ocd.parent_order_id, oct.complete_time, lcs.lpn_count
    ");
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LEVEL_SUMMARY_OLD` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LEVEL_SUMMARY_OLD` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LEVEL_SUMMARY_OLD`(IN Parameters JSON)
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
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_start_date_time         VARCHAR(50);
    DECLARE p_end_date_time           VARCHAR(50);
    DECLARE p_batch_picklist_code     VARCHAR(50);
    
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
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    SET p_batch_picklist_code     = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.batch_picklist_code'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = " ";
    ELSE
        SET p_filter_condition = CONCAT(" WHERE ", p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    DROP TEMPORARY TABLE IF EXISTS t_start_time;
    CREATE TEMPORARY TABLE t_start_time AS
        SELECT 
            a.ORDER_LINE_ID, 
            SUM(a.LEFT_OVER) AS LEFT_OVER,
            MIN(a.INSERTED_TIMESTAMP) AS INSERTED_TIMESTAMP
        FROM (
            SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP 
            FROM pick_wave_wms_data
            WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
            UNION ALL
            SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP 
            FROM pick_wave_wms_data_archive
            WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        ) a
        GROUP BY a.ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS t_complete_time;
    CREATE TEMPORARY TABLE t_complete_time AS
       SELECT 
	    ORDER_ID,
	    MAX(UPDATED_TIMESTAMP) AS COMPLETE_TIME
	FROM wms_to_wcs_order_level_pre_staged_data
	WHERE BATCH_PICKLIST_CODE = p_batch_picklist_code
	GROUP BY ORDER_ID
	HAVING SUM(ORDER_REQUEST_STATUS IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
	UNION ALL
	SELECT 
	    ORDER_ID,
	    MAX(UPDATED_TIMESTAMP) AS COMPLETE_TIME
	FROM wms_to_wcs_order_level_pre_staged_data_archive
	WHERE BATCH_PICKLIST_CODE = p_batch_picklist_code
	GROUP BY ORDER_ID
	HAVING SUM(ORDER_REQUEST_STATUS IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0;
    
    DROP TEMPORARY TABLE IF EXISTS t;
    CREATE TEMPORARY TABLE t (
        WMS_ORDER_REQUEST_DATA_ID BIGINT,
        BATCH_PICKLIST_CODE VARCHAR(100),
        ORDER_ID VARCHAR(100),
        ORDER_LINE_ID VARCHAR(100),
        ARTICLE_ID VARCHAR(100),
        QUANTITY INT,
        LEFT_OVER INT,
        START_TIME DATETIME,
        COMPLETE_TIME DATETIME
    );
    
    INSERT INTO t
    SELECT 
        MIN(wtword.WMS_ORDER_REQUEST_DATA_ID),
        wtword.BATCH_PICKLIST_CODE,
        wtword.ORDER_ID,
        wtwolrd.ORDER_LINE_ID,
        wtwolrd.ARTICLE_ID,
        wtwolrd.QUANTITY,
        tst.LEFT_OVER,
        tst.INSERTED_TIMESTAMP,
        tct.COMPLETE_TIME
    FROM wms_to_wcs_order_level_pre_staged_data wtword
    JOIN wms_to_wcs_order_line_level_pre_staged_data wtwolrd 
        ON wtwolrd.WMS_ORDER_REQUEST_DATA_ID = wtword.WMS_ORDER_REQUEST_DATA_ID
    JOIN t_start_time tst 
        ON tst.ORDER_LINE_ID = wtwolrd.ORDER_LINE_ID
    LEFT JOIN t_complete_time tct 
        ON tct.ORDER_ID = wtwolrd.ORDER_ID
    WHERE wtword.BATCH_PICKLIST_CODE = p_batch_picklist_code
    GROUP BY wtword.BATCH_PICKLIST_CODE, wtword.ORDER_ID, wtwolrd.ORDER_LINE_ID;
    
    INSERT INTO t
    SELECT 
        MIN(wtworda.WMS_ORDER_REQUEST_DATA_ID),
        wtworda.BATCH_PICKLIST_CODE,
        wtworda.ORDER_ID,
        wtwolrda.ORDER_LINE_ID,
        wtwolrda.ARTICLE_ID,
        wtwolrda.QUANTITY,
        tst.LEFT_OVER,
        tst.INSERTED_TIMESTAMP,
        tct.COMPLETE_TIME
    FROM wms_to_wcs_order_level_pre_staged_data_archive wtworda
    JOIN wms_to_wcs_order_line_level_pre_staged_data_archive wtwolrda
        ON wtwolrda.WMS_ORDER_REQUEST_DATA_ID = wtworda.WMS_ORDER_REQUEST_DATA_ID
    JOIN t_start_time tst 
        ON tst.ORDER_LINE_ID = wtwolrda.ORDER_LINE_ID
    LEFT JOIN t_complete_time tct 
        ON tct.ORDER_ID = wtwolrda.ORDER_ID
    WHERE wtworda.BATCH_PICKLIST_CODE = p_batch_picklist_code
    GROUP BY wtworda.BATCH_PICKLIST_CODE, wtworda.ORDER_ID, wtwolrda.ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS total_pick;
    CREATE TEMPORARY TABLE total_pick AS
        SELECT 
            t.ORDER_ID, 
            COALESCE(SUM(b.PICKED_QUANTITY), 0) AS TOTAL_PICKED
        FROM t
        LEFT JOIN (
	    SELECT DISTINCT(`PICK_ORDER_ID`),ORDER_LINE_ID, PICKED_QUANTITY 
	    FROM pick_wave_order_master 
	    WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED') 
	    GROUP BY PICK_ORDER_ID
	    UNION ALL
	    SELECT DISTINCT(`PICK_ORDER_ID`), ORDER_LINE_ID, PICKED_QUANTITY 
	    FROM pick_wave_order_master_archive 
	    WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED') 
	    GROUP BY PICK_ORDER_ID
        ) b ON b.ORDER_LINE_ID = t.ORDER_LINE_ID
        GROUP BY t.ORDER_ID;
    
    DROP TEMPORARY TABLE IF EXISTS total_lpns;
    CREATE TEMPORARY TABLE total_lpns AS
        SELECT 
            t.ORDER_ID, 
            COUNT(c.LPN_ID) AS LPN_COUNT
        FROM t
        LEFT JOIN (
            SELECT pwom.ORDER_LINE_ID, lpwom.LPN_ID
            FROM pick_wave_order_master pwom
            JOIN lpn_pick_wave_order_mapping lpwom 
                ON lpwom.PICK_ORDER_ID = pwom.PICK_ORDER_ID
            GROUP BY pwom.ORDER_LINE_ID
            UNION ALL
            SELECT pwoma.ORDER_LINE_ID, lpwoma.LPN_ID
            FROM pick_wave_order_master_archive pwoma
            JOIN lpn_pick_wave_order_mapping_archive lpwoma 
                ON lpwoma.PICK_ORDER_ID = pwoma.PICK_ORDER_ID
            GROUP BY pwoma.ORDER_LINE_ID
        ) c ON c.ORDER_LINE_ID = t.ORDER_LINE_ID
        GROUP BY t.ORDER_ID;
    
    SET v_base_query = CONCAT(
        "SELECT
            CASE 
                WHEN (COALESCE(b.TOTAL_PICKED, 0) + COALESCE(SUM(t.LEFT_OVER), 0)) = COALESCE(SUM(t.QUANTITY), 0)
                     AND t.COMPLETE_TIME IS NOT NULL THEN 'COMPLETE'
                WHEN t.COMPLETE_TIME IS NULL THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS 'STATUS',
            t.ORDER_ID AS 'ORDER ID',
            COUNT(DISTINCT t.ORDER_LINE_ID) AS 'TOTAL ORDER LINE(s)',
            COUNT(DISTINCT t.ARTICLE_ID) AS 'DISTINCT SKU(s)',
            COALESCE(SUM(t.QUANTITY), 0) AS 'EXPECTED EACHES',
            COALESCE(b.TOTAL_PICKED, 0) AS 'PICKED EACHES',
            COALESCE(SUM(t.LEFT_OVER), 0) AS 'TOTAL STOCK ADJUSTMENT',
            (COALESCE(b.TOTAL_PICKED, 0) + COALESCE(SUM(t.LEFT_OVER), 0)) AS 'OVERALL PICKED EACHES',
            (COALESCE(SUM(t.QUANTITY), 0) - (COALESCE(b.TOTAL_PICKED, 0) + COALESCE(SUM(t.LEFT_OVER), 0))) AS 'PENDING EACHES',
            c.LPN_COUNT AS 'TOTAL LPN(s)',
            DATE_FORMAT(t.START_TIME, '", v_datetime_format, "') AS 'STARTED TIME',
            DATE_FORMAT(t.COMPLETE_TIME, '", v_datetime_format, "') AS 'COMPLETED TIME'
        FROM t
        LEFT JOIN total_pick b ON b.ORDER_ID = t.ORDER_ID
	LEFT JOIN total_lpns c ON c.ORDER_ID = t.ORDER_ID
        ", p_filter_condition, "
        GROUP BY t.BATCH_PICKLIST_CODE, t.ORDER_ID"
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LINE_LEVEL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LINE_LEVEL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LINE_LEVEL_SUMMARY`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number             INT;
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
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_batch_picklist_code     VARCHAR(50);
    
    DECLARE v_sorting         VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_base_query      TEXT;
    DECLARE v_total_rows      INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    
    SET p_page_number             = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.page_number'));
    SET p_rows_per_page           = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.rows_per_page'));
    SET p_user_id                 = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id'));
    SET p_user_name               = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    SET p_page_zero_metadata_flag = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.page_zero_metadata_flag'));
    SET p_count_flag              = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.count'));
    SET p_filter_condition        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.filter_data'));
    SET p_select_clause           = COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.select_clause')), ''), '*');
    SET p_sorting_column_name     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sorting_column_name'));
    SET p_sorting_column_orderby  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sorting_column_orderby'));
    SET p_table_unique_identifier = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.table_unique_identifier'));
    SET p_report_extra_parameters = JSON_EXTRACT(Parameters, '$.report_extra_parameters');
    SET p_batch_picklist_code     = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.batch_picklist_code'));
    SET p_download_flag = (JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true');
    
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
        OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(" WHERE ", p_filter_condition);
    ELSE
        SET p_filter_condition = " ";
    END IF;
    
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    
    SET v_base_query = CONCAT("
        WITH
        -- Step 1: Get parent order IDs for the specific batch
        batch_order_ids AS (
            SELECT DISTINCT parent_order_id
            FROM wms_to_wcs_order_level_pre_staged_data
            WHERE batch_picklist_code = '", p_batch_picklist_code, "'
            UNION
            SELECT DISTINCT parent_order_id
            FROM wms_to_wcs_order_level_pre_staged_data_archive
            WHERE batch_picklist_code = '", p_batch_picklist_code, "'
        ),
        
        -- Step 2: Get batch data combined with parent order IDs
        batch_data_combined AS (
            SELECT DISTINCT
                parent_order_id,
                batch_picklist_code
            FROM wms_to_wcs_order_level_pre_staged_data
            WHERE batch_picklist_code = '", p_batch_picklist_code, "'
                AND parent_order_id IN (SELECT parent_order_id FROM batch_order_ids)
            UNION ALL
            SELECT DISTINCT
                parent_order_id,
                batch_picklist_code
            FROM wms_to_wcs_order_level_pre_staged_data_archive
            WHERE batch_picklist_code = '", p_batch_picklist_code, "'
                AND parent_order_id IN (SELECT parent_order_id FROM batch_order_ids)
        ),
        
        -- Step 3: Get order line data summary from pre-staged data
        order_line_data_summary AS (
            SELECT
                PL.order_line_id,
                PL.article_id,
                PL.quantity,
                PS.parent_order_id,
                PS.batch_picklist_code
            FROM wms_to_wcs_order_line_level_pre_staged_data PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = PS.parent_order_id
                AND bdc.batch_picklist_code = PS.batch_picklist_code
            UNION ALL
            SELECT
                PL.order_line_id,
                PL.article_id,
                PL.quantity,
                PS.parent_order_id,
                PS.batch_picklist_code 
            FROM wms_to_wcs_order_line_level_pre_staged_data_archive PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data_archive PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = PS.parent_order_id
                AND bdc.batch_picklist_code = PS.batch_picklist_code
        ),
        
        -- Step 4: Archive without duplicate PWWDA
        arc_without_duplicate_pwwda AS (
            SELECT DISTINCT
                W.wave_id,
                W.order_line_id,
                W.left_over,
                W.inserted_timestamp
            FROM pick_wave_wms_data_archive W
            INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
        ),
        
        -- Step 5: Get WMS data summary (start times and left over quantities)
        wms_data_summary AS (
            SELECT
                order_line_id,
                SUM(total_left_over) AS total_leftover,
                MIN(first_inserted_timestamp) AS first_inserted_timestamp
            FROM (
                SELECT
                    W.order_line_id,
                    W.left_over AS total_left_over,
                    W.inserted_timestamp AS first_inserted_timestamp
                FROM pick_wave_wms_data W
                INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
                UNION ALL
                SELECT
                    order_line_id,
                    left_over AS total_left_over,
                    inserted_timestamp AS first_inserted_timestamp
                FROM arc_without_duplicate_pwwda
            ) AS combined
            GROUP BY order_line_id
        ),
        
        -- Step 6: Archive without duplicate PWOMA
        arc_without_duplicate_pwoma AS (
            SELECT DISTINCT
                W.pick_order_id,
                W.order_line_id,
                W.order_id,
                W.picked_quantity,
                W.pick_start_timestamp,
                W.pick_timestamp
            FROM pick_wave_order_master_archive W
            INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
        ),
        
        -- Step 7: Get pick wave order master summary
        pick_wave_order_master_summary AS (
            SELECT 
                order_line_id,
                order_id,
                SUM(total_picked_quantity) AS total_picked_quantity, 
                MIN(min_time) AS min_time_start, 
                MAX(max_time) AS max_pick_time
            FROM (
                SELECT
                    W.order_line_id,
                    W.order_id,
                    SUM(picked_quantity) AS total_picked_quantity,
                    MIN(pick_start_timestamp) AS min_time,
                    MAX(pick_timestamp) AS max_time
                FROM pick_wave_order_master W
                INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
                GROUP BY W.order_line_id, W.order_id
                
                UNION ALL
                
                SELECT
                    W.order_line_id,
                    W.order_id,
                    SUM(picked_quantity) AS total_picked_quantity,
                    MIN(pick_start_timestamp) AS min_time,
                    MAX(pick_timestamp) AS max_time
                FROM arc_without_duplicate_pwoma W
                GROUP BY W.order_line_id, W.order_id
            ) combined
            GROUP BY order_id, order_line_id
        ),
        
        -- Step 8: LPN mapping
        lpn_mapping AS (
            SELECT W.pick_order_id, W.order_line_id, W.order_id
            FROM pick_wave_order_master W
            INNER JOIN pick_wave_order_master_summary A ON A.order_line_id = W.order_line_id
            UNION ALL
            SELECT W.pick_order_id, W.order_line_id, W.order_id
            FROM pick_wave_order_master_archive W
            INNER JOIN pick_wave_order_master_summary A ON A.order_line_id = W.order_line_id
        ),
        
        -- Step 9: LPN barcode by order line
        lpn_barcode_by_order_line AS (
            SELECT
                ols.order_line_id,
                GROUP_CONCAT(DISTINCT combined.lpn_barcode SEPARATOR ', ') AS lpn_barcodes,
                COUNT(DISTINCT combined.lpn_id) AS lpn_count
            FROM order_line_data_summary ols
            LEFT JOIN (
                SELECT
                    ll.pick_order_id,
                    lmm.order_line_id,
                    ll.lpn_id,
                    lm.lpn_barcode
                FROM lpn_pick_wave_order_mapping ll
                INNER JOIN lpn_master lm ON ll.lpn_id = lm.lpn_id
                INNER JOIN lpn_mapping lmm ON lmm.pick_order_id = ll.pick_order_id
                UNION ALL
                SELECT
                    ll.pick_order_id,
                    lmm.order_line_id,
                    ll.lpn_id,
                    lm.lpn_barcode
                FROM lpn_pick_wave_order_mapping_archive ll
                INNER JOIN lpn_master lm ON ll.lpn_id = lm.lpn_id
                INNER JOIN lpn_mapping lmm ON lmm.pick_order_id = ll.pick_order_id
            ) combined ON combined.order_line_id = ols.order_line_id
            GROUP BY ols.order_line_id
        ),
        
        -- Step 10: Order line completion times - check if order line is fully completed
        order_line_completion_times AS (
            SELECT
                PL.order_line_id,
                MAX(PS.updated_timestamp) AS complete_time
            FROM wms_to_wcs_order_line_level_pre_staged_data PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = PS.parent_order_id
                AND bdc.batch_picklist_code = PS.batch_picklist_code
            WHERE PS.batch_picklist_code = '", p_batch_picklist_code, "'
                AND PL.order_line_id IN (SELECT order_line_id FROM order_line_data_summary)
            GROUP BY PL.order_line_id
            HAVING SUM(PS.order_request_status IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
            
            UNION ALL
            
            SELECT
                PL.order_line_id,
                MAX(PS.updated_timestamp) AS complete_time
            FROM wms_to_wcs_order_line_level_pre_staged_data_archive PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data_archive PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = PS.parent_order_id
                AND bdc.batch_picklist_code = PS.batch_picklist_code
            WHERE PS.batch_picklist_code = '", p_batch_picklist_code, "'
                AND PL.order_line_id IN (SELECT order_line_id FROM order_line_data_summary)
            GROUP BY PL.order_line_id
            HAVING SUM(PS.order_request_status IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
        ),
        
        -- Step 11: Order line complete data
        order_line_complete_data AS (
            SELECT
                ols.batch_picklist_code,
                ols.parent_order_id,
                ols.order_line_id,
                ols.article_id,
                ols.quantity,
                COALESCE(pwm.total_picked_quantity, 0) AS picked_quantity,
                COALESCE(wms.total_leftover, 0) AS leftover,
                wms.first_inserted_timestamp AS start_time,
                pwm.max_pick_time AS pick_complete_time,
                olct.complete_time AS order_complete_time
            FROM order_line_data_summary ols
            LEFT JOIN pick_wave_order_master_summary pwm 
                ON ols.order_line_id = pwm.order_line_id
            LEFT JOIN wms_data_summary wms 
                ON ols.order_line_id = wms.order_line_id
            LEFT JOIN order_line_completion_times olct 
                ON ols.order_line_id = olct.order_line_id
        )
        
        -- Final SELECT - Order Line Level Details
        SELECT
            CASE
                WHEN (COALESCE(olcd.picked_quantity, 0) + COALESCE(olcd.leftover, 0)) = COALESCE(olcd.quantity, 0)
                    AND olcd.order_complete_time IS NOT NULL 
                THEN 'COMPLETE'
                WHEN olcd.order_complete_time IS NULL 
                THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS `STATUS`,
            olcd.parent_order_id AS `ORDER ID`,
            olcd.order_line_id AS `ORDER LINE ID`,
            olcd.article_id AS `SKU ID`,
            COALESCE(olcd.quantity, 0) AS `EXPECTED EACHES`,
            COALESCE(olcd.picked_quantity, 0) AS `PICKED EACHES`,
            COALESCE(olcd.leftover, 0) AS `TOTAL STOCK ADJUSTMENT`,
            (COALESCE(olcd.picked_quantity, 0) + COALESCE(olcd.leftover, 0)) AS `OVERALL PICKED EACHES`,
            (COALESCE(olcd.quantity, 0) - (COALESCE(olcd.picked_quantity, 0) + COALESCE(olcd.leftover, 0))) AS `PENDING EACHES`,
            COALESCE(lbl.lpn_barcodes, '') AS `LPN BARCODE`,
            DATE_FORMAT(olcd.start_time, '", v_datetime_format, "') AS `STARTED TIME`,
            DATE_FORMAT(olcd.order_complete_time, '", v_datetime_format, "') AS `COMPLETED TIME`
        FROM order_line_complete_data olcd
        LEFT JOIN lpn_barcode_by_order_line lbl 
            ON olcd.order_line_id = lbl.order_line_id
        ", p_filter_condition, "
    ");
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LINE_LEVEL_SUMMARY_1` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LINE_LEVEL_SUMMARY_1` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_ORDER_LINE_LEVEL_SUMMARY_1`(IN Parameters JSON)
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
    DECLARE p_start_date_time VARCHAR(50);
    DECLARE p_end_date_time VARCHAR(50);
    DECLARE p_batch_picklist_code VARCHAR(50);
    
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
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    SET p_batch_picklist_code     = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.batch_picklist_code'));
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = " ";
    ELSE
        SET p_filter_condition = CONCAT(" WHERE ", p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    DROP TEMPORARY TABLE IF EXISTS t_start_time;
    CREATE TEMPORARY TABLE t_start_time AS
        SELECT 
            a.ORDER_LINE_ID, 
            SUM(a.LEFT_OVER) AS LEFT_OVER,
            MIN(a.INSERTED_TIMESTAMP) AS INSERTED_TIMESTAMP
        FROM (
            SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP 
            FROM pick_wave_wms_data
            WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
            UNION ALL
            SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP 
            FROM pick_wave_wms_data_archive
            WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        ) a
        GROUP BY a.ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS t_complete_time;
    CREATE TEMPORARY TABLE t_complete_time AS
        SELECT ORDER_LINE_ID, MAX(UPDATED_TIMESTAMP) AS COMPLETE_TIME
        FROM wms_to_wcs_order_line_level_pre_staged_data
        WHERE UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_LINE_ID
        UNION ALL
        SELECT ORDER_LINE_ID, MAX(UPDATED_TIMESTAMP) AS COMPLETE_TIME
        FROM wms_to_wcs_order_line_level_pre_staged_data_archive
        WHERE UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS t;
    CREATE TEMPORARY TABLE t (
        WMS_ORDER_REQUEST_DATA_ID BIGINT,
        BATCH_PICKLIST_CODE VARCHAR(100),
        ORDER_ID VARCHAR(100),
        ORDER_LINE_ID VARCHAR(100),
        ARTICLE_ID VARCHAR(100),
        QUANTITY INT,
        LEFT_OVER INT,
        START_TIME DATETIME,
        COMPLETE_TIME DATETIME
    );
    
    INSERT INTO t
    SELECT 
        MIN(wtword.WMS_ORDER_REQUEST_DATA_ID),
        wtword.BATCH_PICKLIST_CODE,
        wtword.ORDER_ID,
        wtwolrd.ORDER_LINE_ID,
        wtwolrd.ARTICLE_ID,
        wtwolrd.QUANTITY,
        tst.LEFT_OVER,
        tst.INSERTED_TIMESTAMP,
        tct.COMPLETE_TIME
    FROM wms_to_wcs_order_level_pre_staged_data wtword
    JOIN wms_to_wcs_order_line_level_pre_staged_data wtwolrd 
        ON wtwolrd.WMS_ORDER_REQUEST_DATA_ID = wtword.WMS_ORDER_REQUEST_DATA_ID
    JOIN t_start_time tst 
        ON tst.ORDER_LINE_ID = wtwolrd.ORDER_LINE_ID
    LEFT JOIN t_complete_time tct 
        ON tct.ORDER_LINE_ID = wtwolrd.ORDER_LINE_ID
    WHERE wtword.BATCH_PICKLIST_CODE = p_batch_picklist_code
    GROUP BY wtword.BATCH_PICKLIST_CODE, wtword.ORDER_ID, wtwolrd.ORDER_LINE_ID;
    
    INSERT INTO t
    SELECT 
        MIN(wtworda.WMS_ORDER_REQUEST_DATA_ID),
        wtworda.BATCH_PICKLIST_CODE,
        wtworda.ORDER_ID,
        wtwolrda.ORDER_LINE_ID,
        wtwolrda.ARTICLE_ID,
        wtwolrda.QUANTITY,
        tst.LEFT_OVER,
        tst.INSERTED_TIMESTAMP,
        tct.COMPLETE_TIME
    FROM wms_to_wcs_order_level_pre_staged_data_archive wtworda
    JOIN wms_to_wcs_order_line_level_pre_staged_data_archive wtwolrda
        ON wtwolrda.WMS_ORDER_REQUEST_DATA_ID = wtworda.WMS_ORDER_REQUEST_DATA_ID
    JOIN t_start_time tst 
        ON tst.ORDER_LINE_ID = wtwolrda.ORDER_LINE_ID
    LEFT JOIN t_complete_time tct 
        ON tct.ORDER_LINE_ID = wtwolrda.ORDER_LINE_ID
    WHERE wtworda.BATCH_PICKLIST_CODE = p_batch_picklist_code
    GROUP BY wtworda.BATCH_PICKLIST_CODE, wtworda.ORDER_ID, wtwolrda.ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS total_pick;
    CREATE TEMPORARY TABLE total_pick AS
        SELECT 
            t.ORDER_LINE_ID, 
            COALESCE(SUM(b.PICKED_QUANTITY), 0) AS TOTAL_PICKED
        FROM t
        LEFT JOIN (
	    SELECT DISTINCT(`PICK_ORDER_ID`),ORDER_LINE_ID, PICKED_QUANTITY 
	    FROM pick_wave_order_master 
	    WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED') 
	    GROUP BY PICK_ORDER_ID
	    UNION ALL
	    SELECT DISTINCT(`PICK_ORDER_ID`), ORDER_LINE_ID, PICKED_QUANTITY 
	    FROM pick_wave_order_master_archive 
	    WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED') 
	    GROUP BY PICK_ORDER_ID
        ) b ON b.ORDER_LINE_ID = t.ORDER_LINE_ID
        GROUP BY t.ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS total_lpns;
    CREATE TEMPORARY TABLE total_lpns AS
        SELECT 
            t.ORDER_LINE_ID, 
            c.LPN_BARCODE
        FROM t
        LEFT JOIN (
            SELECT pwom.ORDER_LINE_ID,  GROUP_CONCAT(DISTINCT lm.LPN_BARCODE) AS LPN_BARCODE
            FROM pick_wave_order_master pwom
            JOIN lpn_pick_wave_order_mapping lpwom ON lpwom.PICK_ORDER_ID = pwom.PICK_ORDER_ID
            JOIN lpn_master lm ON lm.LPN_ID = lpwom.LPN_ID
            where ORDER_LINE_ID is not null
            GROUP BY pwom.ORDER_LINE_ID
            UNION ALL
            SELECT pwoma.ORDER_LINE_ID, GROUP_CONCAT(DISTINCT lm.LPN_BARCODE) AS LPN_BARCODE
            FROM pick_wave_order_master_archive pwoma
            JOIN lpn_pick_wave_order_mapping_archive lpwoma ON lpwoma.PICK_ORDER_ID = pwoma.PICK_ORDER_ID
            JOIN lpn_master lm ON lm.LPN_ID = lpwoma.LPN_ID
            WHERE ORDER_LINE_ID IS NOT NULL
            GROUP BY pwoma.ORDER_LINE_ID
        ) c ON c.ORDER_LINE_ID = t.ORDER_LINE_ID;
        
    
    SET v_base_query = CONCAT(
        "SELECT
            CASE 
                WHEN (
                    COALESCE(b.TOTAL_PICKED, 0) + COALESCE(SUM(t.LEFT_OVER), 0)
                ) = COALESCE(SUM(t.QUANTITY), 0)
                AND t.COMPLETE_TIME IS NOT NULL THEN 'COMPLETE'
                WHEN t.COMPLETE_TIME IS NULL THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS 'STATUS',
            t.ORDER_ID AS 'ORDER ID',
            t.ORDER_LINE_ID AS 'ORDER LINE ID',
            t.ARTICLE_ID AS 'SKU ID',
            COALESCE(SUM(t.QUANTITY), 0) AS 'EXPECTED EACHES',
            COALESCE(b.TOTAL_PICKED, 0) AS 'PICKED EACHES',
            COALESCE(SUM(t.LEFT_OVER), 0) AS 'TOTAL STOCK ADJUSTMENT',
            (COALESCE(b.TOTAL_PICKED, 0) + COALESCE(SUM(t.LEFT_OVER), 0)) AS 'OVERALL PICKED EACHES',
            (COALESCE(SUM(t.QUANTITY), 0) - (COALESCE(b.TOTAL_PICKED, 0) + COALESCE(SUM(t.LEFT_OVER), 0))) AS 'PENDING EACHES',
            c.LPN_BARCODE AS 'LPN BARCODE',
            DATE_FORMAT(t.START_TIME, '", v_datetime_format, "') AS 'STARTED TIME',
            DATE_FORMAT(t.COMPLETE_TIME, '", v_datetime_format, "') AS 'COMPLETED TIME'
        FROM t
        LEFT JOIN total_pick b ON b.ORDER_LINE_ID = t.ORDER_LINE_ID
        LEFT JOIN total_lpns c ON c.ORDER_LINE_ID = t.ORDER_LINE_ID
        ", p_filter_condition, "
        GROUP BY t.BATCH_PICKLIST_CODE, t.ORDER_ID, t.ORDER_LINE_ID"
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE p_user_id VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_user_name VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_table_unique_identifier VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_start_date_time VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_end_date_time VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    
    DECLARE v_sorting VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    
    SET p_page_number             = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.page_number'));
    SET p_rows_per_page           = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.rows_per_page'));
    SET p_user_id                 = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id'));
    SET p_user_name               = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    SET p_page_zero_metadata_flag = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.page_zero_metadata_flag'));
    SET p_count_flag              = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.count'));
    SET p_filter_condition        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.filter_data'));
    SET p_select_clause           = COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.select_clause')), ''), '*');
    SET p_sorting_column_name     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sorting_column_name'));
    SET p_sorting_column_orderby  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sorting_column_orderby'));
    SET p_table_unique_identifier = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.table_unique_identifier'));
    SET p_report_extra_parameters = JSON_EXTRACT(Parameters, '$.report_extra_parameters');
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    
    
    SET p_download_flag = (JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true');
    
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
        OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(" WHERE ", p_filter_condition);
    ELSE
        SET p_filter_condition = " ";
    END IF;
    
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    
    SET v_base_query = CONCAT("    
        WITH
        -- Step 1: Find order line IDs based on pick timestamps
        pick_wave_order_line_ids AS (
            SELECT DISTINCT order_line_id
            FROM pick_wave_order_master
            WHERE pick_timestamp BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
            UNION ALL
            SELECT DISTINCT order_line_id
            FROM pick_wave_order_master_archive
            WHERE pick_timestamp BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
        ),
        
        -- Step 2: Get parent order IDs and batch picklist codes from pre-staged data using order lines
        parent_order_and_batch_data AS (
            SELECT DISTINCT 
                PS.parent_order_id,
                PS.batch_picklist_code
            FROM wms_to_wcs_order_line_level_pre_staged_data PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN pick_wave_order_line_ids pwol 
                ON pwol.order_line_id = PL.order_line_id
            UNION
            SELECT DISTINCT 
                PS.parent_order_id,
                PS.batch_picklist_code
            FROM wms_to_wcs_order_line_level_pre_staged_data_archive PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data_archive PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN pick_wave_order_line_ids pwol 
                ON pwol.order_line_id = PL.order_line_id
        ),
        
        -- Step 3: Get batch data combined with parent order IDs
        batch_data_combined AS (
            SELECT DISTINCT
                parent_order_id,
                batch_picklist_code
            FROM wms_to_wcs_order_level_pre_staged_data
            WHERE batch_picklist_code IN (
                SELECT DISTINCT batch_picklist_code 
                FROM parent_order_and_batch_data
            )
            UNION ALL 
            SELECT DISTINCT
                parent_order_id,
                batch_picklist_code
            FROM wms_to_wcs_order_level_pre_staged_data_archive
            WHERE batch_picklist_code IN (
                SELECT DISTINCT batch_picklist_code 
                FROM parent_order_and_batch_data
            )
        ),
        
        -- Step 4: Get order line data summary from pre-staged data
        order_line_data_summary AS (
            SELECT
                PL.order_line_id,
                PL.article_id,
                PL.quantity,
                PS.parent_order_id,
                PS.batch_picklist_code
            FROM wms_to_wcs_order_line_level_pre_staged_data PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = PS.parent_order_id
            UNION ALL
            SELECT
                PL.order_line_id,
                PL.article_id,
                PL.quantity,
                PS.parent_order_id,
                PS.batch_picklist_code 
            FROM wms_to_wcs_order_line_level_pre_staged_data_archive PL
            INNER JOIN wms_to_wcs_order_level_pre_staged_data_archive PS 
                ON PS.wms_order_request_data_id = PL.wms_order_request_data_id
            INNER JOIN batch_data_combined bdc 
                ON bdc.parent_order_id = PS.parent_order_id
        ),
        
        -- Step 4.5: Archive without duplicate PWWDA
        arc_without_duplicate_pwwda AS (
            SELECT DISTINCT
                W.wave_id,
                W.order_line_id,
                W.left_over,
                W.inserted_timestamp
            FROM pick_wave_wms_data_archive W
            INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
        ),
        
        -- Step 5: Get WMS data summary (start times)
        wms_data_summary AS (
            SELECT
                order_line_id,
                SUM(total_left_over) AS total_leftover,
                MIN(first_inserted_timestamp) AS first_inserted_timestamp
            FROM (
                SELECT
                    W.order_line_id,
                    W.left_over AS total_left_over,
                    W.inserted_timestamp AS first_inserted_timestamp
                FROM pick_wave_wms_data W
                INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
                UNION ALL
                SELECT
                    order_line_id,
                    left_over AS total_left_over,
                    inserted_timestamp AS first_inserted_timestamp
                FROM arc_without_duplicate_pwwda
            ) AS combined
            GROUP BY order_line_id
        ),
        
        -- Step 6: Archive without duplicate PWOMA
        arc_without_duplicate_pwoma AS (
            SELECT DISTINCT
                W.pick_order_id,
                W.order_line_id,
                W.picked_quantity,
                W.pick_start_timestamp,
                W.pick_timestamp
            FROM pick_wave_order_master_archive W
            INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
        ),
        
        -- Step 7: Get pick wave order master summary
        pick_wave_order_master_summary AS (
            SELECT 
                order_line_id, 
                SUM(total_picked_quantity) AS total_picked_quantity, 
                MIN(min_time) AS min_time_start, 
                MAX(max_time) AS max_pick_time
            FROM (
                SELECT
                    W.order_line_id,
                    SUM(picked_quantity) AS total_picked_quantity,
                    MIN(pick_start_timestamp) AS min_time,
                    MAX(pick_timestamp) AS max_time
                FROM pick_wave_order_master W
                INNER JOIN order_line_data_summary A ON A.order_line_id = W.order_line_id
                GROUP BY W.order_line_id
                
                UNION ALL
                
                SELECT
                    W.order_line_id,
                    SUM(picked_quantity) AS total_picked_quantity,
                    MIN(pick_start_timestamp) AS min_time,
                    MAX(pick_timestamp) AS max_time
                FROM arc_without_duplicate_pwoma W
                GROUP BY W.order_line_id
            ) combined
            GROUP BY order_line_id
        ),
        
        -- Step 8: LPN mapping
        lpn_mapping AS (
            SELECT W.pick_order_id, W.order_line_id, W.order_id
            FROM pick_wave_order_master W
            INNER JOIN pick_wave_order_master_summary A ON A.order_line_id = W.order_line_id
            UNION ALL
            SELECT W.pick_order_id, W.order_line_id, W.order_id
            FROM pick_wave_order_master_archive W
            INNER JOIN pick_wave_order_master_summary A ON A.order_line_id = W.order_line_id
        ),
        
        -- Step 9: LPN mapping detailed
        lpn_mapping_2 AS (
            SELECT
                bdc.batch_picklist_code,
                COUNT(DISTINCT combined.lpn_id) AS count_lpn_id,
                GROUP_CONCAT(DISTINCT combined.lpn_barcode) AS lpn_barcode,
                MIN(combined.lpn_open_timestamp) AS lpn_open_timestamp,
                MAX(combined.lpn_close_timestamp) AS lpn_close_timestamp
            FROM batch_data_combined bdc
            INNER JOIN order_line_data_summary ols ON bdc.parent_order_id = ols.parent_order_id
            LEFT JOIN (
                SELECT
                    ll.pick_order_id,
                    lmm.order_id,
                    lmm.order_line_id,
                    ll.lpn_id,
                    ll.picked_quantity,
                    lm.lpn_barcode,
                    lm.lpn_open_timestamp,
                    lm.lpn_close_timestamp
                FROM lpn_pick_wave_order_mapping ll
                INNER JOIN lpn_master lm ON ll.lpn_id = lm.lpn_id
                INNER JOIN lpn_mapping lmm ON lmm.pick_order_id = ll.pick_order_id
                UNION ALL
                SELECT
                    ll.pick_order_id,
                    lmm.order_id,
                    lmm.order_line_id,
                    ll.lpn_id,
                    ll.picked_quantity,
                    lm.lpn_barcode,
                    lm.lpn_open_timestamp,
                    lm.lpn_close_timestamp
                FROM lpn_pick_wave_order_mapping_archive ll
                INNER JOIN lpn_master lm ON ll.lpn_id = lm.lpn_id
                INNER JOIN lpn_mapping lmm ON lmm.pick_order_id = ll.pick_order_id
            ) combined ON combined.order_line_id = ols.order_line_id
            GROUP BY bdc.batch_picklist_code
        ),
        
        -- Step 10: Batch completion times - only include batches where ALL orders are completed
        batch_completion_times AS (
            SELECT
                W.batch_picklist_code,
                MAX(updated_timestamp) AS complete_time
            FROM wms_to_wcs_order_level_pre_staged_data W
            INNER JOIN batch_data_combined bdc ON bdc.batch_picklist_code = W.batch_picklist_code
            GROUP BY W.batch_picklist_code
            HAVING SUM(order_request_status IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
            
            UNION ALL
            
            SELECT
                W.batch_picklist_code,
                MAX(updated_timestamp) AS complete_time
            FROM wms_to_wcs_order_level_pre_staged_data_archive W
            INNER JOIN batch_data_combined bdc ON bdc.batch_picklist_code = W.batch_picklist_code
            GROUP BY W.batch_picklist_code
            HAVING SUM(order_request_status IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
        )
        
        -- Final SELECT
        SELECT
            CASE
                WHEN SUM(COALESCE(ols.quantity, 0)) = SUM(COALESCE(pwm.total_picked_quantity, 0) + COALESCE(wms.total_leftover, 0))
                THEN 'COMPLETED'
                WHEN bct.complete_time IS NULL
                THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS `STATUS`,
            bdc.batch_picklist_code AS 'BATCH PICKLIST CODE',
            COUNT(DISTINCT bdc.parent_order_id) AS `TOTAL ORDER(s)`,
            COUNT(DISTINCT ols.order_line_id) AS `TOTAL ORDER LINE(s)`,
            COUNT(DISTINCT ols.article_id) AS `DISTINCT SKU(s)`,
            SUM(COALESCE(ols.quantity, 0)) AS `EXPECTED EACHES`,
            SUM(COALESCE(pwm.total_picked_quantity, 0)) AS `PICKED EACHES`,
            SUM(COALESCE(wms.total_leftover, 0)) AS `TOTAL STOCK ADJUSTMENT`,
            SUM(COALESCE(pwm.total_picked_quantity, 0) + COALESCE(wms.total_leftover, 0)) AS `OVERALL PICKED EACHES`,
            SUM(COALESCE(ols.quantity, 0) - (COALESCE(pwm.total_picked_quantity, 0) + COALESCE(wms.total_leftover, 0))) AS `PENDING EACHES`,
            COALESCE(l2.count_lpn_id, 0) AS `TOTAL LPN(s)`,
            DATE_FORMAT(MIN(wms.first_inserted_timestamp), '", v_datetime_format, "') AS `STARTED TIME`,
            DATE_FORMAT(bct.complete_time, '", v_datetime_format, "') AS `COMPLETED TIME`
        FROM batch_data_combined bdc
        INNER JOIN order_line_data_summary ols ON bdc.parent_order_id = ols.parent_order_id
        LEFT JOIN pick_wave_order_master_summary pwm ON ols.order_line_id = pwm.order_line_id
        LEFT JOIN wms_data_summary wms ON ols.order_line_id = wms.order_line_id
        LEFT JOIN lpn_mapping_2 l2 ON bdc.batch_picklist_code = l2.batch_picklist_code
        LEFT JOIN batch_completion_times bct ON bdc.batch_picklist_code = bct.batch_picklist_code
        ", p_filter_condition, "
        GROUP BY bdc.batch_picklist_code, bct.complete_time, l2.count_lpn_id"
    );
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY_BKP` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY_BKP` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY_BKP`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
    DECLARE p_user_id VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_user_name VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_table_unique_identifier VARCHAR(50)CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_start_date_time VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE p_end_date_time VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    
    DECLARE v_sorting VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci  DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number             = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.page_number'));
    SET p_rows_per_page           = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.rows_per_page'));
    SET p_user_id                 = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id'));
    SET p_user_name               = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));
    SET p_page_zero_metadata_flag = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.page_zero_metadata_flag'));
    SET p_count_flag              = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.count'));
    SET p_filter_condition        = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.filter_data'));
    SET p_select_clause           = COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.select_clause')), ''), '*');
    SET p_sorting_column_name     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sorting_column_name'));
    SET p_sorting_column_orderby  = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sorting_column_orderby'));
    SET p_table_unique_identifier = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.table_unique_identifier'));
    SET p_report_extra_parameters = JSON_EXTRACT(Parameters, '$.report_extra_parameters');
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    
    SET p_download_flag = (JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true');
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
        OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(" WHERE ", p_filter_condition);
    ELSE
        SET p_filter_condition = " ";
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    SET v_base_query = CONCAT("
        WITH
        -- Step 1: Find order IDs based on pick timestamps
        pick_wave_order_ids AS (
            SELECT DISTINCT order_id
            FROM pick_wave_order_master
            WHERE pick_timestamp BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
            UNION ALL
            SELECT DISTINCT order_id
            FROM pick_wave_order_master_archive
            WHERE pick_timestamp BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
        ),
        
        -- Step 2: Get batch picklist codes from those orders
        batch_pick_list_codes AS (
            SELECT DISTINCT batch_picklist_code
            FROM wms_to_wcs_order_level_pre_staged_data
            WHERE order_id IN (SELECT order_id FROM pick_wave_order_ids)
            UNION ALL
            SELECT DISTINCT batch_picklist_code
            FROM wms_to_wcs_order_level_pre_staged_data_archive
            WHERE order_id IN (SELECT order_id FROM pick_wave_order_ids)
        ),
        
        -- Step 3: Get batch data combined
        batch_data_combined AS (
            SELECT batch_picklist_code, order_id, MIN(wms_order_request_data_id) AS min_wms_order_request_data_id
            FROM wms_to_wcs_order_level_pre_staged_data
            WHERE batch_picklist_code IN (SELECT batch_picklist_code FROM batch_pick_list_codes)
            GROUP BY batch_picklist_code, order_id
            UNION ALL
            SELECT batch_picklist_code, order_id, MIN(wms_order_request_data_id) AS min_wms_order_request_data_id
            FROM wms_to_wcs_order_level_pre_staged_data_archive
            WHERE batch_picklist_code IN (SELECT batch_picklist_code FROM batch_pick_list_codes)
            GROUP BY batch_picklist_code, order_id
        ),
        
        -- Step 4: Get order line data summary
        order_line_data_summary AS (
            SELECT
                wms_order_request_data_id,
                order_line_id,
                article_id,
                quantity,
                order_id
            FROM wms_to_wcs_order_line_level_pre_staged_data
            WHERE wms_order_request_data_id IN (SELECT min_wms_order_request_data_id FROM batch_data_combined)
            UNION ALL
            SELECT
                wms_order_request_data_id,
                order_line_id,
                article_id,
                quantity,
                order_id
            FROM wms_to_wcs_order_line_level_pre_staged_data_archive
            WHERE wms_order_request_data_id IN (SELECT min_wms_order_request_data_id FROM batch_data_combined)
        ),
		-- Step 4.5: Archive without duplicate PWWDA
arc_without_duplicate_pwwda AS (
    SELECT DISTINCT
        wave_id,
        order_line_id,
        left_over,
        inserted_timestamp
    FROM pick_wave_wms_data_archive
    WHERE order_line_id IN (SELECT order_line_id FROM order_line_data_summary)
),
        
        -- Step 5: Get WMS data summary (start times)
        wms_data_summary AS (
            SELECT
                order_line_id,
                SUM(total_left_over) AS total_leftover,
                MIN(first_inserted_timestamp) AS first_inserted_timestamp
            FROM (
                SELECT
                    order_line_id,
                    SUM(left_over) AS total_left_over,
                    MIN(inserted_timestamp) AS first_inserted_timestamp
                FROM pick_wave_wms_data
                WHERE order_line_id IN (SELECT order_line_id FROM order_line_data_summary)
                GROUP BY order_line_id
                UNION ALL
                SELECT
                    order_line_id,
                    SUM(left_over) AS total_left_over,
                    MIN(inserted_timestamp) AS first_inserted_timestamp
                FROM arc_without_duplicate_pwwda
                GROUP BY order_line_id
            ) AS combined
            GROUP BY order_line_id
        ),
        
        -- Step 5.5: Get batch completion times
        batch_completion_times AS (
            SELECT
                batch_picklist_code,
                MAX(updated_timestamp) AS complete_time
            FROM wms_to_wcs_order_level_pre_staged_data
            WHERE updated_timestamp BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
                AND batch_picklist_code IN (SELECT batch_picklist_code FROM batch_pick_list_codes)
            GROUP BY batch_picklist_code
            HAVING SUM(order_request_status IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
        
            UNION ALL
        
            SELECT
                batch_picklist_code,
                MAX(updated_timestamp) AS complete_time
            FROM wms_to_wcs_order_level_pre_staged_data_archive
            WHERE updated_timestamp BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
                AND batch_picklist_code IN (SELECT batch_picklist_code FROM batch_pick_list_codes)
            GROUP BY batch_picklist_code
            HAVING SUM(order_request_status IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
        ),
		
		-- Step 6: Archive without duplicate PWOMA
arc_without_duplicate_pwoma AS (
    SELECT DISTINCT
        pick_order_id,
        order_line_id,
        order_id,
        picked_quantity,
        pick_start_timestamp,
        pick_timestamp
    FROM pick_wave_order_master_archive
    WHERE order_line_id IN (SELECT order_line_id FROM order_line_data_summary)
),
        
        -- Step 6: Get pick wave order master summary
        pick_wave_order_master_summary AS (
            SELECT order_line_id, order_id, SUM(total_picked_quantity) AS total_picked_quantity, MIN(min_time) AS min_time_start, MAX(max_time) AS max_pick_time
            FROM (
                SELECT
                    order_line_id,
                    order_id,
                    SUM(picked_quantity) AS total_picked_quantity,
                    MIN(pick_start_timestamp) AS min_time,
                    MAX(pick_timestamp) AS max_time
                FROM pick_wave_order_master
                WHERE order_line_id IN (SELECT order_line_id FROM order_line_data_summary)
                GROUP BY order_line_id, order_id
                UNION ALL
                SELECT
                    order_line_id,
                    order_id,
                    SUM(picked_quantity) AS total_picked_quantity,
                    MIN(pick_start_timestamp) AS min_time,
                    MAX(pick_timestamp) AS max_time
                FROM arc_without_duplicate_pwoma
                GROUP BY order_line_id, order_id
            ) combined
            GROUP BY order_id, order_line_id
        ),
        
        -- Step 7: LPN mapping
        lpn_mapping AS (
            SELECT pick_order_id, order_line_id, order_id
            FROM pick_wave_order_master
            WHERE order_line_id IN (SELECT order_line_id FROM pick_wave_order_master_summary)
            UNION ALL
            SELECT pick_order_id, order_line_id, order_id
            FROM pick_wave_order_master_archive
            WHERE order_line_id IN (SELECT order_line_id FROM pick_wave_order_master_summary)
        ),
        
        -- Step 8: LPN mapping detailed
        lpn_mapping_2 AS (
            SELECT
                bdc.batch_picklist_code,
                COUNT(DISTINCT combined.lpn_id) AS count_lpn_id,
                GROUP_CONCAT(DISTINCT combined.lpn_barcode) AS lpn_barcode,
                MIN(combined.lpn_open_timestamp) AS lpn_open_timestamp,
                MAX(combined.lpn_close_timestamp) AS lpn_close_timestamp
            FROM batch_data_combined bdc
            JOIN order_line_data_summary ols ON bdc.min_wms_order_request_data_id = ols.wms_order_request_data_id
            LEFT JOIN (
                SELECT
                    ll.pick_order_id,
                    lmm.order_id,
                    lmm.order_line_id,
                    ll.lpn_id,
                    ll.picked_quantity,
                    lm.lpn_barcode,
                    lm.lpn_open_timestamp,
                    lm.lpn_close_timestamp
                FROM lpn_pick_wave_order_mapping ll
                JOIN lpn_master lm ON ll.lpn_id = lm.lpn_id
                JOIN lpn_mapping lmm ON lmm.pick_order_id = ll.pick_order_id
                UNION ALL
                SELECT
                    ll.pick_order_id,
                    lmm.order_id,
                    lmm.order_line_id,
                    ll.lpn_id,
                    ll.picked_quantity,
                    lm.lpn_barcode,
                    lm.lpn_open_timestamp,
                    lm.lpn_close_timestamp
                FROM lpn_pick_wave_order_mapping_archive ll
                JOIN lpn_master lm ON ll.lpn_id = lm.lpn_id
                JOIN lpn_mapping lmm ON lmm.pick_order_id = ll.pick_order_id
            ) combined ON combined.order_line_id = ols.order_line_id
            GROUP BY bdc.batch_picklist_code
        ),
        
        -- Step 9: Get batch completion status
        batch_completion_status AS (
            SELECT
                batch_picklist_code,
                CASE
                    WHEN SUM(CASE WHEN order_request_status IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK') THEN 1 ELSE 0 END) > 0 THEN 'PROCESSING'
                    WHEN SUM(CASE WHEN order_request_status = 'COMPLETED' THEN 1 ELSE 0 END) = COUNT(*) THEN 'COMPLETED'
                    ELSE 'IN PROGRESS'
                END AS processing_status
            FROM (
                SELECT DISTINCT batch_picklist_code, order_id, order_request_status
                FROM wms_to_wcs_order_level_pre_staged_data
                WHERE batch_picklist_code IN (SELECT batch_picklist_code FROM batch_pick_list_codes)
                UNION ALL
                SELECT DISTINCT batch_picklist_code, order_id, order_request_status
                FROM wms_to_wcs_order_level_pre_staged_data_archive
                WHERE batch_picklist_code IN (SELECT batch_picklist_code FROM batch_pick_list_codes)
            ) combined_status
            GROUP BY batch_picklist_code
        )
        
        -- Final SELECT
        SELECT
            CASE
                WHEN SUM(COALESCE(ols.quantity, 0)) = SUM(COALESCE(pwm.total_picked_quantity, 0) + COALESCE(wms.total_leftover, 0))
                THEN 'COMPLETED'
                WHEN bct.complete_time IS NULL
                THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS `STATUS`,
            bdc.batch_picklist_code AS 'BATCH PICKLIST CODE',
            COUNT(DISTINCT ols.order_id) AS `TOTAL ORDER(s)`,
            COUNT(DISTINCT ols.order_line_id) AS `TOTAL ORDER LINE(s)`,
            COUNT(DISTINCT ols.article_id) AS `DISTINCT SKU(s)`,
            SUM(COALESCE(ols.quantity, 0)) AS `EXPECTED EACHES`,
            SUM(COALESCE(pwm.total_picked_quantity, 0)) AS `PICKED EACHES`,
            SUM(COALESCE(wms.total_leftover, 0)) AS `TOTAL STOCK ADJUSTMENT`,
            SUM(COALESCE(pwm.total_picked_quantity, 0) + COALESCE(wms.total_leftover, 0)) AS `OVERALL PICKED EACHES`,
            SUM(COALESCE(ols.quantity, 0) - (COALESCE(pwm.total_picked_quantity, 0) + COALESCE(wms.total_leftover, 0))) AS `PENDING EACHES`,
            COALESCE(l2.count_lpn_id, 0) AS `TOTAL LPN(s)`,
            DATE_FORMAT(MIN(wms.first_inserted_timestamp), '", v_datetime_format, "') AS `STARTED TIME`,
            DATE_FORMAT(bct.complete_time, '", v_datetime_format, "') AS `COMPLETED TIME`
        FROM batch_data_combined bdc
        JOIN order_line_data_summary ols
            ON bdc.min_wms_order_request_data_id = ols.wms_order_request_data_id
        LEFT JOIN wms_data_summary wms
            ON ols.order_line_id = wms.order_line_id
        LEFT JOIN pick_wave_order_master_summary pwm
            ON ols.order_line_id = pwm.order_line_id
            AND ols.order_id = pwm.order_id
        LEFT JOIN lpn_mapping_2 l2
            ON bdc.batch_picklist_code = l2.batch_picklist_code
        LEFT JOIN batch_completion_status bcs
            ON bdc.batch_picklist_code = bcs.batch_picklist_code
        LEFT JOIN batch_completion_times bct
            ON bdc.batch_picklist_code = bct.batch_picklist_code
        ", p_filter_condition, "
        GROUP BY
            bdc.batch_picklist_code, bct.complete_time"
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY_OLD` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY_OLD` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_OVERALL_SUMMARY_OLD`(IN Parameters JSON)
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
    DECLARE p_start_date_time VARCHAR(50);
    DECLARE p_end_date_time VARCHAR(50);
    
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
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = " ";
    ELSE
        SET p_filter_condition = CONCAT(" WHERE ", p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    DROP TEMPORARY TABLE IF EXISTS t_start_time;
    CREATE TEMPORARY TABLE t_start_time AS
        SELECT 
            a.ORDER_LINE_ID, 
            SUM(a.LEFT_OVER) AS LEFT_OVER,
            MIN(a.INSERTED_TIMESTAMP) AS INSERTED_TIMESTAMP
        FROM (
            SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP 
            FROM pick_wave_wms_data
            WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
            UNION ALL
            SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP 
            FROM pick_wave_wms_data_archive
            WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        ) a
        GROUP BY a.ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS t_complete_time;
    CREATE TEMPORARY TABLE t_complete_time AS
        SELECT 
            BATCH_PICKLIST_CODE,
            MAX(UPDATED_TIMESTAMP) AS COMPLETE_TIME
        FROM wms_to_wcs_order_level_pre_staged_data
        WHERE UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY BATCH_PICKLIST_CODE
        HAVING SUM(ORDER_REQUEST_STATUS IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0
        UNION ALL
        SELECT 
            BATCH_PICKLIST_CODE,
            MAX(UPDATED_TIMESTAMP) AS COMPLETE_TIME
        FROM wms_to_wcs_order_level_pre_staged_data_archive
        WHERE UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        GROUP BY BATCH_PICKLIST_CODE
        HAVING SUM(ORDER_REQUEST_STATUS IN ('ORDER_PICK_STARTED', 'PENDING', 'ROLLING_BACK')) = 0;
    
    DROP TEMPORARY TABLE IF EXISTS t;
    CREATE TEMPORARY TABLE t (
        WMS_ORDER_REQUEST_DATA_ID BIGINT,
        BATCH_PICKLIST_CODE VARCHAR(100),
        ORDER_ID VARCHAR(100),
        ORDER_LINE_ID VARCHAR(100),
        ARTICLE_ID VARCHAR(100),
        QUANTITY INT,
        LEFT_OVER INT,
        START_TIME DATETIME,
        COMPLETE_TIME DATETIME
    );
    
    INSERT INTO t
    SELECT 
        MIN(wtword.WMS_ORDER_REQUEST_DATA_ID),
        wtword.BATCH_PICKLIST_CODE,
        wtword.ORDER_ID,
        wtwolrd.ORDER_LINE_ID,
        wtwolrd.ARTICLE_ID,
        wtwolrd.QUANTITY,
        tst.LEFT_OVER,
        tst.INSERTED_TIMESTAMP,
        tct.COMPLETE_TIME
    FROM wms_to_wcs_order_level_pre_staged_data wtword
    JOIN wms_to_wcs_order_line_level_pre_staged_data wtwolrd 
        ON wtwolrd.WMS_ORDER_REQUEST_DATA_ID = wtword.WMS_ORDER_REQUEST_DATA_ID
    JOIN t_start_time tst 
        ON tst.ORDER_LINE_ID = wtwolrd.ORDER_LINE_ID
    LEFT JOIN t_complete_time tct 
        ON tct.BATCH_PICKLIST_CODE = wtword.BATCH_PICKLIST_CODE
    GROUP BY wtword.BATCH_PICKLIST_CODE, wtword.ORDER_ID, wtwolrd.ORDER_LINE_ID;
    
    INSERT INTO t
    SELECT 
        MIN(wtworda.WMS_ORDER_REQUEST_DATA_ID),
        wtworda.BATCH_PICKLIST_CODE,
        wtworda.ORDER_ID,
        wtwolrda.ORDER_LINE_ID,
        wtwolrda.ARTICLE_ID,
        wtwolrda.QUANTITY,
        tst.LEFT_OVER,
        tst.INSERTED_TIMESTAMP,
        tct.COMPLETE_TIME
    FROM wms_to_wcs_order_level_pre_staged_data_archive wtworda
    JOIN wms_to_wcs_order_line_level_pre_staged_data_archive wtwolrda
        ON wtwolrda.WMS_ORDER_REQUEST_DATA_ID = wtworda.WMS_ORDER_REQUEST_DATA_ID
    JOIN t_start_time tst 
        ON tst.ORDER_LINE_ID = wtwolrda.ORDER_LINE_ID
    LEFT JOIN t_complete_time tct 
        ON tct.BATCH_PICKLIST_CODE = wtworda.BATCH_PICKLIST_CODE
    GROUP BY wtworda.BATCH_PICKLIST_CODE, wtworda.ORDER_ID, wtwolrda.ORDER_LINE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS total_pick;
    CREATE TEMPORARY TABLE total_pick AS
        SELECT 
            t.BATCH_PICKLIST_CODE, 
            COALESCE(SUM(b.PICKED_QUANTITY), 0) AS TOTAL_PICKED
        FROM t
        LEFT JOIN (
	    SELECT DISTINCT(`PICK_ORDER_ID`),ORDER_LINE_ID, PICKED_QUANTITY 
	    FROM pick_wave_order_master 
	    WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED') 
	    GROUP BY PICK_ORDER_ID
	    UNION ALL
	    SELECT DISTINCT(`PICK_ORDER_ID`), ORDER_LINE_ID, PICKED_QUANTITY 
	    FROM pick_wave_order_master_archive 
	    WHERE STATUS NOT IN ('PENDING', 'PICK_STARTED') 
	    GROUP BY PICK_ORDER_ID
        ) b ON b.ORDER_LINE_ID = t.ORDER_LINE_ID
        GROUP BY t.BATCH_PICKLIST_CODE;
    
    DROP TEMPORARY TABLE IF EXISTS total_lpns;
    CREATE TEMPORARY TABLE total_lpns AS
        SELECT 
            t.BATCH_PICKLIST_CODE, 
            COUNT(c.LPN_ID) AS LPN_COUNT
        FROM t
        LEFT JOIN (
            SELECT pwom.ORDER_LINE_ID, lpwom.LPN_ID
            FROM pick_wave_order_master pwom
            JOIN lpn_pick_wave_order_mapping lpwom 
                ON lpwom.PICK_ORDER_ID = pwom.PICK_ORDER_ID
            GROUP BY lpwom.LPN_ID
            UNION ALL
            SELECT pwoma.ORDER_LINE_ID, lpwoma.LPN_ID
            FROM pick_wave_order_master_archive pwoma
            JOIN lpn_pick_wave_order_mapping_archive lpwoma 
                ON lpwoma.PICK_ORDER_ID = pwoma.PICK_ORDER_ID
            GROUP BY lpwoma.LPN_ID
        ) c ON c.ORDER_LINE_ID = t.ORDER_LINE_ID
        GROUP BY t.BATCH_PICKLIST_CODE;
    
    SET v_base_query = CONCAT(
        "SELECT
            CASE 
                WHEN (
                    COALESCE(b.TOTAL_PICKED, 0) + COALESCE(SUM(t.LEFT_OVER), 0)
                ) = COALESCE(SUM(t.QUANTITY), 0)
                AND t.COMPLETE_TIME IS NOT NULL THEN 'COMPLETE'
                WHEN t.COMPLETE_TIME IS NULL THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS 'STATUS',
            t.BATCH_PICKLIST_CODE AS 'BATCH PICKLIST CODE', 
            COUNT(DISTINCT t.ORDER_ID) AS 'TOTAL ORDER(s)',
            COUNT(DISTINCT t.ORDER_LINE_ID) AS 'TOTAL ORDER LINE(s)',
            COUNT(DISTINCT t.ARTICLE_ID) AS 'DISTINCT SKU(s)',
            COALESCE(SUM(t.QUANTITY), 0) AS 'EXPECTED EACHES',
            COALESCE(b.TOTAL_PICKED, 0) AS 'PICKED EACHES',
            COALESCE(SUM(t.LEFT_OVER), 0) AS 'TOTAL STOCK ADJUSTMENT',
            (COALESCE(b.TOTAL_PICKED, 0) + COALESCE(SUM(t.LEFT_OVER), 0)) AS 'OVERALL PICKED EACHES',
            (COALESCE(SUM(t.QUANTITY), 0) - (COALESCE(b.TOTAL_PICKED, 0) + COALESCE(SUM(t.LEFT_OVER), 0))) AS 'PENDING EACHES',
            c.LPN_COUNT AS 'TOTAL LPN(s)',
            DATE_FORMAT(t.START_TIME, '", v_datetime_format, "') AS 'STARTED TIME',
            DATE_FORMAT(t.COMPLETE_TIME, '", v_datetime_format, "') AS 'COMPLETED TIME'
        FROM t
        LEFT JOIN total_pick b ON b.BATCH_PICKLIST_CODE = t.BATCH_PICKLIST_CODE
        LEFT JOIN total_lpns c ON c.BATCH_PICKLIST_CODE = t.BATCH_PICKLIST_CODE
        ", p_filter_condition, "
        GROUP BY t.BATCH_PICKLIST_CODE"
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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
    
    DROP TEMPORARY TABLE IF EXISTS t_start_time;
    DROP TEMPORARY TABLE IF EXISTS t_complete_time;
    DROP TEMPORARY TABLE IF EXISTS t;
    DROP TEMPORARY TABLE IF EXISTS total_pick;
    DROP TEMPORARY TABLE IF EXISTS total_lpns;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_STATION_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_STATION_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_STATION_SUMMARY`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number                INT;
    DECLARE p_rows_per_page              INT;
    DECLARE p_download_flag              BOOL;
    DECLARE p_page_zero_metadata_flag    BOOL;
    DECLARE p_count_flag                 INT;
    DECLARE p_filter_condition           VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause              TEXT;
    DECLARE p_sorting_column_name        VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby     VARCHAR(50) DEFAULT '';
    DECLARE p_user_id                    VARCHAR(50);
    DECLARE p_user_name                  VARCHAR(50);
    DECLARE p_table_unique_identifier    VARCHAR(50);
    DECLARE p_report_extra_parameters    JSON;
    DECLARE p_start_date_time            VARCHAR(50);
    DECLARE p_end_date_time              VARCHAR(50);
    
    DECLARE v_sorting           VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format   VARCHAR(50);
    DECLARE v_base_query        TEXT;
    DECLARE v_total_rows        INT DEFAULT 0;
    DECLARE v_paginated_query   TEXT;
    
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
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
        OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `UPDATED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    SET v_base_query = CONCAT(
        "SELECT  
            archive_table.WAVE_ID AS 'WAVE ID',
            olld.STATION_ID AS 'STATION ID',
            COUNT(DISTINCT olld.ORDER_ID) AS 'TOTAL ORDERS',
            SUM(olld.TOTAL_ORDER_LINES) AS 'TOTAL ORDER LINES',
            SUM(olld.DISTINCT_ARTICLES) AS 'TOTAL SKU COUNT',
            SUM(olld.TOTAL_PICKING_QUANTITY) AS 'TOTAL PICKING QUANTITY',
            SUM(olld.TOTAL_PICKED_QUANTITY) AS 'TOTAL PICKED QUANTITY',
            SUM(olld.TOTAL_STOCK_ADJUSTMENT_QUANTITY) AS 'TOTAL STOCK ADJUSTMENT QUANTITY',
            SUM(olld.TOTAL_PICKED_QUANTITY + olld.TOTAL_STOCK_ADJUSTMENT_QUANTITY) AS 'TOTAL OVERALL QUANTITY',
            SUM(olld.LPN_BARCODE_COUNT) AS 'TOTAL LPNS',
            archive_table.WAVE_STATUS AS 'WAVE STATUS',
            DATE_FORMAT(archive_table.START_TIMESTAMP, '", v_datetime_format, "') AS 'STARTED TIME',
            archive_table.IS_STOPPED AS 'IS COMPLETED',
            DATE_FORMAT(archive_table.COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'COMPLETED TIME',
            archive_table.IS_CANCELLED AS 'IS SUSPENDED',
            DATE_FORMAT(archive_table.CANCELLED_TIMESTAMP, '", v_datetime_format, "') AS 'SUSPENDED TIME',
            archive_table.CANCELLED_BY AS 'SUSPENDED BY',
            archive_table.INSERTED_BY AS 'INSERTED BY',
            DATE_FORMAT(archive_table.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
            archive_table.UPDATED_BY AS 'UPDATED BY',
            DATE_FORMAT(archive_table.UPDATED_TIMESTAMP, '", v_datetime_format, "') AS 'UPDATED TIME'
        FROM (
            SELECT 
                WAVE_ID, WAVE_STATUS, START_TIMESTAMP,
                IS_STOPPED, COMPLETED_TIMESTAMP, IS_CANCELLED, CANCELLED_TIMESTAMP, CANCELLED_BY,
                INSERTED_BY, INSERTED_TIMESTAMP, UPDATED_BY, UPDATED_TIMESTAMP
            FROM wave_master
            WHERE INSERTED_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
            
            UNION ALL
            SELECT 
                WAVE_ID, WAVE_STATUS, START_TIMESTAMP,
                IS_STOPPED, COMPLETED_TIMESTAMP, IS_CANCELLED, CANCELLED_TIMESTAMP, CANCELLED_BY,
                INSERTED_BY, INSERTED_TIMESTAMP, UPDATED_BY, UPDATED_TIMESTAMP
            FROM wave_master_archive
            WHERE INSERTED_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
        ) AS archive_table
        INNER JOIN (
            SELECT 
                wword.ORDER_ID,
                pwwda_summary.WAVE_ID,
                COUNT(wwolrd.ORDER_LINE_ID) AS TOTAL_ORDER_LINES,
                COUNT(DISTINCT wwolrd.ARTICLE_ID) AS DISTINCT_ARTICLES,
                SUM(COALESCE(wwolrd.QUANTITY, 0)) AS TOTAL_PICKING_QUANTITY,
                COALESCE(pick_data_summary.TOTAL_PICKED_QUANTITY, 0) AS TOTAL_PICKED_QUANTITY,
                COALESCE(pwwda_summary.TOTAL_LEFT_OVER, 0) AS TOTAL_STOCK_ADJUSTMENT_QUANTITY,
                COALESCE(pick_data_summary.LPN_BARCODE_COUNT, 0) AS LPN_BARCODE_COUNT,
                pick_data_summary.STATION_ID
            FROM wms_to_wcs_order_level_pre_staged_data wword
            LEFT JOIN wms_to_wcs_order_line_level_pre_staged_data wwolrd 
                ON wwolrd.WMS_ORDER_REQUEST_DATA_ID = wword.WMS_ORDER_REQUEST_DATA_ID
            LEFT JOIN (
                SELECT ORDER_ID, SUM(LEFT_OVER) AS TOTAL_LEFT_OVER, WAVE_ID
                FROM (
                    SELECT ORDER_ID, LEFT_OVER, WAVE_ID FROM pick_wave_wms_data
                    UNION ALL
                    SELECT ORDER_ID, LEFT_OVER, WAVE_ID FROM pick_wave_wms_data_archive
                ) AS combined_left_over
                GROUP BY ORDER_ID, WAVE_ID
            ) AS pwwda_summary 
                ON pwwda_summary.ORDER_ID = wword.ORDER_ID
            LEFT JOIN (
                SELECT 
                    ORDER_ID,
                    SUM(PICKED_QUANTITY) AS TOTAL_PICKED_QUANTITY,
                    COUNT(DISTINCT LPN_BARCODE) AS LPN_BARCODE_COUNT,
                    STATION_ID
                FROM (
                    SELECT 
                        pwo.ORDER_ID,
                        lm.LPN_BARCODE,
                        lpwoma.PICKED_QUANTITY,
                        pwo.STATION_ID
                    FROM pick_wave_order_master pwo
                    LEFT JOIN lpn_pick_wave_order_mapping lpwoma ON lpwoma.PICK_ORDER_ID = pwo.PICK_ORDER_ID
                    LEFT JOIN lpn_master lm ON lm.LPN_ID = lpwoma.LPN_ID
                    UNION ALL
                    SELECT 
                        pwoa.ORDER_ID,
                        lm.LPN_BARCODE,
                        lpwoma.PICKED_QUANTITY,
                        pwoa.STATION_ID
                    FROM pick_wave_order_master_archive pwoa
                    LEFT JOIN lpn_pick_wave_order_mapping_archive lpwoma ON lpwoma.PICK_ORDER_ID = pwoa.PICK_ORDER_ID
                    LEFT JOIN lpn_master lm ON lm.LPN_ID = lpwoma.LPN_ID
                ) AS combined_pick_data
                GROUP BY ORDER_ID
            ) AS pick_data_summary 
                ON pick_data_summary.ORDER_ID = wword.ORDER_ID
            WHERE wword.WMS_ORDER_REQUEST_DATA_ID IN (
                SELECT w2.WMS_ORDER_REQUEST_DATA_ID
                FROM wms_to_wcs_order_level_pre_staged_data w2
                WHERE w2.INSERTED_TIMESTAMP = (
                    SELECT MIN(w3.INSERTED_TIMESTAMP)
                    FROM wms_to_wcs_order_level_pre_staged_data w3
                    WHERE w3.ORDER_ID = w2.ORDER_ID
                )
            )
            GROUP BY wword.ORDER_ID, pwwda_summary.WAVE_ID
        ) AS olld ON archive_table.WAVE_ID = olld.WAVE_ID", 
        p_filter_condition, "
        GROUP BY 
            archive_table.WAVE_ID,
            archive_table.WAVE_STATUS,
            archive_table.START_TIMESTAMP,
            archive_table.IS_STOPPED,
            archive_table.COMPLETED_TIMESTAMP,
            archive_table.IS_CANCELLED,
            archive_table.CANCELLED_TIMESTAMP,
            archive_table.CANCELLED_BY,
            archive_table.INSERTED_BY,
            archive_table.INSERTED_TIMESTAMP,
            archive_table.UPDATED_BY,
            archive_table.UPDATED_TIMESTAMP"
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PICK_WAVE_LEFT_OVER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PICK_WAVE_LEFT_OVER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PICK_WAVE_LEFT_OVER`(IN Parameters JSON)
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
    DECLARE p_wave_id VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number = Parameters ->> '$.page_number';
    SET p_rows_per_page = Parameters ->> '$.rows_per_page';
    SET p_user_id = Parameters ->> '$.user_id';
    SET p_user_name = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag = Parameters ->> '$.count';
    SET p_filter_condition = Parameters ->> '$.filter_data';
    SET p_select_clause = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby = Parameters ->> '$.sorting_column_orderby';
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_wave_id = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
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
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET v_base_query = CONCAT(
        "SELECT 
                pwwd.WAVE_ID AS 'WAVE ID',
                pwwd.ORDER_ID AS 'ORDER ID',
                pwwd.ORDER_LINE_ID AS 'ORDER LINE ID',
                pwwd.LEFT_OVER AS 'LEFT OVER',
                pwwd.SKU_ID AS 'SKU ID'
         FROM pick_wave_wms_data pwwd
         LEFT JOIN wave_master wm ON pwwd.WAVE_ID = wm.WAVE_ID
         WHERE pwwd.WAVE_ID = '", p_wave_id, "'
         AND pwwd.LEFT_OVER > 0 ",
         p_filter_condition, "
         
         UNION ALL
         
         SELECT 
                pwwd.WAVE_ID AS 'WAVE ID',
                pwwd.ORDER_ID AS 'ORDER ID',
                pwwd.ORDER_LINE_ID AS 'ORDER LINE ID',
                pwwd.LEFT_OVER AS 'LEFT OVER',
                pwwd.SKU_ID AS 'SKU ID'
         FROM pick_wave_wms_data_archive pwwd
         LEFT JOIN wave_master_archive wm ON pwwd.WAVE_ID = wm.WAVE_ID
         WHERE pwwd.WAVE_ID = '", p_wave_id, "'
         AND pwwd.LEFT_OVER > 0 ",
         p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, "
         FROM (", v_base_query, ") AS SUBQUERY",
         v_sorting, "
         LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_table_unique_identifier VARCHAR(50);
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_wave_id VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
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
    SET p_table_unique_identifier         = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters   = Parameters ->> '$.report_extra_parameters';
    SET p_wave_id                   = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
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
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    SET v_base_query = CONCAT(
	    "SELECT 
		pwoman.SKU_ID AS 'SKU ID',
		sbm.MRP AS 'MRP',
		pwoman.BIN_ID AS 'BIN ID',
		pwoman.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
		DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
		pwoman.EXPECTED_QUANTITY AS 'EXPECTED QUANTITY',
		pwoman.STATION_ID AS 'STATION ID',
		pwoman.PUT_QUANTITY AS 'PUT QUANTITY',
		pwoman.SHORT_PUT_QUANTITY AS 'SHORT PUT QUANTITY',
		pwoman.PUT_TIMESTAMP AS 'PUT END TIME',
		pwoman.PUT_START_TIMESTAMP AS 'PUT START TIME',
		obml.LOGGED_TIMESTAMP AS 'BIN ON STATION',
		TIMESTAMPDIFF(SECOND, pwoman.PUT_START_TIMESTAMP, pwoman.PUT_TIMESTAMP) AS 'PUT TIME DIFFERENCE'
	    FROM put_wave_order_master_archive AS pwoman
	    INNER JOIN wave_master_archive AS wma ON pwoman.WAVE_ID = wma.WAVE_ID
	    INNER JOIN sku_batch_master AS sbm ON sbm.BATCH_ID = pwoman.BATCH_ID
	    INNER JOIN order_bin_mapping_log AS obml ON obml.ORDER_BIN_ID = pwoman.ORDER_BIN_ID
	    WHERE pwoman.WAVE_ID = '", p_wave_id, "' 
	      AND obml.STATUS = 'ON_STATION'", p_filter_condition
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL_BY_DATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL_BY_DATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL_BY_DATE`(IN Parameters JSON)
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
    
    
    IF p_sorting_column_name IS NOT NULL AND p_sorting_column_name != '' THEN
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    IF p_filter_condition IS NOT NULL AND p_filter_condition != '' THEN
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition, '');
    END IF;
    
    SET v_base_query = CONCAT("
        WITH CombinedPutWave AS (
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
            WHERE STATUS NOT IN ('PENDING', 'PUT_STARTED')
              AND PUT_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
              AND PUT_QUANTITY > 0
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
           WHERE STATUS NOT IN ('PENDING', 'PUT_STARTED')
              AND PUT_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
              AND PUT_QUANTITY > 0
        ),
        CombinedMappingLog AS (
            SELECT
                ORDER_BIN_ID,
                BIN_ID,
                STATION_ID,
                MAX(CASE WHEN STATUS = 'BIN_PICKED' THEN BOT_ID END) AS TASK_ALLOCATED_BOT_ID,
                MAX(CASE WHEN STATUS = 'PRE_ON_STATION' THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
                MAX(CASE WHEN STATUS = 'ON_STATION' THEN UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
            FROM order_bin_mapping_log
            WHERE TYPE = 'RACK_PICK'
              AND ORDER_BIN_ID IN (SELECT DISTINCT ORDER_BIN_ID FROM CombinedPutWave)
            GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID
        )
        SELECT
            b.WAVE_ID AS 'WAVE ID',
            b.STATION_ID AS 'STATION ID',
            b.STORAGE_REQUEST_ID AS 'STORAGE REQUEST ID',
            b.SKU_ID AS 'SKU ID',
            b.BIN_ID AS 'BIN ID',
            b.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
            sbm.mrp AS 'MRP',
            DATE_FORMAT(sbm.expiry_date, '", v_date_format, "') AS 'EXPIRY',
            b.EXPECTED_QUANTITY AS 'EXPECTED QUANTITY',
            b.PUT_QUANTITY  AS 'PUT QUANTITY',
            b.SHORT_PUT_QUANTITY  AS 'SHORT PUT QUANTITY',
            DATE_FORMAT(o.ON_STATION_TIMESTAMP, '", v_datetime_format, "') AS 'ON STATION TIME',
            DATE_FORMAT(b.PUT_START_TIMESTAMP, '", v_datetime_format, "') AS 'PUT STARTED TIME',
            DATE_FORMAT(b.PUT_TIMESTAMP, '", v_datetime_format, "') AS 'PUT COMPLETED TIME',
            TIMESTAMPDIFF(SECOND, b.PUT_START_TIMESTAMP, b.PUT_TIMESTAMP) AS 'DIFFERENCE (IN SECS)',
            b.PUT_BY AS 'PUT BY',
            o.TASK_ALLOCATED_BOT_ID AS 'BIN PUT BOT ID',
            DATE_FORMAT(o.PRE_ON_STATION_TIMESTAMP, '", v_datetime_format, "') AS 'BIN PUT TIME'
        FROM CombinedPutWave b
        JOIN CombinedMappingLog o ON b.ORDER_BIN_ID = o.ORDER_BIN_ID
        JOIN sku_batch_master sbm ON b.BATCH_ID = sbm.BATCH_ID
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL_BY_DATE_OLD` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL_BY_DATE_OLD` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_BIN_LEVEL_BY_DATE_OLD`(IN Parameters JSON)
BEGIN
    
    DECLARE p_page_number INT;
    DECLARE p_rows_per_page INT;
    DECLARE p_user_id VARCHAR(50);
    DECLARE p_user_name VARCHAR(50);
    DECLARE p_download_flag BOOL;
    DECLARE p_page_zero_metadata_flag BOOL;
    DECLARE p_count_flag INT;
    DECLARE p_filter_condition VARCHAR(2000) DEFAULT '';
    DECLARE p_select_clause TEXT;
    DECLARE p_sorting_column_name VARCHAR(50) DEFAULT '';
    DECLARE p_sorting_column_orderby VARCHAR(50) DEFAULT '';
    DECLARE p_table_unique_identifier VARCHAR(50);
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_start_date_time VARCHAR(50);
    DECLARE p_end_date_time VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
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
    SET p_start_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time             = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    
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
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary;
    CREATE TEMPORARY TABLE temp_pallet_summary AS
    SELECT 
        s.PALLET_ID, 
        s.STORAGE_REQUEST_ID,
        s.STORAGE_ID,
        s.ARTICLE_ID,
        SUM(s.QUANTITY) AS total_quantity
    FROM (
        SELECT 
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrd.STORAGE_ID,
            wtwsrd.ARTICLE_ID,
            wtwsrd.QUANTITY,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID, wtwsrd.STORAGE_ID
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
        JOIN wms_to_wcs_storage_request_data wtwsrd
            ON wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID = wtwsrd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
        WHERE wtwsrpd.PALLET_SCANNED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ) s
    WHERE s.rn = 1
    GROUP BY s.PALLET_ID, s.STORAGE_REQUEST_ID, s.STORAGE_ID, s.ARTICLE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders;
    CREATE TEMPORARY TABLE combined_put_orders AS
    SELECT 
        combined.WAVE_ID,
        combined.STORAGE_ID,
        combined.BIN_ID,
        combined.BIN_SEGMENT_NO,
        combined.EXPECTED_QUANTITY,
        combined.PUT_QUANTITY,
        combined.PUT_START_TIMESTAMP,
        combined.PUT_TIMESTAMP,
        combined.PUT_ORDER_ID,
        combined.STATION_ID,
        combined.ORDER_BIN_ID,
        combined.PUT_BY
    FROM (
        SELECT 
            WAVE_ID,
            STORAGE_ID, 
            BIN_ID,
            EXPECTED_QUANTITY,
            PUT_QUANTITY,
            PUT_START_TIMESTAMP,
            PUT_TIMESTAMP,
            PUT_ORDER_ID,
            STATION_ID,
            BIN_SEGMENT_NO,
            ORDER_BIN_ID,
            PUT_BY
        FROM put_wave_order_master
        UNION ALL
        SELECT 
            WAVE_ID,
            STORAGE_ID, 
            BIN_ID,
            EXPECTED_QUANTITY,
            PUT_QUANTITY,
            PUT_START_TIMESTAMP,
            PUT_TIMESTAMP,
            PUT_ORDER_ID,
            STATION_ID,
            BIN_SEGMENT_NO,
            ORDER_BIN_ID,
            PUT_BY
        FROM put_wave_order_master_archive
    ) combined
    JOIN temp_pallet_summary tps ON tps.STORAGE_ID = combined.STORAGE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders_for_SP;
    CREATE TEMPORARY TABLE combined_put_orders_for_SP AS
    SELECT 
        STORAGE_REQUEST_ID,
        STORAGE_ID,
        PUT_QUANTITY,
        PUT_START_TIMESTAMP,
        PUT_ORDER_ID
    FROM put_wave_order_master_archive
    WHERE ARCHIVE_REASON = 'ARCHIVED';
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_sub_part;
    CREATE TEMPORARY TABLE missing_quantity_sub_part AS
    SELECT 
        PUT_ORDER_ID,
        SUM(SHORT_PUT_QUANTITY) AS total_short_quantity
    FROM short_put_wave_reason 
    WHERE REASON <> 'NO_SPACE_IN_BIN'
    GROUP BY PUT_ORDER_ID;
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_summary;
    CREATE TEMPORARY TABLE missing_quantity_summary AS
    SELECT 
        p.STORAGE_ID,
        p.PUT_ORDER_ID,
        s.total_short_quantity
    FROM combined_put_orders_for_SP p
    JOIN missing_quantity_sub_part s ON p.PUT_ORDER_ID = s.PUT_ORDER_ID;
    
    DROP TEMPORARY TABLE IF EXISTS sku_details;
    CREATE TEMPORARY TABLE sku_details AS
    SELECT 
        SKU_ID,
        MRP,
        EXPIRY_DATE
    FROM sku_batch_master;
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary_2;
    CREATE TEMPORARY TABLE temp_pallet_summary_2 AS
    SELECT 
        s.PALLET_ID,
        s.STORAGE_REQUEST_ID,
        s.PALLET_SCANNED_TIMESTAMP
    FROM (
        SELECT 
            wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID,
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrpd.PALLET_SCANNED_TIMESTAMP,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID DESC
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
    ) s
    WHERE s.rn = 1
    GROUP BY s.PALLET_ID, s.STORAGE_REQUEST_ID, s.PALLET_SCANNED_TIMESTAMP;
    
    SET v_base_query = CONCAT(
        "SELECT 
            cpo.WAVE_ID AS 'WAVE ID',
            cpo.STATION_ID AS 'STATION ID',
            tps.STORAGE_REQUEST_ID AS 'STORAGE REQUEST ID',
            tps.ARTICLE_ID AS 'SKU ID',
            s.MRP AS 'MRP',
            cpo.BIN_ID AS 'BIN ID',
            cpo.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
            DATE_FORMAT(s.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
            cpo.EXPECTED_QUANTITY AS 'EXPECTED QUANTITY',
            cpo.PUT_QUANTITY AS 'PUT QUANTITY',
            COALESCE(mqs.total_short_quantity, 0) AS 'SHORT PUT QUANTITY',
            DATE_FORMAT(obml.LOGGED_TIMESTAMP, '", v_datetime_format, "') AS 'ON STATION TIME',
            DATE_FORMAT(cpo.PUT_START_TIMESTAMP, '", v_datetime_format, "') AS 'PUT STARTED TIME',
            DATE_FORMAT(cpo.PUT_TIMESTAMP, '", v_datetime_format, "') AS 'PUT COMPLETED TIME',
            TIMESTAMPDIFF(SECOND, cpo.PUT_START_TIMESTAMP, cpo.PUT_TIMESTAMP) AS 'DIFFERENCE (IN SECS)',
            cpo.PUT_BY AS 'PUT BY'
        FROM temp_pallet_summary tps
        LEFT JOIN combined_put_orders cpo ON tps.STORAGE_ID = cpo.STORAGE_ID
        LEFT JOIN missing_quantity_summary mqs ON cpo.PUT_ORDER_ID = mqs.PUT_ORDER_ID
        LEFT JOIN temp_pallet_summary_2 tps2 ON tps.STORAGE_REQUEST_ID = tps2.STORAGE_REQUEST_ID
        LEFT JOIN sku_details s ON tps.ARTICLE_ID = s.SKU_ID
        INNER JOIN order_bin_mapping_log obml ON obml.ORDER_BIN_ID = cpo.ORDER_BIN_ID
        WHERE cpo.PUT_START_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "' 
        AND obml.STATUS = 'ON_STATION'", p_filter_condition, "
        GROUP BY 
            cpo.WAVE_ID, tps.PALLET_ID, tps.STORAGE_REQUEST_ID, tps.STORAGE_ID, tps.ARTICLE_ID, 
            tps.total_quantity, cpo.BIN_ID, cpo.BIN_SEGMENT_NO, 
            cpo.PUT_START_TIMESTAMP, cpo.PUT_TIMESTAMP, 
            cpo.PUT_QUANTITY, mqs.total_short_quantity"
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_ORDERS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_ORDERS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_ORDERS`(IN Parameters JSON)
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
    DECLARE p_wave_id VARCHAR(50);
    DECLARE p_wave_status VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
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
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    SET p_table_unique_identifier         = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters   = Parameters ->> '$.report_extra_parameters';
    SET p_wave_id                   = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
    IF p_wave_id IS NOT NULL AND p_wave_id != '' THEN
        SELECT WAVE_STATUS INTO p_wave_status FROM wave_master WHERE WAVE_ID = p_wave_id;
        IF p_wave_status NOT IN ('COMPLETED', 'PROCESSING') THEN
            IF p_table_unique_identifier = 'report_wave_put_orders' THEN
                SET p_table_unique_identifier = 'report_wave_put_orders_wms';
            END IF;
        END IF;
    END IF;
    
    IF p_table_unique_identifier = 'report_wave_put_orders_wms' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                pwwd.WAVE_MASTER_ID AS 'ID',
                wm.WAVE_ID AS 'WAVE ID',
                pwwd.SKU_ID AS 'SKU ID',
                pwwd.BATCH_ID AS 'BATCH ID',
                pwwd.QUANTITY, 
                sbm.MRP, 
                DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
                pwwd.LEFT_OVER AS 'LEFT OVER'
             FROM put_wave_wms_data AS pwwd
             INNER JOIN wave_master AS wm ON pwwd.WAVE_ID = wm.WAVE_ID
             INNER JOIN sku_batch_master AS sbm ON sbm.BATCH_ID = pwwd.BATCH_ID
             WHERE pwwd.WAVE_ID = '", p_wave_id, "'", p_filter_condition
        );
        
    ELSEIF p_table_unique_identifier = 'report_wave_put_orders' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                wm.WAVE_ID AS 'WAVE ID',
                pwoman.SKU_ID AS 'SKU ID',
                sbm.MRP AS 'MRP',
                DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
                pwoman.EXPECTED_QUANTITY AS 'EXPECTED QUANTITY',
                pwoman.PUT_QUANTITY AS 'PUT QUANTITY',
                pwoman.SHORT_PUT_QUANTITY AS 'SHORT PUT QUANTITY',
                DATE_FORMAT(pwoman.PUT_TIMESTAMP, '", v_datetime_format, "') AS 'PUT TIME',
                pwoman.PUT_BY AS 'PUT BY',
                pwoman.STATION_ID AS 'STATION ID',
                DATE_FORMAT(wm.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
                DATE_FORMAT(wm.START_TIMESTAMP, '", v_datetime_format, "') AS 'START TIME',
                DATE_FORMAT(wm.COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'COMPLETED TIME',
                DATE_FORMAT(wm.CANCELLED_TIMESTAMP, '", v_datetime_format, "') AS 'CANCELLED TIME'
             FROM put_wave_order_master AS pwoman
             INNER JOIN wave_master AS wm ON pwoman.WAVE_ID = wm.WAVE_ID
             INNER JOIN sku_batch_master AS sbm ON sbm.BATCH_ID = pwoman.BATCH_ID
             WHERE wm.WAVE_ID = '", p_wave_id, "'", p_filter_condition,
            " UNION ALL ",
            "SELECT 
            
                wma.WAVE_ID AS 'WAVE ID',
                pwoa.SKU_ID AS 'SKU ID',
                sbm.MRP AS 'MRP',
                DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
                pwoa.EXPECTED_QUANTITY AS 'EXPECTED QUANTITY',
                pwoa.PUT_QUANTITY AS 'PUT QUANTITY',
                pwoa.SHORT_PUT_QUANTITY AS 'SHORT PUT QUANTITY',
                DATE_FORMAT(pwoa.PUT_TIMESTAMP, '", v_datetime_format, "') AS 'PUT TIME',
                pwoa.PUT_BY AS 'PUT BY',
                pwoa.STATION_ID AS 'STATION ID',
                DATE_FORMAT(wma.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
                DATE_FORMAT(wma.START_TIMESTAMP, '", v_datetime_format, "') AS 'START TIME',
                DATE_FORMAT(wma.COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'COMPLETED TIME',
                DATE_FORMAT(wma.CANCELLED_TIMESTAMP, '", v_datetime_format, "') AS 'CANCELLED TIME'
             FROM put_wave_order_master_archive AS pwoa
             INNER JOIN wave_master_archive AS wma ON pwoa.WAVE_ID = wma.WAVE_ID
             INNER JOIN sku_batch_master AS sbm ON sbm.BATCH_ID = pwoa.BATCH_ID
             WHERE wma.WAVE_ID = '", p_wave_id, "'", p_filter_condition
        );
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_BIN_LEVEL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_BIN_LEVEL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_BIN_LEVEL_SUMMARY`(IN Parameters JSON)
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
    DECLARE p_start_date_time VARCHAR(50);
    DECLARE p_end_date_time VARCHAR(50);
    DECLARE p_pallet_id VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number               = Parameters ->> '$.page_number';
    SET p_rows_per_page            = Parameters ->> '$.rows_per_page';
    SET p_user_id                  = Parameters ->> '$.user_id';
    SET p_user_name                = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag               = Parameters ->> '$.count';
    SET p_filter_condition         = Parameters ->> '$.filter_data';
    SET p_select_clause            = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name      = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby   = Parameters ->> '$.sorting_column_orderby';
    SET p_table_unique_identifier  = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters  = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time          = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time            = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    SET p_pallet_id                = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.pallet_id'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = ' ';
    ELSE
        SET p_filter_condition = CONCAT(' AND ', p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('DATETIME');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary;
    CREATE TEMPORARY TABLE temp_pallet_summary AS
    SELECT 
        s.PALLET_ID, 
        s.STORAGE_REQUEST_ID,
        s.STORAGE_ID,
        s.ARTICLE_ID,
        SUM(s.QUANTITY) AS total_quantity
    FROM (
        SELECT 
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrd.STORAGE_ID,
            wtwsrd.ARTICLE_ID,
            wtwsrd.QUANTITY,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID, wtwsrd.STORAGE_ID
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
        JOIN wms_to_wcs_storage_request_data wtwsrd
            ON wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID = wtwsrd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
        WHERE PALLET_ID = p_pallet_id  
          AND wtwsrpd.PALLET_SCANNED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ) s
    WHERE s.rn = 1
    GROUP BY s.PALLET_ID, s.STORAGE_REQUEST_ID, s.STORAGE_ID, s.ARTICLE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders;
    CREATE TEMPORARY TABLE combined_put_orders AS
    SELECT 
        combined.WAVE_ID, combined.STORAGE_ID, combined.BIN_ID, combined.BIN_SEGMENT_NO, 
        combined.EXPECTED_QUANTITY, combined.PUT_QUANTITY,
        combined.PUT_START_TIMESTAMP, combined.PUT_TIMESTAMP,
        combined.PUT_ORDER_ID, combined.STATION_ID
    FROM (
        SELECT 
		WAVE_ID,
		STORAGE_ID, 
		BIN_ID,
		EXPECTED_QUANTITY,
		PUT_QUANTITY,
		PUT_START_TIMESTAMP,
		PUT_TIMESTAMP,
		PUT_ORDER_ID,
		STATION_ID,
		BIN_SEGMENT_NO
         FROM put_wave_order_master
        UNION ALL
        SELECT 
                WAVE_ID,
		STORAGE_ID, 
		BIN_ID,
		EXPECTED_QUANTITY,
		PUT_QUANTITY,
		PUT_START_TIMESTAMP,
		PUT_TIMESTAMP,
		PUT_ORDER_ID,
		STATION_ID,
		BIN_SEGMENT_NO
	FROM put_wave_order_master_archive
    ) combined
    JOIN temp_pallet_summary tps ON tps.STORAGE_ID = combined.STORAGE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders_for_SP;
    CREATE TEMPORARY TABLE combined_put_orders_for_SP AS
    SELECT 
        STORAGE_REQUEST_ID, STORAGE_ID, PUT_QUANTITY, 
        PUT_START_TIMESTAMP, PUT_ORDER_ID
    FROM put_wave_order_master_archive
    WHERE ARCHIVE_REASON = 'ARCHIVED';
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_sub_part;
    CREATE TEMPORARY TABLE missing_quantity_sub_part AS
    SELECT 
        PUT_ORDER_ID, SUM(SHORT_PUT_QUANTITY) AS total_short_quantity
    FROM short_put_wave_reason 
    WHERE REASON <> 'NO_SPACE_IN_BIN'
    GROUP BY PUT_ORDER_ID;
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_summary;
    CREATE TEMPORARY TABLE missing_quantity_summary AS
    SELECT 
        p.STORAGE_ID, p.PUT_ORDER_ID, s.total_short_quantity
    FROM combined_put_orders_for_SP p
    JOIN missing_quantity_sub_part s ON p.PUT_ORDER_ID = s.PUT_ORDER_ID;
    
    DROP TEMPORARY TABLE IF EXISTS sku_details;
    CREATE TEMPORARY TABLE sku_details AS
    SELECT SKU_ID, MRP, EXPIRY_DATE FROM sku_batch_master;
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary_2;
    CREATE TEMPORARY TABLE temp_pallet_summary_2 AS
    SELECT 
        s.PALLET_ID, s.STORAGE_REQUEST_ID, s.PALLET_SCANNED_TIMESTAMP
    FROM (
        SELECT 
            wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID,
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrpd.PALLET_SCANNED_TIMESTAMP,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID DESC
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
    ) s
    WHERE s.rn = 1
    GROUP BY s.PALLET_ID, s.STORAGE_REQUEST_ID, s.PALLET_SCANNED_TIMESTAMP;
    
    SET v_base_query = CONCAT(
        "SELECT 
            cpo.WAVE_ID AS 'WAVE ID',
            tps.STORAGE_REQUEST_ID AS 'STORAGE REQUEST ID',
            tps.STORAGE_ID AS 'STORAGE ID',
            tps.ARTICLE_ID AS 'ARTICLE ID',
            s.MRP AS 'MRP',
            cpo.EXPECTED_QUANTITY AS 'EXPECTED EACHES',
            cpo.PUT_QUANTITY AS 'PUT EACHES',
            cpo.BIN_ID AS 'BIN ID',
            cpo.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
            cpo.STATION_ID AS 'STATION ID',
            DATE_FORMAT(s.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
            COALESCE(mqs.total_short_quantity, 0) AS 'TOTAL STOCK ADJUSTMENT',
            DATE_FORMAT(cpo.PUT_START_TIMESTAMP, '", v_datetime_format, "') AS 'STARTED TIME',
            DATE_FORMAT(cpo.PUT_TIMESTAMP, '", v_datetime_format, "') AS 'COMPLETED TIME'
        FROM temp_pallet_summary tps
        LEFT JOIN combined_put_orders cpo ON tps.STORAGE_ID = cpo.STORAGE_ID
        LEFT JOIN missing_quantity_summary mqs ON cpo.PUT_ORDER_ID = mqs.PUT_ORDER_ID
        LEFT JOIN temp_pallet_summary_2 tps2 ON tps.STORAGE_REQUEST_ID = tps2.STORAGE_REQUEST_ID
        LEFT JOIN sku_details s ON tps.ARTICLE_ID = s.SKU_ID
        WHERE cpo.PUT_START_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "' ",
        p_filter_condition, "
        GROUP BY 
            cpo.WAVE_ID, tps.PALLET_ID, tps.STORAGE_REQUEST_ID, tps.STORAGE_ID, tps.ARTICLE_ID, 
            tps.total_quantity, cpo.BIN_ID, cpo.BIN_SEGMENT_NO, 
            cpo.PUT_START_TIMESTAMP, cpo.PUT_TIMESTAMP, 
            cpo.PUT_QUANTITY, mqs.total_short_quantity"
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_SR_LEVEL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_SR_LEVEL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_SR_LEVEL_SUMMARY`(IN Parameters JSON)
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
    DECLARE p_start_date_time VARCHAR(50);
    DECLARE p_end_date_time VARCHAR(50);
    DECLARE p_pallet_id VARCHAR(50);
    
    
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
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    SET p_pallet_id               = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.pallet_id'));
    
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = ' ';
    ELSE
        SET p_filter_condition = CONCAT(' AND ', p_filter_condition);
    END IF;
    
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('DATETIME');
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary;
    CREATE TEMPORARY TABLE temp_pallet_summary AS
    SELECT 
        s.PALLET_ID, 
        s.STORAGE_REQUEST_ID,
        COUNT(DISTINCT s.STORAGE_ID) AS distinct_storage_count,
        COUNT(DISTINCT s.ARTICLE_ID) AS distinct_article_count,
        SUM(s.QUANTITY) AS total_quantity,
        s.PALLET_SCANNED_TIMESTAMP,
        s.PALLET_COMPLETION_TIMESTAMP
    FROM (
        SELECT 
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrd.STORAGE_ID,
            wtwsrd.ARTICLE_ID,
            wtwsrd.QUANTITY,
            wtwsrpd.PALLET_SCANNED_TIMESTAMP,
            wtwsrpd.PALLET_COMPLETION_TIMESTAMP,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID, wtwsrd.STORAGE_ID
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
        JOIN wms_to_wcs_storage_request_data wtwsrd 
            ON wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID = wtwsrd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
        WHERE PALLET_ID = p_pallet_id 
          AND PALLET_SCANNED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ) s
    WHERE s.rn = 1
    GROUP BY s.PALLET_ID, s.STORAGE_REQUEST_ID
    ORDER BY s.PALLET_SCANNED_TIMESTAMP DESC;
    
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders_sync;
    CREATE TEMPORARY TABLE combined_put_orders_sync AS
    SELECT 
        combined.STORAGE_REQUEST_ID, 
        SUM(combined.PUT_QUANTITY) AS PUT_QUANTITY
    FROM (
        SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID, bin_transfer_payload_id 
        FROM put_wave_order_master
        UNION ALL
        SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID, bin_transfer_payload_id 
        FROM put_wave_order_master_archive
    ) combined
    JOIN temp_pallet_summary tps ON tps.STORAGE_REQUEST_ID = combined.STORAGE_REQUEST_ID
    JOIN wcs_to_wms_payload ws ON ws.payload_id = combined.bin_transfer_payload_id
    WHERE ws.is_processed = 1
    GROUP BY combined.STORAGE_REQUEST_ID;
    
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_adjustment_sync;
    CREATE TEMPORARY TABLE combined_put_adjustment_sync AS
    SELECT 
        combined.STORAGE_REQUEST_ID, 
        SUM(combined.STOCK_ADJUSTMENT_QUANTITY) AS TOTAL_STOCK_ADJUSTMENT
    FROM (
        SELECT 
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            MAX(STOCK_ADJUSTMENT_QUANTITY) AS STOCK_ADJUSTMENT_QUANTITY,
            STOCK_ADJUSTMENT_PAYLOAD_ID 
        FROM wms_to_wcs_storage_request_data
        GROUP BY STORAGE_REQUEST_ID, STORAGE_ID
        
        UNION ALL 
        
        SELECT 
            STORAGE_REQUEST_ID,
            STORAGE_ID,
            MAX(STOCK_ADJUSTMENT_QUANTITY) AS STOCK_ADJUSTMENT_QUANTITY,
            STOCK_ADJUSTMENT_PAYLOAD_ID 
        FROM wms_to_wcs_storage_request_data_archive
        GROUP BY STORAGE_REQUEST_ID, STORAGE_ID
    ) combined
    JOIN temp_pallet_summary tps ON tps.STORAGE_REQUEST_ID = combined.STORAGE_REQUEST_ID
    JOIN wcs_to_wms_payload ws ON ws.payload_id = combined.STOCK_ADJUSTMENT_PAYLOAD_ID
    WHERE ws.is_processed = 1
    GROUP BY combined.STORAGE_REQUEST_ID;
    
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders;
    CREATE TEMPORARY TABLE combined_put_orders AS
    SELECT 
        combined.STORAGE_REQUEST_ID,
        SUM(combined.PUT_QUANTITY) AS PUT_QUANTITY,
        MIN(combined.PUT_START_TIMESTAMP) AS PUT_START_TIMESTAMP,
        MAX(combined.PUT_ORDER_ID) AS PUT_ORDER_ID
    FROM (
        SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID 
        FROM put_wave_order_master
        UNION ALL
        SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID 
        FROM put_wave_order_master_archive
    ) combined
    JOIN temp_pallet_summary tps ON tps.STORAGE_REQUEST_ID = combined.STORAGE_REQUEST_ID
    GROUP BY STORAGE_REQUEST_ID;
    
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders_for_SP;
    CREATE TEMPORARY TABLE combined_put_orders_for_SP AS
    SELECT 
        combined.STORAGE_REQUEST_ID,
        combined.PUT_QUANTITY,
        combined.PUT_START_TIMESTAMP,
        combined.PUT_ORDER_ID
    FROM (
        SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID 
        FROM put_wave_order_master
        UNION ALL
        SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID 
        FROM put_wave_order_master_archive
        WHERE ARCHIVE_REASON = 'ARCHIVED'
    ) combined
    JOIN temp_pallet_summary tps ON tps.STORAGE_REQUEST_ID = combined.STORAGE_REQUEST_ID;
    
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_sub_part;
    CREATE TEMPORARY TABLE missing_quantity_sub_part AS
    SELECT 
        PUT_ORDER_ID, 
        SUM(SHORT_PUT_QUANTITY) AS total_short_quantity
    FROM short_put_wave_reason
    WHERE REASON <> 'NO_SPACE_IN_BIN'
    GROUP BY PUT_ORDER_ID;
    
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_summary;
    CREATE TEMPORARY TABLE missing_quantity_summary AS
    SELECT 
        p.STORAGE_REQUEST_ID,
        SUM(s.total_short_quantity) AS total_missing_quantity
    FROM combined_put_orders_for_SP p
    JOIN missing_quantity_sub_part s ON p.PUT_ORDER_ID = s.PUT_ORDER_ID
    GROUP BY p.STORAGE_REQUEST_ID;
    
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary_2;
    CREATE TEMPORARY TABLE temp_pallet_summary_2 AS
    SELECT 
        s.PALLET_ID,
        s.STORAGE_REQUEST_ID,
        s.PALLET_SCANNED_TIMESTAMP,
        s.PALLET_COMPLETION_TIMESTAMP,
        s.STORAGE_REQUEST_STATUS
    FROM (
        SELECT 
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrpd.PALLET_SCANNED_TIMESTAMP,
            wtwsrpd.PALLET_COMPLETION_TIMESTAMP,
            wtwsrpd.STORAGE_REQUEST_STATUS,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID DESC
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
    ) s
    WHERE s.rn = 1
    ORDER BY s.PALLET_SCANNED_TIMESTAMP DESC;
    
    
    SET v_base_query = CONCAT(
        "SELECT 
            CASE 
                WHEN (COALESCE(SUM(cpo.PUT_QUANTITY), 0) + COALESCE(mqs.total_missing_quantity, 0)) = tps.total_quantity 
                     AND tps2.PALLET_COMPLETION_TIMESTAMP IS NOT NULL THEN 'COMPLETE'
                WHEN tps2.PALLET_COMPLETION_TIMESTAMP IS NULL THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS 'STATUS',
            tps.storage_request_id AS 'STORAGE REQUEST ID',
            tps.distinct_storage_count AS 'TOTAL STORAGE(s)',
            tps.distinct_article_count AS 'DISTINCT SKU(s)',
            tps.total_quantity AS 'EXPECTED EACHES',
            COALESCE(MAX(cpos.PUT_QUANTITY), 0) AS 'PUT EACHES SYNCED',
            COALESCE(MAX(cpo.PUT_QUANTITY), 0) AS 'PUT EACHES',
            COALESCE(MAX(cpas.TOTAL_STOCK_ADJUSTMENT), 0) AS 'PUT EACHES ADJUSTMENT SYNCED',
            COALESCE(mqs.total_missing_quantity, 0) AS 'TOTAL STOCK ADJUSTMENT',
            (COALESCE(SUM(cpo.PUT_QUANTITY), 0) + COALESCE(mqs.total_missing_quantity, 0)) AS 'OVERALL PUT EACHES',
            (COALESCE(tps.total_quantity, 0) - COALESCE(SUM(cpo.PUT_QUANTITY), 0) - COALESCE(mqs.total_missing_quantity, 0)) AS 'PENDING EACHES',
            DATE_FORMAT(tps2.PALLET_SCANNED_TIMESTAMP, '", v_datetime_format, "') AS 'STARTED TIME',
            DATE_FORMAT(tps2.PALLET_COMPLETION_TIMESTAMP, '", v_datetime_format, "') AS 'COMPLETED TIME'
        FROM temp_pallet_summary tps
        LEFT JOIN combined_put_orders cpo ON tps.STORAGE_REQUEST_ID = cpo.STORAGE_REQUEST_ID
        LEFT JOIN combined_put_orders_sync cpos ON cpos.STORAGE_REQUEST_ID = cpo.STORAGE_REQUEST_ID
        LEFT JOIN combined_put_adjustment_sync cpas ON cpas.STORAGE_REQUEST_ID = cpo.STORAGE_REQUEST_ID
        LEFT JOIN missing_quantity_summary mqs ON tps.STORAGE_REQUEST_ID = mqs.STORAGE_REQUEST_ID
        LEFT JOIN temp_pallet_summary_2 tps2 ON tps.STORAGE_REQUEST_ID = tps2.STORAGE_REQUEST_ID
        WHERE cpo.PUT_START_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "' 
        ", p_filter_condition, "
        GROUP BY tps.PALLET_ID, tps.STORAGE_REQUEST_ID"
    );
    
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery ", 
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_STORAGE_LEVEL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_STORAGE_LEVEL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_STORAGE_LEVEL_SUMMARY`(IN Parameters JSON)
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
    DECLARE p_start_date_time VARCHAR(50);
    DECLARE p_end_date_time VARCHAR(50);
    DECLARE p_pallet_id VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
    SET p_page_number               = Parameters ->> '$.page_number';
    SET p_rows_per_page            = Parameters ->> '$.rows_per_page';
    SET p_user_id                  = Parameters ->> '$.user_id';
    SET p_user_name                = Parameters ->> '$.user_name';
    SET p_page_zero_metadata_flag = Parameters ->> '$.page_zero_metadata_flag';
    SET p_count_flag               = Parameters ->> '$.count';
    SET p_filter_condition         = Parameters ->> '$.filter_data';
    SET p_select_clause            = COALESCE(NULLIF(Parameters ->> '$.select_clause', ''), '*');
    SET p_sorting_column_name      = Parameters ->> '$.sorting_column_name';
    SET p_sorting_column_orderby   = Parameters ->> '$.sorting_column_orderby';
    SET p_table_unique_identifier  = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters  = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time          = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time            = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    SET p_pallet_id                = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.pallet_id'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = ' ';
    ELSE
        SET p_filter_condition = CONCAT(' AND ', p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('DATETIME');
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary;
    CREATE TEMPORARY TABLE temp_pallet_summary AS
    SELECT 
        s.PALLET_ID, 
        s.STORAGE_REQUEST_ID,
        s.STORAGE_ID,
        s.ARTICLE_ID,
        SUM(s.QUANTITY) AS total_quantity
    FROM (
        SELECT 
            wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID,
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrd.STORAGE_ID,
            wtwsrd.ARTICLE_ID,
            wtwsrd.QUANTITY,
            wtwsrpd.PALLET_SCANNED_TIMESTAMP,
            wtwsrpd.PALLET_COMPLETION_TIMESTAMP,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID, wtwsrd.STORAGE_ID
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
        JOIN wms_to_wcs_storage_request_data wtwsrd 
            ON wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID = wtwsrd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
        WHERE PALLET_ID = p_pallet_id 
            AND PALLET_SCANNED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ) s 
    WHERE s.rn = 1
    GROUP BY s.PALLET_ID, s.STORAGE_REQUEST_ID, s.STORAGE_ID, s.ARTICLE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders;
    CREATE TEMPORARY TABLE combined_put_orders AS
    SELECT 
        combined.STORAGE_ID, 
        combined.PUT_QUANTITY,
        combined.MIN_PUT_START_TIMESTAMP, 
        combined.MAX_PUT_TIMESTAMP 
    FROM (
        SELECT 
            STORAGE_ID,
            SUM(PUT_QUANTITY) AS PUT_QUANTITY,
            MIN(PUT_START_TIMESTAMP) AS MIN_PUT_START_TIMESTAMP,
            MAX(PUT_TIMESTAMP) AS MAX_PUT_TIMESTAMP,
            PUT_ORDER_ID
        FROM put_wave_order_master
        GROUP BY STORAGE_ID, PUT_ORDER_ID
        UNION ALL
        SELECT 
            STORAGE_ID,
            SUM(PUT_QUANTITY) AS PUT_QUANTITY,
            MIN(PUT_START_TIMESTAMP) AS MIN_PUT_START_TIMESTAMP,
            MAX(PUT_TIMESTAMP) AS MAX_PUT_TIMESTAMP,
            PUT_ORDER_ID
        FROM put_wave_order_master_archive
        GROUP BY STORAGE_ID, PUT_ORDER_ID
    ) combined
    JOIN temp_pallet_summary tps 
        ON tps.STORAGE_ID = combined.STORAGE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders_for_SP;
    CREATE TEMPORARY TABLE combined_put_orders_for_SP AS
    SELECT 
        STORAGE_REQUEST_ID,
        STORAGE_ID,
        PUT_QUANTITY,
        PUT_START_TIMESTAMP,
        PUT_ORDER_ID
    FROM put_wave_order_master_archive
    WHERE ARCHIVE_REASON = 'ARCHIVED';
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_sub_part;
    CREATE TEMPORARY TABLE missing_quantity_sub_part AS
    SELECT 
        PUT_ORDER_ID, 
        SUM(SHORT_PUT_QUANTITY) AS total_short_quantity
    FROM short_put_wave_reason 
    WHERE REASON <> 'NO_SPACE_IN_BIN'
    GROUP BY PUT_ORDER_ID;
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_summary;
    CREATE TEMPORARY TABLE missing_quantity_summary AS
    SELECT 
        p.STORAGE_ID,
        SUM(s.total_short_quantity) AS total_missing_quantity
    FROM combined_put_orders_for_SP p
    JOIN missing_quantity_sub_part s 
        ON p.PUT_ORDER_ID = s.PUT_ORDER_ID
    GROUP BY p.STORAGE_ID;
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary_2;
    CREATE TEMPORARY TABLE temp_pallet_summary_2 AS
    SELECT 
        s.PALLET_ID, 
        s.STORAGE_REQUEST_ID,
        s.PALLET_SCANNED_TIMESTAMP
    FROM (
        SELECT 
            wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID,
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrpd.PALLET_SCANNED_TIMESTAMP,
            wtwsrpd.PALLET_COMPLETION_TIMESTAMP,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID DESC
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
    ) s 
    WHERE s.rn = 1
    GROUP BY s.PALLET_ID, s.STORAGE_REQUEST_ID, s.PALLET_SCANNED_TIMESTAMP;
    
    SET v_base_query = CONCAT(
        "SELECT 
            CASE 
                WHEN (COALESCE(SUM(cpo.PUT_QUANTITY), 0) + COALESCE(mqs.total_missing_quantity, 0)) = tps.total_quantity 
                     AND cpo.MAX_PUT_TIMESTAMP IS NOT NULL THEN 'COMPLETE'
                WHEN cpo.MAX_PUT_TIMESTAMP IS NULL THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS 'STATUS',
            tps.STORAGE_REQUEST_ID AS 'STORAGE REQUEST ID',
            tps.STORAGE_ID AS 'STORAGE ID',
            tps.ARTICLE_ID AS 'ARTICLE ID',
            tps.total_quantity AS 'EXPECTED EACHES',
            COALESCE(SUM(cpo.PUT_QUANTITY), 0) AS 'PUT EACHES',
            COALESCE(mqs.total_missing_quantity, 0) AS 'TOTAL STOCK ADJUSTMENT',
            (
                COALESCE(SUM(cpo.PUT_QUANTITY), 0) + 
                COALESCE(mqs.total_missing_quantity, 0)
            ) AS 'OVERALL PUT EACHES',
            (
                COALESCE(tps.total_quantity, 0) - 
                COALESCE(SUM(cpo.PUT_QUANTITY), 0) - 
                COALESCE(mqs.total_missing_quantity, 0)
            ) AS 'PENDING EACHES',
            DATE_FORMAT(MIN(cpo.MIN_PUT_START_TIMESTAMP), '", v_datetime_format, "') AS 'STARTED TIME',
            DATE_FORMAT(MAX(cpo.MAX_PUT_TIMESTAMP), '", v_datetime_format, "') AS 'COMPLETED TIME',
            DATE_FORMAT(tps2.PALLET_SCANNED_TIMESTAMP, '", v_datetime_format, "') AS 'PALLET SCANNED TIME'
        FROM temp_pallet_summary tps
        LEFT JOIN combined_put_orders cpo 
            ON tps.STORAGE_ID = cpo.STORAGE_ID
        LEFT JOIN missing_quantity_summary mqs 
            ON tps.STORAGE_ID = mqs.STORAGE_ID
        LEFT JOIN temp_pallet_summary_2 tps2 
            ON tps.STORAGE_REQUEST_ID = tps2.STORAGE_REQUEST_ID
        WHERE cpo.MIN_PUT_START_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "' ",
        p_filter_condition, 
        " GROUP BY 
            tps.PALLET_ID, 
            tps.STORAGE_REQUEST_ID, 
            tps.STORAGE_ID,
            tps.ARTICLE_ID,
            tps.total_quantity,
            mqs.total_missing_quantity,
            tps2.PALLET_SCANNED_TIMESTAMP"
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery ", 
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_SUMMARY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_SUMMARY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_OVERALL_SUMMARY`(IN Parameters JSON)
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
    DECLARE p_start_date_time VARCHAR(50);
    DECLARE p_end_date_time VARCHAR(50);
    
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
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `STARTED TIME` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = ' ';
    ELSE
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary;
    CREATE TEMPORARY TABLE temp_pallet_summary AS
    SELECT 
        s.PALLET_ID, 
        s.STORAGE_REQUEST_ID,
        COUNT(DISTINCT s.STORAGE_ID) AS distinct_storage_count,
        COUNT(DISTINCT s.ARTICLE_ID) AS distinct_article_count,
        sum(s.QUANTITY) AS total_quantity,
        s.PALLET_SCANNED_TIMESTAMP,
        s.PALLET_COMPLETION_TIMESTAMP
    FROM (
        SELECT 
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrd.STORAGE_ID,
            wtwsrd.ARTICLE_ID,
            wtwsrd.QUANTITY,
            wtwsrpd.PALLET_SCANNED_TIMESTAMP,
            wtwsrpd.PALLET_COMPLETION_TIMESTAMP,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID, wtwsrd.STORAGE_ID 
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
        JOIN wms_to_wcs_storage_request_data wtwsrd 
            ON wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID = wtwsrd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
        WHERE PALLET_SCANNED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ) s
    WHERE s.rn = 1
    GROUP BY s.PALLET_ID, s.STORAGE_REQUEST_ID
    ORDER BY s.PALLET_SCANNED_TIMESTAMP DESC;
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders;
    CREATE TEMPORARY TABLE combined_put_orders AS
    SELECT 
        combined.STORAGE_REQUEST_ID, 
        combined.PUT_QUANTITY, 
        combined.PUT_START_TIMESTAMP, 
        combined.PUT_ORDER_ID
    FROM (
        SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID FROM put_wave_order_master
        UNION ALL
        SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID FROM put_wave_order_master_archive
    ) combined
    JOIN temp_pallet_summary tps ON tps.STORAGE_REQUEST_ID = combined.STORAGE_REQUEST_ID;
    
    DROP TEMPORARY TABLE IF EXISTS combined_put_orders_for_SP;
    CREATE TEMPORARY TABLE combined_put_orders_for_SP AS
    SELECT 
        combined.STORAGE_REQUEST_ID, 
        combined.PUT_QUANTITY, 
        combined.PUT_START_TIMESTAMP, 
        combined.PUT_ORDER_ID
    FROM (
        SELECT 
            STORAGE_REQUEST_ID, 
            PUT_QUANTITY, 
            PUT_START_TIMESTAMP, 
            PUT_ORDER_ID,
            WAVE_ID,
            DENSE_RANK() OVER (
                PARTITION BY STORAGE_REQUEST_ID 
                ORDER BY WAVE_ID DESC
            ) AS rn
        FROM (
            SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID, WAVE_ID 
            FROM put_wave_order_master
            UNION ALL
            SELECT STORAGE_REQUEST_ID, PUT_QUANTITY, PUT_START_TIMESTAMP, PUT_ORDER_ID, WAVE_ID
            FROM put_wave_order_master_archive
            WHERE STATUS = 'INVENTORY_UPDATED'
        ) all_orders
    ) combined
    JOIN temp_pallet_summary tps ON tps.STORAGE_REQUEST_ID = combined.STORAGE_REQUEST_ID
    WHERE combined.rn = 1;
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_sub_part;
    CREATE TEMPORARY TABLE missing_quantity_sub_part AS
    SELECT 
        PUT_ORDER_ID, 
        SUM(SHORT_PUT_QUANTITY) AS total_short_quantity
    FROM short_put_wave_reason 
    WHERE REASON <> 'NO_SPACE_IN_BIN'
    and re_attempt_flag = 0
    GROUP BY PUT_ORDER_ID;
    
    DROP TEMPORARY TABLE IF EXISTS missing_quantity_summary;
    CREATE TEMPORARY TABLE missing_quantity_summary AS
    SELECT 
        p.STORAGE_REQUEST_ID,
        SUM(s.total_short_quantity) AS total_missing_quantity
    FROM combined_put_orders_for_SP p
    JOIN missing_quantity_sub_part s ON p.PUT_ORDER_ID = s.PUT_ORDER_ID
    GROUP BY p.STORAGE_REQUEST_ID;
    
    DROP TEMPORARY TABLE IF EXISTS temp_pallet_summary_2;
    CREATE TEMPORARY TABLE temp_pallet_summary_2 AS
    SELECT 
        s.PALLET_ID, 
        s.STORAGE_REQUEST_ID,
        s.PALLET_SCANNED_TIMESTAMP,
        s.PALLET_COMPLETION_TIMESTAMP,
        s.STORAGE_REQUEST_STATUS
    FROM (
        SELECT 
            wtwsrpd.PALLET_ID,
            wtwsrpd.STORAGE_REQUEST_ID,
            wtwsrpd.PALLET_SCANNED_TIMESTAMP,
            wtwsrpd.PALLET_COMPLETION_TIMESTAMP,
            wtwsrpd.STORAGE_REQUEST_STATUS,
            ROW_NUMBER() OVER (
                PARTITION BY wtwsrpd.PALLET_ID, wtwsrpd.STORAGE_REQUEST_ID 
                ORDER BY wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID DESC
            ) AS rn
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
    ) s
    WHERE s.rn = 1
    ORDER BY s.PALLET_SCANNED_TIMESTAMP DESC;
    
    SET v_base_query = CONCAT(
        "SELECT 
           CASE 
                WHEN (
                    SUM(subquery.PUT_EACHES) + SUM(subquery.TOTAL_STOCK_ADJUSTMENT)
                ) = SUM(subquery.EXPECTED_EACHES)
                AND subquery.COMPELETED_TIME IS NOT NULL THEN 'COMPLETE'
                WHEN subquery.COMPELETED_TIME IS NULL THEN 'IN PROGRESS'
                ELSE 'PENDING'
            END AS 'STATUS',
            subquery.PALLET_ID AS 'PALLET ID',
            COUNT(DISTINCT subquery.STORAGE_REQUEST) AS 'TOTAL STORAGE REQUEST(s)',
            SUM(subquery.TOTAL_STORAGE_COUNT) AS 'TOTAL STORAGE(s)',
            SUM(subquery.DISTINCT_SKU_COUNT) AS 'DISTINCT SKU(s)',
            SUM(subquery.EXPECTED_EACHES) AS 'EXPECTED EACHES',
            SUM(subquery.PUT_EACHES) AS 'PUT EACHES',
            SUM(subquery.TOTAL_STOCK_ADJUSTMENT) AS 'TOTAL STOCK ADJUSTMENT',
            SUM(subquery.OVERALL_PUT_EACHES) AS 'OVERALL PUT EACHES',
            SUM(subquery.PENDING_EACHES) AS 'PENDING EACHES',
            DATE_FORMAT(MIN(subquery.STARTED_TIME), '", v_datetime_format, "') AS 'STARTED TIME',
            DATE_FORMAT(MAX(subquery.COMPELETED_TIME), '", v_datetime_format, "') AS 'COMPLETED TIME'
        FROM (
            SELECT 
                tps2.STORAGE_REQUEST_STATUS,
                tps.pallet_id AS PALLET_ID,
                tps.storage_request_id AS STORAGE_REQUEST,
                tps.distinct_storage_count AS TOTAL_STORAGE_COUNT,
                tps.distinct_article_count AS DISTINCT_SKU_COUNT,
                tps.total_quantity AS EXPECTED_EACHES,
                COALESCE(SUM(cpo.PUT_QUANTITY), 0) AS PUT_EACHES,
                COALESCE(mqs.total_missing_quantity, 0) AS TOTAL_STOCK_ADJUSTMENT,
                (
                    COALESCE(SUM(cpo.PUT_QUANTITY), 0) + 
                    COALESCE(mqs.total_missing_quantity, 0)
                ) AS OVERALL_PUT_EACHES,
                (
                    COALESCE(tps.total_quantity, 0) -
                    COALESCE(SUM(cpo.PUT_QUANTITY), 0) -
                    COALESCE(mqs.total_missing_quantity, 0)
                ) AS PENDING_EACHES,
                tps2.PALLET_SCANNED_TIMESTAMP AS STARTED_TIME,
                tps2.PALLET_COMPLETION_TIMESTAMP AS COMPELETED_TIME
            FROM temp_pallet_summary tps
            LEFT JOIN combined_put_orders cpo ON tps.STORAGE_REQUEST_ID = cpo.STORAGE_REQUEST_ID
            LEFT JOIN missing_quantity_summary mqs ON tps.STORAGE_REQUEST_ID = mqs.STORAGE_REQUEST_ID
            LEFT JOIN temp_pallet_summary_2 tps2 ON tps.STORAGE_REQUEST_ID = tps2.STORAGE_REQUEST_ID
            WHERE cpo.PUT_START_TIMESTAMP BETWEEN '", p_start_date_time, "' AND '", p_end_date_time, "'
            GROUP BY tps.PALLET_ID, tps.STORAGE_REQUEST_ID
        ) AS subquery ",
        p_filter_condition, 
        " GROUP BY subquery.PALLET_ID"
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery ", 
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_PENDING_ORDERS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_PENDING_ORDERS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_PENDING_ORDERS`(IN Parameters JSON)
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
    DECLARE p_wave_id VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
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
    SET p_wave_id                   = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
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
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    SET v_base_query = CONCAT(
        "SELECT 
            wm.WAVE_ID AS 'WAVE ID',
            pwom.SKU_ID AS 'SKU ID',
            sbm.MRP AS 'MRP',
            DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY',
            pwom.EXPECTED_QUANTITY AS 'EXPECTED QUANTITY',
            pwom.PUT_QUANTITY AS 'PUT QUANTITY',
            pwom.SHORT_PUT_QUANTITY AS 'SHORT PUT QUANTITY',
            DATE_FORMAT(pwom.PUT_TIMESTAMP, '", v_datetime_format, "') AS 'PUT TIME',
            pwom.PUT_BY AS 'PUT BY',
            pwom.STATION_ID AS 'STATION ID',
            DATE_FORMAT(wm.INSERTED_TIMESTAMP, '", v_datetime_format, "') AS 'INSERTED TIME',
            DATE_FORMAT(wm.START_TIMESTAMP, '", v_datetime_format, "') AS 'START TIME',
            DATE_FORMAT(wm.COMPLETED_TIMESTAMP, '", v_datetime_format, "') AS 'COMPLETED TIME',
            DATE_FORMAT(wm.CANCELLED_TIMESTAMP, '", v_datetime_format, "') AS 'CANCELLED TIME'
         FROM put_wave_order_master pwom
         INNER JOIN wave_master wm ON pwom.WAVE_ID = wm.WAVE_ID
         INNER JOIN sku_batch_master sbm ON sbm.BATCH_ID = pwom.BATCH_ID
         INNER JOIN order_bin_mapping obm ON obm.ORDER_BIN_ID = pwom.ORDER_BIN_ID
         WHERE wm.WAVE_ID = '", p_wave_id, "' AND obm.STATUS = 'PENDING' ", p_filter_condition
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_PUT_WAVE_LEFT_OVER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_PUT_WAVE_LEFT_OVER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_PUT_WAVE_LEFT_OVER`(IN Parameters JSON)
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
    DECLARE p_wave_id VARCHAR(50);
    DECLARE p_wave_status VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
    DECLARE v_base_query TEXT;
    DECLARE v_total_rows INT DEFAULT 0;
    DECLARE v_paginated_query TEXT;
    
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
        SET p_filter_condition = CONCAT(' AND (', p_filter_condition, ')');
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    SET p_table_unique_identifier         = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters   = Parameters ->> '$.report_extra_parameters';
    SET p_wave_id                   = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
    
    SET v_base_query = CONCAT(
    "SELECT pwwd.WAVE_ID AS 'WAVE ID',
		   pwwd.`STORAGE_REQUEST_ID` as 'STORAGE REQUEST ID',
		   pwwd.`STORAGE_ID` as 'STORAGE ID',
		    pwwd.LEFT_OVER AS 'LEFT OVER',
		    pwwd.SKU_ID AS 'SKU ID',
		    sbm.`MRP` as 'MRP',
		    sbm.`EXPIRY_DATE` as 'EXPIRY DATE'
	     FROM put_wave_wms_data pwwd
	     INNER JOIN wave_master wm ON pwwd.WAVE_ID = wm.WAVE_ID
	     INNER JOIN  `sku_batch_master` sbm  on sbm.`BATCH_ID`=pwwd.`BATCH_ID` 
	     WHERE pwwd.WAVE_ID = '", p_wave_id, "'
	     AND pwwd.LEFT_OVER > 0 ",
	     p_filter_condition, "
	     
	     UNION ALL
	     
	     SELECT pwwd.WAVE_ID AS 'WAVE ID',
		     pwwd.`STORAGE_REQUEST_ID` as 'STORAGE REQUEST ID',
		   pwwd.`STORAGE_ID` as  'STORAGE ID',
		    pwwd.LEFT_OVER AS 'LEFT OVER',
		    pwwd.SKU_ID AS 'SKU ID',
		    sbm.`MRP` as 'MRP',
		    sbm.`EXPIRY_DATE` as 'EXPIRY DATE'
	     FROM put_wave_wms_data_archive pwwd
	     INNER JOIN wave_master_archive wm ON pwwd.WAVE_ID = wm.WAVE_ID
	     INNER JOIN  `sku_batch_master` sbm  on sbm.`BATCH_ID`=pwwd.`BATCH_ID` 
	     WHERE pwwd.WAVE_ID = '", p_wave_id, "'
	     AND pwwd.LEFT_OVER > 0 ",
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

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WAVE_STOCK_AUDIT_ORDERS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WAVE_STOCK_AUDIT_ORDERS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WAVE_STOCK_AUDIT_ORDERS`(IN Parameters JSON)
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
    DECLARE p_wave_id VARCHAR(50);
    DECLARE p_wave_status VARCHAR(50);
    
    DECLARE v_sorting VARCHAR(200) DEFAULT '';
    DECLARE v_datetime_format VARCHAR(50);
    DECLARE v_date_format VARCHAR(50);
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
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = '';
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
    
    SET p_table_unique_identifier = Parameters ->> '$.table_unique_identifier';
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_wave_id                 = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    
    IF p_wave_id IS NOT NULL AND p_wave_id != '' THEN
        SELECT WAVE_STATUS INTO p_wave_status
        FROM (
            SELECT WAVE_STATUS FROM wave_master WHERE WAVE_ID = p_wave_id
            UNION ALL
            SELECT WAVE_STATUS FROM wave_master_archive WHERE WAVE_ID = p_wave_id
        ) AS combined 
        LIMIT 1;
        IF p_wave_status IS NULL THEN
            IF p_table_unique_identifier = 'report_wave_stock_audit_orders' THEN
                SET p_table_unique_identifier = 'report_wave_stock_audit_orders_temp';
            END IF;
        ELSEIF p_wave_status NOT IN ('COMPLETED', 'PROCESSING') THEN
            IF p_table_unique_identifier = 'report_wave_stock_audit_orders' THEN
                SET p_table_unique_identifier = 'report_wave_stock_audit_orders_wms';    
            END IF;    
        END IF;
    END IF;
    
    IF p_table_unique_identifier = 'report_wave_stock_audit_orders_wms' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                sawwd.BIN_ID AS 'BIN ID',
                sawwd.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
                sawwd.SKU_ID AS 'SKU ID',
                sbm.MRP AS 'MRP',
                DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY'
             FROM 
                stock_audit_wave_wms_data sawwd
             INNER JOIN sku_batch_master sbm ON sbm.BATCH_ID = sawwd.BATCH_ID
             INNER JOIN wave_master wm ON sawwd.WAVE_ID = wm.WAVE_ID
             WHERE wm.WAVE_ID = '", p_wave_id, "'", p_filter_condition
        );
    ELSEIF p_table_unique_identifier = 'report_wave_stock_audit_orders_temp' THEN
        SET v_base_query = CONCAT(
            "SELECT 
                bawd.BIN_ID AS 'BIN ID',
                bawd.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
                bawd.SKU_ID AS 'SKU ID',
                sbm.MRP AS 'MRP',
                DATE_FORMAT(sbm.EXPIRY_DATE, '", v_date_format, "') AS 'EXPIRY'
             FROM 
                stock_audit_wave_wms_data_dsb_temp bawd
             INNER JOIN sku_batch_master sbm ON sbm.BATCH_ID = bawd.BATCH_ID
             INNER JOIN dashboard_wave_upload_status dwus ON dwus.WAVE_ID = bawd.WAVE_ID
             WHERE dwus.CLIENT_WAVE_ID = '", p_wave_id, "'", p_filter_condition
        );
    ELSEIF p_table_unique_identifier = 'report_wave_stock_audit_orders' THEN
	DROP TEMPORARY TABLE IF EXISTS temp_sawom;
	CREATE TEMPORARY TABLE temp_sawom AS
	SELECT ORDER_BIN_ID, STOCK_AUDIT_ORDER_ID, STATION_ID, BIN_ID, BIN_SEGMENT_NO, AUDIT_BY
	FROM stock_audit_wave_order_master
	WHERE WAVE_ID = p_wave_id
	UNION ALL
	SELECT ORDER_BIN_ID, STOCK_AUDIT_ORDER_ID, STATION_ID, BIN_ID, BIN_SEGMENT_NO, AUDIT_BY
	FROM stock_audit_wave_order_master_archive
	WHERE WAVE_ID = p_wave_id;
	
	DROP TEMPORARY TABLE IF EXISTS order_bin_mapping_data;
	CREATE TEMPORARY TABLE order_bin_mapping_data AS
	SELECT 
	    t.ORDER_BIN_ID,
	    t.BIN_ID,
	    t.STATION_ID,
	    MAX(CASE WHEN t.STATUS = 'BIN_PICKED' THEN t.BOT_ID END) AS TASK_ALLOCATED_BOT_ID,
	    MAX(CASE WHEN t.STATUS = 'PRE_ON_STATION' THEN t.UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
	    MAX(CASE WHEN t.STATUS = 'ON_STATION' THEN t.UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
	FROM order_bin_mapping_log t
	WHERE t.TYPE = 'RACK_PICK' 
	  AND t.ORDER_BIN_ID IN (
		SELECT order_bin_id 
		FROM stock_audit_wave_order_master 
		WHERE WAVE_ID = p_wave_id
		UNION
		SELECT order_bin_id 
		FROM stock_audit_wave_order_master_archive 
		WHERE WAVE_ID = p_wave_id
	  )
	GROUP BY t.ORDER_BIN_ID, t.BIN_ID, t.STATION_ID
	ORDER BY t.ORDER_BIN_ID, t.BIN_ID, t.STATION_ID;
	
	
	DROP TEMPORARY TABLE IF EXISTS temp_order_bin_mapping;
	CREATE TEMPORARY TABLE temp_order_bin_mapping AS
	SELECT
	    obm.order_bin_id,
	    MIN(obm.logged_timestamp) AS logged_timestamp
	FROM (
	    SELECT order_bin_id, station_id, logged_timestamp
	    FROM order_bin_mapping_log
	    WHERE STATUS = 'ON_STATION'
	) AS obm
	JOIN temp_sawom AS tsw
	    ON tsw.order_bin_id = obm.order_bin_id
	   AND tsw.station_id = obm.station_id
	GROUP BY obm.order_bin_id;
	
	DROP TEMPORARY TABLE IF EXISTS temp_stock_audit_data;
	CREATE TEMPORARY TABLE temp_stock_audit_data AS
	SELECT 
	    ss.stock_audit_order_id,
	    ss.sku_id,
	    ss.updated_sku_id,
	    ss.mrp,
	    ss.updated_mrp,
	    ss.expiry_date,
	    ss.updated_expiry_date,
	    ss.expected_quantity,
	    ss.updated_quantity,
	    sp.audit_start_timestamp, 
	    sp.audit_close_timestamp
	FROM stock_audit_bin_data_push AS sp
	JOIN stock_audit_bin_segments AS ss
	    ON sp.id = ss.stock_audit_id
	WHERE sp.wave_id = p_wave_id;
        SET v_base_query = CONCAT(
            "SELECT 
		  tsw.STATION_ID AS 'STATION ID',
		  tsw.BIN_ID AS 'BIN ID',
		  tsw.BIN_SEGMENT_NO AS 'BIN SEGMENT NO',
		  tsad.sku_id AS 'SKU ID',
		  tsad.updated_sku_id AS 'UPDATED SKU ID',
		  tsad.mrp AS 'MRP',
		  tsad.updated_mrp AS 'UPDATED MRP',
		  DATE_FORMAT(tsad.expiry_date, '", v_date_format, "') AS 'EXPIRY',
		  DATE_FORMAT(tsad.updated_expiry_date, '", v_date_format, "') AS 'UPDATED EXPIRY',
		  tsad.expected_quantity AS 'EXPECTED QUANTITY',
		  tsad.updated_quantity AS 'UPDATED QUANTITY',
		  tsw.AUDIT_BY AS 'AUDIT BY',
		  DATE_FORMAT(tobm.logged_timestamp, '", v_datetime_format, "') AS 'ON STATION TIME',  
		  DATE_FORMAT(tsad.audit_start_timestamp, '", v_datetime_format, "') AS 'AUDIT STARTED TIME', 
		  DATE_FORMAT(tsad.audit_close_timestamp, '", v_datetime_format, "') AS 'AUDIT COMPLETED TIME',
		  obmd.TASK_ALLOCATED_BOT_ID AS 'BIN PUT BOT ID',
		  DATE_FORMAT(obmd.PRE_ON_STATION_TIMESTAMP, '", v_datetime_format, "') AS 'BIN PUT TIME'
		FROM temp_sawom AS tsw
		LEFT JOIN temp_order_bin_mapping AS tobm
		  ON tobm.order_bin_id = tsw.order_bin_id
		LEFT JOIN order_bin_mapping_data AS obmd
		    ON obmd.ORDER_BIN_ID = tsw.ORDER_BIN_ID 
		    AND obmd.BIN_ID = tsw.BIN_ID 
		    AND obmd.STATION_ID = tsw.STATION_ID
		LEFT JOIN temp_stock_audit_data AS tsad
		  ON tsad.stock_audit_order_id = tsw.stock_audit_order_id", p_filter_condition        
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
    
    DROP TEMPORARY TABLE IF EXISTS temp_sawom;
	DROP TEMPORARY TABLE IF EXISTS order_bin_mapping_data;
	DROP TEMPORARY TABLE IF EXISTS temp_order_bin_mapping;
	DROP TEMPORARY TABLE IF EXISTS temp_stock_audit_data;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_DATA_WMS_WCS_INVENTORY_SYNC` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_DATA_WMS_WCS_INVENTORY_SYNC` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_DATA_WMS_WCS_INVENTORY_SYNC`(IN Parameters JSON)
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
    SET p_report_extra_parameters = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.report_extra_parameters'));
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `SKU ID` DESC';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = '';
    ELSE
        SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    SET v_date_format     = DSB_GET_DATE_FORMAT('date');
    
    SET v_base_query = CONCAT(
        "SELECT 
            lim.ARTICLE_ID AS 'SKU ID', 
            sbm.GLN AS 'GLN',
            sbm.CLIENT_BATCH_ID AS 'CLIENT BATCH ID', 
            sbm.BATCH_NUMBER AS 'BATCH NUMBER', 
            SUM(lim.QUANTITY) AS 'TOTAL QUANTITY'
         FROM live_inventory_master lim
         JOIN sku_batch_master sbm ON lim.BATCH_ID = sbm.BATCH_ID
         WHERE lim.QUANTITY > 0
         GROUP BY lim.ARTICLE_ID, sbm.CLIENT_BATCH_ID, sbm.BATCH_NUMBER",
        p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause, 
        " FROM (", v_base_query, ") AS subquery",
        v_sorting,
        " LIMIT ", p_page_number * p_rows_per_page, ", ", p_rows_per_page
    );
    
    SET @countQuery = CONCAT(
        "SELECT COUNT(*) INTO @rowCount FROM (", v_base_query, ") AS t"
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

/* Procedure structure for procedure `DSB_PAGINATED_IPP_BY_BATCH_STATION` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_IPP_BY_BATCH_STATION` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_IPP_BY_BATCH_STATION`(IN Parameters JSON)
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
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_start_date_time         VARCHAR(50);
    DECLARE p_end_date_time           VARCHAR(50);
    DECLARE p_cap_seconds             INT;
    
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
    SET p_report_extra_parameters = Parameters ->> '$.report_extra_parameters';
    SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
    SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
    SET p_cap_seconds             = COALESCE(JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.cap_seconds')), 600);
    
    SET p_download_flag = CASE 
        WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
        ELSE FALSE
    END;
    
    IF p_cap_seconds IS NULL OR p_cap_seconds <= 0 THEN
        SET p_cap_seconds = 600; 
    END IF;
    
    IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '') 
       OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
        SET v_sorting = ' ORDER BY `BATCHPICKLIST CODE`, `STATION ID`';
    ELSE
        SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
    END IF;
    
    IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
        SET p_filter_condition = " ";
    ELSE
        SET p_filter_condition = CONCAT(" WHERE ", p_filter_condition);
    END IF;
    
    SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
    
    DROP TEMPORARY TABLE IF EXISTS t_start_time;
    DROP TEMPORARY TABLE IF EXISTS t_complete_time;
    DROP TEMPORARY TABLE IF EXISTS t_all_order_lines;
    DROP TEMPORARY TABLE IF EXISTS t_master;
    DROP TEMPORARY TABLE IF EXISTS t_on_station;
    DROP TEMPORARY TABLE IF EXISTS total_pick;
    DROP TEMPORARY TABLE IF EXISTS t_wave_pick_results;
    DROP TEMPORARY TABLE IF EXISTS t_station_bin_segment_rollup;
    DROP TEMPORARY TABLE IF EXISTS t_qpl_with_median;
    DROP TEMPORARY TABLE IF EXISTS t_final_results;
    
    CREATE TEMPORARY TABLE t_start_time AS
    SELECT
        s.ORDER_LINE_ID,
        SUM(s.LEFT_OVER)                AS LEFT_OVER,
        MIN(s.INSERTED_TIMESTAMP)       AS INSERTED_TIMESTAMP
    FROM (
        SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP
        FROM pick_wave_wms_data
        WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT ORDER_LINE_ID, LEFT_OVER, INSERTED_TIMESTAMP
        FROM pick_wave_wms_data_archive
        WHERE INSERTED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ) s
    GROUP BY s.ORDER_LINE_ID;
    CREATE INDEX idx_start_time_order_line ON t_start_time(ORDER_LINE_ID);
    CREATE TEMPORARY TABLE t_complete_time AS
    SELECT ORDER_LINE_ID, MAX(UPDATED_TIMESTAMP) AS COMPLETE_TIME
    FROM (
        SELECT ORDER_LINE_ID, UPDATED_TIMESTAMP
        FROM wms_to_wcs_order_line_level_pre_staged_data
        WHERE UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT ORDER_LINE_ID, UPDATED_TIMESTAMP
        FROM wms_to_wcs_order_line_level_pre_staged_data_archive
        WHERE UPDATED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ) u
    GROUP BY ORDER_LINE_ID;
    CREATE INDEX idx_complete_time_order_line ON t_complete_time(ORDER_LINE_ID);
    CREATE TEMPORARY TABLE t_all_order_lines AS
    SELECT
        ol.ORDER_LINE_ID,
        MIN(ol.WMS_ORDER_REQUEST_DATA_ID)            AS WMS_ORDER_REQUEST_DATA_ID,
        ANY_VALUE(ol.BATCH_PICKLIST_CODE)            AS BATCH_PICKLIST_CODE,
        ANY_VALUE(ol.ORDER_ID)                       AS ORDER_ID,
        MAX(ol.ARTICLE_ID)                           AS ARTICLE_ID,
        MAX(ol.QUANTITY)                             AS QUANTITY,
        MIN(ol.ORDER_CREATION_TIME)                  AS MIN_ORDER_CREATION_TIME
    FROM (
        SELECT rld.ORDER_LINE_ID,
               rd.WMS_ORDER_REQUEST_DATA_ID,
               rd.BATCH_PICKLIST_CODE,
               rd.ORDER_ID,
               rld.ARTICLE_ID,
               rld.QUANTITY,
               rd.ORDER_CREATION_TIME
        FROM wms_to_wcs_order_level_pre_staged_data rd
        JOIN wms_to_wcs_order_line_level_pre_staged_data rld
          ON rld.WMS_ORDER_REQUEST_DATA_ID = rd.WMS_ORDER_REQUEST_DATA_ID
        UNION ALL
        SELECT rld.ORDER_LINE_ID,
               rd.WMS_ORDER_REQUEST_DATA_ID,
               rd.BATCH_PICKLIST_CODE,
               rd.ORDER_ID,
               rld.ARTICLE_ID,
               rld.QUANTITY,
               rd.ORDER_CREATION_TIME
        FROM wms_to_wcs_order_level_pre_staged_data_archive rd
        JOIN wms_to_wcs_order_line_level_pre_staged_data_archive rld
          ON rld.WMS_ORDER_REQUEST_DATA_ID = rd.WMS_ORDER_REQUEST_DATA_ID
    ) ol
    GROUP BY ol.ORDER_LINE_ID;
    CREATE INDEX idx_all_lines_order_line ON t_all_order_lines(ORDER_LINE_ID);
    CREATE TEMPORARY TABLE t_master AS
    SELECT
        a.WMS_ORDER_REQUEST_DATA_ID,
        a.BATCH_PICKLIST_CODE,
        a.ORDER_ID,
        a.ORDER_LINE_ID,
        a.ARTICLE_ID,
        a.QUANTITY,
        a.MIN_ORDER_CREATION_TIME,
        st.LEFT_OVER,
        st.INSERTED_TIMESTAMP AS START_TIME,
        ct.COMPLETE_TIME
    FROM t_all_order_lines a
    JOIN t_start_time st
        ON st.ORDER_LINE_ID = a.ORDER_LINE_ID
    LEFT JOIN t_complete_time ct
        ON ct.ORDER_LINE_ID = a.ORDER_LINE_ID;
    CREATE INDEX idx_master_order_line ON t_master(ORDER_LINE_ID);
    CREATE INDEX idx_master_batch_order ON t_master(BATCH_PICKLIST_CODE, ORDER_ID);
    CREATE TEMPORARY TABLE t_on_station AS
    SELECT ORDER_BIN_ID, MAX(LOGGED_TIMESTAMP) AS ON_STATION_TIME
    FROM order_bin_mapping_log
    WHERE STATUS = 'ON_STATION'
        AND LOGGED_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    GROUP BY ORDER_BIN_ID;
    CREATE INDEX idx_onstation_obid ON t_on_station(ORDER_BIN_ID);
    CREATE TEMPORARY TABLE total_pick AS
    SELECT
        p.ORDER_LINE_ID,
        p.WAVE_ID,
        p.BIN_ID,
        p.BIN_SEGMENT_NO,
        p.STATION_ID,
        p.ORDER_BIN_ID,
        SUM(p.PICKED_QUANTITY)              AS TOTAL_PICKED,
        MIN(p.PICK_START_TIMESTAMP)         AS PICK_START_TIMESTAMP,
        MAX(p.PICK_TIMESTAMP)               AS PICK_TIMESTAMP,
        MAX(p.PICK_BY)                      AS PICK_BY
    FROM (
        SELECT ORDER_LINE_ID, WAVE_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATION_ID,
               PICKED_QUANTITY, PICK_START_TIMESTAMP, PICK_TIMESTAMP, PICK_BY
        FROM pick_wave_order_master
        WHERE STATUS NOT IN ('PENDING','PICK_STARTED')
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
        UNION ALL
        SELECT ORDER_LINE_ID, WAVE_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATION_ID,
               PICKED_QUANTITY, PICK_START_TIMESTAMP, PICK_TIMESTAMP, PICK_BY
        FROM pick_wave_order_master_archive
        WHERE STATUS NOT IN ('PENDING','PICK_STARTED')
          AND PICK_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    ) p
    GROUP BY p.ORDER_LINE_ID, p.WAVE_ID, p.BIN_ID, p.BIN_SEGMENT_NO, p.STATION_ID, p.ORDER_BIN_ID;
    CREATE INDEX idx_total_pick_order_line ON total_pick(ORDER_LINE_ID);
    CREATE INDEX idx_total_pick_order_bin  ON total_pick(ORDER_BIN_ID);
    CREATE TEMPORARY TABLE t_wave_pick_results AS
    SELECT
        tp.WAVE_ID,
        tp.STATION_ID,
        m.BATCH_PICKLIST_CODE,
        m.ORDER_ID,
        m.ARTICLE_ID,
        m.MIN_ORDER_CREATION_TIME,
        tp.BIN_ID,
        tp.BIN_SEGMENT_NO,
        m.QUANTITY                                    AS EXPECTED_QUANTITY,
        COALESCE(tp.TOTAL_PICKED, 0)                  AS PICK_QUANTITY,
        COALESCE(m.LEFT_OVER, 0)                      AS SHORT_PICK_QUANTITY,
        os.ON_STATION_TIME,
        tp.PICK_START_TIMESTAMP                       AS PICK_STARTED_TIME,
        tp.PICK_TIMESTAMP                             AS PICK_END_TIME,
        GREATEST(
          0,
          TIMESTAMPDIFF(
            SECOND,
            COALESCE(tp.PICK_START_TIMESTAMP, os.ON_STATION_TIME),
            COALESCE(tp.PICK_TIMESTAMP, tp.PICK_START_TIMESTAMP, os.ON_STATION_TIME)
          )
        )                                              AS DIFFERENCE_SECS,
        tp.PICK_BY,
        tp.ORDER_BIN_ID
    FROM t_master m
    LEFT JOIN total_pick tp
        ON tp.ORDER_LINE_ID = m.ORDER_LINE_ID
    LEFT JOIN t_on_station os
        ON os.ORDER_BIN_ID = tp.ORDER_BIN_ID
    WHERE tp.BIN_ID IS NOT NULL
        AND tp.BIN_SEGMENT_NO IS NOT NULL
        AND tp.STATION_ID IS NOT NULL;
    CREATE INDEX idx_wave_results_grp
        ON t_wave_pick_results(BATCH_PICKLIST_CODE, BIN_ID, BIN_SEGMENT_NO, STATION_ID);
    CREATE TEMPORARY TABLE t_station_bin_segment_rollup AS
    SELECT
        BATCH_PICKLIST_CODE,
        STATION_ID,
        BIN_ID,
        BIN_SEGMENT_NO,
        MIN(MIN_ORDER_CREATION_TIME)                  AS MIN_ORDER_CREATION_TIME,
        MAX(DIFFERENCE_SECS)                          AS MAX_DIFFERENCE_SECS,
        LEAST(MAX(DIFFERENCE_SECS), p_cap_seconds)    AS MAX_DIFFERENCE_SECS_CAPPED,
        SUM(PICK_QUANTITY)                            AS TOTAL_QUANTITY,
        COUNT(DISTINCT ORDER_ID)                      AS OPS,
        SUM(PICK_QUANTITY)/COUNT(DISTINCT ORDER_ID)   AS QPL
    FROM t_wave_pick_results
    GROUP BY BATCH_PICKLIST_CODE, STATION_ID, BIN_ID, BIN_SEGMENT_NO;
    CREATE INDEX idx_rollup_station
        ON t_station_bin_segment_rollup(BATCH_PICKLIST_CODE, STATION_ID);
    CREATE TEMPORARY TABLE t_qpl_with_median AS
    WITH qpl_ranked AS (
        SELECT 
          BATCH_PICKLIST_CODE,
          STATION_ID,
          QPL,
          ROW_NUMBER() OVER (PARTITION BY BATCH_PICKLIST_CODE, STATION_ID ORDER BY QPL) AS row_num,
          COUNT(*) OVER (PARTITION BY BATCH_PICKLIST_CODE, STATION_ID) AS total_count
        FROM t_station_bin_segment_rollup
    )
    SELECT 
        BATCH_PICKLIST_CODE,
        STATION_ID,
        ROUND(AVG(QPL), 2) AS MEDIAN_QPL
    FROM qpl_ranked
    WHERE row_num IN (
        FLOOR((total_count + 1) / 2),
        CEIL((total_count + 1) / 2)
    )
    GROUP BY BATCH_PICKLIST_CODE, STATION_ID;
    CREATE INDEX idx_qpl_median ON t_qpl_with_median(BATCH_PICKLIST_CODE, STATION_ID);
    CREATE TEMPORARY TABLE t_final_results AS
    SELECT
        BATCH_PICKLIST_CODE                              AS BATCH,
        STATION_ID                                       AS STATION,
        DATE_FORMAT(MIN(MIN_ORDER_CREATION_TIME), v_datetime_format) AS MIN_ORDER_CREATION_TIME,
        COUNT(DISTINCT BIN_ID)                           AS DISTINCT_BIN_COUNT,
        SUM(MAX_DIFFERENCE_SECS)                         AS SUM_OF_MAX_DIFFERENCE,
        ROUND(AVG(MAX_DIFFERENCE_SECS), 2)               AS AVG_OF_MAX_DIFFERENCE,
        SUM(TOTAL_QUANTITY)                              AS SUM_TOTAL_QUANTITY,
        ROUND(AVG(OPS), 2)                               AS AVG_OPS,
        ROUND( (SUM(TOTAL_QUANTITY) * 3600.0) / NULLIF(SUM(MAX_DIFFERENCE_SECS_CAPPED), 0), 2) AS NET_IPP,
        ROUND( (SUM(TOTAL_QUANTITY) * 3600.0) / NULLIF(SUM(MAX_DIFFERENCE_SECS), 0), 2) AS GROSS_IPP,
        ROUND(AVG(MAX_DIFFERENCE_SECS), 2)               AS OPERATOR_TIME,
        ROUND( (COUNT(DISTINCT BIN_ID) * 3600.0) / NULLIF(SUM(MAX_DIFFERENCE_SECS), 0), 2) AS BINS_PER_HOUR,
        ROUND( 3600.0 / NULLIF(AVG(MAX_DIFFERENCE_SECS), 0), 2) AS BINS_EXPECTED
    FROM t_station_bin_segment_rollup
    GROUP BY BATCH_PICKLIST_CODE, STATION_ID;
    CREATE INDEX idx_final_results ON t_final_results(BATCH, STATION);
    
    SET v_base_query = CONCAT(
        "SELECT
            f.BATCH as 'BATCHPICKLIST CODE',
            f.STATION as 'STATION ID',
            f.MIN_ORDER_CREATION_TIME AS 'MIN ORDER CREATION TIME',
            f.DISTINCT_BIN_COUNT AS 'DISTINCT BIN COUNT',
            f.SUM_OF_MAX_DIFFERENCE AS 'SUM OF MAX DIFFERENCE',
            f.AVG_OF_MAX_DIFFERENCE AS 'AVG OF MAX DIFFERENCE',
            f.SUM_TOTAL_QUANTITY AS 'SUM TOTAL QUANTITY',
            f.AVG_OPS AS 'AVG OPS',
            f.NET_IPP AS 'NET IPP',
            f.GROSS_IPP AS 'GROSS IPP',
            f.OPERATOR_TIME AS 'OPERATOR TIME',
            f.BINS_PER_HOUR AS 'BINS PER HOUR',
            
            COALESCE(m.MEDIAN_QPL, 0) AS 'MEDIAN QPL'
        FROM t_final_results f
        LEFT JOIN t_qpl_with_median m
            ON m.BATCH_PICKLIST_CODE = f.BATCH 
            AND m.STATION_ID = f.STATION
        ", p_filter_condition
    );
    
    SET v_paginated_query = CONCAT(
        "SELECT ", p_select_clause,
        " FROM (", v_base_query, ") AS subquery ",
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
    
    DROP TEMPORARY TABLE IF EXISTS t_final_results;
    DROP TEMPORARY TABLE IF EXISTS t_qpl_with_median;
    DROP TEMPORARY TABLE IF EXISTS t_station_bin_segment_rollup;
    DROP TEMPORARY TABLE IF EXISTS t_wave_pick_results;
    DROP TEMPORARY TABLE IF EXISTS total_pick;
    DROP TEMPORARY TABLE IF EXISTS t_on_station;
    DROP TEMPORARY TABLE IF EXISTS t_master;
    DROP TEMPORARY TABLE IF EXISTS t_all_order_lines;
    DROP TEMPORARY TABLE IF EXISTS t_complete_time;
    DROP TEMPORARY TABLE IF EXISTS t_start_time;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_IPP_REPORT_PICK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_IPP_REPORT_PICK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_IPP_REPORT_PICK`(IN Parameters JSON)
BEGIN
  DECLARE p_page_number              INT;
  DECLARE p_rows_per_page            INT;
  DECLARE p_download_flag            BOOL;
  DECLARE p_page_zero_metadata_flag  BOOL;
  DECLARE p_count_flag               INT;
  DECLARE p_filter_condition         VARCHAR(2000) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE p_select_clause            TEXT;
  DECLARE p_sorting_column_name      VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE p_sorting_column_orderby   VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE p_user_id                  VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_user_name                VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_table_unique_identifier  VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_report_extra_parameters  JSON;
  DECLARE p_start_date_time          VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_end_date_time            VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE v_sorting                  VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE v_datetime_format          VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE v_date_format              VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE v_base_query               TEXT;
  DECLARE v_total_rows               INT DEFAULT 0;
  DECLARE v_paginated_query          TEXT;

  
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
  SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
  SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
  
  SET p_download_flag = CASE
                           WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
                           ELSE FALSE
                        END;

  
  IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
     OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
    SET v_sorting = ' ORDER BY `WAVE ID`, `PICK HOUR`, `STATION ID`';
  ELSE
    SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
  END IF;

  
  IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
    SET p_filter_condition = ' ';
  ELSE
    SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
  END IF;

  
  SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
  SET v_date_format     = DSB_GET_DATE_FORMAT('date');

  
  
  
  CREATE TEMPORARY TABLE t_combined_pick_wave AS
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
    AND PICKED_QUANTITY > 0;

  CREATE INDEX idx_combined_pick ON t_combined_pick_wave (ORDER_BIN_ID, WAVE_ID, PICK_BY);

  
  
  
  CREATE TEMPORARY TABLE t_combined_mapping_log AS
  SELECT
      ORDER_BIN_ID, BIN_ID, STATION_ID,
      MAX(CASE WHEN STATUS = 'BIN_PICKED' THEN BOT_ID END) AS TASK_ALLOCATED_BOT_ID,
      MAX(CASE WHEN STATUS = 'PRE_ON_STATION' THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
      MAX(CASE WHEN STATUS = 'ON_STATION' THEN UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
  FROM order_bin_mapping_log
  WHERE TYPE = 'RACK_PICK'
    AND ORDER_BIN_ID IN (SELECT DISTINCT ORDER_BIN_ID FROM t_combined_pick_wave)
  GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID;

  CREATE INDEX idx_mapping_log ON t_combined_mapping_log (ORDER_BIN_ID);

  
  
  
  CREATE TEMPORARY TABLE t_bin_level_details AS
  SELECT
      cpw.WAVE_ID,
      cpw.ORDER_BIN_ID,
      cpw.STATION_ID,
      cpw.ORDER_ID,
      cpw.SKU_ID,
      cpw.BIN_ID,
      cpw.BIN_SEGMENT_NO,
      cpw.EXPECTED_QUANTITY,
      cpw.PICKED_QUANTITY,
      cpw.SHORT_PICK_QUANTITY,
      cml.ON_STATION_TIMESTAMP,
      cpw.PICK_START_TIMESTAMP,
      cpw.PICK_TIMESTAMP,
      TIMESTAMPDIFF(SECOND, cpw.PICK_START_TIMESTAMP, cpw.PICK_TIMESTAMP) AS PICKING_TIME_SECS,
      cpw.PICK_BY,
      cml.TASK_ALLOCATED_BOT_ID,
      cml.PRE_ON_STATION_TIMESTAMP
  FROM t_combined_pick_wave cpw
  JOIN t_combined_mapping_log cml ON cpw.ORDER_BIN_ID = cml.ORDER_BIN_ID;

  CREATE INDEX idx_bin_level ON t_bin_level_details (WAVE_ID, PICK_BY, ORDER_BIN_ID);

  
  
  
  CREATE TEMPORARY TABLE t_pick_sessions AS
  SELECT
      WAVE_ID,
      HOUR(MAX(PICK_TIMESTAMP)) AS PICK_HOUR,
      PICK_BY,
      ORDER_BIN_ID,
      ORDER_ID,
      BIN_ID,
      BIN_SEGMENT_NO,
      MAX(STATION_ID) AS STATION_ID,
      MAX(SKU_ID) AS SKU_ID,
      SUM(PICKED_QUANTITY) AS PICKED_QUANTITY,
      MAX(ON_STATION_TIMESTAMP) AS ON_STATION_TS,
      PICK_START_TIMESTAMP,
      MAX(PICK_TIMESTAMP) AS PICK_END_TS,
      MAX(PICKING_TIME_SECS) AS PICKING_TIME_SECS,
      LEAST(MAX(PICKING_TIME_SECS), 180) AS PICKING_TIME_SECS_CAPPED,
      MAX(PRE_ON_STATION_TIMESTAMP) AS PRE_ON_STATION_TS
  FROM t_bin_level_details
  GROUP BY 
      WAVE_ID, PICK_BY, ORDER_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, PICK_START_TIMESTAMP, HOUR(PICK_TIMESTAMP);

  
  
  
  CREATE TEMPORARY TABLE t_final_base AS
  SELECT
      WAVE_ID,
      PICK_HOUR,
      PICK_BY,
      ORDER_BIN_ID,
      ORDER_ID,
      BIN_ID,
      BIN_SEGMENT_NO,
      STATION_ID,
      SKU_ID,
      PICKED_QUANTITY,
      PICKING_TIME_SECS,
      PICKING_TIME_SECS_CAPPED,
      
      CASE 
          WHEN ROW_NUMBER() OVER (
              PARTITION BY ORDER_BIN_ID 
              ORDER BY ON_STATION_TS, PICK_START_TIMESTAMP
          ) = 1 
          THEN TIMESTAMPDIFF(SECOND, ON_STATION_TS, PICK_START_TIMESTAMP)
          ELSE 0
      END AS PICK_START_IDLE_TIME_SECS,
      COALESCE(
          GREATEST(
              TIMESTAMPDIFF(SECOND, 
                  LAG(PICK_END_TS) OVER (
                      PARTITION BY STATION_ID, WAVE_ID
                      ORDER BY PICK_END_TS
                  ), 
                  ON_STATION_TS
              ),
              0
          ),
          0
      ) AS BOT_IDLE_TIME_SECS
  FROM t_pick_sessions;

  
  
  
  CREATE TEMPORARY TABLE t_final_base_2 AS
  SELECT 
      WAVE_ID,
      PICK_HOUR,
      ORDER_BIN_ID,
      PICK_BY,
      BIN_ID,
      BIN_SEGMENT_NO,
      STATION_ID,
      SKU_ID,
      COUNT(ORDER_ID) AS OPS,
      SUM(PICKED_QUANTITY) / NULLIF(COUNT(ORDER_ID), 0) AS QPL,
      SUM(PICKED_QUANTITY) AS PICKED_QUANTITY,
      MAX(PICKING_TIME_SECS) AS PICKING_TIME_SECS,
      MAX(PICKING_TIME_SECS_CAPPED) AS PICKING_TIME_SECS_CAPPED,
      MAX(PICK_START_IDLE_TIME_SECS) AS PICK_START_IDLE_TIME_SECS,
      MAX(BOT_IDLE_TIME_SECS) AS BOT_IDLE_TIME_SECS
  FROM t_final_base
  GROUP BY WAVE_ID, PICK_HOUR, PICK_BY, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATION_ID, SKU_ID;

  
  
  
  CREATE TEMPORARY TABLE t_summation AS
  SELECT 
      WAVE_ID,
      PICK_HOUR,
      PICK_BY,
      ROUND(AVG(OPS), 1) AS AVG_OPS,
      ROUND(AVG(QPL), 1) AS AVG_QPL,
      COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)) AS UNIQUE_BIN,
      STATION_ID,
      COUNT(DISTINCT SKU_ID) AS UNIQUE_SKU,
      SUM(PICKED_QUANTITY) AS TOTAL_PICKED_QUANTITY,
      SUM(PICKING_TIME_SECS) AS TOTAL_PICKING_TIME,
      SUM(PICK_START_IDLE_TIME_SECS) AS TOTAL_PICK_START_IDLE_TIME,
      SUM(BOT_IDLE_TIME_SECS) AS TOTAL_BOT_IDLE_TIME,
      ROUND(SUM(PICKING_TIME_SECS) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)), 0), 0) AS AVG_PICKING_TIME_PER_BIN,
      ROUND(SUM(PICK_START_IDLE_TIME_SECS) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)), 0), 0) AS AVG_PICK_START_IDLE_TIME_PER_BIN,
      ROUND(SUM(BOT_IDLE_TIME_SECS) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)), 0), 0) AS AVG_BOT_IDLE_TIME_PER_BIN,
      ROUND(SUM(PICKED_QUANTITY) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)), 0), 0) AS AVG_QUANTITY_PER_BIN,
      ROUND((SUM(PICKED_QUANTITY) * 3600) / NULLIF(SUM(PICKING_TIME_SECS), 0), 0) AS NET_IPP,
      ROUND((SUM(PICKED_QUANTITY) * 3600) / NULLIF((SUM(PICKING_TIME_SECS_CAPPED) + SUM(PICK_START_IDLE_TIME_SECS) + SUM(BOT_IDLE_TIME_SECS)), 0), 0) AS GROSS_IPP,
      ROUND((COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)) * 3600) / NULLIF((SUM(PICKING_TIME_SECS) + SUM(PICK_START_IDLE_TIME_SECS) + SUM(BOT_IDLE_TIME_SECS)), 0), 0) AS BINS_PER_HOUR
  FROM t_final_base_2
  GROUP BY WAVE_ID, PICK_HOUR, STATION_ID, PICK_BY;

  CREATE INDEX idx_summation ON t_summation (WAVE_ID, PICK_HOUR, STATION_ID);

  
  
  
  SET v_base_query = CONCAT(
    "SELECT
      WAVE_ID                           AS 'WAVE ID',
      PICK_HOUR                         AS 'PICK HOUR',
      PICK_BY                           AS 'PICK BY',
      CAST(COALESCE(STATION_ID, 0) AS UNSIGNED) AS 'STATION ID',
      AVG_OPS                           AS 'AVG OPS',
      AVG_QPL                           AS 'AVG QPL',
      UNIQUE_BIN                        AS 'UNIQUE BIN',
      UNIQUE_SKU                        AS 'UNIQUE SKU',
      TOTAL_PICKED_QUANTITY             AS 'TOTAL PICKED QUANTITY',
      TOTAL_PICKING_TIME                AS 'TOTAL PICKING TIME (secs)',
      TOTAL_PICK_START_IDLE_TIME        AS 'TOTAL PICK START IDLE TIME (secs)',
      TOTAL_BOT_IDLE_TIME               AS 'TOTAL BOT IDLE TIME (secs)',
      AVG_PICKING_TIME_PER_BIN          AS 'AVG PICKING TIME PER BIN (secs)',
      AVG_PICK_START_IDLE_TIME_PER_BIN  AS 'AVG PICK START IDLE TIME PER BIN (secs)',
      AVG_BOT_IDLE_TIME_PER_BIN         AS 'AVG BOT IDLE TIME PER BIN (secs)',
      AVG_QUANTITY_PER_BIN              AS 'AVG QUANTITY PER BIN',
      NET_IPP                           AS 'NET IPP',
      GROSS_IPP                         AS 'GROSS IPP',
      BINS_PER_HOUR                     AS 'BINS PER HOUR'
     FROM t_summation",
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

  
  DROP TEMPORARY TABLE IF EXISTS t_combined_pick_wave;
  DROP TEMPORARY TABLE IF EXISTS t_combined_mapping_log;
  DROP TEMPORARY TABLE IF EXISTS t_bin_level_details;
  DROP TEMPORARY TABLE IF EXISTS t_pick_sessions;
  DROP TEMPORARY TABLE IF EXISTS t_final_base;
  DROP TEMPORARY TABLE IF EXISTS t_final_base_2;
  DROP TEMPORARY TABLE IF EXISTS t_summation;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_IPP_REPORT_PICK_DETAILED` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_IPP_REPORT_PICK_DETAILED` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_IPP_REPORT_PICK_DETAILED`(IN Parameters JSON)
BEGIN
  DECLARE p_page_number              INT;
  DECLARE p_rows_per_page            INT;
  DECLARE p_download_flag            BOOL;
  DECLARE p_page_zero_metadata_flag  BOOL;
  DECLARE p_count_flag               INT;
  DECLARE p_filter_condition         VARCHAR(2000) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE p_select_clause            TEXT;
  DECLARE p_sorting_column_name      VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE p_sorting_column_orderby   VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE p_user_id                  VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_user_name                VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_table_unique_identifier  VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_report_extra_parameters  JSON;
  DECLARE p_start_date_time          VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_end_date_time            VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE v_sorting                  VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE v_datetime_format          VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE v_date_format              VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE v_base_query               TEXT;
  DECLARE v_total_rows               INT DEFAULT 0;
  DECLARE v_paginated_query          TEXT;

  
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
  SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
  SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
  
  SET p_download_flag = CASE
                           WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
                           ELSE FALSE
                        END;

  
  IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
     OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
    SET v_sorting = ' ORDER BY `WAVE ID`, `STATION ID`';
  ELSE
    SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
  END IF;

  
  IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
    SET p_filter_condition = ' ';
  ELSE
    SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
  END IF;

  
  SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
  SET v_date_format     = DSB_GET_DATE_FORMAT('date');

  
  
  
  CREATE TEMPORARY TABLE t_combined_pick_wave AS
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
    AND PICKED_QUANTITY > 0;

  CREATE INDEX idx_combined_pick ON t_combined_pick_wave (ORDER_BIN_ID, WAVE_ID, PICK_BY);

  
  
  
  CREATE TEMPORARY TABLE t_combined_mapping_log AS
  SELECT
      ORDER_BIN_ID, BIN_ID, STATION_ID,
      MAX(CASE WHEN STATUS = 'BIN_PICKED' THEN BOT_ID END) AS TASK_ALLOCATED_BOT_ID,
      MAX(CASE WHEN STATUS = 'PRE_ON_STATION' THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
      MAX(CASE WHEN STATUS = 'ON_STATION' THEN UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
  FROM order_bin_mapping_log
  WHERE TYPE = 'RACK_PICK'
    AND ORDER_BIN_ID IN (SELECT DISTINCT ORDER_BIN_ID FROM t_combined_pick_wave)
  GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID;

  CREATE INDEX idx_mapping_log ON t_combined_mapping_log (ORDER_BIN_ID);

  
  
  
  CREATE TEMPORARY TABLE t_bin_level_details AS
  SELECT
      cpw.WAVE_ID,
      cpw.ORDER_BIN_ID,
      cpw.STATION_ID,
      cpw.ORDER_ID,
      cpw.SKU_ID,
      cpw.BIN_ID,
      cpw.BIN_SEGMENT_NO,
      cpw.EXPECTED_QUANTITY,
      cpw.PICKED_QUANTITY,
      cpw.SHORT_PICK_QUANTITY,
      cml.ON_STATION_TIMESTAMP,
      cpw.PICK_START_TIMESTAMP,
      cpw.PICK_TIMESTAMP,
      TIMESTAMPDIFF(SECOND, cpw.PICK_START_TIMESTAMP, cpw.PICK_TIMESTAMP) AS PICKING_TIME_SECS,
      cpw.PICK_BY,
      cml.TASK_ALLOCATED_BOT_ID,
      cml.PRE_ON_STATION_TIMESTAMP
  FROM t_combined_pick_wave cpw
  JOIN t_combined_mapping_log cml ON cpw.ORDER_BIN_ID = cml.ORDER_BIN_ID;

  CREATE INDEX idx_bin_level ON t_bin_level_details (WAVE_ID, PICK_BY, ORDER_BIN_ID);

  
  
  
  CREATE TEMPORARY TABLE t_pick_sessions AS
  SELECT
      WAVE_ID,
      PICK_BY,
      ORDER_BIN_ID,
      ORDER_ID,
      BIN_ID,
      BIN_SEGMENT_NO,
      MAX(STATION_ID) AS STATION_ID,
      MAX(SKU_ID) AS SKU_ID,
      SUM(PICKED_QUANTITY) AS PICKED_QUANTITY,
      MAX(ON_STATION_TIMESTAMP) AS ON_STATION_TS,
      PICK_START_TIMESTAMP,
      MAX(PICK_TIMESTAMP) AS PICK_END_TS,
      MAX(PICKING_TIME_SECS) AS PICKING_TIME_SECS,
      MAX(PRE_ON_STATION_TIMESTAMP) AS PRE_ON_STATION_TS
  FROM t_bin_level_details
  GROUP BY WAVE_ID, PICK_BY, ORDER_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, PICK_START_TIMESTAMP;

  
  
  
  CREATE TEMPORARY TABLE t_final_base AS
  SELECT
      WAVE_ID,
      PICK_BY,
      ORDER_BIN_ID,
      ORDER_ID,
      BIN_ID,
      BIN_SEGMENT_NO,
      STATION_ID,
      SKU_ID,
      PICKED_QUANTITY,
      PICKING_TIME_SECS,
      
      CASE 
          WHEN ROW_NUMBER() OVER (
              PARTITION BY ORDER_BIN_ID 
              ORDER BY ON_STATION_TS, PICK_START_TIMESTAMP
          ) = 1 
          THEN TIMESTAMPDIFF(SECOND, ON_STATION_TS, PICK_START_TIMESTAMP)
          ELSE 0
      END AS PICK_START_IDLE_TIME_SECS,
      COALESCE(
          GREATEST(
              TIMESTAMPDIFF(SECOND, 
                  LAG(PICK_END_TS) OVER (
                      PARTITION BY STATION_ID, WAVE_ID
                      ORDER BY PICK_END_TS
                  ), 
                  ON_STATION_TS
              ),
              0
          ),
          0
      ) AS BOT_IDLE_TIME_SECS
  FROM t_pick_sessions;

  
  
  
  CREATE TEMPORARY TABLE t_final_base_2 AS
  SELECT 
      WAVE_ID,
      ORDER_BIN_ID,
      PICK_BY,
      BIN_ID,
      BIN_SEGMENT_NO,
      STATION_ID,
      SKU_ID,
      COUNT(ORDER_ID) AS OPS,
      SUM(PICKED_QUANTITY) / NULLIF(COUNT(ORDER_ID), 0) AS QPL,
      SUM(PICKED_QUANTITY) AS PICKED_QUANTITY,
      MAX(PICKING_TIME_SECS) AS PICKING_TIME_SECS,
      MAX(PICK_START_IDLE_TIME_SECS) AS PICK_START_IDLE_TIME_SECS,
      MAX(BOT_IDLE_TIME_SECS) AS BOT_IDLE_TIME_SECS
  FROM t_final_base
  GROUP BY WAVE_ID, PICK_BY, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATION_ID, SKU_ID;

  
  
  
  CREATE TEMPORARY TABLE t_summation AS
  SELECT 
      WAVE_ID,
      PICK_BY,
      ROUND(AVG(OPS), 1) AS AVG_OPS,
      ROUND(AVG(QPL), 1) AS AVG_QPL,
      COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)) AS UNIQUE_BIN,
      STATION_ID,
      COUNT(DISTINCT SKU_ID) AS UNIQUE_SKU,
      SUM(PICKED_QUANTITY) AS TOTAL_PICKED_QUANTITY,
      SUM(PICKING_TIME_SECS) AS TOTAL_PICKING_TIME,
      SUM(PICK_START_IDLE_TIME_SECS) AS TOTAL_PICK_START_IDLE_TIME,
      SUM(BOT_IDLE_TIME_SECS) AS TOTAL_BOT_IDLE_TIME,
      ROUND(SUM(PICKING_TIME_SECS) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)), 0), 0) AS AVG_PICKING_TIME_PER_BIN,
      ROUND(SUM(PICK_START_IDLE_TIME_SECS) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)), 0), 0) AS AVG_PICK_START_IDLE_TIME_PER_BIN,
      ROUND(SUM(BOT_IDLE_TIME_SECS) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)), 0), 0) AS AVG_BOT_IDLE_TIME_PER_BIN,
      ROUND(SUM(PICKED_QUANTITY) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)), 0), 0) AS AVG_QUANTITY_PER_BIN,
      ROUND((SUM(PICKED_QUANTITY) * 3600) / NULLIF(SUM(PICKING_TIME_SECS), 0), 0) AS NET_IPP,
      ROUND((SUM(PICKED_QUANTITY) * 3600) / NULLIF((SUM(PICKING_TIME_SECS) + SUM(PICK_START_IDLE_TIME_SECS) + SUM(BOT_IDLE_TIME_SECS)), 0), 0) AS GROSS_IPP,
      ROUND((COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID)) * 3600) / NULLIF((SUM(PICKING_TIME_SECS) + SUM(PICK_START_IDLE_TIME_SECS) + SUM(BOT_IDLE_TIME_SECS)), 0), 0) AS BINS_PER_HOUR
  FROM t_final_base_2
  GROUP BY WAVE_ID, STATION_ID, PICK_BY;

  CREATE INDEX idx_summation ON t_summation (WAVE_ID, STATION_ID);

  
  
  
  SET v_base_query = CONCAT(
    "SELECT
      WAVE_ID                           AS 'WAVE ID',
      PICK_BY                           AS 'PICK BY',
      CAST(COALESCE(STATION_ID, 0) AS UNSIGNED) AS 'STATION ID',
      AVG_OPS                           AS 'AVG OPS',
      AVG_QPL                           AS 'AVG QPL',
      UNIQUE_BIN                        AS 'UNIQUE BIN',
      UNIQUE_SKU                        AS 'UNIQUE SKU',
      TOTAL_PICKED_QUANTITY             AS 'TOTAL PICKED QUANTITY',
      TOTAL_PICKING_TIME                AS 'TOTAL PICKING TIME (secs)',
      TOTAL_PICK_START_IDLE_TIME        AS 'TOTAL PICK START IDLE TIME (secs)',
      TOTAL_BOT_IDLE_TIME               AS 'TOTAL BOT IDLE TIME (secs)',
      AVG_PICKING_TIME_PER_BIN          AS 'AVG PICKING TIME PER BIN (secs)',
      AVG_PICK_START_IDLE_TIME_PER_BIN  AS 'AVG PICK START IDLE TIME PER BIN (secs)',
      AVG_BOT_IDLE_TIME_PER_BIN         AS 'AVG BOT IDLE TIME PER BIN (secs)',
      AVG_QUANTITY_PER_BIN              AS 'AVG QUANTITY PER BIN',
      NET_IPP                           AS 'NET IPP',
      GROSS_IPP                         AS 'GROSS IPP',
      BINS_PER_HOUR                     AS 'BINS PER HOUR'
     FROM t_summation",
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

  
  DROP TEMPORARY TABLE IF EXISTS t_combined_pick_wave;
  DROP TEMPORARY TABLE IF EXISTS t_combined_mapping_log;
  DROP TEMPORARY TABLE IF EXISTS t_bin_level_details;
  DROP TEMPORARY TABLE IF EXISTS t_pick_sessions;
  DROP TEMPORARY TABLE IF EXISTS t_final_base;
  DROP TEMPORARY TABLE IF EXISTS t_final_base_2;
  DROP TEMPORARY TABLE IF EXISTS t_summation;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PAGINATED_IPP_REPORT_PUT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PAGINATED_IPP_REPORT_PUT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PAGINATED_IPP_REPORT_PUT`(IN Parameters JSON)
BEGIN
  DECLARE p_page_number              INT;
  DECLARE p_rows_per_page            INT;
  DECLARE p_download_flag            BOOL;
  DECLARE p_page_zero_metadata_flag  BOOL;
  DECLARE p_count_flag               INT;
  DECLARE p_filter_condition         VARCHAR(2000) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE p_select_clause            TEXT;
  DECLARE p_sorting_column_name      VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE p_sorting_column_orderby   VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE p_user_id                  VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_user_name                VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_table_unique_identifier  VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_report_extra_parameters  JSON;
  DECLARE p_start_date_time          VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE p_end_date_time            VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE v_sorting                  VARCHAR(200) CHARACTER SET latin1 COLLATE latin1_swedish_ci DEFAULT '';
  DECLARE v_datetime_format          VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE v_date_format              VARCHAR(50) CHARACTER SET latin1 COLLATE latin1_swedish_ci;
  DECLARE v_base_query               TEXT;
  DECLARE v_total_rows               INT DEFAULT 0;
  DECLARE v_paginated_query          TEXT;

  
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
  SET p_start_date_time         = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.start_date_time'));
  SET p_end_date_time           = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.end_date_time'));
  
  SET p_download_flag = CASE
                           WHEN JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.download')) = 'true' THEN TRUE
                           ELSE FALSE
                        END;

  
  IF (p_sorting_column_name IS NULL OR p_sorting_column_name = '')
     OR (p_sorting_column_orderby IS NULL OR p_sorting_column_orderby = '') THEN
    SET v_sorting = ' ORDER BY `WAVE ID`, `PUT HOUR`, `STATION ID`';
  ELSE
    SET v_sorting = CONCAT(' ORDER BY `', p_sorting_column_name, '` ', p_sorting_column_orderby);
  END IF;

  
  IF p_filter_condition IS NULL OR p_filter_condition = '' THEN
    SET p_filter_condition = ' ';
  ELSE
    SET p_filter_condition = CONCAT(' WHERE ', p_filter_condition);
  END IF;

  
  SET v_datetime_format = DSB_GET_DATE_FORMAT('dateTime');
  SET v_date_format     = DSB_GET_DATE_FORMAT('date');

  
  
  
  CREATE TEMPORARY TABLE t_combined_put_wave AS
  SELECT
      WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO,
      STATION_ID, EXPECTED_QUANTITY, PUT_QUANTITY, SHORT_PUT_QUANTITY,
      PUT_START_TIMESTAMP, PUT_TIMESTAMP, PUT_BY
  FROM put_wave_order_master
  WHERE STATUS NOT IN ('PENDING', 'PUT_STARTED')
    AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    AND PUT_QUANTITY > 0

  UNION ALL

  SELECT
      WAVE_ID, STORAGE_REQUEST_ID, STORAGE_ID, SKU_ID, BATCH_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO,
      STATION_ID, EXPECTED_QUANTITY, PUT_QUANTITY, SHORT_PUT_QUANTITY,
      PUT_START_TIMESTAMP, PUT_TIMESTAMP, PUT_BY
  FROM put_wave_order_master_archive
  WHERE STATUS NOT IN ('PENDING', 'PUT_STARTED')
    AND PUT_TIMESTAMP BETWEEN p_start_date_time AND p_end_date_time
    AND PUT_QUANTITY > 0;

  CREATE INDEX idx_combined_put ON t_combined_put_wave (ORDER_BIN_ID, WAVE_ID, PUT_BY);

  
  
  
  CREATE TEMPORARY TABLE t_combined_mapping_log AS
  SELECT
      ORDER_BIN_ID, BIN_ID, STATION_ID,
      MAX(CASE WHEN STATUS = 'BIN_PUT' THEN BOT_ID END) AS TASK_ALLOCATED_BOT_ID,
      MAX(CASE WHEN STATUS = 'PRE_ON_STATION' THEN UPDATED_TIMESTAMP END) AS PRE_ON_STATION_TIMESTAMP,
      MAX(CASE WHEN STATUS = 'ON_STATION' THEN UPDATED_TIMESTAMP END) AS ON_STATION_TIMESTAMP
  FROM order_bin_mapping_log
  WHERE TYPE = 'RACK_PICK'
    AND ORDER_BIN_ID IN (SELECT DISTINCT ORDER_BIN_ID FROM t_combined_put_wave)
  GROUP BY ORDER_BIN_ID, BIN_ID, STATION_ID;

  CREATE INDEX idx_mapping_log ON t_combined_mapping_log (ORDER_BIN_ID);

  
  
  
  CREATE TEMPORARY TABLE t_bin_level_details AS
  SELECT
      cpw.WAVE_ID,
      cpw.ORDER_BIN_ID,
      cpw.STATION_ID,
      cpw.STORAGE_REQUEST_ID,
      cpw.SKU_ID,
      cpw.BIN_ID,
      cpw.BIN_SEGMENT_NO,
      cpw.EXPECTED_QUANTITY,
      cpw.PUT_QUANTITY,
      cpw.SHORT_PUT_QUANTITY,
      cml.ON_STATION_TIMESTAMP,
      cpw.PUT_START_TIMESTAMP,
      cpw.PUT_TIMESTAMP,
      TIMESTAMPDIFF(SECOND, cpw.PUT_START_TIMESTAMP, cpw.PUT_TIMESTAMP) AS PUTTING_TIME_SECS,
      cpw.PUT_BY,
      cml.TASK_ALLOCATED_BOT_ID,
      cml.PRE_ON_STATION_TIMESTAMP
  FROM t_combined_put_wave cpw
  JOIN t_combined_mapping_log cml ON cpw.ORDER_BIN_ID = cml.ORDER_BIN_ID;

  CREATE INDEX idx_bin_level ON t_bin_level_details (WAVE_ID, PUT_BY, ORDER_BIN_ID);

  
  
  
  CREATE TEMPORARY TABLE t_put_sessions AS
  SELECT
      WAVE_ID,
      HOUR(MAX(PUT_TIMESTAMP)) AS PUT_HOUR,
      PUT_BY,
      ORDER_BIN_ID,
      STORAGE_REQUEST_ID,
      BIN_ID,
      BIN_SEGMENT_NO,
      MAX(STATION_ID) AS STATION_ID,
      MAX(SKU_ID) AS SKU_ID,
      SUM(PUT_QUANTITY) AS PUT_QUANTITY,
      MAX(ON_STATION_TIMESTAMP) AS ON_STATION_TS,
      PUT_START_TIMESTAMP,
      MAX(PUT_TIMESTAMP) AS PUT_END_TS,
      MAX(PUTTING_TIME_SECS) AS PUTTING_TIME_SECS,
      LEAST(MAX(PUTTING_TIME_SECS), 180) AS PUTTING_TIME_SECS_CAPPED,
      MAX(PRE_ON_STATION_TIMESTAMP) AS PRE_ON_STATION_TS
  FROM t_bin_level_details
  GROUP BY WAVE_ID, PUT_BY, STORAGE_REQUEST_ID, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, PUT_START_TIMESTAMP, HOUR(PUT_TIMESTAMP);

  
  
  
  CREATE TEMPORARY TABLE t_final_base AS
  SELECT
      WAVE_ID,
      PUT_HOUR,
      PUT_BY,
      ORDER_BIN_ID,
      STORAGE_REQUEST_ID,
      BIN_ID,
      BIN_SEGMENT_NO,
      STATION_ID,
      SKU_ID,
      PUT_QUANTITY,
      PUTTING_TIME_SECS,
      PUTTING_TIME_SECS_CAPPED,
      
      CASE 
          WHEN ROW_NUMBER() OVER (
              PARTITION BY ORDER_BIN_ID 
              ORDER BY ON_STATION_TS, PUT_START_TIMESTAMP
          ) = 1 
          THEN TIMESTAMPDIFF(SECOND, ON_STATION_TS, PUT_START_TIMESTAMP)
          ELSE 0
      END AS PUT_START_IDLE_TIME_SECS,
      COALESCE(
          GREATEST(
              TIMESTAMPDIFF(SECOND, 
                  LAG(PUT_END_TS) OVER (
                      PARTITION BY STATION_ID, WAVE_ID
                      ORDER BY PUT_END_TS
                  ), 
                  ON_STATION_TS
              ),
              0
          ),
          0
      ) AS BOT_IDLE_TIME_SECS
  FROM t_put_sessions;

  
  
  
  CREATE TEMPORARY TABLE t_final_base_2 AS
  SELECT 
      WAVE_ID,
      PUT_HOUR,
      ORDER_BIN_ID,
      PUT_BY,
      BIN_ID,
      BIN_SEGMENT_NO,
      STATION_ID,
      SKU_ID,
      SUM(PUT_QUANTITY) AS PUT_QUANTITY,
      MAX(PUTTING_TIME_SECS) AS PUTTING_TIME_SECS,
      MAX(PUTTING_TIME_SECS_CAPPED) AS PUTTING_TIME_SECS_CAPPED,
      MAX(PUT_START_IDLE_TIME_SECS) AS PUT_START_IDLE_TIME_SECS,
      MAX(BOT_IDLE_TIME_SECS) AS BOT_IDLE_TIME_SECS
  FROM t_final_base
  GROUP BY WAVE_ID, PUT_HOUR, PUT_BY, ORDER_BIN_ID, BIN_ID, BIN_SEGMENT_NO, STATION_ID, SKU_ID;

  
  
  
  CREATE TEMPORARY TABLE t_summation AS
  SELECT 
      WAVE_ID,
      PUT_HOUR,
      PUT_BY,
      COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID, '-', BIN_SEGMENT_NO)) AS UNIQUE_BIN,
      STATION_ID,
      COUNT(DISTINCT SKU_ID) AS UNIQUE_SKU,
      SUM(PUT_QUANTITY) AS TOTAL_PUT_QUANTITY,
      SUM(PUTTING_TIME_SECS) AS TOTAL_PUTTING_TIME,
      SUM(PUT_START_IDLE_TIME_SECS) AS TOTAL_PUT_START_IDLE_TIME,
      SUM(BOT_IDLE_TIME_SECS) AS TOTAL_BOT_IDLE_TIME,
      ROUND(SUM(PUTTING_TIME_SECS) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID, '-', BIN_SEGMENT_NO)), 0), 0) AS AVG_PUTTING_TIME_PER_BIN,
      ROUND(SUM(PUT_START_IDLE_TIME_SECS) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID, '-', BIN_SEGMENT_NO)), 0), 0) AS AVG_PUT_START_IDLE_TIME_PER_BIN,
      ROUND(SUM(BOT_IDLE_TIME_SECS) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID, '-', BIN_SEGMENT_NO)), 0), 0) AS AVG_BOT_IDLE_TIME_PER_BIN,
      ROUND(SUM(PUT_QUANTITY) / NULLIF(COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID, '-', BIN_SEGMENT_NO)), 0), 0) AS AVG_QUANTITY_PER_BIN,
      ROUND((SUM(PUT_QUANTITY) * 3600) / NULLIF(SUM(PUTTING_TIME_SECS), 0), 0) AS NET_IPP,
      ROUND((SUM(PUT_QUANTITY) * 3600) / NULLIF((SUM(PUTTING_TIME_SECS_CAPPED) + SUM(PUT_START_IDLE_TIME_SECS) + SUM(BOT_IDLE_TIME_SECS)), 0), 0) AS GROSS_IPP,
      ROUND((COUNT(DISTINCT CONCAT(ORDER_BIN_ID, '-', BIN_ID, '-', BIN_SEGMENT_NO)) * 3600) / NULLIF((SUM(PUTTING_TIME_SECS) + SUM(PUT_START_IDLE_TIME_SECS) + SUM(BOT_IDLE_TIME_SECS)), 0), 0) AS BINS_PER_HOUR
  FROM t_final_base_2
  GROUP BY WAVE_ID, PUT_HOUR, STATION_ID, PUT_BY;

  CREATE INDEX idx_summation ON t_summation (WAVE_ID, PUT_HOUR, STATION_ID);

  
  
  
  SET v_base_query = CONCAT(
    "SELECT
      WAVE_ID                           AS 'WAVE ID',
      PUT_HOUR                          AS 'PUT HOUR',
      PUT_BY                            AS 'PUT BY',
      CAST(COALESCE(STATION_ID, 0) AS UNSIGNED) AS 'STATION ID',
      UNIQUE_BIN                        AS 'UNIQUE BIN',
      UNIQUE_SKU                        AS 'UNIQUE SKU',
      TOTAL_PUT_QUANTITY                AS 'TOTAL PUT QUANTITY',
      TOTAL_PUTTING_TIME                AS 'TOTAL PUTTING TIME (secs)',
      TOTAL_PUT_START_IDLE_TIME         AS 'TOTAL PUT START IDLE TIME (secs)',
      TOTAL_BOT_IDLE_TIME               AS 'TOTAL BOT IDLE TIME (secs)',
      AVG_PUTTING_TIME_PER_BIN          AS 'AVG PUTTING TIME PER BIN (secs)',
      AVG_PUT_START_IDLE_TIME_PER_BIN   AS 'AVG PUT START IDLE TIME PER BIN (secs)',
      AVG_BOT_IDLE_TIME_PER_BIN         AS 'AVG BOT IDLE TIME PER BIN (secs)',
      AVG_QUANTITY_PER_BIN              AS 'AVG QUANTITY PER BIN',
      NET_IPP                           AS 'NET IPP',
      GROSS_IPP                         AS 'GROSS IPP',
      BINS_PER_HOUR                     AS 'BINS PER HOUR'
     FROM t_summation",
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

  
  DROP TEMPORARY TABLE IF EXISTS t_combined_put_wave;
  DROP TEMPORARY TABLE IF EXISTS t_combined_mapping_log;
  DROP TEMPORARY TABLE IF EXISTS t_bin_level_details;
  DROP TEMPORARY TABLE IF EXISTS t_put_sessions;
  DROP TEMPORARY TABLE IF EXISTS t_final_base;
  DROP TEMPORARY TABLE IF EXISTS t_final_base_2;
  DROP TEMPORARY TABLE IF EXISTS t_summation;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PALLET_DETAILS_BY_PALLET_ID_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PALLET_DETAILS_BY_PALLET_ID_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PALLET_DETAILS_BY_PALLET_ID_GET`(
  IN Parameters JSON
)
BEGIN
  
  DECLARE p_pallet_ids JSON;
  DECLARE p_info_type VARCHAR(100);

  
  SET p_pallet_ids = JSON_EXTRACT(Parameters, '$.pallet_ids');
  SET p_info_type = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.info_type'));

  
  IF p_info_type = 'pallet_info' THEN
    CALL DSB_PALLET_DETAILS_BY_PALLET_ID_GET_PALLET_INFO(p_pallet_ids);
  ELSE
    
    SELECT
      0 AS `Success`,
      CONCAT('Unsupported Pallet info type: ', p_info_type) AS `Result`;
  END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PALLET_DETAILS_BY_PALLET_ID_GET_PALLET_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PALLET_DETAILS_BY_PALLET_ID_GET_PALLET_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PALLET_DETAILS_BY_PALLET_ID_GET_PALLET_INFO`(
    IN p_pallet_ids JSON
)
BEGIN
    WITH
    pallet_union AS (
        SELECT
            MIN(wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID) AS WMS_STORAGE_REQUEST_PALLET_DATA_ID,
            wtwsrpd.PALLET_ID,            
            wtwsrpd.STORAGE_REQUEST_ID,
            MIN(wtwsrpd.INSERT_TIMESTAMP)                   AS PALLET_INSERTED,
            MIN(wtwsrpd.PALLET_SCANNED_TIMESTAMP)           AS PALLET_SCANNED,
            MAX(wtwsrpd.PALLET_COMPLETION_TIMESTAMP)        AS PALLET_COMPLETION
        FROM wms_to_wcs_storage_request_pallet_data wtwsrpd
        WHERE wtwsrpd.PALLET_ID IN (
        SELECT jt.pallet_id
        FROM JSON_TABLE(
            p_pallet_ids,
            '$[*]' COLUMNS (
                pallet_id VARCHAR(100) PATH '$'
            )
        ) jt
        )
        GROUP BY wtwsrpd.STORAGE_REQUEST_ID

        UNION ALL

        SELECT
            MIN(wtwsrpd.WMS_STORAGE_REQUEST_PALLET_DATA_ID) AS WMS_STORAGE_REQUEST_PALLET_DATA_ID,
	    wtwsrpd.PALLET_ID, 
            wtwsrpd.STORAGE_REQUEST_ID,
            MIN(wtwsrpd.INSERT_TIMESTAMP)                   AS PALLET_INSERTED,
            MIN(wtwsrpd.PALLET_SCANNED_TIMESTAMP)           AS PALLET_SCANNED,
            MAX(wtwsrpd.PALLET_COMPLETION_TIMESTAMP)        AS PALLET_COMPLETION
        FROM wms_to_wcs_storage_request_pallet_data_archive wtwsrpd
        WHERE wtwsrpd.PALLET_ID IN (
        SELECT jt.pallet_id
        FROM JSON_TABLE(
            p_pallet_ids,
            '$[*]' COLUMNS (
                pallet_id VARCHAR(100) PATH '$'
            )
        ) jt
        )
        GROUP BY wtwsrpd.STORAGE_REQUEST_ID
    ),

    pallet_dedup AS (
        SELECT
            MIN(WMS_STORAGE_REQUEST_PALLET_DATA_ID) AS WMS_STORAGE_REQUEST_PALLET_DATA_ID,
	    PALLET_ID,             
            STORAGE_REQUEST_ID,
            MIN(PALLET_INSERTED)   AS PALLET_RECEIVED_TIMESTAMP,
            MIN(PALLET_SCANNED)    AS PALLET_SCANNED_TIMESTAMP,
            MAX(PALLET_COMPLETION) AS PALLET_COMPLETION_TIMESTAMP
        FROM pallet_union
        GROUP BY STORAGE_REQUEST_ID
    ),

    pallet_complete_data AS (
        SELECT
            pd.PALLET_ID,
            pd.STORAGE_REQUEST_ID,
            pd.PALLET_RECEIVED_TIMESTAMP,
            pd.PALLET_SCANNED_TIMESTAMP,
            pd.PALLET_COMPLETION_TIMESTAMP,
            COUNT(DISTINCT wtwsrd.STORAGE_ID) AS STORAGE_COUNT,
            COUNT(DISTINCT wtwsrd.ARTICLE_ID) AS ARTICLE_COUNT,
            SUM(wtwsrd.QUANTITY)              AS TOTAL_QUANTITY
        FROM (
            SELECT
                WMS_STORAGE_REQUEST_PALLET_DATA_ID,
                STORAGE_ID,
                ARTICLE_ID,
                QUANTITY
            FROM wms_to_wcs_storage_request_data

            UNION ALL

            SELECT
                WMS_STORAGE_REQUEST_PALLET_DATA_ID,
                STORAGE_ID,
                ARTICLE_ID,
                QUANTITY
            FROM wms_to_wcs_storage_request_data_archive
        ) wtwsrd
        INNER JOIN pallet_dedup pd
            ON wtwsrd.WMS_STORAGE_REQUEST_PALLET_DATA_ID = pd.WMS_STORAGE_REQUEST_PALLET_DATA_ID
        GROUP BY
            pd.STORAGE_REQUEST_ID,
            pd.PALLET_RECEIVED_TIMESTAMP,
            pd.PALLET_SCANNED_TIMESTAMP,
            pd.PALLET_COMPLETION_TIMESTAMP
    ),

    pick_data_complete AS (
        SELECT
	    pcd.PALLET_ID,
            pcd.STORAGE_REQUEST_ID,
            SUM(pwom.PUT_QUANTITY) AS TOTAL_PUT_QUANTITY
        FROM pallet_complete_data pcd
        INNER JOIN (
            SELECT STORAGE_REQUEST_ID, PUT_QUANTITY FROM put_wave_order_master
            UNION ALL
            SELECT STORAGE_REQUEST_ID, PUT_QUANTITY FROM put_wave_order_master_archive
        ) pwom
            ON pwom.STORAGE_REQUEST_ID = pcd.STORAGE_REQUEST_ID
        GROUP BY pcd.STORAGE_REQUEST_ID
    ),

    put_stock_adjustment AS (
        SELECT
            pcd.PALLET_ID,
            pcd.STORAGE_REQUEST_ID,
            SUM(pwwd.LEFT_OVER) AS TOTAL_LEFT_OVER
        FROM pallet_complete_data pcd
        INNER JOIN (
            SELECT STORAGE_REQUEST_ID, LEFT_OVER FROM put_wave_wms_data
            UNION ALL
            SELECT STORAGE_REQUEST_ID, LEFT_OVER FROM put_wave_wms_data_archive
        ) pwwd
            ON pwwd.STORAGE_REQUEST_ID = pcd.STORAGE_REQUEST_ID
        GROUP BY pcd.STORAGE_REQUEST_ID
    ),

    put_order_id_list AS (
        SELECT DISTINCT
            PUT_ORDER_ID,
            STORAGE_REQUEST_ID
        FROM (
            SELECT PUT_ORDER_ID, STORAGE_REQUEST_ID FROM put_wave_order_master
            UNION ALL
            SELECT PUT_ORDER_ID, STORAGE_REQUEST_ID FROM put_wave_order_master_archive
        ) combined
        WHERE STORAGE_REQUEST_ID IN (
            SELECT DISTINCT STORAGE_REQUEST_ID FROM pallet_complete_data
        )
    ),

    put_stock_adjustment_main AS (
        SELECT
            poil.STORAGE_REQUEST_ID,
            SUM(spwr.SHORT_PUT_QUANTITY) AS TOTAL_SHORT_PUT
        FROM short_put_wave_reason spwr
        INNER JOIN put_order_id_list poil
            ON spwr.PUT_ORDER_ID = poil.PUT_ORDER_ID
        WHERE spwr.`REASON` NOT IN ('no_space_in_bin')
        GROUP BY poil.STORAGE_REQUEST_ID
    )

    SELECT
        pcd.PALLET_ID,	
        pcd.STORAGE_REQUEST_ID,
        pcd.PALLET_RECEIVED_TIMESTAMP,
        pcd.PALLET_SCANNED_TIMESTAMP,
        pcd.PALLET_COMPLETION_TIMESTAMP,
        pcd.STORAGE_COUNT AS DISTINCT_STORAGE_ID,
        pcd.ARTICLE_COUNT AS DISTINCT_SKU_ID,
        pcd.TOTAL_QUANTITY,
        COALESCE(pdc.TOTAL_PUT_QUANTITY, 0)                       AS PUT_QUANTITY,
        (COALESCE(psa.TOTAL_LEFT_OVER, 0) + COALESCE(psam.TOTAL_SHORT_PUT, 0)) AS STOCK_ADJUSTMENT
    FROM pallet_complete_data pcd
    LEFT JOIN pick_data_complete       pdc  ON pcd.STORAGE_REQUEST_ID = pdc.STORAGE_REQUEST_ID
    LEFT JOIN put_stock_adjustment     psa  ON pcd.STORAGE_REQUEST_ID = psa.STORAGE_REQUEST_ID
    LEFT JOIN put_stock_adjustment_main psam ON pcd.STORAGE_REQUEST_ID = psam.STORAGE_REQUEST_ID
    ORDER BY pcd.PALLET_SCANNED_TIMESTAMP DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PICK_RULE_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PICK_RULE_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PICK_RULE_GET_ALL`()
BEGIN
    SELECT 
        PICK_RULE_ID,
        RULE_NAME,
        RULE_DESCRIPTION,
        DSB_FILTER_CONDITION,
        DSB_FILTER_JSON,
        IS_ACTIVE,
        INSERTED_BY, 
        INSERTED_TIMESTAMP, 
        UPDATED_BY, 
        UPDATED_TIMESTAMP
    FROM pick_rule_master;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PICK_RULE_INSERT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PICK_RULE_INSERT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PICK_RULE_INSERT`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_pick_rule_id           INT;
    DECLARE p_rule_name              VARCHAR(255);
    DECLARE p_rule_description       TEXT;
    DECLARE p_filter_condition       TEXT;
    DECLARE p_dsb_filter_condition   TEXT;
    DECLARE p_filter_json            TEXT;
    DECLARE p_is_active              INT;
    DECLARE p_updated_by             VARCHAR(100);
    
    DECLARE v_rule_name_exists       INT;
    DECLARE Success                  INT DEFAULT 1;
    DECLARE Result                   VARCHAR(100);
    
    SET p_pick_rule_id         = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.pick_rule_id')) AS UNSIGNED);
    SET p_rule_name            = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.rule_name'));
    SET p_rule_description     = NULLIF(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.rule_description')), '');
    SET p_filter_json          = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.filter_json'));
    SET p_dsb_filter_condition = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.dsb_filter_condition'));
    SET p_is_active            = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.is_active')) AS UNSIGNED);
    SET p_updated_by           = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.updated_by'));
    
    SET p_filter_condition = DSB_PICK_RULE_QUERY_INSERT(p_filter_json);
    
    IF p_pick_rule_id = 0 THEN
        SELECT COUNT(*) INTO v_rule_name_exists
        FROM pick_rule_master
        WHERE RULE_NAME = p_rule_name;
        IF v_rule_name_exists = 0 THEN
            INSERT INTO pick_rule_master (
                RULE_NAME,
                RULE_DESCRIPTION,
                FILTER_CONDITION,
                DSB_FILTER_CONDITION,
                DSB_FILTER_JSON,
                IS_ACTIVE,
                INSERTED_BY,
                INSERTED_TIMESTAMP,
                UPDATED_BY
            ) VALUES (
                p_rule_name,
                p_rule_description,
                p_filter_condition,
                p_dsb_filter_condition,
                p_filter_json,
                p_is_active,
                p_updated_by,
                NOW(),
                p_updated_by
            );
            SET Result = CONCAT(p_rule_name, " inserted successfully");
        ELSE
            SET Success = 0;
            SET Result = CONCAT(p_rule_name, " already exists");
        END IF;
    
    ELSE
        SELECT COUNT(*) INTO v_rule_name_exists
        FROM pick_rule_master
        WHERE PICK_RULE_ID = p_pick_rule_id;
        IF v_rule_name_exists > 0 THEN
            UPDATE pick_rule_master
            SET
                RULE_NAME            = p_rule_name,
                RULE_DESCRIPTION     = p_rule_description,
                FILTER_CONDITION     = p_filter_condition,
                DSB_FILTER_CONDITION = p_dsb_filter_condition,
                DSB_FILTER_JSON      = p_filter_json,
                IS_ACTIVE            = p_is_active,
                UPDATED_BY           = p_updated_by,
                UPDATED_TIMESTAMP    = NOW()
            WHERE PICK_RULE_ID = p_pick_rule_id;
            SET Result = CONCAT(p_rule_name, " updated successfully");
        ELSE
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid pick_rule_id provided';
            SET Success = 0;
            SET Result = "Invalid Rule";
        END IF;
    END IF;
    
    SELECT p_rule_name, Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PTL_DETAILS_BY_PTL_ID_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PTL_DETAILS_BY_PTL_ID_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_PTL_DETAILS_BY_PTL_ID_GET`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_ptl_id    VARCHAR(5);
    DECLARE p_info_type VARCHAR(100);

    SET p_ptl_id    = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ptl_id'));
    SET p_info_type = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.info_type'));

    IF p_info_type = 'last_lpn_activity' THEN
        CALL `DSB_PTL_DETAILS_BY_PTL_ID_GET_LPN_INFO`(p_ptl_id);
    ELSE
        SELECT
            0 AS `Success`,
            CONCAT('Unsupported PTL info type: ', p_info_type) AS `Result`;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PTL_DETAILS_BY_PTL_ID_GET_LPN_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PTL_DETAILS_BY_PTL_ID_GET_LPN_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PTL_DETAILS_BY_PTL_ID_GET_LPN_INFO`(
    IN p_ptl_ids JSON
)
BEGIN
    SELECT 
	lm.PTL_ID,
        lm.LPN_BARCODE,
        lm.LPN_STATUS,
        lm.LPN_OPEN_TIMESTAMP,
        lm.LPN_CLOSE_TIMESTAMP,
        p.JSON_REQUEST,
        p.JSON_RESPONSE
    FROM 
        lpn_master lm
    LEFT JOIN (
        SELECT 
            PAYLOAD_ID,
            JSON_REQUEST,
            JSON_RESPONSE
        FROM wcs_to_wms_payload
        
        UNION ALL
        
        SELECT 
            PAYLOAD_ID,
            JSON_REQUEST,
            JSON_RESPONSE
        FROM 
            wcs_to_wms_payload_archive
    ) AS p
        ON lm.LPN_CLOSED_PAYLOAD_ID = p.PAYLOAD_ID
    WHERE 
        lm.PTL_ID IN (
            SELECT jt.ptl_id
            FROM JSON_TABLE(
                p_ptl_ids,
                '$[*]' COLUMNS (
                    ptl_id VARCHAR(5) PATH '$'
                )
            ) jt
        )
    ORDER BY 
        lm.UPDATED_TIMESTAMP DESC
    limit 100;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PTL_DETAILS_FOR_PICK_BY_STATION_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PTL_DETAILS_FOR_PICK_BY_STATION_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PTL_DETAILS_FOR_PICK_BY_STATION_ID`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_station_id INT;
    
    
    SET p_station_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id'));
    
    

    WITH PTL_BASE AS (
        SELECT
            hpm.PARENT_ID,
            hpm.PTL_ID,
            pcs.DISPLAY,
            pcs.LIGHT,
            lm.LPN_ID,
            lm.LPN_BARCODE,
            lm.LPN_STATUS,
            lm.LPN_OPEN_TIMESTAMP,
            lm.LPN_CLOSE_TIMESTAMP,
            wtword.ORDER_ID,
            
            wtword.PARENT_ORDER_ID, 
            pmdm.MESSAGE,
            pmdm.DESCRIPTION,
            IF(wtword.ORDER_ID IS NOT NULL, 1, 0) AS has_active_orders
        FROM hw_ptl_master hpm
        LEFT JOIN ptl_current_state pcs 
            ON pcs.PTL_ID = hpm.PTL_ID
        LEFT JOIN lpn_master lm 
            ON lm.PTL_ID = hpm.PTL_ID 
            AND lm.LPN_STATUS = 'LPN_OPEN'
        LEFT JOIN wms_to_wcs_order_request_data wtword 
            ON wtword.ALLOCATED_PTL = hpm.PTL_ID  
            AND wtword.ORDER_REQUEST_STATUS = 'ORDER_PICK_STARTED'
        LEFT JOIN ptl_messages_description_master pmdm 
            ON pmdm.DISPLAY = pcs.DISPLAY
        WHERE hpm.PARENT_ID = p_station_id
    ),
    FILTERED_SUMS AS (
        
        SELECT 
            lpwom.LPN_ID, 
            SUM(lpwom.PICKED_QUANTITY) AS TOTAL_PICKED
        FROM lpn_pick_wave_order_mapping lpwom
        INNER JOIN PTL_BASE pb 
            ON lpwom.LPN_ID = pb.LPN_ID
        GROUP BY lpwom.LPN_ID
    ),
    ORDER_DETAILS AS (
        
        
        SELECT DISTINCT
            pre.PARENT_ORDER_ID,
            pre.BATCH_PICKLIST_ID,
            pre.BATCH_PICKLIST_CODE
        FROM wms_to_wcs_order_level_pre_staged_data pre
        INNER JOIN PTL_BASE pb 
            ON pre.PARENT_ORDER_ID = pb.PARENT_ORDER_ID
        WHERE pre.ORDER_REQUEST_STATUS = 'ORDER_PICK_STARTED'
    )
    SELECT
        p.PARENT_ID,
        p.PTL_ID,
        LPAD(p.DISPLAY, 3, '0') AS DISPLAY,
        p.LIGHT,
        CASE
            WHEN p.DISPLAY BETWEEN '0' AND '99999' THEN '000-999'
            ELSE p.MESSAGE
        END AS MESSAGE,
        CASE
            WHEN p.DISPLAY BETWEEN '0' AND '99999' THEN 'Quantity to be put in LPN.'
            ELSE p.DESCRIPTION
        END AS DESCRIPTION,
        COALESCE(p.has_active_orders, 0) AS ACTIVE_ORDERS,
        COALESCE(fs.TOTAL_PICKED, 0) AS PICKED_EACHES,
        p.LPN_ID,
        p.LPN_BARCODE,
        p.LPN_STATUS,
        p.LPN_OPEN_TIMESTAMP,
        p.LPN_CLOSE_TIMESTAMP,
        od.BATCH_PICKLIST_ID,
        od.BATCH_PICKLIST_CODE,
        p.ORDER_ID
    FROM PTL_BASE p
    LEFT JOIN FILTERED_SUMS fs 
        ON fs.LPN_ID = p.LPN_ID
    LEFT JOIN ORDER_DETAILS od 
        ON od.PARENT_ORDER_ID = p.PARENT_ORDER_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_PTL_MESSAGE_DESCRIPTION_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_PTL_MESSAGE_DESCRIPTION_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_PTL_MESSAGE_DESCRIPTION_GET_ALL`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_wave_type VARCHAR(100);
    
    SET p_wave_type = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_type'));
    
    SELECT 
        DISPLAY, 
        MESSAGE, 
        DESCRIPTION 
    FROM 
        ptl_messages_description_master 
    WHERE 
        WAVE_TYPE = p_wave_type;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_REPORTS_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_REPORTS_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_REPORTS_GET_ALL`(IN Parameters JSON)
BEGIN
    DECLARE p_role_id INT;
    SET p_role_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.role_id')) AS UNSIGNED);
    SELECT
        drpm.REPORT_PARENT_NAME,
        drm.*
    FROM dashboard_report_master AS drm
    INNER JOIN dashboard_report_parent_master AS drpm
        ON drpm.REPORT_PARENT_ID = drm.REPORT_PARENT_ID
       AND drpm.IS_ACTIVE = 1
    WHERE drm.IS_ACTIVE = 1
      AND EXISTS (
            SELECT 1
            FROM dashboard_report_role_mapping AS drrm
            WHERE drrm.REPORT_ID = drm.REPORT_ID
              AND drrm.ROLE_ID = p_role_id
              AND drrm.IS_ACTIVE = 1
        )
    ORDER BY
        drpm.SEQUENCE ASC,
        drm.SEQUENCE ASC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_ROLE_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_ROLE_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_ROLE_GET_ALL`(IN Parameters INT)
BEGIN
    IF Parameters = 1 THEN
        
        SELECT 
            drm.IS_ACTIVE,
            drm.ROLE_ID,
            drm.ROLE_NAME,
            dmm.MENU_ID,
            dmm.MENU_NAME,
            drm.INSERTED_BY,
            drm.INSERTED_TIMESTAMP,
            drm.UPDATED_BY,
            drm.UPDATED_TIMESTAMP
        FROM 
            dashboard_role_master AS drm
        LEFT JOIN 
            dashboard_menu_master AS dmm
            ON dmm.MENU_ID = drm.REDIRECT_URL;
    ELSE
        
        SELECT 
            ROLE_ID,
            ROLE_NAME
        FROM 
            dashboard_role_master
        WHERE 
            ((Parameters = 2 AND ROLE_ID IN (3, 4, 5, 6, 7, 8)) OR
            (Parameters = 4 AND ROLE_ID IN (5, 6, 7, 8)) OR
            (Parameters = 100 AND ROLE_ID IN (2, 3, 4, 5, 6, 7, 8)) OR
            (Parameters NOT IN (2, 4, 100) AND ROLE_ID = 0) AND IS_ACTIVE = 1); 
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SET_GLOBAL_LOCAL_INFILE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SET_GLOBAL_LOCAL_INFILE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SET_GLOBAL_LOCAL_INFILE`()
BEGIN
SET GLOBAL local_infile = 1;
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SKU_DETAILS_BY_SKU_ID_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SKU_DETAILS_BY_SKU_ID_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SKU_DETAILS_BY_SKU_ID_GET`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_sku_ids JSON;
    DECLARE p_info_type VARCHAR(100);  
    
    SET p_sku_ids   = JSON_EXTRACT(Parameters, '$.sku_ids');
    SET p_info_type = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.info_type'));
    
    IF p_info_type = 'sku_info' THEN
        CALL DSB_SKU_DETAILS_BY_SKU_ID_GET_SKU_INFO(p_sku_ids);
    ELSEIF p_info_type = 'sku_stock' THEN
        CALL DSB_SKU_DETAILS_BY_SKU_ID_GET_SKU_STOCK(p_sku_ids);
    ELSEIF p_info_type = 'sku_live_inventory_details' THEN
        CALL DSB_SKU_DETAILS_BY_SKU_ID_GET_LIVE_INVENTORY(p_sku_ids);
    ELSEIF p_info_type = 'sku_batch_details' THEN
        CALL DSB_SKU_DETAILS_BY_SKU_ID_GET_BATCH_DETAILS(p_sku_ids);
    ELSEIF p_info_type = 'sku_ean_details' THEN
        CALL DSB_SKU_DETAILS_BY_SKU_ID_GET_EAN_DETAILS(p_sku_ids);
    ELSE
        
        SELECT 
            0 AS Success, 
            CONCAT('Unsupported SKU info type: ', p_info_type) AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SKU_DETAILS_BY_SKU_ID_GET_BATCH_DETAILS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SKU_DETAILS_BY_SKU_ID_GET_BATCH_DETAILS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SKU_DETAILS_BY_SKU_ID_GET_BATCH_DETAILS`(IN p_sku_ids JSON)
BEGIN
    SELECT 
        sm.SKU_ID,
        sm.SKU_NAME,
        sbm.BATCH_ID, 
        sbm.MRP,
        DATE_FORMAT(sbm.EXPIRY_DATE, DSB_GET_DATE_FORMAT('DATE')) AS EXPIRY,
        sbm.GLN,
        sbm.INSERTED_TIMESTAMP,
        sbm.UPDATED_TIMESTAMP
    FROM 
        sku_batch_master sbm
    JOIN 
        sku_master sm ON sm.SKU_ID = sbm.SKU_ID
    WHERE sm.SKU_ID IN (
        SELECT sku_id
        FROM JSON_TABLE(
            p_sku_ids,
            '$[*]' COLUMNS (
                sku_id VARCHAR(100) PATH '$'
            )
        ) jt
    );
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SKU_DETAILS_BY_SKU_ID_GET_EAN_DETAILS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SKU_DETAILS_BY_SKU_ID_GET_EAN_DETAILS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SKU_DETAILS_BY_SKU_ID_GET_EAN_DETAILS`(
    IN p_sku_ids JSON
)
BEGIN
    SELECT
	sm.SKU_ID,
	sm.SKU_NAME,
        sem.EAN_ID, 
        sem.INSERTED_BY, 
        sem.INSERTED_TIMESTAMP, 
        sem.UPDATED_BY, 
        sem.UPDATED_TIMESTAMP
    FROM 
        sku_ean_mapping sem
    LEFT JOIN
        sku_master sm
        ON sem.SKU_ID = sm.SKU_ID
    WHERE sem.SKU_ID IN (
        SELECT jt.sku_id
        FROM JSON_TABLE(
            p_sku_ids,
            '$[*]' COLUMNS (
                sku_id VARCHAR(100) PATH '$'
            )
        ) jt
    );
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SKU_DETAILS_BY_SKU_ID_GET_LIVE_INVENTORY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SKU_DETAILS_BY_SKU_ID_GET_LIVE_INVENTORY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SKU_DETAILS_BY_SKU_ID_GET_LIVE_INVENTORY`(
    IN p_sku_ids JSON
)
BEGIN
    SELECT 
	sbm.SKU_ID,
	sm.SKU_NAME,
        liv.BIN_ID,
        liv.SEGMENT_NO,
        liv.QUANTITY, 
        sbm.MRP
    FROM 
        live_inventory_master liv
    LEFT JOIN 
        sku_batch_master sbm 
        ON sbm.SKU_ID = liv.ARTICLE_ID 
        AND sbm.BATCH_ID = liv.BATCH_ID
        
    LEFT JOIN 
	sku_master sm
	ON sbm.SKU_ID = sm.SKU_ID
        WHERE 
        liv.QUANTITY > 0
        AND liv.ARTICLE_ID IN (
            SELECT jt.sku_id
            FROM JSON_TABLE(
                p_sku_ids,
                '$[*]' COLUMNS (
                    sku_id VARCHAR(100) PATH '$'
                )
            ) jt
        )
    ORDER BY liv.UPDATED_TIMESTAMP DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SKU_DETAILS_BY_SKU_ID_GET_SKU_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SKU_DETAILS_BY_SKU_ID_GET_SKU_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SKU_DETAILS_BY_SKU_ID_GET_SKU_INFO`(
    IN p_sku_ids JSON
)
BEGIN
    SELECT 
        sm.SKU_ID,
        sm.SKU_NAME,
        sm.VELOCITY,
        sm.CATEGORY,
        cm.CATEGORY_NAME,
        sm.MIN_SEGMENT_SIZE, 
        sm.MAX_QUANTITY_PER_SEGMENT, 
        sm.HEIGHT,
        sm.LENGTH, 
        sm.WIDTH,
        sm.WEIGHT_OF_EACH_SKU,
        DSB_NORMALIZE_SKU_IMAGE_URL(sm.IMAGE_URL) AS IMAGE_URL
    FROM 
        sku_master sm
    LEFT JOIN 
        category_master cm ON cm.CATEGORY_ID = sm.CATEGORY
    WHERE sm.SKU_ID IN (
        SELECT sku_id
        FROM JSON_TABLE(
            p_sku_ids,
            '$[*]' COLUMNS (
                sku_id VARCHAR(100) PATH '$'
            )
        ) jt
    );
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SKU_DETAILS_BY_SKU_ID_GET_SKU_STOCK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SKU_DETAILS_BY_SKU_ID_GET_SKU_STOCK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SKU_DETAILS_BY_SKU_ID_GET_SKU_STOCK`(
    IN p_sku_ids JSON
)
BEGIN
    SELECT 
        sm.SKU_ID,
        sm.SKU_NAME,
        IFNULL(SUM(liv.QUANTITY), 0) AS TOTAL_QUANTITY
    FROM 
        sku_master sm
    LEFT JOIN 
        live_inventory_master liv 
        ON liv.ARTICLE_ID = sm.SKU_ID
    WHERE sm.SKU_ID IN (
        SELECT sku_id
        FROM JSON_TABLE(
            p_sku_ids,
            '$[*]' COLUMNS (
                sku_id VARCHAR(100) PATH '$'
            )
        ) jt
    )
    GROUP BY sm.SKU_ID, sm.SKU_NAME;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SKU_IMAGE_URL_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SKU_IMAGE_URL_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SKU_IMAGE_URL_GET`(IN Parameters JSON)
BEGIN
    
    DECLARE p_sku_id VARCHAR(100);
    DECLARE p_sku_name LONGTEXT;
    
    SET p_sku_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sku_id'));
    SET p_sku_name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.sku_name'));
    
    IF p_sku_id IS NOT NULL AND p_sku_id <> ''
       AND p_sku_name IS NOT NULL AND p_sku_name <> '' THEN
        
        SELECT DSB_NORMALIZE_SKU_IMAGE_URL(IMAGE_URL) AS IMAGE_URL FROM sku_master 
        WHERE SKU_ID = p_sku_id AND SKU_NAME = p_sku_name;
    ELSEIF p_sku_id IS NOT NULL AND p_sku_id <> '' THEN
        
        SELECT DSB_NORMALIZE_SKU_IMAGE_URL(IMAGE_URL) AS IMAGE_URL FROM sku_master 
        WHERE SKU_ID = p_sku_id;
    ELSEIF p_sku_name IS NOT NULL AND p_sku_name <> '' THEN
        
        SELECT DSB_NORMALIZE_SKU_IMAGE_URL(IMAGE_URL) AS IMAGE_URL FROM sku_master 
        WHERE SKU_NAME = p_sku_name;
    ELSE
        
        SELECT 0 AS Success, 'SKU ID/SKU NAME can not be empty' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SR_DETAILS_BY_SR_ID_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SR_DETAILS_BY_SR_ID_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_SR_DETAILS_BY_SR_ID_GET`(
  IN Parameters JSON
)
BEGIN
  
  DECLARE p_storage_request_id VARCHAR(100);
  DECLARE p_info_type          VARCHAR(100);

  
  SET p_storage_request_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.storage_request_id'));
  SET p_info_type          = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.info_type'));

  
  IF p_info_type = 'storage_request_info' THEN
    CALL `DSB_SR_DETAILS_BY_SR_ID_GET_STORAGE_REQUEST_INFO`(p_storage_request_id);

  ELSEIF p_info_type = 'bin_transfer_info' THEN
    CALL `DSB_SR_DETAILS_BY_SR_ID_GET_BIN_TRANSFER_INFO`(p_storage_request_id);

  ELSEIF p_info_type = 'stock_adjustment_info' THEN
    CALL `DSB_SR_DETAILS_BY_SR_ID_GET_STOCK_ADJUSTMENT_INFO`(p_storage_request_id);

  ELSEIF p_info_type = 'pallet_status_info' THEN
    CALL `DSB_SR_DETAILS_BY_SR_ID_GET_PALLET_STATUS_INFO`(p_storage_request_id);

  ELSE
    
    SELECT
      0 AS `Success`,
      CONCAT('Unsupported Storage Request info type: ', p_info_type) AS `Result`;
  END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SR_DETAILS_BY_SR_ID_GET_BIN_TRANSFER_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SR_DETAILS_BY_SR_ID_GET_BIN_TRANSFER_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_SR_DETAILS_BY_SR_ID_GET_BIN_TRANSFER_INFO`(
    IN p_storage_request_id VARCHAR(100)
)
BEGIN
    
    DROP TEMPORARY TABLE IF EXISTS tmp_put_payloads;
    CREATE TEMPORARY TABLE tmp_put_payloads (
        BIN_TRANSFER_PAYLOAD_ID VARCHAR(50) PRIMARY KEY,
        STORAGE_ID              VARCHAR(50),
        PUT_QUANTITY            INT
    );

    INSERT IGNORE INTO tmp_put_payloads (BIN_TRANSFER_PAYLOAD_ID, STORAGE_ID, PUT_QUANTITY)
    SELECT BIN_TRANSFER_PAYLOAD_ID, STORAGE_ID, PUT_QUANTITY
    FROM put_wave_order_master
    WHERE STORAGE_REQUEST_ID = p_storage_request_id
      AND BIN_TRANSFER_PAYLOAD_ID IS NOT NULL;

    INSERT IGNORE INTO tmp_put_payloads (BIN_TRANSFER_PAYLOAD_ID, STORAGE_ID, PUT_QUANTITY)
    SELECT BIN_TRANSFER_PAYLOAD_ID, STORAGE_ID, PUT_QUANTITY
    FROM put_wave_order_master_archive
    WHERE STORAGE_REQUEST_ID = p_storage_request_id
      AND BIN_TRANSFER_PAYLOAD_ID IS NOT NULL;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_live;
    CREATE TEMPORARY TABLE tmp_live AS
    SELECT
        DSB_STATUS_FROM_IS_PROCESSED(w.IS_PROCESSED) AS STATUS,
        w.PAYLOAD_ID                AS IDEMPOTENCY_KEY,
        p.STORAGE_ID,
        w.JSON_REQUEST,
        w.JSON_RESPONSE,
        p.PUT_QUANTITY,
        w.HTTP_STATUS,
        w.NO_OF_ATTEMPTS,
        w.INSERTED_TIMESTAMP,
        w.PROCESSED_TIMESTAMP
    FROM tmp_put_payloads p
    INNER JOIN wcs_to_wms_payload w
        ON w.PAYLOAD_ID = p.BIN_TRANSFER_PAYLOAD_ID;

    
    DROP TEMPORARY TABLE IF EXISTS tmp_archive;
    CREATE TEMPORARY TABLE tmp_archive AS
    SELECT
        DSB_STATUS_FROM_IS_PROCESSED(wa.IS_PROCESSED) AS STATUS,
        wa.PAYLOAD_ID               AS IDEMPOTENCY_KEY,
        p.STORAGE_ID,
        wa.JSON_REQUEST,
        wa.JSON_RESPONSE,
        p.PUT_QUANTITY,
        wa.HTTP_STATUS,
        wa.NO_OF_ATTEMPTS,
        wa.INSERTED_TIMESTAMP,
        wa.PROCESSED_TIMESTAMP
    FROM tmp_put_payloads p
    INNER JOIN wcs_to_wms_payload_archive wa
        ON wa.PAYLOAD_ID = p.BIN_TRANSFER_PAYLOAD_ID;

    
    SELECT *
    FROM (
        SELECT * FROM tmp_live
        UNION ALL
        SELECT * FROM tmp_archive
    ) AS combined
    ORDER BY INSERTED_TIMESTAMP DESC;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SR_DETAILS_BY_SR_ID_GET_PALLET_STATUS_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SR_DETAILS_BY_SR_ID_GET_PALLET_STATUS_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_SR_DETAILS_BY_SR_ID_GET_PALLET_STATUS_INFO`(
  IN p_storage_request_id VARCHAR(100)
)
BEGIN
  
  DROP TEMPORARY TABLE IF EXISTS `tmp_put_payloads`;
  CREATE TEMPORARY TABLE `tmp_put_payloads` (
    `Id`                INT AUTO_INCREMENT PRIMARY KEY,
    `PALLET_STATUS_ID`  VARCHAR(50)
  );

  
  INSERT IGNORE INTO `tmp_put_payloads` (`PALLET_STATUS_ID`)
  SELECT `PALLET_COMPLETION_PAYLOAD_ID`
  FROM `wms_to_wcs_storage_request_pallet_data`
  WHERE `STORAGE_REQUEST_ID` = p_storage_request_id
    AND `PALLET_COMPLETION_PAYLOAD_ID` IS NOT NULL;

  INSERT IGNORE INTO `tmp_put_payloads` (`PALLET_STATUS_ID`)
  SELECT `PALLET_SCANNED_PAYLOAD_ID`
  FROM `wms_to_wcs_storage_request_pallet_data`
  WHERE `STORAGE_REQUEST_ID` = p_storage_request_id
    AND `PALLET_SCANNED_PAYLOAD_ID` IS NOT NULL;

  
  INSERT IGNORE INTO `tmp_put_payloads` (`PALLET_STATUS_ID`)
  SELECT `PALLET_COMPLETION_PAYLOAD_ID`
  FROM `wms_to_wcs_storage_request_pallet_data_archive`
  WHERE `STORAGE_REQUEST_ID` = p_storage_request_id
    AND `PALLET_COMPLETION_PAYLOAD_ID` IS NOT NULL;

  INSERT IGNORE INTO `tmp_put_payloads` (`PALLET_STATUS_ID`)
  SELECT `PALLET_SCANNED_PAYLOAD_ID`
  FROM `wms_to_wcs_storage_request_pallet_data_archive`
  WHERE `STORAGE_REQUEST_ID` = p_storage_request_id
    AND `PALLET_SCANNED_PAYLOAD_ID` IS NOT NULL;

  
  DROP TEMPORARY TABLE IF EXISTS `tmp_live`;
  CREATE TEMPORARY TABLE `tmp_live` AS
  SELECT
    DSB_STATUS_FROM_IS_PROCESSED(w.IS_PROCESSED) AS STATUS,
    w.`PAYLOAD_ID`              AS `IDEMPOTENCY_KEY`,
    w.`JSON_REQUEST`,
    w.`JSON_RESPONSE`,
    w.`HTTP_STATUS`,
    w.`NO_OF_ATTEMPTS`,
    w.`INSERTED_TIMESTAMP`,
    w.PROCESSED_TIMESTAMP
  FROM `tmp_put_payloads` AS p
  INNER JOIN `wcs_to_wms_payload` AS w
          ON w.`PAYLOAD_ID` = p.`PALLET_STATUS_ID`;

  DROP TEMPORARY TABLE IF EXISTS `tmp_archive`;
  CREATE TEMPORARY TABLE `tmp_archive` AS
  SELECT
    DSB_STATUS_FROM_IS_PROCESSED(wa.IS_PROCESSED) AS STATUS,
    wa.`PAYLOAD_ID`             AS `IDEMPOTENCY_KEY`,
    wa.`JSON_REQUEST`,
    wa.`JSON_RESPONSE`,
    wa.`HTTP_STATUS`,
    wa.`NO_OF_ATTEMPTS`,
    wa.`INSERTED_TIMESTAMP`,
    wa.PROCESSED_TIMESTAMP
  FROM `tmp_put_payloads` AS p
  INNER JOIN `wcs_to_wms_payload_archive` AS wa
          ON wa.`PAYLOAD_ID` = p.`PALLET_STATUS_ID`;

  
  SELECT *
  FROM (
    SELECT * FROM `tmp_live`
    UNION ALL
    SELECT * FROM `tmp_archive`
  ) AS `combined`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SR_DETAILS_BY_SR_ID_GET_STOCK_ADJUSTMENT_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SR_DETAILS_BY_SR_ID_GET_STOCK_ADJUSTMENT_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_SR_DETAILS_BY_SR_ID_GET_STOCK_ADJUSTMENT_INFO`(
  IN p_storage_request_id VARCHAR(100)
)
BEGIN
  
DROP TEMPORARY TABLE IF EXISTS `tmp_put_payloads`;
CREATE TEMPORARY TABLE `tmp_put_payloads` (
  `Id` INT AUTO_INCREMENT PRIMARY KEY,
  `STOCK_ADJUSTMENT_PAYLOAD_ID` VARCHAR(50),
  `STORAGE_ID` VARCHAR(50),
  `STOCK_ADJUSTMENT_QUANTITY` INT
);
 

INSERT IGNORE INTO `tmp_put_payloads` (`STOCK_ADJUSTMENT_PAYLOAD_ID`, `STORAGE_ID`, `STOCK_ADJUSTMENT_QUANTITY`)
SELECT `STOCK_ADJUSTMENT_PAYLOAD_ID`, `STORAGE_ID`, `STOCK_ADJUSTMENT_QUANTITY`
FROM `wms_to_wcs_storage_request_data`
WHERE `STORAGE_REQUEST_ID` = p_storage_request_id
  AND `STOCK_ADJUSTMENT_PAYLOAD_ID` IS NOT NULL
  AND `STOCK_ADJUSTMENT_PAYLOAD_ID` <> 'not_required';
 
INSERT IGNORE INTO `tmp_put_payloads` (`STOCK_ADJUSTMENT_PAYLOAD_ID`, `STORAGE_ID`, `STOCK_ADJUSTMENT_QUANTITY`)
SELECT `STOCK_ADJUSTMENT_PAYLOAD_ID`, `STORAGE_ID`, `STOCK_ADJUSTMENT_QUANTITY`
FROM `wms_to_wcs_storage_request_data_archive`
WHERE `STORAGE_REQUEST_ID` = p_storage_request_id
  AND `STOCK_ADJUSTMENT_PAYLOAD_ID` IS NOT NULL
  AND `STOCK_ADJUSTMENT_PAYLOAD_ID` <> 'not_required';
 

DROP TEMPORARY TABLE IF EXISTS `tmp_live`;
CREATE TEMPORARY TABLE `tmp_live` AS
SELECT
  DSB_STATUS_FROM_IS_PROCESSED(w.IS_PROCESSED) AS STATUS,
  w.`PAYLOAD_ID`      AS `IDEMPOTENCY_KEY`,
  p.`STORAGE_ID`,
  w.`JSON_REQUEST`,
  w.`JSON_RESPONSE`,
  p.`STOCK_ADJUSTMENT_QUANTITY`,
  w.`HTTP_STATUS`,
  w.`NO_OF_ATTEMPTS`,
  w.`INSERTED_TIMESTAMP`,
  w.PROCESSED_TIMESTAMP
FROM `tmp_put_payloads` AS p
INNER JOIN `wcs_to_wms_payload` AS w
        ON w.`PAYLOAD_ID` = p.`STOCK_ADJUSTMENT_PAYLOAD_ID`;
 
DROP TEMPORARY TABLE IF EXISTS `tmp_archive`;
CREATE TEMPORARY TABLE `tmp_archive` AS
SELECT
  DSB_STATUS_FROM_IS_PROCESSED(wa.IS_PROCESSED) AS STATUS,
  wa.`PAYLOAD_ID`     AS `IDEMPOTENCY_KEY`,
  p.`STORAGE_ID`,
  wa.`JSON_REQUEST`,
  wa.`JSON_RESPONSE`,
  p.`STOCK_ADJUSTMENT_QUANTITY`,
  wa.`HTTP_STATUS`,
  wa.`NO_OF_ATTEMPTS`,
  wa.`INSERTED_TIMESTAMP`,
  wa.PROCESSED_TIMESTAMP
FROM `tmp_put_payloads` AS p
INNER JOIN `wcs_to_wms_payload_archive` AS wa
        ON wa.`PAYLOAD_ID` = p.`STOCK_ADJUSTMENT_PAYLOAD_ID`;
 

SELECT *
FROM (
  SELECT * FROM `tmp_live`
  UNION ALL
  SELECT * FROM `tmp_archive`
) AS `combined`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SR_DETAILS_BY_SR_ID_GET_STORAGE_REQUEST_INFO` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SR_DETAILS_BY_SR_ID_GET_STORAGE_REQUEST_INFO` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`localhost` PROCEDURE `DSB_SR_DETAILS_BY_SR_ID_GET_STORAGE_REQUEST_INFO`(
  IN p_storage_request_id VARCHAR(100)
)
BEGIN
  
  DROP TEMPORARY TABLE IF EXISTS `tmp_put_payloads`;
  CREATE TEMPORARY TABLE `tmp_put_payloads` (
    `STORAGE_RECEIVED_PAYLOAD_ID` VARCHAR(100) PRIMARY KEY
  );

  
  INSERT IGNORE INTO `tmp_put_payloads` (`STORAGE_RECEIVED_PAYLOAD_ID`)
  SELECT `pallet_received_payload_id`
  FROM `wms_to_wcs_storage_request_pallet_data`
  WHERE `STORAGE_REQUEST_ID` = p_storage_request_id
    AND `pallet_received_payload_id` IS NOT NULL;

  INSERT IGNORE INTO `tmp_put_payloads` (`STORAGE_RECEIVED_PAYLOAD_ID`)
  SELECT `pallet_received_payload_id`
  FROM `wms_to_wcs_storage_request_pallet_data_archive`
  WHERE `STORAGE_REQUEST_ID` = p_storage_request_id
    AND `pallet_received_payload_id` IS NOT NULL;

  
  SELECT 
  
  p.`STORAGE_RECEIVED_PAYLOAD_ID`
  FROM `tmp_put_payloads` AS p
  WHERE EXISTS (
          SELECT 1
          FROM `wcs_to_wms_payload` AS w
          WHERE w.`payload_id` = p.`STORAGE_RECEIVED_PAYLOAD_ID`
        )
     OR EXISTS (
          SELECT 1
          FROM `wcs_to_wms_payload_archive` AS wa
          WHERE wa.`payload_id` = p.`STORAGE_RECEIVED_PAYLOAD_ID`
        )
  ORDER BY p.`STORAGE_RECEIVED_PAYLOAD_ID`;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_STATIONS_BOTS_COUNT_VISIBLITY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_STATIONS_BOTS_COUNT_VISIBLITY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_STATIONS_BOTS_COUNT_VISIBLITY`()
BEGIN
		SELECT
		wsrm.STATION_ID,
		wsrm.BOT_COUNT_CURRENT AS ALLOCATION_ENGINE_BOT_COUNT,
		SUM(CASE WHEN (obm.TYPE = 'station_pick' AND obm.STATUS = 'TASK_COMPLETED') OR (obm.BOT_ID IS NULL) THEN 0 ELSE 1 END) AS CURRENT_BOT_COUNT,
		SUM(CASE WHEN obm.TYPE = 'rack_pick' AND obm.BOT_ID IS NOT NULL THEN 1 ELSE 0 END) AS RACK_PICK_BOT_ASSIGNED,
		SUM(CASE WHEN obm.TYPE = 'station_pick' AND obm.`STATUS` NOT IN ('TASK_COMPLETED') AND obm.BOT_ID IS NOT NULL THEN 1 ELSE 0 END) AS STATION_PICK_BOT_ASSIGNED,		
		SUM(CASE WHEN obm.TYPE = 'rack_pick' AND obm.BOT_ID IS NULL THEN 1 ELSE 0 END) AS RACK_PICK_PENDING,
		SUM(CASE WHEN obm.TYPE = 'station_pick' AND obm.`STATUS` NOT IN ('TASK_COMPLETED') AND obm.BOT_ID IS NULL THEN 1 ELSE 0 END) AS STATION_PICK_PENDING
		
		
		
		FROM wave_station_rule_mapping AS wsrm
		INNER JOIN order_bin_mapping AS obm
		ON obm.STATION_ID = wsrm.STATION_ID
		
		GROUP BY wsrm.STATION_ID, wsrm.BOT_COUNT_CURRENT
		ORDER BY wsrm.STATION_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_STATIONS_RECOMMENDATIONS_GET_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_STATIONS_RECOMMENDATIONS_GET_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_STATIONS_RECOMMENDATIONS_GET_FEEDBACK`(
    IN Parameters JSON
)
BEGIN
    DECLARE p_rule_id INT;
    
    
    SET p_rule_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.rule_id')) AS UNSIGNED);

    
    SELECT *
    FROM picklist_split_order_master
    WHERE RULE_ID = p_rule_id AND IS_PROCESSED = "2"
    ORDER BY INSERTED_TIMESTAMP DESC
    LIMIT 1;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_STATIONS_RECOMMENDATIONS_VIEW` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_STATIONS_RECOMMENDATIONS_VIEW` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_STATIONS_RECOMMENDATIONS_VIEW`(
    IN Parameters JSON
)
BEGIN
    DECLARE v_rule_id INT;
    DECLARE v_user_name VARCHAR(50);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        CALL DSB_GENERIC_TRANSACTION_ERROR_HANDLER();
    END;

    
    SET v_rule_id  = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.rule_id')) AS UNSIGNED);
    SET v_user_name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_name'));

    START TRANSACTION;
    
    
    INSERT INTO picklist_split_order_master
    (
        RULE_ID,
        IS_PROCESSED,
        PRIORITY,
        INSERTED_BY,
        INSERTED_TIMESTAMP
    )
    VALUES
    (
        v_rule_id,
        "0",
        'INITIAL',
        v_user_name,
        NOW()
    );

    
    INSERT INTO picklist_split_station_pref
    (
        RULE_ID,
        STATION_ID,
        IS_PROCESSED,
        PRIORITY,
        INSERTED_BY,
        INSERTED_TIMESTAMP
    )
    SELECT
        v_rule_id,
        jt.station_id,
        "0",
        'INITIAL',
        v_user_name,
        NOW()
    FROM JSON_TABLE(
            Parameters,
            '$.station_ids[*]'
            COLUMNS (
                station_id INT PATH '$'
            )
         ) AS jt;

    COMMIT;

    
    SELECT 
        1 AS Success,
        'Picklist split rule created successfully' AS Result;

END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_STATION_WAVE_ORDER_MASTER_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_STATION_WAVE_ORDER_MASTER_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_STATION_WAVE_ORDER_MASTER_FEEDBACK`(
    IN p_station_id VARCHAR(50),
    IN p_wave_id    VARCHAR(50),
    IN p_wave_type  VARCHAR(50)
)
BEGIN
    IF p_wave_type = 'PICK' THEN
        SELECT *
        FROM pick_wave_order_master
        WHERE STATUS NOT IN ('ORDER_COMPLETED')
          AND STATION_ID = p_station_id
          AND WAVE_ID = p_wave_id;
    ELSEIF p_wave_type = 'PUT' THEN
        SELECT *
        FROM put_wave_order_master
        WHERE STATUS NOT IN ('PUT_COMPLETED', 'INVENTORY_UPDATED')
          AND STATION_ID = p_station_id
          AND WAVE_ID = p_wave_id;
    ELSEIF p_wave_type = 'BIN_LOADING' THEN
        SELECT *
        FROM bin_loading_wave_order_master
        WHERE STATUS NOT IN ('BIN_MOVED', 'BIN_REGISTRATION_COMPLETED')
          AND STATION_ID = p_station_id
          AND WAVE_ID = p_wave_id;
    ELSE
        SELECT 
            0 AS Success, 
            'Wrong Wave Type' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_STATION_WAVE_PENDING_SYNC_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_STATION_WAVE_PENDING_SYNC_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_STATION_WAVE_PENDING_SYNC_FEEDBACK`(
    IN p_station_id VARCHAR(50),
    IN p_wave_id    VARCHAR(50),
    IN p_wave_type  VARCHAR(50)
)
BEGIN
    IF p_wave_type = 'PUT' THEN
        SELECT 
            wwp.IDEMPOTENCY_KEY,
            pwom.STORAGE_ID,
            pwom.EXPECTED_QUANTITY,
            pwom.PUT_QUANTITY,
            pwom.SHORT_PUT_QUANTITY,
            wwp.JSON_REQUEST,
            wwp.JSON_RESPONSE,
            wwp.HTTP_STATUS
        FROM put_wave_order_master pwom
        LEFT JOIN wcs_to_wms_payload wwp
            ON pwom.BIN_TRANSFER_PAYLOAD_ID = wwp.PAYLOAD_ID
        WHERE pwom.WAVE_ID = p_wave_id
          AND wwp.HTTP_STATUS <> 200
          AND wwp.IS_PROCESSED = 0;
    ELSE
        SELECT 
            0 AS Success, 
            'Wrong Wave Type' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_STATION_WAVE_STATUS_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_STATION_WAVE_STATUS_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_STATION_WAVE_STATUS_FEEDBACK`(IN Parameters JSON)
BEGIN
    DECLARE p_station_id    INT;
    DECLARE p_wave_type     VARCHAR(20);
    DECLARE p_feedback_type VARCHAR(50);
    DECLARE p_wave_id       VARCHAR(50);
    
    SET p_feedback_type = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.feedback_type'));
    SET p_wave_id       = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
    SET p_station_id    = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
    SET p_wave_type     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_type'));
    IF p_feedback_type = 'order-master' THEN
        CALL DSB_STATION_WAVE_ORDER_MASTER_FEEDBACK(p_station_id, p_wave_id, p_wave_type);
    ELSEIF p_feedback_type = 'pending-sync' THEN
        CALL DSB_STATION_WAVE_PENDING_SYNC_FEEDBACK(p_station_id, p_wave_id, p_wave_type);
    ELSE
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Invalid feedback_type value';
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_AUDIT_WAVE_BY_TIME` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_AUDIT_WAVE_BY_TIME` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_AUDIT_WAVE_BY_TIME`( IN StartTime DATETIME, IN EndTime DATETIME,IN Reason VARCHAR(255) )
BEGIN 
    SELECT p.BIN_ID AS BIN_ID, p.BIN_SEGMENT_NO AS SEGMENT_NO
    FROM pick_wave_order_master_archive p
    INNER JOIN short_pick_wave_reason t ON t.PICK_ORDER_ID = p.PICK_ORDER_ID
    WHERE t.INSERTED_TIMESTAMP > StartTime
      AND t.INSERTED_TIMESTAMP < EndTime
      AND t.Reason = Reason
     GROUP BY p.BIN_ID, p.BIN_SEGMENT_NO;
         
         
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_GET_STOCK_AUDIT_UPLOAD_DETAIL_BY_WAVE_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_GET_STOCK_AUDIT_UPLOAD_DETAIL_BY_WAVE_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_GET_STOCK_AUDIT_UPLOAD_DETAIL_BY_WAVE_ID`(IN WaveId varchar(200))
BEGIN
   
    SELECT A.`WAVE_ID` AS 'WAVE ID',A.`BIN_ID` AS 'BIN ID',A.`BIN_SEGMENT_NO` AS 'BIN SEGMENT NO',A.`SKU_ID` AS 'SKU ID',A.`BATCH_ID` AS 'BATCH ID'
    FROM `stock_audit_wave_wms_data` AS A 
    INNER JOIN `dashboard_wave_upload_status` AS B ON A.`WAVE_ID`=B.`WAVE_ID`
    WHERE B.`CLIENT_WAVE_ID` = WaveId AND B.IS_ACTIVE=1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_KNOW_YOUR_SKU_NAME_BY_PATTERN` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_KNOW_YOUR_SKU_NAME_BY_PATTERN` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_KNOW_YOUR_SKU_NAME_BY_PATTERN`(IN Parameters VARCHAR(255))
BEGIN
    DECLARE input VARCHAR(200);
    SET input = Parameters;
    SELECT 
        SKU_NAME
    FROM 
        sku_master
    WHERE 
        SKU_NAME LIKE CONCAT('%', input, '%') 
        OR SKU_ID like CONCAT('%', input, '%');
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_LPN_DATA_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_LPN_DATA_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_LPN_DATA_GET`( )
BEGIN 
  DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found';
    
    select LPN_ID as 'LPN ID',
    `STATION_ID` as 'STATION ID', 
    `LPN_BARCODE` as 'LPN BARCODE',
    `LPN_REASON` as 'LPN REASON',
    DATE_FORMAT(`LPN_OPEN_TIMESTAMP`, '%b %e, %Y, %r') AS 'LPN CLOSE TIME', 
    DATE_FORMAT(`LPN_CLOSE_TIMESTAMP`, '%b %e, %Y, %r') AS 'LPN OPEN TIME' 
    
    from `lpn_master_stock_audit`;
    
    
   SELECT Success, Result;
    
         
         
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_LPN_DATA_INSERT_BY_STATION_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_LPN_DATA_INSERT_BY_STATION_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_LPN_DATA_INSERT_BY_STATION_ID`(IN Parameters JSON)
BEGIN
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found';
    DECLARE stationId VARCHAR(50);
    DECLARE Reason VARCHAR(50);
    DECLARE LpnBarcode VARCHAR(100);
    DECLARE LpnId INT DEFAULT 0;
    DECLARE reasonCount INT DEFAULT 0;
    DECLARE lpnCount INT DEFAULT 0;
    
    SET LpnId = CAST(Parameters->>'$.LpnId' AS UNSIGNED);
    SET stationId = Parameters->>'$.StationId';
    SET Reason = Parameters->>'$.Reason';
    SET LpnBarcode = Parameters->>'$.LpnBarcode';
    
    IF LpnId = 0 THEN
        
        IF Reason NOT IN ('Incorrect SKU', 'Incorrect Batch', 'Expired Quantity', 'Damaged Quantity') THEN
            SET Result = 'Reason not defined in the system';
        ELSE
            
            SELECT COUNT(*) INTO reasonCount
            FROM `lpn_master_stock_audit`
            WHERE `LPN_REASON` = Reason
              AND `LPN_BARCODE` = LpnBarcode
              AND `STATION_ID` = stationId;
            IF reasonCount > 0 THEN
                SET Result = 'Reason already exists for this LPN and Station';
            ELSE
                
                INSERT INTO `lpn_master_stock_audit` (`STATION_ID`, `LPN_BARCODE`, `LPN_REASON`)
                VALUES (stationId, LpnBarcode, Reason);
                SET Success = 1;
                SET Result = 'Insertion Completed';
            END IF;
        END IF;
    ELSE
        
        SELECT COUNT(*) INTO lpnCount FROM `lpn_master_stock_audit` WHERE `LPN_ID` = LpnId;
        IF lpnCount = 0 THEN
            SET Result = 'LPN ID not found';
        ELSE
            
            UPDATE `lpn_master_stock_audit`
            SET `LPN_BARCODE` = LpnBarcode
            WHERE `LPN_ID` = LpnId;
            SET Success = 1;
            SET Result = 'Update Completed';
        END IF;
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_LPN_DATA_UPDATE_BY_LPN_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_LPN_DATA_UPDATE_BY_LPN_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_LPN_DATA_UPDATE_BY_LPN_ID`( IN Parameters JSON )
BEGIN 
    DECLARE Success INT DEFAULT 0;
    DECLARE Result VARCHAR(100) DEFAULT 'No Data Found';
    DECLARE LpnId INT;  
    DECLARE LpnBarcode VARCHAR(100);
    DECLARE lpnCount INT DEFAULT 0;  
    
    SET LpnId = Parameters->>'$.LpnId';
    SET LpnBarcode = Parameters->>'$.LpnBarcode';
    
    SELECT COUNT(*) INTO lpnCount FROM `lpn_master_stock_audit` WHERE `LPN_ID` = LpnId;
    IF lpnCount = 0 THEN
        SET Result = 'Lpn ID not found';
    ELSE
        
        UPDATE `lpn_master_stock_audit`
        SET `LPN_BARCODE` = LpnBarcode
        WHERE `LPN_ID` = LpnId;
        SET Success = 1;
        SET Result = 'Update Completed';
    END IF;
    
    SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_STATION_OVERVIEW` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_STATION_OVERVIEW` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_STATION_OVERVIEW`()
BEGIN
    SELECT 
        
        hsm.STATUS AS STATION_STATUS,
        hsm.STATION_ID,
        hsm.STATION_ALIAS_NAME,
        
        wm.WAVE_TYPE,
        wm.WAVE_STATUS AS WM_WAVE_STATUS,
        
        CASE 
            WHEN wm.IS_CANCELLED = 1 THEN 'SUSPENSION_INITIATED'
            WHEN wm.IS_STOPPED = 1 THEN 'COMPLETION_INITIATED'
            ELSE hsm.WAVE_STATUS
        END AS HSM_WAVE_STATUS,
        
        wrsm.BOT_COUNT_DEFAULT,
        wrsm.BOT_COUNT_CURRENT,
        hsm.MAX_BUFFER_COUNT AS STATION_BUFFER_COUNT,
        hsm.WAVE_ID,
        wm.LEFT_OVER_STATUS,
        wm.START_TIMESTAMP,
        wm.STARTED_BY,
        wm.IS_CANCELLED,
        wm.CANCELLED_TIMESTAMP,
        wm.CANCELLED_BY,
        wm.IS_STOPPED,
        wm.COMPLETED_TIMESTAMP,
        wm.COMPLETED_BY,
        
        CASE 
            WHEN wm.WAVE_TYPE = 'PICK' THEN wrsm.PICK_RULE_ID_DEFAULT
            ELSE 0
        END AS PICK_RULE_ID_DEFAULT,
        CASE 
            WHEN wm.WAVE_TYPE = 'PICK' THEN prm_d.RULE_NAME
            ELSE ''
        END AS PICK_RULE_NAME_DEFAULT,
        CASE 
            WHEN wm.WAVE_TYPE = 'PICK' THEN wrsm.PICK_RULE_ID_CURRENT
            ELSE 0
        END AS PICK_RULE_ID_CURRENT,
        CASE 
            WHEN wm.WAVE_TYPE = 'PICK' THEN prm_c.RULE_NAME
            ELSE ''
        END AS PICK_RULE_NAME_CURRENT,
        CASE 
            WHEN wm.WAVE_TYPE = 'PICK' THEN (SELECT DSB_FILTER_CONDITION FROM pick_rule_master WHERE PICK_RULE_ID = wrsm.PICK_RULE_ID_CURRENT)
            ELSE ''
        END AS PICK_RULE_DSB_FILTER_CONDITION_CURRENT,        
        CASE 
            WHEN wm.WAVE_TYPE = 'PICK' THEN (SELECT DSB_FILTER_JSON FROM pick_rule_master WHERE PICK_RULE_ID = wrsm.PICK_RULE_ID_CURRENT)
            ELSE ''
        END AS PICK_RULE_JSON
    FROM hw_station_master hsm
    LEFT JOIN wave_master wm 
        ON wm.WAVE_ID = hsm.WAVE_ID
    LEFT JOIN dashboard_user_master dum 
        ON dum.USER_NAME = hsm.LOGGED_IN_USER_ID
    LEFT JOIN dashboard_user_role_setting_mapping dursm 
        ON dursm.USER_ID = dum.USER_ID
    LEFT JOIN wave_station_rule_mapping wrsm 
        ON wrsm.STATION_ID = hsm.STATION_ID
    LEFT JOIN pick_rule_master prm_d 
        ON prm_d.PICK_RULE_ID = wrsm.PICK_RULE_ID_DEFAULT
    LEFT JOIN pick_rule_master prm_c 
        ON prm_c.PICK_RULE_ID = wrsm.PICK_RULE_ID_CURRENT
    WHERE hsm.STATUS IN ('ENABLED', 'DISABLED')
    GROUP BY hsm.STATION_ID;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_STOCK_AUDIT_BIN_ID_AND_SEGMENTS_GET_AUDIT_WAVE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_STOCK_AUDIT_BIN_ID_AND_SEGMENTS_GET_AUDIT_WAVE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_STOCK_AUDIT_BIN_ID_AND_SEGMENTS_GET_AUDIT_WAVE`(IN BinId INT, IN segmentNo INT)
BEGIN 
	SELECT 
	    lim.Bin_Id AS 'BIN ID', 
	    lim.SEGMENT_NO AS 'SEGMENT NO', 
           IFNULL(sm.SKU_NAME, 'No SKU') AS 'SKU NAME',  
           IFNULL(sbm.MRP, NULL) AS 'MRP',               
           IFNULL(DATE_FORMAT(sbm.EXPIRY_DATE, '%Y-%m-%d'), NULL) AS 'EXPIRY DATE'  
	FROM 
	 `live_inventory_master` lim INNER JOIN 
	 `sku_master` sm ON lim.ARTICLE_ID = sm.SKU_ID INNER JOIN 
	 `sku_batch_master` sbm ON sbm.BATCH_ID=lim.BATCH_ID
	  WHERE lim.BIN_ID=BinId AND lim.SEGMENT_NO= segmentNo;
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_STOCK_AUDIT_CREATE_WAVE_WMS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_STOCK_AUDIT_CREATE_WAVE_WMS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_STOCK_AUDIT_CREATE_WAVE_WMS`(IN Parameters JSON)
BEGIN
  DECLARE _validationFailed INT DEFAULT 0;
  DECLARE oldwaveId        VARCHAR(50);
  DECLARE newwaveId        VARCHAR(50);
  DECLARE userName         VARCHAR(50) DEFAULT 'Backend';
  DECLARE waveId           VARCHAR(50);
  DECLARE waveType         VARCHAR(50);
  DECLARE waveUniqueId     INT;
  DECLARE tableName        VARCHAR(20);
  DECLARE sqlQuery         VARCHAR(1000);
  DECLARE backendWaveId    VARCHAR(200);
  DECLARE Success          INT DEFAULT 1;                       
  DECLARE Result           VARCHAR(255) DEFAULT 'Upload Failed';
  
  SET oldwaveId = Parameters ->> '$.oldWaveId';
  SET newwaveId = Parameters ->> '$.newWaveId';
  SET userName  = Parameters ->> '$.userName';
  
  UPDATE dashboard_wave_upload_status
  SET CLIENT_WAVE_ID = newwaveId,
      WAVE_ID        = newwaveId
  WHERE WAVE_ID = oldwaveId;
  
  UPDATE stock_audit_wave_wms_data_dsb_temp
  SET WAVE_ID        = newwaveId
  WHERE WAVE_ID = oldwaveId;
  
  SELECT STATUS INTO Result
  FROM dashboard_wave_upload_status
  WHERE WAVE_ID = newwaveId;
  SELECT Result, Success;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_STOCK_AUDIT_WAVE_BY_TIME` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_STOCK_AUDIT_WAVE_BY_TIME` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_STOCK_AUDIT_WAVE_BY_TIME`( 
    IN StartTime DATETIME, 
    IN EndTime DATETIME,
    IN Reason VARCHAR(255) 
)
BEGIN 
    
    SELECT p.bin_id AS BIN_ID 
    FROM pick_wave_order_master p
    INNER JOIN short_pick_wave_reason t ON t.PICK_ORDER_ID = p.PICK_ORDER_ID
    WHERE t.INSERTED_TIMESTAMP > StartTime
      AND t.INSERTED_TIMESTAMP < EndTime
      AND t.Reason = Reason;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_WAVE_COMPLETION_FEEDBACK` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_WAVE_COMPLETION_FEEDBACK` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_WAVE_COMPLETION_FEEDBACK`(IN Parameters JSON)
BEGIN
  DECLARE p_station_id INT;
  DECLARE p_wave_type  VARCHAR(20);
  
  SET p_station_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.station_id')) AS UNSIGNED);
  SET p_wave_type  = UPPER(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_type')));
  
  IF NOT EXISTS (SELECT 1 FROM hw_station_master WHERE STATION_ID = p_station_id) THEN
    SELECT 0 AS Success, 'Station ID not found' AS Result;
  ELSE
    IF p_wave_type = 'PICK' THEN
      SELECT *
      FROM pick_wave_order_master
      WHERE STATUS NOT IN ('ORDER_COMPLETED')
        AND STATION_ID = p_station_id;
    ELSEIF p_wave_type = 'PUT' THEN
      SELECT *
      FROM put_wave_order_master
      WHERE STATUS NOT IN ('PUT_COMPLETED', 'INVENTORY_UPDATED')
        AND STATION_ID = p_station_id;
    ELSEIF p_wave_type = 'BIN_LOADING' THEN
      SELECT *
      FROM bin_loading_wave_order_master
      WHERE STATUS NOT IN ('BIN_MOVED', 'BIN_REGISTRATION_COMPLETED')
        AND STATION_ID = p_station_id;
    ELSE
      SELECT 0 AS Success, 'Wrong Wave Type' AS Result;
    END IF;
  END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SUPERVISOR_WAVE_LEFT_OVER_APPROVED_NOT_SELECTED` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SUPERVISOR_WAVE_LEFT_OVER_APPROVED_NOT_SELECTED` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SUPERVISOR_WAVE_LEFT_OVER_APPROVED_NOT_SELECTED`(IN parameter JSON)
BEGIN
	DECLARE wave VARCHAR(50);
	DECLARE waveType VARCHAR(50);
	DECLARE skuId VARCHAR(50);
	DECLARE mr_price VARCHAR(50);
	DECLARE expiry VARCHAR(50);
	DECLARE orderId VARCHAR(50);
	
    SET wave = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameter, '$.WAVE_ID')), '');
    SET waveType = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameter, '$.WAVE_TYPE')), '');
    SET skuId = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameter, '$.SKU_ID')), '');
    SET mr_price = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameter, '$.MRP')), '');
    SET expiry = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameter, '$.EXPIRY_DATE')), '');
    SET orderId = IFNULL(JSON_UNQUOTE(JSON_EXTRACT(parameter, '$.ORDER_ID')), '');
     
     IF waveType = 'PICK' THEN
        DELETE FROM pick_wave_wms_data 
        WHERE SKU_ID = skuId 
        AND ORDER_ID = orderId;
    ELSEIF waveType = 'PUT' THEN
        DELETE FROM put_wave_wms_data 
        WHERE MRP = mr_price 
        AND EXPIRY_DATE = expiry 
        AND SKU_ID = skuId 
        AND WAVE_ID = wave;
    END IF;
	
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_SWITCH_TO_MANUAL_MODE_BY_BOT_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_SWITCH_TO_MANUAL_MODE_BY_BOT_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_SWITCH_TO_MANUAL_MODE_BY_BOT_ID`(IN Parameters JSON)
BEGIN
  DECLARE Success            INT         DEFAULT 1;
  DECLARE Result             VARCHAR(255) DEFAULT '';
  DECLARE p_bot_id           VARCHAR(10);
  DECLARE p_manual_mode_bit  INT;
  DECLARE v_error_message    TEXT;

  
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    ROLLBACK;
    SELECT 0 AS Success, v_error_message AS Result;
  END;

  
  SET p_bot_id          = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.botId'));
  SET p_manual_mode_bit = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.manualModeBit')) AS SIGNED);

  START TRANSACTION;

  UPDATE teleoperation_bool_data
  SET
    `Z-Axis Jog Down`                   = 0,
    `Z-Axis Jog Up`                     = 0,
    `Z-Jog Operation Limits Overwrite Bit` = 0
  WHERE bot_id = p_bot_id;

  IF p_manual_mode_bit = 1 THEN
    
    UPDATE teleoperation_bool_data
    SET
      `Auto Mode`            = 0,
      `Manual Position Mode` = 1
    WHERE bot_id = p_bot_id;

    SET Success = 1;
    SET Result  = 'Switched to PLC Manual Mode (Manual Packet)';

  ELSEIF p_manual_mode_bit = 0 THEN
    
    UPDATE teleoperation_bool_data
    SET
      `Auto Mode`                    = 1,
      `Manual Position Mode`         = 0,
      `Rear Finger Actuator on/off`  = 0,
      `Front Finger Actuator on/off` = 0,
      `Z-Axis Synch Jog Down`        = 0
    WHERE bot_id = p_bot_id;

    SET Success = 1;
    SET Result  = 'Switched to Auto Mode (Auto Packet)';
  END IF;

  COMMIT;

  SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_TABLE_BADGE_CLASSES_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_TABLE_BADGE_CLASSES_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_TABLE_BADGE_CLASSES_GET_ALL`()
BEGIN
    SELECT 
        COLUMN_NAME, 
        COLUMN_VALUE, 
        CLASS_NAME
    FROM 
        dashboard_table_badge_classes_master
    WHERE 
        IS_ACTIVE = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_TABLE_COLUMNS_GET_ALL` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_TABLE_COLUMNS_GET_ALL` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_TABLE_COLUMNS_GET_ALL`()
BEGIN
SELECT 
        `COLUMN_HEADER_NAME`, 
        `COLUMN_COMPARISON_KEY`, 
        `COLUMN_DATA_TYPE` 
    FROM 
        `dashboard_table_columns_master` 
    WHERE 
        IS_ACTIVE = 1;	
	END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_TABLE_HEADER_JSON_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_TABLE_HEADER_JSON_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_TABLE_HEADER_JSON_GET`(IN Parameters JSON)
BEGIN
    
    DECLARE p_report_extra_parameters JSON;
    DECLARE p_table_unique_identifier VARCHAR(255);
    DECLARE p_user_id INT;
    DECLARE v_wave_id VARCHAR(50);
    DECLARE v_wave_status VARCHAR(50);
    DECLARE p_alaram_type VARCHAR(50);
    
    SET p_table_unique_identifier     = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.table_unique_identifier'));
    SET p_user_id                     = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id')) AS UNSIGNED);
    SET p_report_extra_parameters     = JSON_EXTRACT(Parameters, '$.report_extra_parameters');
    SET v_wave_id                     = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.wave_id'));
    SET p_alaram_type                 = JSON_UNQUOTE(JSON_EXTRACT(p_report_extra_parameters, '$.alarm_type'));
    
    IF v_wave_id IS NOT NULL AND v_wave_id != '' THEN
        SELECT WAVE_STATUS INTO v_wave_status
        FROM (
            SELECT WAVE_STATUS FROM wave_master WHERE WAVE_ID = v_wave_id
            UNION ALL
            SELECT WAVE_STATUS FROM wave_master_archive WHERE WAVE_ID = v_wave_id
        ) AS combined
        LIMIT 1;
        IF v_wave_status IS NULL THEN
            IF p_table_unique_identifier = 'report_wave_stock_audit_orders' THEN
                SET p_table_unique_identifier = 'report_wave_stock_audit_orders_temp';
            END IF;
        ELSEIF v_wave_status NOT IN ('COMPLETED', 'PROCESSING') THEN
            IF p_table_unique_identifier = 'report_wave_pick_orders' THEN
                SET p_table_unique_identifier = 'report_wave_pick_orders_wms';
            ELSEIF p_table_unique_identifier = 'report_wave_put_orders' THEN
                SET p_table_unique_identifier = 'report_wave_put_orders_wms';
            ELSEIF p_table_unique_identifier = 'report_wave_stock_audit_orders' THEN
                SET p_table_unique_identifier = 'report_wave_stock_audit_orders_wms';
            END IF;
        END IF;
    END IF;
    
    IF p_alaram_type = 'normal' THEN
        SET p_table_unique_identifier = 'report_alarm_history_normal';
    ELSEIF p_alaram_type = 'manual' THEN
        SET p_table_unique_identifier = 'report_alarm_history_manual';
    ELSEIF p_alaram_type = 'maintenance' THEN
        SET p_table_unique_identifier = 'report_alarm_history_maintenance';
    END IF;
    
    SELECT 
        dthjm.DEFAULT_HEADER_JSON,
        dthjum.SELECTED_HEADER_JSON,
        dthjm.ID AS DEFAULT_TABLE_ID
    FROM 
        dashboard_table_header_json_master AS dthjm
    LEFT JOIN 
        dashboard_table_header_json_user_mapping AS dthjum
        ON dthjum.TABLE_ID = dthjm.ID
           AND dthjum.USER_ID = p_user_id
           AND dthjum.IS_ACTIVE = 1
    WHERE 
        dthjm.TABLE_UNIQUE_IDENTIFIER = p_table_unique_identifier
        AND dthjm.IS_ACTIVE = 1;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_TABLE_HEADER_JSON_SET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_TABLE_HEADER_JSON_SET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_TABLE_HEADER_JSON_SET`(IN Parameters JSON)
BEGIN
    
    DECLARE p_user_id INT;
    DECLARE p_table_unique_identifier VARCHAR(255);
    DECLARE p_table_id INT;
    DECLARE p_header_json JSON;
    
    SET p_user_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.user_id')) AS UNSIGNED);
    SET p_table_unique_identifier = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.table_unique_identifier'));
    SET p_table_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.table_id')) AS UNSIGNED);
    SET p_header_json = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.header_json'));
    
    INSERT INTO dashboard_table_header_json_user_mapping (USER_ID, TABLE_ID, SELECTED_HEADER_JSON)
    VALUES (p_user_id, p_table_id, p_header_json)
    ON DUPLICATE KEY UPDATE 
        SELECTED_HEADER_JSON = VALUES(SELECTED_HEADER_JSON);
    
    SELECT 1 AS Success, 'Data Updated Successfully' AS Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_TABLE_PARAMETERS_GET` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_TABLE_PARAMETERS_GET` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_TABLE_PARAMETERS_GET`(IN Parameters JSON)
BEGIN
    
    DECLARE p_menu_id INT;
    DECLARE p_section_name VARCHAR(100);
    DECLARE p_unique_identifier VARCHAR(100);
    
    SET p_menu_id = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.menu_id')) AS UNSIGNED);
    SET p_section_name = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.section_name'));
    SET p_unique_identifier = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.unique_identifier'));
    
    IF EXISTS (
        SELECT 1
        FROM dashboard_table_parameters_master
        WHERE UNIQUE_IDENTIFIER = p_unique_identifier AND IS_ACTIVE = 1
    ) THEN
        
        IF p_section_name IS NOT NULL AND p_section_name <> '' THEN
            SELECT *
            FROM dashboard_table_parameters_master
            WHERE SECTION_NAME = p_section_name
              AND UNIQUE_IDENTIFIER = p_unique_identifier;
        ELSE
            SELECT *
            FROM dashboard_table_parameters_master
            WHERE MENU_ID = p_menu_id
              AND UNIQUE_IDENTIFIER = p_unique_identifier;
        END IF;
    ELSE
        SELECT 
            0 AS Success, 
            'No Entry Found for Table Unique Identifier' AS Result;
    END IF;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_TEST_QUERY` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_TEST_QUERY` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_TEST_QUERY`(
    IN Parameters JSON
)
BEGIN
    
    DECLARE p_query_type        VARCHAR(100);
    DECLARE p_filter_condition  TEXT;
    
    SET p_query_type = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.query_type'));
    SET p_filter_condition = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.filter_condition'));
    
    SET @dynamic_sql = DSB_PICK_RULE_QUERY_VIEW(p_filter_condition);
    
    PREPARE stmt FROM @dynamic_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPDATE_SKU_EAN_MAPPING_BY_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPDATE_SKU_EAN_MAPPING_BY_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPDATE_SKU_EAN_MAPPING_BY_ID`(
    IN Parameters VARCHAR(1000)
)
BEGIN
    
    UPDATE `sku_ean_mapping`
    SET
        `EAN_ID` = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.EAN_ID')) AS CHAR CHARACTER SET latin1), EAN_ID),
        `UPDATED_BY` = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.UPDATED_BY')) AS CHAR CHARACTER SET latin1), 'Backend')
    WHERE `ID` = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.ID')) AS CHAR CHARACTER SET latin1);
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPDATE_SKU_MASTER_BY_SKU_ID` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPDATE_SKU_MASTER_BY_SKU_ID` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPDATE_SKU_MASTER_BY_SKU_ID`(
    IN Parameters VARCHAR(1000)
)
BEGIN
    
    UPDATE sku_master
    SET
        SKU_NAME = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.SKU_NAME')) AS CHAR CHARACTER SET latin1), SKU_NAME),
        VELOCITY = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.VELOCITY')) AS UNSIGNED), VELOCITY),
        CATEGORY = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.CATEGORY')) AS UNSIGNED), CATEGORY),
        MIN_SEGMENT_SIZE = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.MIN_SEGMENT_SIZE')) AS UNSIGNED), MIN_SEGMENT_SIZE),
        MAX_QUANTITY_PER_SEGMENT = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.MAX_QUANTITY_PER_SEGMENT')) AS UNSIGNED), MAX_QUANTITY_PER_SEGMENT),
        MIN_BIN_STORAGE = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.MIN_BIN_STORAGE')) AS UNSIGNED), MIN_BIN_STORAGE),
        MAX_BIN_STORAGE = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.MAX_BIN_STORAGE')) AS UNSIGNED), MAX_BIN_STORAGE),
        MAX_QUANTITY_STORAGE = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.MAX_QUANTITY_STORAGE')) AS UNSIGNED), MAX_QUANTITY_STORAGE),
        VOLUME_OF_EACH_SKU = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.VOLUME_OF_EACH_SKU')) AS DECIMAL(10,3)), VOLUME_OF_EACH_SKU),
        WEIGHT_OF_EACH_SKU = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.WEIGHT_OF_EACH_SKU')) AS DECIMAL(10,3)), WEIGHT_OF_EACH_SKU),
        IMAGE_URL = IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.IMAGE_URL')) AS CHAR CHARACTER SET latin1), IMAGE_URL)
    WHERE SKU_ID = CAST(JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.SKU_ID')) AS CHAR CHARACTER SET latin1);
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_CHECK_IF_EXISTS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_CHECK_IF_EXISTS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_CHECK_IF_EXISTS`(
  IN Parameters JSON
)
BEGIN
  DECLARE p_wave_id VARCHAR(50);
  DECLARE Success   INT DEFAULT 0;
  DECLARE Result    VARCHAR(255);
  
  SET p_wave_id = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.wave_id'));
  
  IF EXISTS (
    SELECT 1
    FROM dashboard_wave_upload_status
    WHERE WAVE_ID = p_wave_id
      AND IS_ACTIVE = 1
  ) THEN
    SET Success = 1;
    SET Result  = CONCAT(p_wave_id, ' Found');
  ELSE
    SET Success = 0;
    SET Result  = CONCAT('No record found for given Wave ID: ', p_wave_id);
  END IF;
  
  SELECT Success, Result;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_GET_TARGET_TABLE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_GET_TARGET_TABLE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_GET_TARGET_TABLE`(IN Parameters JSON)
BEGIN
    DECLARE WaveId VARCHAR(255);
    DECLARE WaveType VARCHAR(255);
    SET WaveId = Parameters ->> '$.WaveId';
    SET WaveType = Parameters ->> '$.WaveType';
    IF WaveType = 'put_wave' THEN 
        SELECT 'put_wave_wms_data_dsb_upload_validation' AS Result;
    ELSEIF WaveType = 'pick_wave' THEN
        SELECT 'pick_wave_wms_data_dsb_upload_validation' AS Result;
    ELSEIF WaveType = 'sku_master' THEN
        SELECT 'sku_master_dsb_upload_validation' AS Result;
    ELSEIF WaveType = 'sku_ean_mapping' THEN
        SELECT 'sku_ean_mapping_dsb_upload_validation' AS Result;
    ELSEIF WaveType = 'stock_audit' THEN 
        SELECT 'stock_audit_wave_wms_data_dsb_upload_validation' AS Result;
    ELSEIF WaveType = 'stock_audit_by_bin_id_new' THEN 
        SELECT 'stock_audit_wave_wms_data_dsb_upload_validation' AS Result;
    ELSEIF WaveType = 'stock_audit_by_sku_id_new' THEN 
        SELECT 'stock_audit_wave_wms_data_dsb_upload_validation' AS Result;
    ELSEIF WaveType = 'stock_audit_by_random_new' THEN 
        SELECT 'stock_audit_wave_wms_data_dsb_upload_validation' AS Result;
     ELSEIF WaveType = 'stock_audit_by_bin_id_and_segment_id_new' THEN 
        SELECT 'stock_audit_wave_wms_data_dsb_upload_validation' AS Result;
     ELSEIF WaveType = 'prepare_orders' THEN
        SELECT 'prepare_orders_wms_data_dsb_upload_validation' AS Result;
       ELSEIF WaveType = 'storage_request' THEN
        SELECT 'storage_request_wms_data_dsb_upload_validation' AS Result;
    ELSE 
        SELECT 'Invalid WaveType or WaveId' AS Result;
    END IF;
    
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_INSERT_INTO_DASHBOARD_UPLOAD_STATUS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_INSERT_INTO_DASHBOARD_UPLOAD_STATUS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_INSERT_INTO_DASHBOARD_UPLOAD_STATUS`(IN Parameters JSON)
BEGIN
  DECLARE p_wave_id     VARCHAR(50);
  DECLARE p_wave_type   VARCHAR(50);
  DECLARE p_updated_by  VARCHAR(50);
  SET p_wave_id    = Parameters ->> '$.WaveId';
  SET p_wave_type  = Parameters ->> '$.WaveType';
  SET p_updated_by = Parameters ->> '$.UserName';
  INSERT INTO dashboard_wave_upload_status (WAVE_ID, CLIENT_WAVE_ID, WAVE_TYPE, INSERTED_BY)
  VALUES (p_wave_id, p_wave_id, p_wave_type, p_updated_by);
  SELECT ID AS Result
  FROM dashboard_wave_upload_status
  WHERE WAVE_ID = p_wave_id;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE`(IN Parameters JSON)
BEGIN
    DECLARE _validationFailed INT DEFAULT 0;
    DECLARE waveId VARCHAR(50);
    DECLARE waveType VARCHAR(50);
    DECLARE waveUniqueId INT;
    
    SET waveId = Parameters ->> '$.WaveId';
    SET waveType = Parameters ->> '$.WaveType';
    SET waveUniqueId = Parameters ->> '$.UploadedWaveId';
    
    IF waveType = 'sku_master' THEN
        CALL DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_SKU_MASTER(Parameters);
    ELSEIF waveType = 'bin_recall' THEN
        CALL DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_BINRECALL(Parameters);
    ELSEIF waveType = 'pick_wave' THEN
        CALL `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PICK_WAVE`(Parameters);
    ELSEIF waveType = 'put_wave' THEN
        CALL `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PUT_WAVE`(Parameters);
    ELSEIF waveType = 'sku_ean_mapping' THEN
        CALL `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_SKU_EAN_MAPPING`(Parameters);
    ELSEIF waveType = 'stock_audit' THEN
        CALL `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STOCK_AUDIT_WAVE`(Parameters);
    ELSEIF waveType = 'stock_audit_by_sku_id_new' OR waveType = 'stock_audit_by_bin_id_new' OR waveType = 'stock_audit_by_bin_id_and_segment_id_new' OR waveType = 'stock_audit_by_random_new' THEN
        CALL `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STOCK_AUDIT`(Parameters);
    ELSEIF waveType = 'prepare_orders'  THEN
        CALL `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PREPARE_ORDERS`(Parameters);
    ELSEIF waveType = 'storage_request'  THEN
        CALL `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STORAGE_REQUEST`(Parameters);
    ELSE
        
        SELECT 'Wrong Wave ID';
    END IF;
    
    SELECT `STATUS` FROM `dashboard_wave_upload_status` WHERE ID = waveUniqueId;
    
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PICK_WAVE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PICK_WAVE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PICK_WAVE`(IN Parameters JSON)
BEGIN
	DECLARE _validationFailed INT;
    DECLARE waveId VARCHAR(50);
    DECLARE waveType VARCHAR(50);
    DECLARE waveUniqueId INT;
    
    SET waveId = Parameters ->> '$.WaveId';
    SET waveType = Parameters ->> '$.WaveType';
    SET waveUniqueId = Parameters ->> '$.UploadedWaveId';
    SET _validationFailed = 0;
    
        DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
        CREATE TEMPORARY TABLE tmp_invalidRowinWaveData (
            ID INT, 
            _message VARCHAR(2000)
        );
       
            
			INSERT INTO tmp_invalidRowinWaveData (ID, _message)
			SELECT 
			    ID, 
			    CONCAT(
				CASE WHEN COALESCE(TRIM(WAVE_ID), '') = '' THEN 'WAVE_ID is null or empty. ' ELSE '' END,
				CASE WHEN COALESCE(TRIM(LOCATION_ID), '') = '' THEN 'LOCATION_ID is null or empty. ' ELSE '' END,
				CASE WHEN COALESCE(TRIM(ORDER_ID), '') = '' THEN 'ORDER_ID is null or empty. ' ELSE '' END,
				CASE WHEN COALESCE(TRIM(SKU_ID), '') = '' THEN 'SKU_ID is null or empty. ' ELSE '' END,
				CASE WHEN COALESCE(MRP, 0) = 0 THEN 'MRP is null or zero. ' ELSE '' END,
				CASE WHEN COALESCE(QUANTITY, 0) = 0 THEN 'QUANTITY is null or zero. ' ELSE '' END,
				CASE WHEN COALESCE(EXPIRY_DATE, '') = '' THEN 'EXPIRY_DATE is null or incorrect. ' ELSE '' END,
				CASE WHEN COALESCE(PRIORITY, 0) = 0 THEN 'PRIORITY is null or zero. ' ELSE '' END
			    ) AS _message
			FROM `pick_wave_wms_data_dsb_upload_validation`
			WHERE UPLOADED_WAVE_ID=waveUniqueId aND(
			    COALESCE(TRIM(WAVE_ID), '') = '' OR 
			     COALESCE(TRIM(LOCATION_ID), '') = '' OR
			    COALESCE(TRIM(ORDER_ID), '') = '' OR
			    COALESCE(TRIM(SKU_ID), '') = '' OR
			    COALESCE(MRP, 0) = 0 OR
			    COALESCE(QUANTITY, 0) = 0 OR
			    COALESCE(EXPIRY_DATE, '') = '' OR
			    COALESCE(PRIORITY, 0) = 0);
			    
		    
            INSERT INTO tmp_invalidRowinWaveData (ID, _message) 
	    SELECT ID, 'SKU_ID not present in database'
	    FROM `pick_wave_wms_data_dsb_upload_validation` AS A 
	    LEFT JOIN `sku_master` AS B 
	    ON A.SKU_ID = B.SKU_ID 
	    WHERE B.SKU_ID IS NULL AND A.UPLOADED_WAVE_ID=waveUniqueId ;
            
       
	INSERT INTO tmp_invalidRowinWaveData(ID, _message)
	SELECT DISTINCT o1.ID, 'Order has same SKU ID and LOT '
	FROM `pick_wave_wms_data_dsb_upload_validation` AS o1
	JOIN `pick_wave_wms_data_dsb_upload_validation` AS o2
	ON (o1.ORDER_ID = o2.ORDER_ID AND o1.UPLOADED_WAVE_ID = o2.UPLOADED_WAVE_ID)
	AND o1.SKU_ID = o2.SKU_ID AND o1.MRP = o2.MRP AND o1.EXPIRY_DATE=o2.EXPIRY_DATE
	AND o1.ID <> o2.ID
	WHERE o1.`UPLOADED_WAVE_ID` = waveUniqueId;
	
	INSERT INTO tmp_invalidRowinWaveData (ID, _message)
	SELECT B.ID, 'SKU_ID with MRP and EXPIRY_DATE not exist'
	FROM `pick_wave_wms_data_dsb_upload_validation` AS B
	LEFT JOIN sku_batch_master AS A 
	ON A.SKU_ID = B.SKU_ID 
	AND A.MRP = B.MRP
	AND A.EXPIRY_DATE = B.EXPIRY_DATE
	WHERE A.SKU_ID IS NULL AND B.`UPLOADED_WAVE_ID` = waveUniqueId; 
	
            IF EXISTS (SELECT ID FROM tmp_invalidRowinWaveData) THEN
                SET _validationFailed = 1;
                UPDATE `pick_wave_wms_data_dsb_upload_validation` C 
                INNER JOIN (
                    SELECT ID, GROUP_CONCAT(_message) AS _message
                    FROM tmp_invalidRowinWaveData
                    GROUP BY ID
                ) T ON T.ID = C.ID
                SET C.`VALIDATION_MESSAGE` = T._message;
            END IF;
       
        
        IF _validationFailed = 1 THEN
            UPDATE `dashboard_wave_upload_status` SET `STATUS` = 'Failed' WHERE `ID` = waveUniqueId; 
            
        ELSE
            UPDATE `dashboard_wave_upload_status` SET `STATUS` = 'Insertion In Progress' WHERE `ID` = waveUniqueId; 
            CALL DSB_WAVE_DATA_INSERT_CONFIG_INTO_TABLES(Parameters);
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
    
   
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PREPARE_ORDERS` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PREPARE_ORDERS` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PREPARE_ORDERS`(IN Parameters JSON)
BEGIN
    DECLARE _validationFailed INT DEFAULT 0;
    DECLARE updatedBy VARCHAR(200);
    DECLARE waveUniqueId INT;
    DECLARE v_orderDataId INT;
    DECLARE v_errorMessage TEXT; 
    DECLARE EXIT HANDLER FOR SQLEXCEPTION  
    BEGIN  
        GET DIAGNOSTICS CONDITION 1 v_errorMessage = MESSAGE_TEXT;  
        ROLLBACK;  
        SELECT 0 AS SUCCESS, 'FAILED DUE TO ERROR' AS MESSAGE, v_errorMessage AS DESCRIPTION;  
    END;
    SET waveUniqueId = Parameters ->> '$.UploadedWaveId';
    SET updatedBy = Parameters ->> '$.UpdatedBy';
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
    CREATE TEMPORARY TABLE tmp_invalidRowinWaveData(ID INT, _message VARCHAR(2000));
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message)
	SELECT 
	    ID,
	    CONCAT(
		CASE WHEN COALESCE(TRIM(ORDER_ID), '') = '' THEN 'ORDER_ID is null or empty. ' ELSE '' END,
		CASE WHEN PRIORITY IS NULL OR PRIORITY <= 0 THEN 'PRIORITY is null or zero. ' ELSE '' END,
		CASE WHEN COALESCE(TRIM(ORDER_LINE_ID), '') = '' THEN 'ORDER_LINE_ID is null or empty. ' ELSE '' END,
		CASE WHEN COALESCE(TRIM(ARTICLE_ID), '') = '' THEN 'ARTICLE_ID is null or empty. ' ELSE '' END,
		CASE WHEN COALESCE(TRIM(GLN), '') = '' THEN 'GLN is null or empty. ' ELSE '' END,
		CASE WHEN QUANTITY IS NULL OR QUANTITY <= 0 THEN 'QUANTITY is null or zero. ' ELSE '' END,
		CASE WHEN EXPIRATION_DATE IS NULL THEN 'EXPIRATION_DATE is null. ' ELSE '' END,
		CASE WHEN MRP IS NULL OR MRP <= 0 THEN 'MRP is null or zero. ' ELSE '' END,
		CASE WHEN CUT_OFF_TIME IS NULL THEN 'CUT_OFF_TIME is null. ' ELSE '' END
	    ) AS _message
	FROM prepare_orders_wms_data_dsb_upload_validation
	WHERE UPLOADED_WAVE_ID = waveUniqueId
	  AND (
	    COALESCE(TRIM(ORDER_ID), '') = '' OR
	    PRIORITY IS NULL OR PRIORITY <= 0 OR
	    COALESCE(TRIM(ORDER_LINE_ID), '') = '' OR
	    COALESCE(TRIM(ARTICLE_ID), '') = '' OR
	    COALESCE(TRIM(GLN), '') = '' OR
	    QUANTITY IS NULL OR QUANTITY <= 0 OR
	    EXPIRATION_DATE IS NULL OR
	    MRP IS NULL OR MRP <= 0 OR
	    CUT_OFF_TIME IS NULL
	);
    
    INSERT INTO tmp_invalidRowinWaveData(ID, _message)
    SELECT A.ID, 'ARTICLE_ID does not exist in SKU master.'
    FROM prepare_orders_wms_data_dsb_upload_validation AS A
    LEFT JOIN sku_master AS B ON A.ARTICLE_ID = B.SKU_ID
    WHERE B.SKU_ID IS NULL AND A.UPLOADED_WAVE_ID = waveUniqueId;
    
  
    
    IF EXISTS (SELECT 1 FROM tmp_invalidRowinWaveData) THEN
        SET _validationFailed = 1;
        
        UPDATE prepare_orders_wms_data_dsb_upload_validation C
        INNER JOIN (
            SELECT ID, GROUP_CONCAT(_message SEPARATOR ' | ') AS _message
            FROM tmp_invalidRowinWaveData
            GROUP BY ID
        ) T ON T.ID = C.ID
        SET C.VALIDATION_MESSAGE = T._message;
        
        UPDATE dashboard_wave_upload_status SET STATUS = 'Failed'
        WHERE ID = waveUniqueId;
    ELSE
        START TRANSACTION;
        
        INSERT IGNORE INTO wms_to_wcs_order_level_pre_staged_data (
           GLN, ORDER_ID, STORE_ID, PARENT_STORE_ID,`PRIORITY`, ORDER_REQUEST_STATUS, CUT_OFF_TIME
        )
        SELECT 
           GLN, ORDER_ID, DESTINATION_STORE_CODE, DESTINATION_STORE_NAME,PRIORITY, 'PENDING', CUT_OFF_TIME
        FROM prepare_orders_wms_data_dsb_upload_validation
        WHERE UPLOADED_WAVE_ID = waveUniqueId
        GROUP BY ORDER_ID, DESTINATION_STORE_CODE, DESTINATION_STORE_NAME, CUT_OFF_TIME;
        INSERT IGNORE INTO sku_batch_master (
            SKU_ID, CLIENT_BATCH_ID, BATCH_ID, MRP, EXPIRY_DATE,GLN, COUNTRY_OF_ORIGIN
        )
        SELECT DISTINCT
            `ARTICLE_ID`, `BATCH_ID`, UUID(), `MRP`, `EXPIRATION_DATE`,`GLN` ,`COUNTRY_OF_ORIGIN`
        FROM prepare_orders_wms_data_dsb_upload_validation
        WHERE UPLOADED_WAVE_ID = waveUniqueId;
        
        INSERT IGNORE INTO wms_to_wcs_order_line_level_pre_staged_data (
        
            `WMS_ORDER_REQUEST_DATA_ID`,ORDER_ID, ORDER_LINE_ID, ARTICLE_ID, QUANTITY, DISPLAY_OPERATOR_INSTRUCTION,
            BATCH_ID, MRP, EXPIRY_DATE, ORDER_LINE_PROCESS_STATUS
        )
        SELECT 
            wtword.`WMS_ORDER_REQUEST_DATA_ID`,p.ORDER_ID, p.ORDER_LINE_ID, p.ARTICLE_ID, p.QUANTITY, `DISPLAY_OPERATION`,
            p.BATCH_ID, p.MRP, p.EXPIRATION_DATE, 'PENDING'
        FROM prepare_orders_wms_data_dsb_upload_validation p
        INNER JOIN `wms_to_wcs_order_level_pre_staged_data` wtword ON wtword.`ORDER_ID`=p.ORDER_ID
        INNER JOIN sku_batch_master sbm
            ON p.ARTICLE_ID = sbm.SKU_ID
            AND p.MRP = sbm.MRP
            AND p.GLN=sbm.GLN
            AND p.EXPIRATION_DATE = sbm.EXPIRY_DATE
        WHERE p.UPLOADED_WAVE_ID = waveUniqueId;
        
        COMMIT;
        
        UPDATE dashboard_wave_upload_status SET STATUS = 'Uploaded Successfully'
        WHERE ID = waveUniqueId;
        DELETE FROM prepare_orders_wms_data_dsb_upload_validation
        WHERE UPLOADED_WAVE_ID = waveUniqueId;
        
        SELECT 1 AS SUCCESS, "Uploaded Successfully" AS `STATUS`, '' AS DESCRIPTION;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PUT_WAVE` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PUT_WAVE` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_PUT_WAVE`(IN Parameters JSON)
BEGIN
	DECLARE _validationFailed INT;
    DECLARE waveId VARCHAR(50);
    DECLARE waveType VARCHAR(50);
    DECLARE waveUniqueId INT;
    
    SET waveId = Parameters ->> '$.WaveId';
    SET waveType = Parameters ->> '$.WaveType';
    SET waveUniqueId = Parameters ->> '$.UploadedWaveId';
    SET _validationFailed = 0;
    
        DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
        CREATE TEMPORARY TABLE tmp_invalidRowinWaveData (
            ID INT, 
            _message VARCHAR(2000)
        );
       
            
		INSERT INTO tmp_invalidRowinWaveData (ID, _message)
		SELECT 
		    ID, 
		    CONCAT(
			CASE WHEN COALESCE(TRIM(WAVE_ID), '') = '' THEN 'WAVE_ID is null or empty. ' ELSE '' END,
			CASE WHEN COALESCE(TRIM(LOCATION_ID), '') = '' THEN 'LOCATION_ID is null or empty. ' ELSE '' END,
			CASE WHEN COALESCE(TRIM(SKU_ID), '') = '' THEN 'SKU_ID is null or empty. ' ELSE '' END,
			CASE WHEN COALESCE(MRP, 0) = 0 THEN 'MRP is null or zero. ' ELSE '' END,
		        CASE WHEN COALESCE(QUANTITY, 0) = 0 THEN 'QUANTITY is null or zero. ' ELSE '' END,
		        CASE WHEN COALESCE(EXPIRY_DATE, '') = '' THEN 'EXPIRY_DATE format is null or incorrect ' ELSE '' END
		    ) AS _message
		FROM `put_wave_wms_data_dsb_upload_validation`
		WHERE UPLOADED_WAVE_ID=waveUniqueId AND(
		    COALESCE(TRIM(WAVE_ID), '') = '' OR 
		    COALESCE(TRIM(LOCATION_ID), '') = '' OR
		    COALESCE(TRIM(SKU_ID), '') = '' OR
		    COALESCE(MRP, 0) = 0 OR
	            COALESCE(QUANTITY, 0) = 0 OR
		    COALESCE(EXPIRY_DATE, '') = '');
		    
		    
            INSERT INTO tmp_invalidRowinWaveData (ID, _message) 
	    SELECT ID, 'SKU_ID not present in database'
	    FROM `put_wave_wms_data_dsb_upload_validation` AS A 
	    LEFT JOIN `sku_master` AS B 
	    ON A.SKU_ID = B.SKU_ID 
	    WHERE B.SKU_ID IS NULL AND A.UPLOADED_WAVE_ID=waveUniqueId ;
            
       
	INSERT INTO tmp_invalidRowinWaveData(ID, _message)
	SELECT DISTINCT o1.ID, 'SKU ID with same MRP AND EXPIRY DATE'
	FROM `put_wave_wms_data_dsb_upload_validation` AS o1
	JOIN `put_wave_wms_data_dsb_upload_validation` AS o2
	ON (o1.UPLOADED_WAVE_ID = o2.UPLOADED_WAVE_ID)
	AND o1.SKU_ID = o2.SKU_ID AND o1.MRP = o2.MRP AND o1.EXPIRY_DATE=o2.EXPIRY_DATE
	AND o1.ID <> o2.ID
	WHERE o1.`UPLOADED_WAVE_ID` = waveUniqueId;
	
            IF EXISTS (SELECT ID FROM tmp_invalidRowinWaveData) THEN
                SET _validationFailed = 1;
                UPDATE `put_wave_wms_data_dsb_upload_validation` C 
                INNER JOIN (
                    SELECT ID, GROUP_CONCAT(_message) AS _message
                    FROM tmp_invalidRowinWaveData
                    GROUP BY ID
                ) T ON T.ID = C.ID
                SET C.`VALIDATION_MESSAGE` = T._message;
            END IF;
       
        DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
        IF _validationFailed = 1 THEN
            UPDATE `dashboard_wave_upload_status` SET `STATUS` = 'Failed' WHERE `ID` = waveUniqueId; 
        ELSE
            UPDATE `dashboard_wave_upload_status` SET `STATUS` = 'Insertion In Progress' WHERE `ID` = waveUniqueId; 
            CALL DSB_WAVE_DATA_INSERT_CONFIG_INTO_TABLES(Parameters);
        END IF;
    
    SELECT `STATUS` FROM `dashboard_wave_upload_status` WHERE ID = waveUniqueId;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_SKU_EAN_MAPPING` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_SKU_EAN_MAPPING` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_SKU_EAN_MAPPING`(IN Parameters JSON)
BEGIN
    DECLARE _validationFailed INT DEFAULT 0;
    DECLARE waveId VARCHAR(50);
    DECLARE waveType VARCHAR(50);
    DECLARE waveUniqueId INT;
    DECLARE tableName VARCHAR(20);
    DECLARE sqlQuery VARCHAR(1000);
    DECLARE updatedBy VARCHAR(200);
    SET waveId = Parameters ->> '$.WaveName';
    SET waveType = Parameters ->> '$.WaveType';
    SET waveUniqueId = Parameters ->> '$.UploadedWaveId';
    SET updatedBy = Parameters ->> '$.UpdatedBy';
    
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
    CREATE TEMPORARY TABLE tmp_invalidRowinWaveData (
        ID INT, 
        _message VARCHAR(2000)
    );
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message)
    SELECT 
        ID, 
        CONCAT(
            CASE WHEN COALESCE(TRIM(LOCATION_ID), '') = '' THEN 'LOCATION_ID is null or empty. ' ELSE '' END,
            CASE WHEN COALESCE(TRIM(SKU_ID), '') = '' THEN 'SKU_ID is null or empty. ' ELSE '' END,
            CASE WHEN COALESCE(EAN_ID, '') = '' THEN 'EAN_ID is null or empty. ' ELSE '' END
        ) AS _message
    FROM `sku_ean_mapping_dsb_upload_validation`
    WHERE UPLOADED_WAVE_ID = waveUniqueId
    AND (
        COALESCE(TRIM(LOCATION_ID), '') = '' OR
        COALESCE(TRIM(SKU_ID), '') = '' OR
        COALESCE(EAN_ID, '') = ''
    );
    
	INSERT INTO tmp_invalidRowinWaveData (ID, _message)
	SELECT 
	    ID, 
	    'EAN_ID is not in the right format'
	FROM `sku_ean_mapping_dsb_upload_validation`
	WHERE UPLOADED_WAVE_ID = waveUniqueId
	AND (EAN_ID LIKE '%E+%' OR EAN_ID LIKE '%E*%');
	
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message) 
    SELECT A.ID, 'SKU_ID not present in database'
    FROM `sku_ean_mapping_dsb_upload_validation` A 
    LEFT JOIN `sku_master` B ON A.SKU_ID = B.SKU_ID 
    WHERE B.SKU_ID IS NULL 
    AND A.UPLOADED_WAVE_ID = waveUniqueId;
    
    IF EXISTS (SELECT 1 FROM tmp_invalidRowinWaveData) THEN
        SET _validationFailed = 1;
        
        UPDATE `sku_ean_mapping_dsb_upload_validation` C
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
        
       INSERT IGNORE INTO `sku_ean_mapping` (
            `LOCATION_ID`, 
            `SKU_ID`, 
            `EAN_ID`,
            `INSERTED_BY`,
            `UPDATED_BY`
        )
        SELECT 
            `LOCATION_ID`, 
            `SKU_ID`, 
            `EAN_ID`,
            updatedBy,
            updatedBy
        FROM `sku_ean_mapping_dsb_upload_validation` 
        WHERE `UPLOADED_WAVE_ID` = waveUniqueId;
        
        UPDATE `dashboard_wave_upload_status` 
        SET `STATUS` = 'Uploaded Successfully' 
        WHERE `ID` = waveUniqueId;
        
     delete from `sku_ean_mapping_dsb_upload_validation` where `UPLOADED_WAVE_ID`=waveUniqueId;
        
    END IF;
    
  
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_SKU_MASTER` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_SKU_MASTER` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_SKU_MASTER`(IN Parameters JSON)
BEGIN
    DECLARE _validationFailed INT DEFAULT 0;
    DECLARE waveId VARCHAR(50);
    DECLARE waveType VARCHAR(50);
    DECLARE waveUniqueId INT;
    DECLARE updatedBy VARCHAR(200);
    
    SET waveId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.WaveName'));
    SET waveType = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.WaveType'));
    SET waveUniqueId = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.UploadedWaveId'));
    SET updatedBy = JSON_UNQUOTE(JSON_EXTRACT(Parameters, '$.UpdatedBy'));
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
    CREATE TEMPORARY TABLE tmp_invalidRowinWaveData (
        ID INT,
        _message VARCHAR(2000)
    );
   INSERT INTO tmp_invalidRowinWaveData (ID, _message)
SELECT 
    ID, 
    CONCAT(
		CASE WHEN COALESCE(TRIM(SKU_ID), '') = '' THEN 'SKU_ID is null or empty. ' ELSE '' END,
		CASE WHEN COALESCE(TRIM(SKU_NAME), '') = '' THEN 'SKU_NAME is null or empty. ' ELSE '' END,
		CASE WHEN COALESCE(VELOCITY, 0) <= 0 THEN 'VELOCITY is null or Zero. ' ELSE '' END,
		CASE WHEN COALESCE(CATEGORY, '') = '' THEN 'CATEGORY is null or empty. ' ELSE '' END,
		CASE WHEN COALESCE(MIN_SEGMENT_SIZE, 0) <= 0 THEN 'MIN_SEGMENT_SIZE is Zero. Size of SKU More than Bin Size. ' ELSE '' END,
		CASE WHEN COALESCE(MAX_QUANTITY_PER_SEGMENT, 0) <= 0 THEN 'MAX_QUANTITY_PER_SEGMENT is null or Zero. ' ELSE '' END,
		CASE WHEN COALESCE(WEIGHT_OF_EACH_SKU, 0) <= 0 THEN 'WEIGHT_OF_EACH_SKU is null or Zero. ' ELSE '' END,
		CASE WHEN COALESCE(TRIM(IMAGE_URL), '') = '' THEN 'IMAGE_URL is null or empty. ' ELSE '' END
	    )
	FROM `sku_master_dsb_upload_validation`
	WHERE 
	    UPLOADED_WAVE_ID = waveUniqueId AND (
		COALESCE(TRIM(SKU_ID), '') = '' OR
		COALESCE(TRIM(SKU_NAME), '') = '' OR
		COALESCE(VELOCITY, 0) <= 0 OR
		COALESCE(CATEGORY, '') = '' OR
		COALESCE(MIN_SEGMENT_SIZE, 0) <= 0 OR
		COALESCE(MAX_QUANTITY_PER_SEGMENT, 0) <= 0 OR
		COALESCE(WEIGHT_OF_EACH_SKU, 0) <= 0 OR
		COALESCE(TRIM(IMAGE_URL), '') = ''
	    );
    IF EXISTS (SELECT 1 FROM tmp_invalidRowinWaveData) THEN
        SET _validationFailed = 1;
	SELECT * FROM  tmp_invalidRowinWaveData;
        UPDATE `sku_master_dsb_upload_validation` C
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
        WHERE `ID` = waveUniqueId;
    ELSE
        
        INSERT IGNORE INTO `category_master` (`CATEGORY_NAME`, `INSERTED_BY`)
        SELECT DISTINCT `CATEGORY`, updatedBy 
        FROM sku_master_dsb_upload_validation 
        WHERE `UPLOADED_WAVE_ID` = waveUniqueId;
        UPDATE `dashboard_wave_upload_status` 
        SET `STATUS` = 'Insertion In Progress' 
        WHERE `ID` = waveUniqueId;
        
        INSERT INTO `sku_master` (
            `SKU_ID`, `SKU_NAME`, `VELOCITY`, `CATEGORY`, `MIN_SEGMENT_SIZE`, 
            `MAX_QUANTITY_PER_SEGMENT`,
            `LENGTH`, `WIDTH`, `HEIGHT`,  `WEIGHT_OF_EACH_SKU`, `IMAGE_URL`,
            `INSERTED_BY`, `UPDATED_BY`
        )
        SELECT 
            B.`SKU_ID`, B.`SKU_NAME`, B.`VELOCITY`, C.`CATEGORY_ID`, B.`MIN_SEGMENT_SIZE`, 
            B.`MAX_QUANTITY_PER_SEGMENT`,
            B.`LENGTH`, B.`WIDTH`, B.`HEIGHT`,  B.`WEIGHT_OF_EACH_SKU`, B.`IMAGE_URL`,
            updatedBy, updatedBy
        FROM `sku_master_dsb_upload_validation` AS B 
        LEFT JOIN `category_master` C 
            ON C.`CATEGORY_NAME` = B.`CATEGORY`
        WHERE B.`UPLOADED_WAVE_ID` = waveUniqueId
        ON DUPLICATE KEY UPDATE
            `SKU_NAME` = VALUES(`SKU_NAME`),
            `VELOCITY` = VALUES(`VELOCITY`),
            `CATEGORY` = VALUES(`CATEGORY`),
            `MIN_SEGMENT_SIZE` = VALUES(`MIN_SEGMENT_SIZE`),
            `MAX_QUANTITY_PER_SEGMENT` = VALUES(`MAX_QUANTITY_PER_SEGMENT`),
            `LENGTH` = VALUES(`LENGTH`),
            `WIDTH` = VALUES(`WIDTH`),
            `HEIGHT` = VALUES(`HEIGHT`),
       
            `WEIGHT_OF_EACH_SKU` = VALUES(`WEIGHT_OF_EACH_SKU`),
            `IMAGE_URL` = VALUES(`IMAGE_URL`),
            `UPDATED_BY` = VALUES(`UPDATED_BY`);
        UPDATE `dashboard_wave_upload_status` 
        SET `STATUS` = 'Uploaded Successfully' 
        WHERE `ID` = waveUniqueId;
        DELETE FROM `sku_master_dsb_upload_validation` 
        WHERE `UPLOADED_WAVE_ID` = waveUniqueId;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
END */$$
DELIMITER ;

/* Procedure structure for procedure `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STOCK_AUDIT` */

/*!50003 DROP PROCEDURE IF EXISTS  `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STOCK_AUDIT` */;

DELIMITER $$

/*!50003 CREATE DEFINER=`root`@`%` PROCEDURE `DSB_UPLOAD_DATA_LOAD_AND_VALIDATE_STOCK_AUDIT`(IN Parameters JSON)
BEGIN
    DECLARE _validationFailed INT DEFAULT 0;
    DECLARE waveId VARCHAR(50);
    DECLARE waveId1 VARCHAR(50);
    DECLARE waveType VARCHAR(50);
    DECLARE waveUniqueId INT;
    DECLARE tableName VARCHAR(20);
    DECLARE sqlQuery VARCHAR(1000);
    DECLARE backendWaveId VARCHAR(200);
    DECLARE binLimit INT;
    
    
    SET waveId = Parameters ->> '$.WaveId';
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
    SELECT A.ID, 'SKU_ID not present in live inventory'
    FROM `stock_audit_wave_wms_data_dsb_upload_validation` A 
    LEFT JOIN `live_inventory_master` B ON A.SKU_ID = B.`ARTICLE_ID` 
    WHERE B.`ARTICLE_ID` IS NULL AND A.SKU_ID IS NOT NULL
    AND A.UPLOADED_WAVE_ID = waveUniqueId;
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message) 
    SELECT DISTINCT A.ID, 'BIN_ID not present in bin_info_master'
    FROM `stock_audit_wave_wms_data_dsb_upload_validation` A 
    LEFT JOIN `bin_info_master` B ON A.`BIN_ID` = B.`BIN_ID` 
    WHERE B.`BIN_ID` IS NULL AND A.`BIN_ID` IS NOT NULL
    AND A.UPLOADED_WAVE_ID = waveUniqueId AND  waveType <> 'stock_audit_by_random_new';
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message) 
    SELECT DISTINCT A.ID, 'BIN_ID not present in live inventory'
    FROM `stock_audit_wave_wms_data_dsb_upload_validation` A 
    LEFT JOIN `live_inventory_master` B ON A.`BIN_ID` = B.`BIN_ID` 
    WHERE B.`BIN_ID` IS NULL AND A.`BIN_ID` IS NOT NULL
    AND A.UPLOADED_WAVE_ID = waveUniqueId AND  waveType <> 'stock_audit_by_random_new';
    
    INSERT INTO tmp_invalidRowinWaveData (ID, _message) 
    SELECT DISTINCT A.ID, 'BIN_SEGMENT not present in bin_info_master'
    FROM `stock_audit_wave_wms_data_dsb_upload_validation` A 
    LEFT JOIN `bin_info_master` B ON A.`BIN_ID` = B.`BIN_ID` 
    WHERE B.`BIN_ID` IS NOT NULL 
    AND B.`BIN_SEGMENTS` < A.`BIN_SEGMENT_NO` 
    AND A.`BIN_ID` IS NOT NULL 
    AND A.BIN_SEGMENT_NO IS NOT NULL
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
        
        SELECT `WAVE_ID` INTO waveId1 
        FROM `dashboard_wave_upload_status` 
        WHERE `ID` = waveUniqueId;
        
        IF waveType = 'stock_audit_by_bin_id_new' THEN
            INSERT INTO `stock_audit_wave_wms_data_dsb_temp` (`WAVE_ID`, `BIN_ID`, `BIN_SEGMENT_NO`, `SKU_ID`,`BATCH_ID`)
            SELECT DISTINCT waveId1, A.`BIN_ID`, A.`SEGMENT_NO`, A.`ARTICLE_ID` ,A.`BATCH_ID`
            FROM `live_inventory_master` AS A
            INNER JOIN `stock_audit_wave_wms_data_dsb_upload_validation` AS B ON B.`BIN_ID` = A.`BIN_ID`
            WHERE `UPLOADED_WAVE_ID` = waveUniqueId ;
          
        ELSEIF waveType = 'stock_audit_by_sku_id_new' THEN
            INSERT INTO `stock_audit_wave_wms_data_dsb_temp` (`WAVE_ID`, `BIN_ID`, `BIN_SEGMENT_NO`, `SKU_ID`,`BATCH_ID`)
            SELECT  DISTINCT waveId1, A.`BIN_ID`, A.`SEGMENT_NO`, A.`ARTICLE_ID` ,A.`BATCH_ID`
            FROM `live_inventory_master` AS A
            INNER JOIN `stock_audit_wave_wms_data_dsb_upload_validation` AS B ON B.`SKU_ID` = A.`ARTICLE_ID`
            WHERE `UPLOADED_WAVE_ID` = waveUniqueId ;
           
        
         ELSEIF waveType = 'stock_audit_by_bin_id_and_segment_id_new' THEN
            INSERT INTO `stock_audit_wave_wms_data_dsb_temp` (`WAVE_ID`, `BIN_ID`, `BIN_SEGMENT_NO`, `SKU_ID`,`BATCH_ID`)
            SELECT DISTINCT waveId1, A.`BIN_ID`, A.`SEGMENT_NO`, A.`ARTICLE_ID` ,A.`BATCH_ID`
            FROM `live_inventory_master` AS A
            INNER JOIN `stock_audit_wave_wms_data_dsb_upload_validation` AS B ON B.`BIN_ID` = A.`BIN_ID` AND B.`BIN_SEGMENT_NO`=A.`SEGMENT_NO`
            WHERE `UPLOADED_WAVE_ID` = waveUniqueId ;
       
            
        ELSEIF waveType = 'stock_audit_by_random_new' THEN
        
		
		
		SELECT `BIN_ID` INTO binLimit 
		FROM `stock_audit_wave_wms_data_dsb_upload_validation` 
		WHERE `UPLOADED_WAVE_ID` = waveUniqueId 
		LIMIT 1;
		call wm_select_uniform_random_bins(binLimit);
		
		INSERT INTO `stock_audit_wave_wms_data_dsb_temp` (`WAVE_ID`, `BIN_ID`, `BIN_SEGMENT_NO`, `SKU_ID`, `BATCH_ID`)
		SELECT waveId1,b.BIN_ID AS 'BIN ID', lim.SEGMENT_NO AS 'SEGMENT NO' , sm.SKU_ID,lim.BATCH_ID  
		    FROM (SELECT bin_id FROM temp_selected_bins LIMIT binLimit) b 
		    LEFT JOIN 
			live_inventory_master lim ON b.BIN_ID = lim.BIN_ID  
		    LEFT JOIN 
			sku_master sm ON lim.ARTICLE_ID = sm.SKU_ID         
		    LEFT JOIN 
			sku_batch_master sbm ON lim.ARTICLE_ID = sbm.SKU_ID 
			AND lim.BATCH_ID = sbm.BATCH_ID  ;
		Drop temporary table if exists temp_selected_bins;
		
		
		END IF;
	
        
        DELETE FROM stock_audit_wave_wms_data_dsb_upload_validation WHERE `UPLOADED_WAVE_ID`=waveUniqueId;
    END IF;
    
    DROP TEMPORARY TABLE IF EXISTS tmp_invalidRowinWaveData;
END */$$
DELIMITER ;