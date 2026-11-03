/* =====================================================================
   Role.sql  -  Role user CIMS: tabel hierarki + stored procedure pembaca role
   Target  : Microsoft SQL Server 2016 SP1+ (CREATE OR ALTER)
   Sifat   : Idempotent, aman dijalankan ulang. Jalankan di DB DEV/TEST.
   Prasyarat:
     1) STRING_SPLIT butuh compatibility level >= 130 pada database CIMS. Cek dulu:
          SELECT name, compatibility_level FROM sys.databases WHERE name = DB_NAME();
        Jika < 130, JANGAN ubah database; laporkan.
     2) Login database CIMS punya hak baca ke database [home] (sama seperti Auth.sql).
   Catatan :
     - Role user disimpan di home..users.[Role]: beberapa role dalam satu string, dipisah ';'.
     - HierarchyLevel: angka kecil = jabatan lebih tinggi (dipakai untuk urutan / "role tertinggi").
     - Seed di bawah SEMENTARA (daftar Training, Description NULL); disesuaikan setelah PRD.
       MERGE hanya MENAMBAH role yang belum ada. Baris yang sudah ada TIDAK diubah/dihapus, jadi
       Description atau level yang sudah Anda sesuaikan di tabel tidak tertimpa saat script
       dijalankan ulang. Mengubah role yang sudah ada: UPDATE langsung di dbo.HierarchyLevel.
     - Script ini hanya untuk TAMPILAN role; tidak ada keputusan akses yang memakainya.
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TABLE dbo.HierarchyLevel
   --------------------------------------------------------------------- */
IF OBJECT_ID(N'dbo.HierarchyLevel', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.HierarchyLevel
    (
        [Role]          VARCHAR(50)   NOT NULL,
        HierarchyLevel  INT           NOT NULL,
        Description     NVARCHAR(100) NULL,
        CONSTRAINT PK_HierarchyLevel PRIMARY KEY CLUSTERED ([Role])
    );
END
GO

/* ---------------------------------------------------------------------
   2. SEED sementara (daftar Training). Hanya menambah yang belum ada.
   --------------------------------------------------------------------- */
MERGE dbo.HierarchyLevel AS t
USING (VALUES
        (N'administrator', 1),
        (N'komisaris',     2),
        (N'director',      3),
        (N'gm',            4),
        (N'civil',            5),
        (N'mo',            6),
        (N'kabag',         7),
        (N'plan',          8),
        (N'spv',           9),
        (N'adm',          10),
        (N'emp',          11),
        (N'creator',      12)
      ) AS s ([Role], HierarchyLevel)
   ON t.[Role] = s.[Role]
WHEN NOT MATCHED BY TARGET THEN
    INSERT ([Role], HierarchyLevel, Description)
    VALUES (s.[Role], s.HierarchyLevel, NULL);
GO

/* ---------------------------------------------------------------------
   2b. Role CIMS sesuai PRD 5.1 (T0-2): tambah fat (5) dan purchasing (6) bila belum ada,
       lalu isi Description 12 role CIMS HANYA bila masih NULL (tidak menimpa perubahan administrator).
       plan, spv, emp: role CIMS hanya-lihat (PRD RL-10..RL-12). komisaris dan creator tidak memberi akses CIMS.
   --------------------------------------------------------------------- */
MERGE dbo.HierarchyLevel AS t
USING (VALUES (N'fat', 5), (N'purchasing', 6)) AS s ([Role], HierarchyLevel)
   ON t.[Role] = s.[Role]
WHEN NOT MATCHED BY TARGET THEN
    INSERT ([Role], HierarchyLevel, Description)
    VALUES (s.[Role], s.HierarchyLevel, NULL);
GO

UPDATE h
SET    h.Description = d.Description
FROM   dbo.HierarchyLevel h
       JOIN (VALUES (N'administrator', N'System Administrator'),
                    (N'director',      N'Director'),
                    (N'gm',            N'General Manager'),
                    (N'civil',         N'Civil Department'),
                    (N'fat',           N'Finance, Accounting & Tax'),
                    (N'mo',            N'Manager Operational'),
                    (N'purchasing',    N'Purchasing'),
                    (N'kabag',         N'Department Head'),
                    (N'adm',           N'Department Admin'),
                    (N'plan',          N'Planner'),
                    (N'spv',           N'Supervisor'),
                    (N'emp',           N'Employee')
            ) AS d ([Role], Description) ON d.[Role] = h.[Role]
WHERE  h.Description IS NULL;
GO

/* ---------------------------------------------------------------------
   3. usp_Auth_GetUserRoles
      Memecah home..users.[Role] per ';', trim, JOIN ke dbo.HierarchyLevel.
      Role yang tidak ada di tabel diabaikan; role ganda dihitung sekali.
      Urut HierarchyLevel naik (baris pertama = role tertinggi).
      0 baris = user tidak punya role terdaftar (atau user tidak ada).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_Auth_GetUserRoles
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  h.[Role],
            h.HierarchyLevel,
            h.Description
    FROM    (
                SELECT DISTINCT LTRIM(RTRIM(s.value)) AS RoleCode
                FROM   home..users u
                       CROSS APPLY STRING_SPLIT(u.[Role], N';') s
                WHERE  u.Username = @Username
                  AND  LTRIM(RTRIM(s.value)) <> N''
            ) x
            JOIN dbo.HierarchyLevel h ON h.[Role] = x.RoleCode
    ORDER BY h.HierarchyLevel, h.[Role];
END
GO

/* =====================================================================
   TEST (jalankan manual di DB dev, blok per blok)

   -- 1) Seed: harus 14 baris (12 + fat + purchasing); 12 role CIMS ber-Description; komisaris dan creator NULL
   SELECT [Role], HierarchyLevel, Description FROM dbo.HierarchyLevel ORDER BY HierarchyLevel;

   -- 2) Role user (ganti dengan username yang ada di home..users)
   --    Lihat string mentahnya:
   SELECT Username, [Role] FROM home..users WHERE Username = N'<username>';
   --    Hasil procedure: role terdaftar saja, urut level naik (baris pertama = tertinggi)
   EXEC dbo.usp_Auth_GetUserRoles @Username = N'<username>';

   -- 3) User tanpa role terdaftar / user tidak ada -> 0 baris
   EXEC dbo.usp_Auth_GetUserRoles @Username = N'tidak-ada-xyz';

   -- 4) Ubah tampilan tanpa ubah kode: isi Description satu role, lalu ulangi langkah 2
   --    UPDATE dbo.HierarchyLevel SET Description = N'General Manager' WHERE [Role] = 'gm';

   -- 5) Jalankan ulang script ini: Description pada langkah 4 TIDAK tertimpa (MERGE hanya INSERT).

   -- 6) Jika error "Invalid object name 'STRING_SPLIT'" / compatibility level < 130:
   --    laporkan; jangan ubah database tanpa persetujuan.

   -- 7) SEKALI JALAN (UI berbahasa Inggris, 03-11-2026): ganti Description lama berbahasa Indonesia.
   --    Hanya mengganti nilai seed lama; Description yang sudah diubah administrator ke nilai lain tidak disentuh.
   UPDATE h SET h.Description = d.NewText
   FROM   dbo.HierarchyLevel h
          JOIN (VALUES (N'administrator', N'Administrator Sistem', N'System Administrator'),
                       (N'kabag',         N'Kepala Bagian',        N'Section Head'),
                       (N'adm',           N'Admin Departemen',     N'Department Admin'),
                       (N'emp',           N'Karyawan',             N'Employee')
               ) AS d ([Role], OldText, NewText) ON d.[Role] = h.[Role] AND h.Description = d.OldText;
   ===================================================================== */
