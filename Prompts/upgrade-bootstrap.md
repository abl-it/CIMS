# Tugas: Upgrade Bootstrap 5.3 + catat Modul Acuan Customer

Baca CLAUDE.md terlebih dahulu dan ikuti semua aturannya.

Versi Bootstrap lokal di wwwroot/lib/bootstrap saat ini adalah 5.1.0.

## A. Upgrade Bootstrap ke 5.3.x stabil terbaru

- Ganti file di wwwroot/lib/bootstrap/dist (css dan js) memakai paket resmi
  (npm registry "bootstrap" atau jsDelivr).
- Jangan ubah struktur folder, nama file, atau referensi di _Layout.cshtml.
- Jangan sentuh library lain (jquery, jquery-validation, jquery-validation-unobtrusive).
- Tampilkan rencana dulu (sumber unduhan, file yang diganti) dan tunggu persetujuan saya
  sebelum mengubah file apa pun.

## B. Verifikasi setelah upgrade

- Pastikan versi pada header bootstrap.css sudah 5.3.x.
- Jalankan dotnet build (target: 0 error, 0 warning).
- Periksa apakah ada class/komponen di Views Customer dan _Layout.cshtml yang terdampak
  perubahan 5.1 -> 5.3. Laporkan temuan saja, jangan ubah tanpa persetujuan saya.

## C. Update CLAUDE.md

1. Ubah "Bootstrap 5" menjadi
   "Bootstrap 5.3 (lokal di wwwroot/lib/bootstrap, bukan CDN)".
2. Tambahkan bagian "Modul Acuan: Customer" yang merangkum pola modul ini
   (maksimal 25 baris, ringkas):
   - daftar file per layer (SQL, Model, Service, Controller, ViewModel, Views)
   - exception 50001/50002/50003 dan pemetaannya di Controller
   - PagedResult
   - pola PRG + TempData
   - pola list: search, filter status, sort whitelist, paging
   - pola view mobile-first
   Tulis bahwa modul baru wajib mengikuti pola ini.

## Format laporan

Diagnosis / Perubahan / Test / Expected Result.
Setelah selesai, berhenti dan tunggu saya menjawab PASS.
