-- получить текущий местоположение
SELECT 'ALTER DATABASE ''tempdb'' MODIFY FILE ( NAME = '+[name]+', FILENAME = '+[physical_name]+' )'
FROM sys.master_files
WHERE database_id = DB_ID(N'tempdb');

-- замена файлов
ALTER DATABASE tempdb MODIFY FILE ( NAME = tempdev, FILENAME = 'T:\DATA\tempdb.mdf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, FILENAME = 'L:\LOG\templog.ldf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp2, FILENAME = 'T:\DATA\tempdb_mssql_2.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp3, FILENAME = 'T:\DATA\tempdb_mssql_3.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp4, FILENAME = 'T:\DATA\tempdb_mssql_4.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp5, FILENAME = 'T:\DATA\tempdb_mssql_5.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp6, FILENAME = 'T:\DATA\tempdb_mssql_6.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp7, FILENAME = 'T:\DATA\tempdb_mssql_7.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp8, FILENAME = 'T:\DATA\tempdb_mssql_8.ndf' )

-- вернуть обратно
ALTER DATABASE tempdb MODIFY FILE ( NAME = tempdev, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\tempdb.mdf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\templog.ldf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp2, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\tempdb_mssql_2.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp3, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\tempdb_mssql_3.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp4, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\tempdb_mssql_4.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp5, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\tempdb_mssql_5.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp6, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\tempdb_mssql_6.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp7, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\tempdb_mssql_7.ndf' )
ALTER DATABASE tempdb MODIFY FILE ( NAME = temp8, FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\tempdb_mssql_8.ndf' )