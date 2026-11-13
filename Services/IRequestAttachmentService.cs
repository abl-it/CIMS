using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>Lampiran request: file di FileStorage:RealizationAttachmentsPath, metadata di dbo.RequestAttachment.</summary>
    public interface IRequestAttachmentService
    {
        Task<IReadOnlyList<RequestAttachment>> ListAsync(int requestId, CancellationToken ct = default);

        /// <summary>Validasi (jenis tahap REQUEST, ekstensi, ukuran, status), simpan file, catat metadata.</summary>
        /// <exception cref="RequestValidationException">Input tidak valid (SP 50072 atau validasi aplikasi).</exception>
        /// <exception cref="RequestNotFoundException">Request di luar lingkup / tidak ada.</exception>
        /// <exception cref="RequestInvalidStateException">Status bukan Draft/Returned.</exception>
        Task<int> UploadAsync(int requestId, int attachmentTypeId, IFormFile? file, CancellationToken ct = default);

        /// <summary>Metadata + path fisik untuk download; null bila tidak ada / di luar lingkup / file hilang.</summary>
        Task<(RequestAttachment Attachment, string FullPath)?> GetForDownloadAsync(int id, CancellationToken ct = default);

        /// <summary>Nonaktifkan lampiran (BR-46: file tidak dihapus).</summary>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        Task DeactivateAsync(int id, CancellationToken ct = default);
    }
}
