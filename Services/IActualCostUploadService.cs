using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>Upload actual cost lewat template Excel (T5-3; PRD 6.4, BR-18, BR-19). Library: ClosedXML.</summary>
    public interface IActualCostUploadService
    {
        /// <summary>Format dan ukuran file dari jenis lampiran tahap COST (BR-45); default xlsx / 5 MB.</summary>
        Task<(string AllowedExtensions, int MaxSizeMB)> GetFileRulesAsync(CancellationToken ct = default);

        /// <summary>
        /// Baca + validasi file (all or nothing). Valid -> file diarsipkan (PENDING) dan preview per project + bulan.
        /// Tidak valid -> daftar error per baris, file tidak disimpan.
        /// </summary>
        /// <exception cref="RequestValidationException">File kosong / format / ukuran / tidak bisa dibaca.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<ActualUploadPreview> PreviewAsync(IFormFile? file, CancellationToken ct = default);

        /// <summary>
        /// Lanjutkan upload PENDING milik user: baca ulang file arsip dan validasi lagi (data bisa berubah sejak upload).
        /// </summary>
        /// <returns>null bila upload tidak ada, bukan milik user, bukan PENDING, atau file arsip tidak ada.</returns>
        Task<ActualUploadPreview?> GetPendingPreviewAsync(int uploadId, CancellationToken ct = default);

        /// <summary>Konfirmasi: baca ulang file arsip lalu simpan semua project + bulan (satu transaksi).</summary>
        /// <returns>Arsip upload setelah diproses.</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (data berubah / sudah diproses).</exception>
        /// <exception cref="RequestNotFoundException">Upload tidak ditemukan.</exception>
        Task<ActualCostUploadItem> ImportAsync(int uploadId, CancellationToken ct = default);

        /// <exception cref="RequestValidationException">SP error 50072 (tidak ada / sudah diproses).</exception>
        Task CancelAsync(int uploadId, CancellationToken ct = default);

        Task<PagedResult<ActualCostUploadItem>> GetPagedAsync(int pageNumber, int pageSize, CancellationToken ct = default);

        /// <returns>null bila tidak berhak / file tidak ada.</returns>
        Task<(ActualCostUploadItem Upload, string FullPath)?> GetForDownloadAsync(int uploadId, CancellationToken ct = default);

        /// <summary>File template kosong (.xlsx) dengan header dan pilihan Goods/Service.</summary>
        byte[] BuildTemplate();
    }
}
