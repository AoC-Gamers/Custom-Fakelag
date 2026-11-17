#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <custom_fakelag>

public Plugin myinfo = {name="Shutdown investigation consumer", author="Custom-Fakelag",
 description="Opt-in observation and real-human public API profiles", version="1.0"};
int Human() {
 for(int c=1;c<=MaxClients;c++) if(IsClientInGame(c)&&!IsFakeClient(c)) return c;
 return 0;
}
public void OnPluginStart() {
 RegServerCmd("cf_shutdown_profile", Profile);
 RegServerCmd("cf_shutdown_reset", Reset);
 RegServerCmd("cf_shutdown_state", State);
}
public Action Profile(int args) {
 int c=Human(); if(!c || args!=3) { LogMessage("[shutdown] profile refused: real human and lag/loss/mode required"); return Plugin_Handled; }
 char text[32]; GetCmdArg(1,text,sizeof(text)); float lag=StringToFloat(text);
 GetCmdArg(2,text,sizeof(text)); int loss=StringToInt(text);
 GetCmdArg(3,text,sizeof(text)); int mode=StringToInt(text);
 CFakeLag_SetPacketLossMode(view_as<CFakeLagPacketLossMode>(mode));
 CFakeLag_SetPlayerProfile(c,lag,loss);
 return State(0);
}
public Action Reset(int args) { CFakeLag_ResetState(); return State(0); }
public Action State(int args) {
 int c=Human(); CFakeLagNetworkProfile p;
 bool has=c && CFakeLag_GetPlayerProfile(c,p);
 LogMessage("[shutdown] human=%d fake=%d supported=%d profiles=%d has=%d lag=%f loss=%d mode=%d",
 c,c?IsFakeClient(c):false,c?CFakeLag_IsClientSupported(c):false,
 CFakeLag_GetProfiledClientCount(),has,p.lagMs,p.packetLossPercent,CFakeLag_GetPacketLossMode());
 return Plugin_Handled;
}
