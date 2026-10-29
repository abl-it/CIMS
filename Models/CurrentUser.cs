namespace CIMS.Models
{
    /// <summary>Data user login dari database portal (home), sesuai kolom usp_Auth_GetUserByUsername.</summary>
    public class CurrentUser
    {
        public string Username { get; set; } = string.Empty;
        public string EmployeeCode { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public string? JobTitle { get; set; }
        public string? CoCode { get; set; }
        public string? DeptName { get; set; }
        public string? ABRV { get; set; }

        /// <summary>home..users.Role. Hanya dimuat; TIDAK dipakai untuk keputusan akses (lihat Tahap B).</summary>
        public string? PortalRole { get; set; }

        /// <summary>Role CIMS yang terdaftar di dbo.HierarchyLevel, urut level naik. Hanya untuk tampilan.</summary>
        public List<UserRole> Roles { get; set; } = new();

        /// <summary>Role tertinggi (level terkecil); null bila tidak punya role terdaftar.</summary>
        public UserRole? HighestRole => Roles.FirstOrDefault();
    }
}
