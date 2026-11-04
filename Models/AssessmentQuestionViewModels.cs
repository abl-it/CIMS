using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class AssessmentQuestionListViewModel
    {
        public string? Search { get; set; }
        public bool? IsActive { get; set; }
        public string SortBy { get; set; } = "SortOrder";
        public string SortDir { get; set; } = "ASC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public PagedResult<AssessmentQuestion> Result { get; set; } = new();
    }

    public class AssessmentQuestionFormViewModel
    {
        public int Id { get; set; }

        [Display(Name = "Sort order")]
        [Range(1, 999, ErrorMessage = "{0} must be between {1} and {2}.")]
        public int SortOrder { get; set; } = 1;

        [Display(Name = "Question")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(300, ErrorMessage = "{0} must be at most {1} characters.")]
        public string QuestionText { get; set; } = string.Empty;

        [Display(Name = "Active")]
        public bool IsActive { get; set; } = true;

        public AssessmentQuestion ToEntity() => new()
        {
            Id = Id,
            SortOrder = SortOrder,
            QuestionText = QuestionText,
            IsActive = IsActive
        };

        public static AssessmentQuestionFormViewModel FromEntity(AssessmentQuestion q) => new()
        {
            Id = q.Id,
            SortOrder = q.SortOrder,
            QuestionText = q.QuestionText,
            IsActive = q.IsActive
        };
    }
}
