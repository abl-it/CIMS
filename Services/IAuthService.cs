using CIMS.Models;

namespace CIMS.Services
{
    public interface IAuthService
    {
        /// <returns>User dari home..users, atau null jika belum terdaftar.</returns>
        Task<CurrentUser?> GetUserByUsernameAsync(string username, CancellationToken ct = default);

        /// <returns>Role terdaftar milik user (dbo.HierarchyLevel), urut level naik; kosong bila tidak ada.</returns>
        Task<IReadOnlyList<UserRole>> GetUserRolesAsync(string username, CancellationToken ct = default);
    }
}
