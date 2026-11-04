namespace CIMS.Services
{
    /// <summary>SP error 50021: Code jenis lampiran duplikat.</summary>
    public class AttachmentTypeDuplicateCodeException : Exception
    {
        public AttachmentTypeDuplicateCodeException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50022: input wajib kosong / tidak valid.</summary>
    public class AttachmentTypeValidationException : Exception
    {
        public AttachmentTypeValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50023: data jenis lampiran tidak ditemukan.</summary>
    public class AttachmentTypeNotFoundException : Exception
    {
        public AttachmentTypeNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
