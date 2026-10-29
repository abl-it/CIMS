using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.IdentityModel.Tokens;

namespace CIMS.Middleware
{
    /// <summary>
    /// Login via portal SSO. Portal mengarahkan ke aplikasi dengan ?token={sessionId};
    /// middleware menukar sessionId ke JWT di API portal, memvalidasinya, lalu menyimpan identitas ke Session.
    /// JANGAN mencatat sessionId, token, atau URL token ke log.
    /// </summary>
    public class SessionTokenMiddleware
    {
        public const string HttpClientName = "SsoPortal";

        private readonly RequestDelegate _next;
        private readonly ILogger<SessionTokenMiddleware> _logger;
        private readonly IWebHostEnvironment _env;
        private readonly IConfiguration _configuration;
        private readonly IHttpClientFactory _httpClientFactory;

        public SessionTokenMiddleware(RequestDelegate next, ILogger<SessionTokenMiddleware> logger,
            IWebHostEnvironment env, IConfiguration configuration, IHttpClientFactory httpClientFactory)
        {
            _next = next;
            _logger = logger;
            _env = env;
            _configuration = configuration;
            _httpClientFactory = httpClientFactory;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            await context.Session.LoadAsync(context.RequestAborted);

            // Dev bypass: hanya Development DAN Auth:DevUsername terisi. Jika kosong, alur SSO normal.
            var devUsername = _configuration["Auth:DevUsername"];
            if (_env.IsDevelopment() && !string.IsNullOrWhiteSpace(devUsername))
            {
                context.Session.SetString("Username", devUsername);
                await _next(context);
                return;
            }

            var sessionId = context.Request.Query["token"].FirstOrDefault();

            if (!string.IsNullOrEmpty(sessionId))
            {
                var jwt = await RequestJwtAsync(sessionId, context.RequestAborted);
                if (string.IsNullOrWhiteSpace(jwt))
                {
                    _logger.LogWarning("SSO ditolak: token tidak diterima dari portal. Path: {Path}", context.Request.Path);
                    await DenyAsync(context);
                    return;
                }

                var username = ValidateAndExtractUsername(jwt);
                if (string.IsNullOrEmpty(username))
                {
                    _logger.LogWarning("SSO ditolak: token tidak valid. Path: {Path}", context.Request.Path);
                    await DenyAsync(context);
                    return;
                }

                context.Session.SetString("JWT", jwt);
                context.Session.SetString("Username", username);
                context.Session.SetString("SessionID", sessionId);
                _logger.LogInformation("SSO diterima untuk user {Username}. Path: {Path}", username, context.Request.Path);

                // Bersihkan token dari URL (address bar, history, log IIS); query lain dipertahankan.
                context.Response.Redirect(BuildUrlWithoutToken(context.Request));
                return;
            }

            if (string.IsNullOrEmpty(context.Session.GetString("JWT")))
            {
                _logger.LogInformation("Tanpa sesi, diarahkan ke login. Path: {Path}", context.Request.Path);
                await DenyAsync(context);
                return;
            }

            await _next(context);
        }

        private async Task DenyAsync(HttpContext context)
        {
            if (context.Request.IsAjaxRequest())
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { success = false, message = "Sesi berakhir" });
                return;
            }

            context.Response.Redirect(_configuration["SSO:PublicLogin"]!);
        }

        private async Task<string?> RequestJwtAsync(string sessionId, CancellationToken ct)
        {
            try
            {
                var client = _httpClientFactory.CreateClient(HttpClientName);
                var baseUrl = _configuration["SSO:InternalApi"]!.TrimEnd('/');
                var url = $"{baseUrl}/home/api/token?sessionId={Uri.EscapeDataString(sessionId)}";

                using var response = await client.GetAsync(url, ct);
                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogWarning("API token SSO mengembalikan {StatusCode}.", (int)response.StatusCode);
                    return null;
                }

                return (await response.Content.ReadAsStringAsync(ct)).Trim();
            }
            catch (Exception ex) when (!ct.IsCancellationRequested)
            {
                _logger.LogError(ex, "Tidak dapat terhubung ke API token SSO.");
                return null;
            }
        }

        // Parameter validasi mengikuti project Training persis (token diterbitkan portal). Jangan diubah.
        private string? ValidateAndExtractUsername(string token)
        {
            var parameters = new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_configuration["SSO:JwtKey"]!)),
                ValidateIssuer = false,
                ValidateAudience = false,
                ClockSkew = TimeSpan.Zero
            };

            try
            {
                var principal = new JwtSecurityTokenHandler().ValidateToken(token, parameters, out _);
                return principal.FindFirst(ClaimTypes.Name)?.Value;
            }
            catch (Exception ex)
            {
                // Hanya tipe exception; pesan/isi token tidak dicatat.
                _logger.LogWarning("Validasi token SSO gagal ({ExceptionType}).", ex.GetType().Name);
                return null;
            }
        }

        private static string BuildUrlWithoutToken(HttpRequest request)
        {
            var query = QueryHelpers.ParseQuery(request.QueryString.Value);
            query.Remove("token");

            var remaining = QueryString.Create(query);
            return $"{request.PathBase}{request.Path}{remaining}";
        }
    }
}
