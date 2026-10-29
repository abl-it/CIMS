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
    }
}
