using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class SurveyTemplateItemListViewModel
    {
        public string? Category { get; set; }
        public string? Search { get; set; }
        public bool? IsActive { get; set; }
        public string SortBy { get; set; } = "Category";
        public string SortDir { get; set; } = "ASC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public PagedResult<SurveyTemplateItem> Result { get; set; } = new();
    }

    public class SurveyTemplateItemFormViewModel
    {
        public int Id { get; set; }

        [Display(Name = "Category")]
        [Required(ErrorMessage = "{0} is required.")]
        [RegularExpression("^(CAPEX|OPEX|LVE)$", ErrorMessage = "{0} is invalid.")]
        public string Category { get; set; } = string.Empty;

        [Display(Name = "Sort order")]
        [Range(1, 999, ErrorMessage = "{0} must be between {1} and {2}.")]
        public int SortOrder { get; set; } = 1;

        [Display(Name = "Item")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(200, ErrorMessage = "{0} must be at most {1} characters.")]
        public string ItemText { get; set; } = string.Empty;

        [Display(Name = "Active")]
        public bool IsActive { get; set; } = true;

        public SurveyTemplateItem ToEntity() => new()
        {
            Id = Id,
            Category = Category,
            SortOrder = SortOrder,
            ItemText = ItemText,
            IsActive = IsActive
        };

        public static SurveyTemplateItemFormViewModel FromEntity(SurveyTemplateItem s) => new()
        {
            Id = s.Id,
            Category = s.Category,
            SortOrder = s.SortOrder,
            ItemText = s.ItemText,
            IsActive = s.IsActive
        };
    }
}
