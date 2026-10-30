using System.Net;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Win32;

namespace Aukkhor.Windows;

internal sealed class MainForm : Form, IAukkhorUi
{
    private const int HotkeyId = 0xB012;
    private const int WmHotkey = 0x0312;
    private const uint ModAlt = 0x1;
    private const uint ModControl = 0x2;
    private readonly AukkhorService service;
    private readonly ComboBox addresses = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 350 };
    private readonly Label pairing = new() { AutoSize = true, Font = new Font("Segoe UI", 18, FontStyle.Bold) };
    private readonly TextBox fingerprint = new() { Width = 500, ReadOnly = true };
    private readonly CheckBox share = new() { Text = "Allow iPhone to read Windows clipboard", AutoSize = true };
    private readonly CheckBox receive = new() { Text = "Allow iPhone to update Windows clipboard", AutoSize = true };
    private readonly CheckBox autoStart = new() { Text = "Start with Windows login", AutoSize = true };
    private readonly Label lastCode = new() { AutoSize = true, Text = "No active code" };
    private readonly Label status = new() { AutoSize = false, Height = 50, Width = 520, Text = "Choose a trusted private Wi-Fi or Ethernet network." };
    private readonly Button start = new() { Text = "Start Windows companion", AutoSize = true };
    private readonly NotifyIcon tray = new() { Icon = SystemIcons.Information, Visible = false, Text = "Aukkhor Windows" };
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 1000 };
    private readonly string settingsFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Aukkhor", "settings.json");
    private bool canShare;
    private bool canReceive;
    private string previousHost = "";
    private string pendingLog = "";
    private bool allowClose;

    private sealed record Settings(string Host, bool AllowRead, bool AllowWrite);
    internal sealed record AddressChoice(IPAddress Address, string Adapter)
    {
        public override string ToString() => $"{Address}  ·  {Adapter}";
    }

    public MainForm()
    {
        service = new AukkhorService(this);
        Text = "Aukkhor · Windows Companion";
        Width = 590; Height = 595;
        MinimumSize = new Size(570, 570);
        Font = new Font("Segoe UI", 10);
        FormBorderStyle = FormBorderStyle.Sizable;
        StartPosition = FormStartPosition.CenterScreen;
        var panel = new FlowLayoutPanel {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, AutoScroll = true,
            WrapContents = false, Padding = new Padding(18)
        };
        Controls.Add(panel);
        panel.Controls.Add(Header("Aukkhor Windows", 20));
        panel.Controls.Add(Header("Trusted LAN adapter", 10));
        panel.Controls.Add(addresses);
        var refresh = new Button { Text = "Refresh adapters", AutoSize = true };
        refresh.Click += (_, _) => RefreshAdapters();
        panel.Controls.Add(refresh);
        panel.Controls.Add(start);
        start.Click += async (_, _) => await StartReceiver();
        panel.Controls.Add(Header("Six-digit pairing code", 10));
        panel.Controls.Add(pairing);
        panel.Controls.Add(Header("SHA-256 certificate fingerprint (copy all 64 digits to iPhone)", 10));
        panel.Controls.Add(fingerprint);
        panel.Controls.Add(share);
        panel.Controls.Add(receive);
        share.CheckedChanged += (_, _) => { canShare = share.Checked; SaveSettings(); };
        receive.CheckedChanged += (_, _) => { canReceive = receive.Checked; SaveSettings(); };
        panel.Controls.Add(autoStart);
        autoStart.CheckedChanged += (_, _) => SetAutoStart(autoStart.Checked);
        panel.Controls.Add(Header("Latest code (expires after 2 minutes)", 10));
        panel.Controls.Add(lastCode);
        var copy = new Button { Text = "Copy code", AutoSize = true };
        copy.Click += (_, _) => CopyCode();
        panel.Controls.Add(copy);
        panel.Controls.Add(Header("Press Ctrl + Alt + B to type the current code into the focused field", 9));
        panel.Controls.Add(status);

        var trayMenu = new ContextMenuStrip();
        trayMenu.Items.Add("Show Aukkhor", null, (_, _) => ShowWindow());
        trayMenu.Items.Add("Exit", null, (_, _) => { allowClose = true; Close(); });
        tray.ContextMenuStrip = trayMenu;
        tray.DoubleClick += (_, _) => ShowWindow();
        Resize += (_, _) => { if (WindowState == FormWindowState.Minimized) Hide(); };
        FormClosing += (_, e) => {
            if (allowClose) return;
            e.Cancel = true;
            Hide();
        };
        FormClosed += async (_, _) => { tray.Visible = false; await service.DisposeAsync(); };
        timer.Tick += (_, _) => {
            if (service.Running) pairing.Text = service.PairCode;
            lastCode.Text = service.TakeCode() is string code ? $"Code ending in {code[^2..]} available" : "No active code";
        };
        timer.Start();
        fingerprint.Text = service.Fingerprint;
        RefreshAdapters();
        RestoreSettings();
        Shown += async (_, _) => {
            RegisterHotKey(Handle, HotkeyId, ModAlt | ModControl, (uint)Keys.B);
            if (!string.IsNullOrEmpty(previousHost)) await StartReceiver();
        };
        tray.Visible = true;
    }

    private static Label Header(string value, int size) => new() {
        AutoSize = true, Text = value, Font = new Font("Segoe UI", size, FontStyle.Bold)
    };

    private void ShowWindow() { Show(); WindowState = FormWindowState.Normal; Activate(); }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotkey && m.WParam.ToInt32() == HotkeyId)
        {
            var code = service.TakeCode(consume: true);
            if (code is not null) SendKeys.SendWait(code);
        }
        base.WndProc(ref m);
    }

    protected override void OnHandleDestroyed(EventArgs e)
    {
        UnregisterHotKey(Handle, HotkeyId);
        base.OnHandleDestroyed(e);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hwnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hwnd, int id);

    private void RefreshAdapters()
    {
        var selected = (addresses.SelectedItem as AddressChoice)?.Address.ToString() ?? previousHost;
        addresses.Items.Clear();
        foreach (var (address, name) in AukkhorService.Interfaces()) addresses.Items.Add(new AddressChoice(address, name));
        for (var i = 0; i < addresses.Items.Count; i++)
            if (((AddressChoice)addresses.Items[i]!).Address.ToString() == selected) { addresses.SelectedIndex = i; break; }
        if (addresses.SelectedIndex < 0 && addresses.Items.Count > 0) addresses.SelectedIndex = 0;
    }

    private async Task StartReceiver()
    {
        if (service.Running) return;
        if (addresses.SelectedItem is not AddressChoice choice) { status.Text = "No usable private LAN adapter found."; return; }
        start.Enabled = false;
        try
        {
            await service.StartAsync(choice.Address);
            pairing.Text = service.PairCode;
            start.Text = "Running on " + choice.Address;
            addresses.Enabled = false;
            previousHost = choice.Address.ToString();
            SaveSettings();
        }
        catch (Exception ex) { status.Text = "Start failed: " + ex.Message; start.Enabled = true; }
    }

    private void CopyCode()
    {
        var code = service.TakeCode();
        if (code is null) { status.Text = "No active code to copy"; return; }
        Clipboard.SetText(code);
        status.Text = "Code copied to Windows clipboard";
    }

    public bool AllowClipboardRead => canShare;
    public bool AllowClipboardWrite => canReceive;

    private Task<T> OnUi<T>(Func<T> work)
    {
        if (!InvokeRequired) return Task.FromResult(work());
        var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        BeginInvoke(new Action(() => {
            try { tcs.SetResult(work()); }
            catch (Exception ex) { tcs.SetException(ex); }
        }));
        return tcs.Task;
    }

    public Task<string> ReadClipboardAsync() => OnUi(() => Clipboard.ContainsText() ? Clipboard.GetText() : "");
    public async Task SetClipboardAsync(string text) { await OnUi(() => { Clipboard.SetText(text); return true; }); }
    public void Report(string text) { pendingLog = text; if (!IsDisposed && IsHandleCreated) BeginInvoke(new Action(() => status.Text = pendingLog)); }
    public void ReceivedCode(string code)
    {
        if (IsDisposed || !IsHandleCreated) return;
        BeginInvoke(new Action(() => {
            lastCode.Text = $"Code ending in {code[^2..]} available";
            tray.BalloonTipTitle = "Aukkhor code received";
            tray.BalloonTipText = "New code ready. Press Ctrl + Alt + B in the destination field.";
            tray.ShowBalloonTip(4000);
        }));
    }

    private void RestoreSettings()
    {
        try
        {
            var cfg = JsonSerializer.Deserialize<Settings>(File.ReadAllText(settingsFile));
            if (cfg is not null) { previousHost = cfg.Host; share.Checked = cfg.AllowRead; receive.Checked = cfg.AllowWrite; }
        }
        catch (IOException) { }
        catch (JsonException) { }
        autoStart.Checked = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run")?.GetValue("Aukkhor") is not null;
        RefreshAdapters();
    }

    private void SaveSettings()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(settingsFile)!);
            File.WriteAllText(settingsFile, JsonSerializer.Serialize(new Settings(previousHost, canShare, canReceive)));
        }
        catch (IOException) { }
    }

    private static void SetAutoStart(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled) key?.SetValue("Aukkhor", $"\"{Application.ExecutablePath}\"");
        else key?.DeleteValue("Aukkhor", false);
    }
}

