; --------------------------------------------------
; MAIN START
; --------------------------------------------------
#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
ConfigFile := A_ScriptDir "\betty_server_settings.ini"
ServersKey := "HKCU\Software\Microsoft\Terminal Server Client\Servers"

; Default dimensions and margins/padding between form controls
guiW := 400
guiH := 200
margin := 10
fullWidth := guiW - (margin*2)
oneHalfWidth := (guiW - (margin*2)) // 2
currentY := 10

; Set the main gui with the form name
mainGui := Gui(, "Betty Gaming Server")
mainGui.SetFont("s11", "Segoe UI")

; Set form text and controls
statusText := mainGui.AddText("x10 y" currentY " w" fullWidth " Center cBlue", "Status: STAND BY")
currentY := currentY + 20
mainGui.AddText("x10 y" currentY " w" fullWidth, "Server: ")
currentY := currentY + 20
rdpSessionDropdown := mainGui.Add("DropDownList","x10" " y" currentY " w" fullWidth, GetRDPServerOptions())
currentY := currentY + 40
mainGui.AddText("x10 y" currentY " w" oneHalfWidth, "Server IP: ")
mainGui.AddText("x" (oneHalfWidth + margin) " y" currentY " w" oneHalfWidth, "Server MAC: ")
currentY := currentY + 20
ipTextBox := mainGui.Add("Edit", "x10 y" currentY " w" oneHalfWidth " vServerIP", "")
macTextBox := mainGui.Add("Edit", "x" (oneHalfWidth + margin) " y" currentY " w" oneHalfWidth " vServerMAC", "")
currentY := currentY + 40
startBtn := mainGui.AddButton("x10" " y" currentY " w" fullWidth " h40", "Start Server")
currentY := currentY + 30


; Handle button clicks and form close events
rdpSessionDropdown.OnEvent("Change", (*) => ValidateRDPDropdownSelected())
ipTextBox.OnEvent("Change", (*) => SaveSelection(ipTextBox, "WakeOnLANIP"))
macTextBox.OnEvent("Change", (*) => SaveSelection(macTextBox, "WakeOnLANMAC"))
startBtn.OnEvent("Click", StartServer)
mainGui.OnEvent("Close", (*) => ExitApp())

; Restore form control values from the config file if it exists
RestoreFormControls()

; Show the form
mainGui.Show("w" guiW " h" guiH)
CheckStatus()


; --------------------------------------------------
; FORM CONTROL DATA FUNCTIONS
; --------------------------------------------------
GetRDPServerOptions(*) {
    ; Build list of server names
    ServerList := []
    Loop Reg, ServersKey, "K"
    {
        ServerList.Push(A_LoopRegName)
    }
    return ServerList
}

ValidateRDPDropdownSelected(*) {
    ; Check if an RDP address was selected, if not show the user
    if(CheckRDPSelected()) {
        SaveSelection(rdpSessionDropdown, "SelectedServer")
        statusText.Text := "Status: STAND BY"
        statusText.SetFont("cBlue")
    } 
}

SaveSelection(ctrl, variableName, *)
{
    ; Save the selected form control value into the config file
    IniWrite(ctrl.Text, ConfigFile, "Settings", variableName)
}

RestoreFormControls(*) {
    ; Restore form control values from the config file if it exists
    if !FileExist(ConfigFile)
        return
    
    ; Restore the selected RDP session if it exists in the config file
    selectedServer := IniRead(ConfigFile, "Settings", "SelectedServer", "")
    if selectedServer
        rdpSessionDropdown.Text := selectedServer

    ; Restore the server IP if it exists in the config file
    savedIP := IniRead(ConfigFile, "Settings", "WakeOnLANIP", "")
    if savedIP
        ipTextBox.Text := savedIP

    ; Restore the server MAC if it exists in the config file
    savedMAC := IniRead(ConfigFile, "Settings", "WakeOnLANMAC", "")
    if savedMAC
        macTextBox.Text := savedMAC
}

; --------------------------------------------------
; CHECK SERVER STATUS FUNCTIONS
; --------------------------------------------------
CheckStatus() {
    ; Only check the server status if an rdp address has been provided, otherwise just show the default status message
    if (CheckRDPSelected()) {
        if PingServer(ipTextBox.Text) {
            statusText.SetFont("cGreen")
            statusText.Text := "Status: ONLINE"
        } else {
            statusText.SetFont("cRed")
            statusText.Text := "Status: OFFLINE"
        }        
    }
}

CheckRDPSelected() {
    ; Check if an RDP address was selected, if not show the user
    if (!rdpSessionDropdown.Text) {
        statusText.SetFont("cBlack")
        statusText.Text := "PLEASE SELECT AN RDP SESSION SERVER"
        return false
    }
    return true
}

PingServer(ip) {
    psCommand := "$c=Test-NetConnection '" ip "' -Port 3389; if($c.TcpTestSucceeded){exit 0}else{exit 1}"
    exitCode := RunWait(A_ComSpec " /c powershell -NoProfile -Command " Chr(34) psCommand Chr(34), , "Hide")
    return exitCode = 0
}

; --------------------------------------------------
; START SERVER FUNCTIONS
; --------------------------------------------------
WakeOnLAN(mac) {
    cleanMac := StrUpper(RegExReplace(mac, "[^0-9A-Fa-f]"))

    psCommand := "$mac='" cleanMac "';"
        . "$m=@();for($i=0;$i -lt 12;$i+=2){$m+=[byte]::Parse($mac.Substring($i,2),[System.Globalization.NumberStyles]::HexNumber)};"
        . "$packet=New-Object byte[] 102;for($i=0;$i -lt 6;$i++){$packet[$i]=0xFF};"
        . "for($i=0;$i -lt 16;$i++){[Array]::Copy($m,0,$packet,6+($i*6),6)};"
        . "$u=New-Object Net.Sockets.UdpClient;$u.EnableBroadcast=$true;"
        . "[void]$u.Send($packet,$packet.Length,'255.255.255.255',9);$u.Close()"

    RunWait(A_ComSpec " /c powershell -NoProfile -Command " Chr(34) psCommand Chr(34), , "Hide")
}

StartServer(*) {
    ; If any of the fields are blank then do not run and show a message to the user
    if (!CheckRDPSelected()) {
        MsgBox("Please select an RDP session server.")
        return
    } else if (!ipTextBox.Text) {
        MsgBox("Please enter the local server IP address. (ex. 192.168.1.100)")
        return
    } else if (!macTextBox.Text) {
        MsgBox("Please enter the local server MAC address. (ex. 00:11:22:33:44:55)")
        return
    }

    ; Disable button while startup flow is in progress.
    startBtn.Enabled := false
    startBtn.Text := "Starting..."
    statusText.SetFont("cBlue")
    statusText.Text := "Status: Sending Wake-on-LAN..."
    rdpSessionDropdown.Enabled := false
    ipTextBox.Enabled := false
    macTextBox.Enabled := false

    ; Send the magic packet to wake the server
    WakeOnLAN(macTextBox.Text)

    ; Wait for the server to come online by pinging the IP address, then launch the RDP session
    loop {
        Sleep 1000
        statusText.Text := "Status: Waiting for RDP..."
        if PingServer(ipTextBox.Text)
            break
    }

    statusText.SetFont("cGreen")
    statusText.Text := "Status: Launching RDP..."

    RunWait(A_ComSpec " /c cmdkey /generic:TERMSRV/" rdpSessionDropdown.Text, , "Hide")
    Run("mstsc.exe /v:" rdpSessionDropdown.Text)
    ExitApp()
}