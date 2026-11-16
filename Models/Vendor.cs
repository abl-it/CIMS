namespace CIMS.Models
{
    /// <summary>Master vendor (dbo.Vendor; PRD MD-03). Dipakai bersama ABL dan NKM.</summary>
    public class Vendor
    {
        public int Id { get; set; }
        public string Code { get; set; } = string.Empty;
        /// <summary>Nomor vendor di ERP (opsional, unik bila diisi).</summary>
        public string? ErpVendorNo { get; set; }
        public string Name { get; set; } = string.Empty;
        public string? ContactPerson { get; set; }
        public string? Phone { get; set; }
        public string? Email { get; set; }
        public string? Address { get; set; }
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }

    /// <summary>Pilihan dropdown vendor (usp_Vendor_GetActive).</summary>
    public class VendorOption
    {
        public int Id { get; set; }
        public string Code { get; set; } = string.Empty;
        public string? ErpVendorNo { get; set; }
        public string Name { get; set; } = string.Empty;

        public string DisplayText => string.IsNullOrEmpty(ErpVendorNo)
            ? $"{Code} - {Name}"
            : $"{Code} - {Name} (ERP {ErpVendorNo})";
    }
}
