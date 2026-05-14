#ifndef _INCLUDE_SOURCEMOD_EXTENSION_CONFIG_H_
#define _INCLUDE_SOURCEMOD_EXTENSION_CONFIG_H_

#define SMEXT_CONF_NAME			"Custom Fakelag"
#define SMEXT_CONF_DESCRIPTION	"Customize Fakelag implementation"
#define SMEXT_CONF_VERSION		"1.0.0.0"
#define SMEXT_CONF_AUTHOR		"ProdigySim"
#define SMEXT_CONF_URL			"http://www.github.com/ProdigySim/custom_fakelag"
#define SMEXT_CONF_LOGTAG		"CUSTOM_FAKELAG"
#define SMEXT_CONF_LICENSE		"GPL"
#define SMEXT_CONF_DATESTRING	__DATE__

#define SMEXT_LINK(name) SDKExtension *g_pExtensionIface = name;

#define SMEXT_CONF_METAMOD		

#define SMEXT_ENABLE_FORWARDSYS
#define SMEXT_ENABLE_PLAYERHELPERS
#define SMEXT_ENABLE_GAMECONF

#endif // _INCLUDE_SOURCEMOD_EXTENSION_CONFIG_H_
