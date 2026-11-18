using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class RequestListViewModel
    {
        /// <summary>Filter Company (BR-57); hanya ditampilkan untuk role lintas Company.</summary>
        public string? CoCode { get; set; }

        /// <summary>Filter departemen (cascade dari Company); hanya departemen dalam lingkup user.</summary>
        public int? DepartmentId { get; set; }

        public string? Search { get; set; }
        public string? Category { get; set; }
        public string? Status { get; set; }

        /// <summary>Filter follow up: "open" = hanya project dengan addendum terbuka (T4-4); null = semua.</summary>
        public string? Addendum { get; set; }
        public bool AddendumOpen => Addendum == "open";

        public string SortBy { get; set; } = "CreatedAt";
        public string SortDir { get; set; } = "DESC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public bool ShowCompanyFilter { get; set; }
        public bool CanCreate { get; set; }

        /// <summary>Pilihan departemen (lingkup user); disaring per Company di browser.</summary>
        public IReadOnlyList<DepartmentOption> Departments { get; set; } = Array.Empty<DepartmentOption>();
        public PagedResult<RequestListItem> Result { get; set; } = new();
    }

    /// <summary>Jawaban satu pertanyaan assessment di form; QuestionText dimuat ulang dari database.</summary>
    public class RequestAnswerInput
    {
        public int QuestionId { get; set; }

        /// <summary>Nullable: tidak dikirim form (hindari implicit Required), diisi ulang dari database.</summary>
        public string? QuestionText { get; set; }

        public bool? Answer { get; set; }
    }

    /// <summary>
    /// Form Request (Draft). Validasi di sini hanya untuk Save Draft (Title + Category wajib, sisanya format);
    /// kelengkapan penuh dicek saat Submit (T2-2). Validasi akhir tetap di stored procedure.
    /// </summary>
    public class RequestFormViewModel
    {
        public int Id { get; set; }

        [Display(Name = "Request title")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(200, ErrorMessage = "{0} must be at most {1} characters.")]
        public string Title { get; set; } = string.Empty;

        [Display(Name = "Budget classification")]
        [Required(ErrorMessage = "{0} is required.")]
        [RegularExpression("^(CAPEX|OPEX|LVE)$", ErrorMessage = "{0} is invalid.")]
        public string Category { get; set; } = string.Empty;

        [Display(Name = "Sub-category")]
        public int? SubCategoryId { get; set; }

        [Display(Name = "Budget remarks")]
        [RegularExpression("^(BUDGETED|UNBUDGETED)$", ErrorMessage = "{0} is invalid.")]
        public string? BudgetRemarks { get; set; }

        [Display(Name = "Cost center")]
        public int? SubDepartmentID { get; set; }

        [Display(Name = "Location")]
        public int? LocationId { get; set; }

        [Display(Name = "PIC of project")]
        [StringLength(30)]
        public string? PicEmployeeCode { get; set; }

        [Display(Name = "Target completion")]
        [DataType(DataType.Date)]
        public DateTime? TargetCompletionDate { get; set; }

        [Display(Name = "Area length (m)")]
        [Range(typeof(decimal), "0.01", "99999999", ErrorMessage = "{0} must be greater than 0.")]
        public decimal? AreaLength { get; set; }

        [Display(Name = "Area width (m)")]
        [Range(typeof(decimal), "0.01", "99999999", ErrorMessage = "{0} must be greater than 0.")]
        public decimal? AreaWidth { get; set; }

        [Display(Name = "Budget expectation (IDR)")]
        [Range(typeof(decimal), "0", "9999999999999999", ErrorMessage = "{0} cannot be negative.")]
        public decimal? BudgetExpectation { get; set; }

        [Display(Name = "Background")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Background { get; set; }

        [Display(Name = "Objective")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Objective { get; set; }

        [Display(Name = "Impact to operational")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? OperationalImpact { get; set; }

        [Display(Name = "Risk if not approved")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? RiskIfNotApproved { get; set; }

        [Display(Name = "Expected benefits")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? ExpectedBenefits { get; set; }

        [Display(Name = "Alternatives")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Alternatives { get; set; }

        [Display(Name = "Special request / note")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? SpecialNote { get; set; }

        [Display(Name = "Expected ROI (%)")]
        [Range(typeof(decimal), "-100", "10000", ErrorMessage = "{0} must be between {1} and {2}.")]
        public decimal? ExpectedRoiPercent { get; set; }

        [Display(Name = "ROI explanation")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? RoiExplanation { get; set; }

        [Display(Name = "Additional information")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? AdditionalInfo { get; set; }

        public List<RequestAnswerInput> Answers { get; set; } = new();

        // ---- Tampilan saja (dimuat dari database / CurrentUser, tidak dipercaya dari form) ----
        public string? RequestNo { get; set; }
        public string Status { get; set; } = RequestStatus.Draft;
        public string? CoCode { get; set; }
        public string? DeptName { get; set; }
        public string? ABRV { get; set; }

        // ---- Pilihan dropdown ----
        public IReadOnlyList<SubCategory> SubCategories { get; set; } = Array.Empty<SubCategory>();
        public IReadOnlyList<CostCenterOption> CostCenters { get; set; } = Array.Empty<CostCenterOption>();
        public IReadOnlyList<LocationOption> Locations { get; set; } = Array.Empty<LocationOption>();
        public IReadOnlyList<EmployeeOption> Employees { get; set; } = Array.Empty<EmployeeOption>();

        public ProjectRequest ToEntity() => new()
        {
            Id = Id,
            Title = Title,
            Category = Category,
            SubCategoryId = SubCategoryId,
            BudgetRemarks = BudgetRemarks,
            SubDepartmentID = SubDepartmentID,
            LocationId = LocationId,
            PicEmployeeCode = PicEmployeeCode,
            TargetCompletionDate = TargetCompletionDate,
            AreaLength = AreaLength,
            AreaWidth = AreaWidth,
            BudgetExpectation = BudgetExpectation,
            Background = Background,
            Objective = Objective,
            OperationalImpact = OperationalImpact,
            RiskIfNotApproved = RiskIfNotApproved,
            ExpectedBenefits = ExpectedBenefits,
            Alternatives = Alternatives,
            SpecialNote = SpecialNote,
            ExpectedRoiPercent = ExpectedRoiPercent,
            RoiExplanation = RoiExplanation,
            AdditionalInfo = AdditionalInfo
        };

        public static RequestFormViewModel FromEntity(ProjectRequest r) => new()
        {
            Id = r.Id,
            Title = r.Title,
            Category = r.Category,
            SubCategoryId = r.SubCategoryId,
            BudgetRemarks = r.BudgetRemarks,
            SubDepartmentID = r.SubDepartmentID,
            LocationId = r.LocationId,
            PicEmployeeCode = r.PicEmployeeCode,
            TargetCompletionDate = r.TargetCompletionDate,
            AreaLength = r.AreaLength,
            AreaWidth = r.AreaWidth,
            BudgetExpectation = r.BudgetExpectation,
            Background = r.Background,
            Objective = r.Objective,
            OperationalImpact = r.OperationalImpact,
            RiskIfNotApproved = r.RiskIfNotApproved,
            ExpectedBenefits = r.ExpectedBenefits,
            Alternatives = r.Alternatives,
            SpecialNote = r.SpecialNote,
            ExpectedRoiPercent = r.ExpectedRoiPercent,
            RoiExplanation = r.RoiExplanation,
            AdditionalInfo = r.AdditionalInfo,
            RequestNo = r.RequestNo,
            Status = r.Status,
            CoCode = r.CoCode,
            DeptName = r.DeptName,
            ABRV = r.ABRV
        };
    }

    /// <summary>Satu baris approval di luar sistem (BR-76); semua opsional, baris kosong diabaikan.</summary>
    public class OutsideApprovalInput
    {
        [StringLength(100, ErrorMessage = "Step/role must be at most {1} characters.")]
        public string? Step { get; set; }

        [StringLength(100, ErrorMessage = "Approver name must be at most {1} characters.")]
        public string? Name { get; set; }

        [DataType(DataType.Date)]
        public DateTime? Date { get; set; }

        public bool IsEmpty => string.IsNullOrWhiteSpace(Step) && string.IsNullOrWhiteSpace(Name) && Date == null;
    }

    /// <summary>
    /// Form input project berjalan (T4-3; FR-03, BR-76, BR-77), khusus civil.
    /// Wajib: departemen, judul, kategori, sub-kategori, lokasi. Validasi akhir di SP.
    /// </summary>
    public class RunningProjectFormViewModel
    {
        public const int MaxOutsideApprovals = 10;

        [Display(Name = "Requesting department")]
        [Required(ErrorMessage = "{0} is required.")]
        public int? DepartmentID { get; set; }

        [Display(Name = "Request title")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(200, ErrorMessage = "{0} must be at most {1} characters.")]
        public string Title { get; set; } = string.Empty;

        [Display(Name = "Budget classification")]
        [Required(ErrorMessage = "{0} is required.")]
        [RegularExpression("^(CAPEX|OPEX|LVE)$", ErrorMessage = "{0} is invalid.")]
        public string Category { get; set; } = string.Empty;

        [Display(Name = "Sub-category")]
        [Required(ErrorMessage = "{0} is required.")]
        public int? SubCategoryId { get; set; }

        [Display(Name = "Location")]
        [Required(ErrorMessage = "{0} is required.")]
        public int? LocationId { get; set; }

        [Display(Name = "PIC of project")]
        [StringLength(30)]
        public string? PicEmployeeCode { get; set; }

        [Display(Name = "Cost center")]
        public int? SubDepartmentID { get; set; }

        [Display(Name = "Budget remarks")]
        [RegularExpression("^(BUDGETED|UNBUDGETED)$", ErrorMessage = "{0} is invalid.")]
        public string? BudgetRemarks { get; set; }

        [Display(Name = "Target completion")]
        [DataType(DataType.Date)]
        public DateTime? TargetCompletionDate { get; set; }

        [Display(Name = "Budget expectation (IDR)")]
        [Range(typeof(decimal), "0", "9999999999999999", ErrorMessage = "{0} cannot be negative.")]
        public decimal? BudgetExpectation { get; set; }

        [Display(Name = "Background")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Background { get; set; }

        [Display(Name = "Objective")]
        [StringLength(2000, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Objective { get; set; }

        [Display(Name = "Current status")]
        [Required(ErrorMessage = "{0} is required.")]
        [RegularExpression("^(PLANNING|SCHEDULING)$", ErrorMessage = "{0} must be Planning or Scheduling.")]
        public string TargetStatus { get; set; } = RequestStatus.Planning;

        [Display(Name = "Execution method")]
        [RegularExpression("^(INHOUSE|OUTSOURCE)$", ErrorMessage = "{0} is invalid.")]
        public string? ExecutionType { get; set; }

        [Display(Name = "BOQ total (IDR)")]
        [Range(typeof(decimal), "0.01", "9999999999999999", ErrorMessage = "{0} must be greater than 0.")]
        public decimal? BoqTotal { get; set; }

        [Display(Name = "Vendor")]
        public int? VendorId { get; set; }

        [Display(Name = "Contract number")]
        [StringLength(50, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? ContractNo { get; set; }

        [Display(Name = "Contract date")]
        [DataType(DataType.Date)]
        public DateTime? ContractDate { get; set; }

        [Display(Name = "Contract value (IDR)")]
        [Range(typeof(decimal), "0.01", "9999999999999999", ErrorMessage = "{0} must be greater than 0.")]
        public decimal? ContractValue { get; set; }

        [Display(Name = "Preparation start date")]
        [DataType(DataType.Date)]
        public DateTime? PreparationStartDate { get; set; }

        [Display(Name = "Remarks")]
        [StringLength(900, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Remarks { get; set; }

        public List<OutsideApprovalInput> Approvals { get; set; } = new();

        // ---- Pilihan dropdown ----
        public IReadOnlyList<DepartmentOption> Departments { get; set; } = Array.Empty<DepartmentOption>();
        public IReadOnlyList<SubCategory> SubCategories { get; set; } = Array.Empty<SubCategory>();
        public IReadOnlyList<LocationOption> Locations { get; set; } = Array.Empty<LocationOption>();
        public IReadOnlyList<CostCenterOption> CostCenters { get; set; } = Array.Empty<CostCenterOption>();
        public IReadOnlyList<EmployeeOption> Employees { get; set; } = Array.Empty<EmployeeOption>();
        public IReadOnlyList<VendorOption> Vendors { get; set; } = Array.Empty<VendorOption>();
    }

    public class RequestDetailsViewModel
    {
        public ProjectRequest Request { get; set; } = new();
        public IReadOnlyList<RequestAssessmentItem> Assessment { get; set; } = Array.Empty<RequestAssessmentItem>();
        public IReadOnlyList<RequestAttachment> Attachments { get; set; } = Array.Empty<RequestAttachment>();

        /// <summary>Jenis lampiran tahap REQUEST (untuk form upload).</summary>
        public IReadOnlyList<AttachmentType> AttachmentTypes { get; set; } = Array.Empty<AttachmentType>();

        public IReadOnlyList<ApprovalStepItem> ApprovalSteps { get; set; } = Array.Empty<ApprovalStepItem>();
        public IReadOnlyList<ApprovalHistoryItem> History { get; set; } = Array.Empty<ApprovalHistoryItem>();

        /// <summary>Requester (adm/plan/spv) dan status Draft/Returned: boleh ubah, kelola lampiran, dan Submit.</summary>
        public bool CanEdit { get; set; }

        /// <summary>Requester dan status masih bisa dibatalkan (BR-09); validasi akhir di SP.</summary>
        public bool CanCancel { get; set; }

        /// <summary>Langkah approval yang boleh diproses user ini (T2-3); null = tombol approval tidak tampil.</summary>
        public ApprovalStepItem? ActionableStep { get; set; }

        /// <summary>Civil dan status Feasibility (T3-1): keputusan Feasibility dan ubah kategori; validasi akhir di SP.</summary>
        public bool CanDecideFeasibility { get; set; }

        /// <summary>Civil dan status Document Preparation (T3-2): BOQ total dan kirim ke management; validasi akhir di SP.</summary>
        public bool CanPrepareDocuments { get; set; }

        /// <summary>
        /// Boleh upload/hapus lampiran: tahap REQUEST oleh requester (Draft/Returned) atau Civil (Feasibility);
        /// tahap DOCUMENT (BOQ/Drawing) oleh Civil (Document Preparation).
        /// </summary>
        public bool CanManageAttachments { get; set; }

        /// <summary>Sub-kategori aktif semua kategori (form ubah kategori); hanya dimuat bila CanDecideFeasibility.</summary>
        public IReadOnlyList<SubCategory> SubCategories { get; set; } = Array.Empty<SubCategory>();

        /// <summary>Log perubahan kategori (BR-02), terbaru di atas.</summary>
        public IReadOnlyList<CategoryChangeItem> CategoryChanges { get; set; } = Array.Empty<CategoryChangeItem>();

        /// <summary>Civil dan status Planning (T4-1): unggah TOR, pilih In-house / Outsource; validasi akhir di SP.</summary>
        public bool CanChooseExecution { get; set; }

        /// <summary>Purchasing dan status Procurement (T4-1): kontrak, lampiran kontrak, selesai / kembalikan TOR.</summary>
        public bool CanProcure { get; set; }

        /// <summary>Kontrak outsource (null = belum ada).</summary>
        public ProjectContract? Contract { get; set; }

        /// <summary>Vendor aktif (+ vendor kontrak saat ini) untuk form kontrak; hanya dimuat bila CanProcure.</summary>
        public IReadOnlyList<VendorOption> Vendors { get; set; } = Array.Empty<VendorOption>();

        /// <summary>Schedule, action plan, estimasi (T4-2); null = tidak ada akses (mis. purchasing).</summary>
        public ProjectSchedule? Schedule { get; set; }

        /// <summary>Civil dan status Scheduling / In Progress: ubah schedule, action plan, estimasi (In Progress: alasan wajib).</summary>
        public bool CanEditSchedule { get; set; }

        /// <summary>Civil dan status Scheduling: catat site handover (-> In Progress).</summary>
        public bool CanHandover { get; set; }

        /// <summary>Progress mingguan + status jadwal (T5-1); null = belum In Progress / tanpa akses.</summary>
        public ProjectProgress? Progress { get; set; }

        /// <summary>Civil dan status In Progress: input progress mingguan.</summary>
        public bool CanEnterProgress { get; set; }

        /// <summary>Progress per action plan minggu terpilih (form untuk Civil, baca saja untuk role lain).</summary>
        public ProgressWeekForm? ProgressWeek { get; set; }

        /// <summary>Kurva S (grafik): % plan vs % aktual per minggu; kosong bila belum ada schedule.</summary>
        public IReadOnlyList<ProgressCurvePoint> ProgressCurve { get; set; } = Array.Empty<ProgressCurvePoint>();

        /// <summary>Actual cost + status biaya/keseluruhan (T5-2); null = belum In Progress / tanpa akses.</summary>
        public ProjectActualCost? ActualCost { get; set; }

        /// <summary>Civil dan status In Progress / BAPP Review: input actual cost bulanan.</summary>
        public bool CanEnterActual { get; set; }

        /// <summary>Bulan terpilih (form untuk Civil, detail baca untuk role lain yang berhak).</summary>
        public ActualMonthForm? ActualMonth { get; set; }

        /// <summary>Saran satuan (master Unit aktif); hanya dimuat bila CanEnterActual.</summary>
        public IReadOnlyList<UnitOption> Units { get; set; } = Array.Empty<UnitOption>();

        /// <summary>Addendum (T4-4), terbaru di atas; kosong bila tidak ada / tidak boleh melihat (BR-86).</summary>
        public IReadOnlyList<ProjectAddendum> Addenda { get; set; } = Array.Empty<ProjectAddendum>();

        /// <summary>Addendum yang masih terbuka (menunggu approval / penyesuaian); null = tidak ada.</summary>
        public ProjectAddendum? OpenAddendum => Addenda.FirstOrDefault(a => a.IsOpen);

        /// <summary>Boleh raise addendum baru (BR-78, BR-79): civil untuk outsource dan in-house; validasi akhir di SP.</summary>
        public bool CanCreateAddendum { get; set; }

        /// <summary>Aturan file raise (MD-09: ADDENDUM = draft kontrak / BOQ_REVISION); null bila CanCreateAddendum = false.</summary>
        public AttachmentType? AddendumFileType { get; set; }

        /// <summary>Civil dan addendum outsource FINAL_CONTRACT: upload kontrak final bertanda tangan (BR-87).</summary>
        public bool CanUploadAddendumContract { get; set; }

        /// <summary>Aturan file kontrak final (MD-09: ADDENDUM_FINAL); null bila CanUploadAddendumContract = false.</summary>
        public AttachmentType? AddendumFinalFileType { get; set; }

        /// <summary>Langkah approval addendum yang boleh diproses user ini (BR-80); null = tombol tidak tampil.</summary>
        public ApprovalStepItem? AddendumActionableStep { get; set; }

        /// <summary>Civil dan addendum berstatus ADJUSTMENT: form penyesuaian action plan + estimasi (BR-82).</summary>
        public bool CanAdjustAddendum { get; set; }

        /// <summary>BAPP per ronde (T6-1), terbaru di atas; kosong bila belum ada / tidak boleh melihat (5.2).</summary>
        public IReadOnlyList<ProjectBapp> Bapps { get; set; } = Array.Empty<ProjectBapp>();

        /// <summary>Civil dan status In Progress: upload lampiran BAPP dan terbitkan BAPP (BR-88); syarat dicek ulang di SP.</summary>
        public bool CanIssueBapp { get; set; }

        /// <summary>Semua action plan 100% dengan tanggal selesai aktual (syarat BR-88; untuk checklist).</summary>
        public bool AllPlansComplete { get; set; }

        /// <summary>Langkah approval BAPP yang boleh diproses user ini (form online per langkah); null = tidak ada.</summary>
        public ApprovalStepItem? BappActionableStep { get; set; }

        /// <summary>Civil dan status Closed / Survey Completed: cetak Berita Acara (BR-94).</summary>
        public bool CanPrintBapp { get; set; }
    }
}
