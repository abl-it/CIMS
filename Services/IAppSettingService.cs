using CIMS.Models;

namespace CIMS.Services
{
    public interface IAppSettingService
    {
        /// <param name="coCode">Filter Company ('*', ABL, NKM); null = semua.</param>
        Task<IReadOnlyList<AppSetting>> ListAsync(string? coCode, CancellationToken ct = default);

        /// <summary>Baris persis (tanpa fallback '*').</summary>
        Task<AppSetting?> GetByKeyAsync(string coCode, string settingKey, CancellationToken ct = default);

        /// <exception cref="AppSettingValidationException">SP error 50052.</exception>
        /// <exception cref="AppSettingNotFoundException">SP error 50053.</exception>
        Task UpdateValueAsync(string coCode, string settingKey, string settingValue, CancellationToken ct = default);
    }
}
