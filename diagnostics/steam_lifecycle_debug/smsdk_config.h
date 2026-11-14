#pragma once
#define SMEXT_CONF_NAME "Steam Lifecycle Debug"
#define SMEXT_CONF_DESCRIPTION "Read-only Steam context lifecycle diagnostics"
#define SMEXT_CONF_VERSION "0.1.0"
#define SMEXT_CONF_AUTHOR "lechuga"
#define SMEXT_CONF_URL "https://github.com/AoC-Gamers/Custom-Fakelag"
#define SMEXT_CONF_LOGTAG "STEAM_LIFECYCLE"
#define SMEXT_CONF_LICENSE "GPL"
#define SMEXT_CONF_DATESTRING __DATE__
#define SMEXT_CONF_METAMOD
#define SMEXT_ENABLE_PLAYERHELPERS
#define SMEXT_LINK(name) SDKExtension *g_pExtensionIface = name;
