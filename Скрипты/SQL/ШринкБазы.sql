use [ERP_dev_aspasskiy] -- Выберите базу для шринка

set NOCOUNT ON;

DECLARE @PortionInMB INT = 1000 -- Замените на нужное значение, количество МБ. освобождаемое за итерацию
DECLARE @StopSizeInMB INT = 2000 -- Количество свободного места в базе, при котором нужно прекратить шринк
DECLARE @CurrentSizeInMB INT
DECLARE @FreeSpaceInMB INT
DECLARE @CurrentDBName nvarchar(64) = DB_NAME()
DECLARE @MomentumSize INT
DECLARE @StartTime datetime2
DECLARE @EndTime datetime2
DECLARE @IterationTime INT
DECLARE @RequiredSeconds INT

SET @FreeSpaceInMB = (select convert(decimal(12,2),round((a.size-fileproperty(a.name,'SpaceUsed'))/128.000,2)) as FreeSpaceMB from dbo.sysfiles a where status & 64 = 0)
WHILE @FreeSpaceInMB > @StopSizeInMB
BEGIN 
    SET @CurrentSizeInMB = (select convert(decimal(12,2),round(a.size/128.000,2)) as FileSizeMB from dbo.sysfiles a where status & 64 = 0)
    SET @FreeSpaceInMB = (select convert(decimal(12,2),round((a.size-fileproperty(a.name,'SpaceUsed'))/128.000,2)) as FreeSpaceMB from dbo.sysfiles a where status & 64 = 0)
	SET @MomentumSize = @CurrentSizeInMB - @PortionInMB

    IF @FreeSpaceInMB > @StopSizeInMB
    BEGIN
		SET @StartTime = CURRENT_TIMESTAMP
		print CONVERT(VARCHAR(100), CURRENT_TIMESTAMP) + ': Start shrink iteration for database [' + @CurrentDBName + ']. From ' + CONVERT(VARCHAR(100), @CurrentSizeInMB) 
			+ ' to ' + CONVERT(VARCHAR(100), @MomentumSize) + '. Remains: ' + CONVERT(VARCHAR(100), @FreeSpaceInMB - @PortionInMB - @StopSizeInMB) + ' Mb.'
		RAISERROR('',0,1) WITH NOWAIT
		DBCC SHRINKFILE ('ERP_prod', @MomentumSize)
		SET @EndTime = CURRENT_TIMESTAMP
		SET @RequiredSeconds = (@FreeSpaceInMB - @StopSizeInMB) / @PortionInMB * datediff(s, @StartTime, @EndTime)
		print 'Iteration successfull on ' + CONVERT(VARCHAR(100), datediff(s, @StartTime, @EndTime)) + ' sec. The required time for all iteration: '
			+ CONVERT(VARCHAR(100), @RequiredSeconds) + ' sec. Completion time: ' + CONVERT(VARCHAR(100), DATEADD(s,@RequiredSeconds,CURRENT_TIMESTAMP))
		RAISERROR( '',0,1) WITH NOWAIT
    END
    ELSE
    BEGIN
        BREAK;
    END
END