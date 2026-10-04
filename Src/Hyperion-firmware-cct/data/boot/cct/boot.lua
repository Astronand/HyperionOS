--:Minify:--
local BOOT_DRIVE_PATH = ({...})[1] or "/$"
---@diagnostic disable-next-line: undefined-global
local lterm = term
local function write(text, term)
    local x, y = term.getCursorPos()
    local w, h = term.getSize()

    for i = 1, #text do
        local c = text:sub(i, i)

        if c == "\n" then
            y = y + 1
            x = 1
        elseif c == "\t" then
            local tabSize = 4
            local spaces = tabSize - ((x - 1) % tabSize)
            term.write(string.rep(" ", spaces))
            x = x + spaces
        elseif c == "\b" then
            if x > 1 then
                x = x - 1
                term.setCursorPos(x, y)
                term.write(" ")
                term.setCursorPos(x, y)
            end
        else
            if x <= w and y <= h then
                term.setCursorPos(x, y)
                term.write(c)
                x = x + 1
            end
        end

        if x > w then
            x = 1
            y = y + 1
        end

        if y - 1 >= h then
            term.scroll(1)
            y = h
            term.setCursorPos(x, y)
        end
    end

    term.setCursorPos(x, y)
end

local function displaySuperBadError(err, noyield)
    lterm.setBackgroundColor(0x1)
    lterm.setTextColor(0x4)
    lterm.clear()
    lterm.setCursorPos(1, 1)
    lterm.write("A critical error occurred while loading the system:")
    lterm.setCursorPos(1, 3)
    write(err, lterm)
    coroutine.yield("key")
end

term.setCursorBlink(false)
local ok, err = xpcall(function()
    --p
    local apis = {BOOT_DRIVE_PATH = BOOT_DRIVE_PATH}

    local lua = {
        coroutine = true,
        debug = true,
        _VERSION = true,
        assert = true,
        collectgarbage = true,
        error = true,
        gcinfo = true,
        getmetatable = true,
        ipairs = true,
        __inext = true,
        load = true,
        math = true,
        next = true,
        pairs = true,
        pcall = true,
        rawequal = true,
        rawget = true,
        rawlen = true,
        rawset = true,
        select = true,
        setmetatable = true,
        string = true,
        table = true,
        tonumber = true,
        tostring = true,
        type = true,
        xpcall = true,
        _G = true
    }

    local debug = debug
    for i, v in pairs(_G) do
        if not lua[i] or lua[i] == nil then
            apis[i] = v
            _G[i] = nil
        end
    end
    --p

    local acekeys={
        [apis.keys.enter]="\n",
        [apis.keys.tab]="\t",
        [apis.keys.backspace]="\b",
        [apis.keys.up]="\17",
        [apis.keys.down]="\18",
        [apis.keys.left]="\19",
        [apis.keys.right]="\20",
    }

    function sleep(time)
        local stoptime = apis.os.clock() + (time)
        while stoptime > apis.os.clock() do end
    end

    apis.term.setPaletteColor(0x1,    0xFFFFFF) -- #000000
    apis.term.setPaletteColor(0x2,    0xFF0000) -- #FFFFFF
    apis.term.setPaletteColor(0x4,    0x00FF00) -- #FF0000
    apis.term.setPaletteColor(0x8,    0x0000FF) -- #00FF00
    apis.term.setPaletteColor(0x10,   0x00FFFF) -- #0000FF
    apis.term.setPaletteColor(0x20,   0xFF00FF) -- #00FFFF
    apis.term.setPaletteColor(0x40,   0xFFFF00) -- #FF00FF
    apis.term.setPaletteColor(0x80,   0xFF6D00) -- #FFFF00
    apis.term.setPaletteColor(0x100,  0x6DFF55) -- #FF6D00
    apis.term.setPaletteColor(0x200,  0x24FFFF) -- #6DFF55
    apis.term.setPaletteColor(0x400,  0x924900) -- #24FFFF
    apis.term.setPaletteColor(0x800,  0x6D6D55) -- #924900
    apis.term.setPaletteColor(0x1000, 0xDBDBAA) -- #6D6D55
    apis.term.setPaletteColor(0x2000, 0x6D00FF) -- #DBDBAA
    apis.term.setPaletteColor(0x4000, 0xB6FF00) -- #6D00FF
    apis.term.setPaletteColor(0x8000, 0x000000) -- #B6FF00

    local function getFile(path)
        local file = apis.fs.open(path, "r")
        if not file then
            displaySuperBadError("Could not open file: " .. path)
        end
        local content = file.readAll()
        file.close()
        return content
    end

    local Kernel = load(getFile(BOOT_DRIVE_PATH .. "/kernel.lua"),"@Kernel")
    local initFs = load(getFile(BOOT_DRIVE_PATH .. "/cct/initdisks"),"@Init_disks")(apis)
    local fs = load(getFile(BOOT_DRIVE_PATH .. "/initfs"), "@InitFs")()

    if not Kernel then displaySuperBadError("Could not load kernel.") end
    if not initFs then displaySuperBadError("Could not load initdisks.") end
    if not fs then displaySuperBadError("Could not load initfs.") end

    if not apis.fs.exists("/nvram.dat") then
        local file = apis.fs.open("/nvram.dat", "w")
        file.write("Hello, World!")
        file.close()
    end

    local eeprom
    if apis.fs.exists("/startup.lua") then
        eeprom="/startup.lua"
    elseif apis.fs.exists("/eeprom") then
        eeprom="/eeprom"
    end

    local eventQueue = {}

    local function queueEvent(event, ...)
        table.insert(eventQueue, {event, ...})
    end

    local colors = {
        [0xFFFFFF]=0x0001,
        [0xFF0000]=0x0002,
        [0x00FF00]=0x0004,
        [0x0000FF]=0x0008,
        [0x00FFFF]=0x0010,
        [0xFF00FF]=0x0020,
        [0xFFFF00]=0x0040,
        [0xFF6D00]=0x0080,
        [0x6DFF55]=0x0100,
        [0x24FFFF]=0x0200,
        [0x924900]=0x0400,
        [0x6D6D55]=0x0800,
        [0xDBDBAA]=0x1000,
        [0x6D00FF]=0x2000,
        [0xB6FF00]=0x4000,
        [0x000000]=0x8000
    }

    local fg,bg=0x6D6D55,0x000000
    local l1f,l1d,l2,ops={},{},{},0

    local function findClosest(tbl, target)
        local closest = nil
        local smallestDiff = math.huge

        for k, _ in pairs(tbl) do
            if k==target then return k end
            local diff = math.abs(k - target)
            if diff < smallestDiff then
                smallestDiff = diff
                closest = k
            end
        end

        return closest
    end

    local function aprox(c24)
        ops = ops + 1

        if ops % 1024 == 0 then
            l1d = {}
            l1f = {}
        end

        if ops % 8192 == 0 then
            l2 = {}
        end

        if l2[c24] ~= nil then
            return l2[c24]
        end

        if l1d[c24] ~= nil then
            l1f[c24] = l1f[c24] + 1

            if l1f[c24] >= 16 then
                l2[c24] = l1d[c24]
                l1d[c24] = nil
                l1f[c24] = nil
                return l2[c24]
            end

            return l1d[c24]
        end

        local closestKey = findClosest(colors, c24)
        if not closestKey then return nil end

        local value = colors[closestKey]

        l1d[c24] = value
        l1f[c24] = 1

        return value
    end

    --p
    local p={}
    local native = apis.peripheral
    local sides = {"top", "bottom", "left", "right", "front", "back"}

    function p.getNames()
        local results = {}
        for n = 1, #sides do
            local side = sides[n]
            if native.isPresent(side) then
                table.insert(results, side)
                if native.hasType(side, "peripheral_hub") then
                    local remote = native.call(side, "getNamesRemote")
                    for _, name in ipairs(remote) do
                        table.insert(results, name)
                    end
                end
            end
        end
        return results
    end

    function p.isPresent(name)
        if native.isPresent(name) then
            return true
        end

        for n = 1, #sides do
            local side = sides[n]
            if native.hasType(side, "peripheral_hub") and native.call(side, "isPresentRemote", name) then
                return true
            end
        end
        return false
    end

    function p.getType(peripheral)
        if type(peripheral) == "string" then
            if native.isPresent(peripheral) then
                return native.getType(peripheral)
            end
            for n = 1, #sides do
                local side = sides[n]
                if native.hasType(side, "peripheral_hub") and native.call(side, "isPresentRemote", peripheral) then
                    return native.call(side, "getTypeRemote", peripheral)
                end
            end
            return nil
        else
            local mt = getmetatable(peripheral)
            if not mt or mt.__name ~= "peripheral" or type(mt.types) ~= "table" then
                error("bad argument #1 (table is not a peripheral)", 2)
            end
            return table.unpack(mt.types)
        end
    end

    function p.hasType(peripheral, peripheral_type)
        if type(peripheral) == "string" then
            if native.isPresent(peripheral) then
                return native.hasType(peripheral, peripheral_type)
            end
            for n = 1, #sides do
                local side = sides[n]
                if native.hasType(side, "peripheral_hub") and native.call(side, "isPresentRemote", peripheral) then
                    return native.call(side, "hasTypeRemote", peripheral, peripheral_type)
                end
            end
            return nil
        else
            local mt = getmetatable(peripheral)
            if not mt or mt.__name ~= "peripheral" or type(mt.types) ~= "table" then
                error("bad argument #1 (table is not a peripheral)", 2)
            end
            return mt.types[peripheral_type] ~= nil
        end
    end

    function p.getMethods(name)
        if native.isPresent(name) then
            return native.getMethods(name)
        end
        for n = 1, #sides do
            local side = sides[n]
            if native.hasType(side, "peripheral_hub") and native.call(side, "isPresentRemote", name) then
                return native.call(side, "getMethodsRemote", name)
            end
        end
        return nil
    end

    function p.getName(peripheral)
        local mt = getmetatable(peripheral)
        if not mt or mt.__name ~= "peripheral" or type(mt.name) ~= "string" then
            error("bad argument #1 (table is not a peripheral)", 2)
        end
        return mt.name
    end

    function p.call(name, method, ...)
        if native.isPresent(name) then
            return native.call(name, method, ...)
        end

        for n = 1, #sides do
            local side = sides[n]
            if native.hasType(side, "peripheral_hub") and native.call(side, "isPresentRemote", name) then
                return native.call(side, "callRemote", name, method, ...)
            end
        end
        return nil
    end

    function p.wrap(name)
        local methods = p.getMethods(name)
        if not methods then
            return nil
        end

        local types = { p.getType(name) }
        for i = 1, #types do types[types[i]] = true end
        local result = setmetatable({}, {
            __name = "peripheral",
            name = name,
            type = types[1],
            types = types,
        })
        for _, method in ipairs(methods) do
            result[method] = function(...)
                return p.call(name, method, ...)
            end
        end
        return result
    end

    function p.find(ty, filter)
        local results = {}
        for _, name in ipairs(p.getNames()) do
            if p.hasType(name, ty) then
                local wrapped = p.wrap(name)
                if filter == nil or filter(name, wrapped) then
                    table.insert(results, wrapped)
                end
            end
        end
        return table.unpack(results)
    end
    --p
    local allscreens = {p.find("monitor")}
    for i=1, #allscreens do
        allscreens[i].setTextScale(.5)
        allscreens[i].clear()
        allscreens[i].setCursorPos(1,1)
    end

    allscreens[#allscreens+1] = apis.term

    local callAsyncQueue = {}
    local callAsyncReturn = {}
    apis.callAsyncReturn = callAsyncReturn
    local callidx=0

    function apis.callAsync(func, ...)
        callidx=callidx+1
        callAsyncQueue[#callAsyncQueue+1] = {callidx, func, ...}
        return callidx
    end

    local EFI = {
        yield=function() end,
        getEpochMs = function() return apis.os.epoch("utc") end,
        getUptime = function() return apis.os.clock() * 1000 end,
        date = function() return apis.os.date("!%Y-%m-%dT%H:%M:%SZ", apis.os.epoch("utc") / 1000) end,
        getMachineEvent = function()
            if #eventQueue > 0 then
                return table.unpack(table.remove(eventQueue, 1))
            else
                return nil
            end
        end,
        getEEPROM = function() return getFile(eeprom) end,
        setEEPROM = function(_, text)
            local h = apis.fs.open(eeprom, "w")
            h.write(text)
            h.close()
        end,
        initfs=fs,
        disks=initFs,
        screenCtl={
            print = function(_, text)
                for i=1, #allscreens do
                    write(text.."\n", allscreens[i])
                end
            end,
            printInline = function(_, text)
                for i=1, #allscreens do
                    write(text, allscreens[i])
                end
            end,
            clear = function()
                for i=1, #allscreens do
                    allscreens[i].clear()
                    allscreens[i].setCursorPos(1, 1)
                end
            end,
            resetCursor = function()
                for i=1, #allscreens do
                    allscreens[i].setCursorPos(1, 1)
                end
            end,
            setBackgroundColor = function(_, color)
                bg=color
                for i=1, #allscreens do
                    allscreens[i].setBackgroundColor(aprox(color))
                end
            end,
            setTextColor = function(_, color)
                fg=color
                for i=1, #allscreens do
                    allscreens[i].setTextColor(aprox(color))
                end
            end,
            getBackgroundColor = function()
                return bg
            end,
            getTextColor = function()
                return fg
            end,
            enable=function()
                for i=1, #allscreens do
                    allscreens[i].clear()
                    allscreens[i].setCursorPos(1, 1)
                end
            end,
            disable=function() end
        },
        architecture="cct",
        getNvram = function() return getFile("/nvram.dat") end,
        setNvram = function(_, text)
            local h = apis.fs.open("/nvram.dat", "w")
            h.write(text)
            h.close()
        end,
        firmware=apis,
        status="running",
        beep=function() end
    }

    apis.term.setBackgroundColor(0x8000)
    apis.term.setTextColor(0x1000)
    apis.term.clear()
    apis.term.setCursorPos(1, 1)

    local kernelCoro = coroutine.create(function()
        --pf
        ---@diagnostic disable-next-line: param-type-mismatch
        local ok, err = xpcall(Kernel, debug.traceback, EFI)
        if not ok then
            error(err)
        else
            apis.os.shutdown()
        end
    end)

    function EFI.resumeWithTimeout(co, timeout, ...)
        local startTime = EFI.getEpochMs()
        debug.sethook(co, function()
            if EFI.getEpochMs() > startTime + timeout then
                return coroutine.yield("timeout")
            end
        end, "", 1000)
        local ret = {coroutine.resume(co, ...)}
        if ret[1] and ret[2] == "timeout" then
            return "timeout"
        elseif ret[1] == false then
            return "error", ret[2]
        else
            debug.sethook(co)
            return "success", table.unpack(ret, 2)
        end
    end

    EFI.screenCtl:print("Loaded in " .. tostring(apis.os.clock()) .. " seconds.\n")
    --p

    while true do
        local status, err = EFI.resumeWithTimeout(kernelCoro, 50)
        apis.os.queueEvent("NoSleep")
        local exit = false
        while not exit do
            local event = {coroutine.yield()}
            if event[1] == "key" then
                queueEvent(table.unpack(event))
                queueEvent("keyPressed", 1, event[2])
                if acekeys[event[2]] then
                    queueEvent("keyTyped", 1, acekeys[event[2]])
                end
            elseif event[1] == "char" then
                queueEvent(table.unpack(event))
                queueEvent("keyTyped", 1, event[2])
            elseif event[1] == "key_up" then
                queueEvent(table.unpack(event))
                queueEvent("keyReleased", 1, event[2])
            elseif event[1] == "NoSleep" then
                exit = true
            else
                queueEvent(table.unpack(event))
            end
        end
        while #callAsyncQueue>0 do
            local bundle = table.remove(callAsyncQueue, 1)
            local ret = {xpcall(bundle[2], debug.traceback, table.unpack(bundle, 3))}
            if not ret[1] then
                callAsyncReturn[bundle[1]]={false, ret[2]}
            else
                callAsyncReturn[bundle[1]]={true, table.unpack(ret,2)}
            end
        end
        if status == "error" or coroutine.status(kernelCoro) == "dead" then
            if EFI.status=="reboot" then
                apis.os.reboot()
            elseif EFI.status=="shutdown" then
                apis.os.shutdown()
            end
            displaySuperBadError("Kernel error: " .. tostring(err))
            coroutine.yield("key")
        elseif status == "success" then
            if EFI.status=="reboot" then
                apis.os.reboot()
            elseif EFI.status=="shutdown" then
                apis.os.shutdown()
            end
            displaySuperBadError("Kernel error: Attempted to yield main thread\n"..debug.traceback(kernelCoro, "Attempted to yield main thread"))
            coroutine.yield("key")
        end
        initFs:refresh()
    end
end, debug.traceback)

if not ok then displaySuperBadError("Fatal error during boot: " .. err) end
while true do coroutine.yield("key") end
