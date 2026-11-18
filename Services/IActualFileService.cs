using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>
    /// Lampiran detail cost per project per bulan (BR-96, Keputusan 18-11-2026). File disimpan di storage lampiran
    /// (FileStorage:RealizationAttachmentsPath); aturan file dari jenis lampiran ACTUAL_DETAIL. Error SP diterjemahkan
    /// sama dengan request (50072-50075).
    /// </summary>
    public interface IActualFileService
    {
        /// <summary>Lampiran aktif satu bulan (month null = semua bulan); kosong bila tidak boleh melihat detail cost.</summary>
        Task<IReadOnlyList<ActualFile>> ListAsync(int requestId, DateTime? month, CancellationToken ct = default);

        /// <summary>Simpan actual bulan (manual) bersama lampiran baru dalam satu transaksi SP; file dihapus bila gagal.</summary>
        Task<ActualSaveResult> SaveMonthAsync(int requestId, DateTime month, IReadOnlyList<ActualItemInput> items, string? remarks,
            IReadOnlyList<IFormFile> files, CancellationToken ct = default);

        /// <summary>Tambah satu lampiran ke bulan (mis. bulan hasil upload Excel).</summary>
        Task AddAsync(int requestId, DateTime month, IFormFile? file, CancellationToken ct = default);

        /// <summary>Hapus (nonaktifkan) lampiran; lampiran terakhir bulan berisi actual ditolak SP.</summary>
        Task RemoveAsync(int fileId, CancellationToken ct = default);

        /// <summary>File untuk download; null bila tidak ada / tidak boleh / file hilang.</summary>
        Task<(ActualFile File, string FullPath)?> GetForDownloadAsync(int fileId, CancellationToken ct = default);
    }
}
