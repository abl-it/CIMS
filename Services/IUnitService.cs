using CIMS.Models;

namespace CIMS.Services
{
    public interface IUnitService
    {
        Task<PagedResult<Unit>> GetPagedAsync(string? search, bool? isActive, string? sortBy, string? sortDir,
            int pageNumber, int pageSize, CancellationToken ct = default);

        Task<Unit?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <summary>Satuan aktif (saran satuan item actual cost).</summary>
        Task<IReadOnlyList<UnitOption>> GetActiveAsync(CancellationToken ct = default);

        /// <returns>Id satuan baru.</returns>
        /// <exception cref="UnitDuplicateNameException">SP error 50091.</exception>
        /// <exception cref="UnitValidationException">SP error 50092.</exception>
        Task<int> InsertAsync(Unit unit, CancellationToken ct = default);

        /// <exception cref="UnitDuplicateNameException">SP error 50091.</exception>
        /// <exception cref="UnitValidationException">SP error 50092.</exception>
        /// <exception cref="UnitNotFoundException">SP error 50093.</exception>
        Task UpdateAsync(Unit unit, CancellationToken ct = default);

        /// <exception cref="UnitNotFoundException">SP error 50093.</exception>
        Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default);
    }
}
