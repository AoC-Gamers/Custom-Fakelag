#pragma semicolon 1
#include <sourcemod>
public Plugin myinfo = {name="Shutdown FillServerInfo consumer", author="Investigation", description="Minimal equivalent Left4DHooks forward consumer", version="1"};
public Action L4D2_OnClientDisableAddons(const char[] steamId) { return Plugin_Continue; }
