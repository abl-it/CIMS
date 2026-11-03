# Tugas T0-2: Otorisasi role CIMS (Tahap B) sesuai PRD

Baca CLAUDE.md, `docs/PRD.md` (bagian 3.9, 3.10, 5), dan `Prompts/design-role.md` terlebih dahulu.
File ini **menggantikan isi `[ISI]` di `Prompts/design-role.md`** dan menambahkan lingkup data. Semua aturan
di `design-role.md` bagian "Perbedaan dari Training" tetap berlaku (any-of, role dimuat sekali per request,
default deny, `CimsRoles`, logging, 403 JSON untuk AJAX, sidebar per role, tanpa `fc_GetRole`).
Referensi PRD: RL-01..RL-09, BR-24, BR-27..BR-31, BR-35, BR-36, BR-56, BR-57, BR-59, BR-63, matriks 5.2, 5.4.

## Prasyarat (cek dulu, berhenti dan laporkan bila tidak terpenuhi)

1. `design-role-display` sudah berjalan: `dbo.HierarchyLevel`, `usp_Auth_GetUserRoles`, `UserRole`,
   `CurrentUser.Roles`/`HighestRole`, pemuatan role di `ProfileAttribute`. **Jangan dibuat ulang.**
2. `Prompts/t0-1-konfigurasi.md` sudah PASS (`dbo.DepartmentGroup`, `dbo.DepartmentGroupMember` ada).
3. Nama kolom tanggal resign di `home..app_employees`: **[ISI]** (tipe: **[ISI]**).
   Jika masih `[ISI]`, BERHENTI dan tanyakan. Jangan menebak nama kolom.

## Daftar role CIMS (Keputusan PRD 5.1)

| Role | HierarchyLevel | Description | Lingkup data | Lintas Company |
|---|---|---|---|---|
| administrator | 1 | Administrator Sistem | Semua | Ya |
| director | 3 | Director | Semua (Company sendiri untuk approve) | Ya (lihat) |
| gm | 4 | General Manager | Semua (Company sendiri untuk approve) | Ya (lihat) |
| civil | 5 | Civil Department | Semua | Ya |
| fat | 5 | Finance, Accounting & Tax | Company sendiri | Tidak |
| mo | 6 | Manager Operational | Grup `MILL` (DepartmentGroup) | Tidak |
| purchasing | 6 | Purchasing | Semua | Ya |
| kabag | 7 | Kepala Bagian | Departemen sendiri = semua DepartmentID dengan **ABRV dan CoCode sama** | Tidak |
| adm | 10 | Admin Departemen | Sama dengan kabag | Tidak |

- Role lain di seed (`komisaris`, `plan`, `spv`, `emp`, `creator`) **tidak** memberi akses ke CIMS. Jangan dihapus
  dari tabel (dipakai aplikasi lain/riwayat); otorisasi CIMS cukup mengenali 9 role di atas lewat `CimsRoles`.
- `fat` dan `purchasing` ditambahkan ke `dbo.HierarchyLevel`. `Description` diisi untuk 9 role di atas
  **hanya bila masih NULL** (jangan menimpa nilai yang sudah diubah administrator).
- Role `civil` tetap kode `civil` (bukan `tc`).

## Hak akses modul yang sudah ada

Customer (modul acuan pola, PRD 6.2): Index, Details, Create, Edit, SetActive = **`administrator`** saja.
Menu Customer hanya tampil untuk `administrator`.

## Yang dibangun

### B.1 SQL (kerjakan DULU, lalu berhenti dan tunggu PASS)

File: `Database/Role.sql` (tambahan, jangan mengubah objek lain yang tidak disebut) dan `Database/Auth.sql`.

1. `Role.sql`: MERGE insert-only untuk `fat` (5) dan `purchasing` (6); UPDATE `Description` untuk 9 role CIMS
   `WHERE Description IS NULL`.
2. `Auth.sql` → `usp_Auth_GetUserByUsername`:
   - tambah kolom `e.DepartmentID` dan `ad.CoCode AS DeptCoCode` (bila berbeda dari `e.CoCode`, laporkan).
   - karyawan resign (kolom prasyarat 3 terisi dan ≤ tanggal hari ini, local time) → **0 baris** (BR-31),
     sehingga `ProfileAttribute` otomatis ke NotAuthorized tanpa perubahan alur.
3. Function baru `dbo.fn_User_AllowedDepartments(@Username NVARCHAR(100))` (inline TVF) di file baru
   `Database/Scope.sql`. Mengembalikan `DepartmentID, CoCode` dari `home..APP_Departments` (`Disabled = 0`)
   yang boleh dilihat user, gabungan (UNION) dari semua role CIMS user (any-of, BR-29):
   - `administrator`, `civil`, `purchasing`, `director`, `gm` → semua departemen ABL dan NKM.
   - `fat` → semua departemen pada `CoCode` karyawan.
   - `kabag`, `adm` → departemen dengan `ABRV` dan `CoCode` sama dengan departemen karyawan (BR-24, BR-28).
   - `mo` → anggota grup aktif `MILL` pada `CoCode` karyawan (`dbo.DepartmentGroupMember`).
   - Tidak punya role CIMS → 0 baris.
   Role user dibaca dengan pola yang sama dengan `usp_Auth_GetUserRoles` (`STRING_SPLIT` + `TRIM`).
   **Lingkup ini hanya untuk melihat data.** Hak approve ditentukan langkah workflow di T2 (BR-63: approver
   hanya untuk request dengan `CoCode` sama dengan `CoCode` karyawannya).
4. Test SQL di akhir file (blok komentar): satu user per role; user QC (C500) melihat C500 dan D500;
   user `mo` melihat 6 departemen MILL; user dengan `kabag;civil` melihat semua; user resign → 0 baris
   di `usp_Auth_GetUserByUsername`.

### B.2 Kode (setelah B.1 PASS)

- `Models/CurrentUser`: tambah `DepartmentID` (int) dan, bila perlu, `DeptCoCode`. Pertahankan properti lain.
- `Filters/CimsRoles` (const string 9 role + array `All`), `Filters/RoleAuthorizeAttribute` (MVC → Home/NotAuthorized),
  `Filters/RoleAuthorizeApiAttribute` (AJAX/API → 403 JSON `{ success:false, message:"Tidak berwenang" }`),
  `Filters/AllowAllRolesAttribute` (= punya minimal satu role CIMS). Semantik any-of, case-insensitive,
  membaca `ICurrentUserService.CurrentUser.Roles` (tanpa query ulang).
- **Default deny global**: user tanpa satu pun role di `CimsRoles.All` → NotAuthorized di semua halaman kecuali
  `Home/NotAuthorized`, `Home/Error`, `Home/LogOut` (pakai daftar pengecualian yang sama dengan `ProfileAttribute`).
  `Home/Index` memakai `[AllowAllRoles]`.
- Kegagalan memuat role: sekarang **memblokir** (default deny), bukan hanya dicatat. Catat error dan arahkan
  ke NotAuthorized/403. Sesuaikan komentar di `ProfileAttribute`.
- `CustomerController`: `[RoleAuthorize(CimsRoles.Administrator)]` di level controller.
- `_Sidebar.cshtml`: tambah properti `Roles` pada `MenuItem` (kosong = semua role CIMS). Customer =
  `administrator`. Item lain yang masih nonaktif ("Segera") tetap tampil untuk semua role CIMS.
  Grup yang semua anak-nya tersembunyi ikut disembunyikan.
- Tidak ada perubahan pada middleware SSO, logout, notifikasi, atau tampilan role di dropdown.
- CLAUDE.md bagian "Autentikasi": ganti baris "Otorisasi berbasis role BELUM aktif" dan "Tahap B (rencana...)"
  dengan bagian **"Otorisasi"** maksimal 10 baris: 9 role CIMS, any-of, default deny, `CimsRoles`,
  `[RoleAuthorize]`/`[RoleAuthorizeApi]`/`[AllowAllRoles]` (hanya untuk read-only), lingkup data wajib lewat
  `dbo.fn_User_AllowedDepartments(@Username)` di setiap SP list/detail transaksi, hak approve dari workflow (T2),
  dan "modul baru wajib menentukan role per action sesuai matriks PRD 5.2".

## Test

- User `gm;civil` (atau kombinasi nyata lain): lolos endpoint yang mengizinkan salah satu role (kasus gagal di Training).
- User hanya `emp` atau `spv`: NotAuthorized di semua halaman, tanpa loop redirect; Logout tetap berfungsi.
- User `administrator`: menu dan halaman Customer bisa diakses. User `civil`: menu Customer tidak tampil,
  akses URL `/Customer` langsung → NotAuthorized; AJAX → 403 JSON tampil di SweetAlert2.
- User resign (uji dengan user dev yang kolom resign-nya diisi tanggal kemarin di DB dev) → NotAuthorized.
- Ganti `Auth:DevUsername` ke beberapa user nyata (`adm`, `kabag`, `mo`, `fat`, `civil`) untuk menguji di atas.
- `dotnet build`: 0 error, 0 warning baru.

## Cara kerja

1. Tampilkan rencana lengkap (file SQL dan file kode yang diubah/dibuat) dan tunggu persetujuan saya.
2. Kerjakan B.1 saja. Berhenti. Saya jalankan di database dev dan menjawab PASS.
3. Setelah PASS: B.2, lalu `dotnet build`.
Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result, lalu berhenti dan tunggu PASS.
