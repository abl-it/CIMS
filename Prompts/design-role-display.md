# Tugas: Tampilkan role user di dropdown header (menggantikan jabatan/JobTitle)

Baca CLAUDE.md terlebih dahulu dan ikuti semua aturannya.

**Prasyarat:** Tahap A (design-auth) sudah berjalan: `CurrentUser`, `ProfileAttribute` global, dan dropdown
user di header (nama, jabatan, departemen, "Kembali ke Portal", Logout). Cek dulu di project. Jika tidak ada,
berhenti dan laporkan.

## Ruang lingkup (penting)

Tugas ini hanya **MENAMPILKAN** role. Ini bagian awal dari Tahap B (`design-role.md`), bukan seluruhnya.
- TIDAK ada perubahan hak akses: tanpa filter RoleAuthorize, tanpa default-deny, tanpa menyembunyikan menu.
  Semua yang bisa diakses user sekarang tetap bisa diakses.
- Filter, default-deny, dan sidebar per role tetap ditunda sampai PRD menetapkan role (design-role.md).

## Perubahan tampilan

Pada panel dropdown user, baris kedua yang sekarang menampilkan jabatan (contoh "Manager IT") diganti dengan
**role tertinggi** user. Baris departemen dan item lain tidak berubah.
- Teks yang tampil: `Description` bila terisi, jika kosong tampilkan kode role.
- Jika user punya lebih dari satu role CIMS: tampilkan hanya yang tertinggi, dan daftar semua role
  (urut dari yang tertinggi, dipisah koma) pada atribut `title` baris itu.
- Jika user tidak punya satu pun role yang terdaftar di tabel: tampilkan teks muted "Belum ada role".
  Ini tidak memblokir akses apa pun.
- Tombol dropdown (saat tertutup) tetap menampilkan nama dan departemen seperti sekarang.
- Jabatan (JobTitle) tidak lagi ditampilkan di dropdown, tetapi properti di `CurrentUser` boleh tetap ada.
- `PortalRole` (jika dibuat di Tahap A) tidak dipakai untuk tampilan ini.
- Mobile 360px: dropdown tidak terpotong dan tetap bisa disentuh.

## Database/Role.sql (kerjakan DULU, lalu berhenti dan tunggu PASS)

Ikuti spesifikasi B.1 pada Prompts\design-role.md (tabel `dbo.HierarchyLevel` dengan kolom `Role VARCHAR(50)`
PK, `HierarchyLevel INT NOT NULL`, `Description NVARCHAR(100) NULL`, dan `dbo.usp_Auth_GetUserRoles` berbasis
`STRING_SPLIT`), dengan satu perbedaan: **seed sementara** memakai daftar dari Training berikut, dengan
`Description` dikosongkan (NULL). Seed ini akan saya sesuaikan setelah PRD (cukup mengubah isi tabel).

| Role | HierarchyLevel |
|---|---|
| administrator | 1 |
| komisaris | 2 |
| director | 3 |
| gm | 4 |
| tc | 5 |
| mo | 6 |
| kabag | 7 |
| plan | 8 |
| spv | 9 |
| adm | 10 |
| emp | 11 |
| creator | 12 |

- Seed memakai `MERGE` sehingga script bisa dijalankan ulang.
- `STRING_SPLIT` perlu compatibility level >= 130. Jika database dev lebih rendah, laporkan, jangan mengubah
  database. Jangan menjalankan script SQL.

## Kode (setelah SQL PASS)

- `Models/CurrentUser`: tambahkan `Roles` (daftar: Role, HierarchyLevel, Description; urut level naik) dan
  properti turunan `HighestRole` (null bila kosong).
- `AuthService`: `GetUserRolesAsync(username)` (Dapper, `usp_Auth_GetUserRoles`).
- `ProfileAttribute` (global): muat role sekali per request setelah memuat user, isi `CurrentUser.Roles`.
- Blok user di header (ViewComponent atau partial yang sudah ada): ganti baris jabatan sesuai aturan di atas.
- Pertahankan semua yang sudah ada: dev bypass, redirect login, NotAuthorized, logout POST, toast, SweetAlert2.
- CLAUDE.md, bagian "Autentikasi": tambahkan 3 baris: role ditampilkan di dropdown (`HighestRole`), sumber role
  (`home.dbo.Users.Role` dicocokkan dengan `dbo.HierarchyLevel`), dan otorisasi berbasis role belum aktif
  (menunggu design-role.md).

## Test

- Dev dengan `Auth:DevUsername` yang punya role di tabel: dropdown menampilkan role tertinggi. Tooltip baris
  itu memuat semua role.
- User dengan beberapa role: yang tampil adalah level terkecil. Role yang tidak ada di tabel diabaikan.
- User tanpa role terdaftar: "Belum ada role", halaman tetap bisa dibuka seperti sebelumnya.
- Ubah isi `dbo.HierarchyLevel` (mis. isi `Description` untuk satu role): tampilan ikut berubah tanpa
  perubahan kode.
- Hak akses tidak berubah: Customer (list, tambah, ubah, nonaktifkan) berjalan seperti sebelum perubahan.
- Mobile 360px: dropdown tampil utuh.
- `dotnet build`: 0 error, 0 warning.

## Cara kerja

1. Tampilkan rencana singkat dan tunggu persetujuan saya.
2. Kerjakan `Database/Role.sql` saja. Berhenti. Saya jalankan di database dev dan jawab PASS.
3. Setelah PASS: kode, lalu dotnet build.
Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result, lalu berhenti dan tunggu PASS.
