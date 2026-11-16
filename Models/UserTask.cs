namespace CIMS.Models
{
    /// <summary>Jenis tugas Tugas Saya (dbo.fn_User_Tasks; PRD 7.1) dan teks UI.</summary>
    public static class UserTaskType
    {
        public const string Approval = "APPROVAL";
        public const string Revise = "REVISE";
        public const string Rejected = "REJECTED";
        public const string Feasibility = "FEASIBILITY";
        public const string DocPreparation = "DOC_PREPARATION";
        public const string Planning = "PLANNING";
        public const string Procurement = "PROCUREMENT";
        public const string Scheduling = "SCHEDULING";

        /// <summary>Urutan tampil (sama dengan usp_Task_GetSummary).</summary>
        public static readonly string[] All = { Approval, Revise, Rejected, Feasibility, DocPreparation, Planning, Procurement, Scheduling };

        public static bool IsValid(string? code) => code != null && All.Contains(code);

        public static string Label(string? code) => code switch
        {
            Approval => "Waiting for my approval",
            Revise => "Returned for revision",
            Rejected => "Rejected",
            Feasibility => "Feasibility",
            DocPreparation => "Document preparation",
            Planning => "Planning",
            Procurement => "Procurement (contract)",
            Scheduling => "Scheduling / site handover",
            _ => code ?? string.Empty
        };

        /// <summary>Teks tombol/link aksi di daftar tugas.</summary>
        public static string ActionText(string? code) => code switch
        {
            Approval => "Review",
            Revise => "Revise",
            Rejected => "View",
            _ => "Open"
        };

        public static string Icon(string? code) => code switch
        {
            Approval => "bi-check2-square",
            Revise => "bi-arrow-counterclockwise",
            Rejected => "bi-x-octagon",
            Feasibility => "bi-clipboard-check",
            DocPreparation => "bi-file-earmark-ruled",
            Planning => "bi-calendar3",
            Procurement => "bi-cart",
            Scheduling => "bi-calendar-range",
            _ => "bi-list-task"
        };
    }

    /// <summary>Jumlah tugas per jenis (usp_Task_GetSummary).</summary>
    public class UserTaskSummaryItem
    {
        public string TaskType { get; set; } = string.Empty;
        public int TaskCount { get; set; }
    }

    /// <summary>Satu baris Tugas Saya (usp_Task_GetList).</summary>
    public class UserTaskItem
    {
        public string TaskType { get; set; } = string.Empty;
        public int RequestId { get; set; }
        public int? ApprovalStepId { get; set; }
        public DateTime? TaskSince { get; set; }
        public string? RequestNo { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string CoCode { get; set; } = string.Empty;
        public string? DeptName { get; set; }
        public string? ABRV { get; set; }
        public string? RequesterName { get; set; }
        public string? Point { get; set; }
        public int? StepOrder { get; set; }
        public string? RoleCode { get; set; }
        public string? RoleName { get; set; }
    }

    /// <summary>Halaman Tugas Saya (FR-01).</summary>
    public class UserTaskListViewModel
    {
        /// <summary>Filter jenis; null = semua.</summary>
        public string? Type { get; set; }
        public IReadOnlyList<UserTaskSummaryItem> Summary { get; set; } = Array.Empty<UserTaskSummaryItem>();
        public IReadOnlyList<UserTaskItem> Items { get; set; } = Array.Empty<UserTaskItem>();
        public int Total => Summary.Sum(s => s.TaskCount);
    }

    /// <summary>Dashboard (Home/Index): shortcut Tugas Saya (FR-01).</summary>
    public class HomeIndexViewModel
    {
        public IReadOnlyList<UserTaskSummaryItem> TaskSummary { get; set; } = Array.Empty<UserTaskSummaryItem>();
        public int TaskTotal => TaskSummary.Sum(s => s.TaskCount);
    }
}
