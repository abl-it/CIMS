# Tugas: Otorisasi role CIMS (Tahap B), mengikuti pola HierarchyLevel dari Training

Baca CLAUDE.md terlebih dahulu dan ikuti semua aturannya.

**Prasyarat (cek dulu):**
1. Tahap A (design-auth) sudah PASS: `ICurrentUserService`, `ProfileAttribute` global, `SessionTokenMiddleware` berjalan.
2. Bagian "Daftar role CIMS" di bawah sudah saya isi. **Jika masih `[ISI]`, BERHENTI dan beri tahu saya.
   Jangan mengisi atau menebak nama role sendiri.**

Project referensi (HANYA BACA): [ISI PATH PROJECT TRAINING]. File acuan: Filters/RoleAuthorizeAttribute.cs,
Filters/RoleAuthorizeApiAttribute.cs, Filters/AllowAllRolesAttribute.cs, Services/TrainingMatrixService.cs
(GetRolesAsync).

**Jika Prompts\design-role-display.md sudah dijalankan:** tabel `dbo.HierarchyLevel`, `usp_Auth_GetUserRoles`,
`CurrentUser.Roles` / `HighestRole`, dan pemuatan role di `ProfileAttribute` sudah ada. Periksa dulu, jangan
dibuat ulang. Yang dikerjakan di sini: sesuaikan seed role dengan hasil PRD (MERGE), lalu filter, default-deny,
`CimsRoles`, sidebar per role, dan hak akses Customer.

## Pola di Training (ikuti bentuknya)

- Tabel `dbo.HierarchyLevel` (`Role VARCHAR(50)` PK, `HierarchyLevel INT`). Angka kecil = jabatan lebih tinggi.
  Contoh isi Training: administrator 1, komisaris 2, director 3, gm 4, tc 5, mo 6, kabag 7, plan 8, spv 9,
  adm 10, emp 11, creator 12.
- Role user disimpan di `home.dbo.Users.Role`: beberapa role dalam satu string, dipisah `;`.
- Filter MVC (`RoleAuthorize`, redirect ke Home/NotAuthorized), filter API (`RoleAuthorizeApi`, 403 JSON),
  dan marker `[AllowAllRoles]` untuk action yang cukup login.

## Perbedaan dari Training (WAJIB)

1. **Semantik "salah satu role cocok" (any-of), bukan pencocokan role tertinggi.**
   Training hanya mengecek satu role tertinggi milik user terhadap daftar yang diizinkan. Akibatnya user
   dengan role `gm` yang juga memegang `tc` ditolak pada endpoint `[RoleAuthorize("tc")]`. Di CIMS:
   akses diizinkan bila SALAH SATU role user ada di daftar yang diizinkan. Level hierarki dipakai untuk
   urutan dan untuk menentukan "role tertinggi" (tampilan), bukan untuk menolak.
2. **Role dimuat sekali per request** oleh `ProfileAttribute` (bersama CurrentUser) ke
   `ICurrentUserService` (`Roles`, `HighestRole`). Filter membaca dari situ dan tidak query database lagi.
3. **Default deny.** User yang tidak punya satu pun role yang ada di `dbo.HierarchyLevel` -> NotAuthorized
   di seluruh aplikasi (kecuali Home/NotAuthorized, Home/Error, Home/LogOut). Jika semua karyawan boleh masuk,
   masukkan role `emp` ke tabel. `[AllowAllRoles]` berarti "punya minimal satu role CIMS".
4. **Konstanta role** di satu class (`CimsRoles`, string const) dan dipakai pada atribut, tanpa string literal
   tersebar. Perbandingan role case-insensitive.
5. **Logging** Debug atau Information, tanpa emoji, tanpa Warning pada setiap request yang berhasil.
6. **403 untuk AJAX/API:** JSON `{ "success": false, "message": "Tidak berwenang" }`; `notify.fetchError`
   menampilkan SweetAlert2 (sudah ada dari Tahap A). 403 untuk halaman MVC: Home/NotAuthorized.
7. **Sidebar per role:** item menu mendapat properti `Roles` (kosong = semua yang punya akses). Item
   disembunyikan bila user tidak berhak. Ini hanya kosmetik, otorisasi tetap di server.
8. Tidak membuat fungsi `fc_GetRole`. Cukup stored procedure dan logika di C#.

## Daftar role CIMS (SAYA ISI, dari hasil PRD)

Titik awal (contoh dari Training, jangan dipakai apa adanya):
administrator 1, director 3, gm 4, kabag 7, spv 9, adm 10, emp 11.

| Role | HierarchyLevel | Keterangan |
|---|---|---|
| [ISI] | [ISI] | [ISI] |

Catatan untuk saya sendiri: role CIMS yang khusus (bukan jabatan umum) harus dipasang pada user lewat
pengelolaan user di portal (`home.dbo.Users.Role`). CIMS tidak punya layar pengelolaan user.

## Hak akses modul yang sudah ada

Customer: lihat (Index, Details) = [ISI]; tambah dan ubah = [ISI]; nonaktifkan/aktifkan = [ISI].
Jika masih `[ISI]`, tanyakan kepada saya, jangan dipilihkan.

## Yang dibangun

### B.1 Database/Role.sql (kerjakan DULU, lalu berhenti dan tunggu PASS)
- `dbo.HierarchyLevel` (`Role VARCHAR(50) NOT NULL` PK, `HierarchyLevel INT NOT NULL`,
  `Description NVARCHAR(100) NULL`), pembuatan idempotent (`IF OBJECT_ID ... IS NULL`).
- Seed dari tabel "Daftar role CIMS" dengan `MERGE` agar bisa dijalankan ulang.
- `dbo.usp_Auth_GetUserRoles(@Username NVARCHAR(100))`: pecah `home.dbo.Users.Role` berdasarkan `;`
  (`STRING_SPLIT` + `LTRIM(RTRIM())`), JOIN ke `dbo.HierarchyLevel`, kembalikan `Role`, `HierarchyLevel`
  diurutkan `HierarchyLevel` naik. Role yang tidak ada di tabel diabaikan.
- `STRING_SPLIT` perlu compatibility level >= 130. Jika database dev lebih rendah, laporkan, jangan
  mengubah database. Jangan menjalankan script SQL.

### B.2 Kode (setelah B.1 PASS)
- `Models/CurrentUser`: tambah `Roles` (daftar string) dan `HighestRole` (string, level terkecil).
- `AuthService.GetUserRolesAsync` (Dapper, stored procedure). `ProfileAttribute` memuat role bersama user.
- `Filters/RoleAuthorizeAttribute` (MVC), `RoleAuthorizeApiAttribute` (API), `AllowAllRolesAttribute`,
  `CimsRoles`. Bentuk dan penamaan mengikuti Training, perilaku sesuai perbedaan di atas.
- Terapkan atribut pada controller Customer sesuai "Hak akses modul yang sudah ada".
- Sidebar: tambahkan `Roles` pada data menu dan sembunyikan item yang tidak berhak.
- Update CLAUDE.md, bagian "Autentikasi": tambahkan "Otorisasi" (tabel HierarchyLevel, sumber role,
  semantik any-of, default deny, `CimsRoles`, aturan "modul baru wajib menentukan role per action",
  `[AllowAllRoles]` hanya untuk action read-only).

## Test

- User dengan beberapa role (mis. `gm;<role CIMS>`): lolos pada endpoint yang mengizinkan salah satunya.
  (Kasus yang gagal di Training.)
- User tanpa role CIMS: NotAuthorized di semua halaman, tanpa loop redirect. Logout tetap bisa.
- Endpoint API tanpa hak: 403 JSON, `notify.fetchError` menampilkan SweetAlert2.
- Sidebar: item tersembunyi sesuai role. Mengakses URL-nya langsung tetap ditolak server.
- Customer: tiap role di tabel hak akses berperilaku sesuai (lihat, tambah/ubah, nonaktifkan).
- Uji beberapa role dengan mengganti `Auth:DevUsername` ke user nyata yang berbeda di `home..users`.
- `dotnet build`: 0 error, 0 warning.

## Cara kerja

1. Tampilkan rencana lengkap dan tunggu persetujuan saya.
2. Kerjakan B.1 saja (Database/Role.sql). Berhenti. Saya jalankan di database dev dan jawab PASS.
3. Setelah PASS: B.2, lalu dotnet build.
Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result, lalu berhenti dan tunggu PASS.
