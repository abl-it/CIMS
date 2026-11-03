namespace CIMS.Models
{
    /// <summary>Master lokasi / area per Company (dbo.Location).</summary>
    public class Location
    {
        public int Id { get; set; }
        public string CoCode { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public bool IsActive { get; set; } = true;
        public DateTime CreatedAt { get; set; }
        public string? CreatedBy { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? UpdatedBy { get; set; }
    }
}
