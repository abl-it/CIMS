using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    /// <summary>Master satuan (dbo.Unit; PRD MD-04). Saran satuan pada item actual cost.</summary>
    public class Unit
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }

    /// <summary>Satuan aktif (usp_Unit_GetActive).</summary>
    public class UnitOption
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? Description { get; set; }
    }

    public class UnitListViewModel
    {
        public string? Search { get; set; }
        public bool? IsActive { get; set; }
        public string SortBy { get; set; } = "Name";
        public string SortDir { get; set; } = "ASC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public PagedResult<Unit> Result { get; set; } = new();
    }

    public class UnitFormViewModel
    {
        public int Id { get; set; }

        [Display(Name = "Name")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(30, ErrorMessage = "{0} must be at most {1} characters.")]
        public string Name { get; set; } = string.Empty;

        [Display(Name = "Description")]
        [StringLength(100, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Description { get; set; }

        [Display(Name = "Active")]
        public bool IsActive { get; set; } = true;

        public Unit ToEntity() => new() { Id = Id, Name = Name, Description = Description, IsActive = IsActive };

        public static UnitFormViewModel FromEntity(Unit u) => new()
        {
            Id = u.Id,
            Name = u.Name,
            Description = u.Description,
            IsActive = u.IsActive
        };
    }
}
