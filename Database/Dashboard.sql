/* =====================================================================
   Dashboard.sql  -  Dashboard dasar (PRD 9.1 "Dashboard dasar", 7.1 FR-01, 8.1 BR-68..BR-71, 9.4 FR-04)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestActualCost.sql
             (kolom OverallStatus/CostStatus) dan RequestProgress.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Aturan (Keputusan 16-11-2026, lihat docs/PRD-log.md):
     - Kartu per kategori (CAPEX/OPEX/LVE):
         * Project aktif (IN_PROGRESS + BAPP_REVIEW) per status keseluruhan On Track / At Risk / Delayed (BR-70).
           OverallStatus NULL (belum ada progress & actual) dihitung On Track (catatan PRD 8.1).
         * Plan cost project aktif, estimasi dan actual kumulatif s.d. bulan terpilih.
         * Pipeline: Approval (WAITING_APPROVAL, MGMT_APPROVAL) · Civil review (FEASIBILITY, DOC_PREPARATION) ·
           Preparation (PLANNING, PROCUREMENT, SCHEDULING) · Closed pada bulan terpilih (CLOSED/SURVEY_COMPLETED,
           tanggal masuk CLOSED dari riwayat; aktif setelah T6).
     - Filter bulan: biaya kumulatif s.d. bulan itu dan Closed di bulan itu. Status jadwal/biaya/keseluruhan =
       nilai terakhir yang dihitung (riwayat status tidak disimpan).
     - Filter Company: NULL = semua Company dalam lingkup user. Lingkup data lewat fn_User_AllowedDepartments.
     - Purchasing tidak punya akses dashboard (matriks 5.2); dicek di Controller.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_Dashboard_GetSummary  (kartu per kategori; selalu 3 baris CAPEX, OPEX, LVE)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetSummary
    @Username  NVARCHAR(100),
    @CoCode    VARCHAR(10) = NULL,
    @Month     DATE        = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, @Today)), MONTH(ISNULL(@Month, @Today)), 1);
    DECLARE @NextMonth DATE = DATEADD(MONTH, 1, @MonthStart);

    DECLARE @Scope TABLE (DepartmentID INT PRIMARY KEY);
    INSERT INTO @Scope (DepartmentID)
    SELECT DISTINCT f.DepartmentID FROM dbo.fn_User_AllowedDepartments(@Username) f;

    ;WITH r AS
    (
        SELECT  pr.Id, pr.Category, pr.Status, pr.OverallStatus, pr.PlanCost,
                (SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e WHERE e.RequestId = pr.Id AND e.PeriodMonth <= @MonthStart) AS EstimateToMonth,
                (SELECT SUM(m.TotalAmount) FROM dbo.ProjectActualMonth m WHERE m.RequestId = pr.Id AND m.PeriodMonth <= @MonthStart) AS ActualToMonth,
                CASE WHEN pr.Status IN ('CLOSED', 'SURVEY_COMPLETED')
                     THEN (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = 'CLOSED') END AS ClosedAt
        FROM    dbo.ProjectRequest pr
                JOIN @Scope s ON s.DepartmentID = pr.DepartmentID
        WHERE   (@CoCode IS NULL OR pr.CoCode = @CoCode)
    )
    SELECT  c.Category,
            COUNT(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') THEN 1 END)                                              AS ActiveTotal,
            COUNT(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') AND ISNULL(r.OverallStatus, 'ON_TRACK') = 'ON_TRACK' THEN 1 END) AS OnTrack,
            COUNT(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') AND r.OverallStatus = 'AT_RISK' THEN 1 END)               AS AtRisk,
            COUNT(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') AND r.OverallStatus = 'DELAYED' THEN 1 END)               AS Delayed,
            ISNULL(SUM(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') THEN r.PlanCost END), 0)                             AS PlanCost,
            ISNULL(SUM(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') THEN r.EstimateToMonth END), 0)                      AS EstimateToMonth,
            ISNULL(SUM(CASE WHEN r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW') THEN r.ActualToMonth END), 0)                        AS ActualToMonth,
            COUNT(CASE WHEN r.Status IN ('WAITING_APPROVAL', 'MGMT_APPROVAL') THEN 1 END)                                         AS InApproval,
            COUNT(CASE WHEN r.Status IN ('FEASIBILITY', 'DOC_PREPARATION') THEN 1 END)                                            AS InCivilReview,
            COUNT(CASE WHEN r.Status IN ('PLANNING', 'PROCUREMENT', 'SCHEDULING') THEN 1 END)                                     AS InPreparation,
            COUNT(CASE WHEN r.ClosedAt >= @MonthStart AND r.ClosedAt < @NextMonth THEN 1 END)                                     AS ClosedInMonth
    FROM    (VALUES ('CAPEX', 1), ('OPEX', 2), ('LVE', 3)) AS c (Category, SortOrder)
            LEFT JOIN r ON r.Category = c.Category
    GROUP BY c.Category, c.SortOrder
    ORDER BY c.SortOrder;
END
GO

/* ---------------------------------------------------------------------
   2. usp_Dashboard_GetProjects  (tabel project aktif: IN_PROGRESS + BAPP_REVIEW)
      @OverallStatus : ON_TRACK (termasuk belum dihitung) | AT_RISK | DELAYED | NULL = semua
      @SortBy        : Overall | RequestNo | Title | Category | Progress | PlanCost   (default Overall: Delayed dulu)
      @PageSize      : 1..100 untuk tampilan; 0 = semua baris (export Excel, maks. 5000)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Dashboard_GetProjects
    @Username       NVARCHAR(100),
    @CoCode         VARCHAR(10)   = NULL,
    @Month          DATE          = NULL,
    @Category       VARCHAR(10)   = NULL,
    @OverallStatus  VARCHAR(20)   = NULL,
    @Search         NVARCHAR(100) = NULL,
    @SortBy         NVARCHAR(20)  = N'Overall',
    @SortDir        NVARCHAR(4)   = N'DESC',
    @PageNumber     INT           = 1,
    @PageSize       INT           = 10,
    @TotalCount     INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode        = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    SET @Category      = NULLIF(LTRIM(RTRIM(@Category)), '');
    SET @OverallStatus = NULLIF(LTRIM(RTRIM(@OverallStatus)), '');
    SET @Search        = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy        = CASE WHEN @SortBy IN (N'Overall', N'RequestNo', N'Title', N'Category', N'Progress', N'PlanCost') THEN @SortBy ELSE N'Overall' END;
    SET @SortDir       = CASE WHEN UPPER(@SortDir) = N'ASC' THEN N'ASC' ELSE N'DESC' END;
    SET @PageNumber    = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN @PageSize IS NULL OR @PageSize < 0 THEN 10
                              WHEN @PageSize = 0 THEN 5000
                              WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, @Today)), MONTH(ISNULL(@Month, @Today)), 1);

    DECLARE @Scope TABLE (DepartmentID INT PRIMARY KEY);
    INSERT INTO @Scope (DepartmentID)
    SELECT DISTINCT f.DepartmentID FROM dbo.fn_User_AllowedDepartments(@Username) f;

    DECLARE @Rows TABLE
    (
        Id INT PRIMARY KEY, CoCode VARCHAR(10), RequestNo VARCHAR(40), Title NVARCHAR(200), Category VARCHAR(10),
        Status VARCHAR(20), DepartmentID INT, ExecutionType VARCHAR(10), ProjectStartDate DATE, ProjectEndDate DATE,
        ProgressPercent DECIMAL(5, 2), PlanProgressPercent DECIMAL(5, 2), ScheduleStatus VARCHAR(20),
        PlanCost DECIMAL(18, 2), EstimateToMonth DECIMAL(18, 2), ActualToMonth DECIMAL(18, 2),
        CostStatus VARCHAR(20), OverallStatus VARCHAR(20), Severity INT
    );

    INSERT INTO @Rows
    SELECT  pr.Id, pr.CoCode, pr.RequestNo, pr.Title, pr.Category, pr.Status, pr.DepartmentID, pr.ExecutionType,
            pr.ProjectStartDate,
            (SELECT MAX(a.PlanEndDate) FROM dbo.ProjectActionPlan a WHERE a.RequestId = pr.Id),
            pr.ProgressPercent, pr.PlanProgressPercent, pr.ScheduleStatus, pr.PlanCost,
            (SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e WHERE e.RequestId = pr.Id AND e.PeriodMonth <= @MonthStart),
            (SELECT SUM(m.TotalAmount) FROM dbo.ProjectActualMonth m WHERE m.RequestId = pr.Id AND m.PeriodMonth <= @MonthStart),
            pr.CostStatus, pr.OverallStatus,
            CASE pr.OverallStatus WHEN 'DELAYED' THEN 3 WHEN 'AT_RISK' THEN 2 ELSE 1 END
    FROM    dbo.ProjectRequest pr
            JOIN @Scope s ON s.DepartmentID = pr.DepartmentID
    WHERE   pr.Status IN ('IN_PROGRESS', 'BAPP_REVIEW')
      AND   (@CoCode   IS NULL OR pr.CoCode = @CoCode)
      AND   (@Category IS NULL OR pr.Category = @Category)
      AND   (@OverallStatus IS NULL OR ISNULL(pr.OverallStatus, 'ON_TRACK') = @OverallStatus)
      AND   (@Search IS NULL OR pr.Title LIKE N'%' + @Search + N'%' OR pr.RequestNo LIKE '%' + @Search + '%');

    SELECT @TotalCount = COUNT(*) FROM @Rows;

    SELECT  x.Id, x.CoCode, x.RequestNo, x.Title, x.Category, x.Status, x.DepartmentID, d.DeptName, d.ABRV,
            x.ExecutionType, x.ProjectStartDate, x.ProjectEndDate, x.ProgressPercent, x.PlanProgressPercent,
            x.ScheduleStatus, x.PlanCost, x.EstimateToMonth, x.ActualToMonth, x.CostStatus, x.OverallStatus
    FROM    @Rows x
            LEFT JOIN home..APP_Departments d ON d.DepartmentID = x.DepartmentID
    ORDER BY
        CASE WHEN @SortBy = N'Overall'   AND @SortDir = N'ASC'  THEN x.Severity  END ASC,
        CASE WHEN @SortBy = N'Overall'   AND @SortDir = N'DESC' THEN x.Severity  END DESC,
        CASE WHEN @SortBy = N'RequestNo' AND @SortDir = N'ASC'  THEN x.RequestNo END ASC,
        CASE WHEN @SortBy = N'RequestNo' AND @SortDir = N'DESC' THEN x.RequestNo END DESC,
        CASE WHEN @SortBy = N'Title'     AND @SortDir = N'ASC'  THEN x.Title     END ASC,
        CASE WHEN @SortBy = N'Title'     AND @SortDir = N'DESC' THEN x.Title     END DESC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'ASC'  THEN CHARINDEX(',' + x.Category + ',', ',CAPEX,OPEX,LVE,') END ASC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'DESC' THEN CHARINDEX(',' + x.Category + ',', ',CAPEX,OPEX,LVE,') END DESC,
        CASE WHEN @SortBy = N'Progress'  AND @SortDir = N'ASC'  THEN x.ProgressPercent END ASC,
        CASE WHEN @SortBy = N'Progress'  AND @SortDir = N'DESC' THEN x.ProgressPercent END DESC,
        CASE WHEN @SortBy = N'PlanCost'  AND @SortDir = N'ASC'  THEN x.PlanCost  END ASC,
        CASE WHEN @SortBy = N'PlanCost'  AND @SortDir = N'DESC' THEN x.PlanCost  END DESC,
        x.RequestNo ASC, x.Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)

   DECLARE @Civil NVARCHAR(100) = N'users1', @Adm NVARCHAR(100) = N'hdahlia', @T INT;

   -- 1) Kartu: 3 baris (CAPEX, OPEX, LVE); civil = semua departemen ABL + NKM
   EXEC dbo.usp_Dashboard_GetSummary @Username = @Civil, @Month = '2026-11-01';
   EXEC dbo.usp_Dashboard_GetSummary @Username = @Civil, @CoCode = 'NKM', @Month = '2026-11-01';   -- hanya NKM
   EXEC dbo.usp_Dashboard_GetSummary @Username = @Adm,   @Month = '2026-11-01';                   -- hanya departemennya
   -- Bandingkan ActualToMonth bulan Okt vs Nov: Okt tidak memuat actual Nov
   EXEC dbo.usp_Dashboard_GetSummary @Username = @Civil, @Month = '2026-10-01';

   -- 2) Tabel: default urut Delayed dulu; filter status / kategori / cari; export (PageSize 0)
   EXEC dbo.usp_Dashboard_GetProjects @Username = @Civil, @Month = '2026-11-01', @TotalCount = @T OUTPUT; SELECT @T AS TotalCount;
   EXEC dbo.usp_Dashboard_GetProjects @Username = @Civil, @OverallStatus = 'DELAYED', @TotalCount = @T OUTPUT;
   EXEC dbo.usp_Dashboard_GetProjects @Username = @Civil, @Category = 'CAPEX', @Search = N'PM-', @SortBy = N'Progress', @SortDir = N'ASC', @TotalCount = @T OUTPUT;
   EXEC dbo.usp_Dashboard_GetProjects @Username = @Civil, @PageSize = 0, @TotalCount = @T OUTPUT;

   -- 3) Request List untuk export (Request.sql dijalankan ulang): PageSize sampai 5000
   EXEC dbo.usp_Request_GetPaged @Username = @Civil, @PageSize = 5000, @TotalCount = @T OUTPUT; SELECT @T AS TotalCount;
   ===================================================================== */
