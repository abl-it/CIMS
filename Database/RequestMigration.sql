/* =====================================================================
   RequestMigration.sql  -  Input project berjalan saat go-live (T4-3; PRD 9.3: FR-03, BR-76, BR-77)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Request.sql (kolom IsMigrated),
             RequestExecution.sql (ProjectContract), dan RequestSchedule.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Aturan (Keputusan 16-11-2026, lihat docs/PRD-log.md):
     - Khusus civil. Project lama langsung dicatat pada status PLANNING atau SCHEDULING, tanpa approval di CIMS.
       Project yang sudah berjalan: masuk SCHEDULING, lalu Civil mengisi schedule/action plan/estimasi dan
       mencatat site handover (tanggal lampau) lewat alur T4-2, sehingga validasi T4-2 tetap berlaku.
     - Wajib: departemen (lingkup user), judul, kategori, sub-kategori, lokasi. Lainnya opsional.
     - SCHEDULING wajib cara eksekusi:
         INHOUSE   : BOQ total wajib -> plan cost = BOQ total.
         OUTSOURCE : kontrak diinput Civil (vendor aktif, nomor, tanggal, nilai) -> plan cost = nilai kontrak.
       Awal periode Preparation: tanggal yang diisi, atau default tanggal kontrak (outsource) / hari ini (in-house).
     - Nomor request format sama, bulan/tahun = bulan input (BR-77); IsMigrated = 1.
     - Approval di luar sistem (BR-76): baris opsional (langkah/role, nama approver, tanggal) dicatat di riwayat
       sebagai OUTSIDE_APPROVAL ("Approved outside CIMS"); pembuatan dicatat sebagai MIGRATION.
     - Requester tercatat = user civil yang menginput (pemilik data migrasi).
   Error   : 50072 = Input wajib kosong / tidak valid
             50075 = Role user tidak sesuai (civil)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_Lookup_DepartmentsForUser  (pilihan departemen dalam lingkup user, punya ABRV)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Lookup_DepartmentsForUser
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  d.DepartmentID, d.CoCode, d.DeptName, d.ABRV
    FROM    dbo.fn_User_AllowedDepartments(@Username) f
            JOIN home..APP_Departments d ON d.DepartmentID = f.DepartmentID
    WHERE   LTRIM(RTRIM(ISNULL(d.ABRV, ''))) <> ''
    ORDER BY d.CoCode, d.DeptName, d.DepartmentID;
END
GO

/* ---------------------------------------------------------------------
   2. usp_Request_CreateRunning  (civil; FR-03)
      @TargetStatus  : PLANNING | SCHEDULING
      @ExecutionType : wajib bila SCHEDULING (INHOUSE | OUTSOURCE); harus NULL bila PLANNING
      @ApprovalsJson : [{"step":"Kabag","name":"Budi","date":"2026-09-01"}, ...] (opsional, maks. 10 baris)
      Hasil: SELECT Id, RequestNo, Status.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_CreateRunning
    @Username              NVARCHAR(100),
    @DepartmentID          INT,
    @Title                 NVARCHAR(MAX),
    @Category              VARCHAR(10),
    @SubCategoryId         INT,
    @LocationId            INT,
    @PicEmployeeCode       VARCHAR(30)    = NULL,
    @SubDepartmentID       INT            = NULL,
    @BudgetRemarks         VARCHAR(12)    = NULL,
    @TargetCompletionDate  DATE           = NULL,
    @BudgetExpectation     DECIMAL(18, 2) = NULL,
    @Background            NVARCHAR(MAX)  = NULL,
    @Objective             NVARCHAR(MAX)  = NULL,
    @TargetStatus          VARCHAR(20),
    @ExecutionType         VARCHAR(10)    = NULL,
    @BoqTotal              DECIMAL(18, 2) = NULL,
    @VendorId              INT            = NULL,
    @ContractNo            NVARCHAR(50)   = NULL,
    @ContractDate          DATE           = NULL,
    @ContractValue         DECIMAL(18, 2) = NULL,
    @PreparationStartDate  DATE           = NULL,
    @ApprovalsJson         NVARCHAR(MAX)  = NULL,
    @Remarks               NVARCHAR(MAX)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);
    DECLARE @Msg NVARCHAR(2048);

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can enter running projects.', 1;

    /* -- Civil yang menginput (karyawan aktif) = requester data migrasi -- */
    DECLARE @EmpCode VARCHAR(30);
    SELECT  @EmpCode = e.EmployeeCode
    FROM    home..users u
            JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
    WHERE   u.Username = @Username
      AND   (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME());

    IF @EmpCode IS NULL
        THROW 50072, N'Your employee data was not found.', 1;

    /* -- Normalisasi -- */
    SET @Title           = NULLIF(LTRIM(RTRIM(@Title)), N'');
    SET @Category        = UPPER(LTRIM(RTRIM(@Category)));
    SET @PicEmployeeCode = NULLIF(LTRIM(RTRIM(@PicEmployeeCode)), '');
    SET @BudgetRemarks   = NULLIF(UPPER(LTRIM(RTRIM(@BudgetRemarks))), '');
    SET @Background      = NULLIF(LTRIM(RTRIM(@Background)), N'');
    SET @Objective       = NULLIF(LTRIM(RTRIM(@Objective)), N'');
    SET @TargetStatus    = UPPER(LTRIM(RTRIM(@TargetStatus)));
    SET @ExecutionType   = NULLIF(UPPER(LTRIM(RTRIM(@ExecutionType))), '');
    SET @ContractNo      = NULLIF(LTRIM(RTRIM(@ContractNo)), N'');
    SET @Remarks         = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    /* -- Departemen (lingkup user) -> Company + ABRV -- */
    DECLARE @CoCode VARCHAR(10), @Abrv VARCHAR(30);
    SELECT  @CoCode = d.CoCode, @Abrv = LTRIM(RTRIM(REPLACE(d.ABRV, ' - NKM', '')))
    FROM    home..APP_Departments d
    WHERE   d.DepartmentID = @DepartmentID
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = d.DepartmentID);

    IF @CoCode IS NULL
        THROW 50072, N'Please select a valid requesting department.', 1;
    IF ISNULL(@CoCode, '') NOT IN ('ABL', 'NKM')
        THROW 50072, N'The department company must be ABL or NKM.', 1;
    IF ISNULL(@Abrv, '') = ''
        THROW 50072, N'The requesting department has no abbreviation (ABRV); request number cannot be generated.', 1;

    /* -- Wajib -- */
    IF @Title IS NULL                                           THROW 50072, N'Request title is required.', 1;
    IF LEN(@Title) > 200                                        THROW 50072, N'Request title must be at most 200 characters.', 1;
    IF ISNULL(@Category, '') NOT IN ('CAPEX', 'OPEX', 'LVE')    THROW 50072, N'Budget classification is required (CAPEX, OPEX, or LVE).', 1;
    IF @SubCategoryId IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.SubCategory WHERE Id = @SubCategoryId AND Category = @Category AND IsActive = 1)
        THROW 50072, N'Please select a valid sub-category for the budget classification.', 1;
    IF @LocationId IS NULL
       OR NOT EXISTS (SELECT 1 FROM dbo.Location WHERE Id = @LocationId AND CoCode = @CoCode AND IsActive = 1)
        THROW 50072, N'Please select a valid location for the department company.', 1;

    /* -- Opsional, divalidasi bila diisi -- */
    IF @PicEmployeeCode IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM home..app_employees e
                       WHERE e.EmployeeCode = @PicEmployeeCode AND e.DepartmentID = @DepartmentID
                         AND (e.ResignDate IS NULL OR e.ResignDate > SYSDATETIME()))
        THROW 50072, N'PIC must be an active employee of the requesting department.', 1;
    IF @SubDepartmentID IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM home..APP_SubDepartments s
                       WHERE s.SubDepartmentID = @SubDepartmentID AND s.DepartmentID = @DepartmentID AND s.Disabled = 0)
        THROW 50072, N'Cost center is invalid for the requesting department.', 1;
    IF @BudgetRemarks IS NOT NULL AND @BudgetRemarks NOT IN ('BUDGETED', 'UNBUDGETED')
        THROW 50072, N'Budget remarks must be Budgeted or Unbudgeted.', 1;
    IF @BudgetExpectation IS NOT NULL AND @BudgetExpectation < 0
        THROW 50072, N'Budget expectation cannot be negative.', 1;
    IF @BoqTotal IS NOT NULL AND @BoqTotal <= 0
        THROW 50072, N'BOQ total must be greater than 0.', 1;
    IF LEN(@Background) > 2000 OR LEN(@Objective) > 2000
        THROW 50072, N'Each text field must be at most 2000 characters.', 1;
    IF LEN(@Remarks) > 900
        THROW 50072, N'Remarks must be at most 900 characters.', 1;

    /* -- Status tujuan + cara eksekusi -- */
    IF ISNULL(@TargetStatus, '') NOT IN ('PLANNING', 'SCHEDULING')
        THROW 50072, N'Current status must be Planning or Scheduling.', 1;

    IF @TargetStatus = 'PLANNING' AND @ExecutionType IS NOT NULL
        THROW 50072, N'The execution method is chosen later for projects in planning.', 1;

    DECLARE @PlanCost DECIMAL(18, 2) = NULL, @PrepStart DATETIME2(3) = NULL;

    IF @TargetStatus = 'SCHEDULING'
    BEGIN
        IF ISNULL(@ExecutionType, '') NOT IN ('INHOUSE', 'OUTSOURCE')
            THROW 50072, N'Please choose in-house or outsource for projects in scheduling.', 1;

        IF @ExecutionType = 'INHOUSE'
        BEGIN
            IF @BoqTotal IS NULL
                THROW 50072, N'BOQ total is required for in-house execution (plan cost).', 1;
            SET @PlanCost = @BoqTotal;
            SET @PrepStart = CAST(ISNULL(@PreparationStartDate, @Today) AS DATETIME2(3));
        END
        ELSE
        BEGIN
            DECLARE @Missing NVARCHAR(500) =
                  CASE WHEN @VendorId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Vendor v WHERE v.Id = @VendorId AND v.IsActive = 1)
                       THEN N', Vendor (active)' ELSE N'' END
                + CASE WHEN @ContractNo IS NULL THEN N', Contract number' ELSE N'' END
                + CASE WHEN @ContractDate IS NULL THEN N', Contract date' ELSE N'' END
                + CASE WHEN @ContractValue IS NULL OR @ContractValue <= 0 THEN N', Contract value (greater than 0)' ELSE N'' END;
            IF @Missing <> N''
            BEGIN
                SET @Msg = N'Please complete the contract: ' + STUFF(@Missing, 1, 2, N'') + N'.';
                THROW 50072, @Msg, 1;
            END
            IF LEN(@ContractNo) > 50
                THROW 50072, N'Contract number must be at most 50 characters.', 1;
            IF @ContractDate > @Today
                THROW 50072, N'Contract date cannot be in the future.', 1;
            SET @PlanCost = @ContractValue;
            SET @PrepStart = CAST(ISNULL(@PreparationStartDate, @ContractDate) AS DATETIME2(3));
        END

        IF @PreparationStartDate IS NOT NULL AND @PreparationStartDate > @Today
            THROW 50072, N'Preparation start date cannot be in the future.', 1;
    END
    ELSE IF @VendorId IS NOT NULL OR @ContractNo IS NOT NULL OR @ContractDate IS NOT NULL OR @ContractValue IS NOT NULL
        THROW 50072, N'Contract data can only be entered for outsourced projects in scheduling.', 1;

    /* -- Approval di luar sistem (BR-76) -- */
    IF ISJSON(ISNULL(@ApprovalsJson, N'[]')) = 0
        THROW 50072, N'Outside approval data is invalid.', 1;

    DECLARE @Approvals TABLE (Seq INT PRIMARY KEY, Step NVARCHAR(200) NULL, Name NVARCHAR(200) NULL, ApprovedOn DATE NULL);

    INSERT INTO @Approvals (Seq, Step, Name, ApprovedOn)
    SELECT  CAST(j.[key] AS INT) + 1, NULLIF(LTRIM(RTRIM(x.step)), N''), NULLIF(LTRIM(RTRIM(x.name)), N''), x.[date]
    FROM    OPENJSON(ISNULL(@ApprovalsJson, N'[]')) j
            CROSS APPLY OPENJSON(j.[value]) WITH (step NVARCHAR(200) '$.step', name NVARCHAR(200) '$.name', [date] DATE '$.date') x;

    DELETE FROM @Approvals WHERE Step IS NULL AND Name IS NULL AND ApprovedOn IS NULL;   -- baris kosong

    IF (SELECT COUNT(*) FROM @Approvals) > 10
        THROW 50072, N'At most 10 outside approval rows are allowed.', 1;

    SELECT TOP (1) @Msg = N'Outside approval row ' + CAST(a.Seq AS NVARCHAR(10)) + N': ' +
           CASE WHEN a.Step IS NULL AND a.Name IS NULL THEN N'step/role or approver name is required.'
                WHEN LEN(a.Step) > 100 OR LEN(a.Name) > 100 THEN N'step/role and name must be at most 100 characters.'
                ELSE N'date cannot be in the future.' END
    FROM   @Approvals a
    WHERE  (a.Step IS NULL AND a.Name IS NULL) OR LEN(a.Step) > 100 OR LEN(a.Name) > 100 OR a.ApprovedOn > @Today
    ORDER BY a.Seq;

    IF @Msg IS NOT NULL
        THROW 50072, @Msg, 1;

    /* -- Simpan -- */
    DECLARE @Id INT, @RequestNo VARCHAR(40);
    DECLARE @Yr SMALLINT = YEAR(@Now), @Mon TINYINT = MONTH(@Now), @Next INT;

    BEGIN TRANSACTION;

    -- Nomor request: format sama, bulan/tahun = bulan input (BR-41, BR-77)
    UPDATE dbo.RequestNoSequence WITH (UPDLOCK, HOLDLOCK)
    SET    @Next = LastNo = LastNo + 1,
           UpdatedAt = @Now
    WHERE  CoCode = @CoCode AND Abrv = @Abrv AND Category = @Category AND SeqYear = @Yr AND SeqMonth = @Mon;

    IF @@ROWCOUNT = 0
    BEGIN
        SET @Next = 1;
        INSERT INTO dbo.RequestNoSequence (CoCode, Abrv, Category, SeqYear, SeqMonth, LastNo)
        VALUES (@CoCode, @Abrv, @Category, @Yr, @Mon, @Next);
    END

    SET @RequestNo = CASE WHEN @CoCode = 'NKM' THEN 'NKM-' ELSE '' END
                   + @Abrv + '-'
                   + CASE @Category WHEN 'CAPEX' THEN 'CPX' WHEN 'OPEX' THEN 'OPX' ELSE 'LVE' END + '-'
                   + RIGHT('0' + CAST(@Mon AS VARCHAR(2)), 2) + '-'
                   + RIGHT(CAST(@Yr AS VARCHAR(4)), 2) + '-'
                   + RIGHT('00' + CAST(@Next AS VARCHAR(10)), CASE WHEN @Next > 999 THEN LEN(CAST(@Next AS VARCHAR(10))) ELSE 3 END);

    INSERT INTO dbo.ProjectRequest
        (CoCode, DepartmentID, RequestNo, Status, RequesterUsername, RequesterEmployeeCode, PicEmployeeCode,
         Title, Category, SubCategoryId, BudgetRemarks, SubDepartmentID, LocationId, TargetCompletionDate,
         BudgetExpectation, Background, Objective, BoqTotal, ExecutionType, PlanCost, PreparationStartAt,
         IsMigrated, SubmittedAt, CreatedAt, CreatedBy)
    VALUES
        (@CoCode, @DepartmentID, @RequestNo, @TargetStatus, @Username, @EmpCode, @PicEmployeeCode,
         @Title, @Category, @SubCategoryId, @BudgetRemarks, @SubDepartmentID, @LocationId, @TargetCompletionDate,
         @BudgetExpectation, @Background, @Objective, @BoqTotal, @ExecutionType, @PlanCost, @PrepStart,
         1, @Now, @Now, @Username);

    SET @Id = CAST(SCOPE_IDENTITY() AS INT);

    -- Nomor tercatat (pencarian nomor; alasan SUBMIT = nomor pertama)
    INSERT INTO dbo.RequestNoHistory (RequestId, RequestNo, Reason, CreatedBy)
    VALUES (@Id, @RequestNo, 'SUBMIT', @Username);

    IF @ExecutionType = 'OUTSOURCE'
        INSERT INTO dbo.ProjectContract (RequestId, VendorId, ContractNo, ContractDate, ContractValue, Remarks, CreatedAt, CreatedBy)
        VALUES (@Id, @VendorId, @ContractNo, @ContractDate, @ContractValue, N'Running project (data migration)', @Now, @Username);

    -- Riwayat: pembuatan data migrasi, lalu approval di luar sistem (BR-76)
    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'MIGRATION', NULL, @TargetStatus,
            LEFT(N'Running project entered (data migration)'
                 + CASE WHEN @ExecutionType IS NULL THEN N'' ELSE N' · ' + CASE @ExecutionType WHEN 'INHOUSE' THEN N'In-house' ELSE N'Outsource' END END
                 + ISNULL(N' · ' + @Remarks, N''), 1000),
            @Username, @Now);

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    SELECT  @Id, 'OUTSIDE_APPROVAL', NULL, NULL,
            LEFT(N'Approved outside CIMS'
                 + ISNULL(N' · ' + a.Step, N'')
                 + ISNULL(N' · ' + a.Name, N'')
                 + ISNULL(N' · ' + FORMAT(a.ApprovedOn, N'dd MMM yyyy', 'en-US'), N''), 1000),
            @Username, @Now
    FROM    @Approvals a
    ORDER BY a.Seq;

    COMMIT TRANSACTION;

    SELECT @Id AS Id, @RequestNo AS RequestNo, @TargetStatus AS Status;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: Request.sql dijalankan ulang (IsMigrated), lalu file ini.

   DECLARE @Civil NVARCHAR(100) = N'users1', @Other NVARCHAR(100) = N'240701',
           @Dept INT = 19, @Sub INT = 1, @Loc INT = 35,
           @Vendor INT = (SELECT TOP (1) Id FROM dbo.Vendor WHERE IsActive = 1);

   -- 0) Pilihan departemen untuk civil (semua ABL + NKM yang punya ABRV)
   EXEC dbo.usp_Lookup_DepartmentsForUser @Username = @Civil;

   -- 1) Bukan civil -> 50075; SCHEDULING tanpa cara eksekusi -> 50072; in-house tanpa BOQ -> 50072; outsource tanpa kontrak -> 50072
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Other, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'PLANNING';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072 (execution)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING', @ExecutionType = 'INHOUSE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072 (BOQ)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING', @ExecutionType = 'OUTSOURCE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1d expect 50072 (contract)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'X', @Category = 'CAPEX',
        @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'PLANNING',
        @ApprovalsJson = N'[{"step":"Kabag","name":"Budi","date":"2099-01-01"}]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1e expect 50072 (approval date)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) PLANNING + 2 approval di luar sistem -> nomor bulan ini, IsMigrated = 1, riwayat MIGRATION + 2x OUTSIDE_APPROVAL
   EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'Running project - planning',
        @Category = 'CAPEX', @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'PLANNING', @BoqTotal = 8000000,
        @ApprovalsJson = N'[{"step":"Kabag","name":"Budi","date":"2026-09-01"},{"step":"GM","name":"","date":"2026-09-10"}]';

   -- 3) SCHEDULING in-house -> PlanCost = BOQ; lanjut isi schedule/handover lewat T4-2 untuk project yang sudah berjalan
   EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'Running project - in-house',
        @Category = 'CAPEX', @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING',
        @ExecutionType = 'INHOUSE', @BoqTotal = 10000000, @PreparationStartDate = '2026-10-01';

   -- 4) SCHEDULING outsource -> ProjectContract terisi, PlanCost = nilai kontrak, Preparation = tanggal kontrak
   EXEC dbo.usp_Request_CreateRunning @Username = @Civil, @DepartmentID = @Dept, @Title = N'Running project - outsource',
        @Category = 'CAPEX', @SubCategoryId = @Sub, @LocationId = @Loc, @TargetStatus = 'SCHEDULING',
        @ExecutionType = 'OUTSOURCE', @VendorId = @Vendor, @ContractNo = N'SPK/OLD/001', @ContractDate = '2026-10-15', @ContractValue = 25000000;

   SELECT TOP (3) Id, RequestNo, Status, IsMigrated, ExecutionType, BoqTotal, PlanCost, PreparationStartAt
   FROM dbo.ProjectRequest WHERE IsMigrated = 1 ORDER BY Id DESC;
   SELECT h.RequestId, h.Action, h.ToStatus, h.Remarks FROM dbo.ApprovalHistory h
   WHERE h.RequestId IN (SELECT TOP (3) Id FROM dbo.ProjectRequest WHERE IsMigrated = 1 ORDER BY Id DESC) ORDER BY h.Id;
   EXEC dbo.usp_Task_GetList @Username = @Civil, @TaskType = 'SCHEDULING';             -- 2 project baru muncul
   ===================================================================== */
