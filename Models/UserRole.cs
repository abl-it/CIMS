namespace CIMS.Models
{
    /// <summary>Satu role user yang terdaftar di dbo.HierarchyLevel (angka HierarchyLevel kecil = lebih tinggi).</summary>
    public class UserRole
    {
        public string Role { get; set; } = string.Empty;
        public int HierarchyLevel { get; set; }
        public string? Description { get; set; }

        /// <summary>Teks tampilan: Description bila terisi, jika kosong kode role.</summary>
        public string DisplayText => string.IsNullOrWhiteSpace(Description) ? Role : Description;
    }
}
