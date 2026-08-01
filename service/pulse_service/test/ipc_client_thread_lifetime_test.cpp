// Regression: destroying ClientConnection from its own reader thread must not
// call std::terminate via std::thread::~thread (joinable).
//
// Repro class (pre-fix): shared_ptr deleter deletes Conn while reader is
// still joinable → 0xc0000409 FAST_FAIL_FATAL_APP_EXIT.
//
// See docs/architecture/27-service-crash-client-thread.md

#include <atomic>
#include <chrono>
#include <cstdio>
#include <memory>
#include <thread>

struct Conn {
  std::atomic<bool> alive{true};
  std::thread reader;
};

int main() {
  std::atomic<int> finished{0};

  {
    auto conn = std::shared_ptr<Conn>(new Conn(), [](Conn* c) {
      if (c == nullptr) return;
      if (c->reader.joinable()) {
        if (c->reader.get_id() == std::this_thread::get_id()) {
          c->reader.detach();
        } else {
          c->alive = false;
          c->reader.join();
        }
      }
      delete c;
    });

    conn->reader = std::thread([conn, &finished] {
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
      finished.store(1);
      // Last shared_ptr released when this lambda ends — deleter must detach.
    });

    for (int i = 0; i < 50 && finished.load() == 0; ++i) {
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
  }

  std::this_thread::sleep_for(std::chrono::milliseconds(50));
  if (finished.load() != 1) {
    std::fprintf(stderr, "FAIL: reader did not finish\n");
    return 1;
  }
  std::printf("ok\n");
  return 0;
}
