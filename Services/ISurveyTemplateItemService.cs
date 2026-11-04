using CIMS.Models;

namespace CIMS.Services
{
    public interface ISurveyTemplateItemService
    {
        Task<PagedResult<SurveyTemplateItem>> GetPagedAsync(string? category, string? search, bool? isActive,
            string? sortBy, string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default);

        Task<SurveyTemplateItem?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <returns>Id item baru.</returns>
        /// <exception cref="SurveyTemplateItemDuplicateException">SP error 50041.</exception>
        /// <exception cref="SurveyTemplateItemValidationException">SP error 50042.</exception>
        Task<int> InsertAsync(SurveyTemplateItem item, CancellationToken ct = default);

        /// <exception cref="SurveyTemplateItemDuplicateException">SP error 50041.</exception>
        /// <exception cref="SurveyTemplateItemValidationException">SP error 50042.</exception>
        /// <exception cref="SurveyTemplateItemNotFoundException">SP error 50043.</exception>
        Task UpdateAsync(SurveyTemplateItem item, CancellationToken ct = default);

        /// <exception cref="SurveyTemplateItemNotFoundException">SP error 50043.</exception>
        Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default);
    }
}
