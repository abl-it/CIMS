/* =====================================================================
   RequestApproval.sql  -  Approval request sebelum Civil (T2-3; PRD 3.9, 5.2, BR-03, BR-08, BR-10, BR-24,
                           BR-28, BR-30, BR-39, BR-50, BR-63, ST-02, ST-03, ST-04, ST-15)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestSubmit.sql.
   Waktu   : Local time (SYSDATETIME / GETDATE), bukan UTC.
   Catatan :
     - Hak aksi per langkah dari snapshot dbo.ApprovalStep (BR-37), bukan hardcode role:
         * user memegang RoleCode langkah (home..users.[Role], dipisah ';'), karyawan belum resign;
         * CoCode karyawan = CoCode request (BR-63);
         * lingkup: DEPT = ABRV departemen karyawan sama dengan ABRV departemen request (BR-24);
                    GROUP = departemen request anggota grup langkah (mis. MILL) pada Company request (BR-50);
                    PLANT = cukup Company sama;
         * bukan requester request tersebut (BR-30).
     - Langkah aktif = PENDING + StartedAt terisi pada ronde terakhir titiknya, dan status request sesuai
       titik (REQUEST -> WAITING_APPROVAL, MGMT -> MGMT_APPROVAL, BAPP -> BAPP_REVIEW).
     - BR-39 (yang pertama berlaku): baris request dikunci (UPDLOCK) dan aksi wajib menyebut @StepId yang
       dilihat user; bila langkah itu sudah diproses orang lain -> 50074.
     - Titik REQUEST (T2-3) dan MGMT (T3-3: GM, lalu Director untuk CAPEX; NKM: Director). BAPP menyusul (T5).
     - Aksi:
         APPROVE -> langkah berikut aktif; tanpa langkah berikut -> REQUEST: FEASIBILITY (ST-04),
                    MGMT: PLANNING (ST-08)
         REVISE  -> sesuai ReviseTo langkah: REQUESTER -> RETURNED (ST-03); CIVIL -> FEASIBILITY (BR-06, BR-07;
                    Civil menilai ulang, lalu Document Preparation dan kirim ulang = ronde MGMT baru, BR-53);
                    catatan wajib
         REJECT  -> REJECTED (ST-15), hanya bila AllowReject = 1; alasan wajib (BR-08)
       REVISE/REJECT menutup (VOID) sisa langkah PENDING ronde tersebut. Semua aksi tercatat (BR-10).
   Error   : 50072 = Input wajib kosong / tidak valid
             50073 = Request / langkah tidak ditemukan atau di luar lingkup user
             50074 = Status request / langkah tidak mengizinkan aksi ini (termasuk sudah diproses approver lain)
             50075 = User tidak berhak memproses langkah ini (role, lingkup, Company, atau request sendiri)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Index langkah PENDING (dipakai function di bawah dan Tugas Saya T2-4)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_ApprovalStep_Pending' AND object_id = OBJECT_ID(N'dbo.ApprovalStep'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ApprovalStep_Pending
        ON dbo.ApprovalStep (RequestId, [Point], Round)
        INCLUDE (StepOrder, RoleCode, Scope, DepartmentGroupCode, StartedAt)
        WHERE Status = 'PENDING';
END
GO

/* ---------------------------------------------------------------------
   2. dbo.fn_User_ActionableSteps(@Username)
      Langkah approval AKTIF yang boleh diproses user (semua titik). 0 baris = tidak ada tugas.
      Dipakai: usp_Request_ApprovalAct (validasi), usp_Request_GetActionableStep (tombol Details),
      Tugas Saya / badge header (T2-4).
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_ActionableSteps
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    WITH me AS
    (
        SELECT  e.CoCode, ad.ABRV
        FROM    home..users u
                JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
                LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
        WHERE   u.Username = @Username
          AND   (e.ResignDate IS NULL OR e.ResignDate > GETDATE())
    ),
    r AS
    (
        SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
        FROM   home..users u
               CROSS APPLY STRING_SPLIT(u.[Role], N';') s
        WHERE  u.Username = @Username
          AND  LTRIM(RTRIM(s.value)) <> N''
    )
    SELECT  s.Id AS ApprovalStepId, s.RequestId, s.[Point], s.Round, s.StepOrder, s.RoleCode, s.StartedAt
    FROM    dbo.ApprovalStep s
            JOIN dbo.ProjectRequest pr       ON pr.Id = s.RequestId
            JOIN home..APP_Departments rd    ON rd.DepartmentID = pr.DepartmentID
            CROSS JOIN me
    WHERE   s.Status = 'PENDING'
      AND   s.StartedAt IS NOT NULL
      AND   s.Round = (SELECT MAX(x.Round) FROM dbo.ApprovalStep x WHERE x.RequestId = s.RequestId AND x.[Point] = s.[Point])
      AND   pr.Status = CASE s.[Point] WHEN 'REQUEST' THEN 'WAITING_APPROVAL'
                                       WHEN 'MGMT'    THEN 'MGMT_APPROVAL'
                                       WHEN 'BAPP'    THEN 'BAPP_REVIEW' END
      AND   pr.CoCode = me.CoCode                                   -- BR-63
      AND   pr.RequesterUsername <> @Username                       -- BR-30
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = s.RoleCode)  -- BR-39: satu langkah = satu role
      AND   (
                s.Scope = 'PLANT'
             OR (s.Scope = 'DEPT' AND rd.ABRV = me.ABRV)            -- BR-24
             OR (s.Scope = 'GROUP'
                 AND EXISTS (SELECT 1
                             FROM   dbo.DepartmentGroup g
                                    JOIN dbo.DepartmentGroupMember m ON m.GroupId = g.Id
                             WHERE  g.CoCode = pr.CoCode AND g.GroupCode = s.DepartmentGroupCode AND g.IsActive = 1
                               AND  m.DepartmentID = pr.DepartmentID))
            )
);
GO

/* ---------------------------------------------------------------------
   3. usp_Request_GetActionableStep  (Details: tampilkan tombol Approve/Revise/Reject)
      0 baris = user tidak bisa memproses request ini sekarang.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetActionableStep
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (1)
            s.Id, s.[Point], s.Round, s.StepOrder, s.RoleCode, h.Description AS RoleName, s.Scope,
            s.DepartmentGroupCode, s.ReviseTo, s.AllowReject, s.Status, s.StartedAt, s.ActedAt, s.ActedBy, s.Remarks,
            CAST(1 AS BIT) AS IsCurrent
    FROM    dbo.fn_User_ActionableSteps(@Username) a
            JOIN dbo.ApprovalStep s          ON s.Id = a.ApprovalStepId
            LEFT JOIN dbo.HierarchyLevel h   ON h.[Role] = s.RoleCode
    WHERE   a.RequestId = @RequestId
    ORDER BY s.StepOrder;
END
GO

/* ---------------------------------------------------------------------
   4. usp_Request_ApprovalAct  (Approve / Revise / Reject langkah titik REQUEST dan MGMT)
      @StepId  = langkah yang ditampilkan ke user (BR-39: cegah aksi ganda).
      @Action  = APPROVE | REVISE | REJECT
      @Remarks = opsional untuk APPROVE; wajib untuk REVISE dan REJECT (maks. 1000 karakter).
      Hasil    : SELECT Status (status request yang baru).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_ApprovalAct
    @Id        INT,
    @StepId    INT,
    @Username  NVARCHAR(100),
    @Action    VARCHAR(10),
    @Remarks   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Action  = UPPER(LTRIM(RTRIM(@Action)));
    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    IF @Action IS NULL OR @Action NOT IN ('APPROVE', 'REVISE', 'REJECT')
        THROW 50072, N'Invalid approval action.', 1;
    IF @Action = 'REVISE' AND @Remarks IS NULL
        THROW 50072, N'Revision notes are required.', 1;
    IF @Action = 'REJECT' AND @Remarks IS NULL
        THROW 50072, N'Rejection reason is required.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Status VARCHAR(20), @Requester NVARCHAR(100);

    BEGIN TRANSACTION;

    -- Kunci baris request: aksi bersamaan pada request yang sama diproses berurutan (BR-39)
    SELECT  @Status = r.Status, @Requester = r.RequesterUsername
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;

    DECLARE @Point VARCHAR(10), @Round INT, @StepOrder INT, @StepStatus VARCHAR(10), @StartedAt DATETIME2(3),
            @ReviseTo VARCHAR(10), @AllowReject BIT;

    SELECT  @Point = s.[Point], @Round = s.Round, @StepOrder = s.StepOrder, @StepStatus = s.Status,
            @StartedAt = s.StartedAt, @ReviseTo = s.ReviseTo, @AllowReject = s.AllowReject
    FROM    dbo.ApprovalStep s
    WHERE   s.Id = @StepId AND s.RequestId = @Id;

    IF @Point IS NULL
        THROW 50073, N'Approval step not found.', 1;
    -- T2-3: REQUEST · T3-3: MGMT (GM / Director). BAPP menyusul (T5).
    IF @Point NOT IN ('REQUEST', 'MGMT')
        THROW 50074, N'This approval step cannot be processed here.', 1;

    DECLARE @PointStatus VARCHAR(20) = CASE @Point WHEN 'REQUEST' THEN 'WAITING_APPROVAL' ELSE 'MGMT_APPROVAL' END;

    IF @Status <> @PointStatus
       OR @StepStatus <> 'PENDING'
       OR @StartedAt IS NULL
       OR @Round <> (SELECT MAX(Round) FROM dbo.ApprovalStep WHERE RequestId = @Id AND [Point] = @Point)
        THROW 50074, N'This approval step has already been processed.', 1;

    IF @Requester = @Username
        THROW 50075, N'You cannot approve your own request.', 1;                         -- BR-30
    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_ActionableSteps(@Username) a WHERE a.ApprovalStepId = @StepId)
        THROW 50075, N'You are not authorized to process this approval step.', 1;

    -- Tujuan Revise dari snapshot langkah: REQUESTER -> RETURNED, CIVIL -> FEASIBILITY (BR-06, BR-07)
    IF @Action = 'REVISE' AND ISNULL(@ReviseTo, '') NOT IN ('REQUESTER', 'CIVIL')
        THROW 50074, N'Revision is not allowed at this approval step.', 1;
    IF @Action = 'REJECT' AND @AllowReject = 0
        THROW 50074, N'Rejection is not allowed at this approval step.', 1;

    DECLARE @NewStatus VARCHAR(20);

    UPDATE dbo.ApprovalStep
    SET    Status   = CASE @Action WHEN 'APPROVE' THEN 'APPROVED' WHEN 'REVISE' THEN 'REVISED' ELSE 'REJECTED' END,
           ActedAt  = @Now,
           ActedBy  = @Username,
           Remarks  = @Remarks
    WHERE  Id = @StepId;

    IF @Action = 'APPROVE'
    BEGIN
        DECLARE @NextOrder INT =
        (
            SELECT MIN(StepOrder) FROM dbo.ApprovalStep
            WHERE  RequestId = @Id AND [Point] = @Point AND Round = @Round
              AND  Status = 'PENDING' AND StepOrder > @StepOrder
        );

        IF @NextOrder IS NOT NULL
        BEGIN
            SET @NewStatus = @PointStatus;
            UPDATE dbo.ApprovalStep SET StartedAt = @Now
            WHERE  RequestId = @Id AND [Point] = @Point AND Round = @Round AND StepOrder = @NextOrder;
        END
        ELSE
            -- Langkah terakhir: REQUEST -> FEASIBILITY (ST-04), MGMT -> PLANNING (ST-08)
            SET @NewStatus = CASE @Point WHEN 'REQUEST' THEN 'FEASIBILITY' ELSE 'PLANNING' END;
    END
    ELSE
    BEGIN
        -- ST-03 / ST-04 (Revise ke Civil) / ST-15
        SET @NewStatus = CASE WHEN @Action = 'REJECT'         THEN 'REJECTED'
                              WHEN @ReviseTo = 'CIVIL'        THEN 'FEASIBILITY'
                              ELSE 'RETURNED' END;

        UPDATE dbo.ApprovalStep SET Status = 'VOID'
        WHERE  RequestId = @Id AND [Point] = @Point AND Round = @Round AND Status = 'PENDING';
    END

    UPDATE dbo.ProjectRequest
    SET    Status = @NewStatus, UpdatedAt = @Now, UpdatedBy = @Username
    WHERE  Id = @Id;

    INSERT INTO dbo.ApprovalHistory (RequestId, ApprovalStepId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, @StepId, @Action, @Status, @NewStatus, @Remarks, @Username, @Now);

    COMMIT TRANSACTION;

    SELECT @NewStatus AS Status;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel hanya hidup dalam satu eksekusi: jalankan blok bersama DECLARE-nya.

   -- 0) Siapkan request WAITING_APPROVAL (Submit lewat aplikasi), lalu cari user per role:
   SELECT u.Username, u.[Role], e.CoCode, ad.ABRV, ad.DepartmentID
   FROM   home..users u
          JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
          LEFT JOIN home..APP_Departments ad ON ad.DepartmentID = e.DepartmentID
   WHERE  u.[Role] LIKE N'%kabag%' OR u.[Role] LIKE N'%mo%';

   DECLARE @Id INT = 3, @Kabag NVARCHAR(100) = N'marisi', @KabagLain NVARCHAR(100) = N'hdahlia',
           @Mo NVARCHAR(100) = N'maamanullang', @Requester NVARCHAR(100) = N'asimbolon';

   -- 1) Tugas: kabag ABRV sama -> 1 baris; kabag ABRV lain / requester / mo (sebelum kabag approve) -> 0 baris
   SELECT * FROM dbo.fn_User_ActionableSteps(@Kabag)     WHERE RequestId = @Id;
   SELECT * FROM dbo.fn_User_ActionableSteps(@KabagLain) WHERE RequestId = @Id;
   SELECT * FROM dbo.fn_User_ActionableSteps(@Mo)        WHERE RequestId = @Id;
   EXEC dbo.usp_Request_GetActionableStep @RequestId = @Id, @Username = @Kabag;

DECLARE @Id INT = 3, @Kabag NVARCHAR(100) = N'marisi', @KabagLain NVARCHAR(100) = N'hdahlia',
           @Mo NVARCHAR(100) = N'maamanullang', @Requester NVARCHAR(100) = N'asimbolon';
   -- 2) Validasi input: aksi salah / Revise tanpa catatan / Reject tanpa alasan -> 50072
   DECLARE @Step INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Kabag) WHERE RequestId = @Id);
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @Kabag, @Action = 'XYZ';
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @Kabag, @Action = 'REVISE';
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @Kabag, @Action = 'REJECT', @Remarks = N'  ';

   -- 3) Tidak berhak: kabag ABRV lain -> 50073 (di luar lingkup lihat) atau 50075; requester (bila juga kabag) -> 50075
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @KabagLain, @Action = 'APPROVE';

DECLARE @Id INT = 3, @Kabag NVARCHAR(100) = N'marisi', @KabagLain NVARCHAR(100) = N'hdahlia',
           @Mo NVARCHAR(100) = N'maamanullang', @Requester NVARCHAR(100) = N'asimbolon';
    DECLARE @Step INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Kabag) WHERE RequestId = @Id);
   -- 4) Approve oleh kabag:
   --    non-MILL -> Status FEASIBILITY;  MILL -> WAITING_APPROVAL, langkah mo aktif (StartedAt terisi)
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @Step, @Username = @Kabag, @Action = 'APPROVE', @Remarks = N'OK';
   EXEC dbo.usp_Request_GetApprovalSteps @RequestId = @Id, @Username = @Kabag;
   EXEC dbo.usp_Request_GetHistory @RequestId = @Id, @Username = @Kabag;           -- APPROVE + remarks

   -- 5) Approve ulang dengan @StepId yang sama (BR-39, approver kedua) -> 50074 "already processed"
   EXEC dbo.usp_Request_ApprovalAct @Id =3, @StepId = 6, @Username = 'marisi', @Action = 'APPROVE';

   -- 6) MILL: mo Revise -> RETURNED; langkah lain ronde ini VOID; requester bisa edit dan Resubmit (ronde baru)
   DECLARE @Id INT = 3, @Kabag NVARCHAR(100) = N'marisi', @KabagLain NVARCHAR(100) = N'hdahlia',
           @Mo NVARCHAR(100) = N'maamanullang', @Requester NVARCHAR(100) = N'asimbolon';

   DECLARE @MoStep INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Mo) WHERE RequestId = @Id);
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @MoStep, @Username = @Mo, @Action = 'REVISE', @Remarks = N'Please add drawing';

   -- 7) Reject (request lain yang WAITING_APPROVAL) -> REJECTED; Submit/Cancel berikutnya -> 50074
   --EXEC dbo.usp_Request_ApprovalAct @Id = 3, @StepId = 6, @Username = 'marisi', @Action = 'REJECT', @Remarks = N'Not a priority';

   -- 8) BR-63: user role kabag dari Company lain (NKM vs ABL) -> 0 baris di fn_User_ActionableSteps
   ===================================================================== */

/* =====================================================================
   TEST T3-3 MANAGEMENT APPROVAL (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (baris TestCase / ErrNo / ErrMsg).
   CATCH wajib ROLLBACK: error di dalam transaksi SP (XACT_ABORT ON) membuat transaksi "doomed";
   tanpa ROLLBACK, statement berikutnya gagal dengan error 3998/3930.
   Prasyarat: request MGMT_APPROVAL (mis. Id 3, ABL CAPEX setelah Send to Management di T3-2).

   -- 0) Cari user gm / director ABL
   SELECT u.Username, u.[Role], e.CoCode FROM home..users u JOIN home..app_employees e ON e.EmployeeCode = u.EmployeeCode
   WHERE  u.[Role] LIKE N'%gm%' OR u.[Role] LIKE N'%director%';

   DECLARE @Id INT = 3, @Gm NVARCHAR(100) = N'<user gm>', @Dir NVARCHAR(100) = N'<user director>';

   -- 1) Langkah aktif: GM -> 1 baris; Director (sebelum GM approve) -> 0 baris
   EXEC dbo.usp_Request_GetActionableStep @RequestId = @Id, @Username = @Gm;
   EXEC dbo.usp_Request_GetActionableStep @RequestId = @Id, @Username = @Dir;

   -- 2) Director memakai StepId GM -> 50075; GM Revise tanpa catatan -> 50072
   DECLARE @GmStep INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Gm) WHERE RequestId = @Id AND [Point] = 'MGMT');
   BEGIN TRY EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @GmStep, @Username = @Dir, @Action = 'APPROVE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '2a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @GmStep, @Username = @Gm, @Action = 'REVISE';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '2b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 3) GM Approve -> tetap MGMT_APPROVAL (CAPEX), langkah Director aktif; OPEX -> PLANNING
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @GmStep, @Username = @Gm, @Action = 'APPROVE', @Remarks = N'OK';
   EXEC dbo.usp_Request_GetApprovalSteps @RequestId = @Id, @Username = @Gm;

   -- 4a) Director Revise -> FEASIBILITY (kembali ke Civil); langkah MGMT sisa VOID; tugas FEASIBILITY Civil muncul
   DECLARE @DirStep INT = (SELECT ApprovalStepId FROM dbo.fn_User_ActionableSteps(@Dir) WHERE RequestId = @Id AND [Point] = 'MGMT');
   EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @DirStep, @Username = @Dir, @Action = 'REVISE', @Remarks = N'Please revise BOQ';
   --    lalu Civil: Feasible -> Document Preparation -> Send to Management -> ronde MGMT 2 (GM lagi)
   -- 4b) atau Director Approve -> PLANNING; tugas PLANNING Civil muncul
   --EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @DirStep, @Username = @Dir, @Action = 'APPROVE';
   -- 4c) atau Reject (alasan wajib) -> REJECTED
   --EXEC dbo.usp_Request_ApprovalAct @Id = @Id, @StepId = @DirStep, @Username = @Dir, @Action = 'REJECT', @Remarks = N'Budget not available';

   -- 5) Setelah ada langkah MGMT APPROVED, requester Cancel -> 50074 (BR-09)
   ===================================================================== */
