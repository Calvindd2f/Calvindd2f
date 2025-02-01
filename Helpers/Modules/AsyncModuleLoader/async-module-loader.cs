using System;
using System.Management.Automation;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Management.Automation.Runspaces;
using System.Collections.Concurrent;

namespace AsyncModuleLoader
{
    [Cmdlet(VerbsData.Import, "ModuleAsync")]
    public class ImportModuleAsyncCommand : PSCmdlet
    {
        [Parameter(Mandatory = true, Position = 0)]
        public string[] ModuleNames { get; set; }

        [Parameter]
        public SwitchParameter Force { get; set; }

        private ConcurrentQueue<string> _verboseMessages;
        private ConcurrentQueue<ErrorRecord> _errors;

        protected override void BeginProcessing()
        {
            _verboseMessages = new ConcurrentQueue<string>();
            _errors = new ConcurrentQueue<ErrorRecord>();

            var tasks = new List<Task>();

            foreach (var moduleName in ModuleNames)
            {
                var task = Task.Run(() => ImportModule(moduleName));
                tasks.Add(task);
            }

            Task.WhenAll(tasks).GetAwaiter().GetResult();

            // Process all queued messages on the main thread
            while (_verboseMessages.TryDequeue(out string message))
            {
                WriteVerbose(message);
            }

            while (_errors.TryDequeue(out ErrorRecord error))
            {
                WriteError(error);
            }
        }

        private void ImportModule(string moduleName)
        {
            try
            {
                using (var powerShell = PowerShell.Create())
                {
                    // Use the current runspace directly
                    powerShell.Runspace = Runspace.DefaultRunspace;

                    powerShell.AddCommand("Import-Module")
                             .AddParameter("Name", moduleName)
                             .AddParameter("Global", true);  // Ensure module is imported globally

                    if (Force)
                    {
                        powerShell.AddParameter("Force");
                    }

                    powerShell.Invoke();
                }

                _verboseMessages.Enqueue($"Successfully imported module: {moduleName}");
            }
            catch (Exception ex)
            {
                _errors.Enqueue(new ErrorRecord(
                    ex,
                    "AsyncModuleImportError",
                    ErrorCategory.OperationStopped,
                    moduleName));
            }
        }
    }
}