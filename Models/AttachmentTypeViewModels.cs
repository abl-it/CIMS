using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class AttachmentTypeListViewModel
    {
        public string? Stage { get; set; }
        public string? Search { get; set; }
        public bool? IsActive { get; set; }
        public string SortBy { get; set; } = "Stage";
        public string SortDir { get; set; } = "ASC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public PagedResult<AttachmentType> Result { get; set; } = new();
    }

    public class AttachmentTypeFormViewModel
    {
        public int Id { get; set; }

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

        [Display(Name = "Stage")]
        [Required(ErrorMessage = "{0} is required.")]
        public string Stage { get; set; } = string.Empty;

        [Display(Name = "Allowed extensions")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(200, ErrorMessage = "{0} must be at most {1} characters.")]
        public string AllowedExtensions { get; set; } = string.Empty;

        [Display(Name = "Max size (MB)")]
        [Range(1, 100, ErrorMessage = "{0} must be between {1} and {2}.")]
        public int MaxSizeMB { get; set; } = 5;

        [Display(Name = "Mandatory for CAPEX")]
        public bool IsMandatoryCapex { get; set; }

        [Display(Name = "Mandatory for OPEX")]
        public bool IsMandatoryOpex { get; set; }

        [Display(Name = "Mandatory for LVE")]
        public bool IsMandatoryLve { get; set; }

        [Display(Name = "Active")]
        public bool IsActive { get; set; } = true;

        public AttachmentType ToEntity() => new()
        {
            Id = Id,
            Code = Code,
            Name = Name,
            Stage = Stage,
            AllowedExtensions = AllowedExtensions,
            MaxSizeMB = MaxSizeMB,
            IsMandatoryCapex = IsMandatoryCapex,
            IsMandatoryOpex = IsMandatoryOpex,
            IsMandatoryLve = IsMandatoryLve,
            IsActive = IsActive
        };

        public static AttachmentTypeFormViewModel FromEntity(AttachmentType a) => new()
        {
            Id = a.Id,
            Code = a.Code,
            Name = a.Name,
            Stage = a.Stage,
            AllowedExtensions = a.AllowedExtensions,
            MaxSizeMB = a.MaxSizeMB,
            IsMandatoryCapex = a.IsMandatoryCapex,
            IsMandatoryOpex = a.IsMandatoryOpex,
            IsMandatoryLve = a.IsMandatoryLve,
            IsActive = a.IsActive
        };
    }
}
