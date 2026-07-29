#include "humanization/event_humanizer.hpp"

#include <cassert>
#include <iostream>

int main() {
  using namespace pulse;
  EventHumanizer humanizer;

  {
    EventRecord r;
    r.provider_name = "Microsoft-Windows-DistributedCOM";
    r.event_id = 10016;
    r.level = EventLevel::Warning;
    r.message = "The application-specific permission settings do not grant...";
    const auto h = humanizer.Humanize(r);
    assert(h.title == "COM Permission Warning");
    assert(h.category == "COM");
    assert(!h.recommendation.empty());
  }

  {
    EventRecord r;
    r.provider_name = "Service Control Manager";
    r.event_id = 7036;
    r.level = EventLevel::Information;
    const auto h = humanizer.Humanize(r);
    assert(h.title == "Service State Changed");
    assert(h.summary == "A Windows service changed its running state.");
  }

  {
    EventRecord r;
    r.provider_name = "Microsoft-Windows-Kernel-General";
    r.event_id = 12;
    const auto h = humanizer.Humanize(r);
    assert(h.title == "Windows Started");
  }

  {
    EventRecord r;
    r.provider_name = "Microsoft-Windows-Kernel-General";
    r.event_id = 13;
    const auto h = humanizer.Humanize(r);
    assert(h.title == "Windows Shutdown");
  }

  {
    EventRecord r;
    r.provider_name = "Microsoft-Windows-Time-Service";
    r.event_id = 158;
    const auto h = humanizer.Humanize(r);
    assert(h.title == "Time Synchronization Stopped");
  }

  {
    EventRecord r;
    r.provider_name = "SomeProvider";
    r.event_id = 9999;
    r.message = "Raw Event Viewer text";
    const auto h = humanizer.Humanize(r);
    assert(h.title == "SomeProvider");
    assert(h.summary == "Raw Event Viewer text");
    assert(h.recommendation.empty());
  }

  std::cout << "event_humanizer_tests OK\n";
  return 0;
}
