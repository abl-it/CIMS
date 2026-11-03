using System.ComponentModel.DataAnnotations;

namespace CIMS.Models
{
    public class CustomerListViewModel
    {
        public string? Search { get; set; }
        public bool? IsActive { get; set; }
        public string SortBy { get; set; } = "Code";
        public string SortDir { get; set; } = "ASC";
        public int Page { get; set; } = 1;
        public int PageSize { get; set; } = 10;

        public PagedResult<Customer> Result { get; set; } = new();
    }

    public class CustomerFormViewModel
    {
        public int Id { get; set; }

        [Display(Name = "Code")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(20, ErrorMessage = "{0} must be at most {1} characters.")]
        public string Code { get; set; } = string.Empty;

        [Display(Name = "Name")]
        [Required(ErrorMessage = "{0} is required.")]
        [StringLength(100, ErrorMessage = "{0} must be at most {1} characters.")]
        public string Name { get; set; } = string.Empty;

        [Display(Name = "Phone")]
        [Phone(ErrorMessage = "{0} format is invalid.")]
        [StringLength(20, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Phone { get; set; }

        [Display(Name = "Email")]
        [EmailAddress(ErrorMessage = "{0} format is invalid.")]
        [StringLength(100, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Email { get; set; }

        [Display(Name = "Address")]
        [StringLength(250, ErrorMessage = "{0} must be at most {1} characters.")]
        public string? Address { get; set; }

        [Display(Name = "Active")]
        public bool IsActive { get; set; } = true;

        public Customer ToEntity() => new()
        {
            Id = Id,
            Code = Code,
            Name = Name,
            Phone = Phone,
            Email = Email,
            Address = Address,
            IsActive = IsActive
        };

        public static CustomerFormViewModel FromEntity(Customer c) => new()
        {
            Id = c.Id,
            Code = c.Code,
            Name = c.Name,
            Phone = c.Phone,
            Email = c.Email,
            Address = c.Address,
            IsActive = c.IsActive
        };
    }
}
