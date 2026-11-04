namespace CIMS.Models
{
    /// <summary>Master item template survei kepuasan per kategori (dbo.SurveyTemplateItem); dinilai skala 1-10.</summary>
    public class SurveyTemplateItem
    {
        /// <summary>Kategori yang valid (sama dengan CHECK constraint), urut sesuai PRD.</summary>
        public static readonly string[] Categories = { "CAPEX", "OPEX", "LVE" };

        public int Id { get; set; }
        public string Category { get; set; } = string.Empty;
        public int SortOrder { get; set; }
        public string ItemText { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }
}
