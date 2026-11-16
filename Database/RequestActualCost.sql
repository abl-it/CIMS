/* =====================================================================
   RequestActualCost.sql  -  Actual cost bulanan per item (input manual), status biaya dan keseluruhan
                             (T5-2; PRD 3.3 langkah 5, 6.4, BR-18, BR-19, BR-69, BR-70, BR-71, CF-08)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestProgress.sql
             (kolom ScheduleStatus dipakai kolom OverallStatus) dan Unit.sql; lalu jalankan ulang RequestSchedule.sql
             (perubahan estimasi saat In Progress menghitung ulang status biaya).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Aturan (Keputusan 16-11-2026, lihat docs/PRD-log.md):
     - Civil menyimpan SELURUH item satu bulan sekaligus; simpan menimpa item bulan itu (sama dengan upload ulang,
       BR-19). Daftar item kosong = hapus actual bulan itu. Setiap simpan tercatat di riwayat (ACTUAL_COST).
     - Bulan: dari bulan awal Preparation (atau bulan mulai project bila kosong) s.d. bulan berjalan.
     - Status request: IN_PROGRESS atau BAPP_REVIEW.
     - Item (6.4): jenis GOODS/SERVICE, nama, qty > 0, satuan (teks bebas; master Unit hanya saran), harga satuan > 0,
       amount = qty × harga satuan (toleransi pembulatan IDR 1), no. referensi dan keterangan opsional.
     - Status biaya (BR-69): rasio = Σ actual ÷ Σ estimasi s.d. bulan closing terakhir (bulan actual terakhir) × 100.
       Bila bulan actual terakhir sebelum bulan estimasi pertama (biaya masa Preparation), pembanding = estimasi bulan
       pertama. Tanpa actual = ON_TRACK. Ambang dari AppSetting COST_ONTRACK_MAX_PCT (100), COST_ATRISK_MAX_PCT (110).
     - Status keseluruhan (BR-70): kolom terhitung OverallStatus = status terburuk jadwal dan biaya.
     - Lihat detail bulan/item: civil, fat, gm, director, administrator (matriks PRD 5.2); ringkasan status
       untuk semua role yang boleh melihat request (kecuali purchasing-only).
   Error   : 50072 = Input wajib kosong / tidak valid
             50073 = Request tidak ditemukan atau di luar lingkup user
             50074 = Status request tidak mengizinkan aksi ini
             50075 = Role user tidak sesuai (civil)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. Migrasi kolom dbo.ProjectRequest (ringkasan biaya + status)
   --------------------------------------------------------------------- */
IF COL_LENGTH(N'dbo.ProjectRequest', N'CostStatus') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD
        ActualCostTotal   DECIMAL(18, 2) NULL,
        CostRatioPercent  DECIMAL(9, 2)  NULL,
        CostStatus        VARCHAR(20)    NULL
            CONSTRAINT CK_ProjectRequest_CostStatus CHECK (CostStatus IS NULL OR CostStatus IN ('ON_TRACK', 'AT_RISK', 'OVER_BUDGET')),
        CostStatusAt      DATETIME2(3)   NULL,
        LastActualMonth   DATE           NULL;
END
GO

-- Status keseluruhan (BR-70): terburuk antara jadwal dan biaya; NULL bila keduanya belum dihitung
IF COL_LENGTH(N'dbo.ProjectRequest', N'OverallStatus') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectRequest ADD OverallStatus AS
        CAST(CASE WHEN ScheduleStatus = 'DELAY' OR CostStatus = 'OVER_BUDGET'      THEN 'DELAYED'
                  WHEN ScheduleStatus = 'SLIGHT_DELAY' OR CostStatus = 'AT_RISK'   THEN 'AT_RISK'
                  WHEN ScheduleStatus IS NULL AND CostStatus IS NULL               THEN NULL
                  ELSE 'ON_TRACK' END AS VARCHAR(20));
END
GO

/* ---------------------------------------------------------------------
   2. TABLE dbo.ProjectActualMonth  (satu baris per project per bulan; entitas CostActualUpload PRD 6.7)
      AttachmentId: cadangan (lampiran per request); tidak dipakai. File Excel upload pusat (T5-3) -> UploadId.
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectActualMonth', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectActualMonth
    (
        Id            INT IDENTITY(1,1) NOT NULL,
        RequestId     INT            NOT NULL,
        PeriodMonth   DATE           NOT NULL,       -- tanggal 1 bulan tersebut
        TotalAmount   DECIMAL(18, 2) NOT NULL,
        ItemCount     INT            NOT NULL,
        Source        VARCHAR(10)    NOT NULL,       -- MANUAL | EXCEL
        AttachmentId  INT            NULL,
        Remarks       NVARCHAR(1000) NULL,
        CreatedAt     DATETIME2(3)   NOT NULL CONSTRAINT DF_ProjectActualMonth_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy     NVARCHAR(100)  NOT NULL,
        UpdatedAt     DATETIME2(3)   NULL,
        UpdatedBy     NVARCHAR(100)  NULL,
        CONSTRAINT PK_ProjectActualMonth PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT UQ_ProjectActualMonth UNIQUE (RequestId, PeriodMonth),
        CONSTRAINT FK_ProjectActualMonth_Request    FOREIGN KEY (RequestId)    REFERENCES dbo.ProjectRequest (Id),
        CONSTRAINT FK_ProjectActualMonth_Attachment FOREIGN KEY (AttachmentId) REFERENCES dbo.RequestAttachment (Id),
        CONSTRAINT CK_ProjectActualMonth_Month  CHECK (DAY(PeriodMonth) = 1),
        CONSTRAINT CK_ProjectActualMonth_Source CHECK (Source IN ('MANUAL', 'EXCEL'))
    );
END
GO

/* ---------------------------------------------------------------------
   2a. TABLE dbo.ActualCostUpload  (T5-3; arsip file Excel actual cost, satu file bisa banyak project/bulan; BR-19)
       Status: PENDING (sudah diupload + dipreview) -> IMPORTED (dikonfirmasi) | CANCELLED.
       RelativePath relatif terhadap FileStorage:RealizationAttachmentsPath (mis. ActualCost\2026\<guid>.xlsx).
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ActualCostUpload', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ActualCostUpload
    (
        Id                INT IDENTITY(1,1) NOT NULL,
        OriginalFileName  NVARCHAR(260)  NOT NULL,
        RelativePath      NVARCHAR(400)  NOT NULL,
        ContentType       VARCHAR(100)   NOT NULL,
        FileSizeBytes     BIGINT         NOT NULL,
        RowTotal          INT            NOT NULL,
        GroupTotal        INT            NOT NULL,       -- jumlah project + bulan
        TotalAmount       DECIMAL(18, 2) NOT NULL,
        Status            VARCHAR(10)    NOT NULL CONSTRAINT DF_ActualCostUpload_Status DEFAULT ('PENDING'),
        CreatedAt         DATETIME2(3)   NOT NULL CONSTRAINT DF_ActualCostUpload_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy         NVARCHAR(100)  NOT NULL,
        ProcessedAt       DATETIME2(3)   NULL,
        ProcessedBy       NVARCHAR(100)  NULL,
        CONSTRAINT PK_ActualCostUpload PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_ActualCostUpload_Status CHECK (Status IN ('PENDING', 'IMPORTED', 'CANCELLED')),
        CONSTRAINT CK_ActualCostUpload_Size   CHECK (FileSizeBytes > 0)
    );
END
GO

-- Bulan actual hasil upload Excel menunjuk file arsipnya
IF COL_LENGTH(N'dbo.ProjectActualMonth', N'UploadId') IS NULL
BEGIN
    ALTER TABLE dbo.ProjectActualMonth ADD
        UploadId INT NULL CONSTRAINT FK_ProjectActualMonth_Upload FOREIGN KEY REFERENCES dbo.ActualCostUpload (Id);
END
GO

/* ---------------------------------------------------------------------
   3. TABLE dbo.ProjectActualItem  (detail per item barang/jasa; PRD 6.4)
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.ProjectActualItem', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProjectActualItem
    (
        Id           INT IDENTITY(1,1) NOT NULL,
        MonthId      INT            NOT NULL,
        LineNumber       INT            NOT NULL,
        ItemType     VARCHAR(10)    NOT NULL,        -- GOODS | SERVICE
        ItemName     NVARCHAR(200)  NOT NULL,
        Qty          DECIMAL(18, 4) NOT NULL,
        Unit         NVARCHAR(30)   NOT NULL,
        UnitPrice    DECIMAL(18, 2) NOT NULL,
        Amount       DECIMAL(18, 2) NOT NULL,
        ReferenceNo  NVARCHAR(100)  NULL,            -- PO / GR / jurnal
        Notes        NVARCHAR(500)  NULL,
        CONSTRAINT PK_ProjectActualItem PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_ProjectActualItem_Month FOREIGN KEY (MonthId) REFERENCES dbo.ProjectActualMonth (Id),
        CONSTRAINT CK_ProjectActualItem_Type  CHECK (ItemType IN ('GOODS', 'SERVICE')),
        CONSTRAINT CK_ProjectActualItem_Qty   CHECK (Qty > 0),
        CONSTRAINT CK_ProjectActualItem_Price CHECK (UnitPrice > 0 AND Amount > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ProjectActualItem_Month' AND object_id = OBJECT_ID(N'dbo.ProjectActualItem'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_ProjectActualItem_Month ON dbo.ProjectActualItem (MonthId, LineNumber);
END
GO

/* ---------------------------------------------------------------------
   4. dbo.fn_User_CanSeeActualCost(@Username)  -> 1 baris bila boleh melihat detail actual cost (matriks 5.2)
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_User_CanSeeActualCost
(
    @Username NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP (1) 1 AS Allowed
    FROM   dbo.fn_User_Roles(@Username) r
    WHERE  r.RoleCode IN (N'civil', N'fat', N'gm', N'director', N'administrator')
);
GO

/* ---------------------------------------------------------------------
   5. usp_Request_RefreshCostStatus  (internal; dipanggil saat actual / estimasi disimpan; BR-69, BR-71)
      Tidak membuka transaksi sendiri (ikut transaksi pemanggil).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_RefreshCostStatus
    @Id        INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CoCode VARCHAR(10) = (SELECT r.CoCode FROM dbo.ProjectRequest r WHERE r.Id = @Id);

    DECLARE @Total DECIMAL(18, 2), @LastMonth DATE;
    SELECT  @Total = SUM(m.TotalAmount), @LastMonth = MAX(m.PeriodMonth)
    FROM    dbo.ProjectActualMonth m
    WHERE   m.RequestId = @Id;

    DECLARE @FirstEstMonth DATE = (SELECT MIN(e.PeriodMonth) FROM dbo.ProjectCostEstimate e WHERE e.RequestId = @Id);
    DECLARE @CompareTo DATE = CASE WHEN @FirstEstMonth IS NOT NULL AND (@LastMonth IS NULL OR @LastMonth < @FirstEstMonth)
                                   THEN @FirstEstMonth ELSE @LastMonth END;
    DECLARE @Estimate DECIMAL(18, 2) = (SELECT SUM(e.Amount) FROM dbo.ProjectCostEstimate e
                                        WHERE e.RequestId = @Id AND e.PeriodMonth <= @CompareTo);

    DECLARE @OnTrackMax DECIMAL(9, 2) = ISNULL((SELECT TOP (1) TRY_CAST(s.SettingValue AS DECIMAL(9, 2)) FROM dbo.AppSetting s
                                                WHERE s.SettingKey = 'COST_ONTRACK_MAX_PCT' AND s.CoCode IN (@CoCode, '*')
                                                ORDER BY CASE WHEN s.CoCode = @CoCode THEN 0 ELSE 1 END), 100);
    DECLARE @AtRiskMax DECIMAL(9, 2)  = ISNULL((SELECT TOP (1) TRY_CAST(s.SettingValue AS DECIMAL(9, 2)) FROM dbo.AppSetting s
                                                WHERE s.SettingKey = 'COST_ATRISK_MAX_PCT' AND s.CoCode IN (@CoCode, '*')
                                                ORDER BY CASE WHEN s.CoCode = @CoCode THEN 0 ELSE 1 END), 110);

    DECLARE @Ratio DECIMAL(9, 2) =
        CASE WHEN @LastMonth IS NULL OR ISNULL(@Estimate, 0) = 0 THEN NULL
             ELSE CAST(ROUND(@Total * 100.0 / @Estimate, 2) AS DECIMAL(9, 2)) END;

    DECLARE @Status VARCHAR(20) =
        CASE WHEN @LastMonth IS NULL                  THEN 'ON_TRACK'        -- belum ada bulan closing
             WHEN ISNULL(@Estimate, 0) = 0           THEN 'OVER_BUDGET'     -- ada actual tanpa estimasi sama sekali
             WHEN @Ratio <= @OnTrackMax              THEN 'ON_TRACK'
             WHEN @Ratio <= @AtRiskMax               THEN 'AT_RISK'
             ELSE 'OVER_BUDGET' END;

    UPDATE dbo.ProjectRequest
    SET    ActualCostTotal = @Total, CostRatioPercent = @Ratio, CostStatus = @Status,
           CostStatusAt = SYSDATETIME(), LastActualMonth = @LastMonth
    WHERE  Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   6. usp_Request_GetActualCost  (Details)
      Result 1: ringkasan (0 baris = tidak ada / di luar lingkup / purchasing-only)
      Result 2: per bulan: estimasi vs actual (hanya bila CanSeeDetail = 1)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetActualCost
    @RequestId INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Visible BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))
             THEN 1 ELSE 0 END;
    DECLARE @CanSeeDetail BIT = CASE WHEN @Visible = 1 AND EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username)) THEN 1 ELSE 0 END;

    SELECT  r.Id AS RequestId, r.Status, r.PlanCost, r.ActualCostTotal, r.CostRatioPercent, r.CostStatus, r.CostStatusAt,
            r.LastActualMonth, r.ScheduleStatus, r.OverallStatus,
            DATEFROMPARTS(YEAR(ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)),
                          MONTH(ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)), 1) AS FirstMonth,
            DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1) AS CurrentMonth,
            @CanSeeDetail AS CanSeeDetail
    FROM    dbo.ProjectRequest r
    WHERE   r.Id = @RequestId AND @Visible = 1;

    SELECT  ISNULL(e.PeriodMonth, m.PeriodMonth) AS PeriodMonth,
            ISNULL(e.Amount, 0) AS EstimateAmount,
            ISNULL(m.TotalAmount, 0) AS ActualAmount,
            ISNULL(m.ItemCount, 0) AS ItemCount,
            m.Source, m.UpdatedAt, m.UpdatedBy, m.CreatedAt, m.CreatedBy,
            CAST(CASE WHEN m.Id IS NULL THEN 0 ELSE 1 END AS BIT) AS HasActual
    FROM    (SELECT * FROM dbo.ProjectCostEstimate WHERE RequestId = @RequestId) e
            FULL OUTER JOIN (SELECT * FROM dbo.ProjectActualMonth WHERE RequestId = @RequestId) m
                ON m.PeriodMonth = e.PeriodMonth
    WHERE   @CanSeeDetail = 1
    ORDER BY ISNULL(e.PeriodMonth, m.PeriodMonth);
END
GO

/* ---------------------------------------------------------------------
   7. usp_Request_GetActualMonth  (form / detail satu bulan; hanya role yang boleh melihat detail)
      Result 1: header bulan (0 baris bila tidak berhak) · Result 2: item
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_GetActualMonth
    @RequestId INT,
    @Month     DATE,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PeriodMonth DATE = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1);
    DECLARE @CanSee BIT =
        CASE WHEN EXISTS (SELECT 1 FROM dbo.ProjectRequest r
                          WHERE  r.Id = @RequestId
                            AND  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID))
              AND NOT EXISTS (SELECT 1 FROM dbo.fn_User_OutsourceOnly(@Username))
              AND EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username))
             THEN 1 ELSE 0 END;

    DECLARE @MonthId INT = (SELECT m.Id FROM dbo.ProjectActualMonth m WHERE m.RequestId = @RequestId AND m.PeriodMonth = @PeriodMonth);

    SELECT  @PeriodMonth AS PeriodMonth,
            (SELECT e.Amount FROM dbo.ProjectCostEstimate e WHERE e.RequestId = @RequestId AND e.PeriodMonth = @PeriodMonth) AS EstimateAmount,
            m.TotalAmount, m.ItemCount, m.Source, m.AttachmentId, m.UploadId, m.Remarks, m.CreatedAt, m.CreatedBy, m.UpdatedAt, m.UpdatedBy,
            CAST(CASE WHEN @MonthId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsSaved
    FROM    (SELECT 1 AS x) d
            LEFT JOIN dbo.ProjectActualMonth m ON m.Id = @MonthId
    WHERE   @CanSee = 1;

    SELECT  i.Id, i.LineNumber, i.ItemType, i.ItemName, i.Qty, i.Unit, i.UnitPrice, i.Amount, i.ReferenceNo, i.Notes
    FROM    dbo.ProjectActualItem i
    WHERE   i.MonthId = @MonthId AND @CanSee = 1
    ORDER BY i.LineNumber, i.Id;
END
GO

/* ---------------------------------------------------------------------
   8. usp_Request_SaveActualMonth  (civil; IN_PROGRESS / BAPP_REVIEW; ganti seluruh item satu bulan)
      @ItemsJson: [{"type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":650000,
                    "ref":"PO-123","notes":null}, ...]   '[]' = hapus actual bulan itu
      @Source   : MANUAL (T5-2) | EXCEL (T5-3, dengan @UploadId; dipanggil usp_ActualUpload_Import)
      Hasil: SELECT ringkasan biaya terbaru.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Request_SaveActualMonth
    @Id            INT,
    @Username      NVARCHAR(100),
    @Month         DATE,
    @ItemsJson     NVARCHAR(MAX),
    @Remarks       NVARCHAR(MAX) = NULL,
    @Source        VARCHAR(10)   = 'MANUAL',
    @AttachmentId  INT           = NULL,
    @UploadId      INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');
    SET @Source  = UPPER(LTRIM(RTRIM(ISNULL(@Source, 'MANUAL'))));

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can enter actual cost.', 1;
    IF @Month IS NULL
        THROW 50072, N'Month is required.', 1;
    IF @Source NOT IN ('MANUAL', 'EXCEL')
        THROW 50072, N'Source is invalid.', 1;
    IF LEN(@Remarks) > 1000
        THROW 50072, N'Remarks must be at most 1000 characters.', 1;
    IF ISJSON(ISNULL(@ItemsJson, N'[]')) = 0
        THROW 50072, N'Actual cost data is invalid.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @Today DATE = CAST(@Now AS DATE);
    DECLARE @PeriodMonth DATE = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1);
    DECLARE @Msg NVARCHAR(2048);

    DECLARE @Items TABLE
    (
        Seq         INT            NOT NULL PRIMARY KEY,
        ItemType    VARCHAR(20)    NULL,
        ItemName    NVARCHAR(400)  NULL,
        Qty         DECIMAL(18, 4) NULL,
        Unit        NVARCHAR(60)   NULL,
        UnitPrice   DECIMAL(18, 2) NULL,
        Amount      DECIMAL(18, 2) NULL,
        ReferenceNo NVARCHAR(200)  NULL,
        Notes       NVARCHAR(1000) NULL
    );

    INSERT INTO @Items (Seq, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo, Notes)
    SELECT  CAST(j.[key] AS INT) + 1,
            UPPER(LTRIM(RTRIM(x.[type]))), NULLIF(LTRIM(RTRIM(x.[name])), N''), x.qty, NULLIF(LTRIM(RTRIM(x.unit)), N''),
            x.price, x.amount, NULLIF(LTRIM(RTRIM(x.[ref])), N''), NULLIF(LTRIM(RTRIM(x.notes)), N'')
    FROM    OPENJSON(ISNULL(@ItemsJson, N'[]')) j
            CROSS APPLY OPENJSON(j.[value])
            WITH ([type] VARCHAR(20) '$.type', [name] NVARCHAR(400) '$.name', qty DECIMAL(18, 4) '$.qty',
                  unit NVARCHAR(60) '$.unit', price DECIMAL(18, 2) '$.price', amount DECIMAL(18, 2) '$.amount',
                  [ref] NVARCHAR(200) '$.ref', notes NVARCHAR(1000) '$.notes') x;

    IF (SELECT COUNT(*) FROM @Items) > 500
        THROW 50072, N'At most 500 items per month are allowed.', 1;

    SELECT TOP (1) @Msg = N'Item row ' + CAST(i.Seq AS NVARCHAR(10)) + N': ' +
           CASE WHEN ISNULL(i.ItemType, '') NOT IN ('GOODS', 'SERVICE') THEN N'type must be Goods or Service.'
                WHEN i.ItemName IS NULL                          THEN N'item name is required.'
                WHEN LEN(i.ItemName) > 200                       THEN N'item name must be at most 200 characters.'
                WHEN i.Qty IS NULL OR i.Qty <= 0                 THEN N'quantity must be greater than 0.'
                WHEN i.Unit IS NULL                              THEN N'unit is required.'
                WHEN LEN(i.Unit) > 30                            THEN N'unit must be at most 30 characters.'
                WHEN i.UnitPrice IS NULL OR i.UnitPrice <= 0     THEN N'unit price must be greater than 0.'
                WHEN i.Amount IS NULL OR i.Amount <= 0           THEN N'amount must be greater than 0.'
                WHEN ABS(i.Amount - ROUND(i.Qty * i.UnitPrice, 2)) > 1
                     THEN N'amount must equal quantity × unit price (' + FORMAT(ROUND(i.Qty * i.UnitPrice, 2), N'#,0.##', 'en-US') + N').'
                WHEN LEN(i.ReferenceNo) > 100                    THEN N'reference number must be at most 100 characters.'
                ELSE N'notes must be at most 500 characters.' END
    FROM   @Items i
    WHERE  ISNULL(i.ItemType, '') NOT IN ('GOODS', 'SERVICE')
       OR  i.ItemName IS NULL OR LEN(i.ItemName) > 200
       OR  i.Qty IS NULL OR i.Qty <= 0
       OR  i.Unit IS NULL OR LEN(i.Unit) > 30
       OR  i.UnitPrice IS NULL OR i.UnitPrice <= 0
       OR  i.Amount IS NULL OR i.Amount <= 0
       OR  ABS(i.Amount - ROUND(i.Qty * i.UnitPrice, 2)) > 1
       OR  LEN(i.ReferenceNo) > 100 OR LEN(i.Notes) > 500
    ORDER BY i.Seq;

    IF @Msg IS NOT NULL
        THROW 50072, @Msg, 1;

    DECLARE @Status VARCHAR(20), @FirstDate DATE;

    BEGIN TRANSACTION;

    SELECT  @Status = r.Status, @FirstDate = ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)
    FROM    dbo.ProjectRequest r WITH (UPDLOCK, ROWLOCK)
    WHERE   r.Id = @Id
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    IF @Status IS NULL
        THROW 50073, N'Request not found.', 1;
    IF @Status NOT IN ('IN_PROGRESS', 'BAPP_REVIEW')
        THROW 50074, N'Actual cost can only be entered while the project is in progress or in BAPP review.', 1;
    IF @FirstDate IS NOT NULL AND @PeriodMonth < DATEFROMPARTS(YEAR(@FirstDate), MONTH(@FirstDate), 1)
    BEGIN
        SET @Msg = N'The month is before the preparation start (' + FORMAT(@FirstDate, N'MMM yyyy', 'en-US') + N').';
        THROW 50072, @Msg, 1;
    END
    IF @PeriodMonth > DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1)
        THROW 50072, N'Actual cost cannot be entered for a future month.', 1;
    IF @AttachmentId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.RequestAttachment a WHERE a.Id = @AttachmentId AND a.RequestId = @Id)
        THROW 50072, N'The upload file is invalid.', 1;
    IF @UploadId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.ActualCostUpload u WHERE u.Id = @UploadId AND u.Status = 'PENDING')
        THROW 50072, N'The upload file is invalid or already processed.', 1;
    IF @Source = 'EXCEL' AND @UploadId IS NULL
        THROW 50072, N'The upload file is required for Excel source.', 1;

    DECLARE @MonthId INT = (SELECT m.Id FROM dbo.ProjectActualMonth m WITH (UPDLOCK, HOLDLOCK)
                            WHERE m.RequestId = @Id AND m.PeriodMonth = @PeriodMonth);
    DECLARE @Count INT = (SELECT COUNT(*) FROM @Items);
    DECLARE @Total DECIMAL(18, 2) = ISNULL((SELECT SUM(Amount) FROM @Items), 0);

    IF @Count = 0 AND @MonthId IS NULL
        THROW 50072, N'Please add at least one item.', 1;

    IF @MonthId IS NOT NULL
        DELETE FROM dbo.ProjectActualItem WHERE MonthId = @MonthId;

    IF @Count = 0
    BEGIN
        -- Hapus actual bulan ini
        DELETE FROM dbo.ProjectActualMonth WHERE Id = @MonthId;
    END
    ELSE
    BEGIN
        IF @MonthId IS NULL
        BEGIN
            INSERT INTO dbo.ProjectActualMonth
                (RequestId, PeriodMonth, TotalAmount, ItemCount, Source, AttachmentId, UploadId, Remarks, CreatedAt, CreatedBy)
            VALUES (@Id, @PeriodMonth, @Total, @Count, @Source, @AttachmentId, @UploadId, @Remarks, @Now, @Username);
            SET @MonthId = CAST(SCOPE_IDENTITY() AS INT);
        END
        ELSE
            UPDATE dbo.ProjectActualMonth
            SET    TotalAmount = @Total, ItemCount = @Count, Source = @Source, AttachmentId = @AttachmentId,
                   UploadId = @UploadId, Remarks = @Remarks, UpdatedAt = @Now, UpdatedBy = @Username
            WHERE  Id = @MonthId;

        INSERT INTO dbo.ProjectActualItem (MonthId, LineNumber, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo, Notes)
        SELECT @MonthId, i.Seq, i.ItemType, i.ItemName, i.Qty, i.Unit, i.UnitPrice, i.Amount, i.ReferenceNo, i.Notes
        FROM   @Items i;
    END

    INSERT INTO dbo.ApprovalHistory (RequestId, Action, FromStatus, ToStatus, Remarks, ActionBy, ActionAt)
    VALUES (@Id, 'ACTUAL_COST', @Status, @Status,
            LEFT(N'Actual cost ' + FORMAT(@PeriodMonth, N'MMM yyyy', 'en-US')
                 + CASE WHEN @Count = 0 THEN N' removed'
                        ELSE N': IDR ' + FORMAT(@Total, N'#,0.##', 'en-US') + N' (' + CAST(@Count AS NVARCHAR(10)) + N' items, '
                             + LOWER(@Source) + N')' END
                 + ISNULL(N' · ' + @Remarks, N''), 1000),
            @Username, @Now);

    UPDATE dbo.ProjectRequest SET UpdatedAt = @Now, UpdatedBy = @Username WHERE Id = @Id;

    EXEC dbo.usp_Request_RefreshCostStatus @Id = @Id, @Username = @Username;

    COMMIT TRANSACTION;

    SELECT  r.ActualCostTotal, r.CostRatioPercent, r.CostStatus, r.ScheduleStatus, r.OverallStatus, r.LastActualMonth
    FROM    dbo.ProjectRequest r
    WHERE   r.Id = @Id;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: Unit.sql, RequestActualCost.sql, lalu RequestSchedule.sql dijalankan ulang.
   Contoh memakai request IN_PROGRESS hasil test T4-2/T5-1: PlanCost 10.000.000, estimasi Nov 2026 4.000.000 (atau
   3.000.000 setelah test 7 T4-2) dan Des 2026 sisanya; Preparation mulai Nov 2026. Sesuaikan angka.

   DECLARE @Req INT = 1008, @Civil NVARCHAR(100) = N'users1', @Other NVARCHAR(100) = N'hdahlia';
   DECLARE @J NVARCHAR(MAX);

   -- 1) Bukan civil -> 50075; bulan depan -> 50072; amount tidak sama qty x harga -> 50072; jenis salah -> 50072
   BEGIN TRY EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Other, @Month = '2026-11-01', @ItemsJson = N'[]';
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1a expect 50075' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":650000}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-12-01', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1b expect 50072 (future month)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":600000}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-01', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1c expect 50072 (amount)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   SET @J = N'[{"type":"OTHER","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":650000}]';
   BEGIN TRY EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-01', @ItemsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '1d expect 50072 (type)' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 2) Nov 2026: 2 item, total 3.500.000 vs estimasi Nov (mis. 3.000.000) -> rasio 116.67 -> OVER_BUDGET
   SET @J = N'[{"type":"GOODS","name":"Cement","qty":20,"unit":"sak","price":75000,"amount":1500000,"ref":"PO-001"},'
          + N'{"type":"SERVICE","name":"Labor","qty":1,"unit":"ls","price":2000000,"amount":2000000}]';
   EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-15', @ItemsJson = @J, @Remarks = N'November closing';

   -- 3) Simpan ulang Nov (menimpa): 1 item 3.200.000 -> rasio 106.67 -> AT_RISK; OverallStatus ikut (terburuk jadwal/biaya)
   SET @J = N'[{"type":"SERVICE","name":"Labor","qty":1,"unit":"ls","price":3200000,"amount":3200000}]';
   EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-01', @ItemsJson = @J;
   EXEC dbo.usp_Request_GetActualCost  @RequestId = @Req, @Username = @Civil;
   EXEC dbo.usp_Request_GetActualMonth @RequestId = @Req, @Month = '2026-11-01', @Username = @Civil;

   -- 4) User tanpa hak detail (mis. adm/kabag departemen itu): ringkasan ada, result 2 kosong
   EXEC dbo.usp_Request_GetActualCost @RequestId = @Req, @Username = N'<user adm/kabag departemen request>';

   -- 5) Hapus actual Nov ('[]') -> CostStatus ON_TRACK, LastActualMonth NULL; riwayat ACTUAL_COST "removed"
   EXEC dbo.usp_Request_SaveActualMonth @Id = @Req, @Username = @Civil, @Month = '2026-11-01', @ItemsJson = N'[]';
   SELECT TOP (3) Action, Remarks, ActionAt FROM dbo.ApprovalHistory WHERE RequestId = @Req ORDER BY Id DESC;

   -- 6) Master Unit untuk saran satuan
   EXEC dbo.usp_Unit_GetActive;
   ===================================================================== */
