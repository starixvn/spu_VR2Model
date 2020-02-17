ALTER PROCEDURE [dbo].[VRModel_Sportsbook_Soccer_1_PrepareData]
		@FromDate			DATE
	,	@ToDate				DATE
	,	@IsDeposit			BIT
	,	@IsLive				BIT
	,	@SportId			INT
	,	@LeagueGroupId		SMALLINT
	,	@Leagues			VARCHAR(200)
	,	@BettypeGroupId		INT
	,	@Bettypes			VARCHAR(200)
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

	-- Initialize
	DECLARE @Settings_MinBetCount	INT	= 1
		,	@Settings_MinBet		MONEY = 499;

	IF	OBJECT_ID('tempdb..#tmpBettypes') IS NOT NULL
		DROP TABLE	#tmpBettypes;

	CREATE TABLE	#tmpBettypes (
			Bettype			SMALLINT PRIMARY KEY
	);

	INSERT INTO #tmpBettypes(BetType)
	SELECT val FROM dbo.SPU_StrSplit(@Bettypes,',');

	IF	OBJECT_ID('tempdb..#tmpLeagues') IS NOT NULL
		DROP TABLE	#tmpLeagues;

	CREATE TABLE	#tmpLeagues (
			LeagueId		SMALLINT PRIMARY KEY
	);

	INSERT INTO #tmpLeagues(LeagueId)
	SELECT val FROM dbo.SPU_StrSplit(@Leagues,',');

	-- START
	TRUNCATE TABLE dbo.[VR2Model_StagingSoccerWeeklyData];
	TRUNCATE TABLE dbo.[VR2Model_CumulativeMarginByWeek];
	TRUNCATE TABLE dbo.[VR2Model_CustomerCumulativeInfo];

	INSERT INTO dbo.VR2Model_StagingSoccerWeeklyData(FromDate, ToDate, CustId, SuperId, RealTurnover, RealWinloss, WeekOrder)
	SELECT	w.FromDate
		,	w.ToDate
		,	w.CustId
		,	w.SuperId
		,	w.RealTurnover
		,	w.RealWinloss		
		,	ROW_NUMBER() OVER(PARTITION BY w.CustId ORDER BY w.FromDate ASC)
	FROM dbo.[SoccerWeeklyData] AS w WITH(NOLOCK)
		INNER JOIN #tmpBettypes AS b WITH(NOLOCK) ON w.BettypeId = b.Bettype
		INNER JOIN #tmpLeagues AS l WITH(NOLOCK) ON w.LeagueId = l.LeagueId
	WHERE w.FromDate >= @FromDate AND w.ToDate <= @ToDate
		AND w.IsDeposit = @IsDeposit
		AND w.IsLive = @IsLive
		AND w.BetCount > @Settings_MinBetCount
		AND w.RealTurnover > @Settings_MinBet;

	INSERT INTO dbo.[VR2Model_CumulativeMarginByWeek](CustId, SuperId, WeekOrder, Margin)
	SELECT t1.CustId, t1.SuperId, t1.WeekOrder, CAST(ROUND(SUM(t2.RealWinloss) / SUM(t2.RealTurnover), 2) AS NUMERIC(3,2))
	FROM dbo.VR2Model_StagingSoccerWeeklyData AS t1 WITH(NOLOCK)
		LEFT JOIN dbo.VR2Model_StagingSoccerWeeklyData AS t2 WITH(NOLOCK)
				ON t1.WeekOrder >= (t2.WeekOrder) AND t1.CustId = t2.CustId	
	GROUP BY t1.CustId, t1.SuperId, t1.WeekOrder;
		
	UPDATE dbo.[VR2Model_CumulativeMarginByWeek] WITH(ROWLOCK, UPDLOCK)
	SET Margin = 0.1
	WHERE Margin > 0.1;

	UPDATE dbo.[VR2Model_CumulativeMarginByWeek] WITH(ROWLOCK, UPDLOCK)
	SET Margin = -0.1
	WHERE Margin < -0.1;

	;WITH cte AS
	(
	   SELECT CustId, SuperId, WeekOrder, Margin,
			 ROW_NUMBER() OVER (PARTITION BY CustId ORDER BY WeekOrder DESC) AS RowNumber
	   FROM dbo.[VR2Model_CumulativeMarginByWeek] WITH(NOLOCK)
	)
	INSERT INTO dbo.[VR2Model_CustomerCumulativeInfo](CustId, SuperId, Margin, NumOfWeeksBet)
	SELECT CustId, SuperId, Margin, WeekOrder
	FROM cte
	WHERE RowNumber = 1;
END;

/*<info serverAlias="DBFS-bodb_FraudSensor" executers="bodbSPUNet" isFunction="0" isNested="0"></info>*/