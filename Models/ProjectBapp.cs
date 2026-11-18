namespace CIMS.Models
{
    /// <summary>Status BAPP per ronde (dbo.ProjectBapp; T6-1, BR-88, BR-89) dan teks UI.</summary>
    public static class BappStatus
    {
        public const string Review = "REVIEW";
        public const string Returned = "RETURNED";
        public const string Accepted = "ACCEPTED";

        public static string Label(string? code) => code switch
        {
            Review => "In review",
            Returned => "Returned to Civil",
            Accepted => "Accepted",
            _ => code ?? string.Empty
        };

        public static string BadgeClass(string? code) => code switch
        {
            Review => "text-bg-info",
            Returned => "text-bg-warning",
            Accepted => "text-bg-success",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>
    /// Hasil pemeriksaan bagian D (diisi Kabag; BR-89). Label English untuk UI, label Indonesia untuk cetak (BR-94).
    /// </summary>
    public static class BappInspection
    {
        public const string AsSpecified = "SESUAI";
        public const string WithNotes = "SESUAI_CATATAN";
        public const string NotAsSpecified = "BELUM_SESUAI";

        public static readonly string[] All = { AsSpecified, WithNotes, NotAsSpecified };

        public static string Label(string? code) => code switch
        {
            AsSpecified => "As per contract / specification",
            WithNotes => "As per contract with correction notes",
            NotAsSpecified => "Not as specified",
            _ => code ?? string.Empty
        };

        /// <summary>Teks cetak sesuai template FM-DGO-03.</summary>
        public static string PrintLabel(string code) => code switch
        {
            AsSpecified => "Sesuai kontrak/spesifikasi",
            WithNotes => "Sesuai dengan catatan perbaikan",
            NotAsSpecified => "Belum sesuai",
            _ => code
        };
    }

    /// <summary>Satu penerbitan BAPP (usp_Bapp_GetByRequest result 1); Steps = langkah approval ronde ini.</summary>
    public class ProjectBapp
    {
        public int Id { get; set; }
        public int RequestId { get; set; }
        public int Round { get; set; }
        public string? BappNo { get; set; }
        public DateTime BappDate { get; set; }

        /// <summary>Lingkup pekerjaan (bagian C), diisi Civil saat terbit.</summary>
        public string? ScopeOfWork { get; set; }

        public string? Remarks { get; set; }
        public string Status { get; set; } = string.Empty;
        public DateTime IssuedAt { get; set; }
        public string IssuedBy { get; set; } = string.Empty;
        public string? IssuedByName { get; set; }

        /// <summary>Bagian D (Kabag) dan F (FAT / DGO / sistem) form BAPP online (BR-89, BR-93).</summary>
        public string? InspectionResult { get; set; }
        public string? InspectionNotes { get; set; }
        public DateTime? InspectedAt { get; set; }
        public string? InspectedBy { get; set; }
        public DateTime? NoOutstandingAt { get; set; }
        public string? NoOutstandingBy { get; set; }
        public DateTime? ClosedStatusAt { get; set; }
        public string? ClosedStatusBy { get; set; }
        public DateTime? ClosedAt { get; set; }
        public string? ClosedBy { get; set; }
        public string? ClosedByName { get; set; }

        public IReadOnlyList<BappStepItem> Steps { get; set; } = Array.Empty<BappStepItem>();

        /// <summary>Alasan "No" (langkah yang mengembalikan ke Civil), untuk petunjuk revisi.</summary>
        public BappStepItem? ReturnedStep => Steps.FirstOrDefault(s => s.Status == "REVISED");
    }

    /// <summary>Langkah approval titik BAPP (usp_Bapp_GetByRequest result 2).</summary>
    public class BappStepItem
    {
        public int Id { get; set; }
        public int Round { get; set; }
        public int StepOrder { get; set; }
        public string RoleCode { get; set; } = string.Empty;
        public string? RoleName { get; set; }
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
            "APPROVED" => "Accepted",
            "REVISED" => "No (returned)",
            "VOID" => "Closed",
            _ => Status
        };

        public string StatusBadgeClass => Status switch
        {
            "PENDING" => IsCurrent ? "text-bg-info" : "text-bg-light border",
            "APPROVED" => "text-bg-success",
            "REVISED" => "text-bg-warning",
            _ => "text-bg-secondary"
        };
    }

    /// <summary>Form terbitkan BAPP online (Civil; BR-88). Nomor BAPP dibuat sistem (BR-95). Validasi akhir di SP.</summary>
    public class BappInput
    {
        public DateTime? BappDate { get; set; }
        public string? ScopeOfWork { get; set; }
        public string? Remarks { get; set; }
    }

    /// <summary>Isian approval BAPP per langkah (BR-89, BR-93). Validasi akhir di SP (usp_Bapp_ApprovalAct).</summary>
    public class BappApprovalInput
    {
        public string? InspectionResult { get; set; }
        public string? InspectionNotes { get; set; }
        public bool Confirm { get; set; }
    }

    /// <summary>Data cetak Berita Acara (usp_Bapp_GetPrintData result 1; BR-94).</summary>
    public class BappPrintHeader
    {
        public int RequestId { get; set; }
        public string CoCode { get; set; } = string.Empty;
        public string? RequestNo { get; set; }
        public string Title { get; set; } = string.Empty;
        public string? ExecutionType { get; set; }
        public string? CostCenterCode { get; set; }
        public string? CostCenterName { get; set; }
        public string? DeptName { get; set; }
        public string? ABRV { get; set; }
        public string? ContractNo { get; set; }
        public DateTime? ContractDate { get; set; }
        public decimal? ContractValue { get; set; }
        public string? VendorName { get; set; }
        public DateTime? PlanStartDate { get; set; }
        public DateTime? PlanEndDate { get; set; }
        public DateTime? ActualStartDate { get; set; }
        public DateTime? ActualEndDate { get; set; }
        public DateTime? SiteHandoverDate { get; set; }
        public decimal? PlanCost { get; set; }
        public decimal ActualCostTotal { get; set; }
        public int Round { get; set; }
        public string? BappNo { get; set; }
        public DateTime BappDate { get; set; }
        public string? ScopeOfWork { get; set; }
        public string? InspectionResult { get; set; }
        public string? InspectionNotes { get; set; }
        public DateTime? NoOutstandingAt { get; set; }
        public DateTime? ClosedStatusAt { get; set; }
        public string? ClosedStatusBy { get; set; }
        public DateTime? ProjectClosedAt { get; set; }
    }

    /// <summary>Tanda tangan digital (penerbit Civil + langkah approval ronde ACCEPTED).</summary>
    public class BappSignature
    {
        public string RoleCode { get; set; } = string.Empty;
        public int StepOrder { get; set; }
        public string? Username { get; set; }
        public string? FullName { get; set; }
        public DateTime? SignedAt { get; set; }
    }

    /// <summary>Rincian biaya Lampiran 1 (item actual cost).</summary>
    public class BappPrintItem
    {
        public DateTime PeriodMonth { get; set; }
        public int LineNumber { get; set; }
        public string ItemType { get; set; } = string.Empty;
        public string ItemName { get; set; } = string.Empty;
        public decimal Qty { get; set; }
        public string Unit { get; set; } = string.Empty;
        public decimal UnitPrice { get; set; }
        public decimal Amount { get; set; }
        public string? ReferenceNo { get; set; }
    }

    /// <summary>Foto dokumentasi Lampiran 2 (lampiran BAPP_PHOTO_*).</summary>
    public class BappPhoto
    {
        public int Id { get; set; }
        public string AttachmentTypeCode { get; set; } = string.Empty;
        public string? AttachmentTypeName { get; set; }
        public string OriginalFileName { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }

    /// <summary>Halaman cetak Berita Acara (BR-94).</summary>
    public class BappPrintViewModel
    {
        public BappPrintHeader Header { get; set; } = new();
        public IReadOnlyList<BappSignature> Signatures { get; set; } = Array.Empty<BappSignature>();
        public IReadOnlyList<BappPrintItem> Items { get; set; } = Array.Empty<BappPrintItem>();
        public IReadOnlyList<BappPhoto> Photos { get; set; } = Array.Empty<BappPhoto>();

        /// <summary>Tanda tangan untuk role langkah (kabag, fat, dgo, gm, director) atau 'civil' (penerbit).</summary>
        public BappSignature? Sign(string roleCode) =>
            Signatures.FirstOrDefault(s => string.Equals(s.RoleCode, roleCode, StringComparison.OrdinalIgnoreCase));
    }
}
