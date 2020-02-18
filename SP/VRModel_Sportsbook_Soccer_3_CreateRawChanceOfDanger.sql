ALTER PROCEDURE [dbo].[VRModel_Sportsbook_Soccer_3_CreateRawChanceOfDanger]
AS
/*
	Created: 20200212@Long.Luu
	Task : 
	DB: bodb_VR2Model
	Original:

	Revisions:
		- 20200212@Long.Luu: Created [Redmine ID: #127584]

	Param's Explanation:
*/
BEGIN

	SET NOCOUNT ON;

	TRUNCATE TABLE dbo.[VR2Model_RawChanceOfDanger];
		
	DECLARE @maxWeekOrder INT;
	DECLARE @week INT = 1;
	DECLARE @marginRange NUMERIC(3,2);	

	SELECT @maxWeekOrder = MAX(c.WeekOrder) FROM DBO.VR2Model_CumulativeMarginByWeek AS c WITH(NOLOCK);
	
	WHILE(@week <= @maxWeekOrder)
		BEGIN
			SET @marginRange = 0.1;
			WHILE(@marginRange >= -0.1 AND @week <= @maxWeekOrder)
				BEGIN
					INSERT INTO dbo.[VR2Model_RawChanceOfDanger](MarginRange, WeekOrder, PercentageOfWin)
					SELECT @marginRange, @week, CASE WHEN @marginRange > 0 THEN 1 ELSE 0 END;
					
					SET @marginRange = @marginRange - 0.01;
				 END;
			
			SET @week = @week + 1;
		END;

	UPDATE r WITH (ROWLOCK, UPDLOCK)
	SET PercentageOfWin = tmp.PercentageOfWin 
	FROM dbo.[VR2Model_RawChanceOfDanger] AS r
		INNER JOIN (	
						SELECT	w.MarginRange
							,	w.WeekOrder
							,	CAST(w.NumOfWinner AS FLOAT) / (w.NumOfWinner + l.NumOfLoser) AS 'PercentageOfWin'
						FROM dbo.[VR2Model_WinnerByWeekCounter] AS w WITH(NOLOCK)
							INNER JOIN dbo.[VR2Model_LoserByWeekCounter] AS l WITH(NOLOCK) ON w.MarginRange = l.MarginRange AND w.WeekOrder = l.WeekOrder
					
					) AS tmp ON tmp.MarginRange = r.MarginRange AND tmp.WeekOrder = r.WeekOrder;

	;WITH cte AS
	(
		SELECT r.MarginRange, MIN(r.WeekOrder) AS StartIndex
		FROM dbo.[VR2Model_RawChanceOfDanger] AS r WITH(NOLOCK)
		WHERE r.PercentageOfWin = 1 OR r.PercentageOfWin = 0
		GROUP BY r.MarginRange
	)
	UPDATE r2 WITH (ROWLOCK, UPDLOCK)
	SET r2.PercentageOfWin = (CASE WHEN r2.MarginRange > 0 THEN 1 ELSE 0 END)
	FROM cte AS r1
		INNER JOIN dbo.[VR2Model_RawChanceOfDanger] AS r2 ON r1.MarginRange = r2.MarginRange
	WHERE r2.WeekOrder > r1.StartIndex;

END;

/*<info serverAlias="DBFS-bodb_FraudSensor" executers="bodbSPUNet" isFunction="0" isNested="0"></info>*/