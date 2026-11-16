/* =====================================================================
   RequestActualUpload.sql  -  Upload actual cost via template Excel (T5-3; PRD 6.4, BR-18, BR-19, BR-67)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER), compat level >= 130 (OPENJSON).
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST SETELAH RequestActualCost.sql
             (jalankan ulang: tabel ActualCostUpload, kolom ProjectActualMonth.UploadId, parameter @UploadId).
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Alur (Keputusan 16-11-2026, lihat docs/PRD-log.md):
     1. Civil mengupload SATU file untuk banyak project/bulan di halaman pusat (Cost Management > Actual Cost Upload).
        Aplikasi (ClosedXML) membaca baris -> JSON -> usp_ActualUpload_Validate (tanpa menulis data).
     2. Ada error di baris mana pun -> tidak ada yang disimpan (all or nothing); daftar error + nomor baris ditampilkan.
     3. Valid -> file disimpan ke arsip + baris ActualCostUpload status PENDING (usp_ActualUpload_Create),
        preview per project + bulan (item, total, bulan yang akan ditimpa).
     4. Civil konfirmasi -> usp_ActualUpload_Import: validasi ulang, lalu per project + bulan memanggil
        usp_Request_SaveActualMonth (Source EXCEL, menimpa bulan itu, BR-19), status IMPORTED. Satu transaksi.
        Batal -> usp_ActualUpload_Cancel (CANCELLED; file tetap diarsipkan).
   Kolom template (6.4): Request No · Month (yyyy-MM) · Type (Goods/Service) · Item name · Qty · Unit · Unit price ·
                         Amount · Reference no. · Notes.  Request No = nomor TERKINI.
   Error   : 50072 = Input tidak valid / file berubah / sudah diproses
             50073 = Upload tidak ditemukan
             50075 = Role user tidak sesuai (civil)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. usp_ActualUpload_CheckRows  (internal)
      Memeriksa tabel sementara #UploadRows milik pemanggil; mengisi RequestId dan Error per baris.
      #UploadRows: RowNo, RequestNo, PeriodMonth, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo,
                   Notes, RequestId, Error.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_CheckRows
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @CurrentMonth DATE = DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1);

    -- Request (nomor terkini, dalam lingkup user)
    UPDATE u
    SET    u.RequestId = r.Id
    FROM   #UploadRows u
           JOIN dbo.ProjectRequest r ON r.RequestNo = u.RequestNo
    WHERE  EXISTS (SELECT 1 FROM dbo.fn_User_AllowedDepartments(@Username) f WHERE f.DepartmentID = r.DepartmentID);

    UPDATE u
    SET    u.Error = CASE
             WHEN u.RequestNo IS NULL THEN N'Request No is required.'
             WHEN u.RequestId IS NULL AND EXISTS (SELECT 1 FROM dbo.RequestNoHistory h WHERE h.RequestNo = u.RequestNo)
                  THEN N'Request No ' + u.RequestNo + N' is an old number; use the current number '
                       + ISNULL((SELECT TOP (1) r.RequestNo FROM dbo.RequestNoHistory h JOIN dbo.ProjectRequest r ON r.Id = h.RequestId
                                 WHERE h.RequestNo = u.RequestNo), N'') + N'.'
             WHEN u.RequestId IS NULL THEN N'Request No ' + u.RequestNo + N' was not found.'
             WHEN r.Status NOT IN ('IN_PROGRESS', 'BAPP_REVIEW')
                  THEN N'Request ' + u.RequestNo + N' is not in progress or BAPP review.'
             WHEN u.PeriodMonth IS NULL THEN N'Month is required (yyyy-MM).'
             WHEN u.PeriodMonth > @CurrentMonth THEN N'Month cannot be in the future.'
             WHEN ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate) IS NOT NULL
                  AND u.PeriodMonth < DATEFROMPARTS(YEAR(ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)),
                                                    MONTH(ISNULL(CAST(r.PreparationStartAt AS DATE), r.ProjectStartDate)), 1)
                  THEN N'Month is before the preparation start of ' + u.RequestNo + N'.'
             WHEN ISNULL(u.ItemType, '') NOT IN ('GOODS', 'SERVICE') THEN N'Type must be Goods or Service.'
             WHEN u.ItemName IS NULL THEN N'Item name is required.'
             WHEN LEN(u.ItemName) > 200 THEN N'Item name must be at most 200 characters.'
             WHEN u.Qty IS NULL OR u.Qty <= 0 THEN N'Qty must be greater than 0.'
             WHEN u.Unit IS NULL THEN N'Unit is required.'
             WHEN LEN(u.Unit) > 30 THEN N'Unit must be at most 30 characters.'
             WHEN u.UnitPrice IS NULL OR u.UnitPrice <= 0 THEN N'Unit price must be greater than 0.'
             WHEN u.Amount IS NULL OR u.Amount <= 0 THEN N'Amount must be greater than 0.'
             WHEN ABS(u.Amount - ROUND(u.Qty * u.UnitPrice, 2)) > 1
                  THEN N'Amount must equal Qty × Unit price (' + FORMAT(ROUND(u.Qty * u.UnitPrice, 2), N'#,0.##', 'en-US') + N').'
             WHEN LEN(u.ReferenceNo) > 100 THEN N'Reference no. must be at most 100 characters.'
             WHEN LEN(u.Notes) > 500 THEN N'Notes must be at most 500 characters.'
             ELSE u.Error END
    FROM   #UploadRows u
           LEFT JOIN dbo.ProjectRequest r ON r.Id = u.RequestId;

    -- Batas item per project + bulan (sama dengan input manual)
    UPDATE u
    SET    u.Error = N'More than 500 items for ' + u.RequestNo + N' in ' + FORMAT(u.PeriodMonth, N'MMM yyyy', 'en-US') + N'.'
    FROM   #UploadRows u
    WHERE  u.Error IS NULL
      AND  (SELECT COUNT(*) FROM #UploadRows x WHERE x.RequestId = u.RequestId AND x.PeriodMonth = u.PeriodMonth) > 500;
END
GO

/* ---------------------------------------------------------------------
   2. usp_ActualUpload_Validate  (preview; tidak menulis data)
      @RowsJson: [{"row":2,"requestNo":"PM-CPX-11-26-002","month":"2026-11-01","type":"GOODS","name":"Cement",
                   "qty":10,"unit":"sak","price":65000,"amount":650000,"ref":"PO-1","notes":null}, ...]
      Result 1: error (RowNo, Message) · Result 2: ringkasan per project + bulan (hanya bila tanpa error).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_Validate
    @Username  NVARCHAR(100),
    @RowsJson  NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can upload actual cost.', 1;
    IF ISJSON(ISNULL(@RowsJson, N'[]')) = 0
        THROW 50072, N'Upload data is invalid.', 1;

    CREATE TABLE #UploadRows
    (
        RowNo        INT            NOT NULL PRIMARY KEY,
        RequestNo    VARCHAR(40)    NULL,
        PeriodMonth  DATE           NULL,
        ItemType     VARCHAR(20)    NULL,
        ItemName     NVARCHAR(400)  NULL,
        Qty          DECIMAL(18, 4) NULL,
        Unit         NVARCHAR(60)   NULL,
        UnitPrice    DECIMAL(18, 2) NULL,
        Amount       DECIMAL(18, 2) NULL,
        ReferenceNo  NVARCHAR(200)  NULL,
        Notes        NVARCHAR(1000) NULL,
        RequestId    INT            NULL,
        Error        NVARCHAR(500)  NULL
    );

    INSERT INTO #UploadRows (RowNo, RequestNo, PeriodMonth, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo, Notes)
    SELECT  x.[row], NULLIF(UPPER(LTRIM(RTRIM(x.requestNo))), ''),
            CASE WHEN x.[month] IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(x.[month]), MONTH(x.[month]), 1) END,
            UPPER(LTRIM(RTRIM(x.[type]))), NULLIF(LTRIM(RTRIM(x.[name])), N''), x.qty, NULLIF(LTRIM(RTRIM(x.unit)), N''),
            x.price, x.amount, NULLIF(LTRIM(RTRIM(x.[ref])), N''), NULLIF(LTRIM(RTRIM(x.notes)), N'')
    FROM    OPENJSON(ISNULL(@RowsJson, N'[]'))
            WITH ([row] INT '$.row', requestNo VARCHAR(40) '$.requestNo', [month] DATE '$.month', [type] VARCHAR(20) '$.type',
                  [name] NVARCHAR(400) '$.name', qty DECIMAL(18, 4) '$.qty', unit NVARCHAR(60) '$.unit',
                  price DECIMAL(18, 2) '$.price', amount DECIMAL(18, 2) '$.amount', [ref] NVARCHAR(200) '$.ref',
                  notes NVARCHAR(1000) '$.notes') x;

    EXEC dbo.usp_ActualUpload_CheckRows @Username = @Username;

    SELECT RowNo, Error AS Message FROM #UploadRows WHERE Error IS NOT NULL ORDER BY RowNo;

    SELECT  g.RequestId, r.RequestNo, r.Title, r.Status, r.CoCode, g.PeriodMonth, g.ItemCount, g.TotalAmount,
            m.TotalAmount AS ExistingAmount, m.Source AS ExistingSource,
            CAST(CASE WHEN m.Id IS NULL THEN 0 ELSE 1 END AS BIT) AS WillReplace,
            e.Amount AS EstimateAmount
    FROM    (SELECT RequestId, PeriodMonth, COUNT(*) AS ItemCount, SUM(Amount) AS TotalAmount
             FROM #UploadRows GROUP BY RequestId, PeriodMonth) g
            JOIN dbo.ProjectRequest r ON r.Id = g.RequestId
            LEFT JOIN dbo.ProjectActualMonth m ON m.RequestId = g.RequestId AND m.PeriodMonth = g.PeriodMonth
            LEFT JOIN dbo.ProjectCostEstimate e ON e.RequestId = g.RequestId AND e.PeriodMonth = g.PeriodMonth
    WHERE   NOT EXISTS (SELECT 1 FROM #UploadRows WHERE Error IS NOT NULL)
    ORDER BY r.RequestNo, g.PeriodMonth;
END
GO

/* ---------------------------------------------------------------------
   3. usp_ActualUpload_Create  (arsip file yang lolos validasi; status PENDING)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_Create
    @Username          NVARCHAR(100),
    @OriginalFileName  NVARCHAR(260),
    @RelativePath      NVARCHAR(400),
    @ContentType       VARCHAR(100),
    @FileSizeBytes     BIGINT,
    @RowTotal          INT,
    @GroupTotal        INT,
    @TotalAmount       DECIMAL(18, 2),
    @NewId             INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can upload actual cost.', 1;
    IF NULLIF(LTRIM(RTRIM(@OriginalFileName)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@RelativePath)), N'') IS NULL
       OR ISNULL(@FileSizeBytes, 0) <= 0
        THROW 50072, N'Upload file is invalid.', 1;

    INSERT INTO dbo.ActualCostUpload
        (OriginalFileName, RelativePath, ContentType, FileSizeBytes, RowTotal, GroupTotal, TotalAmount, CreatedBy)
    VALUES (@OriginalFileName, @RelativePath, @ContentType, @FileSizeBytes, ISNULL(@RowTotal, 0), ISNULL(@GroupTotal, 0),
            ISNULL(@TotalAmount, 0), @Username);

    SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
END
GO

/* ---------------------------------------------------------------------
   4. usp_ActualUpload_Import  (konfirmasi; @RowsJson = isi file yang sama, dibaca ulang aplikasi)
      All or nothing: validasi ulang, lalu tiap project + bulan -> usp_Request_SaveActualMonth (EXCEL), satu transaksi.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_Import
    @UploadId  INT,
    @Username  NVARCHAR(100),
    @RowsJson  NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.fn_User_Roles(@Username) r WHERE r.RoleCode = N'civil')
        THROW 50075, N'Only Civil can upload actual cost.', 1;
    IF ISJSON(ISNULL(@RowsJson, N'[]')) = 0
        THROW 50072, N'Upload data is invalid.', 1;

    CREATE TABLE #UploadRows
    (
        RowNo        INT            NOT NULL PRIMARY KEY,
        RequestNo    VARCHAR(40)    NULL,
        PeriodMonth  DATE           NULL,
        ItemType     VARCHAR(20)    NULL,
        ItemName     NVARCHAR(400)  NULL,
        Qty          DECIMAL(18, 4) NULL,
        Unit         NVARCHAR(60)   NULL,
        UnitPrice    DECIMAL(18, 2) NULL,
        Amount       DECIMAL(18, 2) NULL,
        ReferenceNo  NVARCHAR(200)  NULL,
        Notes        NVARCHAR(1000) NULL,
        RequestId    INT            NULL,
        Error        NVARCHAR(500)  NULL
    );

    INSERT INTO #UploadRows (RowNo, RequestNo, PeriodMonth, ItemType, ItemName, Qty, Unit, UnitPrice, Amount, ReferenceNo, Notes)
    SELECT  x.[row], NULLIF(UPPER(LTRIM(RTRIM(x.requestNo))), ''),
            CASE WHEN x.[month] IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(x.[month]), MONTH(x.[month]), 1) END,
            UPPER(LTRIM(RTRIM(x.[type]))), NULLIF(LTRIM(RTRIM(x.[name])), N''), x.qty, NULLIF(LTRIM(RTRIM(x.unit)), N''),
            x.price, x.amount, NULLIF(LTRIM(RTRIM(x.[ref])), N''), NULLIF(LTRIM(RTRIM(x.notes)), N'')
    FROM    OPENJSON(ISNULL(@RowsJson, N'[]'))
            WITH ([row] INT '$.row', requestNo VARCHAR(40) '$.requestNo', [month] DATE '$.month', [type] VARCHAR(20) '$.type',
                  [name] NVARCHAR(400) '$.name', qty DECIMAL(18, 4) '$.qty', unit NVARCHAR(60) '$.unit',
                  price DECIMAL(18, 2) '$.price', amount DECIMAL(18, 2) '$.amount', [ref] NVARCHAR(200) '$.ref',
                  notes NVARCHAR(1000) '$.notes') x;

    IF NOT EXISTS (SELECT 1 FROM #UploadRows)
        THROW 50072, N'The file has no data rows.', 1;

    EXEC dbo.usp_ActualUpload_CheckRows @Username = @Username;

    IF EXISTS (SELECT 1 FROM #UploadRows WHERE Error IS NOT NULL)
        THROW 50072, N'The file is no longer valid (data changed since the preview). Please upload it again.', 1;

    DECLARE @Now DATETIME2(3) = SYSDATETIME();
    DECLARE @FileName NVARCHAR(260);

    BEGIN TRANSACTION;

    SELECT @FileName = u.OriginalFileName
    FROM   dbo.ActualCostUpload u WITH (UPDLOCK, ROWLOCK)
    WHERE  u.Id = @UploadId AND u.CreatedBy = @Username;

    IF @FileName IS NULL
        THROW 50073, N'Upload not found.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ActualCostUpload WHERE Id = @UploadId AND Status = 'PENDING')
        THROW 50072, N'This upload has already been processed.', 1;

    DECLARE @ReqId INT, @Month DATE, @Json NVARCHAR(MAX), @Remark NVARCHAR(1000) = LEFT(N'Excel upload: ' + @FileName, 1000);

    DECLARE grp CURSOR LOCAL FAST_FORWARD FOR
        SELECT DISTINCT RequestId, PeriodMonth FROM #UploadRows ORDER BY RequestId, PeriodMonth;
    OPEN grp;
    FETCH NEXT FROM grp INTO @ReqId, @Month;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Json =
        (
            SELECT  ItemType AS [type], ItemName AS [name], Qty AS qty, Unit AS unit, UnitPrice AS price, Amount AS amount,
                    ReferenceNo AS [ref], Notes AS notes
            FROM    #UploadRows
            WHERE   RequestId = @ReqId AND PeriodMonth = @Month
            ORDER BY RowNo
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );

        -- Simpan seperti input manual (menimpa bulan, riwayat, status biaya); hasil SELECT-nya diabaikan pemanggil
        EXEC dbo.usp_Request_SaveActualMonth @Id = @ReqId, @Username = @Username, @Month = @Month, @ItemsJson = @Json,
             @Remarks = @Remark, @Source = 'EXCEL', @UploadId = @UploadId;

        FETCH NEXT FROM grp INTO @ReqId, @Month;
    END
    CLOSE grp;
    DEALLOCATE grp;

    UPDATE dbo.ActualCostUpload
    SET    Status = 'IMPORTED', ProcessedAt = @Now, ProcessedBy = @Username
    WHERE  Id = @UploadId;

    COMMIT TRANSACTION;
END
GO

/* ---------------------------------------------------------------------
   5. usp_ActualUpload_Cancel  (batal setelah preview; file tetap diarsipkan)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_Cancel
    @UploadId  INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.ActualCostUpload
    SET    Status = 'CANCELLED', ProcessedAt = SYSDATETIME(), ProcessedBy = @Username
    WHERE  Id = @UploadId AND CreatedBy = @Username AND Status = 'PENDING';

    IF @@ROWCOUNT = 0
        THROW 50072, N'This upload was not found or has already been processed.', 1;
END
GO

/* ---------------------------------------------------------------------
   6. usp_ActualUpload_GetPaged  (riwayat upload; civil, fat, gm, director, administrator)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_GetPaged
    @Username    NVARCHAR(100),
    @PageNumber  INT = 1,
    @PageSize    INT = 10,
    @TotalCount  INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 10 WHEN @PageSize > 100 THEN 100 ELSE @PageSize END;

    DECLARE @CanSee BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username)) THEN 1 ELSE 0 END;

    SELECT @TotalCount = COUNT(*) FROM dbo.ActualCostUpload WHERE @CanSee = 1;

    SELECT  u.Id, u.OriginalFileName, u.FileSizeBytes, u.RowTotal, u.GroupTotal, u.TotalAmount, u.Status,
            u.CreatedAt, u.CreatedBy, u.ProcessedAt, u.ProcessedBy
    FROM    dbo.ActualCostUpload u
    WHERE   @CanSee = 1
    ORDER BY u.CreatedAt DESC, u.Id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO

/* ---------------------------------------------------------------------
   7. usp_ActualUpload_GetById  (download arsip / konfirmasi; 0 baris bila tidak berhak)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_ActualUpload_GetById
    @UploadId  INT,
    @Username  NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  u.Id, u.OriginalFileName, u.RelativePath, u.ContentType, u.FileSizeBytes, u.RowTotal, u.GroupTotal,
            u.TotalAmount, u.Status, u.CreatedAt, u.CreatedBy, u.ProcessedAt, u.ProcessedBy
    FROM    dbo.ActualCostUpload u
    WHERE   u.Id = @UploadId
      AND   EXISTS (SELECT 1 FROM dbo.fn_User_CanSeeActualCost(@Username));
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev; ganti <...> dengan data nyata)
   Kasus yang diharapkan error dibungkus TRY/CATCH (CATCH wajib ROLLBACK, lihat RequestApproval.sql).
   Prasyarat: RequestActualCost.sql dijalankan ulang, lalu file ini. Ada request IN_PROGRESS (mis. hasil test T4-2).

   DECLARE @Civil NVARCHAR(100) = N'users1', @No VARCHAR(40) = 'IT-OPX-11-26-002',
           @J NVARCHAR(MAX), @UploadId INT;

   -- 1) Validasi: baris salah -> result 1 berisi error per baris, result 2 kosong
   SET @J = N'[{"row":2,"requestNo":"' + @No + N'","month":"2026-11-01","type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":600000},'
          + N'{"row":3,"requestNo":"XX-OPX-01-26-999","month":"2026-11-01","type":"SERVICE","name":"Labor","qty":1,"unit":"ls","price":100,"amount":100},'
          + N'{"row":4,"requestNo":"' + @No + N'","month":"2027-01-01","type":"OTHER","name":"X","qty":1,"unit":"ls","price":1,"amount":1}]';
   EXEC dbo.usp_ActualUpload_Validate @Username = @Civil, @RowsJson = @J;      -- baris 2 amount, 3 not found, 4 future month

   -- 2) Validasi file benar: 2 baris November untuk request yang sama
   SET @J = N'[{"row":2,"requestNo":"' + @No + N'","month":"2026-11-01","type":"GOODS","name":"Cement","qty":10,"unit":"sak","price":65000,"amount":650000,"ref":"PO-9"},'
          + N'{"row":3,"requestNo":"' + @No + N'","month":"2026-11-01","type":"SERVICE","name":"Labor","qty":1,"unit":"ls","price":1000000,"amount":1000000}]';
   EXEC dbo.usp_ActualUpload_Validate @Username = @Civil, @RowsJson = @J;      -- result 2: 1 grup Nov, 2 item, 1.650.000, WillReplace bila sudah ada

   -- 3) Arsip (PENDING) lalu import -> bulan Nov diganti (Source EXCEL, UploadId), status IMPORTED, riwayat ACTUAL_COST
   EXEC dbo.usp_ActualUpload_Create @Username = @Civil, @OriginalFileName = N'actual-nov.xlsx', @RelativePath = N'ActualCost\2026\test.xlsx',
        @ContentType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', @FileSizeBytes = 1024,
        @RowTotal = 2, @GroupTotal = 1, @TotalAmount = 1650000, @NewId = @UploadId OUTPUT;
   EXEC dbo.usp_ActualUpload_Import @UploadId = @UploadId, @Username = @Civil, @RowsJson = @J;
   SELECT * FROM dbo.ActualCostUpload WHERE Id = @UploadId;
   SELECT m.PeriodMonth, m.TotalAmount, m.ItemCount, m.Source, m.UploadId FROM dbo.ProjectActualMonth m
          JOIN dbo.ProjectRequest r ON r.Id = m.RequestId WHERE r.RequestNo = @No;

   -- 4) Import ulang upload yang sama -> 50072 (sudah diproses); cancel upload yang sudah IMPORTED -> 50072
   BEGIN TRY EXEC dbo.usp_ActualUpload_Import @UploadId = @UploadId, @Username = @Civil, @RowsJson = @J;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4a expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;
   BEGIN TRY EXEC dbo.usp_ActualUpload_Cancel @UploadId = @UploadId, @Username = @Civil;
   END TRY BEGIN CATCH IF @@TRANCOUNT > 0 ROLLBACK; SELECT '4b expect 50072' AS TestCase, ERROR_NUMBER() AS ErrNo, ERROR_MESSAGE() AS ErrMsg; END CATCH;

   -- 5) Riwayat upload
   DECLARE @T INT; EXEC dbo.usp_ActualUpload_GetPaged @Username = @Civil, @TotalCount = @T OUTPUT; SELECT @T AS TotalCount;
   ===================================================================== */
