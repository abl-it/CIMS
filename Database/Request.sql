/* =====================================================================
   Request.sql  -  Request / Business Case: DRAFT (T2-1; PRD 3.1, 6.1, 6.5, BR-01, BR-02, BR-28, BR-40,
                   BR-42..BR-46, BR-55, BR-56, BR-61, ST-01, ST-03)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Prasyarat: Config.sql, Scope.sql, SubCategory.sql, Location.sql, AssessmentQuestion.sql,
              AttachmentType.sql; hak baca ke database [home] (users, app_employees,
              APP_Departments, APP_SubDepartments).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - T2-1 hanya Draft: buat/ubah draft, jawaban Environment Assessment, lampiran tahap REQUEST,
       list dan detail. Submit (nomor, snapshot approval) = T2-2; approval = T2-3.
     - Save Draft minimal: wajib Title + Category; field lain boleh kosong, tetapi bila diisi
       divalidasi. Kelengkapan penuh (field wajib, assessment, ROI CAPEX, foto area) dicek saat Submit.
     - CoCode dan DepartmentID request diambil dari data karyawan requester (BR-40, BR-56) dan
       tidak berubah saat draft diubah. Cost center = APP_SubDepartments milik DepartmentID itu
       (Disabled = 0). PIC = karyawan aktif (ResignDate) pada DepartmentID itu; kunci EmployeeCode.
     - Lingkup data: semua SP baca/ubah membatasi lewat dbo.fn_User_AllowedDepartments(@Username).
       Hak per role (siapa boleh buat/ubah) di Controller (RoleAuthorize).
     - Relasi, folder lampiran, dan URL memakai Id internal, bukan nomor request (BR-55).
     - Lampiran tidak dihapus fisik; hanya dinonaktifkan (BR-46).
   Error   : 50072 = Input wajib kosong / tidak valid
             50073 = Request / lampiran tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.ProjectRequest
      Status (ST): DRAFT (ST-01), WAITING_APPROVAL (ST-02), RETURNED (ST-03), FEASIBILITY (ST-04),
      DOC_PREPARATION (ST-05), MGMT_APPROVAL (ST-06), PLANNING (ST-08), PROCUREMENT (ST-09),
      SCHEDULING (ST-10), IN_PROGRESS (ST-11), BAPP_REVIEW (ST-12), CLOSED (ST-13),
      SURVEY_COMPLETED (ST-14), REJECTED (ST-15), CANCELLED (ST-16).
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectRequest', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectRequest
    (
        Id                     INT IDENTITY(1,1) NOT NULL,
        CoCode                 VARCHAR(10)    NOT NULL,
        DepartmentID           INT            NOT NULL,   -- home..APP_Departments (tanpa FK)
        RequestNo              VARCHAR(40)    NULL,       -- diisi saat Submit (T2-2)
        Status                 VARCHAR(20)    NOT NULL CONSTRAINT DF_ProjectRequest_Status DEFAULT ('DRAFT'),
        RequesterUsername      NVARCHAR(100)  NOT NULL,
        RequesterEmployeeCode  VARCHAR(30)    NOT NULL,
        PicEmployeeCode        VARCHAR(30)    NULL,
        Title                  NVARCHAR(200)  NOT NULL,
        Category               VARCHAR(10)    NOT NULL,
        SubCategoryId          INT            NULL,
        BudgetRemarks          VARCHAR(12)    NULL,
        SubDepartmentID        INT            NULL,       -- cost center, home..APP_SubDepartments (tanpa FK)
        LocationId             INT            NULL,
        TargetCompletionDate   DATE           NULL,
        AreaLength             DECIMAL(10, 2) NULL,
        AreaWidth              DECIMAL(10, 2) NULL,
        AreaSize               AS CAST(AreaLength * AreaWidth AS DECIMAL(18, 2)) PERSISTED,
        BudgetExpectation      DECIMAL(18, 2) NULL,
        Background             NVARCHAR(2000) NULL,
        Objective              NVARCHAR(2000) NULL,
        OperationalImpact      NVARCHAR(2000) NULL,
        RiskIfNotApproved      NVARCHAR(2000) NULL,
        ExpectedBenefits       NVARCHAR(2000) NULL,
        Alternatives           NVARCHAR(2000) NULL,
        SpecialNote            NVARCHAR(2000) NULL,
        ExpectedRoiPercent     DECIMAL(9, 2)  NULL,
        RoiExplanation         NVARCHAR(2000) NULL,
        AdditionalInfo         NVARCHAR(2000) NULL,
        SubmittedAt            DATETIME2(3)   NULL,       -- Submit pertama (T2-2)
        CreatedAt              DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectRequest_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy              NVARCHAR(100)  NULL,
        UpdatedAt              DATETIME2(3)   NULL,
        UpdatedBy              NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectRequest PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ProjectRequest_SubCategory FOREIGN KEY (SubCategoryId) REFERENCES dbo.SubCategory (Id),
        CONSTRAINT FK_ProjectRequest_Location    FOREIGN KEY (LocationId)    REFERENCES dbo.Location (Id),
        CONSTRAINT CK_ProjectRequest_CoCode   CHECK (CoCode IN ('ABL', 'NKM')),
        CONSTRAINT CK_ProjectRequest_Category CHECK (Category IN ('CAPEX', 'OPEX', 'LVE')),
        CONSTRAINT CK_ProjectRequest_Budget   CHECK (BudgetRemarks IS NULL OR BudgetRemarks IN ('BUDGETED', 'UNBUDGETED')),
        CONSTRAINT CK_ProjectRequest_Status   CHECK (Status IN ('DRAFT', 'WAITING_APPROVAL', 'RETURNED', 'FEASIBILITY',
                                                             'DOC_PREPARATION', 'MGMT_APPROVAL', 'PLANNING', 'PROCUREMENT',
                                                             'SCHEDULING', 'IN_PROGRESS', 'BAPP_REVIEW', 'CLOSED',
                                                             'SURVEY_COMPLETED', 'REJECTED', 'CANCELLED')),
        CONSTRAINT CK_ProjectRequest_Area     CHECK ((AreaLength IS NULL OR AreaLength > 0) AND (AreaWidth IS NULL OR AreaWidth > 0)),
        CONSTRAINT CK_ProjectRequest_Amount   CHECK (BudgetExpectation IS NULL OR BudgetExpectation >= 0)
    );
END
GO

/* MIGRASI T3-2 (Keputusan 13-11-2026, BR-05, BR-12): nilai BOQ total (IDR) diisi Civil di Document Preparation,
   wajib sebelum dikirim ke management. Hanya menambah kolom nullable; data lama tidak berubah. */
IF COL_LENGTH(N'dbo.ProjectRequest', N'BoqTotal') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD
        BoqTotal  DECIMAL(18, 2) NULL
            CONSTRAINT CK_ProjectRequest_BoqTotal CHECK (BoqTotal IS NULL OR BoqTotal > 0);
END
GO

/* MIGRASI T4-1 (PRD 3.3, BR-11, BR-12, BR-15): cara eksekusi, plan cost, awal periode Preparation.
   Hanya menambah kolom nullable; data lama tidak berubah. */
IF COL_LENGTH(N'dbo.ProjectRequest', N'ExecutionType') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD
        ExecutionType       VARCHAR(10)    NULL
            CONSTRAINT CK_ProjectRequest_ExecutionType CHECK (ExecutionType IS NULL OR ExecutionType IN ('INHOUSE', 'OUTSOURCE')),
        PlanCost            DECIMAL(18, 2) NULL
            CONSTRAINT CK_ProjectRequest_PlanCost CHECK (PlanCost IS NULL OR PlanCost > 0),
        PreparationStartAt  DATETIME2(3)   NULL;
END
GO

/* MIGRASI T4-3 (FR-03, BR-77): penanda project berjalan yang diinput Civil saat go-live (data migrasi).
   Kolom NOT NULL dengan default 0; baris lama otomatis 0. */
IF COL_LENGTH(N'dbo.ProjectRequest', N'IsMigrated') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD
        IsMigrated  BIT  NOT NULL CONSTRAINT DF_ProjectRequest_IsMigrated DEFAULT (0);
END
GO

/* ---------------------------------------------------------------------
   1a. dbo.fn_User_OutsourceOnly(@Username)  (RL-06: purchasing hanya melihat project outsource)
       1 baris = user hanya memegang role purchasing (tanpa role CIMS lain yang melihat request);
       SP list/detail request menambah syarat ExecutionType = 'OUTSOURCE' untuk user ini.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_OutsourceOnly
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT 1 AS OutsourceOnly
    FROM   home..users u
    WHERE  u.Username = @Username
      AND  EXISTS (SELECT 1 FROM STRING_SPLIT(u.[Role], N';') s WHERE LTRIM(RTRIM(s.value)) = N'purchasing')
      AND  NOT EXISTS (SELECT 1 FROM STRING_SPLIT(u.[Role], N';') s
                       WHERE LTRIM(RTRIM(s.value)) IN (N'administrator', N'director', N'gm', N'civil', N'kabag', N'mo',
                                                       N'adm', N'plan', N'spv', N'emp'))
);
GO

/* ---------------------------------------------------------------------
   1a-2. dbo.fn_Request_VisibleToUser(@Status, @DepartmentID, @Username)  (RL-05 FAT; Keputusan 18-11-2026)
       1 baris = request boleh dilihat menurut aturan FAT. Departemen yang terlihat HANYA karena role fat
       (fn_User_AllowedDepartments.FatOnlyScope = 1) dibatasi ke In Progress, BAPP Review, Closed, Survey Completed;
       departemen yang terlihat lewat role lain (mis. 'kabag;fat' -> departemen sendiri) tetap semua status.
       Lingkup departemen tetap dicek pemanggil (fn_User_AllowedDepartments).
   --------------------------------------------------------------------- */
DROP FUNCTION IF EXISTS dbo.fn_User_FatOnly;   -- versi awal (FAT-only per user) diganti aturan per departemen
GO

CREATE OR ALTER FUNCTION dbo.fn_Request_VisibleToUser
(
    @Status       VARCHAR(20),
    @DepartmentID INT,
    @Username     NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT 1 AS Visible
    WHERE  @Status IN ('IN_PROGRESS', 'BAPP_REVIEW', 'CLOSED', 'SURVEY_COMPLETED')
       OR  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f
                   WHERE f.DepartmentID = @DepartmentID AND f.FatOnlyScope = 0)
);
GO

/* ---------------------------------------------------------------------
   1a-3. dbo.fn_User_CanSeeBapp(@Username)  (matriks 5.2 baris BAPP; T6-1, Keputusan 18-11-2026)
       1 baris = boleh melihat BAPP (data, langkah, lampiran tahap BAPP): kabag, mo, civil, fat, gm, director,
       administrator. adm / plan / spv / emp / purchasing tidak.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_CanSeeBapp
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) 1 AS Allowed
    FROM   home..users u
           CROSS APPLY STRING_SPLIT(u.[Role], N';') s
    WHERE  u.Username = @Username
      AND  LTRIM(RTRIM(s.value)) IN (N'kabag', N'mo', N'civil', N'fat', N'dgo', N'gm', N'director', N'administrator')
);
GO

/* ---------------------------------------------------------------------
   1b. dbo.fn_User_CanChangeAttachment(@Stage, @Status, @Username)  (satu tempat aturan lampiran)
       1 baris = user boleh upload/hapus lampiran jenis tahap @Stage pada request berstatus @Status:
         REQUEST     : DRAFT / RETURNED (requester; role dicek di aplikasi), FEASIBILITY oleh civil (T3-1)
         DOCUMENT    : DOC_PREPARATION oleh civil (BOQ, Drawing; T3-2)
         PROCUREMENT : PLANNING oleh civil (TOR; T4-1, BR-11)
         CONTRACT    : PROCUREMENT oleh purchasing (lampiran kontrak; T4-1, BR-11)
         BAPP        : IN_PROGRESS oleh civil (foto dokumentasi / dokumen pendukung BAPP; T6-1, BR-88)
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_CanChangeAttachment
(
    @Stage    VARCHAR(20),
    @Status   VARCHAR(20),
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    WITH r AS
    (
        SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
        FROM   home..users u
               CROSS APPLY STRING_SPLIT(u.[Role], N';') s
        WHERE  u.Username = @Username
    )
    SELECT 1 AS Allowed
    WHERE  (@Stage = 'REQUEST' AND @Status IN ('DRAFT', 'RETURNED'))
       OR  (@Stage = 'REQUEST'     AND @Status = 'FEASIBILITY'     AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'civil'))
       OR  (@Stage = 'DOCUMENT'    AND @Status = 'DOC_PREPARATION' AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'civil'))
       OR  (@Stage = 'PROCUREMENT' AND @Status = 'PLANNING'        AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'civil'))
       OR  (@Stage = 'CONTRACT'    AND @Status = 'PROCUREMENT'     AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'purchasing'))
       OR  (@Stage = 'BAPP'        AND @Status = 'IN_PROGRESS'     AND EXISTS (SELECT 1 FROM r WHERE RoleCode = N'civil'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_ProjectRequest_RequestNo' AND object_id = OBJECT_ID(N'dbo.ProjectRequest'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_ProjectRequest_RequestNo ON dbo.ProjectRequest (RequestNo) WHERE RequestNo IS NOT NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_ProjectRequest_Dept_Status' AND object_id = OBJECT_ID(N'dbo.ProjectRequest'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectRequest_Dept_Status ON dbo.ProjectRequest (DepartmentID, Status) INCLUDE (CoCode, CreatedAt);
END
GO

/* ---------------------------------------------------------------------
   2. TABLE dbo.RequestAssessmentAnswer  (MD-08; teks pertanyaan disimpan = snapshot)
      Draft: baris hanya untuk pertanyaan yang sudah dijawab. Saat Submit (T2-2) dilengkapi/dikunci.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.RequestAssessmentAnswer', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RequestAssessmentAnswer
    (
        Id            INT IDENTITY(1,1) NOT NULL,
        RequestId     INT           NOT NULL,
        QuestionId    INT           NOT NULL,
        SortOrder     INT           NOT NULL,
        QuestionText  NVARCHAR(300) NOT NULL,
        Answer        BIT           NOT NULL,
        CreatedAt     DATETIME2(3)  NOT NULL CONSTRAINT DF_RequestAssessmentAnswer_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy     NVARCHAR(100) NULL,
        CONSTRAINT PK_RequestAssessmentAnswer PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_RequestAssessmentAnswer_Request  FOREIGN KEY (RequestId)  REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_RequestAssessmentAnswer_Question FOREIGN KEY (QuestionId) REFERENCES dbo.AssessmentQuestion (Id),
        CONSTRAINT UQ_RequestAssessmentAnswer UNIQUE (RequestId, QuestionId)
    );
END
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.RequestAttachment  (BR-44..BR-46; entitas "Attachment" PRD 6.7)
      RelativePath relatif terhadap FileStorage:RealizationAttachmentsPath, mis. 2026\15\<guid>.pdf
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.RequestAttachment', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RequestAttachment
    (
        Id                INT IDENTITY(1,1) NOT NULL,
        RequestId         INT           NOT NULL,
        AttachmentTypeId  INT           NOT NULL,
        OriginalFileName  NVARCHAR(260) NOT NULL,
        RelativePath      NVARCHAR(400) NOT NULL,
        ContentType       VARCHAR(100)  NOT NULL,
        FileSizeBytes     BIGINT        NOT NULL,
        IsActive          BIT           NOT NULL CONSTRAINT DF_RequestAttachment_IsActive  DEFAULT (1),
        CreatedAt         DATETIME2(3)  NOT NULL CONSTRAINT DF_RequestAttachment_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy         NVARCHAR(100) NULL,
        UpdatedAt         DATETIME2(3)  NULL,
        UpdatedBy         NVARCHAR(100) NULL,
        CONSTRAINT PK_RequestAttachment PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_RequestAttachment_Request FOREIGN KEY (RequestId)        REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_RequestAttachment_Type    FOREIGN KEY (AttachmentTypeId) REFERENCES dbo.AttachmentType (Id),
        CONSTRAINT CK_RequestAttachment_Size    CHECK (FileSizeBytes > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_RequestAttachment_Request' AND object_id = OBJECT_ID(N'dbo.RequestAttachment'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_RequestAttachment_Request ON dbo.RequestAttachment (RequestId, IsActive);
END
GO

/* =====================================================================
   LOOKUP untuk form request
   ===================================================================== */

/* ---------------------------------------------------------------------
   4. usp_Lookup_CostCenters  (BR-40: sub-department milik department requester, Disabled = 0)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_CostCenters
    @DepartmentID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  s.SubDepartmentID, s.SubDepartmentCode, s.SubDepartmentName
    FROM    home..APP_SubDepartments s
    WHERE   s.DepartmentID = @DepartmentID
      AND   s.Disabled = 0
    ORDER BY s.DispIndex, s.SubDepartmentCode;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Lookup_ActiveEmployees  (PIC: karyawan aktif pada department requester)
      Aktif = ResignDate NULL atau masih di masa depan (sama dengan aturan login, BR-31).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_ActiveEmployees
    @DepartmentID INT,
    @Search       NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');

    SELECT TOP (200)
            e.EmployeeCode, e.FullName, e.JobTitle
    FROM    home..app_employees e
    WHERE   e.DepartmentID = @DepartmentID
      AND   (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME())
      AND   (@Search IS NULL OR e.FullName LIKE N'%' + @Search + N'%' OR e.EmployeeCode LIKE N'%' + @Search + N'%')
    ORDER BY e.FullName, e.EmployeeCode;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Lookup_Locations  (MD-02 aktif per Company; BR-61)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_Locations
    @CoCode VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Name
    FROM   dbo.Location
    WHERE  CoCode = @CoCode AND IsActive = 1
    ORDER BY Name, Id;
END
GO

/* ---------------------------------------------------------------------
   7. usp_Lookup_AssessmentQuestions  (MD-08 aktif, urut SortOrder)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_AssessmentQuestions
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, SortOrder, QuestionText
    FROM   dbo.AssessmentQuestion
    WHERE  IsActive = 1
    ORDER BY SortOrder, Id;
END
GO

/* ---------------------------------------------------------------------
   8. usp_Lookup_AttachmentTypesByStage  (MD-09 aktif per tahap; validasi upload di aplikasi)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_AttachmentTypesByStage
    @Stage VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, Name, Stage, AllowedExtensions, MaxSizeMB,
           IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve
    FROM   dbo.AttachmentType
    WHERE  Stage = @Stage AND IsActive = 1
    ORDER BY Name, Id;
END
GO

/* =====================================================================
   REQUEST
   ===================================================================== */

/* ---------------------------------------------------------------------
   9. usp_Request_SaveDraft
      @Id NULL = buat draft baru; @Id terisi = ubah draft (status DRAFT atau RETURNED).
      @AssessmentJson: '[{"q":1,"a":true},{"q":2,"a":false}]' (q = AssessmentQuestion.Id);
                       NULL = jawaban tidak diubah; '[]' = hapus semua jawaban.
      Teks panjang diterima NVARCHAR(MAX) lalu dicek panjangnya (tanpa pemotongan diam-diam).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveDraft
    @Id                    INT            = NULL,
    @Username              NVARCHAR(100),
    @Title                 NVARCHAR(MAX),
    @Category              VARCHAR(10),
    @SubCategoryId         INT            = NULL,
    @BudgetRemarks         VARCHAR(12)    = NULL,
    @SubDepartmentID       INT            = NULL,
    @LocationId            INT            = NULL,
    @PicEmployeeCode       VARCHAR(30)    = NULL,
    @TargetCompletionDate  DATE           = NULL,
    @AreaLength            DECIMAL(10, 2) = NULL,
    @AreaWidth             DECIMAL(10, 2) = NULL,
    @BudgetExpectation     DECIMAL(18, 2) = NULL,
    @Background            NVARCHAR(MAX)  = NULL,
    @Objective             NVARCHAR(MAX)  = NULL,
    @OperationalImpact     NVARCHAR(MAX)  = NULL,
    @RiskIfNotApproved     NVARCHAR(MAX)  = NULL,
    @ExpectedBenefits      NVARCHAR(MAX)  = NULL,
    @Alternatives          NVARCHAR(MAX)  = NULL,
    @SpecialNote           NVARCHAR(MAX)  = NULL,
    @ExpectedRoiPercent    DECIMAL(9, 2)  = NULL,
    @RoiExplanation        NVARCHAR(MAX)  = NULL,
    @AdditionalInfo        NVARCHAR(MAX)  = NULL,
    @AssessmentJson        NVARCHAR(MAX)  = NULL,
    @SavedId               INT            = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EmpCode VARCHAR(30), @CoCode VARCHAR(10), @DeptId INT, @Status VARCHAR(20);

    /* -- Requester (karyawan aktif) -- */
    SELECT  @EmpCode = e.EmployeeCode, @CoCode = e.CoCode, @DeptId = e.DepartmentID
    FROM    home..users u
            JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
    WHERE   u.Username = @Username
      AND   (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME());

    IF @EmpCode IS NULL
        THROW 50072, N'Your employee data was not found.', 1;

    IF @Id IS NULL
    BEGIN
        -- Draft baru: Company dan department dari requester (BR-40, BR-56)
        IF @DeptId IS NULL OR ISNULL(@CoCode, '') NOT IN ('ABL', 'NKM')
            THROW 50072, N'Your department or company is not set in the employee data.', 1;
        IF NOT EXISTS (SELECT 1 FROM home..APP_Departments d WHERE d.DepartmentID = @DeptId AND ISNULL(d.Disabled, 0) = 0)
            THROW 50072, N'Your department is disabled.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = @DeptId)
            THROW 50072, N'Your department is outside your data scope.', 1;
    END
    ELSE
    BEGIN
        -- Ubah draft: Company dan department tetap milik request
        SELECT @Status = r.Status, @CoCode = r.CoCode, @DeptId = r.DepartmentID
        FROM   dbo.ProjectRequest r
        WHERE  r.Id = @Id
          AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

        IF @Status IS NULL
            THROW 50073, N'Request not found.', 1;
        IF @Status NOT IN ('DRAFT', 'RETURNED')
            THROW 50074, N'Only draft or returned requests can be edited.', 1;
    END

    /* -- Normalisasi -- */
    SET @Title             = NULLIF(LTRIM(RTRIM(@Title)), N'');
    SET @Category          = UPPER(LTRIM(RTRIM(@Category)));
    SET @BudgetRemarks     = NULLIF(UPPER(LTRIM(RTRIM(@BudgetRemarks))), '');
    SET @PicEmployeeCode   = NULLIF(LTRIM(RTRIM(@PicEmployeeCode)), '');
    SET @Background        = NULLIF(LTRIM(RTRIM(@Background)), N'');
    SET @Objective         = NULLIF(LTRIM(RTRIM(@Objective)), N'');
    SET @OperationalImpact = NULLIF(LTRIM(RTRIM(@OperationalImpact)), N'');
    SET @RiskIfNotApproved = NULLIF(LTRIM(RTRIM(@RiskIfNotApproved)), N'');
    SET @ExpectedBenefits  = NULLIF(LTRIM(RTRIM(@ExpectedBenefits)), N'');
    SET @Alternatives      = NULLIF(LTRIM(RTRIM(@Alternatives)), N'');
    SET @SpecialNote       = NULLIF(LTRIM(RTRIM(@SpecialNote)), N'');
    SET @RoiExplanation    = NULLIF(LTRIM(RTRIM(@RoiExplanation)), N'');
    SET @AdditionalInfo    = NULLIF(LTRIM(RTRIM(@AdditionalInfo)), N'');

    /* -- Wajib saat Draft -- */
    IF @Title IS NULL                                           THROW 50072, N'Request title is required.', 1;
    IF LEN(@Title) > 200                                        THROW 50072, N'Request title must be at most 200 characters.', 1;
    IF ISNULL(@Category, '') NOT IN ('CAPEX', 'OPEX', 'LVE')    THROW 50072, N'Budget classification is required (CAPEX, OPEX, or LVE).', 1;

    /* -- Opsional saat Draft, divalidasi bila diisi -- */
    IF @SubCategoryId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.SubCategory WHERE Id = @SubCategoryId AND Category = @Category AND IsActive = 1)
        THROW 50072, N'Sub-category is invalid for the selected budget classification.', 1;

    IF @BudgetRemarks IS NOT NULL AND @BudgetRemarks NOT IN ('BUDGETED', 'UNBUDGETED')
        THROW 50072, N'Budget remarks must be Budgeted or Unbudgeted.', 1;

    IF @SubDepartmentID IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM home..APP_SubDepartments s
                       WHERE s.SubDepartmentID = @SubDepartmentID AND s.DepartmentID = @DeptId AND s.Disabled = 0)
        THROW 50072, N'Cost center is invalid for the requesting department.', 1;

    IF @LocationId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.Location WHERE Id = @LocationId AND CoCode = @CoCode AND IsActive = 1)
        THROW 50072, N'Location is invalid for the request company.', 1;

    IF @PicEmployeeCode IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM home..app_employees e
                       WHERE e.EmployeeCode = @PicEmployeeCode AND e.DepartmentID = @DeptId
                         AND (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME()))
        THROW 50072, N'PIC must be an active employee of the requesting department.', 1;

    IF @TargetCompletionDate IS NOT NULL AND @TargetCompletionDate < CAST(SYSDATETIME() AS DATE)
        THROW 50072, N'Target completion cannot be in the past.', 1;
    IF @AreaLength IS NOT NULL AND @AreaLength <= 0             THROW 50072, N'Area length must be greater than 0.', 1;
    IF @AreaWidth  IS NOT NULL AND @AreaWidth  <= 0             THROW 50072, N'Area width must be greater than 0.', 1;
    IF @BudgetExpectation IS NOT NULL AND @BudgetExpectation < 0
        THROW 50072, N'Budget expectation cannot be negative.', 1;
    IF @ExpectedRoiPercent IS NOT NULL AND @ExpectedRoiPercent NOT BETWEEN -100 AND 10000
        THROW 50072, N'Expected ROI must be between -100 and 10000 %.', 1;

    IF LEN(@Background) > 2000 OR LEN(@Objective) > 2000 OR LEN(@OperationalImpact) > 2000
       OR LEN(@RiskIfNotApproved) > 2000 OR LEN(@ExpectedBenefits) > 2000 OR LEN(@Alternatives) > 2000
       OR LEN(@SpecialNote) > 2000 OR LEN(@RoiExplanation) > 2000 OR LEN(@AdditionalInfo) > 2000
        THROW 50072, N'Each text field must be at most 2000 characters.', 1;

    /* -- Jawaban assessment -- */
    DECLARE @Answers TABLE (QuestionId INT PRIMARY KEY, Answer BIT NOT NULL);

    IF @AssessmentJson IS NOT NULL
    BEGIN
        IF ISJSON(@AssessmentJson) = 0
            THROW 50072, N'Environment assessment answers are invalid.', 1;

        BEGIN TRY
            INSERT INTO @Answers (QuestionId, Answer)
            SELECT j.q, j.a
            FROM   OPENJSON(@AssessmentJson) WITH (q INT '$.q', a BIT '$.a') j
            WHERE  j.q IS NOT NULL AND j.a IS NOT NULL;
        END TRY
        BEGIN CATCH
            THROW 50072, N'Environment assessment answers are invalid.', 1;
        END CATCH

        IF EXISTS (SELECT 1 FROM @Answers a
                   WHERE NOT EXISTS (SELECT 1 FROM dbo.AssessmentQuestion q WHERE q.Id = a.QuestionId AND q.IsActive = 1))
            THROW 50072, N'Environment assessment contains an unknown or inactive question.', 1;
    END

    /* -- Simpan -- */
    BEGIN TRANSACTION;

    IF @Id IS NULL
    BEGIN
        INSERT INTO dbo.ProjectRequest
            (CoCode, DepartmentID, Status, RequesterUsername, RequesterEmployeeCode, PicEmployeeCode,
             Title, Category, SubCategoryId, BudgetRemarks, SubDepartmentID, LocationId, TargetCompletionDate,
             AreaLength, AreaWidth, BudgetExpectation, Background, Objective, OperationalImpact,
             RiskIfNotApproved, ExpectedBenefits, Alternatives, SpecialNote, ExpectedRoiPercent,
             RoiExplanation, AdditionalInfo, CreatedBy)
        VALUES
            (@CoCode, @DeptId, 'DRAFT', @Username, @EmpCode, @PicEmployeeCode,
             @Title, @Category, @SubCategoryId, @BudgetRemarks, @SubDepartmentID, @LocationId, @TargetCompletionDate,
             @AreaLength, @AreaWidth, @BudgetExpectation, @Background, @Objective, @OperationalImpact,
             @RiskIfNotApproved, @ExpectedBenefits, @Alternatives, @SpecialNote, @ExpectedRoiPercent,
             @RoiExplanation, @AdditionalInfo, @Username);

        SET @SavedId = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.ProjectRequest
        SET    PicEmployeeCode      = @PicEmployeeCode,
               Title                = @Title,
               Category             = @Category,
               SubCategoryId        = @SubCategoryId,
               BudgetRemarks        = @BudgetRemarks,
               SubDepartmentID      = @SubDepartmentID,
               LocationId           = @LocationId,
               TargetCompletionDate = @TargetCompletionDate,
               AreaLength           = @AreaLength,
               AreaWidth            = @AreaWidth,
               BudgetExpectation    = @BudgetExpectation,
               Background           = @Background,
               Objective            = @Objective,
               OperationalImpact    = @OperationalImpact,
               RiskIfNotApproved    = @RiskIfNotApproved,
               ExpectedBenefits     = @ExpectedBenefits,
               Alternatives         = @Alternatives,
               SpecialNote          = @SpecialNote,
               ExpectedRoiPercent   = @ExpectedRoiPercent,
               RoiExplanation       = @RoiExplanation,
               AdditionalInfo       = @AdditionalInfo,
               UpdatedAt            = SYSDATETIME(),
               UpdatedBy            = @Username
        WHERE  Id = @Id AND Status IN ('DRAFT', 'RETURNED');

        IF @@ROWCOUNT = 0
            THROW 50074, N'Only draft or returned requests can be edited.', 1;

        SET @SavedId = @Id;
    END

    IF @AssessmentJson IS NOT NULL
    BEGIN
        DELETE FROM dbo.RequestAssessmentAnswer WHERE RequestId = @SavedId;

        INSERT INTO dbo.RequestAssessmentAnswer (RequestId, QuestionId, SortOrder, QuestionText, Answer, CreatedBy)
        SELECT @SavedId, q.Id, q.SortOrder, q.QuestionText, a.Answer, @Username
        FROM   @Answers a
               JOIN dbo.AssessmentQuestion q ON q.Id = a.QuestionId;
    END

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   10. usp_Request_GetById  (detail + nama tampilan; 0 baris = tidak ada / di luar lingkup)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetById
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  r.Id, r.CoCode, r.DepartmentID, d.DeptName, d.ABRV, r.RequestNo, r.Status,
            r.RequesterUsername, r.RequesterEmployeeCode, req.FullName AS RequesterName,
            r.PicEmployeeCode, pic.FullName AS PicName,
            r.Title, r.Category, r.SubCategoryId, sc.Name AS SubCategoryName,
            r.BudgetRemarks, r.SubDepartmentID, sd.SubDepartmentCode AS CostCenterCode, sd.SubDepartmentName AS CostCenterName,
            r.LocationId, l.Name AS LocationName, r.TargetCompletionDate,
            r.AreaLength, r.AreaWidth, r.AreaSize, r.BudgetExpectation,
            r.Background, r.Objective, r.OperationalImpact, r.RiskIfNotApproved, r.ExpectedBenefits,
            r.Alternatives, r.SpecialNote, r.ExpectedRoiPercent, r.RoiExplanation, r.AdditionalInfo,
            r.BoqTotal, r.ExecutionType, r.PlanCost, r.PreparationStartAt, r.IsMigrated,
            r.SubmittedAt, r.CreatedAt, r.CreatedBy, r.UpdatedAt, r.UpdatedBy
    FROM    dbo.ProjectRequest r
            LEFT JOIN home..APP_Departments d     ON d.DepartmentID = r.DepartmentID
            LEFT JOIN home..app_employees req     ON req.EmployeeCode = r.RequesterEmployeeCode
            LEFT JOIN home..app_employees pic     ON pic.EmployeeCode = r.PicEmployeeCode
            LEFT JOIN home..APP_SubDepartments sd ON sd.SubDepartmentID = r.SubDepartmentID
            LEFT JOIN dbo.SubCategory sc          ON sc.Id = r.SubCategoryId
            LEFT JOIN dbo.Location l              ON l.Id = r.LocationId
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      -- RL-06: purchasing (tanpa role lain) hanya project outsource
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)))
      -- RL-05: departemen yang terlihat hanya karena role fat -> In Progress ke atas (18-11-2026)
      AND   EXISTS (SELECT 1 FROM dbo.fn_Request_VisibleToUser(r.Status, r.DepartmentID, @Username));
END
GO

/* ---------------------------------------------------------------------
   11. usp_Request_GetAssessment
       DRAFT / RETURNED : pertanyaan aktif + jawaban yang sudah ada (Answer NULL = belum dijawab)
       status lain      : jawaban tersimpan (snapshot saat Submit)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetAssessment
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status VARCHAR(20) =
    (
        SELECT r.Status FROM dbo.ProjectRequest r
        WHERE  r.Id = @RequestId
          AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
    );

    IF @Status IS NULL
        RETURN;

    IF @Status IN ('DRAFT', 'RETURNED')
        SELECT  q.Id AS QuestionId, q.SortOrder, q.QuestionText, a.Answer
        FROM    dbo.AssessmentQuestion q
                LEFT JOIN dbo.RequestAssessmentAnswer a ON a.QuestionId = q.Id AND a.RequestId = @RequestId
        WHERE   q.IsActive = 1
        ORDER BY q.SortOrder, q.Id;
    ELSE
        SELECT  a.QuestionId, a.SortOrder, a.QuestionText, CAST(a.Answer AS BIT) AS Answer
        FROM    dbo.RequestAssessmentAnswer a
        WHERE   a.RequestId = @RequestId
        ORDER BY a.SortOrder, a.QuestionId;
END
GO

/* ---------------------------------------------------------------------
   12. usp_Request_GetPaged  (list dalam lingkup user; filter Company untuk role lintas Company, BR-57;
       filter departemen @DepartmentID, tetap dibatasi lingkup user)
       @SortBy  : CreatedAt | RequestNo | Title | Category | Status   (default CreatedAt)
       @SortDir : ASC | DESC                                          (default DESC)
       T4-4 (Keputusan 18-11-2026): kolom OpenAddendumStatus / OpenAddendumCode = addendum yang masih terbuka
       (PENDING_APPROVAL / FINAL_CONTRACT / ADJUSTMENT) untuk tanda follow up; @AddendumOpen = 1 -> hanya project dengan addendum
       terbuka. Hak lihat BR-86: addendum outsource hanya untuk civil, purchasing, fat, gm, director, administrator
       (sama dengan fn_User_CanSeeAddendum; ditulis inline agar script ini tidak bergantung pada RequestAddendum.sql).
       Tabel ProjectAddendum dibaca saat dijalankan: jalankan RequestAddendum.sql sebelum memakai list.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetPaged
    @Username    NVARCHAR(100),
    @CoCode      VARCHAR(10)   = NULL,
    @DepartmentID INT          = NULL,
    @Search      NVARCHAR(100) = NULL,
    @Category    VARCHAR(10)   = NULL,
    @Status      VARCHAR(20)   = NULL,
    @AddendumOpen BIT          = NULL,
    @SortBy      NVARCHAR(20)  = N'CreatedAt',
    @SortDir     NVARCHAR(4)   = N'DESC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode     = NULLIF(LTRIM(RTRIM(@CoCode)), '');
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @Category   = NULLIF(LTRIM(RTRIM(@Category)), '');
    SET @Status     = NULLIF(LTRIM(RTRIM(@Status)), '');
    SET @SortBy     = CASE WHEN @SortBy IN (N'CreatedAt', N'RequestNo', N'Title', N'Category', N'Status') THEN @SortBy ELSE N'CreatedAt' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'ASC' THEN N'ASC' ELSE N'DESC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    -- Batas 5000 untuk export Excel (FR-04); tampilan list tetap dibatasi Controller (10 baris)
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 5000 THEN 5000
                           ELSE @PageSize END;

    -- FatOnlyScope = 1: departemen terlihat hanya karena role fat -> In Progress ke atas (RL-05, Keputusan 18-11-2026)
    DECLARE @Scope TABLE (DepartmentID INT PRIMARY KEY, FatOnlyScope BIT NOT NULL);
    INSERT INTO @Scope (DepartmentID, FatOnlyScope)
    SELECT f.DepartmentID, MIN(CAST(f.FatOnlyScope AS INT)) FROM dbo.fn_User_AllowedDepartments(@Username) f GROUP BY f.DepartmentID;

    -- RL-06: purchasing (tanpa role lain) hanya project outsource
    DECLARE @OutsourceOnly BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)) THEN 1 ELSE 0 END;

    -- BR-86: boleh melihat addendum outsource (baris Kontrak matriks 5.2); in-house = semua yang melihat request
    DECLARE @SeeOutsourceAddendum BIT =
        CASE WHEN EXISTS (SELECT 1 FROM home..users u CROSS APPLY STRING_SPLIT(u.[Role], N';') x
                          WHERE u.Username = @Username
                            AND LTRIM(RTRIM(x.value)) IN (N'civil', N'purchasing', N'fat', N'dgo', N'gm', N'director', N'administrator'))
             THEN 1 ELSE 0 END;
    SET @AddendumOpen = CASE WHEN @AddendumOpen = 1 THEN 1 ELSE NULL END;

    SELECT @TotalCount = COUNT(*)
    FROM   dbo.ProjectRequest r
           JOIN @Scope s ON s.DepartmentID = r.DepartmentID
    WHERE  (@OutsourceOnly = 0 OR r.ExecutionType = 'OUTSOURCE')
      AND  (s.FatOnlyScope = 0 OR r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW', 'CLOSED', 'SURVEY_COMPLETED'))
      AND  (@CoCode   IS NULL OR r.CoCode   = @CoCode)
      AND  (@DepartmentID IS NULL OR r.DepartmentID = @DepartmentID)
      AND  (@Category IS NULL OR r.Category = @Category)
      AND  (@Status   IS NULL OR r.Status   = @Status)
      AND  (@Search   IS NULL OR r.Title LIKE N'%' + @Search + N'%' OR r.RequestNo LIKE '%' + @Search + '%'
            -- BR-54: nomor lama (sebelum ganti kategori) tetap bisa dicari
            OR EXISTS (SELECT 1 FROM dbo.RequestNoHistory nh WHERE nh.RequestId = r.Id AND nh.RequestNo LIKE '%' + @Search + '%'))
      AND  (@AddendumOpen IS NULL
            OR EXISTS (SELECT 1 FROM dbo.ProjectAddendum ad
                       WHERE ad.RequestId = r.Id AND ad.Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT')
                         AND (ad.ExecutionType = 'INHOUSE' OR @SeeOutsourceAddendum = 1)))
    OPTION (RECOMPILE);

    SELECT  r.Id, r.CoCode, r.RequestNo, r.Title, r.Category, sc.Name AS SubCategoryName, r.Status,
            r.DepartmentID, d.DeptName, d.ABRV, req.FullName AS RequesterName,
            r.TargetCompletionDate, r.BudgetExpectation, r.SubmittedAt, r.CreatedAt, r.UpdatedAt,
            oa.Status AS OpenAddendumStatus, oa.AddendumCode AS OpenAddendumCode
    FROM    dbo.ProjectRequest r
            JOIN @Scope s ON s.DepartmentID = r.DepartmentID
            LEFT JOIN dbo.SubCategory sc      ON sc.Id = r.SubCategoryId
            LEFT JOIN home..APP_Departments d ON d.DepartmentID = r.DepartmentID
            LEFT JOIN home..app_employees req ON req.EmployeeCode = r.RequesterEmployeeCode
            OUTER APPLY (SELECT TOP (1) ad.Status, ad.AddendumCode
                         FROM   dbo.ProjectAddendum ad
                         WHERE  ad.RequestId = r.Id AND ad.Status IN ('PENDING_APPROVAL', 'FINAL_CONTRACT', 'ADJUSTMENT')
                           AND  (ad.ExecutionType = 'INHOUSE' OR @SeeOutsourceAddendum = 1)) oa
    WHERE   (@OutsourceOnly = 0 OR r.ExecutionType = 'OUTSOURCE')
      AND   (s.FatOnlyScope = 0 OR r.Status IN ('IN_PROGRESS', 'BAPP_REVIEW', 'CLOSED', 'SURVEY_COMPLETED'))
      AND   (@CoCode   IS NULL OR r.CoCode   = @CoCode)
      AND   (@DepartmentID IS NULL OR r.DepartmentID = @DepartmentID)
      AND   (@Category IS NULL OR r.Category = @Category)
      AND   (@Status   IS NULL OR r.Status   = @Status)
      AND   (@Search   IS NULL OR r.Title LIKE N'%' + @Search + N'%' OR r.RequestNo LIKE '%' + @Search + '%'
             OR EXISTS (SELECT 1 FROM dbo.RequestNoHistory nh WHERE nh.RequestId = r.Id AND nh.RequestNo LIKE '%' + @Search + '%'))
      AND   (@AddendumOpen IS NULL OR oa.Status IS NOT NULL)
    ORDER BY
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN r.CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN r.CreatedAt END DESC,
        CASE WHEN @SortBy = N'RequestNo' AND @SortDir = N'ASC'  THEN r.RequestNo END ASC,
        CASE WHEN @SortBy = N'RequestNo' AND @SortDir = N'DESC' THEN r.RequestNo END DESC,
        CASE WHEN @SortBy = N'Title'     AND @SortDir = N'ASC'  THEN r.Title     END ASC,
        CASE WHEN @SortBy = N'Title'     AND @SortDir = N'DESC' THEN r.Title     END DESC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'ASC'  THEN CHARINDEX(',' + r.Category + ',', ',CAPEX,OPEX,LVE,') END ASC,
        CASE WHEN @SortBy = N'Category'  AND @SortDir = N'DESC' THEN CHARINDEX(',' + r.Category + ',', ',CAPEX,OPEX,LVE,') END DESC,
        CASE WHEN @SortBy = N'Status'    AND @SortDir = N'ASC'  THEN r.Status    END ASC,
        CASE WHEN @SortBy = N'Status'    AND @SortDir = N'DESC' THEN r.Status    END DESC,
        r.Id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* =====================================================================
   LAMPIRAN
   ===================================================================== */

/* ---------------------------------------------------------------------
   13. usp_RequestAttachment_Insert
       File sudah ditulis aplikasi ke disk; SP memvalidasi ulang (lingkup, status, jenis,
       ekstensi, ukuran) lalu mencatat metadata. Bila SP gagal, aplikasi menghapus file yang baru ditulis.
       Jenis tahap REQUEST: status DRAFT / RETURNED (requester; T2), atau FEASIBILITY oleh role civil
       (mis. lampiran ROI setelah Civil mengubah kategori ke CAPEX; T3-1, BR-42).
       Jenis tahap DOCUMENT (BOQ, Drawing; BR-05): status DOC_PREPARATION oleh role civil (T3-2).
       Jenis tahap PROCUREMENT (TOR): PLANNING oleh civil · CONTRACT: PROCUREMENT oleh purchasing (T4-1, BR-11).
       Aturan lengkap: dbo.fn_User_CanChangeAttachment.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RequestAttachment_Insert
    @RequestId         INT,
    @Username          NVARCHAR(100),
    @AttachmentTypeId  INT,
    @OriginalFileName  NVARCHAR(260),
    @RelativePath      NVARCHAR(400),
    @ContentType       VARCHAR(100),
    @FileSizeBytes     BIGINT,
    @NewId             INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status VARCHAR(20), @Stage VARCHAR(20), @Ext VARCHAR(200), @MaxMB INT, @FileExt VARCHAR(20);

    SELECT @Status = r.Status
    FROM   dbo.ProjectRequest r
    WHERE  r.Id = @RequestId
      AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;

    SELECT @Stage = t.Stage, @Ext = t.AllowedExtensions, @MaxMB = t.MaxSizeMB
    FROM   dbo.AttachmentType t
    WHERE  t.Id = @AttachmentTypeId AND t.IsActive = 1;

    IF @Stage IS NULL
        THROW 50072, N'Attachment type is invalid.', 1;
    IF @Stage NOT IN ('REQUEST', 'DOCUMENT', 'PROCUREMENT', 'CONTRACT', 'BAPP')
        THROW 50072, N'This attachment type cannot be uploaded at this stage.', 1;

    -- Aturan tahap x status x role: dbo.fn_User_CanChangeAttachment (T2, T3-1, T3-2, T4-1)
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_CanChangeAttachment(@Stage, @Status, @Username))
        THROW 50074, N'Attachments cannot be changed at the current request status.', 1;

    SET @OriginalFileName = LTRIM(RTRIM(@OriginalFileName));
    IF ISNULL(@OriginalFileName, N'') = N'' OR ISNULL(@RelativePath, N'') = N''
        THROW 50072, N'File name is required.', 1;

    -- Ekstensi = teks setelah titik terakhir, huruf kecil
    SET @FileExt = CASE WHEN CHARINDEX('.', @OriginalFileName) = 0 THEN ''
                        ELSE LOWER(RIGHT(@OriginalFileName, CHARINDEX('.', REVERSE(@OriginalFileName)) - 1)) END;

    IF @FileExt = '' OR CHARINDEX(',' + @FileExt + ',', ',' + @Ext + ',') = 0
        THROW 50072, N'File type is not allowed for this attachment type.', 1;
    IF @FileSizeBytes IS NULL OR @FileSizeBytes <= 0 OR @FileSizeBytes > CAST(@MaxMB AS BIGINT) * 1048576
        THROW 50072, N'File size exceeds the maximum for this attachment type.', 1;

    INSERT INTO dbo.RequestAttachment
        (RequestId, AttachmentTypeId, OriginalFileName, RelativePath, ContentType, FileSizeBytes, CreatedBy)
    VALUES
        (@RequestId, @AttachmentTypeId, @OriginalFileName, @RelativePath, ISNULL(NULLIF(@ContentType, ''), 'application/octet-stream'),
         @FileSizeBytes, @Username);

    SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
END
GO

/* ---------------------------------------------------------------------
   14. usp_RequestAttachment_ListByRequest  (aktif saja; urut jenis lalu waktu upload)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RequestAttachment_ListByRequest
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  a.Id, a.RequestId, a.AttachmentTypeId, t.Code AS AttachmentTypeCode, t.Name AS AttachmentTypeName, t.Stage,
            a.OriginalFileName, a.ContentType, a.FileSizeBytes, a.CreatedAt, a.CreatedBy
    FROM    dbo.RequestAttachment a
            JOIN dbo.AttachmentType t  ON t.Id = a.AttachmentTypeId
            JOIN dbo.ProjectRequest r  ON r.Id = a.RequestId
    WHERE   a.RequestId = @RequestId
      AND   a.IsActive = 1
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)))
      AND   EXISTS (SELECT 1 FROM dbo.fn_Request_VisibleToUser(r.Status, r.DepartmentID, @Username))   -- RL-05 FAT
      AND   (t.Stage <> 'BAPP' OR EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeBapp(@Username)))   -- 5.2 BAPP (T6-1)
    ORDER BY t.Name, a.CreatedAt, a.Id;
END
GO

/* ---------------------------------------------------------------------
   15. usp_RequestAttachment_GetById  (untuk download; aktif + dalam lingkup user)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RequestAttachment_GetById
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  a.Id, a.RequestId, a.AttachmentTypeId, t.Code AS AttachmentTypeCode, t.Name AS AttachmentTypeName, t.Stage,
            a.OriginalFileName, a.RelativePath, a.ContentType, a.FileSizeBytes, a.CreatedAt, a.CreatedBy
    FROM    dbo.RequestAttachment a
            JOIN dbo.AttachmentType t  ON t.Id = a.AttachmentTypeId
            JOIN dbo.ProjectRequest r  ON r.Id = a.RequestId
    WHERE   a.Id = @Id
      AND   a.IsActive = 1
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)))
      AND   EXISTS (SELECT 1 FROM dbo.fn_Request_VisibleToUser(r.Status, r.DepartmentID, @Username))   -- RL-05 FAT
      AND   (t.Stage <> 'BAPP' OR EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeBapp(@Username)));   -- 5.2 BAPP (T6-1)
END
GO

/* ---------------------------------------------------------------------
   16. usp_RequestAttachment_Deactivate  (BR-46: tidak dihapus fisik)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_RequestAttachment_Deactivate
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status VARCHAR(20), @Stage VARCHAR(20);

    SELECT  @Status = r.Status, @Stage = t.Stage
    FROM    dbo.RequestAttachment a
            JOIN dbo.AttachmentType t ON t.Id = a.AttachmentTypeId
            JOIN dbo.ProjectRequest r ON r.Id = a.RequestId
    WHERE   a.Id = @Id
      AND   a.IsActive = 1
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Attachment not found.', 1;
    -- Aturan sama dengan Insert (dbo.fn_User_CanChangeAttachment)
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_CanChangeAttachment(@Stage, @Status, @Username))
        THROW 50074, N'Attachments cannot be changed at the current request status.', 1;

    UPDATE dbo.RequestAttachment
    SET    IsActive  = 0,
           UpdatedAt = SYSDATETIME(),
           UpdatedBy = @Username
    WHERE  Id = @Id;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel (@U, @Id, ...) hanya hidup dalam satu eksekusi: blok yang berisi baris error (3, 5, 7, 8)
   jalankan per baris bersama DECLARE yang dibutuhkan, atau set @Id ke Id draft uji.

   -- 0) Siapkan: user requester (adm/plan/spv) dan departemennya
   SELECT u.Username, u.[Role], e.EmployeeCode, e.CoCode, e.DepartmentID, ad.ABRV
   FROM   home..users u JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
          LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
   WHERE  u.[Role] LIKE N'%adm%';
   DECLARE @U NVARCHAR(100) = N'<user-adm>', @Dept INT = <DepartmentID-user>;

   -- 1) Lookup
   EXEC dbo.usp_Lookup_CostCenters @DepartmentID = @Dept;                  -- sub-department Disabled = 0
   EXEC dbo.usp_Lookup_ActiveEmployees @DepartmentID = @Dept;              -- karyawan aktif
   EXEC dbo.usp_Lookup_Locations @CoCode = 'ABL';                          -- 40 lokasi aktif ABL
   EXEC dbo.usp_Lookup_AssessmentQuestions;                                -- 12 pertanyaan
   EXEC dbo.usp_Lookup_AttachmentTypesByStage @Stage = 'REQUEST';          -- ROI, AREA_PHOTO

   -- 2) Draft minimal (hanya Title + Category) -> berhasil; CoCode/DepartmentID dari karyawan
   DECLARE @Id INT;
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'  Repair road  ', @Category = 'opex', @SavedId = @Id OUTPUT;
   EXEC dbo.usp_Request_GetById @Id = @Id, @Username = @U;                -- Status DRAFT, Title 'Repair road', OPEX

   -- 3) Validasi -> 50072
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'', @Category = 'OPEX';
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'XYZ';
   DECLARE @ScCapex INT = (SELECT Id FROM dbo.SubCategory WHERE Code = 'CONSTRUCTION_PROJECT');
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @SubCategoryId = @ScCapex;   -- sub-kategori CAPEX
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @SubDepartmentID = -1;
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @PicEmployeeCode = 'TIDAK_ADA';
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @TargetCompletionDate = '2020-01-01';
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @AreaLength = 0;
   EXEC dbo.usp_Request_SaveDraft @Username = @U, @Title = N'A', @Category = 'OPEX', @AssessmentJson = N'[{"q":999999,"a":true}]';

   -- 4) Ubah draft lengkap + jawaban assessment; luas = panjang x lebar
   DECLARE @Q1 INT = (SELECT MIN(Id) FROM dbo.AssessmentQuestion WHERE IsActive = 1);
   DECLARE @Json NVARCHAR(MAX) = N'[{"q":' + CAST(@Q1 AS NVARCHAR(10)) + N',"a":true}]';
   DECLARE @ScOpex INT = (SELECT Id FROM dbo.SubCategory WHERE Code = 'CORRECTIVE_MAINT');
   EXEC dbo.usp_Request_SaveDraft @Id = @Id, @Username = @U, @Title = N'Repair road B', @Category = 'OPEX',
        @SubCategoryId = @ScOpex,
        @BudgetRemarks = 'budgeted', @AreaLength = 12.5, @AreaWidth = 4, @BudgetExpectation = 15000000,
        @TargetCompletionDate = '2026-12-31', @AssessmentJson = @Json, @SavedId = @Id OUTPUT;
   EXEC dbo.usp_Request_GetById @Id = @Id, @Username = @U;                -- AreaSize 50.00, BUDGETED
   EXEC dbo.usp_Request_GetAssessment @RequestId = @Id, @Username = @U;   -- 12 baris, 1 terjawab (1), sisanya NULL

   -- 5) Lingkup: user departemen lain (adm ABRV lain) -> 0 baris; ubah -> 50073
   EXEC dbo.usp_Request_GetById @Id = @Id, @Username = N'<user-adm-dept-lain>';
   EXEC dbo.usp_Request_SaveDraft @Id = @Id, @Username = N'<user-adm-dept-lain>', @Title = N'X', @Category = 'OPEX';

   -- 6) List dalam lingkup
   DECLARE @Total INT;
   EXEC dbo.usp_Request_GetPaged @Username = @U, @TotalCount = @Total OUTPUT;   SELECT @Total;
   EXEC dbo.usp_Request_GetPaged @Username = @U, @Search = N'road', @Status = 'DRAFT', @TotalCount = @Total OUTPUT;

   -- 7) Lampiran (metadata saja; file dibuat aplikasi)
   DECLARE @T INT = (SELECT Id FROM dbo.AttachmentType WHERE Code = 'AREA_PHOTO'), @A INT;
   EXEC dbo.usp_RequestAttachment_Insert @RequestId = @Id, @Username = @U, @AttachmentTypeId = @T,
        @OriginalFileName = N'area.JPG', @RelativePath = N'2026\1\test.jpg', @ContentType = 'image/jpeg',
        @FileSizeBytes = 1000, @NewId = @A OUTPUT;                                       -- berhasil (ekstensi jpg)
   EXEC dbo.usp_RequestAttachment_Insert @RequestId = @Id, @Username = @U, @AttachmentTypeId = @T,
        @OriginalFileName = N'area.exe', @RelativePath = N'x', @ContentType = 'x', @FileSizeBytes = 1000;     -- 50072 ekstensi
   EXEC dbo.usp_RequestAttachment_Insert @RequestId = @Id, @Username = @U, @AttachmentTypeId = @T,
        @OriginalFileName = N'big.pdf', @RelativePath = N'x', @ContentType = 'x', @FileSizeBytes = 6000000;   -- 50072 ukuran (> 5 MB)
   DECLARE @Boq INT = (SELECT Id FROM dbo.AttachmentType WHERE Code = 'BOQ');
   EXEC dbo.usp_RequestAttachment_Insert @RequestId = @Id, @Username = @U, @AttachmentTypeId = @Boq,
        @OriginalFileName = N'boq.pdf', @RelativePath = N'x', @ContentType = 'x', @FileSizeBytes = 1000;      -- 50072 tahap
   EXEC dbo.usp_RequestAttachment_ListByRequest @RequestId = @Id, @Username = @U;   -- 1 baris
   EXEC dbo.usp_RequestAttachment_Deactivate @Id = @A, @Username = @U;
   EXEC dbo.usp_RequestAttachment_ListByRequest @RequestId = @Id, @Username = @U;   -- 0 baris (data tetap ada, IsActive = 0)

   -- 8) Status bukan draft -> 50074 (simulasi; kembalikan setelahnya)
   UPDATE dbo.ProjectRequest SET Status = 'WAITING_APPROVAL' WHERE Id = @Id;
   EXEC dbo.usp_Request_SaveDraft @Id = @Id, @Username = @U, @Title = N'X', @Category = 'OPEX';      -- 50074
   UPDATE dbo.ProjectRequest SET Status = 'DRAFT' WHERE Id = @Id;

   -- 9) Bersihkan data uji (dev saja):
   --    DELETE dbo.RequestAttachment       WHERE RequestId = @Id;
   --    DELETE dbo.RequestAssessmentAnswer WHERE RequestId = @Id;
   --    DELETE dbo.ProjectRequest          WHERE Id = @Id;
   ===================================================================== */
