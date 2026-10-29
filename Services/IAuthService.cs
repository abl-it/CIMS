using CIMS.Models;

namespace CIMS.Services
{
    public interface IAuthService
    {
        /// <returns>User dari home..users, atau null jika belum terdaftar.</returns>
        Task<CurrentUser?> GetUserByUsernameAsync(string username, CancellationToken ct = default);
    }
}
