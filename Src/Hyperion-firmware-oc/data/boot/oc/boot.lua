---@diagnostic disable-next-line: undefined-global
local cp,c=component,computer;local b_addr=c.getBootAddress();local b_fs=cp.proxy(b_addr)
local gpu=cp.list("gpu")() and cp.proxy(cp.list("gpu")())
local e_rom=cp.list("eeprom")() and cp.proxy(cp.list("eeprom")())
local screens={}
for addr in cp.list("screen") do
    if gpu then
        gpu.bind(addr)
        local w,h=gpu.maxResolution()
        gpu.setResolution(w,h)
        gpu.fill(1,1,w,h," ")
        cp.proxy(addr).turnOn()
        screens[#screens+1] = {cx=1,cy=1,w=w,h=h,addr=addr}
    end
end
local function scroll(scr) gpu.copy(1,2,scr.w,scr.h-1,0,-1);gpu.fill(1,scr.h,scr.w,1," ") end
local function write(t)
    if not gpu then return end
    for s=1, #screens do
        local scr=screens[s]
        gpu.bind(scr.addr)
        for i=1,#t do
            local char=t:sub(i,i)
            if char=="\n" then scr.cx=1;scr.cy=scr.cy+1
            elseif char=="\t" then scr.cx=scr.cx+(4-((scr.cx-1)%4))
            elseif char=="\b" then if scr.cx>1 then scr.cx=scr.cx-1;gpu.set(scr.cx,scr.cy," ") end
            else gpu.set(scr.cx,scr.cy,char);scr.cx=scr.cx+1 end
            if scr.cx>scr.w then scr.cx=1;scr.cy=scr.cy+1 end
            if scr.cy>scr.h then scroll(scr);scr.cy=scr.cy-1 end
        end
    end
end
local function throw(err)
    if gpu then
        gpu.setBackground(0x0000AA);
        gpu.setForeground(0xFFFFFF);
        for i=1, #screens do
            gpu.fill(1,1,screens[i].w,screens[i].h," ");
            screens[i].cx,screens[i].cy=1,1;
        end
        write("CRITICAL KERNEL ERROR:\n"..tostring(err))
    end
    while true do c.pullSignal() end
end
local ok,err=xpcall(function()
    local apis={}
    local _l={coroutine=1,debug=1,_VERSION=1,assert=1,collectgarbage=1,error=1,getmetatable=1,ipairs=1,load=1,math=1,next=1,pairs=1,pcall=1,rawequal=1,rawget=1,rawlen=1,rawset=1,select=1,setmetatable=1,string=1,table=1,tonumber=1,tostring=1,type=1,xpcall=1,_G=1}
    for k,v in pairs(_G) do if not _l[k] then apis[k]=v;_G[k]=nil end end
    function sleep(t) local s=c.uptime()+t;while c.uptime()<s do c.pullSignal(s-c.uptime()) end end
    local function getFile(path)
        local h,err=b_fs.open(path,"r")
        if not h then throw("Cannot open: "..path) end
        local buf,chk="",""
        repeat chk=b_fs.read(h,math.huge);buf=buf..(chk or "") until not chk
        b_fs.close(h)
        return buf
    end
    local Kernel=load(getFile("/kernel.lua"),"@Kernel")
    local initFs=load(getFile("/oc/initdisks"),"@Init_disks")
    local fs=load(getFile("/initfs"),"@InitFs")
    if not Kernel then throw("Kernel load failed.") end
    if initFs then initFs=initFs(apis, b_fs, b_addr) end
    if fs then fs=fs() end
    local eQ={}
    local function qEv(e,...) table.insert(eQ,{e,...}) end
    local efi={
        getEpochMs=function() return math.floor(c.uptime()*1000) end,
        getUptime=function() return c.uptime()*1000 end,
        date=function() return tostring(apis.os.date()) end,
        getMachineEvent=function()
            if #eQ > 0 then
                return table.unpack(table.remove(eQ, 1))
            else
                return nil
            end
        end,
        getEEPROM=function() return e_rom and e_rom.get() or "" end,
        setEEPROM=function(_,t) if e_rom then e_rom.set(t) end end,
        getNvram=function() return e_rom and e_rom.getData() or "" end,
        setNvram=function(_,t) if e_rom then e_rom.setData(t) end end,
        beep=function(freq, timeMs) c.beep(freq, timeMs / 1000) end,
        initfs=fs,
        disks=initFs,
        architecture="oc",
        firmware=apis,
        reboot=false,
        yield=function() coroutine.yield() end,
        screenCtl={
            print=function(_,t) write(tostring(t).."\n") end,
            printInline=function(_,t) write(tostring(t)) end,
            clear=function() if gpu then for i=1, #screens do local scr=screens[i];gpu.bind(scr.addr);gpu.fill(1,1,scr.w,scr.h," ");scr.cx,scr.cy=1,1 end end end,
            resetCursor=function() for i=1, #screens do local scr=screens[i];scr.cx,scr.cy=1,1 end end,
            setBackgroundColor=function(_,cl) if gpu then gpu.setBackground(cl) end end,
            setTextColor=function(_,cl) if gpu then gpu.setForeground(cl) end end,
            enable=function() end,
            disable=function() end
        }
    }
    local kCo=coroutine.create(function()
        local s,e=xpcall(Kernel,debug.traceback,efi)
        if not s and not efi.reboot then throw(e) end
        if efi.reboot then c.shutdown(true) else c.shutdown() end
    end)
    efi.screenCtl:print("Loaded in "..tostring(c.uptime()).."s")
    while true do
        local st,e=coroutine.resume(kCo)
        c.pushSignal("NoSleep")
        local ex=false
        while not ex do
            local ev={c.pullSignal(0)}
            if ev[1]=="key_down" then qEv("keyPressed",1,ev[3]);qEv("keyTyped",1,string.char(ev[3]))
            elseif ev[1]=="key_up" then qEv("keyReleased",1,ev[3])
            end
            if ev[1]=="NoSleep" then ex=true else qEv(table.unpack(ev)) end
        end
        if st=="error" or coroutine.status(kCo)=="dead" then
            if efi.reboot then c.shutdown(true) end
            throw("Kernel fault: "..tostring(e))
        end
    end
end,debug.traceback)
if not ok then throw("Boot fault: "..err) end