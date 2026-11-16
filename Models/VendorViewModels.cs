using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class VendorListViewModel
    {
        public string? Search { get; set; }
        public bool? IsActive { get; set; }
        public string SortBy { get; set; } = "Name";
        public string SortDir { get; set; } = "ASC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public PagedResult<Vendor> Result { get; set; } = new();
    }

    public class VendorFormViewModel
    {
        public int Id { get; set; }

        [Display(Name = "Code")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(20, ErrorMessage = "{0} must be at most {1} characters.")]
        public string Code { get; set; } = string.Empty;

        [Display(Name = "ERP vendor number")]
        [StringLength(30, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? ErpVendorNo { get; set; }

        [Display(Name = "Name")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(150, ErrorMessage = "{0} must be at most {1} characters.")]
        public string Name { get; set; } = string.Empty;

        [Display(Name = "Contact person")]
        [StringLength(100, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? ContactPerson { get; set; }

        [Display(Name = "Phone")]
        [Phone(ErrorMessage = "{0} format is invalid.")]
        [StringLength(30, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Phone { get; set; }

        [Display(Name = "Email")]
        [EmailAddress(ErrorMessage = "{0} format is invalid.")]
        [StringLength(100, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Email { get; set; }

        [Display(Name = "Address")]
        [StringLength(300, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Address { get; set; }

        [Display(Name = "Active")]
        public bool IsActive { get; set; } = true;

        public Vendor ToEntity() => new()
        {
            Id = Id,
            Code = Code,
            ErpVendorNo = ErpVendorNo,
            Name = Name,
            ContactPerson = ContactPerson,
            Phone = Phone,
            Email = Email,
            Address = Address,
            IsActive = IsActive
        };

        public static VendorFormViewModel FromEntity(Vendor v) => new()
        {
            Id = v.Id,
            Code = v.Code,
            ErpVendorNo = v.ErpVendorNo,
            Name = v.Name,
            ContactPerson = v.ContactPerson,
            Phone = v.Phone,
            Email = v.Email,
            Address = v.Address,
            IsActive = v.IsActive
        };
    }
}
