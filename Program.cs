using CIMS.Filters;
using CIMS.Middleware;
using CIMS.Services;

var builder = WebApplication.CreateBuilder(args);

// Konfigurasi SSO wajib lengkap di luar Development (JwtKey dari environment variable / konfigurasi server, bukan repo).
if (!builder.Environment.IsDevelopment())
{
    foreach (var key in new[] { "SSO:JwtKey", "SSO:InternalApi", "SSO:PublicLogin" })
    {
        if (string.IsNullOrWhiteSpace(builder.Configuration[key]))
        {
            throw new InvalidOperationException(
                $"Konfigurasi '{key}' kosong. Isi lewat environment variable (mis. SSO__JwtKey) atau file konfigurasi di server.");
        }
    }
}

// Add services to the container.
// ProfileAttribute dipasang global agar controller baru tidak bisa lupa memuat CurrentUser.
builder.Services.AddControllersWithViews(options => options.Filters.AddService<ProfileAttribute>());

builder.Services.AddHttpClient(SessionTokenMiddleware.HttpClientName, client => client.Timeout = TimeSpan.FromSeconds(10));
// Logging bawaan HttpClient mencetak URL lengkap (termasuk ?sessionId=...). Matikan untuk client SSO.
builder.Logging.AddFilter($"System.Net.Http.HttpClient.{SessionTokenMiddleware.HttpClientName}", LogLevel.None);

builder.Services.AddDistributedMemoryCache();
builder.Services.AddSession(options =>
{
    options.Cookie.Name = ".CIMS.Session"; // unik: portal dan aplikasi lain berbagi host
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
    options.Cookie.SameSite = SameSiteMode.Lax;
    options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
    options.IdleTimeout = TimeSpan.FromMinutes(480);
});

builder.Services.AddSingleton<IDbConnectionFactory, SqlConnectionFactory>();
builder.Services.AddScoped<ProfileAttribute>();
builder.Services.AddScoped<ICurrentUserService, CurrentUserService>();
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<ICustomerService, CustomerService>();
builder.Services.AddScoped<ILocationService, LocationService>();
builder.Services.AddScoped<IAttachmentTypeService, AttachmentTypeService>();
builder.Services.AddScoped<IAssessmentQuestionService, AssessmentQuestionService>();
builder.Services.AddScoped<ISurveyTemplateItemService, SurveyTemplateItemService>();
builder.Services.AddScoped<IAppSettingService, AppSettingService>();
builder.Services.AddScoped<ISubCategoryService, SubCategoryService>();
builder.Services.AddScoped<IVendorService, VendorService>();
builder.Services.AddScoped<IUnitService, UnitService>();
builder.Services.AddScoped<IActualCostUploadService, ActualCostUploadService>();
builder.Services.AddScoped<IDashboardService, DashboardService>();
builder.Services.Configure<FileStorageOptions>(builder.Configuration.GetSection(FileStorageOptions.SectionName));
builder.Services.AddScoped<IRequestLookupService, RequestLookupService>();
builder.Services.AddScoped<IRequestService, RequestService>();
builder.Services.AddScoped<IRequestAttachmentService, RequestAttachmentService>();
builder.Services.AddScoped<IAddendumService, AddendumService>();
builder.Services.AddScoped<IBappService, BappService>();
builder.Services.AddScoped<IUserTaskService, UserTaskService>();

var app = builder.Build();

if (app.Environment.IsDevelopment()
    && string.IsNullOrWhiteSpace(app.Configuration["Auth:DevUsername"])
    && string.IsNullOrWhiteSpace(app.Configuration["SSO:JwtKey"]))
{
    app.Logger.LogWarning("Auth:DevUsername dan SSO:JwtKey kosong: login SSO tidak akan berhasil. Isi Auth:DevUsername (appsettings.Development.json) atau SSO:JwtKey (User Secrets).");
}

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
}
app.UseStaticFiles();

// Kultur tetap en-US (UI Inggris): angka desimal dari form (input type=number, titik desimal) terbaca sama
// di semua server, tidak bergantung pada regional setting Windows (mis. id-ID memakai koma desimal).
var appCulture = new System.Globalization.CultureInfo("en-US");
app.UseRequestLocalization(new RequestLocalizationOptions
{
    DefaultRequestCulture = new Microsoft.AspNetCore.Localization.RequestCulture(appCulture),
    SupportedCultures = new[] { appCulture },
    SupportedUICultures = new[] { appCulture }
});

app.UseRouting();

app.UseSession();
app.UseMiddleware<SessionTokenMiddleware>();

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
