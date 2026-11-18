using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>
    /// Addendum kontrak (outsource) / perubahan budget BOQ (in-house) (T4-4; PRD 3.3.1, BR-78 s.d. BR-86).
    /// Error SP diterjemahkan sama dengan request: 50072 RequestValidationException, 50073 RequestNotFoundException,
    /// 50074 RequestInvalidStateException, 50075 RequestNotAuthorizedException.
    /// </summary>
    public interface IAddendumService
    {
        /// <summary>Addendum project (terbaru di atas) beserta langkah approval; kosong bila tidak boleh melihat (BR-86).</summary>
        Task<IReadOnlyList<ProjectAddendum>> GetByRequestAsync(int requestId, CancellationToken ct = default);

        /// <summary>Aturan file raise dari master Jenis Lampiran: ADDENDUM = draft kontrak (outsource) / BOQ_REVISION (in-house).</summary>
        Task<AttachmentType?> GetFileTypeAsync(string? executionType, CancellationToken ct = default);

        /// <summary>Aturan file kontrak final bertanda tangan (ADDENDUM_FINAL; BR-87).</summary>
        Task<AttachmentType?> GetFinalFileTypeAsync(CancellationToken ct = default);

        /// <summary>Raise addendum oleh Civil + file wajib (BR-79). Nilai naik -> menunggu approval (BR-80).</summary>
        Task<AddendumCreateResult> CreateAsync(int requestId, AddendumInput input, IFormFile? file, CancellationToken ct = default);

        /// <summary>Upload kontrak final bertanda tangan (outsource, BR-87): FINAL_CONTRACT -> ADJUSTMENT.</summary>
        Task UploadFinalContractAsync(int requestId, int addendumId, IFormFile? file, string? remarks, CancellationToken ct = default);

        /// <summary>Approve / Reject langkah approval addendum (BR-80). Mengembalikan status addendum yang baru.</summary>
        Task<string> ApprovalActAsync(int addendumId, int stepId, string action, string? remarks, CancellationToken ct = default);

        /// <summary>Penyesuaian Civil: action plan + estimasi dalam satu transaksi (BR-82 s.d. BR-85).</summary>
        Task SaveAdjustmentAsync(int addendumId, DateTime projectStartDate, IEnumerable<ActionPlanInput> actionPlans,
            IEnumerable<(DateTime Month, decimal Amount)> estimates, string? remarks, CancellationToken ct = default);

        /// <summary>
        /// File addendum untuk download (hak lihat BR-86); final = kontrak final, selain itu file saat raise.
        /// Null bila tidak ada / tidak boleh / file hilang.
        /// </summary>
        Task<(AddendumFile File, string FullPath)?> GetForDownloadAsync(int addendumId, bool final, CancellationToken ct = default);
    }
}
