using CIMS.Models;

namespace CIMS.Filters
{
    /// <summary>
    /// Kode role CIMS (PRD 5.1) sesuai dbo.HierarchyLevel.Role. Satu-satunya tempat string role;
    /// atribut dan kode lain wajib memakai konstanta ini.
    /// </summary>
    public static class CimsRoles
    {
        public const string Administrator = "administrator";
        public const string Director = "director";
        public const string Gm = "gm";
        public const string Civil = "civil";
        public const string Fat = "fat";
        public const string Mo = "mo";
        public const string Purchasing = "purchasing";
        public const string Kabag = "kabag";
        public const string Plan = "plan";
        public const string Spv = "spv";
        public const string Adm = "adm";
        public const string Emp = "emp";

        /// <summary>Semua role CIMS. User tanpa satu pun role ini ditolak di seluruh aplikasi.</summary>
        public static readonly string[] All =
        {
            Administrator, Director, Gm, Civil, Fat, Mo, Purchasing, Kabag, Plan, Spv, Adm, Emp
        };

        /// <summary>Any-of, case-insensitive: true bila salah satu role user ada di daftar <paramref name="allowed"/>.</summary>
        public static bool HasAny(CurrentUser? user, IEnumerable<string> allowed)
        {
            if (user == null || user.Roles.Count == 0) return false;
            var set = allowed as ISet<string> ?? new HashSet<string>(allowed, StringComparer.OrdinalIgnoreCase);
            return user.Roles.Any(r => set.Contains(r.Role, StringComparer.OrdinalIgnoreCase));
        }
    }
}
