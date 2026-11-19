/* =====================================================================
   DashboardChart.sql  -  Data grafik dasar (sebagian T8 ditarik ke MVP, Keputusan 16-11-2026; PRD 4, 8.1, BR-17, BR-69)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Dashboard.sql dan RequestProgress.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Grafik (library Chart.js lokal):
     1. Dashboard - status keseluruhan per kategori : memakai usp_Dashboard_GetSummary (tanpa SP baru).
     2. Dashboard - biaya bulanan estimasi vs actual : usp_Dashboard_GetMonthlyCost (di bawah).
     3. Details   - kurva S progress (plan vs actual per minggu) : usp_Request_GetProgressCurve (di bawah).
     4. Details   - kurva biaya (estimasi vs actual kumulatif) : memakai usp_Request_GetActualCost result 2 (tanpa SP baru).
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_Dashboard_GetMonthlyCost
      Project aktif (IN_PROGRESS + BAPP_REVIEW) dalam lingkup user + filter Company/kategori.
      Satu baris per bulan yang punya estimasi atau actual. Actual hanya s.d. bulan terpilih (NULL sesudahnya);
      estimasi semua bulan (rencana ke depan tetap terlihat).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetMonthlyCost
    @Username  NVARCHAR(100),
    @CoCode    VARCHAR(10) = NULL,
    @Month     DATE        = NULL,
    @Category  VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode   = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    SET @Category = NULLIF(LTRIM(RTRIM(@Category)), '');
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, @Today)), MONTH(ISNULL(@Month, @Today)), 1);

    DECLARE @Projects TABLE (Id INT PRIMARY KEY);
    INSERT INTO @Projects (Id)
    SELECT  pr.Id
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status IN ('IN_PROGRESS', 'BAPP_REVIEW')
      AND   (@CoCode   IS NULL OR pr.CoCode = @CoCode)
      AND   (@Category IS NULL OR pr.Category = @Category)
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = pr.DepartmentID);

    ;WITH e AS
    (
        SELECT ce.PeriodMonth, SUM(ce.Amount) AS Amount
        FROM   dbo.ProjectCostEstimate ce JOIN @Projects p ON p.Id = ce.RequestId
        GROUP BY ce.PeriodMonth
    ),
    a AS
    (
        SELECT am.PeriodMonth, SUM(am.TotalAmount) AS Amount
        FROM   dbo.ProjectActualMonth am JOIN @Projects p ON p.Id = am.RequestId
        WHERE  am.PeriodMonth <= @MonthStart
        GROUP BY am.PeriodMonth
    )
    SELECT  ISNULL(e.PeriodMonth, a.PeriodMonth) AS PeriodMonth,
            ISNULL(e.Amount, 0) AS EstimateAmount,
            CASE WHEN ISNULL(e.PeriodMonth, a.PeriodMonth) <= @MonthStart THEN ISNULL(a.Amount, 0) END AS ActualAmount
    FROM    e FULL OUTER JOIN a ON a.PeriodMonth = e.PeriodMonth
    ORDER BY ISNULL(e.PeriodMonth, a.PeriodMonth);
END
GO

/* ---------------------------------------------------------------------
   2. usp_Request_GetProgressCurve  (kurva S satu project; BR-17)
      Satu baris per minggu (Senin) dari minggu mulai project s.d. minggu selesai plan terakhir.
      PlanPercent = % plan pada hari Minggu minggu itu (fn_Request_PlanProgress, bobot linear per hari);
      ActualPercent = % aktual tersimpan minggu itu (NULL bila belum diisi). Lingkup sama dengan usp_Request_GetProgress.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetProgressCurve
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))
             THEN 1 ELSE 0 END;

    IF @Visible = 0 RETURN;

    DECLARE @Start DATE = (SELECT ProjectStartDate FROM dbo.ProjectRequest WHERE Id = @RequestId);
    DECLARE @End DATE = (SELECT MAX(PlanEndDate) FROM dbo.ProjectActionPlan WHERE RequestId = @RequestId);
    IF @Start IS NULL OR @End IS NULL RETURN;

    -- Minggu tersimpan bisa melewati tanggal selesai plan (project terlambat): ikutkan sampai minggu tersimpan terakhir
    DECLARE @LastSaved DATE = (SELECT MAX(WeekStart) FROM dbo.ProjectProgressWeek WHERE RequestId = @RequestId);
    DECLARE @FirstWeek DATE = dbo.fn_WeekStart(@Start);
    DECLARE @LastWeek DATE = dbo.fn_WeekStart(@End);
    IF @LastSaved > @LastWeek SET @LastWeek = @LastSaved;

    ;WITH w AS
    (
        SELECT @FirstWeek AS WeekStart
        UNION ALL
        SELECT DATEADD(DAY, 7, WeekStart) FROM w WHERE WeekStart < @LastWeek
    )
    SELECT  w.WeekStart, DATEADD(DAY, 6, w.WeekStart) AS WeekEnd,
            p.PlanPercent,
            s.ActualPercent
    FROM    w
            CROSS APPLY dbo.fn_Request_PlanProgress(@RequestId, DATEADD(DAY, 6, w.WeekStart)) p
            LEFT JOIN dbo.ProjectProgressWeek s ON s.RequestId = @RequestId AND s.WeekStart = w.WeekStart
    ORDER BY w.WeekStart
    OPTION (MAXRECURSION 600);   -- maks. ±11 tahun mingguan
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)

   DECLARE @Civil NVARCHAR(100) = N'<user civil>', @Req INT = <id request IN_PROGRESS dengan schedule>;

   -- 1) Biaya bulanan: estimasi semua bulan, actual s.d. bulan terpilih (Okt: actual Nov = NULL)
   EXEC dbo.usp_Dashboard_GetMonthlyCost @Username = @Civil, @Month = '2026-11-01';
   EXEC dbo.usp_Dashboard_GetMonthlyCost @Username = @Civil, @Month = '2026-10-01';
   EXEC dbo.usp_Dashboard_GetMonthlyCost @Username = @Civil, @Month = '2026-11-01', @Category = 'CAPEX', @CoCode = 'ABL';

   -- 2) Kurva S: satu baris per minggu dari minggu mulai s.d. minggu selesai; PlanPercent naik ke 100 di minggu terakhir,
   --    ActualPercent terisi pada minggu yang sudah disimpan (mis. 16-11-2026: 12.75)
   EXEC dbo.usp_Request_GetProgressCurve @RequestId = @Req, @Username = @Civil;
   EXEC dbo.usp_Request_GetProgressCurve @RequestId = @Req, @Username = N'<user purchasing>';   -- 0 baris
   ===================================================================== */
