-- Удалить дубли ТЧ
WITH DuplicatesCTE AS (
    SELECT
		[_Reference328_IDRRef]
		,[_KeyField]
		,[_LineNo66135]
		,[_Fld66136RRef]
		,[_Fld66137RRef] 
		,ROW_NUMBER() OVER (PARTITION BY 
			[_Reference328_IDRRef]
			,[_KeyField]
			,[_LineNo66135]
			,[_Fld66136RRef]
			,[_Fld66137RRef] 
			ORDER BY 
			[_KeyField] DESC) AS RowNum
    FROM [Recovered_ERP_prod].[dbo].[_Reference328_vt66134x1]
)
DELETE FROM DuplicatesCTE
WHERE RowNum > 1;

-- Удалить справочника
WITH DuplicatesCTE AS (
    SELECT
		[_IDRRef],
        [_Version],
        ROW_NUMBER() OVER (PARTITION BY 
			[_IDRRef] 
			ORDER BY 
			[_Version] DESC) AS RowNum
    FROM [Recovered_ERP_prod].[dbo].[_Reference198x1]
)
DELETE FROM DuplicatesCTE
WHERE RowNum > 1;