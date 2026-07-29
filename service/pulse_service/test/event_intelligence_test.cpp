#include "intelligence/event_intelligence.hpp"

#include <cassert>
#include <iostream>

int main() {
  using namespace pulse;
  EventIntelligence engine;

  {
    ipc::TimelineEvent e;
    e.provider_name = "Service Control Manager";
    e.win_event_id = 7040;
    e.severity = ipc::Severity::Info;
    e.message = "The start type of the Background Intelligent Transfer Service "
                "service was changed from auto start to demand start.";
    const auto insight = engine.Analyze(e);
    assert(insight.title == "Windows Service Configuration Changed");
    assert(insight.action_required == false);
    assert(insight.recommendation.empty());
    assert(insight.importance == Importance::Low);
  }

  {
    ipc::TimelineEvent e;
    e.provider_name = "Tcpip";
    e.win_event_id = 4266;
    e.severity = ipc::Severity::Warning;
    e.message = "A request to allocate an ephemeral port number from the global "
                "UDP port space has failed due to all such ports being in use.";
    const auto insight = engine.Analyze(e);
    assert(insight.title == "Temporary UDP Port Allocation Failed");
    assert(insight.action_required == true);
    assert(insight.importance == Importance::High);
    assert(!insight.recommendation.empty());
  }

  {
    ipc::TimelineEvent e;
    e.provider_name = "Microsoft-Windows-HttpService";
    e.win_event_id = 114;
    const auto insight = engine.Analyze(e);
    assert(insight.title == "HTTP Service Endpoint Removed");
    assert(insight.action_required == false);
    assert(insight.recommendation.empty());
  }

  {
    ipc::TimelineEvent e;
    e.provider_name = "Microsoft-Windows-DistributedCOM";
    e.win_event_id = 10016;
    const auto insight = engine.Analyze(e);
    assert(insight.title == "COM Permission Warning");
    assert(insight.action_required == false);
  }

  {
    ipc::TimelineEvent e;
    e.provider_name = "SomeUnknownProvider";
    e.win_event_id = 9999;
    e.message = "Raw Event Viewer paragraph that should be softened.\nSecond line.";
    const auto insight = engine.Analyze(e);
    assert(insight.title == "SomeUnknownProvider");
    assert(insight.recommendation.empty());
    assert(insight.action_required == false);
    assert(insight.summary.find("Second line") == std::string::npos);
  }

  std::cout << "event_intelligence_tests OK\n";
  return 0;
}
