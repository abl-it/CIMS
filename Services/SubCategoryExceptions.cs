namespace CIMS.Services
{
    /// <summary>SP error 50061: Code duplikat.</summary>
    public class SubCategoryDuplicateCodeException : Exception
    {
        public SubCategoryDuplicateCodeException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50064: Name duplikat pada kategori yang sama.</summary>
    public class SubCategoryDuplicateNameException : Exception
    {
        public SubCategoryDuplicateNameException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50062: input wajib kosong / tidak valid.</summary>
    public class SubCategoryValidationException : Exception
    {
        public SubCategoryValidationException(string message, Exception? inner = null) : base(message, inner) { }
    }

    /// <summary>SP error 50063: sub-kategori tidak ditemukan.</summary>
    public class SubCategoryNotFoundException : Exception
    {
        public SubCategoryNotFoundException(string message, Exception? inner = null) : base(message, inner) { }
    }
}
