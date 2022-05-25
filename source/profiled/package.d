module profiled;

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

    // dfmt off
    return id
        .text
        .replace("Tid(", "")
        .replace(")", "")[5 .. $ - 1]
        .to!(long)(16)
        .to!string;
    // dfmt on
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
        // dfmt off
        return `{"name":"%s","cat":"category","ph":"X","ts":%s,"dur":%s, "pid":1, "tid":%s}`
            .format(name,
                    convClockFreq(start.ticks,
                                  MonoTime.ticksPerSecond, 1_000_000).to!string,
                    duration.total!("usecs"),
                    tid2string(threadId));
        // dfmt on
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

    ~this()
    {
        profiler.add(new CompleteEvent(name, tid, start, MonoTime.currTime - start));
    }
}

class Profiler
{
    Mutex eventsMutex;
    Appender!(Event[]) events = appender!(Event[]);
    this()
    {
        eventsMutex = new Mutex();
    }

    public Unique!CompleteEventProcess start(string name)
    {
        Unique!CompleteEventProcess result = new CompleteEventProcess(this,
                name, thisTid, MonoTime.currTime);
        return result;
    }

    public void add(Event e)
    {
        eventsMutex.lock;
        scope (exit)
            eventsMutex.unlock;
        events ~= e;
    }

    public void dumpJson(string filename)
    {
        auto f = File(filename, "w");
        f.writeln("[");
        bool first = true;
        foreach (e; events[])
        {
            if (first)
            {
                first = false;
            }
            else
            {
                f.writeln(",");
            }
            f.write(e.toJson());
        }
    }
}
