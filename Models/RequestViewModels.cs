using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class RequestListViewModel
    {
        /// <summary>Filter Company (BR-57); hanya ditampilkan untuk role lintas Company.</summary>
        public string? CoCode { get; set; }
        public string? Search { get; set; }
        public string? Category { get; set; }
        public string? Status { get; set; }
        public string SortBy { get; set; } = "CreatedAt";
        public string SortDir { get; set; } = "DESC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public bool ShowCompanyFilter { get; set; }
        public bool CanCreate { get; set; }
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
    }
}
