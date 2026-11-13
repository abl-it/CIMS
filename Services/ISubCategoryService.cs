using CIMS.Models;

namespace CIMS.Services
{
    public interface ISubCategoryService
    {
        Task<PagedResult<SubCategory>> GetPagedAsync(string? category, string? search, bool? isActive,
            string? sortBy, string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default);

        Task<SubCategory?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <summary>Sub-kategori aktif per kategori, urut SortOrder (dropdown cascade form request, T2).</summary>
        Task<IReadOnlyList<SubCategory>> GetActiveByCategoryAsync(string category, CancellationToken ct = default);

        /// <returns>Id sub-kategori baru.</returns>
        /// <exception cref="SubCategoryDuplicateCodeException">SP error 50061.</exception>
        /// <exception cref="SubCategoryDuplicateNameException">SP error 50064.</exception>
        /// <exception cref="SubCategoryValidationException">SP error 50062.</exception>
        Task<int> InsertAsync(SubCategory subCategory, CancellationToken ct = default);

        /// <summary>Code dan Category tidak ikut diubah.</summary>
        /// <exception cref="SubCategoryDuplicateNameException">SP error 50064.</exception>
        /// <exception cref="SubCategoryValidationException">SP error 50062.</exception>
        /// <exception cref="SubCategoryNotFoundException">SP error 50063.</exception>
        Task UpdateAsync(SubCategory subCategory, CancellationToken ct = default);

        /// <exception cref="SubCategoryNotFoundException">SP error 50063.</exception>
        Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default);
    }
}
