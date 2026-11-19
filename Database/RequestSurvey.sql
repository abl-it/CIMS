/* =====================================================================
   RequestSurvey.sql  -  Survei kepuasan user setelah Project Closed + daftar User Satisfaction
                         (T6-2; PRD 3.4 langkah 7, 5.2, 6.6, BR-22, BR-24, BR-47, BR-48, BR-49, BR-91, BR-92, ST-14, KPI-03)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH SurveyTemplateItem.sql dan RequestBapp.sql,
             lalu jalankan ulang Task.sql (tugas SURVEY_SEND untuk civil dan SURVEY untuk kabag).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Alur (Keputusan 18-11-2026, lihat docs/PRD-log.md):
     1. CLOSED -> Civil klik Send survey (usp_Survey_Send): item template aktif kategori request di-snapshot (BR-48).
     2. Kabag departemen peminta (role kabag, ABRV + Company sama; BR-24) mengisi: semua item skala 1-10 wajib (BR-49),
        Note for Civil opsional. Yang pertama submit berlaku. Submit final -> SURVEY_COMPLETED (ST-14).
     3. Skor survei = rata-rata (nilai / 10) x 100% (6.6).
   Lihat (matriks 5.2): kabag (dept sendiri), mo (grup), civil, gm, director, administrator (fn_User_CanSeeSurvey +
     lingkup fn_User_AllowedDepartments). adm / emp / fat / dgo / purchasing tidak.
   Error   : 50072 = Input wajib kosong / tidak valid
             50073 = Request / survei tidak ditemukan atau di luar lingkup user
             50074 = Status tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.ProjectSurvey  (satu survei per project)  ·  dbo.ProjectSurveyItem (snapshot item + nilai)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectSurvey', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectSurvey
    (
        Id            INT IDENTITY(1,1) NOT NULL,
        RequestId     INT            NOT NULL,
        Category      VARCHAR(10)    NOT NULL,       -- kategori saat dikirim (template)
        Status        VARCHAR(10)    NOT NULL CONSTRAINT DF_ProjectSurvey_Status DEFAULT ('SENT'),
        SentAt        DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectSurvey_SentAt DEFAULT (SYSDATETIME()),
        SentBy        NVARCHAR(100)  NOT NULL,
        SubmittedAt   DATETIME2(3)   NULL,
        SubmittedBy   NVARCHAR(100)  NULL,
        NoteForCivil  NVARCHAR(2000) NULL,
        ScorePercent  DECIMAL(5, 2)  NULL,
        CONSTRAINT PK_ProjectSurvey PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectSurvey_Request UNIQUE (RequestId),
        CONSTRAINT FK_ProjectSurvey_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT CK_ProjectSurvey_Status CHECK (Status IN ('SENT', 'COMPLETED'))
    );
END
GO

IF OBJECT_ID(N'dbo.ProjectSurveyItem', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectSurveyItem
    (
        Id              INT IDENTITY(1,1) NOT NULL,
        SurveyId        INT            NOT NULL,
        TemplateItemId  INT            NULL,           -- asal (informasi saja)
        SortOrder       INT            NOT NULL,
        ItemText        NVARCHAR(200)  NOT NULL,       -- snapshot (BR-48)
        Score           TINYINT        NULL,           -- 1..10
        CONSTRAINT PK_ProjectSurveyItem PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ProjectSurveyItem_Survey FOREIGN KEY (SurveyId) REFERENCES dbo.ProjectSurvey (Id),
        CONSTRAINT CK_ProjectSurveyItem_Score CHECK (Score IS NULL OR Score BETWEEN 1 AND 10)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ProjectSurveyItem_Survey' AND object_id = OBJECT_ID(N'dbo.ProjectSurveyItem'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectSurveyItem_Survey ON dbo.ProjectSurveyItem (SurveyId, SortOrder);
END
GO

/* ---------------------------------------------------------------------
   2. dbo.fn_User_CanSeeSurvey(@Username)   (matriks 5.2 baris Survei)
      dbo.fn_User_CanFillSurvey(@RequestId, @Username)  (BR-24, BR-91: kabag ABRV + Company departemen peminta)
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_CanSeeSurvey
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) 1 AS Allowed
    FROM   dbo.fn_User_Roles(@Username) r
    WHERE  r.RoleCode IN (N'kabag', N'mo', N'civil', N'gm', N'director', N'administrator')
);
GO

CREATE OR ALTER FUNCTION dbo.fn_User_CanFillSurvey
(
    @RequestId INT,
    @Username  NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) 1 AS Allowed
    FROM   dbo.ProjectRequest pr
           JOIN home..APP_Departments rd   ON rd.DepartmentID = pr.DepartmentID
           JOIN home..users u              ON u.Username = @Username
           JOIN home..app_employees e      ON e.EmployeeCode = u.EmployeeCode
           LEFT JOIN home..APP_Departments ed ON ed.DepartmentID = e.DepartmentID
    WHERE  pr.Id = @RequestId
      AND  (e.ResignDate IS NULL OR e.ResignDate > GETDATE())
      AND  e.CoCode = pr.CoCode
      AND  ed.ABRV = rd.ABRV
      AND  EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'kabag')
);
GO

/* ---------------------------------------------------------------------
   3. usp_Survey_Send  (civil; request CLOSED; BR-91, BR-48)
      Hasil: SELECT Id, ItemCount.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Survey_Send
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can send the survey.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @Category VARCHAR(10);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @Category = r.Category
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'CLOSED'
        THROW 50074, N'The survey can only be sent after the project is closed.', 1;
    IF EXISTS (SELECT 1 FROM dbo.ProjectSurvey s WITH (UPDLOCK, HOLDLOCK) WHERE s.RequestId = @RequestId)
        THROW 50074, N'The survey has already been sent.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.SurveyTemplateItem t WHERE t.Category = @Category AND t.IsActive = 1)
        THROW 50072, N'No active survey items for this category. Please contact the administrator.', 1;

    INSERT INTO dbo.ProjectSurvey (RequestId, Category, Status, SentAt, SentBy)
    VALUES (@RequestId, @Category, 'SENT', @Now, @Username);

    DECLARE @SurveyId INT = CAST(SCOPE_IDENTITY() AS INT);

    INSERT INTO dbo.ProjectSurveyItem (SurveyId, TemplateItemId, SortOrder, ItemText)
    SELECT  @SurveyId, t.Id, ROW_NUMBER() OVER (ORDER BY t.SortOrder, t.Id), t.ItemText
    FROM    dbo.SurveyTemplateItem t
    WHERE   t.Category = @Category AND t.IsActive = 1;

    DECLARE @Count INT = @@ROWCOUNT;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@RequestId, 'SURVEY_SEND', @Status, @Status, N'Survey sent to the requesting department head', @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @SurveyId AS Id, @Count AS ItemCount;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Survey_Get  (Details; 0 baris result 1 = belum dikirim / tidak boleh melihat)
      Result 1: header (+ CanFill) · Result 2: item
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Survey_Get
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeSurvey(@Username))
             THEN 1 ELSE 0 END;

    DECLARE @SurveyId INT = (SELECT s.Id FROM dbo.ProjectSurvey s WHERE s.RequestId = @RequestId);

    SELECT  s.Id, s.RequestId, s.Category, s.Status, s.SentAt, s.SentBy, se.FullName AS SentByName,
            s.SubmittedAt, s.SubmittedBy, sb.FullName AS SubmittedByName, s.NoteForCivil, s.ScorePercent,
            CAST(CASE WHEN s.Status = 'SENT' AND EXISTS (SELECT 1 FROM dbo.fn_User_CanFillSurvey(@RequestId, @Username))
                      THEN 1 ELSE 0 END AS BIT) AS CanFill
    FROM    dbo.ProjectSurvey s
            LEFT JOIN home..users su          ON su.Username = s.SentBy
            LEFT JOIN home..app_employees se  ON se.EmployeeCode = su.EmployeeCode
            LEFT JOIN home..users bu          ON bu.Username = s.SubmittedBy
            LEFT JOIN home..app_employees sb  ON sb.EmployeeCode = bu.EmployeeCode
    WHERE   s.Id = @SurveyId AND @Visible = 1;

    SELECT  i.Id, i.SortOrder, i.ItemText, i.Score
    FROM    dbo.ProjectSurveyItem i
    WHERE   i.SurveyId = @SurveyId AND @Visible = 1
    ORDER BY i.SortOrder, i.Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Survey_Submit  (kabag departemen peminta; survei SENT -> COMPLETED, request -> SURVEY_COMPLETED)
      @ScoresJson: [{"id":<ProjectSurveyItem.Id>,"score":9}, ...]  semua item wajib 1..10 (BR-49)
      Hasil: SELECT ScorePercent.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Survey_Submit
    @RequestId    INT,
    @Username     NVARCHAR(100),
    @ScoresJson   NVARCHAR(MAX),
    @NoteForCivil NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @NoteForCivil = NULLIF(LTRIM(RTRIM(@NoteForCivil)), N'');

    IF LEN(@NoteForCivil) > 2000
        THROW 50072, N'Note for Civil must be at most 2000 characters.', 1;
    IF ISJSON(ISNULL(@ScoresJson, N'[]')) = 0
        THROW 50072, N'Survey data is invalid.', 1;

    DECLARE @Scores TABLE (ItemId INT PRIMARY KEY, Score INT NULL);
    INSERT INTO @Scores (ItemId, Score)
    SELECT  x.id, x.score
    FROM    OPENJSON(ISNULL(@ScoresJson, N'[]')) WITH (id INT '$.id', score INT '$.score') x
    WHERE   x.id IS NOT NULL;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @SurveyId INT, @SurveyStatus VARCHAR(10);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;

    SELECT @SurveyId = s.Id, @SurveyStatus = s.Status FROM dbo.ProjectSurvey s WHERE s.RequestId = @RequestId;

    IF @SurveyId IS NULL
        THROW 50073, N'Survey not found.', 1;
    IF @SurveyStatus <> 'SENT' OR @Status <> 'CLOSED'
        THROW 50074, N'This survey has already been submitted.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_CanFillSurvey(@RequestId, @Username))
        THROW 50075, N'Only the department head of the requesting department can fill this survey.', 1;

    -- BR-49: semua item wajib dinilai 1..10
    IF EXISTS (SELECT 1 FROM dbo.ProjectSurveyItem i
               WHERE i.SurveyId = @SurveyId
                 AND NOT EXISTS (SELECT 1 FROM @Scores s WHERE s.ItemId = i.Id AND s.Score BETWEEN 1 AND 10))
        THROW 50072, N'Please rate every item from 1 to 10.', 1;

    UPDATE i
    SET    i.Score = s.Score
    FROM   dbo.ProjectSurveyItem i
           JOIN @Scores s ON s.ItemId = i.Id
    WHERE  i.SurveyId = @SurveyId;

    DECLARE @ScorePct DECIMAL(5, 2) =
        CAST(ROUND((SELECT AVG(CAST(i.Score AS DECIMAL(9, 4))) FROM dbo.ProjectSurveyItem i WHERE i.SurveyId = @SurveyId) * 10, 2) AS DECIMAL(5, 2));

    UPDATE dbo.ProjectSurvey
    SET    Status = 'COMPLETED', SubmittedAt = @Now, SubmittedBy = @Username, NoteForCivil = @NoteForCivil, ScorePercent = @ScorePct
    WHERE  Id = @SurveyId;

    UPDATE dbo.ProjectRequest
    SET    Status = 'SURVEY_COMPLETED', UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @RequestId;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@RequestId, 'SURVEY_SUBMIT', @Status, 'SURVEY_COMPLETED',
            LEFT(N'Survey score ' + FORMAT(@ScorePct, N'0.##', 'en-US') + N'%' + ISNULL(N' · ' + @NoteForCivil, N''), 1000),
            @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @ScorePct AS ScorePercent;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Survey_GetPaged  (halaman User Satisfaction; BR-92)
      Baris = project CLOSED / SURVEY_COMPLETED dalam lingkup user; SurveyStatus: NOT_SENT | SENT | COMPLETED.
      Periode (@Month) = bulan tanggal submit; belum diisi: bulan dikirim; belum dikirim: bulan Closed.
      @PageSize maks. 5000 (export, FR-04). @SortBy: PeriodDate | RequestNo | Score (default PeriodDate DESC).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Survey_GetPaged
    @Username      NVARCHAR(100),
    @CoCode        VARCHAR(10)   = NULL,
    @Category      VARCHAR(10)   = NULL,
    @SurveyStatus  VARCHAR(10)   = NULL,
    @Month         DATE          = NULL,
    @Search        NVARCHAR(100) = NULL,
    @SortBy        NVARCHAR(20)  = N'PeriodDate',
    @SortDir       NVARCHAR(4)   = N'DESC',
    @PageNumber    INT           = 1,
    @PageSize      INT           = 10,
    @TotalCount    INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode       = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    SET @Category     = NULLIF(LTRIM(RTRIM(@Category)), '');
    SET @SurveyStatus = NULLIF(LTRIM(RTRIM(@SurveyStatus)), '');
    SET @Search       = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy       = CASE WHEN @SortBy IN (N'PeriodDate', N'RequestNo', N'Score') THEN @SortBy ELSE N'PeriodDate' END;
    SET @SortDir      = CASE WHEN UPPER(@SortDir) = N'ASC' THEN N'ASC' ELSE N'DESC' END;
    SET @PageNumber   = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize     = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 10 WHEN @PageSize > 5000 THEN 5000 ELSE @PageSize END;

    DECLARE @MonthStart DATE = CASE WHEN @Month IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1) END;
    DECLARE @CanSee BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeSurvey(@Username)) THEN 1 ELSE 0 END;

    DECLARE @Scope TABLE (DepartmentID INT PRIMARY KEY);
    INSERT INTO @Scope (DepartmentID) SELECT DISTINCT f.DepartmentID FROM dbo.fn_User_AllowedDepartments(@Username) f;

    ;WITH x AS
    (
        SELECT  r.Id AS RequestId, r.CoCode, r.RequestNo, r.Title, r.Category, r.Status, d.DeptName, d.ABRV,
                CASE WHEN s.Id IS NULL THEN 'NOT_SENT' ELSE s.Status END AS SurveyStatus,
                s.SentAt, s.SubmittedAt, s.SubmittedBy, sb.FullName AS SubmittedByName, s.ScorePercent, s.NoteForCivil,
                (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = r.Id AND h.ToStatus = 'CLOSED') AS ClosedAt
        FROM    dbo.ProjectRequest r
                JOIN @Scope sc ON sc.DepartmentID = r.DepartmentID
                LEFT JOIN dbo.ProjectSurvey s        ON s.RequestId = r.Id
                LEFT JOIN home..APP_Departments d    ON d.DepartmentID = r.DepartmentID
                LEFT JOIN home..users bu             ON bu.Username = s.SubmittedBy
                LEFT JOIN home..app_employees sb     ON sb.EmployeeCode = bu.EmployeeCode
        WHERE   r.Status IN ('CLOSED', 'SURVEY_COMPLETED') AND @CanSee = 1
    ),
    y AS
    (
        SELECT x.*, CAST(COALESCE(x.SubmittedAt, x.SentAt, x.ClosedAt) AS DATE) AS PeriodDate
        FROM   x
        WHERE  (@CoCode IS NULL OR x.CoCode = @CoCode)
          AND  (@Category IS NULL OR x.Category = @Category)
          AND  (@SurveyStatus IS NULL OR x.SurveyStatus = @SurveyStatus)
          AND  (@Search IS NULL OR x.Title LIKE N'%' + @Search + N'%' OR x.RequestNo LIKE '%' + @Search + '%')
    )
    SELECT  y.*, COUNT(*) OVER () AS TotalRows
    INTO    #rows
    FROM    y
    WHERE   (@MonthStart IS NULL OR (y.PeriodDate >= @MonthStart AND y.PeriodDate < DATEADD(MONTH, 1, @MonthStart)));

    SET @TotalCount = ISNULL((SELECT TOP (1) TotalRows FROM #rows), 0);

    SELECT  RequestId, CoCode, RequestNo, Title, Category, Status, DeptName, ABRV, SurveyStatus, SentAt, SubmittedAt,
            SubmittedBy, SubmittedByName, ScorePercent, NoteForCivil, ClosedAt, PeriodDate
    FROM    #rows
    ORDER BY
        CASE WHEN @SortBy = N'PeriodDate' AND @SortDir = N'ASC'  THEN PeriodDate END ASC,
        CASE WHEN @SortBy = N'PeriodDate' AND @SortDir = N'DESC' THEN PeriodDate END DESC,
        CASE WHEN @SortBy = N'RequestNo'  AND @SortDir = N'ASC'  THEN RequestNo END ASC,
        CASE WHEN @SortBy = N'RequestNo'  AND @SortDir = N'DESC' THEN RequestNo END DESC,
        CASE WHEN @SortBy = N'Score'      AND @SortDir = N'ASC'  THEN ScorePercent END ASC,
        CASE WHEN @SortBy = N'Score'      AND @SortDir = N'DESC' THEN ScorePercent END DESC,
        RequestId DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;

    DROP TABLE #rows;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: request CLOSED (@Req) hasil T6-1; user civil, kabag ABRV departemen peminta, kabag departemen lain, adm.

   DECLARE @Req INT = <id>, @Civil NVARCHAR(100) = N'<civil>', @Kabag NVARCHAR(100) = N'<kabag dept>',
           @KabagLain NVARCHAR(100) = N'<kabag lain>', @Adm NVARCHAR(100) = N'<adm>';

   -- 1) Bukan civil -> 50075; civil kirim -> survei + 5 item (template kategori); kirim ulang -> 50074
   BEGIN TRY EXEC dbo.usp_Survey_Send @RequestId = @Req, @Username = @Kabag;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Survey_Send @RequestId = @Req, @Username = @Civil;
   BEGIN TRY EXEC dbo.usp_Survey_Send @RequestId = @Req, @Username = @Civil;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50074' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) Lihat: kabag -> CanFill 1; adm -> 0 baris
   EXEC dbo.usp_Survey_Get @RequestId = @Req, @Username = @Kabag;
   EXEC dbo.usp_Survey_Get @RequestId = @Req, @Username = @Adm;

   -- 3) Kabag lain -> 50073/50075; item kurang -> 50072; lengkap (10,9,8,10,7) -> 88.00, request SURVEY_COMPLETED
   DECLARE @J NVARCHAR(MAX) = (SELECT i.Id AS id, CASE i.SortOrder WHEN 1 THEN 10 WHEN 2 THEN 9 WHEN 3 THEN 8 WHEN 4 THEN 10 ELSE 7 END AS score
                               FROM dbo.ProjectSurveyItem i JOIN dbo.ProjectSurvey s ON s.Id = i.SurveyId
                               WHERE s.RequestId = @Req FOR JSON PATH);
   BEGIN TRY EXEC dbo.usp_Survey_Submit @RequestId = @Req, @Username = @KabagLain, @ScoresJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '3a expect 50073/50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Survey_Submit @RequestId = @Req, @Username = @Kabag, @ScoresJson = N'[]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '3b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   EXEC dbo.usp_Survey_Submit @RequestId = @Req, @Username = @Kabag, @ScoresJson = @J, @NoteForCivil = N'Good job';

   -- 4) Daftar: civil -> baris @Req COMPLETED 88; filter NOT_SENT / bulan
   DECLARE @T INT;
   EXEC dbo.usp_Survey_GetPaged @Username = @Civil, @TotalCount = @T OUTPUT; SELECT @T AS Total;
   EXEC dbo.usp_Survey_GetPaged @Username = @Civil, @SurveyStatus = 'NOT_SENT', @TotalCount = @T OUTPUT;
   ===================================================================== */
