using CIMS.Models;

namespace CIMS.Services
{
    public interface IVendorService
    {
        Task<PagedResult<Vendor>> GetPagedAsync(string? search, bool? isActive, string? sortBy, string? sortDir,
            int pageNumber, int pageSize, CancellationToken ct = default);

        Task<Vendor?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <summary>Vendor aktif untuk dropdown kontrak; <paramref name="includeId"/> tetap ikut walau nonaktif.</summary>
        Task<IReadOnlyList<VendorOption>> GetActiveAsync(int? includeId = null, CancellationToken ct = default);

        /// <returns>Id vendor baru.</returns>
        /// <exception cref="VendorDuplicateCodeException">SP error 50081.</exception>
        /// <exception cref="VendorValidationException">SP error 50082.</exception>
        /// <exception cref="VendorDuplicateErpNoException">SP error 50084.</exception>
        Task<int> InsertAsync(Vendor vendor, CancellationToken ct = default);

        /// <exception cref="VendorDuplicateCodeException">SP error 50081.</exception>
        /// <exception cref="VendorValidationException">SP error 50082.</exception>
        /// <exception cref="VendorNotFoundException">SP error 50083.</exception>
        /// <exception cref="VendorDuplicateErpNoException">SP error 50084.</exception>
        Task UpdateAsync(Vendor vendor, CancellationToken ct = default);

        /// <exception cref="VendorNotFoundException">SP error 50083.</exception>
        Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default);
    }
}
