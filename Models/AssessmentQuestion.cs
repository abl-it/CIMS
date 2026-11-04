namespace CIMS.Models
{
    /// <summary>Master pertanyaan Environment Assessment (dbo.AssessmentQuestion); jawaban Yes/No di form request.</summary>
    public class AssessmentQuestion
    {
        public int Id { get; set; }
        public int SortOrder { get; set; }
        public string QuestionText { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }
}
