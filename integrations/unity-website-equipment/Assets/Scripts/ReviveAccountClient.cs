using System;
using System.Collections;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

// Standalone account/inventory reader. No gameplay or database write authority.
public class ReviveAccountClient : MonoBehaviour
{
    [SerializeField] private string projectUrl = "https://oowlgmookinibahpeyxl.supabase.co";
    [SerializeField] private string publishableKey = "sb_publishable_4kasHoliFC1-GmUxGpb_Uw_PHK1Bg91";
    public string Status { get; private set; } = "Ready. Sign in with an email code.";
    public bool Busy { get; private set; }
    public string AccountId { get; private set; } = "";
    public string Username { get; private set; } = "";
    public int InventoryRevision { get; private set; }
    public ItemInstance[] Inventory { get; private set; } = new ItemInstance[0];
    [SerializeField] private bool rememberSignIn = true;
    public bool RememberSignIn => rememberSignIn;
    public string RememberStatus { get; private set; } = "";
    public bool IsServerProcess
    {
        get
        {
#if UNITY_SERVER
            return true;
#else
            return Array.IndexOf(Environment.GetCommandLineArgs(), "-server") >= 0;
#endif
        }
    }
    private string CredentialTarget
    {
        get
        {
            Uri endpoint;
            if (!Uri.TryCreate(projectUrl, UriKind.Absolute, out endpoint) || endpoint.Scheme != "https") return "";
#if UNITY_EDITOR
            return "TheRevive/" + endpoint.Host + "/editor";
#else
            return "TheRevive/" + endpoint.Host + "/player";
#endif
        }
    }
    private void Start()
    {
        if (IsServerProcess) { Status = "Server process: player sign-in is not needed."; return; }
        rememberSignIn = PlayerPrefs.GetInt(CredentialTarget + "/remember", rememberSignIn ? 1 : 0) == 1;
        if (rememberSignIn && ReviveWindowsSessionStore.Supported) RestoreRememberedSignIn();
    }
    public void SetRememberSignIn(bool value)
    {
        rememberSignIn = value;
        // Only a preference bit is stored here, never either session token.
        PlayerPrefs.SetInt(CredentialTarget + "/remember", value ? 1 : 0); PlayerPrefs.Save();
        if (!value) ForgetRememberedSession();
        else if (SignedIn) RememberSession();
    }
    private void RememberSession()
    {
        if (!rememberSignIn || IsServerProcess || string.IsNullOrEmpty(CredentialTarget) || string.IsNullOrEmpty(refreshToken)) return;
        string error;
        RememberStatus = ReviveWindowsSessionStore.TrySave(CredentialTarget, refreshToken, out error)
            ? "Sign-in remembered on this Windows account." : error;
    }
    private void ForgetRememberedSession()
    {
        if (string.IsNullOrEmpty(CredentialTarget)) return;
        string error;
        RememberStatus = ReviveWindowsSessionStore.TryDelete(CredentialTarget, out error) ? "Remembered sign-in removed." : error;
    }
    public void RestoreRememberedSignIn()
    {
        if (!Busy && !SignedIn && !IsServerProcess && rememberSignIn) StartCoroutine(RestoreSession());
    }
    private IEnumerator RestoreSession()
    {
        string savedToken, error;
        if (!ReviveWindowsSessionStore.TryLoad(CredentialTarget, out savedToken, out error))
        { RememberStatus = error; yield break; }
        Busy = true;
        RememberStatus = "Restoring remembered sign-in...";
        yield return Request("/auth/v1/token?grant_type=refresh_token", "POST", JsonUtility.ToJson(new RefreshRequest { refresh_token = savedToken }), false);
        savedToken = null;
        if (!requestSucceeded)
        {
            if (lastResponseCode == 400 || lastResponseCode == 401 || lastResponseCode == 403)
            { ForgetRememberedSession(); Status = "Remembered sign-in expired or was revoked. Sign in once with an email code."; }
            else RememberStatus = "Could not restore sign-in. Saved session kept; use Retry remembered sign-in when connected.";
            Busy = false; yield break;
        }
        Session session = null;
        try { session = JsonUtility.FromJson<Session>(responseBody); } catch { }
        Guid account;
        if (session == null || session.user == null || !Guid.TryParse(session.user.id, out account) || string.IsNullOrEmpty(session.access_token) || string.IsNullOrEmpty(session.refresh_token))
        { Status = "Remembered sign-in returned an invalid session. Try again or sign in with an email code."; Busy = false; yield break; }
        SetSession(session); AccountId = account.ToString();
        yield return ReadAccount();
        Busy = false;
    }
    public void SelectUnarmed() { SelectedLoadoutId = ""; }
    public string SelectedLoadoutId { get; private set; } = "";
    public void SelectLoadout(string id)
    {
        foreach (ItemInstance item in Inventory)
            if (item.id == id && item.location == "stash" && item.definition_id == "flux-rifle" && item.condition > 0)
            { SelectedLoadoutId = id; return; }
    }
    // These are owned account records, not client authority to spawn equipment.
    // The mission server still validates and reserves the selected rifle UUID.
    public ItemInstance EquippedItem(string position)
    {
        foreach (ItemInstance item in Inventory)
            if (item.inventory_position == position && (item.location == "stash" || item.location == "mission")) return item;
        return null;
    }
    public void UseSavedEquipment()
    {
        SelectedLoadoutId = "";
        ItemInstance primary = EquippedItem("primary");
        if (primary != null && primary.location == "stash" && primary.definition_id == "flux-rifle" && primary.condition > 0)
            SelectedLoadoutId = primary.id;
    }
    public bool SignedIn { get { return !string.IsNullOrEmpty(accessToken); } }
    private string accessToken = "";
    private string refreshToken = "";
    private long expiresAt;
    private bool requestSucceeded;
    private string responseBody;
    private long sessionGeneration;
    private long lastResponseCode;

    [Serializable] public class AccountUser { public string id; public string email; }
    [Serializable] public class Session { public string access_token; public string refresh_token; public int expires_in; public AccountUser user; }
    [Serializable] public class Profile { public string id; public string username; public string discriminator; }
    [Serializable] private class ProfileList { public Profile[] items; }
    [Serializable] public class Definition { public string name; public string category; public string description; }
    [Serializable] public class ItemInstance { public string id; public string owner_id; public string definition_id; public int condition; public string location; public string source; public string inventory_position; public Definition item_definitions; }
    [Serializable] private class InventoryList { public ItemInstance[] items; }
    [Serializable] private class EmailRequest { public string email; public bool create_user = true; }
    [Serializable] private class VerifyRequest { public string email; public string token; public string type = "email"; }
    [Serializable] private class RefreshRequest { public string refresh_token; }
    [Serializable] private class UsernameRequest { public string p_username; }
    [Serializable] private class ApiError { public string message; public string msg; public string error_description; public string code; }

    public void RequestCode(string email, bool createUser = true)
    {
        if (Busy) return;
        if (string.IsNullOrWhiteSpace(email)) { Status = "Enter your private email."; return; }
        StartCoroutine(SendCode(email.Trim(), createUser));
    }
    private IEnumerator SendCode(string email, bool createUser)
    {
        Busy = true;
        yield return Request("/auth/v1/otp", "POST", JsonUtility.ToJson(new EmailRequest { email = email, create_user = createUser }), false);
        if (requestSucceeded) Status = "Email requested. Enter the code from your inbox. If you received a link, update the Supabase email template.";
        Busy = false;
    }
    public void VerifyCode(string email, string code)
    {
        if (Busy) return;
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(code)) { Status = "Enter your email and its sign-in code."; return; }
        StartCoroutine(Verify(email.Trim(), code.Trim()));
    }
    private IEnumerator Verify(string email, string code)
    {
        Busy = true;
        yield return Request("/auth/v1/verify", "POST", JsonUtility.ToJson(new VerifyRequest { email = email, token = code }), false);
        if (requestSucceeded)
        {
            Session session = JsonUtility.FromJson<Session>(responseBody);
            if (session != null && !string.IsNullOrEmpty(session.access_token) && session.user != null)
            {
                SetSession(session); AccountId = session.user.id;
                yield return ReadAccount();
            }
            else Status = "The sign-in response did not contain a valid session.";
        }
        Busy = false;
    }
    private void SetSession(Session session)
    {
        accessToken = session.access_token; refreshToken = session.refresh_token;
        expiresAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds() + session.expires_in;
        RememberSession();
    }
    private IEnumerator EnsureSession()
    {
        requestSucceeded = false;
        if (!SignedIn) { Status = "Sign in first."; yield break; }
        if (expiresAt > DateTimeOffset.UtcNow.ToUnixTimeSeconds() + 60) { requestSucceeded = true; yield break; }
        yield return Request("/auth/v1/token?grant_type=refresh_token", "POST", JsonUtility.ToJson(new RefreshRequest { refresh_token = refreshToken }), false);
        if (!requestSucceeded)
        {
            if (lastResponseCode == 400 || lastResponseCode == 401 || lastResponseCode == 403)
            {
                ForgetRememberedSession(); accessToken = ""; refreshToken = ""; AccountId = ""; Username = "";
                Inventory = new ItemInstance[0]; SelectedLoadoutId = "";
                Status = "Session expired or was revoked. Sign in once with an email code.";
            }
            yield break;
        }
        Session session = null;
        try { session = JsonUtility.FromJson<Session>(responseBody); } catch { }
        if (session == null || string.IsNullOrEmpty(session.access_token) || string.IsNullOrEmpty(session.refresh_token)) { requestSucceeded = false; Status = "Session expired. Sign in again."; yield break; }
        SetSession(session);
    }
    // Called by the launcher; refreshes an expiring session before joining.
    // The refresh token never leaves this account client.
    public IEnumerator PrepareConnectionToken(Action<string> completed)
    {
        if (Busy) { completed(null); yield break; }
        Busy = true;
        long generation = sessionGeneration;
        yield return EnsureSession();
        bool ready = generation == sessionGeneration && requestSucceeded && SignedIn;
        Busy = false;
        completed(ready ? accessToken : null);
    }
    public void RefreshInventory() { if (!Busy) StartCoroutine(Refresh()); }
    private IEnumerator Refresh() { Busy = true; yield return ReadAccount(); Busy = false; }
    private IEnumerator ReadAccount()
    {
        yield return EnsureSession(); if (!requestSucceeded) yield break;
        string owner = UnityWebRequest.EscapeURL(AccountId);
        yield return Request("/rest/v1/profiles?select=*&id=eq." + owner, "GET", null, true);
        if (!requestSucceeded) yield break;
        ProfileList profiles = JsonUtility.FromJson<ProfileList>("{\"items\":" + responseBody + "}");
        Profile profile = profiles.items != null && profiles.items.Length > 0 ? profiles.items[0] : null;
        Username = profile == null ? "" : profile.username + (string.IsNullOrEmpty(profile.discriminator) ? "" : "#" + profile.discriminator);
        yield return Request("/rest/v1/item_instances?select=id,owner_id,definition_id,condition,location,source,inventory_position,item_definitions(name,category,description)&owner_id=eq." + owner, "GET", null, true);
        if (!requestSucceeded) yield break;
        InventoryList result = JsonUtility.FromJson<InventoryList>("{\"items\":" + responseBody + "}");
        Inventory = result.items ?? new ItemInstance[0]; InventoryRevision++;
        // Refresh is an explicit sync point with the website. Only the primary rifle
        // is implemented by the current mission server; other positions are readable.
        UseSavedEquipment();
        Status = string.IsNullOrEmpty(Username) ? "Signed in. Choose a public username on the website or below." : "Loaded " + Inventory.Length + " item(s) for " + Username + ". Compare their IDs with the website.";
    }
    public void RegisterUsername(string username)
    {
        if (Busy) return;
        if (string.IsNullOrWhiteSpace(username)) { Status = "Enter a public username."; return; }
        StartCoroutine(Register(username.Trim()));
    }
    private IEnumerator Register(string username)
    {
        Busy = true;
        yield return EnsureSession();
        if (requestSucceeded)
        {
            yield return Request("/rest/v1/rpc/register_profile", "POST", JsonUtility.ToJson(new UsernameRequest { p_username = username }), true);
            if (requestSucceeded) yield return ReadAccount();
        }
        Busy = false;
    }
    public void SignOut()
    {
        // Forget this local Windows credential too; other devices are unaffected.
        ForgetRememberedSession();
        if (RememberStatus != "Remembered sign-in removed.")
        {
            // If native deletion fails, don't silently restore the credential next launch.
            rememberSignIn = false;
            PlayerPrefs.SetInt(CredentialTarget + "/remember", 0); PlayerPrefs.Save();
        }
        sessionGeneration++; StopAllCoroutines(); Busy = false;
        accessToken = ""; refreshToken = ""; AccountId = ""; Username = "";
        Inventory = new ItemInstance[0]; SelectedLoadoutId = ""; Status = "Signed out locally.";
    }
    private IEnumerator Request(string path, string method, string body, bool authenticated)
    {
        long generation = sessionGeneration;
        requestSucceeded = false; lastResponseCode = 0; Status = "Connecting…";
        using (UnityWebRequest request = new UnityWebRequest(projectUrl.TrimEnd('/') + path, method))
        {
            request.downloadHandler = new DownloadHandlerBuffer(); request.timeout = 15;
            request.SetRequestHeader("apikey", publishableKey);
            if (authenticated) request.SetRequestHeader("Authorization", "Bearer " + accessToken);
            if (body != null) { request.uploadHandler = new UploadHandlerRaw(Encoding.UTF8.GetBytes(body)); request.SetRequestHeader("Content-Type", "application/json"); }
            yield return request.SendWebRequest();
            if (generation != sessionGeneration) yield break;
            lastResponseCode = request.responseCode;
            responseBody = request.downloadHandler.text;
            requestSucceeded = request.result == UnityWebRequest.Result.Success;
            if (!requestSucceeded)
            {
                ApiError error = null;
                try { error = JsonUtility.FromJson<ApiError>(responseBody); } catch { }
                if (error != null && (error.code == "PGRST205" || error.code == "PGRST202")) Status = "Database setup pending. Run 001_accounts_inventory.sql in Supabase.";
                else if (error != null && error.code == "23505") Status = "Registration conflicted. Check that 002_username_tags.sql was installed.";
                else Status = error != null ? (error.message ?? error.msg ?? error.error_description ?? "Request failed.") : "Connection failed. Check your internet connection.";
            }
        }
    }
    private void OnDestroy() { accessToken = ""; refreshToken = ""; }
}
