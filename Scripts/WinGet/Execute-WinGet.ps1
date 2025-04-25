# CTX ENUM
Add-Type -TypeDefinition @"
    public enum ExecContext {
        System,             // Run as SYSTEM (default for RMM)
        RunAsUser,          // Run as logged-in user
        RunAsUserElevated   // Run as logged-in user with elevation
    }
"@

# ASYNC EXECUTOR
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Diagnostics;
using System.ComponentModel;
using System.Text;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Concurrent;

public class AsyncExecutor {
    #region Win32 API Constants
    private const uint INFINITE = 0xFFFFFFFF;
    private const uint WAIT_OBJECT_0 = 0;
    private const uint WAIT_TIMEOUT = 0x00000102;
    private const uint FILE_FLAG_OVERLAPPED = 0x40000000;
    private const uint GENERIC_READ = 0x80000000;
    private const uint GENERIC_WRITE = 0x40000000;
    private const uint OPEN_EXISTING = 3;
    private const uint CREATE_NEW = 1;
    private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
    #endregion

    #region Win32 API Structures
    [StructLayout(LayoutKind.Sequential)]
    public struct OVERLAPPED {
        public IntPtr Internal;
        public IntPtr InternalHigh;
        public uint Offset;
        public uint OffsetHigh;
        public IntPtr hEvent;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SECURITY_ATTRIBUTES {
        public int nLength;
        public IntPtr lpSecurityDescriptor;
        public bool bInheritHandle;
    }
    #endregion

    #region Win32 API Imports
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateIoCompletionPort(
        IntPtr FileHandle,
        IntPtr ExistingCompletionPort,
        UIntPtr CompletionKey,
        uint NumberOfConcurrentThreads);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetQueuedCompletionStatus(
        IntPtr CompletionPort,
        out uint lpNumberOfBytesTransferred,
        out UIntPtr lpCompletionKey,
        out IntPtr lpOverlapped,
        uint dwMilliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool PostQueuedCompletionStatus(
        IntPtr CompletionPort,
        uint dwNumberOfBytesTransferred,
        UIntPtr dwCompletionKey,
        IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateThreadpool(
        IntPtr reserved);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetThreadpoolThreadMaximum(
        IntPtr ptpp,
        uint cThreads);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetThreadpoolThreadMinimum(
        IntPtr ptpp,
        uint cThreads);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateThreadpoolWork(
        IntPtr pfnwk,
        IntPtr pv,
        IntPtr pcbe);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern void SubmitThreadpoolWork(
        IntPtr pwk);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern void WaitForThreadpoolWorkCallbacks(
        IntPtr pwk,
        bool fCancelPendingCallbacks);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern void CloseThreadpoolWork(
        IntPtr pwk);
    #endregion

    private IntPtr _completionPort;
    private IntPtr _threadPool;
    private ConcurrentDictionary<UIntPtr, TaskCompletionSource<object>> _pendingOperations;
    private CancellationTokenSource _cts;

    public AsyncExecutor(uint maxConcurrentThreads = 0) {
        _completionPort = CreateIoCompletionPort(IntPtr.Zero, IntPtr.Zero, UIntPtr.Zero, maxConcurrentThreads);
        _threadPool = CreateThreadpool(IntPtr.Zero);
        _pendingOperations = new ConcurrentDictionary<UIntPtr, TaskCompletionSource<object>>();
        _cts = new CancellationTokenSource();

        if (maxConcurrentThreads > 0) {
            SetThreadpoolThreadMaximum(_threadPool, maxConcurrentThreads);
            SetThreadpoolThreadMinimum(_threadPool, maxConcurrentThreads);
        }
    }

    public async Task<T> ExecuteAsync<T>(Func<T> operation) {
        var tcs = new TaskCompletionSource<object>();
        var key = new UIntPtr((uint)_pendingOperations.Count);
        _pendingOperations[key] = tcs;

        var work = CreateThreadpoolWork(
            Marshal.GetFunctionPointerForDelegate(new Action(() => {
                try {
                    var result = operation();
                    PostQueuedCompletionStatus(_completionPort, 0, key, IntPtr.Zero);
                    tcs.SetResult(result);
                }
                catch (Exception ex) {
                    tcs.SetException(ex);
                }
            })),
            IntPtr.Zero,
            IntPtr.Zero);

        SubmitThreadpoolWork(work);
        WaitForThreadpoolWorkCallbacks(work, false);
        CloseThreadpoolWork(work);

        return await (Task<T>)tcs.Task;
    }

    public void Dispose() {
        _cts.Cancel();
        if (_completionPort != IntPtr.Zero) {
            PostQueuedCompletionStatus(_completionPort, 0, UIntPtr.Zero, IntPtr.Zero);
        }
        _pendingOperations.Clear();
    }
}
"@

# CONTEXT HANDLER
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Diagnostics;
using System.ComponentModel;
using System.Text;
using System.Linq;

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
            var explorerProcess = Process.GetProcessesByName("explorer").FirstOrDefault();
            if (explorerProcess == null)
                throw new Exception("No user session found");

            if (!OpenProcessToken(explorerProcess.Handle,
                TOKEN_DUPLICATE | TOKEN_QUERY | TOKEN_ASSIGN_PRIMARY | TOKEN_ADJUST_PRIVILEGES,
                out hUserToken))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            if (!DuplicateTokenEx(
                hUserToken,
                MAXIMUM_ALLOWED,
                IntPtr.Zero,
                2, // SecurityImpersonation
                1, // TokenPrimary
                out hDupToken))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            if (elevated) {
                EnablePrivilege(hDupToken, SE_INCREASE_QUOTA_NAME);
                EnablePrivilege(hDupToken, SE_ASSIGNPRIMARYTOKEN_NAME);
            }

            if (!CreateEnvironmentBlock(out hEnvironment, hDupToken, false))
                throw new Win32Exception(Marshal.GetLastWin32Error());

            var si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(si);
            si.dwFlags = STARTF_USESTDHANDLES;

            var pi = new PROCESS_INFORMATION();

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

# EXECUTE-WINGET
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

    $results = @{}
    $executor = [AsyncExecutor]::new([uint]$MaxConcurrent)
    $tasks = @()

    try {
        foreach ($package in $Packages) {
            $arguments = "install $package --silent"
            if ($AcceptSourceAgreements) { $arguments += " --accept-source-agreements" }
            if ($AcceptPackageAgreements) { $arguments += " --accept-package-agreements" }
            
            $fullCommand = "`"$wingetPath`" $arguments"
            Write-Verbose "Starting installation of $package"

            $task = $executor.ExecuteAsync({
                param($cmd, $env, $elevated)
                
                try {
                    switch ($env) {
                        'System' {
                            $process = Start-Process -FilePath $cmd.Split(' ')[0] -ArgumentList $cmd.Split(' ', 2)[1] -Wait -PassThru -NoNewWindow
                            @{
                                Success = $process.ExitCode -eq 0
                                ExitCode = $process.ExitCode
                                Output = ""
                                Error = $null
                            }
                        }
                        'RunAsUser' {
                            $result = [ProcessExecutor]::ExecuteProcessAsUser($cmd, $false)
                            @{
                                Success = $result.exitCode -eq 0
                                ExitCode = $result.exitCode
                                Output = $result.output
                                Error = $null
                            }
                        }
                        'RunAsUserElevated' {
                            $result = [ProcessExecutor]::ExecuteProcessAsUser($cmd, $true)
                            @{
                                Success = $result.exitCode -eq 0
                                ExitCode = $result.exitCode
                                Output = $result.output
                                Error = $null
                            }
                        }
                    }
                }
                catch {
                    @{
                        Success = $false
                        ExitCode = -1
                        Output = $null
                        Error = $_.Exception.Message
                    }
                }
            }, $fullCommand, $ExecutionEnvironment, ($ExecutionEnvironment -eq 'RunAsUserElevated'))

            $tasks += @{
                Package = $package
                Task = $task
            }
        }

        # Wait for all tasks to complete
        $tasks | ForEach-Object {
            $result = $_.Task.GetAwaiter().GetResult()
            $results[$_.Package] = $result
        }

        # Return results
        return $results.GetEnumerator() | ForEach-Object {
            [PSCustomObject]@{
                Package = $_.Key
                Success = $_.Value.Success
                ExitCode = $_.Value.ExitCode
                Output = $_.Value.Output
                Error = $_.Value.Error
            }
        }
    }
    catch {
        Write-Error "Error executing WinGet installations: $_"
        throw
    }
    finally {
        $executor.Dispose()
    }
}

# Example usage:
$packages = @('Microsoft.PowerShell', 'Obsidian.Obsidian')
Execute-WinGet -Packages $packages -ExecutionEnvironment RunAsUserElevated -MaxConcurrent 3 -AcceptSourceAgreements -AcceptPackageAgreements