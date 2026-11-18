using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>
    /// Survei kepuasan user setelah Closed (T6-2; PRD 3.4 langkah 7, BR-24, BR-48, BR-49, BR-91, BR-92).
    /// Error SP diterjemahkan sama dengan request (50072-50075).
    /// </summary>
    public interface ISurveyService
    {
        /// <summary>Survei + item; null bila belum dikirim atau user tidak boleh melihat (5.2).</summary>
        Task<ProjectSurvey?> GetByRequestAsync(int requestId, CancellationToken ct = default);

        /// <summary>Civil mengirim survei (request Closed). Mengembalikan jumlah item.</summary>
        Task<int> SendAsync(int requestId, CancellationToken ct = default);

        /// <summary>Kabag departemen peminta submit nilai (final). Mengembalikan skor %.</summary>
        Task<decimal> SubmitAsync(int requestId, IReadOnlyList<SurveyScoreInput> scores, string? noteForCivil,
            CancellationToken ct = default);

        /// <summary>Daftar User Satisfaction (lingkup user di SP). pageSize maks. 5000 (export).</summary>
        Task<PagedResult<SurveyListItem>> GetPagedAsync(string? coCode, string? category, string? surveyStatus, DateTime? month,
            string? search, string? sortBy, string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default);
    }
}
