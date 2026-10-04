# boot.cfg docs

The /boot/boot.cfg file contains configs for booting

```
initPath<String>
    path that init takes to load the init system (systemd)

allowGloabalOverwrites<bool>
    allow modifying of gloabal env (usually for debug purposes)

enableAdvanacedDebug<bool>
    allow debug into the kernel

maxOpenFiles<num>
    maximum open files for the whole system

maxFilesPerTask<num>
    maximum open files for each task

preempt<bool>
    enable/disable preemptive multitasking

debugSyscalls<bool>
    logs syscalls and their return values aswell as what task executed them

logTaskExit<bool>
    logs task exits and errors

showModLoad<bool>
    log module loads

tmpToDisk<bool>
    writes tmp to disk instead of ram

logSymlinkTraverse<bool>
    logs symlink traversal (can harm preformance)

moreLogsaves<bool>
    enables log debug save points (can harm preformance)

logPathResolution<bool>
    logs how a vfs path resolves to a disk path (can harm preformance)
```