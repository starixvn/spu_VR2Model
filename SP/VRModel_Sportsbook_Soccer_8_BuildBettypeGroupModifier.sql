ALTER PROCEDURE [dbo].[VRModel_Sportsbook_Soccer_8_BuildBettypeGroupModifier]
		@FromDate			DATE
	,	@ToDate				DATE
	,	@IsLive				BIT
	,	@SportId			INT = 1
	,	@LeagueGroupId		SMALLINT = 11
	,	@LeagueId			INT
AS
/*
	Created: 20200122@Long.Luu
	Task : 
	DB: bodb_VR2Model
	Original:

	Revisions:
		- 20200122@Long.Luu: Created [Redmine ID: #127584]

	Param's Explanation:
*/
BEGIN

	SET NOCOUNT ON;

	-- INITIALIZE	
	DECLARE @Settings_MinBetCount	INT	= 5
		,	@Settings_MinBet		MONEY = 499;

	DECLARE @AVGBettypeGroupPercentageOfDanger	FLOAT
		,	@BettypeGroupSQL					VARCHAR(4000);

	IF	OBJECT_ID('tempdb..#tmpBettypeGroups') IS NOT NULL
		DROP TABLE	#tmpBettypeGroups;

	CREATE TABLE	#tmpBettypeGroups (
			BettypeGroupId		SMALLINT
		,	BettypeId			SMALLINT
		,	PRIMARY KEY (BettypeGroupId, BettypeId)
	);
	/*
	SELECT	@BettypeGroupSQL ='INSERT INTO #tmpBettypes(BetType) SELECT BetType FROM OPENQUERY([DBCUST],'' SELECT BetType  FROM CustDB.dbo.VRSettingHierarchy 
		WHERE BetType <> -1 AND SportType = ' + convert( VARCHAR(50),@SportId ) 
			+''')';
	EXEC(@BettypeGroupSQL);
	*/
	INSERT INTO #tmpBettypeGroups(BettypeGroupId, BettypeId)
	VALUES (6,1),(6,7),(6,17),(7,2),(7,12),(8,3),(8,8);

	IF	OBJECT_ID('tempdb..#tmpWinnerCounterByBettypeGroup') IS NOT NULL
	BEGIN
		DROP TABLE #tmpWinnerCounterByBettypeGroup;
	END;

	CREATE TABLE #tmpWinnerCounterByBettypeGroup (
			[BettypGroupId]		INT NOT NULL PRIMARY KEY
		,	[NumOfWinner]		INT
	);

	IF	OBJECT_ID('tempdb..#tmpLoserCounterByBettypeGroup') IS NOT NULL
	BEGIN
		DROP TABLE #tmpLoserCounterByBettypeGroup;
	END;

	CREATE TABLE #tmpLoserCounterByBettypeGroup (
			[BettypGroupId]		INT NOT NULL PRIMARY KEY
		,	[NumOfLoser]		INT
	);

	IF	OBJECT_ID('tempdb..#tmpBettypeGroupPercentageOfWin') IS NOT NULL
	BEGIN
		DROP TABLE #tmpBettypeGroupPercentageOfWin;
	END;

	CREATE TABLE #tmpBettypeGroupPercentageOfWin (
			[BettypGroupId]		INT NOT NULL PRIMARY KEY
		,	[PercentageOfWin]	FLOAT
	);

	IF	OBJECT_ID('tempdb..#tmpCumulativeMarginByBettype') IS NOT NULL
	BEGIN
		DROP TABLE #tmpCumulativeMarginByBettype;
	END;

	CREATE TABLE #tmpCumulativeMarginByBettype (
			[CustId]		INT NOT NULL
		,	[BettypeId]		INT NOT NULL
		,	[Margin]		NUMERIC(3,2) NOT NULL
		,	CONSTRAINT PK_VR2Model_CumulativeMarginByWeek PRIMARY KEY CLUSTERED(
				[CustId]    ASC,
				[BettypeId]	ASC			
			)
	);

	TRUNCATE TABLE dbo.[VR2Model_StagingSoccerWeeklyData];

	INSERT INTO dbo.VR2Model_StagingSoccerWeeklyData(FromDate, ToDate, CustId, SuperId, LeagueId, BettypeId, RealTurnover, RealWinloss, WeekOrder)
	SELECT	w.FromDate
		,	w.ToDate
		,	w.CustId
		,	w.SuperId
		,   w.LeagueId
		,   w.BettypeId
		,	w.RealTurnover
		,	w.RealWinloss		
		,	ROW_NUMBER() OVER(PARTITION BY w.CustId ORDER BY w.FromDate ASC)
	FROM dbo.[SoccerWeeklyData] AS w WITH(NOLOCK)
	WHERE w.FromDate >= @FromDate AND w.ToDate <= @ToDate
		AND w.LeagueId = @LeagueId
		AND w.IsLive = @IsLive
		AND w.BetCount > @Settings_MinBetCount
		AND w.RealTurnover > @Settings_MinBet;

	INSERT INTO #tmpCumulativeMarginByBettype(CustId, BettypeId, Margin)
	SELECT t1.CustId, t1.BettypeId, CAST(ROUND(SUM(t1.RealWinloss) / SUM(t1.RealTurnover), 2) AS NUMERIC(3,2))
	FROM dbo.VR2Model_StagingSoccerWeeklyData AS t1 WITH(NOLOCK)
	GROUP BY t1.CustId, t1.BettypeId;
	
	INSERT INTO #tmpWinnerCounterByBettypeGroup(BettypGroupId, NumOfWinner)
	SELECT b.BettypeGroupId, COUNT(c.CustId)
	FROM #tmpCumulativeMarginByBettype AS c WITH(NOLOCK)
		INNER JOIN #tmpBettypeGroups AS b WITH(NOLOCK) ON b.BettypeId = c.BettypeId
	WHERE c.Margin > 0
	GROUP BY b.BettypeGroupId;

	INSERT INTO #tmpLoserCounterByBettypeGroup(BettypGroupId, NumOfLoser)
	SELECT b.BettypeGroupId, COUNT(c.CustId)
	FROM #tmpCumulativeMarginByBettype AS c WITH(NOLOCK)
		INNER JOIN #tmpBettypeGroups AS b WITH(NOLOCK) ON b.BettypeId = c.BettypeId
	WHERE c.Margin <= 0
	GROUP BY b.BettypeGroupId;

	INSERT INTO #tmpBettypeGroupPercentageOfWin(BettypGroupId, PercentageOfWin)
	SELECT	w.BettypGroupId
		,	CAST(w.NumOfWinner AS FLOAT) / (w.NumOfWinner + l.NumOfLoser)
	FROM #tmpWinnerCounterByBettypeGroup AS w WITH(NOLOCK)
		INNER JOIN #tmpLoserCounterByBettypeGroup AS l WITH(NOLOCK) ON w.BettypGroupId = l.BettypGroupId;

	SELECT @AVGBettypeGroupPercentageOfDanger	= CAST(SUM(w.NumOfWinner) AS FLOAT) / (SUM(w.NumOfWinner) + SUM(l.NumOfLoser))
	FROM #tmpWinnerCounterByBettypeGroup AS w WITH(NOLOCK)
		INNER JOIN #tmpLoserCounterByBettypeGroup AS l WITH(NOLOCK) ON w.BettypGroupId = l.BettypGroupId;

	INSERT INTO dbo.VR2Model_VirtualRate(
			CustId
		,	IsLive
		,	SportId
		,	LeagueGroupId
		,	LeagueId
		,	BettypeGroupId
		,	BettypeId
		,	VirtualMultiplier
		,	CreatedDate
		)
	SELECT	0
		,	@IsLive
		,	@SportId
		,	@LeagueGroupId
		,	@LeagueId
		,	l.BettypGroupId
		,	-1
		,	-(1 - (l.PercentageOfWin / @AVGBettypeGroupPercentageOfDanger))
		,	GETDATE()
	FROM #tmpBettypeGroupPercentageOfWin AS l WITH(NOLOCK);
END;

/*<info serverAlias="DBFS-bodb_FraudSensor" executers="bodbSPUNet" isFunction="0" isNested="0"></info>*/