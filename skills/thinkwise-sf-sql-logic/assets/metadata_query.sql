declare
    @model_id                 NVARCHAR(50)  ='your_model_id',
    @branch_id                NVARCHAR(50)  = 'your_branch_id',
    @tab_ids                  NVARCHAR(MAX) = 'your_first_table,your_second_table',  -- NULL = all tables, comma-separated list to filter e.g. 'brand,order_header'
    @include_details          BIT = 1,               -- Include FK relations where this table is the source (child side)
    @include_lookups          BIT = 1,               -- Include FK relations where this table is the target (parent side)
    @include_tasks            BIT = 1,               -- Include tasks and their parameters
    @include_reports          BIT = 1,               -- Include reports and their parameters
    @include_crud             BIT = 1,               -- Include CRUD options per table (allow_add, allow_update, allow_delete)
    @include_descriptions     BIT = 1,               -- Include description fields; set to 0 to reduce payload size
    @include_domain_elements  BIT = 1,               -- Include domain elements (fixed value lists) per column and parameter
   
    -- Source code filters: each parameter includes one or more prog_object_type_id values
    @include_badge            BIT = 0,               -- BADGE
    @include_change           BIT = 0,               -- CHANGE
    @include_context          BIT = 0,               -- CONTEXT
    @include_default          BIT = 0,               -- DEFAULT
    @include_function         BIT = 0,               -- FUNCTION
    @include_handler          BIT = 0,               -- HANDLE_DELETE, HANDLE_INSERT, HANDLE_UPDATE
    @include_layout           BIT = 0,               -- LAYOUT
    @include_manual           BIT = 0,               -- MANUAL
    @include_process          BIT = 0,               -- PROCESS
    @include_stored_procedure BIT = 0,               -- STORED_PROCEDURE
    @include_task_code        BIT = 0,               -- TASK (code; use @include_tasks for task metadata)
    @include_trigger          BIT = 0,               -- TRIGGER_AFTER_STATEMENT_DEL/INS/UPD, TRIGGER_INSTEAD_OF_STATEMENT_DEL/INS/UPD
    @include_view             BIT = 0                -- VIEW

    SET NOCOUNT ON;

    DECLARE @tables NVARCHAR(MAX);

    -- Legend is only included in compact mode to explain abbreviated field names and datatype codes.
    -- In non-compact mode, field names are self-descriptive.
    DECLARE @legend NVARCHAR(MAX) = N'
    {
        "fields": {
            "id":     "identifier",
            "desc":   "description (omitted when include_descriptions=0)",
            "dom":    "domain_id (omitted when equal to col or param id)",
            "t":      "datatype: S=NVARCHAR/VARCHAR | I=INT/BIGINT/SMALLINT/TINYINT | DT=DATETIME/DATETIME2 | D=DATE | B=BIT | N=NUMERIC/DECIMAL (full type name when compact=0)",
            "m":      "mandatory: 1=required, omitted=optional",
            "dv":     "default_value, omitted when null or empty",
            "co":     "crud_options: C=CREATE | R=READ | U=UPDATE | D=DELETE (omitted when include_crud=0)",
            "elmnts": "domain elements (fixed value list), omitted when domain has no elements or include_domain_elements=0",
            "v":      "db_value of domain element",
            "el":     "elemnt_id of domain element"
        },
        "refs": {
            "detail_refs": "FK relations where this table is the source (child side)",
            "lookup_refs": "FK relations where this table is the target (parent side)",
            "src": "source_tab_id",
            "tgt": "target_tab_id",
            "sc":  "source_col_id",
            "tc":  "target_col_id"
        },
        "tasks":   { "params": "task parameters with their domain and datatype" },
        "reports": { "params": "report parameters with their domain and datatype" },
        "code":    { "type": "prog_object_type_id", "code": "generated source code" }
    }';

    -- Build a datatype mapping table once, shared by both compact and non-compact query variants.
    -- In compact mode, SQL Server types are mapped to single-letter abbreviations to reduce token usage.
    -- In non-compact mode, the original type name is preserved.
    CREATE TABLE #dttp_map (
        dom_id   NVARCHAR(255)  COLLATE database_default NOT NULL,
        dttp     NVARCHAR(255)  COLLATE database_default NOT NULL
    );

    -- Pick the domain source table for this Software Factory version: 2026.2+ moved the
    -- datatype into dom_query, older versions keep it on dom. A static batch that references
    -- a table which does not exist fails to bind (error 208) even inside an untaken IF, so the
    -- table is chosen at run time and the insert runs through sp_executesql. Dynamic SQL runs
    -- in a child scope that still sees the #dttp_map created above.
    DECLARE @dom_source SYSNAME =
        IIF(OBJECT_ID('dom_query', 'U') IS NOT NULL, N'dom_query', N'dom');

    DECLARE @dttp_sql NVARCHAR(MAX) = N'
    INSERT INTO #dttp_map (dom_id, dttp)
    SELECT
        dq.dom_id,
        CASE dq.dttp
                WHEN ''NVARCHAR''  THEN ''S''
                WHEN ''VARCHAR''   THEN ''S''
                WHEN ''INT''       THEN ''I''
                WHEN ''BIGINT''    THEN ''I''
                WHEN ''SMALLINT''  THEN ''I''
                WHEN ''TINYINT''   THEN ''I''
                WHEN ''DATETIME''  THEN ''DT''
                WHEN ''DATETIME2'' THEN ''DT''
                WHEN ''DATE''      THEN ''D''
                WHEN ''BIT''       THEN ''B''
                WHEN ''DECIMAL''   THEN ''N''
                WHEN ''NUMERIC''   THEN ''N''
                ELSE dq.dttp
        END
    FROM ' + QUOTENAME(@dom_source) + N' dq
    WHERE dq.model_id  = @model_id
      AND dq.branch_id = @branch_id;';
    -- Multi-RDBMS models: dom_query can hold one row per RDBMS. If so, add
    --   and dq.rdbms_type = ''<your rdbms>''
    -- to the WHERE inside the string above (note the doubled quotes).

    EXEC sp_executesql
         @dttp_sql,
         N'@model_id NVARCHAR(50), @branch_id NVARCHAR(50)',
         @model_id  = @model_id,
         @branch_id = @branch_id;

    -- Non-compact output: full field names, suitable for developers and small table sets.
    
    -- Compact output: abbreviated field names and datatype codes to minimize token usage.
    -- Includes a self-describing legend block so the output is portable without external documentation.
     SELECT @tables = (
        SELECT
            t.tab_id                                                         AS id,
            IIF(@include_descriptions = 1, t.tab_description, NULL)         AS [desc],
            IIF(@include_crud = 1,
                IIF(t.allow_add    = 1, 'C', '') +
                'R'                              +
                IIF(t.allow_update = 1, 'U', '') +
                IIF(t.allow_delete = 1, 'D', ''),
                NULL
            )                                                                AS co,

            -- Columns with their domain, datatype and optional fixed value list
            (
                SELECT
                    c.col_id                                                              AS id,
                    IIF(@include_descriptions = 1, c.col_description, NULL)               AS [desc],
                    IIF(d.dom_id <> c.col_id, d.dom_id, NULL)                             AS dom,
                    dm.dttp                                                                AS t,
                    IIF(c.mand = 1, 1, NULL)                                              AS m,
                    NULLIF(c.default_value, '')                                            AS dv,
                    (
                        SELECT
                            e.db_value  AS v,
                            e.elemnt_id AS el
                        FROM elemnt e
                        WHERE e.model_id  = d.model_id
                          AND e.branch_id = d.branch_id
                          AND e.dom_id    = d.dom_id
                          AND @include_domain_elements = 1
                        FOR JSON PATH
                    )                                                                      AS elmnts
                FROM col c
                JOIN dom d  ON  d.model_id  = c.model_id
                            AND d.branch_id = c.branch_id
                            AND d.dom_id    = c.dom_id
                JOIN #dttp_map dm ON dm.dom_id = d.dom_id
                WHERE c.model_id  = t.model_id
                  AND c.branch_id = t.branch_id
                  AND c.tab_id    = t.tab_id
                FOR JSON PATH
            ) AS cols,

            -- FK relations where this table is the source (child side)
            (
                SELECT
                    r.ref_id                                                               AS id,
                    IIF(@include_descriptions = 1, r.ref_description, NULL)                AS [desc],
                    r.source_tab_id                                                        AS src,
                    r.target_tab_id                                                        AS tgt,
                    rc.source_col_id                                                       AS sc,
                    rc.target_col_id                                                       AS tc
                FROM ref r
                JOIN ref_col rc ON  rc.model_id  = r.model_id
                                AND rc.branch_id = r.branch_id
                                AND rc.ref_id    = r.ref_id
                WHERE r.model_id       = t.model_id
                  AND r.branch_id      = t.branch_id
                  AND r.source_tab_id  = t.tab_id
                  AND @include_details = 1
                FOR JSON PATH
            ) AS detail_refs,

            -- FK relations where this table is the target (parent side)
            (
                SELECT
                    r.ref_id                                                               AS id,
                    IIF(@include_descriptions = 1, r.ref_description, NULL)                AS [desc],
                    r.source_tab_id                                                        AS src,
                    r.target_tab_id                                                        AS tgt,
                    rc.source_col_id                                                       AS sc,
                    rc.target_col_id                                                       AS tc
                FROM ref r
                JOIN ref_col rc ON  rc.model_id  = r.model_id
                                AND rc.branch_id = r.branch_id
                                AND rc.ref_id    = r.ref_id
                WHERE r.model_id        = t.model_id
                  AND r.branch_id       = t.branch_id
                  AND r.target_tab_id   = t.tab_id
                  AND @include_lookups  = 1
                FOR JSON PATH
            ) AS lookup_refs,

            -- Tasks linked to this table, with their parameters and optional fixed value lists
            (
                SELECT
                    ta.task_id                                                             AS id,
                    IIF(@include_descriptions = 1, ta.task_description, NULL)              AS [desc],
                    (
                        SELECT
                            tp.task_parmtr_id                                              AS id,
                            IIF(@include_descriptions = 1, tp.task_parmtr_description, NULL) AS [desc],
                            IIF(d.dom_id <> tp.task_parmtr_id, d.dom_id, NULL)             AS dom,
                            dm.dttp                                                        AS t,
                            IIF(tp.mand = 1, 1, NULL)                                     AS m,
                            NULLIF(tp.default_value, '')                                   AS dv,
                            (
                                SELECT
                                    e.db_value  AS v,
                                    e.elemnt_id AS el
                                FROM elemnt e
                                WHERE e.model_id  = d.model_id
                                  AND e.branch_id = d.branch_id
                                  AND e.dom_id    = d.dom_id
                                  AND @include_domain_elements = 1
                                FOR JSON PATH
                            )                                                              AS elmnts
                        FROM task_parmtr tp
                        JOIN dom d  ON  d.model_id  = tp.model_id
                                    AND d.branch_id = tp.branch_id
                                    AND d.dom_id    = tp.dom_id
                        JOIN #dttp_map dm ON dm.dom_id = d.dom_id
                        WHERE tp.model_id  = ta.model_id
                          AND tp.branch_id = ta.branch_id
                          AND tp.task_id   = ta.task_id
                        FOR JSON PATH
                    ) AS params
                FROM task ta
                JOIN tab_task tt ON  tt.model_id  = ta.model_id
                                 AND tt.branch_id = ta.branch_id
                                 AND tt.task_id   = ta.task_id
                WHERE tt.model_id    = t.model_id
                  AND tt.branch_id   = t.branch_id
                  AND tt.tab_id      = t.tab_id
                  AND @include_tasks = 1
                FOR JSON PATH
            ) AS tasks,

            -- Reports (prints) linked to this table, with their parameters and optional fixed value lists
            (
                SELECT
                    rp.report_id                                                           AS id,
                    IIF(@include_descriptions = 1, rp.report_description, NULL)            AS [desc],
                    (
                        SELECT
                            rpp.report_parmtr_id                                           AS id,
                            IIF(@include_descriptions = 1, rpp.report_parmtr_description, NULL) AS [desc],
                            IIF(d.dom_id <> rpp.report_parmtr_id, d.dom_id, NULL)          AS dom,
                            dm.dttp                                                        AS t,
                            IIF(rpp.mand = 1, 1, NULL)                                    AS m,
                            NULLIF(rpp.default_value, '')                                  AS dv,
                            (
                                SELECT
                                    e.db_value  AS v,
                                    e.elemnt_id AS el
                                FROM elemnt e
                                WHERE e.model_id  = d.model_id
                                  AND e.branch_id = d.branch_id
                                  AND e.dom_id    = d.dom_id
                                  AND @include_domain_elements = 1
                                FOR JSON PATH
                            )                                                              AS elmnts
                        FROM report_parmtr rpp
                        JOIN dom d  ON  d.model_id  = rpp.model_id
                                    AND d.branch_id = rpp.branch_id
                                    AND d.dom_id    = rpp.dom_id
                        JOIN #dttp_map dm ON dm.dom_id = d.dom_id
                        WHERE rpp.model_id   = rp.model_id
                          AND rpp.branch_id  = rp.branch_id
                          AND rpp.report_id  = rp.report_id
                        FOR JSON PATH
                    ) AS params
                FROM report rp
                JOIN tab_report tr ON  tr.model_id   = rp.model_id
                                   AND tr.branch_id  = rp.branch_id
                                   AND tr.report_id  = rp.report_id
                WHERE tr.model_id      = t.model_id
                  AND tr.branch_id     = t.branch_id
                  AND tr.tab_id        = t.tab_id
                  AND @include_reports = 1
                FOR JSON PATH
            ) AS reports,

            -- Source code objects linked to this table, filtered by type parameters
            (
                SELECT
                    po.prog_object_id                                                      AS id,
                    po.prog_object_type_id                                                 AS type,
                    po.prog_object_generated_code                                          AS code
                FROM prog_object po
                WHERE po.model_id  = t.model_id
                  AND po.branch_id = t.branch_id
                  AND po.tab_id    = t.tab_id
                  AND (   IIF(@include_badge            = 1, 'BADGE'                           , NULL) = po.prog_object_type_id
                       OR IIF(@include_change           = 1, 'CHANGE'                          , NULL) = po.prog_object_type_id
                       OR IIF(@include_context          = 1, 'CONTEXT'                         , NULL) = po.prog_object_type_id
                       OR IIF(@include_default          = 1, 'DEFAULT'                         , NULL) = po.prog_object_type_id
                       OR IIF(@include_function         = 1, 'FUNCTION'                        , NULL) = po.prog_object_type_id
                       OR IIF(@include_handler          = 1, 'HANDLE_DELETE'                   , NULL) = po.prog_object_type_id
                       OR IIF(@include_handler          = 1, 'HANDLE_INSERT'                   , NULL) = po.prog_object_type_id
                       OR IIF(@include_handler          = 1, 'HANDLE_UPDATE'                   , NULL) = po.prog_object_type_id
                       OR IIF(@include_layout           = 1, 'LAYOUT'                          , NULL) = po.prog_object_type_id
                       OR IIF(@include_manual           = 1, 'MANUAL'                          , NULL) = po.prog_object_type_id
                       OR IIF(@include_process          = 1, 'PROCESS'                         , NULL) = po.prog_object_type_id
                       OR IIF(@include_stored_procedure = 1, 'STORED_PROCEDURE'                , NULL) = po.prog_object_type_id
                       OR IIF(@include_task_code        = 1, 'TASK'                            , NULL) = po.prog_object_type_id
                       OR IIF(@include_trigger          = 1, 'TRIGGER_AFTER_STATEMENT_DEL'     , NULL) = po.prog_object_type_id
                       OR IIF(@include_trigger          = 1, 'TRIGGER_AFTER_STATEMENT_INS'     , NULL) = po.prog_object_type_id
                       OR IIF(@include_trigger          = 1, 'TRIGGER_AFTER_STATEMENT_UPD'     , NULL) = po.prog_object_type_id
                       OR IIF(@include_trigger          = 1, 'TRIGGER_INSTEAD_OF_STATEMENT_DEL', NULL) = po.prog_object_type_id
                       OR IIF(@include_trigger          = 1, 'TRIGGER_INSTEAD_OF_STATEMENT_INS', NULL) = po.prog_object_type_id
                       OR IIF(@include_trigger          = 1, 'TRIGGER_INSTEAD_OF_STATEMENT_UPD', NULL) = po.prog_object_type_id
                       OR IIF(@include_view             = 1, 'VIEW'                            , NULL) = po.prog_object_type_id
                      )
                FOR JSON PATH
            ) AS code
        FROM tab t
        WHERE t.model_id  = @model_id
          AND t.branch_id = @branch_id
          AND (
                @tab_ids IS NULL
                OR t.tab_id IN (
                    SELECT TRIM(value)
                    FROM STRING_SPLIT(@tab_ids, ',')
                    WHERE TRIM(value) <> ''
                )
              )
        FOR JSON PATH
    );

    DROP TABLE #dttp_map;

    -- Return compact output as a self-describing root object with legend + tables.
       select
            JSON_QUERY(@legend)  AS legend,
            JSON_QUERY(@tables)  AS tables
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
