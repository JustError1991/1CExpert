Use ERP_prod;

declare @date_start datetime;
declare @cmd nvarchar(max),@tb_name nvarchar(max),@st_name nvarchar(max);

declare cursor_table cursor for
select
 OBJECT_NAME(stat.object_id) as [TABLE NAME],
 stat.name as [STAT NAME]
from
 sys.stats AS stat
 CROSS APPLY sys.dm_db_stats_properties(stat.object_id, stat.stats_id) AS stat_prop
where 
 stat_prop.rows > 1 and stat_prop.modification_counter > 100 
 and OBJECT_NAME(stat.object_id) <> '_Document10000_VT10000X1'
order by
 CAST(100.0*stat_prop.rows_sampled/stat_prop.rows AS decimal(15,2)),
 CAST(100.0*stat_prop.modification_counter/stat_prop.rows AS decimal(15,2)) DESC;

open cursor_table
FETCH NEXT FROM cursor_table into @tb_name,@st_name;
WHILE @@FETCH_STATUS = 0
BEGIN
 set @cmd = 'Use [' + DB_NAME() +  ']; update statistics [' + @tb_name + '] [' + @st_name + '] with fullscan;';
 begin try
  set @date_start = GETDATE();
  EXECUTE sp_executesql @cmd;
  print 'Обработан: ' + @cmd + ' duration = ' + CAST(DATEDIFF(second,@date_start,GETDATE()) AS varchar(6)) + ' sec.';
 end try
 begin catch
  print 'Пропущен: ' + '[' + DB_NAME() + '].[' + @tb_name + '].[' + @st_name + '], error: ' + ERROR_MESSAGE();
 end catch;
 FETCH NEXT FROM cursor_table into @tb_name,@st_name;
END;

CLOSE cursor_table;
DEALLOCATE cursor_table;
