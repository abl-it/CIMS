namespace CIMS.Filters
{
    /// <summary>
    /// Action cukup untuk user yang punya minimal satu role CIMS (<see cref="CimsRoles.All"/>).
    /// Hanya untuk action read-only; action yang mengubah data wajib menyebut role spesifik.
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
    public class AllowAllRolesAttribute : RoleAuthorizeAttribute
    {
        public AllowAllRolesAttribute() : base(CimsRoles.All)
        {
        }
    }
}
