using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>Request / business case (T2). Semua akses dibatasi lingkup data user (fn_User_AllowedDepartments).</summary>
    public interface IRequestService
    {
        Task<PagedResult<RequestListItem>> GetPagedAsync(string? coCode, string? search, string? category, string? status,
            string? sortBy, string? sortDir, int pageNumber, int pageSize, CancellationToken ct = default);

        /// <returns>null bila tidak ada atau di luar lingkup user.</returns>
        Task<ProjectRequest?> GetByIdAsync(int id, CancellationToken ct = default);

        /// <summary>Draft/Returned: pertanyaan aktif + jawaban; status lain: snapshot jawaban.</summary>
        Task<IReadOnlyList<RequestAssessmentItem>> GetAssessmentAsync(int requestId, CancellationToken ct = default);

        /// <summary>Simpan draft baru (Id = 0) atau ubah draft/returned. Jawaban null = belum dijawab (tidak disimpan).</summary>
        /// <returns>Id request.</returns>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        Task<int> SaveDraftAsync(ProjectRequest request, IEnumerable<RequestAnswerInput> answers, CancellationToken ct = default);

        /// <summary>Submit pertama / Resubmit (T2-2): cek kelengkapan, nomor, snapshot langkah approval.</summary>
        /// <returns>Nomor request dan status baru.</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (pesan memuat daftar kekurangan).</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        Task<(string RequestNo, string Status)> SubmitAsync(int id, CancellationToken ct = default);

        /// <summary>Batalkan request (BR-09); alasan wajib.</summary>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        Task CancelAsync(int id, string? reason, CancellationToken ct = default);

        /// <summary>Langkah approval ronde terakhir per titik.</summary>
        Task<IReadOnlyList<ApprovalStepItem>> GetApprovalStepsAsync(int requestId, CancellationToken ct = default);

        /// <summary>Jejak aksi, terbaru di atas.</summary>
        Task<IReadOnlyList<ApprovalHistoryItem>> GetHistoryAsync(int requestId, CancellationToken ct = default);

        /// <summary>Langkah approval aktif yang boleh diproses user saat ini (T2-3); null = tidak ada.</summary>
        Task<ApprovalStepItem?> GetActionableStepAsync(int requestId, CancellationToken ct = default);

        /// <summary>Approve / Revise / Reject langkah titik REQUEST (BR-03, BR-08, BR-30, BR-39, BR-50).</summary>
        /// <param name="action">APPROVE | REVISE | REJECT (lihat <see cref="ApprovalAction"/>).</param>
        /// <returns>Status request yang baru.</returns>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074 (termasuk sudah diproses approver lain).</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075.</exception>
        Task<string> ApprovalActAsync(int id, int stepId, string action, string? remarks, CancellationToken ct = default);

        /// <summary>Ubah kategori / sub-kategori saat Feasibility oleh Civil (BR-02); kategori berubah -> nomor baru (BR-54).</summary>
        /// <returns>Nomor request setelah perubahan.</returns>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<string?> ChangeCategoryAsync(int id, string category, int subCategoryId, string? reason, CancellationToken ct = default);

        /// <summary>Keputusan Feasibility oleh Civil: FEASIBLE | REVISE | REJECT (lihat <see cref="FeasibilityDecision"/>).</summary>
        /// <returns>Status request yang baru.</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (termasuk lampiran wajib belum lengkap).</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<string> FeasibilityDecideAsync(int id, string decision, string? remarks, CancellationToken ct = default);

        /// <summary>Isi / ubah BOQ total (IDR) saat Document Preparation oleh Civil (BR-05, BR-12).</summary>
        /// <exception cref="RequestValidationException">SP error 50072.</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task SetBoqTotalAsync(int id, decimal boqTotal, CancellationToken ct = default);

        /// <summary>Kirim ke management (BR-53: langkah MGMT disusun saat ini). Wajib BOQ total + lampiran DOCUMENT wajib.</summary>
        /// <returns>Status request yang baru (MGMT_APPROVAL, atau PLANNING bila tidak ada langkah MGMT).</returns>
        /// <exception cref="RequestValidationException">SP error 50072 (pesan memuat daftar kekurangan).</exception>
        /// <exception cref="RequestNotFoundException">SP error 50073.</exception>
        /// <exception cref="RequestInvalidStateException">SP error 50074.</exception>
        /// <exception cref="RequestNotAuthorizedException">SP error 50075 (bukan Civil).</exception>
        Task<string> SendToManagementAsync(int id, string? remarks, CancellationToken ct = default);

        /// <summary>Log perubahan kategori (BR-02), terbaru di atas.</summary>
        Task<IReadOnlyList<CategoryChangeItem>> GetCategoryChangesAsync(int requestId, CancellationToken ct = default);
    }
}
