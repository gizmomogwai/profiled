module profiled;

import std.concurrency;
import core.sync.mutex;
import std;

__gshared Profiler theProfiler;

abstract class Event
{
    public abstract string toJson();
}
string tid2string(Tid id)
{
    import std.conv : text;

    return id
        .text
        .replace("Tid(", "")
        .replace(")", "")
        [5..$-1]
        .to!(long)(16)
        .to!string;
}

enum Phase
{
    BEGIN, END
}
class DurationEvent : Event
{
    Phase phase;
    string name;
    Tid threadId;
    MonoTime timestamp;
    this(Phase phase, string name, Tid threadId, MonoTime timestamp)
    {
        this.phase = phase;
        this.name = name;
        this.threadId = threadId;
        this.timestamp = timestamp;
    }
    override public string toJson()
    {
        return `{"name":"%s", "cat": "category", "ph": "%s", "ts": %s, "pid":1, "tid": %s}`.format(name, (phase == Phase.BEGIN ? "B" : "E"), convClockFreq(timestamp.ticks, MonoTime.ticksPerSecond, 1_000_000), tid2string(threadId));
    }
}
class CompleteEvent : Event
{
    string name;
    Tid threadId;
    MonoTime start;
    Duration duration;
    this(string name, Tid threadId, MonoTime start, Duration duration)
    {
        this.name = name;
        this.threadId = threadId;
        this.start = start;
        this.duration = duration;
    }
    override public string toJson()
    {
        return `{"name":"%s","cat":"category","ph":"X","ts":%s,"dur":%s, "pid":1, "tid":%s}`.format(name, convClockFreq(start.ticks, MonoTime.ticksPerSecond, 1_000_000).to!string, duration.total!("usecs"), tid2string(threadId));
    }
}
class DurationEventProcess
{
    Profiler profiler;
    string name;

    this(Profiler profiler, string name)
    {
        this.profiler = profiler;
        this.name = name;
    }
    void finish()
    {
        profiler.add(new DurationEvent(Phase.END, name, thisTid, MonoTime.currTime));
    }
}
class CompleteEventProcess
{
    Profiler profiler;
    string name;
    Tid tid;
    MonoTime start;
    this(Profiler profiler, string name, Tid tid, MonoTime start)
    {
        this.profiler = profiler;
        this.name = name;
        this.tid = tid;
        this.start = start;
    }
    void finish()
    {
        profiler.add(new CompleteEvent(name, tid, start, MonoTime.currTime - start));
    }
}
class Profiler
{
    Mutex eventsMutex;
    Event[] events;
    this()
    {
        eventsMutex = new Mutex();
    }
    public CompleteEventProcess startComplete(string name)
    {
        return new CompleteEventProcess(this, name, thisTid, MonoTime.currTime);
    }
    public DurationEventProcess start(string theName)
    {
        eventsMutex.lock();
        scope (exit) eventsMutex.unlock;
        events ~= new DurationEvent(Phase.BEGIN, theName, thisTid, MonoTime.currTime);
        return new DurationEventProcess(this, theName);
    }
    public void add(Event e) {
        eventsMutex.lock;
        scope (exit) eventsMutex.unlock;
        events ~= e;
    }
    public void dumpJson(string filename)
    {
        auto f = File(filename, "w");
        f.writeln("[");
        bool first = true;
        foreach (e; events)
        {
            if (first)
            {
                first = false;
            } else
            {
                f.writeln(",");
            }
            f.write(e.toJson());
        }
    }
}
