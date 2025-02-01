# First, define our execution environment enum
Add-Type -TypeDefinition @"
    public enum ExecutionEnvironment {
        System,             // Run as SYSTEM (default for RMM)
        RunAsUser,          // Run as logged-in user
        RunAsUserElevated   // Run as logged-in user with elevation
    }
"@

# Add our core execution context handler with async support
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Diagnostics;
using System.ComponentModel;
using System.Text;
using System.Threading.Tasks;
using System.Collections.Concurrent;
using System.Linq;
using System.Threading;

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

    public static async Task<(int exitCode, string output)> ExecuteProcessAsUserAsync(string command, bool elevated, CancellationToken cancellationToken = default) {
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
            
            // Create a TaskCompletionSource for async wait
            var tcs = new TaskCompletionSource<bool>();
            
            // Handle process exit asynchronously
            process.EnableRaisingEvents = true;
            process.Exited += (sender, args) => tcs.TrySetResult(true);
            
            // Register cancellation
            cancellationToken.Register(() => {
                try {
                    if (!process.HasExited) process.Kill();
                } catch { }
            });

            // Wait for either process exit or cancellation
            await tcs.Task;
            
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
        [string[]]$Packages,

        [Parameter(Mandatory = $false)]
        [ExecutionEnvironment]$ExecutionEnvironment = [ExecutionEnvironment]::RunAsUserElevated,

        [Parameter(Mandatory = $false)]
        [int]$MaxConcurrent = 3,

        [Parameter(Mandatory = $false)]
        [switch]$AcceptSourceAgreements,

        [Parameter(Mandatory = $false)]
        [switch]$AcceptPackageAgreements
    )

    $appPath = $(Get-ChildItem -Path 'C:\Program Files\WindowsApps' |
        Where-Object { $_.Name -like "Microsoft.DesktopAppInstaller_*x64__*" } |
        Select-Object -First 1).FullName
    $wingetPath = Join-Path $appPath 'winget.exe'

    if (-not (Test-Path $wingetPath)) {
        throw "WinGet not found at expected location: $wingetPath"
    }

    # Create cancellation token source for managing concurrent operations
    $cts = [System.Threading.CancellationTokenSource]::new()
    
    # Create a collection to store the results
    $results = [System.Collections.Concurrent.ConcurrentDictionary[string,hashtable]]::new()
    
    try {
        # Create an array of installation tasks
        $tasks = $Packages | ForEach-Object {
            $package = $_
            [System.Threading.Tasks.Task]::Run([Action]({
                try {
                    $arguments = "install $package --silent"
                    if ($AcceptSourceAgreements) { $arguments += " --accept-source-agreements" }
                    if ($AcceptPackageAgreements) { $arguments += " --accept-package-agreements" }
                    
                    $fullCommand = "`"$wingetPath`" $arguments"
                    Write-Verbose "Executing command: $fullCommand"
                    
                    switch ($ExecutionEnvironment) {
                        'System' {
                            $process = Start-Process -FilePath $wingetPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
                            $result = @{
                                ExitCode = $process.ExitCode
                                Output = ""
                            }
                        }
                        'RunAsUser' {
                            $result = [ProcessExecutor]::ExecuteProcessAsUserAsync($fullCommand, $false, $cts.Token).GetAwaiter().GetResult()
                        }
                        'RunAsUserElevated' {
                            $result = [ProcessExecutor]::ExecuteProcessAsUserAsync($fullCommand, $true, $cts.Token).GetAwaiter().GetResult()
                        }
                    }
                    
                    $results.TryAdd($package, @{
                        Success = $result.ExitCode -eq 0
                        ExitCode = $result.ExitCode
                        Output = $result.Output
                        Error = $null
                    })
                }
                catch {
                    $results.TryAdd($package, @{
                        Success = $false
                        ExitCode = -1
                        Output = $null
                        Error = $_.Exception.Message
                    })
                }
            }, $cts.Token)
        }

        # Wait for all tasks to complete with a maximum concurrent limit
        for ($i = 0; $i -lt $tasks.Count; $i += $MaxConcurrent) {
            $batch = $tasks | Select-Object -Skip $i -First $MaxConcurrent
            [System.Threading.Tasks.Task]::WaitAll($batch)
        }

        # Return the results
        return $results.ToArray() | ForEach-Object { 
            [PSCustomObject]@{
                Package = $_.Key
                Success = $_.Value.Success
                ExitCode = $_.Value.ExitCode
                Output = $_.Value.Output
                Error = $_.Value.Error
            }
        }
    }
    finally {
        $cts.Cancel()
        $cts.Dispose()
    }
}

# Example usage:
# $packages = @('Microsoft.PowerShell', 'Obsidian.Obsidian')
# Execute-WinGet -Packages $packages -ExecutionEnvironment RunAsUserElevated -MaxConcurrent 3 -AcceptSourceAgreements -AcceptPackageAgreements
