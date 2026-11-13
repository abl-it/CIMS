using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class SubCategoryListViewModel
    {
        public string? Category { get; set; }
        public string? Search { get; set; }
        public bool? IsActive { get; set; }
        public string SortBy { get; set; } = "Category";
        public string SortDir { get; set; } = "ASC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public PagedResult<SubCategory> Result { get; set; } = new();
    }

    public class SubCategoryFormViewModel
    {
        public int Id { get; set; }

        /// <summary>Wajib saat Create; saat Edit hanya ditampilkan (tidak diubah oleh SP Update).</summary>
        [Display(Name = "Category")]
        [Required(ErrorMessage = "{0} is required.")]
        [RegularExpression("^(CAPEX|OPEX|LVE)$", ErrorMessage = "{0} is invalid.")]
        public string Category { get; set; } = string.Empty;

        /// <summary>Wajib saat Create; saat Edit hanya ditampilkan (tidak diubah oleh SP Update).</summary>
        [Display(Name = "Code")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(30, ErrorMessage = "{0} must be at most {1} characters.")]
        [RegularExpression("^[A-Za-z0-9_]+$", ErrorMessage = "{0} may only contain letters, numbers, and underscores.")]
        public string Code { get; set; } = string.Empty;

        [Display(Name = "Name")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(100, ErrorMessage = "{0} must be at most {1} characters.")]
        public string Name { get; set; } = string.Empty;

        [Display(Name = "Sort order")]
        [Range(1, 999, ErrorMessage = "{0} must be between {1} and {2}.")]
        public int SortOrder { get; set; } = 1;

        [Display(Name = "Active")]
        public bool IsActive { get; set; } = true;

        public SubCategory ToEntity() => new()
        {
            Id = Id,
            Category = Category,
            Code = Code,
            Name = Name,
            SortOrder = SortOrder,
            IsActive = IsActive
        };

        public static SubCategoryFormViewModel FromEntity(SubCategory s) => new()
        {
            Id = s.Id,
            Category = s.Category,
            Code = s.Code,
            Name = s.Name,
            SortOrder = s.SortOrder,
            IsActive = s.IsActive
        };
    }
}
