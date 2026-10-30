using System.Collections.Concurrent;
using System.Net;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Hosting;

namespace Aukkhor.Windows;

internal interface IAukkhorUi
{
    Task<string> ReadClipboardAsync();
    Task SetClipboardAsync(string text);
    bool AllowClipboardRead { get; }
    bool AllowClipboardWrite { get; }
    void ReceivedCode(string code);
    void Report(string text);
    bool RemoteTypingEnabled { get; }
    string? FocusedFieldTag { get; }
    Task<bool> TypeRemoteTextAsync(string text, string expectedFocus);
}

internal sealed class AukkhorService(IAukkhorUi ui) : IAsyncDisposable
{
    public const int Port = 45789;
    private const int MaxClipboardBytes = 64 * 1024;
    private readonly object gate = new();
    private readonly ConcurrentDictionary<string, DateTimeOffset> sessions = new();
    private readonly TrustData trust = TrustStore.LoadOrCreate();
    private readonly X509Certificate2 certificate = TrustStore.LoadOrCreateCertificate();
    private WebApplication? app;
    private string pairCode = "";
    private DateTimeOffset pairExpiry;
    private int failedPairings;
    private readonly Dictionary<string, DateTimeOffset> challenges = new();
    private int challengeFailures;
    private string? lastCode;
    private DateTimeOffset codeExpiry;
    private string? lastFocus;
    private string remoteSession = "";
    private string remoteLabel = "Windows text field";

    private sealed record TrustData(string Id, string Secret);
    private sealed record ChallengeData(string Id, string Nonce);
    public string Fingerprint => Convert.ToHexString(SHA256.HashData(certificate.RawData));
    public string PairCode
    {
        get
        {
            lock (gate)
            {
                if (DateTimeOffset.UtcNow >= pairExpiry) NewPairCode();
                return pairCode;
            }
        }
    }
    public bool Running => app is not null;

    private void NewPairCode()
    {
        pairCode = RandomNumberGenerator.GetInt32(1_000_000).ToString("D6");
        pairExpiry = DateTimeOffset.UtcNow.AddMinutes(15);
        failedPairings = 0;
    }

    public static IEnumerable<(IPAddress Address, string Name)> Interfaces() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(n => n.GetIPProperties().UnicastAddresses.Select(a => (a.Address, n.Name)))
            .Where(item => item.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork && IsPrivate(item.Address));

    private static bool IsPrivate(IPAddress ip)
    {
        var p = ip.GetAddressBytes();
        return p[0] == 10 || (p[0] == 172 && p[1] >= 16 && p[1] <= 31) ||
               (p[0] == 192 && p[1] == 168);
    }

    public async Task StartAsync(IPAddress address)
    {
        if (app is not null) throw new InvalidOperationException("Receiver already started");
        if (!IsPrivate(address) || !Interfaces().Any(x => x.Address.Equals(address)))
            throw new InvalidOperationException("Choose an active private IPv4 adapter");
        lock (gate) NewPairCode();

        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.ConfigureKestrel(k => k.Listen(address, Port, listen => listen.UseHttps(certificate)));
        var server = builder.Build();
        server.MapPost("/pair", PairAsync);
        server.MapGet("/challenge", ChallengeAsync);
        server.MapPost("/reconnect", ReconnectAsync);
        server.MapGet("/clipboard", GetClipboardAsync);
        server.MapPost("/clipboard", PostClipboardAsync);
        server.MapPost("/code", PostCodeAsync);
        server.MapGet("/prompt", GetPromptAsync);
        server.MapPost("/type", PostTypeAsync);
        await server.StartAsync();
        app = server;
        ui.Report($"Aukkhor listening on https://{address}:{Port}");
    }

    private static bool ConstantTimeHex(string supplied, string expected) =>
        supplied.Length == expected.Length &&
        CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(supplied), Encoding.ASCII.GetBytes(expected));

    private async Task PairAsync(HttpContext ctx)
    {
        string current;
        lock (gate)
        {
            if (DateTimeOffset.UtcNow >= pairExpiry) NewPairCode();
            if (failedPairings >= 10) { ctx.Response.StatusCode = 429; return; }
            current = pairCode;
        }
        if (!ConstantTimeHex(ctx.Request.Headers["X-Aukkhor-Code"].ToString(), current))
        {
            lock (gate) failedPairings++;
            ctx.Response.StatusCode = 403;
            return;
        }
        ctx.Response.Headers.CacheControl = "no-store";
        await ctx.Response.WriteAsJsonAsync(trust);
        ui.Report("iPhone paired securely. It can reconnect without a code.");
    }

    private async Task ChallengeAsync(HttpContext ctx)
    {
        string nonce;
        lock (gate)
        {
            foreach (var expired in challenges.Where(pair => pair.Value <= DateTimeOffset.UtcNow)
                                            .Select(pair => pair.Key).ToArray()) challenges.Remove(expired);
            if (challenges.Count >= 32) { ctx.Response.StatusCode = 429; return; }
            nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
            challenges[nonce] = DateTimeOffset.UtcNow.AddMinutes(1);
            challengeFailures = 0;
        }
        ctx.Response.Headers.CacheControl = "no-store";
        await ctx.Response.WriteAsJsonAsync(new ChallengeData(trust.Id, nonce));
    }

    private async Task ReconnectAsync(HttpContext ctx)
    {
        var supplied = ctx.Request.Headers["X-Aukkhor-Proof"].ToString();
        bool valid;
        lock (gate)
        {
            var secret = Convert.FromHexString(trust.Secret);
            string? matchingNonce = null;
            foreach (var entry in challenges)
            {
                var expected = Convert.ToHexString(HMACSHA256.HashData(secret, Encoding.UTF8.GetBytes(entry.Key)));
                if (entry.Value > DateTimeOffset.UtcNow && ConstantTimeHex(supplied, expected)) matchingNonce = entry.Key;
            }
            valid = matchingNonce is not null;
            if (matchingNonce is not null) challenges.Remove(matchingNonce);
            if (!valid && ++challengeFailures >= 10) challenges.Clear();
        }
        if (!valid) { ctx.Response.StatusCode = 403; return; }
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
        sessions[token] = DateTimeOffset.UtcNow.AddMinutes(10);
        ctx.Response.Headers.CacheControl = "no-store";
        await ctx.Response.WriteAsync(token);
    }

    private bool Authorized(HttpContext ctx)
    {
        var value = ctx.Request.Headers.Authorization.ToString();
        if (!value.StartsWith("Bearer ", StringComparison.Ordinal)) return false;
        var token = value[7..];
        return sessions.TryGetValue(token, out var expiry) && expiry > DateTimeOffset.UtcNow;
    }

    private async Task GetClipboardAsync(HttpContext ctx)
    {
        if (!Authorized(ctx) || !ui.AllowClipboardRead) { ctx.Response.StatusCode = 403; return; }
        var data = Encoding.UTF8.GetBytes(await ui.ReadClipboardAsync());
        if (data.Length > MaxClipboardBytes) { ctx.Response.StatusCode = 413; return; }
        ctx.Response.ContentType = "text/plain; charset=utf-8";
        ctx.Response.Headers.CacheControl = "no-store";
        await ctx.Response.Body.WriteAsync(data);
    }

    private async Task PostClipboardAsync(HttpContext ctx)
    {
        if (!Authorized(ctx) || !ui.AllowClipboardWrite) { ctx.Response.StatusCode = 403; return; }
        var data = await ReadBounded(ctx, MaxClipboardBytes);
        if (data is null) { ctx.Response.StatusCode = 413; return; }
        try
        {
            var text = new UTF8Encoding(false, true).GetString(data);
            await ui.SetClipboardAsync(text);
            ui.Report("iPhone text clipboard received");
            await ctx.Response.WriteAsync("OK");
        }
        catch (DecoderFallbackException) { ctx.Response.StatusCode = 400; }
    }

    private async Task PostCodeAsync(HttpContext ctx)
    {
        if (!Authorized(ctx)) { ctx.Response.StatusCode = 403; return; }
        var data = await ReadBounded(ctx, 16);
        if (data is null) { ctx.Response.StatusCode = 413; return; }
        var code = Encoding.ASCII.GetString(data);
        if (code.Length is < 4 or > 8 || !code.All(char.IsAsciiDigit))
        {
            ctx.Response.StatusCode = 400; return;
        }
        lock (gate)
        {
            lastCode = code;
            codeExpiry = DateTimeOffset.UtcNow.AddMinutes(2);
        }
        ui.ReceivedCode(code);
        await ctx.Response.WriteAsync("OK");
    }

    /// <summary>Refresh focus state from the local, user-visible Windows UI.</summary>
    public void ObserveTextFocus(string? focusTag)
    {
        lock (gate)
        {
            if (!ui.RemoteTypingEnabled) focusTag = null;
            if (focusTag != lastFocus)
            {
                lastFocus = focusTag;
                remoteSession = focusTag is null ? "" : Convert.ToHexString(RandomNumberGenerator.GetBytes(12));
                remoteLabel = "Windows text field";
            }
        }
    }

    private async Task GetPromptAsync(HttpContext ctx)
    {
        if (!Authorized(ctx)) { ctx.Response.StatusCode = 403; return; }
        bool active;
        string session;
        string label;
        lock (gate)
        {
            active = ui.RemoteTypingEnabled && lastFocus is not null &&
                     ui.FocusedFieldTag == lastFocus && remoteSession.Length == 24;
            session = active ? remoteSession : "";
            label = active ? remoteLabel : "";
        }
        ctx.Response.Headers.CacheControl = "no-store";
        await ctx.Response.WriteAsJsonAsync(new { active, session, label });
    }

    private async Task PostTypeAsync(HttpContext ctx)
    {
        if (!Authorized(ctx) || !ui.RemoteTypingEnabled) { ctx.Response.StatusCode = 403; return; }
        string expectedFocus;
        lock (gate)
        {
            if (lastFocus is null || remoteSession.Length != 24 ||
                ctx.Request.Headers["X-Aukkhor-Session"].ToString() != remoteSession)
            {
                ctx.Response.StatusCode = 409; return;
            }
            expectedFocus = lastFocus;
        }
        var data = await ReadBounded(ctx, 8192);
        if (data is null) { ctx.Response.StatusCode = 413; return; }
        try
        {
            var text = new UTF8Encoding(false, true).GetString(data);
            if (string.IsNullOrWhiteSpace(text) || text.Length > 2048 ||
                text.Contains('\0'))
            {
                ctx.Response.StatusCode = 400; return;
            }
            var accepted = await ui.TypeRemoteTextAsync(text, expectedFocus);
            if (!accepted) { ctx.Response.StatusCode = 409; return; }
            await ctx.Response.WriteAsync("OK");
        }
        catch (DecoderFallbackException) { ctx.Response.StatusCode = 400; }
    }

    public string? TakeCode(bool consume = false)
    {
        lock (gate)
        {
            if (lastCode is null || DateTimeOffset.UtcNow >= codeExpiry)
            {
                lastCode = null; return null;
            }
            var code = lastCode;
            if (consume) lastCode = null;
            return code;
        }
    }

    private static async Task<byte[]?> ReadBounded(HttpContext ctx, int limit)
    {
        using var buffer = new MemoryStream();
        var data = new byte[4096];
        int n;
        while ((n = await ctx.Request.Body.ReadAsync(data, ctx.RequestAborted)) > 0)
        {
            if (buffer.Length + n > limit) return null;
            buffer.Write(data, 0, n);
        }
        return buffer.ToArray();
    }

    public async ValueTask DisposeAsync()
    {
        if (app is not null) { await app.StopAsync(); await app.DisposeAsync(); app = null; }
        certificate.Dispose();
    }

    private static class TrustStore
    {
        private static readonly string Folder = Path.Combine(Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData), "Aukkhor");
        private static string PathFor(string filename)
        {
            Directory.CreateDirectory(Folder);
            return Path.Combine(Folder, filename);
        }
        private static byte[]? LoadProtected(string filename)
        {
            try { return ProtectedData.Unprotect(File.ReadAllBytes(PathFor(filename)), null, DataProtectionScope.CurrentUser); }
            catch (IOException) { return null; }
            catch (CryptographicException) { return null; }
        }
        private static void SaveProtected(string filename, byte[] data)
        {
            File.WriteAllBytes(PathFor(filename), ProtectedData.Protect(data, null, DataProtectionScope.CurrentUser));
        }
        internal static TrustData LoadOrCreate()
        {
            var raw = LoadProtected("trust.dat");
            try
            {
                var trust = raw is null ? null : JsonSerializer.Deserialize<TrustData>(raw);
                if (trust?.Id.Length == 32 && trust.Secret.Length == 64) return trust;
            }
            catch (JsonException) { }
            var fresh = new TrustData(Guid.NewGuid().ToString("N"), Convert.ToHexString(RandomNumberGenerator.GetBytes(32)));
            SaveProtected("trust.dat", JsonSerializer.SerializeToUtf8Bytes(fresh));
            return fresh;
        }
        internal static X509Certificate2 LoadOrCreateCertificate()
        {
            var raw = LoadProtected("https-cert.dat");
            if (raw is not null)
            {
                try { return X509CertificateLoader.LoadPkcs12(raw, ""); }
                catch (CryptographicException) { }
            }
            using var rsa = RSA.Create(3072);
            var req = new CertificateRequest("CN=Aukkhor Windows", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            req.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
            req.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
            req.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(req.PublicKey, false));
            using var cert = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(5));
            SaveProtected("https-cert.dat", cert.Export(X509ContentType.Pfx, ""));
            return X509CertificateLoader.LoadPkcs12(cert.Export(X509ContentType.Pfx, ""), "");
        }
    }
}

