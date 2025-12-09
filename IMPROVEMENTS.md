# Resize-UserProfileDisk - Web Service Improvements

## Summary of Changes

### ✅ Automatic VHDX Processing (No Manual PowerShell Required)

The service now handles everything automatically through the web interface:

1. **Mount VHDX** - Automatically mounts each VHDX file
2. **Shrink VHDX** - Uses native PowerShell `Resize-VHD -ToMinimumSize` cmdlet
3. **Unmount VHDX** - Safely dismounts after processing
4. **Logging** - Comprehensive before/after size reporting
5. **Multiple VHDX** - Processes multiple files sequentially (safe)

### 🔄 Processing Flow

```
For each VHDX file:
  1. Check if accessible (not locked)
  2. Get initial size (GB)
  3. [Optional] Defragment (if -Defrag selected)
  4. [Optional] Zero free space (if -ZeroFreeSpace selected)
  5. Mount VHDX
  6. Resize to minimum size
  7. Dismount VHDX
  8. Log: "BEFORE: X.XX GB → AFTER: Y.YY GB → SAVED: Z.ZZ GB"
  9. Continue to next file
```

### 📊 Enhanced Logging

Each VHDX now shows clear before/after information:

```
=========================================
Processing: D:\UPD\User1.vhdx
BEFORE: VHDX file size = 25.34 GB
SHRINK: Mounting VHDX...
SHRINK: Mounted as Disk 2
SHRINK: Resizing VHDX to minimum size...
SHRINK: AFTER: VHDX file size = 18.12 GB (was 25.34 GB)
SHRINK: Space saved = 7.22 GB
SHRINK: Completed successfully
=========================================
```

Final summary shows totals:

```
=========================================
FINAL SUMMARY
Total BEFORE: 123.45 GB
Total AFTER:  89.12 GB
Total SAVED:  34.33 GB
Files processed: 8 of 8
Elapsed time: 0 hour, 23 minutes and 14 Seconds
=========================================
```

### 🌐 Web Interface Usage

**No PowerShell commands needed!** Just:

1. Open web browser to `http://localhost:8080`
2. Select "Resize all VHDX files in folder" or "Resize single VHDX file"
3. Enter path (e.g., `D:\UPD`)
4. Optional: Check boxes for:
   - ✓ Defragment before compacting
   - ✓ Zero free space (requires sdelete.exe)
5. Click "Start Resize Operation"
6. Monitor progress in **Jobs** tab
7. View detailed logs in **Logs** tab
8. See statistics in **Statistics** tab

### 🔧 Technical Improvements

**Replaced:**
- ❌ Old: DISKPART batch scripting (diskpart_script.txt)
- ✅ New: Native PowerShell cmdlets (`Mount-VHD`, `Resize-VHD`, `Dismount-VHD`)

**Benefits:**
- ✅ Better error handling
- ✅ Real-time progress logging
- ✅ Per-file size reporting
- ✅ Cleaner code
- ✅ No temporary script files
- ✅ More reliable cleanup

### 📝 Logging Enhancements

- Clear section separators (`=========================================`)
- Color-coded severity levels (Information, Warning, Error)
- Detailed step-by-step execution log
- Individual file before/after sizes
- Total summary at end
- Cleanup verification

### 🚀 Multiple VHDX Support

The service processes multiple VHDX files **sequentially** (one at a time) for safety:

```powershell
# Example: Resize all user profile disks in D:\UPD
Path: D:\UPD
Result: Processes all .vhdx files (except template)
```

Each file is:
1. Checked for accessibility
2. Processed individually
3. Logged with before/after sizes
4. Safely dismounted before next file

### 🛡️ Error Handling

- Files locked by active users are **skipped** (not failed)
- Each VHDX processed independently
- Failed file doesn't stop remaining files
- All errors logged with details
- Automatic cleanup ensures no VHDXs left mounted

### 📦 Service Installation

The installation script now has comprehensive debug logging:

```powershell
.\Install-AsAdmin.ps1  # Auto-elevates and installs with logging
```

Log file created: `install-log-yyyyMMdd-HHmmss.txt`

All installation steps are logged for troubleshooting.

### ✨ Result

**Before:** Manual PowerShell commands required, limited visibility

**After:** Fully automated web-based service with:
- Point-and-click interface
- Real-time job tracking
- Detailed per-file logging
- Comprehensive statistics
- Automatic mounting/unmounting
- Clear before/after size reporting

**Everything is controlled from the web interface - no manual PowerShell required!**
