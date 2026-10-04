# Syscalls
---

Syscalls allow for tasks to request somthing only the kernel can do (ex: reading a file).

Syscalls can be called in 2 ways, ```syscall.{id / name}(args...)``` or ```coroutine.yeild("syscall", {name / id}, args...)```.

Syscalls are also implemented as functions in
```
sleep(ms)
print(...)
printInline(...)
printf(fmt, ...)
userinput(fdin, helpstr, replacestr, fdout)
```
