using CIMS.Models;

namespace CIMS.Services
{
    public interface ILocationService
    {
        Task<PagedResult<Location>> GetPagedAsync(string? coCode, string? search, bool? isActive, string? sortBy,
            string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default);

        Task<Location?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <returns>Id lokasi baru.</returns>
        /// <exception cref="LocationDuplicateNameException">SP error 50011.</exception>
        /// <exception cref="LocationValidationException">SP error 50012.</exception>
        Task<int> InsertAsync(Location location, CancellationToken ct = default);

        /// <exception cref="LocationDuplicateNameException">SP error 50011.</exception>
        /// <exception cref="LocationValidationException">SP error 50012.</exception>
        /// <exception cref="LocationNotFoundException">SP error 50013.</exception>
        Task UpdateAsync(Location location, CancellationToken ct = default);

        /// <exception cref="LocationNotFoundException">SP error 50013.</exception>
        Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default);
    }
}
