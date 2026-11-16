namespace CIMS.Services
{
    /// <summary>SP error 50081: kode vendor duplikat.</summary>
    public class VendorDuplicateCodeException : Exception
    {
        public VendorDuplicateCodeException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50082: input wajib kosong / tidak valid.</summary>
    public class VendorValidationException : Exception
    {
        public VendorValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50083: data vendor tidak ditemukan.</summary>
    public class VendorNotFoundException : Exception
    {
        public VendorNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50084: nomor vendor ERP duplikat.</summary>
    public class VendorDuplicateErpNoException : Exception
    {
        public VendorDuplicateErpNoException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
