using CIMS.Models;

namespace CIMS.Services
{
    public interface IAssessmentQuestionService
    {
        Task<PagedResult<AssessmentQuestion>> GetPagedAsync(string? search, bool? isActive, string? sortBy,
            string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default);

        Task<AssessmentQuestion?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <returns>Id pertanyaan baru.</returns>
        /// <exception cref="AssessmentQuestionDuplicateException">SP error 50031.</exception>
        /// <exception cref="AssessmentQuestionValidationException">SP error 50032.</exception>
        Task<int> InsertAsync(AssessmentQuestion question, CancellationToken ct = default);

        /// <exception cref="AssessmentQuestionDuplicateException">SP error 50031.</exception>
        /// <exception cref="AssessmentQuestionValidationException">SP error 50032.</exception>
        /// <exception cref="AssessmentQuestionNotFoundException">SP error 50033.</exception>
        Task UpdateAsync(AssessmentQuestion question, CancellationToken ct = default);

        /// <exception cref="AssessmentQuestionNotFoundException">SP error 50033.</exception>
        Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default);
    }
}
