namespace CIMS.Middleware
{
    public static class RequestExtensions
    {
        /// <summary>Request AJAX/API: header X-Requested-With: XMLHttpRequest atau Accept memuat application/json.</summary>
        public static bool IsAjaxRequest(this HttpRequest request)
        {
            if (string.Equals(request.Headers["X-Requested-With"], "XMLHttpRequest", StringComparison.OrdinalIgnoreCase))
                return true;

            return request.Headers.Accept.ToString().Contains("application/json", StringComparison.OrdinalIgnoreCase);
        }
    }
}
