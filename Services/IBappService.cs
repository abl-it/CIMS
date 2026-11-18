using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>
    /// BAPP online (T6-1; PRD 3.4, BR-88, BR-89, BR-93, BR-94, BR-95).
    /// Error SP diterjemahkan sama dengan request (50072-50075).
    /// </summary>
    public interface IBappService
    {
        /// <summary>BAPP per ronde (terbaru di atas) + langkah approval; kosong bila tidak boleh melihat (5.2).</summary>
        Task<IReadOnlyList<ProjectBapp>> GetByRequestAsync(int requestId, CancellationToken ct = default);

        /// <summary>Terbitkan BAPP online (Civil, In Progress -> BAPP Review). Mengembalikan status baru dan nomor BAPP.</summary>
        Task<(string Status, string? BappNo)> IssueAsync(int requestId, BappInput input, CancellationToken ct = default);

        /// <summary>Accept (APPROVE) / No (REVISE) langkah BAPP + isian per langkah. Mengembalikan status request baru.</summary>
        Task<string> ApprovalActAsync(int requestId, int stepId, string action, string? remarks, BappApprovalInput input,
            CancellationToken ct = default);

        /// <summary>Data cetak Berita Acara (Civil, setelah Closed); null bila tidak boleh / belum Closed.</summary>
        Task<BappPrintViewModel?> GetPrintDataAsync(int requestId, CancellationToken ct = default);
    }
}
