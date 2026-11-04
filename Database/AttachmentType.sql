/* =====================================================================
   AttachmentType.sql  -  Master data Jenis Lampiran (T1; PRD MD-09, BR-45, BR-05, BR-42, BR-43, 6.5)
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Waktu   : Local time (SYSDATETIME), bukan UTC.
   Catatan :
     - Code unik dan TIDAK bisa diubah setelah dibuat (dipakai modul lain sebagai kunci).
     - Stage = tahap proses tempat lampiran diunggah:
         REQUEST (business case), DOCUMENT (Document Preparation Civil), PROCUREMENT (TOR),
         CONTRACT (input Purchasing), BAPP, COST (upload actual cost).
     - IsMandatoryCapex/Opex/Lve = wajib diunggah pada tahap tersebut untuk kategori itu.
       Contoh: TOR dan Contract hanya untuk outsource -> tidak ditandai wajib per kategori; alur
       outsource yang mewajibkannya (BR-11).
     - AllowedExtensions: huruf kecil tanpa titik, dipisah koma (mis. 'pdf,jpg,png'). MaxSizeMB 1..100.
     - Seed MERGE hanya MENAMBAH Code yang belum ada (tidak menimpa perubahan).
     - Soft delete lewat SetActive (tanpa Delete).
   Error   : 50021 = Code duplikat
             50022 = Input wajib kosong / tidak valid
             50023 = Data tidak ditemukan
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.AttachmentType', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AttachmentType
    (
        Id                 INT IDENTITY(1,1) NOT NULL,
        Code               VARCHAR(30)   NOT NULL,
        Name               NVARCHAR(100) NOT NULL,
        Stage              VARCHAR(20)   NOT NULL,
        AllowedExtensions  VARCHAR(200)  NOT NULL,
        MaxSizeMB          INT           NOT NULL,
        IsMandatoryCapex   BIT           NOT NULL CONSTRAINT DF_AttachmentType_MandCapex DEFAULT (0),
        IsMandatoryOpex    BIT           NOT NULL CONSTRAINT DF_AttachmentType_MandOpex  DEFAULT (0),
        IsMandatoryLve     BIT           NOT NULL CONSTRAINT DF_AttachmentType_MandLve   DEFAULT (0),
        IsActive           BIT           NOT NULL CONSTRAINT DF_AttachmentType_IsActive  DEFAULT (1),
        CreatedAt          DATETIME2(3)  NOT NULL CONSTRAINT DF_AttachmentType_CreatedAt DEFAULT (SYSDATETIME()),
        CreatedBy          NVARCHAR(100) NULL,
        UpdatedAt          DATETIME2(3)  NULL,
        UpdatedBy          NVARCHAR(100) NULL,
        CONSTRAINT PK_AttachmentType PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT CK_AttachmentType_Code    CHECK (Code NOT LIKE '%[^A-Z0-9_]%' COLLATE Latin1_General_BIN),
        CONSTRAINT CK_AttachmentType_Stage   CHECK (Stage IN ('REQUEST', 'DOCUMENT', 'PROCUREMENT', 'CONTRACT', 'BAPP', 'COST')),
        CONSTRAINT CK_AttachmentType_Ext     CHECK (AllowedExtensions <> '' AND AllowedExtensions NOT LIKE '%[^a-z0-9,]%' COLLATE Latin1_General_BIN),
        CONSTRAINT CK_AttachmentType_MaxSize CHECK (MaxSizeMB BETWEEN 1 AND 100)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = N'UX_AttachmentType_Code' AND object_id = OBJECT_ID(N'dbo.AttachmentType'))
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX UX_AttachmentType_Code ON dbo.AttachmentType (Code);
END
GO

/* ---------------------------------------------------------------------
   2. SEED (PRD 6.5; wajib: BR-42 ROI CAPEX, BR-43 foto area, BR-05 BOQ semua / Drawing CAPEX)
   --------------------------------------------------------------------- */
MERGE dbo.AttachmentType AS t
USING (VALUES
        ('ROI',         N'ROI Calculation',     'REQUEST',     'pdf,jpg,png',  5, 1, 0, 0),
        ('AREA_PHOTO',  N'Area Photo',          'REQUEST',     'pdf,jpg,png',  5, 1, 1, 1),
        ('BOQ',         N'Bill of Quantities',  'DOCUMENT',    'pdf,xlsx,dwg', 20, 1, 1, 1),
        ('DRAWING',     N'Drawing',             'DOCUMENT',    'pdf,xlsx,dwg', 20, 1, 0, 0),
        ('TOR',         N'Terms of Reference',  'PROCUREMENT', 'pdf,xlsx,dwg', 20, 0, 0, 0),
        ('CONTRACT',    N'Contract',            'CONTRACT',    'pdf,xlsx,dwg', 20, 0, 0, 0),
        ('BAPP',        N'BAPP',                'BAPP',        'pdf,xlsx,dwg', 20, 1, 1, 1),
        ('ACTUAL_COST', N'Actual Cost Upload',  'COST',        'xlsx',          5, 0, 0, 0)
      ) AS s (Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve)
   ON t.Code = s.Code
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, CreatedBy)
    VALUES (s.Code, s.Name, s.Stage, s.AllowedExtensions, s.MaxSizeMB,
            CAST(s.IsMandatoryCapex AS BIT), CAST(s.IsMandatoryOpex AS BIT), CAST(s.IsMandatoryLve AS BIT), N'seed');
GO

/* ---------------------------------------------------------------------
   3. dbo.fn_AttachmentType_NormalizeExt
      'PDF, .Jpg,,png ' -> 'pdf,jpg,png' (huruf kecil, tanpa spasi/titik, tanpa koma ganda/di ujung).
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION dbo.fn_AttachmentType_NormalizeExt (@Ext NVARCHAR(400))
RETURNS VARCHAR(200)
AS
BEGIN
    DECLARE @s NVARCHAR(400) = LOWER(REPLACE(REPLACE(REPLACE(ISNULL(@Ext, N''), N' ', N''), N'.', N''), CHAR(9), N''));
    WHILE CHARINDEX(N',,', @s) > 0 SET @s = REPLACE(@s, N',,', N',');
    IF LEFT(@s, 1) = N','  SET @s = STUFF(@s, 1, 1, N'');
    IF RIGHT(@s, 1) = N',' SET @s = LEFT(@s, LEN(@s) - 1);
    RETURN CAST(@s AS VARCHAR(200));
END
GO

/* ---------------------------------------------------------------------
   4. usp_AttachmentType_GetPaged
      Search (Code/Name), filter Stage dan status, sorting whitelist, paging.
      @SortBy  : Code | Name | Stage | CreatedAt   (default Stage)
      @SortDir : ASC | DESC                        (default ASC)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_GetPaged
    @Stage       VARCHAR(20)   = NULL,
    @Search      NVARCHAR(100) = NULL,
    @IsActive    BIT           = NULL,
    @SortBy      NVARCHAR(20)  = N'Stage',
    @SortDir     NVARCHAR(4)   = N'ASC',
    @PageNumber  INT           = 1,
    @PageSize    INT           = 10,
    @TotalCount  INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Stage      = NULLIF(LTRIM(RTRIM(@Stage)), '');
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @SortBy     = CASE WHEN @SortBy IN (N'Code', N'Name', N'Stage', N'CreatedAt') THEN @SortBy ELSE N'Stage' END;
    SET @SortDir    = CASE WHEN UPPER(@SortDir) = N'DESC' THEN N'DESC' ELSE N'ASC' END;
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize   IS NULL OR @PageSize   < 1 THEN 10
                           WHEN @PageSize   > 100 THEN 100
                           ELSE @PageSize END;

    SELECT @TotalCount = COUNT(*)
    FROM dbo.AttachmentType
    WHERE (@Stage    IS NULL OR Stage = @Stage)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%')
    OPTION (RECOMPILE);

    SELECT Id, Code, Name, Stage, AllowedExtensions, MaxSizeMB,
           IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, IsActive,
           CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.AttachmentType
    WHERE (@Stage    IS NULL OR Stage = @Stage)
      AND (@IsActive IS NULL OR IsActive = @IsActive)
      AND (@Search   IS NULL OR Code LIKE N'%' + @Search + N'%' OR Name LIKE N'%' + @Search + N'%')
    ORDER BY
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'ASC'  THEN Code      END ASC,
        CASE WHEN @SortBy = N'Code'      AND @SortDir = N'DESC' THEN Code      END DESC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'ASC'  THEN Name      END ASC,
        CASE WHEN @SortBy = N'Name'      AND @SortDir = N'DESC' THEN Name      END DESC,
        -- Stage diurutkan sesuai alur proses, bukan alfabet.
        CASE WHEN @SortBy = N'Stage'     AND @SortDir = N'ASC'  THEN
             CHARINDEX(',' + Stage + ',', ',REQUEST,DOCUMENT,PROCUREMENT,CONTRACT,BAPP,COST,') END ASC,
        CASE WHEN @SortBy = N'Stage'     AND @SortDir = N'DESC' THEN
             CHARINDEX(',' + Stage + ',', ',REQUEST,DOCUMENT,PROCUREMENT,CONTRACT,BAPP,COST,') END DESC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'ASC'  THEN CreatedAt END ASC,
        CASE WHEN @SortBy = N'CreatedAt' AND @SortDir = N'DESC' THEN CreatedAt END DESC,
        Code ASC, Id ASC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
    OPTION (RECOMPILE);
END
GO

/* ---------------------------------------------------------------------
   5. usp_AttachmentType_GetById
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Code, Name, Stage, AllowedExtensions, MaxSizeMB,
           IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, IsActive,
           CreatedAt, CreatedBy, UpdatedAt, UpdatedBy
    FROM dbo.AttachmentType
    WHERE Id = @Id;
END
GO

/* ---------------------------------------------------------------------
   6. usp_AttachmentType_Insert
      @NewId = Id baru (OUTPUT); @ActionBy = username pelaku (audit)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_Insert
    @Code               VARCHAR(30),
    @Name               NVARCHAR(100),
    @Stage              VARCHAR(20),
    @AllowedExtensions  NVARCHAR(400),
    @MaxSizeMB          INT,
    @IsMandatoryCapex   BIT           = 0,
    @IsMandatoryOpex    BIT           = 0,
    @IsMandatoryLve     BIT           = 0,
    @IsActive           BIT           = 1,
    @ActionBy           NVARCHAR(100) = NULL,
    @NewId              INT           = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Code  = UPPER(LTRIM(RTRIM(@Code)));
    SET @Name  = LTRIM(RTRIM(@Name));
    SET @Stage = UPPER(LTRIM(RTRIM(@Stage)));
    DECLARE @Ext VARCHAR(200) = dbo.fn_AttachmentType_NormalizeExt(@AllowedExtensions);

    IF ISNULL(@Code, '') = ''                                  THROW 50022, N'Code is required.', 1;
    IF @Code LIKE '%[^A-Z0-9_]%' COLLATE Latin1_General_BIN    THROW 50022, N'Code may only contain letters, numbers, and underscores.', 1;
    IF ISNULL(@Name, N'') = N''                                THROW 50022, N'Name is required.', 1;
    IF ISNULL(@Stage, '') NOT IN ('REQUEST', 'DOCUMENT', 'PROCUREMENT', 'CONTRACT', 'BAPP', 'COST')
                                                               THROW 50022, N'Stage is invalid.', 1;
    IF @Ext = '' OR @Ext LIKE '%[^a-z0-9,]%' COLLATE Latin1_General_BIN
                                                               THROW 50022, N'Allowed extensions are invalid (example: pdf,jpg,png).', 1;
    IF @MaxSizeMB IS NULL OR @MaxSizeMB NOT BETWEEN 1 AND 100  THROW 50022, N'Max size must be between 1 and 100 MB.', 1;

    BEGIN TRY
        INSERT INTO dbo.AttachmentType
            (Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve, IsActive, CreatedBy)
        VALUES
            (@Code, @Name, @Stage, @Ext, @MaxSizeMB, ISNULL(@IsMandatoryCapex, 0), ISNULL(@IsMandatoryOpex, 0),
             ISNULL(@IsMandatoryLve, 0), ISNULL(@IsActive, 1), @ActionBy);

        SET @NewId = CAST(SCOPE_IDENTITY() AS INT);
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 50021, N'Code is already in use.', 1;
        THROW;
    END CATCH
END
GO

/* ---------------------------------------------------------------------
   7. usp_AttachmentType_Update  (Code tidak bisa diubah)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_Update
    @Id                 INT,
    @Name               NVARCHAR(100),
    @Stage              VARCHAR(20),
    @AllowedExtensions  NVARCHAR(400),
    @MaxSizeMB          INT,
    @IsMandatoryCapex   BIT           = 0,
    @IsMandatoryOpex    BIT           = 0,
    @IsMandatoryLve     BIT           = 0,
    @IsActive           BIT           = 1,
    @ActionBy           NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name  = LTRIM(RTRIM(@Name));
    SET @Stage = UPPER(LTRIM(RTRIM(@Stage)));
    DECLARE @Ext VARCHAR(200) = dbo.fn_AttachmentType_NormalizeExt(@AllowedExtensions);

    IF ISNULL(@Name, N'') = N''                                THROW 50022, N'Name is required.', 1;
    IF ISNULL(@Stage, '') NOT IN ('REQUEST', 'DOCUMENT', 'PROCUREMENT', 'CONTRACT', 'BAPP', 'COST')
                                                               THROW 50022, N'Stage is invalid.', 1;
    IF @Ext = '' OR @Ext LIKE '%[^a-z0-9,]%' COLLATE Latin1_General_BIN
                                                               THROW 50022, N'Allowed extensions are invalid (example: pdf,jpg,png).', 1;
    IF @MaxSizeMB IS NULL OR @MaxSizeMB NOT BETWEEN 1 AND 100  THROW 50022, N'Max size must be between 1 and 100 MB.', 1;

    UPDATE dbo.AttachmentType
    SET Name              = @Name,
        Stage             = @Stage,
        AllowedExtensions = @Ext,
        MaxSizeMB         = @MaxSizeMB,
        IsMandatoryCapex  = ISNULL(@IsMandatoryCapex, 0),
        IsMandatoryOpex   = ISNULL(@IsMandatoryOpex, 0),
        IsMandatoryLve    = ISNULL(@IsMandatoryLve, 0),
        IsActive          = ISNULL(@IsActive, IsActive),
        UpdatedAt         = SYSDATETIME(),
        UpdatedBy         = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50023, N'Attachment type not found.', 1;
END
GO

/* ---------------------------------------------------------------------
   8. usp_AttachmentType_SetActive  (soft delete / aktifkan kembali)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_AttachmentType_SetActive
    @Id        INT,
    @IsActive  BIT,
    @ActionBy  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.AttachmentType
    SET IsActive  = @IsActive,
        UpdatedAt = SYSDATETIME(),
        UpdatedBy = @ActionBy
    WHERE Id = @Id;

    IF @@ROWCOUNT = 0
        THROW 50023, N'Attachment type not found.', 1;
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Seed: 8 baris; wajib sesuai PRD (ROI & Drawing CAPEX; Area Photo, BOQ, BAPP semua kategori)
   SELECT Code, Name, Stage, AllowedExtensions, MaxSizeMB, IsMandatoryCapex, IsMandatoryOpex, IsMandatoryLve
   FROM dbo.AttachmentType ORDER BY Id;

   -- 2) Insert jenis baru + normalisasi ekstensi -> AllowedExtensions = 'pdf,jpg,png', Code = 'SITE_REPORT'
   DECLARE @NewId INT;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'site_report', @Name = N'Site Report', @Stage = 'DOCUMENT',
        @AllowedExtensions = N' PDF, .Jpg,,png, ', @MaxSizeMB = 10, @IsMandatoryOpex = 1,
        @ActionBy = N'uji', @NewId = @NewId OUTPUT;
   EXEC dbo.usp_AttachmentType_GetById @Id = @NewId;

   -- 3) Code duplikat -> 50021 ; Code tidak valid / Stage salah / ekstensi kosong / ukuran 0 -> 50022
   EXEC dbo.usp_AttachmentType_Insert @Code = 'BOQ', @Name = N'X', @Stage = 'DOCUMENT', @AllowedExtensions = N'pdf', @MaxSizeMB = 5;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'A-B', @Name = N'X', @Stage = 'DOCUMENT', @AllowedExtensions = N'pdf', @MaxSizeMB = 5;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'X1',  @Name = N'X', @Stage = 'OTHER',    @AllowedExtensions = N'pdf', @MaxSizeMB = 5;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'X2',  @Name = N'X', @Stage = 'DOCUMENT', @AllowedExtensions = N' , ', @MaxSizeMB = 5;
   EXEC dbo.usp_AttachmentType_Insert @Code = 'X3',  @Name = N'X', @Stage = 'DOCUMENT', @AllowedExtensions = N'pdf', @MaxSizeMB = 0;

   -- 4) List: filter Stage DOCUMENT, sort Stage (urutan alur), paging
   DECLARE @Total INT;
   EXEC dbo.usp_AttachmentType_GetPaged @Stage = 'DOCUMENT', @TotalCount = @Total OUTPUT;   -- BOQ, DRAWING, SITE_REPORT
   SELECT @Total AS TotalCount;
   EXEC dbo.usp_AttachmentType_GetPaged @TotalCount = @Total OUTPUT;                       -- REQUEST dulu, COST terakhir

   -- 5) Update (Code tetap), soft delete; Id tidak ada -> 50023
   DECLARE @NewId INT = (SELECT Id FROM dbo.AttachmentType WHERE Code = 'SITE_REPORT');
   EXEC dbo.usp_AttachmentType_Update @Id = @NewId, @Name = N'Site Report (Rev)', @Stage = 'BAPP',
        @AllowedExtensions = N'pdf', @MaxSizeMB = 15, @IsMandatoryCapex = 1, @ActionBy = N'uji';
   EXEC dbo.usp_AttachmentType_SetActive @Id = @NewId, @IsActive = 0, @ActionBy = N'uji';
   EXEC dbo.usp_AttachmentType_GetById @Id = @NewId;
   EXEC dbo.usp_AttachmentType_SetActive @Id = 999999, @IsActive = 0;

   -- 6) Jalankan ulang script -> tidak ada baris dobel; perubahan pada langkah 5 tidak tertimpa.
   --    Bersihkan data uji:
   --    DELETE dbo.AttachmentType WHERE Code = 'SITE_REPORT';
   ===================================================================== */
