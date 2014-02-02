/*
Copyright (c) 2014 Martin Cejp 

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dlib.filesystem.localfilesystem;

import dlib.core.stream;
import dlib.filesystem.filesystem;

import std.array;
import std.conv;
import std.datetime;
import std.path;
import std.range;
import std.stdio;
import std.string;

version (Posix) {
    import dlib.filesystem.posixcommon;
    import dlib.filesystem.posixdirectory;
    import dlib.filesystem.posixfile;
}
else version (Windows) {
    import dlib.filesystem.windowscommon;
    import dlib.filesystem.windowsdirectory;
    import dlib.filesystem.windowsfile;
}

// TODO: Should probably check for FILE_ATTRIBUTE_REPARSE_POINT before recursing

/// LocalFileSystem
class LocalFileSystem : FileSystem {
    override InputStream openForInput(string filename) {
        return cast(InputStream) openFile(filename, read, 0);
    }
    
    override OutputStream openForOutput(string filename, uint creationFlags) {
        return cast(OutputStream) openFile(filename, write, creationFlags); 
    }
    
    override IOStream openForIO(string filename, uint creationFlags) {
        return openFile(filename, read | write, creationFlags);
    }
    
    override bool createDir(string path, bool recursive) {
        import std.algorithm;
        
        if (recursive) {
            ptrdiff_t index = max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
            
            if (index != -1)
                createDir(path[0..index], true);
        }
        
        version (Posix) {
            return mkdir(toStringz(path), access_0755) == 0;
        }
        else version (Windows) {
            return CreateDirectoryW(toUTF16z(path), null) != 0;
        }
        else
            throw new Exception("Not implemented.");
    }
    
    override Directory openDir(string path) {
        // TODO: Windows implementation
        
        version (Posix) {
            DIR* d = opendir(!path.empty ? toStringz(path) : ".");
            
            if (d == null)
                return null;
            else
                return new PosixDirectory(this, d, !path.empty ? path ~ "/" : "");
        }
        else version (Windows) {
            string npath = !path.empty ? buildNormalizedPath(path) : ".";
            DWORD attributes = GetFileAttributesW(toUTF16z(npath));

            enum DWORD INVALID_FILE_ATTRIBUTES = cast(DWORD)0xFFFFFFFF;

            if (attributes == INVALID_FILE_ATTRIBUTES)
                return null;

            if (attributes & FILE_ATTRIBUTE_DIRECTORY)
                return new WindowsDirectory(this, npath, !path.empty ? path ~ "/" : "");
            else
                return null;
        }
        else
            throw new Exception("Not implemented.");
    }
    
    override bool stat(string path, out FileStat stat_out) {
        version (Posix) {
            stat_t st;

            if (stat_(toStringz(path), &st) != 0)
                return false;

            stat_out.isFile = S_ISREG(st.st_mode);
            stat_out.isDirectory = S_ISDIR(st.st_mode);

            stat_out.sizeInBytes = st.st_size;
            stat_out.creationTimestamp = SysTime(unixTimeToStdTime(st.st_ctime));
            stat_out.modificationTimestamp = SysTime(unixTimeToStdTime(st.st_mtime));

            return true;
        }
        else version (Windows) {
            WIN32_FILE_ATTRIBUTE_DATA data;

            if (!GetFileAttributesExW(toUTF16z(path), GET_FILEEX_INFO_LEVELS.GetFileExInfoStandard, &data))
                return false;

            if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                stat_out.isDirectory = true;
            else
                stat_out.isFile = true;

            stat_out.sizeInBytes = (cast(FileSize) data.nFileSizeHigh << 32) | data.nFileSizeLow;
            stat_out.creationTimestamp = SysTime(FILETIMEToStdTime(&data.ftCreationTime));
            stat_out.modificationTimestamp = SysTime(FILETIMEToStdTime(&data.ftLastWriteTime));

            return true;
        }
        else
            throw new Exception("Not implemented.");
    }
    
    override bool move(string path, string newPath) {
        // TODO: Windows implementation
        // TODO: should we allow newPath to actually be a directory?
        
        return rename(toStringz(path), toStringz(newPath)) == 0;
    }
    
    override bool remove(string path, bool recursive) {
        FileStat stat;
        
        if (!this.stat(path, stat))
            return false;
        
        return remove(path, stat.isDirectory, recursive);
    }
    
    override InputRange!DirEntry findFiles(string baseDir, bool recursive) {
        // TODO: lazy evaluation
        DirEntry[] entries;
        
        findFiles(baseDir, recursive, delegate int(ref DirEntry entry) {
            entries ~= entry;
            return 0;
        });
        
        return inputRangeObject(entries);
    }
    
    private int findFiles(string baseDir, bool recursive, int delegate(ref DirEntry entry) dg) {
        Directory dir = openDir(baseDir);

        if (dir is null)
            return 0;
        
        int result = 0;
        
        try {
            foreach (entry; dir.contents) {
                if (!baseDir.empty)
                    entry.name = baseDir ~ "/" ~ entry.name;
                
                result = dg(entry);
                
                if (result != 0)
                    return result;

                if (recursive && entry.isDirectory) {
                    result = findFiles(entry.name, recursive, dg);
                
                    if (result != 0)
                        return result;
                }
            }
        }
        finally {
            dir.close();
        }
        
        return result;
    }
    
private:
    version (Posix) {
        enum access_0644 = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;
        enum access_0755 = S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH;
    }

    IOStream openFile(string filename, uint accessFlags, uint creationFlags) {
        // TODO: Windows implementation
        
        version (Posix) {
            int flags;
            
            switch (accessFlags & (read | write)) {
                case read: flags = O_RDONLY; break;
                case write: flags = O_WRONLY; break;
                case read | write: flags = O_RDWR; break;
                default: flags = 0;
            }
            
            if (creationFlags & FileSystem.create)
                flags |= O_CREAT;
            
            if (creationFlags & FileSystem.truncate)
                flags |= O_TRUNC;
            
            int fd = open(toStringz(filename), flags, access_0644);
            
            if (fd < 0)
                return null;
            else
                return new PosixFile(fd, accessFlags);
        }
        else version (Windows) {
            DWORD access = 0;

            if (accessFlags & read)
                access |= GENERIC_READ;

            if (accessFlags & write)
                access |= GENERIC_WRITE;

            DWORD creationMode;

            final switch (creationFlags & (create | truncate)) {
                case 0: creationMode = OPEN_EXISTING; break;
                case create: creationMode = OPEN_ALWAYS; break;
                case truncate: creationMode = TRUNCATE_EXISTING; break;
                case create | truncate: creationMode = CREATE_ALWAYS; break;
            }

            HANDLE file = CreateFileW(toUTF16z(filename), access, FILE_SHARE_READ, null, creationMode,
                FILE_ATTRIBUTE_NORMAL, null);

            if (file == INVALID_HANDLE_VALUE)
                return null;
            else
                return new WindowsFile(file, accessFlags);
        }
        else
            throw new Exception("Not implemented.");
    }
    
    bool remove(string path, bool isDirectory, bool recursive) {
        // TODO: Windows implementation
        
        if (isDirectory && recursive) {
            // Remove contents
            auto dir = openDir(path);
            
            try {
                foreach (entry; dir.contents)
                    remove(path ~ "/" ~ entry.name, entry.isDirectory, recursive);
            }
            finally {
                dir.close();
            }
        }
            
        version (Posix) {
            if (isDirectory) 
                return rmdir(toStringz(path)) == 0;
            else
                return std.stdio.remove(toStringz(path)) == 0;
        }
        else version (Windows) {
            if (isDirectory)
                return RemoveDirectoryW(toUTF16z(path)) != 0;
            else
                return DeleteFileW(toUTF16z(path)) != 0;
        }
        else
            throw new Exception("Not implemented.");
    }
}

unittest {
    import std.regex;
    
    void listImagesInDirectory(ReadOnlyFileSystem fs, string baseDir = "") {
        foreach (entry; fs.findFiles(baseDir, true)
                .filter!(entry => entry.isFile)
                .filter!(entry => !matchFirst(entry.name, `.*\.(gif|jpg|png)$`).empty)) {
            writefln("%s", entry.name);
        }
    }
    
    listImagesInDirectory(new LocalFileSystem);
}
