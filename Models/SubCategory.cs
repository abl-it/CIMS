namespace CIMS.Models
{
    /// <summary>Master sub-kategori pekerjaan per kategori (dbo.SubCategory; MD-01). Code dan Category tidak bisa diubah.</summary>
    public class SubCategory
    {
        /// <summary>Kategori yang valid (sama dengan CHECK constraint), urut sesuai PRD.</summary>
        public static readonly string[] Categories = { "CAPEX", "OPEX", "LVE" };

        public int Id { get; set; }
        public string Category { get; set; } = string.Empty;
        public string Code { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public int SortOrder { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }
}
