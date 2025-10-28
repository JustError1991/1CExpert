-- Создаем временную таблицу для хранения списка баз данных
DECLARE @DatabaseList TABLE (
    DatabaseName NVARCHAR(255),
    Processed BIT DEFAULT 0
);

-- Заполняем список пользовательских баз данных (исключаем системные)
INSERT INTO @DatabaseList (DatabaseName)
SELECT name 
FROM sys.databases 
WHERE database_id > 4  -- Исключаем системные базы
AND state = 0  -- Только онлайн базы
AND recovery_model_desc != 'SIMPLE'  -- Только базы не в SIMPLE режиме
AND name NOT IN ('model', 'msdb', 'distribution');  -- Дополнительные исключения

-- Объявляем переменные для цикла
DECLARE @DatabaseName NVARCHAR(255);
DECLARE @SQL NVARCHAR(MAX);

-- Цикл по всем базам данных
WHILE EXISTS (SELECT 1 FROM @DatabaseList WHERE Processed = 0)
BEGIN
    -- Выбираем следующую базу для обработки
    SELECT TOP 1 @DatabaseName = DatabaseName FROM @DatabaseList WHERE Processed = 0;
    
    -- Формируем динамический SQL для перевода в SIMPLE recovery mode
    SET @SQL = N'ALTER DATABASE [' + @DatabaseName + '] SET RECOVERY SIMPLE WITH NO_WAIT;';
    
    BEGIN TRY
        -- Выполняем изменение режима восстановления
        EXEC sp_executesql @SQL;
        
        -- Формируем запрос для сжатия лог-файла
        SET @SQL = N'USE [' + @DatabaseName + ']; DBCC SHRINKFILE(2, 1);'; -- 2 обычно это лог-файл
        
        -- Выполняем сжатие лог-файла
        EXEC sp_executesql @SQL;
        
        PRINT N'Успешно обработана база: ' + @DatabaseName;
    END TRY
    BEGIN CATCH
        PRINT N'Ошибка при обработке базы ' + @DatabaseName + ': ' + ERROR_MESSAGE();
    END CATCH
    
    -- Помечаем базу как обработанную
    UPDATE @DatabaseList SET Processed = 1 WHERE DatabaseName = @DatabaseName;
END

PRINT N'Обработка всех баз завершена.';