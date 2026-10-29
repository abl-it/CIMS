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

        [Display(Name = "Kode")]
        [Required(ErrorMessage = "{0} wajib diisi.")]
        [StringLength(20, ErrorMessage = "{0} maksimal {1} karakter.")]
        public string Code { get; set; } = string.Empty;

        [Display(Name = "Nama")]
        [Required(ErrorMessage = "{0} wajib diisi.")]
        [StringLength(100, ErrorMessage = "{0} maksimal {1} karakter.")]
        public string Name { get; set; } = string.Empty;

        [Display(Name = "Telepon")]
        [Phone(ErrorMessage = "Format {0} tidak valid.")]
        [StringLength(20, ErrorMessage = "{0} maksimal {1} karakter.")]
        public string? Phone { get; set; }

        [Display(Name = "Email")]
        [EmailAddress(ErrorMessage = "Format {0} tidak valid.")]
        [StringLength(100, ErrorMessage = "{0} maksimal {1} karakter.")]
        public string? Email { get; set; }

        [Display(Name = "Alamat")]
        [StringLength(250, ErrorMessage = "{0} maksimal {1} karakter.")]
        public string? Address { get; set; }

        [Display(Name = "Aktif")]
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
