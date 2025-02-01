# First, define our execution environment enum
Add-Type -TypeDefinition @"
    public enum ExecutionEnvironment {
        System,             // Run as SYSTEM (default for RMM)
        RunAsUser,          // Run as logged-in user
        RunAsUserElevated   // Run as logged-in user with elevation
    }
"@

# Add our core execution context handler
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Diagnostics;
using System.ComponentModel;
using System.Text;

public class ProcessExecutor {
    #region Win32 API Constants
    private const uint TOKEN_DUPLICATE = 0x0002;
    private const uint TOKEN_QUERY = 0x0008;
    private const uint TOKEN_ASSIGN_PRIMARY = 0x0001;
    private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const uint TOKEN_ADJUST_DEFAULT = 0x0080;
    private const uint TOKEN_ADJUST_SESSIONID = 0x0100;
    private const int MAXIMUM_ALLOWED = 0x2000000;
    private const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    private const int NORMAL_PRIORITY_CLASS = 0x00000020;
    private const uint SE_PRIVILEGE_ENABLED = 0x00000002;
    private const string SE_INCREASE_QUOTA_NAME = "SeIncreaseQuotaPrivilege";
    private const string SE_ASSIGNPRIMARYTOKEN_NAME = "SeAssignPrimaryTokenPrivilege";
    private const int STARTF_USESTDHANDLES = 0x00000100;
    #endregion

    #region Win32 API Structures
    [StructLayout(LayoutKind.Sequential)]
    public struct STARTUPINFO {
        public int cb;
        public string lpReserved;
        public string lpDesktop;
        public string lpTitle;
        public uint dwX;
        public uint dwY;
        public uint dwXSize;
        public uint dwYSize;
        public uint dwXCountChars;
        public uint dwYCountChars;
        public uint dwFillAttribute;
        public uint dwFlags;
        public short wShowWindow;
        public short cbReserved2;
        public IntPtr lpReserved2;
        public IntPtr hStdInput;
        public IntPtr hStdOutput;
        public IntPtr hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess;
        public IntPtr hThread;
        public uint dwProcessId;
        public uint dwThreadId;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_ATTRIBUTES {
        public int Length;
        public IntPtr lpSecurityDescriptor;
        public bool bInheritHandle;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID_AND_ATTRIBUTES {
        public LUID Luid;
        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TOKEN_PRIVILEGES {
        public uint PrivilegeCount;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 1)]
        public LUID_AND_ATTRIBUTES[] Privileges;
    }
    #endregion

    #region Win32 API Imports
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool CreateProcessAsUser(
        IntPtr hToken,
        string lpApplicationName,
        string lpCommandLine,
        IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes,
        bool bInheritHandles,
        uint dwCreationFlags,
        IntPtr lpEnvironment,
        string lpCurrentDirectory,
        ref STARTUPINFO lpStartupInfo,
        out PROCESS_INFORMATION lpProcessInformation);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(
        IntPtr ProcessHandle,
        uint DesiredAccess,
        out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool DuplicateTokenEx(
        IntPtr hExistingToken,
        uint dwDesiredAccess,
        IntPtr lpTokenAttributes,
        int ImpersonationLevel,
        int TokenType,
        out IntPtr phNewToken);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool LookupPrivilegeValue(
        string lpSystemName,
        string lpName,
        out LUID lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(
        IntPtr TokenHandle,
        bool DisableAllPrivileges,
        ref TOKEN_PRIVILEGES NewState,
        int BufferLength,
        IntPtr PreviousState,
        IntPtr ReturnLength);

    [DllImport("userenv.dll", SetLastError = true)]
    private static extern bool CreateEnvironmentBlock(
        out IntPtr lpEnvironment,
        IntPtr hToken,
        bool bInherit);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);
    #endregion

    public static (int exitCode, string output) ExecuteProcessAsUser(string command, bool elevated) {
        IntPtr hUserToken = IntPtr.Zero;
        IntPtr hDupToken = IntPtr.Zero;
        IntPtr hEnvironment = IntPtr.Zero;
        Process process = null;

        try {
            // Get token from explorer process
            var explorerProcess = Process.GetProcessesByName("explorer").FirstOrDefault();
            if (explorerProcess == null)
                throw new Exception("No user session found");

            if (!OpenProcessToken(explorerProcess.Handle,
                TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY | TOKEN_ADJUST_PRIVILEGES,
                out hUserToken))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            // Create duplicate token
            if (!DuplicateTokenEx(
                hUserToken,
                MAXIMUM_ALLOWED,
                IntPtr.Zero,
                2, // SecurityImpersonation
                1, // TokenPrimary
                out hDupToken))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            if (elevated) {
                // Enable necessary privileges for elevation
                EnablePrivilege(hDupToken, SE_INCREASE_QUOTA_NAME);
                EnablePrivilege(hDupToken, SE_ASSIGNPRIMARYTOKEN_NAME);
            }

            // Create environment block
            if (!CreateEnvironmentBlock(out hEnvironment, hDupToken, false))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            var si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(si);
            si.dwFlags = STARTF_USESTDHANDLES;

            var pi = new PROCESS_INFORMATION();

            // Create process with duplicated token
            if (!CreateProcessAsUser(
                hDupToken,
                null,
                command,
                IntPtr.Zero,
                IntPtr.Zero,
                false,
                CREATE_UNICODE_ENVIRONMENT | NORMAL_PRIORITY_CLASS,
                hEnvironment,
                null,
                ref si,
                out pi))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            process = Process.GetProcessById((int)pi.dwProcessId);
            process.WaitForExit();

            return (process.ExitCode, process.StandardOutput.ReadToEnd());
        }
        finally {
            if (hUserToken != IntPtr.Zero) CloseHandle(hUserToken);
            if (hDupToken != IntPtr.Zero) CloseHandle(hDupToken);
            if (hEnvironment != IntPtr.Zero) CloseHandle(hEnvironment);
            if (process != null) process.Dispose();
        }
    }

    private static void EnablePrivilege(IntPtr hToken, string priviledgeName) {
        var tp = new TOKEN_PRIVILEGES();
        tp.PrivilegeCount = 1;
        tp.Privileges = new LUID_AND_ATTRIBUTES[1];

        if (!LookupPrivilegeValue(null, priviledgeName, out tp.Privileges[0].Luid))
            throw new Win32Exception(Marshal.GetLastWin32Error());

        tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

        if (!AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }
}
"@

function Execute-WinGet {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $false)]
        [ExecutionEnvironment]$ExecutionEnvironment = [ExecutionEnvironment]::System
    )

    $appPath = $(Get-ChildItem -Path 'C:\Program Files\WindowsApps' |
        Where-Object { $_.Name -like "Microsoft.DesktopAppInstaller_*x64__*" } |
        Select-Object -First 1).FullName
    $wingetPath = Join-Path $appPath 'winget.exe'

    if (-not (Test-Path $wingetPath)) {
        throw "WinGet not found at expected location: $wingetPath"
    }

    $fullCommand = "`"$wingetPath`" $Command"
    Write-Verbose "Executing command: $fullCommand"
    Write-Verbose "Execution Environment: $ExecutionEnvironment"

    try {
        switch ($ExecutionEnvironment) {
            'System' {
                # Execute as SYSTEM
                $process = Start-Process -FilePath $wingetPath -ArgumentList $Command -Wait -PassThru -NoNewWindow
                return @{
                    ExitCode = $process.ExitCode
                    Output   = $process.StandardOutput.ReadToEnd()
                }
            }
            'RunAsUser' {
                # Execute as current user without elevation
                $result = [ProcessExecutor]::ExecuteProcessAsUser($fullCommand, $false)
                return @{
                    ExitCode = $result.exitCode
                    Output   = $result.output
                }
            }
            'RunAsUserElevated' {
                # Execute as current user with elevation
                $result = [ProcessExecutor]::ExecuteProcessAsUser($fullCommand, $true)
                return @{
                    ExitCode = $result.exitCode
                    Output   = $result.output
                }
            }
            default {
                throw "Unsupported execution environment: $ExecutionEnvironment"
            }
        }
    }
    catch {
        Write-Error "Failed to execute WinGet: $_"
        throw
    }
}

# Example usage:
# Execute-WinGet -Command "install Microsoft.VisualStudioCode --accept-source-agreements" -ExecutionEnvironment RunAsUserElevated
# Execute-WinGet -Command "list" -ExecutionEnvironment RunAsUser
# Execute-WinGet -Command "upgrade --all" -ExecutionEnvironment System
