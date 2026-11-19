/* =====================================================================
   RequestExecution.sql  -  In-house / Outsource, TOR, kontrak Purchasing (T4-1; PRD 3.3 langkah 1-2,
                            BR-11, BR-12, BR-15, ST-08, ST-09, ST-10, RL-06)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH Vendor.sql dan RequestDocPrep.sql
             (dan jalankan ulang Request.sql: kolom ExecutionType/PlanCost/PreparationStartAt, aturan lampiran,
             lingkup purchasing; serta Task.sql: tugas PROCUREMENT untuk purchasing).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Alur    :
     PLANNING (civil)
       - In-house  -> SCHEDULING. Plan cost = BOQ total (BR-12). Awal periode Preparation = selesainya
                      management approval (BR-15, in-house).
       - Outsource -> PROCUREMENT (ST-09). Wajib lampiran TOR (jenis tahap PROCUREMENT) (BR-11).
     PROCUREMENT (purchasing)
       - Simpan kontrak: vendor aktif, nomor, tanggal, nilai > 0 (boleh disimpan berkali-kali).
       - Selesaikan procurement -> SCHEDULING. Wajib data kontrak + lampiran kontrak (jenis tahap CONTRACT).
         Plan cost = nilai kontrak (BR-12). Awal periode Preparation = saat ini (kontrak diinput; BR-15).
       - Kembalikan TOR ke Civil (Keputusan 14-11-2026) -> PLANNING, alasan wajib; cara eksekusi dikosongkan
         sehingga Civil bisa memperbaiki TOR atau memilih In-house.
     Semua aksi tercatat di riwayat: INHOUSE, SEND_TOR, RETURN_TOR, CONTRACT.
   Error   : 50072 = Input wajib kosong / tidak valid / data belum lengkap
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai (civil / purchasing)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.ProjectContract  (satu kontrak per request outsource; BR-11)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectContract', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectContract
    (
        Id             INT IDENTITY(1,1) NOT NULL,
        RequestId      INT            NOT NULL,
        VendorId       INT            NOT NULL,
        ContractNo     NVARCHAR(50)   NOT NULL,
        ContractDate   DATE           NOT NULL,
        ContractValue  DECIMAL(18, 2) NOT NULL,
        Remarks        NVARCHAR(1000) NULL,
        CreatedAt      DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectContract_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy      NVARCHAR(100)  NOT NULL,
        UpdatedAt      DATETIME2(3)   NULL,
        UpdatedBy      NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectContract PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectContract_Request UNIQUE (RequestId),
        CONSTRAINT FK_ProjectContract_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_ProjectContract_Vendor  FOREIGN KEY (VendorId)  REFERENCES dbo.Vendor (Id),
        CONSTRAINT CK_ProjectContract_Value   CHECK (ContractValue > 0)
    );
END
GO

/* ---------------------------------------------------------------------
   2. usp_Request_ChooseExecution  (civil, PLANNING; @ExecutionType = INHOUSE | OUTSOURCE)
      Hasil: SELECT Status (SCHEDULING / PROCUREMENT).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_ChooseExecution
    @Id             INT,
    @Username       NVARCHAR(100),
    @ExecutionType  VARCHAR(10),
    @Remarks        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @ExecutionType = UPPER(LTRIM(RTRIM(@ExecutionType)));
    SET @Remarks       = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF ISNULL(@ExecutionType, '') NOT IN ('INHOUSE', 'OUTSOURCE')
        THROW 50072, N'Please choose in-house or outsource.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can choose the execution method.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @BoqTotal DECIMAL(18, 2);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @BoqTotal = r.BoqTotal
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'PLANNING'
        THROW 50074, N'The execution method can only be chosen during planning.', 1;

    DECLARE @NewStatus VARCHAR(20);

    IF @ExecutionType = 'INHOUSE'
    BEGIN
        IF @BoqTotal IS NULL OR @BoqTotal <= 0
            THROW 50072, N'BOQ total is required for in-house execution.', 1;

        -- Awal Preparation in-house = selesainya management approval (masuk PLANNING terakhir; BR-15)
        DECLARE @MgmtDone DATETIME2(3) =
        (
            SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h
            WHERE  h.RequestId = @Id AND h.ToStatus = 'PLANNING' AND h.FromStatus = 'MGMT_APPROVAL'
        );

        SET @NewStatus = 'SCHEDULING';

        UPDATE dbo.ProjectRequest
        SET    Status = @NewStatus, ExecutionType = 'INHOUSE', PlanCost = @BoqTotal,
               PreparationStartAt = ISNULL(@MgmtDone, @Now), UpdatedAt = @Now, UpdatedBy = @Username
        WHERE  Id = @Id;
    END
    ELSE
    BEGIN
        -- BR-11: outsource wajib TOR (minimal satu lampiran jenis tahap PROCUREMENT)
        IF NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a JOIN dbo.AttachmentType t ON t.Id = a.AttachmentTypeId
                       WHERE a.RequestId = @Id AND a.IsActive = 1 AND t.Stage = 'PROCUREMENT')
            THROW 50072, N'Please upload the TOR before sending to Purchasing.', 1;

        SET @NewStatus = 'PROCUREMENT';

        UPDATE dbo.ProjectRequest
        SET    Status = @NewStatus, ExecutionType = 'OUTSOURCE', PlanCost = NULL, PreparationStartAt = NULL,
               UpdatedAt = @Now, UpdatedBy = @Username
        WHERE  Id = @Id;
    END

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, CASE @ExecutionType WHEN 'INHOUSE' THEN 'INHOUSE' ELSE 'SEND_TOR' END, @Status, @NewStatus, @Remarks, @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewStatus AS Status;
END
GO

/* ---------------------------------------------------------------------
   3. usp_Request_SaveContract  (purchasing, PROCUREMENT; simpan / ubah data kontrak)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveContract
    @Id             INT,
    @Username       NVARCHAR(100),
    @VendorId       INT,
    @ContractNo     NVARCHAR(50),
    @ContractDate   DATE,
    @ContractValue  DECIMAL(18, 2),
    @Remarks        NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @ContractNo = NULLIF(LTRIM(RTRIM(@ContractNo)), N'');
    SET @Remarks    = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'purchasing')
        THROW 50075, N'Only Purchasing can enter the contract.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'PROCUREMENT'
        THROW 50074, N'The contract can only be entered during procurement.', 1;

    -- Validasi isi (setelah cek status agar pesan status lebih dulu)
    DECLARE @Missing NVARCHAR(500) =
          CASE WHEN @VendorId IS NULL OR NOT EXISTS (SELECT 1 FROM dbo.Vendor v WHERE v.Id = @VendorId AND v.IsActive = 1)
               THEN N', Vendor (active)' ELSE N'' END
        + CASE WHEN @ContractNo IS NULL THEN N', Contract number' ELSE N'' END
        + CASE WHEN @ContractDate IS NULL THEN N', Contract date' ELSE N'' END
        + CASE WHEN @ContractValue IS NULL OR @ContractValue <= 0 THEN N', Contract value (greater than 0)' ELSE N'' END;

    IF @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(2048) = N'Please complete: ' + STUFF(@Missing, 1, 2, N'') + N'.';
        THROW 50072, @Msg, 1;
    END
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;

    IF EXISTS (SELECT 1 FROM dbo.ProjectContract WHERE RequestId = @Id)
        UPDATE dbo.ProjectContract
        SET    VendorId = @VendorId, ContractNo = @ContractNo, ContractDate = @ContractDate,
               ContractValue = @ContractValue, Remarks = @Remarks, UpdatedAt = @Now, UpdatedBy = @Username
        WHERE  RequestId = @Id;
    ELSE
        INSERT INTO dbo.ProjectContract (RequestId, VendorId, ContractNo, ContractDate, ContractValue, Remarks, CreatedAt, CreatedBy)
        VALUES (@Id, @VendorId, @ContractNo, @ContractDate, @ContractValue, @Remarks, @Now, @Username);

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Request_CompleteProcurement  (purchasing, PROCUREMENT -> SCHEDULING; BR-11, BR-12, BR-15)
      Hasil: SELECT Status.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_CompleteProcurement
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'purchasing')
        THROW 50075, N'Only Purchasing can complete procurement.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'PROCUREMENT'
        THROW 50074, N'This request is not in procurement.', 1;

    DECLARE @Value DECIMAL(18, 2), @ContractNo NVARCHAR(50), @VendorName NVARCHAR(150);

    SELECT  @Value = c.ContractValue, @ContractNo = c.ContractNo, @VendorName = v.Name
    FROM    dbo.ProjectContract c JOIN dbo.Vendor v ON v.Id = c.VendorId
    WHERE   c.RequestId = @Id;

    DECLARE @Missing NVARCHAR(500) =
          CASE WHEN @Value IS NULL THEN N', Contract data' ELSE N'' END
        + CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a JOIN dbo.AttachmentType t ON t.Id = a.AttachmentTypeId
                                WHERE a.RequestId = @Id AND a.IsActive = 1 AND t.Stage = 'CONTRACT')
               THEN N', Contract attachment' ELSE N'' END;

    IF @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(2048) = N'Please complete before finishing procurement: ' + STUFF(@Missing, 1, 2, N'') + N'.';
        THROW 50072, @Msg, 1;
    END

    UPDATE dbo.ProjectRequest
    SET    Status = 'SCHEDULING', PlanCost = @Value, PreparationStartAt = @Now, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'CONTRACT', @Status, 'SCHEDULING',
            LEFT(N'Contract ' + @ContractNo + N' · ' + @VendorName + N' · IDR ' + FORMAT(@Value, N'#,0.##', 'en-US'), 1000),
            @Username, @Now);

    COMMIT TRANSACTION;

    SELECT CAST('SCHEDULING' AS VARCHAR(20)) AS Status;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Request_ReturnTor  (purchasing, PROCUREMENT -> PLANNING; alasan wajib; Keputusan 14-11-2026)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_ReturnTor
    @Id        INT,
    @Username  NVARCHAR(100),
    @Reason    NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');

    IF @Reason IS NULL
        THROW 50072, N'Reason is required.', 1;
    IF LEN(@Reason) > 1000
        THROW 50072, N'Reason must be at most 1000 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'purchasing')
        THROW 50075, N'Only Purchasing can return the TOR.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'PROCUREMENT'
        THROW 50074, N'This request is not in procurement.', 1;

    UPDATE dbo.ProjectRequest
    SET    Status = 'PLANNING', ExecutionType = NULL, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'RETURN_TOR', @Status, 'PLANNING', @Reason, @Username, @Now);

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Request_GetContract  (Details; 0 baris = belum ada kontrak)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetContract
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  c.Id, c.RequestId, c.VendorId, v.Code AS VendorCode, v.Name AS VendorName,
            c.ContractNo, c.ContractDate, c.ContractValue, c.Remarks,
            c.CreatedAt, c.CreatedBy, c.UpdatedAt, c.UpdatedBy
    FROM    dbo.ProjectContract c
            JOIN dbo.Vendor v         ON v.Id = c.VendorId
            JOIN dbo.ProjectRequest r ON r.Id = c.RequestId
    WHERE   c.RequestId = @RequestId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID)
      AND   (r.ExecutionType = 'OUTSOURCE' OR NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username)));
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: Request.sql, Task.sql, Vendor.sql dijalankan; ada request PLANNING (mis. Id 3 setelah
   management approval) dan request PLANNING lain untuk jalur outsource; user civil dan purchasing.

   DECLARE @InHouse INT = 3, @Out INT = <id request PLANNING lain>,
           @Civil NVARCHAR(100) = N'<user civil>', @Purch NVARCHAR(100) = N'<user purchasing>';

   -- 1) Validasi: bukan civil -> 50075; outsource tanpa TOR -> 50072
   BEGIN TRY EXEC dbo.usp_Request_ChooseExecution @Id = @InHouse, @Username = @Purch, @ExecutionType = 'INHOUSE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_ChooseExecution @Id = @Out, @Username = @Civil, @ExecutionType = 'OUTSOURCE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072 (TOR)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) In-house -> SCHEDULING; PlanCost = BoqTotal; PreparationStartAt = waktu management approval terakhir
   EXEC dbo.usp_Request_ChooseExecution @Id = @InHouse, @Username = @Civil, @ExecutionType = 'INHOUSE';
   SELECT Id, Status, ExecutionType, BoqTotal, PlanCost, PreparationStartAt FROM dbo.ProjectRequest WHERE Id = @InHouse;

   -- 3) Purchasing hanya melihat outsource (RL-06): @InHouse tidak muncul / GetById 0 baris
   EXEC dbo.usp_Request_GetById @Id = @InHouse, @Username = @Purch;
   SELECT * FROM dbo.fn_User_OutsourceOnly(@Purch);                            -- 1 baris bila hanya purchasing

   -- 4) Upload TOR (lewat aplikasi sebagai civil, Tahap C) lalu:
   --EXEC dbo.usp_Request_ChooseExecution @Id = @Out, @Username = @Civil, @ExecutionType = 'OUTSOURCE', @Remarks = N'TOR attached';
   --SELECT * FROM dbo.fn_User_Tasks(@Purch) WHERE RequestId = @Out;           -- PROCUREMENT

   -- 5) Purchasing: kembalikan TOR (alasan wajib) -> PLANNING, ExecutionType NULL
   --BEGIN TRY EXEC dbo.usp_Request_ReturnTor @Id = @Out, @Username = @Purch, @Reason = N' ';
   --END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '5 expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   --EXEC dbo.usp_Request_ReturnTor @Id = @Out, @Username = @Purch, @Reason = N'Scope of work is unclear';

   -- 6) Setelah dikirim ulang: simpan kontrak (vendor dari Vendor.sql), selesaikan tanpa lampiran kontrak -> 50072,
   --    upload lampiran kontrak (aplikasi), selesaikan -> SCHEDULING, PlanCost = nilai kontrak
   --DECLARE @Vendor INT = (SELECT TOP (1) Id FROM dbo.Vendor WHERE IsActive = 1);
   --EXEC dbo.usp_Request_SaveContract @Id = @Out, @Username = @Purch, @VendorId = @Vendor,
   --     @ContractNo = N'SPK/001/XI/2026', @ContractDate = '2026-11-14', @ContractValue = 4600000;
   --EXEC dbo.usp_Request_GetContract @RequestId = @Out, @Username = @Civil;
   --BEGIN TRY EXEC dbo.usp_Request_CompleteProcurement @Id = @Out, @Username = @Purch;
   --END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '6 expect 50072 (attachment)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   ===================================================================== */
