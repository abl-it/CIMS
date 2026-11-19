/* =====================================================================
   RequestDocPrep.sql  -  Document Preparation + kirim ke management (T3-2; PRD 3.1 langkah 5-6,
                          BR-05, BR-06, BR-07, BR-12, BR-37, BR-52, BR-53, ST-05, ST-06)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestFeasibility.sql
             (dan jalankan ulang Request.sql: kolom BoqTotal + lampiran DOCUMENT oleh Civil; serta Task.sql:
             tugas DOC_PREPARATION untuk Civil).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Hanya role civil (matriks 5.2: BOQ, Drawing = C/A civil), status DOC_PREPARATION.
     - Lampiran BOQ dan Drawing = jenis lampiran tahap DOCUMENT (AttachmentType); wajib per kategori diambil
       dari tabel (BOQ semua kategori, Drawing CAPEX; BR-05), bukan hardcode.
     - BOQ total (IDR) wajib > 0 sebelum dikirim (Keputusan 13-11-2026; dasar plan cost in-house BR-12).
       Setiap perubahan dicatat di riwayat (action BOQ_TOTAL).
     - Kirim ke management (BR-53): langkah titik MGMT disusun dari dbo.WorkflowStep SAAT INI (kategori saat ini,
       mis. Director ikut bila sudah menjadi CAPEX) sebagai ronde baru; sisa langkah MGMT ronde lama di-VOID.
       Tanpa langkah MGMT yang cocok -> langsung PLANNING (ST-08). Approval MGMT diproses di T3-3.
   Error   : 50072 = Input wajib kosong / tidak valid / data belum lengkap
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = User bukan Civil
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_Request_SetBoqTotal  (BR-05, BR-12)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SetBoqTotal
    @Id        INT,
    @Username  NVARCHAR(100),
    @BoqTotal  DECIMAL(18, 2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @BoqTotal IS NULL OR @BoqTotal <= 0
        THROW 50072, N'BOQ total must be greater than 0.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can set the BOQ total.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @Old DECIMAL(18, 2);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @Old = r.BoqTotal
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'DOC_PREPARATION'
        THROW 50074, N'The BOQ total can only be changed during document preparation.', 1;

    IF @Old IS NULL OR @Old <> @BoqTotal
    BEGIN
        UPDATE dbo.ProjectRequest
        SET    BoqTotal = @BoqTotal, UpdatedAt = @Now, UpdatedBy = @Username
        WHERE  Id = @Id;

        -- Riwayat: status tidak berubah; catatan memuat nilai lama -> baru
        INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
        VALUES (@Id, 'BOQ_TOTAL', @Status, @Status,
                N'BOQ total: ' + ISNULL(N'IDR ' + FORMAT(@Old, N'#,0.##', 'en-US') + N' → ', N'')
                               + N'IDR ' + FORMAT(@BoqTotal, N'#,0.##', 'en-US'),
                @Username, @Now);
    END

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   2. usp_Request_SendToManagement  (BR-06, BR-07, BR-37, BR-52, BR-53)
      Hasil: SELECT Status (MGMT_APPROVAL, atau PLANNING bila tidak ada langkah MGMT).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SendToManagement
    @Id        INT,
    @Username  NVARCHAR(100),
    @Remarks   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can send a request to management.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @CoCode VARCHAR(10), @DeptId INT, @Category VARCHAR(10), @BoqTotal DECIMAL(18, 2);

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @CoCode = r.CoCode, @DeptId = r.DepartmentID, @Category = r.Category,
            @BoqTotal = r.BoqTotal
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status <> 'DOC_PREPARATION'
        THROW 50074, N'Only requests in document preparation can be sent to management.', 1;

    /* -- Kelengkapan: BOQ total + lampiran wajib tahap DOCUMENT untuk kategori saat ini (BR-05) -- */
    DECLARE @Missing NVARCHAR(MAX) = CASE WHEN @BoqTotal IS NULL OR @BoqTotal <= 0 THEN N', BOQ total' ELSE N'' END;

    SELECT @Missing += N', ' + t.Name + N' attachment'
    FROM   dbo.AttachmentType t
    WHERE  t.Stage = 'DOCUMENT' AND t.IsActive = 1
      AND  1 = CASE @Category WHEN 'CAPEX' THEN CAST(t.IsMandatoryCapex AS INT)
                              WHEN 'OPEX'  THEN CAST(t.IsMandatoryOpex  AS INT)
                              WHEN 'LVE'   THEN CAST(t.IsMandatoryLve   AS INT) END
      AND  NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a
                       WHERE a.RequestId = @Id AND a.AttachmentTypeId = t.Id AND a.IsActive = 1)
    ORDER BY t.Name;

    IF @Missing <> N''
    BEGIN
        DECLARE @Msg NVARCHAR(2048) = LEFT(N'Please complete before sending to management: ' + STUFF(@Missing, 1, 2, N'') + N'.', 2048);
        THROW 50072, @Msg, 1;
    END

    /* -- Snapshot langkah MGMT: ronde baru dari tabel saat ini (BR-37, BR-53) -- */
    DECLARE @Round INT = ISNULL((SELECT MAX(Round) FROM dbo.ApprovalStep WHERE RequestId = @Id AND [Point] = 'MGMT'), 0) + 1;

    UPDATE dbo.ApprovalStep SET Status = 'VOID'
    WHERE  RequestId = @Id AND [Point] = 'MGMT' AND Status = 'PENDING';

    INSERT INTO dbo.ApprovalStep
        (RequestId, [Point], Round, StepOrder, WorkflowStepId, RoleCode, Scope, DepartmentGroupCode, ReviseTo, AllowReject)
    SELECT  @Id, 'MGMT', @Round, w.StepOrder, w.Id, w.RoleCode, w.Scope, w.DepartmentGroupCode, w.ReviseTo, w.AllowReject
    FROM    dbo.WorkflowStep w
    WHERE   w.CoCode = @CoCode
      AND   w.[Point] = 'MGMT'
      AND   w.IsActive = 1
      AND   (w.Category IS NULL OR w.Category = @Category)
      AND   (
                w.DepartmentGroupCode IS NULL
                OR EXISTS (SELECT 1
                           FROM   dbo.DepartmentGroup g
                                  JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                           WHERE  g.CoCode = w.CoCode AND g.GroupCode = w.DepartmentGroupCode AND g.IsActive = 1
                             AND  m.DepartmentID = @DeptId)
            );

    DECLARE @StepCount INT = @@ROWCOUNT;
    DECLARE @NewStatus VARCHAR(20) = 'PLANNING';

    IF @StepCount > 0
    BEGIN
        SET @NewStatus = 'MGMT_APPROVAL';
        UPDATE dbo.ApprovalStep SET StartedAt = @Now
        WHERE  RequestId = @Id AND [Point] = 'MGMT' AND Round = @Round
          AND  StepOrder = (SELECT MIN(StepOrder) FROM dbo.ApprovalStep
                            WHERE RequestId = @Id AND [Point] = 'MGMT' AND Round = @Round);
    END

    UPDATE dbo.ProjectRequest
    SET    Status = @NewStatus, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'SEND_TO_MGMT', @Status, @NewStatus, @Remarks, @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewStatus AS Status;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel hanya hidup dalam satu eksekusi: jalankan blok bersama DECLARE-nya.
   Kasus yang diharapkan error dibungkus TRY/CATCH (baris TestCase / ErrNo / ErrMsg).
   Prasyarat: Request.sql dan Task.sql sudah dijalankan ulang; ada request DOC_PREPARATION
   (mis. Id 3 setelah Feasible di T3-1, CAPEX) dan user civil.

   DECLARE @Id INT = 3, @Civil NVARCHAR(100) = N'users1', @Bukan NVARCHAR(100) = N'marisi';

   -- 0) Kolom baru + tugas Civil DOC_PREPARATION
   SELECT Id, RequestNo, Category, Status, BoqTotal FROM dbo.ProjectRequest WHERE Id = @Id;
   SELECT * FROM dbo.fn_User_Tasks(@Civil) WHERE RequestId = @Id;                          -- TaskType DOC_PREPARATION
   EXEC dbo.usp_Lookup_AttachmentTypesByStage @Stage = 'DOCUMENT';                         -- BOQ, Drawing, ...

   -- 1) Bukan civil -> 50075; BOQ total 0 -> 50072; kirim tanpa BOQ/Drawing -> 50072 (menyebut yang kurang)
   BEGIN TRY EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Bukan, @BoqTotal = 1000;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 0;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_SendToManagement @Id = @Id, @Username = @Civil;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072 (BOQ total, BOQ, Drawing)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) Isi BOQ total dua kali -> riwayat BOQ_TOTAL (kedua: lama -> baru); nilai sama -> tidak ada riwayat baru
   EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 4500000;
   EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 4750000;
   EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 4750000;
   SELECT TOP (3) Action, Remarks, ActionAt FROM dbo.ApprovalHistory WHERE RequestId = @Id ORDER BY Id DESC;

   -- 3) Upload BOQ (dan Drawing untuk CAPEX) lewat aplikasi sebagai civil (Tahap C), lalu:
   --    kirim -> MGMT_APPROVAL; langkah MGMT ronde baru: ABL OPEX = GM, ABL CAPEX = GM + Director; NKM = Director
   --EXEC dbo.usp_Request_SendToManagement @Id = @Id, @Username = @Civil, @Remarks = N'BOQ and drawing attached';
   --EXEC dbo.usp_Request_GetApprovalSteps @RequestId = @Id, @Username = @Civil;          -- MGMT step 1 IsCurrent
   --SELECT * FROM dbo.fn_User_Tasks(N'<user gm>') WHERE RequestId = @Id;                 -- APPROVAL (diproses di T3-3)

   -- 4) Setelah dikirim: ubah BOQ total / kirim ulang -> 50074
   --BEGIN TRY EXEC dbo.usp_Request_SetBoqTotal @Id = @Id, @Username = @Civil, @BoqTotal = 1;
   --END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4 expect 50074' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   ===================================================================== */
