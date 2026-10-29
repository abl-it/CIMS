# Tugas: Buat modul baru mengikuti pola modul Customer

Baca CLAUDE.md (termasuk bagian "Modul Acuan: Customer") terlebih dahulu.
Buat modul di bawah ini mengikuti pola modul Customer persis:
struktur file, penamaan, exception, PRG, dan view mobile-first.

## Nama modul

[ISI NAMA MODUL, contoh: Supplier]

## Kolom

[ISI: nama kolom | tipe | panjang | wajib/opsional | unik]
Contoh:
- Id | INT identity | - | wajib | PK
- Code | NVARCHAR | 20 | wajib | unik
- Name | NVARCHAR | 100 | wajib | -

## Aturan khusus

[ISI: relasi ke tabel lain, validasi bisnis, status, dsb. Tulis "tidak ada" jika kosong]

## Fitur

[ISI, contoh: list dengan search/filter/sort/paging, create, edit, detail, soft delete]

## Cara kerja (berhenti dan tunggu PASS di setiap tahap)

Tahap A:
- Tampilkan rencana lengkap semua file: SQL, Model, Service, Controller, ViewModel,
  Views, registrasi DI, menu navbar.
- Lalu tulis HANYA Database/[NamaModul].sql.
- Berhenti. Saya akan menjalankan SQL di database dev dan menjawab PASS.

Tahap B:
- Model, Service, registrasi DI, Controller, ViewModel.
- Jalankan dotnet build.

Tahap C:
- Views dan menu navbar.
- Jalankan dotnet build.

## Format laporan

Diagnosis / Perubahan / Test / Expected Result.
