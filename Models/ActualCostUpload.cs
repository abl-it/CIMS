namespace CIMS.Models
{
    /// <summary>Status file upload actual cost (dbo.ActualCostUpload; T5-3).</summary>
    public static class ActualUploadStatus
    {
        public const string Pending = "PENDING";
        public const string Imported = "IMPORTED";
        public const string Cancelled = "CANCELLED";

        public static string Label(string? code) => code switch
        {
            Pending => "Pending",
            Imported => "Imported",
            Cancelled => "Cancelled",
            _ => code ?? string.Empty
        };

        public static string BadgeClass(string? code) => code switch
        {
            Pending => "text-bg-warning",
            Imported => "text-bg-success",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Satu baris data dari file Excel (kolom template PRD 6.4).</summary>
    public class ActualUploadRow
    {
        /// <summary>Nomor baris di Excel (untuk pesan error).</summary>
        public int Row { get; set; }
        public string? RequestNo { get; set; }
        public DateTime? Month { get; set; }
        public string? ItemType { get; set; }
        public string? ItemName { get; set; }
        public decimal? Qty { get; set; }
        public string? Unit { get; set; }
        public decimal? UnitPrice { get; set; }
        public decimal? Amount { get; set; }
        public string? ReferenceNo { get; set; }
        public string? Notes { get; set; }
    }

    /// <summary>Error per baris (usp_ActualUpload_Validate result 1, atau error baca file).</summary>
    public class ActualUploadError
    {
        public int RowNo { get; set; }
        public string Message { get; set; } = string.Empty;
    }

    /// <summary>Ringkasan per project + bulan (usp_ActualUpload_Validate result 2).</summary>
    public class ActualUploadGroup
    {
        public int RequestId { get; set; }
        public string RequestNo { get; set; } = string.Empty;
        public string Title { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string CoCode { get; set; } = string.Empty;
        public DateTime PeriodMonth { get; set; }
        public int ItemCount { get; set; }
        public decimal TotalAmount { get; set; }
        public decimal? ExistingAmount { get; set; }
        public string? ExistingSource { get; set; }
        public bool WillReplace { get; set; }
        public decimal? EstimateAmount { get; set; }
    }

    /// <summary>Hasil upload + preview. UploadId null = file ditolak (lihat Errors).</summary>
    public class ActualUploadPreview
    {
        public int? UploadId { get; set; }
        public string FileName { get; set; } = string.Empty;
        public int RowCount { get; set; }
        public IReadOnlyList<ActualUploadError> Errors { get; set; } = Array.Empty<ActualUploadError>();
        public IReadOnlyList<ActualUploadGroup> Groups { get; set; } = Array.Empty<ActualUploadGroup>();
        public decimal TotalAmount => Groups.Sum(g => g.TotalAmount);
        public bool IsValid => UploadId.HasValue && Errors.Count == 0;
    }

    /// <summary>Arsip upload (usp_ActualUpload_GetPaged / GetById).</summary>
    public class ActualCostUploadItem
    {
        public int Id { get; set; }
        public string OriginalFileName { get; set; } = string.Empty;
        public string? RelativePath { get; set; }
        public string? ContentType { get; set; }
        public long FileSizeBytes { get; set; }
        public int RowTotal { get; set; }
        public int GroupTotal { get; set; }
        public decimal TotalAmount { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        public string CreatedBy { get; set; } = string.Empty;
        public DateTime? ProcessedAt { get; set; }
        public string? ProcessedBy { get; set; }
    }

    /// <summary>Halaman Actual Cost Upload: form + riwayat.</summary>
    public class ActualUploadIndexViewModel
    {
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;
        public bool CanUpload { get; set; }

        /// <summary>Untuk tombol Continue/Cancel pada upload PENDING milik user sendiri.</summary>
        public string? CurrentUsername { get; set; }

        public string AllowedExtensions { get; set; } = "xlsx";
        public int MaxSizeMB { get; set; } = 5;
        public PagedResult<ActualCostUploadItem> Result { get; set; } = new();
    }
}
