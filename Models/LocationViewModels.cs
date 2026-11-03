using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class LocationListViewModel
    {
        public string? CoCode { get; set; }
        public string? Search { get; set; }
        public bool? IsActive { get; set; }
        public string SortBy { get; set; } = "Name";
        public string SortDir { get; set; } = "ASC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public PagedResult<Location> Result { get; set; } = new();
    }

    public class LocationFormViewModel
    {
        /// <summary>Company yang valid untuk lokasi (sama dengan CHECK constraint di dbo.Location).</summary>
        public static readonly string[] CoCodes = { "ABL", "NKM" };

        public int Id { get; set; }

        [Display(Name = "Company")]
        [Required(ErrorMessage = "{0} is required.")]
        [RegularExpression("^(ABL|NKM)$", ErrorMessage = "{0} is invalid.")]
        public string CoCode { get; set; } = string.Empty;

        [Display(Name = "Name")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(100, ErrorMessage = "{0} must be at most {1} characters.")]
        public string Name { get; set; } = string.Empty;

        [Display(Name = "Active")]
        public bool IsActive { get; set; } = true;

        public Location ToEntity() => new()
        {
            Id = Id,
            CoCode = CoCode,
            Name = Name,
            IsActive = IsActive
        };

        public static LocationFormViewModel FromEntity(Location l) => new()
        {
            Id = l.Id,
            CoCode = l.CoCode,
            Name = l.Name,
            IsActive = l.IsActive
        };
    }
}
