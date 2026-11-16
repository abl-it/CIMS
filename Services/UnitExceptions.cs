namespace CIMS.Services
{
    /// <summary>SP error 50091: nama satuan duplikat.</summary>
    public class UnitDuplicateNameException : Exception
    {
        public UnitDuplicateNameException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50092: input wajib kosong / tidak valid.</summary>
    public class UnitValidationException : Exception
    {
        public UnitValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50093: data satuan tidak ditemukan.</summary>
    public class UnitNotFoundException : Exception
    {
        public UnitNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
