using CIMS.Models;

namespace CIMS.Services
{
    public interface IAttachmentTypeService
    {
        Task<PagedResult<AttachmentType>> GetPagedAsync(string? stage, string? search, bool? isActive, string? sortBy,
            string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default);

        Task<AttachmentType?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <returns>Id jenis lampiran baru.</returns>
        /// <exception cref="AttachmentTypeDuplicateCodeException">SP error 50021.</exception>
        /// <exception cref="AttachmentTypeValidationException">SP error 50022.</exception>
        Task<int> InsertAsync(AttachmentType attachmentType, CancellationToken ct = default);

        /// <summary>Code tidak diubah.</summary>
        /// <exception cref="AttachmentTypeValidationException">SP error 50022.</exception>
        /// <exception cref="AttachmentTypeNotFoundException">SP error 50023.</exception>
        Task UpdateAsync(AttachmentType attachmentType, CancellationToken ct = default);

        /// <exception cref="AttachmentTypeNotFoundException">SP error 50023.</exception>
        Task SetActiveAsync(int id, bool isActive, CancellationToken ct = default);
    }
}
