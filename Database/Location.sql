/* =====================================================================
   Location.sql  -  Master data Lokasi / Area (T1; PRD MD-02, BR-61)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan : Lokasi per Company (CoCode). Tanpa kode; nama unik per Company.
             Seed MERGE hanya MENAMBAH nama yang belum ada (tidak menimpa perubahan).
             Soft delete lewat SetActive (tanpa Delete).
   Error   : 50011 = Nama lokasi duplikat (pada Company yang sama)
             50012 = Input wajib kosong / tidak valid
             50013 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.Location', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Location
    (
        Id         INT IDENTITY(1,1) NOT NULL,
        CoCode     VARCHAR(10)   NOT NULL,
        Name       NVARCHAR(100) NOT NULL,
        IsActive   BIT           NOT NULL CONSTRAINT DF_Location_IsActive  DEFAULT (1),
        CreatedAt  DATETIME2(3)  NOT NULL CONSTRAINT DF_Location_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy  NVARCHAR(100) NULL,
        UpdatedAt  DATETIME2(3)  NULL,
        UpdatedBy  NVARCHAR(100) NULL,
        CONSTRAINT PK_Location PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_Location_CoCode CHECK (CoCode IN ('ABL', 'NKM'))
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_Location_CoCode_Name' AND object_id = OBJECT_ID(N'dbo.Location'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_Location_CoCode_Name ON dbo.Location (CoCode, Name);
END
GO

/* ---------------------------------------------------------------------
   2. SEED (Company ABL; hanya menambah yang belum ada)
   --------------------------------------------------------------------- */
MERGE dbo.Location AS t
USING (VALUES
        (N'Main Office 1st floor'), (N'Main Office 2nd floor'), (N'HRGA'), (N'Interco Meeting Room'),
        (N'Pos 1 Security'), (N'Pos 2 Security'), (N'Pos 3 Security'), (N'Pos 4 Security'), (N'Pos 5 Security'),
        (N'Paper Raw Material'), (N'Purchasing Office'), (N'Warehouse & Logistic Office'),
        (N'Paper Finished Goods'), (N'Tissue Finished Goods'), (N'Canteen & Hall'), (N'Mess'),
        (N'Multi Purpose Hall'), (N'MO Office'), (N'Finishing Office'), (N'TPM Office'),
        (N'Converting Office'), (N'Cassie Meeting Room'), (N'Fabrication Area'), (N'Engineering Office'),
        (N'Heavy Equipment'), (N'Workshop'), (N'Elektrical Office'), (N'Parking Lot'),
        (N'Boiler'), (N'Reverse Osmosis'), (N'Utility Office'), (N'Fiber Storage'),
        (N'Tissue Raw Material'), (N'TPM Mill'), (N'PM Mill'), (N'Finishing Mill'),
        (N'Converting Mill'), (N'Water Treatment'), (N'Waste Pond'), (N'PM 3 Mill')
      ) AS s (Name)
   ON t.CoCode = 'ABL' AND t.Name = s.Name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (CoCode, Name, CreatedBy)
    VALUES ('ABL', s.Name, N'seed');
GO

/* ---------------------------------------------------------------------
   3. usp_Location_GetPaged
      Search (Name), filter Company dan status, sorting whitelist, paging.
      @SortBy  : Name | CoCode | CreatedAt   (default Name)
      @SortDir : ASC | DESC                  (default ASC)
      @TotalCount = total baris setelah filter (OUTPUT)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_GetPaged
    @CoCode      VARCHAR(10)   = NULL,
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Name',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @CoCode     = NULLIF(LTRIM(RTRIM(@CoCode)), N'');
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'Name', N'CoCode', N'CreatedAt') THEN @SortBy ELSE N'Name' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.Location
    WHERE (@CoCode   IS NULL OR CoCode = @CoCode)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Name LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, CoCode, Name, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Location
    WHERE (@CoCode   IS NULL OR CoCode = @CoCode)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Name LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        CASE WHEN @SortBy = N'CoCode'    AND @SortDir = N'ASC'  THEN CoCode    END ASC,
        CASE WHEN @SortBy = N'CoCode'    AND @SortDir = N'DESC' THEN CoCode    END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        Name ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   4. usp_Location_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, CoCode, Name, IsActive, CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.Location
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   5. usp_Location_Insert
      @NewId = Id baru (OUTPUT); @ActionBy = username pelaku (audit)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_Insert
    @CoCode    VARCHAR(10),
    @Name      NVARCHAR(100),
    @IsActive  BIT           = 1,
    @ActionBy  NVARCHAR(100) = NULL,
    @NewId     INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @CoCode = UPPER(LTRIM(RTRIM(@CoCode)));
    SET @Name   = LTRIM(RTRIM(@Name));

    IF ISNULL(@CoCode, '') NOT IN ('ABL', 'NKM') THROW 50012, N'Company is required (ABL or NKM).', 1;
    IF ISNULL(@Name, N'') = N''                  THROW 50012, N'Location name is required.', 1;

    BEGIN TRY
        INSERT INTO dbo.Location (CoCode, Name, IsActive, CreatedBy)
        VALUES (@CoCode, @Name, ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50011, N'Location name is already in use for this company.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   6. usp_Location_Update
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_Update
    @Id        INT,
    @CoCode    VARCHAR(10),
    @Name      NVARCHAR(100),
    @IsActive  BIT           = 1,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @CoCode = UPPER(LTRIM(RTRIM(@CoCode)));
    SET @Name   = LTRIM(RTRIM(@Name));

    IF ISNULL(@CoCode, '') NOT IN ('ABL', 'NKM') THROW 50012, N'Company is required (ABL or NKM).', 1;
    IF ISNULL(@Name, N'') = N''                  THROW 50012, N'Location name is required.', 1;

    BEGIN TRY
        UPDATE dbo.Location
        SET CoCode    = @CoCode,
            Name      = @Name,
            IsActive  = ISNULL(@IsActive, IsActive),
            UpdatedAt = SYSDATETIME(),
            UpdatedBy = @ActionBy
        WHERE Id = @Id;

        IF @@ROWCOUNT = 0
            THROW 50013, N'Location not found.', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50011, N'Location name is already in use for this company.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_Location_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Location_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Location
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50013, N'Location not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Seed: 40 baris Company ABL, semua aktif, CreatedBy = 'seed'
   SELECT COUNT(*) AS Jumlah FROM dbo.Location WHERE CoCode = 'ABL';   -- 40
   SELECT * FROM dbo.Location ORDER BY Name;

   -- 2) Insert (Company NKM) lalu duplikat -> error 50011
   DECLARE @NewId INT;
   EXEC dbo.usp_Location_Insert @CoCode = 'NKM', @Name = N'Gudang Uji', @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   SELECT @NewId AS NewId;
   EXEC dbo.usp_Location_Insert @CoCode = 'NKM', @Name = N'gudang uji';        -- 50011 (tidak peka huruf besar/kecil)
   EXEC dbo.usp_Location_Insert @CoCode = 'ABL', @Name = N'Gudang Uji';        -- boleh (Company berbeda)

   -- 3) Validasi -> error 50012
   EXEC dbo.usp_Location_Insert @CoCode = 'XYZ', @Name = N'A';
   EXEC dbo.usp_Location_Insert @CoCode = 'ABL', @Name = N'   ';

   -- 4) List: search, filter Company/status, sort, paging
   DECLARE @Total INT;
   EXEC dbo.usp_Location_GetPaged @CoCode = 'ABL', @Search = N'mill', @IsActive = 1,
        @SortBy = N'Name', @SortDir = N'DESC', @PageNumber = 1, @PageSize = 10, @TotalCount = @Total OUTPUT;
   SELECT @Total AS TotalCount;   -- 5 (TPM, PM, Finishing, Converting, PM 3 Mill)

   -- 5) Update, soft delete, get by id (UpdatedAt/UpdatedBy terisi)
   EXEC dbo.usp_Location_Update @Id = 1, @CoCode = 'ABL', @Name = N'Main Office 1st floor', @ActionBy = N'uji';
   EXEC dbo.usp_Location_SetActive @Id = 1, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_Location_GetById @Id = 1;
   EXEC dbo.usp_Location_SetActive @Id = 1, @IsActive = 1, @ActionBy = N'uji';   -- kembalikan

   -- 6) Update nama menjadi nama lokasi lain pada Company sama -> 50011; Id tidak ada -> 50013
   EXEC dbo.usp_Location_Update @Id = 1, @CoCode = 'ABL', @Name = N'HRGA';
   EXEC dbo.usp_Location_SetActive @Id = 999999, @IsActive = 0;

   -- 7) Idempotensi: ubah satu nama seed, jalankan ulang script ini -> tidak ada baris dobel;
   --    nama lama yang diubah akan ditambah kembali sebagai baris baru (MERGE hanya menambah).
   --    Bersihkan data uji:
   --    DELETE dbo.Location WHERE Name = N'Gudang Uji';
   ===================================================================== */
