/* =====================================================================
   FixTextEncoding.sql  -  Perbaikan data teks rusak akibat script .sql terbaca ANSI (Keputusan 19-11-2026)
   Gejala  : riwayat menampilkan "Â·" (seharusnya "·"), "â†’" ("→"), "Ã—" ("×"); unit "mÂ²" / "mÂ³".
   Sebab   : file .sql UTF-8 tanpa BOM dibuka sebagai ANSI (Windows-1252) saat dijalankan, sehingga literal N'·'
             di stored procedure ikut tersimpan rusak. Sejak 19-11-2026 file .sql yang berisi karakter non-ASCII
             disimpan UTF-8 dengan BOM.
   Urutan  : 1) jalankan ulang script SP yang memuat karakter tersebut (agar SP tidak lagi menulis teks rusak):
                RequestBapp.sql, RequestAddendum.sql, RequestActualCost.sql, RequestActualUpload.sql,
                RequestExecution.sql, RequestFeasibility.sql, RequestDocPrep.sql, RequestMigration.sql,
                RequestSchedule.sql, RequestSurvey.sql
             2) jalankan script ini (memperbaiki data yang sudah tersimpan).
   Target  : Microsoft SQL Server 2016 SP1+. Idempotent: aman dijalankan ulang (hanya baris yang masih rusak).
   Karakter benar ditulis lewat NCHAR() agar script ini sendiri tidak bergantung encoding file.
   ===================================================================== */
SET NOCOUNT ON;

DECLARE @Dot    NCHAR(1) = NCHAR(183);    -- ·
DECLARE @Arrow  NCHAR(1) = NCHAR(8594);   -- →
DECLARE @Times  NCHAR(1) = NCHAR(215);    -- ×
DECLARE @Sq     NCHAR(1) = NCHAR(178);    -- ²
DECLARE @Cube   NCHAR(1) = NCHAR(179);    -- ³

-- Bentuk rusak (byte UTF-8 dibaca sebagai Windows-1252)
DECLARE @BadDot   NVARCHAR(3) = NCHAR(194) + NCHAR(183);                 -- Â·
DECLARE @BadArrow NVARCHAR(3) = NCHAR(226) + NCHAR(8224) + NCHAR(8217);  -- â†’
DECLARE @BadTimes NVARCHAR(3) = NCHAR(195) + NCHAR(8212);                -- Ã—
DECLARE @BadSq    NVARCHAR(3) = NCHAR(194) + NCHAR(178);                 -- Â²
DECLARE @BadCube  NVARCHAR(3) = NCHAR(194) + NCHAR(179);                 -- Â³

BEGIN TRANSACTION;

/* 1. Riwayat workflow (catatan otomatis dari SP) */
UPDATE dbo.ApprovalHistory
SET    Remarks = REPLACE(REPLACE(REPLACE(Remarks, @BadDot, @Dot), @BadArrow, @Arrow), @BadTimes, @Times)
WHERE  Remarks LIKE N'%' + @BadDot + N'%'
   OR  Remarks LIKE N'%' + @BadArrow + N'%'
   OR  Remarks LIKE N'%' + @BadTimes + N'%';

SELECT @@ROWCOUNT AS ApprovalHistoryFixed;

/* 2. Master Unit dari seed (m², m³); hanya bila nama yang benar belum ada */
UPDATE u
SET    u.Name = REPLACE(REPLACE(u.Name, @BadSq, @Sq), @BadCube, @Cube)
FROM   dbo.Unit u
WHERE  (u.Name LIKE N'%' + @BadSq + N'%' OR u.Name LIKE N'%' + @BadCube + N'%')
  AND  NOT EXISTS (SELECT 1 FROM dbo.Unit x
                   WHERE x.Name = REPLACE(REPLACE(u.Name, @BadSq, @Sq), @BadCube, @Cube));

SELECT @@ROWCOUNT AS UnitFixed;

COMMIT TRANSACTION;
GO

/* TEST (harus 0 baris)
   SELECT Id, RequestId, Action, Remarks FROM dbo.ApprovalHistory
   WHERE Remarks LIKE N'%' + NCHAR(194) + NCHAR(183) + N'%'
      OR Remarks LIKE N'%' + NCHAR(226) + NCHAR(8224) + NCHAR(8217) + N'%'
      OR Remarks LIKE N'%' + NCHAR(195) + NCHAR(8212) + N'%';
   SELECT Id, Name FROM dbo.Unit WHERE Name LIKE N'%' + NCHAR(194) + N'%';
*/
