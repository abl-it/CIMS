namespace CIMS.Models
{
    /// <summary>Status biaya (BR-69) dan teks/warna UI.</summary>
    public static class CostStatus
    {
        public const string OnTrack = "ON_TRACK";
        public const string AtRisk = "AT_RISK";
        public const string OverBudget = "OVER_BUDGET";

        public static string Label(string? code) => code switch
        {
            OnTrack => "On Track",
            AtRisk => "At Risk",
            OverBudget => "Over Budget",
            _ => "Not calculated"
        };

        public static string BadgeClass(string? code) => code switch
        {
            OnTrack => "text-bg-success",
            AtRisk => "text-bg-warning",
            OverBudget => "text-bg-danger",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Status keseluruhan (BR-70; kolom terhitung OverallStatus) dan teks/warna UI.</summary>
    public static class OverallStatus
    {
        public const string OnTrack = "ON_TRACK";
        public const string AtRisk = "AT_RISK";
        public const string Delayed = "DELAYED";

        public static string Label(string? code) => code switch
        {
            OnTrack => "On Track",
            AtRisk => "At Risk",
            Delayed => "Delayed",
            _ => "Not calculated"
        };

        public static string BadgeClass(string? code) => code switch
        {
            OnTrack => "text-bg-success",
            AtRisk => "text-bg-warning",
            Delayed => "text-bg-danger",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Jenis item actual cost (PRD 6.4: Barang / Jasa).</summary>
    public static class ActualItemType
    {
        public const string Goods = "GOODS";
        public const string Service = "SERVICE";

        public static readonly IReadOnlyList<KeyValuePair<string, string>> All = new[]
        {
            new KeyValuePair<string, string>(Goods, "Goods"),
            new KeyValuePair<string, string>(Service, "Service")
        };

        public static string Label(string? code) => All.FirstOrDefault(t => t.Key == code).Value ?? code ?? string.Empty;
    }

    /// <summary>Ringkasan biaya (usp_Request_GetActualCost result 1; T5-2).</summary>
    public class ActualCostSummary
    {
        public int RequestId { get; set; }
        public string Status { get; set; } = string.Empty;
        public decimal? PlanCost { get; set; }
        public decimal? ActualCostTotal { get; set; }
        public decimal? CostRatioPercent { get; set; }
        public string? CostStatus { get; set; }
        public DateTime? CostStatusAt { get; set; }
        public DateTime? LastActualMonth { get; set; }
        public string? ScheduleStatus { get; set; }
        public string? OverallStatus { get; set; }
        public DateTime? FirstMonth { get; set; }
        public DateTime CurrentMonth { get; set; }

        /// <summary>Boleh melihat detail per bulan/item (civil, fat, gm, director, administrator).</summary>
        public bool CanSeeDetail { get; set; }
    }

    /// <summary>Estimasi vs actual per bulan (usp_Request_GetActualCost result 2).</summary>
    public class ActualMonthRow
    {
        public DateTime PeriodMonth { get; set; }
        public decimal EstimateAmount { get; set; }
        public decimal ActualAmount { get; set; }
        public int ItemCount { get; set; }
        public string? Source { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public bool HasActual { get; set; }
    }

    /// <summary>Actual cost project: ringkasan + per bulan.</summary>
    public class ProjectActualCost
    {
        public ActualCostSummary Summary { get; set; } = new();
        public IReadOnlyList<ActualMonthRow> Months { get; set; } = Array.Empty<ActualMonthRow>();
    }

    /// <summary>Header satu bulan (usp_Request_GetActualMonth result 1).</summary>
    public class ActualMonthHeader
    {
        public DateTime PeriodMonth { get; set; }
        public decimal? EstimateAmount { get; set; }
        public decimal? TotalAmount { get; set; }
        public int? ItemCount { get; set; }
        public string? Source { get; set; }
        public int? AttachmentId { get; set; }
        public string? Remarks { get; set; }
        public DateTime? CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
        public bool IsSaved { get; set; }
    }

    /// <summary>Item actual cost (dbo.ProjectActualItem; PRD 6.4).</summary>
    public class ActualItem
    {
        public int Id { get; set; }
        public int LineNumber { get; set; }
        public string ItemType { get; set; } = string.Empty;
        public string ItemName { get; set; } = string.Empty;
        public decimal Qty { get; set; }
        public string Unit { get; set; } = string.Empty;
        public decimal UnitPrice { get; set; }
        public decimal Amount { get; set; }
        public string? ReferenceNo { get; set; }
        public string? Notes { get; set; }
    }

    /// <summary>Satu bulan lengkap untuk form / detail.</summary>
    public class ActualMonthForm
    {
        public ActualMonthHeader Header { get; set; } = new();
        public IReadOnlyList<ActualItem> Items { get; set; } = Array.Empty<ActualItem>();
    }

    /// <summary>Input item dari form. Validasi akhir di SP.</summary>
    public class ActualItemInput
    {
        public string? ItemType { get; set; }
        public string? ItemName { get; set; }
        public decimal? Qty { get; set; }
        public string? Unit { get; set; }
        public decimal? UnitPrice { get; set; }
        public decimal? Amount { get; set; }
        public string? ReferenceNo { get; set; }
        public string? Notes { get; set; }

        public bool IsEmpty => string.IsNullOrWhiteSpace(ItemName) && Qty == null && UnitPrice == null && Amount == null
                               && string.IsNullOrWhiteSpace(Unit) && string.IsNullOrWhiteSpace(ReferenceNo)
                               && string.IsNullOrWhiteSpace(Notes);
    }

    /// <summary>Hasil simpan actual bulanan (usp_Request_SaveActualMonth).</summary>
    public class ActualSaveResult
    {
        public decimal? ActualCostTotal { get; set; }
        public decimal? CostRatioPercent { get; set; }
        public string? CostStatus { get; set; }
        public string? ScheduleStatus { get; set; }
        public string? OverallStatus { get; set; }
        public DateTime? LastActualMonth { get; set; }
    }
}
