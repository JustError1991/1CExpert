-------------------------------------------
-- НАСТРАИВАЕМЫЕ ПЕРЕМЕННЫЕ
-- База данных назначения
DECLARE @DBName_To as nvarchar(40) = 'ERP_daily2'
-- База данных источник      
DECLARE @DBName_From as nvarchar(40) = 'ERP_daily1'
-- Каталог для резервной копии
DECLARE @Path as nvarchar(400) = 'M:\backup\BackupCopyOnly'
-- Каталог для урезанного бекапа копии
DECLARE @Path_to as nvarchar(400) = 'M:\backup\ShortBackup'
-- Имя почтового профиля, для отправки электонной почты         
DECLARE @profile_name as nvarchar(100) = ''
-- Получатели сообщений электронной почты, разделенные знаком ";"    
DECLARE @recipients as nvarchar(500) = ''

-------------------------------------------
-- СЛУЖЕБНЫЕ ПЕРЕМЕННЫЕ 
DECLARE @SQLString NVARCHAR(4000)
DECLARE @backupfile NVARCHAR(500)
DECLARE @backupfile_to NVARCHAR(500)
DECLARE @physicalName NVARCHAR(500), @logicalName NVARCHAR(500)
DECLARE @out as int = 0
DECLARE @subject as NVARCHAR(100) = ''
DECLARE @finalmassage as NVARCHAR(1000) = ''

-------------------------------------------
-- ТЕЛО СКРИПТА
use master

-- 1. Создаем резервную копию с флагом "Только резервное копирование"
-- Формируем строку для исполнения
SET @backupfile = @Path + '\\' + @DBName_From + '_' + Replace(CONVERT(nvarchar, GETDATE(), 126),':','-') + '.bak'
SET @SQLString = 
 N'BACKUP DATABASE [' + @DBName_From + ']
 TO DISK = N''' + @backupfile + '''  
 WITH NOFORMAT, NOINIT,
 SKIP, NOREWIND, NOUNLOAD, STATS = 10, COPY_ONLY'

-- Выводим и выполняем полученную инструкцию
PRINT @SQLString
BEGIN TRY 
	EXEC sp_executesql @SQLString
END TRY
BEGIN CATCH  
	 -- Ошбика выполнения операции
	 SET @subject = 'ОШИБКА Создания BACKUP DATABASE резервной копии базы ' + @DBName_From
	 SET @finalmassage = 'Ошибка создания BACKUP DATABASE резервной копии базы ' + @DBName_From + ' в каталог ' + @Path + CHAR(13) + CHAR(13)
	  + 'Код ошибки: ' + CAST(ERROR_NUMBER() as nvarchar(10)) + CHAR(13) + CHAR(13)
	  + 'Текст ошибки: ' + ERROR_MESSAGE()  + CHAR(13) + CHAR(13)
	  + 'Текст T-SQL:' + CHAR(13) + @SQLString  
END CATCH;

-- 2. Загружаем полученный файл резервной копии
IF @subject = ''
BEGIN
	 -- Формируем строку для исполнения 
	 SET @SQLString = 
	 N'ALTER DATABASE [' + @DBName_To + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE
	 RESTORE DATABASE [' + @DBName_To + ']
	 FROM DISK = N''' + @backupfile + '''   
	 WITH  
	 FILE = 1,'

	 -- Переименуем файлы базы данных на исходные
	 -- Новый цикл по всем файлам базы данных
	 DECLARE fnc CURSOR LOCAL FAST_FORWARD FOR 
	 (
	  SELECT
	   t_From.name,
	   t_To.physical_name
	  FROM sys.master_files as t_To 
	   join sys.master_files as t_From 
	   on t_To.file_id = t_From.file_id
	  WHERE t_To.database_id = DB_ID(@DBName_To) 
	   and t_From.database_id = DB_ID(@DBName_From)
	 )
	 OPEN fnc;
	 FETCH fnc INTO @logicalName, @physicalName;
	 WHILE @@FETCH_STATUS=0
		BEGIN
		   SET @SQLString = @SQLString + '
		   MOVE N''' + @logicalName + ''' TO N''' + @physicalName + ''','
		   FETCH fnc INTO @logicalName, @physicalName;
		END;
	 CLOSE fnc;
	 DEALLOCATE fnc;

	 SET @SQLString = @SQLString + '
	 RECOVERY,
	 NOUNLOAD,
	 REPLACE,
	 STATS = 5'

	 -- Выводим и выполняем полученную инструкцию
	 PRINT @SQLString
	 BEGIN TRY 
		EXEC sp_executesql @SQLString
	 END TRY
	 BEGIN CATCH  
		-- Ошбика выполнения операции
		SET @subject = 'ОШИБКА ВОССТАНОВЛЕНИЯ RESTORE DATABASE базы данных ' + @DBName_To
		SET @finalmassage = 'Ошибка восстановления RESTORE DATABASE полной резервной копии для базы данных ' + @DBName_To + CHAR(13) + CHAR(13)
		 + 'Код ошибки: ' + CAST(ERROR_NUMBER() as nvarchar(10)) + CHAR(13) + CHAR(13)
		 + 'Текст ошибки: ' + ERROR_MESSAGE()  + CHAR(13) + CHAR(13)
		 + 'Текст T-SQL:' + CHAR(13) + @SQLString  
	 END CATCH;
END

-- 3. Удаляем технические таблицы
IF @subject = ''
BEGIN
	SET @SQLString = 
	N'USE [' + @DBName_To + ']
	TRUNCATE TABLE _InfoRg82110X1
	TRUNCATE TABLE _InfoRg82105X1
	TRUNCATE TABLE _InfoRgSL85989X1
	TRUNCATE TABLE _InfoRg82113X1
	TRUNCATE TABLE _Reference81493
	TRUNCATE TABLE _InfoRg44172
	TRUNCATE TABLE _InfoRg43101
	TRUNCATE TABLE _Reference80704X1
	TRUNCATE TABLE _Reference80707X1
	TRUNCATE TABLE _Reference80707_VT81740X1
	TRUNCATE TABLE _DataHistoryQueue0
	' 
	PRINT @SQLString
	BEGIN TRY 
		EXEC sp_executesql @SQLString
	END TRY
	BEGIN CATCH  
	-- Ошбика выполнения операции
	SET @subject = 'ОШИБКА TRUNCATE базы данных ' + @DBName_To
	SET @finalmassage = 'Ошибка TRUNCATE базы данных ' + @DBName_To + CHAR(13) + CHAR(13)
	+ 'Код ошибки: ' + CAST(ERROR_NUMBER() as nvarchar(10)) + CHAR(13) + CHAR(13)
	+ 'Текст ошибки: ' + ERROR_MESSAGE()  + CHAR(13) + CHAR(13)
	+
	'Текст T-SQL:' + CHAR(13) + @SQLString  
	END CATCH;	
END

-- 4. Переводим базу в простую модель восстановления
IF @subject = ''
BEGIN 
 
 -- Формируем строку для исполнения
 SET @SQLString = 'ALTER DATABASE ' + @DBName_To + ' SET RECOVERY SIMPLE;'
 
 -- Выводим и выполняем полученную инструкцию
 PRINT @SQLString
 BEGIN TRY 
  EXEC sp_executesql @SQLString
 END TRY
 BEGIN CATCH  
  -- Ошбика выполнения операции
  SET @subject = 'ОШИБКА ВОССТАНОВЛЕНИЯ SIMPLE базы данных ' + @DBName_To
  SET @finalmassage = 'Ошибка перевода в SIMPLE простую модель восстановления базы данных ' + @DBName_To + CHAR(13) + CHAR(13)
   + 'Код ошибки: ' + CAST(ERROR_NUMBER() as nvarchar(10)) + CHAR(13) + CHAR(13)
   + 'Текст ошибки: ' + ERROR_MESSAGE()  + CHAR(13) + CHAR(13)
   +
'Текст T-SQL:' + CHAR(13) + @SQLString  
 END CATCH;
END

-- 5. Запускаем сжатие базы данных
IF @subject = ''
BEGIN

 -- Формируем строку для исполнения
 --SET @SQLString = 'DBCC SHRINKDATABASE(N''' + @DBName_To + ''');'
 SET @SQLString = 'USE [' + @DBName_To + '] -- Выберите базу для шринка

	set NOCOUNT ON;
	
	DECLARE @PortionInMB INT = 1000 -- Замените на нужное значение, количество МБ. освобождаемое за итерацию
	DECLARE @CurrentSizeInMB INT
	DECLARE @FreeSpaceInMB INT
	DECLARE @StopSizeInMB INT = 5000 -- Количество свободного места в базе, при котором нужно прекратить шринк
	DECLARE @CurrentDBName nvarchar(64) = DB_NAME()
	DECLARE @MomentumSize INT
	DECLARE @StartTime datetime2
	DECLARE @EndTime datetime2
	DECLARE @IterationTime INT
	DECLARE @RequiredSeconds INT
	
	SET @FreeSpaceInMB = (select convert(decimal(12,2),round((a.size-fileproperty(a.name,''SpaceUsed''))/128.000,2)) as FreeSpaceMB from dbo.sysfiles a where status & 64 = 0)
	WHILE @FreeSpaceInMB > @StopSizeInMB
	BEGIN 
		SET @CurrentSizeInMB = (select convert(decimal(12,2),round(a.size/128.000,2)) as FileSizeMB from dbo.sysfiles a where status & 64 = 0)
		SET @FreeSpaceInMB = (select convert(decimal(12,2),round((a.size-fileproperty(a.name,''SpaceUsed''))/128.000,2)) as FreeSpaceMB from dbo.sysfiles a where status & 64 = 0)
		SET @MomentumSize = @CurrentSizeInMB - @PortionInMB
	
		IF @FreeSpaceInMB > @StopSizeInMB
		BEGIN
			SET @StartTime = CURRENT_TIMESTAMP
			print CONVERT(VARCHAR(100), CURRENT_TIMESTAMP) + '': Start shrink iteration for database ['' + @CurrentDBName + '']. From '' + CONVERT(VARCHAR(100), @CurrentSizeInMB) 
				+ '' to '' + CONVERT(VARCHAR(100), @MomentumSize) + ''. Remains: '' + CONVERT(VARCHAR(100), @FreeSpaceInMB - @PortionInMB - @StopSizeInMB) + '' Mb.''
			RAISERROR('''',0,1) WITH NOWAIT
			DBCC SHRINKFILE (''ERP_prod'', @MomentumSize)
			SET @EndTime = CURRENT_TIMESTAMP
			SET @RequiredSeconds = (@FreeSpaceInMB - @StopSizeInMB) / @PortionInMB * datediff(s, @StartTime, @EndTime)
			--print ''Iteration successfull on '' + CONVERT(VARCHAR(100), datediff(s, @StartTime, @EndTime)) + '' sec. The required time for all iteration: ''
			--	+ CONVERT(VARCHAR(100), @RequiredSeconds) + '' sec. Completion time: '' + CONVERT(VARCHAR(100), DATEADD(s,@RequiredSeconds,CURRENT_TIMESTAMP))
			RAISERROR('''',0,1) WITH NOWAIT
		END
		ELSE
		BEGIN
			BREAK;
		END
	END'
	     
 -- Выводим и выполняем полученную инструкцию
 PRINT @SQLString
 BEGIN TRY 
  EXEC sp_executesql @SQLString
 END TRY
 BEGIN CATCH  
  -- Ошбика выполнения операции
  SET @subject = 'ОШИБКА SHRINKFILE базы данных ' + @DBName_To
  SET @finalmassage = 'Ошибка сжатия SHRINKFILE базы данных ' + @DBName_To + CHAR(13) + CHAR(13)
   + 'Код ошибки: ' + CAST(ERROR_NUMBER() as nvarchar(10)) + CHAR(13) + CHAR(13)
   + 'Текст ошибки: ' + ERROR_MESSAGE()  + CHAR(13) + CHAR(13)
   + 'Текст T-SQL:' + CHAR(13) + @SQLString  
 END CATCH;
END 

--6. перевод в MULTI_USER
IF @subject = ''
BEGIN
	SET @SQLString = 'ALTER DATABASE [' + @DBName_To + '] SET MULTI_USER'
	PRINT @SQLString
	BEGIN TRY 
		EXEC sp_executesql @SQLString
	END TRY
	BEGIN CATCH  
	  -- Ошбика выполнения операции
		SET @subject = 'ОШИБКА MULTI_USER базы данных ' + @DBName_To
		SET @finalmassage = 'Ошибка перевода в MULTI_USER базы данных ' + @DBName_To + CHAR(13) + CHAR(13)
		 + 'Код ошибки: ' + CAST(ERROR_NUMBER() as nvarchar(10)) + CHAR(13) + CHAR(13)
		 + 'Текст ошибки: ' + ERROR_MESSAGE()  + CHAR(13) + CHAR(13)
		 + 'Текст T-SQL:' + CHAR(13) + @SQLString  
	END CATCH;
END

-- 7. Запускаем бекап урезанной базы данных
IF @subject = ''
BEGIN
	SET @backupfile_to = @Path_to + '\\' + @DBName_To + '_' + Replace(CONVERT(nvarchar, GETDATE(), 126),':','-') + '.bak'
	SET @SQLString = 
	 N'BACKUP DATABASE [' + @DBName_To + ']
	 TO DISK = N''' + @backupfile_to + '''  
	 WITH NOFORMAT, NOINIT,
	 SKIP, NOREWIND, NOUNLOAD, STATS = 10, COPY_ONLY'

	-- Выводим и выполняем полученную инструкцию
	PRINT @SQLString
	BEGIN TRY 
	 EXEC sp_executesql @SQLString
	END TRY
	BEGIN CATCH  
	 -- Ошбика выполнения операции
	 SET @subject = 'ОШИБКА Создания BACKUP DATABASE резервной копии базы ' + @DBName_From
	 SET @finalmassage = 'Ошибка создания BACKUP DATABASE резервной копии базы ' + @DBName_From + ' в каталог ' + @Path + CHAR(13) + CHAR(13)
	  + 'Код ошибки: ' + CAST(ERROR_NUMBER() as nvarchar(10)) + CHAR(13) + CHAR(13)
	  + 'Текст ошибки: ' + ERROR_MESSAGE()  + CHAR(13) + CHAR(13)
	  + 'Текст T-SQL:' + CHAR(13) + @SQLString  
	END CATCH;
END

-- 8. Если файл был создан, удалим файл резервной копии
BEGIN TRY
 EXEC master.dbo.xp_fileexist @backupfile, @out out
 IF @out = 1 EXEC master.dbo.xp_delete_file 0, @backupfile
END TRY
BEGIN CATCH  
 -- Ошбика выполнения операции
 SET @subject = 'ОШИБКА ВОССТАНОВЛЕНИЯ базы данных ' + @DBName_To
 SET @finalmassage = 'Ошибка удаления файла резервной копии ' + @backupfile + CHAR(13) + CHAR(13)
  + 'Код ошибки: ' + CAST(ERROR_NUMBER() as nvarchar(10)) + CHAR(13) + CHAR(13)
  + 'Текст ошибки: ' + ERROR_MESSAGE()  + CHAR(13) + CHAR(13)
  + 'Текст T-SQL:' + CHAR(13) + 'master.dbo.xp_delete_file 0, ' + @backupfile  
END CATCH;
 
-- 9.Если ошибок не было, сформируем текст сообщения
IF @subject = ''
BEGIN
 -- Успешное выполнение всех операций
 SET @subject = 'Успешное восстановление базы данных ' + @DBName_To
 SET @finalmassage = 'Успешное восстановление базы данных ' + @DBName_To + ' из резервной копии базы данных ' + @DBName_From
END

-- 10. Если задан профиль электронной почты, отправим сообщение
IF @profile_name <> ''
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = @profile_name,
    @recipients = @recipients,
    @body = @finalmassage,
    @subject = @subject;

-- Выводим сообщение о результате
SELECT
 @subject as subject,
 @finalmassage as finalmassage

GO