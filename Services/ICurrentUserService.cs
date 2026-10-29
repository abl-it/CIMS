using CIMS.Models;

namespace CIMS.Services
{
    /// <summary>
    /// Identitas user untuk request berjalan. Diisi oleh ProfileAttribute (filter global).
    /// Controller/Service wajib memakai ini, jangan membaca Session["Username"] langsung.
    /// </summary>
    public interface ICurrentUserService
    {
        CurrentUser? CurrentUser { get; set; }
    }
}
