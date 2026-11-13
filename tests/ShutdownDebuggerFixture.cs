using System;
using System.Runtime.InteropServices;
using System.Threading;
class ShutdownDebuggerFixture {
 [DllImport("kernel32.dll")] static extern IntPtr CreateThread(IntPtr a,uint b,IntPtr start,IntPtr arg,uint flags,out uint id);
 [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h,uint ms);
 [DllImport("kernel32.dll")] static extern void RaiseFailFastException(IntPtr record,IntPtr context,uint flags);
 static void Main(string[] args) { Thread.Sleep(10000);
 if(args.Length==1 && args[0]=="fastfail") {
  IntPtr record=Marshal.AllocHGlobal(80);
  for(int n=0;n<80;n+=4) Marshal.WriteInt32(record,n,0);
  Marshal.WriteInt32(record,0,unchecked((int)0xc0000409));
  Marshal.WriteInt32(record,4,1); Marshal.WriteInt32(record,16,1); Marshal.WriteInt32(record,20,7);
  RaiseFailFastException(record,IntPtr.Zero,0); return;
 }
 uint id; var t=CreateThread(IntPtr.Zero,0,IntPtr.Zero,IntPtr.Zero,0,out id); WaitForSingleObject(t,60000); }
}
