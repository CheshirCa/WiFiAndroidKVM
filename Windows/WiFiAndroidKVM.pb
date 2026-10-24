; WiFi Android KVM, stages 3-5 (0.4.6). Build with /THREAD (PureBasic 6.41 x64).
; Current release version: 0.4.6.
; Copyright (C) CheshirCa 2026
; https://t.me/cheshircanest
;
; PB handles TCP, the queue, threads and UI. WinAPI provides global input,
; a global hotkey and cursor confinement, unavailable in PB Mouse/Window APIs.
EnableExplicit

CompilerIf #PB_Compiler_Thread = 0
  CompilerError "Build with /THREAD (thread-safe executable)."
CompilerEndIf
CompilerIf #PB_Compiler_Processor <> #PB_Processor_x64
  CompilerError "This client requires the PureBasic x64 compiler."
CompilerEndIf

Enumeration
  #Window_Main
  #Text_Status
  #Text_Diagnostics
  #Text_Device
  #Text_Host
  #Text_Port
  #List_Devices
  #Button_Find
  #String_Host
  #String_Port
  #Button_Toggle
  #Check_KeepAlive
  #String_KeepAliveInterval
  #Check_AutoReconnect
  #Text_Sensitivity
  #Track_Sensitivity
  #Button_ResetSensitivity
  #Button_Hide
  #Text_Language
  #Combo_Language
  #Check_AutoStart
  #Link_Copyright
  #Frame_Devices
  #Frame_Connection
  #Frame_Control
  #Frame_Mouse
  #Text_KeepAliveUnit
  #Window_CaptureNotice
  #Text_CaptureNotice
  #Text_ReturnShortcut
EndEnumeration

#Font_CaptureNotice = 0

Enumeration 100
  #Menu_ShowHide
  #Menu_Toggle
  #Menu_Exit
EndEnumeration

#Menu_LanguageFirst = 200

#Tray_Main = 0
#Menu_Tray = 0
#Image_TrayLocal = 0
#Image_TrayRemote = 1

#Event_SendFailed = #PB_Event_FirstCustomValue
#Event_ReconnectReady = #PB_Event_FirstCustomValue + 1
#Hotkey_Toggle = 1
#Agent_Host$ = "172.16.0.222"
#Agent_Port = 5556
#Discovery_Port = 5557
#Discovery_Request$ = "WAKVM_DISCOVER_1"
#Discovery_Reply$ = "WAKVM_REPLY_1|"
#Message_Move = $01
#Message_Button = $02
#Message_Wheel = $03
#Message_Key = $04
#Message_Ping = $7E
#Message_Disconnect = $7F
#KvmInputSink = $00000100
#KvmRidInput = $10000003
#RawInputHeaderSize = 24 ; RAWINPUTHEADER in x64.
#WhKeyboardLl = 13 ; WH_KEYBOARD_LL is not exposed by all PB Windows includes.
#LlkfExtended = $01
#LlkfInjected = $10
#LlmhfInjected = $01
#KeyeventfKeyup = $0002
#VkShift = $10
#VkControl = $11
#VkMenu = $12 ; VK_MENU is Alt.
#VkLShift = $A0
#VkRShift = $A1
#VkLControl = $A2
#VkRControl = $A3
#VkLMenu = $A4
#VkRMenu = $A5
#ScanCode_M = 50
#Registry_Run_Key$ = "Software\Microsoft\Windows\CurrentVersion\Run"
#Registry_Run_Value$ = "WiFiAndroidKVM"
#Project_Link$ = "https://t.me/cheshircanest"
#HKEY_CURRENT_USER = $80000001
#KEY_QUERY_VALUE = $0001
#KEY_SET_VALUE = $0002
#REG_SZ = 1

Structure KvmRawInputDevice
  UsagePage.w
  Usage.w
  Flags.l
  WindowHandle.i
EndStructure

Structure KvmMouseHookData
  Position.POINT
  MouseData.l
  Flags.l
  Time.l
  ExtraInfo.i
EndStructure

Structure KvmKeyboardHookData
  VkCode.l
  ScanCode.l
  Flags.l
  Time.l
  ExtraInfo.i
EndStructure

Structure KvmPacket
  Type.a
  Value1.w
  Value2.w
  Button.a
EndStructure

Structure KvmSockAddrIn
  Family.w
  Port.w
  Address.l
  Zero.a[8]
EndStructure

Structure KvmIpAddressString
  Next.i
  Address.a[16]
  Mask.a[16]
  Context.l
EndStructure

Structure KvmAdapterInfo
  Next.i
  ComboIndex.l
  AdapterName.a[260]
  Description.a[132]
  HardwareLength.l
  HardwareAddress.a[8]
  Index.l
  Type.l
  DhcpEnabled.l
  CurrentIpAddress.i
  IpAddressList.KvmIpAddressString
  GatewayList.KvmIpAddressString
  DhcpServer.KvmIpAddressString
  HaveWins.l
  PrimaryWinsServer.KvmIpAddressString
  SecondaryWinsServer.KvmIpAddressString
  LeaseObtained.l
  LeaseExpires.l
EndStructure

Structure KvmFoundDevice
  Name.s
  Address.s
  Port.i
EndStructure

Structure KvmLanguage
  Code.s
  Name.s
EndStructure

Global Connection.i, RemoteActive.i, MouseHook.i, KeyboardHook.i, RawInputWindow.i
Global KeyboardCtrlDown.i, KeyboardAltDown.i
Global Dim KeyboardPressed.a(255)
; Keys which were swallowed during remote control must also have their final
; key-up swallowed after control returns to Windows.
Global Dim KeyboardSuppressUp.a(511)
Global SenderThread.i, StopSenderThread.i, Session.i
Global InputMutex.i = CreateMutex()
Global PendingMouseX.q, PendingMouseY.q, WheelRemainder.l
Global Dim RawInputBuffer.a(127) ; RAWINPUT mouse packets are fixed and small.
Global MouseSensitivity.i = 100, MouseRemainderX.q, MouseRemainderY.q
Global TrayReady.i, WindowHidden.i, Exiting.i
Global StartSilent.i, AutoStartEnabled.i, Language$ = "en"
Global RawMoveCount.q, SentMoveCount.q
Global CursorLocked.i, SavedClip.RECT, LockedClip.RECT
Global KeepAliveEnabled.i = #True, KeepAliveInterval.i = 50
Global AutoReconnectEnabled.i = #True, ReconnectDue.i, ReconnectThread.i, ReconnectGeneration.i, ReconnectInProgress.i, ManualConnectPending.i
Global AgentHost$ = #Agent_Host$, AgentPort.i = #Agent_Port
Global DiscoverySocket.i = -1, DiscoveryDeadline.i
Global WsaStarted.i
Global DiscoveryStarting.i, DiscoveryComplete.i, DiscoveryError$
Global DiscoveryThread.i, StopDiscovery.i
Global NewList FoundDevices.KvmFoundDevice()
Global NewList PendingFoundDevices.KvmFoundDevice()
Global NewList Outgoing.KvmPacket()
Global NewMap LocaleText.s()
Global NewList Languages.KvmLanguage()

Declare UpdateStatus()
Declare ReconnectThread(CurrentGeneration.i)

; English is built in. WiFiAndroidKVM.lng supplies optional named language
; sections. Empty or absent values always fall back to the English text below.
Procedure.s Text(Key$)
  Protected Default$
  Select Key$
    Case "TitleMain" : Default$ = "WiFi Android KVM — 0.4.6"
    Case "TitleNotice" : Default$ = "WiFi Android KVM — tablet control"
    Case "StatusLocal" : Default$ = "Windows control. Ctrl+Alt+M sends mouse and keyboard to the tablet."
    Case "StatusRemote" : Default$ = "Tablet control. Ctrl+Alt+M returns mouse and keyboard to Windows."
    Case "Devices" : Default$ = "Discovered devices:"
    Case "SectionDevices" : Default$ = "Devices"
    Case "SectionConnection" : Default$ = "Connection"
    Case "SectionControl" : Default$ = "Control"
    Case "SectionMouse" : Default$ = "Mouse sensitivity"
    Case "Device" : Default$ = "Device"
    Case "Address" : Default$ = "IP address"
    Case "Find" : Default$ = "Find devices"
    Case "Host" : Default$ = "IP/DNS:"
    Case "KeepAlive" : Default$ = "KeepAlive"
    Case "AutoReconnect" : Default$ = "Auto reconnect"
    Case "Sensitivity" : Default$ = "Mouse sensitivity: "
    Case "SensitivityTip" : Default$ = "25–300%; 100% is the original speed. Android mouse movement only."
    Case "Diagnostics" : Default$ = "Mouse events:"
    Case "PacketsSent" : Default$ = "Movement packets:"
    Case "Hide" : Default$ = "Hide to tray"
    Case "Show" : Default$ = "Show window"
    Case "EnableRemote" : Default$ = "Enable tablet control"
    Case "DisableRemote" : Default$ = "Disable tablet control"
    Case "CancelReconnect" : Default$ = "Cancel reconnect"
    Case "Exit" : Default$ = "Exit"
    Case "Language" : Default$ = "Language:"
    Case "AutoStart" : Default$ = "Start with Windows"
    Case "NoticeTitle" : Default$ = "Mouse and keyboard are captured"
    Case "NoticeReturn" : Default$ = "Return Windows control: Ctrl+Alt+M"
    Case "TrayLocal" : Default$ = "WiFi Android KVM: Windows; Ctrl+Alt+M enables tablet control"
    Case "TrayRemote" : Default$ = "WiFi Android KVM: tablet; Ctrl+Alt+M returns control"
    Case "Searching" : Default$ = "Searching for devices on the local network…"
    Case "DiscoverySocketFailed" : Default$ = "Could not open a UDP connection for discovery."
    Case "SearchFailed" : Default$ = "Could not start device discovery."
    Case "NoDevices" : Default$ = "No devices found. Use manual IP/DNS and TCP port."
    Case "SelectDevice" : Default$ = "Double-click to select."
    Case "ConnectionLost" : Default$ = "Connection lost. Windows control restored."
    Case "Connecting" : Default$ = "Connecting to "
    Case "ConnectionAvailable" : Default$ = "Tablet is reachable. Enable control when ready."
    Case "ReconnectWait" : Default$ = "Connection lost. Reconnecting in 2 seconds…"
    Case "ReconnectNow" : Default$ = "Reconnecting to "
    Case "InvalidAddress" : Default$ = "Enter a valid IP/DNS name and TCP port."
    Case "NoConnection" : Default$ = "No direct connection to "
    Case "CheckNetwork" : Default$ = "Check Wi-Fi and the running Android Agent."
    Case "AuthFailed" : Default$ = "The agent rejected direct-connection authentication."
    Case "CursorFailed" : Default$ = "Could not lock the Windows cursor."
    Case "SenderFailed" : Default$ = "Could not create the sender thread."
    Case "ConfigureFailed" : Default$ = "Could not configure the TCP connection."
    Case "TrayFailed" : Default$ = "Could not add a tray icon. The window remains available; closing it exits the application."
    Case "NoticeFailed" : Default$ = "Could not create the input-capture notice."
    Case "HookFailed" : Default$ = "Could not register the hotkey or global mouse/keyboard input." + #CRLF$ + "Close another instance and try again."
    Case "AutoStartFailed" : Default$ = "Could not update Windows startup."
  EndSelect
  If FindMapElement(LocaleText(), Key$)
    ProcedureReturn LocaleText()
  EndIf
  ProcedureReturn Default$
EndProcedure

Procedure.i LanguageIndex(Code$)
  Protected Index.i
  ForEach Languages()
    If Languages()\Code = LCase(Trim(Code$)) : ProcedureReturn Index : EndIf
    Index + 1
  Next
  ProcedureReturn -1
EndProcedure

Procedure.s LanguageCodeAt(Index.i)
  Protected Current.i
  ForEach Languages()
    If Current = Index : ProcedureReturn Languages()\Code : EndIf
    Current + 1
  Next
  ProcedureReturn "en"
EndProcedure

Procedure AddLanguage(Code$, Name$)
  Protected Index.i = LanguageIndex(Code$)
  Code$ = LCase(Trim(Code$))
  Name$ = Trim(Name$)
  If Code$ = "" : ProcedureReturn : EndIf
  If Name$ = "" : Name$ = Code$ : EndIf
  If Index >= 0
    SelectElement(Languages(), Index)
    Languages()\Name = Name$
  Else
    AddElement(Languages())
    Languages()\Code = Code$
    Languages()\Name = Name$
  EndIf
EndProcedure

Procedure LoadLanguages()
  Protected File.i, File$, Line$, Equal.i, Key$, Value$, Section$, Name$
  ClearList(Languages())
  AddLanguage("en", "English")
  File$ = GetPathPart(ProgramFilename()) + "WiFiAndroidKVM.lng"
  File = ReadFile(#PB_Any, File$)
  If File = 0 : ProcedureReturn : EndIf
  While Eof(File) = #False
    Line$ = Trim(ReadString(File, #PB_UTF8))
    If Left(Line$, 1) = Chr($FEFF) : Line$ = Mid(Line$, 2) : EndIf
    If Left(Line$, 1) = "[" And Right(Line$, 1) = "]"
      If Section$ <> "" : AddLanguage(Section$, Name$) : EndIf
      Section$ = LCase(Trim(Mid(Line$, 2, Len(Line$) - 2)))
      Name$ = ""
    Else
      Equal = FindString(Line$, "=")
      If Equal > 1 And Left(Line$, 1) <> "#" And Left(Line$, 1) <> ";"
        Key$ = LCase(Trim(Left(Line$, Equal - 1)))
        Value$ = Trim(Mid(Line$, Equal + 1))
        If Key$ = "name" : Name$ = Value$ : EndIf
      EndIf
    EndIf
  Wend
  If Section$ <> "" : AddLanguage(Section$, Name$) : EndIf
  CloseFile(File)
EndProcedure

Procedure LoadLanguage()
  Protected File.i, Line$, Equal.i, Key$, Value$, File$, Section$, LanguageFound.i
  ClearMap(LocaleText())
  Language$ = LCase(Trim(Language$))
  If LanguageIndex(Language$) < 0 : Language$ = "en" : EndIf
  If Language$ = "en" : ProcedureReturn : EndIf
  File$ = GetPathPart(ProgramFilename()) + "WiFiAndroidKVM.lng"
  File = ReadFile(#PB_Any, File$)
  If File = 0 : Language$ = "en" : ProcedureReturn : EndIf
  While Eof(File) = #False
    Line$ = Trim(ReadString(File, #PB_UTF8))
    If Left(Line$, 1) = Chr($FEFF) : Line$ = Mid(Line$, 2) : EndIf
    If Left(Line$, 1) = "[" And Right(Line$, 1) = "]"
      Section$ = LCase(Trim(Mid(Line$, 2, Len(Line$) - 2)))
      If Section$ = Language$ : LanguageFound = #True : EndIf
    Else
      Equal = FindString(Line$, "=")
      If Section$ = Language$ And Equal > 1 And Left(Line$, 1) <> "#" And Left(Line$, 1) <> ";"
        Key$ = Trim(Left(Line$, Equal - 1))
        Value$ = Trim(Mid(Line$, Equal + 1))
        If Key$ <> "" And LCase(Key$) <> "name" And Value$ <> "" : LocaleText(Key$) = Value$ : EndIf
      EndIf
    EndIf
  Wend
  CloseFile(File)
  If LanguageFound = #False : Language$ = "en" : EndIf
EndProcedure

Procedure ParseCommandLine()
  Protected Index.i, Parameter$
  For Index = 0 To CountProgramParameters() - 1
    Parameter$ = LCase(Trim(ProgramParameter(Index)))
    If Parameter$ = "/silent" Or Parameter$ = "/s" : StartSilent = #True : EndIf
  Next
EndProcedure

Procedure.i ReadAutoStart()
  Protected Key.i, Value$ = Space(2048), ValueSize.l = 4096, Type.l
  If RegOpenKeyEx_(#HKEY_CURRENT_USER, #Registry_Run_Key$, 0, #KEY_QUERY_VALUE, @Key) <> 0
    ProcedureReturn #False
  EndIf
  If RegQueryValueEx_(Key, #Registry_Run_Value$, #Null, @Type, @Value$, @ValueSize) = 0 And Type = #REG_SZ And Trim(Value$) <> ""
    RegCloseKey_(Key)
    ProcedureReturn #True
  EndIf
  RegCloseKey_(Key)
  ProcedureReturn #False
EndProcedure

Procedure.i SetAutoStart(Enabled.i)
  Protected Key.i, Command$, Result.i
  If RegOpenKeyEx_(#HKEY_CURRENT_USER, #Registry_Run_Key$, 0, #KEY_SET_VALUE, @Key) <> 0
    ProcedureReturn #False
  EndIf
  If Enabled
    Command$ = Chr(34) + ProgramFilename() + Chr(34) + " /silent"
    Result = RegSetValueEx_(Key, #Registry_Run_Value$, 0, #REG_SZ, @Command$, (Len(Command$) + 1) * SizeOf(Character))
  Else
    Result = RegDeleteValue_(Key, #Registry_Run_Value$)
    If Result = 2 : Result = 0 : EndIf ; ERROR_FILE_NOT_FOUND is already disabled.
  EndIf
  RegCloseKey_(Key)
  ProcedureReturn Bool(Result = 0)
EndProcedure

Procedure OpenProjectLink()
  ; PureBasic has no standard browser-opening command, so use ShellExecute
  ; only for this HTTPS hyperlink.
  ShellExecute_(#Null, "open", #Project_Link$, #Null, #Null, 1)
EndProcedure

Procedure.i IPv4Number(Address$)
  Protected Field.i, Result.i, Value.i
  For Field = 1 To 4
    Value = Val(StringField(Address$, Field, "."))
    If Value < 0 Or Value > 255 : ProcedureReturn 0 : EndIf
    Result | Value << ((Field - 1) * 8)
  Next
  ProcedureReturn Result
EndProcedure

Procedure.s IPv4String(Address.i)
  ProcedureReturn Str(Address & $FF) + "." + Str((Address >> 8) & $FF) + "." + Str((Address >> 16) & $FF) + "." + Str((Address >> 24) & $FF)
EndProcedure

Procedure CloseDiscovery()
  If DiscoverySocket <> -1
    closesocket_(DiscoverySocket)
    DiscoverySocket = -1
  EndIf
EndProcedure

Procedure AddFoundDevice(Name$, Address$, Port.i)
  Protected Existing.i
  ForEach FoundDevices()
    If FoundDevices()\Address = Address$ And FoundDevices()\Port = Port : ProcedureReturn : EndIf
  Next
  AddElement(FoundDevices())
  FoundDevices()\Name = Name$
  FoundDevices()\Address = Address$
  FoundDevices()\Port = Port
  AddGadgetItem(#List_Devices, -1, Name$ + Chr(10) + Address$ + Chr(10) + Str(Port))
  Existing = CountGadgetItems(#List_Devices) - 1
  If Existing = 0 : SetGadgetState(#List_Devices, 0) : EndIf
EndProcedure

Procedure QueueFoundDevice(Name$, Address$, Port.i)
  LockMutex(InputMutex)
  ForEach PendingFoundDevices()
    If PendingFoundDevices()\Address = Address$ And PendingFoundDevices()\Port = Port
      UnlockMutex(InputMutex)
      ProcedureReturn
    EndIf
  Next
  AddElement(PendingFoundDevices())
  PendingFoundDevices()\Name = Name$
  PendingFoundDevices()\Address = Address$
  PendingFoundDevices()\Port = Port
  UnlockMutex(InputMutex)
EndProcedure

Procedure DrainFoundDevices()
  Protected NewList Batch.KvmFoundDevice()
  LockMutex(InputMutex)
  CopyList(PendingFoundDevices(), Batch())
  ClearList(PendingFoundDevices())
  UnlockMutex(InputMutex)
  ForEach Batch()
    AddFoundDevice(Batch()\Name, Batch()\Address, Batch()\Port)
  Next
EndProcedure

Procedure ReadDiscoveryReplies(Connection.i)
  Protected Count.i
  Protected Dim Buffer.a(255)
  Protected Reply$, Name$, Address$, Port.i
  Repeat
    If NetworkClientEvent(Connection) <> #PB_NetworkEvent_Data : Break : EndIf
    Count = ReceiveNetworkData(Connection, @Buffer(0), ArraySize(Buffer()))
    If Count <= 0 : Break : EndIf
    Reply$ = PeekS(@Buffer(0), Count, #PB_Ascii)
    If Left(Reply$, Len(#Discovery_Reply$)) = #Discovery_Reply$
      Name$ = StringField(Reply$, 2, "|")
      Address$ = StringField(Reply$, 3, "|")
      Port = Val(StringField(Reply$, 4, "|"))
      If Name$ <> "" And IPv4Number(Address$) <> 0 And Port >= 1 And Port <= 65535 And StringField(Reply$, 5, "|") = "1"
        QueueFoundDevice(Name$, Address$, Port)
      EndIf
    EndIf
  ForEver
EndProcedure

Procedure SendDiscoveryThread(Ignored.i)
  Protected LocalAddress.i, Broadcast.i, Address$, RequestLength.i, SocketResult.i
  Protected Connection.i
  Protected NewList Connections.i()
  DiscoveryError$ = ""
  ; PureBasic enumerates active IPv4 addresses without walking mutable
  ; third-party adapter structures. Most LANs use /24; global broadcast is
  ; also attempted for networks with another mask or router configuration.
  If ExamineIPAddresses()
    Repeat
      LocalAddress = NextIPAddress()
      If LocalAddress <> 0
        Address$ = IPString(LocalAddress)
        If Left(Address$, 4) <> "127."
          Broadcast = (LocalAddress & $00FFFFFF) | $FF000000
          Connection = OpenNetworkConnection(IPString(Broadcast), #Discovery_Port, #PB_Network_UDP)
          If Connection
            SendNetworkString(Connection, #Discovery_Request$, #PB_Ascii)
            AddElement(Connections()) : Connections() = Connection
          EndIf
        EndIf
      EndIf
    Until LocalAddress = 0
  EndIf
  Connection = OpenNetworkConnection("255.255.255.255", #Discovery_Port, #PB_Network_UDP)
  If Connection
    SendNetworkString(Connection, #Discovery_Request$, #PB_Ascii)
    AddElement(Connections()) : Connections() = Connection
  EndIf
  If ListSize(Connections()) = 0
    DiscoveryError$ = Text("DiscoverySocketFailed")
  EndIf
  DiscoveryDeadline = ElapsedMilliseconds() + 2000
  While StopDiscovery = #False And ElapsedMilliseconds() < DiscoveryDeadline
    ForEach Connections()
      ReadDiscoveryReplies(Connections())
    Next
    Delay(10)
  Wend
  ForEach Connections()
    CloseNetworkConnection(Connections())
  Next
  DiscoveryComplete = #True
  DiscoveryStarting = #False
EndProcedure

Procedure StartDiscovery()
  If DiscoveryStarting : ProcedureReturn : EndIf
  ClearList(FoundDevices())
  LockMutex(InputMutex)
  ClearList(PendingFoundDevices())
  UnlockMutex(InputMutex)
  ClearGadgetItems(#List_Devices)
  DiscoveryError$ = ""
  DiscoveryComplete = #False
  DiscoveryStarting = #True
  SetGadgetText(#Text_Device, Text("Searching"))
  DiscoveryThread = CreateThread(@SendDiscoveryThread(), 0)
  If DiscoveryThread = 0
    DiscoveryStarting = #False
    SetGadgetText(#Text_Device, Text("SearchFailed"))
  EndIf
EndProcedure

Procedure LoadConnectionSettings()
  Protected File$ = GetPathPart(ProgramFilename()) + "WiFiAndroidKVM.ini"
  If OpenPreferences(File$)
    PreferenceGroup("Connection")
    AgentHost$ = ReadPreferenceString("Host", #Agent_Host$)
    AgentPort = ReadPreferenceLong("Port", #Agent_Port)
    PreferenceGroup("Input")
    MouseSensitivity = ReadPreferenceLong("MouseSensitivityPercent", 100)
    PreferenceGroup("Options")
    KeepAliveEnabled = Bool(ReadPreferenceLong("KeepAliveEnabled", #True))
    KeepAliveInterval = ReadPreferenceLong("KeepAliveInterval", 50)
    AutoReconnectEnabled = Bool(ReadPreferenceLong("AutoReconnectEnabled", #True))
    Language$ = ReadPreferenceString("Language", "en")
    ClosePreferences()
  EndIf
  If AgentPort < 1 Or AgentPort > 65535 : AgentPort = #Agent_Port : EndIf
  If MouseSensitivity < 25 Or MouseSensitivity > 300 : MouseSensitivity = 100 : EndIf
  If KeepAliveInterval < 10 Or KeepAliveInterval > 1000 : KeepAliveInterval = 50 : EndIf
  LoadLanguages()
  LoadLanguage()
  AutoStartEnabled = ReadAutoStart()
EndProcedure

Procedure SaveConnectionSettings()
  Protected File$ = GetPathPart(ProgramFilename()) + "WiFiAndroidKVM.ini"
  If CreatePreferences(File$)
    PreferenceGroup("Connection")
    WritePreferenceString("Host", AgentHost$)
    WritePreferenceLong("Port", AgentPort)
    PreferenceGroup("Input")
    WritePreferenceLong("MouseSensitivityPercent", MouseSensitivity)
    PreferenceGroup("Options")
    WritePreferenceLong("KeepAliveEnabled", KeepAliveEnabled)
    WritePreferenceLong("KeepAliveInterval", KeepAliveInterval)
    WritePreferenceLong("AutoReconnectEnabled", AutoReconnectEnabled)
    WritePreferenceString("Language", Language$)
    ClosePreferences()
  EndIf
EndProcedure

Procedure.i ConfigureRawInput()
  Protected Device.KvmRawInputDevice
  Device\UsagePage = 1
  Device\Usage = 2
  ; Keep legacy movement: blocking it in WH_MOUSE_LL can stop Raw Input too.
  ; Cursor confinement stops the Windows pointer without suppressing movement.
  Device\Flags = #KvmInputSink
  Device\WindowHandle = RawInputWindow
  ProcedureReturn RegisterRawInputDevices_(@Device, 1, SizeOf(KvmRawInputDevice))
EndProcedure

Procedure.i LockWindowsCursor()
  Protected Cursor.POINT
  If GetCursorPos_(@Cursor) = 0 Or GetClipCursor_(@SavedClip) = 0
    ProcedureReturn #False
  EndIf
  LockedClip\left = Cursor\x
  LockedClip\top = Cursor\y
  LockedClip\right = Cursor\x + 1
  LockedClip\bottom = Cursor\y + 1
  ; ExamineMouse() is screen-local. ClipCursor is needed system-wide.
  CursorLocked = ClipCursor_(@LockedClip)
  ProcedureReturn CursorLocked
EndProcedure

Procedure UnlockWindowsCursor()
  If CursorLocked
    If ClipCursor_(@SavedClip) = 0
      ClipCursor_(#Null)
    EndIf
    CursorLocked = #False
  EndIf
EndProcedure

Procedure UpdateTrayState()
  Protected Index.i
  If TrayReady
    If WindowHidden
      SetMenuItemText(#Menu_Tray, #Menu_ShowHide, Text("Show"))
    Else
      SetMenuItemText(#Menu_Tray, #Menu_ShowHide, Text("Hide"))
    EndIf
    If RemoteActive
      ChangeSysTrayIcon(#Tray_Main, ImageID(#Image_TrayRemote))
      SysTrayIconToolTip(#Tray_Main, Text("TrayRemote"))
      SetMenuItemText(#Menu_Tray, #Menu_Toggle, Text("DisableRemote"))
    Else
      ChangeSysTrayIcon(#Tray_Main, ImageID(#Image_TrayLocal))
      SysTrayIconToolTip(#Tray_Main, Text("TrayLocal"))
      If ReconnectDue Or ReconnectInProgress
        SetMenuItemText(#Menu_Tray, #Menu_Toggle, Text("CancelReconnect"))
      Else
        SetMenuItemText(#Menu_Tray, #Menu_Toggle, Text("EnableRemote"))
      EndIf
    EndIf
    ForEach Languages()
      SetMenuItemText(#Menu_Tray, #Menu_LanguageFirst + Index, Languages()\Name)
      SetMenuItemState(#Menu_Tray, #Menu_LanguageFirst + Index, Bool(Language$ = Languages()\Code))
      Index + 1
    Next
  EndIf
EndProcedure

Procedure SetMainWindowHidden(Hidden.i)
  ; Keep the only accessible window visible if the tray could not be created.
  If Hidden And TrayReady = #False : ProcedureReturn : EndIf
  WindowHidden = Hidden
  HideWindow(#Window_Main, Hidden)
  If Hidden = #False : SetActiveWindow(#Window_Main) : EndIf
  UpdateTrayState()
EndProcedure

Procedure.i CreateTray()
  Protected Image.i, Color.i
  ; Native PB drawing embeds both tray images without external dependencies.
  For Image = #Image_TrayLocal To #Image_TrayRemote
    If CreateImage(Image, 16, 16, 32, #PB_Image_Transparent) = 0 : ProcedureReturn #False : EndIf
    If StartDrawing(ImageOutput(Image)) = 0 : ProcedureReturn #False : EndIf
    DrawingMode(#PB_2DDrawing_AllChannels)
    Color = RGBA(60, 110, 180, 255)
    If Image = #Image_TrayRemote : Color = RGBA(30, 160, 85, 255) : EndIf
    RoundBox(1, 1, 14, 12, 2, 2, Color)
    Box(3, 3, 10, 8, RGBA(240, 245, 255, 255))
    Box(7, 13, 2, 2, Color)
    Box(4, 15, 8, 1, Color)
    StopDrawing()
  Next
  If CreatePopupImageMenu(#Menu_Tray) = 0 : ProcedureReturn #False : EndIf
  MenuItem(#Menu_ShowHide, Text("Hide"))
  MenuItem(#Menu_Toggle, Text("EnableRemote"))
  OpenSubMenu(Text("Language"))
  ForEach Languages()
    MenuItem(#Menu_LanguageFirst + ListIndex(Languages()), Languages()\Name)
  Next
  CloseSubMenu()
  MenuBar()
  MenuItem(#Menu_Exit, Text("Exit"))
  If AddSysTrayIcon(#Tray_Main, WindowID(#Window_Main), ImageID(#Image_TrayLocal)) = 0 : ProcedureReturn #False : EndIf
  SysTrayIconMenu(#Tray_Main, MenuID(#Menu_Tray))
  TrayReady = #True
  UpdateTrayState()
  ProcedureReturn #True
EndProcedure

Procedure UpdateSensitivity()
  MouseSensitivity = GetGadgetState(#Track_Sensitivity)
  MouseRemainderX = 0
  MouseRemainderY = 0
  SetGadgetText(#Text_Sensitivity, Str(MouseSensitivity) + "%")
  SaveConnectionSettings()
EndProcedure

Procedure.q ScaleMouseDelta(RawDelta.l, *Remainder.Quad)
  Protected Scaled.q, Whole.q
  ; Signed hundredths preserve tiny moves at <100%, including reversals.
  Scaled = RawDelta
  Scaled * MouseSensitivity
  Scaled + *Remainder\q
  Whole = IntQ(Scaled / 100)
  *Remainder\q = Scaled - Whole * 100
  ProcedureReturn Whole
EndProcedure

Procedure.i CreateCaptureNotice()
  Protected X.i = #PB_Ignore, Y.i = #PB_Ignore
  If ExamineDesktops()
    X = DesktopX(0) + (DesktopWidth(0) - 560) / 2
    Y = DesktopY(0) + 24
  EndIf
  ; A separate, non-modal PB window stays visible even when the main window
  ; is hidden in the tray. No confirmation button can trap intercepted input.
  If OpenWindow(#Window_CaptureNotice, X, Y, 560, 96, Text("TitleNotice"),
                #PB_Window_BorderLess | #PB_Window_Tool | #PB_Window_Invisible | #PB_Window_NoActivate) = 0
    ProcedureReturn #False
  EndIf
  SetWindowColor(#Window_CaptureNotice, RGB(255, 243, 205))
  TextGadget(#Text_CaptureNotice, 16, 18, 528, 26, Text("NoticeTitle"), #PB_Text_Center)
  TextGadget(#Text_ReturnShortcut, 16, 54, 528, 26, Text("NoticeReturn"), #PB_Text_Center)
  If LoadFont(#Font_CaptureNotice, "Segoe UI", 12, #PB_Font_Bold)
    SetGadgetFont(#Text_CaptureNotice, FontID(#Font_CaptureNotice))
    SetGadgetFont(#Text_ReturnShortcut, FontID(#Font_CaptureNotice))
  EndIf
  SetGadgetColor(#Text_CaptureNotice, #PB_Gadget_BackColor, RGB(255, 243, 205))
  SetGadgetColor(#Text_ReturnShortcut, #PB_Gadget_BackColor, RGB(255, 243, 205))
  SetGadgetColor(#Text_CaptureNotice, #PB_Gadget_FrontColor, RGB(115, 55, 0))
  StickyWindow(#Window_CaptureNotice, #True)
  ProcedureReturn #True
EndProcedure

Procedure UpdateCaptureNotice()
  If IsWindow(#Window_CaptureNotice)
    HideWindow(#Window_CaptureNotice, Bool(RemoteActive = #False), #PB_Window_NoActivate)
  EndIf
EndProcedure

Procedure PopulateLanguageGadget()
  Protected Index.i
  ClearGadgetItems(#Combo_Language)
  ForEach Languages()
    AddGadgetItem(#Combo_Language, -1, Languages()\Name)
    If Languages()\Code = Language$ : SetGadgetState(#Combo_Language, Index) : EndIf
    Index + 1
  Next
EndProcedure

Procedure UpdateLanguageUI()
  If IsWindow(#Window_Main)
    SetWindowTitle(#Window_Main, Text("TitleMain"))
    SetGadgetText(#Frame_Devices, Text("SectionDevices"))
    SetGadgetText(#Frame_Connection, Text("SectionConnection"))
    SetGadgetText(#Frame_Control, Text("SectionControl"))
    SetGadgetText(#Frame_Mouse, Text("SectionMouse"))
    SetGadgetText(#Button_Find, Text("Find"))
    SetGadgetText(#Text_Host, Text("Host"))
    SetGadgetText(#Check_KeepAlive, Text("KeepAlive"))
    SetGadgetText(#Check_AutoReconnect, Text("AutoReconnect"))
    SetGadgetText(#Text_Sensitivity, Str(MouseSensitivity) + "%")
    GadgetToolTip(#Track_Sensitivity, Text("SensitivityTip"))
    SetGadgetText(#Button_Hide, Text("Hide"))
    SetGadgetText(#Text_Language, Text("Language"))
    SetGadgetText(#Check_AutoStart, Text("AutoStart"))
    SetGadgetItemText(#List_Devices, -1, Text("Device"), 0)
    SetGadgetItemText(#List_Devices, -1, Text("Address"), 1)
    PopulateLanguageGadget()
  EndIf
  If IsWindow(#Window_CaptureNotice)
    SetWindowTitle(#Window_CaptureNotice, Text("TitleNotice"))
    SetGadgetText(#Text_CaptureNotice, Text("NoticeTitle"))
    SetGadgetText(#Text_ReturnShortcut, Text("NoticeReturn"))
  EndIf
  If TrayReady
    SetMenuItemText(#Menu_Tray, #Menu_Exit, Text("Exit"))
  EndIf
  UpdateStatus()
EndProcedure

Procedure SetLanguage(NewLanguage$)
  Language$ = LCase(NewLanguage$)
  LoadLanguage()
  UpdateLanguageUI()
  SaveConnectionSettings()
EndProcedure

Procedure UpdateStatus()
  UpdateTrayState()
  UpdateCaptureNotice()
  If RemoteActive
    SetGadgetText(#Text_Status, Text("StatusRemote"))
    SetGadgetText(#Button_Toggle, Text("DisableRemote"))
  Else
    SetGadgetText(#Text_Status, Text("StatusLocal"))
    SetGadgetText(#Button_Toggle, Text("EnableRemote"))
  EndIf
EndProcedure

Procedure UpdateDiagnostics()
  Protected RawCount.q, SentCount.q
  LockMutex(InputMutex)
  RawCount = RawMoveCount
  SentCount = SentMoveCount
  UnlockMutex(InputMutex)
  SetGadgetText(#Text_Diagnostics, Text("Diagnostics") + " " + Str(RawCount) + "   " + Text("PacketsSent") + " " + Str(SentCount))
EndProcedure

Procedure.i ConfigureConnection(NetworkConnection.i)
  Protected Socket.i = ConnectionID(NetworkConnection)
  Protected NoDelay.l = 1, SendTimeout.l = 1000
  ; SendNetworkData has no TCP options. Disable Nagle for tiny input packets
  ; and bound a blocked send so switching back never waits indefinitely.
  If setsockopt_(Socket, 6, 1, @NoDelay, SizeOf(Long)) <> 0 ; IPPROTO_TCP, TCP_NODELAY
    ProcedureReturn #False
  EndIf
  ProcedureReturn Bool(setsockopt_(Socket, $FFFF, $1005, @SendTimeout, SizeOf(Long)) = 0) ; SOL_SOCKET, SO_SNDTIMEO
EndProcedure

Procedure.i SendAuthentication(NetworkConnection.i)
  Protected Dim Bytes.a(7), Offset.i, Sent.i
  Bytes(0) = $7D
  Bytes(1) = 75 : Bytes(2) = 86 : Bytes(3) = 77 : Bytes(4) = 50
  Bytes(5) = 48 : Bytes(6) = 50 : Bytes(7) = 54
  While Offset < 8
    Sent = SendNetworkData(NetworkConnection, @Bytes(0) + Offset, 8 - Offset)
    If Sent <= 0 : ProcedureReturn #False : EndIf
    Offset + Sent
  Wend
  ProcedureReturn #True
EndProcedure
Procedure.i SendPacket(*Packet.KvmPacket)
  Protected Dim Bytes.a(7)
  Protected Offset.i, Sent.i
  Bytes(0) = *Packet\Type
  Select *Packet\Type
    Case #Message_Move
      PokeW(@Bytes(1), *Packet\Value1)
      PokeW(@Bytes(3), *Packet\Value2)
    Case #Message_Button
      Bytes(1) = *Packet\Button
      Bytes(2) = *Packet\Value1
    Case #Message_Wheel
      PokeW(@Bytes(1), *Packet\Value1)
    Case #Message_Key
      PokeW(@Bytes(1), *Packet\Value1)
      Bytes(3) = *Packet\Value2
  EndSelect
  ; TCP may accept only part of a packet. Finish it before the next packet.
  While Offset < 8
    Sent = SendNetworkData(Connection, @Bytes(0) + Offset, 8 - Offset)
    If Sent <= 0
      ProcedureReturn #False
    EndIf
    Offset + Sent
  Wend
  ProcedureReturn #True
EndProcedure

; Caller holds InputMutex. Flush movement before buttons to preserve order.
Procedure AppendPendingMovement()
  Protected DeltaX.q, DeltaY.q
  While PendingMouseX <> 0 Or PendingMouseY <> 0
    DeltaX = PendingMouseX
    DeltaY = PendingMouseY
    If DeltaX > 32767 : DeltaX = 32767 : EndIf
    If DeltaX < -32768 : DeltaX = -32768 : EndIf
    If DeltaY > 32767 : DeltaY = 32767 : EndIf
    If DeltaY < -32768 : DeltaY = -32768 : EndIf
    AddElement(Outgoing())
    Outgoing()\Type = #Message_Move
    Outgoing()\Value1 = DeltaX
    Outgoing()\Value2 = DeltaY
    PendingMouseX - DeltaX
    PendingMouseY - DeltaY
  Wend
EndProcedure

Procedure QueueMouseControl(Type.a, Value.w, Button.a = 0)
  LockMutex(InputMutex)
  AppendPendingMovement()
  AddElement(Outgoing())
  Outgoing()\Type = Type
  Outgoing()\Value1 = Value
  Outgoing()\Value2 = 0
  Outgoing()\Button = Button
  UnlockMutex(InputMutex)
EndProcedure

Procedure ResetKeyboardPressed()
  Protected Key.i
  For Key = 0 To ArraySize(KeyboardPressed())
    KeyboardPressed(Key) = #False
  Next
EndProcedure

; Caller may be the UI thread. The sender thread drains this queue before it
; stops, so Android receives key-up for every key captured by the hook.
Procedure QueueAllKeyboardKeyUps()
  Protected Key.i
  LockMutex(InputMutex)
  For Key = 0 To ArraySize(KeyboardPressed())
    If KeyboardPressed(Key)
      AddElement(Outgoing())
      Outgoing()\Type = #Message_Key
      Outgoing()\Value1 = Key
      Outgoing()\Value2 = #False
      Outgoing()\Button = 0
      KeyboardPressed(Key) = #False
    EndIf
  Next
  UnlockMutex(InputMutex)
EndProcedure

Procedure QueueKeyboardKey(KeyCode.w, IsDown.w)
  ; Low-level hooks can receive Windows typematic keydown repeats. Android
  ; receives only state transitions, so one physical press has one down/up.
  If KeyCode < 0 Or KeyCode > ArraySize(KeyboardPressed())
    ProcedureReturn
  EndIf
  If IsDown
    If KeyboardPressed(KeyCode) : ProcedureReturn : EndIf
    KeyboardPressed(KeyCode) = #True
  Else
    If KeyboardPressed(KeyCode) = #False : ProcedureReturn : EndIf
    KeyboardPressed(KeyCode) = #False
  EndIf
  LockMutex(InputMutex)
  AddElement(Outgoing())
  Outgoing()\Type = #Message_Key
  Outgoing()\Value1 = KeyCode
  Outgoing()\Value2 = IsDown
  Outgoing()\Button = 0
  UnlockMutex(InputMutex)
EndProcedure

Procedure ReadRawMouse(InputHandle.i)
  Protected DataSize.l, ReadSize.l, *RawInput = @RawInputBuffer(0)
  Protected DeltaX.l, DeltaY.l
  If GetRawInputData_(InputHandle, #KvmRidInput, #Null, @DataSize, #RawInputHeaderSize) <> 0
    ProcedureReturn
  EndIf
  If DataSize < #RawInputHeaderSize + 24 Or DataSize > ArraySize(RawInputBuffer()) + 1
    ProcedureReturn
  EndIf
  ReadSize = GetRawInputData_(InputHandle, #KvmRidInput, *RawInput, @DataSize, #RawInputHeaderSize)
  ; Type 0 is mouse. Ignore absolute devices (this MVP uses a relative mouse).
  If ReadSize = DataSize And PeekL(*RawInput) = 0 And (PeekW(*RawInput + #RawInputHeaderSize) & 1) = 0
    DeltaX = PeekL(*RawInput + #RawInputHeaderSize + 12)
    DeltaY = PeekL(*RawInput + #RawInputHeaderSize + 16)
    If DeltaX <> 0 Or DeltaY <> 0
      LockMutex(InputMutex)
      PendingMouseX + ScaleMouseDelta(DeltaX, @MouseRemainderX)
      PendingMouseY + ScaleMouseDelta(DeltaY, @MouseRemainderY)
      RawMoveCount + 1
      UnlockMutex(InputMutex)
    EndIf
  EndIf
EndProcedure

Procedure MouseSenderThread(CurrentSession.i)
  Protected Stop.i, LastPing.i = ElapsedMilliseconds()
  Protected Ping.KvmPacket
  Protected NewList Batch.KvmPacket()
  Ping\Type = #Message_Ping
  Repeat
    LockMutex(InputMutex)
    Stop = StopSenderThread
    If Stop = #False
      AppendPendingMovement()
    EndIf
    ; On shutdown Outgoing() contains only the mandatory key releases queued
    ; by DisableRemoteControl(). Drain it before the sender exits.
    CopyList(Outgoing(), Batch())
    ClearList(Outgoing())
    UnlockMutex(InputMutex)

    ; Only this thread sends while remote mode is active. No UI calls here.
    ForEach Batch()
      If SendPacket(@Batch()) = #False
        PostEvent(#Event_SendFailed, #Window_Main, CurrentSession)
        ProcedureReturn
      EndIf
      If Batch()\Type = #Message_Move
        LockMutex(InputMutex)
        SentMoveCount + 1
        UnlockMutex(InputMutex)
      EndIf
    Next
    ClearList(Batch())
    If Stop : Break : EndIf
    If NetworkClientEvent(Connection) = #PB_NetworkEvent_Disconnect
      PostEvent(#Event_SendFailed, #Window_Main, CurrentSession)
      ProcedureReturn
    EndIf
    If KeepAliveEnabled And ElapsedMilliseconds() - LastPing >= KeepAliveInterval
      If SendPacket(@Ping) = #False
        PostEvent(#Event_SendFailed, #Window_Main, CurrentSession)
        ProcedureReturn
      EndIf
      LastPing = ElapsedMilliseconds()
    EndIf
    Delay(5)
  ForEver
EndProcedure

Procedure CancelReconnect()
  ReconnectGeneration + 1
  ReconnectDue = 0
  ManualConnectPending = #False
EndProcedure

Procedure ScheduleReconnect()
  If AutoReconnectEnabled
    ReconnectDue = ElapsedMilliseconds() + 2000
    UpdateTrayState()
    SetGadgetText(#Text_Status, Text("ReconnectWait"))
  EndIf
EndProcedure

Procedure.i ActivateRemoteControl(NewConnection.i)
  Connection = NewConnection
  If LockWindowsCursor() = #False
    CloseNetworkConnection(Connection)
    Connection = 0
    MessageRequester("WiFi Android KVM", Text("CursorFailed"), #PB_MessageRequester_Error)
    ProcedureReturn #False
  EndIf
  LockMutex(InputMutex)
  ClearList(Outgoing())
  PendingMouseX = 0
  PendingMouseY = 0
  MouseRemainderX = 0
  MouseRemainderY = 0
  RawMoveCount = 0
  SentMoveCount = 0
  StopSenderThread = #False
  UnlockMutex(InputMutex)
  Session + 1
  SenderThread = CreateThread(@MouseSenderThread(), Session)
  If SenderThread = 0
    UnlockWindowsCursor()
    CloseNetworkConnection(Connection)
    Connection = 0
    MessageRequester("WiFi Android KVM", Text("SenderFailed"), #PB_MessageRequester_Error)
    ProcedureReturn #False
  EndIf
  RemoteActive = #True
  KeyboardCtrlDown = #False
  KeyboardAltDown = #False
  ResetKeyboardPressed()
  SaveConnectionSettings()
  UpdateStatus()
  ProcedureReturn #True
EndProcedure

Procedure ReleaseWindowsModifiers()
  ; Windows did not receive the key-down events while the low-level hook was
  ; capturing input. Explicitly release both generic and side-specific modifier
  ; states before normal input resumes. This is harmless if a key was not down.
  keybd_event_(#VkShift, 0, #KeyeventfKeyup, 0)
  keybd_event_(#VkControl, 0, #KeyeventfKeyup, 0)
  keybd_event_(#VkMenu, 0, #KeyeventfKeyup, 0)
  keybd_event_(#VkLShift, 0, #KeyeventfKeyup, 0)
  keybd_event_(#VkRShift, 0, #KeyeventfKeyup, 0)
  keybd_event_(#VkLControl, 0, #KeyeventfKeyup, 0)
  keybd_event_(#VkRControl, 0, #KeyeventfKeyup, 0)
  keybd_event_(#VkLMenu, 0, #KeyeventfKeyup, 0)
  keybd_event_(#VkRMenu, 0, #KeyeventfKeyup, 0)
EndProcedure

Procedure DisableRemoteControl()
  Protected Disconnect.KvmPacket
  ; Release local control first, before waiting for the network thread.
  RemoteActive = #False
  ReleaseWindowsModifiers()
  UpdateCaptureNotice()
  KeyboardCtrlDown = #False
  KeyboardAltDown = #False
  QueueAllKeyboardKeyUps()
  UnlockWindowsCursor()
  WheelRemainder = 0
  LockMutex(InputMutex)
  StopSenderThread = #True
  UnlockMutex(InputMutex)
  If SenderThread
    WaitThread(SenderThread)
    SenderThread = 0
  EndIf
  If Connection > 0
    Disconnect\Type = #Message_Disconnect
    SendPacket(@Disconnect)
    CloseNetworkConnection(Connection)
    Connection = 0
  EndIf
  LockMutex(InputMutex)
  PendingMouseX = 0
  PendingMouseY = 0
  MouseRemainderX = 0
  MouseRemainderY = 0
  ClearList(Outgoing())
  UnlockMutex(InputMutex)
  UpdateStatus()
  UpdateDiagnostics()
EndProcedure

Procedure EnableRemoteControl()
  AgentHost$ = Trim(GetGadgetText(#String_Host))
  AgentPort = Val(GetGadgetText(#String_Port))
  If AgentHost$ = "" Or AgentPort < 1 Or AgentPort > 65535
    MessageRequester("WiFi Android KVM", Text("InvalidAddress"), #PB_MessageRequester_Warning)
    ProcedureReturn
  EndIf
  If ReconnectInProgress : ProcedureReturn : EndIf
  ManualConnectPending = #True
  ReconnectInProgress = #True
  ReconnectDue = 0
  ReconnectGeneration + 1
  ReconnectThread = CreateThread(@ReconnectThread(), ReconnectGeneration)
  If ReconnectThread = 0
    ReconnectInProgress = #False
    ManualConnectPending = #False
    MessageRequester("WiFi Android KVM", Text("SenderFailed"), #PB_MessageRequester_Error)
  Else
    SetGadgetText(#Text_Status, Text("Connecting") + AgentHost$ + ":" + Str(AgentPort) + "…")
  EndIf
EndProcedure

Procedure ReconnectThread(CurrentGeneration.i)
  Protected NewConnection.i
  ; This runs outside the UI thread: a missing tablet may take up to the
  ; TCP timeout, but it must never make the Windows window unresponsive.
  NewConnection = OpenNetworkConnection(AgentHost$, AgentPort, #PB_Network_TCP, 3000)
  If NewConnection And ConfigureConnection(NewConnection) And SendAuthentication(NewConnection)
    PostEvent(#Event_ReconnectReady, #Window_Main, CurrentGeneration, 0, NewConnection)
  Else
    If NewConnection : CloseNetworkConnection(NewConnection) : EndIf
    PostEvent(#Event_ReconnectReady, #Window_Main, CurrentGeneration, 0, 0)
  EndIf
EndProcedure

Procedure StartReconnect()
  If ReconnectInProgress Or AutoReconnectEnabled = #False Or AgentHost$ = "" Or AgentPort < 1 Or AgentPort > 65535
    ProcedureReturn
  EndIf
  ReconnectInProgress = #True
  UpdateTrayState()
  ReconnectDue = 0
  ReconnectGeneration + 1
  ReconnectThread = CreateThread(@ReconnectThread(), ReconnectGeneration)
  If ReconnectThread = 0
    ReconnectInProgress = #False
    ScheduleReconnect()
  Else
    SetGadgetText(#Text_Status, Text("ReconnectNow") + AgentHost$ + ":" + Str(AgentPort) + "…")
  EndIf
EndProcedure

Procedure ToggleRemoteControl()
  If RemoteActive
    CancelReconnect()
    DisableRemoteControl()
  ElseIf ReconnectDue Or ReconnectInProgress
    CancelReconnect()
    UpdateStatus()
  Else
    CancelReconnect()
    EnableRemoteControl()
  EndIf
EndProcedure

Procedure.i MouseHookCallback(Code.i, wParam.i, lParam.i)
  Protected *Mouse.KvmMouseHookData, WheelDelta.w, WheelSteps.l
  If Code >= 0 And RemoteActive
    *Mouse = lParam
    ; Do not consume our own synthetic releases when Windows restores state.
    If *Mouse\Flags & #LlmhfInjected
      ProcedureReturn CallNextHookEx_(MouseHook, Code, wParam, lParam)
    EndIf
    ; Do not block WM_MOUSEMOVE: Raw Input needs the physical movement.
    ; Buttons/wheel use the hook once, and are never sent from WM_INPUT.
    Select wParam
      Case #WM_LBUTTONDOWN : QueueMouseControl(#Message_Button, 1, 1) : ProcedureReturn 1
      Case #WM_LBUTTONUP   : QueueMouseControl(#Message_Button, 0, 1) : ProcedureReturn 1
      Case #WM_RBUTTONDOWN : QueueMouseControl(#Message_Button, 1, 2) : ProcedureReturn 1
      Case #WM_RBUTTONUP   : QueueMouseControl(#Message_Button, 0, 2) : ProcedureReturn 1
      Case #WM_MBUTTONDOWN : QueueMouseControl(#Message_Button, 1, 3) : ProcedureReturn 1
      Case #WM_MBUTTONUP   : QueueMouseControl(#Message_Button, 0, 3) : ProcedureReturn 1
      Case #WM_MOUSEWHEEL
        WheelDelta = (*Mouse\MouseData >> 16) & $FFFF
        ; High-resolution wheels may emit fractions of WHEEL_DELTA. Preserve
        ; the remainder instead of sending zero-value packets to Android.
        WheelRemainder + WheelDelta
        WheelSteps = WheelRemainder / 120
        WheelRemainder - WheelSteps * 120
        If WheelSteps <> 0 : QueueMouseControl(#Message_Wheel, WheelSteps) : EndIf
        ProcedureReturn 1
      Case #WM_XBUTTONDOWN, #WM_XBUTTONUP, #WM_MOUSEHWHEEL
        ; The protocol has no X-button/horizontal-wheel packet. Suppress these
        ; events rather than leaking them into Windows during tablet control.
        ProcedureReturn 1
    EndSelect
  EndIf
  ProcedureReturn CallNextHookEx_(MouseHook, Code, wParam, lParam)
EndProcedure

Procedure.w LinuxKeyFromScanCode(ScanCode.i, IsExtended.i)
  ; Windows set-1 scan codes match Linux evdev for the common keyboard keys.
  ; Extended keys use the Linux KEY_* values documented in docs/protocol.md.
  If IsExtended
    Select ScanCode
      Case 28 : ProcedureReturn 96  ; KEY_KPENTER
      Case 55 : ProcedureReturn 99  ; KEY_SYSRQ / Print Screen
      Case 29 : ProcedureReturn 97  ; KEY_RIGHTCTRL
      Case 53 : ProcedureReturn 98  ; KEY_KPSLASH
      Case 56 : ProcedureReturn 100 ; KEY_RIGHTALT
      Case 71 : ProcedureReturn 102 ; KEY_HOME
      Case 72 : ProcedureReturn 103 ; KEY_UP
      Case 73 : ProcedureReturn 104 ; KEY_PAGEUP
      Case 75 : ProcedureReturn 105 ; KEY_LEFT
      Case 77 : ProcedureReturn 106 ; KEY_RIGHT
      Case 79 : ProcedureReturn 107 ; KEY_END
      Case 80 : ProcedureReturn 108 ; KEY_DOWN
      Case 81 : ProcedureReturn 109 ; KEY_PAGEDOWN
      Case 82 : ProcedureReturn 110 ; KEY_INSERT
      Case 83 : ProcedureReturn 111 ; KEY_DELETE
      Case 91 : ProcedureReturn 125 ; KEY_LEFTMETA
      Case 92 : ProcedureReturn 126 ; KEY_RIGHTMETA
      Case 93 : ProcedureReturn 127 ; KEY_COMPOSE / Menu
    EndSelect
    ProcedureReturn 0
  EndIf
  If ScanCode >= 1 And ScanCode <= 88
    ProcedureReturn ScanCode
  EndIf
  ProcedureReturn 0
EndProcedure

Procedure.i KeyboardSuppressionIndex(*Keyboard.KvmKeyboardHookData)
  Protected Index.i = *Keyboard\ScanCode
  If *Keyboard\Flags & #LlkfExtended
    Index + 256
  EndIf
  If Index >= 0 And Index <= ArraySize(KeyboardSuppressUp())
    ProcedureReturn Index
  EndIf
  ProcedureReturn -1
EndProcedure

Procedure.i KeyboardHookCallback(Code.i, wParam.i, lParam.i)
  Protected *Keyboard.KvmKeyboardHookData, KeyCode.w, IsDown.i, IsExtended.i, SuppressIndex.i
  If Code >= 0
    *Keyboard = lParam
    SuppressIndex = KeyboardSuppressionIndex(*Keyboard)
    If wParam = #WM_KEYDOWN Or wParam = #WM_SYSKEYDOWN
      IsDown = 1
    Else
      IsDown = 0
    EndIf
    ; Ctrl+Alt+M changes RemoteActive asynchronously. Do not allow Windows to
    ; receive key-up for a key whose key-down was consumed by this hook.
    If RemoteActive = #False
      If IsDown = #False And SuppressIndex >= 0
        If KeyboardSuppressUp(SuppressIndex)
          KeyboardSuppressUp(SuppressIndex) = #False
          ProcedureReturn 1
        EndIf
      EndIf
      ProcedureReturn CallNextHookEx_(KeyboardHook, Code, wParam, lParam)
    EndIf
    ; Injected events are created locally while Windows state is restored and
    ; must never be forwarded to Android or swallowed by this hook.
    If *Keyboard\Flags & #LlkfInjected
      ProcedureReturn CallNextHookEx_(KeyboardHook, Code, wParam, lParam)
    EndIf
    IsExtended = Bool(*Keyboard\Flags & #LlkfExtended)
    ; Keep the modifier state from the same physical hook. GetAsyncKeyState()
    ; is not reliable inside a low-level callback because Windows updates it
    ; only after the callback returns.
    If *Keyboard\ScanCode = 29
      KeyboardCtrlDown = IsDown
    ElseIf *Keyboard\ScanCode = 56
      KeyboardAltDown = IsDown
    EndIf
    ; Preserve Ctrl+Alt+M as the local exit command even though normal keys are
    ; intercepted while remote control is active.
    ; Use the physical scan code for M. VkCode depends on the active keyboard
    ; layout, while scan code 50 is the same key in Russian and Latin layouts.
    If IsDown And *Keyboard\ScanCode = #ScanCode_M And KeyboardCtrlDown And KeyboardAltDown
      If SuppressIndex >= 0 : KeyboardSuppressUp(SuppressIndex) = #True : EndIf
      QueueKeyboardKey(29, 0)
      QueueKeyboardKey(56, 0)
      PostMessage_(RawInputWindow, #WM_HOTKEY, #Hotkey_Toggle, 0)
      ProcedureReturn 1
    EndIf
    ; The numeric keypad Del key can use scan code 83 without LLKHF_EXTENDED.
    ; Windows distinguishes its Delete function through VK_DELETE; preserve it
    ; for RDP instead of turning it into Linux KEY_KPDOT.
    If *Keyboard\VkCode = 44
      KeyCode = 99 ; Linux KEY_SYSRQ / Print Screen
    ElseIf *Keyboard\VkCode = 93
      KeyCode = 127 ; Linux KEY_COMPOSE / Menu
    ElseIf *Keyboard\VkCode = 46
      KeyCode = 111 ; Linux KEY_DELETE
    ; Backspace is made explicit because it is layout-independent and must not
    ; be confused with an OEM key by a third-party Windows keyboard driver.
    ElseIf *Keyboard\VkCode = 8
      KeyCode = 14 ; Linux KEY_BACKSPACE
    Else
      KeyCode = LinuxKeyFromScanCode(*Keyboard\ScanCode, IsExtended)
    EndIf
    If KeyCode
      If SuppressIndex >= 0 : KeyboardSuppressUp(SuppressIndex) = IsDown : EndIf
      QueueKeyboardKey(KeyCode, IsDown)
      ProcedureReturn 1
    EndIf
    ; Remote control owns the entire physical keyboard. Unknown multimedia or
    ; OEM keys are intentionally ignored instead of reaching Windows.
    ProcedureReturn 1
  EndIf
  ProcedureReturn CallNextHookEx_(KeyboardHook, Code, wParam, lParam)
EndProcedure

Procedure.i WindowCallback(WindowHandle.i, Message.i, wParam.i, lParam.i)
  If Message = #WM_INPUT
    If RemoteActive : ReadRawMouse(lParam) : EndIf
    ; Foreground WM_INPUT requires DefWindowProc for system cleanup.
    ProcedureReturn DefWindowProc_(WindowHandle, Message, wParam, lParam)
  EndIf
  If Message = #WM_HOTKEY And wParam = #Hotkey_Toggle And Exiting = #False
    ToggleRemoteControl()
    ProcedureReturn 0
  EndIf
  ProcedureReturn #PB_ProcessPureBasicEvents
EndProcedure

If InputMutex = 0 : End : EndIf
ParseCommandLine()
LoadConnectionSettings()
If OpenWindow(#Window_Main, #PB_Ignore, #PB_Ignore, 560, 440, Text("TitleMain"), #PB_Window_SystemMenu | #PB_Window_ScreenCentered | #PB_Window_MinimizeGadget)
  Define Quit.i, HotkeyRegistered.i
  ; Redesigned compact layout based on kvm_gui.pb. All existing input,
  ; discovery and tray gadgets remain; only their presentation changes.
  FrameGadget(#Frame_Devices, 12, 12, 536, 128, Text("SectionDevices"))
  ListIconGadget(#List_Devices, 24, 34, 376, 94, Text("Device"), 170, #PB_ListIcon_FullRowSelect | #PB_ListIcon_AlwaysShowSelection | #PB_ListIcon_GridLines)
  AddGadgetColumn(#List_Devices, 1, Text("Address"), 120)
  AddGadgetColumn(#List_Devices, 2, "TCP", 50)
  ButtonGadget(#Button_Find, 412, 34, 124, 28, Text("Find"))
  GadgetToolTip(#Button_Find, Text("Searching"))
  GadgetToolTip(#List_Devices, Text("SelectDevice"))

  FrameGadget(#Frame_Connection, 12, 148, 536, 60, Text("SectionConnection"))
  TextGadget(#Text_Host, 24, 176, 50, 20, Text("Host"))
  StringGadget(#String_Host, 78, 172, 150, 24, AgentHost$)
  TextGadget(#Text_Port, 244, 176, 30, 20, "TCP:")
  StringGadget(#String_Port, 276, 172, 56, 24, Str(AgentPort), #PB_String_Numeric)
  CheckBoxGadget(#Check_KeepAlive, 354, 174, 96, 22, Text("KeepAlive"))
  SetGadgetState(#Check_KeepAlive, KeepAliveEnabled)
  StringGadget(#String_KeepAliveInterval, 450, 172, 44, 24, Str(KeepAliveInterval), #PB_String_Numeric)
  TextGadget(#Text_KeepAliveUnit, 500, 176, 36, 20, "ms")

  FrameGadget(#Frame_Control, 12, 216, 536, 58, Text("SectionControl"))
  ButtonGadget(#Button_Toggle, 24, 236, 280, 30, "")
  CheckBoxGadget(#Check_AutoReconnect, 324, 242, 200, 22, Text("AutoReconnect"))
  SetGadgetState(#Check_AutoReconnect, AutoReconnectEnabled)

  FrameGadget(#Frame_Mouse, 12, 282, 536, 58, Text("SectionMouse"))
  TrackBarGadget(#Track_Sensitivity, 24, 304, 372, 28, 25, 300)
  SetGadgetState(#Track_Sensitivity, MouseSensitivity)
  GadgetToolTip(#Track_Sensitivity, Text("SensitivityTip"))
  TextGadget(#Text_Sensitivity, 408, 310, 44, 20, Str(MouseSensitivity) + "%", #PB_Text_Right)
  ButtonGadget(#Button_ResetSensitivity, 460, 304, 76, 26, "100%")

  CheckBoxGadget(#Check_AutoStart, 12, 354, 200, 22, Text("AutoStart"))
  SetGadgetState(#Check_AutoStart, AutoStartEnabled)
  TextGadget(#Text_Language, 214, 357, 64, 20, Text("Language"), #PB_Text_Right)
  ComboBoxGadget(#Combo_Language, 284, 353, 110, 24)
  PopulateLanguageGadget()
  ButtonGadget(#Button_Hide, 424, 350, 124, 28, Text("Hide"))
  TextGadget(#Text_Device, 412, 68, 124, 60, "")
  TextGadget(#Text_Diagnostics, 12, 388, 310, 18, "")
  HyperLinkGadget(#Link_Copyright, 328, 386, 220, 20, "Copyright (C) CheshirCa 2026", RGB(100, 100, 100), #PB_Text_Right)
  GadgetToolTip(#Link_Copyright, #Project_Link$)
  TextGadget(#Text_Status, 12, 412, 536, 18, "", #PB_Text_Center)
  If CreateTray() = #False
    DisableGadget(#Button_Hide, #True)
    MessageRequester("WiFi Android KVM", Text("TrayFailed"), #PB_MessageRequester_Warning)
  EndIf
  If CreateCaptureNotice() = #False
    MessageRequester("WiFi Android KVM", Text("NoticeFailed"), #PB_MessageRequester_Error)
    Quit = #True
  EndIf
  UpdateStatus()
  UpdateDiagnostics()
  RawInputWindow = WindowID(#Window_Main)
  SetWindowCallback(@WindowCallback(), #Window_Main)
  ; AddKeyboardShortcut() is window-local. $4000 is MOD_NOREPEAT.
  HotkeyRegistered = RegisterHotKey_(RawInputWindow, #Hotkey_Toggle, #MOD_CONTROL | #MOD_ALT | $4000, #VK_M)
  MouseHook = SetWindowsHookEx_(#WH_MOUSE_LL, @MouseHookCallback(), GetModuleHandle_(#Null), 0)
  KeyboardHook = SetWindowsHookEx_(#WhKeyboardLl, @KeyboardHookCallback(), GetModuleHandle_(#Null), 0)
  If HotkeyRegistered = 0 Or MouseHook = 0 Or KeyboardHook = 0 Or ConfigureRawInput() = 0
    MessageRequester("WiFi Android KVM", Text("HookFailed"), #PB_MessageRequester_Error)
    Quit = #True
  EndIf
  AddWindowTimer(#Window_Main, 1, 500)
  StartDiscovery()
  If StartSilent And TrayReady : SetMainWindowHidden(#True) : EndIf
  While Quit = #False
    Select WaitWindowEvent()
      Case #PB_Event_Menu
        Select EventMenu()
          Case #Menu_ShowHide
            SetMainWindowHidden(Bool(WindowHidden = #False))
          Case #Menu_Toggle
            ToggleRemoteControl()
          Case #Menu_Exit
            Quit = #True
          Default
            If EventMenu() >= #Menu_LanguageFirst And EventMenu() < #Menu_LanguageFirst + ListSize(Languages())
              SetLanguage(LanguageCodeAt(EventMenu() - #Menu_LanguageFirst))
            EndIf
        EndSelect
      Case #PB_Event_SysTray
        If EventType() = #PB_EventType_LeftDoubleClick
          SetMainWindowHidden(#False)
        EndIf
      Case #PB_Event_Gadget
        Select EventGadget()
          Case #Button_Toggle
            ToggleRemoteControl()
          Case #Button_Hide
            SetMainWindowHidden(#True)
          Case #Link_Copyright
            OpenProjectLink()
          Case #Combo_Language
            SetLanguage(LanguageCodeAt(GetGadgetState(#Combo_Language)))
          Case #Check_AutoStart
            If SetAutoStart(GetGadgetState(#Check_AutoStart))
              AutoStartEnabled = GetGadgetState(#Check_AutoStart)
            Else
              SetGadgetState(#Check_AutoStart, AutoStartEnabled)
              MessageRequester("WiFi Android KVM", Text("AutoStartFailed"), #PB_MessageRequester_Error)
            EndIf
          Case #Track_Sensitivity
            UpdateSensitivity()
          Case #Button_ResetSensitivity
            SetGadgetState(#Track_Sensitivity, 100)
            UpdateSensitivity()
          Case #Button_Find
            StartDiscovery()
          Case #List_Devices
            If EventType() = #PB_EventType_LeftDoubleClick
              Define SelectedDevice.i = GetGadgetState(#List_Devices)
              If SelectedDevice >= 0
                SelectElement(FoundDevices(), SelectedDevice)
                SetGadgetText(#String_Host, FoundDevices()\Address)
                SetGadgetText(#String_Port, Str(FoundDevices()\Port))
              EndIf
            EndIf
          Case #Check_KeepAlive
            KeepAliveEnabled = GetGadgetState(#Check_KeepAlive)
            SaveConnectionSettings()
          Case #Check_AutoReconnect
            AutoReconnectEnabled = GetGadgetState(#Check_AutoReconnect)
            If AutoReconnectEnabled = #False
              CancelReconnect()
              If RemoteActive = #False : UpdateStatus() : EndIf
            EndIf
            SaveConnectionSettings()
          Case #String_KeepAliveInterval
            KeepAliveInterval = Val(GetGadgetText(#String_KeepAliveInterval))
            If KeepAliveInterval < 10 Or KeepAliveInterval > 1000
              KeepAliveInterval = 50
              SetGadgetText(#String_KeepAliveInterval, "50")
            EndIf
            SaveConnectionSettings()
        EndSelect
      Case #Event_SendFailed
        ; Ignore notifications from an earlier, already stopped session.
        If RemoteActive And EventGadget() = Session
          DisableRemoteControl()
          ScheduleReconnect()
          If AutoReconnectEnabled = #False
            SetGadgetText(#Text_Status, Text("ConnectionLost"))
          EndIf
        EndIf
      Case #Event_ReconnectReady
        If ReconnectThread
          WaitThread(ReconnectThread)
          ReconnectThread = 0
        EndIf
        ReconnectInProgress = #False
        UpdateTrayState()
        If EventGadget() = ReconnectGeneration And RemoteActive = #False
          If ManualConnectPending
            ManualConnectPending = #False
            If EventData() > 0
              ActivateRemoteControl(EventData())
            Else
              MessageRequester("WiFi Android KVM", Text("NoConnection") + AgentHost$ + ":" + Str(AgentPort) + "." + #CRLF$ + Text("CheckNetwork"), #PB_MessageRequester_Warning)
            EndIf
          ElseIf EventData() > 0
            ; Reconnect only verifies reachability. Never steal the user's
            ; local mouse and keyboard after a transient Wi-Fi outage.
            CloseNetworkConnection(EventData())
            SetGadgetText(#Text_Status, Text("ConnectionAvailable"))
          Else
            ScheduleReconnect()
          EndIf
        ElseIf EventData() > 0
          CloseNetworkConnection(EventData())
        EndIf
      Case #PB_Event_Timer
        If RemoteActive And CursorLocked
          ; Win+L, UAC, and other applications may replace ClipCursor().
          ; Reapply the original one-pixel capture rectangle periodically.
          ClipCursor_(@LockedClip)
        EndIf
        UpdateDiagnostics()
        DrainFoundDevices()
        If ReconnectDue > 0 And ElapsedMilliseconds() >= ReconnectDue
          StartReconnect()
        EndIf
        If DiscoveryError$ <> ""
          SetGadgetText(#Text_Device, DiscoveryError$)
          DiscoveryError$ = ""
        ElseIf DiscoveryComplete
          If CountGadgetItems(#List_Devices) = 0
            SetGadgetText(#Text_Device, Text("NoDevices"))
          Else
            SetGadgetText(#Text_Device, Text("SelectDevice"))
          EndIf
          DiscoveryComplete = #False
        EndIf
      Case #PB_Event_CloseWindow
        If EventWindow() = #Window_Main
          If TrayReady
            SetMainWindowHidden(#True)
          Else
            Quit = #True
          EndIf
        EndIf
    EndSelect
  Wend
  Exiting = #True
  DisableRemoteControl()
  CancelReconnect()
  SaveConnectionSettings()
  If TrayReady : RemoveSysTrayIcon(#Tray_Main) : EndIf
  ; Exit from the tray must finish workers before freeing the shared mutex.
  StopDiscovery = #True
  If IsThread(DiscoveryThread) : WaitThread(DiscoveryThread) : EndIf
  If IsThread(ReconnectThread) : WaitThread(ReconnectThread) : EndIf
  ; A cancelled reconnect can still have posted an authenticated connection.
  While WindowEvent()
    If Event() = #Event_ReconnectReady And EventData() > 0
      CloseNetworkConnection(EventData())
    EndIf
  Wend
  CloseDiscovery()
  If WsaStarted : WSACleanup_() : EndIf
  If KeyboardHook : UnhookWindowsHookEx_(KeyboardHook) : EndIf
  If MouseHook : UnhookWindowsHookEx_(MouseHook) : EndIf
  If HotkeyRegistered : UnregisterHotKey_(RawInputWindow, #Hotkey_Toggle) : EndIf
  If IsWindow(#Window_CaptureNotice) : CloseWindow(#Window_CaptureNotice) : EndIf
  CloseWindow(#Window_Main)
EndIf
FreeMutex(InputMutex)
