namespace CIMS.Models
{
    /// <summary>Master jenis lampiran (dbo.AttachmentType): format, ukuran maks, dan wajib per kategori pada satu tahap.</summary>
    public class AttachmentType
    {
        /// <summary>Kode tahap (sama dengan CHECK constraint di dbo.AttachmentType) dan label UI, urut sesuai alur proses.</summary>
        public static readonly IReadOnlyList<KeyValuePair<string, string>> Stages = new[]
        {
            new KeyValuePair<string, string>("REQUEST", "Request"),
            new KeyValuePair<string, string>("DOCUMENT", "Document Preparation"),
            new KeyValuePair<string, string>("PROCUREMENT", "Procurement (TOR)"),
            new KeyValuePair<string, string>("CONTRACT", "Contract"),
            new KeyValuePair<string, string>("BAPP", "BAPP"),
            new KeyValuePair<string, string>("COST", "Actual Cost")
        };

        public static string StageLabel(string? code) =>
            Stages.FirstOrDefault(s => s.Key == code).Value ?? code ?? string.Empty;

        public int Id { get; set; }
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Stage { get; set; } = string.Empty;
        public string AllowedExtensions { get; set; } = string.Empty;
        public int MaxSizeMB { get; set; }
        public bool IsMandatoryCapex { get; set; }
        public bool IsMandatoryOpex { get; set; }
        public bool IsMandatoryLve { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }

        /// <summary>Kategori yang mewajibkan lampiran ini, mis. "CAPEX, OPEX"; "-" bila tidak ada.</summary>
        public string MandatoryText
        {
            get
            {
                var list = new List<string>();
                if (IsMandatoryCapex) list.Add("CAPEX");
                if (IsMandatoryOpex) list.Add("OPEX");
                if (IsMandatoryLve) list.Add("LVE");
                return list.Count == 0 ? "-" : string.Join(", ", list);
            }
        }
    }
}
