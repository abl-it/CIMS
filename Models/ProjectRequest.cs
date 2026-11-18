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

        /// <summary>Kelas badge per status: satu warna per status (token --cims-status-* di site.css).</summary>
        public static string BadgeClass(string? code) => "cims-status " + (code switch
        {
            Draft => "cims-status-draft",
            WaitingApproval => "cims-status-waiting",
            Returned => "cims-status-returned",
            Feasibility => "cims-status-feasibility",
            DocPreparation => "cims-status-docprep",
            MgmtApproval => "cims-status-mgmt",
            Planning => "cims-status-planning",
            Procurement => "cims-status-procurement",
            Scheduling => "cims-status-scheduling",
            InProgress => "cims-status-progress",
            BappReview => "cims-status-bapp",
            Closed => "cims-status-closed",
            SurveyCompleted => "cims-status-survey",
            Rejected => "cims-status-rejected",
            Cancelled => "cims-status-cancelled",
            _ => "cims-status-draft"
        });

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
            // Tujuan Revise mengikuti langkah (REQUESTER / CIVIL); status baru ditampilkan terpisah.
            Revise => "Request returned for revision.",
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

    /// <summary>Cara eksekusi project (usp_Request_ChooseExecution; PRD 3.3, ST-08/ST-09).</summary>
    public static class RequestExecutionType
    {
        public const string InHouse = "INHOUSE";
        public const string Outsource = "OUTSOURCE";

        public static bool IsValid(string? code) => code is InHouse or Outsource;

        public static string Label(string? code) => code switch
        {
            InHouse => "In-house",
            Outsource => "Outsource",
            _ => code ?? string.Empty
        };

        public static string SuccessMessage(string code) => code switch
        {
            InHouse => "In-house execution chosen. The request moved to scheduling.",
            Outsource => "TOR sent to Purchasing.",
            _ => "Done."
        };
    }

    /// <summary>Status jadwal (BR-68) dan teks/warna UI.</summary>
    public static class ScheduleStatus
    {
        public const string OnTrack = "ON_TRACK";
        public const string SlightDelay = "SLIGHT_DELAY";
        public const string Delay = "DELAY";

        public static string Label(string? code) => code switch
        {
            OnTrack => "On Track",
            SlightDelay => "Slightly Delay",
            Delay => "Delay",
            _ => "Not calculated"
        };

        public static string BadgeClass(string? code) => code switch
        {
            OnTrack => "text-bg-success",
            SlightDelay => "text-bg-warning",
            Delay => "text-bg-danger",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Ringkasan progress (usp_Request_GetProgress result 1; T5-1).</summary>
    public class ProgressSummary
    {
        public int RequestId { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime? ProjectStartDate { get; set; }
        public DateTime? ProjectEndDate { get; set; }
        public decimal? ProgressPercent { get; set; }
        public decimal? PlanProgressPercent { get; set; }
        public string? ScheduleStatus { get; set; }
        public DateTime? ScheduleStatusAt { get; set; }
        public DateTime? LatestWeekStart { get; set; }
        public DateTime CurrentWeekStart { get; set; }
        public DateTime? FirstWeekStart { get; set; }
        public decimal? PlanPercentToday { get; set; }
    }

    /// <summary>Satu minggu progress tersimpan (dbo.ProjectProgressWeek).</summary>
    public class ProgressWeekItem
    {
        public int Id { get; set; }
        public int RequestId { get; set; }
        public DateTime WeekStart { get; set; }
        public DateTime WeekEnd { get; set; }
        public decimal PlanPercent { get; set; }
        public decimal ActualPercent { get; set; }
        public decimal Deviation { get; set; }
        public string ScheduleStatus { get; set; } = string.Empty;
        public string? Remarks { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }

    /// <summary>Progress lengkap untuk Details: ringkasan + daftar minggu.</summary>
    public class ProjectProgress
    {
        public ProgressSummary Summary { get; set; } = new();
        public IReadOnlyList<ProgressWeekItem> Weeks { get; set; } = Array.Empty<ProgressWeekItem>();
    }

    /// <summary>Info minggu pada form progress (usp_Request_GetProgressWeek result 1).</summary>
    public class ProgressWeekInfo
    {
        public DateTime WeekStart { get; set; }
        public DateTime WeekEnd { get; set; }
        public bool IsSaved { get; set; }
        public string? Remarks { get; set; }
    }

    /// <summary>Baris action plan pada form progress (usp_Request_GetProgressWeek result 2).</summary>
    public class ProgressWeekRow
    {
        public int ActionPlanId { get; set; }
        public int SortOrder { get; set; }
        public string Name { get; set; } = string.Empty;
        public decimal WeightPercent { get; set; }
        public DateTime PlanStartDate { get; set; }
        public DateTime PlanEndDate { get; set; }
        public DateTime? ActualStartDate { get; set; }
        public DateTime? ActualEndDate { get; set; }

        /// <summary>% plan action plan pada hari Minggu minggu tersebut.</summary>
        public decimal PlanPercent { get; set; }

        /// <summary>% tersimpan untuk minggu ini; null = belum disimpan.</summary>
        public decimal? SavedPercent { get; set; }

        /// <summary>Batas bawah (minggu sebelumnya) dan batas atas (minggu sesudahnya).</summary>
        public decimal MinPercent { get; set; }
        public decimal MaxPercent { get; set; }

        /// <summary>Nilai awal di form: tersimpan, atau nilai minggu sebelumnya.</summary>
        public decimal InitialPercent => SavedPercent ?? MinPercent;
    }

    /// <summary>Form progress satu minggu.</summary>
    public class ProgressWeekForm
    {
        public ProgressWeekInfo Week { get; set; } = new();
        public IReadOnlyList<ProgressWeekRow> Rows { get; set; } = Array.Empty<ProgressWeekRow>();
    }

    /// <summary>Input progress per action plan dari form. Validasi akhir di SP.</summary>
    public class ProgressInput
    {
        public int ActionPlanId { get; set; }
        public decimal? ProgressPercent { get; set; }
        public DateTime? ActualStartDate { get; set; }
        public DateTime? ActualEndDate { get; set; }
    }

    /// <summary>Hasil simpan progress (usp_Request_SaveProgress).</summary>
    public class ProgressSaveResult
    {
        public DateTime WeekStart { get; set; }
        public decimal PlanPercent { get; set; }
        public decimal ActualPercent { get; set; }
        public decimal Deviation { get; set; }
        public string ScheduleStatus { get; set; } = string.Empty;
    }

    /// <summary>Ringkasan schedule (usp_Request_GetSchedule result 1; T4-2, BR-13, BR-15, BR-16).</summary>
    public class ProjectScheduleSummary
    {
        public int RequestId { get; set; }
        public string Status { get; set; } = string.Empty;
        public string? ExecutionType { get; set; }
        public decimal? PlanCost { get; set; }
        public DateTime? PreparationStartAt { get; set; }
        public DateTime? ProjectStartDate { get; set; }

        /// <summary>Tanggal selesai plan terakhir dari action plan.</summary>
        public DateTime? ProjectEndDate { get; set; }

        public DateTime? SiteHandoverDate { get; set; }
        public decimal TotalWeight { get; set; }
        public decimal TotalEstimate { get; set; }

        public bool IsWeightComplete => TotalWeight == 100m;
        public bool IsEstimateComplete => PlanCost.HasValue && TotalEstimate == PlanCost.Value;
    }

    /// <summary>Action plan berbobot (dbo.ProjectActionPlan; BR-16). Progress/aktual diisi di T5.</summary>
    public class ProjectActionPlanItem
    {
        public int Id { get; set; }
        public int RequestId { get; set; }
        public int SortOrder { get; set; }
        public string Name { get; set; } = string.Empty;
        public decimal WeightPercent { get; set; }
        public DateTime PlanStartDate { get; set; }
        public DateTime PlanEndDate { get; set; }
        public decimal ProgressPercent { get; set; }
        public DateTime? ActualStartDate { get; set; }
        public DateTime? ActualEndDate { get; set; }

        /// <summary>
        /// BR-83 (Keputusan 17-11-2026): sudah punya progress (> 0% atau mulai aktual terisi) -> tidak boleh dihapus,
        /// nama dan tanggal mulai plan terkunci. Progress tidak pernah turun, jadi progress terkini > 0 setara
        /// "pernah tersimpan > 0%". Validasi akhir di SP.
        /// </summary>
        public bool HasProgress => ProgressPercent > 0 || ActualStartDate.HasValue;
    }

    /// <summary>Estimasi biaya total per bulan (dbo.ProjectCostEstimate; BR-13).</summary>
    public class ProjectCostEstimateItem
    {
        public int Id { get; set; }
        public int RequestId { get; set; }
        public DateTime PeriodMonth { get; set; }
        public decimal Amount { get; set; }
    }

    /// <summary>Schedule lengkap untuk Details: ringkasan, action plan, estimasi.</summary>
    public class ProjectSchedule
    {
        public ProjectScheduleSummary Summary { get; set; } = new();
        public IReadOnlyList<ProjectActionPlanItem> ActionPlans { get; set; } = Array.Empty<ProjectActionPlanItem>();
        public IReadOnlyList<ProjectCostEstimateItem> CostEstimates { get; set; } = Array.Empty<ProjectCostEstimateItem>();
    }

    /// <summary>Baris action plan dari form (Id 0 = baru). Validasi akhir di SP.</summary>
    public class ActionPlanInput
    {
        public int Id { get; set; }
        public string? Name { get; set; }
        public decimal? WeightPercent { get; set; }
        public DateTime? PlanStartDate { get; set; }
        public DateTime? PlanEndDate { get; set; }
    }

    /// <summary>Baris estimasi dari form. Month = "yyyy-MM" (input type="month").</summary>
    public class CostEstimateInput
    {
        public string? Month { get; set; }
        public decimal? Amount { get; set; }
    }

    /// <summary>Kontrak outsource dari Purchasing (dbo.ProjectContract; BR-11).</summary>
    public class ProjectContract
    {
        public int Id { get; set; }
        public int RequestId { get; set; }
        public int VendorId { get; set; }
        public string VendorCode { get; set; } = string.Empty;
        public string VendorName { get; set; } = string.Empty;
        public string ContractNo { get; set; } = string.Empty;
        public DateTime ContractDate { get; set; }
        public decimal ContractValue { get; set; }
        public string? Remarks { get; set; }
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
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
            "ADDENDUM" => "Addendum approval",
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
            // T6-1: titik BAPP memakai istilah Accept / No (PRD 3.4)
            "APPROVE" => Point == "BAPP" ? "BAPP accepted" : "Approved",
            "REVISE" => Point == "BAPP" ? "BAPP returned (No)" : "Revised",
            "REJECT" => "Rejected",
            "FEASIBLE" => "Feasible",
            "BAPP_ISSUE" => "BAPP issued",
            "CATEGORY_CHANGE" => "Category changed",
            "BOQ_TOTAL" => "BOQ total",
            "SEND_TO_MGMT" => "Sent to management",
            "INHOUSE" => "In-house chosen",
            "SEND_TOR" => "TOR sent to Purchasing",
            "RETURN_TOR" => "TOR returned",
            "CONTRACT" => "Contract completed",
            "SITE_HANDOVER" => "Site handover",
            "SCHEDULE_CHANGE" => "Schedule changed",
            "ESTIMATE_CHANGE" => "Cost estimate changed",
            "MIGRATION" => "Running project entered",
            "OUTSIDE_APPROVAL" => "Approved outside CIMS",
            "ACTUAL_COST" => "Actual cost",
            "ADDENDUM" => "Addendum entered",
            "ADDENDUM_CONTRACT" => "Signed contract uploaded",
            "ADDENDUM_ADJUST" => "Addendum completed",
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
            "BOQ_TOTAL" => "bi-calculator",
            "SEND_TO_MGMT" => "bi-send-check",
            "INHOUSE" => "bi-tools",
            "SEND_TOR" => "bi-cart",
            "RETURN_TOR" => "bi-arrow-return-left",
            "CONTRACT" => "bi-file-earmark-check",
            "SITE_HANDOVER" => "bi-flag",
            "SCHEDULE_CHANGE" => "bi-calendar-event",
            "ESTIMATE_CHANGE" => "bi-cash-stack",
            "MIGRATION" => "bi-box-arrow-in-right",
            "OUTSIDE_APPROVAL" => "bi-patch-check",
            "ACTUAL_COST" => "bi-receipt",
            "ADDENDUM" => "bi-file-earmark-diff",
            "ADDENDUM_CONTRACT" => "bi-file-earmark-lock",
            "BAPP_ISSUE" => "bi-clipboard2-check",
            "ADDENDUM_ADJUST" => "bi-file-earmark-check",
            _ => "bi-dot"
        };

        /// <summary>Warna badge/ikon per aksi.</summary>
        public string ActionBadgeClass => Action switch
        {
            "SUBMIT" or "RESUBMIT" or "SEND_TO_MGMT" or "SEND_TOR" => "text-bg-primary",
            "APPROVE" or "FEASIBLE" or "INHOUSE" or "CONTRACT" or "SITE_HANDOVER" => "text-bg-success",
            "REVISE" or "RETURN_TOR" or "SCHEDULE_CHANGE" or "ESTIMATE_CHANGE" or "ADDENDUM" => "text-bg-warning",
            "ADDENDUM_ADJUST" => "text-bg-success",
            "ADDENDUM_CONTRACT" => "text-bg-primary",
            "BAPP_ISSUE" => "text-bg-primary",
            "REJECT" => "text-bg-danger",
            "CATEGORY_CHANGE" or "BOQ_TOTAL" or "MIGRATION" or "OUTSIDE_APPROVAL" or "ACTUAL_COST" => "text-bg-info",
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

        /// <summary>Nilai BOQ total (IDR) dari Civil di Document Preparation (T3-2; BR-05, BR-12).</summary>
        public decimal? BoqTotal { get; set; }

        /// <summary>Cara eksekusi (T4-1): INHOUSE | OUTSOURCE; null = belum dipilih (lihat <see cref="RequestExecutionType"/>).</summary>
        public string? ExecutionType { get; set; }

        /// <summary>Plan cost (BR-12): in-house = BOQ total, outsource = nilai kontrak.</summary>
        public decimal? PlanCost { get; set; }

        /// <summary>Awal periode Preparation (BR-15).</summary>
        public DateTime? PreparationStartAt { get; set; }

        /// <summary>Project berjalan yang diinput Civil saat go-live (data migrasi; FR-03, BR-77).</summary>
        public bool IsMigrated { get; set; }

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

        /// <summary>Addendum terbuka (PENDING_APPROVAL / ADJUSTMENT) untuk tanda follow up (T4-4); null = tidak ada / tidak boleh lihat.</summary>
        public string? OpenAddendumStatus { get; set; }
        public string? OpenAddendumCode { get; set; }
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

    /// <summary>Departemen (home..APP_Departments) dalam lingkup user.</summary>
    public class DepartmentOption
    {
        public int DepartmentID { get; set; }
        public string CoCode { get; set; } = string.Empty;
        public string? DeptName { get; set; }
        public string? ABRV { get; set; }

        public string DisplayText => $"{CoCode} · {DeptName} ({ABRV})";
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
