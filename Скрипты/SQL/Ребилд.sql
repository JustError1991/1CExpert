Use ERP_prod;

declare @date_start datetime;
declare @cmd nvarchar(max),@tb_name nvarchar(max),@in_name nvarchar(max),@in_type tinyint;
declare @ver nvarchar(200) = @@VERSION;
declare @err_count int = 0;
declare @err_msg nvarchar(max) = '';
declare @msg nvarchar(500);

set @ver = case when CHARINDEX('Enterprise', @ver) > 0 or CHARINDEX('Developer', @ver) > 0 then 'Enterprise' else 'Standart' end;

declare cursor_table cursor for
SELECT
 OBJECT_NAME(ips.object_id) AS [TABLE NAME],
 i.name AS [INDEX NAME],
  i.type AS [INDEX TYPE]
FROM sys.dm_db_index_physical_stats(DB_ID(), default, default, default, 'SAMPLED') AS ips
 INNER JOIN sys.indexes AS i 
 ON ips.object_id = i.object_id AND ips.index_id = i.index_id
where
 ips.avg_fragmentation_in_percent >= 30 and ips.page_count >= 1000
 --and OBJECT_NAME(ips.object_id) <> '_InfoRg10000X1'
ORDER BY 
 ips.page_count DESC;

open cursor_table
FETCH NEXT FROM cursor_table into @tb_name,@in_name,@in_type;
WHILE @@FETCH_STATUS = 0
BEGIN
 set @cmd = 'Use [' + DB_NAME() +  ']; alter index [' + @in_name + '] on [' + @tb_name + '] rebuild with (online=' + case when @ver = 'Standart' or @in_type in (1,3)  then 'off' else 'on' end + ');';
 begin try
  set @date_start = GETDATE();
  EXECUTE sp_executesql @cmd;
  print 'Обработан: ' + @cmd + ' duration = ' + CAST(DATEDIFF(second,@date_start,GETDATE()) AS varchar(6)) + ' sec.';
 end try
 begin catch
  set @err_count = @err_count + 1;
  set @msg = 'Пропущен: ' + '[' + DB_NAME() + '].[' + @tb_name + '].[' + @in_name + '], error: ' + ERROR_MESSAGE();
  if @err_count <=10
   set @err_msg = @err_msg + ' ' + @msg;
  print @msg;
 end catch;
 FETCH NEXT FROM cursor_table into @tb_name,@in_name,@in_type;
END;

CLOSE cursor_table;
DEALLOCATE cursor_table;

if @err_count > 0 
begin 
 set @err_msg = 'Error count: ' + Str(@err_count) + ', ' + @err_msg;
 THROW 51000,@err_msg,1;
end
