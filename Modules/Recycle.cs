using System;
using System.IO;
using System.Runtime.InteropServices;

namespace WindowsCare {
    [ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IShellItem { }

    // COM vtable order is defined by IFileOperation in shobjidl_core.h.
    [ComImport, Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IFileOperation {
        void Advise(IntPtr sink, out uint cookie);
        void Unadvise(uint cookie);
        void SetOperationFlags(uint flags);
        void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)] string message);
        void SetProgressDialog(IntPtr dialog);
        void SetProperties(IntPtr properties);
        void SetOwnerWindow(uint hwnd);
        void ApplyPropertiesToItem(IShellItem item);
        void ApplyPropertiesToItems(IntPtr items);
        void RenameItem(IShellItem item, [MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr sink);
        void RenameItems(IntPtr items, [MarshalAs(UnmanagedType.LPWStr)] string name);
        void MoveItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr sink);
        void MoveItems(IntPtr items, IShellItem destination);
        void CopyItem(IShellItem item, IShellItem destination, [MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr sink);
        void CopyItems(IntPtr items, IShellItem destination);
        void DeleteItem(IShellItem item, IntPtr sink);
        void DeleteItems(IntPtr items);
        void NewItem(IShellItem destination, uint attributes, [MarshalAs(UnmanagedType.LPWStr)] string name, [MarshalAs(UnmanagedType.LPWStr)] string template, IntPtr sink);
        void PerformOperations();
        void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)] out bool aborted);
    }

    public static class Recycle {
        [DllImport("shell32.dll", CharSet=CharSet.Unicode, PreserveSig=false)]
        private static extern void SHCreateItemFromParsingName(string path, IntPtr context, ref Guid iid, out IShellItem item);

        public static void FileOnly(string path) {
            if (!Path.IsPathRooted(path) || !File.Exists(path) || Directory.Exists(path))
                throw new IOException("An existing local file is required.");
            IShellItem item=null;
            IFileOperation operation=null;
            try {
                var iid=typeof(IShellItem).GUID;
                SHCreateItemFromParsingName(path,IntPtr.Zero,ref iid,out item);
                operation=(IFileOperation)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("3ad05575-8857-4850-9277-11b85bdb8e09")));
                // RECYCLEONDELETE, ADDUNDORECORD, EARLYFAILURE, NOERRORUI,
                // NO_CONNECTED_ELEMENTS, NORECURSION, WANTNUKEWARNING, SILENT.
                // No permanent-delete fallback and no Yes-to-All flag.
                operation.SetOperationFlags(0x00080000 | 0x20000000 | 0x00100000 | 0x0400 | 0x2000 | 0x1000 | 0x4000 | 0x0004);
                operation.DeleteItem(item,IntPtr.Zero);
                operation.PerformOperations();
                bool aborted;
                operation.GetAnyOperationsAborted(out aborted);
                if(aborted) throw new OperationCanceledException("Recycling was cancelled or could not be completed.");
                if(File.Exists(path)) throw new IOException("Recycling was not confirmed.");
            } finally {
                if(operation!=null) Marshal.FinalReleaseComObject(operation);
                if(item!=null) Marshal.FinalReleaseComObject(item);
            }
        }
    }
}
