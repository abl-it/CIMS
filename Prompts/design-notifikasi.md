# Tugas: Standar notifikasi, SweetAlert2 (konfirmasi dan error) + Bootstrap Toast (sukses)

Baca CLAUDE.md terlebih dahulu dan ikuti semua aturannya.
Tugas ini berlaku untuk seluruh aplikasi. Terapkan pertama kali pada modul Customer.

## Aturan desain (wajib untuk semua modul)

1. **Konfirmasi** (nonaktifkan/aktifkan, hapus, batal dengan perubahan belum tersimpan,
   aksi berisiko lainnya) memakai **SweetAlert2**.
   Dilarang: confirm() / alert() bawaan browser, dan modal Bootstrap untuk konfirmasi.
2. **Error** memakai **SweetAlert2** (icon error). Ini mencakup:
   - TempData["Error"]
   - error AJAX/fetch (respons non-2xx dan kegagalan jaringan)
   - error umum dari server (bukan error field)
   Pengecualian: validasi per field tetap tampil inline di bawah input
   (asp-validation-for / ModelState field error). Contoh: kode duplikat tetap
   muncul di bawah field Code.
3. **Sukses** memakai **Bootstrap Toast** (bukan SweetAlert2):
   - text-bg-success, posisi pojok kanan atas (top-end), auto-hide 4 detik,
     ada tombol tutup.
   - Sumber: TempData["Success"] dan aksi AJAX yang berhasil.
4. Di luar tiga kasus di atas (mis. info atau warning), tanyakan dulu kepada saya.

## Implementasi

A. **SweetAlert2 lokal**, bukan CDN (sama seperti Bootstrap).
   - Taruh di wwwroot/lib/sweetalert2 (file sweetalert2.all.min.js, sudah termasuk CSS).
   - Unduh dari paket resmi (npm registry "sweetalert2" atau jsDelivr).
   - Tampilkan rencana dulu (sumber unduhan, versi, file yang ditambahkan)
     dan tunggu persetujuan saya sebelum mengubah file.
   - Referensikan di _Layout.cshtml sebelum notify.js.

B. **wwwroot/js/notify.js** (baru) dengan API global:
   - notify.success(message): menampilkan Bootstrap Toast.
   - notify.error(message, title?): menampilkan Swal icon error.
   - notify.confirm({ title, text, confirmText, cancelText, danger }): mengembalikan
     Promise<boolean>.
   - notify.fetchError(responseOrError): helper untuk error fetch
     (respons non-2xx dan kegagalan jaringan), memakai notify.error.
   - Konfirmasi deklaratif: form, button, atau link dengan atribut
     data-confirm="pesan" (opsional data-confirm-title, data-confirm-ok)
     otomatis memunculkan SweetAlert2 dan hanya melanjutkan submit/navigasi
     jika pengguna memilih Ya. Pastikan token anti-forgery tetap terkirim.

C. **_Layout.cshtml**:
   - Tambahkan toast container (position-fixed, top-0 end-0, p-3, z-index di atas navbar).
   - Buat partial Views/Shared/_Notifications.cshtml yang membaca
     TempData["Success"] -> notify.success dan TempData["Error"] -> notify.error.
     Render sekali di _Layout setelah script dimuat.
   - Encode nilai TempData dengan aman (Json.Serialize atau data-attribute).
     Jangan menyisipkan teks mentah ke dalam string JavaScript (risiko XSS).

D. **Views Customer**:
   - Hapus alert Bootstrap untuk TempData jika ada (digantikan toast/swal).
   - Aksi SetActive memakai data-confirm.
   - Error umum dari server memakai notify.error.
   - Jangan ubah Controller kecuali benar-benar perlu. Jika perlu, jelaskan alasannya.

E. **CLAUDE.md**:
   - Tambahkan bagian "Notifikasi dan Dialog" berisi aturan 1-4, daftar API notify,
     dan larangan confirm()/alert().
   - Perbarui bagian AJAX: error fetch memakai notify.error, sukses memakai notify.success.
   - Perbarui bagian Komponen dan Checklist UI agar tidak bertentangan
     (mis. hapus anjuran "toast/alert" generik).

F. **Mobile**:
   - Toast tidak menutupi navbar atau tombol utama dan lebarnya menyesuaikan layar kecil.
   - Tombol SweetAlert2 mudah disentuh.
   - Uji di lebar sekitar 360px.

## Test

- Create berhasil: toast hijau muncul lalu hilang sendiri (4 detik), tanpa dialog swal.
- Kode duplikat: error inline di bawah field Code (tetap), bukan swal.
- SetActive: swal konfirmasi. Batal = tidak ada request. Ya = diproses, lalu toast sukses.
- Error umum (TempData["Error"], atau simulasi database mati): swal icon error.
- Cari sisa confirm( dan alert( bawaan browser di seluruh Views dan js: harus nihil.
- dotnet build: 0 error, 0 warning.

## Cara kerja

Tampilkan rencana lengkap (file baru dan file yang diubah) dan tunggu persetujuan saya
sebelum menulis code. Laporkan dengan format Diagnosis / Perubahan / Test / Expected Result,
lalu berhenti dan tunggu PASS.
