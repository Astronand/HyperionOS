--:Minify:--
local EFI=...
--pf
EFI.beep(440, 500)
local screen=EFI.screenCtl
local ifs=EFI.initfs
local disks=EFI.disks
local arch=EFI.architecture
local kernel = {}
kernel.LOG_Text=""
kernel.version="HyperionOS V1.2.4"
kernel.tag="1.2.4"
kernel.process = "Kernel"
kernel.users={[0]="root",[1000]="User"}
kernel.hostname = "hyperion"
kernel.groups = {}
kernel.uid = 0
kernel.gid = 0
kernel.status = "start"
kernel.key = {}
kernel.cache = {}
kernel.cache.preload = {}
kernel.unixSockets={}
kernel._G=_G
kernel.sleep=sleep

_G.sleep=nil
local windowsExp = false

function kernel.log(msg, level, c, nopanic)
    local f=function()
        c=c or 0x6D6D6D
        kernel.LOG_Text = kernel.LOG_Text..tostring(EFI:date()).." "..kernel.users[kernel.uid].." "..kernel.process.."["..tostring(level or "INFO").."]: "..msg.."\n"
        if kernel.status == "start" then
            screen:setTextColor(c)
            screen:print(tostring(EFI:date()).." "..kernel.users[kernel.uid].." "..kernel.process.."["..tostring(level or "INFO").."]: "..msg)
        elseif kernel.status == "term" then
            kernel.standbyTask=kernel.currentTask
            kernel.currentTask=kernel.kernelTask
            local file=kernel.vfs.open("/dev/console", "w")
            kernel.vfs.devctl(file,"sfgc",c)
            kernel.vfs.write(file,tostring(EFI:date()).." "..kernel.users[kernel.uid].." "..kernel.process.."["..tostring(level or "INFO").."]: "..msg.."\n")
            kernel.vfs.close(file)
            kernel.currentTask=kernel.standbyTask
        end
    end

    local ok,err = xpcall(f,debug.traceback)
    if not ok and not nopanic then
        kernel.panic(err)
    end
end

function kernel.PANIC(msg)
    if kernel.status~="Panic" then
        kernel.log("PANIC: "..msg, "PANIC", 0xFF0000)
        pcall(kernel["saveLog"])
        kernel.status="Panic"
        kernel.reason=msg
        screen:enable()
        screen:setTextColor(0xFF0000)
        screen:setBackgroundColor(0x000000)
        screen:clear()
        screen:resetCursor()
        screen:print(kernel.LOG_Text)
        screen:print("KERNEL PANIC!\n"..msg.."\nSystem halted.")
        screen:print("Press any key to continue...")
        kernel.exitMain = true
    end
    while true do
        EFI:yield()
        local event={EFI:getMachineEvent()}
        if event[1]=="keyPressed" then
            break
        end
    end
    EFI.status="reboot"
    error("KERNEL PANIC")
end
kernel.panic=kernel.PANIC

if windowsExp then
    screen:setTextColor(0xFFFFFF)
    screen:setBackgroundColor(0x0000FF)
    screen:clear()
    screen:resetCursor()
    screen:print("\n\n\n\n\n   :(")
    screen:print("\n   Your PC ran into a problem and needs to restart. We're just collecting some error")
    screen:print("   info, and then we'll restart for you.\n")
    screen:print("\n\n\n   Stop code: average windows experience")
    while true do end
end

kernel.log("Kernel loaded.")
kernel.log("Mounting init disks...")
disks.refresh()
ifs.update(disks)
kernel.disks={}
for _,v in disks.list() do
    kernel.disks[v.address] = v
end
ifs.mount("$", "/boot/")

local fstab=ifs.readAllText("/boot/fstab")
local split = function(str, delim, maxResultCountOrNil)
    assert(#delim == 1, "only delim len 1 supported for now")
    maxResultCountOrNil = (maxResultCountOrNil or 0)-1
    local rv = {}
    local buf = ""
    for i = 1, #str do
        local c = string.sub(str,i,i)
        if #rv ~= maxResultCountOrNil and c == delim then
            table.insert(rv, buf)
            buf = ""
        else
            buf = buf..c
        end
    end
    table.insert(rv, buf)
    return rv
end

if not ifs.isFile("/boot/boot.cfg") then
    kernel.log("First boot detected writing boot.cfg", "INFO", 0x00FF00)
    ifs.writeAllText("/boot/boot.cfg",ifs.readAllText("/boot/safeboot.cfg"))
    kernel.firstBoot=true
end

local initCfgFunc, err = load(ifs.readAllText("/boot/boot.cfg"), "@boot.cfg")
if not initCfgFunc then
    kernel.PANIC("Failed to load /boot/boot.cfg: "..tostring(err))
end

---@diagnostic disable-next-line: param-type-mismatch
local initCfgStatus, config = pcall(initCfgFunc)
if not initCfgStatus then
    kernel.PANIC("Error in /boot/boot.cfg: "..tostring(config))
end
kernel.config = config

local skip=false
local mounted={}
local root=false
for i,v in ipairs(split(fstab,"\n")) do
    if v:sub(1,1)=="U" or v:sub(1,1)=="F" then
        local id=""
        for i=3,#v do
            if v:sub(i,i)==";" then
                if i==3 then kernel.log("Invalid fstab line... Skipping.","WARN", 0xFF8800) skip = true break end
                id=v:sub(3,i-1)
            end
        end
        if not skip then
            local path=v:sub(#id+4)
            if path=="/" then root=true end
            mounted[id]=true
            ifs.mount(id,path)
        else
            skip=false
        end
    end
end
if not root then
    kernel.log("No rootdisk found, prompting user...", "WARN", 0xFF8800)
    screen:setTextColor(0xDDDDDD)
    screen:print("Disk to mount to /:")
    local idx=1
    local canadates={}
    for i,v in pairs(kernel.disks) do
        if not mounted[i] then
            screen:print("("..idx..") : "..i)
            canadates[idx]=i
            idx=idx+1
        end
    end
    while true do
        EFI:yield()
        local event={EFI:getMachineEvent()}
        if event[1]=="keyTyped" then
            if tonumber(event[3]) then
                if canadates[tonumber(event[3])] then
                    fstab="U "..canadates[tonumber(event[3])]..";/\n"..fstab
                    ifs.mount(canadates[tonumber(event[3])], "/")
                    break
                end
            end
            screen:print(event[1], event[3])
        end
    end
end
kernel.log("Disks initialized")

function kernel.saveLog()
    if kernel.status=="running" then
        local file = kernel.vfs.open("/var/log/syslog.log", "w")
        kernel.vfs.write(file, kernel.LOG_Text)
        kernel.vfs.close(file)
    else
        ifs.writeAllText("/var/log/syslog.log", kernel.LOG_Text)
    end
end

function kernel.newFifo()
    local fifo = {}
    fifo.push=function(data)
        table.insert(fifo, data)
    end
    fifo.pop=function()
        return table.remove(fifo,1)
    end
    return fifo
end

function kernel.newUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    local uuid = ""
    for i = 1, #template do
        local c = template:sub(i,i)
        if c == "x" then
            uuid = uuid .. string.format("%x", math.random(0, 15))
        elseif c == "y" then
            uuid = uuid .. string.format("%x", math.random(8, 11))
        else
            uuid = uuid .. c
        end
    end
    return uuid
end

function kernel.sfile(str, writeable)
    local buf = {str or ""}
    local pos = 1
    local closed = false

    local function content()
        return table.concat(buf)
    end

    local function set_content(s)
        buf = {s}
    end

    local function flush()
        str=content()
    end

    local file = {}

    function file.read(n)
        assert(not closed, "file is closed")

        local s = content()
        local len = #s

        if not n then
            local out = s:sub(pos)
            pos = len + 1
            return out
        end

        local out = s:sub(pos, pos + n - 1)
        pos = pos + #out
        return out
    end

    if writeable then
        function file.write(data)
            assert(not closed, "file is closed")

            local s = content()
            local before = s:sub(1, pos - 1)
            local after = s:sub(pos + #data)

            set_content(before .. data .. after)
            pos = pos + #data

            return true
        end
    end

    function file.seek(whence, offset)
        assert(not closed, "file is closed")

        local s = content()
        local len = #s

        whence = whence or "cur"
        offset = offset or 0

        if whence == "set" then
            pos = offset + 1
        elseif whence == "cur" then
            pos = pos + offset
        elseif whence == "end" then
            pos = len + offset + 1
        else
            error("invalid whence")
        end

        if pos < 1 then pos = 1 end
        if pos > len + 1 then pos = len + 1 end

        return pos - 1
    end

    function file.close()
        assert(not closed, "file is closed")
        flush()
        closed = true
    end

    function file.flush()
        assert(not closed, "file is closed")
        flush()
    end

    function file.content()
        return str
    end

    return file
end

kernel.syscalls={}
local modules={[0]={}}
for i=0, 100 do
    modules[i]={}
end

kernel.log("Gathering modules")
for _, i in ipairs(ifs.list("/lib/modules")) do
    local modlist = ifs.list("/lib/modules/"..i)
    if not modlist then
        kernel.log("WARNING: could not list /lib/modules/"..i.." (skipping)", "WARN", 0xFF8800)
    else
        for _,v in ipairs(modlist) do
            local prior=tonumber(v:sub(1,2))
            if prior then
                modules[prior+1][#modules[prior+1]+1]=i.."/"..v
            end
        end
    end
end

kernel.ifs=ifs
--pf
kernel.apis=EFI.firmware
--pf
kernel.EFI=EFI
kernel.arch=arch
kernel.initdisks=disks
kernel.screen=screen
kernel.processes={}
kernel.fstab=fstab
kernel.denied={}
kernel.loadingModule="kernel"
kernel.perTaskHooks={}
kernel.mainHooks={}
kernel.runhooks={}

-- args {taskobj, pid}
function kernel.execPerTask(func, prior)
    if not kernel.perTaskHooks[prior] then kernel.perTaskHooks[prior]={} end
    kernel.perTaskHooks[prior][#kernel.perTaskHooks[prior]+1] = func
    return #kernel.perTaskHooks[prior]
end

function kernel.execOnMain(func)
    kernel.mainHooks[#kernel.mainHooks+1] = func
    return #kernel.mainHooks
end

function kernel.runWhenLoaded(func)
    kernel.runhooks[#kernel.runhooks+1] = func
    return #kernel.runhooks
end

kernel.kernelTask = {
    name="kernel",
    status="R",
    pid=0,
    tgid=0,
    uid=0,
    fd={},
    exit="",
    sleep=0,
    ivs=0,
    vs=0,
    children={},
    syscallReturn={},
    cwd="/",
    timeSlice=0,
    lastTime=0,
    totalTime=0,
    numRuns=0
}
kernel.currentTask = kernel.kernelTask

function kernel.shutdown()
    kernel.exitMain=true
    kernel.status="shutdown"
end

function kernel.reboot()
    kernel.exitMain=true
    kernel.status="reboot"
end

function kernel.halt()
    kernel.exitMain=true
    kernel.status="halt"
end

function kernel.asyncReturn(...)
    kernel.currentTask.syscallReturn = {...}
end

function kernel.deny(moduleid)
    kernel.denied[moduleid]=true
    if kernel.config.showModLoad then kernel.log("Module "..kernel.loadingModule.." denied "..moduleid, "DBUG", 0xFF0000) end
end

kernel.syscalls["time"]=function() return kernel.EFI:getEpochMs() end
kernel.syscalls["date"]=function() return kernel.EFI:date() end
kernel.syscalls["log"]=kernel.log
kernel.syscalls["tag"]=function() return kernel.tag end
kernel.syscalls["getUptime"]=function() return kernel.EFI:getUptime() end
kernel.syscalls["getUsername"]=function(uid) return kernel.users[uid or kernel.uid] end
kernel.syscalls["getHostname"]=function() return kernel.hostname end
kernel.syscalls["getHost"]=function() return kernel.apis._HOST end
kernel.syscalls["version"]=function() return kernel.version end
kernel.syscalls["setHostname"]=function(name) if kernel.uid~=0 then error("Permission denied") end kernel.hostname=name end
kernel.syscalls["arch"]=function() return arch end
kernel.syscalls["sysdump"]=function()
    local rv={}
    for i,v in pairs(kernel.syscalls) do
        rv[#rv+1] = i
    end
    return rv
end
kernel.syscalls["reboot"]=function()
    if kernel.uid==0 or kernel.groups.wheel then
        kernel.reboot()
    end
end
kernel.syscalls["shutdown"]=function()
    if kernel.uid==0 or kernel.groups.wheel then
        kernel.shutdown()
    end
end
kernel.syscalls["halt"]=function()
    if kernel.uid==0 or kernel.groups.wheel then
        kernel.halt()
    end
end
kernel.syscalls["saveLog"]=function()
    if kernel.uid==0 or kernel.groups.wheel then
        kernel.saveLog()
    end
end

ifs.writeAllText("/boot/fstab", fstab)
kernel.saveLog()
kernel.log("Running modules")
for _,p in ipairs(modules) do
    for _,v in ipairs(p) do
        kernel.loadingModule=v
        if not kernel.denied[v] then
            if kernel.config.showModLoad then kernel.log("Loading module "..v, "DBUG", 0x00FFFF) end
            local code=ifs.readAllText("/lib/modules/"..v)
            if not code then
                kernel.panic("Failed to read module "..v)
            end
            local func,err=load(code,"@"..v,"t",_G)
            if not func then kernel.panic("ModuLoadErr: "..tostring(err)) end
            local status, err = xpcall(func,debug.traceback, kernel)
            if not status then kernel.panic("ModuRunErr: "..tostring(err)) end
            if kernel.config.showModLoad then kernel.log("Loaded module "..v, "DBUG", 0x00FFFF) end
            if kernel.config.moreLogsaves then kernel.saveLog() end
        else
            if kernel.config.showModLoad then kernel.log("Denied module "..v, "DBUG", 0xFF0000) end
        end
    end
end

for i=1, #kernel.runhooks do
    local ok,err = xpcall(kernel.runhooks[i], debug.traceback)
    if not ok then kernel.panic(err) end
end

kernel.log("Kernel initialized successfully.")
kernel.saveLog()
kernel.status="running"
kernel.loadingModule=nil
screen:disable()
if not kernel.main then kernel.panic("No scheduler implemented from firmware") end
local ok,err = xpcall(kernel.main, debug.traceback)
if not ok then
    kernel.panic(err)
end
if kernel.status=="panic" then
    kernel.panic(kernel.reason)
end
if kernel.status=="reboot" then
    EFI.status="reboot"
    return true
elseif kernel.status=="halt" then
    kernel.log("System halted.")
    kernel.saveLog()
    while true do end
else
    EFI.status="shutdown"
    return true
end