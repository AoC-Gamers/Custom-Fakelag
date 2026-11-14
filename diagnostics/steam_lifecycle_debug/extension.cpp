#include "smsdk_ext.h"
#include "tier1/convar.h"
#include "WindowsProbe.h"
#include "TraceFile.h"
#include <chrono>
#include <ctime>
#include <cerrno>
#include <cstring>
#ifdef _WIN32
#include <direct.h>
#else
#include <sys/stat.h>
#endif

SH_DECL_HOOK6(IServerGameDLL, LevelInit, SH_NOATTRIB, 0, bool,
              const char*, const char*, const char*, const char*, bool, bool);
SH_DECL_HOOK0_void(IServerGameDLL, LevelShutdown, SH_NOATTRIB, 0);

extern ISmmAPI* g_SMAPI;
namespace {
void ModeChanged(IConVar*, const char*, float);
void Frame(bool);
ConVar debugMode("sm_steam_lifecycle_debug", "0", 0,
    "Steam lifecycle trace: 0=off, 1=lifecycle snapshots, 2=also sample changes at 10Hz (10s heartbeat).",
    true, 0.0f, true, 2.0f);
using Clock = std::chrono::steady_clock;
}

class SteamLifecycleDebug final : public SDKExtension,
    public IConCommandBaseAccessor, public IClientListener {
    SteamTrace::Probe m_Probe;
    SteamTrace::TraceFile m_File;
    SteamTrace::Snapshot m_Last;
    bool m_Loaded = false, m_Failed = false, m_HaveLast = false;
    int m_LastLan = -1;
    unsigned long m_Sequence = 0;
    Clock::time_point m_Start, m_Next, m_LastRecord;

    void Failure() {
        if (!m_Failed) g_pSM->LogError(myself, "[steam_lifecycle] Trace file unavailable; logging suspended until debug is re-enabled.");
        m_Failed = true; m_File.Close();
    }
    void Write(const char* message) {
        if (m_Failed) return;
        char line[1400];
        const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - m_Start).count();
        ke::SafeSprintf(line, sizeof(line), "unix=%lld elapsed_ms=%lld seq=%lu %s\n",
            static_cast<long long>(std::time(nullptr)), static_cast<long long>(elapsed), ++m_Sequence, message);
        if (!m_File.Write(line)) Failure();
    }
    void Observe(const char* event, bool force = true) {
        if (!m_Loaded || debugMode.GetInt() == 0 || m_Failed) return;
        const auto now = Clock::now();
        if (!force && now < m_Next) return;
        m_Next = now + std::chrono::milliseconds(100);
        const auto state = m_Probe.Sample();
        ConVar* lan = g_pCVar->FindVar("sv_lan");
        const int lanValue = lan ? lan->GetInt() : -1;
        if (!force && m_HaveLast && lanValue == m_LastLan && SteamTrace::Same(state, m_Last) &&
            now - m_LastRecord < std::chrono::seconds(10)) return;
        char line[1024];
        ke::SafeSprintf(line, sizeof(line), "event=%s sv_lan=%d context=%s identified=%d",
            event, lanValue, m_Probe.Status(), state.identified);
        Write(line);
        if (state.identified) {
            for (size_t i = 0; i < 2; ++i) {
                const auto& f = state.fields[i];
                const unsigned reads = (f.objectRead ? 1u : 0u) | (f.vtableRead ? 2u : 0u) | (f.methodRead ? 4u : 0u);
                ke::SafeSprintf(line, sizeof(line),
                    "event=context_field offset=%u object=0x%08x vtable=0x%08x method=0x%08x reads=%u vtable_in_steam=%d method_in_steam=%d method_executable=%d",
                    static_cast<unsigned>(4 + i * 4), f.object, f.vtable, f.method, reads,
                    f.vtableInSteam, f.methodInSteam, f.methodExecutable);
                Write(line);
            }
        }
        m_Last = state; m_LastLan = lanValue; m_HaveLast = true; m_LastRecord = now;
    }
    bool LevelInitPre(const char*, const char*, const char*, const char*, bool, bool) {
        Observe("level_init_pre"); RETURN_META_VALUE(MRES_IGNORED, true);
    }
    bool LevelInitPost(const char*, const char*, const char*, const char*, bool, bool) {
        Observe("level_init_post"); RETURN_META_VALUE(MRES_IGNORED, true);
    }
    void LevelShutdownPre() { Observe("level_shutdown_pre"); }
    void LevelShutdownPost() { Observe("level_shutdown_post"); }
    bool RegisterConCommandBase(ConCommandBase* command) override { return META_REGCVAR(command); }
public:
    void ChangeMode() {
        if (!m_Loaded) return;
        if (!debugMode.GetInt()) {
            if (!m_Failed) Write("event=disabled");
            m_File.Close(); m_Probe.Reset(); m_HaveLast = false;
            return;
        }
        m_Failed = false; m_HaveLast = false; m_Probe.Reset();
        char directory[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH];
        g_pSM->BuildPath(Path_SM, directory, sizeof(directory), "logs/steam_lifecycle_debug");
#ifdef _WIN32
        const int created = _mkdir(directory);
#else
        const int created = mkdir(directory, 0700);
#endif
        if (created && errno != EEXIST) { Failure(); return; }
        g_pSM->BuildPath(Path_SM, path, sizeof(path), "logs/steam_lifecycle_debug/trace.log");
        if (!m_File.Open(path)) { Failure(); return; }
        Write("event=enabled version=0.1.0 observation=read_only");
        Observe("mode_changed");
    }
    void OnFrame() { if (debugMode.GetInt() == 2) Observe("sample", false); }
    void OnClientConnected(int) override { Observe("client_connected"); }
    void OnClientDisconnecting(int) override { Observe("client_disconnecting"); }
    bool SDK_OnLoad(char* error, size_t maxlen, bool) override {
        if (std::strcmp(g_pSM->GetGameFolderName(), "left4dead2")) {
            ke::SafeSprintf(error, maxlen, "Steam Lifecycle Debug supports L4D2 only"); return false;
        }
        g_pCVar = static_cast<ICvar*>(g_SMAPI->VInterfaceMatch(g_SMAPI->GetEngineFactory(), CVAR_INTERFACE_VERSION));
        if (!g_pCVar) { ke::SafeSprintf(error, maxlen, "ICvar unavailable"); return false; }
        m_Start = Clock::now();
        ConVar_Register(0, this);
        debugMode.InstallChangeCallback(ModeChanged);
        SH_ADD_HOOK(IServerGameDLL, LevelInit, gamedll, SH_MEMBER(this, &SteamLifecycleDebug::LevelInitPre), false);
        SH_ADD_HOOK(IServerGameDLL, LevelInit, gamedll, SH_MEMBER(this, &SteamLifecycleDebug::LevelInitPost), true);
        SH_ADD_HOOK(IServerGameDLL, LevelShutdown, gamedll, SH_MEMBER(this, &SteamLifecycleDebug::LevelShutdownPre), false);
        SH_ADD_HOOK(IServerGameDLL, LevelShutdown, gamedll, SH_MEMBER(this, &SteamLifecycleDebug::LevelShutdownPost), true);
        playerhelpers->AddClientListener(this);
        g_pSM->AddGameFrameHook(Frame);
        m_Loaded = true;
        if (debugMode.GetInt()) ChangeMode();
        return true;
    }
    void SDK_OnUnload() override {
        Observe("extension_unload"); m_Loaded = false;
        g_pSM->RemoveGameFrameHook(Frame);
        playerhelpers->RemoveClientListener(this);
        SH_REMOVE_HOOK(IServerGameDLL, LevelInit, gamedll, SH_MEMBER(this, &SteamLifecycleDebug::LevelInitPre), false);
        SH_REMOVE_HOOK(IServerGameDLL, LevelInit, gamedll, SH_MEMBER(this, &SteamLifecycleDebug::LevelInitPost), true);
        SH_REMOVE_HOOK(IServerGameDLL, LevelShutdown, gamedll, SH_MEMBER(this, &SteamLifecycleDebug::LevelShutdownPre), false);
        SH_REMOVE_HOOK(IServerGameDLL, LevelShutdown, gamedll, SH_MEMBER(this, &SteamLifecycleDebug::LevelShutdownPost), true);
        debugMode.InstallChangeCallback(nullptr);
        ConVar_Unregister(); m_File.Close(); m_Probe.Reset();
    }
};

namespace {
SteamLifecycleDebug extension;
void ModeChanged(IConVar*, const char*, float) { extension.ChangeMode(); }
void Frame(bool) { extension.OnFrame(); }
}
SMEXT_LINK(&extension);
