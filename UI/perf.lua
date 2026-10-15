local _, sc = ...;

-- /sc perf [seconds]
-- Reports how much CPU time and memory this addon uses, from the client's own
-- addon profiler. Without a number it prints the current figures; with one it
-- measures for that many seconds (5-300) and also reports how fast the
-- addon produces garbage, so a change can be compared before and after:
-- stand idle, fight, or hover items while it runs.

local perf = {};

local profiler = C_AddOnProfiler;
local metric = Enum and Enum.AddOnProfilerMetric;

local function addon_metric(m)
    if not profiler or not metric or not metric[m] then
        return nil;
    end
    local ok, v = pcall(profiler.GetAddOnMetric, sc.core.addon_name, metric[m]);
    return ok and type(v) == "number" and v or nil;
end

local function overall_metric(m)
    if not profiler or not metric or not metric[m] or not profiler.GetOverallMetric then
        return nil;
    end
    local ok, v = pcall(profiler.GetOverallMetric, metric[m]);
    return ok and type(v) == "number" and v or nil;
end

local function memory_kb()
    UpdateAddOnMemoryUsage();
    return GetAddOnMemoryUsage(sc.core.addon_name) or 0;
end

local function ms(v)
    return v and string.format("%.3f ms", v) or "n/a";
end

local function count(v)
    return v and tostring(math.floor(v + 0.5)) or "n/a";
end

local function out(text)
    print("|cFF9B6CFF"..sc.core.addon_name.." perf:|r "..text);
end

local function print_figures()
    if profiler and profiler.IsEnabled and not profiler.IsEnabled() then
        out("the client's addon profiler is off; only memory is shown");
    end
    local recent, all_recent = addon_metric("RecentAverageTime"), overall_metric("RecentAverageTime");
    local share = "";
    if recent and all_recent and all_recent > 0 then
        share = string.format(" (%.0f%% of all addons)", 100 * recent / all_recent);
    end
    out("per frame: recent "..ms(recent)..share..
        ", session "..ms(addon_metric("SessionAverageTime"))..
        ", peak "..ms(addon_metric("PeakTime")));
    out("frames over 5/10/50/100 ms: "..
        count(addon_metric("CountTimeOver5Ms")).." / "..
        count(addon_metric("CountTimeOver10Ms")).." / "..
        count(addon_metric("CountTimeOver50Ms")).." / "..
        count(addon_metric("CountTimeOver100Ms")));
    out(string.format("memory: %.0f KB, fps %.0f", memory_kb(), GetFramerate()));
end

local running = false;

-- samples memory once a second; the positive steps add up to the garbage made
-- (a garbage collection in between shows as a drop and is skipped)
local function measure(seconds)
    if running then
        out("already measuring");
        return;
    end
    running = true;
    local last = memory_kb();
    local start_mem, garbage, elapsed = last, 0, 0;
    local peak_before = addon_metric("PeakTime");
    out(string.format("measuring for %d s ...", seconds));
    local function tick()
        elapsed = elapsed + 1;
        local now = memory_kb();
        if now > last then
            garbage = garbage + (now - last);
        end
        last = now;
        if elapsed < seconds then
            C_Timer.After(1.0, tick);
            return;
        end
        running = false;
        out(string.format("garbage: %.1f KB/s, memory %.0f -> %.0f KB",
            garbage / seconds, start_mem, now));
        local peak = addon_metric("PeakTime");
        if peak and peak_before and peak > peak_before then
            out("new peak during the measurement: "..ms(peak));
        end
        print_figures();
        -- the client bills the memory sampling to this addon
        out("note: peak and slow frames include the once-a-second memory sampling of this measurement");
    end
    C_Timer.After(1.0, tick);
end

function perf.run(arg)
    local seconds = tonumber(arg);
    if arg and arg ~= "" and not seconds then
        out("usage: /sc perf [seconds]");
        return;
    end
    if seconds then
        measure(math.max(5, math.min(300, math.floor(seconds))));
    else
        print_figures();
    end
end

sc.perf = perf;
