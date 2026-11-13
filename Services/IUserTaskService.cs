using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>Tugas Saya (FR-01) dan badge header (FR-02); sumber tunggal dbo.fn_User_Tasks untuk user saat ini.</summary>
    public interface IUserTaskService
    {
        /// <summary>Jumlah tugas per jenis; total = angka badge.</summary>
        Task<IReadOnlyList<UserTaskSummaryItem>> GetSummaryAsync(CancellationToken ct = default);

        /// <summary>Daftar tugas, terlama di atas. <paramref name="taskType"/> null = semua jenis.</summary>
        Task<IReadOnlyList<UserTaskItem>> GetListAsync(string? taskType, CancellationToken ct = default);

        /// <summary>Tandai tugas informasi (REJECTED) sudah dibuka; diabaikan bila bukan tugas user.</summary>
        Task MarkReadAsync(int requestId, string taskType, CancellationToken ct = default);
    }
}
