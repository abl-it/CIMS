namespace CIMS.Models
{
    /// <summary>Kartu per kategori (usp_Dashboard_GetSummary; PRD 9.1, BR-70).</summary>
    public class DashboardCategorySummary
    {
        public string Category { get; set; } = string.Empty;
        public int ActiveTotal { get; set; }
        public int OnTrack { get; set; }
        public int AtRisk { get; set; }
        public int Delayed { get; set; }
        public decimal PlanCost { get; set; }
        public decimal EstimateToMonth { get; set; }
        public decimal ActualToMonth { get; set; }
        public int InApproval { get; set; }
        public int InCivilReview { get; set; }
        public int InPreparation { get; set; }
        public int ClosedInMonth { get; set; }

        /// <summary>Actual ÷ estimasi s.d. bulan (%); null bila estimasi 0.</summary>
        public decimal? CostRatioPercent => EstimateToMonth > 0 ? Math.Round(ActualToMonth * 100m / EstimateToMonth, 2) : null;
    }

    /// <summary>Baris tabel project aktif (usp_Dashboard_GetProjects).</summary>
    public class DashboardProjectItem
    {
        public int Id { get; set; }
        public string CoCode { get; set; } = string.Empty;
        public string? RequestNo { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public int DepartmentID { get; set; }
        public string? DeptName { get; set; }
        public string? ABRV { get; set; }
        public string? ExecutionType { get; set; }
        public DateTime? ProjectStartDate { get; set; }
        public DateTime? ProjectEndDate { get; set; }
        public decimal? ProgressPercent { get; set; }
        public decimal? PlanProgressPercent { get; set; }
        public string? ScheduleStatus { get; set; }
        public decimal? PlanCost { get; set; }
        public decimal? EstimateToMonth { get; set; }
        public decimal? ActualToMonth { get; set; }
        public string? CostStatus { get; set; }
        public string? OverallStatus { get; set; }

        /// <summary>Belum dihitung (belum ada progress dan actual) = On Track (catatan PRD 8.1).</summary>
        public string OverallStatusOrDefault => OverallStatus ?? Models.OverallStatus.OnTrack;
    }

    /// <summary>Grafik biaya bulanan dashboard (usp_Dashboard_GetMonthlyCost). ActualAmount null = sesudah bulan terpilih.</summary>
    public class DashboardMonthlyCost
    {
        public DateTime PeriodMonth { get; set; }
        public decimal EstimateAmount { get; set; }
        public decimal? ActualAmount { get; set; }
    }

    /// <summary>Titik kurva S project (usp_Request_GetProgressCurve). ActualPercent null = minggu belum diisi.</summary>
    public class ProgressCurvePoint
    {
        public DateTime WeekStart { get; set; }
        public DateTime WeekEnd { get; set; }
        public decimal PlanPercent { get; set; }
        public decimal? ActualPercent { get; set; }
    }

    /// <summary>Halaman Dashboard: filter, kartu, tabel project, ringkasan Tugas Saya.</summary>
    public class DashboardViewModel
    {
        public static readonly string[] AllowedSortBy = { "Overall", "RequestNo", "Title", "Category", "Progress", "PlanCost" };

        public string? CoCode { get; set; }

        /// <summary>Bulan laporan "yyyy-MM" (input type="month"); default bulan berjalan.</summary>
        public string? Month { get; set; }

        public string? Category { get; set; }
        public string? OverallStatus { get; set; }
        public string? Search { get; set; }
        public string SortBy { get; set; } = "Overall";
        public string SortDir { get; set; } = "DESC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public bool ShowCompanyFilter { get; set; }

        /// <summary>Bulan hasil parse (tanggal 1).</summary>
        public DateTime MonthDate { get; set; }

        public IReadOnlyList<DashboardCategorySummary> Summary { get; set; } = Array.Empty<DashboardCategorySummary>();

        /// <summary>Estimasi vs actual per bulan (grafik), mengikuti filter Company/kategori/bulan.</summary>
        public IReadOnlyList<DashboardMonthlyCost> MonthlyCost { get; set; } = Array.Empty<DashboardMonthlyCost>();
        public PagedResult<DashboardProjectItem> Result { get; set; } = new();
        public IReadOnlyList<UserTaskSummaryItem> TaskSummary { get; set; } = Array.Empty<UserTaskSummaryItem>();
        public int TaskTotal => TaskSummary.Sum(t => t.TaskCount);
    }
}
