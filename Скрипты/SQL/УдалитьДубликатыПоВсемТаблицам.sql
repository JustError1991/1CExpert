DECLARE 
    @DatabaseName NVARCHAR(128) = 'ERP_prod_recovery',  -- Укажите имя базы данных
    @TableList NVARCHAR(MAX) = '_Document82801,_Document881,_Document884,_Document898,_InfoRg41037,_InfoRg41112,_InfoRg41623',  -- Оставьте NULL для всех таблиц
    @Execute BIT = 0;  -- 1 - выполнить скрипт, 0 - только вывести

DECLARE @Sql NVARCHAR(MAX) = '
USE ' + QUOTENAME(@DatabaseName) + ';
DECLARE @TableSchema NVARCHAR(128), @TableName NVARCHAR(128);
DECLARE @Execute BIT = 0;  -- 1 - выполнить скрипт, 0 - только вывести
DECLARE TableCursor CURSOR LOCAL FORWARD_ONLY READ_ONLY FOR
    SELECT s.name, t.name
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE EXISTS (
        SELECT 1 FROM sys.indexes i 
        WHERE i.object_id = t.object_id AND i.type = 1
    )
    AND (' + CASE WHEN @TableList IS NULL THEN '1=1' ELSE 
        't.name IN (SELECT VALUE FROM STRING_SPLIT(@TableList, '',''))' END + ');

OPEN TableCursor;
FETCH NEXT FROM TableCursor INTO @TableSchema, @TableName;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @Columns NVARCHAR(MAX) = '''';
    SELECT @Columns += QUOTENAME(c.name) + '', ''
    FROM sys.indexes i
    JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
    JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
    WHERE i.type = 1 AND i.object_id = OBJECT_ID(QUOTENAME(@TableSchema) + ''.'' + QUOTENAME(@TableName))
    ORDER BY ic.key_ordinal;

    SET @Columns = LEFT(@Columns, LEN(@Columns) - 1);

    DECLARE @DeleteSql NVARCHAR(MAX) = ''
		IF EXISTS (
			SELECT 1 
			FROM INFORMATION_SCHEMA.TABLES 
			WHERE TABLE_SCHEMA = '''''' + @TableSchema + ''''''
			AND TABLE_NAME = '''''' + @TableName + ''''''
			AND TABLE_TYPE = ''''BASE TABLE''''
			)
		BEGIN
			WITH DuplicatesCTE AS (
				SELECT *, ROW_NUMBER() OVER (PARTITION BY '' + @Columns + '' ORDER BY (SELECT NULL)) AS RowNum
				FROM '' + QUOTENAME(@TableSchema) + ''.'' + QUOTENAME(@TableName) + ''
			)
			DELETE FROM DuplicatesCTE WHERE RowNum > 1;
		END
    '';

    --PRINT ''Таблица: '' + @TableSchema + ''.'' + @TableName;
    --PRINT ''Столбцы индекса: '' + @Columns;
    --PRINT ''SQL: '' + @DeleteSql;
    --PRINT ''---'';
	PRINT @DeleteSql;
    PRINT ''---'';

    IF @Execute = 1
        EXEC sp_executesql @DeleteSql;

    FETCH NEXT FROM TableCursor INTO @TableSchema, @TableName;
END

CLOSE TableCursor;
DEALLOCATE TableCursor;';

EXEC sp_executesql @Sql, N'@TableList NVARCHAR(MAX)', @TableList;