Option Explicit

Dim fileSystem
Dim shell
Dim baseDirectory
Dim guiScript
Dim powershellPath
Dim command
Dim exitCode
Dim selfTest

Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

baseDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
guiScript = fileSystem.BuildPath(baseDirectory, "QQ-Silk-Converter-GUI.ps1")
If Not fileSystem.FileExists(guiScript) Then
    guiScript = fileSystem.BuildPath(baseDirectory, "scripts\QQ-Silk-Converter-GUI.ps1")
End If

selfTest = False
If WScript.Arguments.Count > 0 Then
    If LCase(WScript.Arguments(0)) = "--self-test" Then
        selfTest = True
    End If
End If

If Not fileSystem.FileExists(guiScript) Then
    If Not selfTest Then
        MsgBox "QQ-Silk-Converter-GUI.ps1 was not found." & vbCrLf & _
            "Please extract the complete Release ZIP.", _
            vbCritical, "QQ / WeChat SILK Voice Converter"
    End If
    WScript.Quit 2
End If

powershellPath = shell.ExpandEnvironmentStrings( _
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
command = QuoteArgument(powershellPath) & _
    " -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File " & _
    QuoteArgument(guiScript)
If selfTest Then
    command = command & " -SelfTest"
End If

' Window style 0 hides only the PowerShell console. The WinForms GUI remains visible.
exitCode = shell.Run(command, 0, True)
If exitCode <> 0 And Not selfTest Then
    MsgBox "The converter could not start (exit code " & exitCode & ")." & _
        vbCrLf & "GUI script: " & guiScript, _
        vbCritical, "QQ / WeChat SILK Voice Converter"
End If

WScript.Quit exitCode

Function QuoteArgument(ByVal value)
    QuoteArgument = Chr(34) & value & Chr(34)
End Function
