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
