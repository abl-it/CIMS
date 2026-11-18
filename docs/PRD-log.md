# PRD CIMS: Log Keputusan

Pendamping `docs/PRD.md`.


| Tanggal | Keputusan | Ref |
|---|---|---|
| 2026-10-31 | Flow `CIMS.pdf` jadi baseline workflow | BR-04..BR-22 |
| 2026-10-31 | Kategori dipilih requester, boleh diubah Civil | BR-02 |
| 2026-10-31 | Rejected (alasan wajib), Cancelled (requester), revisi tidak dibatasi | BR-08..BR-10 |
| 2026-10-31 | Purchasing input vendor, nilai kontrak, lampiran kontrak | BR-11 |
| 2026-10-31 | FAT = Finance, Accounting & Tax. GM dan Director level pabrik. Alur: adm → kabag → civil → GM → Director (CAPEX) | BR-01, BR-03, BR-07, BR-23 |
| 2026-10-31 | Plan cost: kontrak / BOQ disetujui; estimasi total per bulan (tidak per item) = plan cost | BR-12, BR-13 |
| 2026-10-31 | Actual cost: satu template Excel per bulan, per item barang/jasa, ditotal vs estimasi; upload ulang menimpa | BR-18, BR-19 |
| 2026-10-31 | Progress berbobot per action plan mingguan, kurva S | BR-16, BR-17 |
| 2026-10-31 | Director hanya CAPEX; Emergency eksekusi dulu; Preventive dijadwalkan Civil | BR-07, BR-25, BR-26 |
| 2026-10-31 | Kabag Approve/Revise/Reject; revisi lewat approval ulang; BAPP dan survei oleh Kabag | BR-03, BR-04, BR-20, BR-22 |
| 2026-10-31 | Role `civil`, `fat` (5), `purchasing` (6); role umum portal otomatis masuk; resign ditolak; satu role civil; tanpa delegasi | RL-01..RL-08, BR-27, BR-31, BR-35, BR-36 |
| 2026-10-31 | Lingkup departemen adm/kabag, gabungan role, larangan self-approve | BR-28..BR-30 |
| 2026-10-31 | Overdue = warning, batas hari di tabel | BR-32, BR-33 |
| 2026-10-31 | Workflow approval disimpan di tabel; batas desain 3.9 disetujui; snapshot saat Submit | 3.9, BR-37 |
| 2026-10-31 | **Departemen Mill (4 dept) wajib approval MO setelah Kabag; role `mo` akses 5 departemen** | BR-50, BR-51, RL-09 |
| 2026-10-31 | Department otomatis dari departemen `adm` (terkunci); cost center cascade dari `APP_SubDepartments` | BR-40 |
| 2026-10-31 | Nomor request format form `{ABRV}-{CPX/OPX/LVE}-{MM}-{YY}-{NNN}`; ikut berubah bila Civil ubah kategori | BR-41, BR-54 |
| 2026-10-31 | Sub-kategori dipilih requester (cascade), boleh diubah Civil | BR-02 |
| 2026-10-31 | Environment Assessment dari tabel (snapshot); foto area wajib | MD-08, BR-43 |
| 2026-10-31 | Master MVP: sub-kategori, lokasi, vendor, satuan; Customer disimpan sebagai acuan pola | 6.2 |
| 2026-10-31 | Lampiran di `D:\APP_DATA\CIMSAttachments`, format dan ukuran di tabel | BR-44, BR-45 |
| 2026-10-31 | Survei: item dinamis dengan template default dari form | BR-47 |
| 2026-11-02 | Satu ABRV = satu Kabag (QC, ENG, UTL, MO, WH-LOG); lingkup adm/kabag per ABRV + Company | BR-24, BR-28 |
| 2026-11-02 | Grup MILL = C100, C200, D100, D200, C600, D600 (satu MO); MO tidak ikut BAPP | 3.9, BR-50 |
| 2026-11-02 | CIMS untuk ABL dan NKM, dengan filter Company | 3.10, BR-56 |
| 2026-11-02 | Nomor saat ganti kategori: bulan/tahun tetap; PIC dari karyawan aktif departemen requester | BR-54, 6.1 |
| 2026-11-02 | BAPP NKM Kabag → FAT → Director; approve hanya Company sendiri; Emergency dibuat Civil, approval susulan 3 hari kerja (tabel); Preventive manual tanpa approval; BOQ wajib semua, Drawing wajib CAPEX | 3.2, 3.9, BR-05, BR-25, BR-26, BR-63, BR-64 |
| 2026-11-02 | Tanpa notifikasi (hanya shortcut Tugas Saya di dashboard); tanpa overdue approval; tanpa integrasi selain SSO | BR-32, BR-66, BR-67, FR-01 |
| 2026-11-02 | Emergency tetap warning 3 hari kerja; status jadwal/biaya/keseluruhan dan 4 KPI disetujui; KPI hanya untuk review (tanpa owner/CA-PA) | BR-65, BR-68..BR-73, KPI-01..KPI-04 |
| 2026-11-02 | Tahap T0-T8 disetujui; MVP = T0-T6 + dashboard dasar; go-live 1 Desember 2026; input project berjalan; export Excel | 9 |
| 2026-11-02 | Development selesai sebelum 1 Des; UAT 2 minggu oleh Civil dan developer; pain point disetujui; baseline belum ada (diukur pasca go-live); badge tugas; format/ukuran lampiran; isi satuan | 0, 2, 9.2, 9.5, FR-02, 6.5, MD-04 |
| 2026-11-02 | Civil ABL melayani NKM; alur NKM Kabag → Civil → Director (dinamis); lintas Company: administrator, civil, director, gm; nomor NKM berprefiks `NKM-`; lokasi dan workflow per Company | BR-57..BR-62 |
| 2026-11-02 | Semua asumsi Lampiran A disetujui; BR-15 direvisi: tanggal mulai project dari schedule Civil, periode Preparation dari kontrak selesai sampai mulai project; go-live 15 Des; rollout ABL+NKM bersamaan. PRD FINAL v1.0 | BR-15, Lampiran A |
| 2026-11-03 | Periode Preparation project in-house: dari selesainya management approval sampai tanggal mulai project. Tidak ada asumsi tersisa | BR-15 |
| 2026-11-03 | Hari libur mingguan hanya Minggu; Sabtu adalah hari kerja (ABL dan NKM) | CF-07, MD-11, BR-64 |
| 2026-11-03 | Role `plan`, `spv` setara `adm` (boleh membuat request); `emp` hanya lihat; lingkup data ketiganya = `adm` (ABRV + Company) | RL-10..RL-12, BR-01, BR-27, 5.2, 5.4 |
| 2026-11-04 | Tanggal libur = gabungan `home..APP_Holidays` (portal, semua Company) + libur tambahan per Company (`WorkCalendarHoliday`) | CF-07, MD-11, BR-64 |
| 2026-11-04 | Halaman Settings (administrator saja): ubah nilai 5 key AppSetting (batas Emergency, ambang jadwal/biaya); key dan override tetap via SQL | BR-38, CF-02, CF-08 |
| 2026-11-04 | T2 dipecah: T2-1 Draft, T2-2 Submit, T2-3 Approval REQUEST, T2-4 List + Tugas Saya. Save Draft minimal (Title + kategori); kelengkapan penuh dicek saat Submit. Resubmit setelah revisi: nomor tetap, langkah approval di-snapshot ulang dari tabel | 9.1, BR-04, BR-37, BR-41 |
| 2026-11-04 | PIC disimpan dengan `EmployeeCode` (unik); cost center = `APP_SubDepartments.SubDepartmentID` milik `DepartmentID` requester | 6.1, BR-40 |
| 2026-11-13 | Tugas Saya "Request di-Revise/Reject" hanya untuk pembuat request (`RequesterUsername`), bukan semua adm/plan/spv departemen | 7.1, FR-01 |
| 2026-11-13 | T3 dipecah: T3-1 Feasibility (Yes/Revise/Reject, ubah kategori + renumber), T3-2 Document Preparation + kirim ke management, T3-3 Management approval GM/Director | 9.1, 3.1 |
| 2026-11-13 | Civil mengisi nilai "BOQ total (IDR)" di Document Preparation, wajib sebelum dikirim ke management (dasar plan cost in-house) | BR-05, BR-12 |
| 2026-11-13 | Civil boleh mengubah kategori ke CAPEX saat Feasibility; Civil boleh mengunggah lampiran ROI; lampiran wajib kategori baru harus lengkap sebelum Feasibility = Yes. ROI dikosongkan bila kategori bukan CAPEX lagi | BR-02, BR-42, BR-54 |
| 2026-11-13 | BOQ total disimpan di `ProjectRequest.BoqTotal` (migrasi kolom nullable), perubahan dicatat di riwayat. Kirim ke management menyusun langkah MGMT dari tabel saat itu (ronde baru); tanpa langkah MGMT langsung Planning | BR-05, BR-12, BR-53 |
| 2026-11-14 | T4 dipecah 3: T4-1 master Vendor + In-house/Outsource + TOR + kontrak Purchasing; T4-2 schedule, action plan berbobot, estimasi biaya bulanan, site handover; T4-3 input project berjalan | 9.1, 3.3, MD-03 |
| 2026-11-14 | Purchasing boleh mengembalikan TOR ke Civil (status kembali Planning, alasan wajib, tercatat di riwayat) | BR-11 |
| 2026-11-14 | Schedule, action plan, dan estimasi biaya tetap boleh diubah Civil saat In Progress, dengan alasan wajib yang tercatat | BR-13, BR-14, BR-16 |
| 2026-11-14 | Plan progress per minggu (kurva S): bobot action plan disebar linear per hari antara tanggal mulai dan selesai plan | BR-17 |
| 2026-11-14 | Master Vendor punya Nomor Vendor ERP (opsional, unik bila diisi) | MD-03 |
| 2026-11-14 | T4-2: tanggal mulai project diisi Civil; tanggal selesai project = tanggal selesai plan terakhir dari action plan. Total bobot 100% dan total estimasi = plan cost wajib saat site handover (draft boleh belum lengkap); saat In Progress setiap simpan wajib lengkap + alasan | BR-13, BR-15, BR-16 |
| 2026-11-14 | Estimasi biaya bulanan hanya untuk bulan mulai s.d. bulan selesai project | BR-13 |
| 2026-11-14 | Tanggal site handover: pada/sesudah tanggal mulai project dan tidak di masa depan | ST-11 |
| 2026-11-16 | Input project berjalan: dicatat langsung di Planning atau Scheduling; project yang sudah In Progress masuk Scheduling lalu schedule + site handover (tanggal lampau) lewat alur T4-2 | FR-03 |
| 2026-11-16 | Project berjalan outsource: kontrak (vendor, nomor, tanggal, nilai) diinput Civil di form input; plan cost = nilai kontrak. In-house: plan cost = BOQ total | FR-03, BR-11, BR-12 |
| 2026-11-16 | Field wajib project berjalan: departemen, judul, kategori, sub-kategori, lokasi; lainnya opsional | FR-03 |
| 2026-11-16 | T5 dipecah 3: T5-1 progress mingguan + kurva S + status jadwal; T5-2 master Satuan + actual cost per item (manual) + status biaya dan keseluruhan; T5-3 upload template Excel + arsip file | 9.1, MD-04, BR-18, BR-19 |
| 2026-11-16 | Minggu progress = Senin s.d. Minggu, satu catatan per project per minggu (simpan ulang menimpa); % plan diambil pada hari Minggu minggu itu; progress hanya untuk minggu mulai project s.d. minggu berjalan | BR-16, BR-17, BR-68 |
| 2026-11-16 | Tanggal mulai/selesai aktual per action plan diisi Civil (mulai wajib bila progress > 0, selesai wajib bila 100%) | Data 4 |
| 2026-11-16 | Progress per action plan tidak boleh turun dibanding minggu sebelumnya; koreksi dengan menyimpan ulang minggu yang sama. Action plan yang sudah punya progress tidak bisa dihapus | BR-16 |
| 2026-11-16 | Tugas Saya "Weekly progress" untuk civil: project In Progress yang progress minggu berjalan belum disimpan; hilang setelah disimpan | 7.1, FR-01, BR-16, BR-66 |
| 2026-11-16 | Actual cost manual: seluruh item satu bulan disimpan sekaligus dan menimpa bulan itu (sama dengan upload ulang); daftar kosong = hapus bulan; tercatat di riwayat | BR-18, BR-19 |
| 2026-11-16 | Bulan actual cost: dari bulan awal Preparation s.d. bulan berjalan; input saat In Progress dan BAPP Review | BR-18 |
| 2026-11-16 | Satuan item actual diketik bebas; master Satuan (MD-04) hanya daftar saran | MD-04, 6.4 |
| 2026-11-16 | Status biaya: actual sebelum bulan estimasi pertama dibandingkan dengan estimasi bulan pertama; actual tanpa estimasi sama sekali = Over Budget; amount item = qty × harga satuan dengan toleransi pembulatan IDR 1 | BR-69, 6.4 |
| 2026-11-16 | Library baca/tulis Excel: ClosedXML (MIT) untuk upload actual cost dan template unduhan | BR-18, 9 (catatan teknis) |
| 2026-11-16 | Upload actual cost di satu halaman pusat (Cost Management > Actual Cost Upload); satu file banyak project/bulan; tiap project + bulan menimpa bulan itu | BR-18, BR-19 |
| 2026-11-16 | Upload all or nothing: satu baris salah = tidak ada yang disimpan, error per nomor baris ditampilkan; preview per project + bulan lalu konfirmasi; file yang lolos validasi diarsipkan (PENDING/IMPORTED/CANCELLED) | BR-18, BR-19 |
| 2026-11-16 | T6 ditunda; dashboard dasar dikerjakan lebih dulu. Halaman Dashboard terpisah (Home tetap shortcut Tugas Saya) | 9.1, FR-01 |
| 2026-11-16 | Kartu dashboard per kategori: project aktif (In Progress + BAPP) per status keseluruhan (belum dihitung = On Track), plan cost vs estimasi vs actual s.d. bulan, pipeline (Approval, Civil review, Preparation, Closed di bulan) | 8.1, BR-70, 9.1 |
| 2026-11-16 | Filter bulan dashboard: biaya kumulatif s.d. bulan itu + Closed di bulan itu; status = nilai terakhir (riwayat status tidak disimpan) | 9.1 |
| 2026-11-16 | Export Excel tahap ini: tabel project dashboard dan Request List sesuai filter aktif; list lain menyusul bersama modulnya | FR-04 |
| 2026-11-16 | Perubahan scope: grafik dasar ditarik dari T8 ke MVP dengan Chart.js (lokal di wwwroot/lib): dashboard (status keseluruhan per kategori, biaya bulanan estimasi vs actual) dan Details (kurva S progress, kurva biaya kumulatif). Grafik Plan vs Actual lengkap, Gantt, dan KPI tetap T8 | 9.1, BR-17, BR-69, BR-70 |
| 2026-11-16 | Perubahan scope: Gantt plan vs actual per action plan di Details > Schedule (Frappe Gantt 0.6.1 lokal, MIT; hanya tampilan). Menu Gantt per kategori (CAPEX/OPEX/LVE) tetap T8 | 9.1, BR-15, BR-16, Data 4 |
| 2026-11-16 | Approval di luar sistem: baris opsional (langkah/role, nama, tanggal), tercatat di riwayat "Approved outside CIMS"; requester data migrasi = user civil penginput | BR-76, BR-77 |
| 2026-11-17 | Penambahan PRD: addendum untuk outsource (perubahan kontrak) dan in-house (perubahan budget/BOQ), saat Scheduling/Preparation atau In Progress; boleh lebih dari satu, riwayat tersimpan; tahap baru T4-4 | 3.3.1, BR-78, 9.1 |
| 2026-11-17 | Input addendum: outsource oleh Purchasing (nomor, tanggal, nilai kontrak baru total, alasan, lampiran addendum wajib); in-house oleh Civil (nilai BOQ baru total, lampiran BOQ revisi wajib) | BR-79 |
| 2026-11-17 | Approval addendum hanya bila nilai naik: titik workflow ADDENDUM (default ABL GM, NKM Director); nilai sama/turun tanpa approval; ditolak = addendum batal, nilai lama tetap | BR-80, 3.9 |
| 2026-11-17 | Selama addendum belum selesai: nilai lama berlaku; addendum lain dan perubahan schedule/estimasi dikunci; progress mingguan dan actual tetap bisa diinput | BR-81 |
| 2026-11-17 | Setelah addendum berlaku, Civil wajib menyesuaikan action plan + estimasi (Tugas Saya "Addendum adjustment"); selesai bila bobot 100% dan estimasi = nilai baru; plan cost = nilai baru | BR-82, BR-12, BR-13 |
| 2026-11-17 | Perubahan aturan 14-11/16-11: saat In Progress, action plan yang sudah punya progress hanya boleh diubah bobot dan tanggal selesai plan (nama, tanggal mulai terkunci; tidak boleh dihapus), berlaku untuk semua perubahan schedule termasuk in-house | BR-83, BR-16 |
| 2026-11-17 | Pengecualian aturan 16-11 (progress tidak turun): % penyelesaian project boleh turun karena perubahan bobot addendum; % per action plan dan data minggu lama tetap; kurva S plan dihitung ulang dari schedule terbaru | BR-84, BR-17 |
| 2026-11-17 | Penyesuaian estimasi addendum: bulan sebelum bulan berjalan dikunci | BR-85, BR-13 |
| 2026-11-17 | Hak lihat addendum: outsource = baris Kontrak, in-house = baris Feasibility/BOQ (emp boleh lihat departemen sendiri) | BR-86, 5.2 |
| 2026-11-17 | "Sudah punya progress" (BR-83) = progress mingguan tersimpan > 0% atau mulai aktual terisi; action plan yang selalu 0% boleh dihapus (baris 0% minggu lalu ikut dihapus) | BR-83, BR-16 |
| 2026-11-18 | Perubahan: addendum outsource juga di-raise Civil (tidak lewat Purchasing; Purchasing hanya lihat) dengan draft kontrak baru wajib; nomor dokumen referensi opsional untuk outsource dan in-house | BR-79, BR-86, 5.2 |
| 2026-11-18 | Addendum outsource: setelah disetujui / tanpa approval, Civil wajib upload kontrak final bertanda tangan sebagai langkah terpisah sebelum penyesuaian dibuka (semua addendum outsource) | BR-87, BR-80, BR-82 |
| 2026-11-18 | FAT bisa membuka Request List dan Details, hanya project In Progress, BAPP Review, Closed, Survey Completed (Company sendiri); semua bagian Details tampil baca saja (business case dan Feasibility/BOQ menjadi R untuk FAT). Untuk user dengan role gabungan (mis. `kabag;fat`), batas status hanya berlaku pada departemen yang terlihat semata-mata karena role FAT; departemen dari role lain tetap semua status | RL-05, 5.2 |
| 2026-11-18 | Site handover diblok selama addendum masih terbuka (menunggu approval / kontrak final / penyesuaian); dibuka lagi setelah addendum selesai atau ditolak | ST-11, BR-81 |
| 2026-11-18 | Request List: tanda addendum terbuka (menunggu approval / penyesuaian) di kolom Status + filter "Addendum open" + kolom di Export; hanya addendum yang boleh dilihat user (BR-86) | BR-80, BR-81, BR-86, FR-04 |
| 2026-11-18 | Nomor addendum otomatis `{RequestNo}-A{n}`; nomor dokumen referensi wajib untuk outsource (dokumen addendum kontrak), opsional untuk in-house | BR-79 |
| 2026-11-17 | Setelah bobot/schedule berubah saat In Progress: % aktual, % plan, dan status jadwal ringkasan project dihitung ulang pada minggu terakhir tersimpan; baris minggu lama tidak diubah | BR-84, BR-17, BR-68 |
| 2026-11-18 | T6 dipecah 2: T6-1 BAPP + approval BAPP + Project Closed; T6-2 survei kepuasan + halaman User Satisfaction | 9.1, 3.4, 6.6 |
| 2026-11-18 | Terbit BAPP (Civil, In Progress): semua action plan 100% + tanggal selesai aktual, lampiran BAPP wajib, tanpa addendum terbuka; data nomor BAPP (opsional), tanggal, catatan | BR-88, BR-81 |
| 2026-11-18 | BAPP No: alasan wajib, kembali In Progress; terbit ulang = ronde baru dari langkah pertama | BR-89, BR-20 |
| 2026-11-18 | Actual cost tidak bisa diubah setelah Closed (hanya sampai BAPP Review) | BR-90, BR-18 |
| 2026-11-18 | Survei: Civil klik Send survey setelah Closed; diisi kabag mana pun pada ABRV + Company departemen peminta (pertama berlaku); submit langsung Survey Completed (tanpa arsip Civil) | BR-91, BR-22, ST-14 |
| 2026-11-18 | Halaman User Satisfaction (daftar survei + filter + Export Excel) masuk T6-2 | BR-92, FR-04 |
| 2026-11-18 | BAPP No -> revisi schedule lewat aturan In Progress yang ada: tambah action plan rework (bobot lama dikurangi, % total boleh turun, BR-84), perpanjang tanggal selesai plan; action plan yang sudah 100% tidak dibuka ulang. BAPP diterbitkan ulang setelah semua action plan (termasuk rework) 100% | BR-89, BR-83, BR-84, BR-88 |
| 2026-11-18 | Perubahan: penutupan project online dengan form BAPP FM-DGO-03 (tanpa tanda tangan basah); dokumen BAPP tidak diupload; Civil isi tanggal BAPP + lingkup pekerjaan, foto opsional | 3.4, BR-88 |
| 2026-11-18 | Rantai BAPP ABL: Kabag user -> FAT -> DGO -> GM; NKM tetap Kabag -> FAT -> Director. Role baru `dgo` (lingkup dan hak lihat sama dengan FAT) | BR-20, 3.9, RL-13 |
| 2026-11-18 | Kabag isi Hasil pemeriksaan (D) saat review; Belum sesuai hanya dengan No. FAT wajib centang tidak ada outstanding, DGO wajib centang status CLOSED (NKM: sistem saat Closed) | BR-89, BR-93 |
| 2026-11-18 | Nomor BAPP otomatis NNN/BAPP/{Company}/{bulan romawi}/{tahun}, urut per Company per tahun, sama saat terbit ulang | BR-95 |
| 2026-11-18 | Cetak Berita Acara setelah Closed oleh Civil: halaman cetak A4 (Save as PDF), Bahasa Indonesia sesuai template, tanda tangan digital (nama + waktu accept online); kop ABL gambar, NKM teks; PIC Project = Civil penerbit; Civil/Kontraktor = vendor (outsource) / Civil (in-house) | BR-94 |
| 2026-11-18 | Perubahan: foto dokumentasi Lampiran 2 wajib sebelum terbit BAPP (foto tahap awal, proses, hasil akhir; masing-masing minimal satu) | BR-88, BR-94 |
| 2026-11-18 | Lampiran detail cost per project per bulan wajib: input manual ditolak tanpa lampiran (unggah di form bulan); bulan hasil upload Excel ditandai missing attachment lalu dilengkapi di Details; lampiran terakhir tidak bisa dihapus; PDF/XLSX/JPG/PNG maks. 20 MB | BR-96, BR-18 |
| 2026-11-18 | T6-2 Survei: halaman User Satisfaction menampilkan semua project Closed (Not sent / Waiting / Completed + skor); filter periode = tanggal submit (belum diisi: tanggal kirim; belum dikirim: tanggal Closed); hak lihat sesuai matriks 5.2 (kabag dept, mo grup, civil, gm, director, administrator); submit Kabag final | BR-91, BR-92, 5.2 |
| 2026-11-18 | Tugas Saya: Civil 'Send survey' untuk project Closed yang belum dikirim survei; Kabag departemen peminta 'Fill survey' untuk survei terkirim | BR-91, 7.1 |
