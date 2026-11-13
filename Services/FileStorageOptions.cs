namespace CIMS.Services
{
    /// <summary>Konfigurasi "FileStorage" di appsettings (CF-04, BR-44).</summary>
    public class FileStorageOptions
    {
        public const string SectionName = "FileStorage";

        /// <summary>Folder akar semua lampiran, mis. D:\APP_DATA\CIMSAttachments. Subfolder {tahun}\{RequestId}.</summary>
        public string RealizationAttachmentsPath { get; set; } = string.Empty;
    }
}
