/* =====================================================================
   Task.sql  -  Tugas Saya + badge header (T2-4; PRD 7.1, FR-01, FR-02, BR-32, BR-63, BR-66)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestApproval.sql.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Satu sumber untuk daftar Tugas Saya (FR-01) dan angka badge (FR-02): dbo.fn_User_Tasks.
     - Jenis tugas (PRD 7.1) yang sudah ada sampai T2:
         APPROVAL    : langkah approval aktif yang boleh diproses user (fn_User_ActionableSteps;
                       role, lingkup, Company, bukan request sendiri). Berlaku juga untuk MGMT/BAPP nanti.
         REVISE      : request RETURNED milik requester (pembuat request) -> revisi dan Submit ulang.
         REJECTED    : request REJECTED milik requester -> informasi; hilang setelah Details dibuka
                       (dbo.RequestTaskRead).
         FEASIBILITY : request FEASIBILITY -> role civil (lingkup Civil = ABL dan NKM, BR-59).
         DOC_PREPARATION : request DOC_PREPARATION -> role civil (BOQ, Drawing, kirim ke management; T3-2).
         PLANNING    : request PLANNING -> role civil (aktif setelah management approval, T3).
         PROCUREMENT : request PROCUREMENT (TOR dikirim) -> role purchasing (input kontrak; T4-1).
         SCHEDULING  : request SCHEDULING -> role civil (schedule, action plan, estimasi biaya, site handover; T4-2).
         PROGRESS    : request IN_PROGRESS yang progress minggu berjalan (Senin s.d. Minggu) belum disimpan
                       -> role civil (pengingat input progress mingguan; T5-1, BR-16, BR-66). Hilang setelah
                       progress minggu itu disimpan. TaskSince = Senin minggu berjalan.
         ADDENDUM    : addendum berstatus FINAL_CONTRACT (outsource: upload kontrak final, BR-87) atau ADJUSTMENT
                       (penyesuaian action plan + estimasi, BR-82) -> role civil (T4-4). TaskSince = saat langkah itu
                       mulai. Approval addendum (nilai naik) muncul sebagai APPROVAL titik ADDENDUM.
         BAPP        : project In Progress dengan semua action plan 100% + tanggal selesai aktual -> role civil
                       (terbitkan BAPP; T6-1, BR-88). Approval BAPP muncul sebagai APPROVAL titik BAPP.
       Urutan menjalankan: Task.sql SETELAH RequestProgress.sql (memakai ProjectProgressWeek dan fn_WeekStart)
       dan SETELAH RequestAddendum.sql (memakai ProjectAddendum).
       Jenis lain (TOR -> purchasing, BAPP, survei) ditambah di modulnya (T4/T6).
     - TaskSince = sejak kapan tugas menunggu (StartedAt langkah, atau waktu status terakhir dari history).
       Tidak ada penanda overdue (BR-32).
     - Semua tugas juga dibatasi lingkup lihat user (fn_User_AllowedDepartments).
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.RequestTaskRead  (tugas informasi yang sudah dibuka, mis. REJECTED)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.RequestTaskRead', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RequestTaskRead
    (
        RequestId  INT            NOT NULL,
        Username   NVARCHAR(100)  NOT NULL,
        TaskType   VARCHAR(20)    NOT NULL,
        ReadAt     DATETIME2(3)   NOT NULL CONSTRAINT DF_RequestTaskRead_ReadAt DEFAULT (SYSDATETIME()),
        CONSTRAINT PK_RequestTaskRead PRIMARY KEY CLUSTERED (RequestId, Username, TaskType),
        CONSTRAINT FK_RequestTaskRead_Request FOREIGN KEY (RequestId) REFERENCES dbo.ProjectRequest (Id)
    );
END
GO

/* ---------------------------------------------------------------------
   2. Index status request (tugas REVISE/REJECTED/civil difilter per status)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'IX_ProjectRequest_Status' AND object_id = OBJECT_ID(N'dbo.ProjectRequest'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectRequest_Status
        ON dbo.ProjectRequest (Status) INCLUDE (DepartmentID, RequesterUsername);
END
GO

/* ---------------------------------------------------------------------
   3. dbo.fn_User_Tasks(@Username)
      Satu baris per tugas: TaskType, RequestId, ApprovalStepId (hanya APPROVAL), TaskSince.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_Tasks
(
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
          AND  LTRIM(RTRIM(s.value)) <> N''
    ),
    scope AS
    (
        SELECT DepartmentID FROM dbo.fn_User_AllowedDepartments(@Username)
    )
    -- Langkah approval aktif (request / management / BAPP)
    SELECT  CAST('APPROVAL' AS VARCHAR(20)) AS TaskType, a.RequestId, a.ApprovalStepId, a.StartedAt AS TaskSince
    FROM    dbo.fn_User_ActionableSteps(@Username) a
            JOIN dbo.ProjectRequest pr ON pr.Id = a.RequestId
    WHERE   pr.DepartmentID IN (SELECT DepartmentID FROM scope)

    UNION ALL

    -- Dikembalikan untuk revisi -> requester
    SELECT  'REVISE', pr.Id, NULL,
            (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = 'RETURNED')
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status = 'RETURNED'
      AND   pr.RequesterUsername = @Username
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)

    UNION ALL

    -- Ditolak -> requester (informasi, sampai Details dibuka)
    SELECT  'REJECTED', pr.Id, NULL,
            (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = 'REJECTED')
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status = 'REJECTED'
      AND   pr.RequesterUsername = @Username
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
      AND   NOT EXISTS (SELECT 1 FROM dbo.RequestTaskRead t
                        WHERE t.RequestId = pr.Id AND t.Username = @Username AND t.TaskType = 'REJECTED')

    UNION ALL

    -- Pekerjaan Civil (Feasibility / Document Preparation (T3-2) / Planning / Scheduling (T4-2))
    SELECT  pr.Status, pr.Id, NULL,
            (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = pr.Status)
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status IN ('FEASIBILITY', 'DOC_PREPARATION', 'PLANNING', 'SCHEDULING')
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'civil')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)

    UNION ALL

    -- Procurement (TOR dikirim Civil) -> purchasing input kontrak (T4-1, BR-11)
    SELECT  pr.Status, pr.Id, NULL,
            (SELECT MAX(h.ActionAt) FROM dbo.ApprovalHistory h WHERE h.RequestId = pr.Id AND h.ToStatus = pr.Status)
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status = 'PROCUREMENT'
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'purchasing')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)

    UNION ALL

    -- Progress minggu berjalan belum disimpan -> civil (T5-1, BR-16)
    SELECT  'PROGRESS', pr.Id, NULL, CAST(wk.WeekStart AS DATETIME2(3))
    FROM    dbo.ProjectRequest pr
            CROSS APPLY (SELECT dbo.fn_WeekStart(CAST(SYSDATETIME() AS DATE)) AS WeekStart) wk
    WHERE   pr.Status = 'IN_PROGRESS'
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'civil')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
      AND   NOT EXISTS (SELECT 1 FROM dbo.ProjectProgressWeek w WHERE w.RequestId = pr.Id AND w.WeekStart = wk.WeekStart)

    UNION ALL

    -- T6-1: semua action plan 100% + selesai aktual saat In Progress -> civil terbitkan BAPP (BR-88)
    SELECT  'BAPP', pr.Id, NULL,
            (SELECT CAST(MAX(a.ActualEndDate) AS DATETIME2(3)) FROM dbo.ProjectActionPlan a WHERE a.RequestId = pr.Id)
    FROM    dbo.ProjectRequest pr
    WHERE   pr.Status = 'IN_PROGRESS'
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'civil')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
      AND   EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a WHERE a.RequestId = pr.Id)
      AND   NOT EXISTS (SELECT 1 FROM dbo.ProjectActionPlan a
                        WHERE a.RequestId = pr.Id AND (a.ProgressPercent < 100 OR a.ActualEndDate IS NULL))

    UNION ALL

    -- Addendum berlaku -> civil: outsource upload kontrak final (BR-87), lalu penyesuaian action plan + estimasi (BR-82)
    SELECT  'ADDENDUM', pr.Id, NULL, COALESCE(d.FinalUploadedAt, d.ApprovedAt, d.CreatedAt)
    FROM    dbo.ProjectAddendum d
            JOIN dbo.ProjectRequest pr ON pr.Id = d.RequestId
    WHERE   d.Status IN ('FINAL_CONTRACT', 'ADJUSTMENT')
      AND   pr.Status IN ('SCHEDULING', 'IN_PROGRESS')
      AND   EXISTS (SELECT 1 FROM r WHERE r.RoleCode = N'civil')
      AND   pr.DepartmentID IN (SELECT DepartmentID FROM scope)
);
GO

/* ---------------------------------------------------------------------
   4. usp_Task_GetSummary  (jumlah per jenis; total = badge header FR-02)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Task_GetSummary
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  t.TaskType, COUNT(*) AS TaskCount
    FROM    dbo.fn_User_Tasks(@Username) t
    GROUP BY t.TaskType
    ORDER BY CHARINDEX(',' + t.TaskType + ',', ',APPROVAL,REVISE,REJECTED,FEASIBILITY,DOC_PREPARATION,PLANNING,PROCUREMENT,SCHEDULING,ADDENDUM,PROGRESS,BAPP,');
END
GO

/* ---------------------------------------------------------------------
   5. usp_Task_GetList  (daftar Tugas Saya; @TaskType NULL = semua). Terlama di atas.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Task_GetList
    @Username NVARCHAR(100),
    @TaskType VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @TaskType = NULLIF(LTRIM(RTRIM(@TaskType)), '');

    SELECT  t.TaskType, t.RequestId, t.ApprovalStepId, t.TaskSince,
            pr.RequestNo, pr.Title, pr.Category, pr.Status, pr.CoCode, d.DeptName, d.ABRV,
            req.FullName AS RequesterName,
            s.[Point], s.StepOrder, s.RoleCode, h.Description AS RoleName
    FROM    dbo.fn_User_Tasks(@Username) t
            JOIN dbo.ProjectRequest pr            ON pr.Id = t.RequestId
            LEFT JOIN home..APP_Departments d     ON d.DepartmentID = pr.DepartmentID
            LEFT JOIN home..app_employees req     ON req.EmployeeCode = pr.RequesterEmployeeCode
            LEFT JOIN dbo.ApprovalStep s          ON s.Id = t.ApprovalStepId
            LEFT JOIN dbo.HierarchyLevel h        ON h.[Role] = s.RoleCode
    WHERE   (@TaskType IS NULL OR t.TaskType = @TaskType)
    ORDER BY CASE WHEN t.TaskSince IS NULL THEN 1 ELSE 0 END, t.TaskSince, t.RequestId;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Task_MarkRead  (tugas informasi dibuka -> hilang dari Tugas Saya)
      Hanya mencatat bila tugas itu memang milik user saat ini (selain itu diabaikan, tanpa error).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Task_MarkRead
    @RequestId INT,
    @Username  NVARCHAR(100),
    @TaskType  VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    IF @TaskType <> 'REJECTED'
        RETURN;   -- hanya tugas informasi; tugas lain hilang karena statusnya berubah

    INSERT INTO dbo.RequestTaskRead (RequestId, Username, TaskType)
    SELECT  @RequestId, @Username, @TaskType
    WHERE   EXISTS (SELECT 1 FROM dbo.fn_User_Tasks(@Username) t
                    WHERE t.RequestId = @RequestId AND t.TaskType = @TaskType)
      AND   NOT EXISTS (SELECT 1 FROM dbo.RequestTaskRead x WITH (UPDLOCK, HOLDLOCK)
                        WHERE x.RequestId = @RequestId AND x.Username = @Username AND x.TaskType = @TaskType);
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Variabel hanya hidup dalam satu eksekusi: jalankan blok bersama DECLARE-nya.

   DECLARE @Kabag NVARCHAR(100) = N'marisi', @Mo NVARCHAR(100) = N'maamanullang',
           @Requester NVARCHAR(100) = N'asimbolon', @Civil NVARCHAR(100) = N'<user civil>';

   -- 1) Approver: request WAITING_APPROVAL departemennya -> APPROVAL (sama dengan fn_User_ActionableSteps)
   EXEC dbo.usp_Task_GetSummary @Username = @Kabag;
   EXEC dbo.usp_Task_GetList    @Username = @Kabag;
   SELECT COUNT(*) AS Harus_Sama FROM dbo.fn_User_ActionableSteps(@Kabag);

   -- 2) Requester: request RETURNED -> REVISE; REJECTED (belum dibuka) -> REJECTED
   EXEC dbo.usp_Task_GetSummary @Username = @Requester;
   EXEC dbo.usp_Task_GetList    @Username = @Requester;

   -- 3) MarkRead: REJECTED hilang; jenis lain / request bukan miliknya -> tidak tercatat, tanpa error
   DECLARE @Rej INT = (SELECT TOP (1) RequestId FROM dbo.fn_User_Tasks(@Requester) WHERE TaskType = 'REJECTED');
   EXEC dbo.usp_Task_MarkRead @RequestId = @Rej, @Username = @Requester, @TaskType = 'REJECTED';
   EXEC dbo.usp_Task_MarkRead @RequestId = @Rej, @Username = @Requester, @TaskType = 'REJECTED';  -- ulang: tetap 1 baris
   SELECT * FROM dbo.RequestTaskRead;
   EXEC dbo.usp_Task_GetList @Username = @Requester, @TaskType = 'REJECTED';                      -- @Rej tidak ada lagi

   -- 4) Civil: request FEASIBILITY (ABL dan NKM) -> FEASIBILITY; user non-civil -> tidak ada jenis ini
   EXEC dbo.usp_Task_GetSummary @Username = @Civil;
   EXEC dbo.usp_Task_GetList    @Username = @Civil, @TaskType = 'FEASIBILITY';

   -- 4b) Civil: project IN_PROGRESS tanpa progress minggu berjalan -> PROGRESS (TaskSince = Senin minggu ini);
   --     setelah usp_Request_SaveProgress untuk minggu ini, baris project itu hilang
   EXEC dbo.usp_Task_GetList @Username = 'users1', @TaskType = 'PROGRESS';
   SELECT pr.Id, pr.RequestNo, w.WeekStart FROM dbo.ProjectRequest pr
          LEFT JOIN dbo.ProjectProgressWeek w ON w.RequestId = pr.Id AND w.WeekStart = dbo.fn_WeekStart(CAST(SYSDATETIME() AS DATE))
   WHERE  pr.Status = 'IN_PROGRESS';                                                  -- WeekStart NULL = muncul sebagai tugas

   -- 5) User tanpa tugas / tidak ada -> 0 baris
   EXEC dbo.usp_Task_GetSummary @Username = N'tidak-ada-xyz';
   ===================================================================== */
