namespace CIMS.Models
{
    /// <summary>Status addendum (dbo.ProjectAddendum.Status; T4-4, BR-80 s.d. BR-82) dan teks UI.</summary>
    public static class AddendumStatus
    {
        public const string PendingApproval = "PENDING_APPROVAL";

        /// <summary>Outsource: menunggu Civil upload kontrak final bertanda tangan (BR-87, Keputusan 18-11-2026).</summary>
        public const string FinalContract = "FINAL_CONTRACT";

        public const string Adjustment = "ADJUSTMENT";
        public const string Completed = "COMPLETED";
        public const string Rejected = "REJECTED";

        /// <summary>Addendum terbuka: mengunci perubahan schedule/estimasi biasa dan addendum baru (BR-81).</summary>
        public static bool IsOpen(string? code) => code is PendingApproval or FinalContract or Adjustment;

        public static string Label(string? code) => code switch
        {
            PendingApproval => "Waiting for approval",
            FinalContract => "Waiting for signed contract",
            Adjustment => "Waiting for schedule adjustment",
            Completed => "Completed",
            Rejected => "Rejected",
            _ => code ?? string.Empty
        };

        public static string BadgeClass(string? code) => code switch
        {
            PendingApproval => "text-bg-info",
            FinalContract => "text-bg-primary",
            Adjustment => "text-bg-warning",
            Completed => "text-bg-success",
            Rejected => "text-bg-danger",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Addendum kontrak (outsource) / perubahan budget BOQ (in-house) dari usp_Addendum_GetByRequest.</summary>
    public class ProjectAddendum
    {
        public int Id { get; set; }
        public int RequestId { get; set; }
        public int AddendumNo { get; set; }

        /// <summary>Nomor addendum otomatis {RequestNo}-A{n} (Keputusan 18-11-2026).</summary>
        public string? AddendumCode { get; set; }

        public string ExecutionType { get; set; } = string.Empty;

        /// <summary>Nomor dokumen referensi: wajib outsource (dokumen addendum kontrak), opsional in-house.</summary>
        public string? DocumentNo { get; set; }

        /// <summary>Nomor tampilan; fallback bila nomor otomatis belum terisi.</summary>
        public string DisplayCode => string.IsNullOrEmpty(AddendumCode) ? $"Addendum {AddendumNo}" : AddendumCode;
        public DateTime AddendumDate { get; set; }
        public decimal PreviousValue { get; set; }
        public decimal NewValue { get; set; }
        public string Reason { get; set; } = string.Empty;
        public bool RequiresApproval { get; set; }
        public string Status { get; set; } = string.Empty;
        public int AttachmentTypeId { get; set; }
        public string? AttachmentTypeName { get; set; }
        public string OriginalFileName { get; set; } = string.Empty;
        public string? ContentType { get; set; }
        public long FileSizeBytes { get; set; }
        public DateTime? ApprovedAt { get; set; }
        public DateTime? ClosedAt { get; set; }
        public string? ClosedBy { get; set; }
        public string? ClosedByName { get; set; }
        public DateTime CreatedAt { get; set; }
        public string CreatedBy { get; set; } = string.Empty;
        public string? CreatedByName { get; set; }

        /// <summary>Kontrak final bertanda tangan (outsource, BR-87); null = belum diupload / in-house.</summary>
        public string? FinalAttachmentTypeName { get; set; }
        public string? FinalFileName { get; set; }
        public long? FinalFileSizeBytes { get; set; }
        public DateTime? FinalUploadedAt { get; set; }
        public string? FinalUploadedBy { get; set; }
        public string? FinalUploadedByName { get; set; }
        public bool HasFinalContract => !string.IsNullOrEmpty(FinalFileName);

        public decimal Difference => NewValue - PreviousValue;
        public bool IsOpen => AddendumStatus.IsOpen(Status);

        /// <summary>Langkah approval addendum ini (Round = AddendumNo); kosong bila tanpa approval.</summary>
        public IReadOnlyList<AddendumStepItem> Steps { get; set; } = Array.Empty<AddendumStepItem>();
    }

    /// <summary>Langkah approval titik ADDENDUM (usp_Addendum_GetByRequest result 2).</summary>
    public class AddendumStepItem
    {
        public int Id { get; set; }
        public int AddendumNo { get; set; }
        public int StepOrder { get; set; }
        public string RoleCode { get; set; } = string.Empty;
        public string? RoleName { get; set; }
        public bool AllowReject { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime? StartedAt { get; set; }
        public DateTime? ActedAt { get; set; }
        public string? ActedBy { get; set; }
        public string? ActedByName { get; set; }
        public string? Remarks { get; set; }
        public bool IsCurrent { get; set; }

        public string StatusLabel => Status switch
        {
            "PENDING" => IsCurrent ? "Waiting" : "Pending",
            "APPROVED" => "Approved",
            "REJECTED" => "Rejected",
            "VOID" => "Closed",
            _ => Status
        };

        public string StatusBadgeClass => Status switch
        {
            "PENDING" => IsCurrent ? "text-bg-info" : "text-bg-light border",
            "APPROVED" => "text-bg-success",
            "REJECTED" => "text-bg-danger",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Hasil usp_Addendum_Create.</summary>
    public class AddendumCreateResult
    {
        public int Id { get; set; }
        public int AddendumNo { get; set; }
        public string? AddendumCode { get; set; }
        public string Status { get; set; } = string.Empty;
        public bool RequiresApproval { get; set; }
    }

    /// <summary>Metadata file addendum untuk download (usp_Addendum_GetFile).</summary>
    public class AddendumFile
    {
        public int Id { get; set; }
        public int RequestId { get; set; }
        public int AddendumNo { get; set; }
        public string? AddendumCode { get; set; }
        public string OriginalFileName { get; set; } = string.Empty;
        public string RelativePath { get; set; } = string.Empty;
        public string ContentType { get; set; } = "application/octet-stream";
        public long FileSizeBytes { get; set; }
    }

    /// <summary>Form input addendum (purchasing: outsource, civil: in-house; BR-79). Validasi akhir di SP.</summary>
    public class AddendumInput
    {
        /// <summary>Nomor dokumen referensi (wajib outsource, opsional in-house); nomor addendum dibuat sistem.</summary>
        public string? DocumentNo { get; set; }
        public DateTime? AddendumDate { get; set; }
        public decimal? NewValue { get; set; }
        public string? Reason { get; set; }
    }
}
