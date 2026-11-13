#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <custom_fakelag>
int g_Client, g_Action, g_Changed, g_Checks, g_Failures, g_Stage;
bool g_ForwardError, g_ReentryRejected;
public Plugin myinfo = {name="Windows Public API Acceptance",author="Custom-Fakelag",description="Isolated acceptance with real human client",version="1.0"};
void Check(bool condition, const char[] name) {
 g_Checks++; if (!condition) g_Failures++;
 LogMessage("[windows_api] test=%s status=%s", name, condition ? "passed" : "FAILED");
}
int Human() { for(int i=1;i<=MaxClients;i++) if(IsClientInGame(i)&&!IsFakeClient(i)) return i; return 0; }
bool Profile(float lag,int loss) { CFakeLagNetworkProfile p;return CFakeLag_GetPlayerProfile(g_Client,p)&&FloatAbs(p.lagMs-lag)<0.01&&p.packetLossPercent==loss; }
public Action CFakeLag_OnSetPlayerLatency(int client,float oldLag,float &newLag,CFakeLagChangeReason reason) {
 if(g_ForwardError) ThrowError("EXPECTED windows API forward failure");
 if(g_Action==5){Call_StartFunction(GetMyHandle(),GetFunctionByName(GetMyHandle(),"Reenter"));g_ReentryRejected=Call_Finish()!=0;return Plugin_Continue;}
 if(g_Action==6)return view_as<Action>(-1);
 if(g_Action==1)return Plugin_Handled;
 if(g_Action==2)return Plugin_Stop;
 if(g_Action==3){newLag=75.0;return Plugin_Changed;}
 return Plugin_Continue;
}
public void CFakeLag_OnPlayerProfileChanged(int c,float o,int ol,float n,int nl,CFakeLagChangeReason r){g_Changed++;}
public void OnPluginStart(){
 RegServerCmd("cf_api_run",Run);
 RegServerCmd("cf_api_traffic",Traffic);
 RegServerCmd("cf_api_plugin",NormalPlugin);
 RegServerCmd("cf_api_arm_reconnect",Arm);
 RegServerCmd("cf_api_status",Status);
 LogMessage("[windows_api] ready=1");
}
public void OnClientPutInServer(int client){if(!IsFakeClient(client))LogMessage("[windows_api] real_client_connected slot=%d userid=%d profile=%d supported=%d",client,GetClientUserId(client),CFakeLag_HasPlayerProfile(client),CFakeLag_IsClientSupported(client));}
public void OnClientDisconnect(int client){if(!IsFakeClient(client)){LogMessage("[windows_api] real_client_disconnected slot=%d",client);CreateTimer(0.2,CleanupCheck);}}
public Action CleanupCheck(Handle timer){Check(CFakeLag_GetProfiledClientCount()==0,"disconnect-clears-profiles");Snapshot();return Plugin_Stop;}
public Action Run(int args){
 g_Client=Human();if(!g_Client){LogMessage("[windows_api] NEED_REAL_CLIENT");return Plugin_Handled;}
 g_Action=0;g_Checks=0;g_Failures=0;g_Changed=0;CFakeLag_ResetState();CFakeLag_SetPacketLossMode(CFakeLagPacketLoss_BernoulliUniform);
 Check(CFakeLag_IsClientSupported(g_Client),"human-eligible");
 Check(CFakeLag_GetProfiledClientCount()==0,"initial-reset");
 for(int action=1;action<=2;action++){
  g_Action=action;int before=g_Changed;CFakeLag_SetPlayerProfile(g_Client,50.0,10);
  Check(!CFakeLag_HasPlayerProfile(g_Client)&&before==g_Changed,action==1?"handled-new-no-error-no-success":"stop-new-no-error-no-success");
 }
 g_Action=0;CFakeLag_SetPlayerProfile(g_Client,50.0,10);Check(Profile(50.0,10),"apply-query-profile");
 for(int action=1;action<=2;action++){
  g_Action=action;int before=g_Changed;CFakeLag_SetPlayerProfile(g_Client,100.0,20);
  Check(Profile(50.0,10)&&before==g_Changed,action==1?"handled-existing-unchanged":"stop-existing-unchanged");
 }
 g_Action=0;int before=g_Changed;CFakeLag_SetPlayerProfile(g_Client,50.0,10);Check(before==g_Changed,"unchanged-no-success-forward");
 g_Action=3;CFakeLag_SetPlayerProfile(g_Client,100.0,20);Check(Profile(75.0,20),"forward-modification-applied");g_Action=0;
 g_ForwardError=true;Call_StartFunction(GetMyHandle(),GetFunctionByName(GetMyHandle(),"ForwardFailure"));int error=Call_Finish();g_ForwardError=false;
 Check(error!=0&&Profile(75.0,20),"forward-error-propagates-without-mutation");
 Call_StartFunction(GetMyHandle(),GetFunctionByName(GetMyHandle(),"InvalidInput"));error=Call_Finish();Check(error!=0&&Profile(75.0,20),"invalid-input-error-without-mutation");
 g_Action=6;Call_StartFunction(GetMyHandle(),GetFunctionByName(GetMyHandle(),"ForwardFailure"));error=Call_Finish();g_Action=0;
 Check(error!=0&&Profile(75.0,20),"invalid-forward-action-rejected");
 g_Action=5;g_ReentryRejected=false;CFakeLag_SetPlayerProfile(g_Client,80.0,20);g_Action=0;
 Check(g_ReentryRejected&&Profile(80.0,20),"reentrant-native-rejected-outer-transaction-coherent");
 CFakeLag_ClearPlayerProfile(g_Client);Check(!CFakeLag_HasPlayerProfile(g_Client),"clear-query");
 CFakeLag_SetPlayerProfile(g_Client,50.0,10);CFakeLag_SetPacketLossMode(CFakeLagPacketLoss_GilbertElliott);
 Check(CFakeLag_GetPacketLossMode()==CFakeLagPacketLoss_GilbertElliott&&CFakeLag_GetProfiledClientCount()==0,"native-mode-resets");
 CFakeLag_SetPlayerProfile(g_Client,50.0,10);FindConVar("sm_custom_fakelag_loss_mode").IntValue=0;
 Check(CFakeLag_GetPacketLossMode()==CFakeLagPacketLoss_BernoulliUniform&&CFakeLag_GetProfiledClientCount()==0,"convar-mode-resets");
 CFakeLag_ResetState();CFakeLag_ResetState();Check(CFakeLag_GetProfiledClientCount()==0,"reset-idempotent");
 LogMessage("[windows_api] API_DONE checks=%d failures=%d",g_Checks,g_Failures);return Plugin_Handled;
}
public void ForwardFailure(){CFakeLag_SetPlayerProfile(g_Client,100.0,10);}
public void InvalidInput(){CFakeLag_SetPlayerProfile(g_Client,-1.0,0);}
void Snapshot(){if(GetCommandFlags("cf_probe_status")!=-1){ServerCommand("cf_probe_status");ServerExecute();}}
public Action Traffic(int args){g_Client=Human();if(!g_Client)return Plugin_Handled;g_Action=0;g_Stage=0;CFakeLag_ResetState();CFakeLag_SetPacketLossMode(CFakeLagPacketLoss_BernoulliUniform);LogMessage("[windows_api] TRAFFIC_START baseline_incoming_avg=%f",GetClientAvgLatency(g_Client,NetFlow_Incoming));CFakeLag_SetPlayerProfile(g_Client,120.0,0);CreateTimer(3.0,TrafficStep);return Plugin_Handled;}
public Action TrafficStep(Handle timer){
 if(!g_Client||!IsClientInGame(g_Client)){CFakeLag_ResetState();LogMessage("[windows_api] TRAFFIC_ABORTED disconnected client");return Plugin_Stop;}
 Snapshot();LogMessage("[windows_api] traffic_stage=%d profile_count=%d incoming_avg=%f",g_Stage,CFakeLag_GetProfiledClientCount(),GetClientAvgLatency(g_Client,NetFlow_Incoming));
 if(g_Stage==0){CFakeLag_SetPlayerProfile(g_Client,120.0,50);g_Stage++;CreateTimer(3.0,TrafficStep);}
 else if(g_Stage==1){CFakeLag_SetPacketLossMode(CFakeLagPacketLoss_GilbertElliott);CFakeLag_SetPlayerProfile(g_Client,120.0,50);g_Stage++;CreateTimer(3.0,TrafficStep);}
 else if(g_Stage==2){CFakeLag_SetPlayerProfile(g_Client,0.0,100);g_Stage++;CreateTimer(1.0,TrafficStep);}
 else if(g_Stage==3){CFakeLag_SetPlayerProfile(g_Client,5000.0,0);g_Stage++;CreateTimer(0.4,TrafficStep);}
 else {CFakeLag_ResetState();Snapshot();Check(CFakeLag_GetProfiledClientCount()==0,"reset-under-real-pending-traffic");LogMessage("[windows_api] TRAFFIC_DONE");}
 return Plugin_Stop;
}
public Action Arm(int args){g_Client=Human();if(g_Client){g_Action=0;CFakeLag_SetPlayerProfile(g_Client,5000.0,0);LogMessage("[windows_api] reconnect_armed slot=%d userid=%d",g_Client,GetClientUserId(g_Client));}return Plugin_Handled;}
public Action Status(int args){int c=Human();LogMessage("[windows_api] human=%d count=%d has_profile=%d",c,CFakeLag_GetProfiledClientCount(),c?CFakeLag_HasPlayerProfile(c):false);Snapshot();return Plugin_Handled;}


public Action NormalPlugin(int args){
 g_Client=Human();if(!g_Client)return Plugin_Handled;g_Action=0;
 int flags=GetUserFlagBits(g_Client);SetUserFlagBits(g_Client,flags|ADMFLAG_ROOT);
 FakeClientCommand(g_Client,"sm_fakelag #%d 120",GetClientUserId(g_Client));
 CFakeLagNetworkProfile actual;bool has=CFakeLag_GetPlayerProfile(g_Client,actual);
 LogMessage("[windows_api] normal_profile lag=%f loss=%d",actual.lagMs,actual.packetLossPercent);
 Check(has&&FloatAbs(actual.lagMs-120.0)<0.01&&actual.packetLossPercent>=0&&actual.packetLossPercent<=FindConVar("sm_fakelag_loss_max_percent").IntValue,"normal-plugin-apply-query");
 FakeClientCommand(g_Client,"sm_fakelag_status");
 FakeClientCommand(g_Client,"sm_fakelag #%d 0",GetClientUserId(g_Client));
 Check(!CFakeLag_HasPlayerProfile(g_Client),"normal-plugin-clear-query");
 SetUserFlagBits(g_Client,flags);LogMessage("[windows_api] NORMAL_PLUGIN_DONE");return Plugin_Handled;
}

public void Reenter(){CFakeLag_SetPlayerProfile(g_Client,250.0,0);}
