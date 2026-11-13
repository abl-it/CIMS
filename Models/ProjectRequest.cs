namespace CIMS.Models
{
    /// <summary>Kode status request (sama dengan CHECK constraint dbo.ProjectRequest; PRD 3.6) dan label UI.</summary>
    public static class RequestStatus
    {
        public const string Draft = "DRAFT";
        public const string WaitingApproval = "WAITING_APPROVAL";
        public const string Returned = "RETURNED";
        public const string Feasibility = "FEASIBILITY";
        public const string DocPreparation = "DOC_PREPARATION";
        public const string MgmtApproval = "MGMT_APPROVAL";
        public const string Planning = "PLANNING";
        public const string Procurement = "PROCUREMENT";
        public const string Scheduling = "SCHEDULING";
        public const string InProgress = "IN_PROGRESS";
        public const string BappReview = "BAPP_REVIEW";
        public const string Closed = "CLOSED";
        public const string SurveyCompleted = "SURVEY_COMPLETED";
        public const string Rejected = "REJECTED";
        public const string Cancelled = "CANCELLED";

        /// <summary>Urut sesuai alur (ST-01..ST-16).</summary>
        public static readonly IReadOnlyList<KeyValuePair<string, string>> All = new[]
        {
            new KeyValuePair<string, string>(Draft, "Draft"),
            new KeyValuePair<string, string>(WaitingApproval, "Waiting Approval"),
            new KeyValuePair<string, string>(Returned, "Returned to User"),
            new KeyValuePair<string, string>(Feasibility, "Feasibility"),
            new KeyValuePair<string, string>(DocPreparation, "Document Preparation"),
            new KeyValuePair<string, string>(MgmtApproval, "Management Approval"),
            new KeyValuePair<string, string>(Planning, "Planning"),
            new KeyValuePair<string, string>(Procurement, "Procurement"),
            new KeyValuePair<string, string>(Scheduling, "Scheduling / Preparation"),
            new KeyValuePair<string, string>(InProgress, "In Progress"),
            new KeyValuePair<string, string>(BappReview, "BAPP Review"),
            new KeyValuePair<string, string>(Closed, "Closed"),
            new KeyValuePair<string, string>(SurveyCompleted, "Survey Completed"),
            new KeyValuePair<string, string>(Rejected, "Rejected"),
            new KeyValuePair<string, string>(Cancelled, "Cancelled")
        };

        public static string Label(string? code) =>
            All.FirstOrDefault(s => s.Key == code).Value ?? code ?? string.Empty;

        /// <summary>Kelas badge Bootstrap per status.</summary>
        public static string BadgeClass(string? code) => code switch
        {
            Draft => "text-bg-secondary",
            Returned => "text-bg-warning",
            WaitingApproval or MgmtApproval or BappReview => "text-bg-info",
            Rejected or Cancelled => "text-bg-danger",
            Closed or SurveyCompleted => "text-bg-success",
            _ => "text-bg-primary"
        };

        /// <summary>Status yang masih boleh diubah requester (draft / dikembalikan).</summary>
        public static bool IsEditable(string? code) => code is Draft or Returned;

        /// <summary>Status yang masih boleh dibatalkan requester (BR-09); SP juga menolak bila management approval sudah dimulai.</summary>
        public static bool IsCancellable(string? code) =>
            code is Draft or WaitingApproval or Returned or Feasibility or DocPreparation or MgmtApproval;
    }

    /// <summary>Kode aksi approval (usp_Request_ApprovalAct) dan pesan sukses UI.</summary>
    public static class ApprovalAction
    {
        public const string Approve = "APPROVE";
        public const string Revise = "REVISE";
        public const string Reject = "REJECT";

        public static bool IsValid(string? code) => code is Approve or Revise or Reject;

        public static string SuccessMessage(string code) => code switch
        {
            Approve => "Request approved.",
            Revise => "Request returned to the requester for revision.",
            Reject => "Request rejected.",
            _ => "Done."
        };
    }

    /// <summary>Keputusan Feasibility oleh Civil (usp_Request_FeasibilityDecide; PRD 3.1 langkah 4).</summary>
    public static class FeasibilityDecision
    {
        public const string Feasible = "FEASIBLE";
        public const string Revise = "REVISE";
        public const string Reject = "REJECT";

        public static bool IsValid(string? code) => code is Feasible or Revise or Reject;

        public static string SuccessMessage(string code) => code switch
        {
            Feasible => "Request marked as feasible.",
            Revise => "Request returned to the requester for revision.",
            Reject => "Request rejected.",
            _ => "Done."
        };
    }

    /// <summary>Log perubahan kategori / sub-kategori oleh Civil (usp_Request_GetCategoryChanges; BR-02, BR-54).</summary>
    public class CategoryChangeItem
    {
        public int Id { get; set; }
        public string OldCategory { get; set; } = string.Empty;
        public string NewCategory { get; set; } = string.Empty;
        public string? OldSubCategoryName { get; set; }
        public string? NewSubCategoryName { get; set; }
        public string? OldRequestNo { get; set; }
        public string? NewRequestNo { get; set; }
        public string Reason { get; set; } = string.Empty;
        public string ChangedBy { get; set; } = string.Empty;
        public string? ChangedByName { get; set; }
        public DateTime ChangedAt { get; set; }

        public bool IsRenumbered => !string.Equals(OldRequestNo, NewRequestNo, StringComparison.Ordinal);
    }

    /// <summary>Langkah approval (snapshot, ronde terakhir per titik) dari usp_Request_GetApprovalSteps.</summary>
    public class ApprovalStepItem
    {
        public int Id { get; set; }
        public string Point { get; set; } = string.Empty;
        public int Round { get; set; }
        public int StepOrder { get; set; }
        public string RoleCode { get; set; } = string.Empty;
        public string? RoleName { get; set; }
        public string Scope { get; set; } = string.Empty;
        public string? DepartmentGroupCode { get; set; }
        public string? ReviseTo { get; set; }
        public bool AllowReject { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime? StartedAt { get; set; }
        public DateTime? ActedAt { get; set; }
        public string? ActedBy { get; set; }
        public string? Remarks { get; set; }
        public bool IsCurrent { get; set; }

        public string PointLabel => Point switch
        {
            "REQUEST" => "Request approval",
            "MGMT" => "Management approval",
            "BAPP" => "BAPP approval",
            _ => Point
        };

        public string StatusLabel => Status switch
        {
            "PENDING" => IsCurrent ? "Waiting" : "Pending",
            "APPROVED" => "Approved",
            "REVISED" => "Revised",
            "REJECTED" => "Rejected",
            "VOID" => "Closed",
            _ => Status
        };

        public string StatusBadgeClass => Status switch
        {
            "PENDING" => IsCurrent ? "text-bg-info" : "text-bg-light border",
            "APPROVED" => "text-bg-success",
            "REVISED" => "text-bg-warning",
            "REJECTED" => "text-bg-danger",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Jejak aksi request (dbo.ApprovalHistory).</summary>
    public class ApprovalHistoryItem
    {
        public int Id { get; set; }
        public string Action { get; set; } = string.Empty;
        public string? FromStatus { get; set; }
        public string? ToStatus { get; set; }
        public string? Remarks { get; set; }
        public string ActionBy { get; set; } = string.Empty;
        public string? ActionByName { get; set; }
        public DateTime ActionAt { get; set; }
        public string? Point { get; set; }
        public int? StepOrder { get; set; }
        public string? RoleCode { get; set; }

        public string ActionLabel => Action switch
        {
            "SUBMIT" => "Submitted",
            "RESUBMIT" => "Resubmitted",
            "CANCEL" => "Cancelled",
            "APPROVE" => "Approved",
            "REVISE" => "Revised",
            "REJECT" => "Rejected",
            "FEASIBLE" => "Feasible",
            "CATEGORY_CHANGE" => "Category changed",
            _ => Action
        };

        /// <summary>Ikon Bootstrap Icons per aksi (timeline History).</summary>
        public string ActionIcon => Action switch
        {
            "SUBMIT" or "RESUBMIT" => "bi-send",
            "APPROVE" => "bi-check-lg",
            "REVISE" => "bi-arrow-counterclockwise",
            "REJECT" => "bi-x-lg",
            "CANCEL" => "bi-slash-circle",
            "FEASIBLE" => "bi-clipboard-check",
            "CATEGORY_CHANGE" => "bi-tag",
            _ => "bi-dot"
        };

        /// <summary>Warna badge/ikon per aksi.</summary>
        public string ActionBadgeClass => Action switch
        {
            "SUBMIT" or "RESUBMIT" => "text-bg-primary",
            "APPROVE" or "FEASIBLE" => "text-bg-success",
            "REVISE" => "text-bg-warning",
            "REJECT" => "text-bg-danger",
            "CATEGORY_CHANGE" => "text-bg-info",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Request / business case (dbo.ProjectRequest) beserta nama tampilan dari usp_Request_GetById.</summary>
    public class ProjectRequest
    {
        public static readonly string[] Categories = { "CAPEX", "OPEX", "LVE" };

        /// <summary>Budget remarks (kode, label).</summary>
        public static readonly IReadOnlyList<KeyValuePair<string, string>> BudgetRemarksOptions = new[]
        {
            new KeyValuePair<string, string>("BUDGETED", "Budgeted"),
            new KeyValuePair<string, string>("UNBUDGETED", "Unbudgeted")
        };

        public static string BudgetRemarksLabel(string? code) =>
            BudgetRemarksOptions.FirstOrDefault(b => b.Key == code).Value ?? code ?? string.Empty;

        public int Id { get; set; }
        public string CoCode { get; set; } = string.Empty;
        public int DepartmentID { get; set; }
        public string? DeptName { get; set; }
        public string? ABRV { get; set; }
        public string? RequestNo { get; set; }
        public string Status { get; set; } = RequestStatus.Draft;
        public string RequesterUsername { get; set; } = string.Empty;
        public string RequesterEmployeeCode { get; set; } = string.Empty;
        public string? RequesterName { get; set; }
        public string? PicEmployeeCode { get; set; }
        public string? PicName { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public int? SubCategoryId { get; set; }
        public string? SubCategoryName { get; set; }
        public string? BudgetRemarks { get; set; }
        public int? SubDepartmentID { get; set; }
        public string? CostCenterCode { get; set; }
        public string? CostCenterName { get; set; }
        public int? LocationId { get; set; }
        public string? LocationName { get; set; }
        public DateTime? TargetCompletionDate { get; set; }
        public decimal? AreaLength { get; set; }
        public decimal? AreaWidth { get; set; }
        public decimal? AreaSize { get; set; }
        public decimal? BudgetExpectation { get; set; }
        public string? Background { get; set; }
        public string? Objective { get; set; }
        public string? OperationalImpact { get; set; }
        public string? RiskIfNotApproved { get; set; }
        public string? ExpectedBenefits { get; set; }
        public string? Alternatives { get; set; }
        public string? SpecialNote { get; set; }
        public decimal? ExpectedRoiPercent { get; set; }
        public string? RoiExplanation { get; set; }
        public string? AdditionalInfo { get; set; }
        public DateTime? SubmittedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }

    /// <summary>Baris list request (usp_Request_GetPaged).</summary>
    public class RequestListItem
    {
        public int Id { get; set; }
        public string CoCode { get; set; } = string.Empty;
        public string? RequestNo { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string? SubCategoryName { get; set; }
        public string Status { get; set; } = string.Empty;
        public int DepartmentID { get; set; }
        public string? DeptName { get; set; }
        public string? ABRV { get; set; }
        public string? RequesterName { get; set; }
        public DateTime? TargetCompletionDate { get; set; }
        public decimal? BudgetExpectation { get; set; }
        public DateTime? SubmittedAt { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    /// <summary>Pertanyaan Environment Assessment + jawaban (null = belum dijawab).</summary>
    public class RequestAssessmentItem
    {
        public int QuestionId { get; set; }
        public int SortOrder { get; set; }
        public string QuestionText { get; set; } = string.Empty;
        public bool? Answer { get; set; }
    }

    /// <summary>Metadata lampiran request (dbo.RequestAttachment). RelativePath hanya diisi untuk download.</summary>
    public class RequestAttachment
    {
        public int Id { get; set; }
        public int RequestId { get; set; }
        public int AttachmentTypeId { get; set; }
        public string AttachmentTypeCode { get; set; } = string.Empty;
        public string AttachmentTypeName { get; set; } = string.Empty;
        public string Stage { get; set; } = string.Empty;
        public string OriginalFileName { get; set; } = string.Empty;
        public string? RelativePath { get; set; }
        public string ContentType { get; set; } = string.Empty;
        public long FileSizeBytes { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
    }

    /// <summary>Cost center (home..APP_SubDepartments).</summary>
    public class CostCenterOption
    {
        public int SubDepartmentID { get; set; }
        public string SubDepartmentCode { get; set; } = string.Empty;
        public string SubDepartmentName { get; set; } = string.Empty;
    }

    /// <summary>Karyawan aktif untuk pilihan PIC (home..app_employees).</summary>
    public class EmployeeOption
    {
        public string EmployeeCode { get; set; } = string.Empty;
        public string? FullName { get; set; }
        public string? JobTitle { get; set; }
    }

    /// <summary>Lokasi aktif untuk pilihan form (dbo.Location).</summary>
    public class LocationOption
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
    }
}
