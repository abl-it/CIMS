namespace CIMS.Models
{
    /// <summary>Status survei kepuasan (dbo.ProjectSurvey.Status + NOT_SENT dari daftar; T6-2, BR-91, BR-92).</summary>
    public static class SurveyStatus
    {
        public const string NotSent = "NOT_SENT";
        public const string Sent = "SENT";
        public const string Completed = "COMPLETED";

        public static readonly string[] All = { NotSent, Sent, Completed };

        public static string Label(string? status) => status switch
        {
            NotSent => "Not sent",
            Sent => "Waiting",
            Completed => "Completed",
            _ => status ?? string.Empty
        };

        public static string BadgeClass(string? status) => status switch
        {
            Sent => "text-bg-warning",
            Completed => "text-bg-success",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Header survei satu project (usp_Survey_Get result 1).</summary>
    public class ProjectSurvey
    {
        public int Id { get; set; }
        public int RequestId { get; set; }
        public string Category { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public DateTime SentAt { get; set; }
        public string SentBy { get; set; } = string.Empty;
        public string? SentByName { get; set; }
        public DateTime? SubmittedAt { get; set; }
        public string? SubmittedBy { get; set; }
        public string? SubmittedByName { get; set; }
        public string? NoteForCivil { get; set; }
        public decimal? ScorePercent { get; set; }

        /// <summary>User boleh mengisi: kabag departemen peminta dan survei masih SENT (BR-24; diperiksa ulang di SP).</summary>
        public bool CanFill { get; set; }

        public bool IsCompleted => Status == SurveyStatus.Completed;

        public IReadOnlyList<ProjectSurveyItem> Items { get; set; } = Array.Empty<ProjectSurveyItem>();
    }

    /// <summary>Item survei (snapshot template saat dikirim, BR-48) + nilai 1-10 (BR-49).</summary>
    public class ProjectSurveyItem
    {
        public int Id { get; set; }
        public int SortOrder { get; set; }
        public string ItemText { get; set; } = string.Empty;
        public byte? Score { get; set; }
    }

    /// <summary>Nilai satu item dari form isi survei.</summary>
    public class SurveyScoreInput
    {
        public int Id { get; set; }
        public int? Score { get; set; }
    }

    /// <summary>Baris halaman User Satisfaction (usp_Survey_GetPaged; BR-92).</summary>
    public class SurveyListItem
    {
        public int RequestId { get; set; }
        public string CoCode { get; set; } = string.Empty;
        public string? RequestNo { get; set; }
        public string Title { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string? DeptName { get; set; }
        public string? ABRV { get; set; }
        public string SurveyStatus { get; set; } = string.Empty;
        public DateTime? SentAt { get; set; }
        public DateTime? SubmittedAt { get; set; }
        public string? SubmittedBy { get; set; }
        public string? SubmittedByName { get; set; }
        public decimal? ScorePercent { get; set; }
        public string? NoteForCivil { get; set; }
        public DateTime? ClosedAt { get; set; }

        /// <summary>Tanggal periode: submit, atau kirim bila belum diisi, atau Closed bila belum dikirim.</summary>
        public DateTime? PeriodDate { get; set; }
    }

    /// <summary>Halaman User Satisfaction: filter + hasil (BR-92, FR-04).</summary>
    public class SurveyListViewModel
    {
        public static readonly string[] AllowedSortBy = { "PeriodDate", "RequestNo", "Score" };

        public string? CoCode { get; set; }
        public string? Category { get; set; }
        public string? SurveyStatus { get; set; }

        /// <summary>Bulan periode "yyyy-MM" (input type="month"); kosong = semua bulan.</summary>
        public string? Month { get; set; }

        public string? Search { get; set; }
        public string SortBy { get; set; } = "PeriodDate";
        public string SortDir { get; set; } = "DESC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public bool ShowCompanyFilter { get; set; }

        /// <summary>Bulan hasil parse (tanggal 1); null = semua.</summary>
        public DateTime? MonthDate { get; set; }

        public PagedResult<SurveyListItem> Result { get; set; } = new();
    }
}
